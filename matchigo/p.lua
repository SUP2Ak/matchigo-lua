-- Pattern descriptors. Single source of truth for pattern-test logic :
-- every P.* constructor (leaf and composite) bakes its `_test` closure at
-- construction. `buildTest(pat)` is the recursive entry that resolves a
-- pattern (P descriptor, bare value, plain shape, top-level array union)
-- into a `function(v) -> bool` predicate ; composites call it on their
-- inner patterns and capture the result. compile.lua and walk.lua both
-- consume `pat._test` directly — no more parallel `compilers[]` /
-- `testers[]` dispatch tables.

local compat = require("matchigo.util.compat")
local BigInt = require("matchigo.types.bigint")
local Map    = require("matchigo.types.map")
local Set    = require("matchigo.types.set")

local mathType  = compat.mathType
local isArray   = compat.isArray
local newBigInt = BigInt.new
local isBigInt  = BigInt.isBigInt
local isMap     = Map.isMap
local isSet     = Set.isSet

local huge = math.huge
local sfind = string.find
local smatch = string.match
local ssub = string.sub
local type = type
local pairs = pairs
local getmetatable = getmetatable
local select = select

local M = {}

local PATTERN = {}
M.PATTERN = PATTERN

local function leaf(name, test)
    return { [PATTERN] = name, _test = test }
end

local function tag(name, t)
    t = t or {}
    t[PATTERN] = name
    return t
end

---@param v any
---@return boolean
local function isP(v)
    return type(v) == "table" and v[PATTERN] ~= nil
end
M.isP = isP

---@param v any
---@return boolean
local function isSelect(v)
    return isP(v) and v[PATTERN] == "select"
end
M.isSelect = isSelect

-- ── buildTest : pattern → predicate ─────────────────────────────────────
local buildTest

local function buildTopArrayTest(arr)
    local set, hasNan, hasNil = {}, false, false
    local n = #arr
    for i = 1, n do
        local v = arr[i]
        if v == nil then hasNil = true
        elseif v ~= v then hasNan = true
        else set[v] = true end
    end
    return function(v)
        if v == nil then return hasNil end
        if v ~= v then return hasNan end
        return set[v] == true
    end
end

local function buildShapeTest(shape)
    local entries, n = {}, 0
    for k, sub in pairs(shape) do
        n = n + 1
        entries[n] = { key = k, test = buildTest(sub) }
    end
    return function(v)
        if type(v) ~= "table" then return false end
        for i = 1, n do
            local e = entries[i]
            if not e.test(v[e.key]) then return false end
        end
        return true
    end
end

-- Weak cache for plain-table patterns (shapes / top-level array unions).
-- P descriptors carry their own `_test` baked at construction so they
-- don't go through the cache. Plain Lua tables don't, so without caching
-- every isMatching call would rebuild a fresh closure (entries table +
-- closure allocation) — keyed weak so user patterns aren't pinned.
local plainCache = setmetatable({}, { __mode = "k" })

buildTest = function(pat)
    if pat == nil then
        return function(v) return v == nil end
    end
    if type(pat) ~= "table" then
        local lit = pat
        if lit ~= lit then
            return function(v) return v ~= v end
        end
        return function(v) return v == lit end
    end
    if pat._test ~= nil then return pat._test end
    if pat[PATTERN] ~= nil then
        error("buildTest : P descriptor missing _test for tag " .. tostring(pat[PATTERN]), 0)
    end
    local cached = plainCache[pat]
    if cached ~= nil then return cached end
    if isArray(pat) then
        cached = buildTopArrayTest(pat)
    else
        cached = buildShapeTest(pat)
    end
    plainCache[pat] = cached
    return cached
end
M.buildTest = buildTest

local P = {}

-- ── Leaf sentinels ────────────────────────────────────────────────────────
P.any            = leaf("any",            function() return true end)
P.string         = leaf("string",         function(v) return type(v) == "string" end)
P.number         = leaf("number",         function(v) return type(v) == "number" end)
P.boolean        = leaf("boolean",        function(v) return type(v) == "boolean" end)
P.bigint         = leaf("bigint",         function(v) return isBigInt(v) end)
P.func           = leaf("function",       function(v) return type(v) == "function" end)
P.nullish        = leaf("nullish",        function(v) return v == nil end)
P.defined        = leaf("defined",        function(v) return v ~= nil end)
P.nonNullable    = P.defined
P.positive       = leaf("positive",       function(v) return type(v) == "number" and v > 0 end)
P.negative       = leaf("negative",       function(v) return type(v) == "number" and v < 0 end)
P.integer        = leaf("integer",        function(v) return mathType(v) == "integer" end)
P.float          = leaf("float",          function(v) return mathType(v) == "float"   end)
P.finite         = leaf("finite",         function(v)
    return type(v) == "number" and v == v and v ~= huge and v ~= -huge
end)
P.bigintPositive = leaf("bigintPositive", function(v) return isBigInt(v) and v:isPositive() end)
P.bigintNegative = leaf("bigintNegative", function(v) return isBigInt(v) and v:isNegative() end)

-- ── Parameterised leafs (closure captures params) ─────────────────────────
function P.when(fn)
    return { [PATTERN] = "when", fn = fn, _test = fn }
end

function P.instanceOf(mt)
    return { [PATTERN] = "instanceOf", mt = mt,
             _test = function(v) return type(v) == "table" and getmetatable(v) == mt end }
end

function P.luaPattern(pat)
    return { [PATTERN] = "luaPattern", pat = pat,
             _test = function(v) return type(v) == "string" and smatch(v, pat) ~= nil end }
end

function P.startsWithStr(s)
    local len = #s
    return { [PATTERN] = "startsWithStr", s = s,
             _test = function(v) return type(v) == "string" and ssub(v, 1, len) == s end }
end

function P.endsWithStr(s)
    local len = #s
    return { [PATTERN] = "endsWithStr", s = s,
             _test = function(v) return type(v) == "string" and ssub(v, -len) == s end }
end

function P.minLengthStr(n)
    return { [PATTERN] = "minLengthStr", n = n,
             _test = function(v) return type(v) == "string" and #v >= n end }
end
function P.maxLengthStr(n)
    return { [PATTERN] = "maxLengthStr", n = n,
             _test = function(v) return type(v) == "string" and #v <= n end }
end
function P.lengthStr(n)
    return { [PATTERN] = "lengthStr", n = n,
             _test = function(v) return type(v) == "string" and #v == n end }
end
function P.includesStr(s)
    return { [PATTERN] = "includesStr", s = s,
             _test = function(v) return type(v) == "string" and sfind(v, s, 1, true) ~= nil end }
end

function P.between(min, max)
    return { [PATTERN] = "between", min = min, max = max,
             _test = function(v) return type(v) == "number" and v >= min and v <= max end }
end
function P.gt(n)  return { [PATTERN] = "gt",  n = n,
                           _test = function(v) return type(v) == "number" and v >  n end } end
function P.gte(n) return { [PATTERN] = "gte", n = n,
                           _test = function(v) return type(v) == "number" and v >= n end } end
function P.lt(n)  return { [PATTERN] = "lt",  n = n,
                           _test = function(v) return type(v) == "number" and v <  n end } end
function P.lte(n) return { [PATTERN] = "lte", n = n,
                           _test = function(v) return type(v) == "number" and v <= n end } end

function P.bigintGt(n)
    n = newBigInt(n)
    return { [PATTERN] = "bigintGt", n = n,
             _test = function(v) return isBigInt(v) and v >  n end }
end
function P.bigintGte(n)
    n = newBigInt(n)
    return { [PATTERN] = "bigintGte", n = n,
             _test = function(v) return isBigInt(v) and v >= n end }
end
function P.bigintLt(n)
    n = newBigInt(n)
    return { [PATTERN] = "bigintLt", n = n,
             _test = function(v) return isBigInt(v) and v <  n end }
end
function P.bigintLte(n)
    n = newBigInt(n)
    return { [PATTERN] = "bigintLte", n = n,
             _test = function(v) return isBigInt(v) and v <= n end }
end
function P.bigintBetween(min, max)
    min = newBigInt(min); max = newBigInt(max)
    return { [PATTERN] = "bigintBetween", min = min, max = max,
             _test = function(v) return isBigInt(v) and v >= min and v <= max end }
end

-- Union : precompute hash set (O(1) lookup) at construction. NaN/nil are
-- shielded into flags because Lua tables can't key on either.
function P.union(...)
    local values, n = { ... }, select("#", ...)
    local set, hasNan, hasNil = {}, false, false
    for i = 1, n do
        local v = values[i]
        if v == nil then hasNil = true
        elseif v ~= v then hasNan = true
        else set[v] = true end
    end
    return {
        [PATTERN] = "union", values = values, n = n,
        _test = function(v)
            if v == nil then return hasNil end
            if v ~= v then return hasNan end
            return set[v] == true
        end,
    }
end

-- ── Composites : eager _test built via buildTest(inner) ──────────────────
function P.not_(inner)
    local innerTest = buildTest(inner)
    return tag("not", { inner = inner,
        _test = function(v) return not innerTest(v) end })
end

function P.optional(inner)
    local innerTest = buildTest(inner)
    return tag("optional", { inner = inner,
        _test = function(v) return v == nil or innerTest(v) end })
end

function P.array(item)
    local itemTest = buildTest(item)
    return tag("array", { item = item,
        _test = function(v)
            if type(v) ~= "table" then return false end
            local n = #v
            for i = 1, n do
                if not itemTest(v[i]) then return false end
            end
            return true
        end })
end

---@param item any
---@param opts? { min?: integer, max?: integer }
function P.arrayOf(item, opts)
    local itemTest = buildTest(item)
    local min = opts and opts.min
    local max = opts and opts.max
    return tag("arrayOf", { item = item, min = min, max = max,
        _test = function(v)
            if type(v) ~= "table" then return false end
            local n = #v
            if min ~= nil and n < min then return false end
            if max ~= nil and n > max then return false end
            for i = 1, n do
                if not itemTest(v[i]) then return false end
            end
            return true
        end })
end

function P.arrayIncludes(item)
    local itemTest = buildTest(item)
    return tag("arrayIncludes", { item = item,
        _test = function(v)
            if type(v) ~= "table" then return false end
            local n = #v
            for i = 1, n do
                if itemTest(v[i]) then return true end
            end
            return false
        end })
end

function P.set(item)
    local itemTest = buildTest(item)
    return tag("set", { item = item,
        _test = function(v)
            if not isSet(v) then return false end
            for it in v:items() do
                if not itemTest(it) then return false end
            end
            return true
        end })
end

function P.map(key, value)
    local keyTest = buildTest(key)
    local valTest = buildTest(value)
    return tag("map", { key = key, value = value,
        _test = function(v)
            if not isMap(v) then return false end
            for k, val in v:pairs() do
                if not keyTest(k) or not valTest(val) then return false end
            end
            return true
        end })
end

function P.intersection(...)
    local parts, n = { ... }, select("#", ...)
    local tests = {}
    for i = 1, n do tests[i] = buildTest(parts[i]) end
    return tag("intersection", { parts = parts, n = n,
        _test = function(v)
            for i = 1, n do
                if not tests[i](v) then return false end
            end
            return true
        end })
end

function P.anyOf(...)
    local items, n = { ... }, select("#", ...)
    local tests = {}
    for i = 1, n do tests[i] = buildTest(items[i]) end
    return tag("anyOf", { items = items, n = n,
        _test = function(v)
            for i = 1, n do
                if tests[i](v) then return true end
            end
            return false
        end })
end

function P.tuple(...)
    local items, n = { ... }, select("#", ...)
    local tests = {}
    for i = 1, n do tests[i] = buildTest(items[i]) end
    return tag("tuple", { items = items, n = n,
        _test = function(v)
            if type(v) ~= "table" or #v ~= n then return false end
            for i = 1, n do
                if not tests[i](v[i]) then return false end
            end
            return true
        end })
end

function P.startsWith(...)
    local items, n = { ... }, select("#", ...)
    local tests = {}
    for i = 1, n do tests[i] = buildTest(items[i]) end
    return tag("startsWith", { items = items, n = n,
        _test = function(v)
            if type(v) ~= "table" or #v < n then return false end
            for i = 1, n do
                if not tests[i](v[i]) then return false end
            end
            return true
        end })
end

function P.endsWith(...)
    local items, n = { ... }, select("#", ...)
    local tests = {}
    for i = 1, n do tests[i] = buildTest(items[i]) end
    return tag("endsWith", { items = items, n = n,
        _test = function(v)
            if type(v) ~= "table" then return false end
            local vn = #v
            if vn < n then return false end
            local offset = vn - n
            for i = 1, n do
                if not tests[i](v[offset + i]) then return false end
            end
            return true
        end })
end

-- Strict shape : like a bare-table pattern but rejects any value carrying
-- keys not declared in `tbl`. Bindings inside (P.select, nested patterns)
-- behave identically to the partial form. Built eagerly : sub-tests baked
-- via buildTest, declared-key set materialised at construction.
function P.shape(tbl)
    if type(tbl) ~= "table" then
        error("P.shape expects a table", 2)
    end
    local entries, n = {}, 0
    local declared = {}
    for k, sub in pairs(tbl) do
        n = n + 1
        entries[n] = { key = k, test = buildTest(sub) }
        declared[k] = true
    end
    return tag("shape", {
        shape = tbl, declared = declared,
        _test = function(v)
            if type(v) ~= "table" then return false end
            for i = 1, n do
                local e = entries[i]
                if not e.test(v[e.key]) then return false end
            end
            for k in pairs(v) do
                if not declared[k] then return false end
            end
            return true
        end
    })
end

-- captureSlice : structural no-op pattern (always matches) whose job is to
-- expose a named binding whose extraction is computed via a closure rather
-- than a static path. Used by the DSL for named-rest bindings.
function P.captureSlice(label, sliceFn)
    return tag("captureSlice", { label = label, sliceFn = sliceFn,
        _test = function() return true end })
end

-- Overloads:
--   P.select()                 -- extract value at this position
--   P.select("label")          -- labelled extract
--   P.select(subPattern)       -- extract only if subPattern matches
--   P.select("label", subPat)  -- labelled + refined
function P.select(arg1, arg2)
    if arg1 == nil and arg2 == nil then
        return tag("select", { label = nil, pattern = nil,
            _test = function() return true end })
    end
    if arg2 == nil then
        if type(arg1) == "string" then
            return tag("select", { label = arg1, pattern = nil,
                _test = function() return true end })
        end
        local innerTest = buildTest(arg1)
        return tag("select", { label = nil, pattern = arg1,
            _test = function(v) return innerTest(v) end })
    end
    local innerTest = buildTest(arg2)
    return tag("select", { label = arg1, pattern = arg2,
        _test = function(v) return innerTest(v) end })
end

M.P = P
return M
