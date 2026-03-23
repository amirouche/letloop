#!/bin/bash
# Generate HTML benchmark report from CSV results
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
NAMES[scheme-pico]="Scheme"
NAMES[bun]="Bun"
NAMES[deno]="Deno"
NAMES[go]="Go"
NAMES[javascript]="Node.js"
NAMES[rust]="Rust"
NAMES[gleam]="Gleam"
NAMES[fastapi]="FastAPI"
NAMES[flask]="Flask"
NAMES[racket]="Racket"
NAMES[c-h2o]="C (h2o)"

FRAMEWORKS[scheme-pico]="pico + io_uring"
FRAMEWORKS[bun]="Bun.serve()"
FRAMEWORKS[deno]="Deno.serve()"
FRAMEWORKS[go]="net/http (stdlib)"
FRAMEWORKS[javascript]="http (stdlib)"
FRAMEWORKS[rust]="axum + tokio"
FRAMEWORKS[gleam]="mist + gleam_otp"
FRAMEWORKS[fastapi]="uvicorn"
FRAMEWORKS[flask]="gunicorn (1 worker)"
FRAMEWORKS[racket]="web-server (stdlib)"
FRAMEWORKS[c-h2o]="libh2o-evloop"

COLORS[scheme-pico]="#ffffff"
COLORS[bun]="#f5e042"
COLORS[deno]="#01c2a9"
COLORS[go]="#00acd7"
COLORS[javascript]="#68a063"
COLORS[rust]="#f97316"
COLORS[gleam]="#ffaff3"
COLORS[fastapi]="#009688"
COLORS[flask]="#646cff"
COLORS[racket]="#9e1a20"
COLORS[c-h2o]="#e44d26"

# Build JSON data from CSVs
DATA_JSON=""
for csv in "$RESULTS_DIR"/*-scaling.csv; do
    key=$(basename "$csv" -scaling.csv)
    name="${NAMES[$key]}"
    framework="${FRAMEWORKS[$key]}"
    color="${COLORS[$key]}"

    if [ -z "$name" ]; then
        name="$key"
        framework="unknown"
        color="#888888"
    fi

    # Parse CSV rows (skip header), build JS array
    rows=""
    while IFS=, read -r conc rps avg_lat max_lat p99_lat errors; do
        [ "$conc" = "concurrency" ] && continue
        [ "$rps" = "0" ] && continue
        [ -n "$rows" ] && rows="$rows,"
        rows="$rows[$conc,$rps,$avg_lat,$max_lat,$p99_lat]"
    done < "$csv"

    [ -z "$rows" ] && continue

    [ -n "$DATA_JSON" ] && DATA_JSON="$DATA_JSON,"
    DATA_JSON="$DATA_JSON
  \"$name\": {
    framework: \"$framework\",
    color: \"$color\",
    rows: [$rows]
  }"
done

# Count implementations
IMPL_COUNT=$(echo "$DATA_JSON" | grep -c '"framework"' || true)

cat > "$OUTPUT" << 'HTMLHEAD'
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
    --accent: #6c8cff;
  }
  * { margin: 0; padding: 0; box-sizing: border-box; }
  body {
    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', system-ui, sans-serif;
    background: var(--bg);
    color: var(--text);
    line-height: 1.6;
    padding: 2rem;
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
  .rank { color: var(--muted); font-weight: 600; }
  .lang { font-weight: 600; }
  .num { font-family: 'SF Mono', 'Fira Code', monospace; font-size: 0.85rem; text-align: right; }
  .peak { color: #4ade80; font-weight: 600; }
  .bar-cell { width: 30%; }
  .bar-bg { background: var(--border); border-radius: 3px; height: 18px; overflow: hidden; }
  .bar-fill { height: 100%; border-radius: 3px; transition: width 0.6s ease; }
  .chart-container {
    background: var(--surface); border: 1px solid var(--border); border-radius: 8px;
    padding: 1.5rem; margin-bottom: 1.5rem;
  }
  .chart-title { font-size: 0.95rem; font-weight: 600; margin-bottom: 1rem; }
  canvas { width: 100% !important; }
  .legend { display: flex; flex-wrap: wrap; gap: 1rem; margin-bottom: 1rem; font-size: 0.8rem; }
  .legend-item { display: flex; align-items: center; gap: 0.4rem; cursor: pointer; opacity: 1; transition: opacity 0.2s; }
  .legend-item.hidden { opacity: 0.3; }
  .legend-dot { width: 10px; height: 10px; border-radius: 2px; flex-shrink: 0; }
  .details-grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(360px, 1fr)); gap: 1rem; margin-top: 1rem; }
  .detail-card { background: var(--surface); border: 1px solid var(--border); border-radius: 8px; padding: 1rem; }
  .detail-card h3 { font-size: 0.95rem; margin-bottom: 0.75rem; display: flex; align-items: center; gap: 0.5rem; }
  .detail-card table { font-size: 0.8rem; }
  .detail-card th { font-size: 0.7rem; }
  .info-row { display: flex; gap: 2rem; margin-bottom: 2rem; flex-wrap: wrap; }
  .info-box {
    background: var(--surface); border: 1px solid var(--border); border-radius: 8px;
    padding: 1rem 1.25rem; flex: 1; min-width: 180px;
  }
  .info-label { font-size: 0.75rem; color: var(--muted); text-transform: uppercase; letter-spacing: 0.05em; }
  .info-value { font-size: 1.4rem; font-weight: 700; margin-top: 0.2rem; }
  .info-detail { font-size: 0.8rem; color: var(--muted); }
  .top3-table td { vertical-align: middle; }
  .top3-conns { font-size: 1.1rem; font-weight: 700; font-family: 'SF Mono', 'Fira Code', monospace; text-align: center; width: 5rem; }
  .podium-cell { min-width: 200px; }
  .podium-entry { display: flex; align-items: center; gap: 0.5rem; }
  .podium-medal {
    width: 22px; height: 22px; border-radius: 50%; display: flex; align-items: center;
    justify-content: center; font-size: 0.7rem; font-weight: 700; flex-shrink: 0;
  }
  .medal-1 { background: #c9951c; color: #000; }
  .medal-2 { background: #8a8a8a; color: #000; }
  .medal-3 { background: #a0522d; color: #fff; }
  .medal-4 { background: #3a3d4a; color: var(--text); }
  .medal-5 { background: #2a2d3a; color: var(--muted); }
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

<div class="info-row" id="summary-row"></div>

<h2>Peak Throughput Rankings</h2>
<table id="rankings">
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
  <tbody></tbody>
</table>

<h2>Throughput Scaling</h2>
<div class="chart-container">
  <div class="chart-title">Requests/sec vs Concurrency</div>
  <div class="legend" id="rps-legend"></div>
  <canvas id="rpsChart" height="400"></canvas>
</div>

<h2>Latency Under Load</h2>
<div class="chart-container">
  <div class="chart-title">p99 Latency (ms) vs Concurrency</div>
  <div class="legend" id="lat-legend"></div>
  <canvas id="latChart" height="400"></canvas>
</div>

<h2>Per-Implementation Details</h2>
<div class="details-grid" id="details"></div>

<h2>Top 5 by Concurrency Level</h2>
<div class="chart-container">
  <table class="top3-table" id="top3-table">
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
    <tbody></tbody>
  </table>
</div>

<footer>
  Generated on <span id="date"></span> &mdash; letloop benchmark suite
</footer>

</div>

<script>
HTMLHEAD

# Inject data
cat >> "$OUTPUT" << DATABLOCK
const DATA = {$DATA_JSON
};
DATABLOCK

cat >> "$OUTPUT" << 'HTMLTAIL'

const CONC = [1, 2, 4, 8, 16, 32, 64, 128, 256];

const ranked = Object.entries(DATA).map(([name, d]) => {
  let peakIdx = 0;
  d.rows.forEach((r, i) => { if (r[1] > d.rows[peakIdx][1]) peakIdx = i; });
  const peak = d.rows[peakIdx];
  return { name, framework: d.framework, color: d.color, peakRps: peak[1], peakConns: peak[0], avgLat: peak[2], p99Lat: peak[4], rows: d.rows };
}).sort((a, b) => b.peakRps - a.peakRps);

const maxRps = ranked[0].peakRps;

// Summary cards
const summaryRow = document.getElementById('summary-row');
const first = ranked[0], second = ranked[1];
let lowestP99 = ranked[0], lowestP99Val = ranked[0].rows[0][4];
ranked.forEach(r => r.rows.forEach(row => { if (row[4] < lowestP99Val && row[4] > 0) { lowestP99Val = row[4]; lowestP99 = r; } }));
summaryRow.innerHTML = `
  <div class="info-box"><div class="info-label">Fastest</div><div class="info-value" style="color:${first.color}">${first.name}</div><div class="info-detail">${Math.round(first.peakRps).toLocaleString()} req/s (${first.framework})</div></div>
  <div class="info-box"><div class="info-label">Runner-up</div><div class="info-value" style="color:${second.color}">${second.name}</div><div class="info-detail">${Math.round(second.peakRps).toLocaleString()} req/s (${second.framework})</div></div>
  <div class="info-box"><div class="info-label">Lowest p99</div><div class="info-value" style="color:${lowestP99.color}">${lowestP99.name}</div><div class="info-detail">${lowestP99Val.toFixed(3)}ms</div></div>
  <div class="info-box"><div class="info-label">Implementations</div><div class="info-value">${ranked.length}</div><div class="info-detail">languages tested</div></div>
`;

// Rankings table
const tbody = document.querySelector('#rankings tbody');
ranked.forEach((r, i) => {
  const pct = (r.peakRps / maxRps * 100).toFixed(1);
  const tr = document.createElement('tr');
  tr.innerHTML = `
    <td class="rank">${i + 1}</td>
    <td class="lang" style="color:${r.color}">${r.name}</td>
    <td style="color:var(--muted)">${r.framework}</td>
    <td class="num peak">${Math.round(r.peakRps).toLocaleString()}</td>
    <td class="num">${r.peakConns}</td>
    <td class="num">${r.avgLat.toFixed(3)}</td>
    <td class="num">${r.p99Lat.toFixed(3)}</td>
    <td class="bar-cell"><div class="bar-bg"><div class="bar-fill" style="width:${pct}%;background:${r.color}"></div></div></td>
  `;
  tbody.appendChild(tr);
});

function drawChart(canvasId, legendId, getY, yLabel, logScale) {
  const canvas = document.getElementById(canvasId);
  const ctx = canvas.getContext('2d');
  const dpr = window.devicePixelRatio || 1;
  const rect = canvas.getBoundingClientRect();
  canvas.width = rect.width * dpr;
  canvas.height = rect.height * dpr;
  ctx.scale(dpr, dpr);
  const W = rect.width, H = rect.height;
  const pad = { top: 20, right: 30, bottom: 40, left: 70 };
  const cw = W - pad.left - pad.right;
  const ch = H - pad.top - pad.bottom;
  const xVals = CONC.map(c => Math.log2(c));
  const xMin = xVals[0], xMax = xVals[xVals.length - 1];
  let allY = [];
  ranked.forEach(r => r.rows.forEach(row => allY.push(getY(row))));
  allY = allY.filter(v => v > 0);
  let yMin, yMax, yMap;
  if (logScale) {
    yMin = Math.floor(Math.log10(Math.min(...allY)));
    yMax = Math.ceil(Math.log10(Math.max(...allY)));
    yMap = v => ch - ((Math.log10(v) - yMin) / (yMax - yMin)) * ch;
  } else {
    yMin = 0; yMax = Math.max(...allY) * 1.1;
    yMap = v => ch - ((v - yMin) / (yMax - yMin)) * ch;
  }
  const xMap = v => ((Math.log2(v) - xMin) / (xMax - xMin)) * cw;
  ctx.save(); ctx.translate(pad.left, pad.top);
  const hidden = new Set();
  function drawLines() {
    ctx.clearRect(0, 0, cw, ch + pad.bottom);
    ctx.strokeStyle = '#2a2d3a'; ctx.lineWidth = 0.5;
    if (logScale) { for (let p = yMin; p <= yMax; p++) { const y = yMap(Math.pow(10, p)); ctx.beginPath(); ctx.moveTo(0, y); ctx.lineTo(cw, y); ctx.stroke(); } }
    else { for (let i = 0; i <= 5; i++) { const v = yMin + (yMax - yMin) * i / 5; const y = yMap(v); ctx.beginPath(); ctx.moveTo(0, y); ctx.lineTo(cw, y); ctx.stroke(); } }
    ctx.fillStyle = '#8b8fa3'; ctx.font = '11px -apple-system, system-ui, sans-serif'; ctx.textAlign = 'right';
    if (logScale) { for (let p = yMin; p <= yMax; p++) { const v = Math.pow(10, p); ctx.fillText(v >= 1 ? v.toFixed(0) : v.toFixed(Math.abs(p)), -8, yMap(v) + 4); } }
    else { for (let i = 0; i <= 5; i++) { const v = yMin + (yMax - yMin) * i / 5; ctx.fillText(v >= 1000 ? (v/1000).toFixed(0) + 'K' : v.toFixed(0), -8, yMap(v) + 4); } }
    ctx.textAlign = 'center';
    CONC.forEach(c => ctx.fillText(c, xMap(c), ch + 20));
    ctx.fillText('Concurrency', cw / 2, ch + 36);
    ranked.forEach(r => {
      if (hidden.has(r.name)) return;
      ctx.strokeStyle = r.color; ctx.lineWidth = 2; ctx.beginPath();
      r.rows.forEach((row, j) => { const x = xMap(row[0]); const y = yMap(getY(row)); if (j === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y); });
      ctx.stroke(); ctx.fillStyle = r.color;
      r.rows.forEach(row => { const x = xMap(row[0]); const y = yMap(getY(row)); ctx.beginPath(); ctx.arc(x, y, 3, 0, Math.PI * 2); ctx.fill(); });
    });
  }
  drawLines(); ctx.restore();
  const legend = document.getElementById(legendId);
  ranked.forEach(r => {
    const item = document.createElement('div'); item.className = 'legend-item';
    item.innerHTML = `<span class="legend-dot" style="background:${r.color}"></span>${r.name}`;
    item.onclick = () => { if (hidden.has(r.name)) { hidden.delete(r.name); item.classList.remove('hidden'); } else { hidden.add(r.name); item.classList.add('hidden'); } ctx.save(); ctx.translate(pad.left, pad.top); drawLines(); ctx.restore(); };
    legend.appendChild(item);
  });
}

drawChart('rpsChart', 'rps-legend', r => r[1], 'req/s', false);
drawChart('latChart', 'lat-legend', r => r[4], 'p99 ms', true);

const details = document.getElementById('details');
ranked.forEach(r => {
  const card = document.createElement('div'); card.className = 'detail-card';
  let rows = r.rows.map(row => `<tr><td class="num">${row[0]}</td><td class="num">${Math.round(row[1]).toLocaleString()}</td><td class="num">${row[2].toFixed(3)}</td><td class="num">${row[4].toFixed(3)}</td></tr>`).join('');
  card.innerHTML = `<h3><span class="legend-dot" style="background:${r.color};display:inline-block"></span>${r.name} <span style="color:var(--muted);font-weight:400;font-size:0.8rem">${r.framework}</span></h3><table><thead><tr><th class="num">Conns</th><th class="num">Req/s</th><th class="num">Avg (ms)</th><th class="num">p99 (ms)</th></tr></thead><tbody>${rows}</tbody></table>`;
  details.appendChild(card);
});

const top3Tbody = document.querySelector('#top3-table tbody');
const medals = ['medal-1', 'medal-2', 'medal-3', 'medal-4', 'medal-5'];
CONC.forEach((conc, ci) => {
  const entries = Object.entries(DATA).map(([name, d]) => ({
    name, color: d.color, rps: d.rows[ci] ? d.rows[ci][1] : 0
  })).sort((a, b) => b.rps - a.rps).slice(0, 5);
  const tr = document.createElement('tr');
  tr.innerHTML = `<td class="top3-conns">${conc}</td>` + entries.map((e, i) =>
    `<td class="podium-cell"><div class="podium-entry"><span class="podium-medal ${medals[i]}">${i + 1}</span><span class="podium-name" style="color:${e.color}">${e.name}</span><span class="podium-rps">${Math.round(e.rps).toLocaleString()} req/s</span></div></td>`
  ).join('');
  top3Tbody.appendChild(tr);
});

document.getElementById('date').textContent = new Date().toLocaleDateString('en-US', { year: 'numeric', month: 'long', day: 'numeric' });
</script>
</body>
</html>
HTMLTAIL

echo "Report generated: $OUTPUT"
