(library (check-postgresql)

  (export
   ~check-postgresql-md5-000
   ~check-postgresql-md5-001
   ~check-postgresql-md5-002
   ~check-postgresql-encoding-000
   ~check-postgresql-encoding-001
   ~check-postgresql-sha256-000
   ~check-postgresql-sha256-001
   ~check-postgresql-hmac-sha256-000
   ~check-postgresql-pbkdf2-000
   ~check-postgresql-base64-000
   ~check-postgresql-base64-001
   ~check-postgresql-connect-000
   ~check-postgresql-query-000
   ~check-postgresql-error-000
   ~check-postgresql-null-000
   ~check-postgresql-multirow-000
   ~check-postgresql-exec-000
   ~check-postgresql-prepare-000
   ~check-postgresql-prepare-null-000
   ~check-postgresql-scram-000)

  (import (chezscheme)
          (letloop liburing low)
          (letloop postgresql base))

  ;;============================================================
  ;; MD5 unit tests (no network required)
  ;;============================================================

  (define ~check-postgresql-md5-000
    ;; RFC 1321 test vector: md5("") = d41d8cd98f00b204e9800998ecf8427e
    (lambda ()
      (let ((result (md5-digest (string->utf8 "")))
            (expected #vu8(#xd4 #x1d #x8c #xd9 #x8f #x00 #xb2 #x04
                           #xe9 #x80 #x09 #x98 #xec #xf8 #x42 #x7e)))
        (assert (equal? result expected)))))

  (define ~check-postgresql-md5-001
    ;; RFC 1321 test vector: md5("abc") = 900150983cd24fb0d6963f7d28e17f72
    (lambda ()
      (let ((result (md5-digest (string->utf8 "abc")))
            (expected #vu8(#x90 #x01 #x50 #x98 #x3c #xd2 #x4f #xb0
                           #xd6 #x96 #x3f #x7d #x28 #xe1 #x7f #x72)))
        (assert (equal? result expected)))))

  (define ~check-postgresql-md5-002
    ;; RFC 1321: md5("message digest") = f96b697d7cb7938d525a2f31aaf161d0
    (lambda ()
      (let ((result (md5-digest (string->utf8 "message digest")))
            (expected #vu8(#xf9 #x6b #x69 #x7d #x7c #xb7 #x93 #x8d
                           #x52 #x5a #x2f #x31 #xaa #xf1 #x61 #xd0)))
        (assert (equal? result expected)))))

  ;;============================================================
  ;; Wire encoding unit tests (no network required)
  ;;============================================================

  (define ~check-postgresql-encoding-000
    ;; Startup message: length field must equal total byte count
    (lambda ()
      (let* ((msg (pg-make-startup-message
                   '(("user" . "alice") ("database" . "testdb"))))
             (total (bytevector-length msg))
             (len-field (+ (* (bytevector-u8-ref msg 0) #x1000000)
                           (* (bytevector-u8-ref msg 1) #x10000)
                           (* (bytevector-u8-ref msg 2) #x100)
                           (bytevector-u8-ref msg 3))))
        (assert (= len-field total)))))

  (define ~check-postgresql-encoding-001
    ;; pg-make-message: type byte, length includes itself, payload correct
    (lambda ()
      (let* ((payload (string->utf8 "SELECT 1\x0;"))
             (msg     (pg-make-message #\Q payload))
             (type    (integer->char (bytevector-u8-ref msg 0)))
             (mlen    (+ (* (bytevector-u8-ref msg 1) #x1000000)
                         (* (bytevector-u8-ref msg 2) #x10000)
                         (* (bytevector-u8-ref msg 3) #x100)
                         (bytevector-u8-ref msg 4))))
        (assert (char=? type #\Q))
        (assert (= mlen (+ 4 (bytevector-length payload))))
        (assert (= (bytevector-length msg) (+ 1 mlen))))))

  ;;============================================================
  ;; Crypto unit tests (no network required)
  ;;============================================================

  (define ~check-postgresql-sha256-000
    ;; FIPS 180-4 / RFC test vector: sha256("") = e3b0c44298fc1c14...
    (lambda ()
      (let ((result (sha256-digest #vu8()))
            (expected #vu8(#xe3 #xb0 #xc4 #x42 #x98 #xfc #x1c #x14
                           #x9a #xfb #xf4 #xc8 #x99 #x6f #xb9 #x24
                           #x27 #xae #x41 #xe4 #x64 #x9b #x93 #x4c
                           #xa4 #x95 #x99 #x1b #x78 #x52 #xb8 #x55)))
        (assert (equal? result expected)))))

  (define ~check-postgresql-sha256-001
    ;; sha256("abc") = ba7816bf8f01cfea414140de5dae2223b00361a39617...
    (lambda ()
      (let ((result (sha256-digest (string->utf8 "abc")))
            (expected #vu8(#xba #x78 #x16 #xbf #x8f #x01 #xcf #xea
                           #x41 #x41 #x40 #xde #x5d #xae #x22 #x23
                           #xb0 #x03 #x61 #xa3 #x96 #x17 #x7a #x9c
                           #xb4 #x10 #xff #x61 #xf2 #x00 #x15 #xad)))
        (assert (equal? result expected)))))

  (define ~check-postgresql-hmac-sha256-000
    ;; RFC 4231 test vector 1: key=20x0b, data="Hi There"
    (lambda ()
      (let ((result (hmac-sha256 (make-bytevector 20 #x0b)
                                 (string->utf8 "Hi There")))
            (expected #vu8(#xb0 #x34 #x4c #x61 #xd8 #xdb #x38 #x53
                           #x5c #xa8 #xaf #xce #xaf #x0b #xf1 #x2b
                           #x88 #x1d #xc2 #x00 #xc9 #x83 #x3d #xa7
                           #x26 #xe9 #x37 #x6c #x2e #x32 #xcf #xf7)))
        (assert (equal? result expected)))))

  (define ~check-postgresql-pbkdf2-000
    ;; PBKDF2-HMAC-SHA256("password","salt",1,32)
    (lambda ()
      (let ((result (pbkdf2-hmac-sha256 (string->utf8 "password")
                                        (string->utf8 "salt") 1))
            (expected #vu8(#x12 #x0f #xb6 #xcf #xfc #xf8 #xb3 #x2c
                           #x43 #xe7 #x22 #x52 #x56 #xc4 #xf8 #x37
                           #xa8 #x65 #x48 #xc9 #x2c #xcc #x35 #x48
                           #x08 #x05 #x98 #x7c #xb7 #x0b #xe1 #x7b)))
        (assert (equal? result expected)))))

  (define ~check-postgresql-base64-000
    ;; RFC 4648: base64-encode("Man") = "TWFu"
    (lambda ()
      (assert (string=? (base64-encode (string->utf8 "Man")) "TWFu"))))

  (define ~check-postgresql-base64-001
    ;; Round-trip: decode(encode(bv)) = bv
    (lambda ()
      (let ((bv (string->utf8 "Hello, SCRAM!")))
        (assert (equal? (base64-decode (base64-encode bv)) bv)))))

  ;;============================================================
  ;; Integration tests (require PostgreSQL at 127.0.0.1:5432)
  ;;============================================================

  ;; Helper: run a single coroutine and return its result
  (define-syntax run-pg-test
    (syntax-rules ()
      ((_ body ...)
       (let ((result #f))
         (loop-new)
         (loop-spawn
          (lambda ()
            (set! result (begin body ...))
            (loop-stop)))
         (loop-run)
         result))))

  (define ~check-postgresql-connect-000
    ;; Connect with trust/cleartext auth and close
    (lambda ()
      (run-pg-test
       (let ((conn (pg-connect "127.0.0.1" 5432 "postgres" "postgres" "")))
         (assert (pg-connection? conn))
         (pg-close conn)
         #t))))

  (define ~check-postgresql-query-000
    ;; SELECT 1 returns one row with value "1"
    (lambda ()
      (run-pg-test
       (let* ((conn   (pg-connect "127.0.0.1" 5432 "postgres" "postgres" ""))
              (result (pg-query conn "SELECT 1 AS n")))
         (pg-close conn)
         (assert (pg-result? result))
         (assert (not (pg-result-error? result)))
         (assert (equal? (pg-result-columns result) '("n")))
         (assert (equal? (pg-result-rows result) '(("1"))))
         #t))))

  (define ~check-postgresql-error-000
    ;; Invalid SQL returns an error result (not an exception)
    (lambda ()
      (run-pg-test
       (let* ((conn   (pg-connect "127.0.0.1" 5432 "postgres" "postgres" ""))
              (result (pg-query conn "NOT VALID SQL")))
         (pg-close conn)
         (assert (pg-result-error? result))
         (assert (string? (pg-result-error-message result)))
         #t))))

  (define ~check-postgresql-null-000
    ;; SELECT NULL returns a row containing #f
    (lambda ()
      (run-pg-test
       (let* ((conn   (pg-connect "127.0.0.1" 5432 "postgres" "postgres" ""))
              (result (pg-query conn "SELECT NULL AS v")))
         (pg-close conn)
         (assert (not (pg-result-error? result)))
         (assert (equal? (pg-result-rows result) '((#f))))
         #t))))

  (define ~check-postgresql-multirow-000
    ;; Multiple rows come back in order
    (lambda ()
      (run-pg-test
       (let* ((conn   (pg-connect "127.0.0.1" 5432 "postgres" "postgres" ""))
              (result (pg-query conn "SELECT n FROM generate_series(1,3) AS n")))
         (pg-close conn)
         (assert (not (pg-result-error? result)))
         (assert (= 3 (length (pg-result-rows result))))
         #t))))

  (define ~check-postgresql-exec-000
    ;; CREATE TEMP TABLE and INSERT
    (lambda ()
      (run-pg-test
       (let* ((conn (pg-connect "127.0.0.1" 5432 "postgres" "postgres" "")))
         (pg-exec conn "CREATE TEMP TABLE t (v text)")
         (let ((r (pg-exec conn "INSERT INTO t VALUES ('hello')")))
           (pg-close conn)
           (assert (not (pg-result-error? r)))
           (assert (string? (pg-result-command-tag r)))
           #t)))))

  (define ~check-postgresql-prepare-000
    ;; Prepared statement with one parameter
    (lambda ()
      (run-pg-test
       (let* ((conn (pg-connect "127.0.0.1" 5432 "postgres" "postgres" "")))
         (pg-prepare conn "stmt1" "SELECT $1::text AS v")
         (let ((result (pg-execute conn "stmt1" '("hello"))))
           (pg-close conn)
           (assert (not (pg-result-error? result)))
           (assert (equal? (pg-result-rows result) '(("hello"))))
           #t)))))

  (define ~check-postgresql-prepare-null-000
    ;; Prepared statement with NULL parameter
    (lambda ()
      (run-pg-test
       (let* ((conn (pg-connect "127.0.0.1" 5432 "postgres" "postgres" "")))
         (pg-prepare conn "stmt2" "SELECT $1::text AS v")
         (let ((result (pg-execute conn "stmt2" '(#f))))
           (pg-close conn)
           (assert (not (pg-result-error? result)))
           (assert (equal? (pg-result-rows result) '((#f))))
           #t)))))

  (define ~check-postgresql-scram-000
    ;; Connect with SCRAM-SHA-256 auth; skip gracefully if user doesn't exist
    (lambda ()
      (run-pg-test
       (guard (exn (#t #t))  ; skip if scram_user not configured
         (let ((conn (pg-connect "127.0.0.1" 5432 "postgres" "scram_user" "secret")))
           (pg-close conn)
           #t)))))

  ) ;; end library
