#!/bin/sh
# Builds NotchIsland (Release), installs it to /Applications and launches it.
# Pass --zip to also create NotchIsland.zip on the Desktop for sharing.
set -eu

cd "$(dirname "$0")/.."

APP=build/Build/Products/Release/NotchIsland.app
DEST=/Applications/NotchIsland.app

echo "==> Building NotchIsland (Release)…"
# Whole-module optimization crashes the Swift compiler on this project
# (Xcode 26), so the Release build is compiled without optimization.
xcodebuild -project NotchIsland.xcodeproj -scheme NotchIsland \
    -configuration Release -derivedDataPath build \
    SWIFT_OPTIMIZATION_LEVEL=-Onone build -quiet

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

echo "==> Launching…"
open "$DEST"
echo "Done. Open it any time with Spotlight (⌘ Space, \"NotchIsland\")."
