-- Rule-list compiler. Produces a single dispatch function that classifies
-- literal-keyed rules into a hash Map (O(1) fast path) and falls back to
-- a loop over `complex` rules (with `:when` guards / selects / structural
-- patterns) for everything else.
--
-- Pattern-test logic itself lives entirely in matchigo.p (`buildTest` +
-- the `_test` closures baked at construction). compileRules only consumes
-- `pat._test`, never re-implements the pattern semantics.

local p = require("matchigo.p")

local PATTERN = p.PATTERN
local isP = p.isP
local isSelect = p.isSelect
local buildTest = p.buildTest
local type = type
local pairs = pairs

local compat = require("matchigo.util.compat")
local isArray = compat.isArray

local M = {}

-- ── Select extraction (paths through the pattern → handler bindings) ──────

local function appendPath(path, pn, key)
    local out = {}
    for i = 1, pn do out[i] = path[i] end
    out[pn + 1] = key
    return out
end

local function collectSelects(pattern, path, pn)
    path = path or {}
    pn = pn or 0
    if isSelect(pattern) then
        local head = { label = pattern.label, path = path, n = pn }
        local sub = pattern.pattern
        if sub == nil then return { head } end
        local rest = collectSelects(sub, path, pn)
        local out = { head }
        local rn = #rest
        for i = 1, rn do out[i + 1] = rest[i] end
        return out
    end
    if isP(pattern) then
        local tag = pattern[PATTERN]
        if tag == "captureSlice" then
            return { { label = pattern.label,
                       path = appendPath(path, pn, pattern.sliceFn),
                       n = pn + 1 } }
        end
        if tag == "array" or tag == "arrayOf" or tag == "arrayIncludes" then
            return collectSelects(pattern.item, appendPath(path, pn, 1), pn + 1)
        end
        if tag == "tuple" or tag == "startsWith" or tag == "endsWith" then
            local out, on = {}, 0
            local n = pattern.n
            local items = pattern.items
            for i = 1, n do
                local sub = collectSelects(items[i], appendPath(path, pn, i), pn + 1)
                local sn = #sub
                for j = 1, sn do
                    on = on + 1
                    out[on] = sub[j]
                end
            end
            return out
        end
        if tag == "not" or tag == "optional" then
            return collectSelects(pattern.inner, path, pn)
        end
        if tag == "intersection" then
            local out, on = {}, 0
            local n = pattern.n
            local parts = pattern.parts
            for i = 1, n do
                local sub = collectSelects(parts[i], path, pn)
                local sn = #sub
                for j = 1, sn do
                    on = on + 1
                    out[on] = sub[j]
                end
            end
            return out
        end
        return {}
    end
    if type(pattern) ~= "table" then return {} end
    if isArray(pattern) then return {} end
    local out, on = {}, 0
    for k, v in pairs(pattern) do
        local sub = collectSelects(v, appendPath(path, pn, k), pn + 1)
        local sn = #sub
        for i = 1, sn do
            on = on + 1
            out[on] = sub[i]
        end
    end
    return out
end
M.collectSelects = collectSelects

local function readPath(value, path, n)
    local cur = value
    for i = 1, n do
        if cur == nil then return nil end
        local step = path[i]
        if type(step) == "function" then
            cur = step(cur)
        else
            cur = cur[step]
        end
    end
    return cur
end
M.readPath = readPath

-- ── Rule-list compile ────────────────────────────────────────────────────

local function resolveThen(thenVal, selects)
    if type(thenVal) ~= "function" then
        return function(_) return thenVal end
    end
    local nsel = #selects
    -- No selects = the user's handler matches the dispatcher's signature
    -- (one positional arg, returns the result), so we hand it back raw.
    if nsel == 0 then return thenVal end
    local fn = thenVal
    if nsel == 1 and selects[1].label == nil then
        local s = selects[1]
        local path, pn = s.path, s.n
        return function(v) return fn(readPath(v, path, pn), v) end
    end
    return function(v)
        local out = {}
        for i = 1, nsel do
            local s = selects[i]
            local key = s.label or "$0"
            out[key] = readPath(v, s.path, s.n)
        end
        return fn(out, v)
    end
end

local function ruleHandler(rule)
    return rule.handler
end

local function isLiteralKeySafe(v)
    if v == nil then return false end
    if type(v) == "table" then return false end
    return v == v -- excludes NaN
end

function M.compileRules(rules)
    local literalMap = {}
    local literalCount = 0
    local complex = {}
    local complexCount = 0
    local fallback = nil

    local n = #rules
    for i = 1, n do
        local rule = rules[i]
        if rule.otherwise ~= nil then
            local r = rule.otherwise
            if type(r) == "function" then
                fallback = r
            else
                fallback = function(_) return r end
            end
        else
            local pattern = rule.with
            local selects = collectSelects(pattern)
            local thenFn = resolveThen(ruleHandler(rule), selects)
            local guard = rule.when

            if isLiteralKeySafe(pattern)
                and guard == nil
                and #selects == 0
                and literalMap[pattern] == nil
            then
                literalMap[pattern] = thenFn
                literalCount = literalCount + 1
            else
                complexCount = complexCount + 1
                complex[complexCount] = {
                    test = buildTest(pattern),
                    guard = guard,
                    thenFn = thenFn,
                }
            end
        end
    end

    local hasMap = literalCount > 0
    local hasComplex = complexCount > 0

    if hasMap and not hasComplex then
        return function(v)
            local hit = literalMap[v]
            if hit ~= nil then return hit(v) end
            if fallback ~= nil then return fallback(v) end
            error("Non-exhaustive match", 0)
        end
    end
    if not hasMap and hasComplex then
        return function(v)
            for i = 1, complexCount do
                local r = complex[i]
                if r.test(v) and (r.guard == nil or r.guard(v)) then
                    return r.thenFn(v)
                end
            end
            if fallback ~= nil then return fallback(v) end
            error("Non-exhaustive match", 0)
        end
    end
    return function(v)
        local hit = literalMap[v]
        if hit ~= nil then return hit(v) end
        for i = 1, complexCount do
            local r = complex[i]
            if r.test(v) and (r.guard == nil or r.guard(v)) then
                return r.thenFn(v)
            end
        end
        if fallback ~= nil then return fallback(v) end
        error("Non-exhaustive match", 0)
    end
end

return M
