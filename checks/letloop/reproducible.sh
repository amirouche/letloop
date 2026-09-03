#!/bin/bash
# Builds letloop twice through the store and requires the two to be
# byte-identical -- the property `letloop update` rests on, since it is
# what lets anyone rebuild a published binary and confirm it is the one
# they were given.
#
# Separate from bootstrap.sh, and from `make check`, because it is a
# release-time question rather than a did-the-chain-work one: it costs
# two full letloop builds. Run it before publishing.
#
# bootstrap.sh already gates the cheap half -- a Scheme program
# compiling reproducibly -- which covers the session key reaching the
# child `letloop compile` spawns. It cannot cover the rest: the outer
# scheme that --compile-imported-libraries writes .so and .wpo from,
# and scripts/library-cache.ss. Both only affect letloop's *own* build,
# and both were broken while the cheap gate was green. That is the gap
# this closes.
#
# Reproducibility fails silently by nature: the build succeeds, the
# binary runs, the tests pass, and only a byte comparison notices. The
# 331 files that differed when this was first written were found by
# diffing two trees on purpose, not by anything failing.
set -exo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
LETLOOP="${LETLOOP:-$ROOT/local/bin/letloop}"
WORKDIR=/tmp/letloop-bootstrap
DERIVATION=letloop

export LETLOOP_STORE="$WORKDIR/store"

# The chain has to exist first: this compares two builds of letloop, it
# does not bootstrap one. bootstrap.sh is what produces the inputs.
test -d "$LETLOOP_STORE" || {
    echo "FAIL: no store at $LETLOOP_STORE -- run checks/letloop/bootstrap.sh first"
    exit 1
}

# Staged fresh, as bootstrap.sh does: a stale snapshot silently builds
# something other than the working tree.
rm -rf "$WORKDIR/letloop-src"
mkdir -p "$WORKDIR/letloop-src"
(cd "$ROOT" && git ls-files -z | tar --null -T - -cf -) | tar -xf - -C "$WORKDIR/letloop-src"

FIRST=$("$LETLOOP" store build "$DERIVATION" | tail -1)
echo "first:  $FIRST"
FIRST_COPY=$(mktemp -d)
trap "rm -rf $FIRST_COPY" EXIT
cp -a "$FIRST/." "$FIRST_COPY/"

# Force a real rebuild. Without this the second call is a cache hit and
# proves nothing -- which it silently did the first time this was
# tried, returning the same path in twenty seconds.
CACHE_ENTRY=$(grep -rl "$(basename "$FIRST")" "$LETLOOP_STORE/.cache/" | head -1)
rm -f "$CACHE_ENTRY"
rm -rf "$FIRST" "$FIRST.drv"

SECOND=$("$LETLOOP" store build "$DERIVATION" | tail -1)
echo "second: $SECOND"

[ "$FIRST" = "$SECOND" ] || {
    echo "FAIL: the two builds landed at different store paths"
    echo "  $FIRST"
    echo "  $SECOND"
    exit 1
}

# Every file, not just the binary: the library cache is where this
# broke before, and the binary can agree while the cache does not.
DIFFERING=$(diff -rq "$FIRST_COPY" "$SECOND" | wc -l)
[ "$DIFFERING" -eq 0 ] || {
    echo "FAIL: $DIFFERING files differ between two builds of letloop"
    diff -rq "$FIRST_COPY" "$SECOND" | head -20
    exit 1
}

echo "=== letloop rebuilds byte-identical ==="
