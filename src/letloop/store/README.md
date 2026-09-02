# `(import (letloop store))`

`letloop store build DERIVATION.scm` reads a single derivation (an
S-expression: a build-environment rootfs, optional fixed-output
fetches, a build script, a declared output), runs the script inside a
network-off `bwrap` sandbox, hashes the result with BLAKE3, and places
it in a content-addressed store at `<store>/<name>-<hash>`,
deduping against an existing path with the same hash. See
`src/letloop/store/derivation.body.scm` for the exact format and
`src/letloop/store/sandbox.body.scm` for the sandbox invocation.

The store is `$LETLOOP_STORE` if set, else `$LETLOOP_PROJECT_PATH/store`,
else `~/.local/letloop/store`. `./venv` sets the middle one, so working
on letloop fills the checkout's own store rather than the one a user has
been accumulating packages in.

A package is an ordinary Scheme library exporting `package`, under
`src/letloop/package/`, so `letloop store build blake3` resolves
`(letloop package blake3)` wherever letloop's own libraries resolve —
which is what lets a package set ship inside a release. A derivation can
also name another with `(derivation "other.scm")`, as an
input or as its build-environment root; `store-build` resolves those
depth-first, guarding against reference cycles and memoising within
the call. A derivation with neither a `build-environment` nor a
`script` is fetch-only: its fetches land in the store directly, with
no rootfs and no sandbox involved.

Builds are cached on what determines them -- the derivation's own
bytes, its rootfs, and its resolved inputs -- so an unchanged
derivation is not rebuilt. Paths outside the store contribute their
content rather than their name, since a bind-mounted working tree can
change underneath a path that does not.

Still not here: a scheduler, parallelism, a substituter, or GC over
the store.

## The bootstrap chain

The packages under `src/letloop/package/`, driven by
`checks/letloop/bootstrap.sh`, build a statically linked, relocatable
letloop without Alpine or any other distribution. Each is
`letloop store build <name>`:

| package | what it is |
| --- | --- |
| `toolchain` | fetch-only: musl.cc's static native `x86_64-linux-musl` gcc + binutils + musl |
| `shell` | fetch-only: a static BusyBox binary |
| `rootfs` | assembles those two into a rootfs a build can run in |
| `make` | GNU make, from source, via its own `build.sh` |
| `busybox` | BusyBox, from source |
| `rootfs-final` | the rootfs downstream work uses: toolchain + the two above |
| `liburing`, `blake3` | from source, for the archives letloop links into its own host |
| `argon2`, `sodium`, `picohttpparser`, `oprf`, `opaque`, `tls` | from source, static archives for the rest of letloop's dlopen'ed FFI libraries -- not linked into the bootstrap letloop itself, for a `letloop compile` consumer to link |
| `chezscheme` | ChezScheme 10.4.1, from source |
| `letloop` | letloop itself, from source, against all of it |

**Exactly two prebuilt binaries are trusted**, both pinned by BLAKE3
with their provenance recorded in each package library's header. Trusting a
prebuilt compiler is Nix's bargain, taken deliberately: building a C
compiler needs a C compiler, and the alternative is Guix's hex0/mes
chain -- years of work that still bottoms out in trusting a seed
binary. The prebuilt BusyBox *is* retired: `bootstrap-busybox`
rebuilds it from source, and `bootstrap.sh` asserts the fetched
binary's bytes are not in the final rootfs.

One bounded exception remains, and it is structural rather than an
oversight: `sandbox-build!` runs `sh` inside whatever rootfs it is
given, so the build that produces the first rootfs-with-a-shell
cannot itself run in one. `bootstrap.sh` breaks that loop from outside
with a fixture of symlinks into the host's own `/usr` and `/bin` --
scaffolding for that one assembly step, which only unpacks and links
bytes from the two pinned inputs. Nothing is compiled there, so no
host header, library or compiler reaches the output.

Things worth knowing before touching it:

- The rootfs layout is not arbitrary. The toolchain's own prefix
  contents sit at the rootfs root because that is where gcc looks for
  its libexec and headers relative to `/bin/gcc`; `/usr` is a real
  directory of one-level-down symlinks rather than the tarball's
  top-level `usr -> .`, since a top-level symlink is an untested edge
  case for bwrap's per-entry `--ro-bind`; BusyBox applets are
  installed only where the toolchain has not already claimed the name,
  so the real `ar`, `nm`, `strip` and `ranlib` win.
- `cc` is a symlink to `gcc` that the derivations add. The tarball
  ships `gcc` and `x86_64-linux-musl-cc` but no plain `cc`, which is
  the name most build systems reach for.
- `tar --no-same-owner` everywhere: the sandbox maps only uid 0, so
  restoring the tarball's recorded ownership fails outright. Nothing
  is lost, since `store-hash-directory` hashes content and the
  owner-execute bit, never uid or gid.
- The chain **is** bit-reproducible now, given a pinned session key --
  see `make check-reproducible`, which builds letloop twice and
  requires every file to match. It was not, and the cause was two
  layers: Chez names gensyms from a per-process random key, and
  letloop baked a build timestamp in at expand time.

## What "done" means, and what is not done

Written down because it was twice claimed complete while it was not.
Both misses were of the same kind: a stage skipped, and nothing that
would say so. The makefile's probes for optional libraries fail
*silently*, so a letloop missing io_uring or BLAKE3 links cleanly,
runs, prints its version, and only fails once something reaches the
part that needed them. "It built" and "it is broken" look identical
until a gate distinguishes them.

So every claim below names the gate that checks it. If a claim has no
gate, it is not a claim.

| must be able to | gated by |
| --- | --- |
| Fetch a pinned artifact with no rootfs at all | `~check-store-001/fetch-only` |
| Build a derivation from another's output, and refuse a cycle | `~check-store-00{2,3,4}` |
| Skip an unchanged build, and *not* skip a changed one | `~check-store-00{5,6}` |
| Assemble a rootfs that compiles C, from two pinned binaries | `rootfs`, `hello` |
| **Compile a Scheme program to a standalone static binary** | `scheme-hello` — the thing the store is actually for, and the one gate that fails when only *that* is broken |
| Rebuild its own shell and build driver from source | `busybox`/`make`, and `bootstrap.sh` comparing bytes against the fetched BusyBox |
| Build ChezScheme and letloop with no distribution involved | `chezscheme`/`letloop` |
| Produce a letloop that needs no dynamic loader, anywhere | absent `INTERP` segment, checked per artifact |
| Actually drive io_uring, not merely link it | `flow2` — the full flow2 suite |
| Actually run the store that built it | `bootstrap.sh`'s self-hosted build, which needs BLAKE3 |
| Compile a Scheme program against a C archive | `static-lib`, and `letloop-check.sh` on the host |
| Build a static archive for the rest of letloop's dlopen'ed FFI libraries | `argon2`/`sodium`/`picohttpparser`/`oprf`/`opaque`/`tls`, each checked for the archive and its own entry points |
| Build one application-level package against another, not just against the rootfs | `opaque` (needs both `sodium` and `oprf` as `(package ...)` inputs) |
| Run all of the above relocated, on a foreign libc | copied to a fresh directory and run there |

Known gaps, all of them deliberate:

- ~~**No cold start.**~~ The mechanism is closed, gated by
  `bootstrap.sh`: `tls` builds real LibreSSL statically,
  `bootstrap-letloop` links it in like `liburing`/`blake3`, and
  `(letloop tls base)`'s `tls-open` resolves a CA bundle explicitly
  (`bundled-ca-file`, walked up from the running executable) rather
  than trusting LibreSSL's own default — which is a compile-time
  constant baked into `libtls.a` pointing at a sandbox-only path,
  useless once the binary is copied out. `(letloop package
  ca-certificates)` ships the bundle itself, hash-pinned like every
  other fetch here. Verified: a `bootstrap-letloop` copy, run outside
  the sandbox on this session's glibc host, makes a real HTTPS GET
  with no host `libtls.so` and no host CA store.

  Not fixed by turning off certificate verification instead, which
  was on the table for a moment — that trades a build-time gap for a
  runtime security hole, in every program this store's `tls` output
  ever gets linked into, not just the bootstrap chain.

  What "closed" does not cover: the gate above proves the *mechanism*
  — an already-built relocated letloop can fetch over HTTPS — not
  that the *whole chain*, from `toolchain` through `letloop`, has been
  run starting from a machine with nothing on it at all. Every fetch
  in this chain so far has run under an ordinary host letloop, using
  the host's own dynamic `libtls.so`; nobody has yet driven
  `bootstrap.sh` itself using only a statically linked letloop as the
  fetcher. That would be the actual end-to-end cold-start proof, and
  it is still unattempted.

  Fetching over plain HTTP instead looked like the cheap way out at
  one point, since every fetch is hash-pinned and TLS therefore adds
  nothing to integrity — it only hides *which* file is being asked
  for. It does not work regardless: measured 2026-08-23, five of the
  seven pinned URLs 301-redirect HTTP to HTTPS, GitHub and
  busybox.net among them, and GitHub will not stop.
- **Not a fixpoint byte-for-byte.** letloop rebuilds letloop, and the
  third generation is as complete as the second and produces identical
  output hashes — but the two binaries differ, because the build is not
  reproducible (see above).
- **The compiler is trusted, not built.** musl.cc's gcc and one
  BusyBox binary are taken on their hashes. Retiring the compiler means
  a full source bootstrap, which this chain does not attempt.
- ~~**ChezScheme diverges.**~~ Closed: the host now pins `v10.4.1`
  too, so the letloop you develop with and the one
  `letloop store build letloop` produces are the same version. The
  chain had to pin a release regardless — a network-off sandbox cannot
  fetch the submodules a git checkout needs, where the release tarball
  bundles them — and `main` was never a fixed point to build against.
  Nothing in the tree needs anything newer: `__errno` and
  `scheme-pre-release` both work in 10.4.1.
- **x86_64-linux-musl only.** No cross-compilation, no other
  architecture.

## Direction, and what is deliberately not being built yet

Decided in design rather than in code, recorded so it is not
rediscovered.

**The root is bundling package definitions with the letloop release.**
Everything the intended workflow needs sits on it: `letloop store
build libgegl` taking a bare name needs a name to resolve against, and
`letloop store build letloop` needs letloop's own source to be a
hash-pinned fetch rather than the bind-mounted working tree
`bootstrap-letloop.derivation.scm` uses today — that path only exists
because the derivations are still test fixtures under `checks/`.

**`letloop update` is gated on something outside code**: there have to
be releases, and a user replacing their own binary needs a source of
truth for what is newest. Reproducibility softened this — a published
binary can be verified by rebuilding it — but did not remove it.

**Static linking is the default** for a compiled program.

**Inferring C dependencies from the import closure is parked.** The
data for it is already in the source: nine libraries name their shared
object with `define-shared-object`, and letloop already computes the
import closure for amalgamation, so importing `(letloop blake3)` is
itself the statement that libblake3 is wanted — no symbol-level
analysis needed. What parks it is that a program's identity would then
include *which* archive it linked, so a binary would only be
reproducible if that were pinned, and would arguably need addressing
by its whole closure.

That dissolves rather than needs managing if a binding pins its
package by a conventional name instead of naming a bare `.so`: the
version is then fixed by the letloop release, which already bundles
the definitions, so a program's identity is its source plus a letloop
version and nothing further. Which puts inference back behind the same
prerequisite as everything else.

Three things it will still have to answer, none solved by pinning:

- C libraries have C dependencies of their own — libtls pulls libssl
  and libcrypto — and static archives are order-sensitive, so
  inference needs a closure emitted dependency-first, not the flat
  list `letloop compile`'s `.a` arguments take today.
- Two archives defining one symbol resolve silently by link order.
  With explicit arguments a person chose them; with inference nobody
  did.
- `define-shared-object` cannot say whether a library is required or
  merely faster. blake3 is now the latter, since `(letloop blake3
  pure)` is the floor.

**Inference makes a substituter matter more than it did when it was
deferred.** Deferring was right for explicit builds: asking for
`store build libgegl` is asking for a wait. Inference makes the build
implicit, so compiling a hello-world that happens to import
`(letloop blake3)` could trigger a sandboxed build, or on a cold
machine most of the chain, with no visible cause. Prebuilt outputs
stop being an optimisation at that point.

**A program's own C library keeps the explicit path.** Inference only
covers bindings letloop ships, so `letloop compile prog.scm main
libfoo.a` stays the escape hatch; the two compose.

**`letloop exec` stays** until the cost of compiling under this design
is known. It is the fast-iteration path, and the argument for removing
it — that a program run through `exec` links dlopen'd shared objects
while a compiled one links static archives, so the two are not quite
the same program — only outweighs that if compiling stays cheap.

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
  produced a statically linked `hello` binary in the store. (That
  derivation and its Alpine-provisioned rootfs were later replaced by
  the bootstrap chain above; the account here is kept as the record of
  how the static-linking work was originally verified.)
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

## `(letloop liburing low)` under static linking — resolved

**`letloop review`** (and anything else reaching `tea/loop.scm` — the
async terminal I/O loop `termbox.scm`/`tea.scm` build on, in turn
reachable from `flow.scm`/`flow2.scm`) transitively imports
`(letloop liburing low)`, which resolves ~170 `io_uring_*` functions via
`lazy-foreign-procedure` against a *named* dlopen of `liburing-ffi.so`
— a second, independent instance of the same class of problem point 9
above fixes for ordinary libc calls, with its own twist:

- `dlopen("liburing-ffi.so.2", RTLD_NOW)` — a real, named `.so`, not
  `dlopen(NULL, ...)` — **also fails** under this Alpine's static musl,
  with musl's own clean `"Dynamic loading not supported"` (not a
  crash: `path` is a real string here, so `load_shared_object`'s
  NULL-format bug from point 7 doesn't trigger). Confirmed: this
  static libc supports no `dlopen` at all, named or not — a stronger
  limit than point 7's `dlopen(NULL, ...)`-specific one.
- No upstream liburing work needed: Alpine's `liburing-dev` package
  already ships `liburing-ffi.a`, a **static** archive of the same
  symbol set `liburing-ffi.so` exports at runtime — built specifically
  because most of `liburing.h`'s API (`io_uring_prep_*`, the sqe/cqe
  accessors, and — this mattered below — the ring-index bookkeeping in
  `io_uring_cq_advance`/`io_uring_cqe_seen`, which calls the memory
  barrier primitives in `liburing/barrier.h`) is `static inline` in
  the header and has no linkable symbol otherwise.
- An earlier version of this fix took each `static inline` function's
  address directly in C (`#include <liburing.h>` + `-luring`,
  unmodified), reasoning that address-taking forces the compiler to
  materialize an equivalent out-of-line copy. That copy is a
  *different* compiled instantiation of the barrier-dependent code
  than the one upstream ships in `liburing-ffi.a` — not provably
  wrong, but an unresolved gap while this bug was still open. The
  fix that actually landed: reference `liburing-ffi.a`'s own
  pre-built symbols directly, via GCC's asm-label extension
  (`extern void name_stub(void) __asm__("name");`) so this
  translation unit never redefines or re-inlines any of them itself —
  it only takes the address the archive already provides, byte-for-byte
  identical to what a dynamic FFI consumer would dlopen. Linking
  `liburing-ffi.a` directly with `IOURINGINLINE` defined empty in this
  file's *own* compilation was tried first and rejected: `liburing.a`'s
  `queue.ol` already carries real, non-inline definitions of a handful
  of these names (`io_uring_get_sqe`, `io_uring_get_events` — kept for
  ABI back-compat from before they became header-only), and duplicating
  them collided at link time ("multiple definition of io_uring_get_sqe").
  The makefile links `liburing-ffi.a` (`-luring-ffi`, replacing plain
  `-luring` — it is a strict superset) instead of taking on that
  conflict.
- `cffi.scm`'s `lazy-foreign-procedure` macro tries a bare
  `foreign-procedure` lookup first, falling back to `(shared-object)`
  (the named dlopen) only on failure — the same probe-first shape as
  `ensure-self-loaded!`, but per-symbol instead of a single global
  gate, since here there is no one call that "unlocks everything
  else." `letloop-main.c` registers the ~170 symbols via
  `Sforeign_symbol` (mechanically extracted from every
  `lazy-foreign-procedure liburing-ffi ...` call in `low.scm`), guarded
  behind `LETLOOP_LIBURING_STATIC` so a build without `liburing-dev`
  installed is entirely unaffected.

**The actual root cause of the runtime crash was unrelated to any of
the above.** `low.scm` had its own raw, unconditional
`(define stdlib (load-shared-object #f))` at its top level —
completely bypassing `ensure-self-loaded!`'s probe, and running the
instant the library was instantiated regardless of whether dlopen was
actually safe. `stdlib` itself was dead: exported, but never
referenced anywhere else in the file. This explained every earlier
observation exactly: a trivial program never instantiates `low.scm` so
never hits it; *importing* `low.scm` without referencing any of its
bindings let dead-code elimination skip instantiation entirely
(looked like success); referencing even a bare, non-FFI constant
forced full instantiation and hit this line before anything else in
the file ran, including the io_uring registration this section
originally suspected. Removed rather than reharnessed — the same
`(letloop cffi)` import already used for `with-lock`/`bytevector-pointer`
/`strerror` forces that library's own body (and its `ensure-self-loaded!`
call) to run first, per R6RS import ordering, which is all `low.scm`'s
own eager, unwrapped `foreign-procedure` calls further down
(`%strlen`, `memcpy`, `fcntl`, `socket`, `setsockopt`, `getsockopt`,
`bind`, `listen`, `getpeername`) actually need. Those symbols, plus
`eventfd`/`write` from `flow.scm`/`flow2.scm`'s own eager calls, were
missing from `letloop-main.c`'s registration table and needed adding —
each failed *cleanly* once `stdlib`'s crash was out of the way
(`Exception in foreign-procedure: no entry for "strlen"`), which is
what made them straightforward to find one at a time.

The same `(define stdlib (load-shared-object #f))` anti-pattern exists
in `desktop/ioctl.scm` and `desktop/evdev.scm` — not exercised by
anything in this session's static-linking path (`letloop desktop`
needs Vulkan/DRM, out of scope per this file's own non-goals), but the
identical latent bug if either is ever built statically.

**Verified**: `letloop check src/ src/letloop/flow2.scm` — real
io_uring ring setup/submit/wait/cancel plus socket and file I/O —
passes cleanly on the static build
(`checks/letloop/bootstrap-flow2.derivation.scm`). `letloop review`
compiles statically too (`checks/letloop/bootstrap-review.derivation.scm`)
but is not run there — it is an interactive TUI needing a real
terminal, not a gap.

Both checks were originally written against an Alpine-provisioned
rootfs, in `store-flow2-static` / `store-review-static`, driven by
`store-static-hello.sh`. Those are gone; the bootstrap chain covers
every check they made without a distribution.
