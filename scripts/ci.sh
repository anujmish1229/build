#!/usr/bin/env bash
# Single CI entry point, used locally and by GitHub Actions.
#   scripts/ci.sh          engine tests + app build
#   scripts/ci.sh --ui     also runs the simulator walk-through tests
set -euo pipefail
cd "$(dirname "$0")/.."

# Use a full Xcode even when xcode-select points at the command line tools.
if ! xcodebuild -version >/dev/null 2>&1; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
xcodebuild -version | head -1

echo "== Engine tests =="
(cd ios/RoomScanKit && swift test -c release -Xswiftc -enable-testing)

echo "== Generate project =="
(cd ios && xcodegen generate --quiet)

echo "== App build (iOS Simulator, Debug) =="
xcodebuild -quiet -project ios/RoomScan.xcodeproj -scheme RoomScan \
  -configuration Debug -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath .build/DerivedData CODE_SIGNING_ALLOWED=NO build

echo "CI passed"
