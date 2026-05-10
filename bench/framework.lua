-- Microbench framework for matchigo-lua.
--
-- Design tenets :
--   * Tables-only output (no prose, no i18n, no narrative).
--   * Stats-first : every run dumps a sidecar `.stats/<label>.lua` so the
--     matrix aggregator can rebuild without re-running anything.
--   * JIT-honest : scenarios cycle through varying inputs to defeat
--     LuaJIT's constant-folding and loop-invariant code motion. A pure
--     constant-input bench reports ~0 ns under JIT — that's the JIT
--     correctly proving the call is free, not a measurement bug.
--   * Per-call escape : every benched call's return goes into M._sink
--     (a module-table field LuaJIT cannot prove dead). Combined with
--     varying inputs, this forces a real call per iteration.
--
-- Run from project root :
--   lua bench/run.lua            -- full bench, current interpreter
--   lua bench/run.lua --fast     -- smoke config (samples=5)

local M = {}

local TARGET_BATCH    = (tonumber(os.getenv("MATCHIGO_BENCH_TARGET_MS")) or 50) / 1000
local DEFAULT_WARMUP  =  tonumber(os.getenv("MATCHIGO_BENCH_WARMUP"))  or 200
local DEFAULT_SAMPLES =  tonumber(os.getenv("MATCHIGO_BENCH_SAMPLES")) or 30
local MAX_ITERS = 1e9

local clock = os.clock
local sort  = table.sort
local floor = math.floor

local _scenarios = {}

-- Escape trap : every benched call writes its return here. Without this,
-- LuaJIT eliminates the call entirely when the result is unused.
M._sink = nil

---@param opts { samples?: integer, warmup?: integer, targetMs?: number }
function M.setDefaults(opts)
    if opts.samples  then DEFAULT_SAMPLES = opts.samples  end
    if opts.warmup   then DEFAULT_WARMUP  = opts.warmup   end
    if opts.targetMs then TARGET_BATCH    = opts.targetMs / 1000 end
end

---Stable identifier for the current Lua interpreter.
---  PUC Lua → "5.1" / "5.2" / "5.3" / "5.4" / "5.5"
---  LuaJIT  → "luajit-2.1"
function M.runtimeLabel()
    if jit then
        return "luajit-" .. (jit.version:match("(%d+%.%d+)") or "?")
    end
    return _VERSION:match("(%d+%.%d+)") or "?"
end

---Human-readable runtime description for the report header.
function M.runtimeDescription()
    if jit then return _VERSION .. " / " .. jit.version end
    return _VERSION .. " (no JIT)"
end

local function calibrate(fn)
    local iters = 100
    while iters < MAX_ITERS do
        local t0 = clock()
        for _ = 1, iters do fn() end
        local elapsed = clock() - t0
        if elapsed >= TARGET_BATCH then return iters, elapsed end
        iters = iters * 10
    end
    return iters, 0
end

local function median(sorted)
    local n = #sorted
    if n % 2 == 0 then
        local half = floor(n / 2)
        return (sorted[half] + sorted[half + 1]) / 2
    end
    return sorted[floor((n + 1) / 2)]
end

local function measureAlloc(fn, iters)
    iters = iters or 10000
    for _ = 1, 3 do collectgarbage("collect") end
    collectgarbage("stop")
    local before = collectgarbage("count")
    for _ = 1, iters do fn() end
    local after = collectgarbage("count")
    collectgarbage("restart")
    local bytes = (after - before) * 1024 / iters
    if bytes < 0 then bytes = 0 end
    return bytes
end

local function countOutliers(times, med)
    local n = 0
    for i = 1, #times do
        if times[i] > 5 * med then n = n + 1 end
    end
    return n
end

-- Wrap user fn so successive calls cycle through `inputs` and the return
-- escapes via M._sink. Cycling defeats LuaJIT constant folding ; the
-- escape defeats DCE. Together they force a real dispatch each iteration.
local function wrapFn(userFn, inputs)
    if not inputs or #inputs == 0 then
        return function() M._sink = userFn() end
    end
    local n = #inputs
    local i = 0
    return function()
        i = i + 1
        if i > n then i = 1 end
        M._sink = userFn(inputs[i])
    end
end

local function runOne(name, userFn, inputs, key)
    local fn = wrapFn(userFn, inputs)

    for _ = 1, DEFAULT_WARMUP do fn() end
    local iters = calibrate(fn)

    local times = {}
    for s = 1, DEFAULT_SAMPLES do
        collectgarbage("collect")
        local t0 = clock()
        for _ = 1, iters do fn() end
        local t1 = clock()
        times[s] = (t1 - t0) / iters
    end
    sort(times)

    local sum = 0
    for i = 1, DEFAULT_SAMPLES do sum = sum + times[i] end
    local med = median(times)

    local allocIters = math.max(1000, floor(iters / 100))
    local alloc      = measureAlloc(fn, allocIters)
    local outliers   = countOutliers(times, med)

    return {
        name       = name,
        key        = key,
        iters      = iters,
        samples    = DEFAULT_SAMPLES,
        avg        = sum / DEFAULT_SAMPLES,
        min        = times[1],
        max        = times[DEFAULT_SAMPLES],
        p50        = med,
        p99        = times[math.max(1, floor(DEFAULT_SAMPLES * 0.99))],
        alloc      = alloc,
        gcOutliers = outliers,
    }
end

---Register a scenario.
---@param name string
---@param benches { name: string, fn: fun(input?: any): any, key: string | nil }[]
---@param opts? { inputs?: any[] }
function M.scenario(name, benches, opts)
    opts = opts or {}
    _scenarios[#_scenarios + 1] = {
        name    = name,
        benches = benches,
        inputs  = opts.inputs,
    }
end

local function consoleHeader()
    print(string.rep("=", 84))
    print("matchigo-lua bench  —  " .. M.runtimeDescription())
    print(string.format("samples=%d, warmup=%d, calibration target=%.0fms/batch",
        DEFAULT_SAMPLES, DEFAULT_WARMUP, TARGET_BATCH * 1000))
    print(string.rep("=", 84))
end

---Execute all registered scenarios, return stats.
function M.runAll()
    consoleHeader()

    local groups = {}
    local byKey  = {}

    for _, scenario in ipairs(_scenarios) do
        print()
        print("── " .. scenario.name .. " ──")
        local results = {}
        for _, bench in ipairs(scenario.benches) do
            local r = runOne(bench.name, bench.fn, scenario.inputs, bench.key)
            results[#results + 1] = r
            if r.key then byKey[r.key] = r end
            print(string.format("  %-44s  %7.1f ns  alloc=%5.0f B  gc=%d/%d",
                r.name, r.avg * 1e9, r.alloc, r.gcOutliers, r.samples))
        end
        groups[#groups + 1] = { name = scenario.name, benches = results }
    end

    return {
        groups = groups,
        byKey  = byKey,
        meta   = {
            generated = os.date("%Y-%m-%d %H:%M"),
            runtime   = M.runtimeDescription(),
            label     = M.runtimeLabel(),
            samples   = DEFAULT_SAMPLES,
            warmup    = DEFAULT_WARMUP,
            targetMs  = TARGET_BATCH * 1000,
        },
    }
end

------------------------------------------------------------
-- Stats serialization (Lua-loadable)
------------------------------------------------------------

---@param stats table
---@param path string
function M.writeStats(stats, path)
    local f = assert(io.open(path, "wb"), "Cannot write " .. path)
    local function write(x, indent)
        local t = type(x)
        if t == "string" then
            f:write(string.format("%q", x))
        elseif t == "number" or t == "boolean" or t == "nil" then
            f:write(tostring(x))
        elseif t == "table" then
            f:write("{\n")
            local n = #x
            for i = 1, n do
                f:write(indent .. "  ")
                write(x[i], indent .. "  ")
                f:write(",\n")
            end
            for k, v in pairs(x) do
                if not (type(k) == "number" and k >= 1 and k <= n and k == floor(k)) then
                    f:write(indent .. "  ")
                    if type(k) == "string" and k:match("^[%a_][%w_]*$") then
                        f:write(k .. " = ")
                    else
                        f:write("[")
                        write(k, indent .. "  ")
                        f:write("] = ")
                    end
                    write(v, indent .. "  ")
                    f:write(",\n")
                end
            end
            f:write(indent .. "}")
        else
            error("cannot serialize " .. t)
        end
    end
    f:write("return ")
    write(stats, "")
    f:write("\n")
    f:close()
end

------------------------------------------------------------
-- Markdown rendering (tables only)
------------------------------------------------------------

local function fmtTime(s)
    if s < 1e-6     then return string.format("%.0f ns", s * 1e9)
    elseif s < 1e-3 then return string.format("%.2f µs", s * 1e6)
    elseif s < 1    then return string.format("%.2f ms", s * 1e3)
    else                 return string.format("%.2f s",  s) end
end

local function fmtBytes(b)
    if not b or b <= 0 then return "0 B"
    elseif b < 1024    then return string.format("%.0f B", b)
    elseif b < 1048576 then return string.format("%.2f KB", b / 1024)
    else                    return string.format("%.2f MB", b / 1048576) end
end

local function fmtRate(opsPerSec)
    if opsPerSec >= 1e9     then return string.format("%.2f G/s", opsPerSec / 1e9)
    elseif opsPerSec >= 1e6 then return string.format("%.2f M/s", opsPerSec / 1e6)
    elseif opsPerSec >= 1e3 then return string.format("%.2f K/s", opsPerSec / 1e3)
    else                         return string.format("%.0f /s", opsPerSec) end
end

local function fmtRel(rel)
    if rel >= 1.05     then return string.format("%.2f× slower", rel)
    elseif rel <= 0.95 then return string.format("%.2f× faster", 1 / rel)
    else                    return "tie" end
end

M.fmtTime  = fmtTime
M.fmtBytes = fmtBytes
M.fmtRate  = fmtRate
M.fmtRel   = fmtRel

---Render a single-runtime detailed report (one section per scenario).
---@param stats table
---@return string
function M.renderRuntime(stats)
    local lines = {}
    local function emit(s) lines[#lines + 1] = s or "" end

    emit("# matchigo-lua bench — `" .. stats.meta.label .. "`")
    emit()
    emit("**Runtime** : " .. stats.meta.runtime)
    emit("**Generated** : " .. stats.meta.generated)
    emit(string.format("**Config** : %d samples, %d warmup, %.0fms calibration target",
        stats.meta.samples, stats.meta.warmup, stats.meta.targetMs))
    emit()

    local isJit = stats.meta.label:match("^luajit") ~= nil

    emit("> [!IMPORTANT]")
    emit("> **Reading these numbers in context.** Microbenches measure the")
    emit("> *abstraction's* per-call overhead in tight loops with cycling")
    emit("> inputs — that's the point, not a flaw.")
    emit(">")
    emit("> In most production code, Lua compute runs in **nanoseconds**")
    emit("> while the work around it (a SQL query, an HTTP call, a file")
    emit("> read, a queue pop) runs in **milliseconds**. A `2× slower` row")
    emit("> here is ~50–200 ns extra per dispatch — orders of magnitude")
    emit("> below the noise floor of any external IO.")
    emit(">")
    emit("> **Where it does matter** : real-time framing contexts (game")
    emit("> engines like LÖVE/Defold, ~16 ms frame budget at 60 Hz),")
    emit("> high-frequency event loops (OpenResty under load), or any tight")
    emit("> inner loop with no IO. In those, **the alloc column matters")
    emit("> more than the ns column** — sustained per-call allocation")
    emit("> causes GC pauses that *will* eat your frame budget. Hot paths")
    emit("> with `alloc = 0 B` are GC-safe regardless of which dispatcher")
    emit("> you pick.")
    emit(">")
    emit("> Pick on readability + maintainability + your runtime's actual")
    emit("> allocation pressure. The bench tells you what dispatch costs ;")
    emit("> only your profiler tells you whether it matters for *your* app.")
    emit()
    emit("Each scenario cycles through varying inputs to defeat JIT constant")
    emit("folding ; the cycling cost is uniform across all benches in a")
    emit("scenario, so ratios stay accurate even on LuaJIT.")
    emit()

    for _, g in ipairs(stats.groups) do
        local isEducational = g.name:lower():find("educational", 1, true) ~= nil

        emit("## " .. g.name)
        emit()

        if isEducational then
            if isJit then
                emit("> [!TIP]")
                emit("> **Educational scenario — this is where LuaJIT shines.**")
                emit("> The dispatcher is called with a **constant** input every")
                emit("> iteration (no cycling), so the JIT can inline the body and")
                emit("> hoist the entire compute out of the loop (LICM). Both")
                emit("> contestants collapse to ~0 ns. **Lesson** : in a hot loop")
                emit("> with a constant input, LuaJIT erases dispatch overhead")
                emit("> entirely, regardless of which dispatcher you pick. Compare")
                emit("> against the cycled scenarios above to see the real cost")
                emit("> when the JIT cannot fold the input away.")
                emit()
            else
                emit("> [!NOTE]")
                emit("> **Educational scenario — the lesson lives on LuaJIT.**")
                emit("> This bench uses a **constant** input every iteration (no")
                emit("> cycling). On this non-JIT runtime, the row reads like any")
                emit("> other dispatch — the per-call cost. The interesting")
                emit("> contrast (LuaJIT folding both contestants to ~0 ns) lives")
                emit("> in [`runtime-luajit-2.1.md`](./runtime-luajit-2.1.md) and")
                emit("> the [matrix](./matrix.md). On Lua 5.x, this scenario is")
                emit("> just included for parity.")
                emit()
            end
        end

        emit("| benchmark | mean | alloc | gc | rate | min..max | p50/p99 | vs base |")
        emit("|---|---:|---:|---:|---:|---:|---:|---:|")
        local baseline = g.benches[1].avg
        for i, r in ipairs(g.benches) do
            local relStr
            if i == 1 then
                relStr = "_(base)_"
            else
                relStr = fmtRel(r.avg / baseline)
            end
            local safeName = r.name:gsub("|", "\\|")
            local gcStr    = string.format("%d/%d", r.gcOutliers or 0, r.samples or 0)
            emit(string.format("| `%s` | %s | %s | %s | %s | %s..%s | %s/%s | %s |",
                safeName, fmtTime(r.avg), fmtBytes(r.alloc), gcStr,
                fmtRate(1 / r.avg),
                fmtTime(r.min), fmtTime(r.max),
                fmtTime(r.p50), fmtTime(r.p99), relStr))
        end
        emit()
    end

    return table.concat(lines, "\n") .. "\n"
end

return M
