(library (check-raise)

  (export ~check-000-unhandled-raise)
  (import (chezscheme))

  (define ~check-000-unhandled-raise
    (lambda ()
      (raise 'unhandled-raise))))
