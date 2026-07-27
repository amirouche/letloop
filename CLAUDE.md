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
src/letloop-program.c        C host — registers Chez boot files, calls Sscheme_start()
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

**Build output:** `make letloop` produces `letloop.boot` from `src/letloop/base.scm` and installs it, the way Chez itself ships: the `scheme` executable hardlinked under another name, which makes it load the boot file that goes by that name.

```
$PREFIX/lib/csv<version>/<machine>/letloop        hardlink to the scheme binary
$PREFIX/lib/csv<version>/<machine>/letloop.boot   amalgamated, the CLI only (678 KB)
$PREFIX/bin/letloop                               relative symlink to the above
$PREFIX/lib/letloop/src/letloop/**.scm            the sources letloop ships
$PREFIX/lib/letloop/obj/<optimize-level>/**       their .so and .wpo, per level
```

**`(letloop base)` imports nothing from letloop, on purpose.** It resolves `cli-read`, `transparent`, `letloop-root` and `letloop-review` at first use through `lazy` / `letloop-library-path!`, against the sources installed at `$PREFIX/lib/letloop`. Two reasons, and both bite hard if someone adds an import back:

- A library imported by `(letloop base)` gets folded into the amalgamated letloop program, and a folded library is **invisible** — its name then blocks *user* programs from importing that same library. `(environment '(letloop match))` fails with "attempt to import invisible library" even with the source on the path.
- Loading letloop's libraries at startup costs **36 ms**. letloop starts in 35.06 ms against a bare Chez floor of 33.04 ms; before this it was 69.6 ms.

So the shape tests in `base.scm` are plain list code rather than `(letloop match)` patterns, and every subcommand that replaces `library-directories` calls `letloop-library-path!` afterwards to put letloop's own libraries back on it.

One consequence: `(letloop base)` is itself folded, so `letloop check ./src/` skips `src/letloop/base.scm` — it exports no `~check-*`, so no test is lost.

Because `bin/letloop` is the `scheme` binary, **Chez's C `main` intercepts `--help`, `--version`, `-b`, `--boot` and `--verbose`** before any Scheme runs: `letloop --help` prints *Chez's* usage. Run `letloop` with no arguments for letloop's. This is also why the flag is spelled `--boot=PATH` and not `--boot PATH`.

The `bin/letloop` symlink has to stay *relative*, because `scheme-binarypath*` locates the boot directory through `dirname($SCHEME) + "/" + readlink($SCHEME)`.

**`letloop compile` amalgamates by default:** the program and every library it imports become one compilation unit via `compile-program` + `compile-whole-program`, so calls across library boundaries can be inlined — worth ~14% on the HTTP benchmark. Two things make that possible and are easy to break:

- It runs in a **child process** spawned as `<exe> -b petite.boot -b scheme.boot --script build.scm`. A library already defined in the process shadows its own source and is never recompiled, so no `.wpo` is written for it — and every `(letloop ...)` library arrives with the boot image. `compile-whole-program` then folds nothing and reports it only through its return value, which is why the child treats a non-empty return as fatal.
- The `.wpo` cache is **per optimize level**. Folding a level 0 cache into a level 3 program measured 401k req/s against 456k for a level 3 cache. `CACHE_LEVELS` in the makefile primes 0 and 3; any other level is built on demand.

`--visible-libraries` restores the old behaviour, and is required by a program that resolves a library name at run time with `environment` or `eval`.

**Runtime boot loading order** (relevant when debugging standalone binaries):
1. `petite.boot`
2. `scheme.boot`
3. `letloop.boot` (only with `--visible-libraries`; an amalgamated program carries no letloop boot image)
4. `program.boot`

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

Key flags: `--dev` (debug/profile), `--optimize-level=0-3`, `--disable-garbage-collector`, `--visible-libraries` (do not amalgamate), `--boot=PATH` (emit a boot file instead of an executable; needs `--visible-libraries`).

## Environment

The `venv` script sets up `LETLOOP_ROOT`, `SCHEME`, and `LD_LIBRARY_PATH`. Its signature is `./venv [PREFIX] [COMMAND ...]`:

- `./venv` — enters a shell with these set, `LETLOOP_PREFIX` defaulting to `$(pwd)/local`.
- `./venv $(pwd)/local/ COMMAND ...` — runs a single command in that environment.

**The first argument is always `LETLOOP_PREFIX`, and it must be an absolute path** — it is consumed and shifted before the rest is exec'd. There is no one-argument "just run this command" form: `./venv make letloop` sets `LETLOOP_PREFIX=make`, creates a stray `./make/bin/`, and then execs `letloop` with no arguments.

Environment variables: `LETLOOP_DEBUG`, `LETLOOP_DEBUG_ROOT`, `SCHEME`, `LD_LIBRARY_PATH`, `LETLOOP_ROOT`, `LETLOOP_PREFIX`.
