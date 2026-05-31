#!/usr/bin/env bash
# Build a Debug ClaudeStats.app to the canonical DerivedData path and launch it.
#
# Why not `open -a Claude\ Stats` or the default DerivedData path: this is a
# menu-bar (LSUIElement) app. Multiple registered .app bundles with the same
# bundle id cause Launch Services conflicts and the menu-bar item silently fails
# to appear. Always build to /tmp/Codex-stats-build and launch by full path so
# there is exactly one known bundle.
set -euo pipefail
cd "$(dirname "$0")/.."

DERIVED=/tmp/Codex-stats-build
APP="$DERIVED/Build/Products/Debug/Claude Stats.app"
APP_PROCESS_PATTERN="Claude Stats.app/Contents/MacOS/Claude Stats"
LOCAL_AI_HELPER_PATTERN="Claude Stats.app/Contents/Helpers/claude-stats-local-ai"
MEMORY_SIDECAR_PATTERN="memoryd serve --root .*/Claude Stats/Memory --host 127.0.0.1 --port 8765"
MEDIAREMOTE_HELPER_PATTERN="Codex-stats-build/Build/Products/Debug/Claude Stats.app/Contents/Resources/mediaremote-adapter.pl"
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

running_mediaremote_helper_pids() {
    pgrep -f "$MEDIAREMOTE_HELPER_PATTERN" 2>/dev/null || true
}

running_local_ai_helper_pids() {
    pgrep -f "$LOCAL_AI_HELPER_PATTERN" 2>/dev/null || true
}

running_memory_sidecar_pids() {
    pgrep -f "$MEMORY_SIDECAR_PATTERN" 2>/dev/null || true
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

wait_until_mediaremote_helpers_stopped() {
    local pids
    local attempts="$1"
    for ((i = 0; i < attempts; i++)); do
        pids="$(running_mediaremote_helper_pids)"
        if [[ -z "$pids" ]]; then
            return 0
        fi
        sleep 0.15
    done
    return 1
}

wait_until_local_ai_helpers_stopped() {
    local pids
    local attempts="$1"
    for ((i = 0; i < attempts; i++)); do
        pids="$(running_local_ai_helper_pids)"
        if [[ -z "$pids" ]]; then
            return 0
        fi
        sleep 0.15
    done
    return 1
}

wait_until_memory_sidecars_stopped() {
    local pids
    local attempts="$1"
    for ((i = 0; i < attempts; i++)); do
        pids="$(running_memory_sidecar_pids)"
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
    if wait_until_stopped 30; then
        return 0
    fi

    pids="$(running_app_pids)"
    echo "error: unable to stop existing Claude Stats process(es): $(echo "$pids" | tr '\n' ' ')" >&2
    return 1
}

stop_running_memory_sidecars() {
    local pids
    pids="$(running_memory_sidecar_pids)"
    if [[ -z "$pids" ]]; then
        return 0
    fi

    echo "==> Stopping stale Code Memory sidecar process(es): $(echo "$pids" | tr '\n' ' ')"
    kill -TERM $pids 2>/dev/null || true
    if wait_until_memory_sidecars_stopped 30; then
        return 0
    fi

    pids="$(running_memory_sidecar_pids)"
    echo "==> Stale Code Memory sidecar ignored SIGTERM; forcing: $(echo "$pids" | tr '\n' ' ')"
    kill -KILL $pids 2>/dev/null || true
    if wait_until_memory_sidecars_stopped 30; then
        return 0
    fi

    pids="$(running_memory_sidecar_pids)"
    echo "error: unable to stop stale Code Memory sidecar process(es): $(echo "$pids" | tr '\n' ' ')" >&2
    return 1
}

stop_running_mediaremote_helpers() {
    local pids
    pids="$(running_mediaremote_helper_pids)"
    if [[ -z "$pids" ]]; then
        return 0
    fi

    echo "==> Stopping stale MediaRemote helper process(es): $(echo "$pids" | tr '\n' ' ')"
    kill -TERM $pids 2>/dev/null || true
    if wait_until_mediaremote_helpers_stopped 30; then
        return 0
    fi

    pids="$(running_mediaremote_helper_pids)"
    echo "==> Stale MediaRemote helper ignored SIGTERM; forcing: $(echo "$pids" | tr '\n' ' ')"
    kill -KILL $pids 2>/dev/null || true
    if wait_until_mediaremote_helpers_stopped 30; then
        return 0
    fi

    pids="$(running_mediaremote_helper_pids)"
    echo "error: unable to stop stale MediaRemote helper process(es): $(echo "$pids" | tr '\n' ' ')" >&2
    return 1
}

stop_running_local_ai_helpers() {
    local pids
    pids="$(running_local_ai_helper_pids)"
    if [[ -z "$pids" ]]; then
        return 0
    fi

    echo "==> Stopping stale Local AI helper process(es): $(echo "$pids" | tr '\n' ' ')"
    kill -TERM $pids 2>/dev/null || true
    if wait_until_local_ai_helpers_stopped 30; then
        return 0
    fi

    pids="$(running_local_ai_helper_pids)"
    echo "==> Stale Local AI helper ignored SIGTERM; forcing: $(echo "$pids" | tr '\n' ' ')"
    kill -KILL $pids 2>/dev/null || true
    if wait_until_local_ai_helpers_stopped 30; then
        return 0
    fi

    pids="$(running_local_ai_helper_pids)"
    echo "error: unable to stop stale Local AI helper process(es): $(echo "$pids" | tr '\n' ' ')" >&2
    return 1
}

unregister_bundle_if_present() {
    local bundle="$1"
    if [[ -d "$bundle" ]]; then
        echo "==> Unregistering stale Claude Stats bundle: $bundle"
        "$LSREGISTER" -u "$bundle" 2>/dev/null || true
    fi
}

cleanup_stale_registrations() {
    unregister_bundle_if_present "/Applications/Claude Stats.app"
    unregister_bundle_if_present "/tmp/claude-stats-build/Build/Products/Debug/Claude Stats.app"
    unregister_bundle_if_present "/tmp/Codex-stats-build-tests/Build/Products/Debug/Claude Stats.app"
}

require_apple_silicon
bash scripts/build-warp-embed.sh
bash scripts/build-linguist-runtime.sh
bash scripts/build-llama-runtime.sh
bash scripts/generate.sh

# Kill any running instance so the rebuild can replace it.
stop_running_app
stop_running_local_ai_helpers
stop_running_memory_sidecars
stop_running_mediaremote_helpers
cleanup_stale_registrations

MEMORY_DEV_LOG_DIR="$PWD/var/memory-logs"
mkdir -p "$MEMORY_DEV_LOG_DIR"
export CLAUDE_STATS_MEMORY_DEV_LOG_DIR="$MEMORY_DEV_LOG_DIR"
launchctl setenv CLAUDE_STATS_MEMORY_DEV_LOG_DIR "$MEMORY_DEV_LOG_DIR" 2>/dev/null || true

xcodebuild \
    -project ClaudeStats.xcodeproj \
    -scheme ClaudeStats \
    -configuration Debug \
    -derivedDataPath "$DERIVED" \
    ARCHS=arm64 \
    build

ENTITLEMENTS="$(mktemp "${TMPDIR:-/tmp}/claude-stats-entitlements.XXXXXX")"
if ! codesign -d --entitlements :- "$APP" > "$ENTITLEMENTS" 2>/dev/null; then
    rm -f "$ENTITLEMENTS"
    ENTITLEMENTS=""
fi
bash scripts/thin-arm64-bundle.sh "$APP"
bash scripts/codesign-ad-hoc-bundle.sh "$APP" "$ENTITLEMENTS"
[[ -n "$ENTITLEMENTS" ]] && rm -f "$ENTITLEMENTS"
bash scripts/verify-arm64-bundle.sh "$APP"

# Refresh Launch Services so the just-built bundle is the registered one.
"$LSREGISTER" -f "$APP" 2>/dev/null || true

open "$APP"
for ((i = 0; i < 20; i++)); do
    if [[ -n "$(running_app_pids)" ]]; then
        break
    fi
    sleep 0.25
done

if [[ -z "$(running_app_pids)" ]]; then
    echo "error: launch did not produce a Claude Stats process" >&2
    exit 1
fi

for ((i = 0; i < 24; i++)); do
    sleep 0.25
    if [[ -z "$(running_app_pids)" ]]; then
        echo "error: Claude Stats process exited during startup verification" >&2
        exit 1
    fi
done

echo "Launched $APP"
