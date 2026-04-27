# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

**letloop** is a Scheme compiler and runtime built on Chez Scheme. It compiles R6RS Scheme libraries into standalone executables and provides a testing framework, REPL, and execution environment.

Main branch for PRs: `dev`

## Build Commands

**Critical:** Always run `make` inside the `./venv` environment. The `makefile` auto-detects `SCHEME=$(shell which scheme)`, which picks up the system Chez (e.g. 9.5.8) instead of the local 10.x build. Running outside `./venv` causes `Exception: attempt to reference unbound identifier scheme-pre-release`.

**First-time setup** (builds ChezScheme from source, ~5–15 min):
```bash
./venv               # enters a shell with SCHEME, LETLOOP_ROOT, LD_LIBRARY_PATH set
make chezscheme
make letloop
mv a.out local/bin/letloop
make check
```

**Rebuild letloop after changes:**
```bash
make letloop          # must be inside ./venv shell, or: ./venv make letloop
mv a.out local/bin/letloop
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

**Build output:** `make letloop` compiles `src/letloop/base.scm` with whole-program optimization, producing `a.out` (and intermediate `.so`/`.wpo` files, which are git-ignored).

**Runtime boot loading order** (relevant when debugging standalone binaries):
1. `petite.boot`
2. `scheme.boot`
3. `letloop.boot` (if present)
4. `program.boot`

## Testing Framework

Test files use the `letloop check` subcommand. Procedures prefixed `~check-` are test cases; `~benchmark-` are benchmarks. The test runner validates output via MD5 hash comparison.

Test sources live in `checks/`:
- `checks/check/*.scm` — success/failure/error/edge-case scenarios
- `checks/codex/` — integration tests with library dependencies
- `checks/example.scm` — simple compilation smoke test

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

Key flags: `--dev` (debug/profile), `--optimize-level=0-3`, `--disable-garbage-collector`.

## Environment

The `venv` script sets up `LETLOOP_ROOT`, `SCHEME`, and `LD_LIBRARY_PATH`. Run `./venv` to enter a shell with these set, or `./venv COMMAND` to run a single command in that environment.

Environment variables: `LETLOOP_DEBUG`, `LETLOOP_DEBUG_ROOT`, `SCHEME`, `LD_LIBRARY_PATH`, `LETLOOP_ROOT`, `LETLOOP_PREFIX`.
