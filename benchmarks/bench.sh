#!/bin/bash
# Scaling benchmark - tests each implementation with growing concurrency
# Records RPS and latency at each concurrency level
set -e

BENCHMARK_DIR="$(cd "$(dirname "$0")" && pwd)"
RESULTS_DIR="$BENCHMARK_DIR/results"
HOST=127.0.0.1
BASE_PORT=18300
GLOBAL_PORT_OFFSET=0
WARMUP_DURATION=3s
BENCH_DURATION=10s

CONCURRENCY_LEVELS=(1 2 4 8 16 32 64 128 256)

mkdir -p "$RESULTS_DIR"

wait_for_server() {
    local port=$1
    local max_attempts=50
    for i in $(seq 1 $max_attempts); do
        if curl -s -o /dev/null http://$HOST:$port/ 2>/dev/null; then
            return 0
        fi
        sleep 0.1
    done
    return 1
}

benchmark_implementation() {
    local name=$1
    local cmd=$2
    local impl_key=${name,,}
    impl_key=${impl_key// /-}

    local csv_file="$RESULTS_DIR/${impl_key}-scaling.csv"

    echo ""
    echo "=========================================="
    echo "Benchmarking: $name"
    echo "=========================================="
    echo ""

    echo "concurrency,req_sec,avg_lat_ms,max_lat_ms,p99_lat_ms,errors" > "$csv_file"

    for CONNS in "${CONCURRENCY_LEVELS[@]}"; do
        PORT=$((BASE_PORT + GLOBAL_PORT_OFFSET))
        GLOBAL_PORT_OFFSET=$((GLOBAL_PORT_OFFSET + 1))

        echo "  $CONNS connections..."

        eval "taskset -c 0 $cmd $PORT" >/dev/null 2>&1 &
        SERVER_PID=$!

        if ! wait_for_server $PORT; then
            echo "  FAILED to start on port $PORT"
            kill $SERVER_PID 2>/dev/null || true
            wait $SERVER_PID 2>/dev/null || true
            echo "$CONNS,0,0,0,0,FAILED" >> "$csv_file"
            sleep 0.5
            continue
        fi

        sleep 0.5

        # Warmup
        taskset -c 1 wrk -t1 -c10 -d$WARMUP_DURATION "http://$HOST:$PORT/" >/dev/null 2>&1 || true
        sleep 0.5

        # Benchmark
        WRK_THREADS=$(( (CONNS + 9) / 10 ))
        if [ $WRK_THREADS -lt 1 ]; then WRK_THREADS=1; fi

        WRK_OUT=$(taskset -c 1-$WRK_THREADS wrk -t$WRK_THREADS -c$CONNS -d$BENCH_DURATION \
            --latency "http://$HOST:$PORT/" 2>&1)

        # Parse wrk output
        RPS=$(echo "$WRK_OUT" | grep "Requests/sec:" | awk '{print $2}')

        normalize_lat() {
            local val="$1"
            if echo "$val" | grep -q "us$"; then
                echo "$val" | sed 's/us$//' | awk '{printf "%.3f", $1/1000}'
            elif echo "$val" | grep -q "s$" && ! echo "$val" | grep -q "ms$"; then
                echo "$val" | sed 's/s$//' | awk '{printf "%.1f", $1*1000}'
            else
                echo "$val" | sed 's/ms$//'
            fi
        }

        RAW_AVG=$(echo "$WRK_OUT" | grep -A 3 "Thread Stats" | grep "Latency" | head -1 | awk '{print $2}')
        RAW_MAX=$(echo "$WRK_OUT" | grep -A 3 "Thread Stats" | grep "Latency" | head -1 | awk '{print $4}')
        RAW_P99=$(echo "$WRK_OUT" | grep "99%" | awk '{print $2}')

        AVG_LAT=$(normalize_lat "$RAW_AVG")
        MAX_LAT=$(normalize_lat "$RAW_MAX")
        P99_LAT=$(normalize_lat "$RAW_P99")

        ERRORS=$(echo "$WRK_OUT" | grep -E "Socket errors|Non-2xx" | head -1)
        ERROR_COUNT=0
        if [ -n "$ERRORS" ]; then
            ERROR_COUNT=$(echo "$ERRORS" | grep -oE "[0-9]+" | paste -sd+ | bc 2>/dev/null || echo "0")
        fi

        RPS=${RPS:-0}
        AVG_LAT=${AVG_LAT:-0}
        MAX_LAT=${MAX_LAT:-0}
        P99_LAT=${P99_LAT:-0}

        printf "  %4d conn: %10s req/s | avg: %8s ms | p99: %8s ms | errors: %d\n" \
            "$CONNS" "$RPS" "$AVG_LAT" "$P99_LAT" "$ERROR_COUNT"

        echo "$CONNS,$RPS,$AVG_LAT,$MAX_LAT,$P99_LAT,$ERROR_COUNT" >> "$csv_file"

        kill -TERM -- -$SERVER_PID 2>/dev/null || kill -TERM $SERVER_PID 2>/dev/null || true
        wait $SERVER_PID 2>/dev/null || true
        sleep 0.3
    done

    echo ""
    echo "Results: $csv_file"
    echo ""
}

declare -A SERVERS
declare -A COMMANDS

echo "Checking available implementations..."
echo ""

# Scheme (compiled)
if [ -x "$BENCHMARK_DIR/bin/scheme-pico-server" ]; then
    SERVERS[scheme-pico]="Scheme-pico"
    COMMANDS[scheme-pico]="$BENCHMARK_DIR/bin/scheme-pico-server"
    echo "✓ Scheme (pico, compiled)"
fi

# Go
if [ -f "$BENCHMARK_DIR/bin/go-server" ] || (mkdir -p "$BENCHMARK_DIR/bin" && cd "$BENCHMARK_DIR/go" && go build -o ../bin/go-server main.go 2>/dev/null); then
    SERVERS[go]="Go"
    COMMANDS[go]="env GOMAXPROCS=1 $BENCHMARK_DIR/bin/go-server"
    echo "✓ Go"
fi

# Node.js
if command -v node &>/dev/null; then
    SERVERS[js]="JavaScript"
    COMMANDS[js]="node $BENCHMARK_DIR/js/index.js"
    echo "✓ JavaScript (Node.js)"
fi

# Rust
if [ -f "$BENCHMARK_DIR/rust/target/release/server" ] || (cd "$BENCHMARK_DIR/rust" && cargo build --release 2>&1 | grep -q "Finished" 2>/dev/null); then
    SERVERS[rust]="Rust"
    COMMANDS[rust]="$BENCHMARK_DIR/rust/target/release/server"
    echo "✓ Rust"
fi

# Bun
if command -v bun &>/dev/null; then
    SERVERS[bun]="Bun"
    COMMANDS[bun]="bun $BENCHMARK_DIR/bun/server.ts"
    echo "✓ Bun"
fi

# Deno
if command -v deno &>/dev/null; then
    SERVERS[deno]="Deno"
    COMMANDS[deno]="env TOKIO_WORKER_THREADS=1 deno run --allow-net $BENCHMARK_DIR/deno/server.ts"
    echo "✓ Deno"
fi

# FastAPI
if command -v python3 &>/dev/null; then
    if [ -d "$BENCHMARK_DIR/fastapi/venv" ] || (cd "$BENCHMARK_DIR/fastapi" && python3 -m venv venv 2>&1 >/dev/null && source venv/bin/activate && pip install -q -r requirements.txt 2>&1 >/dev/null && deactivate); then
        SERVERS[fastapi]="FastAPI"
        COMMANDS[fastapi]="bash -c 'cd $BENCHMARK_DIR/fastapi && source venv/bin/activate && exec python3 server.py \"\$1\"' --"
        echo "✓ FastAPI"
    fi
    if [ -d "$BENCHMARK_DIR/flask/venv" ] || (cd "$BENCHMARK_DIR/flask" && python3 -m venv venv 2>&1 >/dev/null && source venv/bin/activate && pip install -q -r requirements.txt 2>&1 >/dev/null && deactivate); then
        SERVERS[flask]="Flask"
        COMMANDS[flask]="bash -c 'cd $BENCHMARK_DIR/flask && source venv/bin/activate && exec gunicorn -w 1 -b 127.0.0.1:\"\$1\" server:app --log-level critical' --"
        echo "✓ Flask"
    fi
fi

# Gleam
if command -v gleam &>/dev/null && [ -f "$BENCHMARK_DIR/gleam/gleam.toml" ]; then
    (cd "$BENCHMARK_DIR/gleam" && gleam build >/dev/null 2>&1)
    SERVERS[gleam]="Gleam"
    COMMANDS[gleam]="bash -c 'cd $BENCHMARK_DIR/gleam && exec env ERL_FLAGS=\"+S 1:1\" gleam run -- \"\$1\"' --"
    echo "✓ Gleam"
fi

# Racket
if command -v racket &>/dev/null; then
    SERVERS[racket]="Racket"
    COMMANDS[racket]="racket $BENCHMARK_DIR/racket/server.rkt"
    echo "✓ Racket"
fi

echo ""

if [ ${#SERVERS[@]} -eq 0 ]; then
    echo "No implementations available!"
    exit 1
fi

echo "============================================================"
echo "  Scaling Benchmark"
echo "  Concurrency: ${CONCURRENCY_LEVELS[*]}"
echo "  Warmup: $WARMUP_DURATION | Duration: $BENCH_DURATION per level"
echo "  Results: $RESULTS_DIR"
echo "============================================================"

for impl_key in "${!SERVERS[@]}"; do
    benchmark_implementation "${SERVERS[$impl_key]}" "${COMMANDS[$impl_key]}"
    sleep 1
done

echo "=========================================="
echo "Benchmark complete. Results in: $RESULTS_DIR"
echo "=========================================="
