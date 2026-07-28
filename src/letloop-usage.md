Usage:

  Note: letloop is the Chez Scheme executable under another name, so
  Chez's C main would otherwise read --help, --version, --optimize-level,
  --libdirs and a dozen more before letloop saw them -- at any position,
  not just the first. bin/letloop is a wrapper that inserts `--` to end
  that parsing. Two ways around it remain: invoking the binary under
  lib/ directly, and running a boot file from `letloop compile
  --boot=PATH`; pass `--` yourself there. Programs built by `letloop
  compile` are unaffected, they carry their own C main.

  letloop help
  letloop version
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

  --boot=PATH Write a boot file to PATH instead of an executable, which
              needs no C compiler. Chez starts the boot file that goes by
              the name of the executable, so a copy or hardlink of the
              scheme binary named PATH without its extension, beside
              PATH, petite.boot and scheme.boot, is the whole program.
              This is how letloop itself is built and installed.

By default `letloop compile` amalgamates: the program and every library
it imports become a single compilation unit, so that calls across
library boundaries can be inlined. Folding a library into a program
also makes it invisible, so a program that imports a library by name at
run time needs --visible-libraries.

Amalgamating a (letloop ...) library needs the .wpo file that ships
beside letloop's own sources, because a boot image carries none. When
one is missing, letloop names the libraries it could not fold rather
than quietly producing a slower binary.
