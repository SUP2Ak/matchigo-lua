# Patterns — `P.*` reference

Every primitive returns an opaque descriptor consumable by `isMatching`, `match`, `matcher`, etc. Patterns are **immutable**; `_test` is baked at construction (single source of truth in `matchigo/p.lua`).

## Type sentinels (leaves)

| Constructor | Matches when... |
|---|---|
| `P.any` | always (`true`) |
| `P.string` | `type(v) == "string"` |
| `P.number` | `type(v) == "number"` |
| `P.boolean` | `type(v) == "boolean"` |
| `P.func` | `type(v) == "function"` |
| `P.bigint` | `v` is a `BigInt` instance |
| `P.nullish` | `v == nil` |
| `P.defined` (alias `P.nonNullable`) | `v ~= nil` |
| `P.positive` / `P.negative` | number `> 0` / `< 0` |
| `P.integer` | integer number (via `math.type`) |
| `P.finite` | finite number (rejects NaN, ±inf) |
| `P.bigintPositive` / `P.bigintNegative` | signed BigInt |

## Predicates

```lua
P.when(function(v) return type(v) == "string" and #v > 5 end)
P.instanceOf(metatable)
P.luaPattern("^%d+$")  -- via string.match
```

`P.luaPattern` uses **Lua patterns** (the standard library's `string.match`), not PCRE. Use `%d`, `%w`, `[]` classes, `^`/`$` anchors, etc.

## String

```lua
P.startsWithStr("foo")
P.endsWithStr("bar")
P.includesStr("baz")
P.lengthStr(5)        -- exact length
P.minLengthStr(3)
P.maxLengthStr(10)
```

## Number ranges

```lua
P.between(1, 100)      -- inclusive on both ends
P.gt(0)   P.gte(0)
P.lt(10)  P.lte(10)
```

BigInt thresholds: `P.bigintGt`, `P.bigintGte`, `P.bigintLt`, `P.bigintLte`, `P.bigintBetween`.

## Disjunction

```lua
P.union("a", "b", "c", "d")        -- pure values, hash O(1) (NaN/nil safe)
P.anyOf(P.string, P.number)        -- mixed patterns, walk-style O(n)
```

Convention: when every member is a primitive value → `union`. Otherwise → `anyOf`.

## Negation / Optional / Intersection

```lua
P.not_(P.string)               -- match if v is NOT a string
P.optional(P.number)           -- nil or number
P.intersection(P.string, P.startsWithStr("/api/"))
```

## Sequences (arrays / tuples)

```lua
P.array(P.number)              -- every item is a number
P.arrayOf(P.number, { min = 1, max = 10 })   -- + length bounds
P.arrayIncludes(P.string)      -- at least one item matches

P.tuple(P.string, P.number)    -- exactly 2 items, [1]=string, [2]=number
P.startsWith(P.string, P.number)  -- v[1..2] match (free suffix)
P.endsWith(P.string, P.number)    -- v[#-1..#] match (free prefix)
```

## Map / Set (matchigo's own types)

```lua
P.map(P.string, P.number)      -- m.Map<string, number>
P.set(P.number)                -- m.Set<number>
```

These match against the bundled `m.Map` / `m.Set` types only — not raw Lua tables. Use a shape pattern + `pairs` guard if you want to match plain tables instead.

→ Bundled types reference: [`docs/en/types.md`](./types.md).

## Bindings

```lua
-- Capture for handler bindings (see docs/en/matching.md)
P.select()                     -- anonymous capture
P.select("label")              -- named capture
P.select(P.string)             -- refined anonymous (must also match P.string)
P.select("label", P.string)    -- named + refined

-- Custom slice extraction (used by the DSL for named ...rest)
P.captureSlice("rest", function(v) return slice(v) end)
```

`P.captureSlice` is a low-level building block — you're unlikely to need it directly. The DSL emits it for `[a, b, ...tail]` and `{ x, y, ...rest }` forms.

## Bare values & shape tables

Anything that isn't a P descriptor is treated as a literal or a shape:

```lua
m.isMatching("GET", "GET")  --> true   (literal strict equality)
m.isMatching(42, 42)        --> true
m.isMatching(nil, nil)      --> true

-- Plain Lua table = shape (extra keys are ignored)
m.isMatching({ kind = "click" }, { kind = "click", x = 5 })  --> true

-- Top-level array = sugar for P.union over its items (literals)
m.isMatching({ "a", "b", "c" }, "b")  --> true
```

## Helpers

```lua
m.isP(v)        --> v is a P-tagged descriptor
m.isSelect(v)   --> v is a P.select descriptor
```
