# Task: async file I/O primitives for `(letloop flow)`

Add chunked, configurable-size file read/write to `flow.scm`, following
the exact pattern `flow-read`/`flow-write` already use for sockets —
this is new capability, not a fix, and the socket ops are the template
to mirror, not to touch.

## Why these don't exist yet (context, verified against this repo)

`flow-read`/`flow-write` (`src/letloop/flow.scm`, ~lines 538-564) wrap
`io-uring-prep-recv`/`io-uring-prep-send` — socket-only syscalls, fixed
internal buffer size (`%flow-read-buffer-size`, 65536, not a per-call
parameter). They cannot be pointed at a regular file fd (`ENOTSOCK`).
The raw bindings for regular-file I/O already exist and are unused by
`flow`: `io-uring-prep-read`, `io-uring-prep-write`, `io-uring-prep-openat`,
`io-uring-prep-close` (`src/letloop/liburing/low.scm`, ~lines 762-773,
966-990). `(letloop aql disk)` uses these same raw bindings for its own
file I/O, but synchronously (`uring-do`, blocks the OS thread, no fiber
yield) via its own private ring — not built on `flow` at all, and not a
concurrency-model match for this task.

## Required procedures

Export from `(letloop flow)`, alongside the existing `flow-read`/`flow-write`:

```scheme
(flow-open path flags mode)   -> event yielding fd (a plain integer)
(flow-read-at fd offset count) -> event yielding a bytevector (<= count
                                  bytes) or 'eof at end of file
(flow-write-at fd offset bv)   -> event yielding bytes-written (an fixnum)
(flow-close fd)                -> event yielding the close result
```

- `fd` is a **raw integer**, never a wrapped/opaque record — this
  matches every existing fd-producing op in this codebase
  (`flow-accept`, `loop-connect` both return bare integers; there is
  no fd-wrapper record type anywhere in `flow.scm`, confirmed by
  direct inspection). Do not invent one here. If a caller needs to
  track a read/write cursor across calls, that's the caller's
  business (a simple mutable variable, or a small caller-side record)
  — not something these primitives need to provide.
- `offset` is explicit on every call (unlike `recv`/`send`, regular-file
  reads/writes need a position) — no implicit "current file position"
  state is kept by these primitives. A caller doing sequential chunked
  reads tracks and increments its own offset between calls.
- `count` in `flow-read-at` is a real per-call parameter (unlike
  `flow-read`'s fixed 65536) — this is the whole point of the task.
- No guardian, no dynamic-wind, no automatic cleanup of any kind.
  Confirmed by repo-wide grep: zero `guardian`/`make-guardian` usage
  anywhere in this codebase. The established, deliberate idiom
  (`src/letloop/tls/uring.scm:454-477`, `src/letloop/postgresql/base.scm:985`)
  is explicit `loop-close` on the normal path and an explicit `guard`-
  wrapped `loop-close` on the error path — `dynamic-wind` is
  explicitly rejected in a code comment there as unsafe for this
  suspend/resume fiber model. Follow the same idiom for files: callers
  close explicitly, on both paths. Don't add anything more clever.

## Implementation shape

Clone `flow-read`'s exact skeleton (`make-flow%` with a `try` that's
always `#f` and a `block` that submits an SQE and registers a
completion handler + `register-cancel!`) for each new procedure, subbing
in the file-op prep call:

- `flow-open`: `io-uring-prep-openat` (path, flags, mode), yields the
  new fd on success.
- `flow-read-at`: `io-uring-prep-read` (fd, buffer, count, offset).
  A `0`-byte result means EOF — yield the symbol `'eof`, not an empty
  bytevector, so callers can `cond`/`case` cleanly in a read-until-EOF
  loop without special-casing zero-length bytevectors.
- `flow-write-at`: `io-uring-prep-write` (fd, buffer, count, offset).
- `flow-close`: either a new thin wrapper submitting
  `io-uring-prep-close`, or — preferably — extend `loop-close`
  (`src/letloop/liburing/low.scm:2233-2269`) to also accept file fds:
  it already does the right bookkeeping (resume anything parked on
  this fd with a synthetic cancellation, remove from `%fd-handlers`/
  `%active-connections`, submit `IORING_OP_ASYNC_CANCEL` for in-flight
  ops, then `IORING_OP_CLOSE`) and there's no reason a file fd needs
  different teardown than a socket fd — check whether it's already
  fd-kind-agnostic before writing a parallel implementation.

A caller doing "read a whole file in N-byte chunks" composes these
directly — no separate "read until EOF" helper is required by this
task, but adding one small convenience procedure (e.g. `flow-read-file`
looping `flow-read-at` with an increasing offset until `'eof`, calling
back or collecting into a list of bytevectors) is reasonable if it
falls out naturally; don't over-build it.

## Tests

In `flow.check.scm` (or wherever `flow-read`/`flow-write`'s own tests
live), following the same style:

- Write a small file via `flow-open`+`flow-write-at`(+`flow-close`),
  read it back via `flow-open`+`flow-read-at` in one shot, confirm
  bytes match.
- Read-in-chunks: write a file larger than one chunk size, read it back
  looping `flow-read-at` with a small `count` (e.g. 4096) and
  increasing `offset`, confirm the reassembled bytes match and the
  final call yields `'eof`.
- Read/write at a nonzero offset into an existing file (not just
  sequential from 0) — confirms `offset` is actually honored, not just
  accepted and ignored.
- Composability: `flow-choice (flow-read-at fd offset count)
  (flow-timeout t)` — mirror the existing
  `~check-flow-006/read-or-timeout-leaves-fd-usable` socket test, same
  idea for a file fd, confirming a timed-out read leaves the fd
  usable for a subsequent call (not left in some half-submitted state).
- Error path: `flow-open` a nonexistent path with no `O_CREAT`, confirm
  a sensible error/condition rather than a hang or a wrong-shaped
  result.

## Scope

This task is only the four primitives above (plus `flow-close`'s
possible extension) and their tests. Do not build a higher-level
"file reader" abstraction, a buffering/caching layer, or anything
related to the S3/JSONL indexing pipeline that motivated this — that's
a separate, later task built on top of these primitives, not part of
this one.
