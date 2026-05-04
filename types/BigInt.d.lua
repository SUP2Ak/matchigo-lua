---@meta

---Comparison-only BigInt. Sign + magnitude (digit string, no leading zeros
---except canonical "0"). Supports `==`, `<`, `<=`, `>`, `>=`, unary `-`,
---`tostring`. No arithmetic — patterns only need ordering.
---@class matchigo.BigInt
---@field sign 1|-1
---@field digits string  canonical decimal magnitude
local BigInt = {}

---@return boolean
function BigInt:isPositive() end
---@return boolean
function BigInt:isNegative() end
---@return boolean
function BigInt:isZero() end

---@class matchigo.BigIntModule
---@field new fun(v: matchigo.BigInt|number|string): matchigo.BigInt
---@field isBigInt fun(v: any): boolean
---@field compare fun(a: matchigo.BigInt, b: matchigo.BigInt): -1|0|1
---@field ZERO matchigo.BigInt
---@field ONE matchigo.BigInt

return BigInt
