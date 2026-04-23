Usage:

  letloop check [--fail-fast] [DIRECTORY ...] LIBRARY.SCM ...
  letloop compile [DIRECTORY ...] LIBRARY.SCM PROCEDURE [-- CC-FLAGS ...]
  letloop exec [DIRECTORY ...] LIBRARY.SCM PROCEDURE [-- ARGUMENT ...]
  letloop repl
  letloop root available
  letloop root create DISTRIBUTION VERSION MACHINE DIRECTORY
  letloop root exec DIRECTORY TARGET-DIRECTORY -- COMMAND ...
  letloop desktop

The following flags are available:

  --dev Generate allocation, and instruction counts, debug on
        exception, and dump profile information.

  --disable-garbage-collector Disable automatic garbage collection for
                               better performance control and predictability.
                               Warning: Memory usage will grow continuously
                               until program exit without automatic GC.

  --optimize-level=0-3 Configure optimization level, higher is less
                       safe, harder to debug, but faster
