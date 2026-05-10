# matchigo-lua bench — `luajit-2.1`

**Runtime** : Lua 5.1 / LuaJIT 2.1.1727870382
**Generated** : 2026-05-10 16:31
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
| `native       if/elseif` | 3 ns | 0 B | 0/30 | 307.41 M/s | 3 ns..3 ns | 3 ns/3 ns | _(base)_ |
| `matchigo     compile() — literal hash` | 6 ns | 0 B | 0/30 | 160.94 M/s | 6 ns..6 ns | 6 ns/6 ns | 1.91× slower |
| `matchigo     matcher + DSL` | 10 ns | 0 B | 0/30 | 103.88 M/s | 10 ns..10 ns | 10 ns/10 ns | 2.96× slower |

## event handler — shape + guard

| benchmark | mean | alloc | gc | rate | min..max | p50/p99 | vs base |
|---|---:|---:|---:|---:|---:|---:|---:|
| `native       if/elseif + field reads` | 19 ns | 0 B | 0/30 | 51.97 M/s | 19 ns..20 ns | 19 ns/20 ns | _(base)_ |
| `matchigo     compile() shape + when` | 42 ns | 0 B | 0/30 | 24.08 M/s | 41 ns..42 ns | 42 ns/42 ns | 2.16× slower |
| `matchigo     matcher + DSL guard` | 95 ns | 69 B | 0/30 | 10.57 M/s | 93 ns..98 ns | 94 ns/96 ns | 4.92× slower |

## validation cascade — guarded predicates

| benchmark | mean | alloc | gc | rate | min..max | p50/p99 | vs base |
|---|---:|---:|---:|---:|---:|---:|---:|
| `native       if/elseif` | 68 ns | 113 B | 0/30 | 14.72 M/s | 66 ns..73 ns | 68 ns/70 ns | _(base)_ |
| `matchigo     compile() with when=` | 77 ns | 113 B | 0/30 | 12.96 M/s | 75 ns..84 ns | 77 ns/79 ns | 1.14× slower |
| `matchigo     matcher + DSL guards` | 296 ns | 320 B | 0/30 | 3.38 M/s | 292 ns..304 ns | 296 ns/301 ns | 4.36× slower |

## state machine — (state, event) tuple dispatch

| benchmark | mean | alloc | gc | rate | min..max | p50/p99 | vs base |
|---|---:|---:|---:|---:|---:|---:|---:|
| `native       nested string compares` | 26 ns | 0 B | 0/30 | 39.14 M/s | 25 ns..27 ns | 26 ns/26 ns | _(base)_ |
| `matchigo     compile() + tuple DSL` | 67 ns | 0 B | 0/30 | 14.97 M/s | 66 ns..70 ns | 66 ns/69 ns | 2.61× slower |

## numeric range bucketing

| benchmark | mean | alloc | gc | rate | min..max | p50/p99 | vs base |
|---|---:|---:|---:|---:|---:|---:|---:|
| `native       if/elseif on bounds` | 27 ns | 0 B | 0/30 | 36.62 M/s | 27 ns..30 ns | 27 ns/30 ns | _(base)_ |
| `matchigo     compile() + range P` | 62 ns | 0 B | 0/30 | 16.24 M/s | 61 ns..65 ns | 61 ns/64 ns | 2.26× slower |

## 50-branch literal dispatch — uniform mix

| benchmark | mean | alloc | gc | rate | min..max | p50/p99 | vs base |
|---|---:|---:|---:|---:|---:|---:|---:|
| `native       if/elseif chain (50)` | 43 ns | 0 B | 0/30 | 23.07 M/s | 43 ns..44 ns | 43 ns/44 ns | _(base)_ |
| `matchigo     compile() — hash O(1)` | 11 ns | 0 B | 0/30 | 88.97 M/s | 11 ns..12 ns | 11 ns/11 ns | 3.86× faster |

## 50-branch literal dispatch — tail hits + fallback

| benchmark | mean | alloc | gc | rate | min..max | p50/p99 | vs base |
|---|---:|---:|---:|---:|---:|---:|---:|
| `native       if/elseif chain (50)` | 47 ns | 0 B | 0/30 | 21.16 M/s | 47 ns..48 ns | 47 ns/48 ns | _(base)_ |
| `matchigo     compile() — hash O(1)` | 12 ns | 0 B | 0/30 | 86.26 M/s | 11 ns..12 ns | 12 ns/12 ns | 4.08× faster |

## data-driven rules — config map

| benchmark | mean | alloc | gc | rate | min..max | p50/p99 | vs base |
|---|---:|---:|---:|---:|---:|---:|---:|
| `native       hand-rolled hash table` | 47 ns | 0 B | 0/30 | 21.33 M/s | 46 ns..48 ns | 47 ns/48 ns | _(base)_ |
| `matchigo     compile(rules-from-data)` | 11 ns | 0 B | 0/30 | 90.44 M/s | 11 ns..11 ns | 11 ns/11 ns | 4.24× faster |

## JIT folding showcase — constant input (educational)

> [!TIP]
> **Educational scenario — this is where LuaJIT shines.**
> The dispatcher is called with a **constant** input every
> iteration (no cycling), so the JIT can inline the body and
> hoist the entire compute out of the loop (LICM). Both
> contestants collapse to ~0 ns. **Lesson** : in a hot loop
> with a constant input, LuaJIT erases dispatch overhead
> entirely, regardless of which dispatcher you pick. Compare
> against the cycled scenarios above to see the real cost
> when the JIT cannot fold the input away.

| benchmark | mean | alloc | gc | rate | min..max | p50/p99 | vs base |
|---|---:|---:|---:|---:|---:|---:|---:|
| `native       if/elseif (constant 'POST')` | 0 ns | 0 B | 0/30 | 5.33 G/s | 0 ns..0 ns | 0 ns/0 ns | _(base)_ |
| `matchigo     compile() (constant 'POST')` | 0 ns | 0 B | 0/30 | 5.33 G/s | 0 ns..0 ns | 0 ns/0 ns | tie |

