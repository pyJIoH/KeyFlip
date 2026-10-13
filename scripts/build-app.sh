#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/module-cache"
swift build --product KeyFlip -c release --disable-sandbox --cache-path .build/cache --config-path .build/config --security-path .build/security
binary_dir=$(swift build -c release --show-bin-path --disable-sandbox --cache-path .build/cache --config-path .build/config --security-path .build/security)
app="$PWD/dist/KeyFlip.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$binary_dir/KeyFlip" "$app/Contents/MacOS/KeyFlip"
cp Resources/Info.plist "$app/Contents/Info.plist"
cp LICENSE "$app/Contents/Resources/LICENSE.txt"
/usr/bin/codesign --force --sign "${KEYFLIP_SIGN_IDENTITY:--}" "$app"
/usr/bin/codesign --verify --strict "$app"
printf 'Built %s\n' "$app"
