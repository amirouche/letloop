#!chezscheme
(library (letloop postgresql base)

  (export
   ;; connection lifecycle
   pg-connect
   pg-close

   ;; query interface
   pg-exec
   pg-query
   pg-prepare
   pg-execute
   pg-begin
   pg-commit
   pg-rollback

   ;; result accessors
   pg-result?
   pg-result-columns
   pg-result-rows
   pg-result-command-tag
   pg-result-error?
   pg-result-error-message
   pg-result-error-detail
   pg-result-error-sqlstate

   ;; connection accessors
   pg-connection?
   pg-connection-pid
   pg-connection-secret-key

   ;; error type
   pg-error?
   pg-error-message
   pg-error-payload

   ;; wire helpers (for tests)
   md5-digest
   pg-make-message
   pg-make-startup-message

   ;; crypto (useful standalone)
   sha256-digest
   hmac-sha256
   pbkdf2-hmac-sha256
   base64-encode
   base64-decode)

  (import (chezscheme)
          (letloop r999)
          (letloop liburing low))

  ;;============================================================
  ;; Section 1: Error type
  ;;============================================================

  (define-record-type* <pg-error>
    (make-pg-error message payload)
    pg-error?
    (message pg-error-message)
    (payload pg-error-payload))

  (define pg-raise
    (lambda (message . rest)
      (raise (make-pg-error message
                             (if (null? rest) '() (car rest))))))

  ;;============================================================
  ;; Section 2: Connection record
  ;;============================================================

  (define-record-type* <pg-connection>
    (make-pg-connection fd read-u8 read-exact pid secret params)
    pg-connection?
    (fd         pg-conn-fd)
    (read-u8    pg-conn-read-u8)
    (read-exact pg-conn-read-exact)
    (pid        pg-conn-pid    pg-conn-pid!)
    (secret     pg-conn-secret pg-conn-secret!)
    (params     pg-conn-params pg-conn-params!))

  (define pg-connection-pid        (lambda (c) (pg-conn-pid c)))
  (define pg-connection-secret-key (lambda (c) (pg-conn-secret c)))

  ;;============================================================
  ;; Section 3: Buffered reader
  ;;============================================================

  ;; Returns (values read-u8 read-exact).
  ;; read-u8   : (lambda () -> integer 0-255)
  ;; read-exact: (lambda (n) -> bytevector of exactly n bytes)
  ;; Raises pg-error on EOF or I/O error.
  (define make-pg-reader
    (lambda (fd)
      (let ((buf (make-bytevector 0))
            (pos 0)
            (len 0))

        (define refill!
          (lambda ()
            (let ((chunk (loop-read fd)))
              (cond
               ((eq? chunk #t)
                (pg-raise "Connection closed by server" 'eof))
               ((eq? chunk #f)
                (pg-raise "Read error on connection" 'read-error))
               (else
                (set! buf chunk)
                (set! pos 0)
                (set! len (bytevector-length chunk)))))))

        (define read-u8
          (lambda ()
            (when (fx=? pos len) (refill!))
            (let ((b (bytevector-u8-ref buf pos)))
              (set! pos (fx+ pos 1))
              b)))

        (define read-exact
          (lambda (n)
            (let ((out (make-bytevector n)))
              (let loop ((written 0))
                (when (fx<? written n)
                  (when (fx=? pos len) (refill!))
                  (let* ((avail   (fx- len pos))
                         (needed  (fx- n written))
                         (to-copy (fxmin avail needed)))
                    (bytevector-copy! buf pos out written to-copy)
                    (set! pos (fx+ pos to-copy))
                    (loop (fx+ written to-copy)))))
              out)))

        (values read-u8 read-exact))))

  ;;============================================================
  ;; Section 4: Encoding helpers
  ;;============================================================

  (define bv-append
    (lambda bvs
      (let* ((total (apply fx+ (map bytevector-length bvs)))
             (out   (make-bytevector total)))
        (let loop ((bvs bvs) (off 0))
          (unless (null? bvs)
            (let ((b (car bvs)))
              (bytevector-copy! b 0 out off (bytevector-length b))
              (loop (cdr bvs) (fx+ off (bytevector-length b))))))
        out)))

  (define encode-int16-be
    (lambda (n)
      (let ((bv (make-bytevector 2)))
        (bytevector-u8-set! bv 0 (fxand (fxsrl n 8) #xff))
        (bytevector-u8-set! bv 1 (fxand n #xff))
        bv)))

  (define encode-int32-be
    (lambda (n)
      (let ((bv (make-bytevector 4)))
        (bytevector-u8-set! bv 0 (fxand (fxsrl n 24) #xff))
        (bytevector-u8-set! bv 1 (fxand (fxsrl n 16) #xff))
        (bytevector-u8-set! bv 2 (fxand (fxsrl n  8) #xff))
        (bytevector-u8-set! bv 3 (fxand n #xff))
        bv)))

  (define encode-cstring
    (lambda (s)
      (let* ((b   (string->utf8 s))
             (out (make-bytevector (fx+ (bytevector-length b) 1) 0)))
        (bytevector-copy! b 0 out 0 (bytevector-length b))
        out)))

  ;; Standard framed message: [type 1b][length int32 includes itself][payload]
  (define pg-make-message
    (lambda (type-char . payload-bvs)
      (let* ((payload  (apply bv-append payload-bvs))
             (plen     (bytevector-length payload))
             (msg-len  (fx+ 4 plen))
             (out      (make-bytevector (fx+ 1 msg-len))))
        (bytevector-u8-set! out 0 (char->integer type-char))
        (bytevector-u8-set! out 1 (fxand (fxsrl msg-len 24) #xff))
        (bytevector-u8-set! out 2 (fxand (fxsrl msg-len 16) #xff))
        (bytevector-u8-set! out 3 (fxand (fxsrl msg-len  8) #xff))
        (bytevector-u8-set! out 4 (fxand msg-len #xff))
        (bytevector-copy! payload 0 out 5 plen)
        out)))

  ;; Startup message has no type byte: [length int32][0x00030000][params\0...][final \0]
  (define pg-make-startup-message
    (lambda (params-alist)
      (let* ((proto #vu8(0 3 0 0))
             (kvs   (apply bv-append
                           (map (lambda (kv)
                                  (bv-append (encode-cstring (car kv))
                                             (encode-cstring (cdr kv))))
                                params-alist)))
             (body  (bv-append proto kvs #vu8(0)))
             (total (fx+ 4 (bytevector-length body)))
             (out   (make-bytevector total)))
        (bytevector-u8-set! out 0 (fxand (fxsrl total 24) #xff))
        (bytevector-u8-set! out 1 (fxand (fxsrl total 16) #xff))
        (bytevector-u8-set! out 2 (fxand (fxsrl total  8) #xff))
        (bytevector-u8-set! out 3 (fxand total #xff))
        (bytevector-copy! body 0 out 4 (bytevector-length body))
        out)))

  ;;============================================================
  ;; Section 5: Decoding helpers
  ;;============================================================

  (define bv-ref-int32-be
    (lambda (bv off)
      (let ((v (+ (* (bytevector-u8-ref bv off)           #x1000000)
                  (* (bytevector-u8-ref bv (fx+ off 1))   #x10000)
                  (* (bytevector-u8-ref bv (fx+ off 2))   #x100)
                  (bytevector-u8-ref bv (fx+ off 3)))))
        (if (>= v #x80000000) (- v #x100000000) v))))

  (define bv-ref-int16-be
    (lambda (bv off)
      (let ((v (+ (* (bytevector-u8-ref bv off) #x100)
                  (bytevector-u8-ref bv (fx+ off 1)))))
        (if (>= v #x8000) (- v #x10000) v))))

  ;; Returns (values string next-offset)
  (define bv-read-cstring
    (lambda (bv off)
      (let loop ((i off))
        (if (fxzero? (bytevector-u8-ref bv i))
            (values (utf8->string (subbytevector bv off i))
                    (fx+ i 1))
            (loop (fx+ i 1))))))

  ;; Read one complete PG message. Returns (values type-char payload-bv).
  (define pg-read-message
    (lambda (read-u8 read-exact)
      (let* ((type-byte  (read-u8))
             (type-char  (integer->char type-byte))
             (len-bv     (read-exact 4))
             (msg-len    (bv-ref-int32-be len-bv 0))
             (payload-len (fx- msg-len 4)))
        (values type-char
                (if (fxzero? payload-len)
                    (make-bytevector 0)
                    (read-exact payload-len))))))

  ;;============================================================
  ;; Section 6: Result record
  ;;============================================================

  (define-record-type* <pg-result>
    (make-pg-result columns rows command-tag error-fields)
    pg-result?
    (columns      pg-result-columns)
    (rows         pg-result-rows)
    (command-tag  pg-result-command-tag)
    (error-fields pg-result-error-fields))

  (define pg-result-error?
    (lambda (r)
      (not (eq? #f (pg-result-error-fields r)))))

  (define pg-result-error-message
    (lambda (r)
      (let ((f (pg-result-error-fields r)))
        (and f (let ((p (assv #\M f))) (and p (cdr p)))))))

  (define pg-result-error-detail
    (lambda (r)
      (let ((f (pg-result-error-fields r)))
        (and f (let ((p (assv #\D f))) (and p (cdr p)))))))

  (define pg-result-error-sqlstate
    (lambda (r)
      (let ((f (pg-result-error-fields r)))
        (and f (let ((p (assv #\C f))) (and p (cdr p)))))))

  ;;============================================================
  ;; Section 7: Message parsers
  ;;============================================================

  (define pg-parse-row-description
    (lambda (payload)
      ;; int16 nfields; for each: name\0 + 4+2+4+2+4+2 = 18 bytes fixed
      (let ((nfields (bv-ref-int16-be payload 0)))
        (let loop ((i 0) (off 2) (cols '()))
          (if (fx=? i nfields)
              (reverse cols)
              (let-values (((name next) (bv-read-cstring payload off)))
                (loop (fx+ i 1) (fx+ next 18) (cons name cols))))))))

  (define pg-parse-data-row
    (lambda (payload)
      ;; int16 ncols; for each: int32 len (-1=NULL) + bytes
      (let ((ncols (bv-ref-int16-be payload 0)))
        (let loop ((i 0) (off 2) (vals '()))
          (if (fx=? i ncols)
              (reverse vals)
              (let ((vlen (bv-ref-int32-be payload off)))
                (if (fx=? vlen -1)
                    (loop (fx+ i 1) (fx+ off 4) (cons #f vals))
                    (let* ((start (fx+ off 4))
                           (text  (utf8->string
                                   (subbytevector payload start
                                                  (fx+ start vlen)))))
                      (loop (fx+ i 1) (fx+ start vlen) (cons text vals))))))))))

  (define pg-parse-error-response
    (lambda (payload)
      ;; sequence: field-code-byte (non-zero) + null-terminated string; ends with 0x00
      (let loop ((off 0) (fields '()))
        (let ((code (bytevector-u8-ref payload off)))
          (if (fxzero? code)
              (reverse fields)
              (let-values (((msg next) (bv-read-cstring payload (fx+ off 1))))
                (loop next (cons (cons (integer->char code) msg) fields))))))))

  ;;============================================================
  ;; Section 8: MD5 (pure Scheme, RFC 1321)
  ;;============================================================

  (define md5-T
    '#(#xd76aa478 #xe8c7b756 #x242070db #xc1bdceee
       #xf57c0faf #x4787c62a #xa8304613 #xfd469501
       #x698098d8 #x8b44f7af #xffff5bb1 #x895cd7be
       #x6b901122 #xfd987193 #xa679438e #x49b40821
       #xf61e2562 #xc040b340 #x265e5a51 #xe9b6c7aa
       #xd62f105d #x02441453 #xd8a1e681 #xe7d3fbc8
       #x21e1cde6 #xc33707d6 #xf4d50d87 #x455a14ed
       #xa9e3e905 #xfcefa3f8 #x676f02d9 #x8d2a4c8a
       #xfffa3942 #x8771f681 #x6d9d6122 #xfde5380c
       #xa4beea44 #x4bdecfa9 #xf6bb4b60 #xbebfbc70
       #x289b7ec6 #xeaa127fa #xd4ef3085 #x04881d05
       #xd9d4d039 #xe6db99e5 #x1fa27cf8 #xc4ac5665
       #xf4292244 #x432aff97 #xab9423a7 #xfc93a039
       #x655b59c3 #x8f0ccc92 #xffeff47d #x85845dd1
       #x6fa87e4f #xfe2ce6e0 #xa3014314 #x4e0811a1
       #xf7537e82 #xbd3af235 #x2ad7d2bb #xeb86d391))

  (define md5-S
    '#(7 12 17 22  7 12 17 22  7 12 17 22  7 12 17 22
       5  9 14 20  5  9 14 20  5  9 14 20  5  9 14 20
       4 11 16 23  4 11 16 23  4 11 16 23  4 11 16 23
       6 10 15 21  6 10 15 21  6 10 15 21  6 10 15 21))

  (define md5-mask #xffffffff)

  (define md5-rotate-left
    (lambda (x n)
      (bitwise-and
       (bitwise-ior (bitwise-arithmetic-shift x n)
                    (bitwise-arithmetic-shift x (- n 32)))
       md5-mask)))

  (define md5-pad
    (lambda (bv)
      (let* ((len     (bytevector-length bv))
             (bit-len (* len 8))
             ;; r1 = position after appending the 0x80 byte
             (r1      (modulo (+ len 1) 64))
             ;; zero bytes to fill up to 56 mod 64
             (pad-len (if (<= r1 56) (- 56 r1) (- 120 r1)))
             (total   (+ len 1 pad-len 8))
             (out     (make-bytevector total 0)))
        (bytevector-copy! bv 0 out 0 len)
        (bytevector-u8-set! out len #x80)
        ;; 64-bit little-endian bit count at the end
        (let loop ((i 0))
          (when (< i 8)
            (bytevector-u8-set! out (- total (- 8 i))
                                (bitwise-and
                                 (bitwise-arithmetic-shift bit-len (- (* 8 i)))
                                 #xff))
            (loop (+ i 1))))
        out)))

  (define md5-process-block
    (lambda (block off state)
      (let ((M (make-vector 16)))
        (let load ((i 0))
          (when (fx<? i 16)
            (vector-set! M i
              (+ (bytevector-u8-ref block (fx+ off (fx* i 4)))
                 (* (bytevector-u8-ref block (fx+ off (fx+ (fx* i 4) 1))) #x100)
                 (* (bytevector-u8-ref block (fx+ off (fx+ (fx* i 4) 2))) #x10000)
                 (* (bytevector-u8-ref block (fx+ off (fx+ (fx* i 4) 3))) #x1000000)))
            (load (fx+ i 1))))
        (let ((a (vector-ref state 0))
              (b (vector-ref state 1))
              (c (vector-ref state 2))
              (d (vector-ref state 3)))
          (let rounds ((i 0) (a a) (b b) (c c) (d d))
            (if (fx=? i 64)
                (begin
                  (vector-set! state 0 (bitwise-and (+ (vector-ref state 0) a) md5-mask))
                  (vector-set! state 1 (bitwise-and (+ (vector-ref state 1) b) md5-mask))
                  (vector-set! state 2 (bitwise-and (+ (vector-ref state 2) c) md5-mask))
                  (vector-set! state 3 (bitwise-and (+ (vector-ref state 3) d) md5-mask)))
                (let-values (((F g)
                              (cond
                               ((fx<? i 16)
                                (values (bitwise-ior (bitwise-and b c)
                                                     (bitwise-and (bitwise-not b) d))
                                        i))
                               ((fx<? i 32)
                                (values (bitwise-ior (bitwise-and d b)
                                                     (bitwise-and (bitwise-not d) c))
                                        (modulo (+ (* 5 i) 1) 16)))
                               ((fx<? i 48)
                                (values (bitwise-xor b c d)
                                        (modulo (+ (* 3 i) 5) 16)))
                               (else
                                (values (bitwise-xor c (bitwise-ior b (bitwise-not d)))
                                        (modulo (* 7 i) 16))))))
                  (let* ((F    (bitwise-and F md5-mask))
                         (temp (bitwise-and
                                (+ b (md5-rotate-left
                                      (bitwise-and
                                       (+ a F (vector-ref M g) (vector-ref md5-T i))
                                       md5-mask)
                                      (vector-ref md5-S i)))
                                md5-mask)))
                    (rounds (fx+ i 1) d temp b c)))))))))

  (define md5-digest
    (lambda (bv)
      (let ((padded (md5-pad bv))
            (state  (vector #x67452301 #xefcdab89 #x98badcfe #x10325476)))
        (let loop ((off 0))
          (when (fx<? off (bytevector-length padded))
            (md5-process-block padded off state)
            (loop (fx+ off 64))))
        (let ((out (make-bytevector 16)))
          (let store ((w 0))
            (when (fx<? w 4)
              (let ((word (vector-ref state w)))
                (bytevector-u8-set! out (fx+ (fx* w 4) 0) (bitwise-and word #xff))
                (bytevector-u8-set! out (fx+ (fx* w 4) 1) (bitwise-and (bitwise-arithmetic-shift word -8)  #xff))
                (bytevector-u8-set! out (fx+ (fx* w 4) 2) (bitwise-and (bitwise-arithmetic-shift word -16) #xff))
                (bytevector-u8-set! out (fx+ (fx* w 4) 3) (bitwise-and (bitwise-arithmetic-shift word -24) #xff)))
              (store (fx+ w 1))))
          out))))

  (define bv->hex
    (lambda (bv)
      (let ((out (make-string (* 2 (bytevector-length bv)))))
        (let loop ((i 0))
          (when (fx<? i (bytevector-length bv))
            (let ((b (bytevector-u8-ref bv i)))
              (string-set! out (fx* 2 i)       (string-ref "0123456789abcdef" (fxsrl b 4)))
              (string-set! out (fx+ (fx* 2 i) 1) (string-ref "0123456789abcdef" (fxand b #xf))))
            (loop (fx+ i 1))))
        out)))

  ;; PostgreSQL MD5 auth: "md5" + hex(md5(hex(md5(password+username)) + salt))
  (define pg-md5-password
    (lambda (password username salt)
      (let* ((inner     (md5-digest (string->utf8 (string-append password username))))
             (inner-hex (string->utf8 (bv->hex inner)))
             (outer     (md5-digest (bv-append inner-hex salt))))
        (string-append "md5" (bv->hex outer)))))

  ;;============================================================
  ;; Section 9a: Base64
  ;;============================================================

  (define base64-alphabet
    "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/")

  (define base64-encode
    (lambda (bv)
      (let* ((len  (bytevector-length bv))
             (full (quotient len 3))
             (rem  (remainder len 3))
             (out  (make-string (+ (* full 4) (if (= rem 0) 0 4)))))
        (let loop ((i 0) (j 0))
          (when (< i full)
            (let* ((b0 (bytevector-u8-ref bv (* i 3)))
                   (b1 (bytevector-u8-ref bv (+ (* i 3) 1)))
                   (b2 (bytevector-u8-ref bv (+ (* i 3) 2))))
              (string-set! out j     (string-ref base64-alphabet (bitwise-arithmetic-shift-right b0 2)))
              (string-set! out (+ j 1) (string-ref base64-alphabet
                                          (bitwise-ior (bitwise-arithmetic-shift-left (bitwise-and b0 3) 4)
                                                       (bitwise-arithmetic-shift-right b1 4))))
              (string-set! out (+ j 2) (string-ref base64-alphabet
                                          (bitwise-ior (bitwise-arithmetic-shift-left (bitwise-and b1 #xf) 2)
                                                       (bitwise-arithmetic-shift-right b2 6))))
              (string-set! out (+ j 3) (string-ref base64-alphabet (bitwise-and b2 #x3f)))
              (loop (+ i 1) (+ j 4)))))
        (let ((base (* full 3)))
          (cond
           ((= rem 1)
            (let ((b0 (bytevector-u8-ref bv base)))
              (string-set! out (* full 4)     (string-ref base64-alphabet (bitwise-arithmetic-shift-right b0 2)))
              (string-set! out (+ (* full 4) 1) (string-ref base64-alphabet
                                                   (bitwise-arithmetic-shift-left (bitwise-and b0 3) 4)))
              (string-set! out (+ (* full 4) 2) #\=)
              (string-set! out (+ (* full 4) 3) #\=)))
           ((= rem 2)
            (let ((b0 (bytevector-u8-ref bv base))
                  (b1 (bytevector-u8-ref bv (+ base 1))))
              (string-set! out (* full 4)     (string-ref base64-alphabet (bitwise-arithmetic-shift-right b0 2)))
              (string-set! out (+ (* full 4) 1) (string-ref base64-alphabet
                                                   (bitwise-ior (bitwise-arithmetic-shift-left (bitwise-and b0 3) 4)
                                                                (bitwise-arithmetic-shift-right b1 4))))
              (string-set! out (+ (* full 4) 2) (string-ref base64-alphabet
                                                   (bitwise-arithmetic-shift-left (bitwise-and b1 #xf) 2)))
              (string-set! out (+ (* full 4) 3) #\=)))))
        out)))

  (define base64-char->val
    (lambda (c)
      (cond
       ((and (char>=? c #\A) (char<=? c #\Z)) (- (char->integer c) (char->integer #\A)))
       ((and (char>=? c #\a) (char<=? c #\z)) (+ 26 (- (char->integer c) (char->integer #\a))))
       ((and (char>=? c #\0) (char<=? c #\9)) (+ 52 (- (char->integer c) (char->integer #\0))))
       ((char=? c #\+) 62)
       ((char=? c #\/) 63)
       (else #f))))

  (define base64-decode
    (lambda (s)
      (let* ((slen  (string-length s))
             (pad   (cond ((and (> slen 0) (char=? (string-ref s (- slen 1)) #\=))
                           (if (and (> slen 1) (char=? (string-ref s (- slen 2)) #\=)) 2 1))
                          (else 0)))
             (groups (/ slen 4))
             (out   (make-bytevector (- (* groups 3) pad))))
        (let loop ((g 0))
          (when (< g groups)
            (let* ((c0 (base64-char->val (string-ref s (* g 4))))
                   (c1 (base64-char->val (string-ref s (+ (* g 4) 1))))
                   (c2 (let ((ch (string-ref s (+ (* g 4) 2))))
                         (if (char=? ch #\=) 0 (base64-char->val ch))))
                   (c3 (let ((ch (string-ref s (+ (* g 4) 3))))
                         (if (char=? ch #\=) 0 (base64-char->val ch))))
                   (base (* g 3)))
              (when (< base (bytevector-length out))
                (bytevector-u8-set! out base
                  (bitwise-ior (bitwise-arithmetic-shift-left c0 2)
                               (bitwise-arithmetic-shift-right c1 4))))
              (when (< (+ base 1) (bytevector-length out))
                (bytevector-u8-set! out (+ base 1)
                  (bitwise-and (bitwise-ior (bitwise-arithmetic-shift-left (bitwise-and c1 #xf) 4)
                                            (bitwise-arithmetic-shift-right c2 2))
                               #xff)))
              (when (< (+ base 2) (bytevector-length out))
                (bytevector-u8-set! out (+ base 2)
                  (bitwise-and (bitwise-ior (bitwise-arithmetic-shift-left (bitwise-and c2 3) 6) c3)
                               #xff)))
              (loop (+ g 1)))))
        out)))

  ;;============================================================
  ;; Section 9b: SHA-256 (FIPS 180-4)
  ;;============================================================

  (define sha256-K
    '#(#x428a2f98 #x71374491 #xb5c0fbcf #xe9b5dba5
       #x3956c25b #x59f111f1 #x923f82a4 #xab1c5ed5
       #xd807aa98 #x12835b01 #x243185be #x550c7dc3
       #x72be5d74 #x80deb1fe #x9bdc06a7 #xc19bf174
       #xe49b69c1 #xefbe4786 #x0fc19dc6 #x240ca1cc
       #x2de92c6f #x4a7484aa #x5cb0a9dc #x76f988da
       #x983e5152 #xa831c66d #xb00327c8 #xbf597fc7
       #xc6e00bf3 #xd5a79147 #x06ca6351 #x14292967
       #x27b70a85 #x2e1b2138 #x4d2c6dfc #x53380d13
       #x650a7354 #x766a0abb #x81c2c92e #x92722c85
       #xa2bfe8a1 #xa81a664b #xc24b8b70 #xc76c51a3
       #xd192e819 #xd6990624 #xf40e3585 #x106aa070
       #x19a4c116 #x1e376c08 #x2748774c #x34b0bcb5
       #x391c0cb3 #x4ed8aa4a #x5b9cca4f #x682e6ff3
       #x748f82ee #x78a5636f #x84c87814 #x8cc70208
       #x90befffa #xa4506ceb #xbef9a3f7 #xc67178f2))

  (define sha256-rotr
    (lambda (x n)
      (bitwise-and
       (bitwise-ior (bitwise-arithmetic-shift-right x n)
                    (bitwise-arithmetic-shift-left  x (- 32 n)))
       #xffffffff)))

  (define sha256-pad
    (lambda (bv)
      (let* ((len     (bytevector-length bv))
             (bit-len (* len 8))
             (r1      (modulo (+ len 1) 64))
             (pad-len (if (<= r1 56) (- 56 r1) (- 120 r1)))
             (total   (+ len 1 pad-len 8))
             (out     (make-bytevector total 0)))
        (bytevector-copy! bv 0 out 0 len)
        (bytevector-u8-set! out len #x80)
        ;; 64-bit big-endian bit count
        (let loop ((i 0))
          (when (< i 8)
            (bytevector-u8-set! out (- total (- 8 i))
                                (bitwise-and
                                 (bitwise-arithmetic-shift bit-len (- (* 8 (- 7 i))))
                                 #xff))
            (loop (+ i 1))))
        out)))

  (define sha256-process-block
    (lambda (block off state)
      (let ((W (make-vector 64)))
        ;; Prepare message schedule (big-endian 32-bit words)
        (let load ((i 0))
          (when (< i 16)
            (vector-set! W i
              (+ (bitwise-arithmetic-shift-left (bytevector-u8-ref block (+ off (* i 4)))     24)
                 (bitwise-arithmetic-shift-left (bytevector-u8-ref block (+ off (+ (* i 4) 1))) 16)
                 (bitwise-arithmetic-shift-left (bytevector-u8-ref block (+ off (+ (* i 4) 2)))  8)
                 (bytevector-u8-ref block (+ off (+ (* i 4) 3)))))
            (load (+ i 1))))
        (let expand ((i 16))
          (when (< i 64)
            (let* ((w15 (vector-ref W (- i 15)))
                   (w2  (vector-ref W (- i 2)))
                   (s0  (bitwise-xor (sha256-rotr w15 7)  (sha256-rotr w15 18)
                                     (bitwise-arithmetic-shift-right w15 3)))
                   (s1  (bitwise-xor (sha256-rotr w2 17) (sha256-rotr w2 19)
                                     (bitwise-arithmetic-shift-right w2 10))))
              (vector-set! W i
                (bitwise-and (+ (vector-ref W (- i 16)) s0 (vector-ref W (- i 7)) s1) #xffffffff)))
            (expand (+ i 1))))
        (let ((a (vector-ref state 0)) (b (vector-ref state 1))
              (c (vector-ref state 2)) (d (vector-ref state 3))
              (e (vector-ref state 4)) (f (vector-ref state 5))
              (g (vector-ref state 6)) (h (vector-ref state 7)))
          (let rounds ((i 0) (a a) (b b) (c c) (d d) (e e) (f f) (g g) (h h))
            (if (= i 64)
                (begin
                  (vector-set! state 0 (bitwise-and (+ (vector-ref state 0) a) #xffffffff))
                  (vector-set! state 1 (bitwise-and (+ (vector-ref state 1) b) #xffffffff))
                  (vector-set! state 2 (bitwise-and (+ (vector-ref state 2) c) #xffffffff))
                  (vector-set! state 3 (bitwise-and (+ (vector-ref state 3) d) #xffffffff))
                  (vector-set! state 4 (bitwise-and (+ (vector-ref state 4) e) #xffffffff))
                  (vector-set! state 5 (bitwise-and (+ (vector-ref state 5) f) #xffffffff))
                  (vector-set! state 6 (bitwise-and (+ (vector-ref state 6) g) #xffffffff))
                  (vector-set! state 7 (bitwise-and (+ (vector-ref state 7) h) #xffffffff)))
                (let* ((S1  (bitwise-xor (sha256-rotr e 6) (sha256-rotr e 11) (sha256-rotr e 25)))
                       (ch  (bitwise-xor (bitwise-and e f) (bitwise-and (bitwise-not e) g)))
                       (T1  (bitwise-and (+ h S1 ch (vector-ref sha256-K i) (vector-ref W i)) #xffffffff))
                       (S0  (bitwise-xor (sha256-rotr a 2) (sha256-rotr a 13) (sha256-rotr a 22)))
                       (maj (bitwise-xor (bitwise-and a b) (bitwise-and a c) (bitwise-and b c)))
                       (T2  (bitwise-and (+ S0 maj) #xffffffff)))
                  (rounds (+ i 1) (bitwise-and (+ T1 T2) #xffffffff) a b c (bitwise-and (+ d T1) #xffffffff) e f g))))))))

  (define sha256-digest
    (lambda (bv)
      (let ((padded (sha256-pad bv))
            (state  (vector #x6a09e667 #xbb67ae85 #x3c6ef372 #xa54ff53a
                            #x510e527f #x9b05688c #x1f83d9ab #x5be0cd19)))
        (let loop ((off 0))
          (when (< off (bytevector-length padded))
            (sha256-process-block padded off state)
            (loop (+ off 64))))
        (let ((out (make-bytevector 32)))
          (let store ((w 0))
            (when (< w 8)
              (let ((word (vector-ref state w)))
                (bytevector-u8-set! out (+ (* w 4) 0) (bitwise-and (bitwise-arithmetic-shift word -24) #xff))
                (bytevector-u8-set! out (+ (* w 4) 1) (bitwise-and (bitwise-arithmetic-shift word -16) #xff))
                (bytevector-u8-set! out (+ (* w 4) 2) (bitwise-and (bitwise-arithmetic-shift word  -8) #xff))
                (bytevector-u8-set! out (+ (* w 4) 3) (bitwise-and word #xff)))
              (store (+ w 1))))
          out))))

  ;;============================================================
  ;; Section 9c: HMAC-SHA256 (RFC 2104) and PBKDF2
  ;;============================================================

  (define hmac-sha256
    (lambda (key msg)
      (let* ((k (if (> (bytevector-length key) 64)
                    (sha256-digest key)
                    key))
             (kpad (let ((bv (make-bytevector 64 0)))
                     (bytevector-copy! k 0 bv 0 (bytevector-length k))
                     bv))
             (ipad (make-bytevector 64 #x36))
             (opad (make-bytevector 64 #x5c))
             (ki   (make-bytevector 64))
             (ko   (make-bytevector 64)))
        (let xor-loop ((i 0))
          (when (< i 64)
            (bytevector-u8-set! ki i (bitwise-xor (bytevector-u8-ref kpad i) (bytevector-u8-ref ipad i)))
            (bytevector-u8-set! ko i (bitwise-xor (bytevector-u8-ref kpad i) (bytevector-u8-ref opad i)))
            (xor-loop (+ i 1))))
        (sha256-digest (bv-append ko (sha256-digest (bv-append ki msg)))))))

  (define pbkdf2-hmac-sha256
    (lambda (password salt iterations)
      (let* ((salt1 (bv-append salt #vu8(0 0 0 1)))
             (u     (hmac-sha256 password salt1))
             (out   (bytevector-copy u)))
        (let loop ((i 1) (prev u))
          (when (< i iterations)
            (let ((ui (hmac-sha256 password prev)))
              (let xor ((j 0))
                (when (< j 32)
                  (bytevector-u8-set! out j (bitwise-xor (bytevector-u8-ref out j)
                                                          (bytevector-u8-ref ui  j)))
                  (xor (+ j 1))))
              (loop (+ i 1) ui))))
        out)))

  ;;============================================================
  ;; Section 9d: SCRAM-SHA-256 helpers
  ;;============================================================

  (define scram-escape-username
    (lambda (username)
      (let* ((s (string->list username))
             (escaped
              (apply string-append
                     (map (lambda (c)
                            (cond ((char=? c #\=) "=3D")
                                  ((char=? c #\,) "=2C")
                                  (else (string c))))
                          s))))
        escaped)))

  (define scram-make-nonce
    (lambda ()
      (let ((bv (make-bytevector 24)))
        (let fill ((i 0))
          (when (< i 24)
            (bytevector-u8-set! bv i (random 256))
            (fill (+ i 1))))
        (base64-encode bv))))

  (define scram-parse-server-first
    ;; Returns (values combined-nonce salt iterations)
    (lambda (msg)
      (define (find-field s key)
        (let* ((prefix (string-append key "="))
               (plen   (string-length prefix))
               (slen   (string-length s)))
          (let scan ((i 0))
            (if (>= i slen)
                #f
                (if (and (<= (+ i plen) slen)
                         (string=? (substring s i (+ i plen)) prefix))
                    ;; find end of field (next comma or end of string)
                    (let end ((j (+ i plen)))
                      (if (or (>= j slen) (char=? (string-ref s j) #\,))
                          (substring s (+ i plen) j)
                          (end (+ j 1))))
                    (scan (+ i 1)))))))
      (let ((r (find-field msg "r"))
            (s (find-field msg "s"))
            (i (find-field msg "i")))
        (unless (and r s i)
          (pg-raise "Malformed SCRAM server-first-message" msg))
        (values r (base64-decode s) (string->number i)))))

  (define pg-scram-sha256-auth
    (lambda (conn username password mechanism-list)
      (unless (member "SCRAM-SHA-256" mechanism-list)
        (pg-raise "Server does not offer SCRAM-SHA-256" mechanism-list))
      (let* ((fd          (pg-conn-fd conn))
             (read-u8     (pg-conn-read-u8 conn))
             (read-exact  (pg-conn-read-exact conn))
             (nonce       (scram-make-nonce))
             (user-esc    (scram-escape-username username))
             (client-bare (string-append "n=" user-esc ",r=" nonce))
             (client-first (string-append "n,," client-bare))
             (cf-bv       (string->utf8 client-first))
             (mech-bv     (encode-cstring "SCRAM-SHA-256"))
             (len-bv      (encode-int32-be (bytevector-length cf-bv)))
             (sasl-init   (pg-make-message #\p mech-bv len-bv cf-bv)))
        (unless (loop-write fd sasl-init)
          (pg-raise "Write failed during SCRAM initial response" 'write))
        ;; Read server-first (auth-type 11)
        (let-values (((type payload) (pg-read-message read-u8 read-exact)))
          (unless (char=? type #\R)
            (pg-raise "Expected AuthenticationSASLContinue" type))
          (let ((atype (bv-ref-int32-be payload 0)))
            (unless (= atype 11)
              (pg-raise "Expected SASL continue (11)" atype)))
          (let ((server-first (utf8->string (subbytevector payload 4 (bytevector-length payload)))))
            (let-values (((combined-nonce salt iterations)
                          (scram-parse-server-first server-first)))
              ;; Verify nonce prefix
              (unless (and (>= (string-length combined-nonce) (string-length nonce))
                           (string=? (substring combined-nonce 0 (string-length nonce)) nonce))
                (pg-raise "SCRAM nonce mismatch" combined-nonce))
              (let* ((client-final-no-proof (string-append "c=biws,r=" combined-nonce))
                     (auth-message (string-append client-bare "," server-first "," client-final-no-proof))
                     (pass-bv      (string->utf8 password))
                     (salted-pw    (pbkdf2-hmac-sha256 pass-bv salt iterations))
                     (client-key   (hmac-sha256 salted-pw (string->utf8 "Client Key")))
                     (stored-key   (sha256-digest client-key))
                     (client-sig   (hmac-sha256 stored-key (string->utf8 auth-message)))
                     (client-proof (let ((p (make-bytevector 32)))
                                     (let xor ((i 0))
                                       (when (< i 32)
                                         (bytevector-u8-set! p i
                                           (bitwise-xor (bytevector-u8-ref client-key i)
                                                        (bytevector-u8-ref client-sig i)))
                                         (xor (+ i 1))))
                                     p))
                     (server-key   (hmac-sha256 salted-pw (string->utf8 "Server Key")))
                     (server-sig   (hmac-sha256 server-key (string->utf8 auth-message)))
                     (client-final (string-append client-final-no-proof ",p=" (base64-encode client-proof)))
                     (cf-bv2       (string->utf8 client-final))
                     (sasl-resp    (pg-make-message #\p cf-bv2)))
                (unless (loop-write fd sasl-resp)
                  (pg-raise "Write failed during SCRAM final response" 'write))
                ;; Read server-final (auth-type 12)
                (let-values (((type2 payload2) (pg-read-message read-u8 read-exact)))
                  (unless (char=? type2 #\R)
                    (pg-raise "Expected AuthenticationSASLFinal" type2))
                  (let ((atype2 (bv-ref-int32-be payload2 0)))
                    (unless (= atype2 12)
                      (pg-raise "Expected SASL final (12)" atype2)))
                  ;; Verify server signature: payload after int32 is "v=<base64>"
                  (let* ((sfinal (utf8->string (subbytevector payload2 4 (bytevector-length payload2))))
                         (v-prefix "v=")
                         (v-val (if (and (>= (string-length sfinal) 2)
                                         (string=? (substring sfinal 0 2) v-prefix))
                                    (substring sfinal 2 (string-length sfinal))
                                    (pg-raise "Malformed SCRAM server-final" sfinal)))
                         (got-sig (base64-decode v-val)))
                    (unless (equal? got-sig server-sig)
                      (pg-raise "SCRAM server signature mismatch" 'scram)))))))))))

  ;;============================================================
  ;; Section 9: Authentication state machine
  ;;============================================================

  (define pg-authenticate
    (lambda (conn username password)
      (let ((fd         (pg-conn-fd conn))
            (read-u8    (pg-conn-read-u8 conn))
            (read-exact (pg-conn-read-exact conn)))
        (let auth-loop ()
          (let-values (((type payload) (pg-read-message read-u8 read-exact)))
            (case type

              ((#\R)
               (let ((auth-type (bv-ref-int32-be payload 0)))
                 (cond
                  ;; AuthenticationOk
                  ((= auth-type 0)
                   (auth-loop))

                  ;; Cleartext password
                  ((= auth-type 3)
                   (let ((msg (pg-make-message #\p (encode-cstring password))))
                     (unless (loop-write fd msg)
                       (pg-raise "Write failed during cleartext auth" 'write)))
                   (auth-loop))

                  ;; MD5 password
                  ((= auth-type 5)
                   (let* ((salt   (subbytevector payload 4 8))
                          (hashed (pg-md5-password password username salt))
                          (msg    (pg-make-message #\p (encode-cstring hashed))))
                     (unless (loop-write fd msg)
                       (pg-raise "Write failed during MD5 auth" 'write)))
                   (auth-loop))

                  ;; SASL (SCRAM-SHA-256)
                  ((= auth-type 10)
                   (let* ((mechanisms '())
                          (bvlen (bytevector-length payload)))
                     ;; Parse null-terminated mechanism names starting at offset 4
                     (let parse ((off 4) (mechs '()))
                       (if (>= off bvlen)
                           (pg-scram-sha256-auth conn username password (reverse mechs))
                           (let-values (((name next) (bv-read-cstring payload off)))
                             (if (string=? name "")
                                 (pg-scram-sha256-auth conn username password (reverse mechs))
                                 (parse next (cons name mechs))))))
                     (auth-loop)))

                  (else
                   (pg-raise "Unsupported authentication method"
                              `(auth-type ,auth-type))))))

              ((#\S)
               (let-values (((name  off1) (bv-read-cstring payload 0)))
                 (let-values (((value _)  (bv-read-cstring payload off1)))
                   (pg-conn-params! conn
                                    (cons (cons name value)
                                          (pg-conn-params conn)))))
               (auth-loop))

              ((#\K)
               (pg-conn-pid!    conn (bv-ref-int32-be payload 0))
               (pg-conn-secret! conn (bv-ref-int32-be payload 4))
               (auth-loop))

              ((#\Z)
               (void))

              ((#\E)
               (let ((fields (pg-parse-error-response payload)))
                 (let ((msg (cond ((assv #\M fields) => cdr)
                                  (else "Authentication error"))))
                   (pg-raise msg `(pg-error ,fields)))))

              ((#\N)
               (auth-loop))

              (else
               (pg-raise "Unexpected message during auth"
                          `(type ,type)))))))))

  ;;============================================================
  ;; Section 10: Connection — pg-connect
  ;;============================================================

  (define string-split-dots
    (lambda (s)
      (map string->number
           (let loop ((chars (string->list s)) (cur '()) (out '()))
             (cond
              ((null? chars)
               (reverse (cons (list->string (reverse cur)) out)))
              ((char=? (car chars) #\.)
               (loop (cdr chars) '()
                     (cons (list->string (reverse cur)) out)))
              (else
               (loop (cdr chars) (cons (car chars) cur) out)))))))

  (define pg-connect
    (lambda (host port database username password)
      (let* ((parts (string-split-dots host))
             (a (car parts)) (b (cadr parts))
             (c (caddr parts)) (d (cadddr parts)))
        (let-values (((addr-ptr addrlen) (make-sockaddr-in a b c d port)))
          (let ((fd (loop-connect addr-ptr addrlen)))
            (foreign-free addr-ptr)
            (unless fd
              (pg-raise "TCP connection failed"
                         `(host ,host port ,port)))
            (let-values (((read-u8 read-exact) (make-pg-reader fd)))
              (let ((conn (make-pg-connection fd read-u8 read-exact #f #f '())))
                (let ((startup (pg-make-startup-message
                                `(("user"             . ,username)
                                  ("database"         . ,database)
                                  ("application_name" . "letloop-pg")
                                  ("client_encoding"  . "UTF8")))))
                  (unless (loop-write fd startup)
                    (pg-raise "Write failed sending startup" 'write)))
                (pg-authenticate conn username password)
                conn)))))))

  ;;============================================================
  ;; Section 11: Close — pg-close
  ;;============================================================

  (define pg-close
    (lambda (conn)
      (let ((fd (pg-conn-fd conn)))
        (loop-write fd (pg-make-message #\X))
        (loop-close fd))))

  ;;============================================================
  ;; Section 12: Simple query — pg-exec and pg-query
  ;;============================================================

  (define pg-simple-query
    (lambda (conn sql)
      (let ((fd         (pg-conn-fd conn))
            (read-u8    (pg-conn-read-u8 conn))
            (read-exact (pg-conn-read-exact conn)))
        (let ((msg (pg-make-message #\Q (encode-cstring sql))))
          (unless (loop-write fd msg)
            (pg-raise "Write failed sending query" `(sql ,sql))))
        (let result-loop ((columns #f) (rows '()) (tag #f) (err #f))
          (let-values (((type payload) (pg-read-message read-u8 read-exact)))
            (case type

              ((#\T)
               (result-loop (pg-parse-row-description payload) rows tag err))

              ((#\D)
               (result-loop columns
                            (cons (pg-parse-data-row payload) rows)
                            tag err))

              ((#\C)
               (let-values (((s _) (bv-read-cstring payload 0)))
                 (result-loop columns rows s err)))

              ((#\E)
               (result-loop columns rows tag
                            (pg-parse-error-response payload)))

              ((#\Z)
               (make-pg-result (or columns '())
                               (reverse rows)
                               tag
                               err))

              ((#\I)
               (result-loop columns rows "" err))

              ((#\N)
               (result-loop columns rows tag err))

              ((#\G #\H)
               (pg-raise "COPY protocol not supported" `(type ,type)))

              (else
               (pg-raise "Unexpected message in simple query"
                          `(type ,type)))))))))

  (define pg-exec    (lambda (conn sql) (pg-simple-query conn sql)))
  (define pg-query   (lambda (conn sql) (pg-simple-query conn sql)))
  (define pg-begin   (lambda (c) (pg-exec c "BEGIN")))
  (define pg-commit  (lambda (c) (pg-exec c "COMMIT")))
  (define pg-rollback (lambda (c) (pg-exec c "ROLLBACK")))

  ;;============================================================
  ;; Section 13: Extended query — pg-prepare and pg-execute
  ;;============================================================

  (define pg-prepare
    (lambda (conn name sql)
      (let ((fd         (pg-conn-fd conn))
            (read-u8    (pg-conn-read-u8 conn))
            (read-exact (pg-conn-read-exact conn)))
        ;; Parse: name\0 + sql\0 + int16 0 (no param type OIDs)
        (let ((parse-msg (pg-make-message
                          #\P
                          (encode-cstring name)
                          (encode-cstring sql)
                          #vu8(0 0))))
          (unless (loop-write fd parse-msg)
            (pg-raise "Write failed on Parse" `(name ,name sql ,sql))))
        (let ((sync-msg (pg-make-message #\S)))
          (unless (loop-write fd sync-msg)
            (pg-raise "Write failed on Sync" '(sync))))
        (let prep-loop ()
          (let-values (((type payload) (pg-read-message read-u8 read-exact)))
            (case type
              ((#\1) (prep-loop))
              ((#\N) (prep-loop))
              ((#\Z) (void))
              ((#\E)
               (pg-raise "Parse error"
                          `(fields ,(pg-parse-error-response payload))))
              (else  (prep-loop))))))))

  (define pg-execute
    (lambda (conn name params)
      ;; params: list of string-or-#f (text format, #f = NULL)
      (let ((fd         (pg-conn-fd conn))
            (read-u8    (pg-conn-read-u8 conn))
            (read-exact (pg-conn-read-exact conn)))
        ;; Bind: portal=""\0 + stmt=name\0 + 0 format-codes +
        ;;        N params + 0 result-format-codes
        (let* ((nfc-bv    #vu8(0 0))
               (nparam-bv (encode-int16-be (length params)))
               (param-bvs (apply bv-append
                                 (map (lambda (p)
                                        (if (eq? p #f)
                                            #vu8(#xff #xff #xff #xff)
                                            (let ((pbv (string->utf8 p)))
                                              (bv-append (encode-int32-be
                                                          (bytevector-length pbv))
                                                         pbv))))
                                      params)))
               (nrfc-bv   #vu8(0 0))
               (bind-msg  (pg-make-message
                           #\B
                           (encode-cstring "")
                           (encode-cstring name)
                           nfc-bv
                           nparam-bv param-bvs
                           nrfc-bv)))
          (unless (loop-write fd bind-msg)
            (pg-raise "Write failed on Bind" '(bind))))
        ;; Execute: portal=""\0 + max-rows=0
        (let ((exec-msg (pg-make-message #\E (encode-cstring "") #vu8(0 0 0 0))))
          (unless (loop-write fd exec-msg)
            (pg-raise "Write failed on Execute" '(execute))))
        ;; Sync
        (let ((sync-msg (pg-make-message #\S)))
          (unless (loop-write fd sync-msg)
            (pg-raise "Write failed on Sync" '(sync))))
        ;; Collect responses
        (let result-loop ((columns #f) (rows '()) (tag #f) (err #f))
          (let-values (((type payload) (pg-read-message read-u8 read-exact)))
            (case type
              ((#\2) (result-loop columns rows tag err))
              ((#\T) (result-loop (pg-parse-row-description payload) rows tag err))
              ((#\D) (result-loop columns (cons (pg-parse-data-row payload) rows) tag err))
              ((#\C)
               (let-values (((s _) (bv-read-cstring payload 0)))
                 (result-loop columns rows s err)))
              ((#\E)
               (result-loop columns rows tag (pg-parse-error-response payload)))
              ((#\I) (result-loop columns rows "" err))
              ((#\N) (result-loop columns rows tag err))
              ((#\Z)
               (make-pg-result (or columns '())
                               (reverse rows)
                               tag
                               err))
              (else
               (pg-raise "Unexpected message in extended query"
                          `(type ,type)))))))))

  ) ;; end library
