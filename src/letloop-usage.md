Usage:

  letloop check [--fail-fast] [DIRECTORY ...] LIBRARY.SCM ...
  letloop compile [DIRECTORY ...] LIBRARY.SCM PROCEDURE [-- CC-FLAGS ...]
  letloop exec [DIRECTORY ...] LIBRARY.SCM PROCEDURE [-- ARGUMENT ...]
  letloop http serve [--port=PORT] [DIRECTORY ...] LIBRARY.SCM
  letloop repl
  letloop root available
  letloop root create DISTRIBUTION VERSION MACHINE DIRECTORY
  letloop root exec DIRECTORY TARGET-DIRECTORY -- COMMAND ...
  letloop review [DIRECTORY ...]

The following flags are available:

  --dev Generate allocation, and instruction counts, debug on
        exception, and dump profile information.

  --disable-garbage-collector Disable automatic garbage collection for
                               better performance control and predictability.
                               Warning: Memory usage will grow continuously
                               until program exit without automatic GC.

  --optimize-level=0-3 Configure optimization level, higher is less
                       safe, harder to debug, but faster

  --visible-libraries Compile every library as its own unit and leave
                      them importable at run time, instead of folding
                      them into the program. Slower: no call between two
                      libraries can be inlined. Required by a program
                      that resolves a library name at run time, with
                      environment or eval, and by --boot.

  --boot=PATH Write a boot file to PATH instead of an executable. This
              is how letloop itself is built. Requires
              --visible-libraries, since a boot file exists to be
              imported from.

By default `letloop compile` amalgamates: the program and every library
it imports become a single compilation unit, so that calls across
library boundaries can be inlined. Folding a library into a program
also makes it invisible, so a program that imports a library by name at
run time needs --visible-libraries.

Amalgamating a (letloop ...) library needs the .wpo file that ships
beside letloop's own sources, because a boot image carries none. When
one is missing, letloop names the libraries it could not fold rather
than quietly producing a slower binary.
