#!/bin/sh
# Builds NotchIsland (Release), installs it to /Applications and launches it.
# Pass --zip to also create NotchIsland.zip on the Desktop for sharing.
set -eu

cd "$(dirname "$0")/.."

APP=build/Build/Products/Release/NotchIsland.app
DEST=/Applications/NotchIsland.app

echo "==> Building NotchIsland (Release)…"
if xcodebuild -version >/dev/null 2>&1; then
    # Whole-module optimization crashes the Swift compiler on this project
    # (Xcode 26), so the Release build is compiled without optimization.
    xcodebuild -project NotchIsland.xcodeproj -scheme NotchIsland \
        -configuration Release -derivedDataPath build \
        SWIFT_OPTIMIZATION_LEVEL=-Onone build -quiet
    APP=build/Build/Products/Release/NotchIsland.app
else
    echo "==> Building with swiftc (CommandLineTools)…"
    mkdir -p build/NotchIsland.app/Contents/MacOS build/NotchIsland.app/Contents/Resources
    cat << 'EOF' > build/NotchIsland.app/Contents/Info.plist
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>NotchIsland</string>
    <key>CFBundleDisplayName</key>
    <string>NotchIsland</string>
    <key>CFBundleIdentifier</key>
    <string>com.rifkal.NotchIsland</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1</string>
    <key>CFBundleExecutable</key>
    <string>NotchIsland</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSAppleEventsUsageDescription</key>
    <string>NotchIsland reads the current song from Spotify, Music and YouTube in your browser, and controls playback.</string>
    <key>NSCameraUsageDescription</key>
    <string>NotchIsland shows a live camera mirror in the Camera tab. Video is never recorded or sent anywhere.</string>
</dict>
</plist>
EOF
    echo "APPL????" > build/NotchIsland.app/Contents/PkgInfo
    if [ -d NotchIsland/Assets.xcassets/AppIcon.appiconset ]; then
        rm -rf /tmp/AppIcon.iconset
        cp -R NotchIsland/Assets.xcassets/AppIcon.appiconset /tmp/AppIcon.iconset
        iconutil -c icns /tmp/AppIcon.iconset -o build/NotchIsland.app/Contents/Resources/AppIcon.icns 2>/dev/null || true
        rm -rf /tmp/AppIcon.iconset
    fi
    SDK_PATH="/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk"
    if [ ! -d "$SDK_PATH" ]; then
        SDK_PATH="$(xcrun --show-sdk-path 2>/dev/null || echo '/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk')"
    fi
    swiftc -sdk "$SDK_PATH" $(find NotchIsland -name "*.swift") -o build/NotchIsland.app/Contents/MacOS/NotchIsland
    codesign --force --deep --sign - build/NotchIsland.app
    APP=build/NotchIsland.app
fi

echo "==> Installing to ${DEST}…"
pkill -x NotchIsland 2>/dev/null || true
sleep 1
rm -rf "$DEST"
cp -R "$APP" "$DEST"
# Refresh Launch Services so Spotlight and Finder pick up the new icon.
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$DEST"

if [ "${1:-}" = "--zip" ]; then
    echo "==> Creating ~/Desktop/NotchIsland.zip…"
    rm -f "$HOME/Desktop/NotchIsland.zip"
    ditto -c -k --keepParent "$DEST" "$HOME/Desktop/NotchIsland.zip"
fi

if [ "${1:-}" = "--dmg" ]; then
    echo "==> Creating build/NotchIsland.dmg…"
    rm -rf /tmp/dmg_source build/NotchIsland.dmg
    mkdir -p /tmp/dmg_source
    cp -R "$DEST" /tmp/dmg_source/
    ln -s /Applications /tmp/dmg_source/Applications
    hdiutil create -volname "NotchIsland" -srcfolder /tmp/dmg_source -ov -format UDZO build/NotchIsland.dmg
    rm -rf /tmp/dmg_source
fi

echo "==> Launching…"
open "$DEST"
echo "Done. Open it any time with Spotlight (⌘ Space, \"NotchIsland\")."
