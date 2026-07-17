#!chezscheme
(library (letloop argon2)
  (export argon2id argon2id-encode argon2id-verify
          argon2id-t-cost argon2id-m-cost argon2id-parallelism
          ~check-argon2-0)
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
    (let ((func (lazy-foreign-procedure libargon2.so.1 "argon2_encodedlen"
                                   (unsigned-32 unsigned-32 unsigned-32
                                                unsigned-32 unsigned-32
                                                int)
                                   size_t)))

      (lambda (cost-iterations cost-memory parallelism salt-length hash-length argon2-type)
        (func cost-iterations cost-memory parallelism
              salt-length
              hash-length
              argon2-type))))

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
      (check-skip-unless libargon2.so.1
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

  (define bytevector-random
    (lambda (n)
      (u8-list->bytevector (map (lambda _ (random 256)) (iota n)))))

  )
