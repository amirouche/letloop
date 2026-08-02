;; Copyright © 2026 Amirouche A. BOUBEKKI <amirouche at hyper dev>
(library (letloop base64)

  (export base64-encode
          base64-encode!
          base64-jit?

          ~check-base64-000
          ~check-base64-001)

  (import (chezscheme)
          (letloop asm)
          (letloop aql shims))

  (begin
    (include "letloop/base64.body.scm")
    (include "letloop/base64.check.scm")))
