#!chezscheme
(library (transparent-legacy)

  (export transparent json html xml match)

  (import (chezscheme))

  ;; ============================================================
  ;; Section 1: define-record-type* (from letloop r999)
  ;; ============================================================

  (define-syntax define-record-type*
    (lambda (stx)
      (syntax-case stx ()
        ((_ <type>
            uid
            (constructor constructor-tag ...)
            predicate?
            (field-tag accessor setter ...) ...)

         (and (for-all identifier?
                       #'(<type> constructor constructor-tag ... predicate?
                                 field-tag ... accessor ... setter ... ...))
              (for-all (lambda (s) (<= 0 (length s) 1))
                       #'((setter ...) ...))
              (for-all (lambda (ct)
                         (memp (lambda (ft) (bound-identifier=? ct ft))
                               #'(field-tag ...)))
                       #'(constructor-tag ...)))
         (with-syntax (((field-clause ...)
                        (map (lambda (clause)
                               (if (= 2 (length clause))
                                   #`(immutable . #,clause)
                                   #`(mutable . #,clause)))
                             #'((field-tag accessor setter ...) ...)))
                       ((unspec-tag ...)
                        (remp (lambda (ft)
                                (memp (lambda (ct) (bound-identifier=? ft ct))
                                      #'(constructor-tag ...)))
                              #'(field-tag ...))))
                      #'(define-record-type (<type> constructor predicate?)
                          (nongenerative uid)
                          (protocol (lambda (ctor)
                                      (lambda (constructor-tag ...)
                                        (define unspec-tag) ...
                                        (ctor field-tag ...))))
                          (fields field-clause ...))))

        ((_ <type> (constructor constructor-tag ...)
            predicate?
            (field-tag accessor setter ...) ...)

         (and (for-all identifier?
                       #'(<type> constructor constructor-tag ... predicate?
                                 field-tag ... accessor ... setter ... ...))
              (for-all (lambda (s) (<= 0 (length s) 1))
                       #'((setter ...) ...))
              (for-all (lambda (ct)
                         (memp (lambda (ft) (bound-identifier=? ct ft))
                               #'(field-tag ...)))
                       #'(constructor-tag ...)))
         (with-syntax (((field-clause ...)
                        (map (lambda (clause)
                               (if (= 2 (length clause))
                                   #`(immutable . #,clause)
                                   #`(mutable . #,clause)))
                             #'((field-tag accessor setter ...) ...)))
                       ((unspec-tag ...)
                        (remp (lambda (ft)
                                (memp (lambda (ct) (bound-identifier=? ft ct))
                                      #'(constructor-tag ...)))
                              #'(field-tag ...))))
                      #'(define-record-type (<type> constructor predicate?)
                          (nongenerative <type>)
                          (protocol (lambda (ctor)
                                      (lambda (constructor-tag ...)
                                        (define unspec-tag) ...
                                        (ctor field-tag ...))))
                          (fields field-clause ...)))))))

  ;; ============================================================
  ;; Section 2: FFI helpers (from letloop cffi)
  ;; ============================================================

  (define stdlib (load-shared-object #f))

  (define-syntax with-lock
    (syntax-rules ()
      ((_ objects body ...)
       (let ((objects* objects))
         (for-each lock-object objects*)
         (call-with-values (lambda () body ...)
           (lambda out
             (for-each unlock-object objects*)
             (apply values out)))))))

  (define-syntax call-with-errno
    (syntax-rules ()
      ((_ thunk proc)
       (let ((out #f) (errno #f))
         (with-interrupts-disabled
          (set! out (thunk))
          (set! errno (#%$errno)))
         (proc out errno)))))

  (define (bytevector-pointer bv)
    (#%$object-address bv (+ (foreign-sizeof 'void*) 1)))

  (define strerror
    (let ((func (foreign-procedure "strerror" (int) string)))
      (lambda (code)
        (func code))))

  ;; ============================================================
  ;; Section 3: Priority queue (from letloop sq)
  ;; ============================================================

  (define-record-type* <sq>
    (make-sq box)
    sq?
    (box sq-unbox sq-setbox!))

  (define sq-for-each
    (lambda (sq proc)
      (for-each (lambda (kv) (proc (car kv) (cdr kv))) (sq-unbox sq))))

  (define sq-new
    (lambda ()
      (make-sq '())))

  (define sq-empty?
    (lambda (sq)
      (null? (sq-unbox sq))))

  (define sq-min
    (lambda (sq)
      (if (sq-empty? sq)
          #f
          (car (sq-unbox sq)))))

  (define sq-add!
    (lambda (sq k v)
      (define new (sort (lambda (a b) (< (car a) (car b)))
                        (cons (cons k v) (sq-unbox sq))))
      (sq-setbox! sq new)))

  (define sq-split
    (lambda (sq k)
      (let loop ((kv* (sq-unbox sq))
                 (before-or-equal '()))
        (if (null? kv*)
            (values (make-sq (reverse before-or-equal)) (make-sq '()))
            (if (<= (caar kv*) k)
                (loop (cdr kv*) (cons (car kv*) before-or-equal))
                (values (make-sq (reverse before-or-equal)) (make-sq kv*)))))))

  ;; ============================================================
  ;; Section 4: Pattern matcher - SRFI 241 (from letloop match)
  ;; ============================================================

  ;; with-implicit is provided by (chezscheme)

  (define-syntax define/who
    (lambda (x)
      (define parse
        (lambda (x)
          (syntax-case x ()
            [(k (f . u) e1 ... e2)
             (identifier? #'f)
             (values #'k #'f #'((lambda u e1 ... e2)))]
            [(k f e1 ... e2)
             (identifier? #'f)
             (values #'k #'f #'(e1 ... e2))]
            [_ (syntax-violation 'define/who "invalid syntax" x)])))
      (let-values ([(k f e*) (parse x)])
        (with-syntax ([k k] [f f] [(e1 ... e2) e*])
          (with-implicit (k who)
            #'(define f
                (let ([who 'f])
                  e1 ... e2)))))))

  (define-syntax define-syntax/who
    (lambda (x)
      (syntax-case x ()
        [(k n e1 ... e2)
         (identifier? #'n)
         (with-implicit (k who)
           #'(define-syntax n
               (let ([who 'n])
                 e1 ... e2)))])))

  (define-syntax/who define-auxiliary-syntax
    (lambda (x)
      (syntax-case x ()
        [(_ name)
         (identifier? #'name)
         #'(define-syntax/who name
             (lambda (x)
               (syntax-violation who "misplaced auxiliary keyword" x)))]
        [_ (syntax-violation who "invalid syntax" x)])))

  (define-auxiliary-syntax ->)

  (define-syntax/who match
    (define-record-type pattern-variable
      (nongenerative) (sealed #t) (opaque #t)
      (fields (mutable identifier) expression level))
    (define-record-type cata-binding
      (nongenerative) (sealed #t) (opaque #t)
      (fields proc-expr value-id* identifier))

    (define ellipsis?
      (lambda (x)
        (and (identifier? x)
             (free-identifier=? x #'(... ...)))))

    (lambda (stx)
      (define make-identifier-hashtable
        (lambda ()
          (define identifier-hash
            (lambda (id)
              (assert (identifier? id))
              (symbol-hash (syntax->datum id))))
          (make-hashtable identifier-hash bound-identifier=?)))
      (define pattern-variable-guards
        (lambda (pvars)
          (define ht (make-identifier-hashtable))
          (fold-left
           (lambda (guards pvar)
             (let ([id (pattern-variable-identifier pvar)])
               (cond
                [(hashtable-ref ht id #f)
                 (with-syntax ([id id]
                               [(new-id) (generate-temporaries #'(id))]
                               [guards guards])
                   (pattern-variable-identifier-set! pvar #'new-id)
                   #'((equal? id new-id) . guards))]
                [else
                 (hashtable-set! ht id #t)
                 guards])))
           '() pvars)))
      (define check-cata-bindings
        (lambda (catas)
          (define ht (make-identifier-hashtable))
          (for-each
           (lambda (cata)
             (for-each
              (lambda (id)
                (hashtable-update!
                 ht
                 id
                 (lambda (val)
                   (when val
                     (syntax-violation who "repeated cata variable in match clause" stx id))
                   #t)
                 #f))
              (cata-binding-value-id* cata)))
           catas)))
      (define parse-clause
        (lambda (cl)
          (syntax-case cl (guard)
            [(pat (guard guard-expr ...) e1 e2 ...)
             (values #'pat #'(and guard-expr ...) #'(e1 e2 ...))]
            [(pat e1 e2 ...)
             (values #'pat #'#t #'(e1 e2 ...))]
            [_
             (syntax-violation who "ill-formed match clause" stx cl)])))
      (define gen-matcher
        (lambda (expr pat)
          (define ill-formed-match-pattern-violation
            (lambda ()
              (syntax-violation who "ill-formed match pattern" stx pat)))
          (syntax-case pat (-> unquote)
            [,[f -> y ...]
             (for-all identifier? #'(y ...))
             (with-syntax ([(x) (generate-temporaries '(x))])
               (values
                (lambda (k)
                  (k))
                (list (make-pattern-variable #'x expr 0))
                (list (make-cata-binding #'f #'(y ...) #'x))))]
            [,[y ...]
             (for-all identifier? #'(y ...))
             (with-syntax ([(x) (generate-temporaries '(x))])
               (values
                (lambda (k)
                  (k))
                (list (make-pattern-variable #'x expr 0))
                (list (make-cata-binding #'loop #'(y ...) #'x))))]
            [(pat1 ell pat2 ... . ,e)
             (ellipsis? #'ell)
             (gen-ellipsis-matcher expr #'pat1 #'(pat2 ...) #',e)]
            [(pat1 ell pat2 ... . pat3)
             (ellipsis? #'ell)
             (gen-ellipsis-matcher expr #'pat1 #'(pat2 ...) #'pat3)]
            [#(x ...)
             (with-syntax ([(e) (generate-temporaries '(e))])
               (let-values ([(mat pvars catas)
                             (gen-matcher #'e #'(x ...))])
                 (values
                  (lambda (k)
                    #`(if (vector? #,expr)
                          (let ([e (vector->list #,expr)])
                            #,(mat k))
                          (fail)))
                  pvars catas)))]
            [,x
             (identifier? #'x)
             (values
               (lambda (k)
                 (k))
               (if (free-identifier=? #'x #'_)
                   '()
                   (list (make-pattern-variable #'x expr 0)))
               '())]
            [(pat1 . pat2)
             (with-syntax ([(e1 e2) (generate-temporaries '(e1 e2))])
               (let*-values ([(mat1 pvars1 catas1)
                              (gen-matcher #'e1 #'pat1)]
                             [(mat2 pvars2 catas2)
                              (gen-matcher #'e2 #'pat2)])
                 (values
                  (lambda (k)
                    #`(if (pair? #,expr)
                          (let ([e1 (car #,expr)]
                                [e2 (cdr #,expr)])
                            #,(mat1 (lambda () (mat2 k))))
                          (fail)))
                  (append pvars1 pvars2) (append catas1 catas2))))]
            [unquote
             (ill-formed-match-pattern-violation)]
            [_
             (values
              (lambda (k)
                #`(if (equal? #,expr (quote #,pat))
                      #,(k)
                      (fail)))
              '() '())])))
      (define gen-ellipsis-matcher
        (lambda (expr pat1 pat2* pat3)
          (with-syntax ([(e1 e2) (generate-temporaries '(e1 e2))])
            (let*-values ([(mat1 pvars1 catas1)
                           (gen-map #'e1 pat1)]
                          [(mat2 pvars2 catas2)
                           (gen-matcher* #'e2 (append pat2* pat3))])
              (values
               (lambda (k)
                 #`(split
                    #,expr
                    #,(length pat2*)
                    (lambda (e1 e2)
                      #,(mat1 (lambda () (mat2 k))))
                    fail))
               (append pvars1 pvars2)
               (append catas1 catas2))))))
      (define gen-matcher*
        (lambda (expr pat*)
          (syntax-case pat* (unquote)
            [()
             (values
              (lambda (k)
                #`(if (null? #,expr)
                      #,(k)
                      (fail)))
              '() '())]
            [,x
             (gen-matcher expr pat*)]
            [(pat . pat*)
             (with-syntax ([(e1 e2) (generate-temporaries '(e1 e2))])
               (let*-values ([(mat1 pvars1 catas1)
                              (gen-matcher #'e1 #'pat)]
                             [(mat2 pvars2 catas2)
                              (gen-matcher* #'e2 #'pat*)])
                 (values
                  (lambda (k)
                    #`(let ([e1 (car #,expr)]
                            [e2 (cdr #,expr)])
                        #,(mat1
                           (lambda ()
                             (mat2 k)))))
                  (append pvars1 pvars2)
                  (append catas1 catas2))))]
            [_
             (gen-matcher expr pat*)])))
      (define gen-map
        (lambda (expr pat)
          (with-syntax ([(e1 e2 f) (generate-temporaries '(e1 e2 f))])
            (let-values ([(mat ipvars catas)
                          (gen-matcher #'e1 pat)])
              (with-syntax ([(u ...)
                             (generate-temporaries ipvars)]
                            [(v ...)
                             (map pattern-variable-expression ipvars)])
                (values
                 (lambda (k)
                   #`(let f ([e2 (reverse #,expr)]
                             [u '()] ...)
                       (if (null? e2)
                           #,(k)
                           (let ([e1 (car e2)])
                             #,(mat (lambda ()
                                      #`(f (cdr e2) (cons v u) ...)))))))
                 (map
                  (lambda (id pvar)
                    (make-pattern-variable
                     (pattern-variable-identifier pvar)
                     id
                     (fx+ (pattern-variable-level pvar) 1)))
                  #'(u ...) ipvars)
                 catas))))))
      (define gen-map-values
        (lambda (proc-expr y* e n)
          (let f ([n n])
            (if (fxzero? n)
                #`(#,proc-expr #,e)
                (with-syntax ([(tmps ...)
                               (generate-temporaries y*)]
                              [(tmp ...)
                               (generate-temporaries y*)]
                              [e e])
                  #`(let f ([e* (reverse e)]
                            [tmps '()] ...)
                      (if (null? e*)
                          (values tmps ...)
                          (let ([e (car e*)]
                                [e* (cdr e*)])
                            (let-values ([(tmp ...)
                                          #,(f (fx- n 1))])
                              (f e* (cons tmp tmps) ...))))))))))
      (define gen-clause
        (lambda (k cl)
          (let*-values ([(pat guard-expr body)
                         (parse-clause cl)]
                        [(matcher pvars catas)
                         (gen-matcher #'e pat)])
            (define pvar-guards (pattern-variable-guards pvars))
            (check-cata-bindings catas)
            (with-syntax ([(x ...)
                           (map pattern-variable-identifier pvars)]
                          [(u ...)
                           (map pattern-variable-expression pvars)]
                          [(f ...)
                           (map cata-binding-proc-expr catas)]
                          [((y ...) ...)
                           (map cata-binding-value-id* catas)]
                          [(z ...)
                           (map cata-binding-identifier catas)]
                          [(tmp ...)
                           (generate-temporaries catas)])
              (with-syntax ([(e ...)
                             (map
                              (lambda (tmp y* z)
                                (let ([n
                                       (exists
                                        (lambda (pvar)
                                          (let ([x (pattern-variable-identifier pvar)])
                                            (and (bound-identifier=? x z)
                                                 (pattern-variable-level pvar))))
                                        pvars)])
                                  (gen-map-values tmp y* z n)))
                              #'(tmp ...) #'((y ...) ...) #'(z ...))])
                (matcher
                 (lambda ()
                   #`(let ([x u] ...)
                       (if (and #,@pvar-guards (extend-backquote #,k #,guard-expr))
                           (let ([tmp f] ...)
                             (let-values ([(y ...) e] ...)
                               (extend-backquote #,k
                                 #,@body)))
                           (fail))))))))))
      (define gen-match
        (lambda (k cl*)
          (fold-right
           (lambda (cl rest)
             #`(let ([fail (lambda () #,rest)])
                 #,(gen-clause k cl)))
           #'(assertion-violation 'match "expression does not match" e)
           cl*)))

      (syntax-case stx ()
        [(k expr cl ...)
         #`(let loop ([e expr])
             #,(gen-match #'k #'(cl ...)))])))

  (define-syntax/who extend-backquote
    (lambda (x)
      (syntax-case x ()
        [(_ here e1 ... e2)
         (identifier? #'here)
         (with-implicit (here quasiquote)
           #'(let-syntax ([quasiquote quasiquote-transformer])
               e1 ... e2))]
        [_ (syntax-violation who "invalid syntax" x)])))

  (define-syntax/who define-extended-quasiquote
    (lambda (x)
      (syntax-case x ()
        [(_ qq)
         (identifier? #'qq)
         #'(define-syntax qq quasiquote-transformer)])))

  (meta define quasiquote-transformer
    (lambda (stx)
      (define who 'quasiquote)
      (define-record-type template-variable
        (nongenerative) (sealed #t) (opaque #t)
        (fields identifier expression))

      (define ellipsis?
        (lambda (x)
          (and (identifier? x)
               (free-identifier=? x #'(... ...)))))

      (define quasiquote-syntax-violation
        (lambda (subform msg)
          (syntax-violation 'quasiquote msg stx subform)))
      (define gen-output
        (lambda (k tmpl lvl ell?)
          (define quasiquote?
            (lambda (x)
              (and (identifier? x) (free-identifier=? x k))))
          (define gen-ellipsis
            (lambda (tmpl* out* vars* depth tmpl2)
              (let f ([depth depth] [tmpl2 tmpl2])
                (syntax-case tmpl2 ()
                  [(ell . tmpl2)
                   (ell? #'ell)
                   (f (fx+ depth 1) #'tmpl2)]
                  [tmpl2
                   (let-values ([(out2 vars2)
                                 (gen-output k #'tmpl2 0 ell?)])
                     (for-each
                      (lambda (tmpl vars)
                        (when (or (not vars) (null? vars))
                          (quasiquote-syntax-violation tmpl
                            "no substitutions to repeat here")))
                      tmpl* vars*)
                     (with-syntax ([((tmp** ...) ...)
                                    (map (lambda (vars)
                                           (map template-variable-identifier vars))
                                         vars*)]
                                   [(out1 ...) out*])
                       (values #`(append (append-n-map #,depth
                                                       (lambda (tmp** ...)
                                                         out1)
                                                       tmp** ...)
                                         ...
                                         #,out2)
                               (append (apply append vars*)
                                       (or vars2 '())))))]))))
          (define gen-unquote*
            (lambda (expr*)
              (with-syntax ([(tmp* ...) (generate-temporaries expr*)])
                (values #'(tmp* ...)
                        (map (lambda (tmp expr)
                               (list (make-template-variable tmp expr)))
                             #'(tmp* ...) expr*)))))
          (syntax-case tmpl (unquote unquote-splicing)
            [(ell tmpl)
             (ell? #'ell)
             (let-values ([(out vars)
                           (gen-output k #'tmpl lvl (lambda (x) #f))])
               (values out (or vars '())))]
            [`tmpl
             (quasiquote? #'quasiquote)
             (let-values ([(out vars) (gen-output k #'tmpl (fx+ lvl 1) ell?)])
               (if (not vars)
                   (values #'`tmpl
                           #f)
                   (values #`(list 'quasiquote #,out)
                           vars)))]
            [,expr
             (fxzero? lvl)
             (with-syntax ([(tmp) (generate-temporaries '(tmp))])
               (values #'tmp (list (make-template-variable #'tmp #'expr))))]
            [,tmpl
             (let-values ([(out vars)
                           (gen-output k #'tmpl (fx- lvl 1) ell?)])
               (if (not vars)
                   (values #'(quote ,tmpl) #f)
                   (values #`(list 'unquote #,out) vars)))]
            [((unquote-splicing expr ...) ell . tmpl2)
             (and (fxzero? lvl) (ell? #'ell))
             (let-values ([(out* vars*)
                           (gen-unquote* #'(expr ...))])
               (gen-ellipsis #'(expr ...) out* vars* 1 #'tmpl2))]
            [((unquote expr ...) ell . tmpl2)
             (and (fxzero? lvl) (ell? #'ell))
             (let-values ([(out* vars*)
                           (gen-unquote* #'(expr ...))])
               (gen-ellipsis #'(expr ...) out* vars* 0 #'tmpl2))]
            [(tmpl1 ell . tmpl2)
             (and (fxzero? lvl) (ell? #'ell))
             (let-values ([(out1 vars1)
                           (gen-output k #'tmpl1 0 ell?)])
               (gen-ellipsis #'(tmpl1) (list out1) (list vars1) 0 #'tmpl2))]
            [((unquote tmpl1 ...) . tmpl2)
             (let-values ([(out vars)
                           (gen-output k #'tmpl2 lvl ell?)])
               (if (fxzero? lvl)
                   (with-syntax ([(tmp ...)
                                  (generate-temporaries #'(tmpl1 ...))])
                     (values #`(cons* tmp ... #,out)
                             (append
                              (map make-template-variable #'(tmp ...) #'(tmpl1 ...))
                              (or vars '()))))
                   (let-values ([(out* vars*)
                                 (gen-output* k #'(tmpl1 ...) (fx- lvl 1) ell?)])
                     (if (and (not vars)
                              (not vars*))
                         (values #'(quote ((unquote-splicing tmpl1 ...) . tmpl2))
                                 #f)
                         (values #`(cons (list 'unquote #,@out*) #,out)
                                 (append (or vars* '())
                                         (or vars '())))))))]
            [((unquote-splicing tmpl1 ...) . tmpl2)
             (let-values ([(out vars)
                           (gen-output k #'tmpl2 lvl ell?)])
               (if (fxzero? lvl)
                   (with-syntax ([(tmp ...)
                                  (generate-temporaries #'(tmpl1 ...))])
                     (values #`(append tmp ... #,out)
                             (append
                              (map make-template-variable #'(tmp ...) #'(tmpl1 ...))
                              (or vars '()))))
                   (let-values ([(out* vars*)
                                 (gen-output* k #'(tmpl1 ...) (fx- lvl 1) ell?)])
                     (if (and (not vars)
                              (not vars*))
                         (values #'(quote ((unquote-splicing tmpl1 ...) . tmpl2))
                                 '())
                         (values #`(cons (list 'unquote-splicing #,@out*) #,out)
                                 (append (or vars* '())
                                         (or vars '())))))))]
            [(el1 . el2)
             (let-values ([(out1 vars1)
                           (gen-output k #'el1 lvl ell?)]
                          [(out2 vars2)
                           (gen-output k #'el2 lvl ell?)])
               (if (and (not vars1)
                        (not vars2))
                   (values #'(quote (el1 . el2))
                           '())
                   (values #`(cons #,out1 #,out2)
                           (append (or vars1 '()) (or vars2 '())))))]
            [#(el ...)
             (let-values ([(out vars)
                           (gen-output k #'(el ...) lvl ell?)])
               (if (not vars)
                   (values #'(quote #(el ...)) #f)
                   (values #`(list->vector #,out) vars)))]
            [constant
             (values #'(quote constant) #f)])))
      (define gen-output*
        (lambda (k tmpl* lvl ell?)
          (let f ([tmpl* tmpl*] [out* '()] [vars* #f])
            (if (null? tmpl*)
                (values (reverse out*) vars*)
                (let ([tmpl (car tmpl*)]
                      [tmpl* (cdr tmpl*)])
                  (let-values ([(out vars) (gen-output k tmpl lvl ell?)])
                    (f tmpl* (cons out out*)
                       (if vars
                           (append vars (or vars* '()))
                           vars*))))))))
      (syntax-case stx ()
        [(k tmpl)
         (let-values ([(out vars)
                       (gen-output #'k #'tmpl 0
                                   ellipsis?)])
           (let ([vars (or vars '())])
             (with-syntax ([(x ...) (map template-variable-identifier vars)]
                           [(e ...) (map template-variable-expression vars)])
               #`(let ([x e] ...)
                   #,out))))]
        [_
         (syntax-violation who "invalid syntax" stx)])))

  ;; Match runtime support
  (define split
    (lambda (obj k succ fail)
      (let ([n (length+ obj)])
        (if (and n
                 (fx<=? k n))
            (call-with-values
                (lambda ()
                  (split-at obj (fx- n k)))
              succ)
            (fail)))))

  (define length+
    (lambda (x)
      (let f ([x x] [y x] [n 0])
        (if (pair? x)
            (let ([x (cdr x)]
                  [n (fx+ n 1)])
              (if (pair? x)
                  (let ([x (cdr x)]
                        [y (cdr y)]
                        [n (fx+ n 1)])
                    (and (not (eq? x y))
                         (f x y n)))
                  n))
            n))))

  (define/who split-at
    (lambda (ls k)
      (let f ([ls ls] [k k])
        (cond
         [(fxzero? k)
          (values '() ls)]
         [(pair? ls)
          (let-values ([(ls1 ls2) (f (cdr ls) (fx- k 1))])
            (values (cons (car ls) ls1) ls2))]
         [else (assert #f)]))))

  (define append-n-map
    (lambda (n proc . arg*)
      (let f ([n n] [arg* arg*])
        (if (fxzero? n)
            (apply map proc arg*)
            (let ([n (fx- n 1)])
              (apply append
                     (apply map
                            (lambda arg*
                              (f n arg*))
                            arg*)))))))

  ;; ============================================================
  ;; Section 5: Debug logging
  ;; ============================================================

  (define pk
    (lambda args
      (when (getenv "LETLOOP_DEBUG_UNTANGLE")
        (display "#;(transparent) " (current-error-port))
        (write args (current-error-port))
        (newline (current-error-port))
        (flush-output-port (current-error-port)))
      (car (reverse args))))

  (define untangle-log
    (lambda (level message . objects)
      (pk 'untangle-log level message objects)))

  ;; ============================================================
  ;; Section 6: Event loop (from new-untangle)
  ;; ============================================================

  (define epoll-event-direction-in #x001)
  (define epoll-event-direction-out #x004)

  (define-ftype epoll-type-data
    (union (ptr void*)
           (fd int)
           (u32 unsigned-32)
           (u64 unsigned-64)))

  (define-ftype epoll-type-event
    (struct (events unsigned-32)
            (data epoll-type-data)))

  (define epoll-max-events 64)

  (define-ftype epoll-events-array
    (array 64 epoll-type-event))

  (define (epoll-event-new)
    (make-ftype-pointer epoll-type-event
                        (foreign-alloc
                         (ftype-sizeof epoll-type-event))))

  (define (epoll-events-array-new)
    (make-ftype-pointer epoll-events-array
                        (foreign-alloc
                         (ftype-sizeof epoll-events-array))))

  (define (epoll-events-array-ref events i)
    (ftype-&ref epoll-events-array (i) events))

  (define epoll-event-both-new
    (lambda (fd)
      (define fptr
        (make-ftype-pointer epoll-type-event
                            (foreign-alloc
                             (ftype-sizeof epoll-type-event))))
      (ftype-set! epoll-type-event (events) fptr
                  (logior epoll-event-direction-in epoll-event-direction-out))
      (ftype-set! epoll-type-event (data fd) fptr fd)
      fptr))

  (define epoll-event-in-new
    (lambda (fd)
      (define fptr
        (make-ftype-pointer epoll-type-event
                            (foreign-alloc
                             (ftype-sizeof epoll-type-event))))
      (ftype-set! epoll-type-event (events) fptr epoll-event-direction-in)
      (ftype-set! epoll-type-event (data fd) fptr fd)
      fptr))

  (define epoll-event-out-new
    (lambda (fd)
      (define fptr
        (make-ftype-pointer epoll-type-event
                            (foreign-alloc (ftype-sizeof epoll-type-event))))
      (ftype-set! epoll-type-event (events) fptr epoll-event-direction-out)
      (ftype-set! epoll-type-event (data fd) fptr fd)
      fptr))

  (define (epoll-event-fd event)
    (ftype-ref epoll-type-event (data fd) event))

  (define (epoll-event-in? event)
    (fx=? (fxlogand (ftype-ref epoll-type-event (events) event)
                    epoll-event-direction-in)
          epoll-event-direction-in))

  (define (epoll-event-out? event)
    (fx=? (fxlogand (ftype-ref epoll-type-event (events) event)
                    epoll-event-direction-out)
          epoll-event-direction-out))

  (define epoll-new
    (let ((foreign-epoll-create1 (foreign-procedure "epoll_create1" (int) int)))
      (lambda ()
        (foreign-epoll-create1 0))))

  (define epoll-ctl
    (let ((func (foreign-procedure "epoll_ctl" (int int int void*) int)))
      (lambda (epoll op fd event)
        (func epoll op fd (ftype-pointer-address event)))))

  (define epoll-ctl-op=add 1)
  (define epoll-ctl-op=delete 2)
  (define epoll-ctl-op=modify 3)

  (define epoll-wait
    (let ([func (foreign-procedure "epoll_wait" (int void* int int) int)])
      (lambda (epoll events max-events timeout)
        (func epoll (ftype-pointer-address events) max-events timeout))))

  (define mutex (make-mutex))

  (define %untangle #f)

  (define untangle-current (lambda () %untangle))

  (define untangle-prompt-current #f)

  (define socket-error-would-block 11)
  (define socket-error-try-again)

  (define untangle-prompt-singleton '(untangle-prompt-singleton))

  (define-record-type* <untangle>
    (untangle-base-new jiffy sleeping running epoll events thunks others readable writable epoll-buf)
    untangle?
    (jiffy %untangle-jiffy %untangle-jiffy!)
    (sleeping untangle-sleeping untangle-sleeping!)
    (running untangle-running? untangle-running!)
    (epoll untangle-epoll)
    (events untangle-events)
    (thunks untangle-thunks untangle-thunks!)
    (others untangle-others untangle-others!)
    (readable untangle-readable)
    (writable untangle-writable)
    (epoll-buf untangle-epoll-buf))

  (define untangle-jiffy
    (lambda () (%untangle-jiffy %untangle)))

  (define call-with-untangle-prompt
    (lambda (thunk handlery)
      (call-with-values (lambda ()
                          (call/1cc
                           (lambda (k)
                             (set! untangle-prompt-current k)
                             (thunk))))
        (lambda out
          (cond
           ((and (pair? out) (eq? (car out) untangle-prompt-singleton))
            (pk 'handlery out)
            (apply handlery (cdr out)))
           (else (apply values out)))))))

  (define untangle-abort
    (lambda args
      (call/cc
       (lambda (k)
         (let ((prompt untangle-prompt-current))
           (set! untangle-prompt-current #f)
           (pk 'prompt 'oops prompt)
           (apply prompt (cons untangle-prompt-singleton (cons k args))))))))

  (define untangle-event-new cons)
  (define untangle-event-continuation car)
  (define untangle-event-mode cdr)

  (define untangle-apply
    (lambda (thunk)
      (pk 'untangle-apply 'input thunk)
      (guard (ex (else (pk 'untangle-apply thunk
                           (apply format #f
                                  (condition-message ex)
                                  (condition-irritants ex)))))
        (call-with-untangle-prompt thunk (lambda (k handler) (handler k))))))

  (define hashtable-empty?
    (lambda (h)
      (fx=? (hashtable-size h) 0)))

  (define jiffy-current
    (lambda ()
      (let* ((time (current-time 'time-monotonic))
             (seconds (time-second time))
             (nanoseconds (time-nanosecond time)))
        (+ (* seconds (expt 10 9)) nanoseconds))))

  (define untangle-run-once
    (lambda ()
      (pk 'run-once)
      (let ((thunks (untangle-thunks %untangle)))
        (untangle-thunks! %untangle '())
        (for-each (lambda (thunk) (untangle-apply thunk)) thunks))

      (pk 'a)

      (%untangle-jiffy! %untangle (jiffy-current))

      (call-with-values (lambda ()
                          (sq-split (untangle-sleeping %untangle)
                                    (%untangle-jiffy %untangle)))
        (lambda (before after)
          (unless (sq-empty? before)
            (untangle-sleeping! %untangle after)
            (sq-for-each before (lambda (jiffy thunk) (untangle-apply thunk))))))

      (pk 'b)

      (let ((timeout (if (sq-empty? (untangle-sleeping %untangle))
                         -1
                         (- (car (sq-min (untangle-sleeping %untangle)))
                            (%untangle-jiffy %untangle)))))
        (pk 'timeout timeout)
        (let* ((buf (untangle-epoll-buf %untangle))
               (count (epoll-wait (untangle-epoll %untangle)
                                  (make-ftype-pointer epoll-type-event
                                                      (ftype-pointer-address buf))
                                  epoll-max-events
                                  timeout)))
          (pk 'count count)
          (let loop ((i 0))
            (when (fx<? i count)
              (let* ((event (epoll-events-array-ref buf i))
                     (mode (if (epoll-event-in? event) 'read 'write))
                     (key (cons (epoll-event-fd event) mode))
                     (k (hashtable-ref (untangle-events %untangle) key #f)))
                (hashtable-delete! (untangle-events %untangle) key)
                (when k (untangle-apply k)))
              (loop (fx+ i 1))))))))

  (define untangle-watcher
    (lambda ()
      (when (pk 'watch 'running (untangle-running? %untangle))
        (untangle-read (pk 'readable (untangle-readable %untangle)))

        (let ((new (with-mutex mutex
                     (let ((new (untangle-others %untangle)))
                       (untangle-others! %untangle '())
                       new))))
          (untangle-thunks! %untangle
                            (append new
                                    (untangle-thunks %untangle))))
        (untangle-watcher))))

  (define untangle-stop
    (lambda ()
      (untangle-running! %untangle #f)))

  (define untangle-run
    (lambda ()
      (pk 'fuuu)
      (untangle-spawn (lambda () (untangle-watcher)))
      (let loop ()
        (when (untangle-running? %untangle)
          (guard (ex (else (untangle-log 'error
                                         (format #f "Procedure untangle-run, exception: ~a" (condition-message ex))
                                         (condition-irritants ex))
                           (untangle-running! %untangle #f)))
            (untangle-run-once))
          (loop)))))

  (define untangle-spawn
    (lambda (thunk)
      (untangle-thunks! %untangle
                        (cons thunk (untangle-thunks %untangle)))))

  (define untangle-sleep-nanoseconds
    (lambda (nanoseconds)
      (untangle-abort
       (lambda (k)
         (sq-add! (untangle-sleeping %untangle)
                  (fx+ (%untangle-jiffy %untangle) nanoseconds)
                  k)))))

  (define untangle-spawn-threadsafe
    (lambda (thunk)
      (with-mutex mutex
        (untangle-others! %untangle
                          (cons thunk (untangle-others %untangle))))
      (untangle-write (untangle-writable %untangle)
                      (bytevector 26 00))))

  (define untangle-parallel
    (lambda (thunk)
      (untangle-abort
       (lambda (k)
         (fork-thread (lambda () (call-with-values thunk
                                   (lambda args
                                     (untangle-spawn-threadsafe
                                      (lambda () (apply k args)))))))))))

  (define fcntl!
    (let ((func (foreign-procedure "fcntl" (int int int) int)))
      (lambda (fd command value)
        (func fd command value))))

  (define fcntl
    (let ((func (foreign-procedure "fcntl" (int int) int)))
      (lambda (fd)
        (func fd untangle-get-flag))))

  (define-ftype <pipe>
    (array 2 int))

  (define untangle-get-flag 3)
  (define untangle-set-flag 4)
  (define untangle-nonblock 2048)

  (define untangle-nonblock!
    (lambda (fd)
      (fcntl! fd untangle-set-flag
              (fxlogior untangle-nonblock
                        (fcntl fd)))))

  (define make-pipe
    (let ((func (foreign-procedure "pipe" (void* int) int)))
      (lambda ()
        (define pointer (foreign-alloc (ftype-sizeof <pipe>)))
        (call-with-errno (lambda () (func pointer 0))
          (lambda (out errno)
            (when (fx=? out -1)
              (error 'transparent-make-pipe (strerror errno)))))
        (let ((pipe (make-ftype-pointer <pipe> pointer)))
          (let ((readable (ftype-ref <pipe> (0) pipe))
                (writable (ftype-ref <pipe> (1) pipe)))
            (foreign-free pointer)
            (values readable writable))))))

  (define untangle-new
    (lambda ()
      (untangle-log 'notice "Making an untanglement...")
      (call-with-values make-pipe
        (lambda (readable writable)
          (untangle-nonblock! readable)
          (untangle-nonblock! writable)
          (let ((epoll (epoll-new))
                (events (make-hashtable equal-hash equal?)))
            (set! %untangle
              (untangle-base-new (jiffy-current)
                                 (sq-new)
                                 #t
                                 epoll
                                 events
                                 '()
                                 '()
                                 readable
                                 writable
                                 (epoll-events-array-new)))
            %untangle)))))

  (define untangle-socket-new
    (let ((socket-foreign (foreign-procedure "socket" (int int int) int)))
      (lambda (domain type protocol)
        (call-with-errno (lambda () (socket-foreign domain type protocol))
          (lambda (out errno)
            (if (fx=? out -1)
                (begin
                  (untangle-log 'error
                                (format #f "Failed to create socket: ~a"
                                        (strerror errno)))
                  #f)
                (begin
                  (untangle-nonblock! out)
                  out)))))))

  (define untangle-accept
    (let ((accept4-foreign (foreign-procedure "accept4" (int void* void* int) int)))
      (lambda (fd)

        (define accept
          (lambda (fd)
            (define flags=SOCK_NONBLOCK 2048)
            (call-with-errno (lambda () (accept4-foreign fd 0 0 flags=SOCK_NONBLOCK)) values)))

        (define handle-accept
          (lambda (k)
            (hashtable-set! (untangle-events %untangle)
                            (cons fd 'read)
                            k)
            (epoll-ctl (untangle-epoll %untangle)
                       1
                       fd
                       (epoll-event-in-new fd))))

        (let loop ()
          (let-values (((out errno) (accept fd)))
            (cond
             ((and (fx=? out -1) (fx=? errno socket-error-would-block))
              (untangle-abort handle-accept)
              (loop))
             ((fx=? out -1)
              (untangle-log 'error
                            (format #f "Procedure untangle-accept, errno: ~a @ ~a"
                                    (strerror errno)
                                    fd))
              #f)
             (else
              (untangle-socket-option! out 6 'tcp-option/nodelay #t)
              out)))))))

  (define untangle-close
    (let ((untangle-close-foreign (foreign-procedure "close" (int) int)))
      (lambda (fd)
        (untangle-close-foreign fd))))

  (define untangle-socket-option!
    (let ((untangle-socket-option-foreign! (foreign-procedure "setsockopt" (int int int void* int) int)))
      (lambda (fd level optname optval)

        (define (doit opt-int)
          (let* ((size (ftype-sizeof int))
                 (pointer (foreign-alloc size)))
            (foreign-set! 'int pointer 0 (if optval 1 0))
            (call-with-errno (lambda () (untangle-socket-option-foreign! fd level opt-int pointer size))
              (lambda (out errno)
                (foreign-free pointer)
                (if (fxzero? out)
                    #t
                    (error 'transparent
                           (format #f "setsockopt errno ~a" (strerror errno))
                           fd))))))

        (case optname
          ((socket-option/debug) (doit 1))
          ((socket-option/reuseaddr) (doit 2))
          ((socket-option/dontroute) (doit 5))
          ((socket-option/broadcast) (doit 6))
          ((socket-option/keepalive) (doit 9))
          ((socket-option/oobinline) (doit 10))
          ((socket-option/reuseport) (doit 15))
          ((tcp-option/nodelay) (doit 1))
          (else (error 'transparent "Unknown socket option" fd level optname optval))))))

  (define untangle-bind
    (let ((untangle-bind-foreign (foreign-procedure "bind" (int void* size_t) int)))
      (lambda (fd ip port)

        (define string->ipv4
          (lambda (string)

            (define (ipv4 one two three four)
              (+ (* one 256 256 256)
                 (* two 256 256)
                 (* three 256)
                 four))

            (define make-char-predicate
              (lambda (char)
                (lambda (other)
                  (char=? char other))))

            (define (string-split char-delimiter? string)
              (define (maybe-add a b parts)
                (if (= a b) parts (cons (substring string a b) parts)))
              (let ((n (string-length string)))
                (let loop ((a 0) (b 0) (parts '()))
                  (if (< b n)
                      (if (not (char-delimiter? (string-ref string b)))
                          (loop a (+ b 1) parts)
                          (loop (+ b 1) (+ b 1) (maybe-add a b parts)))
                      (reverse (maybe-add a b parts))))))

            (apply ipv4 (map string->number
                             (string-split (make-char-predicate #\.)
                                           string)))))

        (define-ftype <socket-address-in>
          (struct (family unsigned-short)
                  (port (endian big unsigned-16))
                  (address (endian big unsigned-32))
                  (padding (array 8 char))))

        (define (socket-address-in-new ip port)
          (let* ((pointer (foreign-alloc (ftype-sizeof <socket-address-in>)))
                 (address (make-ftype-pointer <socket-address-in> pointer)))
            (ftype-set! <socket-address-in> (family) address 2)
            (ftype-set! <socket-address-in> (port) address port)
            (ftype-set! <socket-address-in> (address) address (string->ipv4 ip))
            (values pointer address)))

        (untangle-socket-option! fd 1 'socket-option/reuseaddr #t)
        (untangle-socket-option! fd 1 'socket-option/reuseport #t)

        (call-with-values (lambda () (socket-address-in-new ip port))
          (lambda (pointer address)
            (call-with-errno (lambda ()
                               (untangle-bind-foreign fd
                                                      pointer
                                                      (ftype-sizeof <socket-address-in>)))
              (lambda (out errno)
                (foreign-free pointer)
                (unless (fxzero? out)
                  (error 'transparent (format #f "bind errno ~a" (strerror errno)))))))))))

  (define untangle-listen
    (let ((untangle-listen-foreign (foreign-procedure "listen" (int int) int)))
      (lambda (fd backlog)
        (call-with-errno (lambda () (untangle-listen-foreign fd backlog))
          (lambda (out errno)
            (unless (fxzero? out)
              (error 'transparent (format #f "listen errno ~a" (strerror errno)))))))))

  (define subbytevector
    (case-lambda
     ((bv start end)
      (assert (bytevector? bv))
      (unless (<= 0 start end (bytevector-length bv))
        (error 'subbytevector "Invalid indices" bv start end))
      (if (and (fxzero? start)
               (fx=? end (bytevector-length bv)))
          bv
          (let ((ret (make-bytevector (fx- end start))))
            (bytevector-copy! bv start
                              ret 0 (fx- end start))
            ret)))
     ((bv start)
      (subbytevector bv start (bytevector-length bv)))))

  (define untangle-read
    (let ((untangle-read-foreign
           (foreign-procedure "read" (int void* size_t) ssize_t)))
      (lambda (fd)

        (define func
          (lambda (fd bv)
            (with-lock (list bv)
              (call-with-errno
                  (lambda ()
                    (untangle-read-foreign fd
                                           (bytevector-pointer bv)
                                           (bytevector-length bv)))
                values))))

        (define bv (make-bytevector 1024))

        (define handle-read
          (lambda (k)
            (pk 'hr 1)
            (hashtable-set! (untangle-events %untangle)
                            (cons fd 'read)
                            k)
            (pk 'hr 2)
            (pk 'hr 3)
            (epoll-ctl (untangle-epoll %untangle)
                       epoll-ctl-op=add
                       fd
                       (epoll-event-in-new fd))))

        (let loop ()
          (let-values (((out errno) (func fd bv)))
            (pk 'read out errno)
            (cond
             ((and (fx=? out -1) (fx=? errno socket-error-would-block))
              (untangle-abort handle-read)
              (loop))
             ((fx=? out -1)
              (untangle-log 'error
                            (format #f "Procedure untangle-read, errno: ~a @ ~a"
                                    (strerror errno)
                                    fd))
              #f)
             ((fxzero? out) #t)
             (else (subbytevector bv 0 out))))))))

  (define untangle-write
    (let ((untangle-write-foreign
           (foreign-procedure "write" (int void* size_t) ssize_t)))
      (lambda (fd bv)
        (define debug (pk 'untangle-write))

        (define func
          (lambda (fd bv)
            (with-lock (list bv)
              (call-with-errno (lambda ()
                                 (untangle-write-foreign fd
                                                         (bytevector-pointer bv)
                                                         (bytevector-length bv)))
                values))))

        (define handle-write
          (lambda (k)
            (hashtable-set! (untangle-events %untangle)
                            (cons fd 'write)
                            k)
            (epoll-ctl (untangle-epoll %untangle)
                       epoll-ctl-op=modify
                       fd
                       (epoll-event-out-new fd))))

        (let loop ((bv bv)
                   (remaining (bytevector-length bv)))
          (let-values (((out errno) (func fd bv)))

            (cond
             ((and (fx=? out -1) (fx=? errno socket-error-would-block))
              (untangle-abort handle-write)
              (loop bv remaining))
             ((fx=? out -1)
              (untangle-log 'error
                            (format #f "Procedure untangle-write, error: ~a @ ~a"
                                    (strerror errno)
                                    fd))
              #f)
             (else (if (fx=? out (bytevector-length bv))
                       #t
                       (let ((rest (subbytevector bv
                                                  out
                                                  (bytevector-length bv))))
                         (loop rest (bytevector-length rest)))))))))))

  (define untangle-tcp-serve
    (lambda (ip port)
      (define DEBUG (pk 'DEBUG))
      (define SOCKET-DOMAIN=AF-INET 2)
      (define SOCKET-TYPE=STREAM 1)
      (define fd (pk 'socket (untangle-socket-new SOCKET-DOMAIN=AF-INET SOCKET-TYPE=STREAM 0)))

      (define accept
        (lambda ()
          (define client (untangle-accept fd))
          (if (not client)
              (values #f #f #f)
              (values (lambda () (untangle-read client))
                      (lambda (bv) (untangle-write client bv))
                      (lambda () (untangle-close client))))))

      (pk 'bind (untangle-bind fd ip port))
      (pk 'listen (untangle-listen fd 128))

      (values accept (lambda () (untangle-close fd)))))

  ;; ============================================================
  ;; Section 7: HTTP parser/writer (from letloop http)
  ;; ============================================================

  (define every
    (lambda (predicate? objects)
      (if (null? objects)
          #t
          (if (predicate? (car objects))
              (every predicate? (cdr objects))
              #f))))

  (define (bytevector-append . bvs)
    (assert (every bytevector? bvs))
    (let* ((total (apply fx+ (map bytevector-length bvs)))
           (out (make-bytevector total)))
      (let loop ((bvs bvs)
                 (index 0))
        (unless (null? bvs)
          (bytevector-copy! (car bvs) 0 out index (bytevector-length (car bvs)))
          (loop (cdr bvs) (fx+ index (bytevector-length (car bvs))))))
      out))

  (define generator->list
    (lambda (generator)
      (let loop ((out '()))
        (let ((object (generator)))
          (if (eof-object? object)
              (reverse out)
              (loop (cons object out)))))))

  (define byte-space 32)
  (define byte-carriage-return 13)
  (define byte-linefeed 10)

  (define make-http-reader
    (lambda (read)
      (let ((buf (bytevector))
            (idx 0)
            (len 0))

        (define refill!
          (lambda ()
            (let ((chunk (read)))
              (if (eof-object? chunk)
                  #f
                  (begin
                    (set! buf chunk)
                    (set! idx 0)
                    (set! len (bytevector-length chunk))
                    #t)))))

        (define read-byte!
          (lambda ()
            (if (fx<? idx len)
                (let ((b (bytevector-u8-ref buf idx)))
                  (set! idx (fx+ idx 1))
                  b)
                (if (refill!)
                    (read-byte!)
                    (eof-object)))))

        (define read-bytes!
          (lambda (n)
            (let ((out (make-bytevector n)))
              (let loop ((written 0))
                (if (fx=? written n)
                    out
                    (let ((avail (fx- len idx)))
                      (if (fxzero? avail)
                          (if (refill!)
                              (loop written)
                              (error 'http "Unexpected end of file"))
                          (let ((to-copy (fxmin avail (fx- n written))))
                            (bytevector-copy! buf idx out written to-copy)
                            (set! idx (fx+ idx to-copy))
                            (loop (fx+ written to-copy))))))))))

        (values read-byte! read-bytes!))))

  (define http-line-read
    (lambda (read-byte!)
      (let loopx ((out '()))
        (let ((byte (read-byte!)))
          (cond
           ((eof-object? byte)
            (if (null? out)
                (error 'http "Unexpected end of file")
                (error 'http "Unexpected end of file")))
           ((and (fx=? byte byte-linefeed) (not (null? out)) (fx=? (car out) byte-carriage-return))
            (u8-list->bytevector (reverse (cdr out))))
           ((and (fx=? byte byte-linefeed) (or (null? out) (not (fx=? (car out) byte-carriage-return))))
            (error 'http "Invalid line ending"))
           (else (loopx (cons byte out))))))))

  (define http-headers-read
    (lambda (read-byte!)

      (define massage*
        (lambda (chars)
          (let loop ((chars chars))
            (if (null? chars)
                '()
                (if (char=? (car chars) #\space)
                    (loop (cdr chars))
                    chars)))))

      (define massage
        (lambda (string)
          (let loopx ((chars (reverse (massage* (reverse (massage* (string->list string))))))
                      (key '()))
            (if (null? chars)
                (error 'http "Invalid header")
                (let ((char (car chars)))
                  (if (char=? char #\:)
                      (cons (string->symbol (string-downcase (list->string (reverse (massage* key)))))
                            (string-downcase (list->string (massage* (reverse (massage* (reverse (cdr chars))))))))
                      (loopx (cdr chars) (cons (car chars) key))))))))

      (let loopy ((out '()))
        (let ((line-bv (http-line-read read-byte!)))
          (if (fxzero? (bytevector-length line-bv))
              (reverse (map (lambda (x) (massage (utf8->string x))) out))
              (loopy (cons line-bv out)))))))

  (define http-chunked-read
    (lambda (read-byte! read-bytes!)
      (let loop ((chunks '()))
        (let ((chunk-size (string->number (utf8->string (http-line-read read-byte!)) 16)))
          (unless chunk-size
            (error 'http "Invalid chunk size"))
          (if (fxzero? chunk-size)
              (apply bytevector-append (reverse chunks))
              (let ((chunk-data (read-bytes! chunk-size)))
                (http-line-read read-byte!)
                (loop (cons chunk-data chunks))))))))

  (define http-body-read
    (lambda (read-byte! read-bytes! headers)
      (let ((content-length (let ((value (assq 'content-length headers)))
                              (if value
                                  (string->number (cdr value))
                                  #f))))
        (if content-length
            (if (fxzero? content-length)
                (bytevector)
                (read-bytes! content-length))
            (let ((chunked? (let ((value (assq 'transfer-encoding headers)))
                              (and value (string=? (cdr value) "chunked")))))
              (if chunked?
                  (http-chunked-read read-byte! read-bytes!)
                  (bytevector)))))))

  ;; http-request-read using persistent reader (for keep-alive)
  (define %http-request-read
    (lambda (read-byte! read-bytes!)
      (define request-line-read
        (lambda (read-byte!)
          (define massage
            (lambda (line-bv)
              (let loop ((bytes (bytevector->u8-list line-bv))
                         (chunk '())
                         (out '()))
                (if (null? bytes)
                    (if (null? chunk)
                        (error 'http "Invalid request line")
                        (reverse (cons (utf8->string (u8-list->bytevector (reverse chunk))) out)))
                    (let ((byte (car bytes)))
                      (if (and (fx=? byte byte-space) (not (null? chunk)))
                          (loop (cdr bytes) '() (cons (utf8->string (u8-list->bytevector (reverse chunk))) out))
                          (loop (cdr bytes) (cons byte chunk) out)))))))
          (let ((strings (massage (http-line-read read-byte!))))
            (unless (fx=? (length strings) 3)
              (error 'http "Invalid request line"))
            (values (string->symbol (car strings)) (cadr strings) (string->symbol (caddr strings))))))

      (guard (ex (else (values #f #f #f #f #f)))
        (call-with-values (lambda () (request-line-read read-byte!))
          (lambda (method uri version)
            (let ((headers (http-headers-read read-byte!)))
              (values method uri version headers (http-body-read read-byte! read-bytes! headers))))))))

  ;; http-response-write
  (define transfer-encoding-chunked?
    (lambda (pair)
      (and (eq? (car pair) 'transfer-encoding)
           (string=? (cdr pair) "chunked"))))

  (define massage-headers-content-length
    (lambda (headers content-length)
      (cond
       ((null? headers) (list (cons 'content-length content-length)))
       ((transfer-encoding-chunked? (car headers)) (cons (cons 'content-length content-length) (cdr headers)))
       (else (cons (car headers) (massage-headers-content-length (cdr headers) content-length))))))

  (define http-response-write
    (lambda (accumulator version code reason headers body)
      (assert (or (pair? headers) (null? headers)))
      (let ((chunks (generator->list body)))
        (let ((content-length (apply fx+ (map bytevector-length chunks))))
          (let* ((headers* (massage-headers-content-length headers content-length))
                 (response-line (format #f "~a ~a ~a\r\n" version code reason))
                 (header-str (apply string-append (map (lambda (x) (format #f "~a: ~a\r\n" (car x) (cdr x))) headers*))))
            (accumulator (string->utf8 (string-append response-line header-str "\r\n")))
            (for-each accumulator chunks))))))

  ;; ============================================================
  ;; Section 8: URI parser (from letloop www)
  ;; ============================================================

  (define string->list*
    (lambda (x)
      (if x (string->list x) '())))

  (define percent-decode
    (lambda (string)
      (let loop ((chars (string->list* string))
                 (out '()))
        (match chars
          (() (list->string (reverse out)))
          ((#\+ ,rest ...)
           (loop rest (cons #\space out)))
          ((#\% ,a ,b ,rest ...)
           (loop rest (cons
                       (integer->char
                        (string->number
                         (list->string (list a b))
                         16))
                       out)))
          ((,char . ,rest) (loop rest (cons char out)))))))

  (define www-form-urlencoded-read
    (lambda (string)

      (define form-item-split
        (lambda (string)
          (let loop ((chars (string->list* string))
                     (out '()))
            (match chars
              (() (list (string->symbol (list->string (reverse out)))))
              ((#\= . ,rest) (cons (string->symbol (percent-decode (list->string (reverse out))))
                                   (percent-decode (list->string rest))))
              ((,char . ,rest) (loop rest (cons char out)))))))

      (let loop ((chars (string->list* string))
                 (out '(())))
        (match chars
          (() (reverse (cons (form-item-split (list->string (reverse (car out)))) (cdr out))))
          ((#\& . ,rest) (loop (cdr chars)
                               (cons* (list)
                                      (form-item-split (list->string (reverse (car out))))
                                      (cdr out))))
          ((#\; . ,rest) (loop (cdr chars)
                               (cons* (list)
                                      (form-item-split (list->string (reverse (car out))))
                                      (cdr out))))
          ((,char . ,rest) (loop (cdr chars) (cons (cons char (car out)) (cdr out))))))))

  (define www-query-read www-form-urlencoded-read)

  (define string-find
    (lambda (string char)
      (let loop ((chars (string->list* string))
                 (index 0))
        (if (null? chars)
            #f
            (if (char=? char (car chars))
                index
                (loop (cdr chars) (fx+ index 1)))))))

  (define uri-parse
    (lambda (string)

      (define path-split
        (lambda (string)
          (when (and (not (string=? string "")) (char=? #\/ (string-ref string 0)))
            (set! string (substring string 1 (string-length string))))

          (when (and (not (string=? string "")) (char=? #\/ (string-ref string (fx- (string-length string) 1))))
            (set! string (substring string 0 (fx- (string-length string) 1))))

          (if (string=? "" string)
              '()
              (let loop ((chars (string->list* string))
                         (out '(())))
                (match chars
                  (() (reverse (cons (percent-decode (list->string (reverse (car out))))
                                     (cdr out))))
                  ((#\/ . ,rest) (loop rest (cons* '()
                                                   (percent-decode (list->string (reverse (car out))))
                                                   (cdr out))))
                  ((,char . ,rest) (loop rest (cons (cons char (car out))
                                                    (cdr out)))))))))

      (define path #f)
      (define query #f)
      (define fragment #f)

      (let ((index (string-find string #\#)))
        (when index
          (set! fragment (substring string (fx+ index 1) (string-length string)))
          (set! string (substring string 0 index))))

      (let ((index (string-find string #\?)))
        (when index
          (set! query (substring string (fx+ index 1) (string-length string)))
          (set! string (substring string 0 index))))

      (set! path string)

      (values (and path (path-split path)) (and query (www-query-read query)) fragment)))

  ;; ============================================================
  ;; Section 9: JSON reader/writer (from letloop json)
  ;; ============================================================

  (define string->generator
    (case-lambda ((str) (string->generator str 0 (string-length str)))
                 ((str start) (string->generator str start (string-length str)))
                 ((str start end)
                  (lambda () (if (>= start end)
                                 (eof-object)
                                 (let ((next (string-ref str start)))
                                   (set! start (+ start 1))
                                   next))))))

  (define json-nesting-depth-limit (make-parameter 99))

  (define (json-null? obj)
    (eq? obj 'null))

  (define-record-type* <json-error>
    (make-json-error reason)
    json-error?
    (reason json-error-reason))

  (define (json-whitespace? char)
    (case char
      ((#\x20 #\x09 #\x0A #\x0D #\x1E) #t)
      (else #f)))

  (define (json-expect value other)
    (when (eof-object? value)
      (raise (make-json-error "Unexpected end-of-file.")))
    (void))

  (define (port->generator port)
    (lambda ()
      (read-char port)))

  (define (%json-tokens generator)

    (define (maybe-ignore-whitespace generator)
      (let loop ((char (generator)))
        (if (json-whitespace? char)
            (loop (generator))
            char)))

    (define (expect-null generator)
      (json-expect (generator) #\u)
      (json-expect (generator) #\l)
      (json-expect (generator) #\l))

    (define (expect-true generator)
      (json-expect (generator) #\r)
      (json-expect (generator) #\u)
      (json-expect (generator) #\e))

    (define (expect-false generator)
      (json-expect (generator) #\a)
      (json-expect (generator) #\l)
      (json-expect (generator) #\s)
      (json-expect (generator) #\e))

    (define (maybe-char generator)
      (let ((char (generator)))
        (when (eof-object? char)
          (raise (make-json-error "Unexpected end-of-file.")))
        (when (char=? char #\")
          (raise (make-json-error "Unexpected end of string.")))
        char))

    (define (read-unicode-escape generator)
      (let* ((one (maybe-char generator))
             (two (maybe-char generator))
             (three (maybe-char generator))
             (four (maybe-char generator)))
        (let ((out (string->number (list->string (list one two three four)) 16)))
          (if out
              out
              (raise (make-json-error "Invalid code point."))))))

    (define (read-json-string generator)
      (let loop ((char (generator))
                 (out '()))
        (when (eof-object? char)
          (raise (make-json-error "Unexpected end of file.")))

        (cond
         ((char=? char #\\)
          (begin
            (let loop-unescape ((char (generator))
                                (chars-unescaped '()))
              (case char
                ((#\" #\\ #\/) (loop (generator)
                                      (cons char (append chars-unescaped
                                                        out))))
                ((#\b) (loop (generator) (cons #\backspace
                                             (append chars-unescaped
                                                     out))))
                ((#\n) (loop (generator) (cons #\newline
                                             (append chars-unescaped
                                                     out))))
                ((#\t) (loop (generator) (cons #\tab
                                             (append chars-unescaped
                                                     out))))
                ((#\u) (let loop-unicode ((code1 (read-unicode-escape generator))
                                        (chars chars-unescaped))
                       (let ((next-char (generator)))
                         (if (and (<= #xd800 code1 #xdbff)
                                  (char=? next-char #\\))
                             (if (char=? (generator) #\u)
                                 (let ((code2 (read-unicode-escape generator)))
                                   (if (<= #xdc00 code2 #xdfff)
                                       (let ((integer
                                              (+ #x10000 (bitwise-ior
                                                          (ash (- code1 #xd800) 10)
                                                          (- code2 #xdc00)))))
                                         (loop (generator)
                                               (cons (integer->char integer)
                                                     (append chars
                                                             out))))
                                       (loop-unicode (read-unicode-escape generator)
                                                     (cons (integer->char code1) chars))))
                                 (loop-unescape char (cons (integer->char code1)
                                                           chars)))
                             (loop next-char
                                   (cons (integer->char code1) (append chars out)))))))
                (else (raise (make-json-error "Unexpected escaped sequence.")))))))
         ((char=? char #\")
          (list->string (reverse out)))
         (else
          (loop (generator) (cons char out))))))

    (define (maybe-read-number char generator)
      (let loop ((char char)
                 (out '()))
        (if (or (eof-object? char)
                (json-whitespace? char)
                (char=? char #\,)
                (char=? char #\])
                (char=? char #\}))
            (let ((string (list->string (reverse out))))
              (let ((number (string->number string)))
                (if number
                    (values number char)
                    (raise (make-json-error (format #f "Invalid number: ~s" string))))))
            (loop (generator) (cons char out)))))

    (define char (maybe-ignore-whitespace generator))

    (lambda ()
      (if (eof-object? char)
          char
          (case char
            ((#\n) (expect-null generator) (set! char (maybe-ignore-whitespace generator)) 'null)
            ((#\t) (expect-true generator) (set! char (maybe-ignore-whitespace generator)) #t)
            ((#\f) (expect-false generator) (set! char (maybe-ignore-whitespace generator)) #f)
            ((#\:) (set! char (maybe-ignore-whitespace generator)) 'colon)
            ((#\,) (set! char (maybe-ignore-whitespace generator)) 'comma)
            ((#\[) (set! char (maybe-ignore-whitespace generator)) 'array-start)
            ((#\]) (set! char (maybe-ignore-whitespace generator)) 'array-end)
            ((#\{) (set! char (maybe-ignore-whitespace generator)) 'object-start)
            ((#\}) (set! char (maybe-ignore-whitespace generator)) 'object-end)
            ((#\") (let ((out (read-json-string generator)))
                     (set! char (maybe-ignore-whitespace generator))
                     out))
            (else
             (call-with-values (lambda () (maybe-read-number char generator))
               (lambda (number next)
                 (if (json-whitespace? next)
                     (set! char (maybe-ignore-whitespace generator))
                     (set! char next))
                 number)))))))

  (define json-tokens
    (lambda args
      (if (null? args)
          (json-tokens (current-input-port))
          (let ((port-or-generator (car args)))
            (cond
             ((procedure? port-or-generator)
              (%json-tokens port-or-generator))
             ((port? port-or-generator)
              (%json-tokens (port->generator port-or-generator)))
             (else (error 'json "json-tokens error, argument is not valid" port-or-generator)))))))

  (define (list->reverse-vector objs length)
    (define vector (make-vector length))
    (let loop ((objs objs)
               (index (fx- length 1)))
      (if (null? objs)
          vector
          (begin
            (vector-set! vector index (car objs))
            (loop (cdr objs) (fx- index 1))))))

  (define json-read
    (lambda args
      (if (null? args)
          (json-read (current-input-port))
          (let ((nesting-depth-remaining (json-nesting-depth-limit)))

            (define nesting-depth-remaining-increment!
              (lambda ()
                (set! nesting-depth-remaining (fx+ nesting-depth-remaining 1))))

            (define nesting-depth-remaining-decrement!
              (lambda ()
                (if (fxzero? nesting-depth-remaining)
                    (raise (make-json-error "Maximum recursion depth exceeded."))
                    (set! nesting-depth-remaining (fx- nesting-depth-remaining 1)))))

            (define (read token generator)
              (cond
               ((or (number? token) (string? token) (boolean? token) (json-null? token))
                token)
               ((eq? token 'array-start)
                (let ((next (generator)))
                  (if (eq? next 'array-end)
                      (begin
                        (nesting-depth-remaining-increment!)
                        (make-vector 0))
                      (let loop ((out (list (read next generator)))
                                 (length 1))
                        (case (generator)
                          ((comma) (loop (cons (read (generator) generator) out)
                                         (fx+ length 1)))
                          ((array-end)
                           (nesting-depth-remaining-increment!)
                           (list->reverse-vector out length))
                          (else (raise (make-json-error "Invalid array."))))))))
               ((eq? token 'object-start)
                (nesting-depth-remaining-decrement!)
                (let loop ((out '()))
                  (let ((next (generator)))
                    (if (eq? next 'object-end)
                        (begin (nesting-depth-remaining-increment!) out)
                        (let* ((key (string->symbol next))
                               (colon (generator))
                               (value (read (generator) generator)))
                          (case (generator)
                            ((comma) (loop (cons (cons key value) out)))
                            ((object-end)
                             (nesting-depth-remaining-increment!)
                             (cons (cons key value) out))
                            (else (raise (make-json-error "Invalid object.")))))))))))

            (let* ((generator (json-tokens (car args)))
                   (token (generator)))
              (guard (ex (else (raise (make-json-error "Invalid JSON"))))
                     (read token generator)))))))

  ;; JSON writer

  (define (json-accumulator accumulator)

    (define (write-json-char char accumulator)
      (case char
        ((#\x00) (accumulator "\\u0000"))
        ((#\") (accumulator "\\\""))
        ((#\\) (accumulator "\\\\"))
        ((#\/) (accumulator "\\/"))
        ((#\return) (accumulator "\\r"))
        ((#\newline) (accumulator "\\n"))
        ((#\tab) (accumulator "\\t"))
        ((#\backspace) (accumulator "\\b"))
        ((#\x0c) (accumulator "\\f"))
        (else (accumulator char))))

    (define (write-json-string string accumulator)
      (accumulator #\")
      (string-for-each
       (lambda (char) (write-json-char char accumulator))
       string)
      (accumulator #\"))

    (define (write-json-value obj accumulator)
      (cond
       ((eq? obj 'null) (accumulator "null"))
       ((boolean? obj) (if obj
                           (accumulator "true")
                           (accumulator "false")))
       ((string? obj) (write-json-string obj accumulator))
       ((number? obj) (accumulator (number->string obj)))
       (else (raise (make-json-error "Invalid json value.")))))

    (define (raise-invalid-event event)
      (raise (make-json-error "json-accumulator: invalid event.")))

    (define (object-start k)
      (lambda (accumulator event)
        (accumulator #\{)
        (case (car event)
          ((json-value)
           (let ((key (cdr event)))
             (unless (symbol? key) (raise-invalid-event event))
             (write-json-string (symbol->string key) accumulator)
             (object-value k)))
          ((json-structure)
           (case (cdr event)
             ((object-end)
              (accumulator #\})
              k)
             (else (raise-invalid-event event))))
          (else (raise-invalid-event event)))))

    (define (object-value k)
      (lambda (accumulator event)
        (accumulator #\:)
        (case (car event)
          ((json-value)
           (write-json-value (cdr event) accumulator)
           (object-maybe-continue k))
          ((json-structure)
           (case (cdr event)
             ((array-start)
              (array-start (object-maybe-continue k)))
             ((object-start)
              (object-start (object-maybe-continue k)))
             (else (raise-invalid-event event))))
          (else (raise-invalid-event event)))))

    (define (object-maybe-continue k)
      (lambda (accumulator event)
        (case (car event)
          ((json-value)
           (accumulator #\,)
           (let ((key (cdr event)))
             (unless (symbol? key) (raise-invalid-event event))
             (write-json-value (symbol->string key) accumulator)
             (object-value k)))
          ((json-structure)
           (case (cdr event)
             ((object-end)
              (accumulator #\})
              k)
             (else (raise-invalid-event event))))
          (else (raise-invalid-event event)))))

    (define (array-start k)
      (lambda (accumulator event)
        (accumulator #\[)
        (case (car event)
          ((json-value)
           (write-json-value (cdr event) accumulator)
           (array-maybe-continue k))
          ((json-structure)
           (case (cdr event)
             ((array-end)
              (accumulator #\])
              k)
             ((array-start) (array-start (array-maybe-continue k)))
             ((object-start) (object-start (array-maybe-continue k)))
             (else (raise-invalid-event event))))
          (else (raise-invalid-event event)))))

    (define (array-maybe-continue k)
      (lambda (accumulator event)
        (case (car event)
          ((json-value)
           (accumulator #\,)
           (write-json-value (cdr event) accumulator)
           (array-maybe-continue k))
          ((json-structure)
           (case (cdr event)
             ((array-end)
              (accumulator #\])
              k)
             ((array-start)
              (accumulator #\,)
              (array-start (array-maybe-continue k)))
             ((object-start)
              (accumulator #\,)
              (object-start (array-maybe-continue k)))
             (else (raise-invalid-event event))))
          (else (raise-invalid-event event)))))

    (define (start accumulator event)
      (case (car event)
        ((json-value)
         (write-json-value (cdr event) accumulator)
         raise-invalid-event)
        ((json-structure)
         (case (cdr event)
           ((array-start)
            (array-start raise-invalid-event))
           ((object-start)
            (object-start raise-invalid-event))
           (else (raise-invalid-event event))))
        (else (raise-invalid-event event))))

    (let ((k start))
      (lambda (event)
        (set! k (k accumulator event)))))

  (define (%json-write obj accumulator)

    (define (raise-unless-valid? obj)
      (cond
       ((null? obj) (void))
       ((eq? obj 'null) (void))
       ((boolean? obj) (void))
       ((string? obj) (void))
       ((and (number? obj)
             (not (infinite? obj))
             (not (nan? obj))
             (real? obj)
             (or (and (exact? obj) (= (denominator obj) 1))
                 (inexact? obj)))
        (void))
       ((vector? obj)
        (vector-for-each (lambda (obj) (raise-unless-valid? obj)) obj))
       ((pair? obj)
        (for-each (lambda (obj)
                    (unless (pair? obj)
                      (raise (make-json-error "Unexpected object, not a pair.")))
                    (unless (symbol? (car obj))
                      (raise (make-json-error "Unexpected object, not a symbol key.")))
                    (raise-unless-valid? (cdr obj)))
                  obj))
       (else (raise (make-json-error "Unexpected object")))))

    (define (write-json obj accumulator)
      (cond
       ((or (eq? obj 'null)
            (boolean? obj)
            (string? obj)
            (symbol? obj)
            (number? obj))
        (accumulator (cons 'json-value obj)))
       ((vector? obj)
        (accumulator '(json-structure . array-start))
        (vector-for-each (lambda (obj) (write-json obj accumulator)) obj)
        (accumulator '(json-structure . array-end)))
       ((null? obj)
        (accumulator '(json-structure . object-start))
        (accumulator '(json-structure . object-end)))
       ((pair? obj)
        (accumulator '(json-structure . object-start))
        (for-each (lambda (pair)
                    (write-json (car pair) accumulator)
                    (write-json (cdr pair) accumulator))
                  obj)
        (accumulator '(json-structure . object-end)))
       (else (error 'json "Unexpected error!"))))

    (raise-unless-valid? obj)
    (write-json obj (json-accumulator accumulator)))

  (define (json-port->accumulator port)
    (lambda (char-or-string)
      (cond
       ((char? char-or-string) (put-char port char-or-string))
       ((string? char-or-string) (put-string port char-or-string))
       (else (raise (make-json-error "Not a char or string"))))))

  (define json-write
    (lambda (obj . args)
      (if (null? args)
          (json-write obj (current-output-port))
          (if (procedure? (car args))
              (%json-write obj (car args))
              (%json-write obj (json-port->accumulator (car args)))))))

  (define jsonify
    (lambda (obj)

      (define accumulator
        (let ((out '()))
          (lambda (object)
            (if (eof-object? object)
                (list->string (reverse out))
                (if (char? object)
                    (set! out (cons object out))
                    (set! out (append (reverse (string->list object)) out)))))))

      (json-write obj accumulator)

      (accumulator (eof-object))))

  (define unjson
    (lambda (string)
      (json-read (string->generator string))))

  ;; ============================================================
  ;; Section 10: HTML writer (from letloop html base)
  ;; ============================================================

  (define html-element-no-end-tag
    '(area base br col command embed hr img input keygen link meta param source track wbr))

  (define html-element-no-end-tag?
    (lambda (tag)
      (pair? (memq tag html-element-no-end-tag))))

  (define html-character->string
    (lambda (char)
      (cdr
       (or (assv char
                 '((#\" . "&quot;")
                   (#\& . "&amp;")
                   (#\< . "&lt;")
                   (#\> . "&gt;")))
           (cons char (list->string (list char)))))))

  (define string->html-string
    (lambda (string)
      (apply string-append
             (map html-character->string (string->list string)))))

  (define html-write-tag-start
    (lambda (tag attributes accumulator)
      (accumulator (format #f "<~a" tag))
      (for-each
       (lambda (attribute)
         (accumulator (format #f " ~a=\"~a\""
                              (car attribute)
                              (cadr attribute))))
       attributes)
      (if (html-element-no-end-tag? tag)
          (accumulator "/>")
          (accumulator ">"))))

  (define html-write-tag-end
    (lambda (tag accumulator)
      (unless (html-element-no-end-tag? tag)
        (accumulator (format #f "</~a>" tag)))))

  (define html-make-string-accumulator
    (lambda ()
      (let ((out '()))
        (lambda (object)
          (if (eof-object? object)
              (apply string-append (reverse out))
              (set! out (cons object out)))))))

  (define html-write
    (case-lambda
     ((object accumulator)
      (cond
       ((string? object) (accumulator (string->html-string object)))
       ((number? object) (accumulator (number->string object)))
       (else
        (match object
          ((,tag (@ ,attributes ...) ,elements ...)
           (html-write-tag-start tag attributes accumulator)
           (for-each (lambda (element) (html-write element accumulator))
                     elements)
           (html-write-tag-end tag accumulator))
          ((,tag ,elements ...)
           (html-write-tag-start tag '() accumulator)
           (for-each (lambda (element) (html-write element accumulator))
                     elements)
           (html-write-tag-end tag accumulator))))))
     ((object)
      (define out (html-make-string-accumulator))
      (html-write object out)
      (out (eof-object)))))

  ;; ============================================================
  ;; Section 11: XML writer (new)
  ;; ============================================================

  (define xml-write
    (case-lambda
     ((object accumulator)
      (cond
       ((string? object) (accumulator (string->html-string object)))
       ((number? object) (accumulator (number->string object)))
       (else
        (match object
          ((,tag (@ ,attributes ...) ,elements ...)
           (accumulator (format #f "<~a" tag))
           (for-each
            (lambda (attribute)
              (accumulator (format #f " ~a=\"~a\"" (car attribute) (cadr attribute))))
            attributes)
           (accumulator ">")
           (for-each (lambda (element) (xml-write element accumulator)) elements)
           (accumulator (format #f "</~a>" tag)))
          ((,tag ,elements ...)
           (accumulator (format #f "<~a>" tag))
           (for-each (lambda (element) (xml-write element accumulator)) elements)
           (accumulator (format #f "</~a>" tag)))))))
     ((object)
      (define out (html-make-string-accumulator))
      (xml-write object out)
      (out (eof-object)))))

  ;; ============================================================
  ;; Section 12: Response helpers and transparent server
  ;; ============================================================

  (define string-contains?
    (lambda (haystack needle)
      (let ((hlen (string-length haystack))
            (nlen (string-length needle)))
        (let loop ((i 0))
          (cond
            ((> (+ i nlen) hlen) #f)
            ((string=? (substring haystack i (+ i nlen)) needle) #t)
            (else (loop (+ i 1))))))))

  (define status-code->reason
    (lambda (code)
      (case code
        ((200) "OK")
        ((201) "Created")
        ((204) "No Content")
        ((301) "Moved Permanently")
        ((302) "Found")
        ((304) "Not Modified")
        ((400) "Bad Request")
        ((401) "Unauthorized")
        ((403) "Forbidden")
        ((404) "Not Found")
        ((405) "Method Not Allowed")
        ((500) "Internal Server Error")
        (else "OK"))))

  (define response
    (lambda (type obj)
      (case type
        ((json) (cons (string->utf8 (jsonify obj)) "application/json"))
        ((html) (cons (string->utf8 (html-write obj)) "text/html"))
        ((xml)  (cons (string->utf8 (xml-write obj)) "application/xml"))
        ((text) (cons (string->utf8 obj) "text/plain"))
        (else (error 'transparent "Unknown response type" type)))))

  (define json (lambda (obj) (response 'json obj)))
  (define html (lambda (obj) (response 'html obj)))
  (define xml  (lambda (obj) (response 'xml obj)))

  (define http-response-write*
    (lambda (write-proc status reason headers body-bv)
      (http-response-write
        write-proc "HTTP/1.1" status reason headers
        (let ((done #f))
          (lambda ()
            (if done (eof-object) (begin (set! done #t) body-bv)))))))

  (define handle-connection
    (lambda (app-state init handler read write close)
      (define chunk-reader
        (lambda ()
          (let ((result (read)))
            (if (bytevector? result) result (eof-object)))))
      (guard (ex (else (guard (ex2 (else (void))) (close))))
        (let-values (((read-byte! read-bytes!) (make-http-reader chunk-reader)))
          (let loop ()
            (let-values (((method uri version headers body)
                          (%http-request-read read-byte! read-bytes!)))
              (if (not method)
                  (close)
                  (begin
                    (guard (ex
                      (else
                        (http-response-write*
                          write 500 "Internal Server Error"
                          '((content-type . "text/plain"))
                          (string->utf8 "Internal Server Error"))))
                      (let* ((request-state (init))
                             (uri-parts (call-with-values (lambda () (uri-parse uri)) list))
                             (path (car uri-parts))
                             (params (or (cadr uri-parts) '()))
                             (parsed-body
                              (if (and (bytevector? body)
                                       (fx>? (bytevector-length body) 0)
                                       (let ((ct (assq 'content-type headers)))
                                         (and ct (string-contains? (cdr ct) "json"))))
                                  (guard (ex (else (eof-object)))
                                    (unjson (utf8->string body)))
                                  (eof-object))))
                        (let-values (((status response-pair extra-headers)
                                      (handler app-state request-state method path params parsed-body)))
                          (http-response-write*
                            write status (status-code->reason status)
                            (cons (cons 'content-type (cdr response-pair)) extra-headers)
                            (car response-pair)))))
                    (loop)))))))))

  (define transparent
    (lambda (port-number app init handler)
      (untangle-new)
      (untangle-spawn
        (lambda ()
          (define app-state (app))
          (call-with-values (lambda () (untangle-tcp-serve "0.0.0.0" port-number))
            (lambda (accept close)
              (format #t "transparent server at http://127.0.0.1:~a/\n" port-number)
              (flush-output-port)
              (let loop ()
                (call-with-values accept
                  (lambda (read write close)
                    (when (and read write close)
                      (untangle-spawn
                        (lambda () (handle-connection app-state init handler read write close))))))
                (loop))))))
      (untangle-run)))

)
