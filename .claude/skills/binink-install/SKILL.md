---
name: binink-install
description: Build binink and install it to local/bin in one step
---

Build the binink binary and install it to `local/bin/binink` for local development use.

**What it does:**
1. Runs `make binink` to compile from source
2. Moves `a.out` to `local/bin/binink`
3. Makes binink available for testing

**Command:**
```bash
make binink && mv a.out local/bin/binink
```

Build and install binink to local/bin.

**Prerequisites:** ChezScheme must be built first (use `/binink-build-chez`)

**Output:** Binink installed at `local/bin/binink`

**After installation:**
- Run tests: `/binink-test`
- Use it: `./local/bin/binink repl`
- Add to PATH: `export PATH="$(pwd)/local/bin:$PATH"`

**Note:** This skill is for installing binink itself during development, not for projects using binink.
