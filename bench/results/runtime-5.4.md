# matchigo-lua bench — `5.4`

**Runtime** : Lua 5.4 (no JIT)
**Generated** : 2026-05-10 16:28
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
| `native       if/elseif` | 42 ns | 0 B | 0/30 | 23.91 M/s | 41 ns..42 ns | 42 ns/42 ns | _(base)_ |
| `matchigo     compile() — literal hash` | 52 ns | 0 B | 0/30 | 19.05 M/s | 51 ns..55 ns | 52 ns/54 ns | 1.26× slower |
| `matchigo     matcher + DSL` | 52 ns | 0 B | 0/30 | 19.12 M/s | 51 ns..59 ns | 52 ns/53 ns | 1.25× slower |

## event handler — shape + guard

| benchmark | mean | alloc | gc | rate | min..max | p50/p99 | vs base |
|---|---:|---:|---:|---:|---:|---:|---:|
| `native       if/elseif + field reads` | 91 ns | 0 B | 0/30 | 10.94 M/s | 90 ns..97 ns | 91 ns/95 ns | _(base)_ |
| `matchigo     compile() shape + when` | 286 ns | 0 B | 0/30 | 3.50 M/s | 283 ns..289 ns | 286 ns/289 ns | 3.13× slower |
| `matchigo     matcher + DSL guard` | 583 ns | 53 B | 0/30 | 1.71 M/s | 570 ns..630 ns | 580 ns/590 ns | 6.38× slower |

## validation cascade — guarded predicates

| benchmark | mean | alloc | gc | rate | min..max | p50/p99 | vs base |
|---|---:|---:|---:|---:|---:|---:|---:|
| `native       if/elseif` | 234 ns | 99 B | 0/30 | 4.27 M/s | 231 ns..243 ns | 233 ns/242 ns | _(base)_ |
| `matchigo     compile() with when=` | 315 ns | 99 B | 0/30 | 3.18 M/s | 311 ns..329 ns | 313 ns/326 ns | 1.34× slower |
| `matchigo     matcher + DSL guards` | 911 ns | 262 B | 0/30 | 1.10 M/s | 880 ns..1.00 µs | 900 ns/1.00 µs | 3.89× slower |

## state machine — (state, event) tuple dispatch

| benchmark | mean | alloc | gc | rate | min..max | p50/p99 | vs base |
|---|---:|---:|---:|---:|---:|---:|---:|
| `native       nested string compares` | 51 ns | 0 B | 0/30 | 19.63 M/s | 50 ns..54 ns | 51 ns/53 ns | _(base)_ |
| `matchigo     compile() + tuple DSL` | 299 ns | 0 B | 0/30 | 3.35 M/s | 295 ns..307 ns | 298 ns/306 ns | 5.86× slower |

## numeric range bucketing

| benchmark | mean | alloc | gc | rate | min..max | p50/p99 | vs base |
|---|---:|---:|---:|---:|---:|---:|---:|
| `native       if/elseif on bounds` | 40 ns | 0 B | 0/30 | 25.26 M/s | 39 ns..40 ns | 40 ns/40 ns | _(base)_ |
| `matchigo     compile() + range P` | 135 ns | 0 B | 0/30 | 7.39 M/s | 133 ns..146 ns | 135 ns/140 ns | 3.42× slower |

## 50-branch literal dispatch — uniform mix

| benchmark | mean | alloc | gc | rate | min..max | p50/p99 | vs base |
|---|---:|---:|---:|---:|---:|---:|---:|
| `native       if/elseif chain (50)` | 113 ns | 0 B | 0/30 | 8.82 M/s | 111 ns..120 ns | 113 ns/116 ns | _(base)_ |
| `matchigo     compile() — hash O(1)` | 56 ns | 0 B | 0/30 | 17.70 M/s | 55 ns..59 ns | 56 ns/58 ns | 2.01× faster |

## 50-branch literal dispatch — tail hits + fallback

| benchmark | mean | alloc | gc | rate | min..max | p50/p99 | vs base |
|---|---:|---:|---:|---:|---:|---:|---:|
| `native       if/elseif chain (50)` | 159 ns | 0 B | 0/30 | 6.28 M/s | 157 ns..168 ns | 158 ns/167 ns | _(base)_ |
| `matchigo     compile() — hash O(1)` | 54 ns | 0 B | 0/30 | 18.35 M/s | 54 ns..56 ns | 54 ns/56 ns | 2.92× faster |

## data-driven rules — config map

| benchmark | mean | alloc | gc | rate | min..max | p50/p99 | vs base |
|---|---:|---:|---:|---:|---:|---:|---:|
| `native       hand-rolled hash table` | 52 ns | 0 B | 0/30 | 19.35 M/s | 50 ns..55 ns | 52 ns/53 ns | _(base)_ |
| `matchigo     compile(rules-from-data)` | 52 ns | 0 B | 0/30 | 19.14 M/s | 51 ns..55 ns | 52 ns/53 ns | tie |

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
| `native       if/elseif (constant 'POST')` | 37 ns | 0 B | 0/30 | 27.36 M/s | 36 ns..37 ns | 37 ns/37 ns | _(base)_ |
| `matchigo     compile() (constant 'POST')` | 50 ns | 0 B | 0/30 | 20.08 M/s | 49 ns..50 ns | 50 ns/50 ns | 1.36× slower |

