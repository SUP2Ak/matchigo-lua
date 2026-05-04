# Types embarqués — `m.BigInt`, `m.Map`, `m.Set`

Lua n'a pas d'équivalents natifs au `BigInt`, `Map` ordonnée ou `Set` de JS. matchigo-lua embarque ses propres versions minimales, utilisées par `P.bigint*`, `P.map`, `P.set`. Elles sont aussi ré-exportées sur la surface publique pour usage direct.

## `m.BigInt`

Un BigInt sous forme de string décimale. Supporte comparaison et égalité (pas d'arithmétique). Utilisé par les patterns `P.bigint*`.

```lua
local big = m.BigInt.new("123456789012345678901234567890")
local neg = m.BigInt.new(-42)
local zero = m.BigInt.ZERO
local one  = m.BigInt.ONE
```

### API

| Symbole | Description |
|---|---|
| `m.BigInt.new(v)` | construit depuis un `number` (doit être un entier fini), une `string` (`-?\d+`), ou un autre `BigInt` (renvoyé tel quel) |
| `m.BigInt.isBigInt(v)` | `true` si `v` est un BigInt |
| `m.BigInt.compare(a, b)` | `-1` / `0` / `1` |
| `m.BigInt.ZERO` / `m.BigInt.ONE` | singletons partagés |

### Métamethodes

`==`, `<`, `<=`, `-` unaire, `tostring` fonctionnent sur les BigInt :

```lua
m.BigInt.new("100") < m.BigInt.new("200")     --> true
-m.BigInt.new("5")                            --> BigInt -5
tostring(m.BigInt.new("42"))                  --> "42"
```

### Méthodes d'instance

```lua
local n = m.BigInt.new("42")
n:isPositive()  --> true
n:isNegative()  --> false
n:isZero()      --> false
```

### Limitations

Pas d'arithmétique (`+`, `-`, `*`, `/`). L'usage cible est la comparaison et le stockage, pas le calcul. Pour de la vraie arithmétique grand-nombre, utilisez une lib dédiée (par ex. `lua-bn`).

## `m.Map`

Une map clé/valeur ordonnée. L'ordre d'insertion est préservé par `pairs`/`keys`/`values`. Les clés peuvent être n'importe quelle valeur Lua, y compris `nil` et `NaN` (normalisées en interne via des clés sentinelles).

```lua
local mp = m.Map.new({ {"a", 1}, {"b", 2} })  -- entrées = paires { key, value }
mp:set("c", 3)
mp:get("a")                                    --> 1
mp.size                                        --> 3

for k, v in mp:pairs() do
    print(k, v)  -- "a" 1, "b" 2, "c" 3 (ordre d'insertion)
end
```

### API

| Symbole | Description |
|---|---|
| `m.Map.new(entries?)` | array optionnel de paires `{ key, value }` |
| `m.Map.isMap(v)` | `true` si `v` est une Map |

### Méthodes d'instance

| Méthode | Description |
|---|---|
| `:get(key)` | valeur ou `nil` |
| `:has(key)` | `true` / `false` |
| `:set(key, value)` | insère ou met à jour ; retourne `self` (chainable) |
| `:delete(key)` | `true` si retiré, `false` si absent |
| `:clear()` | vide la map |
| `:pairs()` | itérateur → `key, value` (ordre d'insertion) |
| `:keys()` | itérateur → `key` |
| `:values()` | itérateur → `value` |
| `:forEach(fn)` | `fn(value, key, self)` pour chaque entrée |

### Champ

- `.size` — nombre d'entrées (lecture seule).

### Usage avec les patterns

```lua
m.isMatching(P.map(P.string, P.number), m.Map.new({ {"a", 1}, {"b", 2} }))  --> true
```

`P.map` ne matche que les instances `m.Map` — pas les tables Lua brutes.

## `m.Set`

Un set ordonné, NaN-safe. L'ordre d'insertion est préservé par `items`/`forEach`. Les items peuvent être n'importe quelle valeur Lua, y compris `nil` et `NaN`.

```lua
local s = m.Set.new({ "a", "b", "c" })
s:add("d")
s:has("a")    --> true
s.size        --> 4

for v in s:items() do print(v) end
```

### API

| Symbole | Description |
|---|---|
| `m.Set.new(items?)` | array optionnel d'items |
| `m.Set.isSet(v)` | `true` si `v` est un Set |

### Méthodes d'instance

| Méthode | Description |
|---|---|
| `:has(item)` | `true` / `false` |
| `:add(item)` | insère (no-op si présent) ; retourne `self` |
| `:delete(item)` | `true` si retiré, `false` si absent |
| `:clear()` | vide le set |
| `:items()` | itérateur → `item` (ordre d'insertion) |
| `:forEach(fn)` | `fn(item, item, self)` pour chaque entrée |

### Champ

- `.size` — nombre d'items (lecture seule).

### Usage avec les patterns

```lua
m.isMatching(P.set(P.string), m.Set.new({ "a", "b" }))  --> true
```

`P.set` ne matche que les instances `m.Set` — pas les tables Lua brutes.

## Quand (ne pas) les utiliser

- **Utilisez les types embarqués** quand vous avez besoin d'ordre d'insertion, de clés NaN/nil-safe, ou d'interop avec `P.map`/`P.set`.
- **Utilisez les tables Lua brutes** pour le reste — elles sont moins coûteuses et idiomatiques. Les shape patterns matchigo (`{ kind = "x", ... }`) fonctionnent directement sur les tables ; on ne sort `m.Map`/`m.Set` que quand ces propriétés comptent.
