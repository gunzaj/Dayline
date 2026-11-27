#!/usr/bin/env bash
# Build and install Dayline into /Applications, then relaunch it.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

./scripts/build.sh

TARGET="/Applications/Dayline.app"

echo "==> installing to $TARGET"
osascript -e 'tell application "Dayline" to quit' >/dev/null 2>&1 || true
rm -rf "$TARGET"
cp -R "$ROOT/dist/Dayline.app" "$TARGET"

# Keep Launch Services honest about the new bundle.
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
  -f "$TARGET" >/dev/null 2>&1 || true

echo "==> launching"
open "$TARGET"

if [ ! -x "$HOME/Library/Application Support/Dayline/Garmin/venv/bin/python3" ]; then
  echo
  echo "Garmin is optional. To connect it, run once:"
  echo "  ./scripts/setup-garmin.sh"
fi

echo "==> installed $TARGET"
