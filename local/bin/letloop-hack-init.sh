#!/bin/sh

set -ex

if test "x$LETLOOP_PREFIX" = "x"; then
    echo ""
    echo "  You need to be in the loop; at the top of the repository run:"
    echo ""
    echo "    ./venv"
    echo ""
    exit 1
fi

SOURCES="$LETLOOP_PREFIX/src/"
LIBRARIES="$LETLOOP_PREFIX/lib/"

mkdir -p $SOURCES
mkdir -p $LIBRARIES

# Install blake3, assume amd64.

rm -rf "$SOURCES/blake3"

git clone --depth=1 https://github.com/BLAKE3-team/BLAKE3 "$SOURCES/blake3"
cd "$SOURCES/blake3/c/"
gcc -shared -O3 -o libblake3.so blake3.c blake3_dispatch.c blake3_portable.c blake3_sse2_x86-64_unix.S blake3_sse41_x86-64_unix.S blake3_avx2_x86-64_unix.S blake3_avx512_x86-64_unix.S
cp libblake3.so $LIBRARIES
