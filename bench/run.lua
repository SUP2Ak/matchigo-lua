-- Single-runtime bench entry point.
--
-- Runs every registered scenario against the current Lua interpreter,
-- writes a per-runtime detailed markdown table and a stats sidecar that
-- bench/matrix.lua consumes for the cross-runtime aggregator.
--
-- Run from project root :
--   lua bench/run.lua             -- full bench, ~3 min
--   lua bench/run.lua --fast      -- smoke config (samples=5), ~30 sec

package.path = "./?.lua;./?/init.lua;" .. package.path

local FAST = false
for _, a in ipairs(arg or {}) do
    if a == "--fast" then FAST = true end
end

local b = require("bench.framework")
if FAST then
    b.setDefaults({ samples = 5, warmup = 20, targetMs = 50 })
end

local m = dofile("dist/matchigo.lua")

-- Register every scenario.
local registerScenarios = assert(loadfile("bench/scenarios.lua"))()
registerScenarios(m, b)

-- Cross-platform `mkdir -p` ; mirrors the helper in build.lua.
local function ensureDir(path)
    local sep = package.config:sub(1, 1)
    if sep == "\\" then
        local winPath = path:gsub("/", "\\")
        os.execute(string.format([[if not exist "%s" mkdir "%s"]], winPath, winPath))
    else
        os.execute(string.format([[mkdir -p "%s"]], path))
    end
end

local stats = b.runAll()

local label      = b.runtimeLabel()
local resultsDir = "bench/results"
local statsDir   = resultsDir .. "/.stats"

ensureDir(resultsDir)
ensureDir(statsDir)

local mdPath    = string.format("%s/runtime-%s.md", resultsDir, label)
local statsPath = string.format("%s/%s.lua", statsDir, label)

local f = assert(io.open(mdPath, "wb"), "Cannot write " .. mdPath)
f:write(b.renderRuntime(stats))
f:close()
print()
print("Wrote " .. mdPath)

b.writeStats(stats, statsPath)
print("Wrote " .. statsPath)
