-- AST node kinds and constructors for the matchigo DSL.
-- Pure data : every node is a plain table stamped with a `kind` string.
-- Constructors don't validate ; the parser is the only producer.

local M = {}

-- ── Pattern kinds ─────────────────────────────────────────────────────────
M.LIT     = "Lit"      -- { value }            literal number/string/bool/nil
M.WILD    = "Wild"     -- {}                   `_`
M.BIND    = "Bind"     -- { name }             lowercase ident (anonymous capture)
M.REF     = "Ref"      -- { name, args? }      PascalCase scope ref ; args = list of field constraints
M.INTERP  = "Interp"   -- { name }             `$ident` runtime injection
M.UNION   = "Union"    -- { items }            n-ary `A | B | C`
M.INTER   = "Inter"    -- { items }            n-ary `A & B & C`
M.OPT     = "Opt"      -- { inner }            `pat?`
M.AS      = "As"       -- { inner, name }      `pat as name`
M.NOT     = "Not"      -- { inner }            `!pat` / `not pat`
M.GUARD   = "Guard"    -- { inner, expr }      `pat if expr`
M.SHAPE   = "Shape"    -- { fields, rest?, strict }  `{ k: v, k2, ...rest }` or `{| k: v |}`
                       --   field  : { key, pattern, shorthand }
                       --   rest   : { name? } or nil (mutually exclusive with strict=true)
                       --   strict : true ⇒ from `{| ... |}`, no extras allowed
M.TUPLE   = "Tuple"    -- { items }            `(a, b)` ≥2
M.ARRAY   = "Array"    -- { items, rest? }     `[a, b, ...r]` or `[...r, a, b]`
                       --   rest : { name?, atStart } or nil

-- ── Expr kinds (used inside guards) ───────────────────────────────────────
M.E_LIT    = "ELit"    -- { value }
M.E_VAR    = "EVar"    -- { name }             ident, resolved against bindings∪scope at eval
M.E_INTERP = "EInterp" -- { name }             `$ident` in expr context
M.E_MEMBER = "EMember" -- { obj, prop }
M.E_CALL   = "ECall"   -- { callee, args }
M.E_UNARY  = "EUnary"  -- { op, operand }
M.E_BINARY = "EBinary" -- { op, left, right }

-- ── Pattern constructors ──────────────────────────────────────────────────
function M.lit(v)              return { kind = M.LIT,   value = v } end
function M.wild()              return { kind = M.WILD } end
function M.bind(name)          return { kind = M.BIND,  name = name } end
function M.ref(name, args)     return { kind = M.REF,   name = name, args = args } end
function M.interp(name)        return { kind = M.INTERP, name = name } end
function M.union(items)        return { kind = M.UNION, items = items } end
function M.inter(items)        return { kind = M.INTER, items = items } end
function M.opt(inner)          return { kind = M.OPT,   inner = inner } end
function M.asNode(inner, name) return { kind = M.AS,    inner = inner, name = name } end
function M.notNode(inner)      return { kind = M.NOT,   inner = inner } end
function M.guard(inner, expr)  return { kind = M.GUARD, inner = inner, expr = expr } end
function M.shape(fields, rest, strict) return { kind = M.SHAPE, fields = fields, rest = rest, strict = strict or false } end
function M.tuple(items)        return { kind = M.TUPLE, items = items } end
function M.array(items, rest)  return { kind = M.ARRAY, items = items, rest = rest } end

-- ── Expr constructors ─────────────────────────────────────────────────────
function M.eLit(v)               return { kind = M.E_LIT,    value = v } end
function M.eVar(name)            return { kind = M.E_VAR,    name = name } end
function M.eInterp(name)         return { kind = M.E_INTERP, name = name } end
function M.eMember(obj, prop)    return { kind = M.E_MEMBER, obj = obj, prop = prop } end
function M.eCall(callee, args)   return { kind = M.E_CALL,   callee = callee, args = args } end
function M.eUnary(op, operand)   return { kind = M.E_UNARY,  op = op, operand = operand } end
function M.eBinary(op, l, r)     return { kind = M.E_BINARY, op = op, left = l, right = r } end

return M
