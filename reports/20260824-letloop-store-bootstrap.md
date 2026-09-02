# `letloop store`: package resolution, the rest of the FFI chain, and a fully static, TLS-capable bootstrap letloop

**Date:** 2026-08-24
**Branch:** `dev-letloop-os`
**Repo:** `private-letloop`

## Abstract

`letloop store` is a Nix-style, content-addressed package manager built into
letloop, used to bootstrap a statically linked, relocatable `letloop` binary
with no Alpine or other distribution involved. Entering this session it
could build exactly one derivation per invocation, addressed either by file
path or by a single bare package name, and only two of letloop's eight
dlopen'ed FFI libraries (`liburing`, `blake3`) had store package definitions.
This work: rewrote `letloop store build`'s CLI to accept versioned,
multi-component package names and project-local package directories, mirroring
the argument-parsing convention already used by `letloop check`/`letloop
compile`; built store packages for the remaining six FFI libraries
(`argon2`, `sodium`, `picohttpparser`, `oprf`, `opaque`, and `tls` — real
LibreSSL, the largest build in the chain); statically linked `tls` into the
bootstrap letloop itself, the way `liburing`/`blake3` already were; and closed
the resulting CA-bundle gap by having `(letloop tls base)` resolve a bundled
certificate file at runtime relative to the running executable, rather than
trusting a compile-time path baked into `libtls.a` that only ever existed
inside the build sandbox. Verified end to end: the full chain builds from
nothing, gated at every stage; a rebuild is byte-for-byte reproducible (0
files differ); and the resulting binary is confirmed statically linked with
no dynamic loader, no `NEEDED` entries, and a genuine HTTPS request succeeding
from a copy run completely outside the sandbox.

## Introduction

letloop is a Scheme compiler and runtime built on Chez Scheme. `letloop
store` exists to answer a specific question: can letloop build itself,
statically, reproducibly, without depending on a Linux distribution's package
manager at any point? Reaching "yes" requires two things to both hold: a
chain of derivations that actually produces a working, relocatable binary,
and a package-naming and resolution scheme flexible enough that the chain
doesn't have to be hand-wired file-by-file. This session picked up that
second problem first — the CLI could only resolve one argument to one
package, with no notion of versions or project-local overrides — and then
used the fix to extend the chain itself: six more FFI libraries got real
store packages, and the largest of them, `tls`, got wired all the way into
the bootstrap binary's own static linking, closing a real functional gap
(a statically linked letloop could compile programs and run a warm store,
but could not fetch anything new over HTTPS).

## Initial state

- `letloop store build` took exactly one positional argument. If it named an
  existing file, that file was read as a derivation; otherwise the whole
  string became `(letloop package <name>)` — a single library-name component,
  hardcoded to letloop's own shipped namespace. `letloop store build libgegl
  v1.2.3` was not expressible.
- `src/letloop/package/` held package definitions for the bootstrap chain's
  own scaffolding (`toolchain`, `shell`, `rootfs`, `make`, `busybox`,
  `rootfs-final`, `chezscheme`, `letloop`) plus exactly two consumable FFI
  libraries: `liburing` and `blake3` — the two linked into the bootstrap
  letloop's own host via `letloop-main.c`'s static symbol registration.
- `(letloop blake3)` dispatched between a C implementation (dlopen'd or,
  under static linking, `Sforeign_symbol`-registered) and a pure-Scheme
  fallback named `(letloop blake3 pure)`. `(letloop store)` imported the
  dispatching library, so its own hashing correctness depended on the C
  path working (or falling back correctly) rather than standing on its own.
- `letloop exec` silently dropped a `.a` archive argument: `guess` classified
  it as `'archive`, but `letloop-exec`'s argument-dispatch `case` had no
  clause for that type, so the archive vanished from parsing with no error —
  surfacing later as an unrelated `Exception in foreign-procedure: no entry
  for "..."` deep inside the running program.
- `letloop-main.c` statically linked `liburing-ffi.a` and `libblake3.a` into
  the bootstrap host when the makefile's musl-only probes found them, via
  `Sforeign_symbol` registration through GCC's asm-label aliasing (no header
  needed — the archive's own symbols are taken directly). No such wiring
  existed for `tls`, `sodium`, `argon2`, `picohttpparser`, `opaque`, or
  `vulkan`.
- The store's build cache (`build-cache-set!`) wrote its entry with
  `call-with-output-file`'s default mode, which raises if the destination
  already exists — undiscovered until a real concurrent build hit it.
- No CA bundle problem existed yet, because no statically linked letloop had
  ever attempted a real HTTPS fetch: `libtls` was outside the chain entirely.

## The various options

Several forks came up during this work; the ones actually decided are listed
with their resolution, not just their existence.

- **Project-package naming shape.** Considered wrapping a project's own
  packages under `(package . COMPONENTS)` inside a dedicated `packages/`
  subdirectory (mirroring `(letloop package NAME)`'s own `letloop/package/`
  layout one level down). Rejected in favor of putting `$LETLOOP_PROJECT_PATH`
  itself directly on the library path, so a project package resolves through
  the literal `package/` segment already present in the library name —
  `$LETLOOP_PROJECT_PATH/package/NAME.scm` — avoiding a redundant
  `packages/package/` stutter.
- **Which library resolves first.** `(package . COMPONENTS)` is tried before
  `(letloop package . COMPONENTS)`, so a project's own package shadows a
  shipped one of the same name, rather than the reverse.
- **Dropping `libblake3` from the store's own hashing path entirely.** Raised
  as a broader idea (drop `letloop exec`, avoid `(letloop blake3)`'s C path in
  bootstrap, rename the pure fallback). Split into pieces by cost: the rename
  and redirect (cheap, done — see below); dropping `letloop exec` and sweeping
  `dlopen` out of the whole Scheme codebase (large, cross-cutting, left
  undecided — nine libraries exist as optional lazily-loaded `.so`s
  specifically so importing letloop never requires them installed, which is
  load-bearing per `CLAUDE.md`, not incidental).
- **Real LibreSSL vs. Debian/Ubuntu's `libretls`.** This host's own installed
  `libtls28t64` package is `libretls`, a thin libtls-API shim over the
  system's OpenSSL — it exists only because a from-scratch LibreSSL's
  `libssl`/`libcrypto` collide by name with OpenSSL's on a distro that already
  depends on OpenSSL everywhere. That reason doesn't apply to a static archive
  this chain builds and consumes entirely on its own, so real LibreSSL was
  built directly — one source tree producing `libtls.a`/`libssl.a`/
  `libcrypto.a` with no external crypto dependency at all.
- **Where to fetch LibreSSL's portable tarball from.** GitHub's release page
  for `libressl/portable` carries only an auto-generated snapshot of the bare
  git tree — missing the pre-generated `configure` script and the ~60
  per-architecture `.S` assembly files the portable dist tarball ships
  instead, both of which would otherwise need `autoreconf` and `perl`, neither
  present in this toolchain. Fetched from `ftp.openbsd.org` instead — upstream's
  own canonical distribution point for the portable releases — verified by
  content hash regardless of which mirror serves the bytes.
- **Bundling a CA file vs. teaching the code to find one.** The first, alone,
  does nothing: LibreSSL's default CA path is a compile-time constant baked
  into `libtls.a`, unrelated to what files happen to exist elsewhere in a
  relocated tree. The two had to be combined — bundle a file, *and* have
  `tls-open` resolve its path explicitly at runtime and call
  `tls_config_set_ca_file` — rather than relying on libtls's own default
  resolution, which cannot be made to work for a relocatable binary at all.
- **Where the CA bundle comes from.** curl's own extraction of Mozilla's CA
  root list (`https://curl.se/ca/cacert.pem`), republished specifically for
  bundling into applications — not Mozilla's raw `certdata.txt` (needs its own
  parser) and not this host's own `/etc/ssl/certs/ca-certificates.crt`
  (Debian's build, not something this store can pin by content the way a
  fetch needs).
- **Disabling certificate verification as a shortcut.** Considered and
  rejected: it would have "fixed" the CA-file error trivially, but trades a
  build-time gap for a runtime security hole in every program the store's
  `tls` archive ever gets linked into, not just the bootstrap chain.
- **`tls`'s largest build risk.** Whether LibreSSL's `.pl`-based assembly
  generators would need `perl` at build time. Checked directly: the portable
  dist tarball ships the generated `.S` files already, and `configure` never
  references `PERL` — the `.pl` scripts are shipped for a maintainer to
  regenerate them, not invoked by an ordinary build.

## What was implemented

Nine commits on `dev-letloop-os`, merged with three unrelated upstream fixes
from `dev` and pushed:

1. **`letloop store build`'s CLI rewritten** to route through `cli-read` /
   `guess`-style argument classification (mirroring `letloop-check`/
   `letloop-compile`): an existing directory extends the library path,
   everything else accumulates in order as the components of a package's
   library name. `letloop store build libgegl v1.2.3 pre` now resolves
   `(package libgegl v1.2.3 pre)`, falling back to `(letloop package libgegl
   v1.2.3 pre)`. `$LETLOOP_PROJECT_PATH` joins the library path automatically
   when present. A lone existing file still resolves as a plain derivation
   path, unchanged.
2. **`letloop exec` rejects a `.a` argument explicitly** instead of silently
   dropping it, naming the archive and pointing at `letloop compile` as the
   actual way to link one.
3. **`(letloop blake3 pure)` renamed to `(letloop blake3 scheme)`**, and
   `(letloop store)`/`(letloop store hash)`/`(letloop store fetch)` now import
   it directly rather than through the C-dispatching `(letloop blake3)` — the
   store's own hashing no longer depends on whether a particular binary's
   static blake3 registration happened to work.
4. **Six new store packages**: `argon2`, `sodium`, `picohttpparser`, `oprf`
   (a build-time-only dependency of `opaque`, not itself dlopen'ed by
   letloop), `opaque`, and `tls` (real LibreSSL — `libtls.a`, `libssl.a`,
   `libcrypto.a`). Each verified by an actual sandboxed build producing the
   expected archive, header, and (where upstream ships one) man page, with
   key entry points confirmed present via `nm`. `opaque` is the first package
   in the chain to depend on two other application-level packages (`sodium`,
   `oprf`) rather than only on the shared toolchain rootfs.
5. **A build-cache race fixed**: `build-cache-set!` now writes with
   `'replace` instead of the default mode, tolerating two builds of the same
   derivation racing to write the same cache key — found for real when an
   accidentally duplicated `tls` build crashed with `file exists`.
   `~check-store-008/cache-write-is-idempotent` reproduces it directly and
   fails against the unpatched code.
6. **`libtls` statically linked into the bootstrap `letloop`**, the same
   shape as `liburing`/`blake3`: a musl-only makefile probe for `-ltls -lssl
   -lcrypto`, a `letloop_register_tls_symbols()` registering every `tls_*`
   symbol `(letloop tls low)` resolves, and `(letloop package letloop)`
   taking `tls` as a fourth input.
7. **A runtime-resolved CA bundle**: `(letloop tls base)`'s new
   `bundled-ca-file` walks `$LETLOOP_PREFIX` then the running executable's own
   directory (a self-contained `/proc/self/exe`-based helper, duplicated
   rather than imported from `(letloop base)`, which is folded into the
   amalgamated program and must import nothing of letloop's own) looking for
   `lib/letloop/cert.pem`. `tls-open` calls `tls_config_set_ca_file`
   explicitly when found; falls through to libtls's own default, unchanged,
   when not — zero behavior change on an ordinary dynamic build using the
   host's own working `libtls.so`. `(letloop package ca-certificates)`
   fetches the bundle itself, hash-pinned; `(letloop package letloop)` copies
   it into place after `make letloop` finishes (copying before would be wiped
   by `letloop-libraries`' own `rm -rf`).
8. **`checks/letloop/bootstrap.sh` and `src/letloop/store/README.md`
   updated** throughout: gates for all six new packages, a `tls_connect`
   symbol check on the bootstrap binary, and a new gate making a real HTTPS
   request through a relocated copy of the bootstrap letloop.

Verified, not just claimed, in three separate passes: `checks/letloop/
bootstrap.sh` (the full chain from an empty store, all 13 stages plus the six
new packages, exit 0); `checks/letloop/reproducible.sh` (`letloop` built
twice with a forced cache eviction between runs, `diff -rq` across the two
full trees finding 0 differing files); and an independent manual check
(`ldd`: statically linked; `readelf -l`: no `INTERP` segment; `readelf -d`:
no `NEEDED` entries; `nm`: `tls_init`/`blake3_hasher_init`/
`io_uring_queue_init` all present in one binary).

## Similar work

- **Nix's bootstrap-tools model.** A small number of pinned, hash-verified
  prebuilt binaries, with everything else built from source against them.
  This chain follows the same shape deliberately (exactly two trusted
  prebuilt artifacts: the musl.cc toolchain and a static BusyBox), rather
  than attempting Guix's full mes/hex0 source bootstrap, which the store's
  own README already rules out as disproportionate for this project's goals.
- **stal-ix/IX.** A source-based, Nix/Guix-family package manager built
  explicitly around static linking for relocatability, with a
  content-addressed store and hermetic sandboxed builds — close prior art
  for the whole subsystem's design, cited when the store itself was first
  designed. Notably, IX's own documentation lists bootstrap work as an open
  contribution area too; no prior art solves the from-scratch bootstrap
  problem cleanly, which is why Nix's practice (trust a few pinned binaries)
  rather than IX's or Guix's was the model actually followed here.
- **Debian/Ubuntu's `libretls`.** A real, shipped example of the "wrap the
  libtls API over a different underlying implementation" approach this
  session considered and rejected for the store's own `tls` package, for a
  reason specific to this context (no existing OpenSSL dependency to avoid
  colliding with).
- **curl's CA bundle extraction service.** `https://curl.se/ca/cacert.pem`
  exists precisely for the problem this session hit — an application that
  needs to bundle a CA list without parsing Mozilla's own certificate-store
  format — and was used directly rather than reinventing that extraction.
- **letloop's own prior art.** The `liburing`/`blake3` static-linking pattern
  (asm-label aliasing via `Sforeign_symbol`, a musl-only makefile probe) was
  already established before this session and reused verbatim for `tls`,
  down to the macro shape. `(letloop base)`'s `executable-directory` /
  `letloop-library-directory` (`/proc/self/exe`-relative path resolution)
  was the direct model for `bundled-ca-file`'s own lookup, necessarily
  duplicated rather than imported because of the folding constraint on
  `(letloop base)`.

## Further work

- **`vulkan`** remains the one dlopen'ed FFI library with no store package.
  Deliberately not attempted: `libvulkan.so.1` is a loader that discovers
  ICDs at runtime (CLAUDE.md already documents needing `mesa-vulkan-drivers`/
  `llvmpipe` or a real GPU+DRM session), so statically archiving the loader
  would not remove the actual runtime dependency the way it did for the other
  seven libraries. Whether a store package is even meaningful here — and if
  so, what it should actually gate — is still an open question, not a
  postponed mechanical task.
- **The full cold-start proof is still unattempted.** This session's gates
  prove the *mechanism*: an already-built, relocated static letloop can make
  a real HTTPS request. They do not prove the *whole chain* — `toolchain`
  through `letloop` — can be driven starting from a machine with nothing on
  it, using only a statically linked letloop as the fetcher throughout. Every
  fetch in every gate run so far has gone through an ordinary host letloop
  using the host's own dynamic `libtls.so`.
- **Dropping `letloop exec`** and **sweeping `dlopen` out of the Scheme
  codebase** — both raised as a bundled idea this session, both deliberately
  split off as separate, larger, undecided questions. The former is gated on
  knowing the cost of compiling under this design; the latter would need the
  parked "infer C dependencies from the import closure, pinned by
  conventional name" work to land first, since static-by-default otherwise
  means every consumer links every optional archive whether it uses it or
  not.
- **Inferring C dependencies from letloop's own import closure** remains
  parked, per `src/letloop/store/README.md`'s own "Direction" section — but
  this session's package-naming convention work is exactly the prerequisite
  the README named for it to stop being parked.
- **letloop's own source as a pinned, fetchable package** remains explicitly
  blocked on a standing instruction from earlier in this engagement (no
  public URL currently serves this private repo's actual source tree) —
  untouched this session, on purpose.
- **The CLI-project-package shadowing check is incomplete.** `~check-store-
  007/cli-project-package` proves a project-only package name resolves; it
  does not set up a same-name collision between a project package and a
  shipped one to prove the project package actually wins, which was part of
  the original plan for this work and was never circled back to.
- **A substituter** and **garbage collection over the store** remain
  deliberately deferred, unaffected by this session's work.

## Conclusion

`letloop store` can now resolve versioned, project-overridable package names
through the same argument-parsing convention the rest of the CLI already
uses, and the bootstrap chain it drives covers all but one of letloop's eight
dlopen'ed FFI libraries — including, as of this session, real LibreSSL,
statically linked into the bootstrap binary itself with a CA bundle resolved
at runtime rather than relying on a path that never survives relocation. Every
claim here is backed by a gate that would fail if it stopped being true: the
full chain builds from an empty store, a rebuild is byte-identical, and the
resulting binary is independently confirmed static, dependency-free, and
capable of a genuine HTTPS request with nothing but itself. What remains open
is recorded rather than assumed solved — `vulkan`, the full cold-start
end-to-end run, `letloop exec`, the broader `dlopen` question, and C-dependency
inference are each a real next decision, not a rounding error against what
was actually verified this session.
