---
name: binink-build
description: Build the binink binary from source in the current project
---

Build the binink binary from source by compiling `src/binink/base.scm`.

**What it does:**
1. Compiles binink base library with whole-program optimization (WPO)
2. Generates `.so` and `.wpo` files for all libraries
3. Creates `a.out` executable in the project root

**Command:**
```bash
make binink
```

Build binink from source.

**Prerequisites:**
- ChezScheme must be built first (use `/binink-build-chez`)
- Required headers: zlib, lz4, uuid

**Output:** Creates `a.out` in project root

**Next steps:**
- Install it: `mv a.out local/bin/binink`
- Or use `/binink-install` to build and install in one step
- Test it: `/binink-test`

**Note:** This skill is for building binink itself, not for building projects that use binink.
