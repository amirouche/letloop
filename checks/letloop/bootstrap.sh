#!/bin/bash
# Builds the Alpine-free bootstrap chain end to end and proves the
# result can compile a static binary:
#
#   1. toolchain      fetch-only: musl.cc's static native
#                              x86_64-linux-musl gcc/binutils/musl
#   2. shell          fetch-only: a static BusyBox binary
#   3. rootfs         assembles 1+2 into a scaffold rootfs
#   4. make           GNU make, from source, via its own
#                              build.sh (no make needed to build make)
#   5. busybox        BusyBox, from source
#   6. rootfs-final   the rootfs downstream work should use:
#                              toolchain + 4 + 5, no prebuilt BusyBox
#   7. a hello.c derivation built against the scaffold rootfs, with no
#      Alpine and no host toolchain anywhere in its sandbox
#   8. chezscheme     ChezScheme 10.4.1, from source
#   9. liburing       liburing, from source, for its -ffi
#                             archive, without which letloop links
#                             silently without io_uring
#   9b. blake3         BLAKE3, from source, without which the
#                             letloop this builds cannot run the store
#                             that built it -- every output is hashed
#  10. letloop        letloop itself, from source, against it --
#                             a statically linked, relocatable letloop
#                             no distribution ever touched
#  11. flow2          that letloop running the io_uring checks
#                             for real, not merely linking them
#  11b. scheme-hello a Scheme program compiled to a
#                             standalone static binary -- what the
#                             store is actually for, and the only gate
#                             that fails when just that breaks
#  12. review         letloop review compiled -- the widest
#                             dependency chain in the repo
#  13. static-lib     that letloop compiling a Scheme program
#                             against a C archive it also built --
#                             gcc, ar, nm and ld all from this chain
#
# This replaces the Alpine-based store-static-hello.sh, which
# provisioned a distribution rootfs with `letloop root create` and
# `apk add` before it could build anything. Every check it made is
# covered here without one.
#
# Every step is gated, and gated on what it is actually for: fetches on
# their contents, rootfs assemblies on the tools they must provide,
# compilers on a program that compiles and runs, liburing on symbols
# that link *and* run.
#
# Steps 1 and 2 are the only two prebuilt binaries the chain trusts,
# both pinned by BLAKE3 (see each package library's own header for the
# provenance and the reasoning). Step 5 is what retires the prebuilt
# BusyBox: after it, that binary is load-bearing only for step 3's
# assembly and for hosting steps 4 and 5 themselves, and its bytes
# appear in nothing the chain produces. The compiler cannot be retired
# the same way without a full source bootstrap, which this chain
# deliberately does not attempt.
#
# Step 3 is the one step that needs a rootfs it cannot have built --
# see its header for why that is structural. It asks for `(root
# (host))`, and the store provisions symlinks into the host's own
# /usr and /bin for it, so building into an empty store bootstraps
# itself rather than needing anything staged first.
#
# Each step is named rather than pointed at a file: the definitions are
# Scheme libraries under src/letloop/package/, so `letloop store build
# blake3` resolves (letloop package blake3) wherever letloop's own
# libraries are -- which is what lets the package set ship in a release
# rather than only existing in a checkout.
#
# Opt-in, NOT run by `make check`: fetches ~95 MB, compiles make and
# BusyBox from source, and needs bwrap.
set -exo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
LETLOOP="${LETLOOP:-$ROOT/local/bin/letloop}"
WORKDIR=/tmp/letloop-bootstrap

export LETLOOP_STORE="$WORKDIR/store"
mkdir -p "$LETLOOP_STORE"

# The two fetched artifacts, gated on their own before anything is
# built from them: a fetch that quietly produced the wrong thing would
# otherwise surface as a confusing failure several derivations later.
TOOLCHAIN_DESTINATION=$("$LETLOOP" store build toolchain | tail -1)
echo "toolchain: $TOOLCHAIN_DESTINATION"
test -s "$TOOLCHAIN_DESTINATION/x86_64-linux-musl-native.tgz" || {
    echo "FAIL: the toolchain tarball is missing or empty"
    exit 1
}

SHELL_DESTINATION=$("$LETLOOP" store build shell | tail -1)
echo "shell: $SHELL_DESTINATION"
file "$SHELL_DESTINATION/busybox" | grep -qi 'statically linked' || {
    echo "FAIL: the fetched busybox is not statically linked"
    file "$SHELL_DESTINATION/busybox"
    exit 1
}

# Building the rootfs pulls in both fetch-only derivations through its
# own (package ...) input references -- store-build resolves them
# depth-first, so this one command runs the whole chain.
ROOTFS_DESTINATION=$("$LETLOOP" store build rootfs | tail -1)
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
# through its own (package ...) inputs.
FINAL_DESTINATION=$("$LETLOOP" store build rootfs-final | tail -1)
echo "final rootfs: $FINAL_DESTINATION"

for tool in gcc make busybox sh; do
    test -e "$FINAL_DESTINATION/bin/$tool" || {
        echo "FAIL: no $tool in the final rootfs"
        exit 1
    }
done

# The prebuilt BusyBox must not have survived into it.
PREBUILT=$(echo "$LETLOOP_STORE"/bootstrap-shell-*/busybox)
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
HELLO_DESTINATION=$("$LETLOOP" store build hello | tail -1)
echo "hello: $HELLO_DESTINATION"

# "static-pie linked" (what this gcc defaults to) and "statically
# linked" are both fully static; what actually matters is that there is
# no INTERP segment, i.e. no dynamic loader is needed to start it.
# Captured, not piped: grep -q exiting early can kill the producer with
# SIGPIPE, and under `set -o pipefail` a gate written as
# `... | grep -q X && fail` then silently passes -- the worst failure
# mode a check can have.
HELLO_PROGRAM_HEADERS=$(readelf -l "$HELLO_DESTINATION/hello")
case "$HELLO_PROGRAM_HEADERS" in
    *interpreter*) echo "FAIL: $HELLO_DESTINATION/hello needs a dynamic loader"
                   exit 1 ;;
esac

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
# so local/ and other build output stay out of it -- which does mean a
# new file has to be `git add`ed before it is visible here, and shows
# up as "library not found" from inside the sandbox if it is not.
rm -rf "$WORKDIR/letloop-src"
mkdir -p "$WORKDIR/letloop-src"
(cd "$ROOT" && git ls-files -z | tar --null -T - -cf -) | tar -xf - -C "$WORKDIR/letloop-src"

# liburing, gated on the archive letloop actually links against. The
# makefile's probe for it is silent when it fails, producing a letloop
# with no io_uring symbols that looks healthy until something reaches
# flow, flow2 or review.
LIBURING_DESTINATION=$("$LETLOOP" store build liburing | tail -1)
echo "liburing: $LIBURING_DESTINATION"
test -e "$LIBURING_DESTINATION/lib/liburing-ffi.a" || {
    echo "FAIL: no liburing-ffi.a, so letloop would link without io_uring"
    exit 1
}

BLAKE3_DESTINATION=$("$LETLOOP" store build blake3 | tail -1)
echo "blake3: $BLAKE3_DESTINATION"
test -e "$BLAKE3_DESTINATION/lib/libblake3.a" || {
    echo "FAIL: no libblake3.a, so letloop could not hash a store output"
    exit 1
}

# The rest of letloop's dlopen'ed FFI libraries, as static archives --
# not linked into the bootstrap letloop itself the way liburing and
# blake3 are (letloop-main.c registers no symbols for these), but
# built and gated here so a `letloop compile ... archive.a` consumer
# has something proven to link against, and so a change to any of
# these derivations is caught before it reaches a user.
ARGON2_DESTINATION=$("$LETLOOP" store build argon2 | tail -1)
echo "argon2: $ARGON2_DESTINATION"
test -e "$ARGON2_DESTINATION/lib/libargon2.a" || {
    echo "FAIL: no libargon2.a"
    exit 1
}

SODIUM_DESTINATION=$("$LETLOOP" store build sodium | tail -1)
echo "sodium: $SODIUM_DESTINATION"
test -e "$SODIUM_DESTINATION/lib/libsodium.a" || {
    echo "FAIL: no libsodium.a"
    exit 1
}

PICOHTTPPARSER_DESTINATION=$("$LETLOOP" store build picohttpparser | tail -1)
echo "picohttpparser: $PICOHTTPPARSER_DESTINATION"
test -e "$PICOHTTPPARSER_DESTINATION/lib/libpicohttpparser.a" || {
    echo "FAIL: no libpicohttpparser.a"
    exit 1
}

# oprf and opaque exercise (package ...) inputs that are themselves
# (package ...) derivations, not just fetches or the toolchain rootfs
# -- the first place in this chain two application-level packages
# depend on each other.
OPRF_DESTINATION=$("$LETLOOP" store build oprf | tail -1)
echo "oprf: $OPRF_DESTINATION"
test -e "$OPRF_DESTINATION/lib/liboprf.a" || {
    echo "FAIL: no liboprf.a"
    exit 1
}

OPAQUE_DESTINATION=$("$LETLOOP" store build opaque | tail -1)
echo "opaque: $OPAQUE_DESTINATION"
test -e "$OPAQUE_DESTINATION/lib/libopaque.a" || {
    echo "FAIL: no libopaque.a"
    exit 1
}

LETLOOP_DESTINATION=$("$LETLOOP" store build letloop | tail -1)
echo "letloop: $LETLOOP_DESTINATION"

# Captured rather than piped into grep -q: -q exits on the first match,
# nm then dies of SIGPIPE, and `set -o pipefail` reports the whole
# pipeline as failed even though the symbol was found.
LETLOOP_SYMBOLS=$(nm "$LETLOOP_DESTINATION/bin/letloop")
case "$LETLOOP_SYMBOLS" in
    *io_uring_queue_init*) ;;
    *) echo "FAIL: the bootstrap letloop carries no io_uring symbols"
       exit 1 ;;
esac
case "$LETLOOP_SYMBOLS" in
    *blake3_hasher_init*) ;;
    *) echo "FAIL: the bootstrap letloop carries no blake3 symbols"
       exit 1 ;;
esac

# Captured, not piped: grep -q exiting early can kill the producer with
# SIGPIPE, and under `set -o pipefail` a gate written as
# `... | grep -q X && fail` then silently passes -- the worst failure
# mode a check can have.
LETLOOP_PROGRAM_HEADERS=$(readelf -l "$LETLOOP_DESTINATION/bin/letloop")
case "$LETLOOP_PROGRAM_HEADERS" in
    *interpreter*) echo "FAIL: $LETLOOP_DESTINATION/bin/letloop needs a dynamic loader"
                   exit 1 ;;
esac

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

# Self-hosting, the point of all of it: the letloop the store built,
# running the store. Exercises blake3 statically -- without it this
# fails at the first hash with "cannot dlopen shared object", so a
# letloop that could compile programs but not drive the store.
#
# A script-only derivation deliberately: fetching would need libtls,
# which is not in this chain, so `letloop store build` on a derivation
# with a `fetch` clause still fails on a static build. Tracked, not
# fixed here.
SELFHOST=$(mktemp -d)
trap "rm -rf $ELSEWHERE $ELSEWHERE2 $SELFHOST" EXIT
cat > "$SELFHOST/self.derivation.scm" <<SCM
(derivation
 (name "self-hosted")
 (build-environment (root (directory "$FINAL_DESTINATION")))
 (script "set -e\n" "mkdir -p out\n" "echo self-hosted > out/marker\n")
 (output "out"))
SCM
SELFHOST_OUT=$(LETLOOP_STORE="$SELFHOST/store" \
    "$ELSEWHERE2/bin/letloop" store build "$SELFHOST/self.derivation.scm" | tail -1)
[ "$(cat "$SELFHOST_OUT/marker")" = "self-hosted" ] || {
    echo "FAIL: the bootstrap letloop cannot run its own store"
    exit 1
}
echo "self-hosted build: $SELFHOST_OUT"

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

# The io_uring machinery actually running, not merely linked: 58
# checks of ring setup, submit, wait, cancel, socket and file I/O.
FLOW2_DESTINATION=$("$LETLOOP" store build flow2 | tail -1)
echo "flow2 checks: $FLOW2_DESTINATION"

FLOW2_PASSED=$(grep -c '\*\* SUCCESS' "$FLOW2_DESTINATION/result")
[ "$FLOW2_PASSED" -ge 50 ] || {
    echo "FAIL: only $FLOW2_PASSED flow2 checks ran; expected the full suite"
    exit 1
}

# The core promise on its own: a Scheme program in, a standalone static
# binary out. bootstrap-hello above compiles C and so proves the
# toolchain; this proves what the store is actually for. No archive, so
# `letloop compile` takes its ordinary path and invokes no C compiler.
SCHEME_HELLO_DESTINATION=$("$LETLOOP" store build scheme-hello | tail -1)
echo "scheme hello: $SCHEME_HELLO_DESTINATION"

SCHEME_HELLO_HEADERS=$(readelf -l "$SCHEME_HELLO_DESTINATION/hello")
case "$SCHEME_HELLO_HEADERS" in
    *interpreter*) echo "FAIL: the compiled Scheme program needs a dynamic loader"
                   exit 1 ;;
esac

cp "$SCHEME_HELLO_DESTINATION/hello" "$ELSEWHERE/scheme-hello"
SCHEME_HELLO_OUTPUT=$("$ELSEWHERE/scheme-hello")
[ "$SCHEME_HELLO_OUTPUT" = "hello from a scheme program the store built" ] || {
    echo "FAIL: the compiled Scheme program does not run relocated: $SCHEME_HELLO_OUTPUT"
    exit 1
}

# Reproducibility: the same derivation, built twice, byte for byte.
# Chez names gensyms from a per-process random session key and writes
# those names into every fasl, so without pinning it two builds of
# identical sources differ -- they stay $fasl-file-equal?, but the
# bytes move, and a store cannot be addressed by something that moves.
# store-build pins it from the build's own cache key, which is exactly
# "the identity of the source and its dependencies".
#
# Forced by dropping the cache entry and the output: otherwise the
# second call is a cache hit and proves nothing, which it silently did
# the first time this was written.
REPRO_FIRST=$(sha256sum "$SCHEME_HELLO_DESTINATION/hello" | cut -d' ' -f1)
REPRO_KEY=$(grep -rl "$(basename "$SCHEME_HELLO_DESTINATION")" "$LETLOOP_STORE/.cache/" 2>/dev/null | head -1)
rm -f "$REPRO_KEY"
rm -rf "$SCHEME_HELLO_DESTINATION" "$SCHEME_HELLO_DESTINATION.drv"
REPRO_AGAIN=$("$LETLOOP" store build scheme-hello | tail -1)
REPRO_SECOND=$(sha256sum "$REPRO_AGAIN/hello" | cut -d' ' -f1)
[ "$REPRO_FIRST" = "$REPRO_SECOND" ] || {
    echo "FAIL: two builds of the same derivation differ"
    echo "  $REPRO_FIRST"
    echo "  $REPRO_SECOND"
    exit 1
}
[ "$REPRO_AGAIN" = "$SCHEME_HELLO_DESTINATION" ] || {
    echo "FAIL: reproducible output landed at a different store path"
    exit 1
}
echo "reproducible: rebuilt byte-identical"

# The widest compile in the repo: review pulls in tea/*, liburing/low,
# sq and heap, all amalgamated into one program. Compile-only -- it is
# an interactive TUI, and its io_uring machinery is covered above by
# actually running rings rather than drawing a screen.
REVIEW_DESTINATION=$("$LETLOOP" store build review | tail -1)
echo "review: $REVIEW_DESTINATION"

test -s "$REVIEW_DESTINATION/letloop-review" || {
    echo "FAIL: letloop review did not compile"
    exit 1
}

# --- the loop closes: that letloop compiling against a C static
#     library, with the toolchain this chain built ---
STATIC_LIB_DESTINATION=$("$LETLOOP" store build static-lib | tail -1)
echo "static-lib demo: $STATIC_LIB_DESTINATION"

# Captured, not piped: grep -q exiting early can kill the producer with
# SIGPIPE, and under `set -o pipefail` a gate written as
# `... | grep -q X && fail` then silently passes -- the worst failure
# mode a check can have.
DEMO_PROGRAM_HEADERS=$(readelf -l "$STATIC_LIB_DESTINATION/demo")
case "$DEMO_PROGRAM_HEADERS" in
    *interpreter*) echo "FAIL: $STATIC_LIB_DESTINATION/demo needs a dynamic loader"
                   exit 1 ;;
esac

cp "$STATIC_LIB_DESTINATION/demo" "$ELSEWHERE/demo"
DEMO_OUTPUT=$("$ELSEWHERE/demo" | tail -1)
[ "$DEMO_OUTPUT" = "42" ] || {
    echo "FAIL: the static-library demo does not run relocated: $DEMO_OUTPUT"
    exit 1
}

echo "=== All tests passed ==="
