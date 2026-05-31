#!/usr/bin/env bash
# Run the unit-test bundle against a dedicated DerivedData path.
set -euo pipefail
cd "$(dirname "$0")/.."

DERIVED=/tmp/Codex-stats-build-tests
TEST_APP="$DERIVED/Build/Products/Debug/Claude Stats.app"
APP_PROCESS_PATTERN="Claude Stats.app/Contents/MacOS/Claude Stats"
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

require_apple_silicon() {
    if [[ "$(uname -m)" != "arm64" ]]; then
        echo "error: Claude Stats now supports Apple Silicon Macs only." >&2
        exit 1
    fi
}

running_app_pids() {
    pgrep -f "$APP_PROCESS_PATTERN" 2>/dev/null || true
}

wait_until_stopped() {
    local attempts="$1"
    local pids
    for ((i = 0; i < attempts; i++)); do
        pids="$(running_app_pids)"
        if [[ -z "$pids" ]]; then
            return 0
        fi
        sleep 0.15
    done
    return 1
}

stop_running_app() {
    local pids
    pids="$(running_app_pids)"
    if [[ -z "$pids" ]]; then
        return 0
    fi

    echo "==> Stopping existing Claude Stats process(es): $(echo "$pids" | tr '\n' ' ')"
    kill -TERM $pids 2>/dev/null || true
    if wait_until_stopped 30; then
        return 0
    fi

    pids="$(running_app_pids)"
    echo "==> Existing process ignored SIGTERM; forcing: $(echo "$pids" | tr '\n' ' ')"
    kill -KILL $pids 2>/dev/null || true
    wait_until_stopped 30 || true
}

cleanup_test_bundle_registration() {
    if [[ -d "$TEST_APP" ]]; then
        "$LSREGISTER" -u "$TEST_APP" 2>/dev/null || true
    fi
    if [[ -d "/tmp/claude-stats-build/Build/Products/Debug/Claude Stats.app" ]]; then
        "$LSREGISTER" -u "/tmp/claude-stats-build/Build/Products/Debug/Claude Stats.app" 2>/dev/null || true
    fi
}

cleanup_after_tests() {
    stop_running_app
    cleanup_test_bundle_registration
}

trap cleanup_after_tests EXIT

require_apple_silicon
python3 -B -m unittest discover scripts/tests

bash scripts/build-warp-embed.sh
bash scripts/build-linguist-runtime.sh
bash scripts/build-llama-runtime.sh
bash scripts/generate.sh

stop_running_app
cleanup_test_bundle_registration

xcodebuild \
    -project ClaudeStats.xcodeproj \
    -scheme ClaudeStats \
    -configuration Debug \
    -derivedDataPath "$DERIVED" \
    -destination 'platform=macOS' \
    ARCHS=arm64 \
    test

bash scripts/thin-arm64-bundle.sh "$TEST_APP"
bash scripts/verify-arm64-bundle.sh "$TEST_APP"
