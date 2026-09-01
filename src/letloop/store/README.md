# `(import (letloop store))`

`letloop store build DERIVATION.scm` reads a single derivation (an
S-expression: a build-environment rootfs, optional fixed-output
fetches, a build script, a declared output), runs the script inside a
network-off `bwrap` sandbox, hashes the result with BLAKE3, and places
it in a content-addressed store at `$LETLOOP_STORE/<hash>-<name>`,
deduping against an existing path with the same hash. See
`src/letloop/store/derivation.body.scm` for the exact format and
`src/letloop/store/sandbox.body.scm` for the sandbox invocation.

This is a v1 walking skeleton: one derivation per build, no dependency
graph, no substituter, no GC over the store. Non-goals and the full
design are in the session's implementation plan, not duplicated here.

## Issues

**Statically-linked musl builds of `letloop` crash on almost any real
operation, via a bug in ChezScheme's own C runtime — open, unresolved
as of 2026-08-23.**

The original motivation for this subsystem includes shipping
relocatable binaries: a `letloop store build` output should run when
copied to an arbitrary host, not just inside its own build sandbox.
Static linking is the mechanism for that (no ELF interpreter
dependency at all, unlike dynamic linking, which hardcodes a specific
loader path — `/lib/ld-musl-x86_64.so.1` for a musl build,
`/lib64/ld-linux-x86-64.so.2` for glibc — and simply cannot run on a
host lacking a compatible one).

Building `letloop`'s own host (`src/letloop-main.c`) with `-static` on
Alpine surfaced this chain of findings, each confirmed empirically
against a real Alpine 3.22 container (`bwrap`-sandboxed, via `letloop
root`):

1. Alpine's `util-linux-dev` ships only `libuuid.so`, no static `.a`
   archive, and no compatible static alternative exists in Alpine's
   repositories (`ossp-uuid-static` is a different, incompatible API).
   `-luuid` blocked static linking outright.
2. `-luuid` turned out to be dead weight: `grep uuid src/letloop-main.c`
   has zero hits, and `nm -u` on Chez's own `kernel.o` shows zero
   undefined uuid symbols. It has been in the makefile's link line
   since the commit that introduced letloop's own C host, apparently
   never actually needed. Removed — confirmed harmless on both glibc
   (host rebuild, `make check` still 498/498 green) and musl.
3. With `-luuid` gone, `-static` links cleanly and produces a genuine
   static ELF. But running it — anything beyond a no-FFI command like
   `letloop version` — crashes:
   ```
   Exception: invalid memory reference.  Some debugging context lost
   ```
   `letloop version` needs no FFI (pure static strings) and always
   works. `letloop compile`, `letloop exec`, and therefore `letloop
   store build` (which calls `compile` inside its sandbox) all crash,
   because `letloop-compile`'s `make-temporary-directory` calls
   `(foreign-procedure "mkdtemp" ...)`, and *every* `foreign-procedure`
   in this codebase resolves through `(load-shared-object #f)` — the
   `dlopen(NULL, ...)` idiom used throughout `cffi.scm`, `root.scm`,
   `base.scm` to get a handle on already-linked libc symbols.
4. `strace -f` on the crash shows it happening in the *parent* process
   (not the forked child, which exits cleanly with status 0), right as
   `system(3)`'s signal-handler restoration runs after `wait4()`
   returns: `SIGSEGV`, `si_code=SEGV_MAPERR`, `si_addr=NULL`.
5. `gdb` pinpoints the exact crash site:
   ```
   #0 strlen (s=0x0)                         src/string/strlen.c
   #1 Sstring_utf8 ()
   #2 load_shared_object ()
   #3-7 S_call_help / boot_call / Sscheme_start / main
   ```
   `load_shared_object` is ChezScheme's own generic C runtime function
   backing *every* Scheme-level `(load-shared-object ...)` call — this
   is not letloop-specific code, it is Chez's own kernel. It calls
   `Sstring_utf8` on a name string without a NULL check;
   `dlopen(NULL, ...)` on a statically-linked musl binary hands back a
   handle whose name field is NULL (there is no dynamic linker in the
   picture at all for a static binary — musl's static-dlopen support
   does not give `dlopen(NULL, ...)` a real name to report), and Chez
   crashes dereferencing it.
6. Four linker-flag combinations were tried against the exact same
   build, all crashing identically at the same instruction: `-static`,
   `-static-pie` (musl supports position-independent static
   executables natively — ruled out "fixed load address confuses
   Chez's GC/segment allocator" as the cause, since `-static-pie`
   crashes the same way), `-static -rdynamic`, and
   `-static-pie -rdynamic` (`-rdynamic` exports the executable's own
   symbol table, in case musl's static-dlopen needed it to resolve the
   self-handle — no effect).

7. Reading ChezScheme's own `c/foreign.c` (source available locally
   under the build tree once `make chezscheme` has run) pins the exact
   mechanism: `load_shared_object`'s error path calls
   `Sstring_utf8(path, -1)` to format `dlerror()`'s message — but only
   reaches that branch when `dlopen(path, RTLD_NOW)` itself returns
   NULL. And it does: `dlopen(NULL, ...)` — "hand me the main
   program's own handle" — has nothing to service it in a fully static
   binary (no dynamic linker in the picture at all), so it fails, and
   `path` at that point *is* NULL (that is literally what `#f` becomes
   in C), so the error-formatting call itself crashes. A NULL check
   there would only turn the crash into a clean failure — `(load-shared-
   object #f)` still could not work under static musl, on principle,
   not just as an unhandled edge case.
8. **Prototyped a working fix**, independent of `dlopen` entirely.
   `S_foreign_entry`'s lookup (`foreign.c`) and plain
   `(foreign-procedure "name" ...)` both search `S_G.foreign_static`, a
   table populated not by `dlopen` but by `Sforeign_symbol(name, addr)`
   — a public, documented Chez embedding API (`scheme.h`,
   `EXPORT void Sforeign_symbol(const char *, void *);`), meant
   exactly for this: `main.c` has a `CUSTOM_INIT` hook
   (`Sbuild_heap(execpath, CUSTOM_INIT)`) documented as "perform
   boot-time initialization, e.g., registering foreign symbols."
   Compiled a throwaway static host (`#define CUSTOM_INIT
   my_init` before `#include "main.c"`, `my_init` calling
   `Sforeign_symbol("getpid", (void*)getpid)` and
   `Sforeign_symbol("mkdtemp", (void*)mkdtemp)`) against the same
   static Alpine toolchain. Result: `((foreign-procedure "getpid" ()
   int))` returned a real pid, and `(mkdtemp "/tmp/proto-XXXXXX")`
   returned a real created directory — both with **zero**
   `load-shared-object` calls anywhere. This is the exact function
   (`mkdtemp`) that crashes today via `make-temporary-directory`.

**Conclusion**: this is not a letloop build-flag problem, and not
purely a ChezScheme bug either — `dlopen(NULL, ...)` genuinely cannot
work under static linking, by design, regardless of any NULL-check
patch. But there is a real, scoped, working fix, needing no patch to
vendored ChezScheme:
- add a `CUSTOM_INIT` hook to `src/letloop-main.c` that calls
  `Sforeign_symbol()` for the handful of libc functions this codebase
  currently obtains via `(load-shared-object #f)` (`mkdtemp`,
  `strerror`, `unsetenv`, `environ`, and whatever else `cffi.scm`/
  `root.scm`/`base.scm` resolve that way — needs an audit, not just
  the two proven here);
- and remove those `(load-shared-object #f)` calls from the Scheme
  side, since calling it *at all* is what crashes — `foreign-procedure`
  itself needs no change, it already searches the table `Sforeign_symbol`
  populates regardless of whether `load-shared-object` was ever called.
- optional/named `.so` loads (`libtls.so`, `libblake3.so`, ...) are a
  separate question — real `dlopen("path", ...)` (not `dlopen(NULL,
  ...)`) was not tested here and may or may not have the same problem
  under static musl; worth checking before assuming it's fine.

Not yet implemented — this needs an audit of every `foreign-procedure`
call in the codebase to enumerate exactly which symbols need
registering, then the `CUSTOM_INIT` hook and the corresponding
Scheme-side cleanup, then re-verifying against the real `letloop store
build` pipeline end to end. Until it lands, `make letloop`'s host link
has no `-static`/`-luuid` special case (reverted to plain dynamic
linking, `-ldl -lm -lpthread`), and a musl/Alpine build of `letloop` is
relocatable only to other musl-compatible hosts, not to arbitrary
glibc systems — the original "ship relocatable binaries" goal is not
yet met, but the path to it is now concrete rather than open-ended.
