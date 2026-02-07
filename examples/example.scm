(library (example)
  (export main)
  (import (chezscheme) (binink match))

  (define pk
    (lambda args
      (write args)(newline)
      (car (reverse args))))
  
  (define main
    (lambda args
      (match 42
        (42 (pk 'ok args))
        (else (pk 'nok))))))
