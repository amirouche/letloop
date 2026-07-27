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

## Not done, and why

**Rewriting `src/letloop` as one giant `(letloop)` library** built from
nested Chez `module` forms, merging user code into it at compile time.
The mechanism works — nested modules isolate private bindings, support
cross-module import, and carry macros across module boundaries, all
checked. But the March monolith measured 224k against 221k for
amalgamated: the two are the same number, and the amalgamated build is
now at it. Against ~1.4% of headroom it would cost the public import
surface (`(import (letloop match))` stops resolving, across all 108
files under `src/` plus every example), a source-to-source R6RS→module
rewriter for arbitrary user libraries, error locations pointing into a
generated file instead of user source, and a full recompile of letloop
on every user build since the compilation unit changes with the user's
code. `compile-whole-program` is Chez's supported mechanism for exactly
this.

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
