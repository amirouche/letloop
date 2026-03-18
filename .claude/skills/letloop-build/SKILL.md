---
name: letloop-build
description: Build the letloop binary from source in the current project
---

Build the letloop binary from source by compiling `src/letloop/base.scm`.

**What it does:**
1. Compiles letloop base library with whole-program optimization (WPO)
2. Generates `.so` and `.wpo` files for all libraries
3. Creates `a.out` executable in the project root

**Command:**
```bash
./venv ./local/ make letloop
```

Build letloop from source.

**Prerequisites:**
- ChezScheme must be built first (use `/letloop-build-chez`)
- Required headers: zlib, lz4, uuid

**Output:** Creates `a.out` in project root

**Next steps:**
- Install it: `mv a.out local/bin/letloop`
- Or use `/letloop-install` to build and install in one step
- Test it: `/letloop-test`

**Note:** This skill is for building letloop itself, not for building projects that use letloop.
