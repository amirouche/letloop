#!chezscheme
(library (letloop store)

  (export letloop-store
          store-build
          store-directory
          store-path

          ~check-store-000)

  (import (chezscheme)
          (letloop root)
          (letloop store derivation)
          (letloop store hash)
          (letloop store sandbox)
          (letloop store fetch))

  (begin
    (include "letloop/store.body.scm")
    (include "letloop/store.check.scm")))
