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

**Statically-linked musl builds of `letloop` crashed on almost any real
operation, via a NULL-unsafe path in ChezScheme's own C runtime —
root-caused and fixed 2026-08-23.** Skip to point 9 for the fix and its
verification if you don't need the investigation trail.

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

9. **Implemented, with one real surprise along the way.** An audit of
   every `foreign-procedure`/`foreign-entry` call reachable from
   `letloop store build`'s actual dependency chain (`root.scm`, and
   `tls/base.scm` for the fixed-output fetch step's HTTPS client) found
   more than the two symbols prototyped above: `strerror`, `mkdtemp`,
   `readlink`, `unsetenv`, `execve`, plus `getaddrinfo`, `freeaddrinfo`,
   `socket`, `connect`, `setsockopt`, `close` for TLS.

   Converting every call site to try-then-fall-back individually was
   tried first and **broke the ordinary dynamic build**: most files
   (`tls/base.scm` among them) do a *bare* `foreign-procedure` call with
   no `load-shared-object` of their own, silently riding on some *other*
   file's eager, unconditional `(load-shared-object #f)` as a
   process-wide side effect. Converting the handful of files that
   originally made that eager call into "only call it if this specific
   symbol isn't already registered" meant that call was never reached
   at all once `Sforeign_symbol` covered their own narrow needs —
   silently pulling the rug out from every *other* file's bare lookup,
   even on glibc. `make check` across the whole tree went from
   498/498 to a dead stop on the first unrelated symbol it hit
   (`getaddrinfo`, then `bind`, ...).

   The actual fix: probe once, safely, in C, before any Scheme runs.
   `letloop-main.c`'s `CUSTOM_INIT` hook calls `dlopen(NULL, RTLD_LAZY)`
   itself (plain C, nothing Chez-level that could crash), and exposes
   the result via an always-registered `letloop_self_dlopen_safe()`
   (`Sforeign_symbol`, independent of `dlopen`). `cffi.scm`'s
   `ensure-self-loaded!` (duplicated inline in `base.scm`, which
   imports nothing from letloop on purpose) checks that flag once and
   calls `(load-shared-object #f)` — exactly as every version of this
   codebase always has — only when it is actually safe. Not found at
   all (a plain `scheme`/`petite` with no letloop-main.c registration,
   e.g. the child process `letloop compile` spawns to do the real
   compilation) is treated as safe too, correctly, since that process
   is never statically linked. This preserves the dynamic build's
   behavior byte for byte and skips the crash exactly where it would
   happen.

   One more real bug surfaced fixing this: registering `"environ"` via
   `Sforeign_symbol("environ", (void*)&environ)` — needed for
   `execve!`'s raw `execve(2)` wrapper — broke
   `environment-variables` (`environment.scm`) on the *ordinary dynamic
   build* with the same "invalid memory reference" crash, reproducibly,
   confirmed by disabling just that one registration. Not fully
   root-caused (a suspected ELF data-symbol aliasing issue between this
   registration's `&environ` and a later `dlsym(handle, "environ")` on
   a separately dlopen'd `libc.so.6` — plausible but unconfirmed).
   Dropped from the registration table rather than chased further: it
   isn't needed for `letloop store build` anyway (`sandbox-build!`
   shells out to `/usr/bin/bwrap` directly, never touching
   `root.scm`'s `execve!`) — only the interactive `letloop root exec`
   uses it, which remains unsupported under a static build until this
   is understood properly.

**Fixed and verified end to end**, against the same static Alpine 3.22
toolchain used throughout this investigation:
- `make letloop`'s host link now passes `-static` when the compiler's
  target triple contains `musl` (`cc -dumpmachine`), leaving glibc
  builds untouched — confirmed via host rebuild, `make check` 498/498
  green both before and after, on both glibc and the Alpine static
  build.
- `letloop root exec /alpine-rootfs / -- letloop compile hello.scm main`
  — the exact operation that used to crash — now runs cleanly inside
  the static Alpine sandbox and produces a static `a.out`.
- The full `letloop store build store-static-hello.derivation.scm`
  pipeline (not just the manual steps above) ran end to end and
  produced a statically linked `hello` binary in the store.
- **Relocatability, the actual goal**: that binary was copied out of
  the store to this session's Ubuntu/glibc host and run directly —
  `hello, letloop store`, exit 0 — with zero dependency on the Alpine
  sandbox, the store layout, or a musl runtime being present. Built on
  musl, runs on glibc, no shared loader involved at all.

The dead `-luuid` flag (point 2) stays removed on both platforms. The
`(cs)load_shared_object` NULL-format bug in ChezScheme itself (point 7)
is unpatched and technically still there, but no longer reachable: this
codebase never calls `(load-shared-object #f)` in the one context where
it would hit it. `environ`/`execve!`/interactive `letloop root exec`
under static linking remains a named, deliberate gap (see point 9)
rather than a silently accepted one.
