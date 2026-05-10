# matchigo-lua bench — `5.4`

**Runtime** : Lua 5.4 (no JIT)
**Generated** : 2026-05-10 21:32
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
| `native       if/elseif` | 42 ns | 0 B | 0/30 | 24.05 M/s | 41 ns..42 ns | 42 ns/42 ns | _(base)_ |
| `matchigo     compile() — literal hash` | 52 ns | 0 B | 0/30 | 19.29 M/s | 50 ns..55 ns | 52 ns/53 ns | 1.25× slower |
| `matchigo     matcher + DSL` | 51 ns | 0 B | 0/30 | 19.48 M/s | 51 ns..52 ns | 51 ns/52 ns | 1.23× slower |

## event handler — shape + guard

| benchmark | mean | alloc | gc | rate | min..max | p50/p99 | vs base |
|---|---:|---:|---:|---:|---:|---:|---:|
| `native       if/elseif + field reads` | 91 ns | 0 B | 0/30 | 11.02 M/s | 89 ns..93 ns | 91 ns/92 ns | _(base)_ |
| `matchigo     compile() shape + when` | 287 ns | 0 B | 0/30 | 3.48 M/s | 285 ns..296 ns | 287 ns/290 ns | 3.17× slower |
| `matchigo     matcher + DSL guard` | 612 ns | 53 B | 0/30 | 1.63 M/s | 600 ns..630 ns | 610 ns/630 ns | 6.75× slower |

## validation cascade — guarded predicates

| benchmark | mean | alloc | gc | rate | min..max | p50/p99 | vs base |
|---|---:|---:|---:|---:|---:|---:|---:|
| `native       if/elseif` | 238 ns | 99 B | 0/30 | 4.20 M/s | 235 ns..243 ns | 238 ns/243 ns | _(base)_ |
| `matchigo     compile() with when=` | 347 ns | 99 B | 0/30 | 2.88 M/s | 332 ns..401 ns | 342 ns/374 ns | 1.46× slower |
| `matchigo     matcher + DSL guards` | 909 ns | 262 B | 0/30 | 1.10 M/s | 880 ns..960 ns | 910 ns/940 ns | 3.82× slower |

## state machine — (state, event) tuple dispatch

| benchmark | mean | alloc | gc | rate | min..max | p50/p99 | vs base |
|---|---:|---:|---:|---:|---:|---:|---:|
| `native       nested string compares` | 59 ns | 0 B | 0/30 | 17.01 M/s | 49 ns..82 ns | 55 ns/82 ns | _(base)_ |
| `matchigo     compile() + tuple DSL` | 344 ns | 0 B | 0/30 | 2.90 M/s | 296 ns..436 ns | 338 ns/407 ns | 5.86× slower |

## numeric range bucketing

| benchmark | mean | alloc | gc | rate | min..max | p50/p99 | vs base |
|---|---:|---:|---:|---:|---:|---:|---:|
| `native       if/elseif on bounds` | 50 ns | 0 B | 0/30 | 19.89 M/s | 39 ns..59 ns | 52 ns/59 ns | _(base)_ |
| `matchigo     compile() + range P` | 156 ns | 0 B | 0/30 | 6.42 M/s | 132 ns..190 ns | 154 ns/183 ns | 3.10× slower |

## 50-branch literal dispatch — uniform mix

| benchmark | mean | alloc | gc | rate | min..max | p50/p99 | vs base |
|---|---:|---:|---:|---:|---:|---:|---:|
| `native       if/elseif chain (50)` | 138 ns | 0 B | 0/30 | 7.25 M/s | 112 ns..179 ns | 133 ns/179 ns | _(base)_ |
| `matchigo     compile() — hash O(1)` | 64 ns | 0 B | 0/30 | 15.62 M/s | 51 ns..74 ns | 66 ns/74 ns | 2.15× faster |

## 50-branch literal dispatch — tail hits + fallback

| benchmark | mean | alloc | gc | rate | min..max | p50/p99 | vs base |
|---|---:|---:|---:|---:|---:|---:|---:|
| `native       if/elseif chain (50)` | 170 ns | 0 B | 0/30 | 5.88 M/s | 155 ns..232 ns | 162 ns/206 ns | _(base)_ |
| `matchigo     compile() — hash O(1)` | 56 ns | 0 B | 0/30 | 17.92 M/s | 53 ns..72 ns | 55 ns/64 ns | 3.05× faster |

## data-driven rules — config map

| benchmark | mean | alloc | gc | rate | min..max | p50/p99 | vs base |
|---|---:|---:|---:|---:|---:|---:|---:|
| `native       hand-rolled hash table` | 55 ns | 0 B | 0/30 | 18.29 M/s | 49 ns..68 ns | 53 ns/66 ns | _(base)_ |
| `matchigo     compile(rules-from-data)` | 58 ns | 0 B | 0/30 | 17.19 M/s | 50 ns..74 ns | 56 ns/72 ns | 1.06× slower |

