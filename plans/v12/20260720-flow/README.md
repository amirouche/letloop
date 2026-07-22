# (letloop flow) — porting the CML layer of coop.scm onto io_uring

Analysis of `plans/v12/20260720-flow/coop.scm` (the `(arew untangle)` sketch)
and a milestone plan for re-hosting its Concurrent ML machinery as
`(letloop flow)` on top of the io_uring event loop that already ships in
`(letloop liburing low)` on `dev`.

## 1. What coop.scm contains

coop.scm is a **design sketch, not compiling code** (see the defect
inventory in §1.5). It is an epoll-era draft from arew that stacks six
layers; only some of them still need porting because `dev` has since grown
an io_uring scheduler that subsumes the bottom half.

| # | Layer                              | Lines    | CML-relevant? | Status vs dev today |
|---|------------------------------------|----------|---------------|----------------------|
| 1 | `box-cas!` lock-free list helpers  | 43–77    | support       | only needed for the multi-thread phase |
| 2 | Cogspace (pause/resume duality)    | 79–134   | support       | superseded by `loop-abort` prompt machinery |
| 3 | Escapade / `call/pause` / `pause`  | 136–198  | support       | superseded by `call-with-loop-prompt` / `loop-abort` / `loop-apply` |
| 4 | `<untangle>` scheduler + sleep     | 200–331  | no            | superseded by `loop-run-once` + `IORING_OP_TIMEOUT` |
| 5 | **Coop = CML event** (wrap/try/block), **choice**, **rendezvous channels** | 333–553 | **yes — this is the port target** | absent from dev |
| 6 | Mailbox channels (`send`/`recv`/`recv*`) | 555–728 | no (non-CML duplicate) | drop, see §4.6 |
| 7 | epoll socket generators/accumulators | 730–888 | no            | superseded by `loop-accept` / `loop-read` / `loop-write` |

### 1.1 The CML core: `coop` = wrap / try / block

`Coop` ("cooperation") is what Reppy's CML calls an *event* and
guile-fibers calls an *operation*. A **base coop** is the classic triple:

- `wrap` — post-synchronization transformer applied to the result;
  `untangle-wrap` composes another procedure onto it (coop.scm:353).
- `try` — optimistic non-blocking poll: returns a result **thunk** on
  success, `#f` when the coop cannot complete right now (coop.scm:379).
- `block` — pessimistic path: receives a shared **state box** plus a
  `resume` procedure and publishes both so a peer can complete the
  rendezvous later (coop.scm:372–376).

`untangle-perform` (coop.scm:378–382) is the synchronization point: call
`try`; on `#f`, suspend the current green thread through
`cogspace-pause`, handing `block` the state box and a resumer that
re-schedules the continuation.

This is exactly the guile-fibers operation structure (`wrap-fn` /
`try-fn` / `block-fn`), which itself implements Reppy–Russo–Xiao
*Parallel CML*. The design is sound and ports unchanged.

### 1.2 Choice

`untangle-choice` (coop.scm:389–455):

1. **Flatten** nested choices into a vector of base coops (choice is
   associative; a 1-element choice collapses to the base coop).
2. **Poll phase**: try each base starting at a random offset (fairness),
   first success wins without suspending.
3. **Block phase**: allocate **one** state box (`'waiting`) shared by all
   bases, call every base's `block` with it; whichever peer CASes
   `'waiting → 'synched` first delivers, all other bases are dead on
   arrival because their `block` registrations share the now-`'synched`
   box.
4. `wrap` on a choice distributes over the bases.

The shared-state-box trick is the crux of the whole design and is what
`(letloop flow)` must marry to io_uring completions (§4.3).

### 1.3 The rendezvous channel protocol

A channel is two queues of `(state-box . resume)` pairs: waiting **puts**
and waiting **pops**. `untangle-put` (coop.scm:477–553) shows the
protocol; the symmetric get/pop coop was never written.

- **try** (put side): scan waiting pops; for each, spin up to `magic*`
  (42) attempts to CAS its state `'waiting → 'synched`; on success resume
  the popper with the object and return immediately.
- **block** (put side): enqueue own `(state . resume)`, then **re-scan**
  pops that may have arrived concurrently, using two-phase locking:
  CAS *own* state `'waiting → 'claimed`, then CAS the *peer*
  `'waiting → 'synched`. On success: own state `→ 'synched`, resume both
  sides. If the peer is `'claimed`, roll back own state to `'waiting`
  and retry bounded times; if the peer is `'synched`, skip it. Skipping
  entries whose state box is `eq?` to one's own prevents a choice from
  rendezvousing with itself.

Two TODOs recorded in the sketch matter for the port:

- a choice containing a put **and** a get on the *same* channel can
  deadlock — detect and reject (coop.scm:514–515);
- queues need periodic compaction of `'synched` corpses — the
  `gc-counter` field of `<queue>` (coop.scm:465–472) was reserved for
  this but never implemented.

### 1.4 Support machinery that io_uring already replaces

- **Escapade** (coop.scm:136–198): a one-shot prompt via `call/1cc` plus
  `call/cc` capture in `pause`. `dev`'s `(letloop liburing low)` has the
  identical structure under different names: `call-with-loop-prompt`,
  `loop-abort`, `loop-apply` — already written, already exercised by
  `loop-read`/`loop-write`/`loop-accept` and by `(letloop tls uring)`.
- **Cogspace** (coop.scm:79–134): dispatches pause/resume to either the
  green-thread arm or a bare-POSIX-thread arm (mutex + condition). The
  io_uring loop is single-threaded (`%loop` global, one ring); the bare
  arm is out of scope for phase 1 (§4.7 keeps the door open).
- **Scheduler + sleep queue** (coop.scm:200–331): untangle keeps a boxed
  list of `(wake-time . thunk)` and ticks it against monotonic time.
  With io_uring the kernel is the timer wheel: `IORING_OP_TIMEOUT` CQEs
  do this with none of the bookkeeping (`loop-sleep` already exists).
- **Sockets** (coop.scm:730–888): epoll readiness generators. Superseded
  by completion-based `loop-accept`/`loop-read`/`loop-write` with
  multishot accept, provided-buffer recv, and cancel-on-close semantics.

### 1.5 Defect inventory

Recorded so the port does not inherit them; coop.scm was abandoned
mid-edit and none of these are subtle design choices:

1. `box-cons!` references unbound `lst` (coop.scm:49) — must snapshot
   `(unbox box)` once and CAS against the snapshot.
2. `untangle-stopping?` reads free variable `untangle` instead of its
   `obj` argument (coop.scm:252).
3. `untangle-exec-network-continuations` passes a literal `TODO`
   (coop.scm:311).
4. `untangle-sleep` pushes `(list (cons when resume))` — a list wrapping
   the pair — onto a queue whose consumers expect bare pairs
   (coop.scm:321).
5. `make-coop`'s `wrapped` mangles `call-with-values` (one argument,
   `proc` dead) (coop.scm:364) and recursively calls `make-coop` with
   the six-argument shape of `make-coop%` (coop.scm:366–370).
6. `<untangle-coop>` declares a `perform` field absent from its
   constructor, yet `make-coop%` is called with four arguments
   (coop.scm:345–351, 384–387); `untangle-perform` calls the
   non-existent `coop-perform` accessor (the field reader is
   `coop-perform%`).
7. `coop-perform` and `coop-choice-perform` both have the
   `(if test (pause))` paren slip that lets the fallthrough run even
   after pausing (coop.scm:380–382, 435–441); `thunk` unbound at
   coop.scm:441 (should be `maybe-thunk`).
8. `untangle-choice`'s `adjoin` is an unclosed `raise 'not-implemented`
   stub (coop.scm:390–391); `untangle-coop-wrap` (coop.scm:414) is
   undefined (should be `untangle-wrap`); the poll loop indexes
   `coops` for the count but `bases` for the elements (coop.scm:432).
9. The channel record exposes `pops`/`puts` wrapping `<queue>` records,
   but every use path does `(unbox (channel-pops channel))` as if the
   fields were bare boxes; `queue-cons!` is never defined
   (coop.scm:459–506).
10. `untangle-put`'s block path is structurally unclosed — the
    `case`/`loop1` tower never terminates and `(make-coop values try
    block)` lands outside the procedure (coop.scm:516–553).
11. Layer 6 operates on `channel-resumers`/`channel-inbox` fields that
    the channel record does not have — two channel designs were never
    reconciled (coop.scm:555–595).
12. `untangle-channel-recv` calls `box-uncons!` with three arguments,
    one of them the unbound `obj` (coop.scm:590–592).
13. `untangle-channel-recv*`'s helpers close over free `mutex`, `pool`
    (spelled `poll` once), and `k`; its tail (coop.scm:705–728) sits at
    library top level.
14. Export list vs definitions: `make-untangle-channel` exported but
    defined as `untangle-make-channel`; `untangle-accept`,
    `untangle-bind`, `untangle-listen`, `untangle-closing?` exported
    but never defined.
15. Socket layer: missing `begin` in the accept retry loop
    (coop.scm:794–797), `buffer` for `bytevector` (coop.scm:843), free
    `fd` in `connection-accumulator` (coop.scm:864).

## 2. What dev already provides

`(letloop liburing low)` on `dev` is both the FFI (complete liburing
surface, including `futex-wait`/`futex-wake`, `msg-ring`, `cancel64`,
multishot accept/recv, provided buffer rings) **and** a working
single-threaded coroutine loop:

- prompt machinery: `call-with-loop-prompt`, `loop-abort`, `loop-apply` —
  byte-for-byte the role of escapade/`call/pause`/`pause`;
- `<loop>` record: ring, cqe pointer, `handlers` (u64 user_data id →
  parked continuation), pending `thunks`, monotonic `jiffy`;
- `loop-run-once`: run spawned thunks to first suspension, submit,
  `io_uring_wait_cqe_timeout`, drain CQEs, dispatch `(handler res)`
  through the prompt; multishot bookkeeping (`IORING_CQE_F_MORE`),
  buffer-ring recycling (`IORING_CQE_F_BUFFER`), accept backlog for
  unclaimed multishot clients;
- suspending ops: `loop-accept`, `loop-read`, `loop-write`,
  `loop-connect`, `loop-close` (with synthetic `-ECANCELED` resume of
  parked waiters), `loop-sleep`, `loop-poll-wait`, `loop-tcp-serve`;
- consumers proving the substrate: `(letloop tls uring)`,
  `src/letloop/dns.body.scm`, `src/letloop/http/server.body.scm`.

**Gap**: everything in coop.scm layer 5 — the event algebra (wrap / try
/ block), `choice`, rendezvous channels — plus exposing I/O and timeouts
*as events* so they compose under `choice`. Today `loop-read` parks
exactly one continuation per operation and cannot lose a race: there is
no way to say "read from this fd **or** receive from that channel **or**
time out after 2s".

## 3. Concept mapping

| coop.scm concept                     | (letloop flow) on io_uring |
|--------------------------------------|----------------------------|
| escapade / `call/pause` / `pause`    | `call-with-loop-prompt` / `loop-abort` / `loop-apply` (reuse as is) |
| cogspace (green arm)                 | implicit — everything runs inside `loop-run` |
| cogspace (bare POSIX arm)            | phase 2: `io-uring-prep-futex-wait`/`wake` or `msg_ring` (§4.7) |
| `untangle-spawn`                     | `loop-spawn` |
| untangle tick / time queue           | `loop-run-once` + `IORING_OP_TIMEOUT` |
| `untangle-sleep`                     | `flow-sleep` = `(flow-perform (flow-timeout ns))` |
| coop (base event)                    | `<flow>` record: `wrap` × `try` × `block` |
| `untangle-wrap` / `untangle-perform` | `flow-wrap` / `flow-perform` |
| `untangle-choice`                    | `flow-choice` + SQE cancellation of losers (§4.3) |
| state box `'waiting/'claimed/'synched` | same protocol, plain `box` ops in phase 1 (§4.7) |
| channel put/pop queues (`box-cas!` lists) | plain mutable FIFOs + `gc-counter` compaction |
| epoll readiness registration          | SQE submission inside `block`; CQE handler completes the rendezvous |
| socket generators/accumulators        | `flow-accept` / `flow-read` / `flow-write` events over the `loop-*` internals |
| mailbox `send`/`recv`/`recv*`         | dropped; buffered channels become a library over rendezvous (§4.6) |

## 4. Design for (letloop flow)

New library `src/letloop/flow.scm`, `(library (letloop flow) ...)`,
importing `(chezscheme)` and `(letloop liburing low)`. It layers on the
loop exactly as `(letloop tls uring)` does; `liburing/low.scm` is not
modified except where §4.3 requires a hook.

### 4.1 Exports

```scheme
;; event algebra
make-flow flow? flow-wrap flow-choice flow-perform flow-guard
;; channels
make-flow-channel flow-channel? flow-put flow-get      ;; events
flow-put! flow-get!                                    ;; (flow-perform (flow-put ...)) shorthands
;; time
flow-timeout flow-sleep
;; I/O events
flow-accept flow-read flow-write
;; scheduler re-exports for convenience
flow-spawn flow-run flow-stop
```

`flow-put`/`flow-get` return events; the `!` variants perform them. This
keeps the CML law visible: *everything composable is a value*.
`flow-guard` (delayed event construction, trivial once base events
exist) rounds out the classic CML kernel; `wrap-abort`/nack is explicitly
out of scope until a consumer needs it.

### 4.2 Base events

```scheme
(define-record-type <flow>
  (make-flow% type data wrap try block) ...)
```

`type` is `'base` or `'choice` (data = vector of bases), as in coop.scm
but with the constructor/field arities actually consistent (§1.5 items
5–6). `flow-perform`:

1. flatten if choice; poll `try`s from a random offset;
2. otherwise allocate the state box, call every `block` with
   `(state resume)` where `resume` wraps `loop-abort`'s parked
   continuation in a `loop-spawn`, and suspend.

Resumption always goes through `loop-spawn`, never a direct call — the
completing side may be in the middle of the CQE drain.

### 4.3 io_uring events and choice: the one genuinely new problem

epoll registration is idempotent and free to abandon; an SQE is not —
once submitted, a completion **will** arrive. Three rules make CML
choice sound over completions:

1. **`block` submits, `try` never does.** For pure-I/O bases the `try`
   is (almost, see 4.5) always `#f`; the SQE is prepped and submitted in
   the block phase, keyed by a fresh `loop-alloc-id!`.
2. **The parked handler owns the CAS.** Instead of parking the raw
   continuation `k` in `(loop-handlers %loop)`, park a closure:
   `(lambda (res) (when (box-cas! state 'waiting 'synched)
   (cancel-siblings!) (loop-spawn (lambda () (k (post res))))))`.
   The existing CQE drain in `loop-run-once` needs **no change**: it
   already just calls `(handler res)`. A losing base's CQE (arriving
   after some sibling synched) finds the box `'synched` and its handler
   reduces to a no-op — apart from mandatory resource recycling: a
   buffer-ring recv that "wins the kernel but loses the choice" must
   re-add its buffer, which the drain loop already does before
   dispatch, so losers only need to drop the `%buf-data` entry.
3. **Losers are cancelled eagerly.** When a base wins,
   `cancel-siblings!` walks the other bases' submitted ids and preps
   `io-uring-prep-cancel64` for each (`io-uring-prep-timeout-remove`
   for timeouts). Cancellation is best-effort — the op may already have
   completed; rule 2 makes that harmless. Without eager cancel a
   `flow-read` losing to a timeout would leave a recv pinned to the fd
   until close; with it, the `-ECANCELED` CQE hits the no-op handler.

One asymmetry: **channel bases resumed by a peer** (not by a CQE) must
also cancel sibling SQEs. So `cancel-siblings!` is built once per
`flow-perform`, closed over the per-base submitted-id list that blocks
append to, and every base's resume path calls it after winning the CAS.

### 4.4 Channels

Port §1.3 with the get side written (it mirrors put), on plain Scheme
FIFOs (single-threaded loop ⇒ no `box-cas!` needed; `box-cas!` on
unshared boxes is still cheap, and keeping the
`'waiting/'claimed/'synched` *protocol* — states and transition order —
costs nothing and keeps the phase-2 path (§4.7) a data-structure swap
rather than an algorithm change). Implement the two coop.scm TODOs:

- compaction: bump `gc-counter` on every enqueue; at zero, filter
  `'synched` entries and reset (initial threshold 1024, measured later);
- same-channel guard: `flow-perform` on a choice scans base data for a
  put and a get on an `eq?` channel and raises
  `&flow-same-channel-choice` instead of deadlocking.

### 4.5 Concrete base events

- `flow-timeout` — block: prep `IORING_OP_TIMEOUT` with a
  `make-timespec` freed on resume; try: `#f`.
- `flow-read fd` — try: `#f`; block: prep recv with
  `IOSQE-BUFFER-SELECT` exactly as `loop-read`, result post-processed to
  `bv | #t (eof) | #f (error)` by the base's internal wrap.
- `flow-write fd bv` — the short-write retry loop of `loop-write` lives
  *inside* the event's completion path (a partial write re-arms its own
  SQE rather than re-entering choice; once a write has started it is
  committed — CML semantics attach to the *first* byte).
- `flow-accept fd` — try: pop `%accept-backlog` when non-empty (a real
  non-blocking fast path, unlike read/write); block: park on the
  multishot's id with the state-box handler. The multishot itself is
  never cancelled by a losing choice — it is per-fd infrastructure, not
  per-event. Requires `liburing/low.scm` to export the small backlog/
  multishot accessors (or a `loop-accept-try`/`loop-accept-block`
  pair) — the one place the substrate needs a hook.

`flow-sleep s` = `(flow-perform (flow-timeout s))`, replacing nothing —
`loop-sleep` stays for non-CML users.

### 4.6 What is deliberately dropped

- Layer 6 mailboxes (`untangle-channel-send`/`recv`/`recv*`): rendezvous
  channels + `flow-choice` subsume `recv*`; a buffered/async channel,
  if ever needed, is a spawned fiber owning a queue and two rendezvous
  channels — a users' pattern, not core API.
- Cogspace's bare-POSIX-thread arm, `with-mutex`, conditions — phase 2.
- The epoll socket layer — `loop-*` already won.

### 4.7 Threading posture

Phase 1 is single-shard: one ring, one POSIX thread, matching
`IORING_SETUP_SINGLE_ISSUER` reality and the existing `%loop` global.
The protocol (state boxes, two-phase claim, bounded retry `magic*`)
is kept shape-compatible so that phase 2 — N shards, each a loop on its
own ring — only has to (a) swap FIFOs for the `box-cas!` lists of
coop.scm layer 1 (with defect 1 fixed), (b) make `resume` cross-shard
via `io-uring-prep-msg-ring` (ring→ring wakeup, binding already
exported) with `futex-wait`/`wake` as the bare-thread fallback — i.e.
cogspace returns as "which shard do I poke", not as an if-forest.

## 5. Milestones

Repo conventions: checks are exported `~check-flow-NNN` thunks run with
`$LETLOOP check`; each chunk lands compiling and checked, PLAN-style.

| Chunk | Deliverable | Checks |
|-------|-------------|--------|
| FL-1  | `<flow>` record, `make-flow`, `flow-wrap`, `flow-guard`, `flow-perform` (base only), always-ready + never-ready synthetic events | ~check-flow-000: perform of always-ready; wrap composition order |
| FL-2  | `flow-choice`: flatten, random-offset poll, shared state box, block fan-out | ~check-flow-001: choice of two ready picks one; choice ready+never picks ready; nested choice flattens |
| FL-3  | Channels: `make-flow-channel`, `flow-put`, `flow-get`, compaction, same-channel-choice guard | ~check-flow-002..4: ping-pong across two spawns; N producers/1 consumer ordering-free delivery count; same-channel choice raises |
| FL-4  | `flow-timeout` / `flow-sleep`; cancellation of losing timeout (`timeout-remove`) | ~check-flow-005: get-or-timeout where put arrives first; where it doesn't |
| FL-5  | I/O events `flow-accept`/`flow-read`/`flow-write` + the `liburing/low.scm` backlog hook + `cancel64` of losing I/O | ~check-flow-006: echo pair over loopback via events; read-or-timeout on a silent socket leaves fd usable after cancel |
| FL-6  | Port one real consumer as proof (candidate: `http/server.body.scm` read-with-timeout path) | existing consumer checks stay green |
| FL-7 (later) | Multi-shard: `box-cas!` helpers (defect-1 fix), `msg_ring` cross-shard resume, futex bare-thread arm | stress check under `--dev` |

Risks worth flagging early: FL-5's cancellation semantics depend on
kernel version behavior of `IORING_OP_ASYNC_CANCEL` (the sandbox kernel
is recent; CI's may not be — probe with `io-uring-opcode-supported`);
and `call/1cc` one-shot continuations in `loop-abort` are only correct
because the state-box CAS guarantees single resumption — FL-2's checks
must include a double-completion race simulation to pin that invariant.

## 6. Public API reference (target)

None of this is implemented yet; this section pins down what each
export in §4.1 will do so FL-1..FL-6 have a single source of truth to
check against.

**`(make-flow wrap try block)`** — constructs a base `<flow>` event
(`type = 'base`) from a post-synchronization transformer `wrap`, a
non-blocking poll `try`, and a `block` registration procedure. Mirrors
`make-coop%` in coop.scm, but with the constructor/field arity actually
consistent (fixes §1.5 defects 5–6). Not normally called by users
directly — `flow-timeout`/`flow-read`/`flow-put`/etc. are all built on
top of it.

**`(flow? obj)`** — predicate; `#t` iff `obj` is a `<flow>` record,
base or choice.

**`(flow-wrap event proc)`** — returns a new event equivalent to
`event` except its eventual result is post-processed by `proc`. Wraps
compose (nested `flow-wrap` calls chain, outermost applied last) and
distribute over the bases of a `flow-choice` (§4.2).

**`(flow-choice event ...)`** — combines events into one event that
synchronizes on whichever base becomes ready first. Nested choices
flatten (choice is associative); a one-element choice is the identity.
Raises `&flow-same-channel-choice` if a `flow-put` and `flow-get` on
the same channel both appear among the (transitively flattened) bases,
instead of deadlocking (§4.4).

**`(flow-perform event)`** — the synchronization point. Polls every
flattened base's `try` from a random starting offset; the first
non-`#f` result is a thunk, called for the final value. If every `try`
returns `#f`, allocates one shared state box, calls every base's
`block` with `(state resume)`, and suspends the current fiber via
`loop-abort` until some base's parked CQE/peer handler wins the
`'waiting → 'synched` CAS and resumes it, cancelling sibling SQEs
first (§4.2–§4.3).

**`(flow-guard thunk)`** — delayed event construction: `thunk` is
called, and must return an event, only when `flow-perform` actually
attempts synchronization — lets the event to synchronize on (e.g.
which channel) depend on state computed right before blocking.

**`(make-flow-channel)`** — allocates a fresh unbuffered rendezvous
channel: a waiting-puts FIFO, a waiting-pops FIFO, and a `gc-counter`
used to periodically compact `'synched` entries out of both (§4.4). A
put and a get on the same channel must synchronize directly; there is
no queueing of values.

**`(flow-channel? obj)`** — predicate.

**`(flow-put channel obj)`** — event that succeeds by handing `obj` to
a matching `flow-get` on `channel`. `try` scans the waiting-pops FIFO
and attempts the bounded CAS rendezvous; `block` enqueues onto the
waiting-puts FIFO, then re-scans pops that may have arrived
concurrently under the two-phase `'waiting → 'claimed → 'synched`
protocol (§1.3, §4.4). The wrapped result on the put side is
unspecified.

**`(flow-get channel)`** — the symmetric event: `try`/`block` scan and
enqueue the gets FIFO instead of the puts FIFO. The wrapped result is
the object handed over by the matching put.

**`(flow-put! channel obj)`** — shorthand for
`(flow-perform (flow-put channel obj))`.

**`(flow-get! channel)`** — shorthand for
`(flow-perform (flow-get channel))`.

**`(flow-timeout ns)`** — event that becomes ready after `ns`
nanoseconds. `try` is always `#f`; `block` preps an `IORING_OP_TIMEOUT`
SQE with a `make-timespec` freed on resume. If this event loses a
choice, its SQE is cancelled via `io-uring-prep-timeout-remove` rather
than left to fire uselessly (§4.5).

**`(flow-sleep ns)`** — `(flow-perform (flow-timeout ns))`. Exists for
CML-style code that wants a plain sleep as a special case of
synchronization; does not replace `loop-sleep`, which stays for
non-CML callers.

**`(flow-accept fd)`** — event: `try` pops `%accept-backlog` when
non-empty, a genuine non-blocking fast path unlike the other I/O
events; `block` parks the state-box handler on the fd's multishot
accept id. The multishot registration is per-fd infrastructure and is
never torn down just because one choice involving it loses (§4.5).

**`(flow-read fd)`** — event: `try` is always `#f`; `block` preps a
buffer-select recv exactly as `loop-read` does. The result is
post-processed by the event's own internal wrap into `bv` (data),
`#t` (EOF), or `#f` (error).

**`(flow-write fd bv)`** — event: `block` preps a write of `bv`. A
partial write re-arms its own follow-up SQE from inside the event's
completion path rather than re-entering `flow-choice` — once any bytes
have gone out, the write is committed and can no longer be cancelled
by a losing choice (§4.5).

**`(flow-spawn thunk)`** — re-export of `loop-spawn`: schedules
`thunk` to run as a new fiber on the loop.

**`(flow-run)`** — re-export/thin wrapper over the loop's drive loop
(`loop-run-once`, looped): runs spawned fibers, submits pending SQEs,
waits for and dispatches CQEs, repeats until stopped or no work
remains.

**`(flow-stop)`** — signals the running loop to stop after its current
iteration.
