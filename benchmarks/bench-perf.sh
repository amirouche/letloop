#!/bin/bash
# Benchmark Scheme server with perf profiling
# Produces perf.data in the project root for later analysis
set -e

BENCHMARK_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$BENCHMARK_DIR/.." && pwd)"
export LD_LIBRARY_PATH="$PROJECT_DIR/local/lib/:${LD_LIBRARY_PATH:-}"
HOST=192.168.105.2
PORT=${2:-18400}
BENCH_DURATION=10s
WARMUP_DURATION=3s
PERF_DATA="$PROJECT_DIR/perf.data"

# Which server to profile (default: scheme-iouring-server)
SERVER="${1:-$BENCHMARK_DIR/scheme-iouring-server}"

if [ ! -x "$SERVER" ]; then
    echo "Server not found: $SERVER"
    echo "Usage: $0 [path-to-server-binary]"
    echo "Build with: make build-scheme"
    exit 1
fi

echo "=== Scheme Server Perf Profiling ==="
echo "Server: $SERVER"
echo "Port: $PORT"
echo "Benchmark: $BENCH_DURATION"
echo "perf.data: $PERF_DATA"
echo ""

# Backup existing perf.data
if [ -f "$PERF_DATA" ]; then
    mv "$PERF_DATA" "$PERF_DATA.old"
    echo "Backed up existing perf.data to perf.data.old"
fi

# Start server pinned to core 0
taskset -c 0 "$SERVER" "$PORT" >/dev/null 2>&1 &
SERVER_PID=$!
echo "Server started (PID: $SERVER_PID)"

# Wait for server to be ready
for i in $(seq 1 50); do
    if curl -s -o /dev/null "http://$HOST:$PORT/" 2>/dev/null; then
        break
    fi
    sleep 0.1
done

if ! curl -s -o /dev/null "http://$HOST:$PORT/" 2>/dev/null; then
    echo "ERROR: Server failed to start"
    kill $SERVER_PID 2>/dev/null || true
    exit 1
fi
echo "Server ready"

# Warmup
echo "Warmup ($WARMUP_DURATION)..."
taskset -c 1 wrk -t1 -c10 -d"$WARMUP_DURATION" "http://$HOST:$PORT/" >/dev/null 2>&1 || true
sleep 0.5

# Start perf recording
echo "Starting perf record..."
perf record -g -p $SERVER_PID -o "$PERF_DATA" &
PERF_PID=$!
sleep 0.5

# Run benchmark
echo "Benchmarking ($BENCH_DURATION, 16 connections)..."
WRK_OUT=$(taskset -c 1 wrk -t1 -c16 -d"$BENCH_DURATION" --latency "http://$HOST:$PORT/" 2>&1)

# Stop perf (SIGINT makes it finalize perf.data cleanly)
kill -INT $PERF_PID 2>/dev/null || true
wait $PERF_PID 2>/dev/null || true

# Stop server
kill $SERVER_PID 2>/dev/null || true
wait $SERVER_PID 2>/dev/null || true

echo ""
echo "=== wrk results ==="
echo "$WRK_OUT"
echo ""
echo "=== perf.data ==="
echo "Saved to: $PERF_DATA"
echo "View with: perf report -i $PERF_DATA"
echo "Flamegraph: perf script -i $PERF_DATA | stackcollapse-perf.pl | flamegraph.pl > flamegraph.svg"
