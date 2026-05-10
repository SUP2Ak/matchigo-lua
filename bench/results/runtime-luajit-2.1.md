# matchigo-lua bench — `luajit-2.1`

**Runtime** : Lua 5.1 / LuaJIT 2.1.1727870382
**Generated** : 2026-05-10 21:35
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
| `native       if/elseif` | 3 ns | 0 B | 0/30 | 305.31 M/s | 3 ns..4 ns | 3 ns/3 ns | _(base)_ |
| `matchigo     compile() — literal hash` | 7 ns | 0 B | 0/30 | 139.34 M/s | 6 ns..8 ns | 7 ns/8 ns | 2.19× slower |
| `matchigo     matcher + DSL` | 10 ns | 0 B | 0/30 | 97.21 M/s | 9 ns..13 ns | 10 ns/12 ns | 3.14× slower |

## event handler — shape + guard

| benchmark | mean | alloc | gc | rate | min..max | p50/p99 | vs base |
|---|---:|---:|---:|---:|---:|---:|---:|
| `native       if/elseif + field reads` | 21 ns | 0 B | 0/30 | 48.05 M/s | 19 ns..25 ns | 20 ns/23 ns | _(base)_ |
| `matchigo     compile() shape + when` | 44 ns | 0 B | 0/30 | 22.93 M/s | 41 ns..48 ns | 43 ns/47 ns | 2.10× slower |
| `matchigo     matcher + DSL guard` | 98 ns | 69 B | 0/30 | 10.24 M/s | 90 ns..113 ns | 97 ns/109 ns | 4.69× slower |

## validation cascade — guarded predicates

| benchmark | mean | alloc | gc | rate | min..max | p50/p99 | vs base |
|---|---:|---:|---:|---:|---:|---:|---:|
| `native       if/elseif` | 74 ns | 113 B | 0/30 | 13.51 M/s | 66 ns..96 ns | 70 ns/92 ns | _(base)_ |
| `matchigo     compile() with when=` | 84 ns | 113 B | 0/30 | 11.88 M/s | 74 ns..109 ns | 82 ns/103 ns | 1.14× slower |
| `matchigo     matcher + DSL guards` | 348 ns | 320 B | 0/30 | 2.88 M/s | 309 ns..433 ns | 340 ns/417 ns | 4.70× slower |

## state machine — (state, event) tuple dispatch

| benchmark | mean | alloc | gc | rate | min..max | p50/p99 | vs base |
|---|---:|---:|---:|---:|---:|---:|---:|
| `native       nested string compares` | 28 ns | 0 B | 0/30 | 35.55 M/s | 26 ns..33 ns | 27 ns/33 ns | _(base)_ |
| `matchigo     compile() + tuple DSL` | 81 ns | 0 B | 0/30 | 12.39 M/s | 75 ns..96 ns | 80 ns/95 ns | 2.87× slower |

## numeric range bucketing

| benchmark | mean | alloc | gc | rate | min..max | p50/p99 | vs base |
|---|---:|---:|---:|---:|---:|---:|---:|
| `native       if/elseif on bounds` | 30 ns | 0 B | 0/30 | 33.71 M/s | 27 ns..34 ns | 29 ns/34 ns | _(base)_ |
| `matchigo     compile() + range P` | 67 ns | 0 B | 0/30 | 14.97 M/s | 60 ns..78 ns | 65 ns/77 ns | 2.25× slower |

## 50-branch literal dispatch — uniform mix

| benchmark | mean | alloc | gc | rate | min..max | p50/p99 | vs base |
|---|---:|---:|---:|---:|---:|---:|---:|
| `native       if/elseif chain (50)` | 49 ns | 0 B | 0/30 | 20.39 M/s | 43 ns..56 ns | 49 ns/55 ns | _(base)_ |
| `matchigo     compile() — hash O(1)` | 12 ns | 0 B | 0/30 | 85.76 M/s | 11 ns..14 ns | 11 ns/13 ns | 4.21× faster |

## 50-branch literal dispatch — tail hits + fallback

| benchmark | mean | alloc | gc | rate | min..max | p50/p99 | vs base |
|---|---:|---:|---:|---:|---:|---:|---:|
| `native       if/elseif chain (50)` | 50 ns | 0 B | 0/30 | 19.83 M/s | 47 ns..59 ns | 50 ns/53 ns | _(base)_ |
| `matchigo     compile() — hash O(1)` | 13 ns | 0 B | 0/30 | 77.72 M/s | 11 ns..15 ns | 13 ns/15 ns | 3.92× faster |

## data-driven rules — config map

| benchmark | mean | alloc | gc | rate | min..max | p50/p99 | vs base |
|---|---:|---:|---:|---:|---:|---:|---:|
| `native       hand-rolled hash table` | 53 ns | 0 B | 0/30 | 19.00 M/s | 47 ns..63 ns | 51 ns/62 ns | _(base)_ |
| `matchigo     compile(rules-from-data)` | 12 ns | 0 B | 0/30 | 81.41 M/s | 11 ns..15 ns | 12 ns/14 ns | 4.29× faster |

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
| `native       if/elseif (constant 'POST')` | 0 ns | 0 B | 0/30 | 5.04 G/s | 0 ns..0 ns | 0 ns/0 ns | _(base)_ |
| `matchigo     compile() (constant 'POST')` | 0 ns | 0 B | 0/30 | 4.91 G/s | 0 ns..0 ns | 0 ns/0 ns | tie |

