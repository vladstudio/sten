#!/bin/bash
set -e

REPO="vladstudio/sten"
APP_NAME="Sten"
INSTALL_DIR="/Applications"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

info() { echo -e "${GREEN}==>${NC} $1"; }
warn() { echo -e "${YELLOW}==>${NC} $1"; }
error() { echo -e "${RED}Error:${NC} $1"; exit 1; }

# Check macOS
[[ "$(uname)" == "Darwin" ]] || error "This script only runs on macOS"

# Check Apple Silicon
[[ "$(uname -m)" == "arm64" ]] || error "This app requires Apple Silicon"

# Check macOS version (need 14+)
MACOS_VERSION=$(sw_vers -productVersion | cut -d. -f1)
[[ "$MACOS_VERSION" -ge 14 ]] || error "macOS 14 (Sonoma) or later required"

# Get latest release URL
info "Fetching latest release..."
DOWNLOAD_URL=$(curl -sL "https://api.github.com/repos/$REPO/releases/latest" \
    | grep "browser_download_url.*\.zip" \
    | cut -d '"' -f 4)

[[ -n "$DOWNLOAD_URL" ]] || error "Could not find release. Check https://github.com/$REPO/releases"

info "Downloading $APP_NAME..."
TMP_DIR=$(mktemp -d)
trap "rm -rf $TMP_DIR" EXIT

curl -sL "$DOWNLOAD_URL" -o "$TMP_DIR/$APP_NAME.zip"

info "Installing to $INSTALL_DIR..."
unzip -q "$TMP_DIR/$APP_NAME.zip" -d "$TMP_DIR"

# Quit running app and remove old version
pkill -x "$APP_NAME" 2>/dev/null || true
sleep 0.5
[[ -d "$INSTALL_DIR/$APP_NAME.app" ]] && rm -rf "$INSTALL_DIR/$APP_NAME.app"

mv "$TMP_DIR/$APP_NAME.app" "$INSTALL_DIR/"

# Remove quarantine (allows unsigned app to run)
xattr -dr com.apple.quarantine "$INSTALL_DIR/$APP_NAME.app" 2>/dev/null || true

info "Installed $APP_NAME.app"

echo ""
warn "Opening $APP_NAME... Follow the onboarding to grant permissions."
echo ""
echo "  If prompted about an unidentified developer:"
echo "  → Click 'Open' to proceed"
echo ""
echo "  You'll need to grant:"
echo "  1. Microphone access (click 'Allow' when prompted)"
echo "  2. Accessibility access (System Settings → Privacy & Security → Accessibility → enable $APP_NAME)"
echo ""

open "$INSTALL_DIR/$APP_NAME.app"
