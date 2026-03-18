---
name: letloop-clean
description: Clean temporary letloop files from /tmp/letloop/
---

Remove temporary letloop files to clean up disk space.

**What it does:**
- Removes `/tmp/letloop/` directory and all temporary files

**Command:**
```bash
./venv ./local/ make clean
```

Clean temporary letloop files.

**Use cases:**
- Free up disk space
- Clear stale temporary files
- Clean slate for testing

**Safe:** This only removes files in `/tmp/letloop/`, not your source code or compiled binaries.

**Note:** Compiled `.so` and `.wpo` files in the source tree are NOT removed by this command.
