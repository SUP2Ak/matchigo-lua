# Patterns — référence `P.*`

Toute primitive renvoie un descripteur opaque consommable par `isMatching`, `match`, `matcher`, etc. Les patterns sont **immuables** ; `_test` est baked à la construction (single source of truth dans `matchigo/p.lua`).

## Type sentinels (leaf)

| Constructeur | Match si... |
|---|---|
| `P.any` | `true` (toujours) |
| `P.string` | `type(v) == "string"` |
| `P.number` | `type(v) == "number"` |
| `P.boolean` | `type(v) == "boolean"` |
| `P.func` | `type(v) == "function"` |
| `P.bigint` | `v` est un `BigInt` |
| `P.nullish` | `v == nil` |
| `P.defined` (alias `P.nonNullable`) | `v ~= nil` |
| `P.positive` / `P.negative` | nombre `> 0` / `< 0` |
| `P.integer` | nombre entier (math.type) |
| `P.finite` | nombre fini (pas NaN, ±inf) |
| `P.bigintPositive` / `P.bigintNegative` | BigInt signé |

## Predicate

```lua
P.when(function(v) return type(v) == "string" and #v > 5 end)
P.instanceOf(metatable)
P.luaPattern("^%d+$")  -- via string.match
```

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
P.between(1, 100)      -- inclusive both ends
P.gt(0)   P.gte(0)
P.lt(10)  P.lte(10)
```

BigInt thresholds : `P.bigintGt`, `P.bigintGte`, `P.bigintLt`, `P.bigintLte`, `P.bigintBetween`.

## Disjunction

```lua
P.union("a", "b", "c", "d")        -- pure values, hash O(1) (NaN/nil sûrs)
P.anyOf(P.string, P.number)        -- patterns mixés, walk-style O(n)
```

Convention : si tous les membres sont des values primitives → `union`. Sinon → `anyOf`.

## Negation / Optional / Intersection

```lua
P.not_(P.string)               -- match si v n'est PAS string
P.optional(P.number)           -- nil ou number
P.intersection(P.string, P.startsWithStr("/api/"))
```

## Sequences (arrays / tuples)

```lua
P.array(P.number)              -- tous les éléments sont des numbers
P.arrayOf(P.number, { min = 1, max = 10 })  -- + bornes de longueur
P.arrayIncludes(P.string)      -- au moins un élément match

P.tuple(P.string, P.number)    -- exactement 2 éléments, [1]=string, [2]=number
P.startsWith(P.string, P.number)  -- v[1..2] match (suffix libre)
P.endsWith(P.string, P.number)    -- v[#-1..#] match (prefix libre)
```

## Map / Set (matchigo types)

```lua
P.map(P.string, P.number)      -- m.Map<string, number>
P.set(P.number)                -- m.Set<number>
```

Ces patterns matchent uniquement les instances `m.Map` / `m.Set` embarquées — pas les tables Lua brutes. Pour matcher une table plain, utilisez un shape + un guard `pairs`.

→ Référence des types embarqués : [`docs/fr/types.md`](./types.md).

## Bindings

```lua
-- Capture pour le handler bindings (cf docs/matching.md)
P.select()                     -- capture anonyme
P.select("label")              -- capture nommée
P.select(P.string)             -- capture refined (anonyme)
P.select("label", P.string)    -- capture nommée + refined

-- Custom slice extraction (utilisé par le DSL pour ...rest nommés)
P.captureSlice("rest", function(v) return slice(v) end)
```

## Bare values & shape tables

Tout ce qui n'est **pas** un descripteur P est traité comme un literal ou un shape :

```lua
m.isMatching("GET", "GET")  --> true   (literal strict equality)
m.isMatching(42, 42)        --> true
m.isMatching(nil, nil)      --> true

-- Plain Lua table = shape (extra keys ignorées)
m.isMatching({ kind = "click" }, { kind = "click", x = 5 })  --> true

-- Top-level array = sugar pour P.union sur ses items (literals)
m.isMatching({ "a", "b", "c" }, "b")  --> true
```

## API utilitaires

```lua
m.isP(v)        --> v est un descripteur P-tagged
m.isSelect(v)   --> v est un P.select
```
