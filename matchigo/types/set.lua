-- Insertion-ordered set with full item-type support (any value, including nil,
-- NaN, and tables compared by identity). Same linked-list trick as Map.

local M = {}

local mt = {}

local NIL_ITEM = {}
local NAN_ITEM = {}

local function normalizeItem(v)
    if v == nil then return NIL_ITEM end
    if v ~= v then return NAN_ITEM end
    return v
end

local function denormalizeItem(v)
    if v == NIL_ITEM then return nil end
    if v == NAN_ITEM then return 0 / 0 end
    return v
end

---@param v any
---@return boolean
local function isSet(v)
    return type(v) == "table" and getmetatable(v) == mt
end
M.isSet = isSet

local methods = {}
mt.__index = methods

---@param items? table  array of items
---@return matchigo.Set
function M.new(items)
    local self = setmetatable({
        _byItem = {},
        _head = nil,
        _tail = nil,
        size = 0,
    }, mt)
    if items ~= nil then
        local n = #items
        for i = 1, n do
            self:add(items[i])
        end
    end
    return self
end

function methods:has(item)
    return self._byItem[normalizeItem(item)] ~= nil
end

function methods:add(item)
    local ni = normalizeItem(item)
    if self._byItem[ni] then return self end
    local entry = { item = ni, prev = self._tail, next = nil }
    self._byItem[ni] = entry
    if self._tail then
        self._tail.next = entry
    else
        self._head = entry
    end
    self._tail = entry
    self.size = self.size + 1
    return self
end

function methods:delete(item)
    local ni = normalizeItem(item)
    local entry = self._byItem[ni]
    if not entry then return false end
    self._byItem[ni] = nil
    if entry.prev then entry.prev.next = entry.next else self._head = entry.next end
    if entry.next then entry.next.prev = entry.prev else self._tail = entry.prev end
    self.size = self.size - 1
    return true
end

function methods:clear()
    self._byItem = {}
    self._head = nil
    self._tail = nil
    self.size = 0
end

function methods:items()
    local cur = self._head
    return function()
        if not cur then return nil end
        local e = cur
        cur = cur.next
        return denormalizeItem(e.item)
    end
end

function methods:forEach(fn)
    local cur = self._head
    while cur do
        local v = denormalizeItem(cur.item)
        fn(v, v, self)
        cur = cur.next
    end
end

return M
