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
;;   (define name (kernel ((type arg) ...) body))
;;   (define name (kernel ((type arg) ...) return body))
;;   (define name (assembly ((type arg) ...) instruction ...))
;;   (define name (assembly ((type arg) ...) return instruction ...))
;;
;; kernel and assembly are expressions: they compile at evaluation
;; time and return the procedure. types: u8* (byte span, passed as a
;; bytevector) and u64; return u64 (the default) or i64. assembly is
;; the escape hatch one floor down: the body is (letloop asm)
;; instruction sexps taken literally — the signature only shapes the
;; FFI and documents what arrives in rdi, rsi, rdx, rcx, r8, r9 and
;; on the stack; the value returned is whatever the code leaves in
;; rax. Both forms register their source. The kernel language:
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
;;   assumptions   (assert test) ... before the body — O(1) entry
;;                 guards on the Scheme side of the call, exact
;;                 integer semantics, (len span) available
;;
;; Every kernel is doubted at definition time (type discipline:
;; spans vs words); (dubito proc) doubts any procedure with
;; recoverable source and returns a report — verdict verified for
;; kernels, trusted for assembly.
;;
;; The kernel body is the return value. kernel also records its own
;; source, keyed by the procedure itself — (kernel-source proc)
;; recovers the definition, which is the `sum` half of
;; (dubito (sum proc)) for plain Chez code: sum operates on the
;; value, the way Kernel's meta operative operates on a combiner.

(define %kernel-sources (make-weak-eq-hashtable))

(define kernel-register!
  (lambda (procedure source)
    (eq-hashtable-set! %kernel-sources procedure source)
    procedure))

(define kernel-source
  (lambda (procedure)
    (eq-hashtable-ref %kernel-sources procedure #f)))

;; --- dubito: the doubting pass -------------------------------------
;;
;; Doubt verifies; it does not optimize. The v1 kernel language is
;; total with respect to the leaf contract — it cannot express
;; allocation, calls out, or continuation capture — so what remains
;; to doubt is: the type discipline (spans u8* versus words u64,
;; checked below on every kernel at definition time), and the entry
;; assumptions. (assert test) forms before the body become O(1)
;; guards checked on the Scheme side of the call boundary, amortized
;; over the O(n) kernel; they evaluate with exact integer semantics
;; (no 64-bit wraparound), and (len span) — available only inside
;; assert — is the span's byte length. Rejection is an error naming
;; the offending expression; the fallback is the caller's scalar
;; Scheme.

(define dubito-doubt
  ;; Type discipline over ARGUMENTS ((type name) ...), ASSERTS
  ;; (test ...) and BODY. Raises on violation; returns 'verified.
  (lambda (arguments asserts body)

    (define oops
      (lambda (message expr)
        (error 'dubito message expr)))

    (define word!
      (lambda (t e)
        (unless (eq? t 'u64) (oops "expected a word, got a span" e))
        'u64))

    (define unify
      ;; #f is the type of a loop jump: it never returns a value.
      (lambda (a b e)
        (cond ((not a) b)
              ((not b) a)
              ((eq? a b) a)
              (else (oops "branches disagree: span on one side, word on the other" e)))))

    (define expr-type
      (lambda (e env loops len?)
        (cond
         ((integer? e) 'u64)
         ((symbol? e)
          (cond ((assq e env) => cdr)
                (else (oops "unbound variable" e))))
         ((pair? e)
          (case (car e)
            ((+)
             (let ((spans (filter (lambda (t) (eq? t 'u8*))
                                  (map (lambda (x) (expr-type x env loops len?))
                                       (cdr e)))))
               (cond ((null? spans) 'u64)
                     ((null? (cdr spans)) 'u8*)
                     (else (oops "adding two spans" e)))))
            ((- * band bor << >>)
             (for-each (lambda (x) (word! (expr-type x env loops len?) x))
                       (cdr e))
             'u64)
            ((bnot popcount tzcnt)
             (word! (expr-type (cadr e) env loops len?) (cadr e)))
            ((pdep)
             (word! (expr-type (cadr e) env loops len?) (cadr e))
             (word! (expr-type (caddr e) env loops len?) (caddr e)))
            ((u8@ u32@ u64@)
             (unless (eq? (expr-type (cadr e) env loops len?) 'u8*)
               (oops "load needs a span" e))
             (word! (expr-type (caddr e) env loops len?) (caddr e)))
            ((len)
             (unless len? (oops "len is only available inside assert" e))
             (unless (eq? (expr-type (cadr e) env loops len?) 'u8*)
               (oops "len needs a span" e))
             'u64)
            ((if)
             (test-check (cadr e) env loops len?)
             (unify (expr-type (caddr e) env loops len?)
                    (expr-type (cadddr e) env loops len?)
                    e))
            ((let)
             (if (symbol? (cadr e))
                 (let* ((bindings (caddr e))
                        (types (map (lambda (b)
                                      (expr-type (cadr b) env loops len?))
                                    bindings)))
                   (expr-type (cadddr e)
                              (append (map (lambda (b t) (cons (car b) t))
                                           bindings types)
                                      env)
                              (cons (cons (cadr e) types) loops)
                              len?))
                 (let walk ((bindings (cadr e)) (env env))
                   (if (null? bindings)
                       (expr-type (caddr e) env loops len?)
                       (walk (cdr bindings)
                             (cons (cons (caar bindings)
                                         (expr-type (cadar bindings) env loops len?))
                                   env))))))
            (else
             (cond
              ((assq (car e) loops)
               => (lambda (loop)
                    (unless (fx=? (length (cdr e)) (length (cdr loop)))
                      (oops "loop arity mismatch" e))
                    (for-each
                     (lambda (arg t)
                       (unless (eq? (expr-type arg env loops len?) t)
                         (oops "loop argument changes type across iterations" e)))
                     (cdr e) (cdr loop))
                    #f))
              (else (oops "unknown expression" e))))))
         (else (oops "unknown expression" e)))))

    (define test-check
      (lambda (t env loops len?)
        (cond
         ((and (pair? t) (eq? (car t) 'and))
          (for-each (lambda (x) (test-check x env loops len?)) (cdr t)))
         ((and (pair? t) (memq (car t) '(= < <= > >=)))
          (word! (expr-type (cadr t) env loops len?) (cadr t))
          (word! (expr-type (caddr t) env loops len?) (caddr t)))
         (else
          (word! (expr-type t env loops len?) t)))))

    (let ((env (map (lambda (a) (cons (cadr a) (car a))) arguments)))
      (for-each (lambda (t) (test-check t env '() #t)) asserts)
      (when (eq? (expr-type body env '() #f) 'u8*)
        (oops "a kernel returns a word, not a span" body))
      'verified)))

(define dubito-eval
  ;; Evaluate an assert test on the Scheme side of the boundary:
  ;; exact integer semantics, spans are bytevectors.
  (lambda (e env)
    (cond
     ((integer? e) e)
     ((symbol? e) (cdr (assq e env)))
     ((pair? e)
      (let ((operands (lambda () (map (lambda (x) (dubito-eval x env)) (cdr e)))))
        (case (car e)
          ((and) (for-all (lambda (x) (dubito-eval x env)) (cdr e)))
          ((=) (apply = (operands)))
          ((<) (apply < (operands)))
          ((<=) (apply <= (operands)))
          ((>) (apply > (operands)))
          ((>=) (apply >= (operands)))
          ((+) (apply + (operands)))
          ((-) (apply - (operands)))
          ((*) (apply * (operands)))
          ((band) (apply bitwise-and (operands)))
          ((bor) (apply bitwise-ior (operands)))
          ((bnot) (bitwise-not (dubito-eval (cadr e) env)))
          ((<<) (bitwise-arithmetic-shift-left
                 (dubito-eval (cadr e) env) (dubito-eval (caddr e) env)))
          ((>>) (bitwise-arithmetic-shift-right
                 (dubito-eval (cadr e) env) (dubito-eval (caddr e) env)))
          ((len) (bytevector-length (dubito-eval (cadr e) env)))
          (else (error 'dubito "unsupported form in assert" e)))))
     (else (error 'dubito "unsupported form in assert" e)))))

(define kernel-wrap
  ;; Guard RAW behind the kernel's entry assumptions. Kernels
  ;; without asserts pay nothing.
  (lambda (raw parameters asserts)
    (if (null? asserts)
        raw
        (lambda args
          (let ((env (map cons parameters args)))
            (for-each (lambda (test)
                        (unless (dubito-eval test env)
                          (error 'kernel "entry assumption violated"
                                 (list 'assert test))))
                      asserts))
          (apply raw args)))))

(define kernel-parse
  ;; Split a registered (kernel sig [return] (assert t) ... body)
  ;; source into (values arguments return asserts body).
  (lambda (source)
    (let* ((arguments (cadr source))
           (rest (cddr source))
           (return (if (and (pair? rest) (memq (car rest) '(u64 i64)))
                       (car rest)
                       'u64))
           (rest (if (and (pair? rest) (memq (car rest) '(u64 i64)))
                     (cdr rest)
                     rest)))
      (let split ((rest rest) (asserts '()))
        (cond ((and (pair? (car rest)) (eq? (caar rest) 'assert))
               (split (cdr rest) (cons (cadar rest) asserts)))
              (else (values arguments return (reverse asserts) (car rest))))))))

(define dubito
  ;; Doubt a procedure: recover its source (sum) and verify the
  ;; kernel contract. Returns a report alist; raises when the source
  ;; violates the contract, or when there is nothing to doubt. An
  ;; assembly procedure cannot be verified, only believed: its
  ;; verdict is trusted.
  (lambda (procedure)
    (let ((source (kernel-source procedure)))
      (unless source
        (error 'dubito "nothing to doubt: no recoverable source" procedure))
      (case (car source)
        ((kernel)
         (let-values (((arguments return asserts body) (kernel-parse source)))
           (dubito-doubt arguments asserts body)
           (list '(form . kernel)
                 (cons 'arguments arguments)
                 (cons 'return return)
                 (cons 'asserts (length asserts))
                 '(verdict . verified))))
        ((assembly)
         (list '(form . assembly)
               (cons 'arguments (cadr source))
               '(verdict . trusted)))
        (else (error 'dubito "unrecognized source" source))))))

(define-syntax kernel
  (lambda (stx)
    (define (ffi-type t)
      (case t
        ((u8*) 'u8*)
        ((u64) 'unsigned-64)
        (else (syntax-violation 'kernel "unknown argument type" t))))
    (define (ffi-return t)
      (case t
        ((u64) 'unsigned-64)
        ((i64) 'integer-64)
        (else (syntax-violation 'kernel "unknown return type" t))))
    (define (split-body forms)
      ;; leading (assert test) forms, then exactly one body expression
      (let loop ((forms forms) (asserts '()))
        (cond ((null? forms)
               (syntax-violation 'kernel "missing kernel body" stx))
              ((and (pair? (car forms)) (eq? (caar forms) 'assert))
               (unless (and (pair? (cdar forms)) (null? (cddar forms)))
                 (syntax-violation 'kernel "assert takes a single test"
                                   (car forms)))
               (loop (cdr forms) (cons (cadar forms) asserts)))
              ((null? (cdr forms))
               (values (reverse asserts) (car forms)))
              (else
               (syntax-violation 'kernel "kernel body is a single expression"
                                 (cadr forms))))))
    (define (build return-stx forms)
      (lambda (sig-stx source-stx)
        (let-values (((asserts body) (split-body forms)))
          (with-syntax ((((type arg) ...) sig-stx)
                        (ffi-ret (datum->syntax #'kernel
                                                (ffi-return
                                                 (syntax->datum return-stx))))
                        (body-d (datum->syntax #'kernel body))
                        (asserts-d (datum->syntax #'kernel asserts))
                        (source source-stx))
            (with-syntax (((ffi ...)
                           (map (lambda (t)
                                  (datum->syntax #'kernel
                                                 (ffi-type (syntax->datum t))))
                                #'(type ...))))
              #'(kernel-register!
                 (kernel-wrap
                  (assembly->procedure
                   (sexp->assembly
                    (kernel-compile '((type arg) ...) 'body-d 'asserts-d))
                   (ffi ...)
                   ffi-ret)
                  '(arg ...)
                  'asserts-d)
                 'source))))))
    (syntax-case stx ()
      ((_ ((type arg) ...) return e0 e* ...)
       (memq (syntax->datum #'return) '(u64 i64))
       ((build #'return (syntax->datum #'(e0 e* ...)))
        #'((type arg) ...)
        #'(kernel ((type arg) ...) return e0 e* ...)))
      ((_ ((type arg) ...) e0 e* ...)
       ((build #'u64 (syntax->datum #'(e0 e* ...)))
        #'((type arg) ...)
        #'(kernel ((type arg) ...) e0 e* ...))))))

(define-syntax assembly
  (lambda (stx)
    (define (ffi-type t)
      (case t
        ((u8*) 'u8*)
        ((u64) 'unsigned-64)
        (else (syntax-violation 'assembly "unknown argument type" t))))
    (define (ffi-return t)
      (case t
        ((u64) 'unsigned-64)
        ((i64) 'integer-64)
        ((void) 'void)                  ; side-effect kernels: no value
        (else (syntax-violation 'assembly "unknown return type" t))))
    (syntax-case stx ()
      ((_ ((type arg) ...) return instruction0 instruction ...)
       (memq (syntax->datum #'return) '(u64 i64 void))
       (with-syntax (((ffi ...)
                      (map (lambda (t)
                             (datum->syntax #'assembly (ffi-type (syntax->datum t))))
                           #'(type ...)))
                     (ffi-ret
                      (datum->syntax #'assembly
                                     (ffi-return (syntax->datum #'return)))))
         #'(kernel-register!
            (assembly->procedure
             (sexp->assembly '(instruction0 instruction ...))
             (ffi ...)
             ffi-ret)
            '(assembly ((type arg) ...) return instruction0 instruction ...))))
      ((_ ((type arg) ...) instruction0 instruction ...)
       (with-syntax (((ffi ...)
                      (map (lambda (t)
                             (datum->syntax #'assembly (ffi-type (syntax->datum t))))
                           #'(type ...))))
         #'(kernel-register!
            (assembly->procedure
             (sexp->assembly '(instruction0 instruction ...))
             (ffi ...)
             unsigned-64)
            '(assembly ((type arg) ...) instruction0 instruction ...)))))))

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
  ;; Doubt, then compile ARGUMENTS ((type name) ...) and BODY into a
  ;; list of (letloop asm) instructions. ASSERTS take part in the
  ;; doubting only — their runtime lives on the Scheme side, in
  ;; kernel-wrap.
  (case-lambda
    ((arguments body) (kernel-compile arguments body '()))
    ((arguments body asserts)
     (dubito-doubt arguments asserts body)
     ;; hoisting adds bindings; if they overflow the pool, compile
     ;; the untransformed source instead
     (guard (ex ((%kernel-pressure? ex) (%kernel-compile arguments body)))
       (%kernel-compile arguments (kernel-licm body))))))

(define kernel-addends
  ;; Catamorphism: flatten a (+ ...) tree into its addends.
  (lambda (e)
    (match e
      ((+ ,(kernel-addends -> parts) ...) (apply append parts))
      (,other (list other)))))

;; --- loop-invariant code motion, source to source ------------------
;;
;; Two rewrites, applied to every named let from the inside out:
;; load addresses split so that invariant addends migrate into the
;; pointer — (u8@ base (+ wrel-off (+ w 1))) becomes
;; (u8@ (+ base wrel-off) (+ w 1)) — and maximal invariant
;; pure-arithmetic subexpressions of the body (no loads: hoisting
;; never speculates a memory access) are bound outside the loop:
;;
;;   (let name ((v i) ...) body)
;;   ⇒ (let ((%licm-1 E1) ...) (let name ((v i') ...) body'))
;;
;; Hoisted values are ordinary variables, so allocation, pinning and
;; pruning guarantee their registers survive exactly as long as the
;; loop can still be reached — no special cases. If the extra
;; bindings overflow the register pool, kernel-compile retries on
;; the untransformed source: the transform can never reject a
;; program that compiled without it.

(define %kernel-licm-arith
  '(+ - * band bor bnot << >> popcount tzcnt pdep))

(define kernel-licm
  (lambda (body)
    (define counter 0)
    (define fresh!
      (lambda ()
        (set! counter (fx+ counter 1))
        (string->symbol (format "%licm-~a" counter))))

    (define pure-arith?
      (lambda (e)
        (cond ((integer? e) #t)
              ((symbol? e) #t)
              ((pair? e) (and (memq (car e) %kernel-licm-arith)
                              (for-all pure-arith? (cdr e))))
              (else #f))))

    (define invariant?
      ;; references at least one variable, none of them variant
      (lambda (e variant)
        (let ((frees (kernel-free-variables e '())))
          (and (pair? frees)
               (not (exists (lambda (v) (memq v variant)) frees))))))

    (define hoistable?
      (lambda (e variant)
        (and (pair? e)
             (memq (car e) %kernel-licm-arith)
             (pure-arith? e)
             (invariant? e variant))))

    (define collect
      ;; maximal hoistable subexpressions; VARIANT grows with every
      ;; local binding so shadowed names disqualify
      (lambda (e variant out)
        (cond
         ((not (pair? e)) out)
         ((hoistable? e variant)
          (if (member e out) out (cons e out)))
         (else
          (case (car e)
            ((let)
             (if (symbol? (cadr e))
                 (let ((out (fold-left (lambda (o b) (collect (cadr b) variant o))
                                       out (caddr e))))
                   (collect (cadddr e)
                            (append (map car (caddr e)) variant)
                            out))
                 (let walk ((bindings (cadr e)) (variant variant) (out out))
                   (if (null? bindings)
                       (collect (caddr e) variant out)
                       (walk (cdr bindings)
                             (cons (caar bindings) variant)
                             (collect (cadar bindings) variant out))))))
            (else (fold-left (lambda (o x) (collect x variant o))
                             out (cdr e))))))))

    (define split-loads
      ;; only meaningful under a loop (VARIANT non-empty)
      (lambda (e variant)
        (cond
         ((not (pair? e)) e)
         (else
          (case (car e)
            ((u8@ u32@ u64@)
             (let ((p (split-loads (cadr e) variant))
                   (off (split-loads (caddr e) variant)))
               (if (or (null? variant) (not (invariant? p variant)))
                   (list (car e) p off)
                   (let-values (((still moved)
                                 (partition
                                  (lambda (a)
                                    (or (not (pure-arith? a))
                                        (not (invariant? a variant))))
                                  (kernel-addends off))))
                     (if (or (null? moved) (null? still))
                         (list (car e) p off)
                         (list (car e)
                               (cons '+ (cons p moved))
                               (if (null? (cdr still))
                                   (car still)
                                   (cons '+ still))))))))
            ((let)
             (if (symbol? (cadr e))
                 (list 'let (cadr e)
                       (map (lambda (b)
                              (list (car b) (split-loads (cadr b) variant)))
                            (caddr e))
                       (split-loads (cadddr e)
                                    (append (map car (caddr e)) variant)))
                 (let walk ((bindings (cadr e)) (variant variant) (acc '()))
                   (if (null? bindings)
                       (list 'let (reverse acc)
                             (split-loads (caddr e) variant))
                       (walk (cdr bindings)
                             (cons (caar bindings) variant)
                             (cons (list (caar bindings)
                                         (split-loads (cadar bindings) variant))
                                   acc))))))
            (else (cons (car e)
                        (map (lambda (x) (split-loads x variant)) (cdr e)))))))))

    (define substitute
      ;; replace candidate occurrences by their hoisted names,
      ;; skipping scopes that shadow any of the candidate's inputs
      (lambda (e table bound)
        (cond
         ((and (pair? e) (assoc e table))
          => (lambda (hit)
               (if (exists (lambda (v) (memq v bound))
                           (kernel-free-variables (car hit) '()))
                   (cons (car e)
                         (map (lambda (x) (substitute x table bound)) (cdr e)))
                   (cdr hit))))
         ((not (pair? e)) e)
         (else
          (case (car e)
            ((let)
             (if (symbol? (cadr e))
                 (list 'let (cadr e)
                       (map (lambda (b)
                              (list (car b) (substitute (cadr b) table bound)))
                            (caddr e))
                       (substitute (cadddr e) table
                                   (append (map car (caddr e)) bound)))
                 (let walk ((bindings (cadr e)) (bound bound) (acc '()))
                   (if (null? bindings)
                       (list 'let (reverse acc)
                             (substitute (caddr e) table bound))
                       (walk (cdr bindings)
                             (cons (caar bindings) bound)
                             (cons (list (caar bindings)
                                         (substitute (cadar bindings) table bound))
                                   acc))))))
            (else (cons (car e)
                        (map (lambda (x) (substitute x table bound)) (cdr e)))))))))

    (define transform
      (lambda (e variant)
        (cond
         ((not (pair? e)) e)
         (else
          (case (car e)
            ((let)
             (if (symbol? (cadr e))
                 (let* ((name (cadr e))
                        (bindings (map (lambda (b)
                                         (list (car b) (transform (cadr b) variant)))
                                       (caddr e)))
                        (variant* (append (map car (caddr e)) variant))
                        (body (split-loads (transform (cadddr e) variant*)
                                           variant*))
                        (candidates (collect body variant* '())))
                   (if (null? candidates)
                       (list 'let name bindings body)
                       (let* ((names (map (lambda (c) (fresh!)) candidates))
                              (table (map cons candidates names)))
                         (list 'let (map (lambda (c n) (list n c))
                                         candidates names)
                               (list 'let name
                                     (map (lambda (b)
                                            (list (car b)
                                                  (substitute (cadr b) table '())))
                                          bindings)
                                     (substitute body table '()))))))
                 (let walk ((bindings (cadr e)) (variant variant) (acc '()))
                   (if (null? bindings)
                       (list 'let (reverse acc) (transform (caddr e) variant))
                       (walk (cdr bindings)
                             (cons (caar bindings) variant)
                             (cons (list (caar bindings)
                                         (transform (cadar bindings) variant))
                                   acc))))))
            (else (cons (car e)
                        (map (lambda (x) (transform x variant)) (cdr e)))))))))

    (transform body '())))

(define %kernel-pressure?
  (lambda (ex)
    (and (message-condition? ex)
         (string=? (condition-message ex)
                   "out of registers (too many live variables) at"))))

(define %kernel-compile
  (lambda (arguments body)

    (define code '())                   ; reversed instructions
    (define free %kernel-pool)          ; registers not held
    (define used-callee '())            ; callee-saved ever allocated
    (define counter 0)

    (define oops
      (lambda (message expr)
        (error 'kernel message expr)))

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

    ;; Available expressions: (expr reg deps owned?) — a pure
    ;; subexpression already computed in REG, valid on the current
    ;; straight-line path. DEPS are the registers of its free
    ;; variables. OWNED entries hold their register (scavenged under
    ;; pressure before erroring); unowned entries borrow a caller's
    ;; register. Joins (labels) kill everything: values arriving from
    ;; two paths may differ.
    (define available '())

    (define cache-flush!
      (lambda ()
        (for-each (lambda (entry)
                    (when (cadddr entry)
                      (set! free (cons (cadr entry) free))))
                  available)
        (set! available '())))

    (define cache-write!
      ;; REG is about to be overwritten: kill every entry that lives
      ;; in it or depends on it, freeing owned casualties.
      (lambda (reg)
        (let ((dead (filter (lambda (entry)
                              (or (eq? (cadr entry) reg)
                                  (memq reg (caddr entry))))
                            available)))
          (unless (null? dead)
            (set! available (filter (lambda (e) (not (memq e dead))) available))
            (for-each (lambda (entry)
                        (when (and (cadddr entry)
                                   (not (eq? (cadr entry) reg)))
                          (release! (cadr entry))))
                      dead)))))

    (define cache-ref
      (lambda (e)
        (cond ((assoc e available) => cadr) (else #f))))

    (define cache-add!
      (lambda (e reg env owned?)
        (unless (or (eq? reg 'rax) (eq? reg 'rcx))
          (let ((deps (fold-left (lambda (out v)
                                   (cond ((assq v env) => (lambda (x) (cons (cdr x) out)))
                                         (else out)))
                                 '()
                                 (kernel-free-variables e '()))))
            (set! available (cons (list e reg deps owned?) available))))))

    (define cache-own!
      ;; Transfer ownership of REG's entry to the cache (the caller
      ;; will not release it).
      (lambda (e reg)
        (set! available
              (map (lambda (entry)
                     (if (and (eq? (cadr entry) reg) (equal? (car entry) e))
                         (list (car entry) (cadr entry) (caddr entry) #t)
                         entry))
                   available))))

    (define allocate!
      (lambda (context)
        ;; Prefer caller-saved: keep pool order, not release order.
        ;; Under pressure, scavenge cache-owned registers before
        ;; giving up.
        (let try ()
          (let loop ((pool %kernel-pool))
            (cond ((null? pool)
                   (let ((victim (find (lambda (e) (cadddr e)) available)))
                     (if victim
                         (begin (release! (cadr victim)) (try))
                         (oops "out of registers (too many live variables) at"
                               context))))
                  ((memq (car pool) free)
                   (hold! (car pool))
                   (car pool))
                  (else (loop (cdr pool))))))))

    (define release!
      (lambda (reg)
        (set! free (cons reg free))
        (cache-write! reg)))

    (define emit-label!
      (lambda (name)
        (cache-flush!)
        (emit! (list 'label name))))

    (define lookup
      (lambda (variable env)
        (cond ((assq variable env) => cdr)
              (else (oops "unbound variable" variable)))))

    (define int32?
      (lambda (x) (and (integer? x) (<= -2147483648 x 2147483647))))

    (define r32
      (lambda (reg) (cdr (assq reg %kernel-r32))))

    (define operand
      ;; Evaluate E for use as a source operand: returns (values reg
      ;; release?) — a variable's own register, a cached
      ;; computation, or a fresh temporary whose ownership passes to
      ;; the available-expression cache (scavenged under pressure,
      ;; never released by the caller).
      (lambda (e env)
        (cond
         ((and (symbol? e) (assq e env))
          (values (lookup e env) #f))
         ((and (pair? e) (cache-ref e))
          (values (cache-ref e) #f))
         ((pair? e)
          (let ((r (allocate! e)))
            (comp-expr e r env)
            (cache-own! e r)
            (values r #f)))
         (else
          (let ((r (allocate! e)))
            (comp-expr e r env)
            (values r #t))))))

    (define comp-lea!
      ;; Synthesize a (+ ...) whose addends fit base + index*scale +
      ;; disp32 into a single lea. #f falls back to comp-binop!.
      (lambda (e target env)
        (let sort ((addends (kernel-addends e))
                   (bases '()) (index #f) (disp 0))
          (if (pair? addends)
              (match (car addends)
                (,n
                 (guard (integer? n))
                 (sort (cdr addends) bases index (+ disp n)))
                ((<< ,x ,k)
                 (guard (and (symbol? x) (assq x env)
                             (memv k '(1 2 3)) (not index)))
                 (sort (cdr addends) bases
                       (cons (lookup x env) (expt 2 k)) disp))
                (,v
                 (guard (and (symbol? v) (assq v env)))
                 (sort (cdr addends) (cons (lookup v env) bases) index disp))
                (,_ #f))
              (and (int32? disp)
                   (cond
                    ((and (fx=? (length bases) 1) index)
                     (emit! (list 'lea target
                                  (list '& (car bases) (car index)
                                        (cdr index) disp)))
                     #t)
                    ((and (fx=? (length bases) 2) (not index))
                     (emit! (list 'lea target
                                  (list '& (car bases) (cadr bases) 1 disp)))
                     #t)
                    ((and (fx=? (length bases) 1) (not index)
                          (not (zero? disp)))
                     (emit! (list 'lea target (list '& (car bases) disp)))
                     #t)
                    (else #f)))))))

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
      ;; SIB fusion: fold the offset's constant part into the
      ;; displacement and one (<< i k) addend into index*scale, so
      ;; the address unit computes what would otherwise be explicit
      ;; shifts and adds. One further variable addend costs a single
      ;; lea; more than that falls back to the generic path.
      (lambda (e target env)
        (let ((width (car e)) (pointer (cadr e)) (offset (caddr e)))
          (let-values (((p prelease?) (operand pointer env)))
            (define (emit-load! address)
              (case width
                ((u8@) (emit! (list 'movzx target address)))
                ((u32@) (emit! (list 'mov (r32 target) address)))
                (else (emit! (list 'mov target address)))))
            (define (generic!)
              (let-values (((o orelease?) (operand offset env)))
                (emit-load! (list '& p o 1 0))
                (when orelease? (release! o))))
            (let sort ((addends (kernel-addends offset))
                       (others '()) (index #f) (disp 0))
              (cond
               ((pair? addends)
                (match (car addends)
                  (,n
                   (guard (integer? n))
                   (sort (cdr addends) others index (+ disp n)))
                  ((<< ,x ,k)
                   (guard (and (memv k '(1 2 3)) (not index)))
                   (sort (cdr addends) others (cons x (expt 2 k)) disp))
                  (,other
                   (sort (cdr addends) (cons other others) index disp))))
               ((or (not (int32? disp)) (fx>? (length others) 1))
                (generic!))
               ((and (null? others) (not index))
                (emit-load! (if (zero? disp)
                                (list '& p)
                                (list '& p disp))))
               ((and (pair? others) (not index))
                ;; one variable addend, no scaled index: the SIB
                ;; carries it directly, no lea needed
                (let-values (((o orelease?) (operand (car others) env)))
                  (emit-load! (list '& p o 1 disp))
                  (when orelease? (release! o))))
               (else
                (let ((base (if (null? others)
                                p
                                (let-values (((o orelease?)
                                              (operand (car others) env)))
                                  (let ((t (allocate! offset)))
                                    (emit! (list 'lea t (list '& p o 1 0)))
                                    (when orelease? (release! o))
                                    t)))))
                  (let-values (((i irelease?) (operand (car index) env)))
                    (emit-load! (list '& base i (cdr index) disp))
                    (when irelease? (release! i)))
                  (unless (eq? base p) (release! base))))))
            (when prelease? (release! p))))))

    (define comp-expr
      ;; Common subexpression reuse sits here: a pair expression
      ;; already available on this straight-line path is a register
      ;; move (or nothing), not a recomputation.
      (lambda (e target env)
        (let ((cached (and (pair? e) (cache-ref e))))
          (cond
           ((eq? cached target))        ; already in place
           (cached
            (cache-write! target)
            (emit! (list 'mov target cached)))
           (else
            (cache-write! target)
            (comp-dispatch! e target env)
            (when (pair? e)
              (cache-add! e target env #f)))))))

    (define comp-dispatch!
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
            ((+) (unless (comp-lea! e target env)
                   (comp-binop! '+ e target env)))
            ((- * band bor) (comp-binop! (car e) e target env))
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
               (emit-label! otherwise)
               (comp-expr (cadddr e) target env)
               (emit-label! join)))
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

    (define calls-loop?
      ;; Does E contain a call to the loop named NAME?
      (lambda (e name)
        (and (pair? e)
             (or (eq? (car e) name)
                 (exists (lambda (x) (calls-loop? x name))
                         (cdr e))))))

    (define pinned
      ;; Registers a later iteration of a still-reachable loop may
      ;; read: its loop variables, and every outer variable its body
      ;; references. A loop the tail expression E never calls cannot
      ;; be re-entered, so its pins do not apply. Loop records are
      ;; (name label (reg ...) (pinned-reg ...)).
      (lambda (e loops)
        (apply append (map (lambda (loop)
                             (if (calls-loop? e (car loop))
                                 (append (caddr loop) (cadddr loop))
                                 '()))
                           loops))))

    (define prune!
      ;; Release environment entries not referenced by tail
      ;; expression E (control never returns to this scope), except
      ;; registers a reachable loop still needs. Returns the pruned
      ;; environment.
      (lambda (e env loops)
        (let ((needed (kernel-free-variables e '()))
              (keep (pinned e loops)))
          (filter (lambda (entry)
                    (if (or (memq (car entry) needed)
                            (memq (cdr entry) keep))
                        #t
                        (begin (release! (cdr entry)) #f)))
                  env))))

    (define comp-tail
      (lambda (e env loops)
        (cache-flush!)
        (let ((env (prune! e env loops)))
          (cond
           ((and (pair? e) (eq? (car e) 'if))
            (let ((otherwise (fresh-label "else")))
              (comp-test (cadr e) otherwise env)
              ;; flush before the free-pool snapshot so cache-owned
              ;; registers cannot straddle the branch bookkeeping
              (cache-flush!)
              (let ((snapshot free))
                (comp-tail (caddr e) env loops)
                (cache-flush!)
                (set! free snapshot))
              (emit-label! otherwise)
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
              (emit-label! label)
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

    ;; Two passes: pin every in-register argument in its home
    ;; register first, so relocations (the rcx argument, stack
    ;; arguments) cannot be handed a home register still to come.
    (let bind ((arguments arguments) (index 0))
      (unless (null? arguments)
        (when (and (fx<? index 6)
                   (not (eq? (list-ref %kernel-arg-registers index) 'rcx)))
          (let ((reg (list-ref %kernel-arg-registers index)))
            (hold! reg)
            (set! env (cons (cons (cadar arguments) reg) env))))
        (bind (cdr arguments) (fx+ index 1))))
    (let bind ((arguments arguments) (index 0))
      (unless (null? arguments)
        (let ((name (cadar arguments)))
          (when (or (fx>=? index 6)
                    (eq? (list-ref %kernel-arg-registers index) 'rcx))
            (let ((reg (allocate! name)))
              (set! deferred
                    (cons (cons reg (if (fx<? index 6) 'rcx (fx- index 6)))
                          deferred))
              (set! env (cons (cons name reg) env)))))
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
