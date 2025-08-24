#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   ANDROID_NDK=<path> ./scripts/build-android.sh /abs/path/to/third_party/freetds-1.5.4 /abs/path/to/outdir "arm64-v8a armeabi-v7a x86_64"
#
# Produces:
#   $OUT_DIR/<ABI>/libsybdb.so

SRC_DIR="$1"
OUT_DIR="$2"
ABIS="${3:-arm64-v8a}"

: "${ANDROID_NDK:?ANDROID_NDK env var must be set}"

mkdir -p "$OUT_DIR"

for ABI in $ABIS; do
  BUILD_DIR="$OUT_DIR/build-$ABI"
  rm -rf "$BUILD_DIR" && mkdir -p "$BUILD_DIR"
  pushd "$BUILD_DIR" >/dev/null

  cmake "$SRC_DIR" \
    -DCMAKE_TOOLCHAIN_FILE="$ANDROID_NDK/build/cmake/android.toolchain.cmake" \
    -DANDROID_ABI="$ABI" \
    -DANDROID_PLATFORM=21 \
    -DBUILD_SHARED_LIBS=ON \
    -DCMAKE_BUILD_TYPE=Release

  cmake --build . --config Release -j

  # Find produced libs (libsybdb* usually)
  mkdir -p "$OUT_DIR/$ABI"
  find . -name "lib*.so" -maxdepth 3 -print -exec cp {} "$OUT_DIR/$ABI/" \;

  popd >/dev/null
done

echo "Built Android libs into: $OUT_DIR/<ABI>"
