-- Single-pattern test entry point. Pattern semantics live in matchigo.p
-- (every P descriptor carries `_test`, built eagerly at construction).
-- This module exists only to expose `isMatching` as a public function ;
-- everything heavy is in p.lua.

local p = require("matchigo.p")

local buildTest = p.buildTest
local type = type

local M = {}

---@param pattern any
---@param value any
---@return boolean
function M.isMatching(pattern, value)
    if pattern == nil then return value == nil end
    if type(pattern) ~= "table" then
        if pattern ~= pattern then return value ~= value end
        return value == pattern
    end
    if pattern._test ~= nil then return pattern._test(value) end
    return buildTest(pattern)(value)
end

return M
