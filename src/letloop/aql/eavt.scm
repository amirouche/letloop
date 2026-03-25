(library (letloop aql eavt)
  (export make-eavt eavt-add! eavt-query eavt-query-at)
  (import (chezscheme)
          (letloop r999)
          (letloop aql)
          (letloop byter)
          (letloop aql nstore))

  (include "letloop/aql/eavt.body.scm"))
