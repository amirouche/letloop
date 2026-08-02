;; Copyright © 2026 Amirouche A. BOUBEKKI <amirouche at hyper dev>
;;
;; (letloop kernel) — define-kernel: simili Scheme in, machine code
;; out. Stage 4 of plans/v12/20260802-sexp-assembler-jit.md.
;;
;; A kernel is a leaf procedure over machine words and byte spans,
;; written in a tiny Scheme-looking language and compiled *naively*
;; to (letloop asm) mnemonics — no inference, no doubt, no spilling:
;; running out of registers is a compile-time error naming the
;; expression, and anything outside the language is rejected. The
;; contract is the leaf-FFI contract: no allocation, no calls back
;; into Scheme, no continuation capture.
;;
;;   (define-kernel (name (arg type) ...) return body)
;;
;; types: u8* (byte span, passed as a bytevector) and u64; return
;; u64 or i64. The language:
;;
;;   expressions   integer literals, variables,
;;                 (+ e ...) (- e e) (* e e) (band e ...) (bor e ...)
;;                 (bnot e) (<< e e) (>> e e)      — unsigned, 64-bit
;;                 (u8@ p e) (u32@ p e) (u64@ p e) — load at byte
;;                 offset e from pointer p; u8/u32 zero-extend
;;                 (popcount e) (tzcnt e) (pdep e e)
;;                 (if test e e)
;;   tests         (= e e) (< e e) (<= e e) (> e e) (>= e e)
;;                 (and test ...)                  — unsigned compares
;;   binding       (let ((v e) ...) body)          — sequential
;;   loops         (let name ((v e) ...) body)     — tail position
;;                 only; (name e ...) jumps back, also tail only
;;
;; The kernel body is the return value. define-kernel also records
;; its own source — (kernel-source 'name) recovers it, which is the
;; `sum` half of (dubito (sum proc)) for plain Chez code.

(define %kernel-sources '())

(define kernel-register!
  (lambda (name source)
    (set! %kernel-sources (cons (cons name source) %kernel-sources))))

(define kernel-source
  (lambda (name)
    (cond ((assq name %kernel-sources) => cdr) (else #f))))

(define-syntax define-kernel
  (lambda (stx)
    (define (ffi-type t)
      (case t
        ((u8*) 'u8*)
        ((u64) 'unsigned-64)
        (else (syntax-violation 'define-kernel "unknown argument type" t))))
    (define (ffi-return t)
      (case t
        ((u64) 'unsigned-64)
        ((i64) 'integer-64)
        (else (syntax-violation 'define-kernel "unknown return type" t))))
    (syntax-case stx ()
      ((_ (name (arg type) ...) return body)
       (with-syntax (((ffi ...)
                      (map (lambda (t)
                             (datum->syntax #'name (ffi-type (syntax->datum t))))
                           #'(type ...)))
                     (ffi-ret
                      (datum->syntax #'name
                                     (ffi-return (syntax->datum #'return)))))
         #'(define name
             (begin
               (kernel-register!
                'name '(define-kernel (name (arg type) ...) return body))
               (assembly->procedure
                (sexp->assembly (kernel-compile '((arg type) ...) 'body))
                (ffi ...)
                ffi-ret))))))))

;; --- the compiler --------------------------------------------------

(define %kernel-arg-registers '(rdi rsi rdx rcx r8 r9))

;; rax is the value register at tails, rcx the shift-count scratch;
;; neither is ever allocated to a variable or temporary.
(define %kernel-pool '(rdi rsi rdx r8 r9 r10 r11 rbx r12 r13 r14 r15))
(define %kernel-callee-saved '(rbx r12 r13 r14 r15))

(define %kernel-r32
  '((rax . eax) (rcx . ecx) (rdx . edx) (rbx . ebx)
    (rsi . esi) (rdi . edi) (r8 . r8d) (r9 . r9d) (r10 . r10d)
    (r11 . r11d) (r12 . r12d) (r13 . r13d) (r14 . r14d) (r15 . r15d)))

(define %kernel-compares
  ;; test head → jump-if-false mnemonic (unsigned)
  '((= . jne) (< . jae) (<= . ja) (> . jbe) (>= . jb)))

(define %kernel-binops
  '((+ . add) (- . sub) (band . and) (bor . or) (* . imul)))

(define kernel-free-variables
  ;; Free variable symbols of EXPR; loop names bind like variables.
  (lambda (expr bound)
    (cond
     ((symbol? expr) (if (memq expr bound) '() (list expr)))
     ((integer? expr) '())
     ((pair? expr)
      (case (car expr)
        ((let)
         (if (symbol? (cadr expr))
             (let ((name (cadr expr))
                   (bindings (caddr expr))
                   (body (cadddr expr)))
               (apply append
                      (kernel-free-variables
                       body (cons name (append (map car bindings) bound)))
                      (map (lambda (b) (kernel-free-variables (cadr b) bound))
                           bindings)))
             (let walk ((bindings (cadr expr)) (bound bound) (out '()))
               (if (null? bindings)
                   (append out (kernel-free-variables (caddr expr) bound))
                   (walk (cdr bindings)
                         (cons (caar bindings) bound)
                         (append out (kernel-free-variables
                                      (cadar bindings) bound)))))))
        (else
         (apply append
                (map (lambda (e) (kernel-free-variables e bound))
                     (cdr expr))))))
     (else '()))))

(define kernel-compile
  ;; Compile ARGUMENTS ((name type) ...) and BODY into a list of
  ;; (letloop asm) instructions.
  (lambda (arguments body)

    (define code '())                   ; reversed instructions
    (define free %kernel-pool)          ; registers not held
    (define used-callee '())            ; callee-saved ever allocated
    (define counter 0)

    (define oops
      (lambda (message expr)
        (error 'define-kernel message expr)))

    (define emit!
      (lambda (instruction)
        (set! code (cons instruction code))))

    (define fresh-label
      (lambda (prefix)
        (set! counter (fx+ counter 1))
        (string->symbol (format "~a-~a" prefix counter))))

    (define hold!
      ;; Take REG out of the free set.
      (lambda (reg)
        (set! free (remq reg free))
        (when (and (memq reg %kernel-callee-saved)
                   (not (memq reg used-callee)))
          (set! used-callee (cons reg used-callee)))))

    (define allocate!
      (lambda (context)
        ;; Prefer caller-saved: keep pool order, not release order.
        (let loop ((pool %kernel-pool))
          (cond ((null? pool)
                 (oops "out of registers (too many live variables) at" context))
                ((memq (car pool) free)
                 (hold! (car pool))
                 (car pool))
                (else (loop (cdr pool)))))))

    (define release!
      (lambda (reg)
        (set! free (cons reg free))))

    (define lookup
      (lambda (variable env)
        (cond ((assq variable env) => cdr)
              (else (oops "unbound variable" variable)))))

    (define int32?
      (lambda (x) (and (integer? x) (<= -2147483648 x 2147483647))))

    (define r32
      (lambda (reg) (cdr (assq reg %kernel-r32))))

    (define operand
      ;; Evaluate E for use as a second operand: returns (values reg
      ;; release?) — a variable's own register, or a fresh temporary.
      (lambda (e env)
        (if (and (symbol? e) (assq e env))
            (values (lookup e env) #f)
            (let ((r (allocate! e)))
              (comp-expr e r env)
              (values r #t)))))

    (define comp-binop!
      (lambda (op e target env)
        (let ((mnemonic (cdr (assq op %kernel-binops))))
          (comp-expr (cadr e) target env)
          (for-each
           (lambda (x)
             (cond ((and (int32? x) (not (eq? op '*)))
                    (emit! (list mnemonic target x)))
                   (else
                    (let-values (((r release?) (operand x env)))
                      (emit! (list mnemonic target r))
                      (when release? (release! r))))))
           (cddr e)))))

    (define comp-shift!
      (lambda (e target env)
        (let ((mnemonic (if (eq? (car e) '<<) 'shl 'shr))
              (value (cadr e))
              (count (caddr e)))
          (cond
           ((integer? count)
            (unless (<= 0 count 63) (oops "bad shift count" e))
            (comp-expr value target env)
            (emit! (list mnemonic target count)))
           ((eq? target 'rcx)
            ;; evaluating the count would clobber the value: detour
            (let ((temp (allocate! e)))
              (comp-expr value temp env)
              (comp-expr count 'rcx env)
              (emit! (list mnemonic temp 'cl))
              (emit! (list 'mov 'rcx temp))
              (release! temp)))
           (else
            (comp-expr value target env)
            (comp-expr count 'rcx env)
            (emit! (list mnemonic target 'cl)))))))

    (define comp-load!
      (lambda (e target env)
        (let ((width (car e)) (pointer (cadr e)) (offset (caddr e)))
          (let-values (((p prelease?) (operand pointer env)))
            (define (emit-load! address)
              (case width
                ((u8@) (emit! (list 'movzx target address)))
                ((u32@) (emit! (list 'mov (r32 target) address)))
                (else (emit! (list 'mov target address)))))
            (if (int32? offset)
                (emit-load! (list '& p offset))
                (let-values (((o orelease?) (operand offset env)))
                  (emit-load! (list '& p o 1 0))
                  (when orelease? (release! o))))
            (when prelease? (release! p))))))

    (define comp-expr
      (lambda (e target env)
        (cond
         ((integer? e)
          (unless (<= (- (expt 2 63)) e (- (expt 2 64) 1))
            (oops "literal out of range" e))
          (emit! (list 'mov target e)))
         ((symbol? e)
          (let ((reg (lookup e env)))
            (unless (eq? reg target)
              (emit! (list 'mov target reg)))))
         ((pair? e)
          (case (car e)
            ((+ - * band bor) (comp-binop! (car e) e target env))
            ((<< >>) (comp-shift! e target env))
            ((bnot)
             (comp-expr (cadr e) target env)
             (emit! (list 'not target)))
            ((u8@ u32@ u64@) (comp-load! e target env))
            ((popcount tzcnt)
             (comp-expr (cadr e) target env)
             (emit! (list (if (eq? (car e) 'popcount) 'popcnt 'tzcnt)
                          target target)))
            ((pdep)
             (comp-expr (cadr e) target env)
             (let-values (((r release?) (operand (caddr e) env)))
               (emit! (list 'pdep target target r))
               (when release? (release! r))))
            ((if)
             (let ((otherwise (fresh-label "else"))
                   (join (fresh-label "join")))
               (comp-test (cadr e) otherwise env)
               (comp-expr (caddr e) target env)
               (emit! (list 'jmp join))
               (emit! (list 'label otherwise))
               (comp-expr (cadddr e) target env)
               (emit! (list 'label join))))
            ((let)
             (when (symbol? (cadr e))
               (oops "loops are only allowed in tail position" e))
             (let walk ((bindings (cadr e)) (env env) (bound '()))
               (if (null? bindings)
                   (begin (comp-expr (caddr e) target env)
                          (for-each release! bound))
                   (let ((reg (allocate! (caar bindings))))
                     (comp-expr (cadar bindings) reg env)
                     (walk (cdr bindings)
                           (cons (cons (caar bindings) reg) env)
                           (cons reg bound))))))
            (else (oops "unknown expression" e))))
         (else (oops "unknown expression" e)))))

    (define comp-test
      (lambda (test false-label env)
        (cond
         ((and (pair? test) (eq? (car test) 'and))
          (for-each (lambda (t) (comp-test t false-label env)) (cdr test)))
         ((pair? test)
          (let ((jump (assq (car test) %kernel-compares)))
            (if jump
                (let-values (((a arelease?) (operand (cadr test) env)))
                  (let ((b (caddr test)))
                    (if (int32? b)
                        (emit! (list 'cmp a b))
                        (let-values (((br brelease?) (operand b env)))
                          (emit! (list 'cmp a br))
                          (when brelease? (release! br)))))
                  (when arelease? (release! a))
                  (emit! (list (cdr jump) false-label)))
                ;; bare expression: false iff zero
                (let-values (((r release?) (operand test env)))
                  (emit! (list 'test r r))
                  (when release? (release! r))
                  (emit! (list 'je false-label))))))
         (else (oops "unknown test" test)))))

    (define pinned
      ;; Registers a later loop iteration may still read: every loop
      ;; variable, and every outer variable the loop body references.
      ;; Loop records are (name label (reg ...) (pinned-reg ...)).
      (lambda (loops)
        (apply append (map (lambda (loop)
                             (append (caddr loop) (cadddr loop)))
                           loops))))

    (define prune!
      ;; Release environment entries not referenced by tail
      ;; expression E (control never returns to this scope), except
      ;; loop variables. Returns the pruned environment.
      (lambda (e env loops)
        (let ((needed (kernel-free-variables e '()))
              (keep (pinned loops)))
          (filter (lambda (entry)
                    (if (or (memq (car entry) needed)
                            (memq (cdr entry) keep))
                        #t
                        (begin (release! (cdr entry)) #f)))
                  env))))

    (define comp-tail
      (lambda (e env loops)
        (let ((env (prune! e env loops)))
          (cond
           ((and (pair? e) (eq? (car e) 'if))
            (let ((otherwise (fresh-label "else")))
              (comp-test (cadr e) otherwise env)
              (let ((snapshot free))
                (comp-tail (caddr e) env loops)
                (set! free snapshot))
              (emit! (list 'label otherwise))
              (comp-tail (cadddr e) env loops)))
           ((and (pair? e) (eq? (car e) 'let) (symbol? (cadr e)))
            ;; named let: a loop
            (let* ((name (cadr e))
                   (bindings (caddr e))
                   (body (cadddr e))
                   (regs (map (lambda (b)
                                (let ((reg (allocate! (car b))))
                                  (comp-expr (cadr b) reg env)
                                  reg))
                              bindings))
                   (label (fresh-label name))
                   ;; outer registers the body reads: a later
                   ;; iteration needs them, liveness must not prune
                   (extra (let ((needed (kernel-free-variables
                                         body
                                         (cons name (map car bindings)))))
                            (fold-left (lambda (out entry)
                                         (if (memq (car entry) needed)
                                             (cons (cdr entry) out)
                                             out))
                                       '() env))))
              (emit! (list 'label label))
              (comp-tail body
                         (append (map (lambda (b reg) (cons (car b) reg))
                                      bindings regs)
                                 env)
                         (cons (list name label regs extra) loops))))
           ((and (pair? e) (eq? (car e) 'let))
            (let walk ((bindings (cadr e)) (env env))
              (if (null? bindings)
                  (comp-tail (caddr e) env loops)
                  (let ((reg (allocate! (caar bindings))))
                    (comp-expr (cadar bindings) reg env)
                    (walk (cdr bindings)
                          (cons (cons (caar bindings) reg) env))))))
           ((and (pair? e) (assq (car e) loops))
            => (lambda (loop)               ; (name label regs pinned)
                 (let ((label (cadr loop))
                       (regs (caddr loop))
                       (args (cdr e)))
                   (unless (fx=? (length args) (length regs))
                     (oops "loop arity mismatch" e))
                   (if (fx=? (length regs) 1)
                       (comp-expr (car args) (car regs) env)
                       ;; parallel assignment through temporaries
                       (let ((temps
                              (map (lambda (arg reg)
                                     (if (and (symbol? arg)
                                              (assq arg env)
                                              (eq? (lookup arg env) reg))
                                         #f  ; already in place
                                         (let ((t (allocate! arg)))
                                           (comp-expr arg t env)
                                           t)))
                                   args regs)))
                         (for-each (lambda (t reg)
                                     (when t
                                       (emit! (list 'mov reg t))
                                       (release! t)))
                                   temps regs)))
                   (emit! (list 'jmp label)))))
           (else
            (comp-expr e 'rax env)
            (emit! (list 'jmp '%kernel-return)))))))

    ;; --- entry: bind arguments ------------------------------------

    (define env '())
    (define deferred '())               ; (reg . entry-thunk-data)

    (let bind ((arguments arguments) (index 0))
      (unless (null? arguments)
        (let ((name (caar arguments)))
          (cond
           ((and (fx<? index 6)
                 (not (eq? (list-ref %kernel-arg-registers index) 'rcx)))
            (let ((reg (list-ref %kernel-arg-registers index)))
              (hold! reg)
              (set! env (cons (cons name reg) env))))
           (else
            ;; the rcx argument and stack arguments move into the pool
            (let ((reg (allocate! name)))
              (set! deferred
                    (cons (cons reg (if (fx<? index 6) 'rcx (fx- index 6)))
                          deferred))
              (set! env (cons (cons name reg) env))))))
        (bind (cdr arguments) (fx+ index 1))))

    (comp-tail body env '())

    ;; --- prologue and epilogue ------------------------------------

    (let ((pushes (reverse used-callee)))
      (append
       (map (lambda (reg) (list 'push reg)) pushes)
       (map (lambda (move)
              (if (eq? (cdr move) 'rcx)
                  (list 'mov (car move) 'rcx)
                  (list 'mov (car move)
                        (list '& 'rsp (+ 8 (* 8 (length pushes))
                                         (* 8 (cdr move)))))))
            (reverse deferred))
       (reverse code)
       (list (list 'label '%kernel-return))
       (map (lambda (reg) (list 'pop reg)) (reverse pushes))
       (list (list 'ret))))))
