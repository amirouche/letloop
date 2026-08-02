;; Copyright © 2026 Amirouche A. BOUBEKKI <amirouche at hyper dev>
(library (letloop kernel)

  (export kernel
          kernel-compile
          kernel-source

          ~check-kernel-000
          ~check-kernel-001
          ~check-kernel-002
          ~check-kernel-003)

  (import (chezscheme)
          (letloop asm))

  (begin
    (include "letloop/kernel.body.scm")
    (include "letloop/kernel.check.scm")))
