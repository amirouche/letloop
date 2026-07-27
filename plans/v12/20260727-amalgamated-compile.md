# `letloop compile` amalgamates — what it took

2026-07-27

Follow-up to `20260726-shipping-and-compilation-strategy.md`, which
measured the ~10% available from whole-program compilation, could not
explain why it evaporated when packaged into a binary, and left the
shipping question open. Both are answered here, and the thing is
committed.

## The three facts that explain the old result

All verified in a scratch Chez, not reasoned about.

**1. A boot-image library shadows its own source.** With a boot file
defining `(t a)`/`(t b)` registered, `compile-program` on a program that
imports them does *not* recompile them from source — no `.wpo` is
written. In a pristine process it does. This is the same effect as the
long-known "edits to `src/` are invisible until `make letloop`
rebuilds".

**2. `compile-whole-program` degrades silently.** With those libraries in
the boot image and their `.wpo` files deleted, it raised nothing and
returned `((t b) (t a))`. The return value is *the libraries it could not
fold, which must still exist at run time*. Pristine, with sources on the
path, it returned `()`.

So the earlier prototype folded the user's libraries and left the whole
letloop hot path — `http server` → `picohttpparser` → `liburing low` —
as separate boot-image units. `letloop compile` runs inside the letloop
binary, where every `(letloop ...)` library is already defined. That is
the 202k.

**3. A `.wpo` is tied to the optimize level it was compiled at.** This
one was not in the earlier document and cost a full measurement round.
Folding libraries out of a level 0 cache into a level 3 program measured
**401k req/s**, against **456k** for the same program folded out of a
level 3 cache — i.e. the entire benefit, silently forfeited, with
`compile-whole-program` still returning `()`. The object cache is
therefore keyed by optimize level.

## What was built

`letloop compile` amalgamates by default. `build-boot-file/whole-program`
in `src/letloop/base.scm` writes an import-first R6RS top-level program
and a build script, then re-execs letloop itself with an empty library
environment:

```
<exe> -b <boot>/petite.boot -b <boot>/scheme.boot --quiet --script <tmp>/build.scm
```

The child does `compile-program`, then `compile-whole-program ... #f`,
and **treats a non-empty return value as fatal** — the check whose
absence produced the 202k. Then `make-boot-file`, and the parent embeds
petite + scheme + program into `letloop-program.c` and runs `cc`. The
`letloop_boot` slot is left empty for an amalgamated program, so
`letloop-program.c` now guards that registration.

`--visible-libraries` keeps the old path: separately compiled libraries,
importable at run time. It is required by a program that resolves a
library name at run time with `environment` or `eval`, and by `--boot`.

## Shipping

letloop ships the way Chez itself does — the `scheme` executable
hardlinked under another name, which makes it load the boot file that
goes by that name. `make letloop` produces `letloop.boot` via
`--visible-libraries --boot=letloop.boot` and installs:

```
$PREFIX/lib/csv<version>/<machine>/letloop{,.boot}
$PREFIX/bin/letloop                             -> relative symlink
$PREFIX/lib/letloop/src/letloop/**.scm          shipped sources
$PREFIX/lib/letloop/obj/<level>/**.{so,wpo}     per-level object cache
```

This is what makes the pristine child free: the shipped executable
accepts `-b`. It also drops a multi-megabyte `-O0` C compile from the
self-build, and standalone user binaries still need no Chez installed —
`kernel.o` and `scheme.h` were always bytevector literals inside
`(letloop base)`, so they ride along in `letloop.boot`.

The symlink must stay **relative**: `scheme-binarypath*` locates the boot
directory through `dirname($SCHEME) + "/" + readlink($SCHEME)`.

## Measured

Same machine, back to back, `taskset -c 0`, bench.sh methodology.

| build | c=16 | c=32 |
|---|---|---|
| old `letloop compile`, separate libraries | 401,819 | 408,408 |
| level 0 cache folded into a level 3 program | 401,547 | 412,972 |
| `./src` passed, compiled fresh at level 3 | 456,060 | 463,401 |
| **shipped level 3 cache, no `./src`** | **456,958** | **464,239** |

The 2026-07-27 09:36 hand-built reference was 446,244 / 452,542.

### Startup, which turns out to be the larger effect

A `fib` library importing nothing but `(chezscheme)`, 200 runs per figure,
two passes agreeing to within 0.7 ms:

| build | startup | vs the Chez floor |
|---|---|---|
| bare `scheme`, empty script | 32.77 ms | — |
| amalgamated `a.out` | 33.27 ms | **+0.5 ms** |
| amalgamated boot file + scheme copy | 32.52 / 32.89 ms | +0 ms |
| module monolith boot file | 32.81 / 32.48 ms | +0 ms |
| `--visible-libraries` `a.out` | 69.43 ms | **+36.7 ms** |
| `letloop` itself | 69.60 ms | +36.8 ms |

An amalgamated program starts at the floor. A separately-compiled one
pays 37 ms loading and invoking `letloop.boot`'s 74 libraries **even
though `fib` imports none of them** — 2.1x, far more than the ~14% on
throughput, and the figure that matters for anything CLI-shaped.

Reading the boot files off disk costs nothing against carrying them as C
arrays, so `--boot` is a real option rather than a compromise.

This also prices letloop's own CLI latency: the 70 ms is that same tax.
`letloop compile` never imports those libraries — `base.scm` pulls in
`(letloop http server)` only for `http serve` — so resolving those few
imports lazily through `environment` would let letloop itself be
amalgamated and start in ~33 ms, loading the library boot only for
`check`, `exec`, `repl` and `serve`. Not attempted here.

## Not done: the module monolith, settled by measurement

**Rewriting `src/letloop` as one compilation unit** built from nested Chez
`module` forms, merging user code into it at compile time. Prototyped for
real — a 150-line generator that reads every `library` form, rewrites each
into a `module`, orders them dependency-first and emits one top-level
program. It compiles and serves.

Interleaved A/B against the committed whole-program build, same machine
state, `taskset -c 0`, bench.sh methodology:

| conns | whole-program | monolith | delta |
|---|---|---|---|
| 16 | 432,137 / 439,208 | 439,723 / 441,151 | +1.8% / +0.4% |
| 32 | 427,068 / 438,033 | 441,370 / 447,281 | +3.3% / +2.1% |
| 64 | 445,205 / 442,181 | 442,983 / 444,602 | -0.5% / +0.5% |
| mean | 437,306 | 442,852 | **+1.3%** |

**+1.3%, under a noise floor of 2.6%** — the same binary varied
427,068 → 438,033 at c=32. This reproduces the March table (224k monolith
vs 221k amalgamated, +1.4%) closely enough to trust both. On startup it
is worth nothing at all: 32.81/32.48 ms against 32.52/32.89 ms for the
amalgamated boot file, both at the Chez floor.

Note that the whole program was merged, not part of it: all 16 libraries
the counter app imports, plus the handler and server, 18 modules in one
compilation unit. Merging the other 58 libraries could only add code that
never runs, so there is no further throughput to find this way.

Two earlier objections to this design were wrong and should not be
repeated: build time is *not* a cost (all 74 libraries compile at
optimize-level 3 in **2.07s**, the hot-path subset in 1.8s including
`cc`), and the public import surface need *not* break, because the merge
is a build-time transformation — user source keeps `(import (letloop
http server))` and the rewriter maps names.

What it does cost is a compiler pass to maintain. Three fidelity bugs
turned up in an afternoon, on 16 of the 74 libraries, each fatal to the
compile:

- **Body-level `import` forms.** `letloop/json.scm` keeps two
  dependencies in its body rather than the header clause, which Chez
  allows. They have to be rewritten *and* counted as graph edges.
- **A module must be defined before it is imported**, where Chez resolves
  libraries in any order. The merge needs a real topological sort, and a
  dependency cycle between libraries becomes unrepresentable.
- **A `module` export list rejects `(rename ...)`**, which `(letloop www)`
  uses. Chez's `alias` covers it — it binds macros and record names too,
  verified — but every renamed export needs one synthesized.

The 58 libraries left alone include the `define-ftype` ones and
`base.scm`'s `meta define`, where phase differences would surface.
`compile-whole-program` is Chez's supported mechanism for the same
result. The prototype is not committed.

## Traps worth keeping

- `guard` around a compile catches Chez's **continuable warnings** and
  unwinds, writing off a library that merely warns. That silently kept
  `(letloop aql eavt)` out of the boot image. Warnings now go back to the
  default handler via `raise-continuable`; only serious conditions escape.
- `/proc/self/exe` **cannot be read with a subprocess** — it resolves
  against whichever process reads it, so `readlink /proc/self/exe` in a
  child dutifully reports the child. It is read with a foreign call now.
- The distro's **liburing-ffi 2.11** against the 2.14 the makefile builds
  makes the server accept connections and answer nothing — a plausible
  0.00 req/s rather than an error. `bench.sh` now sets `LD_LIBRARY_PATH`
  for the Scheme server itself instead of inheriting it.
