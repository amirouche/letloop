#!/bin/bash
# End-to-end smoke test for `letloop store build`: statically compile
# four targets inside a network-off, musl/Alpine sandbox, and prove
# the resulting binaries are relocatable, statically linked executables
# -- not just something that happens to run inside its own build
# sandbox. In increasing order of ambition:
#   1. hello.scm, a trivial inline example.
#   2. letloop review, the largest real subsystem in this repo
#      (compile-only -- see store-review-static.derivation.scm's own
#      header comment for why it is not run).
#   3. (letloop liburing low)'s own checks, actually run (not just
#      compiled) statically -- real io_uring ring setup, submit,
#      wait, cancel, socket and file ops.
#   4. letloop itself, producing a self-hosting distribution named
#      letloop-musl-static.
#
# This is opt-in, NOT run by `make check`: provisioning builds
# ChezScheme + letloop from source inside an Alpine container, a
# multi-minute, network-heavy operation (see CLAUDE.md's own
# first-time-setup timing), unlike every other check under checks/.
set -exo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
LETLOOP="${LETLOOP:-$ROOT/local/bin/letloop}"
WORKDIR=/tmp/letloop-store-check
ROOTFS="$WORKDIR/alpine-buildenv"

mkdir -p "$WORKDIR"

# --- Provision the build-environment rootfs (network-enabled, out-of-band) ---
#
# A bare Alpine rootfs has neither a compiler nor a working letloop,
# and the sandboxed build step itself is --unshare-net, so toolchain
# provisioning happens once here, before any derivation is built.
if [ ! -x "$ROOTFS/usr/local/bin/letloop" ]; then
    mkdir -p "$ROOTFS"
    "$LETLOOP" root create alpine 3.22 amd64 "$ROOTFS"
    # bash is required: the project's own makefile hardcodes
    # SHELL=/bin/bash, and a bare Alpine build-base has only busybox sh.
    # git is required: `make chezscheme` clones ChezScheme's source.
    # util-linux-dev provides libuuid, which `make letloop`'s link step
    # needs (-luuid) -- this matches README.md's own documented Alpine
    # build dependency line. coreutils is required too: busybox's `ln`
    # has no GNU -r (relative) flag, and the makefile's install step
    # uses `ln -srf` -- under busybox that call silently no-ops (prints
    # usage to stderr, exits nonzero, but the recipe's `;`-joined shell
    # keeps going), leaving local/bin/letloop never created.
    # liburing-dev + linux-headers let `make letloop` statically link
    # (letloop liburing low)'s ~170 io_uring_* symbols (see
    # src/letloop/store/README.md's liburing section) -- optional in
    # the sense that the makefile probes for them and skips silently
    # if absent, but needed here since store-review-static.derivation
    # and store-letloop-musl-static.derivation both exercise that path.
    "$LETLOOP" root exec "$ROOTFS" / -- \
        sh -c 'apk add --no-cache build-base bash git util-linux-dev coreutils liburing-dev linux-headers'
    # `letloop root exec` always bind-mounts the invoker's own cwd at
    # /mnt/host -- building directly there would run `make chezscheme`
    # / `make letloop` (which `rm -rf`s and repopulates ./local) against
    # THIS repo checkout's own ./local, clobbering the host-side build.
    # Copy the source into the rootfs first so the Alpine build is
    # fully isolated from the host's own working tree.
    "$LETLOOP" root exec "$ROOTFS" / -- \
        sh -c 'rm -rf /root/letloop-src && cp -a /mnt/host /root/letloop-src && rm -rf /root/letloop-src/local /root/letloop-src/a.out /root/letloop-src/a.out.boot'
    "$LETLOOP" root exec "$ROOTFS" /root/letloop-src -- \
        sh -c 'export PATH="$(pwd)/local/bin:$PATH" && make chezscheme && export SCHEME="$(which scheme)" && make letloop'
    # Copy the whole install tree (bin/ + lib/), not just the letloop
    # binary: letloop-library-path! resolves (letloop cli base) and
    # every other (letloop ...) library relative to a sibling
    # lib/letloop/src next to the running binary (see CLAUDE.md's
    # install layout) -- a bare binary copy can run `letloop version`
    # but not `letloop compile`/`letloop exec`, which both need
    # (letloop cli base) to parse their own arguments. cp -a (not -L)
    # preserves bin/letloop's relative symlink into lib/csv.../letloop.
    "$LETLOOP" root exec "$ROOTFS" / -- \
        sh -c 'rm -f /usr/local/bin/letloop && mkdir -p /usr/local/bin /usr/local/lib && cp -a /root/letloop-src/local/bin/. /usr/local/bin/ && cp -a /root/letloop-src/local/lib/. /usr/local/lib/'
fi

# --- 1. hello.scm: build, static-link check, relocatability check ---
export LETLOOP_STORE="$WORKDIR/store"
# letloop compile's own progress lines ("compiling ...", "Produced:
# ./a.out") go to stdout too, ahead of store-build's final printed
# store path -- only the last line is the path itself.
DESTINATION=$("$LETLOOP" store build "$ROOT/checks/letloop/store-static-hello.derivation.scm" | tail -1)
echo "store path: $DESTINATION"

file "$DESTINATION/hello" | grep -qi 'statically linked' || {
    echo "FAIL: $DESTINATION/hello is not statically linked"
    file "$DESTINATION/hello"
    exit 1
}

# A static binary that only happens to run inside its build sandbox
# doesn't satisfy the relocatability requirement; it must run
# unmodified, copied anywhere, with zero dependency on the store
# layout or the sandbox.
ELSEWHERE=$(mktemp -d)
trap "rm -rf $ELSEWHERE" EXIT
cp "$DESTINATION/hello" "$ELSEWHERE/hello"
OUTPUT=$("$ELSEWHERE/hello")
[ "$OUTPUT" = "hello, letloop store" ] || {
    echo "FAIL: unexpected output: $OUTPUT"
    exit 1
}

# --- 2. letloop review: build, static-link check only (not run -- see
#        store-review-static.derivation.scm's header comment) ---
REVIEW_DESTINATION=$("$LETLOOP" store build "$ROOT/checks/letloop/store-review-static.derivation.scm" | tail -1)
echo "store path: $REVIEW_DESTINATION"

file "$REVIEW_DESTINATION/letloop-review" | grep -qi 'statically linked' || {
    echo "FAIL: $REVIEW_DESTINATION/letloop-review is not statically linked"
    file "$REVIEW_DESTINATION/letloop-review"
    exit 1
}

# --- 3. (letloop liburing low): actually run its io_uring checks
#        statically (not just compile) -- see
#        store-flow2-static.derivation.scm's header comment ---
FLOW2_DESTINATION=$("$LETLOOP" store build "$ROOT/checks/letloop/store-flow2-static.derivation.scm" | tail -1)
echo "store path: $FLOW2_DESTINATION"

# --- 4. letloop itself: build, static-link check, relocatability check ---
LETLOOP_MUSL_DESTINATION=$("$LETLOOP" store build "$ROOT/checks/letloop/store-letloop-musl-static.derivation.scm" | tail -1)
echo "store path: $LETLOOP_MUSL_DESTINATION"

file "$LETLOOP_MUSL_DESTINATION/bin/letloop-musl-static" | grep -qi 'statically linked' || {
    echo "FAIL: $LETLOOP_MUSL_DESTINATION/bin/letloop-musl-static is not statically linked"
    file "$LETLOOP_MUSL_DESTINATION/bin/letloop-musl-static"
    exit 1
}

ELSEWHERE2=$(mktemp -d)
trap "rm -rf $ELSEWHERE $ELSEWHERE2" EXIT
cp "$LETLOOP_MUSL_DESTINATION/bin/letloop-musl-static" "$ELSEWHERE2/letloop-musl-static"
VERSION_OUTPUT=$("$ELSEWHERE2/letloop-musl-static" version)
echo "$VERSION_OUTPUT" | grep -q "Chez Scheme Version" || {
    echo "FAIL: unexpected version output: $VERSION_OUTPUT"
    exit 1
}

echo "=== All tests passed ==="
