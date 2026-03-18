# Claude Code Skills for Letloop

This directory contains project-local Claude Code skills for letloop development. These skills provide convenient shortcuts for common build, test, and development workflows.

## Available Skills

### Build & Installation

#### `/letloop-build-chez`
Build ChezScheme from source (required before building letloop).

**What it does:**
- Clones ChezScheme from GitHub
- Configures and compiles with parallel make
- Installs to `local/`

**When to use:** First-time setup or after cleaning ChezScheme

**Time:** 5-15 minutes

---

#### `/letloop-build`
Build the letloop binary from source.

**What it does:**
- Compiles `src/letloop/base.scm` with whole-program optimization
- Generates `.so` and `.wpo` files
- Creates `a.out` executable

**Prerequisites:** ChezScheme must be built first

**Output:** `a.out` in project root

---

#### `/letloop-install`
Build and install letloop to `local/bin` in one step.

**What it does:**
- Runs `make letloop`
- Moves `a.out` to `local/bin/letloop`

**After installation:**
```bash
./local/bin/letloop repl              # Start REPL
export PATH="$(pwd)/local/bin:$PATH" # Add to PATH
```

---

#### `/letloop-full-setup`
Complete setup workflow from scratch.

**What it does:**
1. Setup virtual environment (`./venv`)
2. Build ChezScheme (5-15 minutes)
3. Build letloop binary
4. Install to `local/bin/letloop`
5. Run complete test suite

**When to use:**
- Initial setup on a new machine
- After major cleanup
- Verifying a clean build

**Time:** 5-20 minutes depending on system

**Requirements:**
- Git
- C compiler (gcc/clang)
- Build tools (make, etc.)
- Development libraries: zlib-dev, lz4-dev, uuid-dev

---

### Testing & Cleanup

#### `/letloop-test`
Run the complete letloop test suite.

**What it tests:**
- REPL functionality
- Check command (errors, failures, success)
- Compile command (library to executable)
- Exec command (run procedures)
- Library embedding and dependencies
- Output validation (MD5 hashes)

**Test files:**
- `checks/check/*.scm` - Check command tests
- `checks/example.scm` - Simple compilation test
- `checks/codex/` - Complex library tests

**Exit codes:**
- 0: All tests passed ✓
- Non-zero: One or more tests failed ✗

---

#### `/letloop-clean`
Clean temporary letloop files.

**What it does:**
- Removes `/tmp/letloop/` directory and all temporary files

**Use cases:**
- Free up disk space
- Clear stale temporary files
- Clean slate for testing

**Safe:** Only removes files in `/tmp/letloop/`, not source code or compiled binaries.

---

## Usage

### Slash Command Syntax

Invoke skills directly with slash commands:

```
/letloop-test
/letloop-build
/letloop-install
```

### Natural Language

Or use natural language requests:

```
"Run the tests"
"Build letloop"
"Set up letloop from scratch"
```

Claude Code will automatically invoke the appropriate skill based on your request.

---

## Common Workflows

### First-Time Setup

```
/letloop-full-setup
```

This runs the complete workflow: venv → ChezScheme → letloop → install → test

### Development Cycle

1. Make code changes
2. `/letloop-install` - Rebuild and install
3. `/letloop-test` - Verify tests pass

### After Pulling Changes

```
/letloop-install
/letloop-test
```

Rebuild and verify everything works with the latest changes.

### Troubleshooting Build Issues

```
/letloop-clean         # Clean temporary files
/letloop-build-chez    # Rebuild ChezScheme if needed
/letloop-install       # Rebuild letloop
/letloop-test          # Verify tests pass
```

---

## Prerequisites

All skills assume you're in the `/src/letloop` project directory. Skills will execute relative to the project root.

**System requirements:**
- **Git**: For cloning ChezScheme
- **C compiler**: gcc or clang
- **Build tools**: make, autoconf, automake
- **Development libraries**: zlib-dev, lz4-dev, uuid-dev

**Ubuntu/Debian:**
```bash
apt-get install build-essential git uuid-dev zlib1g-dev liblz4-dev
```

**Arch Linux:**
```bash
pacman -S base-devel git util-linux-libs zlib lz4
```

---

## Troubleshooting

### "ChezScheme not found"

Run `/letloop-build-chez` to build ChezScheme first.

### "Cannot find local/bin/letloop"

Run `/letloop-install` to build and install the binary.

### Test failures

1. Check that letloop is installed: `ls -lh local/bin/letloop`
2. Verify ChezScheme libraries are accessible
3. Review test output for specific failures
4. Try a clean rebuild: `/letloop-clean` then `/letloop-install`

### Build errors

1. Ensure all system dependencies are installed
2. Check that `local/` directory is writable
3. Try a clean ChezScheme rebuild: `rm -rf local/ && /letloop-build-chez`

---

## Additional Skills

This project also has 9 global skills for working with the **installed** letloop binary (not covered here):

- `/letloop-exec` - Execute Scheme procedures
- `/letloop-repl` - Start interactive REPL
- `/letloop-check` - Run tests in Scheme libraries
- `/letloop-compile` - Compile libraries to executables
- And more...

These remain global because they're generic wrappers around the letloop binary and don't depend on the project's makefile.

---

## Notes

- **Project-local vs Global**: These 6 skills are project-local because they depend on the project's makefile. The 9 binary-wrapper skills remain global.
- **Automatic Discovery**: Claude Code automatically discovers and loads skills from `.claude/skills/`
- **Priority**: Project-local skills take precedence over global skills with the same name
- **Git Tracking**: All skills are tracked in git, but `settings.local.json` is excluded via `.gitignore`
