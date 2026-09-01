#!/bin/bash
# End-to-end smoke test for `letloop store build`: statically compile a
# tiny Scheme program inside a network-off, musl/Alpine sandbox, and
# prove the resulting binary is a relocatable, statically linked
# executable -- not just something that happens to run inside its own
# build sandbox.
#
# This is opt-in, NOT run by `make check`: provisioning builds
# ChezScheme + letloop from source inside an Alpine container, a
# multi-minute, network-heavy operation (see CLAUDE.md's own
# first-time-setup timing), unlike every other check under checks/.
set -ex

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
    "$LETLOOP" root exec "$ROOTFS" / -- \
        sh -c 'apk add --no-cache build-base bash git util-linux-dev coreutils'
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

# --- Build the derivation ---
export LETLOOP_STORE="$WORKDIR/store"
DESTINATION=$("$LETLOOP" store build "$ROOT/checks/letloop/store-static-hello.derivation.scm")
echo "store path: $DESTINATION"

# --- Statically linked: no dynamic interpreter/loader ---
file "$DESTINATION/hello" | grep -qi 'statically linked' || {
    echo "FAIL: $DESTINATION/hello is not statically linked"
    file "$DESTINATION/hello"
    exit 1
}

# --- Relocatable: copy it OUT of the store and run it standalone ---
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

echo "=== All tests passed ==="
