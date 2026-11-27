#!/usr/bin/env bash
# Package dist/Dayline.app as a disk image with a drag-to-Applications layout.
# Usage: scripts/make-dmg.sh   (builds the app first)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

./scripts/build.sh

APP="$ROOT/dist/Dayline.app"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
ARCH="$(lipo -archs "$APP/Contents/MacOS/Dayline" | tr ' ' '-')"
DMG="$ROOT/dist/Dayline-$VERSION-$ARCH.dmg"

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

echo "==> staging"
ditto "$APP" "$STAGE/Dayline.app"
ln -s /Applications "$STAGE/Applications"

echo "==> creating $DMG"
rm -f "$DMG"
hdiutil create -volname "Dayline $VERSION" -srcfolder "$STAGE" \
  -fs HFS+ -format UDZO -imagekey zlib-level=9 -quiet "$DMG"

# Sign the image itself (ad-hoc), so its contents cannot change unnoticed.
codesign --force --sign - "$DMG" >/dev/null 2>&1 || true

echo "==> built $DMG"
shasum -a 256 "$DMG"
