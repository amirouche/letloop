#!chezscheme
(library (letloop sodium)
  (export sodium-init
          crypto-hash-sha256
          randombytes-buf
          sodium-memcmp
          ~check-sodium-0)
  (import (chezscheme)
          (letloop cffi))

  (define libsodium (load-shared-object "libsodium.so"))

  ;; int sodium_init(void);
  ;; Returns 0 on success, 1 if already initialized, -1 on failure.
  (define sodium-init
    (let ((func (foreign-procedure "sodium_init" () int)))
      (lambda ()
        (let ((rc (func)))
          (when (fx=? rc -1)
            (error 'sodium "sodium_init failed"))
          rc))))

  ;; int crypto_hash_sha256(unsigned char *out,
  ;;                        const unsigned char *in,
  ;;                        unsigned long long inlen);
  (define crypto-hash-sha256
    (let ((func (foreign-procedure "crypto_hash_sha256"
                                   (void* void* unsigned-64)
                                   int)))
      (lambda (input)
        (let ((out (make-bytevector 32)))
          (with-lock (list input out)
                     (func (bytevector-pointer out)
                           (bytevector-pointer input)
                           (bytevector-length input)))
          out))))

  ;; void randombytes_buf(void * const buf, const size_t size);
  (define randombytes-buf
    (let ((func (foreign-procedure "randombytes_buf"
                                   (void* size_t)
                                   void)))
      (lambda (n)
        (let ((buf (make-bytevector n)))
          (with-lock (list buf)
                     (func (bytevector-pointer buf) n))
          buf))))

  ;; int sodium_memcmp(const void * const b1_,
  ;;                   const void * const b2_,
  ;;                   size_t len);
  ;; Returns 0 if equal.
  (define sodium-memcmp
    (let ((func (foreign-procedure "sodium_memcmp"
                                   (void* void* size_t)
                                   int)))
      (lambda (a b)
        (unless (fx=? (bytevector-length a) (bytevector-length b))
          (error 'sodium "bytevectors must have equal length"
                 (bytevector-length a) (bytevector-length b)))
        (with-lock (list a b)
                   (fxzero? (func (bytevector-pointer a)
                                  (bytevector-pointer b)
                                  (bytevector-length a)))))))

  (define ~check-sodium-0
    (lambda ()
      (sodium-init)
      (let* ((data (string->bytevector "hello" (make-transcoder (utf-8-codec))))
             (hash1 (crypto-hash-sha256 data))
             (hash2 (crypto-hash-sha256 data))
             (random1 (randombytes-buf 32))
             (random2 (randombytes-buf 32)))
        (assert (= 32 (bytevector-length hash1)))
        (assert (sodium-memcmp hash1 hash2))
        (assert (= 32 (bytevector-length random1)))
        (assert (not (sodium-memcmp random1 random2))))))

  )
