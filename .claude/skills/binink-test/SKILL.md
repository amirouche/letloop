---
name: binink-test
description: Run the complete binink test suite
---

Run the binink test suite to verify all functionality works correctly.

**What it tests:**
1. REPL functionality
2. Check command (errors, failures, success)
3. Compile command (library to executable)
4. Exec command (run procedures)
5. Library embedding (dependencies)
6. Output validation (MD5 hashes)

**Command:**
```bash
make check
```

Run the binink test suite.

**Test files:**
- `checks/check/*.scm` - Check command tests
- `checks/example.scm` - Simple compilation test
- `checks/codex/` - Complex library tests

**Requirements:**
- Binink must be installed: `local/bin/binink`
- ChezScheme libraries in LD_LIBRARY_PATH

**Exit codes:**
- **0**: All tests passed ✓
- **Non-zero**: One or more tests failed ✗

**Note:** This tests binink itself, not projects using binink. For testing your Scheme projects, use `/binink-check`.
