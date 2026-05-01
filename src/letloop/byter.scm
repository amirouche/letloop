(library (letloop byter)

  (export byter-end
          byter-encode
          byter-decode
          byter-compare
          byter-compare*
          byter-next-prefix
          byter-slice
          byter-append
          byter-concatenate
          byter-split
          byter-random
          ~check-byter-000
          ~check-byter-001
          ~check-byter-002
          ~check-byter-003
          ~check-byter-004
          ~check-byter-005
          ~check-byter-006/random
          ~check-byter-007/random
          ~check-byter-008
          ~check-byter-009
          ~check-byter-010
          ~check-byter-011
          ~check-byter-012
          ~check-byter-013
          ~check-byter-014
          ~check-byter-015
          ~check-byter-016
          ~check-byter-017/random
          ~check-byter-100
          ~check-byter-101
          ~check-byter-102
          ~check-byter-103
          ~check-byter-104
          ~check-byter-998/seed
          ~check-byter-998/random
          ~check-byter-999/seed
          ~check-byter-999/random)

  (import (chezscheme))

  (define pk
    (lambda args
      (display ";; ")
      (write args)
      (newline)
      (flush-output-port)
      (car (reverse args))))

  ;; TODO: move to (letloop bytevector)

  (define (byter-next-prefix bytevector)
    "Return the first bytevector that is not prefix of BYTEVECTOR"
    ;; See https://git.io/fj34F, TODO: OPTIMIZE
    (let ((bytes (reverse (bytevector->u8-list bytevector))))
      ;; strip #xFF
      (let loop ((out bytes))
        (when (null? out)
          (error 'foundationdb
                 "BYTEVECTOR must contain at least one byte not equal to #xFF."
                 bytevector))
        (if (= (car out) #xFF)
            (loop (cdr out))
            (set! bytes out)))
      ;; increment first byte, reverse and return the bytevector
      (u8-list->bytevector (reverse (cons (fx+ 1 (car bytes)) (cdr bytes))))))

  ;; TODO: rename bytevector-slice, and move to (letloop bytevector)
  (define subbytes
    (case-lambda
      ((bv start end)
       (unless (<= 0 start end (bytevector-length bv))
         (error 'subbytes "Invalid indices: ~a ~a ~a" bv start end (bytevector-length bv)))
       (if (and (fxzero? start)
                (fx=? end (bytevector-length bv)))
           bv
           (let ((ret (make-bytevector (fx- end start))))
             (bytevector-copy! bv start
                               ret 0 (fx- end start))
             ret)))
      ((bv start)
       (subbytes bv start (bytevector-length bv)))))

  (define byter-slice subbytes)

  (define byter-random
    (lambda (length)
      (u8-list->bytevector (map (lambda x (random 256)) (iota length)))))
  
  (define byter-concatenate
    (lambda (bvs)
      (let* ((total (apply fx+ (map bytevector-length bvs)))
             (out (make-bytevector total)))
        (let loop ((bvs bvs)
                   (index 0))
          (unless (null? bvs)
            (bytevector-copy! (car bvs) 0 out index (bytevector-length (car bvs)))
            (loop (cdr bvs) (fx+ index (bytevector-length (car bvs))))))
        out)))

  (define byter-append
    (lambda args
      (byter-concatenate args)))

  (define byter-split
    (lambda (bytevector length)
      (let loop ((start 0)
                 (out '()))
        (if (<= (- (bytevector-length bytevector) start) length)
            (reverse
             (cons (byter-append (byter-slice bytevector start (bytevector-length bytevector))
                                 (make-bytevector (- length
                                                     (- (bytevector-length bytevector) start))
                                                  0))
                   out))
            (loop (+ start length)
                  (cons (byter-slice bytevector start (+ start length)) out))))))

  (define byter-null #x00)
  (define byter-false #x01)
  (define byter-true #x02)
  (define byter-pair #x03)
  (define byter-vector #x04)
  (define byter-vector-end #x05)
  (define byter-bytevector #x06)
  (define byter-string #x07)
  (define byter-symbol #x08)
  (define byter-flonum #x09)

  ;; before zero ...
  (define byter-zero #x20)
  ;; ... after zero

  (define byter-escape #xFF)

  (define byter-end (bytevector 255))

  (define boolean-compare
    (lambda (a b)
      (if (eq? a b)
          'equal
          (if (not a)
              'smaller
              'bigger))))

  (define byter-spec-find
    (lambda (object)
      (find (lambda (spec) ((car spec) object)) byter-spec)))

  (define byter-compare*
    (lambda (object other)
      (let ((object-spec (byter-spec-find object))
            (other-spec (byter-spec-find other)))
        (if (eq? object-spec other-spec)
            (let ((comparator (list-ref object-spec 2)))
              (comparator object other))
            (let ((object-tag (list-ref object-spec 1))
                  (other-tag (list-ref other-spec 1)))
              (integer-compare object-tag other-tag))))))

  (define byter-integer?
    (lambda (x)
      (and (number? x)
           (exact? x)
           (< x (expt 2 64)))))

  (define integer-compare
    (lambda (a b)
      (if (< a b)
          'smaller
          (if (= a b)
              'equal
              'bigger))))

  (define pair-compare
    (lambda (a b)
      (case (byter-compare* (car a) (car b))
        ((smaller) 'smaller)
        ((bigger) 'bigger)
        ((equal) (byter-compare* (cdr a) (cdr b))))))

  (define vector-compare
    (lambda (a b)
      (let ((end (fxmin (vector-length a)
                        (vector-length b))))
        (let loop ((index 0))
          (if (fx=? end index)
              (if (fx=? (vector-length a)
                        (vector-length b))
                  'equal
                  (if (fx<? (vector-length a)
                            (vector-length b))
                      'smaller
                      'bigger))
              (case (byter-compare* (vector-ref a index)
                                    (vector-ref b index))
                ((bigger) 'bigger)
                ((smaller) 'smaller)
                ((equal) (loop (fx+ index 1)))))))))

  (define (byter-compare bytevector other)
    ;; Returns the symbol 'smaller if BYTEVECTOR is before OTHER, if
    ;; they are equal return the symbol 'equal, and otherwise returns
    ;; the symbol 'bigger.
    (let ((end (fxmin (bytevector-length bytevector)
                      (bytevector-length other))))
      (let loop ((index 0))
        (if (fx=? end index)
            ;; BYTEVECTOR and OTHER are equal until index; BYTEVECTOR
            ;; is smaller lexicographically, if it is smaller in
            ;; length.
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
                      'bigger)))))))

  (define string-compare
    (lambda (a b)
      (if (string<? a b)
          'smaller
          (if (string=? a b)
              'equal
              'bigger))))

  (define symbol-compare
    (lambda (a b)
      (string-compare (symbol->string a) (symbol->string b))))

  (define flonum-compare
    (lambda (a b)
      (if (fl<? a b) 'smaller
          (if (fl=? a b) 'equal 'bigger))))

  (define byter-spec
    (list (list null? byter-null (lambda (a b) 'equal))
          (list boolean? byter-false boolean-compare)
          (list pair? byter-pair pair-compare)
          (list byter-integer? byter-zero integer-compare)
          (list vector? byter-vector vector-compare)
          (list bytevector? byter-bytevector byter-compare)
          (list string? byter-string string-compare)
          (list symbol? byter-symbol symbol-compare)
          (list flonum? byter-flonum flonum-compare)))

  ;; helpers

  (define bytevector-accumulator
    (lambda ()
      (let ((bytes '())
            (length 0))
        (lambda (maybe-byte)
          (if (eof-object? maybe-byte)
              (let ((out (make-bytevector length)))
                (let loop ((index length)
                           (bytes bytes))
                  (if (fxzero? index)
                      out
                      (let ((index (fx- index 1)))
                        (bytevector-u8-set! out index (car bytes))
                        (loop index (cdr bytes))))))
              (begin
                (set! bytes (cons maybe-byte bytes))
                (set! length (fx+ length 1))))))))

  (define bytevector-for-each
    (lambda (proc bytevector)
      (let loop ((index 0))
        (unless (fx=? index (bytevector-length bytevector))
          (proc (bytevector-u8-ref bytevector index))
          (loop (fx+ index 1))))))

  ;; packing

  (define (byter-bytevector-pack accumulator tag bytevector)
    (accumulator tag)
    (let loop ((index 0))
      (unless (fx=? index (bytevector-length bytevector))
        (let ((byte (bytevector-u8-ref bytevector index)))
          (if (fxzero? byte)
              (begin ;; escape null byte
                (accumulator #x00)
                (accumulator byter-escape))
              (accumulator byte))
          (loop (fx+ index 1)))))
    (accumulator #x00))

  (define byter-string-pack
    (lambda (accumulator object)
      (byter-bytevector-pack accumulator
                             byter-string
                             (string->utf8 object))))

  (define byter-symbol-pack
    (lambda (accumulator object)
      (byter-bytevector-pack accumulator
                             byter-symbol
                             (string->utf8 (symbol->string object)))))

  (define byter-bytevector-unpack
    (lambda (bytevector index)
      (let ((out (bytevector-accumulator)))
        (let loop ((index (fx+ index 1)))
          (if (fxzero? (bytevector-u8-ref bytevector index))
              (cond
               ;; end of input
               ((fx=? (fx+ index 1) (bytevector-length bytevector))
                (values (out (eof-object)) (fx+ index 1)))
               ;; escaped null bytes
               ((fx=? (bytevector-u8-ref bytevector (fx+ index 1)) byter-escape)
                (out #x00)
                (loop (fx+ index 2)))
               ;; end of bytevector
               (else (values (out (eof-object)) (fx+ index 1))))
              ;; just a byte
              (begin
                (out (bytevector-u8-ref bytevector index))
                (loop (fx+ index 1))))))))

  (define byter-string-unpack
    (lambda (bytevector index)
      (call-with-values (lambda () (byter-bytevector-unpack bytevector index))
        (lambda (bytevector index)
          (values (utf8->string bytevector) index)))))

  (define byter-symbol-unpack
    (lambda (bytevector index)
      (call-with-values (lambda () (byter-bytevector-unpack bytevector index))
        (lambda (bytevector index)
          (values (string->symbol (utf8->string bytevector)) index)))))

  (define byter-flonum-pack
    (lambda (accumulator value)
      (accumulator byter-flonum)
      (let ((bv (make-bytevector 8)))
        (bytevector-ieee-double-set! bv 0 value 'big)
        (if (fx>=? (bytevector-u8-ref bv 0) #x80)
            ;; Negative: flip all bits for correct ordering
            (let loop ((i 0))
              (unless (fx=? i 8)
                (accumulator (fxlogxor (bytevector-u8-ref bv i) #xFF))
                (loop (fx+ i 1))))
            ;; Positive (including +0): flip sign bit
            (begin
              (accumulator (fxlogior (bytevector-u8-ref bv 0) #x80))
              (let loop ((i 1))
                (unless (fx=? i 8)
                  (accumulator (bytevector-u8-ref bv i))
                  (loop (fx+ i 1)))))))))

  (define byter-flonum-unpack
    (lambda (bytevector index)
      (let ((bv (make-bytevector 8))
            (first (bytevector-u8-ref bytevector (fx+ index 1))))
        (if (fx>=? first #x80)
            ;; Was positive: flip sign bit back
            (begin
              (bytevector-u8-set! bv 0 (fxlogxor first #x80))
              (let loop ((i 1))
                (unless (fx=? i 8)
                  (bytevector-u8-set! bv i
                    (bytevector-u8-ref bytevector (fx+ index 1 i)))
                  (loop (fx+ i 1)))))
            ;; Was negative: flip all bits back
            (let loop ((i 0))
              (unless (fx=? i 8)
                (bytevector-u8-set! bv i
                  (fxlogxor (bytevector-u8-ref bytevector (fx+ index 1 i)) #xFF))
                (loop (fx+ i 1)))))
        (values (bytevector-ieee-double-ref bv 0 'big)
                (fx+ index 9)))))

  (define integer->bytevector
    (lambda (integer)
      (let ((bytevector (make-bytevector 8)))
        (bytevector-u64-set! bytevector 0 integer 'big)
        bytevector)))

  (define bytevector->integer
    (lambda (bytevector)
      (bytevector-u64-ref bytevector 0 'big)))

  (define byter-positive-integer-pack
    (lambda (accumulator integer)
      (define bytevector (integer->bytevector integer))
      ;; There is necessarly a byte that is not zero, because integer
      ;; is not zero.
      (define zero-count-from-the-left
        (let loop ((index 0))
          (if (fxzero? (bytevector-u8-ref bytevector index))
              (loop (fx+ index 1))
              index)))
      (define byter-zero-shift (fx- 8 zero-count-from-the-left))
      (define byter-code (fx+ byter-zero byter-zero-shift))
      (accumulator byter-code)
      (let loop ((index zero-count-from-the-left))
        (unless (fx=? index 8)
          (accumulator (bytevector-u8-ref bytevector index))
          (loop (fx+ index 1))))))

  (define byter-positive-integer-unpack
    (lambda (bytevector index)
      (define out (make-bytevector 8 0))
      (define length (fx- (bytevector-u8-ref bytevector index) byter-zero))
      (define start (fx- 8 length))
      (define end (fx+ index length 1))
      (let loop ((index (fx+ index 1))
                 (other start))
        (unless (fx=? index end)
          (bytevector-u8-set! out other (bytevector-u8-ref bytevector index))
          (loop (fx+ index 1) (fx+ other 1))))
      (values (bytevector->integer out) (fx+ index length 1))))

  (define byter-negative-integer-pack
    (lambda (accumulator integer)
      (define bytevector (integer->bytevector (- integer)))
      ;; There is necessarly a byte that is not zero, because integer
      ;; is not zero.
      (define zero-count-from-the-left
        (let loop ((index 0))
          (if (fxzero? (bytevector-u8-ref bytevector index))
              (loop (fx+ index 1))
              index)))
      (define byter-zero-shift (fx- 8 zero-count-from-the-left))
      (define byter-code (fx- byter-zero byter-zero-shift))
      (accumulator byter-code)
      (let loop ((index zero-count-from-the-left))
        (unless (fx=? index 8)
          (accumulator (bitwise-xor (bytevector-u8-ref bytevector
                                                       index)
                                    #xFF))
          (loop (fx+ index 1))))))

  (define byter-negative-integer-unpack
    (lambda (bytevector index)
      (define out (make-bytevector 8 0))
      (define length (fx- byter-zero (bytevector-u8-ref bytevector index)))
      (define start (fx- 8 length))
      (define end (fx+ index length 1))
      (let loop ((index (fx+ index 1))
                 (other start))
        (unless (fx=? index end)
          (bytevector-u8-set! out other
                              (bitwise-xor (bytevector-u8-ref bytevector index)
                                           #xFF))
          (loop (fx+ index 1) (fx+ other 1))))
      (values (- (bytevector->integer out)) (fx+ index length 1))))

  (define byter-encode
    (case-lambda
      ((object)
       (byter-encode object (bytevector-accumulator)))
      ((object accumulator)
       (cond
        ((null? object) (accumulator byter-null))
        ((pair? object)
         (accumulator byter-pair)
         (byter-encode (car object) accumulator)
         (byter-encode (cdr object) accumulator))
        ((eq? object #f) (accumulator byter-false))
        ((eq? object #t) (accumulator byter-true))
        ((bytevector? object) (byter-bytevector-pack accumulator
                                                     byter-bytevector
                                                     object))
        ((and (number? object)
              (exact? object)
              (< (abs object) (expt 2 64)))
         (if (zero? object)
             (accumulator byter-zero)
             (if (positive? object)
                 (byter-positive-integer-pack accumulator object)
                 (byter-negative-integer-pack accumulator object))))
        ((flonum? object) (byter-flonum-pack accumulator object))
        ((string? object) (byter-string-pack accumulator object))
        ((symbol? object) (byter-symbol-pack accumulator object))
        ((vector? object)
         (accumulator byter-vector)
         (vector-for-each
          (lambda (object) (byter-encode object accumulator))
          object)
         (accumulator byter-vector-end))
        (else (error 'byter-encode "Unsupported type" object)))
       (accumulator (eof-object)))))

  (define byter-base-unpack
    (lambda (bytevector index)
      (let ((tag (bytevector-u8-ref bytevector index)))
        (case tag
          ((#x00) (values '() (fx+ index 1)))
          ((#x01) (values #f (fx+ index 1)))
          ((#x02) (values #t (fx+ index 1)))
          ((#x03) (byter-pair-unpack bytevector index))
          ((#x04) (byter-vector-unpack bytevector (fx+ index 1) '() 0))
          ((#x06) (byter-bytevector-unpack bytevector index))
          ((#x07) (byter-string-unpack bytevector index))
          ((#x08) (byter-symbol-unpack bytevector index))
          ((#x09) (byter-flonum-unpack bytevector index))
          ((#x18 #x19 #x1A #x1B #x1C #x1D #x1E #x1F) (byter-negative-integer-unpack bytevector index))
          ((#x20) (values 0 (fx+ index 1)))
          ((#x21 #x22 #x23 #x24 #x25 #x26 #x27 #x28) (byter-positive-integer-unpack bytevector index))
          (else (error 'byter-decode "Unsupported type with tag" (number->string tag 16)))))))

  (define byter-decode
    (lambda (bytevector)
      (call-with-values (lambda () (byter-base-unpack bytevector 0))
        (lambda (out index) out))))

  (define byter-pair-unpack
    (lambda (bytevector index)
      (call-with-values (lambda () (byter-base-unpack bytevector (fx+ index 1)))
        (lambda (out index)
          (call-with-values (lambda () (byter-base-unpack bytevector index))
            (lambda (out* index)
              (values (cons out out*) index)))))))

  (define byter-vector-unpack
    (lambda (bytevector index out length)

      (define massage
        (lambda (objects length)
          (define out (make-vector length))
          (let loop ((index length)
                     (objects objects))
            (unless (fxzero? index)
              (vector-set! out (fx- index 1) (car objects))
              (loop (fx- index 1) (cdr objects))))
          out))

      (let ((tag (bytevector-u8-ref bytevector index)))
        (if (fx=? tag byter-vector-end)
            (values (massage out length) (fx+ index 1))
            (call-with-values (lambda ()
                                (byter-base-unpack bytevector index))
              (lambda (out* index)
                (byter-vector-unpack bytevector
                                     index
                                     (cons out* out)
                                     (fx+ length 1))))))))

  ;; tests

  (define ~check-byter-000
    (lambda ()
      (eq? #f (byter-decode (byter-encode #f)))))

  (define ~check-byter-001
    (lambda ()
      (eq? #t (byter-decode (byter-encode #t)))))

  (define ~check-byter-002
    (lambda ()
      (null? (byter-decode (byter-encode '())))))

  (define ~check-byter-003
    (lambda ()
      (equal? (bytevector 13 37) (byter-decode (byter-encode (bytevector 13 37))))))

  (define ~check-byter-004
    (lambda ()
      (let loop ((power 65))
        (if (fxzero? power)
            #t
            (let ((number (- (expt 2 (fx- power 1)) 1)))
              (assert (= number (byter-decode (byter-encode number))))
              (loop (fx- power 1)))))))

  (define ~check-byter-005
    (lambda ()
      (let loop ((power 65))
        (if (fxzero? power)
            #t
            (let ((number (- (- (expt 2 (fx- power 1)) 1))))
              (assert (= number (byter-decode (byter-encode number))))
              (loop (fx- power 1)))))))

  (define ~check-byter-006/random
    (lambda ()
      (let loop ((i 1000))
        (if (fxzero? i)
            #t
            (let ((number (random (expt 2 64))))
              (assert (= number (byter-decode (byter-encode number))))
              (loop (fx- i 1)))))))

  (define ~check-byter-007/random
    (lambda ()
      (let loop ((i 1000))
        (if (fxzero? i)
            #t
            (let ((number (- (random (expt 2 64)))))
              (assert (= number (byter-decode (byter-encode number))))
              (loop (fx- i 1)))))))

  (define ~check-byter-008
    (lambda ()
      (string=? "azul" (byter-decode (byter-encode "azul")))))

  (define ~check-byter-009
    (lambda ()
      (eq? 'grenouille (byter-decode (byter-encode 'grenouille)))))

  (define ~check-byter-010
    (lambda ()
      (equal? (bytevector) (byter-decode (byter-encode (bytevector))))))

  (define ~check-byter-011
    (lambda ()
      (equal? (bytevector 0) (byter-decode (byter-encode (bytevector 0))))))

  (define ~check-byter-012
    (lambda ()
      (equal? (bytevector 0 0 0) (byter-decode (byter-encode (bytevector 0 0 0))))))

  (define ~check-byter-013
    (lambda ()
      (fl=? 3.14 (byter-decode (byter-encode 3.14)))))

  (define ~check-byter-014
    (lambda ()
      (fl=? -2.718 (byter-decode (byter-encode -2.718)))))

  (define ~check-byter-015
    (lambda ()
      (and (fl=? 0.0 (byter-decode (byter-encode 0.0)))
           (fl=? -0.0 (byter-decode (byter-encode -0.0)))
           (fl=? +inf.0 (byter-decode (byter-encode +inf.0)))
           (fl=? -inf.0 (byter-decode (byter-encode -inf.0))))))

  (define ~check-byter-016
    (lambda ()
      ;; Ordering: -inf < -1.5 < -0.0 < 0.0 < 1.5 < +inf
      (let ((vals (list -inf.0 -1.5 -0.0 0.0 1.5 +inf.0)))
        (let loop ((encoded (map byter-encode vals)))
          (if (null? (cdr encoded))
              #t
              (and (eq? 'smaller (byter-compare (car encoded) (cadr encoded)))
                   (loop (cdr encoded))))))))

  (define ~check-byter-017/random
    (lambda ()
      (let loop ((i 1000))
        (if (fxzero? i)
            #t
            (let ((v (fl* (fl- (fixnum->flonum (random 2000000)) 1000000.0)
                          (fixnum->flonum (+ 1 (random 1000000))))))
              (assert (fl=? v (byter-decode (byter-encode v))))
              (loop (fx- i 1)))))))

  (define ~check-byter-100
    (lambda ()
      (define expected (list 'symbolics
                             #t
                             #f
                             0
                             (bytevector 13 37)
                             "az ul inu"
                             42
                             -42
                             1337
                             -1337
                             (expt 2 32)
                             (- (expt 2 32))
                             (- (expt 2 64) 1)
                             (- (- (expt 2 64) 1))))
      (equal? (byter-decode (byter-encode expected)) expected)))

  (define ~check-byter-101
    (lambda ()
      (define base (list 'symbolics
                         #t
                         #f
                         0
                         (bytevector 13 37)
                         "az ul inu"
                         42
                         -42
                         1337
                         -1337
                         (expt 2 32)
                         (- (expt 2 32))
                         (- (expt 2 64) 1)
                         (- (- (expt 2 64) 1))))
      (define expected (list->vector base))
      (equal? (byter-decode (byter-encode expected)) expected)))

  (define ~check-byter-102
    (lambda ()
      (define base (list 'symbolics
                         #t
                         #f
                         0
                         (bytevector 13 37)
                         "az ul inu"
                         42
                         -42
                         1337
                         -1337
                         (expt 2 32)
                         (- (expt 2 32))
                         (- (expt 2 64) 1)
                         (- (- (expt 2 64) 1))))
      (define expected (cons (list->vector base) base))
      (equal? (byter-decode (byter-encode expected)) expected)))

  (define ~check-byter-103
    (lambda ()
      (for-each (lambda (i)
                  (define base (make-bytevector 4096))
                  (define expected (+ (random 2048) 1))
                  (for-each (lambda (x) (assert (= expected (bytevector-length x))))
                            (byter-split base expected)))
                (iota 128))
      #t))

  (define ~check-byter-104
    (lambda ()
      ;; -------------------------------------------------------
      ;; exwen key encoding assumption tests
      ;;
      ;; The claim: if we encode keys as
      ;;
      ;;   (byter-encode (list prefix uid attribute-name))
      ;;
      ;; then a range scan from
      ;;
      ;;   (byter-encode (list prefix uid))
      ;;
      ;; to
      ;;
      ;;   (byter-encode (list prefix uid (bytevector 255)))
      ;;
      ;; will capture all attribute keys for that entity and
      ;; nothing else.
      ;;
      ;; This requires:
      ;;
      ;;   1. (list prefix uid) < (list prefix uid attr) for any attr
      ;;   2. (list prefix uid attr) < (list prefix uid (bytevector 255))
      ;;   3. (list prefix other-uid attr) is NOT in that range
      ;;      when other-uid ≠ uid
      ;;   4. attributes sort consistently within an entity
      ;; -------------------------------------------------------

      (define pk
        (lambda args
          (display ";; ")
          (write args)
          (newline)
          (flush-output-port)
          (car (reverse args))))

      (define (assert-smaller label a b)
        (let ((result (byter-compare (byter-encode a) (byter-encode b))))
          (unless (eq? result 'smaller)
            (error 'assert-smaller
                   (string-append label ": expected smaller, got ")
                   result a b))))

      (define (assert-bigger label a b)
        (let ((result (byter-compare (byter-encode a) (byter-encode b))))
          (unless (eq? result 'bigger)
            (error 'assert-bigger
                   (string-append label ": expected bigger, got ")
                   result a b))))

      (define (assert-equal label a b)
        (let ((result (byter-compare (byter-encode a) (byter-encode b))))
          (unless (eq? result 'equal)
            (error 'assert-equal
                   (string-append label ": expected equal, got ")
                   result a b))))

      ;; --- test fixtures ---

      (define prefix 'todos)
      (define uid-a 1)
      (define uid-b 2)

      (define start (list prefix uid-a))
      (define end   (list prefix uid-a (bytevector 255)))

      ;; --- test 1: two-element list < three-element list ---
      ;; (list prefix uid) < (list prefix uid 'todo/title)
      ;;
      ;; structurally: (cons prefix (cons uid '()))
      ;;            vs (cons prefix (cons uid (cons 'todo/title '())))
      ;;
      ;; they diverge at the third position: '() (tag #x03)
      ;; vs (cons ...) (tag #x02). pair tag #x02 < null tag #x03.
      ;;
      ;; WAIT — that means the three-element list sorts BEFORE
      ;; the two-element list. #x02 < #x03.
      ;;
      ;; let's find out.

      (display "test 1: start < key?\n")
      (let* ((key (list prefix uid-a 'todo/title))
             (result (byter-compare (byter-encode start) (byter-encode key))))
        (pk 'test-1 result)
        ;; if this prints 'bigger, our range scan is backwards
        )

      ;; --- test 2: key < end? ---
      (display "test 2: key < end?\n")
      (let* ((key (list prefix uid-a 'todo/title))
             (result (byter-compare (byter-encode key) (byter-encode end))))
        (pk 'test-2 result)
        )

      ;; --- test 3: multiple attributes sort within range ---
      (display "test 3: multiple attributes within range\n")
      (for-each
       (lambda (attr)
         (let* ((key (list prefix uid-a attr))
                (vs-start (byter-compare (byter-encode start) (byter-encode key)))
                (vs-end   (byter-compare (byter-encode key) (byter-encode end))))
           (pk 'test-3 attr vs-start vs-end)))
       '(todo/done todo/title todo/created-at actor/email))

      ;; --- test 4: different uid is outside range ---
      (display "test 4: different uid outside range\n")
      (let* ((foreign-key (list prefix uid-b 'todo/title))
             (vs-start (byter-compare (byter-encode start) (byter-encode foreign-key)))
             (vs-end   (byter-compare (byter-encode foreign-key) (byter-encode end))))
        (pk 'test-4-vs-start vs-start)
        (pk 'test-4-vs-end   vs-end)
        ;; foreign key should be BIGGER than end (uid-b > uid-a)
        )

      ;; --- test 5: attribute sort order is stable ---
      (display "test 5: attribute ordering\n")
      (let* ((key-done  (byter-encode (list prefix uid-a 'todo/done)))
             (key-title (byter-encode (list prefix uid-a 'todo/title))))
        (pk 'test-5-done-vs-title (byter-compare key-done key-title))
        ;; should be consistent with (byter-compare (byter-encode 'todo/done)
        ;;                                          (byter-encode 'todo/title))
        (pk 'test-5-bare (byter-compare (byter-encode 'todo/done)
                                        (byter-encode 'todo/title))))

      ;; --- test 6: the critical pair/null tag question ---
      ;; list encoding: (list a b) = (cons a (cons b '()))
      ;; at the divergence point we compare '() vs (cons attr ...)
      ;; null tag = #x03, pair tag = #x02
      ;; so #x02 < #x03 means three-element sorts BEFORE two-element
      ;;
      ;; if that's the case, we need to swap: start should be the
      ;; shorter list and end the sentinel, but only if shorter > longer.
      ;; let's just see what happens.

      (display "test 6: raw tag check\n")
      (pk 'null-tag #x03)
      (pk 'pair-tag #x02)
      (pk 'pair<null? (< #x02 #x03))

      ;; if pair < null, then (list p u attr) < (list p u)
      ;; and our range scan needs (list p u attr) as START
      ;; which breaks the model.
      ;;
      ;; possible fix: use vectors instead of lists for keys
      ;; since vector encoding uses length prefix, not recursive cons.

      (display "test 7: vector encoding alternative\n")
      (let* ((vstart (vector prefix uid-a))
             (vkey   (vector prefix uid-a 'todo/title))
             (vend   (vector prefix uid-a (bytevector 255))))
        (pk 'vec-start<key (byter-compare (byter-encode vstart) (byter-encode vkey)))
        (pk 'vec-key<end   (byter-compare (byter-encode vkey) (byter-encode vend))))

      ;; vector uses byter-vector (#x04) tag then elements then
      ;; byter-vector-end (#x05). A two-element vector hits #x05
      ;; at position 3. A three-element vector has another element
      ;; at position 3. Since any element tag > #x05? Let's check:
      ;; #x05 vs #x08 (symbol tag) — #x05 < #x08, so three-element
      ;; sorts AFTER two-element. That's what we want.

      (display "test 8: vector end tag check\n")
      (pk 'vector-end-tag #x05)
      (pk 'symbol-tag #x08)
      (pk 'string-tag #x07)
      (pk 'bytevector-tag #x06)
      (pk 'bool-false-tag #x00)
      (pk 'bool-true-tag #x01)
      ;; #x00 and #x01 are BELOW #x05 — booleans as attributes
      ;; would sort before vector-end, breaking the range.
      ;; but we're using symbols for attribute names, so #x08 > #x05. ok.

      ;; --- test 9: what about integer uids? ---

      ;; all above #x05, so vector encoding works for integer uids too.

      (display "test 9: integer uid with vectors\n")
      (let* ((vstart (vector 'todos 42))
             (vkey   (vector 'todos 42 'todo/title))
             (vend   (vector 'todos 42 (bytevector 255))))
        (pk 'int-uid-start<key (byter-compare (byter-encode vstart) (byter-encode vkey)))
        (pk 'int-uid-key<end   (byter-compare (byter-encode vkey) (byter-encode vend))))

      ;; --- test 10: uuid as bytevector uid ---
      (display "test 10: bytevector uid (pseudo-uuid)\n")
      (let* ((fake-uuid (bytevector 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16))
             (vstart (vector 'todos fake-uuid))
             (vkey   (vector 'todos fake-uuid 'todo/title))
             (vend   (vector 'todos fake-uuid (bytevector 255))))
        (pk 'bv-uid-start<key (byter-compare (byter-encode vstart) (byter-encode vkey)))
        (pk 'bv-uid-key<end   (byter-compare (byter-encode vkey) (byter-encode vend))))

      (display "\ndone.\n")))
  
  (define random-object-max-complexity (expt 10 4))

  (define random-object-complexity (make-parameter random-object-max-complexity))

  (define random-object-exhaustion-singleton (cons 'exhaustion 'sentinel))

  (define random-object-exhaustion
    (lambda ()
      random-object-exhaustion-singleton))

  (define random-object-exhaustion?
    (lambda (object)
      (eq? object random-object-exhaustion-singleton)))

  (define random-bytevector
    (lambda ()

      (define random-byte
        (lambda ()
          (random 256)))

      (let ((length (random (random-object-complexity))))
        (random-object-complexity (fx- (random-object-complexity) length))
        (if (fxzero? length)
            (bytevector)
            (let loop ((out '())
                       (length length))
              (if (fxzero? length)
                  (u8-list->bytevector out)
                  (loop (cons (random-byte) out)
                        (fx- length 1))))))))

  (define random-string
    (lambda ()
      (let loop ()
        (guard (ex (else "byter-string"))
          (utf8->string (random-bytevector))))))

  (define random-symbol
    (lambda ()
      (let loop ()
        (guard (ex (else 'byter-symbol))
          (string->symbol (random-string))))))

  (define random-vector-item
    (lambda (vector)
      (define index (random (vector-length vector)))
      (vector-ref vector index)))

  (define random-integer
    (lambda ()
      ;; TODO: replace (expt 2 64) with a bigger power when bigint are supported
      (* (random-vector-item (vector -1 +1)) (random (expt 2 64)))))

  ;; TODO: add support for inexact numbers?

  (define make-seed
    (lambda ()
      (let* ((now (current-time))
             (seed (* (time-second now) (time-nanosecond now))))
        (+ (modulo seed (expt 2 32)) 1))))

  (define byter-random-object
    (case-lambda
      (() (byter-random-object (make-seed)))
      ((seed)
       (string-append "*** LETLOOP_BYTER_SEED=" (number->string seed))
       (random-seed seed)
       (let loop ()
         (random-object-complexity random-object-max-complexity)
         (let ((object (random-object)))
           (if (random-object-exhaustion? object)
               (loop)
               (values seed object)))))))

  (define random-pair
    (lambda ()
      (if (fx<? (random-object-complexity) 2)
          (random-object-exhaustion)
          (begin
            (random-object-complexity (fx- (random-object-complexity) 2))
            (let ((x (random-object))
                  (y (random-object)))
              (if (or (random-object-exhaustion? x)
                      (random-object-exhaustion? y))
                  (random-object-exhaustion)
                  (cons x y)))))))

  (define random-vector
    (lambda ()
      (let ((length (random (random-object-complexity))))
        (random-object-complexity (fx- (random-object-complexity) length))
        (if (fxzero? length)
            (vector)
            (let loop ((out '())
                       (length length))
              (if (or (fxzero? length)
                      (and (not (null? out))
                           (random-object-exhaustion? (car out))))
                  (apply vector (cdr out))
                  (loop (cons (random-object) out)
                        (fx- length 1))))))))

  (define random-object
    (lambda ()
      (random-object-complexity (fx- (random-object-complexity) 1))
      (if (fx<=? (random-object-complexity) 0)
          (random-object-exhaustion)
          (let ((generator
                 (random-vector-item
                  (vector (lambda () #f)
                          (lambda () #t)
                          (lambda () '())
                          random-integer
                          random-bytevector
                          random-string
                          random-symbol
                          random-pair
                          random-vector
                          ;; without the following generated object
                          ;; will always have a complexity equal to
                          ;; random-object-max-complexity
                          random-object-exhaustion
                          ))))
            (generator)))))

  (define ~check-byter-998/seed
    (lambda ()
      (define seed (string->number (or (getenv "LETLOOP_BYTER_SEED") "1")))
      (call-with-values (lambda () (byter-random-object seed))
        (lambda (seed object)
          (equal? object (byter-decode (byter-encode object)))))))

  (define ~check-byter-998/random
    (lambda ()
      (let loop ((i (expt 2 (string->number (or (getenv "LETLOOP_BYTER_N") "8")))))
        (if (fxzero? i)
            #t
            (call-with-values (lambda () (byter-random-object))
              (lambda (seed object)
                (assert (equal? object (byter-decode (byter-encode object))))
                (loop (fx- i 1))))))))

  (define make-comparator
    (lambda (object other)
      (lambda (a b) (eq? (byter-compare* a b)
                         (byter-compare* object other)))))

  (define ~check-byter-999/seed
    (lambda ()
      (define seed (string->number (or (getenv "LETLOOP_BYTER_SEED") "1")))
      (call-with-values (lambda () (byter-random-object seed))
        (lambda (seed object)
          (call-with-values (lambda () (byter-random-object seed))
            (lambda (seed other)
              (let ((comparator (make-comparator object other)))
                (comparator (byter-encode object) (byter-encode other)))))))))

  (define ~check-byter-999/random
    (lambda ()
      (let loop ((i (expt 2 (string->number (or (getenv "LETLOOP_BYTER_N") "8")))))
        (if (fxzero? i)
            #t
            (let ((seed (make-seed)))
              (call-with-values (lambda () (byter-random-object seed))
                (lambda (seed object)
                  (call-with-values (lambda () (byter-random-object seed))
                    (lambda (seed other)
                      (let ((comparator (make-comparator object other)))
                        (assert (comparator (byter-encode object) (byter-encode other)))
                        (loop (fx- i 1))))))))))))

  )
