#!/usr/bin/env bash
# Build a Debug Claude Stats Lite app to its canonical DerivedData path and launch it.
#
# Keep this separate from run-debug.sh so the Lite bundle id, scheme, and
# DerivedData path stay isolated from the full menu-bar app during development.
set -euo pipefail
cd "$(dirname "$0")/.."

DERIVED=/tmp/Codex-stats-lite-build
APP="$DERIVED/Build/Products/Debug/Claude Stats Lite.app"
APP_PROCESS_PATTERN="Claude Stats Lite.app/Contents/MacOS/Claude Stats Lite"
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

require_apple_silicon() {
    if [[ "$(uname -m)" != "arm64" ]]; then
        echo "error: Claude Stats Lite supports Apple Silicon Macs only." >&2
        exit 1
    fi
}

running_app_pids() {
    pgrep -f "$APP_PROCESS_PATTERN" 2>/dev/null || true
}

wait_until_stopped() {
    local pids
    local attempts="$1"
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

    echo "==> Stopping existing Claude Stats Lite process(es): $(echo "$pids" | tr '\n' ' ')"
    kill -TERM $pids 2>/dev/null || true
    if wait_until_stopped 30; then
        return 0
    fi

    pids="$(running_app_pids)"
    echo "==> Existing Lite process ignored SIGTERM; forcing: $(echo "$pids" | tr '\n' ' ')"
    kill -KILL $pids 2>/dev/null || true
    if wait_until_stopped 30; then
        return 0
    fi

    pids="$(running_app_pids)"
    echo "error: unable to stop existing Claude Stats Lite process(es): $(echo "$pids" | tr '\n' ' ')" >&2
    return 1
}

unregister_bundle_if_present() {
    local bundle="$1"
    if [[ -d "$bundle" ]]; then
        echo "==> Unregistering stale Claude Stats Lite bundle: $bundle"
        "$LSREGISTER" -u "$bundle" 2>/dev/null || true
    fi
}

cleanup_stale_registrations() {
    unregister_bundle_if_present "/Applications/Claude Stats Lite.app"
    unregister_bundle_if_present "/tmp/Codex-stats-lite-build-tests/Build/Products/Debug/Claude Stats Lite.app"
}

require_apple_silicon
bash scripts/build-linguist-runtime.sh
bash scripts/generate.sh

stop_running_app
cleanup_stale_registrations

xcodebuild \
    -project ClaudeStats.xcodeproj \
    -scheme "ClaudeStats Lite" \
    -configuration Debug \
    -derivedDataPath "$DERIVED" \
    ARCHS=arm64 \
    build

ENTITLEMENTS="$(mktemp "${TMPDIR:-/tmp}/claude-stats-lite-entitlements.XXXXXX")"
if ! codesign -d --entitlements :- "$APP" > "$ENTITLEMENTS" 2>/dev/null; then
    rm -f "$ENTITLEMENTS"
    ENTITLEMENTS=""
fi
bash scripts/thin-arm64-bundle.sh "$APP"
bash scripts/codesign-ad-hoc-bundle.sh "$APP" "$ENTITLEMENTS"
[[ -n "$ENTITLEMENTS" ]] && rm -f "$ENTITLEMENTS"
bash scripts/verify-arm64-bundle.sh "$APP"

"$LSREGISTER" -f "$APP" 2>/dev/null || true

open "$APP"
for ((i = 0; i < 20; i++)); do
    if [[ -n "$(running_app_pids)" ]]; then
        break
    fi
    sleep 0.25
done

if [[ -z "$(running_app_pids)" ]]; then
    echo "error: launch did not produce a Claude Stats Lite process" >&2
    exit 1
fi

for ((i = 0; i < 24; i++)); do
    sleep 0.25
    if [[ -z "$(running_app_pids)" ]]; then
        echo "error: Claude Stats Lite process exited during startup verification" >&2
        exit 1
    fi
done

echo "Launched $APP"
