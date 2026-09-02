Usage:

  letloop help
  letloop version
  letloop check [--fail-fast] [DIRECTORY ...] LIBRARY.SCM ...
  letloop compile [DIRECTORY ...] LIBRARY.SCM PROCEDURE [LIBRARY.A ...]
  letloop http serve [--port=PORT] [DIRECTORY ...] LIBRARY.SCM
  letloop repl
  letloop store build DERIVATION.scm
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
                      environment or eval.


`letloop compile` writes ./a.out, one self-contained file that needs
nothing beside it, and no C compiler unless a static library is named
below: letloop's own host binary, then a boot
image carrying the program together with petite and scheme, then a
trailer giving its length. The host reads that trailer from itself and
starts the boot from memory. ./a.out.boot is written too, as a
by-product -- the boot image on its own, which `make letloop` uses to
build the binary it ships, and which --visible-libraries folds. Only
./a.out is needed to run the program.

Because that host parses no arguments at all, a compiled program -- and
letloop itself -- receives --help, --version and every other flag
untouched. Compiling needs a real `scheme` binary for its child process,
looked up as $LETLOOP_SCHEME, then beside letloop's boot files, then on
$PATH.

A standalone argument ending in .a is a static library to link into the
program, and may appear in any position. Its symbols are then reachable
with a plain (foreign-procedure "name" ...), with no
load-shared-object and no .so to ship or find at run time -- which is
what makes such a program relocatable, and what makes it work at all on
a statically linked build, where there is no dynamic loader to ask.

That is the one case where compiling needs a C compiler: an archive has
to be linked, and no amount of copying bytes will do it. letloop then
rebuilds its host from the letloop-main.c installed beside its
libraries, against the Chez kernel.o and the named archives, having
listed their symbols with nm. The compiler is looked up as $CC, then cc,
then gcc on $PATH, and letloop says what it tried rather than quietly
dropping the archive. On musl the result is linked -static.

By default `letloop compile` amalgamates: the program and every library
it imports become a single compilation unit, so that calls across
library boundaries can be inlined. Folding a library into a program
also makes it invisible, so a program that imports a library by name at
run time needs --visible-libraries.

Amalgamating a (letloop ...) library needs the .wpo file that ships
beside letloop's own sources, because a boot image carries none. When
one is missing, letloop names the libraries it could not fold rather
than quietly producing a slower binary.
