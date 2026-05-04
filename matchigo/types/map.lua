-- Insertion-ordered map with full key-type support (any value, including nil,
-- NaN, and tables compared by identity).
--
-- Storage: hash bucket _byKey[k] -> entry, plus a doubly-linked list rooted at
-- _head/_tail for O(1) insert/delete with stable iteration order.

local M = {}

local mt = {}

local NIL_KEY = {}
local NAN_KEY = {}

local function normalizeKey(k)
    if k == nil then return NIL_KEY end
    if k ~= k then return NAN_KEY end
    return k
end

local function denormalizeKey(k)
    if k == NIL_KEY then return nil end
    if k == NAN_KEY then return 0 / 0 end
    return k
end

---@param v any
---@return boolean
local function isMap(v)
    return type(v) == "table" and getmetatable(v) == mt
end
M.isMap = isMap

local methods = {}
mt.__index = methods

---@param entries? table  array of {key, value} pairs
---@return matchigo.Map
function M.new(entries)
    local self = setmetatable({
        _byKey = {},
        _head = nil,
        _tail = nil,
        size = 0,
    }, mt)
    if entries ~= nil then
        local n = #entries
        for i = 1, n do
            local e = entries[i]
            self:set(e[1], e[2])
        end
    end
    return self
end

function methods:get(key)
    local entry = self._byKey[normalizeKey(key)]
    return entry and entry.value or nil
end

function methods:has(key)
    return self._byKey[normalizeKey(key)] ~= nil
end

function methods:set(key, value)
    local nk = normalizeKey(key)
    local entry = self._byKey[nk]
    if entry then
        entry.value = value
        return self
    end
    entry = { key = nk, value = value, prev = self._tail, next = nil }
    self._byKey[nk] = entry
    if self._tail then
        self._tail.next = entry
    else
        self._head = entry
    end
    self._tail = entry
    self.size = self.size + 1
    return self
end

function methods:delete(key)
    local nk = normalizeKey(key)
    local entry = self._byKey[nk]
    if not entry then return false end
    self._byKey[nk] = nil
    if entry.prev then entry.prev.next = entry.next else self._head = entry.next end
    if entry.next then entry.next.prev = entry.prev else self._tail = entry.prev end
    self.size = self.size - 1
    return true
end

function methods:clear()
    self._byKey = {}
    self._head = nil
    self._tail = nil
    self.size = 0
end

function methods:pairs()
    local cur = self._head
    return function()
        if not cur then return nil end
        local e = cur
        cur = cur.next
        return denormalizeKey(e.key), e.value
    end
end

function methods:keys()
    local cur = self._head
    return function()
        if not cur then return nil end
        local e = cur
        cur = cur.next
        return denormalizeKey(e.key)
    end
end

function methods:values()
    local cur = self._head
    return function()
        if not cur then return nil end
        local e = cur
        cur = cur.next
        return e.value
    end
end

function methods:forEach(fn)
    local cur = self._head
    while cur do
        fn(cur.value, denormalizeKey(cur.key), self)
        cur = cur.next
    end
end

return M
