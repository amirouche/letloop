#!chezscheme
(library (letloop store hash)

  (export directory-manifest
          store-hash-directory
          bytevector->hex-string
          shell-single-quote
          system!

          ~check-hash-000
          ~check-hash-001
          ~check-hash-002
          ~check-hash-003)

  (import (chezscheme)
          (letloop blake3))

  (begin
    (include "letloop/store/hash.body.scm")
    (include "letloop/store/hash.check.scm")))
