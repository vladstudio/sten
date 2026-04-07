#!/bin/bash
set -e
cd "$(dirname "$0")"
source ../scripts/build-kit.sh
build_app "Sten" \
  --info app/Sten/Info.plist \
  --resources "icons/*.png" "icons/AppIcon.icns" \
  --entitlements app/Sten/Sten.entitlements
