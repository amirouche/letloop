---
name: letloop-test
description: Run the complete letloop test suite
---

Run the letloop test suite to verify all functionality works correctly.

**What it tests:**
1. REPL functionality
2. Check command (errors, failures, success)
3. Compile command (library to executable)
4. Exec command (run procedures)
5. Library embedding (dependencies)
6. Output validation (MD5 hashes)

**Command:**
```bash
./venv ./local/ make check
```

Run the letloop test suite.

**Test files:**
- `checks/check/*.scm` - Check command tests
- `checks/example.scm` - Simple compilation test
- `checks/codex/` - Complex library tests

**Requirements:**
- Letloop must be installed: `local/bin/letloop`
- ChezScheme libraries in LD_LIBRARY_PATH

**Exit codes:**
- **0**: All tests passed ✓
- **Non-zero**: One or more tests failed ✗

**Note:** This tests letloop itself, not projects using letloop. For testing your Scheme projects, use `/letloop-check`.
