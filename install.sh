#!/bin/bash
set -e

APP_NAME="Sten"
REPO="vladstudio/sten"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

URL=$(curl -sL "https://api.github.com/repos/$REPO/releases/latest" \
  | grep browser_download_url | head -1 | cut -d'"' -f4)
curl -sL "$URL" -o "$TMP/$APP_NAME.zip"
unzip -q "$TMP/$APP_NAME.zip" -d "$TMP"

pkill -x "$APP_NAME" 2>/dev/null || true
rm -rf "/Applications/$APP_NAME.app"
mv "$TMP/$APP_NAME.app" /Applications/
open "/Applications/$APP_NAME.app"
echo "==> Installed $APP_NAME"
