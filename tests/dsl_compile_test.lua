-- M2 tests : DSL string → P descriptor → behaviour parity with
-- hand-written P. Plus deferred-feature compile errors.

return function(env, m)
    local test         = env.test
    local assertEq     = env.assertEq
    local assertTrue   = env.assertTrue
    local assertFalse  = env.assertFalse
    local assertThrows = env.assertThrows

    local P = m.P
    local parsePattern = m.parsePattern
    local isMatching   = m.isMatching

    local function pp(src, scope, ctx) return parsePattern(src, scope, ctx) end

    -- ── literal / wild / bind ────────────────────────────────────────────
    test("compile : string literal", function()
        local pat = pp("'GET'")
        assertTrue(isMatching(pat, "GET"))
        assertFalse(isMatching(pat, "POST"))
    end)

    test("compile : number literal", function()
        local pat = pp("42")
        assertTrue(isMatching(pat, 42))
        assertFalse(isMatching(pat, 41))
    end)

    test("compile : wildcard matches anything", function()
        local pat = pp("_")
        assertTrue(isMatching(pat, "x"))
        assertTrue(isMatching(pat, 42))
        assertTrue(isMatching(pat, nil))
        assertTrue(isMatching(pat, {}))
    end)

    test("compile : binding matches anything (P.select)", function()
        local pat = pp("foo")
        assertTrue(isMatching(pat, "x"))
        assertTrue(m.isP(pat))
        assertTrue(m.isSelect(pat))
        assertEq(pat.label, "foo")
    end)

    -- ── scope ref / interpolation ────────────────────────────────────────
    test("compile : scope ref resolves", function()
        local scope = { Str = P.string, Num = P.number }
        local pat = pp("Str", scope)
        assertTrue(isMatching(pat, "hi"))
        assertFalse(isMatching(pat, 42))
    end)

    test("compile : missing scope ref errors", function()
        assertThrows(function() pp("Missing", {}) end)
    end)

    test("compile : interpolation resolves at parse-time", function()
        local hot = P.union("ping", "health")
        local pat = pp("$hot", {}, { hot = hot })
        assertTrue(isMatching(pat, "ping"))
        assertFalse(isMatching(pat, "x"))
    end)

    test("compile : missing interpolation errors", function()
        assertThrows(function() pp("$missing", {}, {}) end)
    end)

    -- ── union : pure literal vs mixed ────────────────────────────────────
    test("compile : pure literal union → P.union (hash)", function()
        local pat = pp("'POST' | 'PUT' | 'PATCH'")
        assertTrue(isMatching(pat, "POST"))
        assertTrue(isMatching(pat, "PUT"))
        assertTrue(isMatching(pat, "PATCH"))
        assertFalse(isMatching(pat, "GET"))
        assertEq(pat[m.P and "" or "" ] or pat.values and #pat.values, 3)
    end)

    test("compile : mixed-type union → P.anyOf", function()
        local scope = { Str = P.string, Num = P.number }
        local pat = pp("Str | Num", scope)
        assertTrue(isMatching(pat, "x"))
        assertTrue(isMatching(pat, 42))
        assertFalse(isMatching(pat, true))
    end)

    test("compile : union mixing literal + scope ref", function()
        local scope = { Str = P.string }
        local pat = pp("'GET' | Str", scope)
        assertTrue(isMatching(pat, "GET"))
        assertTrue(isMatching(pat, "anything"))
        assertFalse(isMatching(pat, 42))
    end)

    -- ── intersection / optional / as / not ───────────────────────────────
    test("compile : intersection", function()
        local scope = {
            Pos = P.gt(0),
            Lt100 = P.lt(100),
        }
        local pat = pp("Pos & Lt100", scope)
        assertTrue(isMatching(pat, 50))
        assertFalse(isMatching(pat, -1))
        assertFalse(isMatching(pat, 150))
    end)

    test("compile : optional", function()
        local scope = { Str = P.string }
        local pat = pp("Str?", scope)
        assertTrue(isMatching(pat, "x"))
        assertTrue(isMatching(pat, nil))
        assertFalse(isMatching(pat, 42))
    end)

    test("compile : as binding wraps with labelled select", function()
        local scope = { Str = P.string }
        local pat = pp("Str as s", scope)
        assertTrue(m.isSelect(pat))
        assertEq(pat.label, "s")
        assertTrue(isMatching(pat, "x"))
        assertFalse(isMatching(pat, 42))
    end)

    test("compile : not / bang", function()
        local scope = { Str = P.string }
        local pat = pp("!Str", scope)
        assertTrue(isMatching(pat, 42))
        assertFalse(isMatching(pat, "x"))
    end)

    -- ── shapes ───────────────────────────────────────────────────────────
    test("compile : shape with typed field", function()
        local pat = pp("{ kind: 'click' }")
        assertTrue(isMatching(pat, { kind = "click" }))
        assertTrue(isMatching(pat, { kind = "click", x = 1 }))  -- extras OK
        assertFalse(isMatching(pat, { kind = "hover" }))
    end)

    test("compile : shape shorthand binds field", function()
        local pat = pp("{ x }")
        assertTrue(isMatching(pat, { x = 42 }))
        assertTrue(isMatching(pat, { x = "anything" }))
    end)

    test("compile : shape multiple fields", function()
        local scope = { Num = P.number }
        local pat = pp("{ kind: 'click', count: Num }", scope)
        assertTrue(isMatching(pat, { kind = "click", count = 3 }))
        assertFalse(isMatching(pat, { kind = "click", count = "x" }))
        assertFalse(isMatching(pat, { kind = "hover", count = 3 }))
    end)

    test("compile : shape with anonymous rest is no-op", function()
        local pat = pp("{ kind: 'click', ... }")
        assertTrue(isMatching(pat, { kind = "click", extra = "field" }))
    end)

    -- ── strict shapes : `{| ... |}` ──────────────────────────────────────
    test("compile : strict shape — exact match", function()
        local pat = pp("{| kind: 'click' |}")
        assertTrue(isMatching(pat, { kind = "click" }))
    end)
    test("compile : strict shape — rejects extras", function()
        local pat = pp("{| kind: 'click' |}")
        assertFalse(isMatching(pat, { kind = "click", extra = "no" }))
    end)
    test("compile : strict shape — rejects missing", function()
        local scope = { Num = P.number }
        local pat = pp("{| kind: 'click', x: Num |}", scope)
        assertFalse(isMatching(pat, { kind = "click" }))
    end)
    test("compile : strict shape — empty matches empty table only", function()
        local pat = pp("{||}")
        assertTrue(isMatching(pat, {}))
        assertFalse(isMatching(pat, { x = 1 }))
    end)
    test("compile : strict shape — bindings via shorthand", function()
        local rules = {
            { with = pp("{| kind: 'add', x, y |}"),
              handler = function(sel) return sel.x + sel.y end },
            { otherwise = function() return -1 end },
        }
        assertEq(m.match({ kind = "add", x = 3, y = 4 }, rules), 7)
        -- extra key blocks the strict shape, falls through to otherwise
        assertEq(m.match({ kind = "add", x = 3, y = 4, z = 0 }, rules), -1)
    end)
    test("compile : strict shape — typed field with optional", function()
        local scope = { Num = P.number, Str = P.string }
        local pat = pp("{| id: Num, name: Str? |}", scope)
        assertTrue(isMatching(pat, { id = 1 }))
        assertTrue(isMatching(pat, { id = 1, name = "Bob" }))
        assertFalse(isMatching(pat, { id = 1, name = "Bob", age = 30 }))
    end)
    test("compile : strict shape — discriminated union", function()
        local scope = { Num = P.number }
        local rules = {
            { with = pp("{| kind: 'click', x: Num, y: Num |}", scope),
              handler = function() return "click" end },
            { with = pp("{| kind: 'key',  code: Num |}", scope),
              handler = function() return "key" end },
            { otherwise = function() return "?" end },
        }
        assertEq(m.match({ kind = "click", x = 1, y = 2 }, rules), "click")
        assertEq(m.match({ kind = "key", code = 27 }, rules),      "key")
        -- Extra field blocks both strict branches, falls to otherwise
        assertEq(m.match({ kind = "click", x = 1, y = 2, z = 3 }, rules), "?")
    end)

    -- ── tuples / arrays ──────────────────────────────────────────────────
    test("compile : tuple via parens", function()
        local scope = { Str = P.string, Num = P.number }
        local pat = pp("(Str, Num)", scope)
        assertTrue(isMatching(pat, { "x", 42 }))
        assertFalse(isMatching(pat, { "x", "y" }))
        assertFalse(isMatching(pat, { "x" }))  -- length mismatch
    end)

    test("compile : array no rest → tuple", function()
        local scope = { Num = P.number }
        local pat = pp("[Num, Num]", scope)
        assertTrue(isMatching(pat, { 1, 2 }))
        assertFalse(isMatching(pat, { 1, 2, 3 }))  -- extra elem
    end)

    test("compile : array tail rest (anonymous) → startsWith", function()
        local scope = { Num = P.number }
        local pat = pp("[Num, Num, ...]", scope)
        assertTrue(isMatching(pat, { 1, 2 }))
        assertTrue(isMatching(pat, { 1, 2, 3, 4 }))
        assertFalse(isMatching(pat, { 1 }))  -- too short
    end)

    test("compile : array head rest (anonymous) → endsWith", function()
        local scope = { Num = P.number }
        local pat = pp("[..., Num]", scope)
        assertTrue(isMatching(pat, { 1 }))
        assertTrue(isMatching(pat, { "x", "y", 99 }))
        assertFalse(isMatching(pat, { 1, "x" }))
    end)

    test("compile : empty array matches empty tuple only", function()
        local pat = pp("[]")
        assertTrue(isMatching(pat, {}))
        assertFalse(isMatching(pat, { 1 }))
    end)

    -- ── combined / realistic ─────────────────────────────────────────────
    test("compile : Admin & shape with typed field", function()
        local scope = { Admin = { role = "admin" }, Str = P.string }
        local pat = pp("Admin & { name: Str }", scope)
        assertTrue(isMatching(pat, { role = "admin", name = "Mira" }))
        assertFalse(isMatching(pat, { role = "user", name = "Mira" }))
        assertFalse(isMatching(pat, { role = "admin", name = 42 }))
    end)

    test("compile : full rule via match() — literals + tuple + default", function()
        local scope = { Str = P.string, Num = P.number }
        local rules = {
            { with = pp("'GET'"),             handler = function() return "list"  end },
            { with = pp("'POST' | 'PUT'"),    handler = function() return "write" end },
            { with = pp("(Str, Num)", scope), handler = function(v) return "tup:" .. v[1] end },
            { otherwise = function() return "default" end },
        }
        assertEq(m.match("GET",      rules), "list")
        assertEq(m.match("POST",     rules), "write")
        assertEq(m.match({ "x", 42 }, rules), "tup:x")
        assertEq(m.match(123,        rules), "default")
        assertEq(m.match({},         rules), "default")
    end)

    test("compile : as-binding flows into handler bindings", function()
        local scope = { Str = P.string }
        local rules = {
            { with = pp("Str as s", scope),
              handler = function(b) return "got:" .. b.s end },
            { otherwise = function() return "no" end },
        }
        assertEq(m.match("hello", rules), "got:hello")
        assertEq(m.match(42,      rules), "no")
    end)

    test("compile : interpolation in union, mixed", function()
        local hot = P.union("ping", "health")
        local pat = pp("$hot | 'fallback'", {}, { hot = hot })
        assertTrue(isMatching(pat, "ping"))
        assertTrue(isMatching(pat, "fallback"))
        assertFalse(isMatching(pat, "x"))
    end)

    -- ── named rest binding (slice extractor) ────────────────────────────
    test("named rest : array tail captured", function()
        local scope = { Num = P.number }
        local rules = {
            { with = pp("[Num, Num, ...tail]", scope),
              handler = function(b) return ("h2,t" .. #b.tail) end },
            { otherwise = function() return "no" end },
        }
        assertEq(m.match({ 1, 2 },          rules), "h2,t0")
        assertEq(m.match({ 1, 2, 3, 4, 5 }, rules), "h2,t3")
        assertEq(m.match({ 1 },             rules), "no")
    end)

    test("named rest : array head captured (endsWith)", function()
        local scope = { Num = P.number }
        local rules = {
            { with = pp("[...init, Num]", scope),
              handler = function(b) return ("init=" .. #b.init) end },
            { otherwise = function() return "no" end },
        }
        assertEq(m.match({ 9 },          rules), "init=0")
        assertEq(m.match({ 1, 2, 3, 9 }, rules), "init=3")
    end)

    test("named rest : array rest only", function()
        local rules = {
            { with = pp("[...all]"),
              handler = function(b) return #b.all end },
            { otherwise = function() return -1 end },
        }
        assertEq(m.match({ 1, 2, 3, 4 }, rules), 4)
        assertEq(m.match({},             rules), 0)
    end)

    test("named rest : array rest contents preserved in order", function()
        local scope = { Num = P.number }
        local pat = pp("[Num, ...tail]", scope)
        local rules = {
            { with = pat,
              handler = function(b) return table.concat(b.tail, ",") end },
        }
        assertEq(m.match({ 0, 10, 20, 30 }, rules), "10,20,30")
    end)

    test("named rest : shape rest captures unknown keys", function()
        local rules = {
            { with = pp("{ kind: 'click', ...rest }"),
              handler = function(b)
                  local keys = {}
                  for k in pairs(b.rest) do keys[#keys+1] = k end
                  table.sort(keys)
                  return table.concat(keys, ",")
              end },
            { otherwise = function() return "no" end },
        }
        assertEq(m.match({ kind = "click", x = 1, y = 2 }, rules), "x,y")
        assertEq(m.match({ kind = "click" },                rules), "")
        assertEq(m.match({ kind = "hover" },                rules), "no")
    end)

    test("named rest : shape rest excludes declared keys only", function()
        local pat = pp("{ a: 'x', b: 'y', ...others }")
        local rules = {
            { with = pat,
              handler = function(b) return b.others.c end },
        }
        assertEq(m.match({ a = "x", b = "y", c = "z" }, rules), "z")
    end)

    -- ── M3 : guards (pat if expr) ────────────────────────────────────────
    test("guard : binding compared to literal", function()
        local pat = pp("x if x > 0")
        assertTrue(isMatching(pat, 5))
        assertFalse(isMatching(pat, -1))
        assertFalse(isMatching(pat, 0))
    end)

    test("guard : multiple bindings via shape shorthand", function()
        local pat = pp("{ x, y } if x > 0 and y > 0")
        assertTrue(isMatching(pat, { x = 1, y = 2 }))
        assertFalse(isMatching(pat, { x = -1, y = 2 }))
        assertFalse(isMatching(pat, { x = 1, y = 0 }))
    end)

    test("guard : applies to whole union", function()
        local pat = pp("x if x == 'a' or x == 'b'")
        assertTrue(isMatching(pat, "a"))
        assertTrue(isMatching(pat, "b"))
        assertFalse(isMatching(pat, "c"))
    end)

    test("guard : member access in expr", function()
        local pat = pp("u if u.age >= 18")
        assertTrue(isMatching(pat, { age = 22 }))
        assertFalse(isMatching(pat, { age = 12 }))
    end)

    test("guard : scope function call", function()
        local scope = { isEmail = function(s) return type(s)=="string" and s:find("@",1,true) ~= nil end }
        local pat = pp("s if isEmail(s)", scope)
        assertTrue(isMatching(pat, "x@y.z"))
        assertFalse(isMatching(pat, "nope"))
    end)

    test("guard : not in expr", function()
        local scope = { isEmail = function(s) return type(s)=="string" and s:find("@",1,true) ~= nil end }
        local pat = pp("s if not isEmail(s)", scope)
        assertTrue(isMatching(pat, "nope"))
        assertFalse(isMatching(pat, "x@y.z"))
    end)

    test("guard : interpolation in expr", function()
        local pat = pp("x if x > $threshold", {}, { threshold = 10 })
        assertTrue(isMatching(pat, 20))
        assertFalse(isMatching(pat, 5))
    end)

    test("guard : binding flows to handler too", function()
        local rules = {
            { with = pp("x if x > 0"),
              handler = function(b) return b.x * 2 end },
            { otherwise = function() return -1 end },
        }
        assertEq(m.match(5, rules), 10)
        assertEq(m.match(-1, rules), -1)
    end)

    test("guard : zero bindings — pure-value guard", function()
        local pat = pp("'GET' if true")
        assertTrue(isMatching(pat, "GET"))
        assertFalse(isMatching(pat, "POST"))
    end)

    -- ── M3 : ref-args sugar Type(field op val) ───────────────────────────
    test("ref args : single comparison", function()
        local scope = { User = { role = "admin" } }
        local pat = pp("User(age > 18)", scope)
        assertTrue(isMatching(pat,  { role = "admin", age = 22 }))
        assertFalse(isMatching(pat, { role = "admin", age = 12 }))
        assertFalse(isMatching(pat, { role = "user",  age = 22 }))
    end)

    test("ref args : multiple comparisons (AND)", function()
        local scope = { User = { kind = "user" } }
        local pat = pp("User(age >= 18, score < 100)", scope)
        assertTrue(isMatching(pat,  { kind = "user", age = 18, score = 50 }))
        assertFalse(isMatching(pat, { kind = "user", age = 17, score = 50 }))
        assertFalse(isMatching(pat, { kind = "user", age = 18, score = 200 }))
    end)

    test("ref args : with $interpolation in rhs", function()
        local scope = { User = P.any }
        local pat = pp("User(age > $minAge)", scope, { minAge = 21 })
        assertTrue(isMatching(pat,  { age = 30 }))
        assertFalse(isMatching(pat, { age = 19 }))
    end)

    test("ref args : non-table value fails fast", function()
        local scope = { User = P.any }
        local pat = pp("User(age > 0)", scope)
        assertFalse(isMatching(pat, 42))
        assertFalse(isMatching(pat, "x"))
    end)

    -- ── M3 combined : User(age > 18) as u flows binding to handler ──────
    test("combined : User(age > 18) as u — binding via match", function()
        local scope = { User = { kind = "user" } }
        local rules = {
            { with = pp("User(age > 18) as u", scope),
              handler = function(b) return "adult:" .. b.u.age end },
            { otherwise = function() return "no" end },
        }
        assertEq(m.match({ kind = "user", age = 22 }, rules), "adult:22")
        assertEq(m.match({ kind = "user", age = 12 }, rules), "no")
    end)

    -- ── M4 : AST cache ──────────────────────────────────────────────────
    test("cache : repeated parse of same src reuses AST", function()
        local parsePat = require("matchigo.parsePattern")
        parsePat.clearCache()
        assertEq(parsePat.cacheSize(), 0)
        parsePat.parsePattern("'GET'")
        assertEq(parsePat.cacheSize(), 1)
        parsePat.parsePattern("'GET'")
        assertEq(parsePat.cacheSize(), 1)  -- no growth
        parsePat.parsePattern("'POST'")
        assertEq(parsePat.cacheSize(), 2)
    end)

    test("cache : different scopes still produce correct results from same src", function()
        local parsePat = require("matchigo.parsePattern")
        parsePat.clearCache()
        local pat1 = parsePat.parsePattern("X", { X = P.string })
        local pat2 = parsePat.parsePattern("X", { X = P.number })
        assertTrue(isMatching(pat1, "x"));  assertFalse(isMatching(pat1, 42))
        assertTrue(isMatching(pat2, 42));   assertFalse(isMatching(pat2, "x"))
    end)

    -- ── M6 : shadowing detection ────────────────────────────────────────
    test("shadowing : duplicate binding in tuple errors", function()
        assertThrows(function() pp("(x, x)") end)
    end)

    test("shadowing : same binding name in two shape fields errors", function()
        assertThrows(function() pp("{ a: x, b: x }") end)
    end)

    test("shadowing : binding then rest with same name errors", function()
        local scope = { Num = P.number }
        assertThrows(function() pp("[Num as tail, ...tail]", scope) end)
    end)

    test("shadowing : as conflict with binding errors", function()
        assertThrows(function() pp("(x, y as x)") end)
    end)

    test("shadowing : OK across union branches", function()
        local pat = pp("'a' as x | 'b' as x")
        assertTrue(isMatching(pat, "a"))
        assertTrue(isMatching(pat, "b"))
    end)

    test("shadowing : OK in different intersection parts that don't bind", function()
        local scope = { Str = P.string }
        local pat = pp("Str & x", scope)
        assertTrue(isMatching(pat, "ok"))
    end)
end
