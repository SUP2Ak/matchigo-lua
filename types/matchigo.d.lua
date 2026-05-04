---@meta

-- ────────────────────────────────────────────────────────────────────────
-- matchigo type definitions for lua-language-server (LuaLS / sumneko).
-- Drop the `types/` folder anywhere in your workspace ; LuaLS picks up
-- `---@meta` files as definition-only (no runtime code executes).
--
-- Splits :
--   types/matchigo.d.lua  — module M + Pattern / Handler / Rule aliases
--   types/P.d.lua         — pattern primitives namespace
--   types/Matcher.d.lua   — chained matcher class
--   types/BigInt.d.lua    — BigInt + module
--   types/Map.d.lua       — Map + module
--   types/Set.d.lua       — Set + module
-- ────────────────────────────────────────────────────────────────────────

---Opaque pattern descriptor. Build via `m.P.*`, plain Lua values
---(literals), plain shape tables, or `m.parsePattern(string, ...)`.
---@class matchigo.Pattern

---Anything that can be passed where a pattern is expected. matchigo
---auto-handles bare values and plain tables on top of the P descriptors.
---@alias matchigo.PatternLike matchigo.Pattern | string | number | boolean | nil | table

---Handler signature : matchigo decides between `(value)` and
---`(bindings, value)` at compile time depending on whether the rule's
---pattern carries any `P.select` / DSL binding. See docs/matching.md.
---@alias matchigo.Handler fun(arg1: any, arg2?: any): any

---@class matchigo.Rule
---@field with matchigo.PatternLike
---@field handler? matchigo.Handler|any
---@field when? fun(value: any): any
---@field otherwise? any|matchigo.Handler

-- ── Module API ─────────────────────────────────────────────────────────

---@class matchigo
local M = {}

---@type matchigo.P
M.P = nil

---@param v any
---@return boolean
function M.isP(v) end

---@param v any
---@return boolean
function M.isSelect(v) end

---Test a single pattern against a value.
---@param pattern matchigo.PatternLike
---@param value any
---@return boolean
function M.isMatching(pattern, value) end

---One-off dispatch. Compiles `rules` lazily and caches by table identity
---(weak-keyed). Subsequent calls with the same `rules` table hit the cache.
---@param value any
---@param rules matchigo.Rule[]
---@return any
function M.match(value, rules) end

---Eager compile. Returns the dispatch fn directly — no `__call` wrapper,
---no `.run` field. For hot loops, hold this fn and call it.
---@param rules matchigo.Rule[]
---@return fun(value: any): any
function M.compile(rules) end

---Chained matcher. Pass `scope` (or `ctx`) to enable DSL auto-parsing of
---string patterns in `:with(...)`. Without args, strings are literals.
---@param scope? table  PascalCase ref bindings used by `:with(string, ...)`
---@param ctx? table    `$interp` values used by `:with(string, ...)`
---@return matchigo.Matcher
function M.matcher(scope, ctx) end

---Parse a DSL string into a P pattern descriptor. ASTs are cached by
---source string (re-parsing the same string is free).
---@param src string
---@param scope? table  PascalCase ref bindings
---@param ctx? table    `$interp` values
---@return matchigo.Pattern
function M.parsePattern(src, scope, ctx) end

---@type matchigo.BigIntModule
M.BigInt = nil

---@type matchigo.MapModule
M.Map = nil

---@type matchigo.SetModule
M.Set = nil

return M
