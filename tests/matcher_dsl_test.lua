-- Chained `matcher(scope?, ctx?)` with DSL string patterns.
-- Verifies string patterns auto-parse via the captured (scope, ctx),
-- terminal methods compile, and mixing string + raw P descriptors works.

return function(env, m)
    local test         = env.test
    local assertEq     = env.assertEq
    local assertThrows = env.assertThrows

    local P       = m.P
    local matcher = m.matcher

    -- ── basics ───────────────────────────────────────────────────────────
    test("matcher(dsl) : literal-only chain", function()
        local dispatch = matcher({})
            :with("'GET'",  function() return "list"  end)
            :with("'POST'", function() return "write" end)
            :otherwise(     function() return "no"    end)
        assertEq(dispatch("GET"),  "list")
        assertEq(dispatch("POST"), "write")
        assertEq(dispatch("X"),    "no")
    end)

    test("matcher(dsl) : exhaustive throws on miss", function()
        local dispatch = matcher({})
            :with("'GET'", function() return 1 end)
            :exhaustive()
        assertEq(dispatch("GET"), 1)
        assertThrows(function() dispatch("POST") end)
    end)

    test("matcher(dsl) : compile() returns raw dispatch fn", function()
        local dispatch = matcher({})
            :with("'A'", function() return 1 end)
            :with("'B'", function() return 2 end)
            :compile()
        assertEq(dispatch("A"), 1)
        assertEq(dispatch("B"), 2)
    end)

    test("matcher(dsl) : run() before compile works (lazy)", function()
        local mt = matcher({})
            :with("'X'", function() return "yep" end)
            :with("'Y'", function() return "yeppp" end)
        assertEq(mt:run("X"), "yep")
    end)

    -- ── scope + ctx flow ─────────────────────────────────────────────────
    test("matcher(scope) : scope refs flow into all :with strings", function()
        local scope = { Str = P.string, Num = P.number }
        local dispatch = matcher(scope)
            :with("Str", function() return "s" end)
            :with("Num", function() return "n" end)
            :otherwise(   function() return "?" end)
        assertEq(dispatch("hi"), "s")
        assertEq(dispatch(42),   "n")
        assertEq(dispatch(true), "?")
    end)

    test("matcher(scope, ctx) : interpolation usable across rules", function()
        local hot = P.union("ping", "health")
        local dispatch = matcher({}, { hot = hot })
            :with("$hot",        function() return "cached" end)
            :otherwise(           function() return "miss"   end)
        assertEq(dispatch("ping"),   "cached")
        assertEq(dispatch("health"), "cached")
        assertEq(dispatch("xyz"),    "miss")
    end)

    test("matcher(dsl) : guards work via DSL", function()
        local dispatch = matcher({})
            :with("x if x > 0",  function(b) return "pos:" .. b.x end)
            :with("x if x < 0",  function(b) return "neg:" .. b.x end)
            :otherwise(           function() return "zero" end)
        assertEq(dispatch(5),  "pos:5")
        assertEq(dispatch(-3), "neg:-3")
        assertEq(dispatch(0),  "zero")
    end)

    test("matcher(scope) : User(age > 18) as u via chain", function()
        local scope = { User = { kind = "user" } }
        local dispatch = matcher(scope)
            :with("User(age > 18) as u",
                  function(b) return "adult:" .. b.u.age end)
            :otherwise(function() return "no" end)
        assertEq(dispatch({ kind = "user", age = 22 }), "adult:22")
        assertEq(dispatch({ kind = "user", age = 12 }), "no")
        assertEq(dispatch("xx"), "no")
    end)

    -- ── mixing string + raw P descriptors ────────────────────────────────
    test("matcher(dsl) : raw P descriptors pass through unchanged", function()
        local dispatch = matcher({})
            :with(P.string,  function() return "s" end)
            :with("'42'",    function() return "literal-42" end)
            :with(P.number,  function() return "n" end)
            :otherwise(       function() return "?" end)
        assertEq(dispatch("x"),  "s")
        assertEq(dispatch("42"), "literal-42")
        assertEq(dispatch(42),    "n")
        assertEq(dispatch(true),  "?")
    end)

    -- ── 3-arg :with(pattern, when, then) — runtime guard side ────────────
    test("matcher(dsl) : explicit when callback (raw P pattern)", function()
        local dispatch = matcher({})
            :with(P.number, function(v) return v > 0 end,
                            function()  return "pos" end)
            :otherwise(     function() return "no" end)
        assertEq(dispatch(5),  "pos")
        assertEq(dispatch(-1), "no")
    end)

    -- ── matcher() with no args still works (backward-compat) ─────────────
    test("matcher() : no-arg form preserves prior semantics", function()
        local fn = matcher()
            :with(P.string, function(v) return "s:" .. v end)
            :with(P.number, function(v) return "n:" .. v end)
            :otherwise(function() return "?" end)
        assertEq(fn("hi"), "s:hi")
        assertEq(fn(42), "n:42")
        assertEq(fn(true), "?")
    end)
end
