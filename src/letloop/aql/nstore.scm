;; Copyright © 2019-2023 Amirouche BOUBEKKI <amirouche at hyper dev>
(library (letloop aql nstore)

  (export make-nstore nstore-add! nstore-clear!
          nstore-var nstore-var? nstore-var-name
          nstore-gte nstore-gt nstore-lte nstore-lt
          nstore-morton
          nstore-ref nstore-query nstore-query*

          ~check-nstore-000
          ~check-nstore-001
          ~check-nstore-002
          ~check-nstore-003
          ~check-nstore-004
          ~check-nstore-005
          ~check-nstore-006
          ~check-nstore-007)

  (import (chezscheme)
          (letloop r999)
          (letloop aql)
          (letloop aql shims)
          (letloop aql morton)
          (letloop byter))

  (begin

    (include "letloop/aql/nstore.body.scm")
    (include "letloop/aql/nstore.check.scm")))
