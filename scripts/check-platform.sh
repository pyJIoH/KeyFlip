#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ $# -gt 1 || ($# -eq 1 && "$1" != "--with-layouts") ]]; then
    printf 'Usage: bash scripts/check-platform.sh [--with-layouts]\n' >&2
    exit 2
fi

binary="dist/KeyFlip.app/Contents/MacOS/KeyFlip"
if [[ ! -x "$binary" ]]; then
    printf 'Build the app first: bash scripts/build-app.sh\n' >&2
    exit 1
fi

# Run in a logged-in macOS desktop session. These checks never post keys
# or use the general clipboard; they do not require Accessibility grants.
"$binary" --check-paste-events
"$binary" --check-clipboard
if [[ "${1:-}" == "--with-layouts" ]]; then
    "$binary" --check-layouts
fi
