# matchigo-lua bench — `5.3`

**Runtime** : Lua 5.3 (no JIT)
**Generated** : 2026-05-10 16:33
**Config** : 30 samples, 200 warmup, 50ms calibration target

> [!IMPORTANT]
> **Reading these numbers in context.** Microbenches measure the
> *abstraction's* per-call overhead in tight loops with cycling
> inputs — that's the point, not a flaw.
>
> In most production code, Lua compute runs in **nanoseconds**
> while the work around it (a SQL query, an HTTP call, a file
> read, a queue pop) runs in **milliseconds**. A `2× slower` row
> here is ~50–200 ns extra per dispatch — orders of magnitude
> below the noise floor of any external IO.
>
> **Where it does matter** : real-time framing contexts (game
> engines like LÖVE/Defold, ~16 ms frame budget at 60 Hz),
> high-frequency event loops (OpenResty under load), or any tight
> inner loop with no IO. In those, **the alloc column matters
> more than the ns column** — sustained per-call allocation
> causes GC pauses that *will* eat your frame budget. Hot paths
> with `alloc = 0 B` are GC-safe regardless of which dispatcher
> you pick.
>
> Pick on readability + maintainability + your runtime's actual
> allocation pressure. The bench tells you what dispatch costs ;
> only your profiler tells you whether it matters for *your* app.

Each scenario cycles through varying inputs to defeat JIT constant
folding ; the cycling cost is uniform across all benches in a
scenario, so ratios stay accurate even on LuaJIT.

## HTTP router (5 literals + fallback)

| benchmark | mean | alloc | gc | rate | min..max | p50/p99 | vs base |
|---|---:|---:|---:|---:|---:|---:|---:|
| `native       if/elseif` | 47 ns | 0 B | 0/30 | 21.21 M/s | 46 ns..49 ns | 47 ns/48 ns | _(base)_ |
| `matchigo     compile() — literal hash` | 51 ns | 0 B | 0/30 | 19.77 M/s | 50 ns..51 ns | 51 ns/51 ns | 1.07× slower |
| `matchigo     matcher + DSL` | 51 ns | 0 B | 0/30 | 19.78 M/s | 50 ns..52 ns | 51 ns/51 ns | 1.07× slower |

## event handler — shape + guard

| benchmark | mean | alloc | gc | rate | min..max | p50/p99 | vs base |
|---|---:|---:|---:|---:|---:|---:|---:|
| `native       if/elseif + field reads` | 89 ns | 0 B | 0/30 | 11.21 M/s | 87 ns..91 ns | 89 ns/90 ns | _(base)_ |
| `matchigo     compile() shape + when` | 283 ns | 0 B | 0/30 | 3.53 M/s | 278 ns..293 ns | 283 ns/286 ns | 3.17× slower |
| `matchigo     matcher + DSL guard` | 600 ns | 61 B | 0/30 | 1.67 M/s | 580 ns..620 ns | 600 ns/610 ns | 6.72× slower |

## validation cascade — guarded predicates

| benchmark | mean | alloc | gc | rate | min..max | p50/p99 | vs base |
|---|---:|---:|---:|---:|---:|---:|---:|
| `native       if/elseif` | 257 ns | 114 B | 0/30 | 3.89 M/s | 251 ns..274 ns | 257 ns/262 ns | _(base)_ |
| `matchigo     compile() with when=` | 339 ns | 114 B | 0/30 | 2.95 M/s | 332 ns..357 ns | 339 ns/345 ns | 1.32× slower |
| `matchigo     matcher + DSL guards` | 965 ns | 283 B | 0/30 | 1.04 M/s | 940 ns..990 ns | 965 ns/990 ns | 3.75× slower |

## state machine — (state, event) tuple dispatch

| benchmark | mean | alloc | gc | rate | min..max | p50/p99 | vs base |
|---|---:|---:|---:|---:|---:|---:|---:|
| `native       nested string compares` | 58 ns | 0 B | 0/30 | 17.17 M/s | 56 ns..63 ns | 58 ns/60 ns | _(base)_ |
| `matchigo     compile() + tuple DSL` | 322 ns | 0 B | 0/30 | 3.10 M/s | 320 ns..326 ns | 322 ns/325 ns | 5.53× slower |

## numeric range bucketing

| benchmark | mean | alloc | gc | rate | min..max | p50/p99 | vs base |
|---|---:|---:|---:|---:|---:|---:|---:|
| `native       if/elseif on bounds` | 45 ns | 0 B | 0/30 | 22.30 M/s | 44 ns..45 ns | 45 ns/45 ns | _(base)_ |
| `matchigo     compile() + range P` | 143 ns | 0 B | 0/30 | 6.98 M/s | 142 ns..145 ns | 143 ns/145 ns | 3.20× slower |

## 50-branch literal dispatch — uniform mix

| benchmark | mean | alloc | gc | rate | min..max | p50/p99 | vs base |
|---|---:|---:|---:|---:|---:|---:|---:|
| `native       if/elseif chain (50)` | 129 ns | 0 B | 0/30 | 7.75 M/s | 127 ns..131 ns | 129 ns/131 ns | _(base)_ |
| `matchigo     compile() — hash O(1)` | 56 ns | 0 B | 0/30 | 17.78 M/s | 55 ns..59 ns | 56 ns/59 ns | 2.30× faster |

## 50-branch literal dispatch — tail hits + fallback

| benchmark | mean | alloc | gc | rate | min..max | p50/p99 | vs base |
|---|---:|---:|---:|---:|---:|---:|---:|
| `native       if/elseif chain (50)` | 181 ns | 0 B | 0/30 | 5.51 M/s | 180 ns..185 ns | 181 ns/184 ns | _(base)_ |
| `matchigo     compile() — hash O(1)` | 53 ns | 0 B | 0/30 | 18.92 M/s | 51 ns..56 ns | 53 ns/54 ns | 3.43× faster |

## data-driven rules — config map

| benchmark | mean | alloc | gc | rate | min..max | p50/p99 | vs base |
|---|---:|---:|---:|---:|---:|---:|---:|
| `native       hand-rolled hash table` | 48 ns | 0 B | 0/30 | 20.73 M/s | 48 ns..53 ns | 48 ns/50 ns | _(base)_ |
| `matchigo     compile(rules-from-data)` | 51 ns | 0 B | 0/30 | 19.69 M/s | 50 ns..52 ns | 51 ns/52 ns | 1.05× slower |

## JIT folding showcase — constant input (educational)

> [!NOTE]
> **Educational scenario — the lesson lives on LuaJIT.**
> This bench uses a **constant** input every iteration (no
> cycling). On this non-JIT runtime, the row reads like any
> other dispatch — the per-call cost. The interesting
> contrast (LuaJIT folding both contestants to ~0 ns) lives
> in [`runtime-luajit-2.1.md`](./runtime-luajit-2.1.md) and
> the [matrix](./matrix.md). On Lua 5.x, this scenario is
> just included for parity.

| benchmark | mean | alloc | gc | rate | min..max | p50/p99 | vs base |
|---|---:|---:|---:|---:|---:|---:|---:|
| `native       if/elseif (constant 'POST')` | 35 ns | 0 B | 0/30 | 28.66 M/s | 35 ns..35 ns | 35 ns/35 ns | _(base)_ |
| `matchigo     compile() (constant 'POST')` | 43 ns | 0 B | 0/30 | 23.07 M/s | 43 ns..52 ns | 43 ns/44 ns | 1.24× slower |

