-- Match-mode entries. Both `match` (lazy + cached) and `compile` (eager)
-- return raw Lua functions — no callable-table / `__call` indirection.
-- Hot loops just call the returned fn directly.

local compile = require("matchigo.compile")

local M = {}

local cache = setmetatable({}, { __mode = "k" })

---@param value any
---@param rules table  array of `{ with=..., handler=... }` (and optional `{ otherwise=... }`)
---@return any
function M.match(value, rules)
    local fn = cache[rules]
    if fn == nil then
        fn = compile.compileRules(rules)
        cache[rules] = fn
    end
    return fn(value)
end

---@param rules table
---@return fun(value:any):any  raw dispatch fn
function M.compile(rules)
    return compile.compileRules(rules)
end

return M
