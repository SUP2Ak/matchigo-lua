local M = {}

---@type fun(n: any): "integer"|"float"|nil
M.mathType = math.type or function(n)
    if type(n) ~= "number" then return nil end
    if n ~= n or n == math.huge or n == -math.huge then return "float" end
    return (math.floor(n) == n) and "integer" or "float"
end

-- isArray : strict 1..n contiguous sequence with no extra keys.
-- Lua has no portable built-in :
--   - `table.type` (suggested for 5.5, present on CFX-patched runtimes) returns
--     "array"|"hash"|"mixed"|"empty" — useful as a quick negative filter, but
--     positive cases still need verification (some platforms tag sparse tables
--     "array" via their internal layout hint).
--   - `#t` is undefined-behavior on sparse tables.
-- Strategy : single-pass via pairs with fail-fast bounds check, plus an
-- optional quick-reject through `table.type` when present.

local nativeTableType = table.type

local function pureIsArray(t)
    local n = #t
    if n == 0 then return next(t) == nil end
    local count = 0
    for k in pairs(t) do
        count = count + 1
        if type(k) ~= "number" or k % 1 ~= 0 or k < 1 or k > n then
            return false
        end
    end
    return count == n
end

---@type fun(t: any): boolean
M.isArray = nativeTableType
    and function(t)
        if type(t) ~= "table" then return false end
        local kind = nativeTableType(t)
        if kind == "hash" or kind == "mixed" then return false end
        return pureIsArray(t)
    end
    or function(t)
        if type(t) ~= "table" then return false end
        return pureIsArray(t)
    end

return M
