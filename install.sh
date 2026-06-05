#!/bin/bash
set -euo pipefail

APP_NAME="Sten"
REPO="vladstudio/sten"
ASSET_NAME="$APP_NAME.zip"
INSTALL_DIR="/Applications"
APP_PATH="$INSTALL_DIR/$APP_NAME.app"


die() { echo "Error: $*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "$1 is required but was not found"; }
run_privileged() {
  if [ -w "$INSTALL_DIR" ]; then
    "$@"
  else
    sudo "$@"
  fi
}

need curl
need ditto
need codesign
need plutil

TMP=$(mktemp -d)
BACKUP="$TMP/$APP_NAME.backup.app"
cleanup() {
  local status=$?
  set +e
  if [ $status -ne 0 ] && [ -d "$BACKUP" ]; then
    echo "==> Restoring previous $APP_NAME"
    run_privileged rm -rf "$APP_PATH"
    run_privileged mv "$BACKUP" "$APP_PATH"
  fi
  rm -rf "$TMP"
  exit $status
}
trap cleanup EXIT
ZIP_PATH="$TMP/$ASSET_NAME"
EXTRACT_DIR="$TMP/extract"
EXTRACTED_APP="$EXTRACT_DIR/$APP_NAME.app"

mkdir -p "$EXTRACT_DIR"

echo "==> Downloading $APP_NAME"
curl -fL --retry 3 --progress-bar "https://github.com/$REPO/releases/latest/download/$ASSET_NAME" -o "$ZIP_PATH"

echo "==> Extracting"
ditto -x -k "$ZIP_PATH" "$EXTRACT_DIR"

[ -d "$EXTRACTED_APP" ] || die "Downloaded archive did not contain $APP_NAME.app"
[ -f "$EXTRACTED_APP/Contents/Info.plist" ] || die "Downloaded app bundle is missing Info.plist"
BUNDLE_NAME=$(plutil -extract CFBundleName raw -o - "$EXTRACTED_APP/Contents/Info.plist" 2>/dev/null || true)
[ "$BUNDLE_NAME" = "$APP_NAME" ] || die "Downloaded app bundle has unexpected name: ${BUNDLE_NAME:-missing}"

codesign --verify --strict --verbose=2 "$EXTRACTED_APP"
if command -v spctl >/dev/null 2>&1; then
  spctl -a -t exec -vv "$EXTRACTED_APP" || die "Gatekeeper rejected $APP_NAME"
fi

echo "==> Installing to $INSTALL_DIR"
pkill -x "$APP_NAME" 2>/dev/null || true
[ ! -d "$APP_PATH" ] || run_privileged mv "$APP_PATH" "$BACKUP"
run_privileged ditto "$EXTRACTED_APP" "$APP_PATH" || {
  run_privileged rm -rf "$APP_PATH"
  die "Install failed"
}
run_privileged rm -rf "$BACKUP"

open "$APP_PATH"
echo "==> Installed $APP_NAME"
