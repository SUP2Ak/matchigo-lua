-- Bundles matchigo into dist/matchigo.lua + dist/matchigo.min.lua.
-- Run from matchigo-lua/ root :  lua build.lua
--
-- Strategy: each source module is wrapped in a `do ... end` scope (zero
-- closure allocation, zero call overhead) with its trailing `return M`
-- rewritten as an assignment to a chunk-local. Internal `require("src.X")`
-- calls become direct local references. The entry's `return { ... }` lives
-- inside its own `do` block — `return` exits the enclosing chunk, which is
-- exactly what `require("matchigo")` consumes.
--
-- Two outputs :
--   dist/matchigo.lua      → comments stripped, indent kept (readable runtime)
--   dist/matchigo.min.lua  → comments + indent + blank lines stripped (compact)
-- LuaLS-friendly type defs live in `types/*.d.lua` ; the runtime bundle
-- carries no `---@class` / `---@field` annotations.

local OUT_DIR = "dist"
local OUT_FILE = OUT_DIR .. "/matchigo.lua"
local OUT_MIN  = OUT_DIR .. "/matchigo.min.lua"
local ENTRY = "matchigo/init.lua"

-- Topological order: deps first. p.lua now depends on bigint (eager coercion
-- of P.bigint* thresholds), so bigint must precede p. The DSL modules
-- (ast/lexer/parser/eval/compile + parsePattern) come after the core P
-- machinery they emit against.
local MODULES = {
    { req = "matchigo.util.compat",  file = "matchigo/util/compat.lua",  var = "_M_compat"   },
    { req = "matchigo.types.bigint", file = "matchigo/types/bigint.lua", var = "_M_bigint"   },
    { req = "matchigo.types.map",    file = "matchigo/types/map.lua",    var = "_M_map"      },
    { req = "matchigo.types.set",    file = "matchigo/types/set.lua",    var = "_M_set"      },
    { req = "matchigo.p",            file = "matchigo/p.lua",            var = "_M_p"        },
    { req = "matchigo.compile",      file = "matchigo/compile.lua",      var = "_M_compile"  },
    { req = "matchigo.walk",         file = "matchigo/walk.lua",         var = "_M_walk"     },
    { req = "matchigo.match",        file = "matchigo/match.lua",        var = "_M_match"    },
    { req = "matchigo.dsl.ast",      file = "matchigo/dsl/ast.lua",      var = "_M_dsl_ast"  },
    { req = "matchigo.dsl.lexer",    file = "matchigo/dsl/lexer.lua",    var = "_M_dsl_lex"  },
    { req = "matchigo.dsl.parser",   file = "matchigo/dsl/parser.lua",   var = "_M_dsl_parse"},
    { req = "matchigo.dsl.eval",     file = "matchigo/dsl/eval.lua",     var = "_M_dsl_eval" },
    { req = "matchigo.dsl.compile",  file = "matchigo/dsl/compile.lua",  var = "_M_dsl_comp" },
    { req = "matchigo.parsePattern", file = "matchigo/parsePattern.lua", var = "_M_parsePat" },
    { req = "matchigo.matcher",      file = "matchigo/matcher.lua",      var = "_M_matcher"  },
}

local reqToVar = {}
for i = 1, #MODULES do reqToVar[MODULES[i].req] = MODULES[i].var end

local function readFile(path)
    local f = assert(io.open(path, "rb"), "Cannot open " .. path)
    local s = f:read("*a")
    f:close()
    return s
end

local function writeFile(path, content)
    local f = assert(io.open(path, "wb"), "Cannot write " .. path)
    f:write(content)
    f:close()
end

-- Cross-platform `mkdir -p`-equivalent. Detects the host via the path
-- separator from `package.config` : `\` on Windows, `/` on POSIX. On
-- Windows we use `cmd.exe`'s `if not exist ... mkdir ...` ; on POSIX
-- we use `mkdir -p`. Both are no-ops if the directory already exists.
local function ensureDir(path)
    local sep = package.config:sub(1, 1)
    if sep == "\\" then
        local winPath = path:gsub("/", "\\")
        os.execute(string.format([[if not exist "%s" mkdir "%s"]], winPath, winPath))
    else
        os.execute(string.format([[mkdir -p "%s"]], path))
    end
end

-- ── Comment / whitespace stripping ────────────────────────────────────────
-- State machine that respects string literals (single/double quote and long
-- brackets `[[`, `[==[`...) so `"-- not a comment"` survives intact.
local function stripComments(src)
    local out, n = {}, 0
    local function add(s) n = n + 1; out[n] = s end
    local i, len = 1, #src

    while i <= len do
        local c = src:sub(i, i)

        if c == "'" or c == '"' then
            -- short string
            local quote = c
            local j = i + 1
            while j <= len do
                local cc = src:sub(j, j)
                if cc == "\\" then
                    j = j + 2
                elseif cc == quote then
                    j = j + 1; break
                elseif cc == "\n" then
                    break -- malformed but bail
                else
                    j = j + 1
                end
            end
            add(src:sub(i, j - 1))
            i = j

        elseif c == "[" then
            -- maybe long-bracket string : `[[`, `[=[`, `[==[`...
            local k = i + 1
            local level = 0
            while src:sub(k, k) == "=" do level = level + 1; k = k + 1 end
            if src:sub(k, k) == "[" then
                local close = "]" .. string.rep("=", level) .. "]"
                local endIdx = src:find(close, k + 1, true)
                if endIdx then
                    add(src:sub(i, endIdx + #close - 1))
                    i = endIdx + #close
                else
                    add(c); i = i + 1
                end
            else
                add(c); i = i + 1
            end

        elseif c == "-" and src:sub(i + 1, i + 1) == "-" then
            -- comment : line or block ?
            i = i + 2
            if src:sub(i, i) == "[" then
                local k = i + 1
                local level = 0
                while src:sub(k, k) == "=" do level = level + 1; k = k + 1 end
                if src:sub(k, k) == "[" then
                    -- block comment
                    local close = "]" .. string.rep("=", level) .. "]"
                    local endIdx = src:find(close, k + 1, true)
                    i = endIdx and (endIdx + #close) or (len + 1)
                else
                    while i <= len and src:sub(i, i) ~= "\n" do i = i + 1 end
                end
            else
                while i <= len and src:sub(i, i) ~= "\n" do i = i + 1 end
            end

        else
            add(c); i = i + 1
        end
    end

    return table.concat(out)
end

-- Readable variant : strip comments, drop blank-line runs, trim trailing ws,
-- but keep indentation.
local function stripCommentsKeepLayout(src)
    src = stripComments(src)
    local out, m = {}, 0
    local prevBlank = false
    for line in (src .. "\n"):gmatch("([^\n]*)\n") do
        local trailingTrimmed = line:gsub("%s+$", "")
        if trailingTrimmed:match("%S") then
            m = m + 1; out[m] = trailingTrimmed
            prevBlank = false
        elseif not prevBlank then
            -- collapse blank-line runs to a single blank line
            m = m + 1; out[m] = ""
            prevBlank = true
        end
    end
    return table.concat(out, "\n") .. "\n"
end

-- ── Token-aware minifier (single line output) ─────────────────────────
-- Tokenize the source then re-emit each token with the minimum whitespace
-- needed to preserve lexical boundaries :
--   • two adjacent word-like tokens (id/keyword/number) need a space
--   • a number followed by `.` would form an ambiguous `1..2` → space
--   • two adjacent `-` would form a `--` line comment → space
-- Everything else collapses ; output is a single line modulo string
-- literals that contain newlines (which we preserve as-is).

local function tokenize(src)
    local tokens, n = {}, 0
    local i, len = 1, #src
    local function push(text) n = n + 1; tokens[n] = text end

    while i <= len do
        local c = src:sub(i, i)
        local b = c:byte() or 0

        if b == 32 or b == 9 or b == 10 or b == 13 then
            i = i + 1

        elseif c == "-" and src:sub(i + 1, i + 1) == "-" then
            -- comment : drop entirely
            i = i + 2
            if src:sub(i, i) == "[" then
                local k = i + 1
                local level = 0
                while src:sub(k, k) == "=" do level = level + 1; k = k + 1 end
                if src:sub(k, k) == "[" then
                    local close = "]" .. string.rep("=", level) .. "]"
                    local endIdx = src:find(close, k + 1, true)
                    i = endIdx and (endIdx + #close) or (len + 1)
                else
                    while i <= len and src:sub(i, i) ~= "\n" do i = i + 1 end
                end
            else
                while i <= len and src:sub(i, i) ~= "\n" do i = i + 1 end
            end

        elseif c == "'" or c == '"' then
            local quote = c
            local j = i + 1
            while j <= len do
                local cc = src:sub(j, j)
                if cc == "\\" then j = j + 2
                elseif cc == quote then j = j + 1; break
                elseif cc == "\n" then break
                else j = j + 1 end
            end
            push(src:sub(i, j - 1))
            i = j

        elseif c == "[" then
            local k = i + 1
            local level = 0
            while src:sub(k, k) == "=" do level = level + 1; k = k + 1 end
            if src:sub(k, k) == "[" then
                local close = "]" .. string.rep("=", level) .. "]"
                local endIdx = src:find(close, k + 1, true)
                if endIdx then
                    push(src:sub(i, endIdx + #close - 1))
                    i = endIdx + #close
                else
                    push("["); i = i + 1
                end
            else
                push("["); i = i + 1
            end

        elseif (b >= 48 and b <= 57)
            or (c == "." and src:sub(i + 1, i + 1):match("%d")) then
            -- number : decimal or hex, optional fraction + exponent
            local j = i
            if c == "0" and (src:sub(i + 1, i + 1) == "x" or src:sub(i + 1, i + 1) == "X") then
                j = i + 2
                while j <= len and src:sub(j, j):match("[%x.]") do j = j + 1 end
                local cc = src:sub(j, j)
                if cc == "p" or cc == "P" then
                    j = j + 1
                    if src:sub(j, j) == "+" or src:sub(j, j) == "-" then j = j + 1 end
                    while j <= len and src:sub(j, j):match("%d") do j = j + 1 end
                end
            else
                while j <= len and src:sub(j, j):match("[%d.]") do j = j + 1 end
                local cc = src:sub(j, j)
                if cc == "e" or cc == "E" then
                    j = j + 1
                    if src:sub(j, j) == "+" or src:sub(j, j) == "-" then j = j + 1 end
                    while j <= len and src:sub(j, j):match("%d") do j = j + 1 end
                end
            end
            push(src:sub(i, j - 1))
            i = j

        elseif c:match("[%a_]") then
            local j = i + 1
            while j <= len and src:sub(j, j):match("[%w_]") do j = j + 1 end
            push(src:sub(i, j - 1))
            i = j

        else
            -- operators : longest-match-first (3 → 2 → 1 char)
            local s3 = src:sub(i, i + 2)
            if s3 == "..." then
                push("..."); i = i + 3
            else
                local s2 = src:sub(i, i + 1)
                if s2 == ".." or s2 == "==" or s2 == "~=" or s2 == "<="
                    or s2 == ">=" or s2 == "::" or s2 == "//"
                    or s2 == "<<" or s2 == ">>" then
                    push(s2); i = i + 2
                else
                    push(c); i = i + 1
                end
            end
        end
    end

    return tokens
end

local function minify(src)
    local tokens = tokenize(src)
    local out, m = {}, 0
    for i = 1, #tokens do
        local t = tokens[i]
        if i > 1 then
            local prev = tokens[i - 1]
            local pl = prev:sub(-1)
            local cf = t:sub(1, 1)
            local needSep =
                (pl:match("[%w_]") and cf:match("[%w_]"))     -- word-word
                or (pl:match("%d") and cf == ".")              -- 1..2 ambiguity
                or (pl == "-" and cf == "-")                   -- forms `--` comment
            if needSep then m = m + 1; out[m] = " " end
        end
        m = m + 1; out[m] = t
    end
    return table.concat(out)
end

local function rewriteRequires(body)
    local result = body:gsub('require%s*%(%s*"([^"]+)"%s*%)', function(req)
        local var = reqToVar[req]
        if not var then error("Unknown require in source: " .. req) end
        return var
    end)
    return result
end

-- Strip the trailing `return <ident>` line. Modules are expected to end with
-- exactly that form (verified by tests — if a module gains an early return,
-- the bundler will need a smarter splitter).
local function splitTrailingReturn(body)
    local trimmed = body:gsub("%s+$", "")
    local before, name = trimmed:match("^(.-)\n?return%s+([%w_]+)$")
    if not before then
        error("Could not find trailing `return <ident>` in module body")
    end
    before = before:gsub("\n+$", "")
    return before, name
end

local function indentBlock(s, prefix)
    local out, n = {}, 0
    for line in (s .. "\n"):gmatch("([^\n]*)\n") do
        n = n + 1
        if line == "" then
            out[n] = ""
        else
            out[n] = prefix .. line
        end
    end
    -- Drop the trailing empty line introduced by appending "\n".
    if out[n] == "" then out[n] = nil end
    return table.concat(out, "\n")
end

-- Distribution header — only injected into the readable bundle (the minifier
-- strips comments anyway, and we don't want a giant comment block at the top
-- of the single-line .min file). Kept as a `--[[ ... ]]` block so embedders
-- can spot the metadata at a glance ; line-level `---` markers inside are
-- harmless decoration since LuaLS only parses `---` line comments, not nested
-- ones — proper EmmyLua type defs live in `types/*.d.lua`.
local HEADER = string.format([[
--[%s[
--- matchigo-lua
--- Pattern matching for Lua — composable P.* primitives, optional Rust-like DSL,
--- compiled dispatcher.
---
--- Author:     SUP2Ak (Wesley Cormier)
--- License:    MIT
--- Github:     https://github.com/SUP2Ak/matchigo-lua
--- Sponsor:    SUP2Ak (https://github.com/sponsors/SUP2Ak)
--- Generated:  %s (day-month-year)
---
--- This file is the bundled, auto-generated distribution. Do not edit —
--- edit the sources under matchigo/ and rebuild via `lua build.lua`.
]%s]
]], "=", os.date("%d-%m-%Y"), "=")

local parts, pn = {}, 0
local function emit(line) pn = pn + 1; parts[pn] = line end

-- Forward declarations for the module locals.
local fwd = "local "
for i = 1, #MODULES do
    fwd = fwd .. MODULES[i].var .. (i < #MODULES and ", " or "")
end
emit(fwd)
emit("")

for i = 1, #MODULES do
    local mod = MODULES[i]
    local body = rewriteRequires(readFile(mod.file))
    local before, retName = splitTrailingReturn(body)
    emit("do")
    emit(indentBlock(before, "    "))
    emit("    " .. mod.var .. " = " .. retName)
    emit("end")
    emit("")
end

-- Entry stays unwrapped — its `return { ... }` is naturally the chunk's return,
-- consumed by `require("matchigo")` / `dofile("dist/matchigo.lua")`.
local entry = rewriteRequires(readFile(ENTRY)):gsub("%s+$", "")
emit(entry)

ensureDir(OUT_DIR)

local raw = table.concat(parts, "\n") .. "\n"
local readable = stripCommentsKeepLayout(raw)
local minified = minify(raw)

local readableOut = HEADER .. readable
writeFile(OUT_FILE, readableOut)
writeFile(OUT_MIN, minified)

local function size(s) return #s end
print(string.format("Wrote %s (%d bytes)", OUT_FILE, size(readableOut)))
print(string.format("Wrote %s (%d bytes, %.0f%% of readable)",
    OUT_MIN, size(minified), 100 * size(minified) / size(readableOut)))
