#!chezscheme
(library (transparenturing)

  (export transparent json html xml match
          loop-new loop-run loop-sleep loop-spawn loop-close loop-stop
          www-request)

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
         (dynamic-wind
           (lambda () (for-each lock-object objects*))
           (lambda () body ...)
           (lambda () (for-each unlock-object objects*)))))))

  (define (bytevector-pointer bv)
    (#%$object-address bv (+ (foreign-sizeof 'void*) 1)))

  (define strerror
    (let ((func (foreign-procedure "strerror" (int) string)))
      (lambda (code)
        (func code))))

  (define %strlen (foreign-procedure "strlen" (void*) size_t))

  (define (pointer->string p)
    (if (zero? p)
        #f
        (let* ((len (%strlen p))
               (bv (make-bytevector len)))
          (let loop ((i 0))
            (when (< i len)
              (bytevector-u8-set! bv i (foreign-ref 'unsigned-8 p i))
              (loop (+ i 1))))
          (utf8->string bv))))

  ;; fcntl / non-blocking socket support
  (define fcntl!
    (let ((func (foreign-procedure __atomic "fcntl" (int int int) int)))
      (lambda (fd cmd arg)
        (func fd cmd arg))))

  (define fcntl
    (let ((func (foreign-procedure __atomic "fcntl" (int int) int)))
      (lambda (fd cmd)
        (func fd cmd))))

  (define %F_GETFL 3)
  (define %F_SETFL 4)
  (define %O_NONBLOCK 2048)

  (define loop-nonblock!
    (lambda (fd)
      (fcntl! fd %F_SETFL
              (fxlogior %O_NONBLOCK
                        (fcntl fd %F_GETFL)))))

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
  ;; Section 6: Event loop (from new-loop)
  ;; ============================================================

  ;; ---- io_uring FFI (inlined from letloop liburing low) ----

  (define liburing-ffi (load-shared-object "liburing-ffi.so.2"))

  (define io-uring-size 216)
  (define kernel-timespec-size 16)

  (define-ftype <kernel-timespec>
    (struct
     (seconds long-long)
     (nanoseconds long-long)))

  (define-ftype <cqe>
    (struct
     (user-data unsigned-64)
     (res integer-32)
     (flags unsigned-32)))

  (define make-io-uring
    (lambda ()
      (foreign-alloc io-uring-size)))

  (define make-cqe-pointer
    (lambda ()
      (foreign-alloc 8)))

  (define make-timespec
    (lambda (seconds nanoseconds)
      (let ((out (make-ftype-pointer
                  <kernel-timespec>
                  (foreign-alloc (ftype-sizeof <kernel-timespec>)))))
        (ftype-set! <kernel-timespec> (seconds) out seconds)
        (ftype-set! <kernel-timespec> (nanoseconds) out nanoseconds)
        out)))

  (define io-uring-queue-init
    (let ((func (foreign-procedure "io_uring_queue_init"
                                   (unsigned void* unsigned) int)))
      (lambda (entries ring flags)
        (func entries ring flags))))

  (define io-uring-queue-exit
    (let ((func (foreign-procedure "io_uring_queue_exit" (void*) void)))
      (lambda (ring)
        (func ring))))

  (define io-uring-get-sqe
    (let ((func (foreign-procedure "io_uring_get_sqe" (void*) void*)))
      (lambda (ring)
        (let ((sqe (func ring)))
          (when (eqv? sqe 0)
            (error 'transparenturing "SQ full: io_uring_get_sqe returned NULL"))
          sqe))))

  (define io-uring-sqe-set-data64
    (let ((func (foreign-procedure "io_uring_sqe_set_data64"
                                   (void* unsigned-64) void)))
      (lambda (sqe data)
        (func sqe data))))

  (define io-uring-submit
    (let ((func (foreign-procedure "io_uring_submit" (void*) int)))
      (lambda (ring)
        (func ring))))

  (define io-uring-wait-cqe
    (let ((func (foreign-procedure "io_uring_wait_cqe"
                                   (void* void*) int)))
      (lambda (ring cqe-ptr)
        (func ring cqe-ptr))))

  (define io-uring-wait-cqe-timeout
    (let ((func (foreign-procedure "io_uring_wait_cqe_timeout"
                                   (void* void* void*) int)))
      (lambda (ring cqe-ptr ts)
        (func ring cqe-ptr (ftype-pointer-address ts)))))

  (define io-uring-peek-cqe
    (let ((func (foreign-procedure "io_uring_peek_cqe"
                                   (void* void*) int)))
      (lambda (ring cqe-ptr)
        (func ring cqe-ptr))))

  (define io-uring-cqe-seen
    (let ((func (foreign-procedure "io_uring_cqe_seen"
                                   (void* void*) void)))
      (lambda (ring cqe)
        (func ring cqe))))

  (define io-uring-cqe-get-data64
    (let ((func (foreign-procedure "io_uring_cqe_get_data64"
                                   (void*) unsigned-64)))
      (lambda (cqe)
        (func cqe))))

  (define io-uring-cqe-get-res
    (lambda (cqe)
      (ftype-ref <cqe> (res)
                 (make-ftype-pointer <cqe> cqe))))

  (define io-uring-cqe-get-flags
    (lambda (cqe)
      (ftype-ref <cqe> (flags)
                 (make-ftype-pointer <cqe> cqe))))

  (define IORING-CQE-F-MORE 2)
  (define IORING-CQE-F-BUFFER 1)
  (define IOSQE-IO-LINK 4)
  (define IOSQE-BUFFER-SELECT (bitwise-arithmetic-shift-left 1 5))

  (define io-uring-sqe-set-flags
    (let ((func (foreign-procedure "io_uring_sqe_set_flags"
                                   (void* unsigned) void)))
      (lambda (sqe flags)
        (func sqe flags))))

  (define io-uring-sqe-set-buf-group
    (let ((func (foreign-procedure "io_uring_sqe_set_buf_group"
                                   (void* int) void)))
      (lambda (sqe bgid)
        (func sqe bgid))))

  (define io-uring-setup-buf-ring
    (let ((func (foreign-procedure "io_uring_setup_buf_ring"
                                   (void* unsigned int unsigned void*) void*)))
      (lambda (ring nentries bgid flags err-ptr)
        (func ring nentries bgid flags err-ptr))))

  (define io-uring-buf-ring-add
    (let ((func (foreign-procedure "io_uring_buf_ring_add"
                                   (void* void* unsigned unsigned-16
                                          int int) void)))
      (lambda (br addr len bid mask buf-offset)
        (func br addr len bid mask buf-offset))))

  (define io-uring-buf-ring-advance
    (let ((func (foreign-procedure "io_uring_buf_ring_advance"
                                   (void* int) void)))
      (lambda (br count)
        (func br count))))

  (define io-uring-buf-ring-mask
    (let ((func (foreign-procedure "io_uring_buf_ring_mask"
                                   (unsigned-32) int)))
      (lambda (ring-entries)
        (func ring-entries))))

  (define io-uring-prep-timeout
    (let ((func (foreign-procedure "io_uring_prep_timeout"
                                   (void* void* unsigned unsigned) void)))
      (lambda (sqe ts count flags)
        (func sqe ts count flags))))

  (define io-uring-prep-link-timeout
    (let ((func (foreign-procedure "io_uring_prep_link_timeout"
                                   (void* void* unsigned) void)))
      (lambda (sqe ts flags)
        (func sqe ts flags))))

  (define io-uring-prep-close
    (let ((func (foreign-procedure "io_uring_prep_close"
                                   (void* int) void)))
      (lambda (sqe fd)
        (func sqe fd))))

  (define io-uring-prep-cancel64
    (let ((func (foreign-procedure "io_uring_prep_cancel64"
                                   (void* unsigned-64 int) void)))
      (lambda (sqe user-data flags)
        (func sqe user-data flags))))

  (define memcpy
    (let ((func (foreign-procedure "memcpy" (void* void* size_t) void*)))
      (lambda (dest src n)
        (func dest src n))))

  (define io-uring-prep-accept
    (let ((func (foreign-procedure "io_uring_prep_accept"
                                   (void* int void* void* int) void)))
      (lambda (sqe fd addr addrlen flags)
        (func sqe fd addr addrlen flags))))

  (define io-uring-prep-multishot-accept
    (let ((func (foreign-procedure "io_uring_prep_multishot_accept"
                                   (void* int void* void* int) void)))
      (lambda (sqe fd addr addrlen flags)
        (func sqe fd addr addrlen flags))))

  (define io-uring-prep-recv
    (let ((func (foreign-procedure "io_uring_prep_recv"
                                   (void* int void* size_t int) void)))
      (lambda (sqe sockfd buf len flags)
        (func sqe sockfd buf len flags))))

  (define io-uring-prep-send
    (let ((func (foreign-procedure "io_uring_prep_send"
                                   (void* int void* size_t int) void)))
      (lambda (sqe sockfd buf len flags)
        (func sqe sockfd buf len flags))))

  (define io-uring-submit-and-wait-timeout
    (let ((func (foreign-procedure "io_uring_submit_and_wait_timeout"
                                   (void* void* unsigned void* void*) int)))
      (lambda (ring cqe-ptr wait-nr ts sigmask)
        (func ring cqe-ptr wait-nr ts sigmask))))

  (define io-uring-sq-ready
    (let ((func (foreign-procedure "io_uring_sq_ready"
                                   (void*) unsigned)))
      (lambda (ring)
        (func ring))))

  (define io-uring-prep-connect
    (let ((func (foreign-procedure "io_uring_prep_connect"
                                   (void* int void* unsigned) void)))
      (lambda (sqe fd addr addrlen)
        (func sqe fd addr addrlen))))

  (define io-uring-prep-poll-add
    (let ((func (foreign-procedure "io_uring_prep_poll_add"
                                   (void* int unsigned) void)))
      (lambda (sqe fd poll-mask)
        (func sqe fd poll-mask))))

  (define POLLIN 1)
  (define POLLOUT 4)

  (define %loop #f)

  ;; Multishot accept tracking (fd → id, id → fd)
  (define %multishots (make-eqv-hashtable))
  (define %multishot-ids (make-eqv-hashtable))

  ;; Buffer ring state
  (define %buf-ring-nentries 4096)
  (define %buf-ring-buf-size 4096)
  (define %buf-ring-bgid 0)
  (define %buf-ring #f)        ;; pointer to buffer ring struct
  (define %buf-ring-base 0)    ;; base address of buffer memory
  (define %buf-ring-mask 0)    ;; ring mask
  (define %buf-data (make-eqv-hashtable))  ;; id → bytevector (extracted buffer data)

  ;; Read timeout: 30 seconds — defends against Slowloris and cleans up
  ;; orphaned connections after clients disconnect
  (define %read-timeout-seconds 5)
  (define %read-timeout-ts #f)  ;; allocated in loop-new
  (define %wait-timeout #f)     ;; 1s timeout for wait-cqe, allows signal delivery

  (define loop-prompt-current #f)

  (define loop-prompt-singleton '(loop-prompt-singleton))

  (define-record-type* <loop>
    (loop-base-new jiffy sleeping running ring cqe-ptr handlers next-id thunks)
    loop?
    (jiffy %loop-jiffy %loop-jiffy!)
    (sleeping loop-sleeping loop-sleeping!)
    (running loop-running? loop-running!)
    (ring loop-ring)
    (cqe-ptr loop-cqe-ptr)
    (handlers loop-handlers)
    (next-id loop-next-id loop-next-id!)
    (thunks loop-thunks loop-thunks!))

  (define loop-alloc-id!
    (lambda ()
      (let ((id (loop-next-id %loop)))
        (loop-next-id! %loop (fx+ id 1))
        id)))

  (define call-with-loop-prompt
    (lambda (thunk handlery)
      (call-with-values (lambda ()
                          (call/1cc
                           (lambda (k)
                             (set! loop-prompt-current k)
                             (thunk))))
        (lambda out
          (cond
           ((and (pair? out) (eq? (car out) loop-prompt-singleton))
            (apply handlery (cdr out)))
           (else (apply values out)))))))

  (define loop-abort
    (lambda args
      (call/cc
       (lambda (k)
         (let ((prompt loop-prompt-current))
           (set! loop-prompt-current #f)
           (apply prompt (cons loop-prompt-singleton (cons k args))))))))

  (define loop-apply
    (lambda (thunk)
      (guard (ex (else (void)))
        (call-with-loop-prompt thunk (lambda (k handler) (handler k))))))

  (define jiffy-current
    (lambda ()
      (let* ((time (current-time 'time-monotonic))
             (seconds (time-second time))
             (nanoseconds (time-nanosecond time)))
        (+ (* seconds (expt 10 9)) nanoseconds))))

  (define loop-run-once
    (lambda ()
      ;; 1. Run queued thunks (may prep SQEs)
      (let ((thunks (loop-thunks %loop)))
        (loop-thunks! %loop '())
        (for-each (lambda (thunk) (loop-apply thunk)) thunks))

      ;; 2. Submit pending SQEs + wait for CQEs
      (let ((ring (loop-ring %loop))
            (cqe-ptr (loop-cqe-ptr %loop)))
        (let ((has-handlers? (not (fxzero? (hashtable-size (loop-handlers %loop)))))
              (has-pending? (not (fxzero? (io-uring-sq-ready ring)))))
          (cond
           ;; Have handlers: submit pending SQEs, then wait for a CQE
           ;; Use a 1-second timeout so signals (SIGINT) are delivered between calls
           (has-handlers?
            (io-uring-submit ring)
            (io-uring-wait-cqe-timeout ring cqe-ptr %wait-timeout))
           ;; No handlers but pending SQEs: submit without waiting
           (has-pending?
            (io-uring-submit ring))
           (else (void))))

        ;; 3. Drain all available CQEs (resumed coroutines may prep new SQEs)
        (let drain ()
          (when (fxzero? (io-uring-peek-cqe ring cqe-ptr))
            (let* ((cqe (foreign-ref 'void* cqe-ptr 0))
                   (id (io-uring-cqe-get-data64 cqe))
                   (res (io-uring-cqe-get-res cqe))
                   (flags (io-uring-cqe-get-flags cqe)))
              (io-uring-cqe-seen ring cqe)
              ;; If multishot CQE without MORE flag, the multishot ended
              (when (fxzero? (fxlogand flags IORING-CQE-F-MORE))
                (let ((ms-fd (hashtable-ref %multishot-ids id #f)))
                  (when ms-fd
                    (hashtable-delete! %multishot-ids id)
                    (hashtable-delete! %multishots ms-fd))))
              ;; If buffer was selected, extract data and return buffer to ring
              (when (and (fx>? res 0)
                         (not (fxzero? (fxlogand flags IORING-CQE-F-BUFFER))))
                (let* ((bid (fxsrl (fxlogand flags #xFFFF0000) 16))
                       (buf-addr (+ %buf-ring-base (* bid %buf-ring-buf-size)))
                       (bv (make-bytevector res)))
                  (with-lock (list bv)
                    (memcpy (bytevector-pointer bv) buf-addr res))
                  ;; Return buffer to ring for reuse
                  (io-uring-buf-ring-add %buf-ring buf-addr %buf-ring-buf-size
                                         bid %buf-ring-mask 0)
                  (io-uring-buf-ring-advance %buf-ring 1)
                  ;; Stash for loop-read to retrieve
                  (hashtable-set! %buf-data id bv)))
              (let ((handler (hashtable-ref (loop-handlers %loop) id #f)))
                (hashtable-delete! (loop-handlers %loop) id)
                (when handler
                  (loop-apply (lambda () (handler res))))))
            (drain)))

        ;; 4. Flush SQEs prepped during drain (avoids extra loop iteration latency)
        (when (not (fxzero? (io-uring-sq-ready ring)))
          (io-uring-submit ring)))))

  (define loop-run
    (lambda ()
      (let loop ()
        (when (loop-running? %loop)
          (guard (ex (else (loop-running! %loop #f)))
            (loop-run-once))
          (loop)))))

  (define loop-spawn
    (lambda (thunk)
      (loop-thunks! %loop
                        (cons thunk (loop-thunks %loop)))))

  (define loop-new
    (lambda ()
      (let ((ring (make-io-uring))
            (cqe-ptr (make-cqe-pointer))
            (handlers (make-eqv-hashtable)))
        (let ((ret (io-uring-queue-init 4096 ring 0)))
          (unless (fxzero? ret)
            (error 'transparenturing
                   (format #f "io_uring_queue_init failed: ~a" (strerror (fx- 0 ret))))))
        (set! %loop
          (loop-base-new (jiffy-current)
                         (sq-new)
                         #t
                         ring
                         cqe-ptr
                         handlers
                         0
                         '()))
        (set! %read-timeout-ts (make-timespec %read-timeout-seconds 0))
        (set! %wait-timeout (make-timespec 1 0))
        (set! %multishots (make-eqv-hashtable))
        (set! %multishot-ids (make-eqv-hashtable))
        (set! %buf-data (make-eqv-hashtable))
        ;; Set up provided buffer ring
        (let ((err-ptr (foreign-alloc 4)))
          (foreign-set! 'integer-32 err-ptr 0 0)
          (let ((br (io-uring-setup-buf-ring ring %buf-ring-nentries
                                             %buf-ring-bgid 0 err-ptr)))
            (let ((err (foreign-ref 'integer-32 err-ptr 0)))
              (foreign-free err-ptr)
              (when (eqv? br 0)
                (error 'transparenturing
                       (format #f "io_uring_setup_buf_ring failed: ~a"
                               (strerror (fx- 0 err))))))
            (let ((base (foreign-alloc (* %buf-ring-nentries %buf-ring-buf-size)))
                  (mask (io-uring-buf-ring-mask %buf-ring-nentries)))
              ;; Fill ring with buffers
              (let fill ((i 0))
                (when (fx<? i %buf-ring-nentries)
                  (io-uring-buf-ring-add br (+ base (* i %buf-ring-buf-size))
                                         %buf-ring-buf-size i mask i)
                  (fill (fx+ i 1))))
              (io-uring-buf-ring-advance br %buf-ring-nentries)
              (set! %buf-ring br)
              (set! %buf-ring-base base)
              (set! %buf-ring-mask mask))))
        %loop)))

  (define loop-socket-new
    (let ((socket-foreign (foreign-procedure __atomic __disable_interrupts __errno "socket" (int int int) int)))
      (lambda (domain type protocol)
        (call-with-values (lambda () (socket-foreign domain type protocol))
          (lambda (out errno)
            (if (fx=? out -1)
                #f
                out))))))

  (define loop-accept
    (lambda (fd)
      ;; Multishot: submit once, get one CQE per incoming connection
      (let ((active-id (hashtable-ref %multishots fd #f)))
        (unless active-id
          ;; No active multishot for this fd — submit one
          (let* ((sqe (io-uring-get-sqe (loop-ring %loop)))
                 (id (loop-alloc-id!)))
            (io-uring-prep-multishot-accept sqe fd 0 0 0)
            (io-uring-sqe-set-data64 sqe id)
            (hashtable-set! %multishots fd id)
            (hashtable-set! %multishot-ids id fd)
            (set! active-id id)))
        (let ((res (loop-abort
                     (lambda (k)
                       (hashtable-set! (loop-handlers %loop) active-id k)))))
          (if (fx<? res 0)
              (begin
                ;; Error — multishot may have ended, clean up just in case
                (let ((mid (hashtable-ref %multishots fd #f)))
                  (when mid
                    (hashtable-delete! %multishots fd)
                    (hashtable-delete! %multishot-ids mid)))
                #f)
              (begin
                (loop-socket-option! res 6 'tcp-option/nodelay #t)
                (loop-socket-option! res 1 'socket-option/keepalive #t)
                res))))))

  (define IORING-ASYNC-CANCEL-ALL 1)
  (define IORING-ASYNC-CANCEL-FD 2)

  (define loop-close
    (lambda (fd)
      ;; Cancel all pending io_uring operations on this fd first,
      ;; otherwise orphaned recv/send SQEs never get CQEs and leak handlers
      (let* ((cancel-sqe (io-uring-get-sqe (loop-ring %loop)))
             (cancel-id (loop-alloc-id!)))
        (io-uring-prep-cancel64 cancel-sqe fd
                                (fxlogor IORING-ASYNC-CANCEL-ALL IORING-ASYNC-CANCEL-FD))
        (io-uring-sqe-set-data64 cancel-sqe cancel-id)
        (loop-abort
          (lambda (k)
            (hashtable-set! (loop-handlers %loop) cancel-id k))))
      ;; Now close the fd
      (let* ((sqe (io-uring-get-sqe (loop-ring %loop)))
             (id (loop-alloc-id!)))
        (io-uring-prep-close sqe fd)
        (io-uring-sqe-set-data64 sqe id)
        (let ((res (loop-abort
                     (lambda (k)
                       (hashtable-set! (loop-handlers %loop) id k)))))
          res))))


  (define loop-socket-option!
    (let ((loop-socket-option-foreign! (foreign-procedure __atomic __disable_interrupts __errno "setsockopt" (int int int void* int) int)))
      (lambda (fd level optname optval)

        (define (doit opt-int)
          (let* ((size (ftype-sizeof int))
                 (pointer (foreign-alloc size)))
            (foreign-set! 'int pointer 0 (if optval 1 0))
            (call-with-values (lambda () (loop-socket-option-foreign! fd level opt-int pointer size))
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

  (define loop-socket-error?
    (let ((getsockopt-foreign (foreign-procedure __atomic __disable_interrupts __errno "getsockopt" (int int int void* void*) int)))
      (lambda (fd)
        (let* ((val-size (ftype-sizeof int))
               (val-ptr (foreign-alloc val-size))
               (len-ptr (foreign-alloc (ftype-sizeof int))))
          (foreign-set! 'int val-ptr 0 0)
          (foreign-set! 'int len-ptr 0 val-size)
          (call-with-values (lambda () (getsockopt-foreign fd 1 4 val-ptr len-ptr))
            (lambda (out errno)
              (let ((so-error (foreign-ref 'int val-ptr 0)))
                (foreign-free len-ptr)
                (foreign-free val-ptr)
                (not (fxzero? so-error)))))))))

  (define loop-bind
    (let ((loop-bind-foreign (foreign-procedure __atomic __disable_interrupts __errno "bind" (int void* size_t) int)))
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

        (loop-socket-option! fd 1 'socket-option/reuseaddr #t)
        (loop-socket-option! fd 1 'socket-option/reuseport #t)

        (call-with-values (lambda () (socket-address-in-new ip port))
          (lambda (pointer address)
            (call-with-values (lambda ()
                               (loop-bind-foreign fd
                                                      pointer
                                                      (ftype-sizeof <socket-address-in>)))
              (lambda (out errno)
                (foreign-free pointer)
                (unless (fxzero? out)
                  (error 'transparent (format #f "bind errno ~a" (strerror errno)))))))))))

  (define loop-listen
    (let ((loop-listen-foreign (foreign-procedure __atomic __disable_interrupts __errno "listen" (int int) int)))
      (lambda (fd backlog)
        (call-with-values (lambda () (loop-listen-foreign fd backlog))
          (lambda (out errno)
            (unless (fxzero? out)
              (error 'transparent (format #f "listen errno ~a" (strerror errno)))))))))

  (define loop-getpeername
    (let ((getpeername-foreign (foreign-procedure __atomic __disable_interrupts __errno "getpeername" (int void* void*) int)))
      (lambda (fd)
        (let* ((addr-ptr (foreign-alloc (ftype-sizeof <sockaddr-in>)))
               (addr (make-ftype-pointer <sockaddr-in> addr-ptr))
               (len-ptr (foreign-alloc (foreign-sizeof 'unsigned-32)))
               (_ (foreign-set! 'unsigned-32 len-ptr 0 (ftype-sizeof <sockaddr-in>))))
          (call-with-values (lambda () (getpeername-foreign fd addr-ptr len-ptr))
            (lambda (out errno)
              (let ((ip (if (fxzero? out)
                            (let ((raw (ftype-ref <sockaddr-in> (address) addr)))
                              (format #f "~a.~a.~a.~a"
                                      (fxsrl raw 24)
                                      (fxand (fxsrl raw 16) #xff)
                                      (fxand (fxsrl raw 8) #xff)
                                      (fxand raw #xff)))
                            #f)))
                (foreign-free len-ptr)
                (foreign-free addr-ptr)
                ip)))))))

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

  (define loop-read
    (lambda (fd)
      (let* ((sqe (io-uring-get-sqe (loop-ring %loop)))
             (id (loop-alloc-id!)))
        ;; Use provided buffer ring — no bytevector allocation or locking needed
        ;; Link a timeout SQE so idle connections are cleaned up (Slowloris defense)
        (io-uring-prep-recv sqe fd 0 %buf-ring-buf-size 0)
        (io-uring-sqe-set-flags sqe (fxlogor IOSQE-BUFFER-SELECT IOSQE-IO-LINK))
        (io-uring-sqe-set-buf-group sqe %buf-ring-bgid)
        (io-uring-sqe-set-data64 sqe id)
        ;; Linked timeout: if recv doesn't complete within %read-timeout-seconds,
        ;; the kernel cancels it and delivers res=-ECANCELED
        (let* ((timeout-sqe (io-uring-get-sqe (loop-ring %loop)))
               (timeout-id (loop-alloc-id!)))
          (io-uring-prep-link-timeout timeout-sqe
                                      (ftype-pointer-address %read-timeout-ts) 0)
          (io-uring-sqe-set-data64 timeout-sqe timeout-id)
          ;; No handler for timeout — if recv completes first, timeout CQE
          ;; arrives with -ECANCELED and is harmlessly ignored (no handler)
          )
        (let ((res (loop-abort
                     (lambda (k)
                       (hashtable-set! (loop-handlers %loop) id k)))))
          (cond
            ((fx<? res 0)
             (hashtable-delete! %buf-data id)
             #f)  ;; error or -ECANCELED from timeout
            ((fxzero? res)
             (hashtable-delete! %buf-data id)
             #t)    ;; EOF
            (else
             ;; Buffer data was extracted by drain loop
             (let ((bv (hashtable-ref %buf-data id #f)))
               (hashtable-delete! %buf-data id)
               bv)))))))

  (define loop-write
    (lambda (fd bv)
      (let write-loop ((bv bv))
        (lock-object bv)
        (let* ((sqe (io-uring-get-sqe (loop-ring %loop)))
               (id (loop-alloc-id!)))
          (io-uring-prep-send sqe fd (bytevector-pointer bv) (bytevector-length bv) 0)
          (io-uring-sqe-set-data64 sqe id)
          (let ((res (loop-abort
                       (lambda (k)
                         (hashtable-set! (loop-handlers %loop) id k)))))
            (unlock-object bv)
            (cond
              ((fx<=? res 0) #f)
              ((fx=? res (bytevector-length bv)) #t)
              (else (write-loop (subbytevector bv res)))))))))

  (define loop-tcp-serve
    (lambda (ip port)
      (define SOCKET-DOMAIN=AF-INET 2)
      (define SOCKET-TYPE=STREAM 1)
      (define fd (loop-socket-new SOCKET-DOMAIN=AF-INET SOCKET-TYPE=STREAM 0))

      (define accept
        (lambda ()
          (define client (loop-accept fd))
          (if (not client)
              (values #f #f #f #f)
              (let ((peer-ip (loop-getpeername client)))
                (values (lambda () (loop-read client))
                        (lambda (bv) (loop-write client bv))
                        (lambda () (loop-close client))
                        peer-ip)))))

      (loop-bind fd ip port)
      (loop-listen fd 128)

      (values accept (lambda () (loop-close fd)))))

  (define loop-sleep
    (lambda (seconds)
      (let* ((nanoseconds (exact (round (* seconds 1000000000))))
             (sqe (io-uring-get-sqe (loop-ring %loop)))
             (id (loop-alloc-id!))
             (ts (make-timespec (div nanoseconds 1000000000)
                                (mod nanoseconds 1000000000))))
        (io-uring-prep-timeout sqe (ftype-pointer-address ts) 0 0)
        (io-uring-sqe-set-data64 sqe id)
        (let ((res (loop-abort
                     (lambda (k)
                       (hashtable-set! (loop-handlers %loop) id k)))))
          (foreign-free (ftype-pointer-address ts))
          res))))

  (define loop-stop
    (lambda ()
      (loop-running! %loop #f)
      ;; Cancel all pending multishot accepts
      (let-values (((keys vals) (hashtable-entries %multishots)))
        (vector-for-each
          (lambda (fd id)
            (let ((sqe (io-uring-get-sqe (loop-ring %loop))))
              (io-uring-prep-cancel64 sqe id 0)
              (io-uring-sqe-set-data64 sqe (loop-alloc-id!))))
          keys vals))
      ;; Submit cancellations
      (when (not (fxzero? (io-uring-sq-ready (loop-ring %loop))))
        (io-uring-submit (loop-ring %loop)))))

  (define loop-connect
    (lambda (addr addrlen)
      (let ((fd (loop-socket-new 2 1 0)))  ;; AF_INET, SOCK_STREAM
        (unless fd (error 'loop-connect "socket failed"))
        (loop-nonblock! fd)
        (let* ((sqe (io-uring-get-sqe (loop-ring %loop)))
               (id (loop-alloc-id!)))
          (io-uring-prep-connect sqe fd addr addrlen)
          (io-uring-sqe-set-data64 sqe id)
          (let ((res (loop-abort
                       (lambda (k)
                         (hashtable-set! (loop-handlers %loop) id k)))))
            (if (fx<? res 0)
                (begin (loop-close fd) #f)
                fd))))))

  (define loop-poll-wait
    (lambda (fd poll-mask)
      (let* ((sqe (io-uring-get-sqe (loop-ring %loop)))
             (id (loop-alloc-id!)))
        (io-uring-prep-poll-add sqe fd poll-mask)
        (io-uring-sqe-set-data64 sqe id)
        (loop-abort
          (lambda (k)
            (hashtable-set! (loop-handlers %loop) id k))))))

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
            (error 'http "Unexpected end of file"))
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
                            (list->string (massage* (reverse (massage* (reverse (cdr chars)))))))
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
                              (and value (string-ci=? (cdr value) "chunked")))))
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
           (string-ci=? (cdr pair) "chunked"))))

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
            ;; Check write results — abort on broken pipe (client disconnected)
            (unless (accumulator (string->utf8 (string-append response-line header-str "\r\n")))
              (error 'http "write failed"))
            (for-each (lambda (chunk)
                        (unless (accumulator chunk)
                          (error 'http "write failed")))
                      chunks))))))

  ;; http-request-write (for client requests)
  (define http-request-write
    (lambda (accumulator method target version headers body)
      ;; body is (lambda () -> bytevector | eof-object)
      (let ((chunks (generator->list body)))
        (let ((content-length (apply fx+ (map bytevector-length chunks))))
          (let* ((headers* (massage-headers-content-length headers content-length))
                 (request-line (format #f "~a ~a ~a\r\n" method target version))
                 (header-str (apply string-append (map (lambda (x) (format #f "~a: ~a\r\n" (car x) (cdr x))) headers*))))
            (accumulator (string->utf8 (string-append request-line header-str "\r\n")))
            (for-each accumulator chunks))))))

  ;; http-response-read (for client responses)
  (define http-response-read
    (lambda (read)
      ;; READ is (lambda () -> bytevector | eof-object)

      (define response-line-read
        (lambda (read-byte!)

          (define massage
            (lambda (line-bv)
              (let loop ((bytes (bytevector->u8-list line-bv))
                         (chunk '())
                         (out '()))
                (if (null? bytes)
                    (if (null? chunk)
                        (error 'http "Invalid response line")
                        (reverse (cons (utf8->string (u8-list->bytevector (reverse chunk))) out)))
                    (let ((byte (car bytes)))
                      (if (and (fx=? byte byte-space) (not (null? chunk)))
                          (loop (cdr bytes) '() (cons (utf8->string (u8-list->bytevector (reverse chunk))) out))
                          (loop (cdr bytes) (cons byte chunk) out)))))))

          (let ((strings (massage (http-line-read read-byte!))))
            (values (string->symbol (car strings)) (string->number (cadr strings)) #f))))

      (let-values (((read-byte! read-bytes!) (make-http-reader read)))
        (call-with-values (lambda () (response-line-read read-byte!))
          (lambda (version code reason)
            (let ((headers (http-headers-read read-byte!)))
              (values version code reason headers (http-body-read read-byte! read-bytes! headers))))))))

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

  (define (json-expect value expected)
    (when (eof-object? value)
      (raise (make-json-error "Unexpected end-of-file.")))
    (unless (char=? value expected)
      (raise (make-json-error "Unexpected character."))))

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
                              (string->html-string (format #f "~a" (cadr attribute))))))
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
              (accumulator (format #f " ~a=\"~a\"" (car attribute) (string->html-string (format #f "~a" (cadr attribute))))))
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
  ;; Section 12a: Async DNS resolver
  ;; ============================================================

  (define %dns-nameserver #f)

  (define %dns-read-resolv-conf
    (lambda ()
      (guard (ex (else "8.8.8.8"))
        (let ((lines (call-with-input-file "/etc/resolv.conf"
                       (lambda (port)
                         (let loop ((out '()))
                           (let ((line (get-line port)))
                             (if (eof-object? line)
                                 (reverse out)
                                 (loop (cons line out)))))))))
          (let find ((lines lines))
            (if (null? lines)
                "8.8.8.8"
                (let ((line (car lines)))
                  (if (and (> (string-length line) 11)
                           (string=? "nameserver " (substring line 0 11)))
                      (let ((ns (substring line 11 (string-length line))))
                        ;; Trim trailing whitespace
                        (let trim ((s ns))
                          (if (and (> (string-length s) 0)
                                   (char<=? (string-ref s (- (string-length s) 1)) #\space))
                              (trim (substring s 0 (- (string-length s) 1)))
                              s)))
                      (find (cdr lines))))))))))

  (define %dns-get-nameserver
    (lambda ()
      (unless %dns-nameserver
        (set! %dns-nameserver (%dns-read-resolv-conf)))
      %dns-nameserver))

  (define %dns-encode-name
    (lambda (hostname)
      ;; "example.com" → #vu8(7 101 120 97 109 112 108 101 3 99 111 109 0)
      (let ((parts (let split ((chars (string->list hostname))
                                (current '())
                                (out '()))
                     (cond
                       ((null? chars)
                        (reverse (cons (list->string (reverse current)) out)))
                       ((char=? (car chars) #\.)
                        (split (cdr chars) '()
                               (cons (list->string (reverse current)) out)))
                       (else
                        (split (cdr chars) (cons (car chars) current) out))))))
        (let ((bvs (map (lambda (part)
                          (let ((bv (string->utf8 part)))
                            (let ((out (make-bytevector (+ 1 (bytevector-length bv)))))
                              (bytevector-u8-set! out 0 (bytevector-length bv))
                              (bytevector-copy! bv 0 out 1 (bytevector-length bv))
                              out)))
                        parts)))
          (apply bytevector-append (append bvs (list (bytevector 0))))))))

  (define %dns-build-query
    (lambda (hostname)
      (let* ((id-hi (random 256))
             (id-lo (random 256))
             (header (bytevector id-hi id-lo
                                 1 0    ;; QR=0, OPCODE=0, RD=1
                                 0 1    ;; QDCOUNT=1
                                 0 0    ;; ANCOUNT=0
                                 0 0    ;; NSCOUNT=0
                                 0 0))  ;; ARCOUNT=0
             (name (%dns-encode-name hostname))
             (qtype (bytevector 0 1))   ;; A record
             (qclass (bytevector 0 1))) ;; IN class
        (bytevector-append header name qtype qclass))))

  (define %dns-parse-response
    (lambda (bv)
      ;; Returns (values a b c d) for IPv4 or #f on failure
      (guard (ex (else #f))
        (when (< (bytevector-length bv) 12)
          (error 'dns "Response too short"))
        ;; Check QR=1 (response)
        (let ((flags (bytevector-u8-ref bv 2)))
          (unless (not (fxzero? (fxlogand flags #x80)))
            (error 'dns "Not a response")))
        ;; Check RCODE=0
        (let ((rcode (fxlogand (bytevector-u8-ref bv 3) #x0F)))
          (unless (fxzero? rcode)
            (error 'dns "DNS error" rcode)))
        ;; ANCOUNT
        (let ((ancount (+ (* 256 (bytevector-u8-ref bv 6))
                          (bytevector-u8-ref bv 7))))
          (when (fxzero? ancount)
            (error 'dns "No answers"))
          ;; Skip question section
          (let skip-question ((pos 12))
            (let ((b (bytevector-u8-ref bv pos)))
              (cond
                ((fxzero? b)
                 ;; Past null terminator + QTYPE(2) + QCLASS(2)
                 (let parse-answers ((pos (+ pos 5)) (i 0))
                   (if (fx>=? i ancount)
                       (error 'dns "No A record found")
                       ;; Skip name (may be compressed), find where RR fields start
                       (let skip-name ((pos pos))
                         (let ((b (bytevector-u8-ref bv pos)))
                           (cond
                             ;; Compression pointer — 2 bytes total, then RR fields
                             ((not (fxzero? (fxlogand b #xC0)))
                              (let* ((rr-pos (+ pos 2))
                                     (rtype (+ (* 256 (bytevector-u8-ref bv rr-pos))
                                               (bytevector-u8-ref bv (+ rr-pos 1))))
                                     (rdlen (+ (* 256 (bytevector-u8-ref bv (+ rr-pos 8)))
                                               (bytevector-u8-ref bv (+ rr-pos 9))))
                                     (rdata-pos (+ rr-pos 10)))
                                (if (and (= rtype 1) (= rdlen 4))
                                    (values (bytevector-u8-ref bv rdata-pos)
                                            (bytevector-u8-ref bv (+ rdata-pos 1))
                                            (bytevector-u8-ref bv (+ rdata-pos 2))
                                            (bytevector-u8-ref bv (+ rdata-pos 3)))
                                    (parse-answers (+ rdata-pos rdlen) (+ i 1)))))
                             ;; Null terminator — end of name, RR fields follow
                             ((fxzero? b)
                              (let* ((rr-pos (+ pos 1))
                                     (rtype (+ (* 256 (bytevector-u8-ref bv rr-pos))
                                               (bytevector-u8-ref bv (+ rr-pos 1))))
                                     (rdlen (+ (* 256 (bytevector-u8-ref bv (+ rr-pos 8)))
                                               (bytevector-u8-ref bv (+ rr-pos 9))))
                                     (rdata-pos (+ rr-pos 10)))
                                (if (and (= rtype 1) (= rdlen 4))
                                    (values (bytevector-u8-ref bv rdata-pos)
                                            (bytevector-u8-ref bv (+ rdata-pos 1))
                                            (bytevector-u8-ref bv (+ rdata-pos 2))
                                            (bytevector-u8-ref bv (+ rdata-pos 3)))
                                    (parse-answers (+ rdata-pos rdlen) (+ i 1)))))
                             ;; Normal label — skip length byte + label bytes
                             (else
                              (skip-name (+ pos 1 b)))))))))
                ;; Compression pointer in question
                ((not (fxzero? (fxlogand b #xC0)))
                 (skip-question (+ pos 2)))
                (else
                 (skip-question (+ pos 1 b))))))))))

  (define %dns-ip-string?
    (lambda (s)
      (let ((len (string-length s)))
        (and (> len 0)
             (let loop ((i 0))
               (if (fx>=? i len)
                   #t
                   (let ((c (string-ref s i)))
                     (if (or (char<=? #\0 c #\9) (char=? c #\.))
                         (loop (fx+ i 1))
                         #f))))))))

  (define %dns-parse-ip
    (lambda (s)
      (let ((parts (let split ((chars (string->list s))
                                (current '())
                                (out '()))
                     (cond
                       ((null? chars)
                        (reverse (cons (string->number (list->string (reverse current))) out)))
                       ((char=? (car chars) #\.)
                        (split (cdr chars) '()
                               (cons (string->number (list->string (reverse current))) out)))
                       (else
                        (split (cdr chars) (cons (car chars) current) out))))))
        (values (car parts) (cadr parts) (caddr parts) (cadddr parts)))))

  (define-ftype <sockaddr-in>
    (struct (family unsigned-short)
            (port (endian big unsigned-16))
            (address (endian big unsigned-32))
            (padding (array 8 char))))

  (define %make-sockaddr-in
    (lambda (a b c d port)
      (let* ((ptr (foreign-alloc (ftype-sizeof <sockaddr-in>)))
             (addr (make-ftype-pointer <sockaddr-in> ptr)))
        (ftype-set! <sockaddr-in> (family) addr 2)  ;; AF_INET
        (ftype-set! <sockaddr-in> (port) addr port)
        (ftype-set! <sockaddr-in> (address) addr
                    (+ (* a 256 256 256) (* b 256 256) (* c 256) d))
        (values ptr (ftype-sizeof <sockaddr-in>)))))

  (define dns-resolve-a
    (lambda (hostname port)
      ;; Returns (values addr-ptr addrlen) or error
      (if (%dns-ip-string? hostname)
          ;; Already an IP address
          (call-with-values (lambda () (%dns-parse-ip hostname))
            (lambda (a b c d)
              (%make-sockaddr-in a b c d port)))
          ;; DNS lookup via io_uring
          (let* ((ns (%dns-get-nameserver))
                 (udp-fd (loop-socket-new 2 2 0)))  ;; AF_INET, SOCK_DGRAM
            (unless udp-fd (error 'dns-resolve-a "UDP socket failed"))
            (loop-nonblock! udp-fd)
            ;; Connect UDP socket to nameserver:53
            (call-with-values (lambda () (%dns-parse-ip ns))
              (lambda (a b c d)
                (call-with-values (lambda () (%make-sockaddr-in a b c d 53))
                  (lambda (ns-addr ns-addrlen)
                    (let* ((sqe (io-uring-get-sqe (loop-ring %loop)))
                           (id (loop-alloc-id!)))
                      (io-uring-prep-connect sqe udp-fd ns-addr ns-addrlen)
                      (io-uring-sqe-set-data64 sqe id)
                      (let ((res (loop-abort
                                   (lambda (k)
                                     (hashtable-set! (loop-handlers %loop) id k)))))
                        (foreign-free ns-addr)
                        (when (fx<? res 0)
                          (loop-close udp-fd)
                          (error 'dns-resolve-a "UDP connect failed" (strerror (fx- 0 res))))))))))
            ;; Build and send DNS query
            (let ((query (%dns-build-query hostname)))
              (lock-object query)
              (let* ((sqe (io-uring-get-sqe (loop-ring %loop)))
                     (id (loop-alloc-id!)))
                (io-uring-prep-send sqe udp-fd (bytevector-pointer query) (bytevector-length query) 0)
                (io-uring-sqe-set-data64 sqe id)
                (let ((res (loop-abort
                             (lambda (k)
                               (hashtable-set! (loop-handlers %loop) id k)))))
                  (unlock-object query)
                  (when (fx<? res 0)
                    (loop-close udp-fd)
                    (error 'dns-resolve-a "DNS send failed")))))
            ;; Receive DNS response
            (let ((buf (make-bytevector 512)))
              (lock-object buf)
              (let* ((sqe (io-uring-get-sqe (loop-ring %loop)))
                     (id (loop-alloc-id!)))
                (io-uring-prep-recv sqe udp-fd (bytevector-pointer buf) 512 0)
                (io-uring-sqe-set-data64 sqe id)
                (let ((res (loop-abort
                             (lambda (k)
                               (hashtable-set! (loop-handlers %loop) id k)))))
                  (unlock-object buf)
                  (loop-close udp-fd)
                  (when (fx<=? res 0)
                    (error 'dns-resolve-a "DNS recv failed"))
                  (let ((response (subbytevector buf 0 res)))
                    (call-with-values (lambda () (%dns-parse-response response))
                      (lambda (a b c d)
                        (%make-sockaddr-in a b c d port)))))))))))

  ;; ============================================================
  ;; Section 12b: libtls FFI bindings
  ;; ============================================================

  (define libtls (load-shared-object "libtls.so"))

  (define TLS_PROTOCOLS_DEFAULT
    (bitwise-ior (bitwise-arithmetic-shift-left 1 3)   ;; TLSv1.2
                 (bitwise-arithmetic-shift-left 1 4)))  ;; TLSv1.3
  (define TLS_WANT_POLLIN -2)
  (define TLS_WANT_POLLOUT -3)

  (define tls-init (foreign-procedure "tls_init" () int))

  (define tls-config-new (foreign-procedure "tls_config_new" () void*))
  (define tls-config-free (foreign-procedure "tls_config_free" (void*) void))
  (define tls-config-set-protocols (foreign-procedure "tls_config_set_protocols" (void* unsigned-32) int))

  (define tls-config-error*
    (let ((func (foreign-procedure "tls_config_error" (void*) void*)))
      (lambda (config)
        (pointer->string (func config)))))

  (define tls-error*
    (let ((func (foreign-procedure "tls_error" (void*) void*)))
      (lambda (ctx)
        (pointer->string (func ctx)))))

  (define tls-client (foreign-procedure "tls_client" () void*))
  (define tls-configure (foreign-procedure "tls_configure" (void* void*) int))
  (define tls-connect-socket (foreign-procedure "tls_connect_socket" (void* int string) int))
  (define tls-handshake (foreign-procedure "tls_handshake" (void*) int))
  (define tls-read* (foreign-procedure "tls_read" (void* void* size_t) ssize_t))
  (define tls-write* (foreign-procedure "tls_write" (void* void* size_t) ssize_t))
  (define tls-close* (foreign-procedure "tls_close" (void*) int))
  (define tls-free* (foreign-procedure "tls_free" (void*) void))

  ;; ============================================================
  ;; Section 12c: Non-blocking TLS over io_uring
  ;; ============================================================

  (define %tls-initialized #f)

  (define %tls-ensure-init
    (lambda ()
      (unless %tls-initialized
        (let ((rc (tls-init)))
          (unless (zero? rc)
            (error 'tls-open "tls_init failed" rc))
          (set! %tls-initialized #t)))))

  (define tls-open
    (lambda (host port)
      (%tls-ensure-init)
      (let ((config (tls-config-new)))
        (when (zero? config)
          (error 'tls-open "tls_config_new failed"))
        (let ((rc (tls-config-set-protocols config TLS_PROTOCOLS_DEFAULT)))
          (unless (zero? rc)
            (let ((msg (tls-config-error* config)))
              (tls-config-free config)
              (error 'tls-open "tls_config_set_protocols failed" msg))))
        (let ((ctx (tls-client)))
          (when (zero? ctx)
            (tls-config-free config)
            (error 'tls-open "tls_client failed"))
          (let ((rc (tls-configure ctx config)))
            (unless (zero? rc)
              (let ((msg (tls-error* ctx)))
                (tls-config-free config)
                (tls-free* ctx)
                (error 'tls-open "tls_configure failed" msg))))
          (tls-config-free config)
          ;; Async DNS + connect
          (let-values (((addr addrlen) (dns-resolve-a host port)))
            (let ((fd (loop-connect addr addrlen)))
              (foreign-free addr)
              (unless fd
                (tls-free* ctx)
                (error 'tls-open "connect failed"))
              ;; Attach TLS to connected socket
              (let ((rc (tls-connect-socket ctx fd host)))
                (unless (zero? rc)
                  (let ((msg (tls-error* ctx)))
                    (tls-free* ctx)
                    (loop-close fd)
                    (error 'tls-open "tls_connect_socket failed" msg))))
              ;; Non-blocking handshake — yield on WANT_POLLIN/POLLOUT
              (let loop ()
                (let ((rc (tls-handshake ctx)))
                  (cond
                    ((zero? rc) (void))
                    ((= rc TLS_WANT_POLLIN)
                     (loop-poll-wait fd POLLIN)
                     (loop))
                    ((= rc TLS_WANT_POLLOUT)
                     (loop-poll-wait fd POLLOUT)
                     (loop))
                    (else
                     (let ((msg (tls-error* ctx)))
                       (tls-close* ctx)
                       (tls-free* ctx)
                       (loop-close fd)
                       (error 'tls-open "tls_handshake failed" msg))))))
              (values ctx fd)))))))

  (define tls-reader
    (lambda (ctx fd)
      (let ((buf (make-bytevector 4096)))
        (lambda ()
          (let loop ()
            (let ((n (with-lock (list buf)
                       (tls-read* ctx (bytevector-pointer buf) 4096))))
              (cond
                ((> n 0)
                 (let ((out (make-bytevector n)))
                   (bytevector-copy! buf 0 out 0 n)
                   out))
                ((zero? n) (eof-object))
                ((= n TLS_WANT_POLLIN)
                 (loop-poll-wait fd POLLIN)
                 (loop))
                ((= n TLS_WANT_POLLOUT)
                 (loop-poll-wait fd POLLOUT)
                 (loop))
                (else
                 (error 'tls-reader "tls_read failed" (tls-error* ctx))))))))))

  (define tls-writer
    (lambda (ctx fd)
      (lambda (bv)
        (let ((total (bytevector-length bv)))
          (let loop ((offset 0))
            (when (< offset total)
              (let ((n (with-lock (list bv)
                         (tls-write* ctx
                                     (+ (bytevector-pointer bv) offset)
                                     (- total offset)))))
                (cond
                  ((> n 0) (loop (+ offset n)))
                  ((= n TLS_WANT_POLLIN)
                   (loop-poll-wait fd POLLIN)
                   (loop offset))
                  ((= n TLS_WANT_POLLOUT)
                   (loop-poll-wait fd POLLOUT)
                   (loop offset))
                  (else
                   (error 'tls-writer "tls_write failed" (tls-error* ctx)))))))))))

  (define tls-shutdown
    (lambda (ctx fd)
      (tls-close* ctx)
      (tls-free* ctx)
      (loop-close fd)))

  ;; ============================================================
  ;; Section 12d: URL parser
  ;; ============================================================

  (define url-parse
    (lambda (url)
      (let ((sep (let loop ((i 0))
                   (and (< i (- (string-length url) 2))
                        (if (and (char=? (string-ref url i) #\:)
                                 (char=? (string-ref url (+ i 1)) #\/)
                                 (char=? (string-ref url (+ i 2)) #\/))
                            i
                            (loop (+ i 1)))))))
        (unless sep
          (error 'url-parse "invalid URL: no ://" url))
        (let* ((scheme (substring url 0 sep))
               (rest (substring url (+ sep 3) (string-length url)))
               (slash-pos (let loop ((i 0))
                            (if (>= i (string-length rest))
                                #f
                                (if (char=? (string-ref rest i) #\/)
                                    i
                                    (loop (+ i 1))))))
               (authority (if slash-pos
                              (substring rest 0 slash-pos)
                              rest))
               (request-target (if slash-pos
                                   (substring rest slash-pos (string-length rest))
                                   "/"))
               (colon-pos (let loop ((i (- (string-length authority) 1)))
                            (if (< i 0)
                                #f
                                (if (char=? (string-ref authority i) #\:)
                                    i
                                    (loop (- i 1))))))
               (host (if colon-pos
                         (substring authority 0 colon-pos)
                         authority))
               (port (if colon-pos
                         (string->number (substring authority (+ colon-pos 1) (string-length authority)))
                         #f)))
          (values scheme host port request-target)))))

  ;; ============================================================
  ;; Section 12e: www-request — HTTPS client
  ;; ============================================================

  (define www-request
    (lambda (method url headers body)
      (guard (ex (else
                  (if (condition? ex)
                      (display-condition ex (current-error-port))
                      (format (current-error-port) "www-request error: ~a\n" ex))
                  (newline (current-error-port))
                  (flush-output-port (current-error-port))
                  (values #f #f #f)))
        (let-values (((scheme host port request-target) (url-parse url)))
          (let ((port* (or port (if (string=? scheme "https") 443 80))))
            ;; NOTE: cannot use dynamic-wind here because loop-abort
            ;; uses continuations that would trigger the exit guard prematurely
            (let-values (((ctx fd) (tls-open host port*)))
              (let ((headers* (if (assq 'host headers)
                                  headers
                                  (cons (cons 'host host) headers))))
                ;; Write request
                (let ((write! (tls-writer ctx fd)))
                  (http-request-write write!
                                      method
                                      request-target
                                      'HTTP/1.1
                                      headers*
                                      (if (bytevector? body)
                                          (let ((sent #f))
                                            (lambda ()
                                              (if sent
                                                  (eof-object)
                                                  (begin (set! sent #t) body))))
                                          body)))
                ;; Read response
                (let-values (((version code reason resp-headers resp-body)
                              (http-response-read (tls-reader ctx fd))))
                  (tls-shutdown ctx fd)
                  (values code resp-headers resp-body)))))))))

  ;; ============================================================
  ;; Section 13: Response helpers and transparent server
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

  (define connection-close?
    (lambda (headers)
      (let ((conn (assq 'connection headers)))
        (and conn (string-ci=? (cdr conn) "close")))))

  (define handle-connection
    (lambda (application context dispatch client read write close)
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
                      (let* ((request-state (context application client headers))
                             (uri-parts (call-with-values (lambda () (uri-parse uri)) list))
                             (path (car uri-parts))
                             (params (or (cadr uri-parts) '()))
                             (parsed-body
                              (if (and (bytevector? body)
                                       (fx>? (bytevector-length body) 0)
                                       (let ((ct (assq 'content-type headers)))
                                         (and ct (string-contains? (string-downcase (cdr ct)) "json"))))
                                  (guard (ex (else (eof-object)))
                                    (unjson (utf8->string body)))
                                  (eof-object))))
                        (let-values (((status response-pair extra-headers)
                                      (dispatch application request-state method path params parsed-body)))
                          (http-response-write*
                            write status (status-code->reason status)
                            (cons (cons 'content-type (cdr response-pair)) extra-headers)
                            (car response-pair)))))
                    (if (or (connection-close? headers)
                            (loop-socket-error? client))
                        (close)
                        (loop))))))))))

  (define transparent
    (lambda (port-number application context dispatch)
      (loop-new)
      ;; SIGINT/SIGTERM → graceful shutdown
      (register-signal-handler 2  ;; SIGINT
        (lambda (sig)
          (when (and %loop (loop-running? %loop))
            (format #t "\nReceived SIGINT, shutting down...\n")
            (flush-output-port)
            (loop-stop))))
      (register-signal-handler 15 ;; SIGTERM
        (lambda (sig)
          (when (and %loop (loop-running? %loop))
            (format #t "\nReceived SIGTERM, shutting down...\n")
            (flush-output-port)
            (loop-stop))))
      (loop-spawn
        (lambda ()
          (define app-state (application))
          (call-with-values (lambda () (loop-tcp-serve "0.0.0.0" port-number))
            (lambda (accept close)
              (format #t "transparent server at http://127.0.0.1:~a/\n" port-number)
              (flush-output-port)
              (let loop ()
                (when (loop-running? %loop)
                  (call-with-values accept
                    (lambda (read write close peer-ip)
                      (when (and read write close)
                        (loop-spawn
                          (lambda () (handle-connection app-state context dispatch peer-ip read write close))))))
                  (loop)))))))
      (loop-run)
      ;; Cleanup after loop exits
      (io-uring-queue-exit (loop-ring %loop))))

)
