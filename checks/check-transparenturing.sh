#!/bin/bash
# Integration test for transparenturing io_uring HTTP server
# Tests: server start, GET, POST, /sleep endpoint, graceful shutdown
set -e

PORT=18080
EXAMPLES_DIR="$(cd "$(dirname "$0")/.." && pwd)/examples"
LETLOOP="${LETLOOP:-$(cd "$(dirname "$0")/.." && pwd)/local/bin/letloop}"

cleanup() {
    if [ -n "$SERVER_PID" ]; then
        kill "$SERVER_PID" 2>/dev/null || true
        wait "$SERVER_PID" 2>/dev/null || true
    fi
}
trap cleanup EXIT

echo "=== transparenturing integration tests ==="

# Start server in background
$LETLOOP http serve --port=$PORT "$EXAMPLES_DIR/" "$EXAMPLES_DIR/my-web-library.scm" &
SERVER_PID=$!

# Wait for server to be ready
for i in $(seq 1 30); do
    if curl -s -o /dev/null http://127.0.0.1:$PORT/ 2>/dev/null; then
        break
    fi
    sleep 0.1
done

echo "1. GET / — expect 200"
STATUS=$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:$PORT/)
if [ "$STATUS" = "200" ]; then
    echo "   PASS"
else
    echo "   FAIL: got $STATUS"
    exit 1
fi

echo "2. GET / — response contains Count"
BODY=$(curl -s http://127.0.0.1:$PORT/)
if echo "$BODY" | grep -q "Count:"; then
    echo "   PASS"
else
    echo "   FAIL: response missing Count"
    exit 1
fi

echo "3. POST /increment — expect 302 redirect"
STATUS=$(curl -s -o /dev/null -w '%{http_code}' -X POST http://127.0.0.1:$PORT/increment)
if [ "$STATUS" = "302" ]; then
    echo "   PASS"
else
    echo "   FAIL: got $STATUS"
    exit 1
fi

echo "4. GET / after increment — count should be 1"
BODY=$(curl -s http://127.0.0.1:$PORT/)
if echo "$BODY" | grep -q "Count: 1"; then
    echo "   PASS"
else
    echo "   FAIL: count not incremented"
    exit 1
fi

echo "5. GET /notfound — expect 404"
STATUS=$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:$PORT/notfound)
if [ "$STATUS" = "404" ]; then
    echo "   PASS"
else
    echo "   FAIL: got $STATUS"
    exit 1
fi

echo "6. GET /sleep — expect 200 (tests io_uring timeout)"
STATUS=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 http://127.0.0.1:$PORT/sleep)
if [ "$STATUS" = "200" ]; then
    echo "   PASS"
else
    echo "   FAIL: got $STATUS"
    exit 1
fi

echo "7. Graceful shutdown via SIGINT"
kill -INT "$SERVER_PID"
wait "$SERVER_PID" 2>/dev/null || true
SERVER_PID=""
echo "   PASS"

echo ""
echo "=== All tests passed ==="
