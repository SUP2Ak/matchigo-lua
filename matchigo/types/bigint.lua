-- Comparison-only BigInt. Sign + magnitude (digit string, no leading zeros
-- except canonical "0"). Supports ==, <, <=, > , >=, unary -, tostring.
-- No arithmetic — patterns only need ordering.

local M = {}

local mt = {}

---@param v any
---@return boolean
local function isBigInt(v)
    return type(v) == "table" and getmetatable(v) == mt
end
M.isBigInt = isBigInt

---@param sign 1|-1
---@param digits string
---@return matchigo.BigInt
local function normalize(sign, digits)
    local i, n = 1, #digits
    while i < n and digits:sub(i, i) == "0" do
        i = i + 1
    end
    digits = digits:sub(i)
    if digits == "0" then sign = 1 end
    return setmetatable({ sign = sign, digits = digits }, mt)
end

---@param v matchigo.BigInt|number|string
---@return matchigo.BigInt
function M.new(v)
    ---@diagnostic disable-next-line: return-type-mismatch
    if isBigInt(v) then return v end
    if type(v) == "number" then
        if v ~= v or v == math.huge or v == -math.huge then
            error("BigInt: cannot construct from non-finite number", 2)
        end
        if v % 1 ~= 0 then
            error("BigInt: cannot construct from non-integer number " .. tostring(v), 2)
        end
        local s = string.format("%.0f", v)
        local sign = 1
        if s:sub(1, 1) == "-" then
            sign = -1
            s = s:sub(2)
        end
        return normalize(sign, s)
    end
    if type(v) == "string" then
        local sign = 1
        local s = v
        local first = s:sub(1, 1)
        if first == "-" then sign = -1; s = s:sub(2)
        elseif first == "+" then s = s:sub(2) end
        if s == "" or not s:match("^%d+$") then
            error("BigInt: invalid string '" .. v .. "'", 2)
        end
        return normalize(sign, s)
    end
    error("BigInt: cannot construct from " .. type(v), 2)
end

---@param a string
---@param b string
---@return -1|0|1
local function compareMagnitude(a, b)
    local la, lb = #a, #b
    if la < lb then return -1
    elseif la > lb then return 1
    elseif a < b then return -1
    elseif a > b then return 1
    else return 0 end
end

---@param a matchigo.BigInt
---@param b matchigo.BigInt
---@return -1|0|1
local function compare(a, b)
    if a.sign ~= b.sign then
        return a.sign < b.sign and -1 or 1
    end
    local m = compareMagnitude(a.digits, b.digits)
    if a.sign == -1 then m = -m end
    return m
end
M.compare = compare

mt.__eq = function(a, b)
    return a.sign == b.sign and a.digits == b.digits
end

mt.__lt = function(a, b)
    return compare(a, b) < 0
end

mt.__le = function(a, b)
    return compare(a, b) <= 0
end

mt.__unm = function(a)
    if a.digits == "0" then return a end
    return setmetatable({ sign = -a.sign, digits = a.digits }, mt)
end

mt.__tostring = function(a)
    return (a.sign == -1 and "-" or "") .. a.digits
end

mt.__index = {
    isPositive = function(self) return self.sign == 1 and self.digits ~= "0" end,
    isNegative = function(self) return self.sign == -1 end,
    isZero     = function(self) return self.digits == "0" end,
}

M.ZERO = normalize(1, "0")
M.ONE  = normalize(1, "1")

return M
