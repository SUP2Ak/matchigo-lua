-- M1 tests : lexer + parser → AST. Pure structural assertions, no P.
-- Imported by tests/run.lua, called with the shared `env` of helpers.

return function(env)
    local test         = env.test
    local assertEq     = env.assertEq
    local assertThrows = env.assertThrows

    local lexer  = require("matchigo.dsl.lexer")
    local parser = require("matchigo.dsl.parser")
    local ast    = require("matchigo.dsl.ast")

    -- ── helpers ──────────────────────────────────────────────────────────
    local function kinds(src)
        local toks = lexer.tokenize(src)
        local out = {}
        for i = 1, #toks do out[i] = toks[i].kind end
        return table.concat(out, ",")
    end

    local function parse(src) return parser.parse(src) end

    -- ── lexer ────────────────────────────────────────────────────────────
    test("lex : empty input → just EOF", function()
        assertEq(kinds(""), "EOF")
    end)

    test("lex : whitespace skipped", function()
        assertEq(kinds("   \t\n  "), "EOF")
    end)

    test("lex : number int/float", function()
        local toks = lexer.tokenize("42 3.14")
        assertEq(toks[1].kind, "NUMBER"); assertEq(toks[1].value, 42)
        assertEq(toks[2].kind, "NUMBER"); assertEq(toks[2].value, 3.14)
    end)

    test("lex : string with escapes", function()
        local toks = lexer.tokenize([['hi\n\t' "x\""]])
        assertEq(toks[1].value, "hi\n\t")
        assertEq(toks[2].value, 'x"')
    end)

    test("lex : keywords vs idents", function()
        assertEq(kinds("if and or not as true false nil"),
            "KW_IF,KW_AND,KW_OR,KW_NOT,KW_AS,KW_TRUE,KW_FALSE,KW_NIL,EOF")
    end)

    test("lex : ident lo/up + wildcard", function()
        local toks = lexer.tokenize("foo Bar _ _x")
        assertEq(toks[1].kind, "IDENT_LO"); assertEq(toks[1].value, "foo")
        assertEq(toks[2].kind, "IDENT_UP"); assertEq(toks[2].value, "Bar")
        assertEq(toks[3].kind, "WILDCARD")
        assertEq(toks[4].kind, "IDENT_LO"); assertEq(toks[4].value, "_x")
    end)

    test("lex : longest-match ops", function()
        assertEq(kinds("... == ~= != <= >= || && //"),
            "ELLIPSIS,EQ,NEQ,NEQ,LTE,GTE,OR,AND,IDIV,EOF")
    end)

    test("lex : single-char ops", function()
        assertEq(kinds("|&!?$()[]{}.,:+-*/%"),
            "PIPE,AMP,BANG,QMARK,DOLLAR,LPAREN,RPAREN,LBRACK,RBRACK,LBRACE,RBRACE,DOT,COMMA,COLON,PLUS,MINUS,STAR,SLASH,PERCENT,EOF")
    end)

    test("lex : position tracking", function()
        local toks = lexer.tokenize("foo\n  Bar")
        assertEq(toks[1].line, 1); assertEq(toks[1].col, 1)
        assertEq(toks[2].line, 2); assertEq(toks[2].col, 3)
    end)

    test("lex error : unterminated string", function()
        assertThrows(function() lexer.tokenize("'hello") end)
    end)

    test("lex error : unknown char", function()
        assertThrows(function() lexer.tokenize("@") end)
    end)

    test("lex error : bad escape", function()
        assertThrows(function() lexer.tokenize([['\q']]) end)
    end)

    -- ── parser : literals & primaries ────────────────────────────────────
    test("parse : number literal", function()
        local r = parse("42")
        assertEq(r.kind, ast.LIT); assertEq(r.value, 42)
    end)

    test("parse : negative number literal", function()
        local r = parse("-5")
        assertEq(r.kind, ast.LIT); assertEq(r.value, -5)
    end)

    test("parse : string literal", function()
        local r = parse("'GET'")
        assertEq(r.kind, ast.LIT); assertEq(r.value, "GET")
    end)

    test("parse : booleans + nil", function()
        assertEq(parse("true").value, true)
        assertEq(parse("false").value, false)
        assertEq(parse("nil").kind, ast.LIT)
        assertEq(parse("nil").value, nil)
    end)

    test("parse : wildcard", function()
        assertEq(parse("_").kind, ast.WILD)
    end)

    test("parse : lower ident → binding", function()
        local r = parse("user")
        assertEq(r.kind, ast.BIND); assertEq(r.name, "user")
    end)

    test("parse : upper ident → ref no args", function()
        local r = parse("User")
        assertEq(r.kind, ast.REF); assertEq(r.name, "User"); assertEq(r.args, nil)
    end)

    test("parse : upper ident with field-constraint args", function()
        local r = parse("User(age > 18, name == 'x')")
        assertEq(r.kind, ast.REF)
        assertEq(#r.args, 2)
        assertEq(r.args[1].field, "age");  assertEq(r.args[1].op, ">")
        assertEq(r.args[1].expr.kind, ast.E_LIT); assertEq(r.args[1].expr.value, 18)
        assertEq(r.args[2].field, "name"); assertEq(r.args[2].op, "==")
        assertEq(r.args[2].expr.value, "x")
    end)

    test("parse : interpolation", function()
        local r = parse("$pat")
        assertEq(r.kind, ast.INTERP); assertEq(r.name, "pat")
    end)

    -- ── parser : combinators ─────────────────────────────────────────────
    test("parse : union 2", function()
        local r = parse("'a' | 'b'")
        assertEq(r.kind, ast.UNION); assertEq(#r.items, 2)
        assertEq(r.items[1].value, "a"); assertEq(r.items[2].value, "b")
    end)

    test("parse : union flattened (3 items)", function()
        local r = parse("'a' | 'b' | 'c'")
        assertEq(r.kind, ast.UNION); assertEq(#r.items, 3)
    end)

    test("parse : intersection", function()
        local r = parse("Admin & User")
        assertEq(r.kind, ast.INTER); assertEq(#r.items, 2)
    end)

    test("parse : intersection binds tighter than union", function()
        local r = parse("A | B & C")
        assertEq(r.kind, ast.UNION); assertEq(#r.items, 2)
        assertEq(r.items[2].kind, ast.INTER)
    end)

    test("parse : optional postfix", function()
        local r = parse("Str?")
        assertEq(r.kind, ast.OPT)
        assertEq(r.inner.kind, ast.REF); assertEq(r.inner.name, "Str")
    end)

    test("parse : as binding", function()
        local r = parse("User as u")
        assertEq(r.kind, ast.AS); assertEq(r.name, "u")
        assertEq(r.inner.kind, ast.REF); assertEq(r.inner.name, "User")
    end)

    test("parse : not / bang", function()
        local r1 = parse("!Str")
        assertEq(r1.kind, ast.NOT); assertEq(r1.inner.name, "Str")
        local r2 = parse("not Str")
        assertEq(r2.kind, ast.NOT)
    end)

    test("parse : guard if expr", function()
        local r = parse("x if x > 0")
        assertEq(r.kind, ast.GUARD)
        assertEq(r.inner.kind, ast.BIND); assertEq(r.inner.name, "x")
        assertEq(r.expr.kind, ast.E_BINARY); assertEq(r.expr.op, ">")
    end)

    test("parse : guard applies to whole union", function()
        local r = parse("'a' | 'b' if x > 0")
        assertEq(r.kind, ast.GUARD)
        assertEq(r.inner.kind, ast.UNION)
    end)

    test("parse : paren grouping", function()
        local r = parse("(A | B) & C")
        assertEq(r.kind, ast.INTER)
        assertEq(r.items[1].kind, ast.UNION)
    end)

    test("parse : paren tuple ≥2 items", function()
        local r = parse("('login', user, _)")
        assertEq(r.kind, ast.TUPLE); assertEq(#r.items, 3)
        assertEq(r.items[1].value, "login")
        assertEq(r.items[2].kind, ast.BIND); assertEq(r.items[2].name, "user")
        assertEq(r.items[3].kind, ast.WILD)
    end)

    -- ── parser : shapes ──────────────────────────────────────────────────
    test("parse : shape with typed field", function()
        local r = parse("{ k: 'click' }")
        assertEq(r.kind, ast.SHAPE); assertEq(#r.fields, 1)
        assertEq(r.fields[1].key, "k"); assertEq(r.fields[1].pattern.value, "click")
    end)

    test("parse : shape shorthand binds key→same name", function()
        local r = parse("{ x }")
        assertEq(r.fields[1].shorthand, true)
        assertEq(r.fields[1].key, "x")
        assertEq(r.fields[1].pattern.kind, ast.BIND)
        assertEq(r.fields[1].pattern.name, "x")
    end)

    test("parse : shape multiple fields + trailing comma", function()
        local r = parse("{ a: Str, b, c: Num, }")
        assertEq(#r.fields, 3)
        assertEq(r.fields[2].shorthand, true)
    end)

    test("parse : shape with string key", function()
        local r = parse("{ 'x-y': Str }")
        assertEq(r.fields[1].key, "x-y")
    end)

    test("parse : shape with rest", function()
        local r = parse("{ a: Str, ...rest }")
        assertEq(#r.fields, 1)
        assertEq(r.rest.name, "rest")
    end)

    test("parse : shape rest must be last (error)", function()
        assertThrows(function() parse("{ ...rest, a: Str }") end)
    end)

    -- ── parser : arrays / tuples ─────────────────────────────────────────
    test("parse : empty array", function()
        local r = parse("[]")
        assertEq(r.kind, ast.ARRAY); assertEq(#r.items, 0); assertEq(r.rest, nil)
    end)

    test("parse : tuple-like array no rest", function()
        local r = parse("[Num, Str]")
        assertEq(#r.items, 2); assertEq(r.rest, nil)
    end)

    test("parse : array tail rest", function()
        local r = parse("[Num, Num, ...tail]")
        assertEq(#r.items, 2)
        assertEq(r.rest.atStart, false); assertEq(r.rest.name, "tail")
    end)

    test("parse : array head rest", function()
        local r = parse("[...init, Num]")
        assertEq(#r.items, 1)
        assertEq(r.rest.atStart, true); assertEq(r.rest.name, "init")
    end)

    test("parse : array rest only", function()
        local r = parse("[...r]")
        assertEq(#r.items, 0)
        assertEq(r.rest.atStart, true); assertEq(r.rest.name, "r")
    end)

    test("parse : array anonymous rest", function()
        local r = parse("[Num, ...]")
        assertEq(r.rest.name, nil); assertEq(r.rest.atStart, false)
    end)

    test("parse : array two rests not allowed", function()
        assertThrows(function() parse("[...a, Num, ...b]") end)
    end)

    -- ── parser : combined / examples ─────────────────────────────────────
    test("parse : User(age > 18) as u", function()
        local r = parse("User(age > 18) as u")
        assertEq(r.kind, ast.AS); assertEq(r.name, "u")
        assertEq(r.inner.kind, ast.REF); assertEq(#r.inner.args, 1)
    end)

    test("parse : Admin & { perms: [Str, ...rest]? }", function()
        local r = parse("Admin & { perms: [Str, ...rest]? }")
        assertEq(r.kind, ast.INTER); assertEq(#r.items, 2)
        local shape = r.items[2]
        assertEq(shape.kind, ast.SHAPE)
        local perms = shape.fields[1].pattern
        assertEq(perms.kind, ast.OPT)
        assertEq(perms.inner.kind, ast.ARRAY)
    end)

    test("parse : guarded shape with shorthand", function()
        local r = parse("{ kind: 'click', x, y } if x > 0 and y > 0")
        assertEq(r.kind, ast.GUARD)
        local shape = r.inner
        assertEq(shape.kind, ast.SHAPE); assertEq(#shape.fields, 3)
        local g = r.expr
        assertEq(g.kind, ast.E_BINARY); assertEq(g.op, "and")
    end)

    test("parse : interpolation in union", function()
        local r = parse("$hot | 'fallback'")
        assertEq(r.kind, ast.UNION)
        assertEq(r.items[1].kind, ast.INTERP); assertEq(r.items[1].name, "hot")
        assertEq(r.items[2].value, "fallback")
    end)

    -- ── parser : expression grammar inside guard ─────────────────────────
    test("parse expr : precedence add/mul", function()
        local r = parse("x if x + 1 * 2 == 5")
        local e = r.expr
        assertEq(e.kind, ast.E_BINARY); assertEq(e.op, "==")
        local l = e.left
        assertEq(l.kind, ast.E_BINARY); assertEq(l.op, "+")
        assertEq(l.right.kind, ast.E_BINARY); assertEq(l.right.op, "*")
    end)

    test("parse expr : member access + call", function()
        local r = parse("x if user.role == 'admin'")
        local lhs = r.expr.left
        assertEq(lhs.kind, ast.E_MEMBER); assertEq(lhs.prop, "role")
    end)

    test("parse expr : call with member", function()
        local r = parse("s if isEmail(s)")
        local e = r.expr
        assertEq(e.kind, ast.E_CALL)
        assertEq(e.callee.kind, ast.E_VAR); assertEq(e.callee.name, "isEmail")
        assertEq(#e.args, 1)
    end)

    test("parse expr : not in guard", function()
        local r = parse("s if not isEmail(s)")
        local e = r.expr
        assertEq(e.kind, ast.E_UNARY); assertEq(e.op, "not")
    end)

    test("parse expr : interpolation in expr context", function()
        local r = parse("x if x == $threshold")
        local rhs = r.expr.right
        assertEq(rhs.kind, ast.E_INTERP); assertEq(rhs.name, "threshold")
    end)

    -- ── parser : error cases ─────────────────────────────────────────────
    test("parse error : trailing tokens", function()
        assertThrows(function() parse("Str Num") end)
    end)

    test("parse error : missing close paren", function()
        assertThrows(function() parse("(Str") end)
    end)

    test("parse error : missing close brace", function()
        assertThrows(function() parse("{ k: Str") end)
    end)

    test("parse error : as without ident", function()
        assertThrows(function() parse("Str as 5") end)
    end)

    test("parse error : invalid scope ref args", function()
        assertThrows(function() parse("User(Str)") end)
    end)
end
