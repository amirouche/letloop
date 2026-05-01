;; Copyright © 2019-2023 Amirouche BOUBEKKI <amirouche at hyper dev>
(library (letloop aql)

  (export make-aql
          aql?
          aql-close!
          aql-transaction?
          aql-handle?
          aql-key-maximum-size
          aql-value-maximum-size
          make-aql-transaction-variable
          aql-transaction-parameterize
          aql-begin-hook
          aql-pre-commit-hook
          aql-post-commit-hook
          aql-rollback-hook
          aql-in-transaction
          aql-approximate-keys
          aql-approximate-bytes
          aql-set!
          aql-remove!
          aql-query
          aql-keys
          aql-bytevector-next-prefix

          ~check-aql-000
          ~check-aql-001
          ~check-aql-002
          ~check-aql-003
          ~check-aql-004
          ~check-aql-005
          ~check-aql-006
          ~check-aql-007
          ~check-aql-008
          ~check-aql-009
          ~check-aql-010
          ~check-aql-011
          ~check-aql-012
          ~check-aql-013
          ~check-aql-100/random
          ~check-aql-101/random
          ~check-aql-102/random
          ~check-aql-103/random
          ~check-aql-104/random
          ~check-aql-105/random)

  (import (chezscheme)
          (letloop r999)
          (letloop hook)
          (letloop aql lbst)
          (letloop byter)
          (letloop aql shims))

  ;; Record types

  (define-record-type* <aql>
    (make-aql-base lbst key-max-length value-max-length
                   transaction-timeout transaction-max-bytes
                   begin-hook pre-commit-hook post-commit-hook rollback-hook)
    aql?
    (lbst aql-lbst aql-lbst!)
    (key-max-length aql-key-max-length)
    (value-max-length aql-value-max-length)
    (transaction-timeout aql-transaction-timeout)
    (transaction-max-bytes aql-transaction-max-bytes)
    (begin-hook aql-begin-hook)
    (pre-commit-hook aql-pre-commit-hook)
    (post-commit-hook aql-post-commit-hook)
    (rollback-hook aql-rollback-hook))

  (define-record-type* <aql-transaction>
    (make-aql-transaction aql lbst read-only? context)
    aql-transaction?
    (aql aql-transaction-aql)
    (lbst aql-transaction-lbst aql-transaction-lbst!)
    (read-only? aql-transaction-read-only?)
    (context aql-transaction-context))

  (define-record-type* <aql-error>
    (make-aql-error key)
    aql-error?
    (key aql-error-key))

  (define-record-type* <aql-cursor>
    (make-cursor transaction key value)
    aql-cursor?
    (transaction aql-cursor-transaction)
    (key aql-cursor-key aql-cursor-key!)
    (value aql-cursor-value aql-cursor-value!))

  ;; Defaults

  (define aql-key-max-length-default
    (lambda ()
      ;; taken from foundationdb
      (expt 10 3)))

  (define aql-value-max-length-default
    (lambda ()
      ;; taken from foundationdb
      (expt 10 5)))

  ;; Internal helpers

  (define handle-aql
    (lambda (handle)
      (cond
       ((aql? handle) handle)
       ((aql-transaction? handle) (aql-transaction-aql handle))
       ((aql-cursor? handle) (aql-transaction-aql
                              (aql-cursor-transaction handle))))))

  (define aql-handle?
    (lambda (object)
      (or (aql? object)
          (aql-transaction? object)
          (aql-cursor? object))))

  (define bytevector-compare
    (lambda (bytevector other)
      ;; Returns 'smaller, 'equal, or 'bigger
      (let ((end (fxmin (bytevector-length bytevector)
                        (bytevector-length other))))
        (let loop ((index 0))
          (if (fx=? end index)
              (if (fx=? (bytevector-length bytevector)
                        (bytevector-length other))
                  'equal
                  (if (fx<? (bytevector-length bytevector)
                            (bytevector-length other))
                      'smaller
                      'bigger))
              (let ((delta (fx- (bytevector-u8-ref bytevector index)
                                (bytevector-u8-ref other index))))
                (if (fxzero? delta)
                    (loop (fx+ 1 index))
                    (if (fxnegative? delta)
                        'smaller
                        'bigger))))))))

  (define generator-foreach
    (lambda (proc g)
      (let loop ()
        (let ((object (g)))
          (unless (eof-object? object)
            (proc object)
            (loop))))))

  (define (make-coroutine-generator proc)
    (define return #f)
    (define resume #f)
    (define yield (lambda (v)
                    (call/cc (lambda (r) (set! resume r) (return v)))))
    (lambda () (call/cc
                (lambda (cc) (set! return cc)
                        (if resume
                            (resume (if #f #f))
                            (begin (proc yield)
                                   (set! resume (lambda (v) (return (eof-object))))
                                   (return (eof-object))))))))

  (define generator->list
    (lambda (g)
      (let f ()
        (let ((o (g)))
          (if (eof-object? o)
              '()
              (cons o (f)))))))

  ;; Transaction machinery

  (define call-with-aql-transaction-base
    (case-lambda
     ((tx proc)
      (call-with-aql-transaction-base tx proc raise values))
     ((tx proc failure)
      (call-with-aql-transaction-base tx proc failure values))
     ((tx proc failure success)
      (hook-run (aql-begin-hook (aql-transaction-aql tx)) tx)
      (guard (ex (else (hook-run (aql-rollback-hook
                                  (aql-transaction-aql tx)) tx)
                       (failure ex)))
        (call-with-values (lambda () (proc tx))
          (lambda args
            (hook-run (aql-pre-commit-hook (aql-transaction-aql tx)) tx)
            (unless (aql-transaction-read-only? tx)
              (aql-lbst! (aql-transaction-aql tx)
                         (aql-transaction-lbst tx)))
            (hook-run (aql-post-commit-hook (aql-transaction-aql tx)) tx)
            (apply success args)))))))

  (define call-with-aql-transaction
    (lambda (aql . args)
      (apply call-with-aql-transaction-base
             (make-aql-transaction aql (aql-lbst aql) #f (make-eq-hashtable))
             args)))

  (define call-with-aql-transaction-read-only
    (lambda (aql . args)
      (apply call-with-aql-transaction-base
             (make-aql-transaction aql (aql-lbst aql) #t (make-eq-hashtable))
             args)))

  ;; Cursor operations

  (define call-with-aql-cursor
    (lambda (handle key proc)

      (define search
        (lambda (tx key proc)
          (define root (aql-transaction-lbst tx))

          (call-with-lbst root key
            (lambda (lbst position)
              (if (not position)
                  (proc #f #f)
                  (proc (make-cursor tx
                                     (lbst-key lbst)
                                     (lbst-value lbst))
                        (case position
                          ((exact) 'key-exact)
                          ((before) 'key-before)
                          ((after) 'key-after))))))))

      (cond
       ((aql? handle) (call-with-aql-transaction handle
                        (lambda (tx)
                          (search tx key proc))))
       ((aql-transaction? handle)
        (search handle key proc))
       ((aql-cursor? handle)
        (search (aql-cursor-transaction handle) key proc)))))

  (define aql-cursor-next
    (lambda (cursor)
      (define root (aql-transaction-lbst (aql-cursor-transaction cursor)))

      (call-with-lbst root (aql-cursor-key cursor)
        (lambda (lbst position)
          (if (not position)
              (begin
                (aql-cursor-key! cursor #f)
                (aql-cursor-value! cursor #f)
                #f)
              (if (eq? position 'bigger)
                  (begin
                    (aql-cursor-key! cursor (lbst-key lbst))
                    (aql-cursor-value! cursor (lbst-value lbst))
                    #t)
                  (let loop ((lbst lbst))
                    (if (not lbst)
                        (begin
                          (aql-cursor-key! cursor #f)
                          (aql-cursor-value! cursor #f)
                          #f)
                        (case (bytevector-compare (lbst-key lbst) (aql-cursor-key cursor))
                          ((smaller equal) (loop (lbst-next lbst)))
                          (else
                           (if (not lbst)
                               (begin
                                 (aql-cursor-key! cursor #f)
                                 (aql-cursor-value! cursor #f)
                                 #f)
                               (begin
                                 (aql-cursor-key! cursor (lbst-key lbst))
                                 (aql-cursor-value! cursor (lbst-value lbst))
                                 #t))))))))))))

  (define aql-cursor-previous
    (lambda (cursor)
      (define root (aql-transaction-lbst (aql-cursor-transaction cursor)))

      (call-with-lbst root (aql-cursor-key cursor)
        (lambda (lbst position)
          (if (not position)
              (begin
                (aql-cursor-key! cursor #f)
                (aql-cursor-value! cursor #f)
                #f)
              (if (eq? position 'smaller)
                  (begin
                    (aql-cursor-key! cursor (lbst-key lbst))
                    (aql-cursor-value! cursor (lbst-value lbst))
                    #t)
                  (let loop ((lbst lbst))
                    (if (not lbst)
                        (begin
                          (aql-cursor-key! cursor #f)
                          (aql-cursor-value! cursor #f)
                          #f)
                        (case (bytevector-compare (lbst-key lbst) (aql-cursor-key cursor))
                          ((bigger equal) (loop (lbst-previous lbst)))
                          (else
                           (if (not lbst)
                               (begin
                                 (aql-cursor-key! cursor #f)
                                 (aql-cursor-value! cursor #f)
                                 #f)
                               (begin
                                 (aql-cursor-key! cursor (lbst-key lbst))
                                 (aql-cursor-value! cursor (lbst-value lbst))
                                 #t))))))))))))

  (define aql-cursor-ref
    (lambda (tx key)
      (call-with-aql-cursor tx key
        (lambda (cursor position)
          (case position
            ((key-exact) (aql-cursor-value cursor))
            (else #f))))))

  ;; Query machinery

  (define aql-query-base-generator
    (lambda (tx key other offset limit iterate symbol1 symbol2)
      (make-coroutine-generator
       (lambda (yield)
         (call-with-aql-cursor
          tx key
          (lambda (cursor position)
            (when cursor

              (when (if (eq? position symbol1)
                        (iterate cursor)
                        #t)
                (let loop ((offset offset)
                           (limit limit))
                  (when (or (< 0 limit) (>= -1 limit))
                    (when (aql-cursor-key cursor)
                      (when (eq? symbol2 (bytevector-compare (aql-cursor-key cursor) other))
                        (if (< 0 offset)
                            (begin
                              (if (iterate cursor)
                                  (loop (- offset 1) limit)))
                            (begin
                              (yield (cons (aql-cursor-key cursor)
                                           (aql-cursor-value cursor)))
                              (if (iterate cursor)
                                  (loop offset (- limit 1)))))))))))))))))

  (define aql-query-base
    (case-lambda
     ((tx key) (aql-cursor-ref tx key))
     ((tx key other) (aql-query-base tx key other 0 -1))
     ((tx key other offset) (aql-query-base tx key other offset -1))
     ((tx key other offset limit)
      (case (bytevector-compare key other)
        ((smaller) (aql-query-base-generator tx key other offset limit
                                             aql-cursor-next 'key-before 'smaller))
        ((bigger) (aql-query-base-generator tx key other offset limit
                                            aql-cursor-previous 'key-after 'bigger))
        ((equal) (error 'aql "Invalid aql-query arguments" key other))))))

  ;; Public API

  (define make-aql
    (lambda ()
      (make-aql-base (make-lbst)
                      (aql-key-max-length-default)
                      (aql-value-max-length-default)
                      5 ;; timeout
                      (expt 10 9) ;; 1G
                      (make-hook 1)
                      (make-hook 1)
                      (make-hook 1)
                      (make-hook 1))))

  (define aql-close!
    (lambda (aql)
      #t))

  (define aql-key-maximum-size aql-key-max-length)

  (define aql-value-maximum-size aql-value-max-length)

  (define aql-in-transaction call-with-aql-transaction)

  (define aql-approximate-keys
    (lambda (handle)
      (lbst-length (aql-lbst (handle-aql handle)))))

  (define aql-approximate-bytes
    (lambda (handle)
      (lbst-bytes (aql-lbst (handle-aql handle)))))

  (define aql-set!
    (lambda (handle key value)
      (cond
       ((aql? handle) (call-with-aql-transaction handle
                        (lambda (tx)
                          (aql-set! tx key value))))
       ((aql-transaction? handle)
        (when (aql-transaction-read-only? handle)
          (raise (make-aql-error 'readonly)))
        (aql-transaction-lbst! handle
                                (lbst-set
                                 (aql-transaction-lbst handle) key value)))
       ((aql-cursor? handle)
        (aql-set! (aql-cursor-transaction handle) key value)))))

  (define aql-remove!
    (case-lambda
     ((handle key)
      (cond
       ((aql? handle)
        (call-with-aql-transaction handle (lambda (tx) (aql-remove! tx key))))
       ((aql-transaction? handle)
        (aql-transaction-lbst! handle
                                (lbst-delete
                                 (aql-transaction-lbst handle) key)))
       ((aql-cursor? handle) (aql-remove! (aql-cursor-transaction handle) key))))
     ((handle key other)
      ;; this works because there is a single writer
      (cond
       ((aql? handle)
        (call-with-aql-transaction handle (lambda (tx) (aql-remove! tx key other))))
       ((aql-transaction? handle)
        (for-each (lambda (x) (aql-remove! handle (car x)))
                  (aql-query handle key other)))))))

  (define aql-query
    (lambda (handle . args)
      (cond
       ((aql? handle)
        (call-with-aql-transaction handle
          (lambda (tx)
            (define out (apply aql-query-base tx args))
            (if (null? (cdr args))
                ;; it is (aql-query x key) aka. point lookup
                out
                ;; Otherwise `out` is a generator, convert to a list.
                (generator->list out)))))
       ((aql-transaction? handle)
        (let ((out (apply aql-query-base handle args)))
          (if (null? (cdr args))
              out
              (generator->list out))))
       ((aql-cursor? handle)
        (let ((out (apply aql-query-base (aql-cursor-transaction handle) args)))
          (if (null? (cdr args))
              out
              (generator->list out)))))))

  ;; New public API

  (define make-aql-transaction-variable
    (lambda (init)
      (define key (cons #f #f)) ;; unique identity
      (case-lambda
       ((tx)
        (let ((ctx (aql-transaction-context tx)))
          (if (eq-hashtable-contains? ctx key)
              (eq-hashtable-ref ctx key #f)
              init)))
       ((tx value)
        (eq-hashtable-set! (aql-transaction-context tx) key value)))))

  (define-syntax aql-transaction-parameterize
    (syntax-rules ()
      ((_ tx ((var val) ...) body ...)
       (let ((saved-var (var tx)) ...)
         (var tx val) ...
         (let-values ((results (begin body ...)))
           (var tx saved-var) ...
           (apply values results))))))

  (define aql-keys
    (lambda (handle . args)
      (cond
       ((aql? handle)
        (call-with-aql-transaction handle
          (lambda (tx)
            (apply aql-keys tx args))))
       ((aql-transaction? handle)
        (if (null? (cdr args))
            ;; point lookup: return the key if it exists
            (let ((key (car args)))
              (let ((val (aql-cursor-ref handle key)))
                (if val key #f)))
            ;; range: return list of keys
            (map car (apply aql-query handle args))))
       ((aql-cursor? handle)
        (apply aql-keys (aql-cursor-transaction handle) args)))))

  (define aql-bytevector-next-prefix byter-next-prefix)

  (include "letloop/aql/aql.check.scm")

  )
