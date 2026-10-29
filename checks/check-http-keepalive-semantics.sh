#!/bin/bash
# End-to-end: what (letloop http server) owes a keep-alive client
# whose next move arrives while DISPATCH runs.
#
#   - half-close: the client sends a request and shuts down its write
#     side; it still gets the response.
#   - pipelining: a second request arrives while the first dispatches;
#     both are answered, in order.
#
# Each against a handler that suspends (/slow, raced against the
# connection) and one that answers at once (/, never raced). Both
# used to fail for /slow: any read result ended the race and the
# response was abandoned.
#
# Runs the server from ./src, so it tests the working tree, not the
# installed copy. Needs python3 for the raw-socket client.
set -e

PORT=${PORT:-18090}
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LETLOOP="${LETLOOP:-$ROOT/local/bin/letloop}"
SERVER_LOG="$(mktemp -t keepalive-semantics-XXXXXX.log)"
SERVER_PID=""

cleanup() {
    if [ -n "$SERVER_PID" ]; then
        kill "$SERVER_PID" 2>/dev/null || true
        wait "$SERVER_PID" 2>/dev/null || true
    fi
    rm -f "$SERVER_LOG"
}
trap cleanup EXIT

"$LETLOOP" http serve --port=$PORT "$ROOT/src/" "$ROOT/checks/" \
    "$ROOT/checks/check-http-keepalive-semantics-lib.scm" > "$SERVER_LOG" 2>&1 &
SERVER_PID=$!

for i in $(seq 1 200); do
    curl -s -o /dev/null "http://127.0.0.1:$PORT/" 2>/dev/null && break
    sleep 0.1
done

python3 - "$PORT" <<'PY'
import socket, sys
port = int(sys.argv[1])

def exchange(chunks, half_close=False):
    s = socket.create_connection(("127.0.0.1", port))
    s.settimeout(3)
    for i, chunk in enumerate(chunks):
        if i:
            import time; time.sleep(0.1)
        s.sendall(chunk)
    if half_close:
        s.shutdown(socket.SHUT_WR)
    out = b""
    try:
        while True:
            d = s.recv(65536)
            if not d:
                break
            out += d
    except socket.timeout:
        pass
    s.close()
    return out

def req(path, close=False):
    extra = b"Connection: close\r\n" if close else b""
    return b"GET " + path + b" HTTP/1.1\r\nHost: x\r\n" + extra + b"\r\n"

failures = 0
def expect(name, out, bodies):
    global failures
    got = [b for b in bodies if b in out]
    ok = out.count(b"HTTP/1.1 200") == len(bodies) and got == bodies \
        and all(out.index(a) < out.index(b) for a, b in zip(bodies, bodies[1:]))
    print(("PASS " if ok else "FAIL ") + name)
    if not ok:
        failures += 1
        print("   response bytes:", out[:400])

for path, body in ((b"/slow", b"ok (slow)"), (b"/", b"ok ()")):
    expect("half-close " + path.decode(),
           exchange([req(path)], half_close=True), [body])
    expect("pipelined " + path.decode(),
           exchange([req(path), req(b"/two", close=True)]), [body, b"ok (two)"])

sys.exit(1 if failures else 0)
PY
status=$?
if [ $status -ne 0 ]; then
    echo "--- server output ---"
    cat "$SERVER_LOG"
fi
exit $status
