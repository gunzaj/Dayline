#!/usr/bin/env bash
# One-time setup for the Garmin helper. Creates a private virtualenv inside
# Dayline's Application Support folder and installs a pinned garminconnect.
#
#   ./scripts/setup-garmin.sh
#
# Re-run after Garmin changes its login and a newer pin is available.
set -euo pipefail

PIN="0.3.20"
SUPPORT="$HOME/Library/Application Support/Dayline/Garmin"
VENV="$SUPPORT/venv"

find_python() {
  for candidate in python3.14 python3.13 python3.12 /opt/homebrew/bin/python3.13 /usr/local/bin/python3.13; do
    if command -v "$candidate" >/dev/null 2>&1; then
      if "$candidate" -c 'import sys; raise SystemExit(0 if sys.version_info >= (3,12) else 1)' 2>/dev/null; then
        command -v "$candidate"
        return 0
      fi
    elif [ -x "$candidate" ]; then
      if "$candidate" -c 'import sys; raise SystemExit(0 if sys.version_info >= (3,12) else 1)' 2>/dev/null; then
        echo "$candidate"
        return 0
      fi
    fi
  done
  return 1
}

if ! PY="$(find_python)"; then
  echo "Garmin needs Python 3.12 or newer. Installing it with Homebrew…"
  if ! command -v brew >/dev/null 2>&1; then
    echo "error: install Python 3.12+ first, or install Homebrew and run this again." >&2
    exit 1
  fi
  brew install python@3.13
  PY="/opt/homebrew/bin/python3.13"
fi

echo "Using $PY"
mkdir -p "$SUPPORT"
if [ ! -x "$VENV/bin/python3" ]; then
  "$PY" -m venv "$VENV"
fi

"$VENV/bin/python3" -m pip install --quiet --upgrade pip
"$VENV/bin/python3" -m pip install --quiet "garminconnect==$PIN"

echo "Garmin helper ready. Pinned garminconnect $PIN in $VENV"
"$VENV/bin/python3" -c 'import garminconnect; print("import ok")'
