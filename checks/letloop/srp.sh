#!/bin/bash
# Cross-implementation SRP test: letloop/srp (Scheme) vs pysrp (Python)
# Both sides use SHA-256, 2048-bit group, RFC 5054 padding.
set -xe

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
LETLOOP="${LETLOOP:-$ROOT/local/bin/letloop}"
TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

echo "=== SRP interop: letloop/srp vs pysrp (SHA-256, 2048-bit) ==="

# --- Python side ---
echo "Running pysrp..."
python3 - > "$TMPDIR/python.txt" 2>"$TMPDIR/python_err.txt" <<'PYEOF'
import hashlib
import sys

# Use pure Python pysrp for full transparency
import srp._pysrp as srp
srp.rfc5054_enable()

SHA256 = srp.SHA256
hash_class = srp._hash_map[SHA256]


def derive_secret(seed, length):
    """Derive deterministic secret using SHA-256 counter mode."""
    out = b''
    i = 0
    while len(out) < length:
        out += hashlib.sha256(seed + i.to_bytes(4, 'big')).digest()
        i += 1
    return out[:length]


def pad_hex(data, width):
    """Pad hex to fixed width (width in bytes)."""
    if isinstance(data, int):
        return format(data, 'x').zfill(width * 2)
    return data.hex().zfill(width * 2)


# Fixed test inputs
salt = bytes.fromhex('BEB25379D1A8581EB5A727673A2441EE')
identity = b'alice'
password = b'password123'
a_secret = derive_secret(b'srp-test-client-secret', 256)
b_secret = derive_secret(b'srp-test-server-secret', 256)

# Group parameters
N, g = srp.get_ng(srp.NG_2048, None, None)
byte_count = len(srp.long_to_bytes(N))  # 256

# Compute verifier: v = g^x mod N
x = srp.gen_x(hash_class, salt, identity, password)
v = pow(g, x, N)
v_bytes = srp.long_to_bytes(v)

# Client
user = srp.User(identity, password, hash_alg=SHA256, bytes_a=a_secret)
_, A_bytes = user.start_authentication()

# Server
verifier_obj = srp.Verifier(identity, salt, v_bytes, bytes_A=A_bytes,
                              hash_alg=SHA256, bytes_b=b_secret)
s, B_bytes = verifier_obj.get_challenge()
if B_bytes is None:
    print("FAIL: server safety check failed", file=sys.stderr)
    sys.exit(1)

# Client processes challenge
M1 = user.process_challenge(s, B_bytes)
if M1 is None:
    print("FAIL: client safety check failed", file=sys.stderr)
    sys.exit(1)

# Server verifies M1
M2 = verifier_obj.verify_session(M1)
if M2 is None:
    print("FAIL: server could not verify M1", file=sys.stderr)
    sys.exit(1)

# Client verifies M2
user.verify_session(M2)
if not user.authenticated():
    print("FAIL: client could not verify M2", file=sys.stderr)
    sys.exit(1)

# Output (pad integers to 256 bytes for fair comparison with Scheme)
print(f'verifier={pad_hex(v_bytes, byte_count)}')
print(f'A={pad_hex(A_bytes, byte_count)}')
print(f'B={pad_hex(B_bytes, byte_count)}')
print(f'K={user.get_session_key().hex()}')
print(f'M1={M1.hex()}')
print(f'M2={M2.hex()}')
PYEOF

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
