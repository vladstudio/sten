#!/bin/bash
set -e
cd "$(dirname "$0")"
source ../scripts/build-kit.sh
build_app "Sten" \
  --info app/Sten/Info.plist \
  --resources "icons/*.png" \
  --entitlements app/Sten/Sten.entitlements
