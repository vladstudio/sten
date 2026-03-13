#!/bin/bash
set -e

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

URL=$(curl -sL https://api.github.com/repos/vladstudio/sten/releases/latest \
  | grep browser_download_url | head -1 | cut -d'"' -f4)
curl -sL "$URL" -o "$TMP/Sten.zip"
unzip -q "$TMP/Sten.zip" -d "$TMP"

pkill -x Sten 2>/dev/null || true
rm -rf /Applications/Sten.app
mv "$TMP/Sten.app" /Applications/
xattr -dr com.apple.quarantine /Applications/Sten.app 2>/dev/null || true
open /Applications/Sten.app
echo "==> Installed Sten"
