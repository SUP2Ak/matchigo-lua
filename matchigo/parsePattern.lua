-- Public entry : parse a DSL string + compile it into a matchigo P descriptor.
-- ASTs are cached by source string (parsing is the deterministic, scope-free
-- step ; compile depends on scope+ctx and re-runs each call). Strings are
-- interned in Lua so the cache doesn't keep extra string objects alive ;
-- bounded only by the count of distinct DSL sources used by the program.

local parser  = require("matchigo.dsl.parser")
local compile = require("matchigo.dsl.compile")

local M = {}

local astCache = {}

---@param src string    DSL source
---@param scope? table  PascalCase ref bindings
---@param ctx? table    $interpolation values
---@return any a        matchigo pattern descriptor
function M.parsePattern(src, scope, ctx)
    local node = astCache[src]
    if node == nil then
        node = parser.parse(src)
        astCache[src] = node
    end
    return compile.compile(node, scope, ctx)
end

---@return integer  current AST cache entry count (mostly for tests/inspection)
function M.cacheSize()
    local n = 0
    for _ in pairs(astCache) do n = n + 1 end
    return n
end

function M.clearCache()
    astCache = {}
end

return M
