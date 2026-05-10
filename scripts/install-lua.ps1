#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Install Lua/LuaJIT runtimes for cross-runtime benchmarking.

.DESCRIPTION
    Uses hererocks (a Python tool, also used internally by leafo/gh-actions-lua)
    to build self-contained Lua/LuaJIT installs under ./.lua/. No system
    pollution: every runtime lives in its own isolated tree.

    Prerequisites:
      * Python 3 on PATH (winget install Python.Python.3, scoop install python,
        or python.org).
      * A C toolchain. MSVC (Visual Studio Build Tools) is the most reliable on
        Windows; MinGW-w64 / gcc on PATH also works for PUC Lua.

.PARAMETER Versions
    Lua versions to install. Defaults to 5.1, 5.2, 5.3, 5.4, luajit.
    Pass a subset to install only specific versions.

.PARAMETER Force
    Reinstall even if the destination directory already exists.

.EXAMPLE
    .\scripts\install-lua.ps1
    Installs all default runtimes.

.EXAMPLE
    .\scripts\install-lua.ps1 -Versions 5.4, luajit
    Installs only Lua 5.4 and LuaJIT 2.1.

.EXAMPLE
    .\scripts\install-lua.ps1 -Versions 5.4 -Force
    Reinstalls Lua 5.4 from scratch.
#>

param(
    [string[]]$Versions = @("5.1", "5.2", "5.3", "5.4", "luajit"),
    [switch]$Force
)

$ErrorActionPreference = "Stop"

function Test-Cmd([string]$Name) {
    $null -ne (Get-Command $Name -ErrorAction SilentlyContinue)
}

if (-not (Test-Cmd python) -and -not (Test-Cmd python3)) {
    Write-Error @"
Python not found on PATH.

Install Python 3 first, then re-run this script:
  winget install Python.Python.3
  scoop install python
  https://www.python.org/downloads/
"@
}

$Python = if (Test-Cmd python) { "python" } else { "python3" }

# Use `python -m hererocks` so the script works whether the pip install put
# `hererocks.exe` on PATH or not (depends on the user's pip config).
& $Python -c "import hererocks" 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Host "[install-lua] Installing hererocks via pip..."
    & $Python -m pip install --user hererocks
    if ($LASTEXITCODE -ne 0) {
        Write-Error "pip install hererocks failed. Try with elevated privileges or in a venv."
    }
}

$Root      = Split-Path -Parent $PSScriptRoot
$TargetDir = Join-Path $Root ".lua"
New-Item -ItemType Directory -Force -Path $TargetDir | Out-Null

foreach ($v in $Versions) {
    $Dest = Join-Path $TargetDir "lua-$v"
    if ((Test-Path $Dest) -and -not $Force) {
        Write-Host "[install-lua] $v already at $Dest (use -Force to reinstall)."
        continue
    }
    if (Test-Path $Dest) {
        Write-Host "[install-lua] Removing existing $Dest..."
        Remove-Item -Recurse -Force $Dest
    }

    Write-Host "[install-lua] Building $v -> $Dest"
    if ($v -eq "luajit") {
        & $Python -m hererocks $Dest --luajit 2.1 --no-readline --verbose
    } else {
        & $Python -m hererocks $Dest --lua $v --no-readline --verbose
    }
    if ($LASTEXITCODE -ne 0) {
        Write-Error "hererocks failed for $v. Check that a C toolchain is on PATH."
    }
}

Write-Host ""
Write-Host "[install-lua] Done. Installed under $TargetDir :"
Get-ChildItem $TargetDir -Directory -ErrorAction SilentlyContinue | ForEach-Object {
    $bin = Join-Path $_.FullName "bin"
    Write-Host ("  {0}  ->  {1}" -f $_.Name, $bin)
}

Write-Host ""
Write-Host "Run a bench against a specific runtime:"
Write-Host "  .\.lua\lua-5.4\bin\lua.exe bench\run.lua            # full"
Write-Host "  .\.lua\lua-5.4\bin\lua.exe bench\run.lua --fast     # smoke (~30s)"
Write-Host ""
Write-Host "Aggregate the cross-runtime matrix from existing stats (no rebench):"
Write-Host "  lua bench\matrix.lua"
Write-Host ""
Write-Host "Or rebench everything detected and aggregate:"
Write-Host "  lua bench\matrix.lua --all"
