;; Copyright © 2026 Amirouche A. BOUBEKKI <amirouche at hyper dev>
(library (letloop asm)

  (export sexp->assembly
          assembly->address
          assembly->procedure

          ~check-asm-000
          ~check-asm-001
          ~check-asm-002
          ~check-asm-003
          ~check-asm-004
          ~check-asm-005
          ~check-asm-006
          ~check-asm-007
          ~check-asm-008)

  (import (chezscheme)
          (letloop aql shims))

  (begin
    (include "letloop/asm.body.scm")
    (include "letloop/asm.check.scm")))
