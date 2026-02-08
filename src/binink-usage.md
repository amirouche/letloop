Usage:

  binink check [--fail-fast] [DIRECTORY ...] LIBRARY.SCM ...
  binink compile [DIRECTORY ...] LIBRARY.SCM PROCEDURE
  binink exec [DIRECTORY ...] LIBRARY.SCM PROCEDURE [-- ARGUMENT ...]
  binink repl
  binink root available
  binink root create DISTRIBUTION VERSION MACHINE DIRECTORY
  binink root exec DIRECTORY TARGET-DIRECTORY -- COMMAND ...

The following flags are available:

  --dev Generate allocation, and instruction counts, debug on
        exception, and dump profile information.

  --disable-garbage-collector Disable automatic garbage collection for
                               better performance control and predictability.
                               Warning: Memory usage will grow continuously
                               until program exit without automatic GC.

  --optimize-level=0-3 Configure optimization level, higher is less
                       safe, harder to debug, but faster
