;; Copyright © 2026 Amirouche A. BOUBEKKI <amirouche at hyper dev>
(library (letloop heap)

  (export heap-new heap? heap-empty?
          heap-min heap-add! heap-pop-min!
          heap-split heap-for-each

          ~check-heap-000
          ~check-heap-001
          ~check-heap-002
          ~check-heap-003
          ~check-heap-004)

  (import (chezscheme)
          (letloop r999)
          (letloop aql shims))

  (begin
    (include "letloop/heap.body.scm")
    (include "letloop/heap.check.scm")))
