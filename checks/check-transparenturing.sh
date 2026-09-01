#!/bin/bash
# End-to-end test of (letloop http server)'s `transparent` entry point,
# driven through the real `letloop http serve` CLI with
# examples/my-web-library.scm as the application:
#
#   letloop http serve
#     -> letloop-http-serve            src/letloop/base.scm
#          -> transparent / transparent*  src/letloop/http/server.body.scm
#               -> loop-new, register-signal-handler, handle-connection
#
# (The name is historical. There is no (letloop transparent) library,
# and the examples/transparent*.scm files are unrelated to this test.)
#
# Covers: startup, GET, POST, per-application state surviving across
# connections, 404 fall-through, a request that holds an io_uring
# timeout open (/sleep), and SIGINT graceful shutdown.
#
# This script is deliberately loud on failure. It has flaked in CI-like
# back-to-back runs with curl exit 52 and no other evidence, because the
# original version discarded everything a diagnosis needs: the readiness
# loop gave up silently and fell through into test 1, the server's own
# output was interleaved with the test's and lost, and the EXIT trap
# killed the server before anything could be inspected. Every failure
# path now dumps curl's exit code, who holds the port, whether the
# server is still alive, and the server's output. Useful curl codes:
# 7 = connection refused (nothing listening), 52 = empty reply
# (something accepted the connection and closed it without a response),
# 28 = timed out.
set -e

PORT=18080
READY_TIMEOUT_SECONDS=20
EXAMPLES_DIR="$(cd "$(dirname "$0")/.." && pwd)/examples"
LETLOOP="${LETLOOP:-$(cd "$(dirname "$0")/.." && pwd)/local/bin/letloop}"
SERVER_LOG="$(mktemp -t transparenturing-server-XXXXXX.log)"
SERVER_PID=""

cleanup() {
    if [ -n "$SERVER_PID" ]; then
        kill "$SERVER_PID" 2>/dev/null || true
        wait "$SERVER_PID" 2>/dev/null || true
    fi
    rm -f "$SERVER_LOG"
}
trap cleanup EXIT

diagnose() {
    echo ""
    echo "   --- diagnostics ---"
    echo "   curl exit code:     ${1:-n/a}"
    if [ -n "$SERVER_PID" ] && kill -0 "$SERVER_PID" 2>/dev/null; then
        echo "   server pid:         $SERVER_PID (alive)"
    else
        echo "   server pid:         ${SERVER_PID:-none} (not running)"
    fi
    # Capture first: piping into sed would make the pipeline's status
    # sed's, so a `|| echo (none)` fallback would never fire.
    local listeners processes
    listeners=$(ss -ltnp 2>/dev/null | grep ":$PORT" || true)
    processes=$(pgrep -a -f 'letloop http serve' 2>/dev/null || true)
    echo "   listeners on $PORT:"
    if [ -n "$listeners" ]; then
        printf '%s\n' "$listeners" | sed 's/^/     /'
    else
        echo "     (none — nothing is bound, so curl would see connection refused)"
    fi
    echo "   'letloop http serve' processes:"
    if [ -n "$processes" ]; then
        printf '%s\n' "$processes" | sed 's/^/     /'
    else
        echo "     (none)"
    fi
    echo "   server output:"
    if [ -s "$SERVER_LOG" ]; then
        sed 's/^/     | /' "$SERVER_LOG"
    else
        echo "     (empty)"
    fi
    echo "   --- end diagnostics ---"
}

fail() {
    echo "   FAIL: $1"
    diagnose "${2:-}"
    exit 1
}

# Run curl without letting `set -e` abort before we can report why.
# Sets CURL_RC, and HTTP_STATUS or HTTP_BODY.
http_status() {
    local rc=0
    HTTP_STATUS=$(curl -s -o /dev/null -w '%{http_code}' "$@") || rc=$?
    CURL_RC=$rc
}

http_body() {
    local rc=0
    HTTP_BODY=$(curl -s "$@") || rc=$?
    CURL_RC=$rc
}

echo "=== transparenturing integration tests ==="

$LETLOOP http serve --port=$PORT "$EXAMPLES_DIR/" "$EXAMPLES_DIR/my-web-library.scm" \
    > "$SERVER_LOG" 2>&1 &
SERVER_PID=$!

echo "0. server becomes ready — expect a real response within ${READY_TIMEOUT_SECONDS}s"
# Not "did curl return 0": a server that is shutting down, or someone
# else's process on this port, can accept a connection and answer
# something useless. Wait for OUR application's response.
READY=""
READY_START=$(date +%s%N)
READY_DEADLINE=$(( $(date +%s) + READY_TIMEOUT_SECONDS ))
while [ "$(date +%s)" -lt "$READY_DEADLINE" ]; do
    if BODY=$(curl -s --max-time 2 "http://127.0.0.1:$PORT/" 2>/dev/null); then
        if printf '%s' "$BODY" | grep -q "Count:"; then
            READY=yes
            break
        fi
    fi
    if ! kill -0 "$SERVER_PID" 2>/dev/null; then
        fail "server exited before it became ready"
    fi
    sleep 0.1
done
READY_MS=$(( ( $(date +%s%N) - READY_START ) / 1000000 ))
if [ -z "$READY" ]; then
    fail "no valid response on port $PORT within ${READY_TIMEOUT_SECONDS}s"
fi
echo "   PASS (ready in ${READY_MS}ms)"

echo "1. GET / — expect 200"
http_status "http://127.0.0.1:$PORT/"
[ "$CURL_RC" = "0" ] || fail "curl could not complete the request" "$CURL_RC"
[ "$HTTP_STATUS" = "200" ] || fail "got $HTTP_STATUS" "$CURL_RC"
echo "   PASS"

echo "2. GET / — response contains Count"
http_body "http://127.0.0.1:$PORT/"
[ "$CURL_RC" = "0" ] || fail "curl could not complete the request" "$CURL_RC"
printf '%s' "$HTTP_BODY" | grep -q "Count:" || fail "response missing Count" "$CURL_RC"
echo "   PASS"

echo "3. POST /increment — expect 302 redirect"
http_status -X POST "http://127.0.0.1:$PORT/increment"
[ "$CURL_RC" = "0" ] || fail "curl could not complete the request" "$CURL_RC"
[ "$HTTP_STATUS" = "302" ] || fail "got $HTTP_STATUS" "$CURL_RC"
echo "   PASS"

echo "4. GET / after increment — count should be 1"
http_body "http://127.0.0.1:$PORT/"
[ "$CURL_RC" = "0" ] || fail "curl could not complete the request" "$CURL_RC"
printf '%s' "$HTTP_BODY" | grep -q "Count: 1" || fail "count not incremented" "$CURL_RC"
echo "   PASS"

echo "5. GET /notfound — expect 404"
http_status "http://127.0.0.1:$PORT/notfound"
[ "$CURL_RC" = "0" ] || fail "curl could not complete the request" "$CURL_RC"
[ "$HTTP_STATUS" = "404" ] || fail "got $HTTP_STATUS" "$CURL_RC"
echo "   PASS"

echo "6. GET /sleep — expect 200 (tests io_uring timeout)"
http_status --max-time 5 "http://127.0.0.1:$PORT/sleep"
[ "$CURL_RC" = "0" ] || fail "curl could not complete the request" "$CURL_RC"
[ "$HTTP_STATUS" = "200" ] || fail "got $HTTP_STATUS" "$CURL_RC"
echo "   PASS"

echo "7. Graceful shutdown via SIGINT"
kill -INT "$SERVER_PID"
wait "$SERVER_PID" 2>/dev/null || true
# The shutdown must be the handler's, not the default disposition, so
# require the message register-signal-handler's handler prints.
grep -q "shutting down" "$SERVER_LOG" || fail "no graceful-shutdown message from the server"
SERVER_PID=""
echo "   PASS"

echo ""
echo "=== All tests passed ==="
