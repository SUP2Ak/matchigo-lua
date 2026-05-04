# DSL — patterns as strings

`m.parsePattern(src, scope?, ctx?)` parses a DSL string and returns an equivalent P descriptor. The DSL is **purely compile-time** — no runtime overhead vs a hand-written pattern.

```lua
local pat = m.parsePattern("'GET' | 'POST'")
m.isMatching(pat, "GET")  --> true
```

The DSL is also consumed directly by `m.matcher(scope?, ctx?)` when you pass it a scope (or ctx):

```lua
local handle = m.matcher({ Str = m.P.string })
    :with("Str | 'fallback'", function() return "ok" end)
    :otherwise(               function() return "no" end)
```

## Casing convention

- **lowercase** ident → **binding** (capture under that name)
- **PascalCase** ident → **scope ref** (resolved via `scope[name]` at compile-time)
- `_` → **wildcard** (match anything, no capture)

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

## Combinators

| Syntax | Semantics |
|---|---|
| `A \| B` | union/anyOf — pure literals → `P.union` (hash O(1)); mixed → `P.anyOf` |
| `A & B` | `P.intersection(A, B)` |
| `A?` | `P.optional(A)` |
| `!A` or `not A` | `P.not_(A)` |
| `A as name` | `P.select("name", A)` (refined binding) |
| `A if expr` | runtime guard (see [Guards](#guards)) |
| `(A)` | grouping |
| `(A, B, ...)` | tuple ≥ 2 items (equivalent to `[A, B, ...]`) |

Precedence: `if` < `|` < `&` < postfix (`?` / `as`) < primary.

## Shapes

```lua
"{ kind: 'click', x: Num, y: Num }"
"{ x }"                           -- shorthand: { x: x } → P.select("x")
"{ a: Str, b: Num, ...rest }"     -- ...rest captures undeclared keys
"{ 'kebab-key': Str }"            -- string keys allowed
```

## Arrays / tuples

```lua
"[Num, Num]"             -- exact tuple (2 numbers)
"[Num, Num, ...tail]"    -- startsWith + bind tail = v[3..#v]
"[...init, Num]"         -- endsWith + bind init = v[1..#v-1]
"[...all]"               -- bind the whole array
"[]"                     -- exactly empty
```

At most one `...` per array. A `...` without a name = anonymous (structural match without capture).

## Scope refs with comparison sugar

```lua
"User"                          -- scope.User as-is
"User(age > 18)"                -- User & v.age > 18  (sugar)
"User(age >= 18, name == 'Alice')"  -- multiple constraints (AND)
```

The RHS of constraints is **evaluated at parse-time** from scope/ctx (no bindings available in this position).

## `$ident` interpolation

To inject a Lua-built pattern at runtime:

```lua
local hot = m.P.union("ping", "health")
local pat = m.parsePattern("$hot | 'fallback'", {}, { hot = hot })
```

`$ident` is resolved **at parse-time** from `ctx[ident]`.

## Guards (`if expr`)

```lua
"x if x > 0"
"{ x, y } if x > 0 and y > 0"
"u if u.age >= 18"
"s if not isEmail(s)"
"x if x > $threshold"
```

The expression sees pattern bindings + scope functions/values + ctx `$interp`.

**Operators supported** in guards:
- comparison: `==`, `~=` (or `!=`), `<`, `<=`, `>`, `>=`
- logical: `and` (`&&`), `or` (`||`), `not` (`!`)
- arithmetic: `+`, `-`, `*`, `/`, `%`, `//`
- access: `obj.field`, `f(arg1, arg2)`

Functions called inside a guard must come from `scope` (no free eval):

```lua
local scope = {
    isEmail = function(s) return s:find("@") ~= nil end,
}
m.parsePattern("s if isEmail(s)", scope)
```

## Shadowing

Reusing the same binding name on the same match path → compile error:

```lua
m.parsePattern("(x, x)")              -- ERROR: x bound twice
m.parsePattern("'a' as x | 'b' as x") -- OK: disjoint union branches
```

## Cache

`parsePattern` caches the AST keyed on `src` identity. Re-parsing the same string is free.

```lua
local parsePat = require("matchigo.parsePattern")
parsePat.cacheSize()    -- current entry count
parsePat.clearCache()   -- reset (tests, hot reload)
```

These maintenance helpers live on the `matchigo.parsePattern` module — not on the public `m.parsePattern` function. Require them directly when you need them.

## Known limitations

- Arbitrary Lua functions (closures) cannot be expressed in the DSL — use `P.when(fn)` on the scope side, then reference it via a scope ref.
- Guards have no access to the host Lua's upvalues (only `scope` / `ctx` explicitly).
