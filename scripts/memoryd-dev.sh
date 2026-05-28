#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

ROOT="${CLAUDE_STATS_MEMORY_ROOT:-$HOME/Library/Application Support/Claude Stats/Memory}"
HOST="${CLAUDE_STATS_MEMORYD_HOST:-127.0.0.1}"
PORT="${CLAUDE_STATS_MEMORYD_PORT:-8765}"

PYTHONPATH="$PWD/MemorySidecar${PYTHONPATH:+:$PYTHONPATH}" \
python3 -m memoryd serve --root "$ROOT" --host "$HOST" --port "$PORT"
