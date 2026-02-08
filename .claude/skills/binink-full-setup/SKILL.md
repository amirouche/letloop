---
name: binink-full-setup
description: Complete binink setup from scratch (build ChezScheme, build binink, install, test)
---

Run the complete binink setup workflow from scratch. Use this for initial setup or clean rebuild.

**What it does:**
1. Sets up virtual environment (`./venv`)
2. Builds ChezScheme from source (5-15 minutes)
3. Builds binink binary
4. Installs to `local/bin/binink`
5. Runs complete test suite

**Command:**
```bash
./venv && make chezscheme && make binink && mv a.out local/bin/binink && make check
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
3. `make binink` - Build binink
4. `mv a.out local/bin/binink` - Install
5. `make check` - Run tests

**Output:** Fully installed and tested binink at `local/bin/binink`

**Note:** This is for setting up binink development environment, not for projects using binink.
