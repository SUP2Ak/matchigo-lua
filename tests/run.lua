-- Run from matchigo-lua/ root :
--   lua tests/run.lua          -- against ./matchigo.lua (sources)
--   lua tests/run.lua dist     -- against ./dist/matchigo.lua (bundled)
local mode = arg and arg[1]
local m
if mode == "dist" then
    m = dofile("dist/matchigo.lua")
else
    package.path = "./?.lua;./?/init.lua;" .. package.path
    m = require("matchigo")
end
local P = m.P
local BigInt = m.BigInt
local Map = m.Map
local Set = m.Set

local passed, failed = 0, 0
local failures = {}

local function nanEq(a, b)
    if a == b then return true end
    if type(a) == "number" and type(b) == "number" and a ~= a and b ~= b then return true end
    return false
end

local function test(name, fn)
    local ok, err = pcall(fn)
    if ok then
        passed = passed + 1
    else
        failed = failed + 1
        failures[#failures + 1] = name .. " :: " .. tostring(err)
    end
end

local function assertEq(actual, expected)
    if not nanEq(actual, expected) then
        error(("expected %s, got %s"):format(tostring(expected), tostring(actual)), 2)
    end
end
local function assertTrue(v)  if not v then error("expected truthy", 2) end end
local function assertFalse(v) if v     then error("expected falsy",  2) end end
local function assertThrows(fn) if pcall(fn) then error("expected throw", 2) end end

------------------------------------------------------------
-- P leaf sentinels
------------------------------------------------------------
test("P.string", function()
    assertTrue(m.isMatching(P.string, "hi"))
    assertFalse(m.isMatching(P.string, 42))
end)
test("P.number", function()
    assertTrue(m.isMatching(P.number, 42))
    assertFalse(m.isMatching(P.number, "42"))
end)
test("P.boolean", function()
    assertTrue(m.isMatching(P.boolean, true))
    assertTrue(m.isMatching(P.boolean, false))
    assertFalse(m.isMatching(P.boolean, 1))
end)
test("P.func", function()
    assertTrue(m.isMatching(P.func, function() end))
    assertFalse(m.isMatching(P.func, "x"))
end)
test("P.nullish", function()
    assertTrue(m.isMatching(P.nullish, nil))
    assertFalse(m.isMatching(P.nullish, false))
end)
test("P.defined", function()
    assertTrue(m.isMatching(P.defined, 0))
    assertFalse(m.isMatching(P.defined, nil))
end)
test("P.any", function()
    assertTrue(m.isMatching(P.any, nil))
    assertTrue(m.isMatching(P.any, 0))
    assertTrue(m.isMatching(P.any, {}))
end)
test("P.integer", function()
    assertTrue(m.isMatching(P.integer, 5))
    assertFalse(m.isMatching(P.integer, 1.5))
end)
test("P.finite", function()
    assertTrue(m.isMatching(P.finite, 0))
    assertFalse(m.isMatching(P.finite, math.huge))
    assertFalse(m.isMatching(P.finite, 0/0))
end)
test("P.positive / P.negative", function()
    assertTrue(m.isMatching(P.positive, 1))
    assertFalse(m.isMatching(P.positive, 0))
    assertTrue(m.isMatching(P.negative, -1))
    assertFalse(m.isMatching(P.negative, 0))
end)

------------------------------------------------------------
-- Number refinements
------------------------------------------------------------
test("P.between inclusive", function()
    assertTrue(m.isMatching(P.between(1, 10), 5))
    assertTrue(m.isMatching(P.between(1, 10), 1))
    assertTrue(m.isMatching(P.between(1, 10), 10))
    assertFalse(m.isMatching(P.between(1, 10), 0))
    assertFalse(m.isMatching(P.between(1, 10), 11))
end)
test("P.gt / gte / lt / lte", function()
    assertTrue(m.isMatching(P.gt(5), 6))
    assertFalse(m.isMatching(P.gt(5), 5))
    assertTrue(m.isMatching(P.gte(5), 5))
    assertTrue(m.isMatching(P.lt(5), 4))
    assertFalse(m.isMatching(P.lt(5), 5))
    assertTrue(m.isMatching(P.lte(5), 5))
end)

------------------------------------------------------------
-- String refinements
------------------------------------------------------------
test("P.startsWithStr / endsWithStr", function()
    assertTrue(m.isMatching(P.startsWithStr("foo"), "foobar"))
    assertFalse(m.isMatching(P.startsWithStr("foo"), "barfoo"))
    assertTrue(m.isMatching(P.endsWithStr("bar"), "foobar"))
    assertFalse(m.isMatching(P.endsWithStr("bar"), "barfoo"))
end)
test("P.minLengthStr / maxLengthStr / lengthStr", function()
    assertTrue(m.isMatching(P.minLengthStr(3), "abc"))
    assertFalse(m.isMatching(P.minLengthStr(3), "ab"))
    assertTrue(m.isMatching(P.maxLengthStr(3), "abc"))
    assertFalse(m.isMatching(P.maxLengthStr(3), "abcd"))
    assertTrue(m.isMatching(P.lengthStr(3), "abc"))
    assertFalse(m.isMatching(P.lengthStr(3), "ab"))
end)
test("P.includesStr", function()
    assertTrue(m.isMatching(P.includesStr("oba"), "foobar"))
    assertFalse(m.isMatching(P.includesStr("xyz"), "foobar"))
end)
test("P.luaPattern", function()
    assertTrue(m.isMatching(P.luaPattern("^%d+$"), "12345"))
    assertFalse(m.isMatching(P.luaPattern("^%d+$"), "abc"))
end)

------------------------------------------------------------
-- Composers
------------------------------------------------------------
test("P.union literals", function()
    local pat = P.union("a", "b", "c")
    assertTrue(m.isMatching(pat, "a"))
    assertTrue(m.isMatching(pat, "b"))
    assertFalse(m.isMatching(pat, "d"))
end)
test("P.union with nil and NaN", function()
    local pat = P.union(nil, 0/0, "x")
    assertTrue(m.isMatching(pat, nil))
    assertTrue(m.isMatching(pat, 0/0))
    assertTrue(m.isMatching(pat, "x"))
    assertFalse(m.isMatching(pat, "y"))
end)
test("P.when predicate", function()
    local pat = P.when(function(v) return type(v) == "number" and v > 100 end)
    assertTrue(m.isMatching(pat, 200))
    assertFalse(m.isMatching(pat, 50))
end)
test("P.not_ negation", function()
    assertTrue(m.isMatching(P.not_(P.string), 42))
    assertFalse(m.isMatching(P.not_(P.string), "hi"))
end)
test("P.optional", function()
    local pat = P.optional(P.string)
    assertTrue(m.isMatching(pat, nil))
    assertTrue(m.isMatching(pat, "hi"))
    assertFalse(m.isMatching(pat, 42))
end)
test("P.intersection", function()
    local pat = P.intersection(P.string, P.minLengthStr(3))
    assertTrue(m.isMatching(pat, "hello"))
    assertFalse(m.isMatching(pat, "hi"))
    assertFalse(m.isMatching(pat, 42))
end)
test("P.instanceOf with metatable", function()
    local mt = {}
    local obj = setmetatable({}, mt)
    local other = setmetatable({}, {})
    assertTrue(m.isMatching(P.instanceOf(mt), obj))
    assertFalse(m.isMatching(P.instanceOf(mt), other))
    assertFalse(m.isMatching(P.instanceOf(mt), {}))
end)

------------------------------------------------------------
-- Array patterns
------------------------------------------------------------
test("P.array all match", function()
    assertTrue(m.isMatching(P.array(P.number), {1, 2, 3}))
    assertFalse(m.isMatching(P.array(P.number), {1, "x", 3}))
    assertTrue(m.isMatching(P.array(P.number), {}))
end)
test("P.tuple exact length and positional", function()
    local pat = P.tuple(P.string, P.number)
    assertTrue(m.isMatching(pat, {"hi", 42}))
    assertFalse(m.isMatching(pat, {"hi"}))
    assertFalse(m.isMatching(pat, {"hi", 42, "extra"}))
    assertFalse(m.isMatching(pat, {42, "hi"}))
end)
test("P.startsWith / endsWith", function()
    assertTrue(m.isMatching(P.startsWith(1, 2), {1, 2, 3, 4}))
    assertFalse(m.isMatching(P.startsWith(1, 2), {1}))
    assertTrue(m.isMatching(P.endsWith(3, 4), {1, 2, 3, 4}))
    assertFalse(m.isMatching(P.endsWith(3, 4), {3}))
end)
test("P.arrayOf min/max", function()
    assertTrue(m.isMatching(P.arrayOf(P.number, {min=2, max=4}), {1, 2, 3}))
    assertFalse(m.isMatching(P.arrayOf(P.number, {min=2}), {1}))
    assertFalse(m.isMatching(P.arrayOf(P.number, {max=2}), {1, 2, 3}))
end)
test("P.arrayIncludes", function()
    assertTrue(m.isMatching(P.arrayIncludes(2), {1, 2, 3}))
    assertFalse(m.isMatching(P.arrayIncludes(99), {1, 2, 3}))
end)

------------------------------------------------------------
-- Top-level array sugar (= union)
------------------------------------------------------------
test("array literal as top-level pattern = union", function()
    assertTrue(m.isMatching({"GET", "POST", "PUT"}, "POST"))
    assertFalse(m.isMatching({"GET", "POST"}, "DELETE"))
end)

------------------------------------------------------------
-- Object shape (partial)
------------------------------------------------------------
test("partial shape match", function()
    local pat = { kind = "click", x = P.number }
    assertTrue(m.isMatching(pat, { kind = "click", x = 5, extra = "ok" }))
    assertFalse(m.isMatching(pat, { kind = "key" }))
end)

------------------------------------------------------------
-- BigInt
------------------------------------------------------------
test("BigInt basic comparisons", function()
    local a = BigInt.new(123)
    local b = BigInt.new("123")
    local c = BigInt.new("-456")
    assertTrue(a == b)
    assertTrue(c < a)
    assertTrue(a > c)
    assertTrue(BigInt.new("99999999999999999999") > BigInt.new("99999999999999999998"))
    assertEq(tostring(a), "123")
    assertEq(tostring(c), "-456")
end)
test("BigInt zero canonical", function()
    local z = BigInt.new(0)
    local nz = BigInt.new("-0")
    assertTrue(z == nz)
    assertEq(tostring(nz), "0")
end)
test("BigInt unary minus", function()
    local a = BigInt.new(5)
    local na = -a
    assertEq(tostring(na), "-5")
    assertTrue(na < a)
end)
test("P.bigint detection", function()
    assertTrue(m.isMatching(P.bigint, BigInt.new(42)))
    assertFalse(m.isMatching(P.bigint, 42))
end)
test("P.bigintGt / Between", function()
    assertTrue(m.isMatching(P.bigintGt(10), BigInt.new(20)))
    assertFalse(m.isMatching(P.bigintGt(10), BigInt.new(5)))
    assertTrue(m.isMatching(P.bigintBetween(1, 10), BigInt.new(5)))
    assertFalse(m.isMatching(P.bigintBetween(1, 10), BigInt.new(11)))
end)
test("P.bigintPositive / Negative", function()
    assertTrue(m.isMatching(P.bigintPositive, BigInt.new(1)))
    assertFalse(m.isMatching(P.bigintPositive, BigInt.new(0)))
    assertFalse(m.isMatching(P.bigintPositive, BigInt.new(-1)))
    assertTrue(m.isMatching(P.bigintNegative, BigInt.new(-1)))
end)

------------------------------------------------------------
-- Map / Set
------------------------------------------------------------
test("Map basic ops + insertion order", function()
    local mp = Map.new()
    mp:set("a", 1):set("b", 2):set("c", 3)
    assertEq(mp.size, 3)
    assertEq(mp:get("b"), 2)
    assertTrue(mp:has("a"))
    local keys = {}
    for k in mp:keys() do keys[#keys + 1] = k end
    assertEq(table.concat(keys, ","), "a,b,c")
end)
test("Map all key types incl. nil/NaN/table", function()
    local mp = Map.new()
    local key1, key2 = {}, {}
    mp:set(nil, "nil-val")
    mp:set(0/0, "nan-val")
    mp:set(key1, "k1")
    mp:set(key2, "k2")
    assertEq(mp:get(nil), "nil-val")
    assertEq(mp:get(0/0), "nan-val")
    assertEq(mp:get(key1), "k1")
    assertEq(mp:get(key2), "k2")
    assertEq(mp.size, 4)
end)
test("Map delete updates linked list", function()
    local mp = Map.new()
    mp:set("a", 1):set("b", 2):set("c", 3)
    assertTrue(mp:delete("b"))
    assertFalse(mp:has("b"))
    assertEq(mp.size, 2)
    local keys = {}
    for k in mp:keys() do keys[#keys + 1] = k end
    assertEq(table.concat(keys, ","), "a,c")
end)
test("Set basic", function()
    local s = Set.new({1, 2, 3, 2, 1})
    assertEq(s.size, 3)
    assertTrue(s:has(2))
    assertFalse(s:has(99))
    local items = {}
    for it in s:items() do items[#items + 1] = tostring(it) end
    assertEq(table.concat(items, ","), "1,2,3")
end)
test("P.map pattern", function()
    local mp = Map.new({{ "a", 1 }, { "b", 2 }})
    assertTrue(m.isMatching(P.map(P.string, P.number), mp))
    local mpBad = Map.new({{ 1, "x" }})
    assertFalse(m.isMatching(P.map(P.string, P.number), mpBad))
end)
test("P.set pattern", function()
    local s = Set.new({1, 2, 3})
    assertTrue(m.isMatching(P.set(P.number), s))
    local sBad = Set.new({1, "x"})
    assertFalse(m.isMatching(P.set(P.number), sBad))
end)

------------------------------------------------------------
-- Select extraction
------------------------------------------------------------
test("P.select() — single anonymous", function()
    local rules = {
        { with = { user = { id = P.select() } }, handler = function(id) return id end },
    }
    assertEq(m.match({ user = { id = 42 } }, rules), 42)
end)
test("P.select(label) — labelled", function()
    local rules = {
        { with = { user = { id = P.select("uid"), name = P.select("nm") } },
          handler = function(sel) return sel.uid .. ":" .. sel.nm end },
    }
    assertEq(m.match({ user = { id = 1, name = "Bob" } }, rules), "1:Bob")
end)
test("P.select(subPattern) — refined", function()
    local rules = {
        { with = { age = P.select(P.gte(18)) },
          handler = function(age) return "adult:" .. age end },
        { with = { age = P.number },
          handler = function() return "minor" end },
    }
    assertEq(m.match({ age = 30 }, rules), "adult:30")
    assertEq(m.match({ age = 10 }, rules), "minor")
end)

------------------------------------------------------------
-- Dispatch paths
------------------------------------------------------------
test("match + otherwise", function()
    local rules = {
        { with = "a", handler = function() return 1 end },
        { with = "b", handler = function() return 2 end },
        { otherwise = function() return -1 end },
    }
    assertEq(m.match("a", rules), 1)
    assertEq(m.match("b", rules), 2)
    assertEq(m.match("z", rules), -1)
end)
test("match throws on non-exhaustive", function()
    local rules = { { with = "a", handler = function() return 1 end } }
    assertThrows(function() m.match("z", rules) end)
end)
test("match() data-driven", function()
    local rules = {
        { with = "a", handler = function() return 1 end },
        { with = "b", handler = function() return 2 end },
        { otherwise = function() return -1 end },
    }
    assertEq(m.match("a", rules), 1)
    assertEq(m.match("b", rules), 2)
    assertEq(m.match("z", rules), -1)
end)
test("compile() returns raw dispatch fn", function()
    local rules = {
        { with = P.string, handler = function(v) return "s:" .. v end },
        { with = P.number, handler = function(v) return "n:" .. v end },
        { otherwise = function() return "?" end },
    }
    local fn = m.compile(rules)
    assertEq(fn("hi"), "s:hi")
    assertEq(fn(42), "n:42")
end)
test("matcher chained", function()
    local fn = m.matcher()
        :with(P.string, function(v) return "s:" .. v end)
        :with(P.number, function(v) return "n:" .. v end)
        :otherwise(function() return "?" end)
    assertEq(fn("hi"), "s:hi")
    assertEq(fn(42), "n:42")
    assertEq(fn(true), "?")
end)
test("matcher exhaustive without otherwise", function()
    local fn = m.matcher()
        :with("a", function() return 1 end)
        :with("b", function() return 2 end)
        :exhaustive()
    assertEq(fn("a"), 1)
    assertThrows(function() fn("z") end)
end)
test("matcher :run inline", function()
    local mt = m.matcher()
        :with("hi", function() return "greet" end)
        :with("bye", function() return "leave" end)
    assertEq(mt:run("hi"), "greet")
    assertEq(mt:run("bye"), "leave")
end)

------------------------------------------------------------
-- Fast-path Map vs complex bucket
------------------------------------------------------------
test("all-literal rules → Map fast path", function()
    local rules = {
        { with = "GET",    handler = function() return 1 end },
        { with = "POST",   handler = function() return 2 end },
        { with = "PUT",    handler = function() return 3 end },
        { with = "DELETE", handler = function() return 4 end },
        { otherwise = function() return -1 end },
    }
    local fn = m.compile(rules)
    assertEq(fn("GET"), 1)
    assertEq(fn("DELETE"), 4)
    assertEq(fn("OPTIONS"), -1)
end)
test("mixed literal + complex", function()
    local rules = {
        { with = 0,          handler = function() return "zero" end },
        { with = P.negative, handler = function() return "neg" end },
        { with = P.positive, handler = function() return "pos" end },
    }
    local fn = m.compile(rules)
    assertEq(fn(0), "zero")
    assertEq(fn(-3), "neg")
    assertEq(fn(7), "pos")
end)
test("guard via 'when'", function()
    local rules = {
        { with = P.number, when = function(v) return v > 100 end,
          handler = function() return "big" end },
        { with = P.number, handler = function() return "small" end },
    }
    local fn = m.compile(rules)
    assertEq(fn(200), "big")
    assertEq(fn(5), "small")
end)
test("nil and NaN values fall through correctly", function()
    local rules = {
        { with = P.nullish, handler = function() return "null" end },
        { with = P.when(function(v) return type(v) == "number" and v ~= v end),
          handler = function() return "nan" end },
        { with = P.number,  handler = function() return "num" end },
        { otherwise = function() return "other" end },
    }
    local fn = m.compile(rules)
    assertEq(fn(nil), "null")
    assertEq(fn(0/0), "nan")
    assertEq(fn(42), "num")
    assertEq(fn("x"), "other")
end)
test("rule shape : with + handler", function()
    local rules = { { with = "a", handler = function() return 1 end } }
    assertEq(m.match("a", rules), 1)
end)

------------------------------------------------------------
-- isMatching as standalone gate
------------------------------------------------------------
test("isMatching as filter", function()
    local data = {{age=10}, {age=20}, {age=30}}
    local pat = { age = P.gte(18) }
    local kept = {}
    for i = 1, #data do
        if m.isMatching(pat, data[i]) then kept[#kept + 1] = data[i].age end
    end
    assertEq(table.concat(kept, ","), "20,30")
end)

------------------------------------------------------------
-- DSL parser tests (M1) — only when running against sources.
------------------------------------------------------------
if mode ~= "dist" then
    local env = {
        test = test, assertEq = assertEq, assertTrue = assertTrue,
        assertFalse = assertFalse, assertThrows = assertThrows,
    }
    dofile("tests/dsl_test.lua")(env)
    dofile("tests/dsl_compile_test.lua")(env, m)
    dofile("tests/matcher_dsl_test.lua")(env, m)
end

------------------------------------------------------------
-- Report
------------------------------------------------------------
print(("\n%d passed, %d failed"):format(passed, failed))
if failed > 0 then
    print("Failures:")
    for i = 1, #failures do
        print("  - " .. failures[i])
    end
    os.exit(1)
end
