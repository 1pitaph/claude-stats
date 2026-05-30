#!/usr/bin/env bash
# Prepare the experimental Warp embedding checkout.
set -euo pipefail
cd "$(dirname "$0")/.."

WARP_DIR="${WARP_DIR:-$PWD/ThirdParty/Warp}"

if [[ ! -d "$WARP_DIR" ]]; then
    echo "error: Warp submodule is missing at $WARP_DIR" >&2
    echo "hint: git submodule update --init --recursive ThirdParty/Warp" >&2
    exit 1
fi

if [[ ! -f "$WARP_DIR/Cargo.toml" ]]; then
    echo "error: Warp checkout at $WARP_DIR does not look like a Cargo workspace" >&2
    exit 1
fi

echo "==> Warp checkout ready: $WARP_DIR"
echo "==> In-process bridge build is not wired yet; WarpEmbed will report bridge pending."
