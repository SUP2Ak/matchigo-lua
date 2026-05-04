# matchigo-lua — release bundle

Pattern matching for Lua. Composable `P.*` primitives, optional Rust-like
DSL, compiled dispatcher.

## What's in this archive

```
matchigo.lua          ← readable bundled distribution (with header)
matchigo.min.lua      ← minified single-line distribution (same code)
matchigo-lua-type/    ← LuaLS / EmmyLua type definitions (.d.lua, ---@meta)
LICENSE
README.md             ← this file
```

Both `matchigo.lua` and `matchigo.min.lua` are functionally identical. Use
the readable one in development for stack traces / debugging, the minified
one when shipping a tight build. They expose the exact same API.

## Install

Drop `matchigo.lua` (or `.min.lua`) anywhere on your `package.path`, then:

```lua
local m = require("matchigo")
local P = m.P

-- Single test
m.isMatching(P.string, "hi")            --> true

-- Compiled dispatcher (raw Lua function, no callable-table wrapper)
local route = m.compile({
    { with = "GET",  handler = function() return list_handler   end },
    { with = "POST", handler = function() return create_handler end },
    { otherwise = function() return method_not_allowed end },
})
route("GET")(request)

-- Chained matcher with the DSL (passing a scope activates it)
local handle = m.matcher({ Str = P.string, Num = P.number })
    :with("'GET' | 'POST'", function(v) return "method:" .. v end)
    :with("{ kind: 'click', x, y }", function(b) return ("at %d,%d"):format(b.x, b.y) end)
    :otherwise(function() return nil end)
```

If `package.path` is awkward in your context, you can also load directly:

```lua
local m = dofile("path/to/matchigo.lua")
```

## LuaLS / EmmyLua type support

Drop the `matchigo-lua-type/` folder anywhere in your workspace. The
language server (`lua-language-server`, a.k.a. `sumneko.lua`) auto-picks
up `---@meta` files for completion, hover, and type checks — no runtime
code in those files, definitions only.

VSCode users : place the folder at the workspace root and it's found
automatically. For other layouts, add the folder to your
`Lua.workspace.library` setting.

## Documentation & sources

- Repository : https://github.com/SUP2Ak/matchigo-lua
- Patterns reference, matching API, DSL grammar, types module reference,
  examples : in `docs/` on the repo (English + French).

## License

[MIT](./LICENSE) — Copyright (c) 2026 Wesley Cormier (SUP2Ak).
