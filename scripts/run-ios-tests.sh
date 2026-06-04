#!/usr/bin/env bash
# Generate the Xcode project and run the iOS companion tests on Simulator.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

bash scripts/generate.sh

DESTINATION="${IOS_TEST_DESTINATION:-platform=iOS Simulator,name=iPhone 17}"
DERIVED_DATA="${IOS_DERIVED_DATA_PATH:-/tmp/Codex-stats-ios-build}"

xcodebuild test \
  -project ClaudeStats.xcodeproj \
  -scheme "ClaudeStats iOS" \
  -destination "$DESTINATION" \
  -derivedDataPath "$DERIVED_DATA"
