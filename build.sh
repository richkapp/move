#!/bin/bash
# Builds Move.app in a temp folder and installs it to ~/Applications (single copy, no Spotlight duplicate).
set -euo pipefail
cd "$(dirname "$0")"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
APP="$TMP/Move.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Move</string>
  <key>CFBundleDisplayName</key><string>Move</string>
  <key>CFBundleIdentifier</key><string>com.richkapp.move</string>
  <key>CFBundleExecutable</key><string>Move</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.1</string>
  <key>CFBundleVersion</key><string>2</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
</dict></plist>
PLIST
swift make-icon.swift "$TMP/AppIcon.iconset"
iconutil -c icns "$TMP/AppIcon.iconset" -o "$APP/Contents/Resources/AppIcon.icns"
swiftc -O -parse-as-library -target arm64-apple-macos14 Move.swift -o "$APP/Contents/MacOS/Move"
codesign --force --sign - "$APP"
pkill -x Move 2>/dev/null || true
mkdir -p ~/Applications
rm -rf ~/Applications/Move.app
cp -R "$APP" ~/Applications/
touch ~/Applications/Move.app
open ~/Applications/Move.app
echo "Installed and launched ~/Applications/Move.app"
