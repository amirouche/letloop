(library (letloop aql xz)

  (export make-xzstore xzstore? xzstore-ndims xzstore-g
          xzstore-index xzstore-ranges
          xzstore-set! xzstore-remove! xzstore-ref xzstore-query

          ~check-xz-000
          ~check-xz-001
          ~check-xz-002
          ~check-xz-003
          ~check-xz-004
          ~check-xz-005
          ~check-xz-006
          ~check-xz-007/random)

  (import (chezscheme)
          (letloop r999)
          (letloop aql)
          (letloop aql shims)
          (letloop byter))

  (begin
    (include "letloop/aql/xz.body.scm")
    (include "letloop/aql/xz.check.scm")))
