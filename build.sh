#!/bin/bash
# Compila MenuStats.app. Serve solo Xcode Command Line Tools (xcode-select --install).
#   ./build.sh               per questo Mac
#   ./build.sh --universal   Apple Silicon + Intel, e crea MenuStats.zip da distribuire
set -e
cd "$(dirname "$0")"
APP=MenuStats.app
VERSION=0.1
rm -rf "$APP" build; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" build
BIN="$APP/Contents/MacOS/MenuStats"
compile() {   # compile <arch>
  clang -c -O2 -target $1-apple-macos14.2 CSupport/msupport.c -o build/msupport-$1.o
  xcrun swiftc -O -swift-version 5 -module-name MenuStats -target $1-apple-macos14.2 \
    -import-objc-header CSupport/msupport.h Sources/*.swift build/msupport-$1.o \
    -framework IOKit -framework CoreAudio -framework AudioToolbox -o build/MenuStats-$1
}
if [ "$1" = "--universal" ]; then
  compile arm64; compile x86_64
  lipo -create build/MenuStats-arm64 build/MenuStats-x86_64 -output "$BIN"
else
  compile "$(uname -m)"
  cp "build/MenuStats-$(uname -m)" "$BIN"
fi
[ -f Resources/AppIcon.icns ] && cp Resources/AppIcon.icns "$APP/Contents/Resources/"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>app.menustats</string>
  <key>CFBundleName</key><string>MenuStats</string>
  <key>CFBundleExecutable</key><string>MenuStats</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>LSUIElement</key><true/>
  <key>LSMinimumSystemVersion</key><string>14.2</string>
  <key>NSHumanReadableCopyright</key><string>Made by mdrzn</string>
  <key>NSAudioCaptureUsageDescription</key><string>MenuStats intercepts an app's sound only to change its volume. Nothing is recorded or saved.</string>
</dict></plist>
PLIST
codesign --force -s - "$APP"   # firma "ad hoc": basta per avviarla, non per Gatekeeper
rm -rf build
if [ "$1" = "--universal" ]; then
  rm -f MenuStats.zip; ditto -c -k --keepParent "$APP" MenuStats.zip
  echo "ok: $PWD/MenuStats.zip ($(lipo -archs "$BIN"))"
else
  echo "ok: $PWD/$APP"
fi
