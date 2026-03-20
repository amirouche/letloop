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
