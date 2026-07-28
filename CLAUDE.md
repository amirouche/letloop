# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

**letloop** is a Scheme compiler and runtime built on Chez Scheme. It compiles R6RS Scheme libraries into standalone executables and provides a testing framework, REPL, and execution environment.

Main branch for PRs: `dev`

## System Dependencies

### Optional shared objects (dlopen'd lazily, on first use)
FFI binding libraries (`tls`, `liburing`, `vulkan`, `sodium`, `argon2`, `blake3`, `picohttpparser`, `opaque`) load their shared object on the **first foreign call**, via `define-shared-object` / `lazy-foreign-procedure` from `(letloop cffi)`. Importing a binding library — and therefore building letloop itself — requires **no** optional `.so` to be installed. A missing shared object surfaces as `Exception in libfoo: cannot dlopen shared object, tried ...` at first use, and `~check-*` procedures print a `** SKIP` note and pass instead (see `check-skip-unless`).

- **libvulkan.so.1** (`libvulkan1` on Debian/Ubuntu) — needed at runtime by `letloop desktop`.
- **libtls.so** — needed at runtime for TLS features (`letloop serve` over https, `(letloop tls)`).
- **liburing-ffi.so.2, libsodium, libargon2, libblake3, libpicohttpparser, libopaque** — needed at runtime by their respective modules; `make check` skips their checks when absent.

### Runtime-only (for `letloop desktop`)
- **A Vulkan ICD** — on headless machines install `mesa-vulkan-drivers` for software rendering via `llvmpipe`. Without any ICD, `vkCreateInstance` returns `VK_ERROR_INCOMPATIBLE_DRIVER`.
- **A real TTY + GPU for the full M2.x path** — `/dev/tty0` (requires `CAP_SYS_ADMIN` to issue `KDSETMODE`) and `/dev/dri/card0` (requires DRM master, i.e. root or seat-managed session). Sandbox runs will fail at `DRM_IOCTL_SET_MASTER` or earlier; the seat-take rollback handles this cleanly.

### Optional (developer cross-checking)
- **libvulkan-dev** — only needed if you want to verify Chez ftype sizes against `sizeof()` from Vulkan headers. See `src/letloop/desktop/vulkan/low.scm` for the ftype definitions; struct sizes are recorded in comments.

## Build Commands

**Critical:** Always run `make` inside the `./venv` environment. The `makefile` auto-detects `SCHEME=$(shell which scheme)`, which picks up the system Chez (e.g. 9.5.8) instead of the local 10.x build. Running outside `./venv` causes `Exception: attempt to reference unbound identifier scheme-pre-release`.

**First-time setup** (builds ChezScheme from source, ~5–15 min):
```bash
./venv               # enters a shell with SCHEME, LETLOOP_ROOT, LD_LIBRARY_PATH set
make chezscheme      # ChezScheme $(CHEZ_REF), currently main = 10.5.0-pre-release.1
make letloop         # installs itself, no `mv a.out` step
make check
```

**Rebuild letloop after changes:**
```bash
make letloop          # must be inside ./venv shell, or: ./venv $(pwd)/local/ make letloop
```

**Run all tests:**
```bash
make check
```

**Run a single test manually:**
```bash
$LETLOOP check checks/check/ checks/check/check-success.scm
$LETLOOP exec checks/ checks/codex/base.scm codex-usage
```

**Find in-progress items:**
```bash
make todo   # find TODO comments
make xxx    # find XXX comments
```

**Clean temp files:** `make clean` (removes `/tmp/letloop/`)

## Claude Code Skills

Prefer these skills for common workflows:
- `/letloop-full-setup` — complete setup from scratch
- `/letloop-build` — rebuild letloop
- `/letloop-install` — build and install to `local/bin`
- `/letloop-test` — run full test suite
- `/letloop-build-chez` — rebuild ChezScheme only
- `/letloop-clean` — clean `/tmp/letloop/`

## Architecture

```
src/letloop-main.c           C host — parses no flags, finds its boot in its own trailer
src/letloop/base.scm         Main entry point: letloop-main, letloop-compile, letloop-exec,
                            letloop-repl, letloop-check — handles CLI dispatch, library
                            discovery, and compilation
src/letloop/cli/base.scm     Argument parser — cli-read / cli-write, parses flags,
                            positional args, and extra args (after --)
src/letloop/root/base.scm    Isolated execution environments (container-like sandboxes)
src/letloop/r999.scm         define-record-type* macro (extended record types)
src/letloop/sq.scm           Priority queue (sq-new, sq-add!, sq-min, sq-split)
src/letloop/match.scm        Pattern matching (SRFI 241)
src/letloop/http.scm         HTTP request/response handling
src/letloop/html/            HTML parsing (htmlprag + utilities)
src/letloop/generator.scm    Generators/coroutines
src/letloop/sxpath.scm       XML/XPath queries (SXPath)
src/letloop/environment.scm  Environment variables (SRFI-98)
src/letloop/www.scm          Web utilities
src/letloop/cffi.scm         C FFI bindings
```

**Build output:** `make letloop` compiles `src/letloop-main.c` against Chez's `kernel.o`, then appends the amalgamated boot image and a 16-byte trailer to it. The result is one self-contained file that needs nothing beside it.

```
$PREFIX/lib/csv<version>/<machine>/letloop        host + boot + trailer, one file (4.4 MB)
$PREFIX/lib/csv<version>/<machine>/letloop-host   the bare host, kept for reference
$PREFIX/lib/csv<version>/<machine>/letloop.boot   the boot on its own (3.3 MB), what
                                                  --visible-libraries folds into a program
$PREFIX/bin/letloop                               relative symlink to the above
$PREFIX/lib/letloop/src/letloop/**.scm            the sources letloop ships
$PREFIX/lib/letloop/obj/<optimize-level>/**       their .so and .wpo, per level
```

**Building letloop now requires a Chez installation**, for `scheme.h` and `kernel.o`. Compiling a *user* program still requires no C compiler — `letloop compile` copies its own host and appends a different boot — but it does require a real `scheme` binary for its child process.

**`(letloop base)` imports nothing from letloop, on purpose.** It resolves `cli-read`, `transparent`, `letloop-root` and `letloop-review` at first use through `lazy` / `letloop-library-path!`, against the sources installed at `$PREFIX/lib/letloop`. Two reasons, and both bite hard if someone adds an import back:

- A library imported by `(letloop base)` gets folded into the amalgamated letloop program, and a folded library is **invisible** — its name then blocks *user* programs from importing that same library. `(environment '(letloop match))` fails with "attempt to import invisible library" even with the source on the path.
- Loading letloop's libraries at startup costs **36 ms**. letloop starts in 35.06 ms against a bare Chez floor of 33.04 ms; before this it was 69.6 ms.

So the shape tests in `base.scm` are plain list code rather than `(letloop match)` patterns, and every subcommand that replaces `library-directories` calls `letloop-library-path!` afterwards to put letloop's own libraries back on it.

One consequence: `(letloop base)` is itself folded, so `letloop check ./src/` skips `src/letloop/base.scm` — it exports no `~check-*`, so no test is lost.

**`src/letloop-main.c` exists to not parse the command line.** Chez's own `c/main.c` reads argv before any Scheme runs and claims `--help`, `--version`, `--optimize-level`, `--libdirs`, `-b`/`--boot`, `--verbose` and a dozen more — **at any position**, not just the first, so a letloop that was the `scheme` binary renamed printed *Chez's* version for `letloop check --version`. letloop's `main` hands `argc`/`argv` to `Sscheme_start` untouched, so every flag reaches `letloop-main`. `letloop help` and `letloop version` exist as dashless spellings too.

Three things about that host are load-bearing:

- **It finds its boot by reading its own trailer**, `[boot][8-byte LE length][magic "LETLOOP\1"]`, via `/proc/self/exe` — not `argv[0]`, which is whatever the caller put there and breaks under a PATH lookup or a symlink. With no trailer it falls back to `Sbuild_heap(argv[0], 0)`, which loads `<basename>.boot`. One binary therefore serves both roles.
- **It `mmap`s rather than reads.** A `malloc` + `fread` of the 3.3 MB payload on every start measured **~0.8 ms** against the old separate-boot arrangement; `mmap` brought that to ~0.36 ms. On a 27 ms startup that is the difference between 3% and 1.3%.
- **The whole file is mapped**, because `mmap` offsets must be page-aligned and the payload starts wherever the host happens to end. The mapping is never unmapped — Chez keeps the pointer for the run.

`$PREFIX/bin/letloop` is a plain *relative* symlink; it must stay relative because `scheme-binarypath*` locates the boot directory through `dirname($SCHEME) + "/" + readlink($SCHEME)`.

**`letloop compile` builds the same shape without a C compiler**: it reads its own binary, strips its own payload to recover the bare host, and appends the new program's boot. That is why `emit-program!` also writes `./a.out.boot` — `make letloop` needs the boot alone to assemble the binary it ships, and `--visible-libraries` folds it. Only `./a.out` is needed to run a program.

**The compiler child cannot be letloop itself** any more, precisely because letloop no longer parses `-b` or `--script`. `scheme-executable` looks up `$LETLOOP_SCHEME`, then `scheme` beside the boot directory, then `$PATH`. A version-mismatched Chez here is the failure CLAUDE.md warns about elsewhere, so the error names all three places it looked.

**`letloop compile` amalgamates by default:** the program and every library it imports become one compilation unit via `compile-program` + `compile-whole-program`, so calls across library boundaries can be inlined — worth ~14% on the HTTP benchmark. Two things make that possible and are easy to break:

- It runs in a **child process** spawned as `<scheme> -b petite.boot -b scheme.boot --script build.scm`. A library already defined in the process shadows its own source and is never recompiled, so no `.wpo` is written for it — and every `(letloop ...)` library arrives with the boot image. `compile-whole-program` then folds nothing and reports it only through its return value, which is why the child treats a non-empty return as fatal. `<scheme>` is a **real Chez**, not letloop — letloop's own host parses no flags, so it cannot honour `-b` or `--script`; see `scheme-executable`.
- The `.wpo` cache is **per optimize level**. Folding a level 0 cache into a level 3 program measured 401k req/s against 456k for a level 3 cache. `CACHE_LEVELS` in the makefile primes 0 and 3; any other level is built on demand.

`--visible-libraries` restores the old behaviour, and is required by a program that resolves a library name at run time with `environment` or `eval`.

**Runtime boot loading** (relevant when debugging standalone binaries): there is now a *single* boot image, appended to the binary and registered from memory as `program`. `make-boot-file` is called with an **empty base list**, which is what makes it standalone — the first input must then itself be a base boot file. The inputs are `petite.boot`, `scheme.boot`, then the program; with `--visible-libraries` they are `letloop.boot` (already a base boot, it carries petite and scheme) then the libraries.

## Testing Framework

Test files use the `letloop check` subcommand. Procedures prefixed `~check-` are test cases; `~benchmark-` are benchmarks. The test runner validates output via MD5 hash comparison.

**Library checks live with their library** under `src/`: the library exports its `~check-*` procedures and `include`s a sibling `NAME.check.scm` fragment (see `src/letloop/aql/morton.scm` or `src/letloop/tea/cell.scm` for the pattern). `make check` discovers them by scanning `./src/`. Checks that want a live service (e.g. PostgreSQL) print a SKIP note and pass when the service is absent.

The `checks/` directory is only for proving the test runner itself works:
- `checks/check/*.scm` — success/failure/error/edge-case scenarios for `letloop check`
- `checks/codex/` — compile/exec scenarios with library dependencies
- `checks/example.scm` — simple compilation smoke test
- `checks/*.sh` — shell-driven end-to-end tests of the CLI (serve, stress)

## CLI Usage

```
letloop check [--fail-fast] [DIRECTORY ...] LIBRARY.SCM ...
letloop compile [DIRECTORY ...] LIBRARY.SCM PROCEDURE
letloop exec [DIRECTORY ...] LIBRARY.SCM PROCEDURE [-- ARGUMENT ...]
letloop repl
letloop root available
letloop root create DISTRIBUTION VERSION MACHINE DIRECTORY
letloop root exec DIRECTORY TARGET-DIRECTORY -- COMMAND ...
```

Key flags: `--dev` (debug/profile), `--optimize-level=0-3`, `--disable-garbage-collector`, `--visible-libraries` (do not amalgamate).

## Environment

The `venv` script sets up `LETLOOP_ROOT`, `SCHEME`, and `LD_LIBRARY_PATH`. Its signature is `./venv [PREFIX] [COMMAND ...]`:

- `./venv` — enters a shell with these set, `LETLOOP_PREFIX` defaulting to `$(pwd)/local`.
- `./venv $(pwd)/local/ COMMAND ...` — runs a single command in that environment.

**The first argument is always `LETLOOP_PREFIX`, and it must be an absolute path** — it is consumed and shifted before the rest is exec'd. There is no one-argument "just run this command" form: `./venv make letloop` sets `LETLOOP_PREFIX=make`, creates a stray `./make/bin/`, and then execs `letloop` with no arguments.

Environment variables: `LETLOOP_DEBUG`, `LETLOOP_DEBUG_ROOT`, `SCHEME`, `LD_LIBRARY_PATH`, `LETLOOP_ROOT`, `LETLOOP_PREFIX`.
