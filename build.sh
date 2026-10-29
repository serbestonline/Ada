#!/bin/zsh
# Ada.app'i derler.
#   ./build.sh            → build/Ada.app
#   ./build.sh --install  → ayrıca /Applications altına kurar ve yeniden başlatır
set -euo pipefail
cd "$(dirname "$0")"

APP="build/Ada.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" build/AppIcon.iconset
swiftc -O -target arm64-apple-macos14.0 Sources/*.swift -o "$APP/Contents/MacOS/Ada"
swift scripts/make_icon.swift build/AppIcon-1024.png
for size in 16 32 128 256 512; do
    sips -z $size $size build/AppIcon-1024.png --out "build/AppIcon.iconset/icon_${size}x${size}.png" >/dev/null
    sips -z $((size * 2)) $((size * 2)) build/AppIcon-1024.png --out "build/AppIcon.iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns build/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>com.serbest.ada</string>
  <key>CFBundleName</key><string>Ada</string>
  <key>CFBundleExecutable</key><string>Ada</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
</dict></plist>
PLIST
codesign --force -s - "$APP"

if [[ "${1:-}" == "--install" ]]; then
    pkill -x Ada || true
    rm -rf /Applications/Ada.app
    cp -R "$APP" /Applications/Ada.app
    open -g /Applications/Ada.app
fi
