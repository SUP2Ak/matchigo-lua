-- Tiny tree-walk evaluator for guard expressions.
-- env  : table for variable lookup (bindings shadowing scope ; scope as
--        __index fallback) ; constructed once at guard-compile time and
--        mutated per match to avoid per-call allocations.
-- ctx  : table for `$interp` lookup ; usually fixed at parse time.

---@diagnostic disable-next-line
local tunpack = table.unpack or unpack

local M = {}

local function eval(e, env, ctx)
    local k = e.kind
    if k == "ELit"    then return e.value end
    if k == "EVar"    then return env[e.name] end
    if k == "EInterp" then return ctx and ctx[e.name] end
    if k == "EMember" then
        local obj = eval(e.obj, env, ctx)
        if obj == nil then return nil end
        return obj[e.prop]
    end
    if k == "ECall" then
        local fn = eval(e.callee, env, ctx)
        if type(fn) ~= "function" then
            error("DSL eval : attempted to call non-function", 0)
        end
        local n = #e.args
        local args = {}
        for i = 1, n do args[i] = eval(e.args[i], env, ctx) end
        return fn(tunpack(args, 1, n))
    end
    if k == "EUnary" then
        local x = eval(e.operand, env, ctx)
        local op = e.op
        if op == "not" then return not x end
        if op == "-"   then return -x end
        if op == "+"   then return x end
    end
    if k == "EBinary" then
        local op = e.op
        local l = eval(e.left, env, ctx)
        if op == "and" then
            if not l then return l end
            return eval(e.right, env, ctx)
        end
        if op == "or" then
            if l then return l end
            return eval(e.right, env, ctx)
        end
        local r = eval(e.right, env, ctx)
        if op == "==" then return l == r end
        if op == "~=" or op == "!=" then return l ~= r end
        if op == "<"  then return l <  r end
        if op == "<=" then return l <= r end
        if op == ">"  then return l >  r end
        if op == ">=" then return l >= r end
        if op == "+"  then return l +  r end
        if op == "-"  then return l -  r end
        if op == "*"  then return l *  r end
        if op == "/"  then return l /  r end
        if op == "%"  then return l %  r end
        -- math.floor(a/b) is the Lua 5.1/5.2 polyfill for `a // b` (5.3+).
        -- Both round toward -inf so they're equivalent on negatives too.
        if op == "//" then return math.floor(l / r) end
    end
    error("DSL eval : unknown expr kind '" .. tostring(k) .. "'", 0)
end

M.eval = eval
return M
