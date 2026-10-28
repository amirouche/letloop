# Fibers and channels over io_uring

Library name: `(letloop flow2)`

## Author

Amirouche A. BOUBEKKI

## Status

`(letloop flow2)` is **implemented**, in `src/letloop/flow2.scm`, with
73 checks in `src/letloop/flow2.check.scm`. It has no consumers yet;
`(letloop flow)` stays untouched and keeps serving its current ones.

This document began as a draft specification and is now the library's
reference, so where the two ever disagree the source wins. It was last
reconciled against the implementation on 2026-10-21, after the
sixth pass's findings were fixed. The day before, nurseries were
removed — the largest change to documented behaviour since the
draft: `flow-nursery`, `flow-monitor`, scope cancellation and the
compute-task error reply are gone, and `flow-submit!` takes a thunk
only (see the last paragraphs of Issues, and Rationale). Two earlier
reconciliations changed documented behaviour: channels became bounded
by default with a full put parking (2026-08-17), and `flow-read-at`
now reports a clean EOF as `#t` like `flow-read` rather than as `'eof`
(2026-08-26).
Decisions herein were resolved on 2026-08-14; the
motivating failures are documented in `TODO.md` (sections "monitored
trees with automatic timeout-and-cancel" and
"flow-block-and-wait-off-loop registers ring events from the worker
thread").

## Abstract

flow2 is a concurrency library for the letloop runtime built on two
primitives: **fibers** (cooperative lightweight threads multiplexed on
one OS thread that owns an io_uring) and **channels** (buffered,
many-producer many-consumer queues, the only mechanism that crosses OS
threads), composed with Concurrent ML events. A **latch** — fired
once, seen by every waiter — covers the one thing a channel cannot
say: "this happened", to everyone at once.

flow2 owns delivery and the cleanup of a choice's losers, and nothing
about lifetimes. A fiber or a task runs until it returns; an error it
does not handle ends it and becomes a `flow-log` entry. How a fan-out
waits — for all, for the first, for a quorum, until a deadline — and
what it does with the stragglers is the program's, written with
channels, `flow-choice` and `flow-timeout`.

The main thread is the only thread that touches the io_uring.
Compute threads run user thunks submitted over channels and have no
I/O verbs of their own: a compute task that needs I/O sends messages
in a user-defined protocol over channels, and the fiber that
submitted the task performs the I/O on its behalf.

Errors are plain records of one type, `<flow-error>`, dispatched by
symbol — not R6RS conditions.

## Issues

The passes recorded below were made against a design that still had
nurseries, and they are kept as written: they are the history of how
each guarantee was earned or lost. The last paragraphs say what the
sixth pass found and why the nursery went.

The four issues raised by the first draft — whether the framework's
error reply respects the response channel's buffer bound, a `stopped`
error symbol for `flow-stop`, shrinking a bound below the current queue
length, and wholesale `flow-scope-attach!` of a worker channel — were
resolved on 2026-08-16 and their resolutions are specified inline (see
`flow-stop`, `flow-channel-buffer-size!`, and Compute threads; the
scope-tagging resolution went with nurseries).

Every gap the 2026-08-17 adverse review found is closed. Its findings
are recorded in the commits that fixed them, and the two design costs
that came out of the fixes are stated where they apply rather than
here: a full put parks, so deadlock is expressible (see `flow-put!`),
and a cancelled scope drains before it propagates, so an uncancellable
child holds its parent (see Nurseries).

A second adverse pass on 2026-08-19 — run against the tree with every
first-pass fix in — found six more, all closed the next day, and their
pattern is worth keeping: each invariant had been proven on the loop
thread and inherited, unverified, by the cross-thread and post-mortem
paths. The worker-resume path inverted the cancels-before-continuation
order the on-loop fix had established; a nursery opened inside an
already-dead scope escaped cancellation entirely; the monitor's race
skipped the drain the nursery's join performs; the pool's shared
globals let a straggler worker corrupt the next `flow-run`. Their
findings, too, live in the commits that fixed them, each with its
regression check.

A third pass on 2026-08-24 went after the **cleanup path** and after
this document's own examples, and both gave way. All nine findings are
closed, and their pattern is different again: the first two passes
found invariants that were true somewhere and assumed everywhere, while
this one found places where the *specification* and the code had drifted
apart and nobody had re-run the example. `flow-close` inside a cancelled
scope raised `cancelled` before reaching the ring, so the fd leaked on
precisely the path described here as the one that releases it. The
"Fan out, gather, and never hang" pattern below deadlocked past the
default bound, on the page that states the rule it broke. A `flow-read`
that lost its choice discarded bytes the kernel had already taken off
the socket. "Callable from any thread" was true of exactly one
procedure, and it was the one that said it was the only one.

Two costs are stated where they apply rather than here: a write that
loses a race cannot be recovered the way a read now can (see
`flow-write`), and a bounded channel drained only after a join must be
sized for the whole fan-out (see the pattern).

A fourth pass on 2026-08-27 read the third pass's own fixes, and its
six findings are what those fixes had left behind. The pattern this
time is **where a fix was applied, not whether it was right**. The
cross-thread guard was correct and went to the three procedures the
finding named, while `flow-perform` — which every suspending operation
funnels through, and which four more entry points bypass — went
without: `flow-get!` from a thread the user forked did not raise
`wrong-thread`, it succeeded, dequeuing off-loop and stranding the
putter it "resumed". `flow-read`'s new backlog was purged on close by
an index its own recv had never joined, so a late payload could
re-create the stash under an fd number the kernel was about to reissue
— the cross-connection leak the purge exists to prevent. And two
examples still contradicted the reference sections this document had
just reconciled: one read a clean EOF as falsy after the encoding was
unified, the other used `#f` as both a sentinel and a legal reply.

So the lesson the third pass drew has a second half. **A fix belongs at
the choke point the finding passes through, and documentation that
enumerates what is covered will drift to what was covered.** The three
procedures named in the Threads section were the three that had the
check; the guard lives in `flow-perform` now and the section states a
rule. The reproducers are in `checks/repro-flow2-fourth-pass.scm`, and
the two for the examples run the page's code as printed — which is the
third pass's own lesson, applied to the pass that stated it.

A fifth pass on 2026-09-03 went after what the earlier four had
*certified* rather than what they had fixed — the pool, the CML core,
the log — and found six defects and five drifts, all closed. Its
pattern: **a property proven for the value was assumed for the
vehicle.** The eventfd wake was a write of 1 in the source and, to the
kernel, a write of whatever the last read had left in the shared cell,
so coalesced wakes multiplied it to 2^64 and workers then blocked in
`write(2)` one per loop tick. `flow-wrap`'s procedure ran on whichever
thread delivered the value, before the commit, so a raising wrap
killed the putter and stranded the getter, and a worker delivering to
a loop fiber ran loop-side code on the compute thread — the one thing
the Rationale says cannot be written. A straggler's isolation covered
its own pool and not the channels it shares with the next run. The
flush thread read `current-error-port` on its own thread, where a
later `parameterize` never arrives. And `flow-channel-buffer-size!`
was the fifth guarded-by-name entry point, one past the fourth pass's
list of four. The reproducers are in
`checks/repro-flow2-fifth-pass.scm`; each defect has a regression check.

The lesson for this document specifically: **reconciling docs against
code is only right when the code is the part that is right.** The
2026-08-17 pass wrote a drifted `flow-write` implementation down as
intent; this pass had to undo that. An example that is not executed
somewhere is a claim, not a specification — the patterns below now have
checks.

A sixth pass on 2026-10-20 found eight more, and its pattern was
**identity carried by a thread or a global, inherited or left stale**.
`flow-run` had no guard against a second call, so one made from a
fiber or a compute task freed the ring that was running. A thread
forked inside a compute task inherited the worker's identity and was
accepted where it should have been refused — and, outliving the run,
wrote freed memory into a reused descriptor; the log's per-thread
boxes were inherited the same way; a failed start left `flow-run`
believing a run was in progress; a flush thread that died left
`flow-log-stop!` waiting forever; and a read after a lost race could
return the stream's bytes out of order. And the nursery's own current
scope was a dynamically scoped variable faked with a global and
reinstalled only on flow2's resume path, so a fiber that suspended
through the ring layer directly came back in whatever scope ran last,
and its nursery returned before its child had finished.

That last one opened the design question rather than a fix. A nursery
encodes one fan-out policy — the first failure cancels the siblings
and nothing outlives the block — as the shape every fiber must take,
and coordination that is not a tree cannot be written in it at all: a
search that gathers results until a deadline, answers with what it
has, and hands the same channels to a completer that outlives it and
fills a cache for the next query is precisely "a child outlives its
scope". On 2026-10-20 nurseries, monitors and scope cancellation were
removed, with the compute-task error reply that existed to serve them;
an uncaught error became a log entry; latches were added for
broadcast; and the flush thread's death no longer hangs its stop. The
remaining findings were fixed on 2026-10-21, each with a regression
check: `flow-run` claims the loop and releases it on every way out,
per-thread identity is no longer inherited by `fork-thread`, and a
losing read hands its in-flight recv to the next reader instead of
cancelling it. A suspicion from the same pass was confirmed and fixed
too: a `flow-get` that put a value back could leave a channel one past
its bound.

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

flow2's first answer was the **nursery**: every fiber spawned inside a
scope, a join that waits for all of them, and a child's raise
cancelling its siblings. It was removed on 2026-10-20 (see Issues),
and the reasoning is worth keeping because it reverses this paragraph.

A fan-out has many correct shapes — wait for all, take the first,
take a quorum, stop at a deadline and keep going in the background —
and the nursery made one of them the shape of every fiber. Cancel on
first error is a *policy*, and a library that owns the policy cannot
express the others; it can only grow escape hatches. What the counting
loop needs is narrower than a nursery: to learn that a fiber ended,
and how. That is a value the fiber can send itself — one `guard`
around its body that puts `(done . v)` or `(failed . ex)` on the
channel the gatherer reads — and a gatherer that races its reads
against a `flow-timeout` cannot hang on a fiber that never answers,
whatever the reason.

So the guarantee moved rather than vanished. What flow2 still
guarantees unconditionally is that an error nobody handles is never
silent: it ends the fiber (or task) and becomes a
`(flow2 uncaught ...)` entry in `flow-log`, which the program routes
where it likes. The unguarded fetch that leaked 10 GB under flow
leaves a log entry under flow2, and a gather written with a deadline
does not hang on it.

The cost is real: "no fiber outlives its scope" is no longer something
a reader can check from the shape of the code. It is a property of the
program, established by its own protocols and checked by its tests.

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
me" message. A task is a thunk; whatever the task needs from the main
thread it expresses in the *user's* protocol over channels it closes
over, and the submitting fiber is
responsible for reading and acting on those messages. The framework
that would otherwise live here — request routing, correlation,
batching, proxy fibers — is exactly the part that varies per
application, and freezing it into the library would either be too
rigid (one outstanding request at a time was measured **2× slower**
than the single-threaded server on cold I/O-bound queries) or grow
into a second io_uring implemented in Scheme. flow2 owns only what it
can guarantee: delivery, and the cleanup of a choice's losers.

**One error type, dispatched by symbol.** flow2 raises plain
`<flow-error>` records, not R6RS conditions. A self-contained record
with a symbol is the same value raised or put on a channel, so a
program's own protocols can reuse it, and dispatch is `case` on
`flow-error-symbol` or a direct predicate in a `guard` clause; there
is no condition-type hierarchy to import, subtype, or get wrong.

## Prior art

- **Concurrent ML** (Reppy). The event algebra — `flow-wrap`,
  `flow-guard`, `flow-choice`, synchronization as a first-class value
  — is CML's, inherited from `(letloop flow)` unchanged. flow2 keeps
  it because composable synchronization is what lets a deadline or a
  stop request be *just another event* raced against whatever a fiber
  is doing, written by the fiber itself.
- **guile-fibers** (Wingo) and **Loko Scheme fibers**. The same CML
  lineage in Scheme. fibers funnels all I/O through suspendable ports
  so no call site carries a wrapping discipline — flow2 reaches the
  same "no discipline to forget" property by giving non-loop threads
  no I/O surface at all.
- **Erlang/OTP.** Erlang's `spawn` is fire-and-forget like flow2's,
  and its `DOWN` message is how a process learns another ended. flow2
  had that guarantee in two places — the nursery join and the compute
  error reply — and gave both up for the convention it replaces them
  with: a fiber reports its own end on a channel, and an end nobody
  reported is a log entry. The properties flow2 does not copy:
  unbounded mailboxes (channels are bounded by default and put
  parks), untrappable `exit(kill)` (nothing can stop a fiber from
  outside; a fiber that should be stoppable listens for it), and
  restart-based supervision (in a shared heap a restart cleans almost
  nothing).
- **Trio** (Smith, "Notes on structured concurrency"). The nursery:
  no fiber outlives its scope, first error cancels siblings and
  re-raises at the join, timeouts are scopes. flow2 had this design as
  `flow-nursery` and `flow-monitor` until 2026-10-20 and removed it:
  its guarantee is strong, and it is also one fan-out policy made
  mandatory (see Rationale).
- **ØMQ.** The patterns flow2's fan-out now looks like: a ventilator
  that pushes work, a sink that gathers with a deadline, and no
  lifetime coupling between them — a slow worker is a missing reply,
  not a stuck parent.
- **seastar / glommio / thread-per-core io_uring runtimes.** The
  share-nothing rule — a ring is owned by exactly one thread, other
  threads communicate with messages, the loop is woken by eventfd —
  is the standard answer to exactly the corruption flow hit. flow2 is
  the single-shard special case; scaling across cores remains
  SO_REUSEPORT's job, as flow already concluded when it dropped its
  multi-shard experiment.
- **Go.** Channels as the communication backbone and an unstructured
  `go` statement, as here. Where Go threads `context.Context` through
  every call to carry cancellation, a flow2 fiber composes a stop
  latch into its own choices, so it is stoppable exactly where it says
  it is.

## Specification

### Errors

The failures flow2 raises are instances of one record type,
`<flow-error>`, created with `make-flow-error` and inspected with
accessors and predicates. They are raised at the call that failed — a
put that cannot park, a re-bound below the current length, an
operation from the wrong thread.

The taxonomy, by symbol:

| symbol         | meaning                                                       |
|----------------|---------------------------------------------------------------|
| `overflow`     | a full channel with no scheduler to park on, or a re-bound below the current length |
| `wrong-thread` | an operation was attempted from a thread that does not own it — a loop-thread-only operation on a compute thread, or any flow2 operation on a thread the user forked |

#### `(make-flow-error symbol message irritants cause)`

Returns a fresh `<flow-error>`. `SYMBOL` is any symbol — the taxonomy
above is what flow2 raises, and a program's own protocols may use
others — `MESSAGE` a string, `IRRITANTS` a list, `CAUSE` an
originating object or `#f`. flow2 itself always passes `#f`.

#### `(flow-error? obj)`

Returns `#t` if `OBJ` is a `<flow-error>`, otherwise `#f`.

#### `(flow-error-symbol flow-error)`

Returns the error's symbol, for `case` dispatch:

```scheme
(guard (ex ((flow-error? ex)
            (case (flow-error-symbol ex)
              ((overflow) 'dropped)
              ((wrong-thread) (error 'enqueue "called off the loop"))
              (else (raise ex)))))
  (flow-put! jobs job))
```

#### `(flow-error-message flow-error)`
#### `(flow-error-irritants flow-error)`
#### `(flow-error-cause flow-error)`

Accessors for the remaining fields.

#### `(flow-error-overflow? obj)`
#### `(flow-error-wrong-thread? obj)`

One predicate per symbol flow2 raises; `(flow-error-overflow? obj)` is
`(and (flow-error? obj) (eq? (flow-error-symbol obj) 'overflow))`, and
likewise for the other. These are the natural `guard` clause tests when only one or
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

`COMPUTE-COUNT` must be a non-negative fixnum; anything else is an
error at the call, before a loop or a thread exists. The number of
compute threads is fixed for the run. `flow-run` returns once the loop
has stopped *and* the compute pool has been joined, which is bounded
at two seconds — past that it logs
`(flow2 shutdown-workers-still-running N)` and leaks the eventfd rather
than hand a live writer a descriptor number about to be reused. A
worker still out after that is a *straggler*: it keeps its own run's
pool, so what it does with its own state lands on the dead run, and
every flow2 operation it attempts once a later `flow-run` is in
progress raises `wrong-thread` (see Threads).

There is one loop per process. Calling `flow-run` while a run is in
progress — from one of its fibers, or from any other thread — raises
"a flow-run is already in progress", and calling it from a compute
thread raises `wrong-thread`; the run in progress is unaffected
either way. A start that fails part-way, for example because no file
descriptor is left for the eventfd, raises after joining whatever part
of the pool had started, and leaves flow2 with no run in progress.

Note what does **not** stop the loop: a raise out of fiber zero. It is
a fiber like any other, so an unguarded raise ends it with a
`(flow2 uncaught fiber ...)` log entry and leaves the loop running with
nothing to run — `flow-run` never returns. Guard fiber zero, or make
its last act `flow-stop`.

#### `(flow-stop)`

Stops the loop; `flow-run` then returns. Main thread only.

Fibers still parked when the loop stops are simply never resumed —
`flow-stop` is a shutdown, not a cancellation, and there is no
`stopped` error symbol. A program that wants cleanup to run at
shutdown tells its fibers to finish — a stop latch they include in
their choices — waits for them to say they have, then stops.

### Fibers

#### `(flow-spawn thunk)`

Spawns `THUNK` as a new fiber on the main thread, and returns. Fire
and forget: flow2 keeps no record of the fiber, so nothing waits for
it and nothing but its own code can stop it. A spawner that needs to
know how the fiber ended says so in the thunk — puts a result, or a
failure caught by a `guard`, on a channel it reads (see Patterns).

An error the fiber does not handle ends it and is logged as
`(flow2 uncaught fiber CONDITION)`, the condition rendered to a
string; the loop and every other fiber carry on. Main thread only —
called from a compute thread it raises `wrong-thread`; a compute task
that needs a fiber spawned asks for one over a channel (see Patterns).

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
to the result. `PROC` runs on the **performing** fiber or thread, after
the synchronization has committed, inside whatever `guard` surrounds
the `flow-perform` — never on the thread that delivered the value. A
`PROC` that raises therefore raises out of `flow-perform`, whichever
path won, and a `PROC` that itself performs is an ordinary nested
perform.

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
When one base wins, the losing bases' registrations are withdrawn and
their in-flight operations (reads, timeouts, accepts, writes) are
cancelled on the ring, before the performer resumes. That is the only
cancellation flow2 has.

### Channels

A flow2 channel is a buffered many-producer many-consumer queue, and
the only primitive that crosses OS threads. One channel type serves
every role: fiber-to-fiber on the main thread, worker request
channels, and whatever channels a program's tasks reply on. Bounded by
default. When the main
thread is parked in the ring waiting for completions, a put from a
compute thread wakes it through an eventfd registered on the ring;
this is internal.

#### `(make-flow-channel [name [bound]])`

Returns a fresh channel bounded at 43 values. `NAME` is any object; it
appears in the saturation warning and in an `overflow` error's
irritants, and a worker's request channel is named `(worker . I)`,
which is how an uncaught task error says which thread it came from.
Give it one you will recognise in a log. A channel created without a name still
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
`(flow-channel-space-length channel)`.

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
believe are parked on the channel.

#### `(flow-channel? obj)`

Returns `#t` if `OBJ` is a channel, otherwise `#f`.

#### `(flow-channel-buffer-size! channel n)`

Re-bounds `CHANNEL` at `N` queued values. If `CHANNEL` already holds
more than `N` values, the call itself raises `overflow` — the bound is
never observably violated, and the mismatch surfaces at the call site
that created it. Prefer passing the bound to `make-flow-channel`;
this is for adjusting a channel you did not create.

#### `(flow-put! channel obj)`

Enqueues `OBJ` on `CHANNEL` — or hands it straight to a parked getter
— returning immediately unless the channel is full, in which case it
**parks until there is room**. So `flow-put!` is a suspension point,
and a putter parked on a full channel nobody drains stays parked:
nothing in flow2 will wake it but room.

Parking needs a scheduler. On a fiber it parks on the loop, on a
compute thread on its condition variable, and with neither — a bare
`flow-put!` outside `flow-run` — a full channel raises `overflow`
instead, because there is nothing to park on and hanging with no
diagnosis would be worse.

The first put to park on a given channel logs one
`(flow2 channel-full NAME BOUND)` warning through `flow-log`, re-armed
once the queue drains to half the bound. One line per saturation
episode, not per blocked put.

Callable from the loop thread or from a **compute** thread — see
[Threads](#threads). Put is a procedure, not an event — see Rationale.

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
otherwise returns `DEFAULT`. Never parks. Callable from the loop thread
or from a **compute** thread — see [Threads](#threads).

`DEFAULT` is returned, not distinguished: nothing marks it as coming
from an empty channel rather than from the queue. `#f` is the tempting
choice and the wrong one wherever `#f` is a legal value on that
channel, because a gather loop written as `(let loop () (let ((v
(flow-get-try ch #f))) (if v ...)))` then stops at the first real `#f`
and drops everything queued behind it. Count the values when the count
is known, or pass a sentinel that cannot collide — a fresh `(list
'empty)`, compared with `eq?`.

### Timers

#### `(flow-timeout seconds)`

Returns an event ready after `SECONDS` (a real number). Backed by a
ring timeout SQE; as a losing choice member it is cancelled on the
ring. Loop thread only — *performing* it from a compute thread raises
`wrong-thread`, like every other ring event. Constructing one there is
harmless, which is what lets a worker build an event it hands back for
the submitting fiber to perform.

#### `(flow-sleep seconds)`

`(flow-perform (flow-timeout seconds))`.

### Network and file I/O

All main thread only; from a compute thread each raises
`wrong-thread` — a compute task obtains I/O through a channel
protocol of its own (see Patterns). Semantics carried over from
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

A read that **loses** a `flow-choice` — the idle-timeout idiom below,
say — does not lose its bytes, and does not reorder them. Its recv is
not cancelled: it stays in flight, and the next `flow-read` on that fd
takes it over rather than submitting a second one, so bytes arrive in
the order the kernel took them off the socket. A recv that completes
while nobody is reading — including in the same tick the winner
completed — keeps its payload on a per-fd backlog that the next
`flow-read` takes first. The backlog and any recv left in flight are
discarded with the fd, on close.

#### `(flow-write fd bytevector [start])`

Event: one `send` of `BYTEVECTOR` from `START` (default `0`). Result is
the count actually written, or `#f` on failure. The count is a positive
fixnum for a real send, and `0` when `START` equals the length — nothing
is left to send, so no syscall is issued and the event is immediately
ready. `START` lets a caller resume a partial write without copying
anything.

It does **not** loop internally, and that is deliberate. Resubmitting
the remainder from inside the completion handler runs on the
scheduler's stack with the fiber parked across every round trip, which
made the write unstoppable (the chain kept issuing ring operations
against an fd the cleanup path had already closed), unraceable (a
`flow-choice` timeout that won could not stop it), and quadratic (the
whole remainder was copied per partial write, worst exactly when
partial writes happen). Looping in the caller makes each chunk its own
perform, so a deadline raced against it takes effect between chunks,
and
costs no atomicity — each resubmit was a separate ring operation
either way, so a competing send on the same fd could always interleave.

The write side has no equivalent of the read backlog and cannot: a send
that completed but lost its `flow-choice` has already put those bytes on
the wire, and there is nothing to hand to a later caller. The result is
reported to nobody, so **a caller that retries after losing a race
duplicates what it already sent**. Race a write against a deadline only
when you are prepared to abandon the connection, which is usually the
honest response to a peer that cannot keep up anyway.

#### `(flow-write-all! fd bytevector)`

Writes all of `BYTEVECTOR`, resuming after each partial write. Returns
`#t` when everything is written, `#f` if a write failed; ask
`flow-write` directly if you need to know how far it got. A procedure
rather than an event, exactly as `flow-put!` is — every iteration
performs `flow-write`, so it is a suspension point throughout. An
empty bytevector costs no syscall.

#### `(flow-open path flags mode)`

Three arguments. `FLAGS` is a bitwise-or of the exported open flags —
`O-RDONLY`, `O-WRONLY`, `O-RDWR`, `O-CREAT`, `O-TRUNC`, `O-APPEND` —
and `MODE` is the permission bits used when `O-CREAT` creates the
file, and ignored otherwise. Result is the fd, or `#f` on failure.

#### `(flow-read-at fd offset size)`

Event: up to `SIZE` bytes of `FD` at `OFFSET`. These primitives keep no
cursor — the caller tracks its own offset. Results follow `flow-read`:

| result | meaning |
|---|---|
| bytevector | that many bytes were read, possibly fewer than `SIZE` |
| `#t` | clean EOF, nothing left at that offset |
| `#f` | the read failed |

#### `(flow-write-at fd offset bytevector)`

Event: one write of `BYTEVECTOR` at `OFFSET`. Result is the count
actually written, or `#f` on failure; like `flow-write` it does not
loop, so a caller wanting all of it writes the loop.

#### `(flow-close fd)`

Event: closes `FD`; result is `0`, or `#f` on failure. The one ring
event that registers no cancel, because cancelling a close would leak
the fd. Composed with other bases — `(flow-choice (flow-close fd)
(flow-read fd))` — the choice is decided as a whole; a close already in
flight when another base wins still completes, and its result is
discarded.

No `dynamic-wind`: callers close fds explicitly on both the normal and
the error path.

### Latches

A channel hands each value to *one* getter, so it cannot tell everyone
who cares that something happened. A latch can: it fires at most once,
with a value, and from then on every wait — parked or later —
completes with that value. Typical uses are a stop request to every
producer of a fan-out, and "the result for this key is complete" to
every query parked on it. A latch is never reset; a new episode is a
new latch. Like a channel, it crosses threads: a compute thread may
fire one and wait on one.

#### `(make-flow-latch)`

Returns a fresh, unfired latch.

#### `(flow-latch? obj)`

Returns `#t` if `OBJ` is a latch, otherwise `#f`.

#### `(flow-latch-fire! latch value)`

Fires `LATCH` with `VALUE` and wakes every waiter. Returns `#t` if this
call fired it, `#f` if it had already fired, in which case nothing
changes — the first value stays. Callable from the loop thread or a
compute thread.

#### `(flow-latch-fired? latch)`

Returns `#t` once `LATCH` has fired. Never parks; the checkpoint for a
compute loop that touches no channel.

#### `(flow-latch-wait latch)`

Returns an *event* ready once `LATCH` has fired, with its value as the
result. A wait consumes nothing, and a wait that loses a choice removes
itself. Composing it into a fiber's own choices is how that fiber
becomes stoppable:

```scheme
(flow-perform
 (flow-choice (flow-wrap (flow-latch-wait stop) (lambda (_) 'stop))
              (flow-get work)))
```

#### `(flow-latch-wait! latch)`

`(flow-perform (flow-latch-wait latch))`.

### Threads

There are exactly two kinds of thread flow2 knows about: the one that
called `flow-run`, which owns the ring and runs every fiber, and the
compute threads that same `flow-run` forked. "Cross-thread" throughout
this document means between those, and nothing else.

A thread the **user** forked is neither — including one forked by code
running *inside* a compute task, directly or through a library that
starts threads of its own. Such a thread does not inherit the worker's
identity: it is refused like any other, and hands its results back to
the task that forked it through ordinary Chez synchronization (a mutex
and condition, or a joined thread), for the task to put on a channel.
Without a check it would be worse than refused. It holds no worker
pool, so
flow2 mistakes it for the loop thread: an operation from it mutates
channels and the loop's
pending-thunk list with no synchronization against the loop's
take-and-clear of them, sends no eventfd wake — so a resume is lost
outright or delayed by a whole wait timeout — and parks on a
continuation that does not exist in that thread.

**Every flow2 operation raises `wrong-thread` when called from one.**
Not a list of them: `flow-perform` carries the check, so every
suspending operation inherits it, and the six that reach a channel, a
latch or the scheduler without suspending — `flow-put!`,
`flow-get-try`, `flow-submit!`, `flow-spawn`,
`flow-channel-buffer-size!`, `flow-latch-fire!` — plus `flow-stop`
check on their own. Read the rule
as universal; do not read the parenthetical as the boundary. An
earlier version of this page named three procedures, and the three
were the only three that had the check; the version after that named
four, and `flow-channel-buffer-size!` — which wakes parked putters, a
resume like any other — was the fifth.

A compute thread that outlived its run's shutdown join — a
*straggler*, see `flow-run` — is treated the same way by every later
`flow-run`: from the live run's point of view it is a thread flow2 does
not own, so its operations raise `wrong-thread` rather than reach a
channel the live run is parked on through a pool nobody drains.

Outside a `flow-run` there is nothing to corrupt and no check: priming
a channel before the loop starts is legitimate.

`flow-log` is the one exception, and genuinely takes any thread: it
appends to a box that the calling thread alone writes.

### Compute threads

A compute thread runs a framework loop over its request channel:
dequeue a task, run it, repeat. It never touches the ring and never
spawns fibers. What the framework guarantees per task is small on
purpose:

- **An unhandled raise is logged, and the worker survives.** If the
  thunk raises and does not catch it, the framework logs
  `(flow2 uncaught task (worker . I) CONDITION)` and takes the next
  task, so the pool never shrinks because one task failed. It does
  **not** reply on the task's behalf: a task whose submitter must hear
  about failure wraps its own body in a `guard` and puts the outcome
  on the channel the submitter reads.
- **Nothing stops a running task but the task.** A Scheme thread cannot
  be preempted, and flow2 has no cancellation; a long task that should
  be stoppable checks a latch — `flow-latch-fired?` between chunks, or
  `flow-latch-wait` in the choice it parks on.

Until 2026-10-20 the framework also put a `compute` `<flow-error>` on a
response channel passed to `flow-submit!` whenever the task raised,
and skipped or cancelled tasks whose submitting scope had died. Both
went with nurseries (see Rationale).

#### `(flow-submit! worker-channel thunk)`

Enqueues `THUNK` on `WORKER-CHANNEL`; the worker runs it with no
arguments. Returns immediately unless the worker channel is full, in
which case it parks like any other put — that is the pool exerting
backpressure on its submitters, and it means `flow-submit!` is a
suspension point. The thunk talks to the rest of the program over
channels it closes over, in whatever protocol it and its submitter
agree on.

### Diagnostics

#### `(flow-log sexp)`

Records `SEXP`, timestamped with the loop's cached per-tick jiffy, and
returns. Callable from **any** thread, and the one facility here that
is: a call conses onto a box the calling thread owns and does nothing
else — no mutex, no port, no syscall. That is the whole design
requirement. Logging has to be safe on the loop thread, where a
syscall costs every fiber, and on a compute thread, where blocking
wastes the core the pool exists to use. The one exception is the
first call in a process that has not taken the log over, which also
forks the default printer (see `flow-log-start!`) — once, not per
call. Before there is a loop the timestamp is `0` rather than an
error, so a library can warn during startup without taking the
program down.

#### `(flow-log-drain!)`

Every pending entry as a list of `(timestamp . sexp)`, oldest first
within each thread's own accumulator, threads concatenated in
registration order rather than globally sorted — sort on the
timestamps if you need strict cross-thread order. Draining empties.

A drain also takes the log over from the default printer (see below),
which stops; what is logged afterwards waits for the next drain.

#### `(flow-log-start! period-seconds [sink])` / `(flow-log-stop!)`

Start draining the log every `PERIOD-SECONDS` into `SINK`, and stop.
`SINK` is a textual output port or a procedure, and the two run in
different places on purpose.

A **port** is written one entry per line by a single dedicated OS
thread, because a write can block and a blocked loop stops every fiber.

A **procedure** is called with each non-empty list of entries **on the
loop thread**, by a fiber, while a run is in progress. The procedure is
where a program decides what flow2's own events mean to it — count
uncaught errors, forward them, drop the noise — and deciding usually
means acting, so it may do anything a fiber may: fire a latch, put on a
channel, call `flow-stop`. The cost is the same as any fiber's: a slow
sink delays every other fiber, and a sink that parks parks the log.
Between runs nothing calls it, and entries wait; the end of a run
hands it whatever was logged since the last period, shutdown entries
included, on the thread that called `flow-run`. During a run, starting
or stopping a procedure sink anywhere but the loop thread raises
`wrong-thread` — `flow-log-stop!` hands the sink its final batch on the
calling thread.

`SINK` defaults to the caller's `(current-error-port)` **at the moment
of the call**, captured on the calling thread: `current-error-port` is
a thread parameter, so a `parameterize` established later, on another
thread, is invisible to a flusher already running. To redirect, pass
the port, or stop and start inside the `parameterize`. A
`flow-log-start!` while the default printer runs replaces it; while a
flusher the program started runs, a second `flow-log-start!` does not
fork another and its sink is ignored. `flow-log-stop!` blocks until
the thread has done a final drain, so nothing logged before the
request is lost; after it, entries accumulate until the program drains
them or starts a flusher again.

If the sink raises — a port that fails to write, a procedure that
raises — the flusher stops: the flush thread exits, or the procedure is
unregistered. `flow-log-stop!` returns and a new `flow-log-start!`
works, and the batch the sink refused goes back into the log, followed
by a `(flow2 log-flush-raised CONDITION)` entry.

**By default the log prints to stderr.** The first `flow-log` in the
process starts a flusher writing to the calling thread's
`(current-error-port)` every 0.1 seconds, so a program that never
mentions the logger still sees its uncaught errors, and its entries do
not pile up in memory unread — an unbounded queue reached by *not*
configuring something is the failure channels are bounded to prevent.
The program takes the log over the first time it calls
`flow-log-drain!`, `flow-log-start!` or `flow-log-stop!`: the default
printer stops, printing what it already holds, and never restarts on
its own. A test drains first and then asserts on what it logs; a
program that wants the entries elsewhere starts its own flusher. If
writing to stderr fails, the default printer stops like any flusher
whose sink raised, and entries then accumulate.

What the library itself logs:

| entry | when |
|---|---|
| `(flow2 uncaught fiber CONDITION)` | a fiber raised and did not handle it; the fiber ended, the loop carried on |
| `(flow2 uncaught task (worker . I) CONDITION)` | a compute task raised and did not handle it; the worker took its next task |
| `(flow2 channel-full NAME BOUND)` | a put parked on a full channel, once per saturation episode |
| `(flow2 cancel-raised BASE CONDITION)` | a losing base's cancel thunk raised; the rest of the batch still ran. `BASE` is the base's tag (`(flow2-get NAME)` for a channel get, `(flow2-space NAME)` for a parked put, `flow2-latch` for a latch wait, `#f` for a ring event or a base built with `make-flow`) |
| `(flow2 block-raised-after-win CONDITION)` | a base's block proc raised after another base of the same perform had already won; the fiber kept the winner's value |
| `(flow2 collector-wait-raised)` | the collector could not re-arm its eventfd read; it retries next tick |
| `(flow2 shutdown-workers-still-running N)` | `flow-run` gave up joining `N` workers and leaked the eventfd rather than reuse its number |
| `(flow2 log-flush-raised CONDITION)` | the sink raised; the flusher stopped and its batch was put back |

`CONDITION` is the raised object rendered for a log line: a condition
becomes its message as a string, a `<flow-error>` becomes
`(flow-error SYMBOL MESSAGE)`, anything else is kept as is. The
`uncaught` entries are the first thing to look at after an unexplained
hang — a gather waiting on a fiber that died is waiting on one of
them; the last three name a path that recovered, or deliberately did
not.

## Patterns

flow2 ships mechanisms, not protocols. These are the intended shapes,
and each one's shape is executed somewhere — the check or reproducer
that runs it is named with it.

### Spawn a fiber, plainly

```scheme
(flow-run
 (lambda (workers)
   (flow-spawn (lambda () (serve-http 8080)))
   (flow-spawn (lambda () (metrics-tick)))))
```

No bookkeeping: a spawn is a `loop-spawn` under a guard, and this is
the HTTP server's hot path.

### Fan out and gather, every fiber reporting its end

```scheme
(define (query-ngrams ngrams)
  (define replies (make-flow-channel 'replies))
  (for-each (lambda (ngram)
              (flow-spawn
               (lambda ()
                 ;; one reply per fiber, whatever happens to it
                 (flow-put! replies
                            (guard (ex (#t (cons 'failed ex)))
                              (cons 'done (fetch-ngram ngram)))))))
            ngrams)
  ;; exactly (length ngrams) replies, so count them out
  (let loop ((n (length ngrams)) (out '()))
    (if (zero? n)
        out
        (loop (- n 1) (cons (flow-get! replies) out)))))
```

The `guard` is what keeps the count honest: without it a raising fetch
sends nothing, and the gather waits forever for a reply that will not
come (with a `(flow2 uncaught fiber ...)` entry in the log saying
which). Count the replies rather than testing them — a fetch may
legitimately answer `#f`, and `(flow-get-try replies #f)` as a loop test
stops at the first one. The gather runs while the fetches do, so the
default bound is fine: a fetch that outruns the gatherer parks until it
catches up. Run by `checks/repro-flow2-fourth-pass.scm`,
`readme-gather-keeps-a-false-reply`.

### Gather until a deadline, then hand off

The coordination a nursery could not express. A search fans out over
producers that stream pages, ranks whatever arrived by the deadline,
and hands the *same* channels to a completer that outlives the request
and fills the cache for the next query:

```scheme
(define (gather pages exits live seen deadline)
  (let loop ((live live) (seen seen))
    (if (zero? live)
        (values 'complete seen)
        (let ((ev (flow-perform
                   (apply flow-choice
                          (flow-wrap (flow-get pages) (lambda (p) (cons 'page p)))
                          (flow-wrap (flow-get exits) (lambda (x) (cons 'exit x)))
                          (if deadline
                              (list (flow-wrap (flow-timeout (seconds-until deadline))
                                               (lambda (_) '(deadline))))
                              '())))))
          (case (car ev)
            ((page) (loop live (cons (cdr ev) seen)))
            ((exit) (loop (- live 1) seen))
            (else (values (cons 'partial live) seen)))))))

(define (search key combos)
  (let ((pages (make-flow-channel 'pages))
        (exits (make-flow-channel 'exits)))
    (for-each (lambda (combo)
                (flow-spawn
                 (lambda ()
                   (flow-put! exits
                              (guard (ex (#t (list 'failed combo ex)))
                                (fetch-pages combo pages)   ; streams onto PAGES
                                (list 'done combo))))))
              combos)
    (let-values (((state seen) (gather pages exits (length combos) '()
                                       (deadline-in 0.050))))
      (if (eq? state 'complete)
          (begin (cache-complete! key seen) (rank-full seen))
          (begin
            ;; the producers never learn their reader changed
            (flow-spawn
             (lambda ()
               (let-values (((_ all) (gather pages exits (cdr state) seen #f)))
                 (cache-complete! key all))))
            (rank-approx seen))))))
```

A `flow-timeout` arms when it is performed, so the remaining time is
recomputed for every perform rather than reusing one event. Nothing
here is cancelled: past the deadline the request stops *waiting*, not
the work. Run by `~check-flow2-012/fan-out-gather-until-a-deadline-then-hand-off`.

### Stop a fan-out

There is no cancellation, so a fiber that should be stoppable says
where — it puts a stop latch in its own choices — and reports that it
stopped like any other end:

```scheme
(define stop (make-flow-latch))

(flow-spawn
 (lambda ()
   (let loop ()
     (case (flow-perform
            (flow-choice (flow-wrap (flow-latch-wait stop) (lambda (_) 'stop))
                         (flow-wrap (flow-get work) (lambda (job) (do-job job) 'more))))
       ((stop) (flow-put! exits 'stopped))
       (else (loop))))))

;; later, from any fiber or a compute thread
(flow-latch-fire! stop 'shutdown)
```

A fiber parked in an operation that does not include the latch — a
`flow-read` with no deadline, a put on a full channel nobody drains —
is not reached by it. That is the price of having no cancellation, and
the reason to race long waits against something. Run by
`~check-flow2-013/latch-as-a-stop-event`.

### Do I/O from a compute thread

The whole point of the verb-less design: the protocol below belongs
to the *application*, not to flow2. A task sends requests up a channel;
the submitting fiber interprets them and performs the ring I/O; results
come back on a downlink channel.

```scheme
;; --- main thread: submit, then serve the task's protocol ---
(define (run-indexing worker filepath)
  (define up (make-flow-channel))     ; task -> main
  (define down (make-flow-channel))   ; main -> task
  (flow-submit! worker
                (lambda ()
                  ;; the task reports its own failure; flow2 will not
                  (guard (ex (#t (flow-put! up `(raised ,ex))))
                    (index-file down up filepath))))
  (let loop ()
    (let ((msg (flow-get! up)))
      (case (car msg)
        ((read-at)                              ; (read-at path offset size)
         (flow-spawn                            ; concurrent, not serial:
          (lambda ()                            ; N read-ats overlap on the ring
            (flow-put! down (apply do-read-at (cdr msg)))))
         (loop))
        ((done) (cadr msg))
        ((failed) (error 'run-indexing "read failed" (cadr msg)))
        ((raised) (raise (cadr msg)))))))

;; --- compute thread: pure compute, I/O by message ---
(define (index-file down up filepath)
  (let loop ((offset 0) (index empty-index))
    (flow-put! up `(read-at ,filepath ,offset 65536))
    (let ((chunk (flow-get! down)))             ; parks the OS thread
      (cond
       ((bytevector? chunk)
        (loop (+ offset 65536) (index-chunk index chunk)))
       ;; #t is a clean EOF and #f is a failure -- the three-way result
       ;; of flow-read-at, not a truth test. `(if chunk ...)` here loops
       ;; forever on EOF, feeding #t to index-chunk, and reports a
       ;; failure as a normal `done` carrying a truncated index.
       ((eq? chunk #t) (flow-put! up `(done ,index)))
       (else (flow-put! up `(failed ,offset)))))))
```

The main-side handler *spawns a fiber per request*, so a task that
sends several requests before collecting gets genuinely overlapping
I/O — the serial version of this exact pattern measured 2× slower on
cold queries, which is why the protocol is left in user hands where it
can be pipelined. Run by `checks/repro-flow2-fourth-pass.scm`,
`readme-index-file-example-terminates`.

### Route uncaught errors

```scheme
(define failures (make-flow-latch))

(flow-log-start! 0.1
  (lambda (entries)
    (for-each (lambda (entry)
                (let ((sexp (cdr entry)))
                  (when (and (pair? sexp) (eq? 'flow2 (car sexp))
                             (pair? (cdr sexp))
                             (eq? 'uncaught (cadr sexp)))
                    (report! sexp)
                    (flow-latch-fire! failures sexp))))
              entries)))
```

The policy for an error nobody handled lives here, at the logger, not
in the library: print it, count it, page someone, or fire a latch a
supervising fiber waits on and let *it* decide whether to stop the
run. A procedure sink runs on the loop, so it could call `flow-stop`
itself; firing a latch keeps the decision with a fiber that knows what
is still in flight. Until 2026-10-28 the sink ran on the flush thread,
which flow2 refuses like any thread it does not own, and this page's
`flow-latch-fire!` raised `wrong-thread` and stopped the logger on the
first uncaught error — while the check named here never fired a latch.
Run as printed by `~check-flow2-000/a-procedure-sink-runs-on-the-loop`.

## References

- John Reppy, *Concurrent Programming in ML*, Cambridge University
  Press, 1999 — the event algebra (`wrap`, `guard`, `choose`,
  `sync`).
- Andy Wingo, *Lightweight concurrency in Guile with fibers*, and the
  guile-fibers manual — CML operations over an epoll scheduler in
  Scheme.
- Nathaniel J. Smith, *Notes on structured concurrency, or: Go
  statement considered harmful*, 2018 — nurseries, first-error
  cancellation, timeouts as scopes; the design flow2 had, and removed.
- Pieter Hintjens, *ØMQ - The Guide* — the ventilator / worker / sink
  pipeline, and deadlines owned by the gatherer.
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
