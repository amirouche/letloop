---
name: binink-clean
description: Clean temporary binink files from /tmp/binink/
---

Remove temporary binink files to clean up disk space.

**What it does:**
- Removes `/tmp/binink/` directory and all temporary files

**Command:**
```bash
make clean
```

Clean temporary binink files.

**Use cases:**
- Free up disk space
- Clear stale temporary files
- Clean slate for testing

**Safe:** This only removes files in `/tmp/binink/`, not your source code or compiled binaries.

**Note:** Compiled `.so` and `.wpo` files in the source tree are NOT removed by this command.
