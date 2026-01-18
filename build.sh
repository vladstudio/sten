#!/bin/bash
set -e
cd "$(dirname "$0")"

rm -rf app/build app/Sten.app .build
mkdir -p app/Sten.app/Contents/MacOS app/Sten.app/Contents/Resources

swift build -c release

cp .build/release/Sten app/Sten.app/Contents/MacOS/
cp app/Sten/Info.plist app/Sten.app/Contents/
cp icons/*.png icons/*.icns app/Sten.app/Contents/Resources/ 2>/dev/null || true
touch app/Sten.app

# Sign if certificate exists
if security find-identity -v | grep -q "Sten Signing"; then
    codesign --force --deep --sign "Sten Signing" app/Sten.app
    echo "✓ Built and signed Sten.app"
else
    echo "✓ Built Sten.app (unsigned)"
fi

rm -rf /Applications/Sten.app
mv app/Sten.app /Applications/
open /Applications/Sten.app
