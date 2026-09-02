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
          ~check-store-004/cyclic-reference
          ~check-store-005/build-cache-skips-the-build
          ~check-store-006/build-cache-sees-changed-inputs
          ~check-store-007/cli-project-package)

  (import (chezscheme)
          (letloop cli base)
          (letloop store derivation)
          (letloop store hash)
          (letloop store sandbox)
          (letloop store fetch)
          ;; www-request and blake3 are only for
          ;; ~check-store-001/fetch-only, which builds its own expected
          ;; hash from a live probe request rather than pinning one that
          ;; would rot; the incremental blake3 procedures key the build
          ;; cache
          (only (letloop www) www-request)
          (letloop blake3)
          (letloop r999))

  (begin
    (include "letloop/store.body.scm")
    (include "letloop/store.check.scm")))
