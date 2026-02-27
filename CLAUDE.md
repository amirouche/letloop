# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

**binink** is a Scheme compiler and runtime built on Chez Scheme. It compiles R6RS Scheme libraries into standalone executables and provides a testing framework, REPL, and execution environment.

Main branch for PRs: `dev`

## Build Commands

**Critical:** Always run `make` inside the `./venv` environment. The `makefile` auto-detects `SCHEME=$(shell which scheme)`, which picks up the system Chez (e.g. 9.5.8) instead of the local 10.x build. Running outside `./venv` causes `Exception: attempt to reference unbound identifier scheme-pre-release`.

**First-time setup** (builds ChezScheme from source, ~5–15 min):
```bash
./venv               # enters a shell with SCHEME, BININK_ROOT, LD_LIBRARY_PATH set
make chezscheme
make binink
mv a.out local/bin/binink
make check
```

**Rebuild binink after changes:**
```bash
make binink          # must be inside ./venv shell, or: ./venv make binink
mv a.out local/bin/binink
```

**Run all tests:**
```bash
make check
```

**Run a single test manually:**
```bash
$BININK check checks/check/ checks/check/check-success.scm
$BININK exec checks/ checks/codex/base.scm codex-usage
```

**Find in-progress items:**
```bash
make todo   # find TODO comments
make xxx    # find XXX comments
```

**Clean temp files:** `make clean` (removes `/tmp/binink/`)

## Claude Code Skills

Prefer these skills for common workflows:
- `/binink-full-setup` — complete setup from scratch
- `/binink-build` — rebuild binink
- `/binink-install` — build and install to `local/bin`
- `/binink-test` — run full test suite
- `/binink-build-chez` — rebuild ChezScheme only
- `/binink-clean` — clean `/tmp/binink/`

## Architecture

```
src/binink-program.c        C host — registers Chez boot files, calls Sscheme_start()
src/binink/base.scm         Main entry point: binink-main, binink-compile, binink-exec,
                            binink-repl, binink-check — handles CLI dispatch, library
                            discovery, and compilation
src/binink/cli/base.scm     Argument parser — cli-read / cli-write, parses flags,
                            positional args, and extra args (after --)
src/binink/root/base.scm    Isolated execution environments (container-like sandboxes)
src/binink/r999.scm         define-record-type* macro (extended record types)
src/binink/sq.scm           Priority queue (sq-new, sq-add!, sq-min, sq-split)
src/binink/match.scm        Pattern matching (SRFI 241)
src/binink/http.scm         HTTP request/response handling
src/binink/html/            HTML parsing (htmlprag + utilities)
src/binink/generator.scm    Generators/coroutines
src/binink/sxpath.scm       XML/XPath queries (SXPath)
src/binink/environment.scm  Environment variables (SRFI-98)
src/binink/www.scm          Web utilities
src/binink/cffi.scm         C FFI bindings
```

**Build output:** `make binink` compiles `src/binink/base.scm` with whole-program optimization, producing `a.out` (and intermediate `.so`/`.wpo` files, which are git-ignored).

**Runtime boot loading order** (relevant when debugging standalone binaries):
1. `petite.boot`
2. `scheme.boot`
3. `binink.boot` (if present)
4. `program.boot`

## Testing Framework

Test files use the `binink check` subcommand. Procedures prefixed `~check-` are test cases; `~benchmark-` are benchmarks. The test runner validates output via MD5 hash comparison.

Test sources live in `checks/`:
- `checks/check/*.scm` — success/failure/error/edge-case scenarios
- `checks/codex/` — integration tests with library dependencies
- `checks/example.scm` — simple compilation smoke test

## CLI Usage

```
binink check [--fail-fast] [DIRECTORY ...] LIBRARY.SCM ...
binink compile [DIRECTORY ...] LIBRARY.SCM PROCEDURE
binink exec [DIRECTORY ...] LIBRARY.SCM PROCEDURE [-- ARGUMENT ...]
binink repl
binink root available
binink root create DISTRIBUTION VERSION MACHINE DIRECTORY
binink root exec DIRECTORY TARGET-DIRECTORY -- COMMAND ...
```

Key flags: `--dev` (debug/profile), `--optimize-level=0-3`, `--disable-garbage-collector`.

## Environment

The `venv` script sets up `BININK_ROOT`, `SCHEME`, and `LD_LIBRARY_PATH`. Run `./venv` to enter a shell with these set, or `./venv COMMAND` to run a single command in that environment.

Environment variables: `BININK_DEBUG`, `BININK_DEBUG_ROOT`, `SCHEME`, `LD_LIBRARY_PATH`, `BININK_ROOT`, `BININK_PREFIX`.

## Known Chez Scheme Limitation

Documented in `binink-issue.md`: compiled libraries that `import` each other across boot-file boundaries can fail with "requires a different compilation instance". Workaround: use `include` instead of `import` for interdependent libraries within the same compilation unit.

`src/binink/base.scm` uses compile-time macros (`include-scheme-version`, `include-git-branch`, etc.) that call `scheme-pre-release` and `run/output` at macro-expansion time. These only work with Chez 10.x — another reason to always build inside `./venv`.
