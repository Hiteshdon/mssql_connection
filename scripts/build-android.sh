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

  # Work around Android lacking system iconv: force-disable HAVE_ICONV in generated config.h
  # so FreeTDS uses its internal replacements instead of system iconv.
  CONFIG_H="$BUILD_DIR/include/config.h"
  if [ -f "$CONFIG_H" ]; then
    # Replace a strict match to avoid unintended changes
    sed -i.bak -e 's/^#define HAVE_ICONV 1$/#undef HAVE_ICONV/' "$CONFIG_H" || true
  fi

  # Build only dblib and ct targets to avoid compiling ODBC (which needs unixODBC/iODBC headers)
  cmake --build . --config Release --target sybdb db-lib ct -j

  # Find produced libs (libsybdb and its dependencies)
  mkdir -p "$OUT_DIR/$ABI"
  find . -name "lib*.so" -maxdepth 3 -print -exec cp {} "$OUT_DIR/$ABI/" \;

  popd >/dev/null
done

echo "Built Android libs into: $OUT_DIR/<ABI>"
