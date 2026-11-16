#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
bash scripts/build-app.sh
APP="$PWD/dist/Sisyphus.app"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")
ARCH=$(uname -m)
cd dist
ARCHIVE="Sisyphus-$VERSION-macOS-$ARCH.zip"
ditto --norsrc --noextattr -c -k --keepParent "$APP" "$ARCHIVE"
shasum -a 256 "$ARCHIVE" > "$ARCHIVE.sha256"
printf '\nPackaged: %s\n' "$ARCHIVE"
