-- Cross-runtime bench matrix aggregator.
--
-- Reads `bench/results/.stats/*.lua` snapshots (produced by bench/run.lua
-- under each runtime) and produces a single matrix report at
-- `bench/results/matrix.md`. By default it does NOT re-run anything —
-- you bench whichever runtimes you want via bench/run.lua, then assemble
-- the matrix from the latest stats. Updating one runtime is just :
--
--   <lua-5.4-binary> bench/run.lua
--   lua bench/matrix.lua
--
-- Usage :
--   lua bench/matrix.lua                       # render from existing stats
--   lua bench/matrix.lua --all                 # rebench every detected runtime, then render
--   lua bench/matrix.lua --all --fast          # rebench all in smoke mode
--   lua bench/matrix.lua 5.4=path/to/lua       # rebench just this runtime, then render
--   lua bench/matrix.lua 5.4=...  --fast       # rebench specific runtime in smoke mode

local SEP = package.config:sub(1, 1)
local IS_WIN = SEP == "\\"
local EXE = IS_WIN and ".exe" or ""

local STATS_DIR   = "bench/results/.stats"
local RESULTS_DIR = "bench/results"

------------------------------------------------------------
-- Filesystem helpers
------------------------------------------------------------

local function fileExists(path)
    local f = io.open(path, "rb")
    if f then f:close(); return true end
    return false
end

local function writeFile(path, content)
    local f = assert(io.open(path, "wb"), "Cannot write " .. path)
    f:write(content)
    f:close()
end

local function ensureDir(path)
    if IS_WIN then
        local winPath = path:gsub("/", "\\")
        os.execute(string.format([[if not exist "%s" mkdir "%s"]], winPath, winPath))
    else
        os.execute(string.format([[mkdir -p "%s"]], path))
    end
end

local function execOk(rc)
    return rc == true or rc == 0
end

------------------------------------------------------------
-- Listing and loading existing stats files
------------------------------------------------------------

local function listStatsFiles()
    -- Discover bench/results/.stats/*.lua via a popen'd directory listing.
    local found = {}
    local cmd
    if IS_WIN then
        cmd = string.format('dir /b "%s\\*.lua" 2>nul', STATS_DIR:gsub("/", "\\"))
    else
        cmd = string.format("ls -1 %s/*.lua 2>/dev/null", STATS_DIR)
    end
    local pipe = io.popen(cmd, "r")
    if not pipe then return found end
    for line in pipe:lines() do
        local fname = line:match("([^\\/]+)%.lua$")
        if fname then
            local path = STATS_DIR .. "/" .. fname .. ".lua"
            if fileExists(path) then
                found[#found + 1] = { label = fname, path = path }
            end
        end
    end
    pipe:close()
    return found
end

local function loadStats(path)
    local ok, stats = pcall(dofile, path)
    if not ok or type(stats) ~= "table" then return nil end
    return stats
end

------------------------------------------------------------
-- Runtime detection (only used by --all rebench mode)
------------------------------------------------------------

local function resolveOnPath(name)
    local cmd = IS_WIN and ("where " .. name .. " 2>nul")
                       or  ("command -v " .. name .. " 2>/dev/null")
    local pipe = io.popen(cmd, "r")
    if not pipe then return nil end
    local out = pipe:read("*a") or ""
    pipe:close()
    local first = out:match("([^\r\n]+)")
    if first and first ~= "" then return first end
    return nil
end

local function probeVersion(binPath)
    local pipe = io.popen(string.format('"%s" -v 2>&1', binPath), "r")
    if not pipe then return nil end
    local out = pipe:read("*a") or ""
    pipe:close()
    local jit = out:match("LuaJIT%s+([%d%.]+)")
    if jit then return "luajit-" .. (jit:match("^(%d+%.%d+)") or jit) end
    local lua = out:match("Lua%s+(%d+%.%d+)")
    if lua then return lua end
    return nil
end

local function detectRuntimes()
    local found = {}

    local hereCandidates = {
        ".lua/lua-5.1/bin/lua"       .. EXE,
        ".lua/lua-5.2/bin/lua"       .. EXE,
        ".lua/lua-5.3/bin/lua"       .. EXE,
        ".lua/lua-5.4/bin/lua"       .. EXE,
        ".lua/lua-5.5/bin/lua"       .. EXE,
        ".lua/lua-luajit/bin/luajit" .. EXE,
    }
    for _, candidate in ipairs(hereCandidates) do
        local p = candidate:gsub("/", SEP)
        if fileExists(p) then
            local label = probeVersion(p)
            if label then found[#found + 1] = { label = label, path = p } end
        end
    end

    if #found == 0 then
        local probeNames = { "lua", "luajit", "lua5.1", "lua5.2", "lua5.3", "lua5.4", "lua5.5" }
        local seenPath = {}
        for _, name in ipairs(probeNames) do
            local path = resolveOnPath(name)
            if path and not seenPath[path] then
                seenPath[path] = true
                local label = probeVersion(path)
                if label then found[#found + 1] = { label = label, path = path } end
            end
        end
    end
    return found
end

------------------------------------------------------------
-- Rebench helper : spawn a runtime, run bench/run.lua against it
------------------------------------------------------------

local function rebench(runtime, fast)
    local extra  = fast and " --fast" or ""
    local logPath = string.format("%s/.rebench-%s.log", STATS_DIR, runtime.label)
    ensureDir(STATS_DIR)
    local cmd
    if IS_WIN then
        cmd = string.format('"%s" bench\\run.lua%s >%s 2>&1',
            runtime.path, extra, logPath)
    else
        cmd = string.format('"%s" bench/run.lua%s >"%s" 2>&1',
            runtime.path, extra, logPath)
    end
    print(string.format("[matrix] Rebenching %s%s ...", runtime.label, extra))
    local rc = os.execute(cmd)
    if not execOk(rc) then
        print(string.format("[matrix]   FAILED for %s (see %s)", runtime.label, logPath))
        return false
    end
    print(string.format("[matrix]   ok"))
    return true
end

------------------------------------------------------------
-- Format helpers (mirror framework.lua so output stays consistent)
------------------------------------------------------------

local function fmtTime(s)
    if s < 1e-6     then return string.format("%.0f ns", s * 1e9)
    elseif s < 1e-3 then return string.format("%.2f µs", s * 1e6)
    elseif s < 1    then return string.format("%.2f ms", s * 1e3)
    else                 return string.format("%.2f s",  s) end
end

local function fmtBytes(bytes)
    if not bytes or bytes <= 0 then return "0 B"
    elseif bytes < 1024        then return string.format("%.0f B", bytes)
    elseif bytes < 1048576     then return string.format("%.2f KB", bytes / 1024)
    else                            return string.format("%.2f MB", bytes / 1048576) end
end

local function fmtRel(rel)
    if rel >= 1.05     then return string.format("%.2f× slower", rel)
    elseif rel <= 0.95 then return string.format("%.2f× faster", 1 / rel)
    else                    return "tie" end
end

local function median(arr)
    if #arr == 0 then return nil end
    local sorted = {}
    for i = 1, #arr do sorted[i] = arr[i] end
    table.sort(sorted)
    local n = #sorted
    if n % 2 == 0 then
        local half = math.floor(n / 2)
        return (sorted[half] + sorted[half + 1]) / 2
    end
    return sorted[math.floor((n + 1) / 2)]
end

local function classifyBench(name)
    local low = name:lower()
    if low:find("native", 1, true) then return "native" end
    if low:find("compile", 1, true) then return "compile" end
    if low:find("matcher", 1, true) then return "matcher" end
    return "other"
end

------------------------------------------------------------
-- Render
------------------------------------------------------------

local function sortKeyForLabel(label)
    if label:match("^luajit") then return 99 end
    local maj, min = label:match("^(%d+)%.(%d+)")
    if maj and min then return tonumber(maj) * 10 + tonumber(min) end
    return 999
end

local function renderMatrix(runtimeStats)
    table.sort(runtimeStats, function(a, b)
        return sortKeyForLabel(a.label) < sortKeyForLabel(b.label)
    end)

    local lines = {}
    local function emit(s) lines[#lines + 1] = s or "" end

    emit("# matchigo-lua bench matrix")
    emit()
    emit("Generated by `bench/matrix.lua` from per-runtime stats sidecars under")
    emit("`bench/results/.stats/`. Each runtime is rebuilt independently — to")
    emit("update one column, just rerun `bench/run.lua` under that interpreter")
    emit("and re-run `lua bench/matrix.lua`.")
    emit()
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
    emit("> [!NOTE]")
    emit("> **Reading LuaJIT cells** : ratios near 1.0× and small absolute ns")
    emit("> values are not measurement failures. Cycling inputs defeat constant")
    emit("> folding, but the JIT can still inline both contestants down to")
    emit("> nearly identical machine code on pure dispatches. Under JIT,")
    emit("> **allocation is the one cost the optimizer cannot make disappear**")
    emit("> — that's the column to watch.")
    emit()

    -- ── Runtimes section ─────────────────────────────────────────────
    emit("## Runtimes")
    emit()
    emit("| label | description | generated |")
    emit("|---|---|---|")
    for _, r in ipairs(runtimeStats) do
        emit(string.format("| `%s` | %s | %s |",
            r.label, r.stats.meta.runtime, r.stats.meta.generated))
    end
    emit()

    -- ── Summary table ────────────────────────────────────────────────
    emit("## Summary")
    emit()
    emit("Median ratios across **real-world** scenarios per runtime")
    emit("(scenarios named `educational` are excluded from the medians).")
    emit("`compile()` = `m.compile(rules)` data-driven dispatch.")
    emit("`matcher+DSL` = `m.matcher():with(...)` chained API with the")
    emit("Rust-style DSL. The **alloc-neutral** columns count scenarios")
    emit("where matchigo's hot path allocates the same bytes/call as")
    emit("native (within 8 B noise) — i.e., matchigo adds no allocation")
    emit("pressure that wasn't already there in the equivalent hand-written")
    emit("code.")
    emit()
    emit("| runtime | scenarios | `compile()` median | `compile()` alloc-neutral | `matcher+DSL` median | `matcher+DSL` alloc-neutral |")
    emit("|---|---:|---:|---:|---:|---:|")
    for _, r in ipairs(runtimeStats) do
        local compileRatios, matcherRatios = {}, {}
        local compileAllocNeutral, compileTotal = 0, 0
        local matcherAllocNeutral, matcherTotal = 0, 0
        local realScenarios = 0
        for _, g in ipairs(r.stats.groups) do
            if g.name:lower():find("educational", 1, true) then
                -- skip — pedagogical scenarios shouldn't skew the medians
            else
                realScenarios = realScenarios + 1
                local nativeBench, compileBench, matcherBench
                for _, bench in ipairs(g.benches) do
                    local kind = classifyBench(bench.name)
                    if     kind == "native"  then nativeBench  = bench
                    elseif kind == "compile" then compileBench = bench
                    elseif kind == "matcher" then matcherBench = bench
                    end
                end
                if nativeBench and nativeBench.avg > 0 then
                    local nativeAlloc = nativeBench.alloc or 0
                    if compileBench then
                        compileRatios[#compileRatios + 1] = compileBench.avg / nativeBench.avg
                        compileTotal = compileTotal + 1
                        if (compileBench.alloc or 0) <= nativeAlloc + 8 then
                            compileAllocNeutral = compileAllocNeutral + 1
                        end
                    end
                    if matcherBench then
                        matcherRatios[#matcherRatios + 1] = matcherBench.avg / nativeBench.avg
                        matcherTotal = matcherTotal + 1
                        if (matcherBench.alloc or 0) <= nativeAlloc + 8 then
                            matcherAllocNeutral = matcherAllocNeutral + 1
                        end
                    end
                end
            end
        end
        local compileMed = median(compileRatios)
        local matcherMed = median(matcherRatios)
        local matcherCells = matcherTotal > 0
            and { fmtRel(matcherMed), string.format("%d/%d", matcherAllocNeutral, matcherTotal) }
            or  { "—", "—" }
        emit(string.format("| `%s` | %d | %s | %d/%d | %s | %s |",
            r.label, realScenarios,
            compileMed and fmtRel(compileMed) or "—",
            compileAllocNeutral, compileTotal,
            matcherCells[1], matcherCells[2]))
    end
    emit()

    -- ── Per-scenario matrix ──────────────────────────────────────────
    emit("## Per-scenario matrix")
    emit()
    emit("Each cell : `mean · alloc · ratio_vs_native`. The ratio is")
    emit("computed within the runtime, so cross-runtime cell comparisons")
    emit("show absolute ns differences while same-row comparisons show")
    emit("how matchigo's overhead changes per VM.")
    emit()

    local canonGroups = runtimeStats[1].stats.groups
    for _, g in ipairs(canonGroups) do
        local isEducational = g.name:lower():find("educational", 1, true) ~= nil

        emit("### " .. g.name)
        emit()

        if isEducational then
            emit("> [!TIP]")
            emit("> **Educational — read the LuaJIT column carefully.** This bench")
            emit("> deliberately uses a **constant** input every iteration (no")
            emit("> cycling). On standard Lua you'll see the real per-call cost ;")
            emit("> on LuaJIT both contestants collapse to ~0 ns because the JIT")
            emit("> inlines the body and hoists the compute out of the loop")
            emit("> (LICM). The lesson : **in a hot loop with a constant input,")
            emit("> LuaJIT erases dispatch overhead entirely**, regardless of which")
            emit("> dispatcher you pick. Compare against the cycled scenarios above")
            emit("> for the actual dispatch cost when the JIT cannot fold.")
            emit()
        end

        local headerCells = { "benchmark" }
        for _, r in ipairs(runtimeStats) do
            headerCells[#headerCells + 1] = "`" .. r.label .. "`"
        end
        emit("| " .. table.concat(headerCells, " | ") .. " |")

        local sepCells = { "---" }
        for _ = 1, #runtimeStats do sepCells[#sepCells + 1] = "---:" end
        emit("| " .. table.concat(sepCells, " | ") .. " |")

        for i, b in ipairs(g.benches) do
            local row = { "`" .. b.name:gsub("|", "\\|") .. "`" }
            for _, r in ipairs(runtimeStats) do
                local rGroup
                for _, gg in ipairs(r.stats.groups) do
                    if gg.name == g.name then rGroup = gg; break end
                end
                local cell = "—"
                if rGroup and rGroup.benches[i] then
                    local found = rGroup.benches[i]
                    if i == 1 then
                        cell = string.format("%s · %s · _(base)_",
                            fmtTime(found.avg), fmtBytes(found.alloc))
                    else
                        local baseline = rGroup.benches[1].avg
                        cell = string.format("%s · %s · %s",
                            fmtTime(found.avg),
                            fmtBytes(found.alloc),
                            fmtRel(found.avg / baseline))
                    end
                end
                row[#row + 1] = cell
            end
            emit("| " .. table.concat(row, " | ") .. " |")
        end
        emit()
    end

    emit("---")
    emit()
    emit("Re-render this matrix at any time with `lua bench/matrix.lua`")
    emit("(no rebenching). To refresh a single runtime, run `bench/run.lua`")
    emit("under that interpreter and re-render.")

    return table.concat(lines, "\n") .. "\n"
end

------------------------------------------------------------
-- Main : parse argv, optionally rebench, then render
------------------------------------------------------------

local FAST = false
local REBENCH_ALL = false
local explicitRebench = {}  -- array of { label, path }

for _, a in ipairs(arg or {}) do
    if a == "--fast" then
        FAST = true
    elseif a == "--all" then
        REBENCH_ALL = true
    else
        local label, path = a:match("^([^=]+)=(.+)$")
        if label and path and fileExists(path) then
            explicitRebench[#explicitRebench + 1] = { label = label, path = path }
        else
            print("[matrix] Ignoring arg (expected --fast / --all / label=path) : " .. a)
        end
    end
end

if REBENCH_ALL then
    local detected = detectRuntimes()
    if #detected == 0 then
        print("[matrix] --all : no runtimes detected.")
        os.exit(1)
    end
    for _, rt in ipairs(detected) do rebench(rt, FAST) end
end

for _, rt in ipairs(explicitRebench) do rebench(rt, FAST) end

local statsFiles = listStatsFiles()
if #statsFiles == 0 then
    print("[matrix] No stats found under " .. STATS_DIR .. ".")
    print("[matrix] Run `lua bench/run.lua` under at least one interpreter,")
    print("[matrix] or pass --all to rebench every detected runtime.")
    os.exit(1)
end

local runtimeStats = {}
for _, sf in ipairs(statsFiles) do
    local stats = loadStats(sf.path)
    if stats and stats.groups and stats.meta then
        runtimeStats[#runtimeStats + 1] = { label = sf.label, stats = stats }
    else
        print("[matrix] Skipping malformed stats file : " .. sf.path)
    end
end

if #runtimeStats == 0 then
    print("[matrix] No usable stats. Aborting.")
    os.exit(1)
end

ensureDir(RESULTS_DIR)

-- Re-render every runtime-<label>.md from the loaded stats. Idempotent and
-- cheap : avoids rebenching just to refresh a renderer change. Loads the
-- framework lazily because the framework reads env vars at top-level.
package.path = "./?.lua;./?/init.lua;" .. package.path
local framework = require("bench.framework")
for _, r in ipairs(runtimeStats) do
    local mdPath = string.format("%s/runtime-%s.md", RESULTS_DIR, r.label)
    writeFile(mdPath, framework.renderRuntime(r.stats))
    print("[matrix] Re-rendered " .. mdPath)
end

local matrixPath = RESULTS_DIR .. "/matrix.md"
writeFile(matrixPath, renderMatrix(runtimeStats))

print()
print(string.format("[matrix] Aggregated %d runtime(s) into %s",
    #runtimeStats, matrixPath))
