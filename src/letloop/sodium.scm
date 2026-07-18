#!chezscheme
(library (letloop sodium)
  (export sodium-init
          crypto-hash-sha256
          randombytes-buf
          sodium-memcmp
          crypto-aead-xchacha20poly1305-ietf-encrypt
          crypto-aead-xchacha20poly1305-ietf-decrypt
          crypto-aead-xchacha20poly1305-ietf-keygen
          ~check-sodium-0
          ~check-sodium-1
          ~check-sodium-2)
  (import (chezscheme)
          (letloop cffi))

  (define-shared-object libsodium "libsodium.so" "libsodium.so.26" "libsodium.so.23")

  ;; int sodium_init(void);
  ;; Returns 0 on success, 1 if already initialized, -1 on failure.
  (define sodium-init
    (let ((func (lazy-foreign-procedure libsodium "sodium_init" () int)))
      (lambda ()
        (let ((rc (func)))
          (when (fx=? rc -1)
            (error 'sodium "sodium_init failed"))
          rc))))

  ;; int crypto_hash_sha256(unsigned char *out,
  ;;                        const unsigned char *in,
  ;;                        unsigned long long inlen);
  (define crypto-hash-sha256
    (let ((func (lazy-foreign-procedure libsodium "crypto_hash_sha256"
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
    (let ((func (lazy-foreign-procedure libsodium "randombytes_buf"
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
    (let ((func (lazy-foreign-procedure libsodium "sodium_memcmp"
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

  ;; XChaCha20-Poly1305 AEAD
  ;;
  ;; Key:   32 bytes (KEYBYTES)
  ;; Nonce: 24 bytes (NPUBBYTES)
  ;; Tag:   16 bytes (ABYTES)

  ;; int crypto_aead_xchacha20poly1305_ietf_encrypt(
  ;;     unsigned char *c, unsigned long long *clen_p,
  ;;     const unsigned char *m, unsigned long long mlen,
  ;;     const unsigned char *ad, unsigned long long adlen,
  ;;     const unsigned char *nsec,
  ;;     const unsigned char *npub, const unsigned char *k);
  (define crypto-aead-xchacha20poly1305-ietf-encrypt
    (let ((func (lazy-foreign-procedure libsodium "crypto_aead_xchacha20poly1305_ietf_encrypt"
                                   (void* void* void* unsigned-64
                                    void* unsigned-64
                                    void* void* void*)
                                   int)))
      (lambda (plaintext key nonce)
        (let* ((mlen (bytevector-length plaintext))
               (ciphertext (make-bytevector (+ mlen 16)))
               (clen-ptr (foreign-alloc 8)))
          (foreign-set! 'unsigned-64 clen-ptr 0 0)
          (with-lock (list plaintext key nonce ciphertext)
            (let ((rc (func (bytevector-pointer ciphertext)
                            clen-ptr
                            (bytevector-pointer plaintext)
                            mlen
                            0 0   ;; no additional data
                            0     ;; nsec unused
                            (bytevector-pointer nonce)
                            (bytevector-pointer key))))
              (foreign-free clen-ptr)
              (when (not (fxzero? rc))
                (error 'crypto-aead-xchacha20poly1305-ietf-encrypt
                       "encryption failed" rc))
              ciphertext))))))

  ;; int crypto_aead_xchacha20poly1305_ietf_decrypt(
  ;;     unsigned char *m, unsigned long long *mlen_p,
  ;;     unsigned char *nsec,
  ;;     const unsigned char *c, unsigned long long clen,
  ;;     const unsigned char *ad, unsigned long long adlen,
  ;;     const unsigned char *npub, const unsigned char *k);
  (define crypto-aead-xchacha20poly1305-ietf-decrypt
    (let ((func (lazy-foreign-procedure libsodium "crypto_aead_xchacha20poly1305_ietf_decrypt"
                                   (void* void* void*
                                    void* unsigned-64
                                    void* unsigned-64
                                    void* void*)
                                   int)))
      (lambda (ciphertext key nonce)
        (let ((clen (bytevector-length ciphertext)))
          (if (< clen 16)
              #f  ;; too short to hold the 16 bytes authentication tag
              (let ((plaintext (make-bytevector (- clen 16)))
                    (mlen-ptr (foreign-alloc 8)))
                (foreign-set! 'unsigned-64 mlen-ptr 0 0)
                (with-lock (list ciphertext key nonce plaintext)
                  (let ((rc (func (bytevector-pointer plaintext)
                                  mlen-ptr
                                  0     ;; nsec unused
                                  (bytevector-pointer ciphertext)
                                  clen
                                  0 0   ;; no additional data
                                  (bytevector-pointer nonce)
                                  (bytevector-pointer key))))
                    (foreign-free mlen-ptr)
                    (if (fx=? rc -1)
                        #f  ;; authentication failure
                        plaintext)))))))))

  ;; void crypto_aead_xchacha20poly1305_ietf_keygen(unsigned char k[32]);
  (define crypto-aead-xchacha20poly1305-ietf-keygen
    (let ((func (lazy-foreign-procedure libsodium "crypto_aead_xchacha20poly1305_ietf_keygen"
                                   (void*) void)))
      (lambda ()
        (let ((key (make-bytevector 32)))
          (with-lock (list key)
            (func (bytevector-pointer key)))
          key))))

  (define ~check-sodium-0
    (lambda ()
      (check-skip-unless libsodium
      (sodium-init)
      (let* ((data (string->bytevector "hello" (make-transcoder (utf-8-codec))))
             (hash1 (crypto-hash-sha256 data))
             (hash2 (crypto-hash-sha256 data))
             (random1 (randombytes-buf 32))
             (random2 (randombytes-buf 32)))
        (assert (= 32 (bytevector-length hash1)))
        (assert (sodium-memcmp hash1 hash2))
        (assert (= 32 (bytevector-length random1)))
        (assert (not (sodium-memcmp random1 random2)))))))

  (define ~check-sodium-1
    (lambda ()
      (check-skip-unless libsodium
      ;; XChaCha20-Poly1305 encrypt/decrypt round-trip
      (sodium-init)
      (let* ((key (crypto-aead-xchacha20poly1305-ietf-keygen))
             (nonce (randombytes-buf 24))
             (plaintext (string->bytevector "hello, world!"
                          (make-transcoder (utf-8-codec))))
             (ciphertext (crypto-aead-xchacha20poly1305-ietf-encrypt
                           plaintext key nonce))
             (decrypted (crypto-aead-xchacha20poly1305-ietf-decrypt
                          ciphertext key nonce)))
        (assert (= (bytevector-length ciphertext)
                   (+ (bytevector-length plaintext) 16)))
        (assert decrypted)
        (assert (bytevector=? decrypted plaintext))))))

  (define ~check-sodium-2
    (lambda ()
      (check-skip-unless libsodium
      ;; Decrypt with wrong key fails
      (sodium-init)
      (let* ((key (crypto-aead-xchacha20poly1305-ietf-keygen))
             (wrong-key (crypto-aead-xchacha20poly1305-ietf-keygen))
             (nonce (randombytes-buf 24))
             (plaintext (string->bytevector "secret"
                          (make-transcoder (utf-8-codec))))
             (ciphertext (crypto-aead-xchacha20poly1305-ietf-encrypt
                           plaintext key nonce))
             (result (crypto-aead-xchacha20poly1305-ietf-decrypt
                       ciphertext wrong-key nonce)))
        (assert (not result))))))

  )
