#!/bin/bash
# Genera Resources/AppIcon.icns dal logo disegnato in SwiftUI (AppLogo).
set -e
cd "$(dirname "$0")"
[ -d MenuStats.app ] || ./build.sh
rm -rf build/AppIcon.iconset; mkdir -p build Resources
./MenuStats.app/Contents/MacOS/MenuStats --icon build/AppIcon.iconset
iconutil -c icns build/AppIcon.iconset -o Resources/AppIcon.icns
rm -rf build/AppIcon.iconset
echo "ok: Resources/AppIcon.icns"
