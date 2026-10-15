#!/bin/zsh
# Builds FloatingLyrics.app in ./build
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release
APP=build/FloatingLyrics.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/FloatingLyrics "$APP/Contents/MacOS/"
[[ -f Resources/AppIcon.icns ]] || scripts/make-icon.sh
mkdir -p "$APP/Contents/Resources"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>FloatingLyrics</string>
    <key>CFBundleDisplayName</key><string>Floating Lyrics</string>
    <key>CFBundleIdentifier</key><string>local.floatinglyrics</string>
    <key>CFBundleExecutable</key><string>FloatingLyrics</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleShortVersionString</key><string>0.3</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>15.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>LSUIElement</key><true/>
    <key>NSAppTransportSecurity</key><dict><key>NSAllowsLocalNetworking</key><true/></dict>
    <key>NSAppleEventsUsageDescription</key>
    <string>Floating Lyrics reads the current track from Music and Spotify to show its lyrics.</string>
</dict>
</plist>
PLIST

# Login-item helper for "launch with player"
HELPER="$APP/Contents/Library/LoginItems/FloatingLyricsHelper.app"
mkdir -p "$HELPER/Contents/MacOS"
cp .build/release/FloatingLyricsHelper "$HELPER/Contents/MacOS/"
cat > "$HELPER/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>FloatingLyricsHelper</string>
    <key>CFBundleIdentifier</key><string>local.floatinglyrics.helper</string>
    <key>CFBundleExecutable</key><string>FloatingLyricsHelper</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.3</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>15.0</string>
    <key>LSBackgroundOnly</key><true/>
</dict>
</plist>
PLIST

codesign --force --sign - "$HELPER"
codesign --force --sign - "$APP"
echo "Built $APP"
