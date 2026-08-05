# City-explorer: how letloop went from last place to second

**Date:** 2026-08-02
**Repos:** `letloop/invvv` (benchmark app + corpus), `letloop/north` (runtime)
**Question asked:** three implementations of the same app — letloop (Chez Scheme,
flow/io_uring), Rust (axum/tokio), Bun — and the letloop one is the slowest,
even against JavaScript. Why?

## TL;DR

The letloop implementation was not slow at serving HTTP, scheduling fibers, or
driving io_uring — it was slow at *transcoding payloads*. Scalar Scheme base64
of the city photograph consumed ~80% of the per-request CPU budget, with
char-by-char JSON parsing next in line. Three targeted fixes — a SIMD base64
encoder behind the FFI, a bytevector-indexed JSON parser, and 16KB io_uring
provided buffers — took letloop from 1,974 to 5,249 req/s on the reference
workload (pinned Paris, 448KB page, c=4): **2.7x faster, ahead of Bun, within
~10% of axum**. A GC-tuning attempt was measured and rejected. Two benchmark
traps (SO_REUSEPORT port-sharing and a silently failing `fuser -k`) invalidated
whole measurement rounds before being caught, and are worth remembering.

## The workload

Every request builds a complete HTML page for one city: pick the city, look up
its Wikidata QID in the warm index, fan out four concurrent HTTP GETs to local
nginx mock upstreams (wikipedia summary, wikiquote, weather, commons photo),
parse three JSON bodies, base64 the photo into a CSS `url(data:...)`, render.
Median corpus image is ~290KB, so a typical page is ~450KB. All servers are
single-threaded and pinned to core 0; wrk runs on other cores; upstream nginx
answers in 10–21µs, so all three implementations are CPU-bound.

## Investigation

Reproduced baseline (pinned Paris, all full 448KB pages, single verified
process per port): **letloop 1,974 / axum 4,269 / bun 4,834 req/s** at c=4.

`perf` was unavailable (perf_event_paranoid=4, no sudo), so attribution came
from microbenchmarks run inside the same Chez runtime at optimize-level 3, on
the real corpus payloads, against the request budget implied by throughput
(1,974 req/s on one core ⇒ 506µs/request):

| component (per request) | cost |
|---|---|
| base64 of the 335KB Paris image (scalar Scheme) | **409µs** |
| JSON parse ×3 (`(letloop json)` via textual port) | ~36µs |
| `http-response-read` reader machinery, 4KB chunks | ~20µs |
| page assembly (bytevector-append of 448KB) | ~9µs |
| request serialization ×4 | ~1.5µs |

Base64 alone was ~80% of the budget. For calibration, Bun encodes the same
335KB in **15.8µs** (SIMD `Buffer.toString('base64')`, 26x) and parses the 5KB
wikipedia record in 4.3µs vs Chez's 27µs.

Two findings cleared the runtime itself:

- Under load the process was 87% user / 13% sys CPU — the io_uring/flow layer
  was not where time went.
- With upstreams down (fan-out failing fast, tiny degraded pages), letloop was
  the *fastest* of the three (34.3k vs 29.2k/32.5k req/s) — raw request
  handling and the fiber fan-out were already competitive.

One real runtime-level cost did surface: `%buf-ring-buf-size` was 4KB, so a recv
can deliver at most 4KB per completion, and a 335KB body cost ~84 full
suspend/resume + SQE/CQE + copy round trips per fetch.

## Fixes

### 1. SIMD base64 via FFI (invvv `d1f561d`)

`apps/letloop/b64simd.c`: the Muła/Lemire reshuffle+translate kernels — AVX2
main path (24 bytes in / 32 out per iteration), SSSE3 fallback, runtime CPU
dispatch, scalar reference for tails and non-x86. Loaded from Scheme with
`load-shared-object` + `foreign-procedure` (`u8*` bytevector passing, no
copies), resolution order `B64SIMD_LIB` env → `LD_LIBRARY_PATH` →
corpus-relative, falling back to the scalar loop if absent. The C self-test
compares SIMD paths against the scalar reference for every input length
0–4096. Served pages verified byte-identical scalar vs SIMD.

Effect: 409µs → ~16µs per image; letloop 1,974 → ~4,555 req/s (c=4).

### 2. Bytevector JSON parser (invvv `ccbf587`)

`json-read-bytevector` indexes the raw UTF-8 bytevector directly — safe because
quote (0x22) and backslash (0x5C) can never appear inside UTF-8 continuation
sequences — decodes plain strings with a single slice, fast-paths integer
literals, and handles full escape/surrogate-pair forms. It reproduces
`(letloop json)`'s exact representation (alists with symbol keys in reverse
source order, arrays as vectors, `'null`), verified `equal?` against
`json-read` on **all 9,785 corpus JSON files** plus edge cases. The equivalence
suite caught one real bug before deployment (a `let` vs `let*`
evaluation-order slip that duplicated escaped characters). `html-escape` also
gained a scan-first fast path returning the input unchanged when clean.

Effect: wikipedia record 27.2 → 8.5µs; weather 5.7 → 3.4µs.

### 3. 16KB provided buffers (north `c7d3889`, branch `dev-feature-literacy`)

`%buf-ring-buf-size` 4KB → 16KB in `(letloop liburing low)`. Buffer size caps
bytes-per-completion for buffer-select recv, so the median image now costs ~21
round trips instead of ~84. Entry count stays 4096 because each parked
keep-alive connection pins one pending buffer-select recv — entries bound
concurrent connections — growing the pinned pool 16MB → 64MB. All 44
low/flow/http-server checks pass (`LD_LIBRARY_PATH=local/lib` so
`libpicohttpparser.so` resolves; without it two checks error spuriously).

## Dead end, measured: GC tuning

A full page allocates ~1.3MB (body chunks, base64 output, page assembly), so
collections are frequent. Raising `collect-trip-bytes` to 16MB (and 4MB) was
tried and is **~2% worse** than the default at c=16 in a clean interleaved A/B
(default 3,884/3,896/3,807 vs 16MB 3,812/3,724/3,797 req/s): a larger nursery
scans more live in-flight pages per collection and loses cache locality. The
first, non-interleaved attempt had suggested −13%, but that measurement was
contaminated (below). The productive direction is allocating less, not
collecting less often.

## The two benchmark traps

**SO_REUSEPORT.** `loop-tcp-serve` sets it
(`src/letloop/liburing/low.scm`), so a stale server does not fail to bind — it
silently *shares* the port and the kernel round-robins new connections across
processes. Symptoms observed before diagnosis: bimodal throughput, mixed
response sizes in one run, "metastable degradation" that survived restarts. At
one point six servers shared port 9002. Worse for A/B tests: processes pinned
to the same core blend their throughput, so a stale old binary quietly dilutes
the new binary's measurement.

**`fuser -k` fails silently here.** It reported nothing killed nothing, every
"cleanup" leaked the previous server, and each benchmark round added one more
process behind the port. The working pattern, now in the session's
`hygiene.sh`: kill by PIDs taken from `ss -ltnp` (filter
`$4 ~ (":" port "$")`), then *assert exactly one listener* before trusting any
number. Every result below was collected under that guard, 3 trials, medians.

## Results (pinned Paris, 448KB page, single core, 3-trial medians)

| | c=4 | c=16 |
|---|---|---|
| Rust / axum | 5,756 | 4,647 |
| **letloop (after)** | **5,249** | **4,115** |
| Bun | 4,847 | 3,931 |
| letloop (before) | 1,974 | ~1,700 |

letloop moved from last to second at every level, ahead of Bun, ~9–11% behind
axum. The remaining gap sits in reader copies, per-fetch fiber machinery, and
allocation churn (~1.3MB/request) — each addressable, none free.

The public artifact ("City Explorer: letloop vs Rust/axum vs Bun") was
regenerated with the same protocol it used originally: three pinned cities
spanning the size range, c=1/4/16/64, wrk 3s warmup + 10s measured, p50/p99
recorded, one verified listener per port. letloop req/s, with the morning
(pre-optimization) run in parentheses:

| city / page | c=1 | c=4 | c=16 | c=64 | cell rank after |
|---|---|---|---|---|---|
| Gastonia, 182KB | 8,399 (3,376) | 10,175 (4,202) | 9,120 (4,150) | 6,821 (3,490) | 2nd / ~tie / 2nd / 2nd |
| Tabuk, 380KB | 5,498 (2,064) | 6,058 (2,211) | 4,956 (2,135) | 3,498 (1,785) | **1st / 1st** / 2nd / 2nd |
| Bani Walid, 1.4MB | 896 (559) | 1,475 (591) | 1,040 (540) | 790 (446) | 3rd / 2nd / 3rd / 3rd |

Every cell is 1.6–2.7x its morning value. letloop now wins the 380KB page
outright at low concurrency and ties axum on the 182KB page at c=4; axum still
takes every page size at c=64, and Bun keeps the 1.4MB page at low concurrency.

## Follow-ups worth considering

- Faster string decode in the JSON parser (the 8.5µs is mostly `utf8->string`
  slices and symbol interning).
- A sized-read primitive for known-content-length bodies, skipping the
  buffer-ring for large transfers entirely.
- Reduce per-request allocation: reuse fan-out buffers across requests, or
  stream the page instead of assembling one 448KB bytevector.
- Upstream `json-read-bytevector` into `(letloop json)`.
- Fold the single-listener assertion into `benchmarks/bench.sh` — its
  `kill_tree` + fixed `BASE_PORT=19100` can replay the SO_REUSEPORT trap across
  invocations.
