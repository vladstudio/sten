#!/bin/bash
set -e
cd "$(dirname "$0")"

swift build -c release

APP=app/Sten.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Sten "$APP/Contents/MacOS/"
cp app/Sten/Info.plist "$APP/Contents/"
cp icons/*.png icons/*.icns "$APP/Contents/Resources/" 2>/dev/null || true
touch "$APP"

# Sign if certificate exists
if security find-identity -v | grep -q "Sten Signing"; then
    codesign --force --deep --sign "Sten Signing" "$APP"
    echo "==> Built and signed Sten.app"
else
    echo "==> Built Sten.app (unsigned)"
fi

rm -rf /Applications/Sten.app
mv "$APP" /Applications/
open /Applications/Sten.app
