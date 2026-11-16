#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
bash scripts/swift-local.sh build -c release --product Sisyphus
APP="$PWD/dist/Sisyphus.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Sisyphus "$APP/Contents/MacOS/Sisyphus"
cp Resources/Info.plist "$APP/Contents/Info.plist"
if [ -f Resources/AppIcon.icns ]; then cp Resources/AppIcon.icns "$APP/Contents/Resources/"; fi
if [ -d Resources/Characters ]; then ditto Resources/Characters "$APP/Contents/Resources/Characters"; fi
SIGNING_IDENTITY="${CODESIGN_IDENTITY:--}"
codesign --force --sign "$SIGNING_IDENTITY" "$APP"
codesign --verify --deep --strict "$APP"
if [ "$SIGNING_IDENTITY" = - ]; then
  printf '\nLocal ad-hoc build: a changed build has a new identity. Existing screen-recording grants may need refreshing. Set CODESIGN_IDENTITY to your Apple signing certificate for stable development builds.\n'
fi
printf '\nBuilt: %s\n' "$APP"
