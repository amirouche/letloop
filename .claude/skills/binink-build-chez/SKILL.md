---
name: binink-build-chez
description: Build ChezScheme from source (required before building binink)
---

Clone and compile ChezScheme from source. This is required before building binink.

**What it does:**
1. Clones ChezScheme from GitHub (shallow clone)
2. Configures with threads, without X11/curses
3. Compiles using parallel make
4. Installs to `local/`

**Command:**
```bash
./venv && make chezscheme
```

Build ChezScheme from source.

**Build time:** 5-15 minutes depending on system

**Requirements:**
- Git
- C compiler (gcc/clang)
- Build tools (make, etc.)
- Development libraries: zlib-dev, lz4-dev, uuid-dev

**Output:** ChezScheme installed to `local/`

**Next steps:** Use `/binink-build` to build binink itself

**Note:** This skill is for building the ChezScheme dependency for binink development, not for general Scheme projects.
