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

echo "== No personal-use catalogue data in the repository =="
if git ls-files | grep -E '^catalog-local/' ; then echo "catalog-local must stay out of the repository"; exit 1; fi
if git ls-files -- '*.json' | xargs grep -il 'ikea' ; then echo "IKEA data must stay out of the repository"; exit 1; fi

echo "== Engine tests =="
(cd ios/PoltarKit && swift test -c release -Xswiftc -enable-testing)

echo "== Generate project =="
(cd ios && xcodegen generate --quiet)

echo "== App build (iOS Simulator, Debug) =="
xcodebuild -quiet -project ios/Poltar.xcodeproj -scheme Poltar \
  -configuration Debug -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath .build/DerivedData CODE_SIGNING_ALLOWED=NO build

echo "== App build (device, Debug): RoomPlan and ARKit paths only compile here =="
xcodebuild -quiet -project ios/Poltar.xcodeproj -scheme Poltar \
  -configuration Debug -destination 'generic/platform=iOS' \
  -derivedDataPath .build/DerivedData CODE_SIGNING_ALLOWED=NO build

if [ "${1:-}" = "--ui" ]; then
  echo "== Simulator walk-throughs =="
  xcodebuild -quiet -project ios/Poltar.xcodeproj -scheme Poltar \
    -destination "platform=iOS Simulator,name=${SIMULATOR:-iPhone 18 Pro}" \
    -derivedDataPath .build/DerivedData CODE_SIGNING_ALLOWED=NO test
fi

echo "CI passed"
