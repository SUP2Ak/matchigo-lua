-- Tokenizer for the matchigo DSL. Eager : returns a list of tokens
-- terminated by an EOF marker. Tokens carry source position (line, col)
-- pointing at the token's first character.

local ssub = string.sub

local M = {}

local KEYWORDS = {
    ["if"]    = "KW_IF",    ["and"]   = "KW_AND",   ["or"]    = "KW_OR",
    ["not"]   = "KW_NOT",   ["as"]    = "KW_AS",
    ["true"]  = "KW_TRUE",  ["false"] = "KW_FALSE", ["nil"]   = "KW_NIL",
}

local THREE_CHAR = { ["..."] = "ELLIPSIS" }

local TWO_CHAR = {
    ["=="] = "EQ",  ["~="] = "NEQ", ["!="] = "NEQ",
    ["<="] = "LTE", [">="] = "GTE",
    ["||"] = "OR",  ["&&"] = "AND",
    ["//"] = "IDIV",
    ["{|"] = "LBRACE_PIPE", ["|}"] = "PIPE_RBRACE",
}

local ONE_CHAR = {
    ["|"] = "PIPE",   ["&"] = "AMP",    ["!"] = "BANG",   ["?"] = "QMARK",
    ["$"] = "DOLLAR", ["("] = "LPAREN", [")"] = "RPAREN",
    ["["] = "LBRACK", ["]"] = "RBRACK", ["{"] = "LBRACE", ["}"] = "RBRACE",
    ["."] = "DOT",    [","] = "COMMA",  [":"] = "COLON",
    ["+"] = "PLUS",   ["-"] = "MINUS",  ["*"] = "STAR",   ["/"] = "SLASH",
    ["%"] = "PERCENT", ["<"] = "LT",    [">"] = "GT",
}

local function isAlpha(c)
    return (c >= "a" and c <= "z") or (c >= "A" and c <= "Z") or c == "_"
end
local function isDigit(c) return c >= "0" and c <= "9" end
local function isAlnum(c) return isAlpha(c) or isDigit(c) end
local function isUpper(c) return c >= "A" and c <= "Z" end

---@param src string
---@return table[]  list of tokens, last element kind = "EOF"
function M.tokenize(src)
    local tokens, ntok = {}, 0
    local pos, line, col = 1, 1, 1
    local n = #src

    local function err(msg)
        error(("DSL lex error at %d:%d : %s"):format(line, col, msg), 0)
    end

    local function push(kind, value, l, c)
        ntok = ntok + 1
        tokens[ntok] = { kind = kind, value = value, line = l, col = c }
    end

    while pos <= n do
        local c = ssub(src, pos, pos)

        if c == " " or c == "\t" or c == "\r" then
            pos = pos + 1; col = col + 1

        elseif c == "\n" then
            pos = pos + 1; line = line + 1; col = 1

        elseif pos + 2 <= n and THREE_CHAR[ssub(src, pos, pos + 2)] then
            local s = ssub(src, pos, pos + 2)
            push(THREE_CHAR[s], s, line, col)
            pos = pos + 3; col = col + 3

        elseif pos + 1 <= n and TWO_CHAR[ssub(src, pos, pos + 1)] then
            local s = ssub(src, pos, pos + 1)
            push(TWO_CHAR[s], s, line, col)
            pos = pos + 2; col = col + 2

        elseif c == "'" or c == '"' then
            local quote = c
            local startL, startC = line, col
            pos = pos + 1; col = col + 1
            local buf, bn = {}, 0
            while pos <= n do
                local ch = ssub(src, pos, pos)
                if ch == quote then break end
                if ch == "\\" then
                    if pos + 1 > n then err("unterminated escape") end
                    local esc = ssub(src, pos + 1, pos + 1)
                    local mapped
                    if     esc == "n"  then mapped = "\n"
                    elseif esc == "t"  then mapped = "\t"
                    elseif esc == "r"  then mapped = "\r"
                    elseif esc == "\\" then mapped = "\\"
                    elseif esc == "'"  then mapped = "'"
                    elseif esc == '"'  then mapped = '"'
                    else err("unknown escape \\" .. esc) end
                    bn = bn + 1; buf[bn] = mapped
                    pos = pos + 2; col = col + 2
                elseif ch == "\n" then
                    err("unterminated string (newline in literal)")
                else
                    bn = bn + 1; buf[bn] = ch
                    pos = pos + 1; col = col + 1
                end
            end
            if pos > n then err("unterminated string") end
            pos = pos + 1; col = col + 1
            push("STRING", table.concat(buf), startL, startC)

        elseif isDigit(c) then
            local startL, startC = line, col
            local startPos = pos
            while pos <= n and isDigit(ssub(src, pos, pos)) do
                pos = pos + 1; col = col + 1
            end
            if pos <= n and ssub(src, pos, pos) == "." then
                local next1 = ssub(src, pos + 1, pos + 1)
                if isDigit(next1) then
                    pos = pos + 1; col = col + 1
                    while pos <= n and isDigit(ssub(src, pos, pos)) do
                        pos = pos + 1; col = col + 1
                    end
                end
            end
            local s = ssub(src, startPos, pos - 1)
            local num = tonumber(s)
            if num == nil then err("invalid number '" .. s .. "'") end
            push("NUMBER", num, startL, startC)

        elseif isAlpha(c) then
            local startL, startC = line, col
            local startPos = pos
            while pos <= n and isAlnum(ssub(src, pos, pos)) do
                pos = pos + 1; col = col + 1
            end
            local s = ssub(src, startPos, pos - 1)
            local kw = KEYWORDS[s]
            local kind
            if kw then
                kind = kw
            elseif s == "_" then
                kind = "WILDCARD"
            elseif isUpper(ssub(s, 1, 1)) then
                kind = "IDENT_UP"
            else
                kind = "IDENT_LO"
            end
            push(kind, s, startL, startC)

        elseif ONE_CHAR[c] then
            push(ONE_CHAR[c], c, line, col)
            pos = pos + 1; col = col + 1

        else
            err("unexpected character '" .. c .. "'")
        end
    end

    push("EOF", nil, line, col)
    return tokens
end

return M
