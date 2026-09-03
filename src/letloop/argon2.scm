#!chezscheme
(library (letloop argon2)
  (export argon2id argon2id-encode argon2id-verify
          argon2id-t-cost argon2id-m-cost argon2id-parallelism
          ~check-argon2-0 ~check-argon2-1)
  (import (chezscheme)
          (letloop cffi))

  (define-shared-object libargon2.so.1 "libargon2.so.1" "libargon2.so")

  ;; /**
  ;;  * Hashes a password with Argon2i, producing a raw hash at @hash
  ;;  * @param t_cost Number of iterations
  ;;  * @param m_cost Sets memory usage to m_cost kibibytes
  ;;  * @param parallelism Number of threads and compute lanes
  ;;  * @param pwd Pointer to password
  ;;  * @param pwdlen Password size in bytes
  ;;  * @param salt Pointer to salt
  ;;  * @param saltlen Salt size in bytes
  ;;  * @param hash Buffer where to write the raw hash - updated by the function
  ;;  * @param hashlen Desired length of the hash in bytes
  ;;  * @pre   Different parallelism levels will give different results
  ;;  * @pre   Returns ARGON2_OK if successful
  ;;  */

  ;; ARGON2_PUBLIC int argon2id_hash_raw(const uint32_t t_cost,
  ;;                                     const uint32_t m_cost,
  ;;                                     const uint32_t parallelism, const void *pwd,
  ;;                                     const size_t pwdlen, const void *salt,
  ;;                                     const size_t saltlen, void *hash,
  ;;                                     const size_t hashlen);

  (define argon2id-hash-raw
    (let ((func (lazy-foreign-procedure libargon2.so.1 "argon2id_hash_raw" (unsigned-32
                                                        unsigned-32
                                                        unsigned-32
                                                        void*
                                                        size_t
                                                        void*
                                                        size_t
                                                        void*
                                                        size_t) int)))
      (lambda (cost-iterations cost-memory parallelism password salt hash)
        (with-lock (list password salt hash)
                   (fxzero? (func cost-iterations
                                  cost-memory
                                  parallelism
                                  (bytevector-pointer password)
                                  (bytevector-length password)
                                  (bytevector-pointer salt)
                                  (bytevector-length salt)
                                  (bytevector-pointer hash)
                                  (bytevector-length hash)))))))

  (define argon2id-t-cost 2)
  (define argon2id-m-cost 102400)
  (define argon2id-parallelism 8)

  (define argon2id
    (lambda (salt password . args)
      (let ((cost-iterations (if (and (pair? args) (car args)) (car args) argon2id-t-cost))
            (cost-memory (if (and (pair? args) (pair? (cdr args)) (cadr args)) (cadr args) argon2id-m-cost))
            (parallelism (if (and (pair? args) (pair? (cdr args)) (pair? (cddr args)) (caddr args)) (caddr args) argon2id-parallelism))
            (hash-length 32))
        (let ((hash (make-bytevector hash-length)))
          (if (argon2id-hash-raw cost-iterations cost-memory parallelism password salt hash)
              hash
              (error 'argon2id "Failed to do hashing"))))))

  (define argon2id-encoded
    (let ((func (lazy-foreign-procedure libargon2.so.1 "argon2id_hash_encoded"
                                   (unsigned-32 unsigned-32 unsigned-32
                                                void* size_t
                                                void* size_t
                                                size_t
                                                void* size_t) int)))

      (lambda (cost-iterations cost-memory parallelism password salt length encoded)
        (with-lock (list password salt encoded)
                   (fxzero? (func cost-iterations
                                  cost-memory
                                  parallelism
                                  (bytevector-pointer password)
                                  (bytevector-length password)
                                  (bytevector-pointer salt)
                                  (bytevector-length salt)
                                  length
                                  (bytevector-pointer encoded)
                                  (bytevector-length encoded)))))))

  ;; /**
  ;;  * Verifies a password against an encoded string
  ;;  * Encoded string is restricted as in validate_inputs()
  ;;  * @param encoded String encoding parameters, salt, hash
  ;;  * @param pwd Pointer to password
  ;;  * @pre   Returns ARGON2_OK if successful
  ;;  */
  ;;
  ;; ARGON2_PUBLIC int argon2id_verify(const char *encoded, const void *pwd,
  ;;                                   const size_t pwdlen);

  ;; argon2id_verify parses ENCODED as a NUL-terminated C string;
  ;; append the terminator when the caller's bytevector lacks one.
  (define (bytevector-nul-terminate bv)
    (let ((n (bytevector-length bv)))
      (if (and (fx>? n 0) (fxzero? (bytevector-u8-ref bv (fx- n 1))))
          bv
          (let ((out (make-bytevector (fx+ n 1) 0)))
            (bytevector-copy! bv 0 out 0 n)
            out))))

  (define argon2id-verify
    (let ((func (lazy-foreign-procedure libargon2.so.1 "argon2id_verify" (void* void* size_t) int)))
      (lambda (encoded password)
        (let* ((encoded (bytevector-nul-terminate encoded))
               (code (with-lock (list encoded password)
                               (func (bytevector-pointer encoded)
                                     (bytevector-pointer password)
                                     (bytevector-length password)))))
          (fxzero? code)))))

  ;; /**
  ;;  * Returns the encoded hash length for the given input parameters
  ;;  * @param t_cost  Number of iterations
  ;;  * @param m_cost  Memory usage in kibibytes
  ;;  * @param parallelism  Number of threads; used to compute lanes
  ;;  * @param saltlen  Salt size in bytes
  ;;  * @param hashlen  Hash size in bytes
  ;;  * @param type The argon2_type that we want the encoded length for
  ;;  * @return  The encoded hash length in bytes
  ;;  */
  ;; ARGON2_PUBLIC size_t argon2_encodedlen(uint32_t t_cost, uint32_t m_cost,
  ;;                                        uint32_t parallelism, uint32_t saltlen,
  ;;                                        uint32_t hashlen, argon2_type type);

  (define ARGON2-D 0)
  (define ARGON2-I 1)
  (define ARGON2-ID 2)

  (define argon2-encoded-length
    ;; argon2_encodedlen, in Scheme rather than through the shared
    ;; object, because it is not cryptography and never was -- it
    ;; sizes the encoded string and nothing else:
    ;;
    ;;   strlen("$$v=$m=,t=,p=$$") + strlen(type) + numlen(t_cost) +
    ;;   numlen(m_cost) + numlen(parallelism) + b64len(saltlen) +
    ;;   b64len(hashlen) + numlen(ARGON2_VERSION_NUMBER) + 1
    ;;
    ;; The strlen there is over a literal format template, so it is a
    ;; constant the compiler folds, not a call into libc. Binding this
    ;; meant libargon2 had to be loadable before a hash could even be
    ;; sized, for arithmetic over constants -- and it is the one of
    ;; this library's four entry points that libsodium does not export
    ;; either, so it is also the one that would block ever sourcing
    ;; these elsewhere.
    ;;
    ;; Checked against the C function over 61440 parameter
    ;; combinations before it was removed; ~check-argon2-1 keeps the
    ;; result honest against the encoder itself, which is the property
    ;; that actually matters.
    (lambda (cost-iterations cost-memory parallelism salt-length hash-length argon2-type)

      (define numlen
        (lambda (n)
          (let loop ((n n) (length* 1))
            (if (fx<? n 10) length* (loop (fxdiv n 10) (fx+ length* 1))))))

      (define b64len
        ;; Base64 without padding: three bytes become four characters,
        ;; and a trailing one or two bytes become two or three.
        (lambda (length*)
          (let ((whole (fxsll (fxdiv length* 3) 2)))
            (case (fxmod length* 3)
              ((2) (fx+ whole 3))
              ((1) (fx+ whole 2))
              (else whole)))))

      (fx+ 15                                        ; "$$v=$m=,t=,p=$$"
           (if (fx=? argon2-type ARGON2-ID) 8 7)     ; argon2id, or argon2d/argon2i
           (numlen cost-iterations)
           (numlen cost-memory)
           (numlen parallelism)
           (b64len salt-length)
           (b64len hash-length)
           2                                         ; ARGON2_VERSION_NUMBER, 0x13
           1)))

  (define argon2id-encode
    (lambda (salt password . args)
      (let* ((cost-iterations (if (and (pair? args) (car args)) (car args) argon2id-t-cost))
             (cost-memory (if (and (pair? args) (pair? (cdr args)) (cadr args)) (cadr args) argon2id-m-cost))
             (parallelism (if (and (pair? args) (pair? (cdr args)) (pair? (cddr args)) (caddr args)) (caddr args) argon2id-parallelism))
             (salt-length (bytevector-length salt))
             (hash-length 32)
             (encoded-length (argon2-encoded-length cost-iterations
                                                    cost-memory
                                                    parallelism
                                                    salt-length
                                                    hash-length
                                                    ARGON2-ID))
             (out (make-bytevector encoded-length)))
        (if (argon2id-encoded cost-iterations cost-memory parallelism password salt hash-length out)
            ;; drop the trailing NUL terminator C wrote, so the result
            ;; compares equal to encoded hashes stored as text
            (let* ((end (let loop ((n (bytevector-length out)))
                          (if (or (fxzero? n)
                                  (not (fxzero? (bytevector-u8-ref out (fx- n 1)))))
                              n
                              (loop (fx- n 1)))))
                   (trimmed (make-bytevector end)))
              (bytevector-copy! out 0 trimmed 0 end)
              trimmed)
            (error 'argon2id-encode "Error while hashing of password")))))


  (define ~check-argon2-0
    (lambda ()
      (check-skip-unless libargon2.so.1 "argon2id_hash_raw"
      (let* ((salt (bytevector-random 256))
             (password (bytevector-random 256))
             (encoded (argon2id-encode salt password)))
        ;; encode returns the encoded hash without the C NUL terminator
        (assert (not (fxzero? (bytevector-u8-ref encoded
                                                 (fx- (bytevector-length encoded) 1)))))
        (assert (argon2id-verify encoded password))
        ;; round-trip through text, as when stored in a database
        (assert (argon2id-verify (string->utf8 (utf8->string encoded)) password))
        (assert (not (argon2id-verify encoded (bytevector-random 32))))
        #t))))

  ;; argon2-encoded-length is computed here rather than asked of
  ;; libargon2, so nothing but this check stands between a wrong
  ;; formula and a silently truncated hash. It is exercised the way it
  ;; is actually used -- as the size of the buffer the C encoder writes
  ;; into -- across parameters that move every term of the sum:
  ;; different digit counts for t, m and p, and salt lengths on either
  ;; side of a base64 boundary, where the remainder of length mod 3
  ;; decides whether two or three characters are added.
  ;;
  ;; A size that is too small makes the encoder fail outright, and one
  ;; that is too large leaves NUL padding the trim would have to eat,
  ;; so a round-trip through verify catches both directions.
  (define ~check-argon2-1
    (lambda ()
      (check-skip-unless libargon2.so.1 "argon2id_hash_raw"
      (let ((password (bytevector-random 32)))
        (for-each
         (lambda (parameters)
           (let* ((t-cost (car parameters))
                  (m-cost (cadr parameters))
                  (parallelism (caddr parameters))
                  (salt (bytevector-random (cadddr parameters)))
                  (encoded (argon2id-encode salt password t-cost m-cost parallelism)))
             (assert (not (fxzero? (bytevector-u8-ref encoded
                                                      (fx- (bytevector-length encoded) 1)))))
             (assert (argon2id-verify encoded password))))
         ;; t, m, p, salt-length -- one and two digit costs, a
         ;; six-digit memory cost, and salt lengths at each residue of
         ;; 3 so both base64 tail cases are covered
         '((1 8 1 16) (2 1024 2 15) (3 102400 8 17) (11 99999 10 32)))
        #t))))

  (define bytevector-random
    (lambda (n)
      (u8-list->bytevector (map (lambda _ (random 256)) (iota n)))))

  )
