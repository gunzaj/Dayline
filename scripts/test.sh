#!/usr/bin/env bash
# Behavioural checks plus a release build of both targets.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

echo "==> swift build"
swift build

echo "==> swift run dayline-checks"
swift run dayline-checks

echo "==> release build"
swift build -c release

echo "==> all checks passed"
