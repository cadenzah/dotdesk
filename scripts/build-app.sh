#!/bin/sh
# Builds DotDesk.app into ./build (release, ad-hoc signed).
set -e
cd "$(dirname "$0")/.."
VERSION="${VERSION:-$(cat VERSION)}"
swift build -c release
APP=build/DotDesk.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/DotDesk "$APP/Contents/MacOS/DotDesk"
[ -f Resources/AppIcon.icns ] && cp Resources/AppIcon.icns "$APP/Contents/Resources/"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>DotDesk</string>
  <key>CFBundleDisplayName</key><string>DotDesk</string>
  <key>CFBundleIdentifier</key><string>dev.dotdesk.app</string>
  <key>CFBundleExecutable</key><string>DotDesk</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST
codesign --force --sign - "$APP" >/dev/null
echo "Built $APP"
