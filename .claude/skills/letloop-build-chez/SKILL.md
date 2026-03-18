---
name: letloop-build-chez
description: Build ChezScheme from source (required before building letloop)
---

Clone and compile ChezScheme from source. This is required before building letloop.

**What it does:**
1. Clones ChezScheme from GitHub (shallow clone)
2. Configures with threads, without X11/curses
3. Compiles using parallel make
4. Installs to `local/`

**Command:**
```bash
./venv ./local/ make chezscheme
```

Build ChezScheme from source.

**Build time:** 5-15 minutes depending on system

**Requirements:**
- Git
- C compiler (gcc/clang)
- Build tools (make, etc.)
- Development libraries: zlib-dev, lz4-dev, uuid-dev

**Output:** ChezScheme installed to `local/`

**Next steps:** Use `/letloop-build` to build letloop itself

**Note:** This skill is for building the ChezScheme dependency for letloop development, not for general Scheme projects.
