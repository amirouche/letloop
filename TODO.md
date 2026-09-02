# TODO

- **CONFIRMED BUG, found 2026-08-14: `(letloop flow)` channels
  (`flow.scm`) never compact dead entries under sustained
  low-backlog, high-throughput use, leaking every payload ever put
  through them for the channel's whole lifetime.** Root cause:
  `flow-channel-compact!` (the `filter flow-channel-entry-waiting?`
  pass that actually drops dead entries from a channel's `puts`/`pops`
  lists) only runs from `flow-channel-bump-gc!`, called ONLY on the
  blocking-registration path (`flow-put-block`/`flow-get-block`) when
  its shared counter crosses `%flow-channel-gc-threshold` (1024). A
  rendezvous resolved via the non-blocking `flow-put-try`/
  `flow-get-try` path -- the common case when a channel's producer and
  consumer are both keeping up, i.e. exactly steady-state healthy
  operation -- matches and resumes the waiting peer's entry but never
  removes it from the list and never bumps the counter. So a channel
  under sustained throughput where most operations resolve via try
  accumulates dead entries indefinitely; each `<flow-channel-entry>`
  still holds its `value` field (the real payload) even once "resolved",
  so nothing it ever carried is ever collected.

  Found chasing a downstream indexing pipeline's unbounded RSS growth
  (44GB and climbing on a large corpus pass, no plateau across chunk
  boundaries). The compute-step business logic (html->sxml,
  capsule-extract, language-detect, stemmer, document-postings) was
  proven completely clean by direct repeated-allocation testing --
  identical bytes-allocated across 8 passes over the same 197
  documents, and actually DECREASING bytes-allocated over 1750
  distinct documents. The channels between io-source/compute/owner
  were the only remaining candidate, and adding raw internal list-
  length instrumentation (`flow-channel-puts-length`/
  `flow-channel-pops-length`, temporary diagnostic export) confirmed
  it directly: at 70 total batch-channel puts (with logical pending
  always exactly 0 -- every message already matched to a consumer),
  the raw internal `puts` list still held 62 entries; at 68 total
  kv-channel gets, the raw `pops` list held 54. The ratio stayed
  ~80-90% of cumulative throughput the entire run, never dropping --
  i.e. essentially nothing was ever actually being freed, despite the
  channel LOOKING logically balanced the whole time.

  Fix candidates: (1) bump the gc-counter (or otherwise trigger
  compaction) on every successful match, not only on blocking
  registrations -- cheapest, keeps the existing periodic-filter
  design; (2) remove a matched entry from its list immediately upon
  claim in `flow-put-try`/`flow-get-try`/the block-path rendezvous,
  rather than deferring to periodic compaction at all -- more
  correct, no threshold-dependent lag window, but touches the hot
  path on every single operation instead of amortizing over 1024.
  Long-lived, high-throughput channels (this indexer's kv-channel/
  batch-channel, one per chunk, thousands of messages each) are where
  this bites; short-lived per-request channels (e.g. a search
  server's per-query `ngram-channel`, discarded whole after each
  query) are far less exposed since the channel itself becomes
  garbage before the lag matters.

- api: cookies: parse and set cookies with a Map-like API.
- api: http router: dynamic paths and wildcards.
- api: http server: the idle-connection reaper (`http/server.body.scm:314-328`, `%idle-timeout-seconds = 30`) force-closes a connection after 30s with no read/write activity on ITS OWN fd -- but it has no notion of "a request is in flight and the server is computing its response via I/O on OTHER fds" (e.g. upstream fetches for a slow handler). A handler that legitimately takes longer than 30s gets its client connection killed mid-response, producing a bare connection reset / empty reply with NO server-side log line at all. Found 2026-08-14 reproducing this against a downstream search server's real production database: `q=algorithme` returned in 20.5s (succeeded), `q=scheme` under the same load got no reply at all (reaped, presumably just past 30s) -- same server, same code path, the only difference was which side of 30s the query landed on. Fix: touch the connection's last-active timestamp when dispatch starts and when it ends (not only on raw socket I/O), so a truly idle connection still gets reaped but an in-flight one never does regardless of how long its handler runs. Worth checking whether this explains part of the "keep-alive gets worse under concurrency" finding logged just above: a connection reaped mid-request presents to a load generator as a hard reset/collapse, not a slow-but-completing response, and more concurrent load -> individual requests more likely to cross 30s -> more reaped connections.
- api: http server: harden (letloop http server) and `letloop http serve`: chunked request bodies, streaming responses, richer error handling.
- api: http server: RESOLVED 2026-08-14 — verified under real concurrent HTTP/1.1 load whether the fixed call-with-loop-prompt bug ever actually fired in `handle-connection`. Two corrections to the original premise, found while building the reproducer: (1) `handle-connection` does NOT run under `flow-choice`/`flow-timeout` — that per-connection idle-timeout shape was tried in `ec70498` and reverted in `05ab523` (cost ~19% throughput to CML bookkeeping overhead), current code uses plain `read`/`write` closures from `loop-tcp-serve`'s accept, self-recursing in `handle-loop`; (2) it still suspends/resumes via `call-with-loop-prompt` on every `read`/`write` (those are `loop-read`/`loop-write`, built on `loop-abort`/`call/1cc`), so the general shape the fix addresses is still exercised continuously, just not through `flow-choice`. Reproducer: `checks/repro-keepalive-dispatch-lib.scm` (server, no downstream-application dependency, logs every request's unique token) + `checks/repro-keepalive-dispatch-client.scm` (drives real keep-alive connections doing many sequential requests each, plus fresh-connection-per-request controls, over real sockets via `loop-connect`/`loop-write`/`loop-read`). Result at 100 connections × 50 requests (5000 keep-alive) + 5000 fresh, and again at 8 connections × 300 requests (2400 keep-alive) + 200 fresh: **zero duplicate dispatches** in every run — every token dispatched exactly once. Latency is the textbook keep-alive shape: request 1 on a connection pays full connection-setup cost (matches fresh-connection latency almost exactly), requests 2+ drop to a small fraction of that and stay flat out to 300 requests on one connection, no growth trend. Conclusion: this bug is not live in `handle-connection` today, and the server layer shows no keep-alive pathology in isolation — see a downstream project's own bench-server tracking notes, whose "keep-alive slower than fresh, gets worse with concurrency" finding this reproducer was built to chase; since it doesn't reproduce here with a trivial handler, the cause is very likely specific to that server's own heavier per-request path (scoring/storage/worker dispatch), not this library.
- api: http client: give (letloop tls uring)'s `www-request` and (letloop tls base)'s `https-request` ONE interface, and rename the synchronous one to `https-request/sync` so which is which is visible at the call site. Today they differ silently in ARITY: `www-request` returns `(values code headers body)` while `https-request` returns `(values version code reason headers body)`. Swapping one for the other therefore fails at run time with "incorrect number of values received in multiple value context" -- or, worse, succeeds against a wrapper that discards the extras and then silently drops data. Both failure modes were hit while benchmarking atlas-stoa: one crash, and one case where a marshalling layer kept only the first of five values so every S3 read returned garbage and queries quietly returned ZERO results while still looking fast. The names compound it -- `www-` vs `https-` says nothing about blocking versus coroutine-parking, and a benchmark that reached for the blocking one inside a flow loop measured a code path production never runs (a blocking call stalls the single OS thread every fiber shares, so nothing overlaps), producing a 5-15x error and nearly sending a bug hunt after a non-bug.
- api: http server: the listen backlog is hardcoded to 128 (`liburing/low.scm:2581`, `(loop-listen fd 128)`) while this host's `somaxconn` is 4096. A wrk run against a consumer opening 640 connections at once measured a 10.1% error rate with `netstat -s` reporting 12,661 listen-queue overflows and 12,676 SYNs dropped -- i.e. connections refused before the server ever saw them, which reads as a capacity limit but is not one. Make it a parameter (default at least 1024, or read `somaxconn`), and note it compounds under SO_REUSEPORT: N processes each get their own 128-slot queue, so the apparent limit moves with process count and is easy to misattribute to the application.
- api: json: parser review and improvements: correctness, readability, CLI.
- api: redis: built-in client with Pub/Sub support.
- api: s3: upload/download from S3-compatible cloud storage.
- api: secrets: encrypted secrets storage with OS-native keychain integration.
- api: single-file executables: compile to a standalone executable.
- api: sql drivers: PostgreSQL, MySQL, SQLite, and LMDB with a fast, unified SQL/KV API.
- api: websocket server: including pub/sub and backpressure handling.
- api: yaml: first-class support, like JSON.
- core: async i/o: consolidate the untangle prototypes on the io_uring loop; the async HTTPS client (letloop tls uring) is tested against httpbin, epoll variants remain experimental.
- core: jsx: first-class support without configuration.
- core: module loader plugins: plugin API for importing/requiring custom file types.
- core: native addons: call C-compatible native code from JavaScript.
- core: node.js compatibility: drop-in replacement for Node.js apps.
- core: typescript: first-class support, including "paths" enum namespace.
- core: web standard apis: fetch, URL, EventTarget, Headers, etc.
- desktop: 2d graphics: Cairo or Skia bindings for custom rendering, canvas-style drawing.
- desktop: app packaging: produce .deb/.rpm, .dmg, .msi, AppImage, and Flatpak bundles.
- desktop: audio / media: SDL_mixer, PipeWire, or PortAudio bindings for playback and recording.
- desktop: auto-updater: delta updates with cryptographic signature verification.
- desktop: clipboard: read and write text/image data from the system clipboard.
- desktop: d-bus: Linux system/session bus integration for IPC with system services.
- desktop: file system watching: unified abstraction over inotify (Linux), FSEvents (macOS), kqueue (BSD).
- desktop: gui native toolkit: GTK, Qt, or SDL2 bindings for native look-and-feel.
- desktop: gui webview: embed a browser engine (Tauri/Electron model) for cross-platform HTML/CSS UI.
- desktop: hardware access: camera, microphone, and GPU compute (OpenCL/Vulkan) bindings.
- desktop: ipc: pipes, Unix domain sockets, named pipes; D-Bus on Linux.
- desktop: keymaps: the evdev keymap is US-QWERTY only; the scancode table has structure for swapping, add more layouts.
- desktop: multi-window rendering: the render loop is a single cooperative thread; a second window needs a dedicated render thread consuming damage commands over a channel.
- desktop: native dialogs: file picker, message boxes, color picker via OS-native APIs.
- desktop: notifications: OS push notifications (libnotify on Linux, UNUserNotificationCenter on macOS).
- desktop: oauth2 pkce: desktop-specific auth flow using loopback redirect URI.
- desktop: repl port redirection: the graphical REPL reads only from its line editor; redirect current-input/output/error ports into the window so display/write from evaluated code renders there.
- desktop: rtl shaping: Arabic glyphs render in logical order; real right-to-left shaping still pending.
- desktop: shader build step: shaders are handwritten GLSL compiled to SPIR-V offline and embedded as bytevectors; as they accumulate, add an in-tree shader build step (or a Scheme→SPIR-V compiler).
- desktop: system tray: OS tray icon with context menu (libappindicator / systray).
- ecosystem: authentication: OAuth, sessions, JWT, etc.
- ecosystem: cryptography: symmetric/asymmetric encryption beyond hashing.
- ecosystem: data structures: standard collections beyond arrays and maps.
- ecosystem: error handling: structured errors, result types, stack enrichment.
- ecosystem: html parser: with SXPath and CSS selector support, based on justhtml (https://github.com/EmilStenstrom/justhtml/).
- ecosystem: regexes: extended regex support or a dedicated library.
- ecosystem: serialization: formats beyond JSON/YAML (MessagePack, CBOR, Protobuf, etc.).
- ecosystem: tls / http client: openssl/libtls bindings for Chez Scheme, or libcurl bindings.
- reference: bun: https://bun.com/reference
- reference: codeberg: https://codeberg.org/amirouche/letloop
- review: scroll jump on fold: when a folded (define ...) is at the top of the viewport and the cursor reaches the viewport bottom, scroll jumps by the entire fold size (N raw lines) in one keypress, because advancing past a fold-start requires skipping to fold-end+1; visually jarring, no clean fix without auto-expanding folds on scroll.
- tls: make target: build libtls (LibreTLS) from a `make tls` target instead of relying on distro packages or the stub-.so workaround documented in CLAUDE.md.
- tooling: bundler: production-ready code for frontend & backend, works with packages.
- tooling: documentation source: canonical reference that most libraries link to.
- tooling: error messages: source code locations, snippets, and explanations.
- tooling: formatter & linter: built-in.
- tooling: frontend development server: fully-featured dev server.
- tooling: hot reloading (server): reload backend without disconnecting connections.
- tooling: jest-compatible test runner: compatible with Jest.
- tooling: language server: IDE integration (go-to-definition, completions, etc.).
- tooling: monorepo support: workspaces and cross-workspace commands.
- tooling: npm package management: install, manage, and publish npm-compatible dependencies.
- tooling: online playground: run and share code in the browser.
- tooling: project generator: scaffold new projects.
- tooling: shell api: cross-platform $ shell, native bash-like scripting.
- tooling: version manager: install and switch between language versions.
- util: csrf: generate and verify CSRF tokens.
- util: css color conversion: convert between CSS color formats.
- util: glob: glob patterns for file matching.
- util: password & hashing: bcrypt, argon2, and non-cryptographic hashes.
- util: semver: compare and sort semver strings.
- util: string width: calculate terminal display width of a string.
- web: background jobs: async workers, retry logic, scheduling, dead-letter queues.
- web: config management: TOML and dotenv parsing, layered config (env > file > defaults).
- web: database migrations: schema versioning tool; up/down migrations, state tracking.
- web: email (smtp client): send transactional email; support TLS, AUTH, attachments.
- web: graphql: server (schema + resolvers) and client (query execution).
- web: grpc: Protobuf code generation and streaming RPC over HTTP/2.
- web: headless browser control: drive a browser via CDP/Playwright protocol for E2E and functional tests.
- web: i18n / l10n: internationalization: message catalogs, plural rules, locale-aware formatting.
- web: metrics + tracing: OpenTelemetry-compatible instrumentation; counters, histograms, spans.
- web: middleware pipeline: composable request/response middleware with `next` chaining.
- web: multipart / form-data: parse multipart/form-data requests for file uploads and HTML form submissions.
- web: rate limiting: per-IP, per-user, and global limits; token-bucket and sliding-window algorithms.
- web: sse (server-sent events): lightweight alternative to WebSocket for server-push streams.
- web: structured logging: JSON log output, log levels, request-scoped context propagation.
- web: template engine: server-side HTML rendering (Mustache/Jinja-style); composable, escapable, streaming-friendly.
- web: wasm target: compile Scheme to WebAssembly for in-browser execution.

## dubito ergo cogito — sexp assembler JIT

State as of 2026-08-03: stages 0–5 plus codegen quality are done on
branch `dev-dubito-ergo-cogito` — (letloop asm), (letloop base64),
(letloop kernel) with the kernel/assembly expression forms, dubito v1,
and SIB fusion + lea synthesis + CSE + LICM; the simili-Scheme LOUDS
tier measures ahead of the C .so and within ~4% of hand-written
assembly (atlas-stoa benchmarks/louds-simd, RESULTS.md addenda 8–9).
Plan: plans/v12/20260802-sexp-assembler-jit.md. Spec artifact:
https://claude.ai/code/artifact/16d0776d-cb06-4026-9933-d1a8187ad3a1

Blocked on credentials:

- push: `dev-dubito-ergo-cogito` (north), `stoa2` (atlas-stoa) and
  `main` (invvv) are committed but unpushed — ssh-agent/GH_TOKEN
  unavailable in the working session.

Milestone hygiene (mechanical, one session):

- jit: flip city-explorer's default base64 mode to jit (B64_MODE=jit
  proved byte-identical pages and +1% throughput); demote b64simd.c
  to reference/fallback so "zero C toolchain" holds without env vars.
- jit: one clean end-to-end gate run as the closing record: full
  atlas-stoa run.sh (5 tiers + writer parity + checksum agreement)
  and the official invvv bench.sh sweep with the letloop-jit key.
- jit: review pass over the ~2000 new lines before merging —
  the CSE/LICM interaction with the register allocator most of all.
- jit: merge decision: dev-dubito-ergo-cogito → dev gates other
  branches consuming (letloop kernel).

Stage 6 / v13 research, in order of leverage:

- kernel: vector simili Scheme: a v256 type with shuffle/arith ops so
  the base64 kernel can climb from the assembly floor to the kernel
  floor; VEX encoding and the translator already exist below it.
- dubito: range analysis: derive from the (assert ...) entry guards
  that every load is in bounds, upgrading the verdict from verified
  (well-typed) toward sound (memory-safe).
- dubito: termination evidence for kernel loops.
- kernel: sum via SINK's meta operative once the v13 vau fusion lands
  (plans/v13/20260730-fusion-vau-primary-language.md), retiring the
  procedure-keyed registry.

Deliberately deferred (fine to leave): the last ~4% to hand assembly
(value-preserving copy movs, rename-eliminated on modern cores),
code-page reclamation, cpuid-based feature detection instead of
/proc/cpuinfo, ARM/NEON, base64 decode kernel, sar/div/cmov and other
mnemonics until a kernel needs them.

## flow: monitored trees with automatic timeout-and-cancel

A `flow-choice(primary, flow-timeout(...))` race per REQUEST already
exists (atlas-stoa's hedged reads use exactly this), but nothing here
scopes a timeout over a WHOLE TREE of concurrent work -- N fibers doing
network I/O and/or compute, fanned out together, where "this query's
budget ran out" should cancel every still-running branch (every
in-flight read, every nested spawn) at once, not just race one read
against one clock.

Concretely missing, hit live: atlas-stoa's stoa3-v4-search-serve.scm
fans one query out into one fiber per ngram (each doing a real S3
read), then waits for ALL of them via a `flow-get!` loop expecting
EXACTLY `(length ngrams)` messages -- there is no primitive for "give
this whole fan-out N milliseconds, and whatever hasn't answered by
then, cancel its I/O and stop waiting on its message." Two pieces of
defensive plumbing stand in for it today, neither of which actually
bounds the query's own latency: (1) every fetch fiber must be guarded
so a raise still `flow-put!`s SOMETHING, or the wait loop hangs
forever on a message a dead fiber will never send (this was live: a
connection flood hung every worker thread and leaked ~10GB in minutes
before the guard was added); (2) the top-level HTTP framework's idle-
connection reaper eventually notices, on its own sweep interval, long
after the fact.

Shape sketch: `(flow-monitor timeout-seconds (lambda () ...spawn a
subtree of fibers/network ops... ))`, tracking every fiber and ring op
spawned inside its dynamic extent, firing real cancellation for each on
timeout (or on the thunk itself raising) -- the same
`register-cancel!`/`IORING_OP_*_CANCEL` machinery `flow-choice` already
uses per-base, generalized from a fixed vector known at `flow-choice`
call time to an arbitrary, dynamically-grown set. Open question: a
fiber spawned INSIDE the monitored thunk that itself spawns MORE
fibers -- swept transitively (a tree) or only one level (a set)? The
former is what "cancel a query's whole outstanding work" actually
needs.

Related: the flow-block-and-wait-off-loop entry directly below (ring
events prepped from a worker thread) -- any monitored-tree primitive
used from worker-dispatched code inherits the same off-loop hazard and
needs the same flow-worker-io wrapping discipline; stoa3-v4-search-
serve.scm hit this too (hedged-www-request's flow-timeout called
directly from a flow-worker-call-dispatched fiber) while chasing the
leak above.

## flow-block-and-wait-off-loop registers ring events from the worker thread

`flow-block-and-wait` dispatches on `%worker-current?`. The off-loop
variant then calls each event's block-proc INLINE, on the worker:

```scheme
(for-each (lambda (base)
            ((flow-block-proc base) state resume register-cancel!))
          bases)
```

For channel events that is safe -- their block-procs only touch CAS
boxes -- which is why `flow-worker-call` and `flow-worker-io` work and
why worker mode looks fine until it does not. For anything that preps an
SQE (`flow-timeout`, `flow-read`, `flow-write`, `flow-accept`,
`flow-open`, `flow-read-at`) the block-proc calls `loop-get-sqe`,
`io-uring-prep-*`, `io-uring-sqe-set-data64` and `hashtable-set!` on
`(loop-handlers (loop-current))` -- all loop-thread-only state, from the
wrong thread.

Observed downstream as a hard crash: atlas-stoa's h9p3r server, running
query workers, died with `nonrecoverable invalid memory reference` /
`status=6/ABRT` under ~20 simultaneous requests, and hung for 25 minutes
on another occasion. Worker mode has been forced off there ever since.

**The same file already applies the correct rule to cancels**, twenty
lines above, with the comment "Cancels touch the ring, so they must run
ON the loop even though we are not on it", marshalling them through
`%flow-spawn-safe`. Registrations were not given the same treatment. The
asymmetry is the bug.

**Fix**: marshal the registration for-each through `%flow-spawn-safe`
too, so SQE preparation happens on the loop while only the
condition-variable wakeup happens on the worker. Registration becoming
asynchronous is safe: `resume-from`'s `box-cas!` still elects one
winner, and the worker either finds `done?` already set or waits as it
does now.

**Check that must exist before worker mode is trusted again** (its
absence is why this shipped): perform a `flow-timeout` -- or any
ring-touching event -- from a worker thread and assert it completes
correctly rather than corrupting the ring. Today nothing fails when an
SQE is prepped off-loop; it simply breaks later, somewhere else.
`~check-flow-worker-io-runs-on-loop` covers the path that was already
right.

Measured while investigating: three different queries on three workers
took 5,435ms against 11,538ms serial -- a real 2.1x, with the parallel
total equal to the slowest single query. Worker mode is worth fixing,
not deleting. That harness had no HTTP server, so it never exercised
`flow-accept`/`flow-read` off-loop, which is consistent with the crash
living in the serving path rather than in query execution.

### Consumer note

Anything that performs a ring event must run on the loop. In atlas-stoa
that means hedged requests (`(atlas-stoa hedge)`, which uses
`flow-timeout`) have to wrap the INNER client inside the
`flow-worker-io` thunk, not the outer request function -- wrapping
outside would prep the timeout SQE from the worker and reproduce this
crash exactly.

## dns.body.scm preps SQEs without null-checking io_uring_get_sqe

`io_uring_get_sqe()` returns NULL when the submission queue is full.
`loop-get-sqe` (`src/letloop/liburing/low.scm:1998`) exists to handle
exactly that -- submit, retry once, then raise `"submission queue
full"`:

```scheme
(define loop-get-sqe
  (lambda (ring)
    (let ((sqe (io-uring-get-sqe ring)))
      (if (eqv? sqe 0)
          (begin
            (io-uring-submit ring)
            (let ((sqe (io-uring-get-sqe ring)))
              (if (eqv? sqe 0)
                  (error 'loop "submission queue full")
                  sqe)))
          sqe))))
```

31 call sites in `flow.scm` use it. `dns.body.scm` does not -- four raw
`io-uring-get-sqe` calls, each feeding its result straight into a prep
with no check in between:

| line | prep |
|---|---|
| 247 | `io-uring-prep-connect` |
| 261 | `io-uring-prep-send` |
| 275 | `io-uring-prep-recv` |
| 285 | `io-uring-prep-link-timeout` |

All four are built on `io_uring_prep_rw`, which writes fields *through*
the SQE pointer it is handed. With a full SQ that is a write through
address 0.

Note this is a DIFFERENT defect from the entry above, and the earlier
one being fixed does not cover it: there the problem was the right call
made from the wrong thread; here it is a missing null check on the loop
thread itself.

### Observed

atlas-stoa's search server (TODO 0x004D there), 2026-08-24. Symptom is
`Exception: invalid memory reference. Some debugging context lost`,
logged repeatedly while the server keeps serving -- 112 lines in one
~4-minute production window, and 752 from a single round of 12
concurrent queries in a scratch reproduction.

Caught under `gdb -p PID -batch -ex 'handle SIGSEGV stop print pass'
-ex continue -ex 'thread apply all bt'`:

```
#0  io_uring_prep_rw () from .../liburing-ffi.so.2
#1  0x00000000447db548 in ?? ()          <- Scheme frame
#3  S_call_help ()
#4  boot_call ()
#5  Sscheme_start ()
#6  main ()
```

Thread 1 -- the loop thread (`main` at the bottom). Every worker was
parked in `S_condition_wait`, i.e. exactly where `flow-worker-io` puts
them, which is what rules out the off-loop entry above as the cause.

### Why it needs concurrency to show up

`src/letloop/tls/uring.scm:160` resolves through `dns-resolve-a` on
connection setup, and `dns.body.scm:23-24` caches results with a
60-second TTL. So the SQ only fills when many connections are
established SIMULTANEOUSLY with the DNS entry missing from the cache at
that same instant -- a cache stampede at TTL expiry, or connection-pool
exhaustion under a fetch storm. Sequential load did not reproduce it;
12 concurrent requests did, immediately.

Two consequences worth knowing when hunting this:

- `--optimize-level=0` and `=3` behave identically. It is a C-level
  null write, so there is no Scheme type check for `-O0` to catch --
  which also rules out the usual "unchecked record accessor at -O3"
  explanation for `invalid memory reference`.
- Attaching gdb can SUPPRESS it. ptrace slows the process enough to
  keep the SQ from filling; the sequential repro that crashed reliably
  unattached went clean under the debugger until concurrency was
  raised.

### Fix

Route the four sites through `loop-get-sqe` instead of raw
`io-uring-get-sqe`.

**One subtlety, do not substitute naively:** the recv SQE (275) and its
linked timeout (285) are an `IOSQE-IO-LINK` pair and must be
CONSECUTIVE in the submission queue. `loop-get-sqe` calls
`io-uring-submit` on a full queue before retrying, which would flush
the recv SQE and break the link. That pair needs both SQEs reserved
before either is prepped -- check both, and do the single
submit-and-retry up front if either comes back null.

### Check that should exist

Nothing currently fails when an SQE is prepped from a null pointer; it
simply crashes later, and only under load. A check that fills the
submission queue and then drives a DNS resolution would pin this --
same gap the entry above notes for off-loop SQE preparation.
