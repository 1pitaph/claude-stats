#!/usr/bin/env bash
# Build a Release Claude Stats.app and package it for distribution into ./dist/.
#
# Two modes, selected automatically by whether SIGN_IDENTITY is set:
#
#   • Signed mode (SIGN_IDENTITY set): codesign with a Developer ID Application
#     identity + hardened runtime, package a DMG, notarize it with notarytool,
#     and staple the ticket.  Output: dist/ClaudeStats-<version>.dmg
#
#   • Unsigned mode (SIGN_IDENTITY unset): ad-hoc sign, package both a DMG and a
#     .zip.  Gatekeeper will warn on first launch (right-click ▸ Open).
#     Output: dist/ClaudeStats-<version>.dmg and dist/ClaudeStats-<version>.zip
#
# Usage: bash scripts/release-build.sh [version]
#   [version]  version label for the artifact file names; defaults to the
#              MARKETING_VERSION currently in project.yml.
#
# Environment (signed mode):
#   SIGN_IDENTITY              codesign identity, e.g. "Developer ID Application: Foo (TEAMID)"
#   APPLE_TEAM_ID              10-char Apple Developer Team ID
#   PROVISIONING_PROFILE_SPECIFIER
#                              Developer ID provisioning profile with the
#                              iCloud/CloudKit capability enabled
#   APPLE_ID + APP_PASSWORD    Apple ID + app-specific password for notarytool
#   NOTARY_KEYCHAIN_PROFILE    (alternative to APPLE_ID/APP_PASSWORD) a stored notarytool profile
#
# Environment (all release builds):
#   LINGUIST_RUNTIME_SOURCE    relocatable GitTools runtime produced by
#                              scripts/build-gittools-runtime.sh
#   GHOSTTY_RELEASE_OPTIMIZE   GhosttyKit optimize mode for distributable builds;
#                              defaults to ReleaseFast. Must be ReleaseFast or
#                              ReleaseSmall so Ghostty's debug warning is never
#                              shipped.
#
# The finished artifacts are written to ./dist/.
set -euo pipefail
cd "$(dirname "$0")/.."

DERIVED=/tmp/claude-stats-release
DIST="$PWD/dist"
CLOUDKIT_ENTITLEMENTS="ClaudeStats/App/ClaudeStatsCloudKit.entitlements"
SIGNED_ENTITLEMENTS="$DIST/signed-entitlements.plist"
UNSIGNED_ENTITLEMENTS="$DIST/unsigned-entitlements.plist"

VERSION="${1:-$(grep -E '^[[:space:]]*MARKETING_VERSION:' project.yml | head -1 | sed -E 's/.*"([^"]+)".*/\1/')}"
[[ -n "$VERSION" ]] || { echo "error: could not determine version" >&2; exit 1; }
DMG="$DIST/ClaudeStats-$VERSION.dmg"
ZIP="$DIST/ClaudeStats-$VERSION.zip"

SIGNED=0
[[ -n "${SIGN_IDENTITY:-}" ]] && SIGNED=1
GHOSTTY_RELEASE_OPTIMIZE="${GHOSTTY_RELEASE_OPTIMIZE:-ReleaseFast}"

if [[ "$(uname -m)" != "arm64" ]]; then
    echo "error: Claude Stats release builds must run on Apple Silicon." >&2
    exit 1
fi

case "$GHOSTTY_RELEASE_OPTIMIZE" in
    ReleaseFast|ReleaseSmall) ;;
    *)
        echo "error: release builds require GHOSTTY_RELEASE_OPTIMIZE=ReleaseFast or ReleaseSmall" >&2
        echo "hint: Ghostty shows a debug performance warning for Debug and ReleaseSafe builds" >&2
        exit 1
        ;;
esac

echo "==> Building Claude Stats $VERSION (Release, $([[ $SIGNED -eq 1 ]] && echo "signed + notarized" || echo "unsigned"))"
GHOSTTY_OPTIMIZE="$GHOSTTY_RELEASE_OPTIMIZE" \
GHOSTTY_XCFRAMEWORK_TARGET="${GHOSTTY_XCFRAMEWORK_TARGET:-native}" \
    bash scripts/build-ghosttykit.sh
REQUIRE_LINGUIST_RUNTIME="${REQUIRE_LINGUIST_RUNTIME:-1}" \
REQUIRE_RELOCATABLE_LINGUIST_RUNTIME="${REQUIRE_RELOCATABLE_LINGUIST_RUNTIME:-1}" \
    bash scripts/build-linguist-runtime.sh
LLAMA_ARCHS=arm64 bash scripts/build-llama-runtime.sh
python3 scripts/generate-release-history.py --tag "v$VERSION"
bash scripts/generate.sh

rm -rf "$DERIVED" "$DIST"
mkdir -p "$DIST"

CONFIGURATION=Release
RELEASE_ARCHS="${RELEASE_ARCHS:-arm64}"
if [[ "$RELEASE_ARCHS" != "arm64" ]]; then
    echo "error: RELEASE_ARCHS must be arm64 for Apple Silicon-only releases (got '$RELEASE_ARCHS')" >&2
    exit 1
fi
XCODE_BUILD_ARGS=(ARCHS="$RELEASE_ARCHS")
if [[ $SIGNED -eq 1 ]]; then
    [[ -n "${APPLE_TEAM_ID:-}" ]] || {
        echo "error: signed CloudKit builds require APPLE_TEAM_ID" >&2
        exit 1
    }
    [[ -n "${PROVISIONING_PROFILE_SPECIFIER:-}" || -n "${PROVISIONING_PROFILE:-}" ]] || {
        echo "error: signed CloudKit builds require PROVISIONING_PROFILE_SPECIFIER (or PROVISIONING_PROFILE) for a CloudKit-capable Developer ID profile" >&2
        exit 1
    }
    echo "==> Signing with: $SIGN_IDENTITY (hardened runtime)"
    export CLAUDE_STATS_PROVISIONING_PROFILE_SPECIFIER="${PROVISIONING_PROFILE_SPECIFIER:-}"
    export CLAUDE_STATS_PROVISIONING_PROFILE="${PROVISIONING_PROFILE:-}"
    CONFIGURATION=ReleaseSigned
else
    XCODE_BUILD_ARGS+=(CODE_SIGN_IDENTITY="-" CODE_SIGN_STYLE=Automatic ENABLE_HARDENED_RUNTIME=NO)
fi

PRODUCTS="$DERIVED/Build/Products/$CONFIGURATION"
APP="$PRODUCTS/Claude Stats.app"
ROCKXY_HELPER_TOOL="$APP/Contents/Library/HelperTools/RockxyHelperTool"
LOCAL_AI_HELPER_TOOL="$APP/Contents/Helpers/claude-stats-local-ai"

codesign_release() {
    local attempt=1
    local max_attempts=3
    local delay=5
    local status=0

    while true; do
        if codesign "$@"; then
            return 0
        fi

        status=$?
        if [[ "$attempt" -ge "$max_attempts" ]]; then
            return "$status"
        fi

        echo "warning: codesign failed on attempt $attempt/$max_attempts; retrying in ${delay}s" >&2
        sleep "$delay"
        attempt=$((attempt + 1))
        delay=$((delay * 2))
    done
}

codesign_nested_release_code() {
    local root="$1"
    shift
    local sign_args=("$@")

    while IFS= read -r -d '' item; do
        case "$item" in
            *.o|*/CMakeFiles/*|*/CMakeCache.txt) continue ;;
        esac
        if file "$item" | grep -q 'Mach-O'; then
            codesign_release --force "${sign_args[@]}" "$item"
        fi
    done < <(find "$root" -type d -name '*.dSYM' -prune -o -type f -print0)

    while IFS= read -r bundle; do
        [[ "$bundle" == "$root" ]] && continue
        codesign_release --force "${sign_args[@]}" "$bundle"
    done < <(
        find "$root" -type d \( \
            -name '*.app' -o \
            -name '*.appex' -o \
            -name '*.bundle' -o \
            -name '*.framework' -o \
            -name '*.plugin' -o \
            -name '*.xpc' \
        \) -print | awk '{ print length, $0 }' | sort -rn | cut -d' ' -f2-
    )
}

xcodebuild \
    -project ClaudeStats.xcodeproj \
    -scheme ClaudeStats \
    -configuration "$CONFIGURATION" \
    -derivedDataPath "$DERIVED" \
    "${XCODE_BUILD_ARGS[@]}" \
    build

[[ -d "$APP" ]] || { echo "error: build did not produce $APP" >&2; exit 1; }

bash scripts/thin-arm64-bundle.sh "$APP"
bash scripts/verify-arm64-bundle.sh "$APP"

GITTOOLS_DIR="$APP/Contents/Resources/GitTools"
bash scripts/gittools/prune-debug-symbols.sh "$GITTOOLS_DIR"

echo "==> Verifying bundled GitTools runtime"
bash scripts/verify-gittools-runtime.sh "$GITTOOLS_DIR"

if [[ $SIGNED -eq 1 ]]; then
    # Xcode combines our requested CloudKit entitlements with restricted values
    # from the provisioning profile, including `com.apple.application-identifier`.
    # Preserve that resolved set for the final manual re-sign below; using only
    # our source entitlements plist strips the application identifier and makes
    # CloudKit fail at runtime with "without an application ID".
    echo "==> Capturing resolved app entitlements"
    codesign -d --entitlements :- "$APP" > "$SIGNED_ENTITLEMENTS"
    /usr/libexec/PlistBuddy -c 'Delete :com.apple.security.get-task-allow' "$SIGNED_ENTITLEMENTS" 2>/dev/null || true

    # xcodebuild signs before our release pruning/thinning steps are complete,
    # and Sparkle contains nested XPC/helper code. Re-sign all nested code
    # bottom-up, then re-sign the main app with the resolved CloudKit entitlements.
    echo "==> Deep re-signing nested code + main app"
    codesign_nested_release_code "$APP" --options runtime --timestamp --sign "$SIGN_IDENTITY"
    if [[ ! -f "$ROCKXY_HELPER_TOOL" ]]; then
        echo "error: missing bundled Rockxy helper at $ROCKXY_HELPER_TOOL" >&2
        exit 1
    fi
    if [[ ! -f "$LOCAL_AI_HELPER_TOOL" ]]; then
        echo "error: missing bundled Local AI helper at $LOCAL_AI_HELPER_TOOL" >&2
        exit 1
    fi
    echo "==> Re-signing Rockxy helper tool"
    codesign_release --force --options runtime --timestamp \
        --sign "$SIGN_IDENTITY" \
        "$ROCKXY_HELPER_TOOL"
    echo "==> Re-signing Local AI helper tool"
    codesign_release --force --options runtime --timestamp \
        --sign "$SIGN_IDENTITY" \
        "$LOCAL_AI_HELPER_TOOL"
    codesign_release --force --options runtime --timestamp \
        --sign "$SIGN_IDENTITY" \
        --entitlements "$SIGNED_ENTITLEMENTS" \
        "$APP"
fi

make_dmg() {
    local stage; stage="$(mktemp -d)"
    local rw_dmg="$DIST/.ClaudeStats-$VERSION-rw.dmg"
    local mount_dir; mount_dir="$(mktemp -d)"
    local attached=0

    cleanup_dmg_stage() {
        if [[ $attached -eq 1 ]]; then
            hdiutil detach "$mount_dir" -quiet || hdiutil detach "$mount_dir" -force || true
        fi
        rm -f "$rw_dmg"
        rmdir "$mount_dir" 2>/dev/null || true
        rm -rf "$stage"
    }
    trap cleanup_dmg_stage RETURN

    cp -R "$APP" "$stage/"
    ln -s /Applications "$stage/Applications"
    mkdir -p "$stage/.background"
    swift scripts/render-dmg-background.swift "$stage/.background/dmg-background.png"

    hdiutil create -volname "Claude Stats" -srcfolder "$stage" -ov -fs HFS+ -format UDRW "$rw_dmg"
    hdiutil attach "$rw_dmg" -mountpoint "$mount_dir" -nobrowse -noverify -noautoopen
    attached=1

    osascript <<APPLESCRIPT
tell application "Finder"
    set dmgFolder to folder (POSIX file "$mount_dir" as alias)
    set backgroundImage to POSIX file "$mount_dir/.background/dmg-background.png" as alias

    tell dmgFolder
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {220, 120, 1140, 682}

        set viewOptions to the icon view options of container window
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to 128
        set text size of viewOptions to 16
        set background picture of viewOptions to backgroundImage

        set position of item "Claude Stats.app" to {235, 255}
        set position of item "Applications" to {665, 255}
        select item "Claude Stats.app"

        close
        open
        update without registering applications
        delay 1
    end tell
end tell
APPLESCRIPT

    sync
    hdiutil detach "$mount_dir" -quiet || hdiutil detach "$mount_dir" -force
    attached=0
    hdiutil convert "$rw_dmg" -format UDZO -imagekey zlib-level=9 -o "$DMG" -ov
    trap - RETURN
    cleanup_dmg_stage
}

assert_no_get_task_allow_entitlements() {
    local root="$1"
    local found=0

    while IFS= read -r -d '' item; do
        if ! file "$item" | grep -q 'Mach-O'; then
            continue
        fi

        local entitlements
        entitlements="$(mktemp "$DIST/entitlements-check.XXXXXX")"
        if codesign -d --entitlements :- "$item" > "$entitlements" 2>/dev/null; then
            local get_task_allow
            get_task_allow="$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.get-task-allow' "$entitlements" 2>/dev/null || true)"
            if [[ "$get_task_allow" == "true" ]]; then
                echo "error: release executable has com.apple.security.get-task-allow=true: $item" >&2
                found=1
            fi
        fi
        rm -f "$entitlements"
    done < <(find "$root" -type d -name '*.dSYM' -prune -o -type f -print0)

    if [[ $found -ne 0 ]]; then
        exit 1
    fi
}

if [[ $SIGNED -eq 0 ]]; then
    echo "==> Packaging DMG + zip (unsigned)"
    codesign -d --entitlements :- "$APP" > "$UNSIGNED_ENTITLEMENTS" 2>/dev/null || rm -f "$UNSIGNED_ENTITLEMENTS"
    bash scripts/codesign-ad-hoc-bundle.sh "$APP" "$UNSIGNED_ENTITLEMENTS"
    codesign --verify --deep --strict --verbose=2 "$APP"
    make_dmg
    ditto -c -k --keepParent "$APP" "$ZIP"
    echo "==> Done (unsigned): $DMG, $ZIP"
    ls -la "$DIST"
    exit 0
fi

echo "==> Verifying app signature"
codesign --verify --deep --strict --verbose=2 "$APP"
echo "==> Checking release entitlements"
assert_no_get_task_allow_entitlements "$APP"
ENTITLEMENTS_OUT="$DIST/entitlements.plist"
codesign -dvvv --entitlements :- "$APP" > "$ENTITLEMENTS_OUT"
grep -q "com.apple.developer.icloud-services" "$ENTITLEMENTS_OUT" || {
    echo "error: signed app is missing the CloudKit entitlement" >&2
    exit 1
}
grep -q "com.apple.application-identifier" "$ENTITLEMENTS_OUT" || {
    echo "error: signed app is missing the application identifier entitlement required by CloudKit" >&2
    exit 1
}

echo "==> Packaging DMG"
make_dmg

echo "==> Signing DMG"
codesign_release --sign "$SIGN_IDENTITY" --timestamp "$DMG"

echo "==> Submitting to Apple notary service (this can take a few minutes)"
NOTARY_ARGS=()
if [[ -n "${NOTARY_KEYCHAIN_PROFILE:-}" ]]; then
    NOTARY_ARGS=(--keychain-profile "$NOTARY_KEYCHAIN_PROFILE")
elif [[ -n "${APPLE_ID:-}" && -n "${APP_PASSWORD:-}" && -n "${APPLE_TEAM_ID:-}" ]]; then
    NOTARY_ARGS=(--apple-id "$APPLE_ID" --password "$APP_PASSWORD" --team-id "$APPLE_TEAM_ID")
else
    echo "error: notarization needs NOTARY_KEYCHAIN_PROFILE or APPLE_ID + APP_PASSWORD + APPLE_TEAM_ID" >&2
    exit 1
fi

# notarytool returns 0 even when status=Invalid (submission "completed",
# content was rejected), so parse the status ourselves and fail loudly with
# the actual log instead of letting stapler fail with a misleading error.
SUBMIT_LOG="$DIST/notarytool-submit.log"
xcrun notarytool submit "$DMG" "${NOTARY_ARGS[@]}" --wait | tee "$SUBMIT_LOG"
SUBMIT_STATUS="$(awk -F': *' '/^[[:space:]]*status:/ {print $2; exit}' "$SUBMIT_LOG" | tr -d '[:space:]')"
if [[ "$SUBMIT_STATUS" != "Accepted" ]]; then
    SUBMIT_ID="$(awk -F': *' '/^[[:space:]]*id:/ {print $2; exit}' "$SUBMIT_LOG" | tr -d '[:space:]')"
    echo "==> Notarization failed (status: $SUBMIT_STATUS) — fetching log" >&2
    [[ -n "$SUBMIT_ID" ]] && xcrun notarytool log "$SUBMIT_ID" "${NOTARY_ARGS[@]}" >&2 || true
    exit 1
fi

echo "==> Stapling notarization ticket"
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"
spctl -a -t open --context context:primary-signature -v "$DMG" || true

echo "==> Done (signed + notarized): $DMG"
ls -la "$DIST"
