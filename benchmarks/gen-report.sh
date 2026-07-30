#!/bin/bash
# Generate HTML benchmark report from CSV results — pure HTML/CSS, no JavaScript
set -e

BENCHMARK_DIR="$(cd "$(dirname "$0")" && pwd)"
RESULTS_DIR="$BENCHMARK_DIR/results"
OUTPUT="$RESULTS_DIR/report.html"

if [ ! -d "$RESULTS_DIR" ] || ! ls "$RESULTS_DIR"/*-scaling.csv >/dev/null 2>&1; then
    echo "No benchmark results found in $RESULTS_DIR"
    echo "Run 'make bench' first."
    exit 1
fi

# Map CSV filenames to display names, frameworks, and colors
declare -A NAMES FRAMEWORKS COLORS
NAMES[letloop]="letloop"
NAMES[bun]="Bun"
NAMES[bun-canary]="Bun (canary)"
NAMES[deno]="Deno"
NAMES[go]="Go"
NAMES[javascript]="Node.js"
NAMES[rust]="Rust"
NAMES[gleam]="Gleam"
NAMES[fastapi]="FastAPI"
NAMES[flask]="Flask"
NAMES[racket]="Racket"
NAMES[c-h2o]="C (h2o)"
NAMES[common-lisp]="Common Lisp"
NAMES[ruby]="Ruby"
NAMES[java-loom]="Java (Loom)"
NAMES[java-vertx]="Java (Vert.x)"

FRAMEWORKS[letloop]="pico + io_uring"
FRAMEWORKS[bun]="Bun.serve()"
FRAMEWORKS[bun-canary]="Bun.serve() (canary, Rust)"
FRAMEWORKS[deno]="Deno.serve()"
FRAMEWORKS[go]="net/http (stdlib)"
FRAMEWORKS[javascript]="http (stdlib)"
FRAMEWORKS[rust]="axum + tokio"
FRAMEWORKS[gleam]="mist + gleam_otp"
FRAMEWORKS[fastapi]="uvicorn"
FRAMEWORKS[flask]="gunicorn (1 worker)"
FRAMEWORKS[racket]="web-server (stdlib)"
FRAMEWORKS[c-h2o]="libh2o-evloop"
FRAMEWORKS[common-lisp]="Hunchentoot"
FRAMEWORKS[ruby]="Falcon (async)"
FRAMEWORKS[java-loom]="HttpServer + virtual threads"
FRAMEWORKS[java-vertx]="Vert.x"

COLORS[letloop]="#ffffff"
COLORS[bun]="#f5e042"
COLORS[bun-canary]="#f0b429"
COLORS[deno]="#01c2a9"
COLORS[go]="#00acd7"
COLORS[javascript]="#68a063"
COLORS[rust]="#f97316"
COLORS[gleam]="#ffaff3"
COLORS[fastapi]="#009688"
COLORS[flask]="#646cff"
COLORS[racket]="#9e1a20"
COLORS[c-h2o]="#e44d26"
COLORS[common-lisp]="#a855f7"
COLORS[ruby]="#cc342d"
COLORS[java-loom]="#ed8b00"
COLORS[java-vertx]="#5b2d8e"

CONCURRENCY_LEVELS="1 2 4 8 16 32 64 128 256"

# Parse all CSVs into arrays: key -> concurrency -> values
declare -A PEAK_RPS PEAK_CONNS PEAK_AVG PEAK_P99
declare -A ALL_RPS ALL_AVG ALL_P99
KEYS=()

for csv in "$RESULTS_DIR"/*-scaling.csv; do
    key=$(basename "$csv" -scaling.csv)
    name="${NAMES[$key]:-$key}"

    # Check for valid data
    has_data=false
    while IFS=, read -r conc rps avg_lat max_lat p99_lat errors; do
        [ "$conc" = "concurrency" ] && continue
        [ "$rps" = "0" ] && continue
        has_data=true
        break
    done < "$csv"
    $has_data || continue

    KEYS+=("$key")

    best_rps=0
    best_conns=0
    best_avg=0
    best_p99=0

    while IFS=, read -r conc rps avg_lat max_lat p99_lat errors; do
        [ "$conc" = "concurrency" ] && continue
        [ "$rps" = "0" ] && continue
        ALL_RPS[$key,$conc]="$rps"
        ALL_AVG[$key,$conc]="$avg_lat"
        ALL_P99[$key,$conc]="$p99_lat"

        # Track peak
        if awk "BEGIN{exit(!($rps > $best_rps))}"; then
            best_rps="$rps"
            best_conns="$conc"
            best_avg="$avg_lat"
            best_p99="$p99_lat"
        fi
    done < "$csv"

    PEAK_RPS[$key]="$best_rps"
    PEAK_CONNS[$key]="$best_conns"
    PEAK_AVG[$key]="$best_avg"
    PEAK_P99[$key]="$best_p99"
done

# Sort keys by peak RPS descending
SORTED_KEYS=($(for k in "${KEYS[@]}"; do echo "${PEAK_RPS[$k]} $k"; done | sort -rn | awk '{print $2}'))

# Find max RPS for bar scaling
MAX_RPS="${PEAK_RPS[${SORTED_KEYS[0]}]}"

# Helper: format number with commas
fmt_num() {
    printf "%'.0f" "$1" 2>/dev/null || printf "%.0f" "$1"
}

# Helper: compute bar percentage
bar_pct() {
    awk "BEGIN{printf \"%.1f\", ($1 / $MAX_RPS) * 100}"
}

IMPL_COUNT=${#SORTED_KEYS[@]}
FIRST_KEY="${SORTED_KEYS[0]}"
SECOND_KEY="${SORTED_KEYS[1]}"

# Find lowest p99
LOWEST_P99_KEY="${SORTED_KEYS[0]}"
LOWEST_P99_VAL="999"
for k in "${SORTED_KEYS[@]}"; do
    for c in $CONCURRENCY_LEVELS; do
        v="${ALL_P99[$k,$c]}"
        [ -z "$v" ] && continue
        if awk "BEGIN{exit(!($v < $LOWEST_P99_VAL && $v > 0))}"; then
            LOWEST_P99_VAL="$v"
            LOWEST_P99_KEY="$k"
        fi
    done
done

DATE=$(date '+%B %d, %Y')

# --- Generate HTML ---
cat > "$OUTPUT" << HTMLEOF
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>HTTP Server Benchmark Report</title>
<style>
  :root {
    --bg: #0f1117;
    --surface: #1a1d27;
    --border: #2a2d3a;
    --text: #e1e4ed;
    --muted: #8b8fa3;
  }
  * { margin: 0; padding: 0; box-sizing: border-box; }
  body {
    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', system-ui, sans-serif;
    background: var(--bg); color: var(--text); line-height: 1.6; padding: 2rem;
  }
  .container { max-width: 1200px; margin: 0 auto; }
  h1 { font-size: 1.8rem; font-weight: 600; margin-bottom: 0.25rem; }
  .subtitle { color: var(--muted); font-size: 0.95rem; margin-bottom: 2rem; }
  h2 {
    font-size: 1.3rem; font-weight: 600; margin: 2.5rem 0 1rem;
    padding-bottom: 0.5rem; border-bottom: 1px solid var(--border);
  }
  table { width: 100%; border-collapse: collapse; margin-bottom: 1.5rem; font-size: 0.9rem; }
  th {
    text-align: left; padding: 0.6rem 0.8rem; border-bottom: 2px solid var(--border);
    color: var(--muted); font-weight: 500; font-size: 0.8rem; text-transform: uppercase; letter-spacing: 0.05em;
  }
  td { padding: 0.6rem 0.8rem; border-bottom: 1px solid var(--border); }
  tr:hover td { background: rgba(108, 140, 255, 0.05); }
  .num { font-family: 'SF Mono', 'Fira Code', monospace; font-size: 0.85rem; text-align: right; }
  .peak { color: #4ade80; font-weight: 600; }
  .rank { color: var(--muted); font-weight: 600; }
  .lang { font-weight: 600; }
  .bar-cell { width: 25%; }
  .bar-bg { background: var(--border); border-radius: 3px; height: 18px; overflow: hidden; }
  .bar-fill { height: 100%; border-radius: 3px; }
  .info-row { display: flex; gap: 2rem; margin-bottom: 2rem; flex-wrap: wrap; }
  .info-box {
    background: var(--surface); border: 1px solid var(--border); border-radius: 8px;
    padding: 1rem 1.25rem; flex: 1; min-width: 180px;
  }
  .info-label { font-size: 0.75rem; color: var(--muted); text-transform: uppercase; letter-spacing: 0.05em; }
  .info-value { font-size: 1.4rem; font-weight: 700; margin-top: 0.2rem; }
  .info-detail { font-size: 0.8rem; color: var(--muted); }
  .details-grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(360px, 1fr)); gap: 1rem; margin-top: 1rem; }
  .detail-card {
    background: var(--surface); border: 1px solid var(--border); border-radius: 8px; padding: 1rem;
  }
  .detail-card h3 { font-size: 0.95rem; margin-bottom: 0.75rem; display: flex; align-items: center; gap: 0.5rem; }
  .detail-card table { font-size: 0.8rem; }
  .detail-card th { font-size: 0.7rem; }
  .dot { width: 10px; height: 10px; border-radius: 2px; display: inline-block; }
  .podium-table td { vertical-align: middle; }
  .podium-conns { font-size: 1.1rem; font-weight: 700; font-family: 'SF Mono', 'Fira Code', monospace; text-align: center; width: 5rem; }
  .podium-cell { min-width: 180px; }
  .podium-entry { display: flex; align-items: center; gap: 0.5rem; }
  .podium-medal {
    width: 22px; height: 22px; border-radius: 50%; display: inline-flex; align-items: center;
    justify-content: center; font-size: 0.7rem; font-weight: 700; flex-shrink: 0;
  }
  .m1 { background: #c9951c; color: #000; }
  .m2 { background: #8a8a8a; color: #000; }
  .m3 { background: #a0522d; color: #fff; }
  .m4 { background: #3a3d4a; color: var(--text); }
  .m5 { background: #2a2d3a; color: var(--muted); }
  .podium-name { font-weight: 600; }
  .podium-rps { font-family: 'SF Mono', 'Fira Code', monospace; font-size: 0.8rem; color: var(--muted); margin-left: auto; }
  footer {
    margin-top: 3rem; padding-top: 1rem; border-top: 1px solid var(--border);
    color: var(--muted); font-size: 0.8rem; text-align: center;
  }
</style>
</head>
<body>
<div class="container">

<h1>HTTP Server Benchmark Report</h1>
<p class="subtitle">Counter application &mdash; single-threaded, 10s per concurrency level, wrk load generator</p>

<div class="info-row">
  <div class="info-box">
    <div class="info-label">Fastest</div>
    <div class="info-value" style="color:${COLORS[$FIRST_KEY]}">${NAMES[$FIRST_KEY]}</div>
    <div class="info-detail">$(fmt_num "${PEAK_RPS[$FIRST_KEY]}") req/s (${FRAMEWORKS[$FIRST_KEY]})</div>
  </div>
  <div class="info-box">
    <div class="info-label">Runner-up</div>
    <div class="info-value" style="color:${COLORS[$SECOND_KEY]}">${NAMES[$SECOND_KEY]}</div>
    <div class="info-detail">$(fmt_num "${PEAK_RPS[$SECOND_KEY]}") req/s (${FRAMEWORKS[$SECOND_KEY]})</div>
  </div>
  <div class="info-box">
    <div class="info-label">Lowest p99</div>
    <div class="info-value" style="color:${COLORS[$LOWEST_P99_KEY]}">${NAMES[$LOWEST_P99_KEY]}</div>
    <div class="info-detail">${LOWEST_P99_VAL}ms</div>
  </div>
  <div class="info-box">
    <div class="info-label">Implementations</div>
    <div class="info-value">${IMPL_COUNT}</div>
    <div class="info-detail">languages tested</div>
  </div>
</div>

<h2>Peak Throughput Rankings</h2>
<table>
  <thead>
    <tr>
      <th style="width:3rem">#</th>
      <th>Language</th>
      <th>Framework</th>
      <th class="num">Peak req/s</th>
      <th class="num">@ conns</th>
      <th class="num">Avg (ms)</th>
      <th class="num">p99 (ms)</th>
      <th class="bar-cell"></th>
    </tr>
  </thead>
  <tbody>
HTMLEOF

# Rankings rows
rank=1
for k in "${SORTED_KEYS[@]}"; do
    name="${NAMES[$k]:-$k}"
    fw="${FRAMEWORKS[$k]:-unknown}"
    color="${COLORS[$k]:-#888}"
    rps="${PEAK_RPS[$k]}"
    conns="${PEAK_CONNS[$k]}"
    avg="${PEAK_AVG[$k]}"
    p99="${PEAK_P99[$k]}"
    pct=$(bar_pct "$rps")

    cat >> "$OUTPUT" << ROWEOF
    <tr>
      <td class="rank">$rank</td>
      <td class="lang" style="color:$color">$name</td>
      <td style="color:var(--muted)">$fw</td>
      <td class="num peak">$(fmt_num "$rps")</td>
      <td class="num">$conns</td>
      <td class="num">$avg</td>
      <td class="num">$p99</td>
      <td class="bar-cell"><div class="bar-bg"><div class="bar-fill" style="width:${pct}%;background:$color"></div></div></td>
    </tr>
ROWEOF
    rank=$((rank + 1))
done

cat >> "$OUTPUT" << 'HTMLEOF'
  </tbody>
</table>

<h2>Scaling Data</h2>
HTMLEOF

# Per-implementation detail cards
echo '<div class="details-grid">' >> "$OUTPUT"

for k in "${SORTED_KEYS[@]}"; do
    name="${NAMES[$k]:-$k}"
    fw="${FRAMEWORKS[$k]:-unknown}"
    color="${COLORS[$k]:-#888}"

    cat >> "$OUTPUT" << CARDEOF
<div class="detail-card">
  <h3><span class="dot" style="background:$color"></span>$name <span style="color:var(--muted);font-weight:400;font-size:0.8rem">$fw</span></h3>
  <table>
    <thead><tr><th class="num">Conns</th><th class="num">Req/s</th><th class="num">Avg (ms)</th><th class="num">p99 (ms)</th></tr></thead>
    <tbody>
CARDEOF
    for c in $CONCURRENCY_LEVELS; do
        rps="${ALL_RPS[$k,$c]}"
        [ -z "$rps" ] && continue
        avg="${ALL_AVG[$k,$c]}"
        p99="${ALL_P99[$k,$c]}"
        echo "    <tr><td class=\"num\">$c</td><td class=\"num\">$(fmt_num "$rps")</td><td class=\"num\">$avg</td><td class=\"num\">$p99</td></tr>" >> "$OUTPUT"
    done
    echo '    </tbody></table></div>' >> "$OUTPUT"
done

echo '</div>' >> "$OUTPUT"

# Top 5 by concurrency level
cat >> "$OUTPUT" << 'HTMLEOF'

<h2>Top 5 by Concurrency Level</h2>
<table class="podium-table">
  <thead>
    <tr>
      <th>Connections</th>
      <th>1st</th>
      <th>2nd</th>
      <th>3rd</th>
      <th>4th</th>
      <th>5th</th>
    </tr>
  </thead>
  <tbody>
HTMLEOF

MEDAL_CLASSES=("m1" "m2" "m3" "m4" "m5")

for c in $CONCURRENCY_LEVELS; do
    # Sort implementations by RPS at this concurrency level
    sorted_at_c=()
    for k in "${KEYS[@]}"; do
        rps="${ALL_RPS[$k,$c]}"
        [ -z "$rps" ] && continue
        sorted_at_c+=("$rps $k")
    done
    sorted_at_c=($(printf '%s\n' "${sorted_at_c[@]}" | sort -rn))

    echo "    <tr><td class=\"podium-conns\">$c</td>" >> "$OUTPUT"

    i=0
    while [ $i -lt 10 ] && [ $i -lt ${#sorted_at_c[@]} ] && [ $((i / 2)) -lt 5 ]; do
        rps="${sorted_at_c[$i]}"
        k="${sorted_at_c[$((i + 1))]}"
        medal="${MEDAL_CLASSES[$((i / 2))]}"
        name="${NAMES[$k]:-$k}"
        color="${COLORS[$k]:-#888}"

        cat >> "$OUTPUT" << PODEOF
      <td class="podium-cell"><div class="podium-entry"><span class="podium-medal $medal">$((i / 2 + 1))</span><span class="podium-name" style="color:$color">$name</span><span class="podium-rps">$(fmt_num "$rps") req/s</span></div></td>
PODEOF
        i=$((i + 2))
    done

    echo "    </tr>" >> "$OUTPUT"
done

cat >> "$OUTPUT" << HTMLEOF
  </tbody>
</table>

<footer>
  Generated on $DATE &mdash; letloop benchmark suite
</footer>

</div>
</body>
</html>
HTMLEOF

echo "Report generated: $OUTPUT"
