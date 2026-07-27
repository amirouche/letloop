# Shipping and compilation strategy — whole-program optimization

2026-07-26

> **Superseded 2026-07-27** by `20260727-amalgamated-compile.md`. The
> unexplained result below — 202k as `a.out` against 221k for the same
> code as a `.so` — is explained there: a boot-image library shadows its
> own source, so no `.wpo` is written for it, and `compile-whole-program`
> reports what it could not fold only through its return value. The
> shipping question is settled and `letloop compile` amalgamates by
> default. One finding here needs qualifying: `optimize-level` is *not*
> irrelevant to amalgamation — a `.wpo` compiled at level 0 folded into a
> level 3 program forfeits the entire benefit.

Findings from chasing an HTTP server throughput regression. The
performance work itself is done and committed; this document records
the one lever that is **not** done, because it needs a decision about
how letloop ships rather than a patch.

## What `letloop compile` does today

`letloop-compile` (`src/letloop/base.scm`) sets:

```scheme
(generate-wpo-files #t)
(compile-imported-libraries #f)
```

…then compiles each discovered library, compiles the generated
`program.scm` with `compile-file`, and builds the boot image from the
resulting **`.so`** files:

```scheme
(apply make-boot-file program.boot (list "scheme" "petite")
       (append (map .so (map cdr sorted-discovered))
               (list (.so program.scm))))
```

So `.wpo` files are *generated and then discarded*. `compile-whole-program`
is never called. Every library is a separate compilation unit, and every
cross-library call is opaque to the optimizer.

That matters because a single HTTP request crosses four libraries:

```
bench-handler → (letloop http server) → (letloop picohttpparser)
                                      → (letloop liburing low)
                                      → (letloop http)
```

## Measured effect

Same source, same machine, back to back. `prog-whole.so` built with
`compile-program` + `compile-whole-program` at `optimize-level 3`:

| build | req/s |
|---|---|
| separate libraries (what `letloop compile` produces) | ~200,000 |
| **amalgamated (`compile-whole-program`)** | **221,133 / 221,072** |
| March monolith — one library by construction | ~224,000 |

Amalgamation accounts for essentially the whole difference between
letloop's split-library build and the old single-library monolith it
was extracted from. Roughly **+10%**, and it is not workload-specific:
it is the cost of every cross-library call on the hot path.

An important caveat about how this was found: an earlier test of the
exact same change measured **neutral**. At that point
`string->html-string` was allocating a cons cell and a one-character
string per character, and that dominated everything. Only once the
allocation bug was fixed did the inlining benefit become visible. The
same trap hid the `optimize-level` result. **Do not conclude a
compilation-strategy change is worthless until the obvious allocation
bugs are out of the way.**

## Why it is not simply switched on

Three real obstacles, all hit while attempting it.

### 1. `libs-visible?` is load-bearing, and `#t` defeats the point

`(compile-whole-program in out libs-visible?)`:

- `#f` — libraries are folded in and become invisible. This is what
  produces the speedup. Correct for a standalone binary, which never
  imports a library at runtime.
- `#t` — libraries stay importable, **and the optimization
  disappears**: measured 197k, i.e. the same as separate compilation.

letloop's *own* binary needs `#t`. `letloop compile`, `exec` and `repl`
resolve user libraries against the ones baked into the boot image, and
building letloop with `#f` fails at runtime with:

```
Exception in environment: attempt to import invisible library (letloop http server)
```

So this cannot be a blanket change to `letloop-compile`: the same code
path builds both letloop itself (needs visible libraries) and user
programs (want them folded away).

### 2. `compile-whole-program` needs a `.wpo` for every imported library

The libraries baked into the letloop binary ship as boot-image code
with no `.wpo` alongside. So a user running

```
letloop compile ./examples ./examples/app.scm main
```

cannot amalgamate `(letloop http server)` — the `.wpo` does not exist
on their machine. It only works when letloop's own `./src` is passed
as a source directory so those libraries are compiled from source as
part of the program.

Options, none free:

- ship `.wpo` files alongside the binary (they are large — `low.wpo`
  alone is 246 KB, and they must match the shipped sources exactly);
- ship sources and compile letloop's libraries into each user program
  (slow builds, and the sources must be installed);
- keep it opt-in and document that it requires the source tree.

### 3. `.wpo` files desync trivially

All `.wpo` inputs must come from one consistent compilation. Mixing
them produces:

```
Exception in compile-whole-program:
  ".../letloop/generator.wpo" does not define expected compilation
  instance of library (letloop generator)
```

This happened immediately when libraries were recompiled in a
different order/session. Any implementation needs to build the `.wpo`
set atomically, and `compile-imported-libraries` has to be `#t` during
that build (letloop currently sets `#f`).

### Also: `compile-whole-program` wants a real program

It rejects `compile-file` output:

```
Exception in compile-whole-program: expected program or library form,
  but encountered top-level expression (($primitive 2 suppress-greeting) #t)
```

The generated `program.scm` is a sequence of loose top-level
expressions. It has to be a genuine R6RS top-level program — `import`
first — compiled with `compile-program`, not `compile-file`. That part
is a small mechanical change and it works.

## Partial implementation, not committed

A `--whole-program` flag was prototyped: it emits an import-first
program, uses `compile-program`, then `compile-whole-program` with
`libs-visible? #f`, and builds the boot file from the single resulting
object.

It was **not committed**, because in `a.out` form it delivered
202k against 200k for the normal path — noise — while the identical
code as a standalone `.so` run under `scheme --program` reached 221k.
Something in the boot-image packaging gives the optimization back. That
is unexplained and is the first thing to investigate if this is picked
up. Committing the flag as a performance feature would have been
overclaiming.

## Non-findings worth recording

Each of these was tested by direct A/B measurement, not reasoning, and
each was **neutral**. They should not be re-litigated without new
evidence:

- **`optimize-level` 0 → 3 for letloop's own libraries.** `make letloop`
  compiles `src/letloop/**` at the default level 0 while user libraries
  get whatever `letloop compile` is passed. Raising it to 3 changed
  nothing (measured twice, including after the allocation fixes; the
  second run was marginally *slower*). Level 3 is Chez's unsafe mode —
  it drops bounds and type checks — so it currently trades safety for
  no measurable gain.
- **Garbage collection.** Built with `--disable-garbage-collector`, both
  the current server and the monolith were unchanged (196.5k → 196.9k,
  225k → 227k). Allocation pressure was not differential between them.

## Recommendation

Treat whole-program compilation as a **shipping** decision, not a
compiler flag. The ~10% is real and general, but collecting it requires
answering: does letloop ship `.wpo` files, ship sources, or neither?
Until that is settled, the fix with the better ratio is what this
session's commits already did — remove the per-request allocation and
the string round-trips, which needed no change to how letloop is built.
