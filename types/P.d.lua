---@meta

---@class matchigo.P
local P = {}

-- ── Leaf sentinels ─────────────────────────────────────────────────────

---@type matchigo.Pattern
P.any = nil
---@type matchigo.Pattern
P.string = nil
---@type matchigo.Pattern
P.number = nil
---@type matchigo.Pattern
P.boolean = nil
---@type matchigo.Pattern
P.bigint = nil
---@type matchigo.Pattern
P.func = nil
---@type matchigo.Pattern
P.nullish = nil
---@type matchigo.Pattern
P.defined = nil
---@type matchigo.Pattern
P.nonNullable = nil
---@type matchigo.Pattern
P.positive = nil
---@type matchigo.Pattern
P.negative = nil
---@type matchigo.Pattern
P.integer = nil
---@type matchigo.Pattern
P.finite = nil
---@type matchigo.Pattern
P.bigintPositive = nil
---@type matchigo.Pattern
P.bigintNegative = nil

-- ── Predicate ──────────────────────────────────────────────────────────

---Custom predicate. The `_test` is the predicate fn directly (no wrapper).
---@param fn fun(v: any): boolean
---@return matchigo.Pattern
function P.when(fn) end

---Match if `getmetatable(v) == mt`.
---@param mt table
---@return matchigo.Pattern
function P.instanceOf(mt) end

---Match if `v` is a string and `string.match(v, pat) ~= nil`.
---@param pat string
---@return matchigo.Pattern
function P.luaPattern(pat) end

-- ── String ─────────────────────────────────────────────────────────────

---@param s string
---@return matchigo.Pattern
function P.startsWithStr(s) end
---@param s string
---@return matchigo.Pattern
function P.endsWithStr(s) end
---@param s string
---@return matchigo.Pattern
function P.includesStr(s) end
---@param n integer
---@return matchigo.Pattern
function P.lengthStr(n) end
---@param n integer
---@return matchigo.Pattern
function P.minLengthStr(n) end
---@param n integer
---@return matchigo.Pattern
function P.maxLengthStr(n) end

-- ── Number ranges ──────────────────────────────────────────────────────

---@param min number
---@param max number
---@return matchigo.Pattern
function P.between(min, max) end
---@param n number
---@return matchigo.Pattern
function P.gt(n) end
---@param n number
---@return matchigo.Pattern
function P.gte(n) end
---@param n number
---@return matchigo.Pattern
function P.lt(n) end
---@param n number
---@return matchigo.Pattern
function P.lte(n) end

-- ── BigInt thresholds ──────────────────────────────────────────────────

---@param n matchigo.BigInt|number|string
---@return matchigo.Pattern
function P.bigintGt(n) end
---@param n matchigo.BigInt|number|string
---@return matchigo.Pattern
function P.bigintGte(n) end
---@param n matchigo.BigInt|number|string
---@return matchigo.Pattern
function P.bigintLt(n) end
---@param n matchigo.BigInt|number|string
---@return matchigo.Pattern
function P.bigintLte(n) end
---@param min matchigo.BigInt|number|string
---@param max matchigo.BigInt|number|string
---@return matchigo.Pattern
function P.bigintBetween(min, max) end

-- ── Disjunction ────────────────────────────────────────────────────────

---Pure-value disjunction. All members must be primitives (non-tables).
---Hash O(1) lookup at runtime ; NaN/nil are shielded into flags.
---@param ... any
---@return matchigo.Pattern
function P.union(...) end

---Pattern-typed disjunction. Members can be any PatternLike. Walks the
---list at runtime ; use `union` instead when all members are values.
---@param ... matchigo.PatternLike
---@return matchigo.Pattern
function P.anyOf(...) end

-- ── Negation / Optional / Intersection ─────────────────────────────────

---@param inner matchigo.PatternLike
---@return matchigo.Pattern
function P.not_(inner) end

---@param inner matchigo.PatternLike
---@return matchigo.Pattern
function P.optional(inner) end

---@param ... matchigo.PatternLike
---@return matchigo.Pattern
function P.intersection(...) end

-- ── Sequences ──────────────────────────────────────────────────────────

---Match a sequence where every element matches `item`.
---@param item matchigo.PatternLike
---@return matchigo.Pattern
function P.array(item) end

---@param item matchigo.PatternLike
---@param opts? { min?: integer, max?: integer }
---@return matchigo.Pattern
function P.arrayOf(item, opts) end

---Match a sequence where at least one element matches `item`.
---@param item matchigo.PatternLike
---@return matchigo.Pattern
function P.arrayIncludes(item) end

---Exact-length sequence : `v[i]` matches `items[i]` for all i, and `#v == n`.
---@param ... matchigo.PatternLike
---@return matchigo.Pattern
function P.tuple(...) end

---Match prefix : `v[1..n]` matches `items[1..n]` ; `v` may be longer.
---@param ... matchigo.PatternLike
---@return matchigo.Pattern
function P.startsWith(...) end

---Match suffix : `v[#-n+1..#]` matches `items[1..n]` ; `v` may be longer.
---@param ... matchigo.PatternLike
---@return matchigo.Pattern
function P.endsWith(...) end

-- ── Map / Set ──────────────────────────────────────────────────────────

---@param item matchigo.PatternLike
---@return matchigo.Pattern
function P.set(item) end

---@param key matchigo.PatternLike
---@param value matchigo.PatternLike
---@return matchigo.Pattern
function P.map(key, value) end

-- ── Bindings ───────────────────────────────────────────────────────────

---Capture for the handler bindings. Overloads :
---  `P.select()`                  - anonymous capture
---  `P.select("label")`           - labelled capture
---  `P.select(subPattern)`        - anonymous + refined
---  `P.select("label", subPat)`   - labelled + refined
---@param arg1? string|matchigo.PatternLike
---@param arg2? matchigo.PatternLike
---@return matchigo.Pattern
function P.select(arg1, arg2) end

---Always-true pattern that exposes a labelled binding whose extracted
---value is computed via a closure (used by the DSL for `...rest` named
---bindings in arrays / shapes).
---@param label string
---@param sliceFn fun(v: any): any
---@return matchigo.Pattern
function P.captureSlice(label, sliceFn) end

return P
