#!/bin/bash
set -e
cd "$(dirname "$0")"
source ../app-scripts/release-kit.sh
release_app "Sten" --info app/Sten/Info.plist
