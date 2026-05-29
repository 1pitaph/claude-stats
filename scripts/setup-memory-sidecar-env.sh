#!/usr/bin/env bash
# Create the Python environment used by the Code Memory sidecar adapters.
set -euo pipefail
cd "$(dirname "$0")/.."

PYTHON="${PYTHON:-}"
if [[ -z "$PYTHON" ]]; then
    if [[ -x /opt/homebrew/bin/python3 ]]; then
        PYTHON=/opt/homebrew/bin/python3
    else
        PYTHON="$(command -v python3)"
    fi
fi

"$PYTHON" - <<'PY'
import sys
if sys.version_info < (3, 10):
    raise SystemExit(f"Python >= 3.10 is required for mem0/Graphiti, got {sys.version.split()[0]}")
PY

MEMORY_ROOT="${CLAUDE_STATS_MEMORY_ROOT:-$HOME/Library/Application Support/Claude Stats/Memory}"
VENV="${CLAUDE_STATS_MEMORYD_VENV:-$MEMORY_ROOT/.venv}"

mkdir -p "$MEMORY_ROOT"
"$PYTHON" -m venv "$VENV"
"$VENV/bin/python" -m pip install --upgrade pip setuptools wheel
"$VENV/bin/python" -m pip install -r MemorySidecar/requirements.lock

if [[ -f ThirdParty/mem0/pyproject.toml ]]; then
    "$VENV/bin/python" -m pip install --no-deps -e ThirdParty/mem0
fi
if [[ -f ThirdParty/graphiti/pyproject.toml ]]; then
    "$VENV/bin/python" -m pip install --no-deps -e 'ThirdParty/graphiti[kuzu]'
fi

"$VENV/bin/python" - <<'PY'
from mem0 import Memory
from graphiti_core import Graphiti
print("memory adapters ready: mem0 + graphiti import successfully")
PY

echo "Memory sidecar Python: $VENV/bin/python"
