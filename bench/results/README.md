# matchigo-lua benchmark results

📖 English · [Français](./README.fr.md)

Live, reproducible benchmark output for matchigo-lua's pattern-matching dispatchers
versus hand-written native Lua (`if/elseif` chains and `t[key]` lookup tables).

> [!IMPORTANT]
> **These numbers do not reflect production reality.** They are deliberately
> measured in microsecond-tight loops with cycling inputs to surface the
> *abstraction's* per-call overhead. In any real application a 2–5× ratio
> here is invisible noise next to HTTP calls, DB queries, file IO, or even
> a single Lua table allocation in your request handler.
>
> Pick a dispatcher on **readability**, **maintainability**, and **how it
> reads when you re-open the code six months later**. Not on these ratios.
> The bench tells you what dispatch costs ; only your profiler tells you
> whether it matters for *your* app.

---

## What's in this directory

| File | What |
|---|---|
| [`matrix.md`](./matrix.md) | Cross-runtime aggregate. One row per benchmark, one column per Lua/LuaJIT runtime. Shows `mean · alloc · ratio_vs_native` per cell. |
| [`runtime-5.3.md`](./runtime-5.3.md) | Detailed per-scenario tables for Lua 5.3. Includes `min..max`, `p50/p99`, allocation per call, and GC outlier counts. |
| [`runtime-5.4.md`](./runtime-5.4.md) | Same, Lua 5.4. |
| [`runtime-luajit-2.1.md`](./runtime-luajit-2.1.md) | Same, LuaJIT 2.1. |
| `.stats/*.lua` | Raw stats sidecars consumed by `bench/matrix.lua`. Not committed. |

The matrix is **decoupled from benching** : run `bench/run.lua` under whichever
interpreters you have, drop their stats into `.stats/`, then aggregate at any
time via `lua bench/matrix.lua` — no rebenching required.

---

## How to read the matrix

Each cell reads `mean · alloc · ratio_vs_native` :

- **mean** — average per-call time (cycling through varied inputs each iteration)
- **alloc** — bytes allocated per call (zero for hot paths, > 0 when the dispatcher
  builds tables / closures / bindings)
- **ratio** — relative to the *native* baseline within the same runtime

Native is the baseline in every group. matchigo's row reports how much overhead
the abstraction adds (or, on hash-based scenarios, how much it saves) on that
specific VM.

### Looking at the right column

Different runtimes tell different stories :

- **Lua 5.3 / 5.4** (no JIT) : honest dispatch cost. Numbers are stable, ratios
  reflect the abstraction's real interpreter-level overhead.
- **LuaJIT 2.1** : the JIT inlines aggressively. Pure-dispatch ratios near
  `1.0×` are real — the JIT compiled both contestants to nearly identical
  machine code. The signal that survives JIT optimization is **allocation**,
  so the alloc column matters more on LuaJIT than the ns column.

> [!NOTE]
> The bench cycles through varying inputs every iteration to defeat LuaJIT's
> constant folding and loop-invariant code motion. Without cycling, both
> contestants would report `0 ns` on LuaJIT regardless of dispatcher — the
> JIT would correctly prove the call is free given a predictable input. The
> dedicated **JIT folding showcase** scenario keeps the input constant
> precisely to demonstrate this effect, so you can see the contrast.

---

## When matchigo wins, ties, loses

### matchigo wins

- **Long if/elseif chains** (≥ 20 branches). matchigo's compiled hash dispatch
  is `O(1)` ; native's chain is `O(n)`. The clearest win is the
  `50-branch literal dispatch — tail hits + fallback` scenario.
- **Data-driven rules** built from a config / DB / runtime input. Native has
  to roll its own hash, matchigo just consumes the rules array.
- **Discriminated unions with destructuring**. matchigo extracts fields and
  validates their shape in one declarative step ; native nests `if e.kind ==`
  + manual field reads.

### matchigo ties

- Small dispatch (3–5 branches with simple literals). Native and matchigo
  hash-dispatch end up at the same per-call cost on every runtime.
- Hash-table dispatch built by hand vs `m.compile()` from the same data.
  Both are `O(1)` ; the gap closes to noise.

### matchigo loses

- Tight inline shape matching like `if e.kind == "click"` followed by
  `e.x` / `e.y`. Native is just two field reads ; matchigo has to walk the
  shape descriptor. Expect 1.5–3× slower.
- Tight numeric guards with constant bounds. Native `if n < 10` is one
  comparison ; `P.lt(10)` is a closure call.
- The `matcher() + DSL` chained API on guard-heavy scenarios. The DSL is
  zero-overhead **at compile time** but the guard machinery and binding
  closures cost 4–7× more per call than `compile()` for the same logic.
  Use the DSL for ergonomics ; reach for `compile()` in real hot paths.

---

## Performance roadmap

> [!IMPORTANT]
> **matchigo-lua v1.0 is shipped readable, not maxed out.** The internals
> prioritize a clean compile model + easy maintenance over peak ns counts.
> What's in the matrix above is the **current** state of the dispatcher,
> not its **maximum** achievable performance.

The numbers we publish are the floor of "what a reasonable v1 looks like",
not the ceiling. Concrete avenues we have not yet pulled :

### Specialize the rule list as Lua source (the big one)

Today, `m.compile(rules)` composes closures at runtime — one per `_test`,
one per handler, plus the dispatch shell. Each call walks at least one
closure boundary. The win sitting on the table : **emit a single
`function(v) ... end` Lua source string per rule list at construction
time, then `load(src)` it**. Effectively a JIT-at-construction.

The emitted body knows the rules statically and can :

- Inline every `_test` into the body — no closure call at dispatch.
- Materialize bindings as inline locals (`local x, y = v.x, v.y`)
  instead of allocating a `{ x = ..., y = ... }` binding table per call.
- Specialize hash keys when literals are known.

Expected impact : closes most of the 1.2–1.5× gap on `compile()` ; the
`matcher + DSL` allocation overhead disappears entirely on shape-with-binding
scenarios.

### Recycle binding tables

Where source emission isn't possible (DSL guards that need closures,
or genuinely dynamic patterns), reuse a single per-rule scratch
binding table instead of allocating fresh. Trades a small amount of
liveness analysis at compile-time for zero per-call alloc.

### Flatten wrapper layers

Today `compile()` returns a closure that calls into the dispatcher
that calls the handler. Three call frames. With source emission, this
collapses to one — the dispatcher *is* the function returned, the
handler call is inlined where statically known.

### Iteration micro-opts

- Replace `ipairs(rules)` with `for i = 1, #rules` in the rule walker
  (small win on PUC Lua, no impact on LuaJIT, but free).
- Pre-resolve `pat._test` into upvalues at compile time so the
  dispatcher reads from a flat upvalue array instead of fetching
  fields per call.

### Earlier locals, fewer upvalue lookups

Move `type`, `pairs`, etc. into module-level locals (already done in
parts of the codebase, not uniformly). Saves a global table lookup
per dispatch on PUC Lua.

---

These levers are **concrete, not handwaving**. Together they would
realistically close 30–50 % of the residual gap to native dispatch on
PUC Lua, and erase the matcher+DSL allocation footprint on bound
scenarios. They are **deliberately not in v1.0** because :

- The current numbers are already reasonable for the use cases this
  library targets (config-driven dispatch, discriminated unions,
  Rust-like ergonomics).
- Code clarity matters more for a fresh open-source project than peak
  ns counts. Source emission via `load()` is harder to debug, harder
  to step through, and harder for new contributors to read.
- Optimizing without real-world feedback risks chasing benchmarks
  that don't reflect actual usage.

> [!TIP]
> **If you have a real-world use case where matchigo's overhead actually
> shows up in your profiler — open an issue with metrics.** The
> optimization roadmap above is on the table if there's evidence it
> would help someone. A trace, a flamegraph, a "this dispatcher is the
> top of my profile" — that's what tips the cost/benefit. Generic
> "make it faster" requests will get a polite "send a PR" in return.

---

## Reproducing locally

From the project root :

```sh
# Bench whichever interpreter you have
lua bench/run.lua             # full run, ~3 min — authoritative numbers
lua bench/run.lua --fast      # smoke run, ~30 sec — pipeline check only

# Aggregate everything in .stats/ into matrix.md (no rebenching)
lua bench/matrix.lua

# Or rebench all detected runtimes, then render
lua bench/matrix.lua --all

# Or rebench specific runtimes only
lua bench/matrix.lua 5.4=path/to/lua-5.4 luajit=path/to/luajit
```

Need the runtime matrix installed first ? See `scripts/install-lua.{ps1,sh}` —
both build self-contained Lua 5.1 / 5.2 / 5.3 / 5.4 / LuaJIT 2.1 trees under
`./.lua/` via [hererocks](https://github.com/luarocks/hererocks).

---

> [!CAUTION]
> **Do not benchmark on a shared CI runner and trust the absolute ns numbers.**
> GitHub-hosted runners are mutualized VMs with noisy neighbors ; the same
> bench can vary 30–100% between runs. The CI smoke job exists only to verify
> the bench script runs cleanly across runtimes. Authoritative numbers come
> from local runs on stable hardware.
