#!/bin/bash
# Benchmark comparing transparent-legacy (epoll), transparent, and transparenturing (io_uring)
set -e

LETLOOP="${LETLOOP:-./local/bin/letloop}"
WRK_THREADS=4
WRK_DURATION=10s
EXAMPLES_DIR="./examples"

declare -A FILES
FILES[transparent-legacy]="transparent-legacy-example.scm"
FILES[transparent]="transparent-example.scm"
FILES[transparenturing]="transparenturing-example.scm"

BASE_PORT=18100

wait_for_server() {
    local port=$1
    for i in $(seq 1 50); do
        if curl -s -o /dev/null http://127.0.0.1:$port/ 2>/dev/null; then
            return 0
        fi
        sleep 0.1
    done
    echo "FAIL: server on port $port did not start"
    return 1
}

get_rss_kb() {
    local pid=$1
    if [ -f /proc/$pid/status ]; then
        grep VmRSS /proc/$pid/status | awk '{print $2}'
    else
        ps -o rss= -p $pid 2>/dev/null | tr -d ' '
    fi
}

echo "============================================================"
echo "  Benchmark: transparent-legacy vs transparent vs transparenturing"
echo "  wrk: ${WRK_THREADS} threads, ${WRK_DURATION} duration"
echo "  Concurrency levels: 10, 50, 200"
echo "============================================================"
echo ""

PORT_COUNTER=0

for CONNS in 10 50 200; do
    echo "======================== $CONNS connections ========================"
    printf "%-22s %10s %10s %12s %10s %10s\n" \
        "Server" "Req/sec" "Avg Lat" "Max Lat" "RSS (KB)" "Errors"
    echo "----------------------------------------------------------------------"

    for SERVER in transparent-legacy transparent transparenturing; do
        # Each run gets a unique port to avoid bind conflicts
        PORT_COUNTER=$((PORT_COUNTER + 1))
        PORT=$((BASE_PORT + PORT_COUNTER))
        FILE=${FILES[$SERVER]}

        # Start server
        $LETLOOP exec "$EXAMPLES_DIR/" "$EXAMPLES_DIR/$FILE" main -- $PORT >/dev/null 2>&1 &
        SERVER_PID=$!

        if ! wait_for_server $PORT; then
            echo "$SERVER: FAILED TO START"
            kill $SERVER_PID 2>/dev/null; wait $SERVER_PID 2>/dev/null || true
            continue
        fi

        # Warmup with low concurrency to stabilize
        wrk -t2 -c10 -d2s http://127.0.0.1:$PORT/ >/dev/null 2>&1
        sleep 0.3

        # Benchmark
        WRK_OUT=$(wrk -t$WRK_THREADS -c$CONNS -d$WRK_DURATION http://127.0.0.1:$PORT/ 2>&1)

        # Measure RSS after benchmark
        RSS=$(get_rss_kb $SERVER_PID)
        RSS=${RSS:-0}

        # Parse wrk output
        RPS=$(echo "$WRK_OUT" | grep "Requests/sec:" | awk '{print $2}')
        AVG_LAT=$(echo "$WRK_OUT" | grep "Latency" | awk '{print $2}')
        MAX_LAT=$(echo "$WRK_OUT" | grep "Latency" | awk '{print $4}')
        ERRORS=$(echo "$WRK_OUT" | grep -E "Socket errors:|Non-2xx" | head -1)
        [ -z "$ERRORS" ] && ERRORS="0"

        printf "%-22s %10s %10s %12s %10s %10s\n" \
            "$SERVER" "$RPS" "$AVG_LAT" "$MAX_LAT" "$RSS" "$ERRORS"

        # Stop server
        kill -INT $SERVER_PID 2>/dev/null
        wait $SERVER_PID 2>/dev/null || true
        sleep 0.5
    done
    echo ""
done
