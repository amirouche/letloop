#!chezscheme
(library (letloop package static-lib)
  (export package)
  (import (chezscheme))

  ;; Closes the loop: the bootstrap letloop compiling a Scheme program
  ;; against a C static library, using the bootstrap toolchain, inside
  ;; the bootstrap rootfs. Every part of that sentence was produced by
  ;; this chain -- the compiler that builds the archive, the ar that
  ;; packs it, the nm that lists its symbols, and the letloop that links
  ;; the whole thing into one executable.
  ;;
  ;; This is the case `letloop compile` cannot serve by copying its own
  ;; host: an archive has to be linked, so the host is recompiled from
  ;; the letloop-main.c that ships beside the libraries, together with a
  ;; generated companion registering the archive's symbols. It is also
  ;; the only case where `letloop compile` needs a C compiler at all --
  ;; which is why it belongs here, where the rootfs supplies one by
  ;; construction rather than by assumption.
  (define package
    '(derivation
     (name "bootstrap-static-lib")
     (build-environment (root (package (letloop package rootfs-final))))
     (inputs ((package (letloop package letloop))))
     (script
      "set -e\n"
      "mkdir -p /build/out /build/work\n"
      "cd /build/work\n"
      ;; a C library with nothing shared about it
      "cat > arith.c <<'EOF'\n"
      "#include <stdio.h>\n"
      "int letloop_demo_add(int a, int b) { return a + b; }\n"
      "void letloop_demo_hello(void) { printf(\"hello from a static library\\n\"); }\n"
      "EOF\n"
      "gcc -c arith.c -o arith.o\n"
      "ar rcs libarith.a arith.o\n"
      ;; a Scheme program reaching into it with no load-shared-object
      "cat > demo.scm <<'EOF'\n"
      "(library (demo)\n"
      "  (export main)\n"
      "  (import (chezscheme))\n"
      "  (define add (foreign-procedure \"letloop_demo_add\" (int int) int))\n"
      "  (define hello (foreign-procedure \"letloop_demo_hello\" () void))\n"
      "  (define (main . args)\n"
      "    (hello)\n"
      "    (display (add 20 22))\n"
      "    (newline)))\n"
      "EOF\n"
      ;; the archive is a positional argument, recognised by its suffix,
      ;; and deliberately given before the procedure name to show that
      ;; position does not matter
      "/build/inputs/bootstrap-letloop/bin/letloop compile \\\n"
      "    /build/work/ /build/work/demo.scm libarith.a main\n"
      "./a.out\n"
      "test \"$(./a.out | tail -1)\" = 42\n"
      "cp a.out /build/out/demo\n")
     (output "out"))))
