-- Chained matcher. Optionally captures a (scope, ctx) pair — when set, any
-- string passed to `:with(...)` is auto-parsed via `parsePattern(string,
-- scope, ctx)` ; non-string patterns (raw P descriptors / shapes / literals)
-- always pass through untouched.
--
-- This is the canonical chained API. Without args, behaviour is identical
-- to the previous `matcher()` (raw P only).

local compile      = require("matchigo.compile")
local parsePatMod  = require("matchigo.parsePattern")

local parsePattern = parsePatMod.parsePattern

local M = {}

local matcherMt = {}
local methods = {}
matcherMt.__index = methods

function methods:with(pattern, a, b)
    self._cached = nil
    if self._dsl and type(pattern) == "string" then
        pattern = parsePattern(pattern, self._scope, self._ctx)
    end
    local rules = self._rules
    local i = #rules + 1
    if b ~= nil then
        rules[i] = { with = pattern, when = a, handler = b }
    else
        rules[i] = { with = pattern, handler = a }
    end
    return self
end

function methods:otherwise(result)
    self._cached = nil
    local rules = self._rules
    rules[#rules + 1] = { otherwise = result }
    return self:compile()
end

function methods:exhaustive()
    return self:compile()
end

function methods:run(value)
    if self._cached == nil then
        self._cached = compile.compileRules(self._rules)
    end
    return self._cached(value)
end

function methods:compile()
    if self._cached == nil then
        self._cached = compile.compileRules(self._rules)
    end
    return self._cached
end

-- Passing `scope` or `ctx` (even an empty table) opts the matcher into
-- DSL mode : every subsequent `:with(string, ...)` is auto-parsed via
-- `parsePattern(string, scope, ctx)`. Without args, strings are treated
-- as literal patterns (preserves the no-DSL contract).
---@param scope? table  PascalCase ref bindings used by `:with(string, ...)`
---@param ctx? table    `$interp` values used by `:with(string, ...)`
function M.matcher(scope, ctx)
    return setmetatable({
        _rules  = {},
        _cached = nil,
        _scope  = scope or {},
        _ctx    = ctx or {},
        _dsl    = scope ~= nil or ctx ~= nil,
    }, matcherMt)
end

return M
