---@meta

---Insertion-ordered set with full item-type support (any value, including
---nil, NaN, and tables compared by identity).
---@class matchigo.Set
---@field size integer
local Set = {}

---@param item any
---@return boolean
function Set:has(item) end
---@param item any
---@return matchigo.Set
function Set:add(item) end
---@param item any
---@return boolean
function Set:delete(item) end
function Set:clear() end
---@return fun(): any
function Set:items() end
---@param fn fun(value: any, value2: any, set: matchigo.Set)
function Set:forEach(fn) end

---@class matchigo.SetModule
---@field new fun(items?: any[]): matchigo.Set
---@field isSet fun(v: any): boolean

return Set
