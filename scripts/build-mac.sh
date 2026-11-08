#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
export CLANG_MODULE_CACHE_PATH="/tmp/StickeyNoteModuleCache"
export SWIFTPM_MODULECACHE_OVERRIDE="/tmp/StickeyNoteModuleCache"
swift build -c release --scratch-path build/swift --cache-path /tmp/StickeyNoteSwiftCache --disable-sandbox
APP="build/Stickey Notes.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp build/swift/release/StickeyNote "$APP/Contents/MacOS/StickeyNote"
python3 scripts/package-info.py "$APP"
if [[ -f Assets/AppIcon.icns ]]; then cp Assets/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"; fi
codesign --force --sign - "$APP"
print "Built $PWD/$APP"
