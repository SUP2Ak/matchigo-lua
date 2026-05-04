---@meta

---@class matchigo.Matcher
local Matcher = {}

---Append a rule. When the matcher was built with a `scope` (or `ctx`),
---string patterns are auto-parsed via `parsePattern(string, scope, ctx)`.
---Without scope/ctx, strings are treated as literal patterns.
---@param pattern matchigo.PatternLike|string
---@param handler matchigo.Handler|any
---@return matchigo.Matcher
---@overload fun(self: matchigo.Matcher, pattern: matchigo.PatternLike|string, when: fun(v:any):any, handler: matchigo.Handler|any): matchigo.Matcher
function Matcher:with(pattern, handler) end

---Append the `otherwise` rule and finalise. Returns the compiled dispatch fn.
---@param result any|matchigo.Handler
---@return fun(value: any): any
function Matcher:otherwise(result) end

---Finalise without a default. Dispatches throw on non-exhaustive match.
---@return fun(value: any): any
function Matcher:exhaustive() end

---Compile and return the dispatch fn (raw Lua function ; no callable-table).
---@return fun(value: any): any
function Matcher:compile() end

---Lazy-compile then dispatch in one shot. Keeps the matcher reusable
---for further `:with` calls afterwards.
---@param value any
---@return any
function Matcher:run(value) end

return Matcher
