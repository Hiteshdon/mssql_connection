#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   ./scripts/build-posix.sh /abs/path/to/third_party/freetds-1.5.4 /abs/path/to/outdir
#
# Builds a shared library:
#   Linux:  libsybdb.so      (and libtds.so, etc. as FreeTDS provides)
#   macOS:  libsybdb.dylib

SRC_DIR="$1"
OUT_DIR="$2"

mkdir -p "$OUT_DIR"
pushd "$SRC_DIR" >/dev/null

# Prefer autotools for POSIX (FreeTDS ships configure)
# Ensure clean and force-regenerate autotools files so make won't invoke versioned aclocal
ACLOCAL_EXTRA_ARGS=""
ICONV_M4_CANDIDATES=(
  "/usr/share/aclocal/iconv.m4"
  "/opt/homebrew/opt/gettext/share/aclocal/iconv.m4"
  "/usr/local/opt/gettext/share/aclocal/iconv.m4"
)
if command -v brew >/dev/null 2>&1; then
  GETTEXT_PREFIX="$(brew --prefix gettext 2>/dev/null || true)"
  if [ -n "$GETTEXT_PREFIX" ] && [ -d "$GETTEXT_PREFIX/share/aclocal" ]; then
    export ACLOCAL_PATH="$GETTEXT_PREFIX/share/aclocal${ACLOCAL_PATH:+:$ACLOCAL_PATH}"
    ACLOCAL_EXTRA_ARGS="-I $GETTEXT_PREFIX/share/aclocal"
  fi
fi
# Proactively vendor iconv.m4 into local m4/ to avoid search path issues on CI
mkdir -p m4
for CAND in "${ICONV_M4_CANDIDATES[@]}"; do
  if [ -f "$CAND" ]; then
    cp -f "$CAND" m4/iconv.m4
    break
  fi
done
autoreconf -fi $ACLOCAL_EXTRA_ARGS
chmod +x ./configure || true
[ -f Makefile ] && make distclean || true
rm -rf build-autotools && mkdir build-autotools && cd build-autotools

# Configure for shared libs under a local prefix within OUT_DIR
../configure \
  --prefix="$OUT_DIR/prefix" \
  --enable-shared \
  --disable-static \
  --disable-libiconv

make -j"$(sysctl -n hw.ncpu 2>/dev/null || nproc)"
make install

# Copy main runtime libs to OUT_DIR/lib for convenience
mkdir -p "$OUT_DIR/lib"
cp -a "$OUT_DIR/prefix/lib/"* "$OUT_DIR/lib/"

popd >/dev/null
echo "Built POSIX libs into: $OUT_DIR"
