#!/usr/bin/env bash
# Build Dayline.app from the Swift package and ad-hoc sign it.
# Usage: scripts/build.sh [--debug]
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

CONFIG="release"
if [ "${1:-}" = "--debug" ]; then
  CONFIG="debug"
fi

APP_NAME="Dayline"
DIST="$ROOT/dist"
APP="$DIST/$APP_NAME.app"

echo "==> swift build -c $CONFIG"
swift build -c "$CONFIG"

BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"
if [ ! -x "$BIN_DIR/Dayline" ]; then
  echo "error: missing $BIN_DIR/Dayline" >&2
  exit 1
fi

echo "==> assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/garmin"

cp "$BIN_DIR/Dayline" "$APP/Contents/MacOS/Dayline"
chmod +x "$APP/Contents/MacOS/Dayline"

cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
plutil -lint "$APP/Contents/Info.plist" >/dev/null

for asset in Dayline.icns MenuBarIcon.png MenuBarIcon@2x.png; do
  if [ -f "$ROOT/Resources/$asset" ]; then
    cp "$ROOT/Resources/$asset" "$APP/Contents/Resources/$asset"
  fi
done

# The Garmin helper is read-only data run by the app. The Python venv lives in
# ~/Library/Application Support/Dayline and is created by scripts/setup-garmin.sh.
cp "$ROOT/scripts/garmin_helper.py" "$APP/Contents/Resources/garmin/garmin_helper.py"
cp "$ROOT/scripts/setup-garmin.sh" "$APP/Contents/Resources/garmin/setup-garmin.sh"

printf 'APPL????' > "$APP/Contents/PkgInfo"

echo "==> codesign (ad-hoc)"
codesign --force --sign - --deep "$APP" >/dev/null 2>&1 || {
  echo "warning: ad-hoc codesign failed; retrying without --deep" >&2
  codesign --force --sign - "$APP"
}

echo "==> built $APP"
codesign -dv "$APP" 2>&1 | sed -n '1,3p' || true
