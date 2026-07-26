# FL-7 (multi-shard) removal — migration notes

**Date:** 2026-07-26
**Affects:** `(letloop flow)`, `(letloop liburing low)`

FL-7 — the multi-shard extension to `(letloop flow)` (N OS threads,
each running its own `io_uring` ring, cross-shard resume via
`IORING_OP_MSG_RING`, lock-free mailboxes) — has been removed from
letloop. This document explains what changed, why, and how to migrate
code that used it (in particular `atlas-stoa`, which has letloop as a
git submodule and calls `flow-shard-spawn` directly).

## What was removed

From `(letloop flow)`:

- `flow-shard-spawn`, `flow-shard-post!`, `flow-shard-stop!`
- `flow-current-shard`, `flow-shard?`
- The `<flow-shard>` record, `flow-shard-run!`, `flow-shard-drain-mailbox!`
- `flow-resume-owner!` and the owner-tracking `flow-block-and-wait`
  did internally — every event now resumes via a plain `loop-spawn`,
  exactly like every consumer already ran under before FL-7

From `(letloop liburing low)`:

- `loop-detach!` and `loop-ring-fd` (both existed solely to support
  `flow-shard-spawn`)
- The 17 core event-loop globals (`%loop`, `%multishots`,
  `%multishot-ids`, the buffer-ring quintet, `%buf-data`,
  `%fd-handlers`, `%active-connections`, `%accept-backlog`, the
  read-timeout pair, `%wait-timeout`, and `loop-prompt-current`) are
  **plain top-level variables again**, not `define-thread-parameter`.

**Consequence: `(letloop liburing low)`'s event loop is single-threaded
again.** Calling `loop-new`/`loop-run` from more than one OS thread in
the same process is no longer safe — exactly the hazard
thread-parameters existed to prevent. One process = one ring = one
thread, same as before FL-7 existed.

What's unaffected: `flow-choice`, `flow-perform`, channels
(`flow-put!`/`flow-get!`), timeouts, file I/O
(`flow-open`/`flow-read-at`/etc.), and `flow-log` all still work
exactly as before, on a single OS thread. The lock-free
`box-cons!`/`box-drain!`/`box-increment!` primitives channels and
`flow-log` are built on are untouched — they're a fine general-purpose
primitive independent of multi-shard and cost nothing when unused.

## Why

Two things converged:

1. **No consumer in letloop's own tree ever called `flow-shard-spawn`
   outside `flow.check.scm`'s own FL-7 tests.** Every real consumer
   (`http/server`, `tls/uring`) calls `loop-new` exactly once, on its
   own thread.
2. **The thread-parameter plumbing FL-7 required cost real throughput
   on the single-shard path everyone actually runs**, discovered while
   chasing an unrelated regression in `http/server`'s benchmark (see
   `git log` around commits `ec70498`, `48f0273`, `05ab523` for the
   full investigation — a strace A/B against a pre-FL-7 build, then a
   worktree A/B isolating `loop-prompt-current` specifically, both
   showed double-digit-percent throughput recovery from removing
   thread-parameter overhead from the hot path).

Given (1) and (2), and that scaling across cores has a simpler answer
(`SO_REUSEPORT` + N independent single-shard processes — kernel-level
load balancing, zero cross-thread synchronization cost) for anything
that doesn't need one shared in-process state across every core, FL-7
was judged not worth its permanent tax on the common case.

## Migrating `atlas-stoa`

`scripts/louds-shard-decode-benchmark.scm` and
`scripts/s3-search-concurrent-check.scm` call `flow-shard-spawn`
directly. Since `atlas-stoa` pins letloop as a submodule at a specific
commit, **nothing breaks until that pin is updated** — this section is
for when that update happens.

Looking at `louds-shard-decode-benchmark.scm`'s actual usage: it spawns
a fixed pool of persistent worker "shards" up front
(`flow-shard-spawn (lambda () (void))`), then dispatches decode work to
them via `flow-shard-post!`, collecting results through a plain
lock-free box (not `flow-put!`/`flow-get!`). The workers do CPU-bound
LOUDS decoding — no indication they ever perform real `io_uring` I/O of
their own. That means the `io_uring` ring each shard carried was
probably never exercised; `flow-shard-spawn` was being used purely as
"give me a POSIX thread with a cheap mailbox to post thunks to," not
for its I/O concurrency.

If that read is right, the mechanical migration is small — replace the
ring-owning worker with a plain OS thread:

```scheme
;; before
(flow-shard-spawn (lambda () (void)))
;; ... later ...
(flow-shard-post! worker (lambda () (do-decode-work! chunk)))
;; ... shutdown ...
(flow-shard-stop! worker)
```

```scheme
;; after: a bare fork-thread + the same lock-free box flow-shard-post!
;; used internally (flow-box-cons!/flow-box-drain! are still exported
;; and untouched), polled instead of msg_ring-woken
(define mailbox (box '()))
(define stop-requested? (box #f))
(fork-thread
 (lambda ()
   (let lp ()
     (for-each (lambda (thunk) (thunk)) (flow-box-drain! mailbox))
     (unless (unbox stop-requested?)
       (sleep (make-time 'time-duration 2000000 0)) ;; same poll floor flow-shard already had
       (lp)))))
;; post: (flow-box-cons! mailbox (lambda () (do-decode-work! chunk)))
;; stop: (set-box! stop-requested? #t)
```

This drops the `io_uring` ring per worker entirely (never needed for
CPU-bound decode work) and keeps the same lock-free mailbox semantics
`flow-shard-post!` had, at the same ~2ms poll granularity the
benchmark script's own coordinator loop already tolerates elsewhere.

**If any worker genuinely needs its own `io_uring` ring** (real async
I/O per worker, not just CPU work), that's a bigger question than this
migration covers — it means FL-7's actual multi-ring model has a real
use case after all, and the right move is probably reviving it as a
deliberate, cost-accepted opt-in (e.g. gated behind a build flag or a
separate entry point) rather than reintroducing the always-on
thread-parameter tax. Worth a conversation before re-implementing.

## Verification

Full `make check` (383 checks, exit 0) and
`checks/check-transparenturing.sh` pass after this change.
`~check-flow-007/*` and `~check-flow-008/*` (multi-shard-specific) were
removed; `~check-flow-010/two-shard-cross-thread-drain` was removed
too since it required calling `flow-log` (hence `loop-jiffy`, hence a
live `%loop`) from two genuinely concurrent OS threads — only safe when
`%loop` is thread-local, which it deliberately no longer is.
