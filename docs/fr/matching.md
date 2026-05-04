# Matching — `isMatching`, `match`, `compile`, `matcher`

Quatre façons d'utiliser un pattern, du plus tendu (hot loop) au plus ergonomique (chaîné).

## `isMatching(pattern, value)` — test unique

```lua
m.isMatching(P.string, "hi")          --> true
m.isMatching({ kind = "click" }, val) --> true si val.kind == "click"
m.isMatching(parsePattern("Str | Num", scope), v)
```

Pour tester **un seul** pattern contre **une seule** valeur. Pas de rules, pas de dispatch.

## `match(value, rules)` — one-off cached

```lua
local result = m.match("GET", {
    { with = "GET",  handler = function() return "list" end },
    { with = "POST", handler = function() return "create" end },
    { otherwise = function() return "?" end },
})
```

Compile le tableau de rules à la **première** invocation, cache par identité du tableau (weak-keyed). Subsequent calls = cache hit + dispatch.

Idéal quand les rules sont définies une fois en haut d'un module et appelées sporadiquement. **+5-8 ns** par appel vs `compile` (un weak-table lookup).

## `compile(rules)` — fonction brute

```lua
local dispatch = m.compile({
    { with = "GET",  handler = function() return 1 end },
    { with = "POST", handler = function() return 2 end },
    { otherwise = function() return -1 end },
})
dispatch("GET")  --> 1
```

Retourne **directement** une fonction Lua. Pas de callable-table, pas de `__call`, pas de `.run`. Pour les hot loops.

## `matcher(scope?, ctx?)` — chained builder

### Sans args = mode "raw P only"

```lua
local route = m.matcher()
    :with(P.string,  function(v) return "str:" .. v end)
    :with(P.number,  function(v) return "num:" .. v end)
    :otherwise(      function() return "?" end)
route("hi")  --> "str:hi"
```

Strings passées à `:with` sont traitées comme des **literals** (compat backward — pas d'auto-parse DSL).

### Avec scope/ctx = mode DSL activé

```lua
local scope = { Str = P.string, Num = P.number }
local route = m.matcher(scope)
    :with("'GET'",                function() return "list" end)
    :with("Str if #s > 0",        function(b) return "non-empty:" .. b.s end)
    :with("Str | Num",            function(v) return "any:" .. tostring(v) end)
    :otherwise(                   function() return "no" end)
```

Quand `scope` (ou `ctx`) est passé (même `{}` vide), les strings dans `:with` sont **auto-parsées** via `parsePattern(string, scope, ctx)`.

### Méthodes terminales

| Méthode | Retour | Usage |
|---|---|---|
| `:otherwise(fn)` | fn dispatch | défaut + termine la chaîne |
| `:exhaustive()` | fn dispatch | pas de défaut, throw sur miss |
| `:compile()` | fn dispatch | comme exhaustive ; lazy compile interne |
| `:run(value)` | result | dispatch direct, garde l'objet matcher vivant |

`:otherwise`, `:exhaustive`, `:compile` retournent une **fonction Lua brute** — appelez-la directement.

## Forme d'une rule

```lua
{ with = pattern, handler = handler }                    -- match → handler
{ with = pattern, when = guardFn, handler = handler }    -- + guard runtime
{ otherwise = handlerOrValue }                          -- défaut (anywhere in array, mais conventionnellement à la fin)
```

`then` est un mot-clé Lua : utilisez `handler` (ou la string-key `["then"]` si vous tenez à la cohérence avec TS).

## Bindings → handler

Les `P.select` (et leur équivalent DSL) capturent des sous-valeurs. La signature du handler dépend du nombre et type de selects :

```lua
-- Aucun select : handler reçoit la value brute
{ with = P.string, handler = function(v) return "str:" .. v end }

-- Un select unlabeled : handler reçoit (selectedValue, fullValue)
{ with = { user = { id = P.select() } },
  handler = function(id, v) return id end }

-- Un ou plusieurs labeled : handler reçoit (bindings, fullValue)
{ with = { user = { id = P.select("uid"), name = P.select("nm") } },
  handler = function(b, v) return b.uid .. ":" .. b.nm end }
```

Avec le DSL, **toutes** les bindings sont labeled (le compile DSL utilise toujours `P.select(name, ...)`). Donc le handler reçoit toujours `(bindings, fullValue)` :

```lua
m.matcher({})
    :with("(a, b) if a < b", function(b) return b.a, b.b end)
    :otherwise(function() return nil end)
```

## Guard runtime (`when`) vs guard DSL (`if`)

```lua
-- Via raw rule.when : reçoit la value brute
{ with = P.number, when = function(v) return v > 0 end,
  handler = function(v) return "positive" end }

-- Via DSL : reçoit les bindings
"x if x > 0"
```

Les deux peuvent coexister. Le DSL est plus expressif (accès aux bindings) ; le `rule.when` est utile pour des prédicats Lua arbitraires.

## Exhaustivité

Sans `otherwise` ni `:otherwise(...)`, un dispatch sur une valeur non matchée throw :

```lua
local fn = m.compile({
    { with = "GET", handler = function() return 1 end },
})
fn("POST")  --> error "Non-exhaustive match"
```

Pour qu'une chaîne `matcher` se termine en exhaustive sans défaut, utilisez `:exhaustive()` ou `:compile()`.

## Quel choix pour quel cas ?

| Cas | Outil |
|---|---|
| Un test de pattern unique | `isMatching` |
| Dispatch one-off, rules définies une fois | `match` |
| Dispatch hot loop, rules figées | `compile` (extrait la fn) |
| Construction fluent + DSL | `matcher(scope)` |
| Rules construites dynamiquement | `matcher()` + `:with` itératif |
