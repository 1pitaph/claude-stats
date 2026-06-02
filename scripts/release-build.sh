#!/usr/bin/env bash
# Build Release Claude Stats.app and Claude Stats Lite.app packages into ./dist/.
#
# Two modes, selected automatically by whether SIGN_IDENTITY is set:
#
#   • Signed mode (SIGN_IDENTITY set): codesign with a Developer ID Application
#     identity + hardened runtime, package a DMG, notarize it with notarytool,
#     and staple the ticket.  Output:
#       dist/ClaudeStats-<version>.dmg
#       dist/ClaudeStatsLite-<version>.dmg
#
#   • Unsigned mode (SIGN_IDENTITY unset): ad-hoc sign, package both a DMG and a
#     .zip.  Gatekeeper will warn on first launch (right-click ▸ Open).
#     Output:
#       dist/ClaudeStats-<version>.dmg
#       dist/ClaudeStats-<version>.zip
#       dist/ClaudeStatsLite-<version>.dmg
#       dist/ClaudeStatsLite-<version>.zip
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
#
# The finished artifacts are written to ./dist/.
set -euo pipefail
cd "$(dirname "$0")/.."

DERIVED=/tmp/claude-stats-release
DIST="$PWD/dist"
MAIN_ARTIFACT_PREFIX="ClaudeStats"
MAIN_SCHEME="ClaudeStats"
MAIN_APP_NAME="Claude Stats"
MAIN_REQUIRES_CLOUDKIT=1
LITE_ARTIFACT_PREFIX="ClaudeStatsLite"
LITE_SCHEME="ClaudeStats Lite"
LITE_APP_NAME="Claude Stats Lite"
LITE_REQUIRES_CLOUDKIT=0

VERSION="${1:-$(grep -E '^[[:space:]]*MARKETING_VERSION:' project.yml | head -1 | sed -E 's/.*"([^"]+)".*/\1/')}"
[[ -n "$VERSION" ]] || { echo "error: could not determine version" >&2; exit 1; }

SIGNED=0
[[ -n "${SIGN_IDENTITY:-}" ]] && SIGNED=1

if [[ "$(uname -m)" != "arm64" ]]; then
    echo "error: Claude Stats release builds must run on Apple Silicon." >&2
    exit 1
fi

echo "==> Building Claude Stats $VERSION + Lite (Release, $([[ $SIGNED -eq 1 ]] && echo "signed + notarized" || echo "unsigned"))"
bash scripts/build-warp-embed.sh
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

build_app() {
    local scheme="$1"
    local app_name="$2"
    local app="$PRODUCTS/$app_name.app"

    echo "==> Building $app_name"
    xcodebuild \
        -project ClaudeStats.xcodeproj \
        -scheme "$scheme" \
        -configuration "$CONFIGURATION" \
        -derivedDataPath "$DERIVED" \
        "${XCODE_BUILD_ARGS[@]}" \
        build

    [[ -d "$app" ]] || { echo "error: build did not produce $app" >&2; exit 1; }
    bash scripts/thin-arm64-bundle.sh "$app"
    bash scripts/verify-arm64-bundle.sh "$app"

    local gittools_dir="$app/Contents/Resources/GitTools"
    bash scripts/gittools/prune-debug-symbols.sh "$gittools_dir"

    echo "==> Verifying bundled GitTools runtime for $app_name"
    bash scripts/verify-gittools-runtime.sh "$gittools_dir"
}

sign_release_app() {
    local app="$1"
    local artifact_prefix="$2"
    local app_name="$3"
    local requires_cloudkit="$4"
    local entitlements="$DIST/$artifact_prefix-signed-entitlements.plist"

    # Xcode combines the main app's CloudKit entitlements with restricted values
    # from the provisioning profile, including `com.apple.application-identifier`.
    # Preserve that resolved set before the final manual re-sign.
    echo "==> Capturing resolved app entitlements for $app_name"
    codesign -d --entitlements :- "$app" > "$entitlements"
    /usr/libexec/PlistBuddy -c 'Delete :com.apple.security.get-task-allow' "$entitlements" 2>/dev/null || true

    echo "==> Deep re-signing nested code + $app_name"
    codesign_nested_release_code "$app" --options runtime --timestamp --sign "$SIGN_IDENTITY"

    if [[ "$requires_cloudkit" -eq 1 ]]; then
        local rockxy_helper_tool="$app/Contents/Library/HelperTools/RockxyHelperTool"
        local local_ai_helper_tool="$app/Contents/Helpers/claude-stats-local-ai"
        if [[ ! -f "$rockxy_helper_tool" ]]; then
            echo "error: missing bundled Rockxy helper at $rockxy_helper_tool" >&2
            exit 1
        fi
        if [[ ! -f "$local_ai_helper_tool" ]]; then
            echo "error: missing bundled Local AI helper at $local_ai_helper_tool" >&2
            exit 1
        fi
        echo "==> Re-signing Rockxy helper tool"
        codesign_release --force --options runtime --timestamp \
            --sign "$SIGN_IDENTITY" \
            "$rockxy_helper_tool"
        echo "==> Re-signing Local AI helper tool"
        codesign_release --force --options runtime --timestamp \
            --sign "$SIGN_IDENTITY" \
            "$local_ai_helper_tool"
    fi

    codesign_release --force --options runtime --timestamp \
        --sign "$SIGN_IDENTITY" \
        --entitlements "$entitlements" \
        "$app"
}

make_dmg() {
    local app="$1"
    local artifact_prefix="$2"
    local app_item_name="$3.app"
    local volume_name="$3"
    local dmg="$DIST/$artifact_prefix-$VERSION.dmg"
    local stage; stage="$(mktemp -d)"
    local rw_dmg="$DIST/.$artifact_prefix-$VERSION-rw.dmg"
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

    cp -R "$app" "$stage/"
    ln -s /Applications "$stage/Applications"
    mkdir -p "$stage/.background"
    swift scripts/render-dmg-background.swift "$stage/.background/dmg-background.png"

    hdiutil create -volname "$volume_name" -srcfolder "$stage" -ov -fs HFS+ -format UDRW "$rw_dmg"
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

        set position of item "$app_item_name" to {235, 255}
        set position of item "Applications" to {665, 255}
        select item "$app_item_name"

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
    hdiutil convert "$rw_dmg" -format UDZO -imagekey zlib-level=9 -o "$dmg" -ov
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

package_unsigned_app() {
    local app="$1"
    local artifact_prefix="$2"
    local app_name="$3"
    local dmg="$DIST/$artifact_prefix-$VERSION.dmg"
    local zip="$DIST/$artifact_prefix-$VERSION.zip"
    local unsigned_entitlements="$DIST/$artifact_prefix-unsigned-entitlements.plist"

    echo "==> Packaging $app_name DMG + zip (unsigned)"
    codesign -d --entitlements :- "$app" > "$unsigned_entitlements" 2>/dev/null || rm -f "$unsigned_entitlements"
    bash scripts/codesign-ad-hoc-bundle.sh "$app" "$unsigned_entitlements"
    codesign --verify --deep --strict --verbose=2 "$app"
    make_dmg "$app" "$artifact_prefix" "$app_name"
    ditto -c -k --keepParent "$app" "$zip"
    echo "==> Packaged $app_name: $dmg, $zip"
}

verify_signed_app() {
    local app="$1"
    local artifact_prefix="$2"
    local app_name="$3"
    local requires_cloudkit="$4"
    local entitlements_out="$DIST/$artifact_prefix-entitlements.plist"

    echo "==> Verifying $app_name signature"
    codesign --verify --deep --strict --verbose=2 "$app"
    echo "==> Checking $app_name release entitlements"
    assert_no_get_task_allow_entitlements "$app"
    codesign -dvvv --entitlements :- "$app" > "$entitlements_out"

    if [[ "$requires_cloudkit" -eq 1 ]]; then
        grep -q "com.apple.developer.icloud-services" "$entitlements_out" || {
            echo "error: signed app is missing the CloudKit entitlement" >&2
            exit 1
        }
        grep -q "com.apple.application-identifier" "$entitlements_out" || {
            echo "error: signed app is missing the application identifier entitlement required by CloudKit" >&2
            exit 1
        }
    fi
}

NOTARY_ARGS=()
configure_notary_args() {
    if [[ -n "${NOTARY_KEYCHAIN_PROFILE:-}" ]]; then
        NOTARY_ARGS=(--keychain-profile "$NOTARY_KEYCHAIN_PROFILE")
    elif [[ -n "${APPLE_ID:-}" && -n "${APP_PASSWORD:-}" && -n "${APPLE_TEAM_ID:-}" ]]; then
        NOTARY_ARGS=(--apple-id "$APPLE_ID" --password "$APP_PASSWORD" --team-id "$APPLE_TEAM_ID")
    else
        echo "error: notarization needs NOTARY_KEYCHAIN_PROFILE or APPLE_ID + APP_PASSWORD + APPLE_TEAM_ID" >&2
        exit 1
    fi
}

notarize_dmg() {
    local dmg="$1"
    local artifact_prefix="$2"
    shift 2
    local notary_args=("$@")

    echo "==> Signing DMG: $dmg"
    codesign_release --sign "$SIGN_IDENTITY" --timestamp "$dmg"

    echo "==> Submitting $artifact_prefix DMG to Apple notary service (this can take a few minutes)"
    # notarytool returns 0 even when status=Invalid (submission "completed",
    # content was rejected), so parse the status ourselves and fail loudly with
    # the actual log instead of letting stapler fail with a misleading error.
    local submit_log="$DIST/$artifact_prefix-notarytool-submit.log"
    xcrun notarytool submit "$dmg" "${notary_args[@]}" --wait | tee "$submit_log"
    local submit_status
    submit_status="$(awk -F': *' '/^[[:space:]]*status:/ {print $2; exit}' "$submit_log" | tr -d '[:space:]')"
    if [[ "$submit_status" != "Accepted" ]]; then
        local submit_id
        submit_id="$(awk -F': *' '/^[[:space:]]*id:/ {print $2; exit}' "$submit_log" | tr -d '[:space:]')"
        echo "==> Notarization failed for $artifact_prefix (status: $submit_status) — fetching log" >&2
        [[ -n "$submit_id" ]] && xcrun notarytool log "$submit_id" "${notary_args[@]}" >&2 || true
        exit 1
    fi

    echo "==> Stapling notarization ticket: $dmg"
    xcrun stapler staple "$dmg"
    xcrun stapler validate "$dmg"
    spctl -a -t open --context context:primary-signature -v "$dmg" || true
}

MAIN_APP="$PRODUCTS/$MAIN_APP_NAME.app"
LITE_APP="$PRODUCTS/$LITE_APP_NAME.app"

build_app "$MAIN_SCHEME" "$MAIN_APP_NAME"
build_app "$LITE_SCHEME" "$LITE_APP_NAME"

if [[ $SIGNED -eq 0 ]]; then
    package_unsigned_app "$MAIN_APP" "$MAIN_ARTIFACT_PREFIX" "$MAIN_APP_NAME"
    package_unsigned_app "$LITE_APP" "$LITE_ARTIFACT_PREFIX" "$LITE_APP_NAME"
    echo "==> Done (unsigned)"
    ls -la "$DIST"
    exit 0
fi

sign_release_app "$MAIN_APP" "$MAIN_ARTIFACT_PREFIX" "$MAIN_APP_NAME" "$MAIN_REQUIRES_CLOUDKIT"
sign_release_app "$LITE_APP" "$LITE_ARTIFACT_PREFIX" "$LITE_APP_NAME" "$LITE_REQUIRES_CLOUDKIT"

verify_signed_app "$MAIN_APP" "$MAIN_ARTIFACT_PREFIX" "$MAIN_APP_NAME" "$MAIN_REQUIRES_CLOUDKIT"
verify_signed_app "$LITE_APP" "$LITE_ARTIFACT_PREFIX" "$LITE_APP_NAME" "$LITE_REQUIRES_CLOUDKIT"

echo "==> Packaging DMGs"
make_dmg "$MAIN_APP" "$MAIN_ARTIFACT_PREFIX" "$MAIN_APP_NAME"
make_dmg "$LITE_APP" "$LITE_ARTIFACT_PREFIX" "$LITE_APP_NAME"

configure_notary_args
notarize_dmg "$DIST/$MAIN_ARTIFACT_PREFIX-$VERSION.dmg" "$MAIN_ARTIFACT_PREFIX" "${NOTARY_ARGS[@]}"
notarize_dmg "$DIST/$LITE_ARTIFACT_PREFIX-$VERSION.dmg" "$LITE_ARTIFACT_PREFIX" "${NOTARY_ARGS[@]}"

echo "==> Done (signed + notarized)"
ls -la "$DIST"
