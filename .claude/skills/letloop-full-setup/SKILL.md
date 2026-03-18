---
name: letloop-full-setup
description: Complete letloop setup from scratch (build ChezScheme, build letloop, install, test)
---

Run the complete letloop setup workflow from scratch. Use this for initial setup or clean rebuild.

**What it does:**
1. Sets up virtual environment (`./venv`)
2. Builds ChezScheme from source (5-15 minutes)
3. Builds letloop binary
4. Installs to `local/bin/letloop`
5. Runs complete test suite

**Command:**
```bash
./venv && make chezscheme && make letloop && mv a.out local/bin/letloop && make check
```

Run complete setup workflow.

**Time:** 5-20 minutes depending on system

**Requirements:**
- Git
- C compiler
- Build tools
- Development libraries: zlib-dev, lz4-dev, uuid-dev

**Steps executed:**
1. `./venv` - Setup environment
2. `make chezscheme` - Build ChezScheme
3. `make letloop` - Build letloop
4. `mv a.out local/bin/letloop` - Install
5. `make check` - Run tests

**Output:** Fully installed and tested letloop at `local/bin/letloop`

**Note:** This is for setting up letloop development environment, not for projects using letloop.
