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
          ~check-hash-003
          ~check-hash-004/symlinks
          ~check-hash-005/symlink-target-matters
          ~check-hash-006/symlink-is-not-its-target)

  (import (chezscheme)
          (letloop blake3))

  (begin
    (include "letloop/store/hash.body.scm")
    (include "letloop/store/hash.check.scm")))
