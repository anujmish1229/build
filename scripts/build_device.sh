#!/usr/bin/env bash
# Builds a signed copy of the app for your own phone. Nothing here is for publication.
#   scripts/build_device.sh            build and sign
#   scripts/build_device.sh --install  also install on the connected iPhone
# The signing team comes from your keychain, or set DEVELOPMENT_TEAM to choose one.
set -euo pipefail
cd "$(dirname "$0")/.."

if ! xcodebuild -version >/dev/null 2>&1; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

TEAM="${DEVELOPMENT_TEAM:-}"
if [ -z "$TEAM" ]; then
  TEAM=$(security find-certificate -c "Apple Development" -p 2>/dev/null \
    | openssl x509 -noout -subject 2>/dev/null | sed -nE 's/.*OU ?= ?([A-Z0-9]{10}).*/\1/p' | head -1)
fi
if [ -z "$TEAM" ]; then
  echo "No Apple Development certificate found. Add your Apple ID in Xcode > Settings > Accounts, or set DEVELOPMENT_TEAM." >&2
  exit 1
fi

(cd ios && xcodegen generate --quiet)
xcodebuild -quiet -project ios/Poltar.xcodeproj -scheme Poltar -configuration Release \
  -destination 'generic/platform=iOS' -derivedDataPath .build/DeviceBuild \
  -allowProvisioningUpdates DEVELOPMENT_TEAM="$TEAM" CODE_SIGN_STYLE=Automatic build

APP=.build/DeviceBuild/Build/Products/Release-iphoneos/Poltar.app
codesign --verify --deep --strict "$APP"
echo "Signed: $APP"

if [ "${1:-}" = "--install" ]; then
  DEVICE=$(xcrun devicectl list devices 2>/dev/null | awk '/iPhone/ && /connected|available \(paired\)/ {for (i=1;i<=NF;i++) if ($i ~ /^[0-9A-F]{8}-[0-9A-F]{16}$/) {print $i; exit}}')
  if [ -z "$DEVICE" ]; then
    echo "No iPhone connected. Plug it in, unlock it, and run this again." >&2
    exit 1
  fi
  xcrun devicectl device install app --device "$DEVICE" "$APP"
  echo "Installed on $DEVICE"
fi
