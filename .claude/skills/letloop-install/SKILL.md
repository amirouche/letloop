---
name: letloop-install
description: Build letloop and install it to local/bin in one step
---

Build the letloop binary and install it to `local/bin/letloop` for local development use.

**What it does:**
1. Runs `make letloop` to compile from source
2. Moves `a.out` to `local/bin/letloop`
3. Makes letloop available for testing

**Command:**
```bash
make letloop && mv a.out local/bin/letloop
```

Build and install letloop to local/bin.

**Prerequisites:** ChezScheme must be built first (use `/letloop-build-chez`)

**Output:** Letloop installed at `local/bin/letloop`

**After installation:**
- Run tests: `/letloop-test`
- Use it: `./local/bin/letloop repl`
- Add to PATH: `export PATH="$(pwd)/local/bin:$PATH"`

**Note:** This skill is for installing letloop itself during development, not for projects using letloop.
