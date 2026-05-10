# matchigo-lua bench — `5.3`

**Runtime** : Lua 5.3 (no JIT)
**Generated** : 2026-05-10 21:37
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
| `native       if/elseif` | 52 ns | 0 B | 0/30 | 19.40 M/s | 47 ns..59 ns | 51 ns/58 ns | _(base)_ |
| `matchigo     compile() — literal hash` | 61 ns | 0 B | 0/30 | 16.50 M/s | 54 ns..80 ns | 60 ns/70 ns | 1.18× slower |
| `matchigo     matcher + DSL` | 64 ns | 0 B | 0/30 | 15.72 M/s | 54 ns..85 ns | 59 ns/78 ns | 1.23× slower |

## event handler — shape + guard

| benchmark | mean | alloc | gc | rate | min..max | p50/p99 | vs base |
|---|---:|---:|---:|---:|---:|---:|---:|
| `native       if/elseif + field reads` | 101 ns | 0 B | 0/30 | 9.88 M/s | 88 ns..134 ns | 97 ns/132 ns | _(base)_ |
| `matchigo     compile() shape + when` | 325 ns | 0 B | 0/30 | 3.08 M/s | 292 ns..413 ns | 316 ns/387 ns | 3.21× slower |
| `matchigo     matcher + DSL guard` | 745 ns | 61 B | 0/30 | 1.34 M/s | 580 ns..1000 ns | 735 ns/960 ns | 7.36× slower |

## validation cascade — guarded predicates

| benchmark | mean | alloc | gc | rate | min..max | p50/p99 | vs base |
|---|---:|---:|---:|---:|---:|---:|---:|
| `native       if/elseif` | 283 ns | 114 B | 0/30 | 3.53 M/s | 249 ns..345 ns | 278 ns/342 ns | _(base)_ |
| `matchigo     compile() with when=` | 370 ns | 114 B | 0/30 | 2.70 M/s | 326 ns..455 ns | 362 ns/431 ns | 1.31× slower |
| `matchigo     matcher + DSL guards` | 1.16 µs | 283 B | 0/30 | 860.34 K/s | 920 ns..1.66 µs | 1.08 µs/1.66 µs | 4.11× slower |

## state machine — (state, event) tuple dispatch

| benchmark | mean | alloc | gc | rate | min..max | p50/p99 | vs base |
|---|---:|---:|---:|---:|---:|---:|---:|
| `native       nested string compares` | 66 ns | 0 B | 0/30 | 15.23 M/s | 55 ns..93 ns | 63 ns/88 ns | _(base)_ |
| `matchigo     compile() + tuple DSL` | 373 ns | 0 B | 0/30 | 2.68 M/s | 337 ns..451 ns | 371 ns/420 ns | 5.68× slower |

## numeric range bucketing

| benchmark | mean | alloc | gc | rate | min..max | p50/p99 | vs base |
|---|---:|---:|---:|---:|---:|---:|---:|
| `native       if/elseif on bounds` | 53 ns | 0 B | 0/30 | 18.85 M/s | 45 ns..71 ns | 52 ns/71 ns | _(base)_ |
| `matchigo     compile() + range P` | 160 ns | 0 B | 0/30 | 6.26 M/s | 140 ns..199 ns | 156 ns/191 ns | 3.01× slower |

## 50-branch literal dispatch — uniform mix

| benchmark | mean | alloc | gc | rate | min..max | p50/p99 | vs base |
|---|---:|---:|---:|---:|---:|---:|---:|
| `native       if/elseif chain (50)` | 147 ns | 0 B | 0/30 | 6.80 M/s | 127 ns..212 ns | 140 ns/184 ns | _(base)_ |
| `matchigo     compile() — hash O(1)` | 61 ns | 0 B | 0/30 | 16.48 M/s | 55 ns..78 ns | 59 ns/73 ns | 2.43× faster |

## 50-branch literal dispatch — tail hits + fallback

| benchmark | mean | alloc | gc | rate | min..max | p50/p99 | vs base |
|---|---:|---:|---:|---:|---:|---:|---:|
| `native       if/elseif chain (50)` | 208 ns | 0 B | 0/30 | 4.81 M/s | 181 ns..288 ns | 200 ns/266 ns | _(base)_ |
| `matchigo     compile() — hash O(1)` | 61 ns | 0 B | 0/30 | 16.40 M/s | 54 ns..80 ns | 58 ns/73 ns | 3.41× faster |

## data-driven rules — config map

| benchmark | mean | alloc | gc | rate | min..max | p50/p99 | vs base |
|---|---:|---:|---:|---:|---:|---:|---:|
| `native       hand-rolled hash table` | 54 ns | 0 B | 0/30 | 18.47 M/s | 50 ns..69 ns | 52 ns/61 ns | _(base)_ |
| `matchigo     compile(rules-from-data)` | 62 ns | 0 B | 0/30 | 16.03 M/s | 54 ns..82 ns | 59 ns/80 ns | 1.15× slower |

