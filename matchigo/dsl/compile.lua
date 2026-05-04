-- DSL AST → matchigo P descriptor.
-- Pure traversal : every kind has a tiny compiler ; the dispatch table
-- maps ast.* tags to the right one. scope resolves PascalCase refs ;
-- ctx resolves $interpolations at compile time.
--
-- M2 scope : literals, wild, bindings, refs (no args), interpolation,
-- unions (smart split union/anyOf), intersection, optional, as, not,
-- shapes (anonymous rest only), tuples, arrays (anonymous rest only).
-- Deferred to M3+ (compile error) : guards, ref args sugar, named rest
-- in shape and array (need runtime extractor primitives).

local ast       = require("matchigo.dsl.ast")
local p         = require("matchigo.p")
local mcompile  = require("matchigo.compile")
local evalMod   = require("matchigo.dsl.eval")

local P = p.P
local collectSelects = mcompile.collectSelects
local readPath       = mcompile.readPath
local evalExpr       = evalMod.eval

---@diagnostic disable-next-line
local tunpack = table.unpack or unpack

local M = {}

local compile -- forward decl

local function err(msg)
    error("DSL compile error : " .. msg, 0)
end

-- Walk the AST and detect duplicate binding names along any single match
-- path. Union branches are independent (only one branch matches per call)
-- so each gets a fresh name set. Caught at compile time before the
-- pattern is ever evaluated.
local function checkShadowing(node, names)
    local k = node.kind
    if k == ast.BIND then
        if names[node.name] then
            err("binding '" .. node.name .. "' shadows an earlier binding in the same pattern")
        end
        names[node.name] = true
        return
    end
    if k == ast.AS then
        if names[node.name] then
            err("binding '" .. node.name .. "' shadows an earlier binding in the same pattern")
        end
        names[node.name] = true
        checkShadowing(node.inner, names)
        return
    end
    if k == ast.UNION then
        for i = 1, #node.items do
            checkShadowing(node.items[i], {})  -- fresh scope per branch
        end
        return
    end
    if k == ast.INTER then
        for i = 1, #node.items do checkShadowing(node.items[i], names) end
        return
    end
    if k == ast.OPT or k == ast.NOT then
        checkShadowing(node.inner, names); return
    end
    if k == ast.GUARD then
        checkShadowing(node.inner, names); return
    end
    if k == ast.SHAPE then
        for i = 1, #node.fields do
            checkShadowing(node.fields[i].pattern, names)
        end
        if node.rest and node.rest.name then
            if names[node.rest.name] then
                err("rest binding '" .. node.rest.name .. "' shadows an earlier binding")
            end
            names[node.rest.name] = true
        end
        return
    end
    if k == ast.TUPLE or k == ast.ARRAY then
        for i = 1, #node.items do checkShadowing(node.items[i], names) end
        if node.rest and node.rest.name then
            if names[node.rest.name] then
                err("rest binding '" .. node.rest.name .. "' shadows an earlier binding")
            end
            names[node.rest.name] = true
        end
        return
    end
    -- LIT / WILD / REF / INTERP — no bindings of their own.
end

local function isLiteralValue(v)
    local t = type(v)
    if t == "string" or t == "number" or t == "boolean" then return true end
    return v == nil
end

-- ── Per-kind compilers ────────────────────────────────────────────────────
local function cLit(node)   return node.value end
local function cWild()      return P.any end
local function cBind(node)  return P.select(node.name) end

-- Build a P.when guard for `Type(field op val, ...)` sugar. RHS exprs are
-- evaluated once at compile time (they can use scope/$interp but not bindings).
local function buildRefArgsGuard(args, scope, ctx)
    local n = #args
    local fields, ops, rhss = {}, {}, {}
    local env = setmetatable({}, { __index = scope })
    for i = 1, n do
        fields[i] = args[i].field
        ops[i]    = args[i].op
        rhss[i]   = evalExpr(args[i].expr, env, ctx)
    end
    return P.when(function(v)
        if type(v) ~= "table" then return false end
        for i = 1, n do
            local l, r, op = v[fields[i]], rhss[i], ops[i]
            local ok
            if     op == "==" then ok = (l == r)
            elseif op == "~=" then ok = (l ~= r)
            elseif op == "<"  then ok = (l <  r)
            elseif op == "<=" then ok = (l <= r)
            elseif op == ">"  then ok = (l >  r)
            elseif op == ">=" then ok = (l >= r)
            end
            if not ok then return false end
        end
        return true
    end)
end

local function cRef(node, scope, ctx)
    local v = scope[node.name]
    if v == nil then
        err(("scope ref '%s' not found"):format(node.name))
    end
    if node.args == nil or #node.args == 0 then
        return v
    end
    return P.intersection(v, buildRefArgsGuard(node.args, scope, ctx))
end

local function cInterp(node, _, ctx)
    if ctx[node.name] == nil then
        err(("$interpolation '%s' not provided in ctx"):format(node.name))
    end
    return ctx[node.name]
end

local function cUnion(node, scope, ctx)
    local n = #node.items
    local items, allLit = {}, true
    for i = 1, n do
        local c = compile(node.items[i], scope, ctx)
        items[i] = c
        if not isLiteralValue(c) then allLit = false end
    end
    if allLit then return P.union(tunpack(items, 1, n)) end
    return P.anyOf(tunpack(items, 1, n))
end

local function cInter(node, scope, ctx)
    local n = #node.items
    local items = {}
    for i = 1, n do
        items[i] = compile(node.items[i], scope, ctx)
    end
    return P.intersection(tunpack(items, 1, n))
end

local function cOpt(node, scope, ctx)
    return P.optional(compile(node.inner, scope, ctx))
end

local function cAs(node, scope, ctx)
    return P.select(node.name, compile(node.inner, scope, ctx))
end

local function cNot(node, scope, ctx)
    return P.not_(compile(node.inner, scope, ctx))
end

local function cGuard(node, scope, ctx)
    local inner = compile(node.inner, scope, ctx)
    local selects = collectSelects(inner)
    local nsel = #selects
    -- env reused across matches to avoid per-call allocation. PascalCase
    -- scope refs flow through __index ; bindings are mutated in.
    local env = setmetatable({}, { __index = scope })
    local expr = node.expr
    local guardFn
    if nsel == 0 then
        guardFn = function(_)
            return evalExpr(expr, env, ctx) and true or false
        end
    else
        guardFn = function(v)
            for i = 1, nsel do
                local s = selects[i]
                env[s.label or false] = readPath(v, s.path, s.n)
            end
            return evalExpr(expr, env, ctx) and true or false
        end
    end
    return P.intersection(inner, P.when(guardFn))
end

-- Slice extractor for shape rest : returns a fresh table containing only
-- the keys NOT in `declared`. Built as a closure so the declared-key set
-- is captured once at compile time.
local function buildShapeRestExtractor(declaredKeys)
    local declared = {}
    for i = 1, #declaredKeys do declared[declaredKeys[i]] = true end
    return function(v)
        if type(v) ~= "table" then return nil end
        local out = {}
        for k, val in pairs(v) do
            if not declared[k] then out[k] = val end
        end
        return out
    end
end

local function cShape(node, scope, ctx)
    local out = {}
    local declared = {}
    for i = 1, #node.fields do
        local f = node.fields[i]
        out[f.key] = compile(f.pattern, scope, ctx)
        declared[i] = f.key
    end
    if node.rest and node.rest.name then
        return p.P.intersection(out,
            p.P.captureSlice(node.rest.name, buildShapeRestExtractor(declared)))
    end
    return out
end

local function cTuple(node, scope, ctx)
    local n = #node.items
    local items = {}
    for i = 1, n do
        items[i] = compile(node.items[i], scope, ctx)
    end
    return P.tuple(tunpack(items, 1, n))
end

-- Slice extractors for array rest. `headLen` and `tailLen` are the count of
-- fixed items at the start/end ; everything between them is the captured
-- slice. Built once at compile time, called once per match.
local function buildArrayTailExtractor(headLen)
    return function(v)
        if type(v) ~= "table" then return nil end
        local len = #v
        local out = {}
        for i = headLen + 1, len do out[i - headLen] = v[i] end
        return out
    end
end

local function buildArrayHeadExtractor(tailLen)
    return function(v)
        if type(v) ~= "table" then return nil end
        local len = #v
        local out = {}
        for i = 1, len - tailLen do out[i] = v[i] end
        return out
    end
end

local function cArray(node, scope, ctx)
    local rest = node.rest
    local n = #node.items
    local items = {}
    for i = 1, n do
        items[i] = compile(node.items[i], scope, ctx)
    end
    if rest == nil then
        return P.tuple(tunpack(items, 1, n))
    end
    -- Rest without name : structural startsWith/endsWith only.
    if rest.name == nil then
        if rest.atStart then return P.endsWith(tunpack(items, 1, n)) end
        return P.startsWith(tunpack(items, 1, n))
    end
    -- Named rest : compose structural pattern with a captureSlice extractor.
    if rest.atStart then
        return P.intersection(
            P.endsWith(tunpack(items, 1, n)),
            p.P.captureSlice(rest.name, buildArrayHeadExtractor(n))
        )
    end
    return P.intersection(
        P.startsWith(tunpack(items, 1, n)),
        p.P.captureSlice(rest.name, buildArrayTailExtractor(n))
    )
end

-- ── Dispatch ──────────────────────────────────────────────────────────────
local DISPATCH = {
    [ast.LIT]    = cLit,
    [ast.WILD]   = cWild,
    [ast.BIND]   = cBind,
    [ast.REF]    = cRef,
    [ast.INTERP] = cInterp,
    [ast.UNION]  = cUnion,
    [ast.INTER]  = cInter,
    [ast.OPT]    = cOpt,
    [ast.AS]     = cAs,
    [ast.NOT]    = cNot,
    [ast.GUARD]  = cGuard,
    [ast.SHAPE]  = cShape,
    [ast.TUPLE]  = cTuple,
    [ast.ARRAY]  = cArray,
}

compile = function(node, scope, ctx)
    local fn = DISPATCH[node.kind]
    if fn == nil then err("unknown AST kind '" .. tostring(node.kind) .. "'") end
    return fn(node, scope, ctx) ---@diagnostic disable-line
end

---@param node table   AST root from matchigo.dsl.parser
---@param scope? table PascalCase ref bindings
---@param ctx? table   $interpolation values
---@return any         a matchigo pattern descriptor (P or bare value/table)
function M.compile(node, scope, ctx)
    checkShadowing(node, {})
    return compile(node, scope or {}, ctx or {})
end

return M
