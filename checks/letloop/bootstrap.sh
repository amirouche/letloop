#!/bin/bash
# Builds the Alpine-free bootstrap chain end to end and proves the
# result can compile a static binary:
#
#   1. bootstrap-toolchain    fetch-only: musl.cc's static native
#                              x86_64-linux-musl gcc/binutils/musl
#   2. bootstrap-shell        fetch-only: a static BusyBox binary
#   3. bootstrap-rootfs       assembles 1+2 into a scaffold rootfs
#   4. bootstrap-make         GNU make, from source, via its own
#                              build.sh (no make needed to build make)
#   5. bootstrap-busybox      BusyBox, from source
#   6. bootstrap-rootfs-final the rootfs downstream work should use:
#                              toolchain + 4 + 5, no prebuilt BusyBox
#   7. a hello.c derivation built against the scaffold rootfs, with no
#      Alpine and no host toolchain anywhere in its sandbox
#   8. bootstrap-chezscheme  ChezScheme 10.4.1, from source
#   9. bootstrap-letloop     letloop itself, from source, against it --
#                             a statically linked, relocatable letloop
#                             no distribution ever touched
#
# Steps 1 and 2 are the only two prebuilt binaries the chain trusts,
# both pinned by BLAKE3 (see each derivation's own header for the
# provenance and the reasoning). Step 5 is what retires the prebuilt
# BusyBox: after it, that binary is load-bearing only for step 3's
# assembly and for hosting steps 4 and 5 themselves, and its bytes
# appear in nothing the chain produces. The compiler cannot be retired
# the same way without a full source bootstrap, which this chain
# deliberately does not attempt.
#
# Step 3 is the one step that still needs a pre-existing rootfs to run
# its assembly script in -- see its header for why that is structural
# -- and this script supplies it as a fixture of symlinks into the
# host's own /usr, /bin, /lib rather than by downloading a
# distribution.
#
# Opt-in, NOT run by `make check`: fetches ~95 MB, compiles make and
# BusyBox from source, and needs bwrap.
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

# The from-source rootfs: same shape, but assembled out of components
# this chain compiled rather than fetched. Pulls in make and BusyBox
# through its own (derivation ...) inputs.
FINAL_DESTINATION=$("$LETLOOP" store build "$ROOT/checks/letloop/bootstrap-rootfs-final.derivation.scm" | tail -1)
echo "final rootfs: $FINAL_DESTINATION"

for tool in gcc make busybox sh; do
    test -e "$FINAL_DESTINATION/bin/$tool" || {
        echo "FAIL: no $tool in the final rootfs"
        exit 1
    }
done

# The prebuilt BusyBox must not have survived into it.
PREBUILT=$(echo "$LETLOOP_STORE"/*-bootstrap-shell/busybox)
if cmp -s "$FINAL_DESTINATION/bin/busybox" "$PREBUILT"; then
    echo "FAIL: final rootfs still carries the prebuilt busybox"
    exit 1
fi

# make is linked static like everything else here, so it runs from a
# store path directly rather than only from inside the rootfs.
"$FINAL_DESTINATION/bin/make" --version | grep -q "GNU Make" || {
    echo "FAIL: the from-source make does not run standalone"
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

# --- ChezScheme and letloop itself, with Alpine nowhere in sight ---
#
# The source tree is staged fresh each run rather than bind-mounted
# from the working directory: the build needs a writable copy, and a
# stale snapshot silently builds the wrong thing. Only tracked files,
# so local/ and other build output stay out of it.
rm -rf "$WORKDIR/letloop-src"
mkdir -p "$WORKDIR/letloop-src"
(cd "$ROOT" && git ls-files -z | tar --null -T - -cf -) | tar -xf - -C "$WORKDIR/letloop-src"

LETLOOP_DESTINATION=$("$LETLOOP" store build "$ROOT/checks/letloop/bootstrap-letloop.derivation.scm" | tail -1)
echo "letloop: $LETLOOP_DESTINATION"

readelf -l "$LETLOOP_DESTINATION/bin/letloop" | grep -qi 'interpreter' && {
    echo "FAIL: the bootstrap letloop needs a dynamic loader"
    exit 1
}

# It has to be a working letloop, not just one that prints a version:
# run it from a copy outside the store, on this host's own libc.
ELSEWHERE2=$(mktemp -d)
trap "rm -rf $ELSEWHERE $ELSEWHERE2" EXIT
cp -a "$LETLOOP_DESTINATION/." "$ELSEWHERE2/"

"$ELSEWHERE2/bin/letloop" version | grep -q "Chez Scheme Version" || {
    echo "FAIL: bootstrap letloop cannot report its version"
    exit 1
}

mkdir -p "$ELSEWHERE2/work"
cat > "$ELSEWHERE2/work/hi.scm" <<'SCM'
(library (hi)
  (export main)
  (import (chezscheme))
  (define (main . args) (display "bootstrap letloop works\n")))
SCM
EXEC_OUTPUT=$("$ELSEWHERE2/bin/letloop" exec "$ELSEWHERE2/work/" "$ELSEWHERE2/work/hi.scm" main)
[ "$EXEC_OUTPUT" = "bootstrap letloop works" ] || {
    echo "FAIL: bootstrap letloop cannot run a program: $EXEC_OUTPUT"
    exit 1
}

# And its own package manager runs -- the subsystem that produced it.
# Captured rather than piped: `letloop store` with no verb prints its
# usage and exits 1, which under `set -o pipefail` would fail the
# pipeline even though the output is exactly what is being asserted.
STORE_USAGE=$("$ELSEWHERE2/bin/letloop" store 2>&1 || true)
case "$STORE_USAGE" in
    *"letloop store build"*) ;;
    *) echo "FAIL: bootstrap letloop's store subcommand does not run: $STORE_USAGE"
       exit 1 ;;
esac

echo "=== All tests passed ==="
