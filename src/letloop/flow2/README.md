# Fibers, channels, and nurseries over io_uring

Library name: `(letloop flow2)`

## Author

Amirouche A. BOUBEKKI

## Status

`(letloop flow2)` is **implemented**, in `src/letloop/flow2.scm`, with
49 checks in `src/letloop/flow2.check.scm`. It has no consumers yet;
`(letloop flow)` stays untouched and keeps serving its current ones.

This document began as a draft specification and is now the library's
reference, so where the two ever disagree the source wins. It was last
reconciled against the implementation on 2026-08-17, after an adverse
review whose findings changed several documented behaviours — channels
are now bounded by default and a full put parks, which is the one
change that would break code written against the original draft.
Decisions herein were resolved on 2026-08-14; the
motivating failures are documented in `TODO.md` (sections "monitored
trees with automatic timeout-and-cancel" and
"flow-block-and-wait-off-loop registers ring events from the worker
thread").

## Abstract

flow2 is a concurrency library for the letloop runtime built on three
primitives: **fibers** (cooperative lightweight threads multiplexed on
one OS thread that owns an io_uring), **channels** (buffered,
many-producer many-consumer queues, the only mechanism that crosses OS
threads), and **nurseries** (structured-concurrency scopes that own
every fiber and I/O operation spawned in their dynamic extent, and
cancel all of it on error, timeout, or request).

The main thread is the only thread that touches the io_uring.
Compute threads run user thunks submitted over channels and have no
I/O verbs of their own: a compute task that needs I/O sends messages
in a user-defined protocol over a response channel, and the fiber
that submitted the task performs the I/O on its behalf.

Errors are plain records of one type, `<flow-error>`, dispatched by
symbol — not R6RS conditions.

## Issues

The four issues raised by the first draft — whether the framework's
error reply respects the response channel's buffer bound, a `stopped`
error symbol for `flow-stop`, shrinking a bound below the current queue
length, and wholesale `flow-scope-attach!` of a worker channel — were
resolved on 2026-08-16 and their resolutions are specified inline (see
`flow-stop`, `flow-channel-buffer-size!`, Compute threads, and the
Rationale on scope tagging).

Five gaps found by the 2026-08-17 adverse review are **open**, listed
here rather than left in a report nobody reads. Each is a place where
this document currently describes an intent the implementation does not
fully deliver:

- **`flow-write-at` and `flow-close` are not cancellable.** Neither
  registers a cancel thunk, so a cancelled scope leaves their ring
  operations in flight. `flow-write` was the sharp case and is fixed:
  it no longer loops internally and registers the same cancel
  `flow-read` does. "Every in-flight ring operation belonging to the
  subtree is cancelled", below, still overstates the remaining two.
- **Shutdown does not join workers.** `flow-run` puts the stop message,
  signals the eventfd and closes it without waiting. A worker still
  inside a task can then find the eventfd already `#f`, or race the
  assignment and write into a closed fd number that a later `loop-new`
  or `socket` may have reused.
- **Cancellation checkpoints are asymmetric.** `flow-get-try` raises
  `cancelled` on a compute thread but not on the main thread, so a
  main-thread fiber in a cancelled scope can keep draining a channel as
  long as it never performs a suspending event. (`flow-put!` no longer
  belongs on this list: it parks when full and is therefore a
  cancellation point on both.)

## Rationale

flow2 exists because two architectural decisions in `(letloop flow)`
produced whole classes of bugs that discipline could not contain:

**A ring shared across threads.** flow lets worker threads register
events themselves; anything that preps an SQE (`flow-timeout`,
`flow-read`, ...) from a worker mutates loop-thread-only state.
Nothing fails at the call site — the ring corrupts and the process
dies later, somewhere unrelated. A production server died with
`nonrecoverable invalid memory reference` under ~20 concurrent
requests and hung for 25 minutes on another occasion; worker mode has
been forced off there since. The correct usage rule ("wrap the INNER
client in `flow-worker-io`, not the outer function") existed, was
documented, and was still violated in practice — a rule that must be
remembered at every call site is not a design.

flow2's answer is structural: **only the main thread owns the ring**,
and the only thing another thread can do is put a value on a channel.
There is no API through which a compute thread can reach the loop's
state, so the bug class cannot be written.

**Unstructured spawn.** flow's `flow-spawn` creates a fiber nobody
owns. A fan-out that spawns one fiber per sub-query and then counts N
reply messages hangs forever if any fiber dies without replying —
which is exactly what happened: an unguarded raise in a fetch fiber
under connection flood leaked ~10 GB in minutes. The workaround
(guard every fiber so a raise still sends SOMETHING) is the Erlang
lesson relearned: a death notification must be the runtime's
unconditional guarantee, not a convention each call site
reimplements.

flow2's answer is the **nursery**: every fiber is spawned inside a
scope, the scope does not join until every child has returned or
raised, a child's raise cancels its siblings (and their in-flight
I/O) and re-raises at the join. The counting loop and the guards
disappear; a dead fiber is accounted for by the scope, always.

Three further choices deserve justification:

**Channels are bounded by default, and a full put parks.** Unbounded
is not a capacity choice; it is the decision to convert a rate
mismatch into unbounded memory growth and discover it as an OOM hours
later — the Erlang mailbox failure mode, and the shape of the 44GB
incident in `(letloop flow)`'s own history. So every channel gets a
finite bound (43) unless the call site says `#f`, and a put that finds
the channel full waits for room.

Waiting for *room* is not a rendezvous: it does not need a matching
getter, only space. That distinction is what lets put park without
becoming an event. A consequence worth its own sentence: since no put
**event** is exported, **put is not an
event** — only get composes with `flow-choice`. This deletes flow's
same-channel-choice hazard (put and get of one channel racing in a
single choice) by making it inexpressible.

**Workers have no verbs.** flow2 does not define a "read a file for
me" message. A task is `(thunk . response-channel)`; whatever the
task needs from the main thread it expresses in the *user's*
protocol over the response channel, and the submitting fiber is
responsible for reading and acting on those messages. The framework
that would otherwise live here — request routing, correlation,
batching, proxy fibers — is exactly the part that varies per
application, and freezing it into the library would either be too
rigid (one outstanding request at a time was measured **2× slower**
than the single-threaded server on cold I/O-bound queries) or grow
into a second io_uring implemented in Scheme. flow2 owns only what it
can guarantee: delivery, error routing, and cancellation.

**One error type, dispatched by symbol.** flow2 raises and sends
plain `<flow-error>` records, not R6RS conditions. Two reasons.
First, the same error must travel two transports — raised at a
fiber's suspension point, or *sent over a channel* as a worker task's
reply — and a self-contained record with a symbol is the same value
in both, inspected the same way. Second, dispatch is `case` on
`flow-error-symbol` or a direct predicate in a `guard` clause; there
is no condition-type hierarchy to import, subtype, or get wrong.
Cancellation and timeout are ordinary members of this taxonomy, not
special control flow.

**Per-request scope tagging, not channel attachment.** Killing "the
compute attached to a nursery" is expressed per *request*: a
submission made inside a nursery's dynamic extent is tagged with that
scope automatically. Attaching a whole worker *channel* to a nursery
was considered and rejected for the first version: a worker is a
shared resource serving requests from many scopes, and killing every
task on it because one scope timed out is precisely the kind of
blast-radius surprise this design is trying to remove. The need it
would serve is covered without new API by the *dedicated worker*
pattern: give a nursery its own worker channel and submit only from
inside its extent — every task on that worker is then scope-tagged
to the nursery, and cancelling the nursery kills exactly them.

## Prior art

- **Concurrent ML** (Reppy). The event algebra — `flow-wrap`,
  `flow-guard`, `flow-choice`, synchronization as a first-class value
  — is CML's, inherited from `(letloop flow)` unchanged. flow2 keeps
  it because composable synchronization is what lets scope
  cancellation be *just another event* raced against whatever a fiber
  is doing.
- **guile-fibers** (Wingo) and **Loko Scheme fibers**. The same CML
  lineage in Scheme. fibers funnels all I/O through suspendable ports
  so no call site carries a wrapping discipline — flow2 reaches the
  same "no discipline to forget" property by giving non-loop threads
  no I/O surface at all.
- **Erlang/OTP.** The property flow2 copies is the monitor guarantee:
  a `DOWN` message is delivered unconditionally, so waiting on a dead
  process cannot hang. flow2's nursery join and the worker guard's
  always-a-reply rule are that guarantee in two places. The
  properties flow2 deliberately does not copy: unbounded mailboxes
  (channels are bounded by default and put parks), unstructured
  `spawn`/link/trap
  (nurseries instead), untrappable `exit(kill)` that skips cleanup
  (cancellation is a raise, so explicit close-on-both-paths cleanup
  runs), and restart-based supervision (in a shared heap a restart
  cleans almost nothing, so a worker that catches a task's raise
  simply reports it and lives).
- **Trio** (Smith, "Notes on structured concurrency"). The nursery:
  no fiber outlives its scope, first error cancels siblings and
  re-raises at the join, timeouts are scopes. flow2's `flow-nursery`
  and `flow-monitor` are this design.
- **seastar / glommio / thread-per-core io_uring runtimes.** The
  share-nothing rule — a ring is owned by exactly one thread, other
  threads communicate with messages, the loop is woken by eventfd —
  is the standard answer to exactly the corruption flow hit. flow2 is
  the single-shard special case; scaling across cores remains
  SO_REUSEPORT's job, as flow already concluded when it dropped its
  multi-shard experiment.
- **Go.** Channels as the communication backbone, but Go's
  unstructured `go` statement and absent cancellation (retrofitted as
  `context.Context` threading) are the negative example structured
  concurrency answers.

## Specification

### Errors

All flow2 failures are instances of one record type, `<flow-error>`,
created with `make-flow-error` and inspected with accessors and
predicates. A `<flow-error>` reaches the program in one of two ways:
**raised** (at a suspension point, at a checkpoint, or by an API
misuse) or **received** on a response channel (a worker task's
failure reply). It is the same object either way.

The taxonomy, by symbol:

| symbol         | meaning                                                       |
|----------------|---------------------------------------------------------------|
| `cancelled`    | the scope owning this fiber or task was cancelled             |
| `timeout`      | a `flow-monitor` deadline expired                             |
| `overflow`     | a full channel with no scheduler to park on, or a re-bound below the current length |
| `compute`      | a worker task raised; the original object is in the cause     |
| `wrong-thread` | a main-thread-only operation was attempted on a compute thread|

#### `(make-flow-error symbol message irritants cause)`

Returns a fresh `<flow-error>`. `SYMBOL` is one of the taxonomy
symbols above, `MESSAGE` a string, `IRRITANTS` a list, `CAUSE` the
originating raised object when there is one (only `compute` errors
carry one today) and `#f` otherwise. User code normally never calls
this; it is exported so user protocols can reuse the type for their
own replies if they wish.

#### `(flow-error? obj)`

Returns `#t` if `OBJ` is a `<flow-error>`, otherwise `#f`.

#### `(flow-error-symbol flow-error)`

Returns the error's symbol, for `case` dispatch:

```scheme
(guard (ex ((flow-error? ex)
            (case (flow-error-symbol ex)
              ((timeout) (values 'partial (drain! results)))
              ((cancelled) (values 'gone #f))
              (else (raise ex)))))
  (flow-monitor 0.5 query))
```

#### `(flow-error-message flow-error)`
#### `(flow-error-irritants flow-error)`
#### `(flow-error-cause flow-error)`

Accessors for the remaining fields. `flow-error-cause` returns the
object originally raised by a worker task for a `compute` error, and
`#f` for every other symbol.

#### `(flow-error-cancelled? obj)`
#### `(flow-error-timeout? obj)`
#### `(flow-error-overflow? obj)`
#### `(flow-error-compute? obj)`
#### `(flow-error-wrong-thread? obj)`

One predicate per symbol; `(flow-error-timeout? obj)` is `(and
(flow-error? obj) (eq? (flow-error-symbol obj) 'timeout))`, and so on
for each. These are the natural `guard` clause tests when only one or
two symbols matter at a call site.

### Starting and stopping

#### `(flow-run proc)`
#### `(flow-run proc compute-count)`

Starts the io_uring loop on the calling thread — the **main thread**
— and spawns `PROC` as the initial fiber, *fiber zero*. With
`COMPUTE-COUNT` (default `0`) greater than zero, starts that many
**compute threads** before fiber zero runs; each compute thread
owns one request channel, and `PROC` receives the list of these
channels as its single argument (the empty list when
`COMPUTE-COUNT` is zero). Distribution of the channels beyond fiber
zero is the program's business: whoever holds a worker's channel may
submit to it.

The number of compute threads is fixed for the run. `flow-run`
returns when the loop stops.

#### `(flow-stop)`

Stops the loop; `flow-run` then returns. Main thread only.

Fibers still parked when the loop stops are simply never resumed —
`flow-stop` is a shutdown, not a cancellation, and there is no
`stopped` error symbol. A program that wants cleanup to run at
shutdown cancels its own top-level nursery first, then stops.

### Fibers

#### `(flow-spawn thunk)`

Spawns `THUNK` as a new fiber on the main thread. The fiber inherits
the current scope (see Nurseries): a fiber spawned inside a nursery
is a child of that nursery, transitively. Main thread only — called
from a compute thread it raises `wrong-thread`; a compute task that
needs a fiber spawned asks for one over its response channel (see
Patterns).

### Events

The Concurrent ML core, unchanged from `(letloop flow)`:

#### `(make-flow wrap try block)`

Returns a base event from its three behaviors: `WRAP` transforms the
synchronized value, `TRY` polls without blocking, `BLOCK` registers
for later completion. Library authors only.

#### `(flow? obj)`

Returns `#t` if `OBJ` is an event, otherwise `#f`.

#### `(flow-wrap event proc)`

Returns an event that synchronizes as `EVENT` does and applies `PROC`
to the result.

#### `(flow-guard thunk)`

Returns an event that calls `THUNK` to produce a fresh event at each
synchronization attempt.

#### `(flow-choice event ...)`

Returns an event that synchronizes on exactly one of `EVENT ...` —
whichever is ready first. Associative; nested choices flatten.

#### `(flow-perform event)`

Synchronizes on `EVENT`: returns immediately if some base is ready,
otherwise parks — the current *fiber* on the main thread, the
current *OS thread* (on a condition variable) on a compute thread.
While parked on the main thread inside a cancelled scope,
`flow-perform` raises `cancelled` and the losing bases' in-flight
operations (reads, timeouts, accepts) are cancelled on the ring.

### Channels

A flow2 channel is a buffered many-producer many-consumer queue, and
the only primitive that crosses OS threads. One channel type serves
every role: fiber-to-fiber on the main thread, worker request
channels, response channels. Bounded by default. When the main
thread is parked in the ring waiting for completions, a put from a
compute thread wakes it through an eventfd registered on the ring;
this is internal.

#### `(make-flow-channel [name [bound]])`

Returns a fresh channel bounded at 43 values. `NAME` is any object; it
appears in the saturation warning and in nothing else, so give it one
you will recognise in a log. A channel created without a name still
gets a process-unique integer, because a diagnostic that cannot say
which channel is in trouble is barely a diagnostic. Pass `#f` as
`BOUND` for a genuinely unbounded channel — deliberately, and visibly
at the call site.

#### `(flow-channel-name channel)`

The channel's name.

#### `(flow-channel-bound channel)`

The channel's bound, or `#f` if it is unbounded.

#### Diagnostics

`(flow-channel-queue-length channel)`,
`(flow-channel-getters-length channel)`,
`(flow-channel-space-length channel)`,
`(flow-scope-children-count scope)`,
`(flow-scope-waiters-length scope)`,
`(flow-scope-join-waiters-length scope)`.

Raw internal lengths, for telling apart *logically idle* from *still
holding state nobody will ever resume*. Every leak in this family lives
in the gap between the two numbers, and a structure full of entries no
one will resume looks identical from the outside to one that is
genuinely empty — in `(letloop flow)`'s 44GB incident the raw puts list
held 62 entries at 70 cumulative puts while logical pending stayed at
exactly 0, and reading both numbers is what finally identified it after
the application code had been exonerated by eight repeated-allocation
passes.

Watch `flow-channel-getters-length` against the number of fibers you
believe are parked on the channel, and `flow-scope-join-waiters-length`
in particular: that list has neither compaction nor removal, only the
implicit filter of a resume returning `#f`.

#### `(flow-channel? obj)`

Returns `#t` if `OBJ` is a channel, otherwise `#f`.

#### `(flow-channel-buffer-size! channel n)`

Re-bounds `CHANNEL` at `N` queued values. If `CHANNEL` already holds
more than `N` values, the call itself raises `overflow` — the bound is
never observably violated, and the mismatch surfaces at the call site
that created it. Prefer passing the bound to `make-flow-channel`;
this is for adjusting a channel you did not create.

#### `(flow-put! channel obj)`

Enqueues `OBJ` on `CHANNEL`. Returns immediately unless the channel is
full, in which case it **parks until there is room** — so `flow-put!`
is a suspension point and a cancellation point: a putter parked on a
full channel inside a cancelled scope is woken and raises `cancelled`.

Parking needs a scheduler. On a fiber it parks on the loop, on a
compute thread on its condition variable, and with neither — a bare
`flow-put!` outside `flow-run` — a full channel raises `overflow`
instead, because there is nothing to park on and hanging with no
diagnosis would be worse.

The first put to park on a given channel logs one
`(flow2 channel-full NAME BOUND)` warning through `flow-log`, re-armed
once the queue drains to half the bound. One line per saturation
episode, not per blocked put.

Callable from any thread. Put is a procedure, not an event — see
Rationale.

**Deadlock is now expressible**, as it is with any backpressure: a
fiber that fills a channel only it would drain waits forever. Bound
channels according to who drains them.

#### `(flow-get channel)`

Returns an *event* that synchronizes when a value can be dequeued
from `CHANNEL`, with the value as the result. Composable:

```scheme
(flow-perform (flow-choice (flow-get replies)
                           (flow-timeout 1.0)))
```

#### `(flow-get! channel)`

`(flow-perform (flow-get channel))` — dequeue, parking until a value
arrives. On a compute thread, parks the OS thread on its condition
variable.

#### `(flow-get-try channel default)`

Dequeues and returns a value if one is immediately available,
otherwise returns `DEFAULT`. Never parks. Callable from any thread.

### Timers

#### `(flow-timeout seconds)`

Returns an event ready after `SECONDS` (a real number). Backed by a
ring timeout SQE; as a losing choice member it is cancelled on the
ring. Main thread only (`wrong-thread` from a compute thread).

#### `(flow-sleep seconds)`

`(flow-perform (flow-timeout seconds))`.

### Network and file I/O

All main thread only; from a compute thread each raises
`wrong-thread` — a compute task obtains I/O through its response
channel protocol (see Patterns). Semantics carried over from
`(letloop flow)`:

#### `(flow-accept fd)`

Event: a client connection accepted on listening `FD`; result is the
client fd, or `#f` on failure.

#### `(flow-read fd)`

Event: bytes readable on `FD`. Three results, and EOF is **not** `#f`:

| result | meaning |
|---|---|
| bytevector | that many bytes were read |
| `#t` | clean EOF, the peer closed |
| `#f` | the read failed |

Distinguishing the last two matters — a loop that treats `#f` as EOF
silently turns an error into a normal end of stream.

#### `(flow-write fd bytevector [start])`

Event: one `send` of `BYTEVECTOR` from `START` (default `0`). Result is
the count actually written — a positive fixnum — or `#f` on failure.
`START` lets a caller resume a partial write without copying anything.

It does **not** loop internally, and that is deliberate. Resubmitting
the remainder from inside the completion handler runs on the
scheduler's stack with the fiber parked across every round trip, which
made the write uncancellable (a cancelled scope's chain kept issuing
ring operations against an fd the cleanup path had already closed),
unraceable (a `flow-choice` timeout that won could not stop it), and
quadratic (the whole remainder was copied per partial write, worst
exactly when partial writes happen). Looping in the caller makes each
chunk its own perform and therefore its own cancellation point, and
costs no atomicity — each resubmit was a separate ring operation
either way, so a competing send on the same fd could always interleave.

#### `(flow-write-all! fd bytevector)`

Writes all of `BYTEVECTOR`, resuming after each partial write. Returns
`#t` when everything is written, `#f` if a write failed; ask
`flow-write` directly if you need to know how far it got. A procedure
rather than an event, exactly as `flow-put!` is — every iteration
performs `flow-write`, so it is a suspension point and a cancellation
point throughout. An empty bytevector costs no syscall.

#### `(flow-open path flags mode)`

Three arguments. `FLAGS` is a bitwise-or of the exported open flags —
`O-RDONLY`, `O-WRONLY`, `O-RDWR`, `O-CREAT`, `O-TRUNC`, `O-APPEND` —
and `MODE` is the permission bits used when `O-CREAT` creates the
file, and ignored otherwise. Result is the fd, or `#f` on failure.

#### `(flow-read-at fd offset size)`
#### `(flow-write-at fd offset bytevector)`
#### `(flow-close fd)`

File events, same shape: result on success, `#f` on failure. No
`dynamic-wind`: callers close fds explicitly on both the normal and
the error path, and cancellation arriving as a raised `cancelled`
error (rather than a silent kill) is what makes that explicit cleanup
reachable.

### Nurseries

A **scope** owns fibers and, transitively, everything they do: their
in-flight ring operations, their child fibers, and the compute tasks
they submit. Scopes form a tree by inheritance — `flow-spawn` and
`flow-submit!` performed inside a scope's dynamic extent belong to
that scope. A cancelled scope drains before it propagates: when an
enclosing cancellation interrupts a nursery's join, the nursery kills
its own scope, waits — uninterruptibly this time — for its children to
finish unwinding, and only then re-raises. Nothing outlives its scope,
including on the cancellation path. The cost is that a child parked in
an operation that cannot be cancelled will hold its parent there; see
Issues for the two that still cannot be. Fibers outside any nursery
belong to the *root scope*,
which is never cancelled and costs nothing on the hot path.

#### `(flow-nursery proc)`

Creates a fresh scope as a child of the current one and calls `PROC`
with it. Does not return until every fiber spawned inside the scope
has returned or raised — the **join**. Returns `PROC`'s value.

If a child fiber raises, the scope is cancelled — every sibling
parked on an event is resumed with a raised `cancelled`, every
in-flight ring operation belonging to the subtree is cancelled, every
scope-tagged compute task is flagged — and the child's original
raised object re-raises at the join. First error wins;
later siblings' errors are dropped.

If the scope was cancelled by `flow-scope-cancel!`, the join raises
`cancelled`. Under `flow-monitor`, deadline cancellation raises
`timeout` instead.

#### `(flow-scope? obj)`

Returns `#t` if `OBJ` is a scope, otherwise `#f`.

#### `(flow-scope-cancel! scope)`

Cancels `SCOPE` and its subtree, as described above. Idempotent.

#### `(flow-monitor seconds thunk)`

`flow-nursery` with a deadline: runs `THUNK` in a fresh scope racing
a `SECONDS` timeout. If the subtree joins first, returns `THUNK`'s
value and the timeout is cancelled on the ring. If the deadline
fires first, the scope is cancelled and `flow-monitor` raises a
`timeout` `<flow-error>`. This is the primitive the fan-out patterns
below build on: "give this whole query N milliseconds, and whatever
has not answered, cancel its I/O and stop waiting."

#### `(flow-cancelled?)`

Returns `#t` if the current scope (on the main thread) or the
current task's scope (on a compute thread) has been cancelled. The
explicit checkpoint for long stretches of pure compute; channel
operations check it implicitly.

### Compute threads

A compute thread runs a framework loop over its request channel:
dequeue a task, run it under a guard, repeat. It never touches the
ring and never spawns fibers. What the framework guarantees per
task:

- **Always a reply on failure.** If the thunk raises, the guard
  wraps the raised object as a `compute` `<flow-error>` (the original
  in `flow-error-cause`) and puts it on the task's response channel.
  The worker survives and takes the next task. A submitter waiting
  on the response channel therefore cannot hang on a dead task —
  the Erlang `DOWN` guarantee, at the thread boundary. The error
  reply is exempt from the response channel's buffer bound: it
  enqueues even on a full bounded channel (one value of slack, on
  the failure path only), so the guarantee is unconditional.
- **Cancellation.** Each task carries the scope current at
  submission. A task whose scope is cancelled *before* it is
  dequeued is skipped entirely. A *running* task observes
  cancellation cooperatively: every channel operation it performs
  raises `cancelled` once the scope is dead, and `(flow-cancelled?)`
  is the explicit checkpoint for compute loops that touch no
  channel; its puts after cancellation are dropped. Compute between
  checkpoints runs to its next checkpoint — a Scheme thread cannot
  be preempted, so an uncooperative infinite loop is out of scope
  (literally).

#### `(flow-submit! worker-channel thunk response-channel)`

Enqueues the task `(THUNK . RESPONSE-CHANNEL)` on `WORKER-CHANNEL`,
tagged with the current scope **and counted as one of its children**,
so the enclosing nursery's join waits for the task exactly as it waits
for a fiber. Returns immediately unless the worker channel is full, in
which case it parks like any other put — that is the pool exerting
backpressure on its submitters, and it means `flow-submit!` is a
suspension point and a cancellation point. The
submitting side then reads `RESPONSE-CHANNEL` and interprets whatever
protocol it and the thunk agreed on. `THUNK` runs on the compute
thread with no arguments; by convention it closes over
`RESPONSE-CHANNEL` (and any downlink channel) itself — the copy in
the task record is for the framework's error reply and nothing else.

### Diagnostics

#### `(flow-log sexp)`

Records `SEXP`, timestamped with the loop's cached per-tick jiffy, and
returns. Callable from **any** thread, and the one facility here that
is: a call conses onto a box the calling thread owns and does nothing
else — no mutex, no port, no syscall. That is the whole design
requirement. Logging has to be safe on the loop thread, where a
syscall costs every fiber, and on a compute thread, where blocking
wastes the core the pool exists to use. Before there is a loop the
timestamp is `0` rather than an error, so a library can warn during
startup without taking the program down.

#### `(flow-log-drain!)`

Every pending entry as a list of `(timestamp . sexp)`, oldest first
within each thread's own accumulator, threads concatenated in
registration order rather than globally sorted — sort on the
timestamps if you need strict cross-thread order. Draining empties.

#### `(flow-log-start! period-seconds)` / `(flow-log-stop!)`

Start a single dedicated OS thread that drains and writes to
`(current-error-port)` every `PERIOD-SECONDS`, and stop it. Calling
`flow-log-start!` twice does not fork a second flush thread. The port
is read at flush time, not captured at start, so reparameterizing it
is honored on the next cycle. `flow-log-stop!` blocks until the thread
has done a final drain, so nothing logged before the request is lost.

What the library itself logs:

| entry | when |
|---|---|
| `(flow2 channel-full NAME BOUND)` | a put parked on a full channel, once per saturation episode |

## Patterns

flow2 ships mechanisms, not protocols. These are the intended shapes.

### Spawn a fiber, plainly

```scheme
(flow-run
 (lambda (workers)
   (flow-spawn (lambda () (serve-http 8080)))
   (flow-spawn (lambda () (metrics-tick)))))
```

Fibers spawned outside a nursery live in the root scope: never
cancelled, no bookkeeping cost. This is the HTTP server's hot path
and it compiles to exactly what flow does today.

Inside a nursery it is not free, and the difference is worth knowing
before you decide every fiber should belong to one. Every perform in a
cancellable scope carries one extra base event, and
`benchmarks/flow2-nursery-bench.scm` measures what that costs:

| workload | root | in a nursery | |
|---|---|---|---|
| ping-pong, every operation parks | 1.20M ops/s | 1.03M ops/s | **+16%** |
| drain, nothing parks | 12.99M ops/s | 10.47M ops/s | **+24%** |

`flow-monitor` measures the same as `flow-nursery` to within 1
percentage point, which is the expected result — a deadline adds one
ring timeout for the whole scope, not per operation — and is what the
benchmark uses as its own sanity check.

For scale: a per-connection `flow-choice` read timeout was added to
this repository's HTTP server in `ec70498` and reverted in `05ab523`,
costing "~19% throughput to CML bookkeeping overhead" (TODO.md:60).
A nursery is the same shape of change and the same order of cost. Use
one where you want its guarantee — that no fiber outlives its scope —
and not by reflex on the hottest path you have.

### Fan out, gather, and never hang

The pattern that motivated the nursery. No guard in the fetch fiber,
no counting N replies:

```scheme
(define (query-ngrams ngrams)
  (define replies (make-flow-channel))
  (flow-nursery
   (lambda (scope)
     (for-each (lambda (ngram)
                 (flow-spawn
                  (lambda ()
                    (flow-put! replies (fetch-ngram ngram)))))
               ngrams)))
  ;; the join guarantees: every fiber returned, or one raised and
  ;; the nursery re-raised it after cancelling the others' I/O.
  (let loop ((out '()))
    (let ((r (flow-get-try replies #f)))
      (if r (loop (cons r out)) out))))
```

If `fetch-ngram` raises in any fiber, the nursery cancels every
sibling's in-flight read, and the raise surfaces here — instead of a
wait loop hanging on a message a dead fiber will never send.

### Bound a whole query

```scheme
(guard (ex ((flow-error-timeout? ex) 'not-fast-enough))
  (flow-monitor 0.250
    (lambda () (query-ngrams ngrams))))
```

Everything transitively spawned under the monitor — fibers, their
reads, their compute submissions — is cancelled when the budget
expires. Partial results gathered on a channel *outside* the monitor
remain readable in the `timeout` branch, if partial answers are
acceptable.

### Do I/O from a compute thread

The whole point of the verb-less design: the protocol below belongs
to the *application*, not to flow2. A task sends requests up its
response channel; the submitting fiber interprets them and performs
the ring I/O; results come back on a downlink channel the task
created for itself.

```scheme
;; --- main thread: submit, then serve the task's protocol ---
(define (run-indexing worker filepath)
  (define up (make-flow-channel))     ; task -> main
  (define down (make-flow-channel))   ; main -> task
  (flow-submit! worker
                (lambda () (index-file down up filepath))
                up)
  (let loop ()
    (let ((msg (flow-get! up)))
      (cond
       ((flow-error? msg) (raise msg))          ; framework error reply
       (else
        (case (car msg)
          ((read-at)                            ; (read-at fd offset size)
           (flow-spawn                          ; concurrent, not serial:
            (lambda ()                          ; N read-ats overlap on the ring
              (flow-put! down (apply do-read-at (cdr msg)))))
           (loop))
          ((done) (cadr msg))))))))

;; --- compute thread: pure compute, I/O by message ---
(define (index-file down up filepath)
  (let loop ((offset 0) (index empty-index))
    (flow-put! up `(read-at ,filepath ,offset 65536))
    (let ((chunk (flow-get! down)))             ; parks the OS thread
      (if chunk
          (loop (+ offset 65536) (index-chunk index chunk))
          (flow-put! up `(done ,index))))))
```

Two things to notice. The main-side handler *spawns a fiber per
request*, so a task that sends several requests before collecting
gets genuinely overlapping I/O — the serial version of this exact
pattern measured 2× slower on cold queries, which is why the
protocol is left in user hands where it can be pipelined. And
`flow-get!` on the compute thread is the task's cancellation point:
if the submitting scope dies, the get raises `cancelled` and the
framework converts the unwound task into a (dropped) reply.

### Dispatch on errors

```scheme
(let ((msg (flow-get! up)))
  (if (flow-error? msg)
      (case (flow-error-symbol msg)
        ((compute)                          ; task raised; look inside
         (log-failure (flow-error-cause msg))
         'retry)
        ((cancelled) 'gone)
        (else (raise msg)))
      (handle msg)))
```

The same `case` works in a `guard` clause for the raised transport;
`<flow-error>` is one representation across both.

### Keep long compute cancellable

```scheme
(define (crunch down up rows)
  (let loop ((rows rows) (acc '()) (n 0))
    (when (and (fx= 0 (fxmod n 4096)) (flow-cancelled?))
      (raise (make-flow-error 'cancelled "crunch: scope died" '() #f)))
    (if (null? rows)
        (flow-put! up `(done ,acc))
        (loop (cdr rows) (cons (transform (car rows)) acc) (fx+ n 1)))))
```

A task that performs channel operations gets cancellation checks for
free; a pure loop must volunteer them. Choose the stride by how much
latency a cancelled monitor may tolerate — compute between two
checkpoints always runs to the next one.

## References

- John Reppy, *Concurrent Programming in ML*, Cambridge University
  Press, 1999 — the event algebra (`wrap`, `guard`, `choose`,
  `sync`).
- Andy Wingo, *Lightweight concurrency in Guile with fibers*, and the
  guile-fibers manual — CML operations over an epoll scheduler in
  Scheme.
- Nathaniel J. Smith, *Notes on structured concurrency, or: Go
  statement considered harmful*, 2018 — nurseries, first-error
  cancellation, timeouts as scopes.
- Joe Armstrong, *Making reliable distributed systems in the presence
  of software errors*, PhD thesis, 2003 — links, monitors, and the
  always-delivered `DOWN` guarantee.
- The Seastar documentation and Glommio design notes —
  thread-per-core, share-nothing ownership of the ring, message
  passing between shards.
- `TODO.md` in this repository — the observed failures motivating
  this design: ring corruption from off-loop SQE preparation, and
  the unguarded fan-out leak.
- `plans/v12/20260720-flow/README.md` — the original `(letloop
  flow)` design and milestone plan flow2 forks from.

## Copyright

© 2026 Amirouche A. BOUBEKKI.
