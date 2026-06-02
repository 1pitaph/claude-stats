#!/usr/bin/env bash
# Sign the freshly-built release archive with Sparkle's EdDSA key and write an
# updated appcast to ./_site/<appcast-file> (the workflow then pushes _site/ to
# the gh-pages branch, which GitHub Pages serves at the SUFeedURL in Info.plist).
#
# Expects the artifacts produced by scripts/release-build.sh to already be in
# ./dist/. This script may add Sparkle .delta files to ./dist/ before the
# workflow uploads all assets to GitHub Releases.
#
# Usage: bash scripts/publish-appcast.sh <version> <build> <tag> [artifact-prefix] [appcast-file] [channel-title]
#   <version>  marketing version, e.g. 1.2.0
#   <build>    build number (CURRENT_PROJECT_VERSION) — must be monotonically
#              increasing across releases; Sparkle compares on this
#   <tag>      the git tag, e.g. v1.2.0 (used to build the release asset URL)
#   [artifact-prefix]
#              release artifact prefix; defaults to ClaudeStats
#   [appcast-file]
#              output/feed filename under gh-pages; defaults to appcast.xml
#   [channel-title]
#              RSS channel title for newly-created appcasts
#
# Environment:
#   SPARKLE_PRIVATE_ED_KEY   base64 EdDSA private key from Sparkle's
#                            `generate_keys -x <file>` (store as a repo secret)
#   SPARKLE_MAX_DELTAS       optional number of previous versions to diff
#                            against; defaults to 3
#   SPARKLE_DELTA_FORMAT_VERSION
#                            optional BinaryDelta format version; defaults to 4
set -euo pipefail
cd "$(dirname "$0")/.."

USAGE="usage: publish-appcast.sh <version> <build> <tag> [artifact-prefix] [appcast-file] [channel-title]"
VERSION="${1:?$USAGE}"
BUILD="${2:?$USAGE}"
TAG="${3:?$USAGE}"
ARTIFACT_PREFIX="${4:-ClaudeStats}"
APPCAST_FILE="${5:-appcast.xml}"
CHANNEL_TITLE="${6:-Claude Stats}"
: "${SPARKLE_PRIVATE_ED_KEY:?SPARKLE_PRIVATE_ED_KEY is not set}"

REPO="1pitaph/claude-stats"
FEED_URL="https://1pitaph.github.io/claude-stats/$APPCAST_FILE"
CHANNEL_DESCRIPTION="${APPCAST_CHANNEL_DESCRIPTION:-Most recent updates to $CHANNEL_TITLE.}"
SPARKLE_TOOLS_VERSION="2.9.1"   # the version of Sparkle CLI tools to download
SPARKLE_MAX_DELTAS="${SPARKLE_MAX_DELTAS:-3}"
SPARKLE_DELTA_FORMAT_VERSION="${SPARKLE_DELTA_FORMAT_VERSION:-4}"

case "$SPARKLE_MAX_DELTAS" in
    ''|*[!0-9]*)
        echo "error: SPARKLE_MAX_DELTAS must be a non-negative integer" >&2
        exit 1
        ;;
esac
case "$SPARKLE_DELTA_FORMAT_VERSION" in
    ''|*[!0-9]*)
        echo "error: SPARKLE_DELTA_FORMAT_VERSION must be a positive integer" >&2
        exit 1
        ;;
    0)
        echo "error: SPARKLE_DELTA_FORMAT_VERSION must be a positive integer" >&2
        exit 1
        ;;
esac

gh_warning() {
    local message="$1"
    if [[ -n "${GITHUB_ACTIONS:-}" ]]; then
        echo "::warning::$message"
    else
        echo "warning: $message" >&2
    fi
}

# Sparkle updates from a .zip when one is present (no disk image to mount),
# otherwise from the .dmg (notarized + stapled in the signed release path).
ARCHIVE=""
for candidate in "dist/$ARTIFACT_PREFIX-$VERSION.zip" "dist/$ARTIFACT_PREFIX-$VERSION.dmg"; do
    if [[ -f "$candidate" ]]; then ARCHIVE="$candidate"; break; fi
done
[[ -n "$ARCHIVE" ]] || { echo "error: no dist/$ARTIFACT_PREFIX-$VERSION.{zip,dmg} to sign" >&2; exit 1; }
ARCHIVE_NAME="$(basename "$ARCHIVE")"
echo "==> Signing $ARCHIVE for $APPCAST_FILE"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

curl -fsSL "https://github.com/sparkle-project/Sparkle/releases/download/${SPARKLE_TOOLS_VERSION}/Sparkle-${SPARKLE_TOOLS_VERSION}.tar.xz" \
    -o "$WORK/sparkle.tar.xz"
tar -xJf "$WORK/sparkle.tar.xz" -C "$WORK" bin/sign_update bin/BinaryDelta

KEY_FILE="$WORK/ed_private_key"
printf '%s' "$SPARKLE_PRIVATE_ED_KEY" > "$KEY_FILE"

# sign_update prints: sparkle:edSignature="…" length="…"
ENCLOSURE_ATTRS="$("$WORK/bin/sign_update" "$ARCHIVE" --ed-key-file "$KEY_FILE")"
[[ "$ENCLOSURE_ATTRS" == *edSignature* ]] || { echo "error: sign_update produced no signature: $ENCLOSURE_ATTRS" >&2; exit 1; }

# Start from the currently-published appcast so older versions are preserved.
curl -fsSL "$FEED_URL" -o "$WORK/appcast.xml" || rm -f "$WORK/appcast.xml"

extract_archive_app() {
    local archive="$1"
    local output_dir="$2"
    local mount_dir app_path app_name

    rm -rf "$output_dir"
    mkdir -p "$output_dir"

    case "$archive" in
        *.zip)
            ditto -x -k "$archive" "$output_dir"
            ;;
        *.dmg)
            mount_dir="$output_dir.mount"
            rm -rf "$mount_dir"
            mkdir -p "$mount_dir"
            if ! hdiutil attach "$archive" -mountpoint "$mount_dir" -nobrowse -readonly -quiet; then
                rmdir "$mount_dir" 2>/dev/null || true
                return 1
            fi

            app_path="$(find "$mount_dir" -type d -name '*.app' -prune -print | head -n 1)"
            if [[ -z "$app_path" ]]; then
                hdiutil detach "$mount_dir" -quiet || hdiutil detach "$mount_dir" -force || true
                rmdir "$mount_dir" 2>/dev/null || true
                return 1
            fi
            app_name="$(basename "$app_path")"
            ditto "$app_path" "$output_dir/$app_name"
            hdiutil detach "$mount_dir" -quiet || hdiutil detach "$mount_dir" -force
            rmdir "$mount_dir" 2>/dev/null || true
            ;;
        *)
            echo "unsupported archive type: $archive" >&2
            return 1
            ;;
    esac

    find "$output_dir" -type d -name '*.app' -prune -print | head -n 1
}

delta_safety_problem() {
    local app="$1"
    local first

    first="$(find "$app" -type d -name '*.dSYM' -print -quit)"
    if [[ -n "$first" ]]; then
        echo "debug symbol bundle: $first"
        return 0
    fi

    first="$(find "$app" -type f -name '*.o' -print -quit)"
    if [[ -n "$first" ]]; then
        echo "object file: $first"
        return 0
    fi

    if command -v xattr >/dev/null 2>&1; then
        while IFS= read -r -d '' item; do
            if xattr "$item" 2>/dev/null | grep -Eq '^com\.apple\.cs\.'; then
                echo "code-signing extended attributes: $item"
                return 0
            fi
        done < <(find "$app" -type d -name '*.dSYM' -prune -o -print0)
    fi

    return 0
}

append_delta_json() {
    local json_file="$1"
    local delta_from="$2"
    local delta_from_display="$3"
    local url="$4"
    local attrs="$5"

    python3 - "$json_file" "$delta_from" "$delta_from_display" "$url" "$attrs" <<'PY'
import json
import sys

path, delta_from, delta_from_display, url, attrs = sys.argv[1:6]
with open(path, encoding="utf-8") as fh:
    data = json.load(fh)
entry = {"deltaFrom": delta_from, "url": url, "enclosureAttrs": attrs}
if delta_from_display:
    entry["deltaFromDisplay"] = delta_from_display
data.append(entry)
with open(path, "w", encoding="utf-8") as fh:
    json.dump(data, fh, indent=2)
    fh.write("\n")
PY
}

write_previous_releases() {
    local appcast="$1"
    local max_deltas="$2"
    local current_build="$3"
    local output="$4"

    python3 - "$appcast" "$max_deltas" "$current_build" > "$output" <<'PY'
import sys
import xml.etree.ElementTree as ET

appcast, max_deltas, current_build = sys.argv[1], int(sys.argv[2]), sys.argv[3]
if max_deltas <= 0:
    raise SystemExit(0)
try:
    root = ET.parse(appcast).getroot()
except (ET.ParseError, FileNotFoundError):
    raise SystemExit(0)

ns = {"sparkle": "http://www.andymatuschak.org/xml-namespaces/sparkle"}
count = 0
for item in root.findall("./channel/item"):
    build = item.findtext("sparkle:version", namespaces=ns)
    display = item.findtext("sparkle:shortVersionString", namespaces=ns) or build
    enclosure = item.find("enclosure")
    url = enclosure.get("url") if enclosure is not None else None
    if not build or not url:
        continue
    if build == current_build:
        continue
    if not (url.endswith(".zip") or url.endswith(".dmg")):
        continue
    print("\t".join([build, display or build, url]))
    count += 1
    if count >= max_deltas:
        break
PY
}

DELTAS_JSON="$WORK/deltas.json"
printf '[]\n' > "$DELTAS_JSON"

CURRENT_EXTRACT="$WORK/current"
CURRENT_APP="$(extract_archive_app "$ARCHIVE" "$CURRENT_EXTRACT")" || {
    echo "error: failed to extract current archive for delta generation: $ARCHIVE" >&2
    exit 1
}
[[ -n "$CURRENT_APP" ]] || { echo "error: current archive contains no .app bundle: $ARCHIVE" >&2; exit 1; }
CURRENT_PROBLEM="$(delta_safety_problem "$CURRENT_APP")"
if [[ -n "$CURRENT_PROBLEM" ]]; then
    echo "error: current release bundle is not safe for Sparkle delta generation: $CURRENT_PROBLEM" >&2
    exit 1
fi

PREVIOUS_RELEASES="$WORK/previous-releases.tsv"
write_previous_releases "$WORK/appcast.xml" "$SPARKLE_MAX_DELTAS" "$BUILD" "$PREVIOUS_RELEASES"

if [[ -s "$PREVIOUS_RELEASES" ]]; then
    echo "==> Generating Sparkle delta update(s)"
fi

while IFS=$'\t' read -r OLD_BUILD OLD_DISPLAY OLD_URL; do
    [[ -n "$OLD_BUILD" && -n "$OLD_URL" ]] || continue

    case "$OLD_URL" in
        *.zip) OLD_ARCHIVE="$WORK/old-$OLD_BUILD.zip" ;;
        *.dmg) OLD_ARCHIVE="$WORK/old-$OLD_BUILD.dmg" ;;
        *)
            gh_warning "Skipping delta from $OLD_DISPLAY ($OLD_BUILD): unsupported archive URL $OLD_URL"
            continue
            ;;
    esac

    echo "==> Preparing delta from $OLD_DISPLAY (build $OLD_BUILD)"
    if ! curl -fsSL "$OLD_URL" -o "$OLD_ARCHIVE"; then
        gh_warning "Skipping delta from $OLD_DISPLAY ($OLD_BUILD): failed to download $OLD_URL"
        continue
    fi

    OLD_EXTRACT="$WORK/old-$OLD_BUILD"
    if ! OLD_APP="$(extract_archive_app "$OLD_ARCHIVE" "$OLD_EXTRACT")" || [[ -z "$OLD_APP" ]]; then
        gh_warning "Skipping delta from $OLD_DISPLAY ($OLD_BUILD): failed to extract app bundle"
        continue
    fi

    OLD_PROBLEM="$(delta_safety_problem "$OLD_APP")"
    if [[ -n "$OLD_PROBLEM" ]]; then
        gh_warning "Skipping delta from $OLD_DISPLAY ($OLD_BUILD): old bundle is not delta-safe ($OLD_PROBLEM)"
        continue
    fi

    DELTA_NAME="$ARTIFACT_PREFIX-$BUILD-from-$OLD_BUILD.delta"
    DELTA_PATH="dist/$DELTA_NAME"
    PATCHED_DIR="$WORK/patched-$OLD_BUILD"
    PATCHED_APP="$PATCHED_DIR/$(basename "$CURRENT_APP")"
    rm -rf "$DELTA_PATH" "$PATCHED_DIR"
    mkdir -p "$PATCHED_DIR"

    if ! "$WORK/bin/BinaryDelta" create \
        --version "$SPARKLE_DELTA_FORMAT_VERSION" \
        "$OLD_APP" \
        "$CURRENT_APP" \
        "$DELTA_PATH"; then
        gh_warning "Skipping delta from $OLD_DISPLAY ($OLD_BUILD): BinaryDelta create failed"
        rm -f "$DELTA_PATH"
        continue
    fi

    if ! "$WORK/bin/BinaryDelta" apply "$OLD_APP" "$PATCHED_APP" "$DELTA_PATH"; then
        gh_warning "Skipping delta from $OLD_DISPLAY ($OLD_BUILD): BinaryDelta apply verification failed"
        rm -f "$DELTA_PATH"
        continue
    fi

    DELTA_ATTRS="$("$WORK/bin/sign_update" "$DELTA_PATH" --ed-key-file "$KEY_FILE")"
    if [[ "$DELTA_ATTRS" != *edSignature* ]]; then
        gh_warning "Skipping delta from $OLD_DISPLAY ($OLD_BUILD): sign_update produced no signature"
        rm -f "$DELTA_PATH"
        continue
    fi

    append_delta_json \
        "$DELTAS_JSON" \
        "$OLD_BUILD" \
        "$OLD_DISPLAY" \
        "https://github.com/$REPO/releases/download/$TAG/$DELTA_NAME" \
        "$DELTA_ATTRS"
done < "$PREVIOUS_RELEASES"

mkdir -p _site
NOTES_FILE="${RELEASE_NOTES_FILE:-release_notes.html}"
[[ -f "$NOTES_FILE" ]] || { echo "error: release notes file '$NOTES_FILE' not found" >&2; exit 1; }

python3 scripts/update-appcast.py \
    --version "$VERSION" \
    --build "$BUILD" \
    --url "https://github.com/$REPO/releases/download/$TAG/$ARCHIVE_NAME" \
    --enclosure-attrs "$ENCLOSURE_ATTRS" \
    --release-notes-file "$NOTES_FILE" \
    --feed-url "$FEED_URL" \
    --channel-title "$CHANNEL_TITLE" \
    --channel-description "$CHANNEL_DESCRIPTION" \
    --min-system-version "14.0.0" \
    --hardware-requirements "arm64" \
    --deltas-file "$DELTAS_JSON" \
    --in "$WORK/appcast.xml" \
    --out "_site/$APPCAST_FILE"

echo "==> Wrote _site/$APPCAST_FILE:"
cat "_site/$APPCAST_FILE"
