#!/bin/bash
# Stress test: run wrk multiple times, monitor server health between runs
# Usage: bash checks/stress-transparenturing.sh [ROUNDS] [THREADS] [CONNS] [DURATION]
set -e

ROUNDS=${1:-6}
THREADS=${2:-4}
CONNS=${3:-50}
DURATION=${4:-10s}
PORT=18081
EXAMPLES_DIR="$(cd "$(dirname "$0")/.." && pwd)/examples"
LETLOOP="${LETLOOP:-$(cd "$(dirname "$0")/.." && pwd)/local/bin/letloop}"

cleanup() {
    if [ -n "$MONITOR_PID" ]; then
        kill "$MONITOR_PID" 2>/dev/null || true
    fi
    if [ -n "$SERVER_PID" ]; then
        kill "$SERVER_PID" 2>/dev/null || true
        wait "$SERVER_PID" 2>/dev/null || true
    fi
}
trap cleanup EXIT

server_stats() {
    local pid=$1
    local label=$2
    if [ -d "/proc/$pid" ]; then
        local fds=$(ls /proc/$pid/fd 2>/dev/null | wc -l)
        local sockets=$(ls -la /proc/$pid/fd 2>/dev/null | grep -c 'socket:' || echo 0)
        local rss=$(awk '/VmRSS/{print $2}' /proc/$pid/status 2>/dev/null)
        local threads=$(awk '/Threads/{print $2}' /proc/$pid/status 2>/dev/null)
        local state=$(awk '/State/{print $2, $3}' /proc/$pid/status 2>/dev/null)
        echo "  [$label] fds=$fds (sockets=$sockets)  RSS=${rss}kB  threads=$threads  state=$state"
    else
        echo "  [$label] PID=$pid — process gone!"
    fi
}

# Background monitor: sample fds+RSS every second during wrk runs
monitor_loop() {
    local pid=$1
    local logfile=$2
    while [ -d "/proc/$pid" ]; do
        local ts=$(date +%s)
        local fds=$(ls /proc/$pid/fd 2>/dev/null | wc -l)
        local sockets=$(ls -la /proc/$pid/fd 2>/dev/null | grep -c 'socket:' || echo 0)
        local rss=$(awk '/VmRSS/{print $2}' /proc/$pid/status 2>/dev/null)
        echo "$ts $fds $sockets $rss" >> "$logfile"
        sleep 1
    done
}

echo "=== transparenturing stress test ==="
echo "  rounds=$ROUNDS  threads=$THREADS  conns=$CONNS  duration=$DURATION"
echo ""

# Start server
$LETLOOP exec "$EXAMPLES_DIR/" "$EXAMPLES_DIR/transparenturing-example.scm" main -- $PORT &
SERVER_PID=$!

# Wait for server ready
for i in $(seq 1 50); do
    if curl -s -o /dev/null http://127.0.0.1:$PORT/ 2>/dev/null; then
        break
    fi
    sleep 0.1
done

# Verify server is up
STATUS=$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:$PORT/ 2>/dev/null || echo "000")
if [ "$STATUS" != "200" ]; then
    echo "FATAL: server not responding (status=$STATUS)"
    exit 1
fi

MONLOG=$(mktemp /tmp/stress-mon-XXXXXX.log)
echo "  monitor log: $MONLOG"
server_stats $SERVER_PID "baseline"
echo ""

# Start background monitor
monitor_loop $SERVER_PID "$MONLOG" &
MONITOR_PID=$!

FAILED=0
for round in $(seq 1 $ROUNDS); do
    echo "--- round $round/$ROUNDS: wrk -t$THREADS -c$CONNS -d$DURATION ---"

    # Run wrk, capture output
    WRK_OUT=$(wrk -t$THREADS -c$CONNS -d$DURATION http://127.0.0.1:$PORT/ 2>&1)

    # Extract key metrics
    REQS=$(echo "$WRK_OUT" | grep 'Requests/sec' | awk '{print $2}')
    ERRORS=$(echo "$WRK_OUT" | grep 'Socket errors' || true)
    TOTAL=$(echo "$WRK_OUT" | grep 'requests in' | head -1)

    echo "  $TOTAL"
    echo "  Requests/sec: $REQS"
    [ -n "$ERRORS" ] && echo "  $ERRORS"

    server_stats $SERVER_PID "after round $round"

    # Quick health check: can we still get a 200?
    sleep 0.5
    STATUS=$(curl -s -o /dev/null -w '%{http_code}' --max-time 3 http://127.0.0.1:$PORT/ 2>/dev/null || echo "000")
    if [ "$STATUS" != "200" ]; then
        echo "  HEALTH CHECK FAILED (status=$STATUS) — server unresponsive!"
        FAILED=$round
        break
    else
        echo "  health check: OK"
    fi
    echo ""
done

# Stop monitor
kill "$MONITOR_PID" 2>/dev/null || true
wait "$MONITOR_PID" 2>/dev/null || true
MONITOR_PID=""

echo ""
echo "--- monitor timeline (ts fds sockets rss_kb) ---"
cat "$MONLOG"
echo ""

if [ "$FAILED" -gt 0 ]; then
    echo "=== FAILED after round $FAILED ==="
    echo ""
    echo "--- diagnosis ---"
    server_stats $SERVER_PID "final"
    if [ -d "/proc/$SERVER_PID" ]; then
        echo ""
        echo "  fd breakdown:"
        ls -la /proc/$SERVER_PID/fd 2>/dev/null | awk '{print $NF}' | sed 's/\[.*\]/[type]/' | sort | uniq -c | sort -rn | head -10
        echo ""
        echo "  socket states:"
        ss -tnp 2>/dev/null | grep "pid=$SERVER_PID" | awk '{print $1}' | sort | uniq -c | sort -rn || true
        echo ""
        echo "  strace snapshot (2s):"
        timeout 2 strace -p $SERVER_PID -e trace=io_uring_enter,read,write,close -c 2>&1 || true
        echo ""
        echo "  trying a single curl with verbose:"
        curl -v --max-time 3 http://127.0.0.1:$PORT/ 2>&1 || true
    fi
    rm -f "$MONLOG"
    exit 1
else
    echo "=== ALL $ROUNDS ROUNDS PASSED ==="
    rm -f "$MONLOG"
fi
