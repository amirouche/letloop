#!/bin/bash
# Builds the Alpine-free bootstrap chain end to end and proves the
# result can compile a static binary:
#
#   1. bootstrap-toolchain  fetch-only: musl.cc's static native
#                            x86_64-linux-musl gcc/binutils/musl tarball
#   2. bootstrap-shell      fetch-only: a static BusyBox binary
#   3. bootstrap-rootfs     assembles 1+2 into a usable rootfs
#   4. a hello.c derivation built *against* that rootfs, with no Alpine
#      and no host toolchain anywhere in its sandbox
#
# Steps 1 and 2 are the only two prebuilt binaries the chain trusts,
# both pinned by BLAKE3 (see each derivation's own header for the
# provenance and the reasoning). Step 3 is the one step that still
# needs a pre-existing rootfs to run its assembly script in -- see its
# header for why that is structural -- and this script supplies it as
# a fixture of symlinks into the host's own /usr, /bin, /lib rather
# than by downloading a distribution.
#
# Opt-in, NOT run by `make check`: fetches ~90 MB and needs bwrap.
set -exo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
LETLOOP="${LETLOOP:-$ROOT/local/bin/letloop}"
WORKDIR=/tmp/letloop-bootstrap
SCAFFOLD="$WORKDIR/host-scaffold"

export LETLOOP_STORE="$WORKDIR/store"
mkdir -p "$LETLOOP_STORE"

# The scaffold rootfs for step 3 only. Symlinks, not copies: nothing
# here is read by anything except that one assembly script, which uses
# the host's sh/tar/cp to unpack bytes it never inspects.
rm -rf "$SCAFFOLD"
mkdir -p "$SCAFFOLD"
for name in usr bin sbin lib lib64 etc; do
    if [ -e "/$name" ]; then ln -s "/$name" "$SCAFFOLD/$name"; fi
done

# Building the rootfs pulls in both fetch-only derivations through its
# own (derivation ...) input references -- store-build resolves them
# depth-first, so this one command runs the whole chain.
ROOTFS_DESTINATION=$("$LETLOOP" store build "$ROOT/checks/letloop/bootstrap-rootfs.derivation.scm" | tail -1)
echo "bootstrap rootfs: $ROOTFS_DESTINATION"

test -x "$ROOTFS_DESTINATION/bin/gcc" || {
    echo "FAIL: no gcc in the assembled rootfs"
    exit 1
}
test -e "$ROOTFS_DESTINATION/bin/sh" || {
    echo "FAIL: no sh in the assembled rootfs"
    exit 1
}

# The real milestone: a derivation whose build-environment is the
# assembled rootfs itself, compiling C with nothing from Alpine or from
# the host in its sandbox.
HELLO_DESTINATION=$("$LETLOOP" store build "$ROOT/checks/letloop/bootstrap-hello.derivation.scm" | tail -1)
echo "hello: $HELLO_DESTINATION"

# "static-pie linked" (what this gcc defaults to) and "statically
# linked" are both fully static; what actually matters is that there is
# no INTERP segment, i.e. no dynamic loader is needed to start it.
readelf -l "$HELLO_DESTINATION/hello" | grep -qi 'interpreter' && {
    echo "FAIL: $HELLO_DESTINATION/hello needs a dynamic loader"
    file "$HELLO_DESTINATION/hello"
    exit 1
}

# Relocatability, same bar the Alpine-based smoke test holds its own
# outputs to: run it outside the store and outside any sandbox.
ELSEWHERE=$(mktemp -d)
trap "rm -rf $ELSEWHERE" EXIT
cp "$HELLO_DESTINATION/hello" "$ELSEWHERE/hello"
OUTPUT=$("$ELSEWHERE/hello")
[ "$OUTPUT" = "hello from the bootstrap toolchain" ] || {
    echo "FAIL: unexpected output: $OUTPUT"
    exit 1
}

echo "=== All tests passed ==="
