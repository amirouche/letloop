#!chezscheme
;; Standalone entry point for the benchmark suite: compile with
;;
;;   letloop compile ./examples ./benchmarks/scheme ./benchmarks/scheme/bench-server.scm main
;;
;; The resulting binary serves examples/my-web-library.scm routes on
;; the port given as first argument (default 8080), matching what
;; bench.sh expects: bin/scheme-pico-server PORT
(library (bench-server)

  (export main)

  (import (chezscheme)
          (letloop http server)
          (my-web-library))

  (define main
    (lambda args
      (let ((port (if (null? args)
                      8080
                      (string->number (car args)))))
        (transparent port application context dispatch)))))
