#!chezscheme
(library (argon2sum)
  (export main)
  (import (chezscheme)
          (letloop cffi)
          (letloop match))

  (define libargon2.so.1 (load-shared-object "libargon2.so.1"))

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
    (let ((func (foreign-procedure "argon2id_hash_raw" (unsigned-32
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
  (define argon2id-m-cost 19456)
  (define argon2id-parallelism 1)

  (define argon2id
    (lambda (salt password . args)
      (let ((cost-iterations (if (and (pair? args) (car args)) (car args) argon2id-t-cost))
            (cost-memory (if (and (pair? args) (pair? (cdr args)) (cadr args)) (cadr args) argon2id-m-cost))
            (parallelism (if (and (pair? args) (pair? (cdr args)) (pair? (cddr args)) (caddr args)) (caddr args) argon2id-parallelism))
            (hash-length 32))
        (let ((hash (make-bytevector hash-length)))
          (if (argon2id-hash-raw cost-iterations cost-memory parallelism password salt hash)
              hash
              (error 'letloop "Failed to do hashing" argon2id))))))

  (define argon2id-encoded
    (let ((func (foreign-procedure "argon2id_hash_encoded"
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

  (define argon2id-verify
    (let ((func (foreign-procedure "argon2id_verify" (void* void* size_t) int)))
      (lambda (encoded password)
        (let ((code (with-lock (list encoded password)
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
    (let ((func (foreign-procedure "argon2_encodedlen"
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
            out
            (error 'letloop "Error while hashing of password")))))


  (define ~check-argon2-0
    (lambda ()
      (let ((salt (bytevector-random 256))
            (password (bytevector-random 256)))
        (assert (argon2id-verify (argon2id-encode salt password) password)))))

  (define bytevector-random
    (lambda (n)
      (u8-list->bytevector (map (lambda _ (random 256)) (iota n)))))

  (define main
    (lambda args
      (match args
        [("encode" ,password)
         (let* ((salt (bytevector-random 16))
                (encoded (argon2id-encode salt (string->utf8 password)))
                (len (bytevector-length encoded))
                (trimmed (if (and (fx> len 0) (fx=? 0 (bytevector-u8-ref encoded (fx- len 1))))
                             (u8-list->bytevector (list-head (bytevector->u8-list encoded) (fx- len 1)))
                             encoded)))
           (display (utf8->string trimmed))
           (newline))]
        [("verify" ,hash ,password)
         (if (argon2id-verify (u8-list->bytevector (append (bytevector->u8-list (string->utf8 hash)) '(0))) (string->utf8 password))
             (begin (display "OK") (newline))
             (begin (display "FAIL") (newline) (exit 1)))]
        [,_ (display "Usage:\n  argon2 encode PASSWORD\n  argon2 verify HASH PASSWORD\n")
            (exit 1)])))

  )
