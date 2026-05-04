# Matching — `isMatching`, `match`, `compile`, `matcher`

Four ways to use a pattern, from the tightest (hot loop) to the most ergonomic (chained).

## `isMatching(pattern, value)` — single test

```lua
m.isMatching(P.string, "hi")          --> true
m.isMatching({ kind = "click" }, val) --> true if val.kind == "click"
m.isMatching(parsePattern("Str | Num", scope), v)
```

For testing **one** pattern against **one** value. No rules, no dispatch.

## `match(value, rules)` — one-off cached

```lua
local result = m.match("GET", {
    { with = "GET",  handler = function() return "list" end },
    { with = "POST", handler = function() return "create" end },
    { otherwise = function() return "?" end },
})
```

Compiles the rules table on the **first** invocation, caches by table identity (weak-keyed). Subsequent calls = cache hit + dispatch.

Ideal when rules are defined once at module top-level and called sporadically. **+5–8 ns** per call vs `compile` (one weak-table lookup).

## `compile(rules)` — raw function

```lua
local dispatch = m.compile({
    { with = "GET",  handler = function() return 1 end },
    { with = "POST", handler = function() return 2 end },
    { otherwise = function() return -1 end },
})
dispatch("GET")  --> 1
```

Returns a **plain Lua function** directly. No callable-table, no `__call` metamethod, no `.run` field. Best for hot loops.

## `matcher(scope?, ctx?)` — chained builder

### No args = "raw P only" mode

```lua
local route = m.matcher()
    :with(P.string,  function(v) return "str:" .. v end)
    :with(P.number,  function(v) return "num:" .. v end)
    :otherwise(      function() return "?" end)
route("hi")  --> "str:hi"
```

Strings passed to `:with` are treated as **literals** (backward compat — no DSL auto-parse).

### With scope/ctx = DSL mode enabled

```lua
local scope = { Str = P.string, Num = P.number }
local route = m.matcher(scope)
    :with("'GET'",                function() return "list" end)
    :with("Str if #s > 0",        function(b) return "non-empty:" .. b.s end)
    :with("Str | Num",            function(v) return "any:" .. tostring(v) end)
    :otherwise(                   function() return "no" end)
```

When `scope` (or `ctx`) is passed (even an empty `{}`), strings in `:with` are **auto-parsed** via `parsePattern(string, scope, ctx)`.

### Terminal methods

| Method | Returns | Use |
|---|---|---|
| `:otherwise(fn)` | dispatch fn | default + closes the chain |
| `:exhaustive()` | dispatch fn | no default, throws on miss |
| `:compile()` | dispatch fn | same as exhaustive; lazy internal compile |
| `:run(value)` | result | direct dispatch, keeps the matcher object alive |

`:otherwise`, `:exhaustive`, `:compile` return a **plain Lua function** — call it directly.

## Rule shape

```lua
{ with = pattern, handler = handler }                    -- match → handler
{ with = pattern, when = guardFn, handler = handler }    -- + runtime guard
{ otherwise = handlerOrValue }                           -- default (anywhere in array, conventionally last)
```

`then` is a Lua keyword: use `handler` (or the string-key `["then"]` if you want strict TS parity).

## Bindings → handler signature

`P.select` (and its DSL equivalent) capture sub-values. The handler signature depends on the count and kind of selects:

```lua
-- No selects: handler receives the raw value
{ with = P.string, handler = function(v) return "str:" .. v end }

-- One unlabeled select: handler receives (selectedValue, fullValue)
{ with = { user = { id = P.select() } },
  handler = function(id, v) return id end }

-- One or more labeled selects: handler receives (bindings, fullValue)
{ with = { user = { id = P.select("uid"), name = P.select("nm") } },
  handler = function(b, v) return b.uid .. ":" .. b.nm end }
```

With the DSL, **every** binding is labeled (the DSL compiler always uses `P.select(name, ...)`). So handlers always receive `(bindings, fullValue)`:

```lua
m.matcher({})
    :with("(a, b) if a < b", function(b) return b.a, b.b end)
    :otherwise(function() return nil end)
```

## Runtime guard (`when`) vs DSL guard (`if`)

```lua
-- Via raw rule.when: receives the raw value
{ with = P.number, when = function(v) return v > 0 end,
  handler = function(v) return "positive" end }

-- Via DSL: the expression sees bindings + scope
"x if x > 0"
```

Both can coexist. The DSL is more expressive (binding access); `rule.when` is useful for arbitrary Lua predicates that don't fit the DSL grammar.

## Exhaustiveness

Without `otherwise` nor `:otherwise(...)`, dispatching on an unmatched value throws:

```lua
local fn = m.compile({
    { with = "GET", handler = function() return 1 end },
})
fn("POST")  --> error "Non-exhaustive match"
```

To close a `matcher` chain as exhaustive without a default, use `:exhaustive()` or `:compile()`.

## Which one for which case?

| Case | Tool |
|---|---|
| Single one-shot pattern test | `isMatching` |
| One-off dispatch, rules defined once | `match` |
| Hot-loop dispatch, rules frozen | `compile` (extract the fn) |
| Fluent construction + DSL | `matcher(scope)` |
| Rules built dynamically | `matcher()` + iterative `:with` |
