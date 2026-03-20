#!/bin/bash
# Cross-implementation SRP test: letloop/srp (Scheme) vs pysrp (Python)
# Both sides use SHA-256, 2048-bit group, RFC 5054 padding.
set -ex

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
LETLOOP="${LETLOOP:-$ROOT/local/bin/letloop}"
TMPDIR=$(mktemp -d)
trap "cat $TMPDIR/*.txt && rm -rf $TMPDIR" EXIT

echo "=== SRP interop: letloop/srp vs pysrp (SHA-256, 2048-bit) ==="

# --- Python side ---
echo "Running pysrp..."
python3 "$ROOT/checks/letloop/srpcheck.py" > "$TMPDIR/python.txt" 2>"$TMPDIR/python_err.txt"

if [ $? -ne 0 ]; then
    echo "Python script failed:"
    cat "$TMPDIR/python_err.txt"
    exit 1
fi

# --- Scheme side ---
echo "Running letloop/srp..."
$LETLOOP exec "$ROOT/src/" "$ROOT/checks/letloop/" \
    "$ROOT/checks/letloop/srp-interop.scm" main \
    > "$TMPDIR/scheme.txt" 2>"$TMPDIR/scheme_err.txt"

if [ $? -ne 0 ]; then
    echo "Scheme script failed:"
    cat "$TMPDIR/scheme_err.txt"
    exit 1
fi

# --- Compare ---
echo ""
PASS=0
FAIL=0

while IFS= read -r py_line; do
    key="${py_line%%=*}"
    py_val="${py_line#*=}"
    scm_val=$(grep "^${key}=" "$TMPDIR/scheme.txt" | head -1 | cut -d= -f2-)

    if [ -z "$scm_val" ]; then
        echo "  $key ... SKIP (not in Scheme output)"
        continue
    fi

    if [ "$py_val" = "$scm_val" ]; then
        echo "  $key ... PASS"
        PASS=$((PASS + 1))
    else
        echo "  $key ... FAIL"
        echo "    python: ${py_val:0:64}..."
        echo "    scheme: ${scm_val:0:64}..."
        FAIL=$((FAIL + 1))
    fi
done < "$TMPDIR/python.txt"

echo ""
echo "$PASS passed, $FAIL failed"

if [ "$FAIL" -ne 0 ]; then
    echo ""
    echo "NOTE: K/M1/M2 mismatches are expected if pysrp uses minimal"
    echo "byte encoding for S/A/B in hash inputs while Scheme uses"
    echo "fixed 256-byte (PAD) encoding. verifier/A/B should always match."
    exit 1
fi

echo ""
echo "=== All tests passed ==="
