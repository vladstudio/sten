#!/bin/bash
set -e
cd "$(dirname "$0")"

WHISPER=app/lib/whisper.cpp
BUILD=$WHISPER/build

rm -rf app/build app/Sten.app
mkdir -p app/build app/Sten.app/Contents/MacOS app/Sten.app/Contents/Resources

swiftc -O -target arm64-apple-macosx13.0 \
    -I $WHISPER/include -I $WHISPER/ggml/include \
    $BUILD/src/libwhisper.a \
    $BUILD/ggml/src/libggml.a \
    $BUILD/ggml/src/libggml-base.a \
    $BUILD/ggml/src/libggml-cpu.a \
    $BUILD/ggml/src/ggml-metal/libggml-metal.a \
    $BUILD/ggml/src/ggml-blas/libggml-blas.a \
    -framework Accelerate -framework Metal -framework Foundation -lc++ \
    -o app/build/Sten \
    app/Sten/*.swift

cp app/build/Sten app/Sten.app/Contents/MacOS/
cp app/Sten/Info.plist app/Sten.app/Contents/
cp icons/*.png icons/*.icns app/Sten.app/Contents/Resources/ 2>/dev/null || true
touch app/Sten.app
echo "✓ Built Sten.app"

rm -rf /Applications/Sten.app
mv app/Sten.app /Applications/
open /Applications/Sten.app
