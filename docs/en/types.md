# Bundled types — `m.BigInt`, `m.Map`, `m.Set`

Lua has no native equivalents to JS's `BigInt`, ordered `Map`, or `Set`. matchigo-lua ships its own minimal versions, used by `P.bigint*`, `P.map`, `P.set`. They're also re-exported on the public surface so you can use them directly.

## `m.BigInt`

A decimal-string BigInt. Supports comparison and equality (no arithmetic). Used by the `P.bigint*` patterns.

```lua
local big = m.BigInt.new("123456789012345678901234567890")
local neg = m.BigInt.new(-42)
local zero = m.BigInt.ZERO
local one  = m.BigInt.ONE
```

### API

| Symbol | Description |
|---|---|
| `m.BigInt.new(v)` | construct from `number` (must be a finite integer), `string` (`-?\d+`), or another `BigInt` (returns it as-is) |
| `m.BigInt.isBigInt(v)` | `true` if `v` is a BigInt |
| `m.BigInt.compare(a, b)` | `-1` / `0` / `1` |
| `m.BigInt.ZERO` / `m.BigInt.ONE` | shared singletons |

### Metamethods

`==`, `<`, `<=`, unary `-`, `tostring` all work on BigInt values:

```lua
m.BigInt.new("100") < m.BigInt.new("200")     --> true
-m.BigInt.new("5")                            --> BigInt -5
tostring(m.BigInt.new("42"))                  --> "42"
```

### Instance methods

```lua
local n = m.BigInt.new("42")
n:isPositive()  --> true
n:isNegative()  --> false
n:isZero()      --> false
```

### Limitations

No arithmetic (`+`, `-`, `*`, `/`). The use case is comparison and storage, not maths. If you need full big-number arithmetic, use a dedicated library (e.g. `lua-bn`).

## `m.Map`

An ordered key/value map. Insertion order is preserved across `pairs`/`keys`/`values`. Keys can be any Lua value, including `nil` and `NaN` (normalized internally to sentinel keys).

```lua
local mp = m.Map.new({ {"a", 1}, {"b", 2} })  -- entries as { key, value } tuples
mp:set("c", 3)
mp:get("a")                                    --> 1
mp.size                                        --> 3

for k, v in mp:pairs() do
    print(k, v)  -- "a" 1, "b" 2, "c" 3 (insertion order)
end
```

### API

| Symbol | Description |
|---|---|
| `m.Map.new(entries?)` | optional array of `{ key, value }` pairs |
| `m.Map.isMap(v)` | `true` if `v` is a Map |

### Instance methods

| Method | Description |
|---|---|
| `:get(key)` | value or `nil` |
| `:has(key)` | `true` / `false` |
| `:set(key, value)` | inserts or updates; returns `self` (chainable) |
| `:delete(key)` | `true` if removed, `false` if absent |
| `:clear()` | empty the map |
| `:pairs()` | iterator → `key, value` (insertion order) |
| `:keys()` | iterator → `key` |
| `:values()` | iterator → `value` |
| `:forEach(fn)` | `fn(value, key, self)` for each entry |

### Field

- `.size` — read-only entry count.

### Pattern usage

```lua
m.isMatching(P.map(P.string, P.number), m.Map.new({ {"a", 1}, {"b", 2} }))  --> true
```

`P.map` only matches `m.Map` instances — not raw Lua tables.

## `m.Set`

An ordered, NaN-safe set. Insertion order is preserved across `items`/`forEach`. Items can be any Lua value, including `nil` and `NaN`.

```lua
local s = m.Set.new({ "a", "b", "c" })
s:add("d")
s:has("a")    --> true
s.size        --> 4

for v in s:items() do print(v) end
```

### API

| Symbol | Description |
|---|---|
| `m.Set.new(items?)` | optional array of items |
| `m.Set.isSet(v)` | `true` if `v` is a Set |

### Instance methods

| Method | Description |
|---|---|
| `:has(item)` | `true` / `false` |
| `:add(item)` | inserts (no-op if present); returns `self` |
| `:delete(item)` | `true` if removed, `false` if absent |
| `:clear()` | empty the set |
| `:items()` | iterator → `item` (insertion order) |
| `:forEach(fn)` | `fn(item, item, self)` for each entry |

### Field

- `.size` — read-only item count.

### Pattern usage

```lua
m.isMatching(P.set(P.string), m.Set.new({ "a", "b" }))  --> true
```

`P.set` only matches `m.Set` instances — not raw Lua tables.

## When (not) to use these

- **Use the bundled types** when you need insertion order, NaN/nil-safe keys, or pattern interop with `P.map`/`P.set`.
- **Use plain Lua tables** for everything else — they're cheaper and idiomatic. matchigo's shape patterns (`{ kind = "x", ... }`) work directly on plain tables; you only reach for `m.Map`/`m.Set` when those affordances matter.
