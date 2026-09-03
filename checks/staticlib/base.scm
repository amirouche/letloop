;; Calls into a C static library with a plain foreign-procedure: no
;; load-shared-object, no .so to find at run time. `letloop compile`
;; links the archive into the program and registers its symbols, so
;; these resolve against the binary itself.
(library (staticlib base)
  (export staticlib-usage)
  (import (chezscheme))

  (define add (foreign-procedure "letloop_check_add" (int int) int))
  (define hello (foreign-procedure "letloop_check_hello" () void))

  (define staticlib-usage
    (lambda ()
      (hello)
      (unless (= (add 20 22) 42)
        (error 'staticlib-usage "the static library returned the wrong answer"))
      (display "static library add: 42")
      (newline))))
