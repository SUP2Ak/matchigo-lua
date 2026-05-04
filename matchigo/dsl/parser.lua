-- Recursive-descent parser for the matchigo DSL.
-- All parsing functions are module-level and thread an explicit `state`
-- ({ tokens, pos }) — no closures rebuilt per call. parse(src) allocates
-- exactly one state table on top of the token list.

local lexer = require("matchigo.dsl.lexer")
local ast   = require("matchigo.dsl.ast")

local M = {}

-- ── Error + cursor helpers ────────────────────────────────────────────────
local function perr(t, msg)
    error(("DSL parse error at %d:%d : %s"):format(t.line, t.col, msg), 0)
end

local function peek(s, off)
    return s.tokens[s.pos + (off or 0)]
end

local function take(s)
    local t = s.tokens[s.pos]; s.pos = s.pos + 1; return t
end

local function check(s, kind)
    return s.tokens[s.pos].kind == kind
end

local function accept(s, kind)
    if s.tokens[s.pos].kind == kind then return take(s) end
    return nil
end

local function expect(s, kind, what)
    local t = s.tokens[s.pos]
    if t.kind ~= kind then
        perr(t, ("expected %s, got %s"):format(what or kind, t.kind))
    end
    return take(s)
end

-- ── Forward declarations ──────────────────────────────────────────────────
local parsePattern, parseUnion, parseIntersect, parsePostfix, parsePrimary
local parseShape, parseArray, parseScopeRefArgs
local parseExpr, parseOr, parseAnd, parseNot, parseCmp
local parseAdd, parseMul, parseUnary, parseCall, parseAtom

-- ── Pattern grammar ───────────────────────────────────────────────────────
parsePattern = function(s)
    local p = parseUnion(s)
    if accept(s, "KW_IF") then
        return ast.guard(p, parseExpr(s))
    end
    return p
end

parseUnion = function(s)
    local first = parseIntersect(s)
    if not check(s, "PIPE") then return first end
    local items = { first }
    while accept(s, "PIPE") do
        items[#items + 1] = parseIntersect(s)
    end
    return ast.union(items)
end

parseIntersect = function(s)
    local first = parsePostfix(s)
    if not check(s, "AMP") then return first end
    local items = { first }
    while accept(s, "AMP") do
        items[#items + 1] = parsePostfix(s)
    end
    return ast.inter(items)
end

parsePostfix = function(s)
    local p = parsePrimary(s)
    while true do
        if accept(s, "QMARK") then
            p = ast.opt(p)
        elseif accept(s, "KW_AS") then
            local nameTok = peek(s)
            if nameTok.kind ~= "IDENT_LO" then
                perr(nameTok, "expected lowercase binding name after 'as'")
            end
            take(s)
            p = ast.asNode(p, nameTok.value)
        else
            break
        end
    end
    return p
end

parsePrimary = function(s)
    local t = peek(s)
    local k = t.kind

    if k == "WILDCARD" then take(s); return ast.wild() end
    if k == "NUMBER"   then take(s); return ast.lit(t.value) end
    if k == "STRING"   then take(s); return ast.lit(t.value) end
    if k == "KW_TRUE"  then take(s); return ast.lit(true) end
    if k == "KW_FALSE" then take(s); return ast.lit(false) end
    if k == "KW_NIL"   then take(s); return ast.lit(nil) end
    if k == "IDENT_LO" then take(s); return ast.bind(t.value) end

    if k == "IDENT_UP" then
        take(s)
        local args = nil
        if accept(s, "LPAREN") then
            args = parseScopeRefArgs(s)
            expect(s, "RPAREN", "')'")
        end
        return ast.ref(t.value, args)
    end

    if k == "DOLLAR" then
        take(s)
        local id = peek(s)
        if id.kind ~= "IDENT_LO" and id.kind ~= "IDENT_UP" then
            perr(id, "expected ident after '$'")
        end
        take(s)
        return ast.interp(id.value)
    end

    if k == "LBRACE" then return parseShape(s, false) end
    if k == "LBRACE_PIPE" then return parseShape(s, true) end
    if k == "LBRACK" then return parseArray(s) end
    if k == "LPAREN" then
        take(s)
        local first = parsePattern(s)
        if accept(s, "COMMA") then
            local items = { first }
            while true do
                items[#items + 1] = parsePattern(s)
                if not accept(s, "COMMA") then break end
                if check(s, "RPAREN") then break end
            end
            expect(s, "RPAREN", "')'")
            return ast.tuple(items)
        end
        expect(s, "RPAREN", "')'")
        return first
    end

    if k == "BANG" or k == "KW_NOT" then
        take(s)
        return ast.notNode(parsePrimary(s))
    end

    if (k == "MINUS" or k == "PLUS") and peek(s, 1).kind == "NUMBER" then
        local sign = take(s).kind
        local num = take(s).value
        if sign == "MINUS" then num = -num end
        return ast.lit(num)
    end

    perr(t, ("unexpected %s '%s' in pattern"):format(k, tostring(t.value)))
end

parseScopeRefArgs = function(s)
    if check(s, "RPAREN") then return {} end
    local args = {}
    while true do
        local fld = peek(s)
        if fld.kind ~= "IDENT_LO" and fld.kind ~= "IDENT_UP" then
            perr(fld, "expected field name in scope ref args")
        end
        take(s)
        local op = peek(s)
        local opStr
        if     op.kind == "EQ"  then opStr = "=="
        elseif op.kind == "NEQ" then opStr = "~="
        elseif op.kind == "LT"  then opStr = "<"
        elseif op.kind == "LTE" then opStr = "<="
        elseif op.kind == "GT"  then opStr = ">"
        elseif op.kind == "GTE" then opStr = ">="
        else
            perr(op, "expected comparison operator (==, ~=, <, <=, >, >=)")
        end
        take(s)
        local rhs = parseExpr(s)
        args[#args + 1] = { field = fld.value, op = opStr, expr = rhs }
        if not accept(s, "COMMA") then break end
    end
    return args
end

parseShape = function(s, strict)
    local openKind  = strict and "LBRACE_PIPE" or "LBRACE"
    local openStr   = strict and "'{|'"        or "'{'"
    local closeKind = strict and "PIPE_RBRACE" or "RBRACE"
    local closeStr  = strict and "'|}'"        or "'}'"
    expect(s, openKind, openStr)
    local fields, rest = {}, nil
    if accept(s, closeKind) then return ast.shape(fields, rest, strict) end
    while true do
        if accept(s, "ELLIPSIS") then
            if strict then
                perr(s.tokens[s.pos - 1],
                    "...rest is not allowed in a strict shape ('{| ... |}'). Use a regular '{ ... }' shape if you want to capture extras.")
            end
            local name = nil
            local nx = peek(s)
            if nx.kind == "IDENT_LO" then take(s); name = nx.value end
            rest = { name = name }
            if accept(s, "COMMA") then
                perr(s.tokens[s.pos - 1], "...rest must be the last field in shape")
            end
            break
        end
        local keyTok = peek(s)
        local k = keyTok.kind
        if k ~= "IDENT_LO" and k ~= "IDENT_UP" and k ~= "STRING" then
            perr(keyTok, "expected field name (ident or quoted string)")
        end
        take(s)
        local key = keyTok.value
        if accept(s, "COLON") then
            local p = parsePattern(s)
            fields[#fields + 1] = { key = key, pattern = p, shorthand = false }
        else
            if k ~= "IDENT_LO" then
                perr(keyTok, "shape shorthand requires lowercase ident (got '" .. tostring(key) .. "')")
            end
            fields[#fields + 1] = { key = key, pattern = ast.bind(key), shorthand = true }
        end
        if not accept(s, "COMMA") then break end
        if check(s, closeKind) then break end
    end
    expect(s, closeKind, closeStr)
    return ast.shape(fields, rest, strict)
end

parseArray = function(s)
    expect(s, "LBRACK", "'['")
    local items, rest = {}, nil
    if accept(s, "RBRACK") then return ast.array(items, rest) end

    if accept(s, "ELLIPSIS") then
        local name = nil
        local nx = peek(s)
        if nx.kind == "IDENT_LO" then take(s); name = nx.value end
        rest = { name = name, atStart = true }
        if accept(s, "COMMA") then
            -- continue parsing tail items below
        elseif check(s, "RBRACK") then
            take(s)
            return ast.array(items, rest)
        else
            perr(peek(s), "expected ',' or ']' after rest")
        end
    end

    while true do
        if accept(s, "ELLIPSIS") then
            if rest ~= nil then
                perr(s.tokens[s.pos - 1], "only one '...' allowed per array")
            end
            local name = nil
            local nx = peek(s)
            if nx.kind == "IDENT_LO" then take(s); name = nx.value end
            rest = { name = name, atStart = false }
            if accept(s, "COMMA") then
                perr(s.tokens[s.pos - 1], "...rest must be the last item in array")
            end
            break
        end
        items[#items + 1] = parsePattern(s)
        if not accept(s, "COMMA") then break end
        if check(s, "RBRACK") then break end
    end
    expect(s, "RBRACK", "']'")
    return ast.array(items, rest)
end

-- ── Expression grammar (used inside guards) ───────────────────────────────
parseExpr = function(s) return parseOr(s) end

parseOr = function(s)
    local l = parseAnd(s)
    while check(s, "KW_OR") or check(s, "OR") do
        take(s)
        l = ast.eBinary("or", l, parseAnd(s))
    end
    return l
end

parseAnd = function(s)
    local l = parseNot(s)
    while check(s, "KW_AND") or check(s, "AND") do
        take(s)
        l = ast.eBinary("and", l, parseNot(s))
    end
    return l
end

parseNot = function(s)
    if accept(s, "KW_NOT") or accept(s, "BANG") then
        return ast.eUnary("not", parseNot(s))
    end
    return parseCmp(s)
end

parseCmp = function(s)
    local l = parseAdd(s)
    local k = peek(s).kind
    local op
    if     k == "EQ"  then op = "=="
    elseif k == "NEQ" then op = "~="
    elseif k == "LT"  then op = "<"
    elseif k == "LTE" then op = "<="
    elseif k == "GT"  then op = ">"
    elseif k == "GTE" then op = ">="
    end
    if op then
        take(s)
        return ast.eBinary(op, l, parseAdd(s))
    end
    return l
end

parseAdd = function(s)
    local l = parseMul(s)
    while true do
        local k = peek(s).kind
        if k == "PLUS" or k == "MINUS" then
            local op = take(s).value
            l = ast.eBinary(op, l, parseMul(s))
        else break end
    end
    return l
end

parseMul = function(s)
    local l = parseUnary(s)
    while true do
        local k = peek(s).kind
        if k == "STAR" or k == "SLASH" or k == "PERCENT" or k == "IDIV" then
            local op = take(s).value
            l = ast.eBinary(op, l, parseUnary(s))
        else break end
    end
    return l
end

parseUnary = function(s)
    local k = peek(s).kind
    if k == "MINUS" or k == "PLUS" then
        local op = take(s).value
        return ast.eUnary(op, parseUnary(s))
    end
    return parseCall(s)
end

parseCall = function(s)
    local p = parseAtom(s)
    while true do
        local k = peek(s).kind
        if k == "DOT" then
            take(s)
            local id = peek(s)
            if id.kind ~= "IDENT_LO" and id.kind ~= "IDENT_UP" then
                perr(id, "expected ident after '.'")
            end
            take(s)
            p = ast.eMember(p, id.value)
        elseif k == "LPAREN" then
            take(s)
            local args = {}
            if not check(s, "RPAREN") then
                while true do
                    args[#args + 1] = parseExpr(s)
                    if not accept(s, "COMMA") then break end
                end
            end
            expect(s, "RPAREN", "')'")
            p = ast.eCall(p, args)
        else
            break
        end
    end
    return p
end

parseAtom = function(s)
    local t = peek(s)
    local k = t.kind
    if k == "NUMBER"   then take(s); return ast.eLit(t.value) end
    if k == "STRING"   then take(s); return ast.eLit(t.value) end
    if k == "KW_TRUE"  then take(s); return ast.eLit(true) end
    if k == "KW_FALSE" then take(s); return ast.eLit(false) end
    if k == "KW_NIL"   then take(s); return ast.eLit(nil) end
    if k == "IDENT_LO" or k == "IDENT_UP" then
        take(s); return ast.eVar(t.value)
    end
    if k == "DOLLAR" then
        take(s)
        local id = peek(s)
        if id.kind ~= "IDENT_LO" and id.kind ~= "IDENT_UP" then
            perr(id, "expected ident after '$'")
        end
        take(s)
        return ast.eInterp(id.value)
    end
    if k == "LPAREN" then
        take(s)
        local e = parseExpr(s)
        expect(s, "RPAREN", "')'")
        return e
    end
    perr(t, ("unexpected %s in expression"):format(k))
end

-- ── Public entry ──────────────────────────────────────────────────────────
---@param src string
---@return table  AST root (a pattern node)
function M.parse(src)
    local state = { tokens = lexer.tokenize(src), pos = 1 }
    local result = parsePattern(state)
    if state.tokens[state.pos].kind ~= "EOF" then
        perr(state.tokens[state.pos],
            ("trailing input, expected EOF, got %s"):format(state.tokens[state.pos].kind))
    end
    return result
end

return M
