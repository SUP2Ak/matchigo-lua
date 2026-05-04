# DSL — patterns en string

`m.parsePattern(src, scope?, ctx?)` parse une string DSL et retourne un descripteur P équivalent. Le DSL est **purement compile-time** — pas d'overhead runtime vs un pattern hand-written.

```lua
local pat = m.parsePattern("'GET' | 'POST'")
m.isMatching(pat, "GET")  --> true
```

Le DSL est aussi consommé directement par `m.matcher(scope?, ctx?)` quand vous lui passez un scope (ou ctx) :

```lua
local handle = m.matcher({ Str = m.P.string })
    :with("Str | 'fallback'", function() return "ok" end)
    :otherwise(               function() return "no" end)
```

## Convention de casse

- **lowercase** ident → **binding** (capture la valeur sous ce nom)
- **UpperCase** ident → **scope ref** (résolu via `scope[name]` au compile)
- `_` → **wildcard** (match tout, pas de binding)

```lua
local scope = { Str = m.P.string, Num = m.P.number }
m.parsePattern("Str", scope)        -- = scope.Str = P.string
m.parsePattern("x", scope)          -- = P.select("x") (anonymous bind)
m.parsePattern("_", scope)          -- = P.any
```

## Literals

```lua
"'GET'"    -- string
"42"       -- number
"-5"       -- negative number
"3.14"     -- float
"true"  "false"  "nil"
```

## Combinateurs

| Syntaxe | Sémantique |
|---|---|
| `A \| B` | union/anyOf — pure literals → `P.union` (hash O(1)) ; mixed → `P.anyOf` |
| `A & B` | `P.intersection(A, B)` |
| `A?` | `P.optional(A)` |
| `!A` ou `not A` | `P.not_(A)` |
| `A as name` | `P.select("name", A)` (binding refined) |
| `A if expr` | guard runtime (cf [Guards](#guards)) |
| `(A)` | grouping |
| `(A, B, ...)` | tuple ≥ 2 items (équivalent à `[A, B, ...]`) |

Précédence : `if` < `\|` < `&` < postfix (`?` / `as`) < primary.

## Shapes

```lua
"{ kind: 'click', x: Num, y: Num }"
"{ x }"                           -- shorthand : { x: x } → P.select("x")
"{ a: Str, b: Num, ...rest }"     -- ...rest capture les keys non déclarées
"{ 'kebab-key': Str }"            -- string keys autorisées
```

## Arrays / tuples

```lua
"[Num, Num]"             -- tuple exact (2 numbers)
"[Num, Num, ...tail]"    -- startsWith + bind tail = v[3..#v]
"[...init, Num]"         -- endsWith + bind init = v[1..#v-1]
"[...all]"               -- bind l'array entier
"[]"                     -- exactement vide
```

Au plus un `...` par array. Un `...` sans nom = anonyme (match structural sans capture).

## Scope refs avec sugar de comparaison

```lua
"User"                          -- scope.User tel quel
"User(age > 18)"                -- User & v.age > 18  (sugar)
"User(age >= 18, name == 'Alice')"  -- multiple constraints (AND)
```

Les RHS des contraintes sont **eval au parse-time** depuis scope/ctx (pas de bindings dispo dans cette position).

## Interpolation `$ident`

Pour injecter un pattern Lua construit en runtime :

```lua
local hot = m.P.union("ping", "health")
local pat = m.parsePattern("$hot | 'fallback'", {}, { hot = hot })
```

`$ident` est résolu **au parse-time** depuis `ctx[ident]`.

## Guards (`if expr`)

```lua
"x if x > 0"
"{ x, y } if x > 0 and y > 0"
"u if u.age >= 18"
"s if not isEmail(s)"
"x if x > $threshold"
```

L'expression utilise les bindings du pattern + les fonctions/valeurs du scope + `$interp` du ctx.

**Opérateurs supportés** dans les guards :
- comparaisons : `==`, `~=` (ou `!=`), `<`, `<=`, `>`, `>=`
- logiques : `and` (`&&`), `or` (`||`), `not` (`!`)
- arithmétique : `+`, `-`, `*`, `/`, `%`, `//`
- accès : `obj.field`, `f(arg1, arg2)`

Les fonctions appelées dans un guard doivent venir du `scope` (pas d'eval libre) :

```lua
local scope = {
    isEmail = function(s) return s:find("@") ~= nil end,
}
m.parsePattern("s if isEmail(s)", scope)
```

## Shadowing

Réutiliser le même nom de binding sur un même chemin de match → erreur compile :

```lua
m.parsePattern("(x, x)")              -- ERROR : x bound twice
m.parsePattern("'a' as x | 'b' as x") -- OK : branches d'union disjointes
```

## Cache

`parsePattern` cache l'AST par identité du `src`. Re-parser la même string est gratuit.

```lua
local parsePat = require("matchigo.parsePattern")
parsePat.cacheSize()    -- nombre d'entrées courantes
parsePat.clearCache()   -- reset (test, hot reload)
```

Ces helpers de maintenance vivent sur le module `matchigo.parsePattern` — pas sur la fonction publique `m.parsePattern`. À require directement quand besoin.

## Limitations connues

- Les fonctions Lua arbitraires (closures) ne s'expriment pas en DSL — utilisez `P.when(fn)` côté scope, puis référencez par scope ref.
- Les guards n'ont pas accès aux upvalues du host Lua (sauf via scope/ctx explicites).
