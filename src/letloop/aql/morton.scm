;; Copyright © 2026 Amirouche A. BOUBEKKI <amirouche at hyper dev>
(library (letloop aql morton)

  (export make-morton morton? morton-dimensions morton-bits
          morton-encode morton-decode
          morton-interleave morton-deinterleave
          morton-in-box?
          morton-ranges
          morton-set! morton-remove! morton-ref
          morton-query

          ~check-morton-000
          ~check-morton-001
          ~check-morton-002
          ~check-morton-003
          ~check-morton-004
          ~check-morton-005
          ~check-morton-006
          ~check-morton-007/random
          ~check-morton-008
          ~check-morton-009)

  (import (chezscheme)
          (letloop r999)
          (letloop aql)
          (letloop aql shims)
          (letloop byter))

  (begin
    (include "letloop/aql/morton.body.scm")
    (include "letloop/aql/morton.check.scm")))
