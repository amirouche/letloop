#!chezscheme
(library (letloop store)

  (export letloop-store
          store-build
          store-directory
          store-path

          ~check-store-000
          ~check-store-001/fetch-only
          ~check-store-002/derivation-input
          ~check-store-003/derivation-root
          ~check-store-004/cyclic-reference)

  (import (chezscheme)
          (letloop root)
          (letloop store derivation)
          (letloop store hash)
          (letloop store sandbox)
          (letloop store fetch)
          ;; only for ~check-store-001/fetch-only, which builds its own
          ;; expected hash from a live probe request rather than pinning
          ;; a hash that would rot
          (only (letloop www) www-request)
          (only (letloop blake3) blake3))

  (begin
    (include "letloop/store.body.scm")
    (include "letloop/store.check.scm")))
