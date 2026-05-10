#!/usr/bin/env bash
# Install Lua/LuaJIT runtimes for cross-runtime benchmarking.
#
# Uses hererocks (a Python tool, also used internally by leafo/gh-actions-lua)
# to build self-contained Lua/LuaJIT installs under ./.lua/. No system
# pollution : every runtime lives in its own isolated tree.
#
# Prerequisites :
#   - Python 3 on PATH        (apt install python3 / brew install python)
#   - A C toolchain (gcc, clang) - usually default on Linux/macOS
#
# Usage :
#   ./scripts/install-lua.sh                       # install all defaults
#   ./scripts/install-lua.sh 5.4 luajit            # install a subset
#   FORCE=1 ./scripts/install-lua.sh 5.4           # reinstall

set -euo pipefail

DEFAULT_VERSIONS=("5.1" "5.2" "5.3" "5.4" "luajit")
if [ "$#" -eq 0 ]; then
    VERSIONS=("${DEFAULT_VERSIONS[@]}")
else
    VERSIONS=("$@")
fi
FORCE="${FORCE:-0}"

# Locate Python 3.
if command -v python3 >/dev/null 2>&1; then
    PYTHON=$(command -v python3)
elif command -v python >/dev/null 2>&1; then
    PYTHON=$(command -v python)
else
    cat <<EOF >&2
Python not found on PATH.

Install Python 3 first, then re-run this script :
  apt install python3 python3-pip       # Debian/Ubuntu
  brew install python                    # macOS
  pacman -S python python-pip            # Arch
EOF
    exit 1
fi

# Ensure hererocks is importable. Use `python -m hererocks` so we don't
# depend on the `hererocks` shim being on PATH (varies by pip config).
if ! "$PYTHON" -c "import hererocks" >/dev/null 2>&1; then
    echo "[install-lua] Installing hererocks via pip..."
    "$PYTHON" -m pip install --user hererocks
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET="$ROOT/.lua"
mkdir -p "$TARGET"

for v in "${VERSIONS[@]}"; do
    DEST="$TARGET/lua-$v"
    if [ -d "$DEST" ] && [ "$FORCE" != "1" ]; then
        echo "[install-lua] $v already at $DEST (set FORCE=1 to reinstall)."
        continue
    fi
    if [ -d "$DEST" ]; then
        echo "[install-lua] Removing existing $DEST..."
        rm -rf "$DEST"
    fi

    echo "[install-lua] Building $v -> $DEST"
    if [ "$v" = "luajit" ]; then
        "$PYTHON" -m hererocks "$DEST" --luajit 2.1 --no-readline --verbose
    else
        "$PYTHON" -m hererocks "$DEST" --lua "$v" --no-readline --verbose
    fi
done

echo
echo "[install-lua] Done. Installed under $TARGET :"
for d in "$TARGET"/lua-*; do
    [ -d "$d" ] || continue
    echo "  $(basename "$d")  ->  $d/bin"
done

cat <<EOF

Run a bench against a specific runtime :
  ./.lua/lua-5.4/bin/lua bench/run.lua            # full
  ./.lua/lua-5.4/bin/lua bench/run.lua --fast     # smoke (~30s)

Aggregate the cross-runtime matrix from existing stats (no rebench) :
  lua bench/matrix.lua

Or rebench everything detected and aggregate :
  lua bench/matrix.lua --all
EOF
