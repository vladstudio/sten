#!/bin/bash
set -e
cd "$(dirname "$0")"

CURRENT=$(plutil -extract CFBundleShortVersionString raw app/Sten/Info.plist)
VERSION=${1:-${CURRENT%.*}.$((${CURRENT##*.} + 1))}
echo "==> $CURRENT -> $VERSION"

plutil -replace CFBundleShortVersionString -string "$VERSION" app/Sten/Info.plist
plutil -replace CFBundleVersion -string "$VERSION" app/Sten/Info.plist

./build.sh

git add app/Sten/Info.plist
git commit -m "v$VERSION"
git tag "v$VERSION"
git push --tags

ditto -c -k --sequesterRsrc --keepParent /Applications/Sten.app /tmp/Sten.zip
gh release create "v$VERSION" /tmp/Sten.zip --title "v$VERSION" --notes ""
echo "==> Released v$VERSION"
