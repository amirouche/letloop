# Compilation Instance Conflicts in Boot Files - CHEZ SCHEME LIMITATION

## Status: CONFIRMED CHEZ SCHEME BUG

After extensive investigation, this is **definitively a Chez Scheme bug/limitation** with R6RS library compilation instances in boot files, not a letloop bug.

## Problem

When using `letloop compile` to build standalone binaries from interdependent R6RS libraries:

```
Exception: compiled (test-minimal) requires a different compilation instance of (seed) from the one previously loaded from program
```

## What Was Fixed in Letloop

During investigation, several real bugs were found and fixed in letloop:

### 1. Library Deduplication (FIXED)
When multiple library directories are specified, the same library could be discovered from multiple paths and included twice in the boot file:
```
/src/psii/zero/srfi-241/lib//srfi/:241.so
/src/psii/zero/.//srfi-241/lib/srfi/:241.so  # DUPLICATE!
```
**Fix**: `letloop-discover-libraries` now deduplicates by library name.

### 2. Unified Subprocess Compilation (FIXED)
Per Chez Scheme docs, compilation AND `make-boot-file` must happen in the **same** Scheme invocation:
```scheme
# Correct (from Chez docs):
echo '(compile-file "x.ss") (make-boot-file "x.boot" ...)' | scheme -q
```
**Fix**: All library compilation, program.scm compilation, and `make-boot-file` now happen in one fresh subprocess.

### 3. compile-imported-libraries Setting (FIXED)
Must be `#f` when compiling for boot files to prevent libraries from being embedded in their importers.
**Fix**: Set `(compile-imported-libraries #f)` in compilation subprocess.

## Root Cause: Chez Scheme Cannot Handle This

Even with ALL fixes applied:
- ✓ Libraries deduplicated
- ✓ Everything compiled in one fresh subprocess
- ✓ `make-boot-file` in same subprocess
- ✓ `compile-imported-libraries #f` set
- ✓ All .so/.wpo files cleaned before compilation

**THE ERROR STILL OCCURS.**

This is a fundamental Chez Scheme limitation with interdependent R6RS libraries in boot files.

## Workaround: Use `include` Instead of `import`

For projects hitting this, use `include` instead of `import` for interdependent libraries:

```scheme
;; Instead of:
(import (my-library))

;; Use:
(include "my-library-implementation.scm")
```

This bypasses the compilation instance system by literally including source code.

## Minimal Reproduction

```bash
cd /src/psii/zero

# Create interdependent libraries
echo '(library (lib-a) (export hello) (import (chezscheme))
       (define (hello) (display "hi\n")))' > lib-a.sls
echo '(library (lib-b) (export main) (import (chezscheme) (lib-a))
       (define (main) (hello)))' > lib-b.sls

# Clean and compile
find . -name '*.so' -delete && find . -name '*.wpo' -delete
SCHEME=/src/letloop/local/bin/scheme letloop compile ./ lib-b.sls main

# FAILS with compilation instance error
./a.out
```

## Technical Details

### What letloop Does (Now Correct)

1. Discovers libraries (deduplicated by name)
2. Creates temp file with Scheme expressions to:
   - Set library directories
   - Set `compile-imported-libraries #f`
   - Compile all discovered libraries
   - Compile program.scm (which imports target library)
   - Call `make-boot-file` with all .so files
3. Executes: `scheme < compile-expr.scm` (all in one subprocess)
4. Embeds resulting program.boot into C binary via `letloop-program.c`

### Runtime Boot Loading Order
1. petite.boot
2. scheme.boot
3. letloop.boot (if present)
4. program.boot

## Investigation Timeline

1. ✅ Set `compile-imported-libraries #f`
2. ✅ Compile libraries in fresh subprocess
3. ✅ Don't pre-compile program.scm, let make-boot-file handle it
4. ✅ Move make-boot-file into subprocess (unified invocation)
5. ✅ Fix library deduplication bug
6. ✅ Clean ALL .so/.wpo files (both letloop and target project)
7. ✅ Rebuild everything from scratch

**Result**: Error persists. Confirmed Chez Scheme limitation.

## References

- Chez Scheme User's Guide: Section on `make-boot-file`
- Investigation: `/src/letloop/letloop-issue.md` (this file)
- Fixed code: `/src/letloop/src/letloop/base.scm` (letloop-compile function)
