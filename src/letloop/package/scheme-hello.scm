#!chezscheme
(library (letloop package scheme-hello)
  (export package)
  (import (chezscheme))

  ;; The core promise, on its own: a Scheme program compiled to a
  ;; standalone static binary by the store.
  ;;
  ;; bootstrap-hello proves the *toolchain* works by compiling C, and
  ;; bootstrap-static-lib proves archives can be linked in -- but neither
  ;; is this. The plain case, a .scm going in and a relocatable
  ;; executable coming out with nothing beside it, is what `letloop
  ;; store build` is for, and it deserves a gate that fails when only it
  ;; is broken.
  ;;
  ;; This is the coverage the Alpine-era store-static-hello derivation
  ;; provided. When that was retired its checks were said to be covered
  ;; by bootstrap-hello and bootstrap-static-lib; bootstrap-hello
  ;; compiles C, so that was half true.
  ;;
  ;; No archive, so `letloop compile` takes its ordinary path here: it
  ;; copies its own host and appends a boot image, invoking no C
  ;; compiler at all. The rootfs has one, and this deliberately does not
  ;; use it.
  (define package
    '(derivation
     (name "bootstrap-scheme-hello")
     (build-environment (root (package (letloop package rootfs-final))))
     (inputs ((package (letloop package letloop))))
     (script
      "set -e\n"
      "mkdir -p /build/out /build/work\n"
      "cd /build/work\n"
      "cat > hello.scm <<'EOF'\n"
      "(library (hello)\n"
      "  (export main)\n"
      "  (import (chezscheme))\n"
      "  (define (main . args)\n"
      "    (display \"hello from a scheme program the store built\")\n"
      "    (newline)))\n"
      "EOF\n"
      "/build/inputs/bootstrap-letloop/bin/letloop compile /build/work/ hello.scm main\n"
      ;; it has to run, and to need no loader to do it
      "./a.out\n"
      "test \"$(./a.out)\" = 'hello from a scheme program the store built'\n"
      "! readelf -l a.out | grep -qi interpreter\n"
      "cp a.out /build/out/hello\n")
     (output "out"))))
