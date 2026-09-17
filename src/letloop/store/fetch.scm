#!chezscheme
(library (letloop store fetch)

  (export fetch-verify!
          fetch-downloader
          fetch-with-curl

          ~check-fetch-000
          ~check-fetch-001
          ~check-fetch-002/curl)

  (import (chezscheme)
          (letloop www)
          ;; Directly, not the dispatching (letloop blake3): see
          ;; (letloop store hash)'s own import for why.
          (letloop blake3 scheme)
          (letloop store hash))

  (begin
    (include "letloop/store/fetch.body.scm")
    (include "letloop/store/fetch.check.scm")))
