Usage:

  binink check [--fail-fast] [DIRECTORY ...] LIBRARY.SCM ...
  binink compile [DIRECTORY ...] LIBRARY.SCM PROCEDURE
  binink exec [DIRECTORY ...] LIBRARY.SCM PROCEDURE [-- ARGUMENT ...]
  binink repl

The following flags are available:

  --dev Generate allocation, and instruction counts, debug on
        exception, and dump profile information.

  --optimize-level=0-3 Configure optimization level, higher is less
                       safe, harder to debug, but faster
