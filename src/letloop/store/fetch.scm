#!chezscheme
(library (letloop store fetch)

  (export fetch-verify!

          ~check-fetch-000
          ~check-fetch-001)

  (import (chezscheme)
          (letloop www)
          (letloop blake3)
          (letloop store hash))

  (begin
    (include "letloop/store/fetch.body.scm")
    (include "letloop/store/fetch.check.scm")))
