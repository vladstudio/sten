#!/bin/bash
set -e
cd "$(dirname "$0")"

# Get current version from Info.plist
CURRENT=$(plutil -extract CFBundleShortVersionString raw app/Sten/Info.plist)
# Bump minor: 1.13 -> 1.14
MAJOR=${CURRENT%.*}
MINOR=${CURRENT##*.}
NEW="$MAJOR.$((MINOR + 1))"

echo "==> $CURRENT -> $NEW"

# Update Info.plist (both version fields)
plutil -replace CFBundleShortVersionString -string "$NEW" app/Sten/Info.plist
plutil -replace CFBundleVersion -string "$NEW" app/Sten/Info.plist

# Build
./build.sh

# Commit, tag, push
git add -A
git commit -m "v$NEW"
git push

# Zip and release
rm -f /tmp/Sten.zip
ditto -c -k --sequesterRsrc --keepParent /Applications/Sten.app /tmp/Sten.zip
gh release create "v$NEW" /tmp/Sten.zip --title "v$NEW" --notes ""
echo "==> Released v$NEW"
