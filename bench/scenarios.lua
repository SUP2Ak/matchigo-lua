-- Scenario definitions for the matchigo-lua bench suite.
--
-- Every scenario provides a list of inputs the framework cycles through,
-- so each iteration of the timing loop sees a different input. This
-- defeats LuaJIT's constant folding and loop-invariant code motion : the
-- per-iteration call has to actually dispatch on a value the JIT cannot
-- precompute.
--
-- The cycling cost (a counter increment + array load) is paid uniformly
-- by every contestant in a scenario, so ratios stay accurate.

return function(m, b)
    local P = m.P

    --==============================================================
    -- Scenario 1 : HTTP method router (5 literal arms + fallback)
    --==============================================================

    do
        local function nativeRouter(method)
            if     method == "GET"    then return 1
            elseif method == "POST"   then return 2
            elseif method == "PUT"    then return 3
            elseif method == "DELETE" then return 4
            elseif method == "PATCH"  then return 5
            else                           return -1
            end
        end

        local mFn = m.compile({
            { with = "GET",    handler = function() return 1  end },
            { with = "POST",   handler = function() return 2  end },
            { with = "PUT",    handler = function() return 3  end },
            { with = "DELETE", handler = function() return 4  end },
            { with = "PATCH",  handler = function() return 5  end },
            { otherwise = function() return -1 end },
        })

        local mDsl = m.matcher({})
            :with("'GET'",    function() return 1  end)
            :with("'POST'",   function() return 2  end)
            :with("'PUT'",    function() return 3  end)
            :with("'DELETE'", function() return 4  end)
            :with("'PATCH'",  function() return 5  end)
            :otherwise(       function() return -1 end)

        b.scenario("HTTP router (5 literals + fallback)", {
            { name = "native       if/elseif",                fn = nativeRouter, key = "http.native"  },
            { name = "matchigo     compile() — literal hash", fn = mFn,          key = "http.compile" },
            { name = "matchigo     matcher + DSL",            fn = mDsl,         key = "http.matcher" },
        }, {
            inputs = { "GET", "POST", "PUT", "DELETE", "PATCH", "OPTIONS" },
        })
    end

    --==============================================================
    -- Scenario 2 : event handler — discriminated union with shape +
    --              guard (scroll requires delta > 0).
    --==============================================================

    do
        local function nativeEvent(e)
            if e.kind == "click" then
                return ("click@%d,%d"):format(e.x, e.y)
            elseif e.kind == "hover" then
                return "hover:" .. e.target
            elseif e.kind == "scroll" then
                if e.delta > 0 then return "scrollDown:" .. e.delta end
                return "ignore"
            else
                return "ignore"
            end
        end

        local mFn = m.compile({
            { with = { kind = "click" },
              handler = function(v) return ("click@%d,%d"):format(v.x, v.y) end },
            { with = { kind = "hover" },
              handler = function(v) return "hover:" .. v.target end },
            { with = { kind = "scroll" },
              when = function(v) return v.delta > 0 end,
              handler = function(v) return "scrollDown:" .. v.delta end },
            { otherwise = function() return "ignore" end },
        })

        local mDsl = m.matcher({ Str = P.string, Num = P.number })
            :with("{ kind: 'click', x: Num as x, y: Num as y }",
                  function(bind) return ("click@%d,%d"):format(bind.x, bind.y) end)
            :with("{ kind: 'hover', target: Str as id }",
                  function(bind) return "hover:" .. bind.id end)
            :with("{ kind: 'scroll', delta: Num as d } if d > 0",
                  function(bind) return "scrollDown:" .. bind.d end)
            :otherwise(function() return "ignore" end)

        b.scenario("event handler — shape + guard", {
            { name = "native       if/elseif + field reads", fn = nativeEvent, key = "event.native"  },
            { name = "matchigo     compile() shape + when",  fn = mFn,         key = "event.compile" },
            { name = "matchigo     matcher + DSL guard",     fn = mDsl,        key = "event.matcher" },
        }, {
            inputs = {
                { kind = "click",  x = 10, y = 20 },
                { kind = "hover",  target = "header" },
                { kind = "scroll", delta = 5 },
                { kind = "scroll", delta = -3 },
                { kind = "unknown" },
            },
        })
    end

    --==============================================================
    -- Scenario 3 : validation cascade (predicate guards on strings)
    --==============================================================

    do
        local function isEmail(s) return type(s) == "string" and s:find("@", 1, true) ~= nil end
        local function isUrl(s)   return type(s) == "string" and s:match("^https?://") ~= nil end

        local function nativeValidate(v)
            if isEmail(v) then return { kind = "email", value = v }
            elseif isUrl(v) then return { kind = "url", value = v }
            elseif type(v) == "string" then return { kind = "text", value = v }
            else return { kind = "invalid" }
            end
        end

        local mFn = m.compile({
            { with = P.string, when = isEmail,
              handler = function(v) return { kind = "email", value = v } end },
            { with = P.string, when = isUrl,
              handler = function(v) return { kind = "url", value = v } end },
            { with = P.string,
              handler = function(v) return { kind = "text", value = v } end },
            { otherwise = function() return { kind = "invalid" } end },
        })

        local mDsl = m.matcher({ Str = P.string, isEmail = isEmail, isUrl = isUrl })
            :with("s if isEmail(s)", function(bind) return { kind = "email", value = bind.s } end)
            :with("s if isUrl(s)",   function(bind) return { kind = "url",   value = bind.s } end)
            :with("Str",             function(v) return { kind = "text",  value = v } end)
            :otherwise(              function() return { kind = "invalid" } end)

        b.scenario("validation cascade — guarded predicates", {
            { name = "native       if/elseif",            fn = nativeValidate, key = "valid.native"  },
            { name = "matchigo     compile() with when=", fn = mFn,            key = "valid.compile" },
            { name = "matchigo     matcher + DSL guards", fn = mDsl,           key = "valid.matcher" },
        }, {
            inputs = {
                "foo@bar.com",
                "https://example.org",
                "plain text",
                "another@email.dev",
                42,  -- non-string → invalid
            },
        })
    end

    --==============================================================
    -- Scenario 4 : state machine — (state, event) tuple dispatch
    --==============================================================

    do
        local function nativeFsm(state, event)
            if event == "reset" then return "idle" end
            if state == "idle"    and event == "start" then return "running" end
            if state == "running" and event == "pause" then return "paused"  end
            if state == "paused"  and event == "start" then return "running" end
            if state == "running" and event == "stop"  then return "stopped" end
            return state
        end

        local mFn = m.compile({
            { with = m.parsePattern("(_, 'reset')"),         handler = function() return "idle"    end },
            { with = m.parsePattern("('idle',    'start')"), handler = function() return "running" end },
            { with = m.parsePattern("('running', 'pause')"), handler = function() return "paused"  end },
            { with = m.parsePattern("('paused',  'start')"), handler = function() return "running" end },
            { with = m.parsePattern("('running', 'stop')"),  handler = function() return "stopped" end },
            { otherwise = function(v) return v[1] end },
        })

        b.scenario("state machine — (state, event) tuple dispatch", {
            { name = "native       nested string compares",
              fn = function(t) return nativeFsm(t[1], t[2]) end,
              key = "fsm.native" },
            { name = "matchigo     compile() + tuple DSL",
              fn = mFn,
              key = "fsm.compile" },
        }, {
            inputs = {
                { "running", "pause" },
                { "paused",  "start" },
                { "running", "stop"  },
                { "running", "reset" },
                { "idle",    "start" },
            },
        })
    end

    --==============================================================
    -- Scenario 5 : numeric range bucketing
    --==============================================================

    do
        local function nativeBucket(n)
            if     n < 0     then return "negative"
            elseif n == 0    then return "zero"
            elseif n < 10    then return "small"
            elseif n <= 100  then return "medium"
            else                  return "large"
            end
        end

        local mFn = m.compile({
            { with = P.lt(0),            handler = function() return "negative" end },
            { with = 0,                  handler = function() return "zero"     end },
            { with = P.lt(10),           handler = function() return "small"    end },
            { with = P.between(10, 100), handler = function() return "medium"   end },
            { otherwise = function() return "large" end },
        })

        b.scenario("numeric range bucketing", {
            { name = "native       if/elseif on bounds", fn = nativeBucket, key = "num.native"  },
            { name = "matchigo     compile() + range P", fn = mFn,          key = "num.compile" },
        }, {
            inputs = { -5, 0, 5, 50, 1000 },
        })
    end

    --==============================================================
    -- Scenario 6 : 50-branch literal dispatch — where matchigo's
    --              hash O(1) actually pays off versus native's
    --              O(n) if/elseif chain.
    --
    -- Two variants share the same fixtures :
    --   * uniform mix    : all positions equally likely (realistic
    --                      load-balanced workload).
    --   * tail + fallback : hits cluster near the end of the chain
    --                       and on misses (long-tail dispatch tables,
    --                       APIs with many cold endpoints) — this is
    --                       matchigo's clearest win versus a native
    --                       linear chain.
    --==============================================================

    do
        local KEYS = {}
        for i = 1, 50 do KEYS[i] = "code_" .. i end

        local src = { "return function(k)\n" }
        for i, k in ipairs(KEYS) do
            src[#src + 1] = (i == 1 and "  if " or "  elseif ")
            src[#src + 1] = ("k == %q then return %d\n"):format(k, i)
        end
        src[#src + 1] = "  else return -1 end\nend\n"
        -- Lua 5.1 has loadstring() ; 5.2+ overloads load() to accept strings.
        ---@diagnostic disable-next-line: deprecated
        local loadstr = loadstring or load
        local nativeBig = assert(loadstr(table.concat(src)))()

        local rules = {}
        for i, k in ipairs(KEYS) do
            rules[i] = { with = k, handler = function() return i end }
        end
        rules[#rules + 1] = { otherwise = function() return -1 end }
        local mFnBig = m.compile(rules)

        b.scenario("50-branch literal dispatch — uniform mix", {
            { name = "native       if/elseif chain (50)",  fn = nativeBig, key = "big.uniform.native"  },
            { name = "matchigo     compile() — hash O(1)", fn = mFnBig,    key = "big.uniform.compile" },
        }, {
            inputs = { "code_1", "code_10", "code_25", "code_42", "code_50", "unknown" },
        })

        b.scenario("50-branch literal dispatch — tail hits + fallback", {
            { name = "native       if/elseif chain (50)",  fn = nativeBig, key = "big.tail.native"  },
            { name = "matchigo     compile() — hash O(1)", fn = mFnBig,    key = "big.tail.compile" },
        }, {
            inputs = { "code_45", "code_46", "code_47", "code_48", "code_49", "code_50", "unknown" },
        })
    end

    --==============================================================
    -- Scenario 7 : data-driven rules — rule set built from a config
    --              at runtime. Native has to roll its own hash.
    --==============================================================

    do
        local config = {
            { key = "GET",    value = 1 },
            { key = "POST",   value = 2 },
            { key = "PUT",    value = 3 },
            { key = "DELETE", value = 4 },
            { key = "PATCH",  value = 5 },
        }

        local nativeMap = {}
        for _, c in ipairs(config) do
            local v = c.value
            nativeMap[c.key] = function() return v end
        end
        local nativeFallback = function() return -1 end
        local function nativeHash(k)
            local fn = nativeMap[k]
            if fn then return fn() end
            return nativeFallback()
        end

        local mRules = {}
        for i, c in ipairs(config) do
            local v = c.value
            mRules[i] = { with = c.key, handler = function() return v end }
        end
        mRules[#mRules + 1] = { otherwise = nativeFallback }
        local mFn = m.compile(mRules)

        b.scenario("data-driven rules — config map", {
            { name = "native       hand-rolled hash table",   fn = nativeHash, key = "data.native"  },
            { name = "matchigo     compile(rules-from-data)", fn = mFn,        key = "data.compile" },
        }, {
            inputs = { "GET", "POST", "PUT", "DELETE", "PATCH", "OPTIONS" },
        })
    end

    --==============================================================
    -- Scenario 8 : JIT folding showcase — EDUCATIONAL.
    --
    -- This scenario deliberately calls the dispatcher with the SAME
    -- constant input every iteration (no cycling). The point is to
    -- show how LuaJIT handles a fully predictable hot loop :
    --
    --   * On Lua 5.x (no JIT), you get the real per-call cost.
    --   * On LuaJIT, both contestants collapse to ~0 ns because the
    --     JIT inlines the body and treats the result as loop-invariant
    --     (LICM hoists the compute out of the loop entirely).
    --
    -- Lesson : if your dispatch site is hot AND the input is constant
    -- in that loop, LuaJIT erases the cost regardless of which
    -- dispatcher you picked. Choose on readability + maintainability,
    -- not on ns. Compare against scenario 1 ("HTTP router (5 literals
    -- + fallback)") which cycles through varied inputs to see what the
    -- real dispatch cost is when the JIT can't fold the input away.
    --==============================================================

    do
        local function nativeRouter(method)
            if     method == "GET"    then return 1
            elseif method == "POST"   then return 2
            elseif method == "PUT"    then return 3
            elseif method == "DELETE" then return 4
            elseif method == "PATCH"  then return 5
            else                           return -1
            end
        end

        local mFn = m.compile({
            { with = "GET",    handler = function() return 1  end },
            { with = "POST",   handler = function() return 2  end },
            { with = "PUT",    handler = function() return 3  end },
            { with = "DELETE", handler = function() return 4  end },
            { with = "PATCH",  handler = function() return 5  end },
            { otherwise = function() return -1 end },
        })

        -- No `inputs` opt → the framework falls back to the no-cycle
        -- wrapper that just calls fn() with no args. We bake "POST" into
        -- the closure so each iteration sees the same predictable input.
        b.scenario("JIT folding showcase — constant input (educational)", {
            { name = "native       if/elseif (constant 'POST')",
              fn  = function() return nativeRouter("POST") end,
              key = "jit.native" },
            { name = "matchigo     compile() (constant 'POST')",
              fn  = function() return mFn("POST") end,
              key = "jit.compile" },
        })
    end
end
