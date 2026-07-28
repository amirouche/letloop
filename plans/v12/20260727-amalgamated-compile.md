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

### letloop's own startup: 69.6 ms → 35.06 ms

Done, since the 37 ms was letloop's own tax too. `(letloop base)` now
imports nothing from letloop and resolves `cli-read`, `transparent`,
`letloop-root` and `letloop-review` at first use, against the sources
installed at `$PREFIX/lib/letloop`. letloop.boot is amalgamated and holds
the CLI alone: 678 KB against 2.8 MB, starting 2 ms above the bare Chez
floor of 33.04 ms.

Both reasons this had to be a lazy *resolution* rather than a smaller boot
image are load-bearing:

- **A folded library's name stays occupied.** Verified: with `(t b)`
  folded into a program, `(environment '(t b))` fails with "attempt to
  import invisible library" *even with its source on the library path*,
  while a never-folded `(t c)` loads from source fine. So anything
  `(letloop base)` imports becomes unimportable for user programs —
  `(letloop match)` and `(letloop http server)`, which the benchmark
  handler and server both import, would have broken.
- **Baking a smaller subgraph would not have helped.** Loading a compiled
  library invokes its imports, so the cost is paid at startup whatever
  the boot image holds. Only importing nothing avoids it.

The `(letloop match)` dependency was removed by rewriting four library
shape tests as plain list code. Every subcommand that replaces
`library-directories` calls `letloop-library-path!` afterwards, or
letloop's own libraries drop off the path mid-run.

Two consequences worth knowing:

- `(letloop base)` is itself folded, so `letloop check ./src/` skips
  `src/letloop/base.scm`. It exports no `~check-*`, so no test is lost.
- `bin/letloop` being the `scheme` binary, Chez's C `main` intercepts
  `--help`, `--version`, `-b`, `--boot` and `--verbose` before any Scheme
  runs, so `letloop --help` prints Chez's usage rather than letloop's.
  That is a regression against the old C-hosted binary, which passed
  everything through to `letloop-main`. It is also why the flag is
  `--boot=PATH` and not `--boot PATH`.

  **Fixed since, and it was worse than written here.** The list is 17
  tokens, not five -- `--optimize-level` and `--libdirs` are among them,
  and `--optimize-level` is a name letloop documents itself. Worse,
  interception is *positional*: `letloop check --version` printed Chez's
  version, because Chez's parser does not stop at the first non-option.
  `--` ends that parsing and hands the rest to `scheme-start` untouched,
  so `bin/letloop` is now a generated `sh` wrapper that inserts one.
  Measured free: 31.9 ms against a 32.0 ms direct-exec floor, but only
  because it uses `${0%/*}` -- the obvious `readlink -f` plus `dirname`
  spelling costs two forks and measured 3.4 ms.

  The wrapper must be written via `rm -f` or a temp file and `mv`.
  `$BOOT/letloop` is a hardlink to the `scheme` binary and the old
  `$PREFIX/bin/letloop` was a symlink to it, so a plain `>` redirect
  follows the symlink and truncates the shared inode -- taking `scheme`,
  `petite` and `scheme-script` with it, since all four are one inode.
  Restoring it means copying `local/src/chezscheme/ta6le/bin/ta6le/scheme`
  back and re-making the three hardlinks; no rebuild needed.

  Scope: only `bin/letloop`. `letloop compile` links
  `src/letloop-program.c`, whose `main` calls `Sscheme_start(argc, argv)`
  directly, so compiled programs never meet Chez's parser. A
  `--boot=PATH` artifact does, being run by a renamed `scheme`.

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

## Not done: a flagless scheme binary, and the two shipping shapes

**Forking Chez's `c/main.c`** so the binary does no option parsing at
all, leaving the wrapper unnecessary and fixing every renamed-scheme
program rather than just `bin/letloop`. Not obviously wrong: `main.c:114`
already branches on `path_last(execpath)` to special-case
`scheme-script`, so keying behaviour off argv[0] is an upstream idiom,
and letloop already builds its own Chez from a pinned `CHEZ_REF`, so a
build-time patch costs less than it would elsewhere.

It was dropped because **the compiler depends on the flags it would
remove**. `base.scm:1037` spawns the child as `<exe> -b petite.boot -b
scheme.boot --quiet --script build.scm`, where `exe` is `/proc/self/exe`.
That child is the whole mechanism behind amalgamation -- a library
already defined in-process is never recompiled and writes no `.wpo` --
so a flagless letloop cannot build one. This failure mode is already
known and fenced: `base.scm:989` refuses whole-program compilation when
`(foreign-entry? "petite-boot")` succeeds, because "its main registers
them and ignores `-b`, so it cannot give the child an empty library
environment". A forked flagless `main` is that same shape again.

It is repairable -- point the child at the sibling `$BOOT/scheme`, which
keeps its flags, and arguably should anyway since it wants a bare Chez --
but the wrapper already measured free, so the only thing left to buy is
working CLIs for `--boot` artifacts, and a wrapper emitted beside the
boot file would buy that without a fork to rebase.

**The two shapes start at the same speed.** `letloop compile` (C-hosted
`a.out`) against `--boot=PATH` plus a renamed scheme binary, same
program, interleaved, `taskset -c 0`, 60 runs per round:

| | trivial | library-importing |
|---|---|---|
| `a.out` | 26.24-26.70 ms | 26.12-26.73 ms |
| `--boot` | 26.32-26.52 ms | 26.20-26.50 ms |
| delta | +85, +77, +30, -178, +280 us | +132, -143, -452, +84, +15 us |

The sign flips in both, three negative rounds out of ten, against a
~450us per-round spread. There is no resolvable difference, which is
what the mechanism predicts: both register the same `petite.boot` and
`scheme.boot` and build the same heap, one from the data segment and one
from the page cache, and that heap construction dominates. The program's
own image is rounding error -- 1,970 bytes for the trivial case, 3,280
for the other. Total bytes shipped are a wash too: one 4.4 MB file
against four totalling ~4.5 MB.

So choose between them on shipping shape, not speed: `a.out` is
self-contained but needs `cc` at build time; `--boot` needs no C
compiler but ships four files that must stay together, and inherits
Chez's argv parsing.

## Traps worth keeping

- **`let` does not sequence its initializers, and instrumentation notices.**
  `(letloop tea terminfo)`'s `read-u16le` was
  `(let ((lo (get-u8 p)) (hi (get-u8 p))) ...)`: two side-effecting reads
  in one `let`, whose evaluation order Scheme leaves unspecified. Chez
  picked the order the code wanted, until `(compile-profile 'source)`
  picked the other one and byte-swapped every 16-bit field in the file.
  It presented as a terminal with no capabilities rather than as an
  error, because `build-cap-set` takes the name from its argument rather
  than from the parse, so `~check-terminfo-load-xterm` kept passing while
  the two content checks failed. Now `let*`.

  Worth knowing how it surfaced: making `(letloop base)` import nothing
  meant `(letloop tea terminfo)` was no longer pulled in transitively via
  `(letloop review)` → `(letloop termbox)` *before* `letloop-check` turns
  profiling on. It had been compiled uninstrumented by luck of import
  order. Any check that only passes because of when its library happens
  to be compiled is worth a second look.

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
