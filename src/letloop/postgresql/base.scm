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
   pg-make-startup-message)

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
