---@meta

---Insertion-ordered map with full key-type support (any value, including
---nil, NaN, and tables compared by identity).
---@class matchigo.Map
---@field size integer
local Map = {}

---@param key any
---@return any
function Map:get(key) end
---@param key any
---@return boolean
function Map:has(key) end
---@param key any
---@param value any
---@return matchigo.Map
function Map:set(key, value) end
---@param key any
---@return boolean
function Map:delete(key) end
function Map:clear() end
---@return fun(): any, any
function Map:pairs() end
---@return fun(): any
function Map:keys() end
---@return fun(): any
function Map:values() end
---@param fn fun(value: any, key: any, m: matchigo.Map)
function Map:forEach(fn) end

---@class matchigo.MapModule
---@field new fun(entries?: table[]): matchigo.Map
---@field isMap fun(v: any): boolean

return Map
