#!chezscheme
;; OPAQUE Asymmetric PAKE Protocol (RFC 9807)
;; Low-level FFI bindings for libopaque
(library (letloop opaque)

  (export
   ;; Buffer size constants (RFC 9807 / libsodium)
   OPAQUE_SHARED_SECRETBYTES
   OPAQUE_ENVELOPE_NONCEBYTES
   OPAQUE_NONCE_BYTES
   OPAQUE_REGISTRATION_RECORD_LEN
   OPAQUE_USER_RECORD_LEN
   OPAQUE_USER_SESSION_PUBLIC_LEN
   OPAQUE_USER_SESSION_SECRET_LEN
   OPAQUE_SERVER_SESSION_LEN
   OPAQUE_REGISTER_USER_SEC_LEN
   OPAQUE_REGISTER_PUBLIC_LEN
   OPAQUE_REGISTER_SECRET_LEN

   ;; Ids struct helpers
   make-opaque-ids
   opaque-ids-pointer
   opaque-ids-free

   ;; Buffer allocation helpers
   make-user-record
   make-registration-record
   make-user-session-secret
   make-user-session-public
   make-server-session
   make-register-user-secret
   make-register-public
   make-register-secret
   make-shared-secret
   make-auth-tag
   make-export-key

   ;; One-step registration
   opaque-register

   ;; Four-step registration (RFC 9807 Section 5)
   opaque-create-registration-request
   opaque-create-registration-response
   opaque-finalize-request
   opaque-store-user-record

   ;; AKE / Online authentication (RFC 9807 Section 6)
   opaque-create-credential-request
   opaque-create-credential-response
   opaque-recover-credentials
   opaque-user-auth

   ;; Tests
   ;; ~check-000-one-step-register-and-login
   ;; ~check-001-four-step-register-and-login
   ;; ~check-002-wrong-password-fails
   ;; ~check-003-default-ids
   ;; ~check-004-export-key-consistent
   )

  (import (chezscheme) (letloop cffi))

  (define-shared-object libopaque "libopaque.so" "libopaque.so.0")

  ;; ============================================================
  ;; Constants
  ;; ============================================================
  ;;
  ;; Derived from libopaque/src/opaque.h using libsodium sizes:
  ;;   crypto_scalarmult_BYTES            = 32
  ;;   crypto_scalarmult_SCALARBYTES      = 32
  ;;   crypto_core_ristretto255_BYTES     = 32
  ;;   crypto_core_ristretto255_SCALARBYTES = 32
  ;;   crypto_hash_sha512_BYTES           = 64
  ;;   crypto_auth_hmacsha512_BYTES       = 64

  (define OPAQUE_SHARED_SECRETBYTES 64)
  (define OPAQUE_ENVELOPE_NONCEBYTES 32)
  (define OPAQUE_NONCE_BYTES 32)

  ;; client_public_key(32) + masking_key(64) + envelope_nonce(32) + envelope_mac(64)
  (define OPAQUE_REGISTRATION_RECORD_LEN 192)

  ;; kU(32) + skS(32) + registration_record(192)
  (define OPAQUE_USER_RECORD_LEN 256)

  ;; blinded(32) + X_u(32) + nonceU(32)
  (define OPAQUE_USER_SESSION_PUBLIC_LEN 96)

  ;; r(32) + x_u(32) + nonceU(32) + blinded(32) + ke1(96) + pwdU_len(2)
  (define OPAQUE_USER_SESSION_SECRET_LEN 226)

  ;; Z(32) + masking_nonce(32) + server_public_key(32) + nonceS(32)
  ;; + X_s(32) + auth(64) + envelope_nonce(32) + envelope_mac(64)
  (define OPAQUE_SERVER_SESSION_LEN 320)

  ;; r(32) + pwdU_len(2)
  (define OPAQUE_REGISTER_USER_SEC_LEN 34)

  ;; Z(32) + pkS(32)
  (define OPAQUE_REGISTER_PUBLIC_LEN 64)

  ;; skS(32) + kU(32)
  (define OPAQUE_REGISTER_SECRET_LEN 64)

  ;; ============================================================
  ;; Opaque_Ids struct helpers
  ;; ============================================================
  ;;
  ;; typedef struct {
  ;;   uint16_t idU_len;
  ;;   uint8_t *idU;
  ;;   uint16_t idS_len;
  ;;   uint8_t *idS;
  ;; } Opaque_Ids;
  ;;
  ;; On 64-bit: 32 bytes with padding for pointer alignment.

  (define %ids-size 32)

  ;; Allocate and populate an Opaque_Ids struct from bytevectors.
  ;; Pass #f for either id to use the default (long-term public key).
  ;; Returns an opaque handle (foreign pointer + pinned bytevectors).
  (define (make-opaque-ids idU-bv idS-bv)
    (let ((ptr (foreign-alloc %ids-size)))
      ;; Zero out padding
      (let loop ((i 0))
        (when (< i %ids-size)
          (foreign-set! 'unsigned-8 ptr i 0)
          (loop (+ i 1))))
      (if idU-bv
          (begin
            (lock-object idU-bv)
            (foreign-set! 'unsigned-16 ptr 0 (bytevector-length idU-bv))
            (foreign-set! 'void* ptr 8 (bytevector-pointer idU-bv)))
          (begin
            (foreign-set! 'unsigned-16 ptr 0 0)
            (foreign-set! 'void* ptr 8 0)))
      (if idS-bv
          (begin
            (lock-object idS-bv)
            (foreign-set! 'unsigned-16 ptr 16 (bytevector-length idS-bv))
            (foreign-set! 'void* ptr 24 (bytevector-pointer idS-bv)))
          (begin
            (foreign-set! 'unsigned-16 ptr 16 0)
            (foreign-set! 'void* ptr 24 0)))
      (vector ptr idU-bv idS-bv)))

  ;; Extract the raw pointer from an ids handle for passing to C.
  (define (opaque-ids-pointer ids)
    (vector-ref ids 0))

  ;; Free an ids handle. Must be called when done.
  (define (opaque-ids-free ids)
    (let ((idU-bv (vector-ref ids 1))
          (idS-bv (vector-ref ids 2)))
      (when idU-bv (unlock-object idU-bv))
      (when idS-bv (unlock-object idS-bv))
      (foreign-free (vector-ref ids 0))))

  ;; ============================================================
  ;; Buffer allocation helpers
  ;; ============================================================

  (define (make-user-record) (make-bytevector OPAQUE_USER_RECORD_LEN 0))
  (define (make-registration-record) (make-bytevector OPAQUE_REGISTRATION_RECORD_LEN 0))
  (define (make-user-session-public) (make-bytevector OPAQUE_USER_SESSION_PUBLIC_LEN 0))
  (define (make-server-session) (make-bytevector OPAQUE_SERVER_SESSION_LEN 0))
  (define (make-register-public) (make-bytevector OPAQUE_REGISTER_PUBLIC_LEN 0))
  (define (make-register-secret) (make-bytevector OPAQUE_REGISTER_SECRET_LEN 0))
  (define (make-shared-secret) (make-bytevector OPAQUE_SHARED_SECRETBYTES 0))
  (define (make-auth-tag) (make-bytevector 64 0))   ;; crypto_auth_hmacsha512_BYTES
  (define (make-export-key) (make-bytevector 64 0))  ;; crypto_hash_sha512_BYTES

  ;; Variable-length secret buffers (include space for password copy)
  (define (make-user-session-secret pwd-len)
    (make-bytevector (+ OPAQUE_USER_SESSION_SECRET_LEN pwd-len) 0))

  (define (make-register-user-secret pwd-len)
    (make-bytevector (+ OPAQUE_REGISTER_USER_SEC_LEN pwd-len) 0))

  ;; ============================================================
  ;; One-step registration (not in RFC, convenience function)
  ;; ============================================================

  ;; opaque_Register(pwdU, pwdU_len, skS, ids, rec, export_key) -> int
  ;;
  ;; Server-side: creates a user record from the password directly.
  ;; Reveals password to server. Use four-step variant for privacy.
  ;;
  ;; pwdU       - bytevector: user password
  ;; skS        - bytevector (32 bytes) or #f: server private key
  ;; ids        - opaque-ids handle (from make-opaque-ids)
  ;; rec        - bytevector: output, OPAQUE_USER_RECORD_LEN bytes
  ;; export-key - bytevector: output, 64 bytes (or #f to skip)
  (define %opaque-register
    (lazy-foreign-procedure libopaque "opaque_Register"
                       (void* unsigned-16 void* void* void* void*)
                       int))

  (define (opaque-register pwdU skS ids rec export-key)
    (with-lock (append (list pwdU rec)
                       (if skS (list skS) (list))
                       (if export-key (list export-key) (list)))
      (%opaque-register
       (bytevector-pointer pwdU)
       (bytevector-length pwdU)
       (if skS (bytevector-pointer skS) 0)
       (opaque-ids-pointer ids)
       (bytevector-pointer rec)
       (if export-key (bytevector-pointer export-key) 0))))

  ;; ============================================================
  ;; Four-step registration (RFC 9807 Section 5)
  ;; ============================================================

  ;; Step 1: Client -> Server: RegistrationRequest
  ;;
  ;; opaque_CreateRegistrationRequest(pwdU, pwdU_len, sec, request) -> int
  ;;
  ;; pwdU    - bytevector: user password
  ;; sec     - bytevector: output, OPAQUE_REGISTER_USER_SEC_LEN + pwdU_len
  ;; request - bytevector: output, 32 bytes (ristretto255 element)
  (define %opaque-create-registration-request
    (lazy-foreign-procedure libopaque "opaque_CreateRegistrationRequest"
                       (void* unsigned-16 void* void*)
                       int))

  (define (opaque-create-registration-request pwdU sec request)
    (with-lock (list pwdU sec request)
      (%opaque-create-registration-request
       (bytevector-pointer pwdU)
       (bytevector-length pwdU)
       (bytevector-pointer sec)
       (bytevector-pointer request))))

  ;; Step 2: Server -> Client: RegistrationResponse
  ;;
  ;; opaque_CreateRegistrationResponse(request, skS, sec, pub) -> int
  ;;
  ;; request - bytevector: blinded password from step 1 (32 bytes)
  ;; skS     - bytevector (32 bytes) or #f: server private key
  ;; sec     - bytevector: output, OPAQUE_REGISTER_SECRET_LEN
  ;; pub     - bytevector: output, OPAQUE_REGISTER_PUBLIC_LEN
  (define %opaque-create-registration-response
    (lazy-foreign-procedure libopaque "opaque_CreateRegistrationResponse"
                       (void* void* void* void*)
                       int))

  (define (opaque-create-registration-response request skS sec pub)
    (with-lock (append (list request sec pub)
                       (if skS (list skS) (list)))
      (%opaque-create-registration-response
       (bytevector-pointer request)
       (if skS (bytevector-pointer skS) 0)
       (bytevector-pointer sec)
       (bytevector-pointer pub))))

  ;; Step 3: Client -> Server: RegistrationRecord
  ;;
  ;; opaque_FinalizeRequest(sec, pub, ids, reg_rec, export_key) -> int
  ;;
  ;; sec        - bytevector: client secret from step 1
  ;; pub        - bytevector: server response from step 2
  ;; ids        - opaque-ids handle
  ;; reg-rec    - bytevector: output, OPAQUE_REGISTRATION_RECORD_LEN
  ;; export-key - bytevector: output, 64 bytes (or #f to skip)
  (define %opaque-finalize-request
    (lazy-foreign-procedure libopaque "opaque_FinalizeRequest"
                       (void* void* void* void* void*)
                       int))

  (define (opaque-finalize-request sec pub ids reg-rec export-key)
    (with-lock (append (list sec pub reg-rec)
                       (if export-key (list export-key) (list)))
      (%opaque-finalize-request
       (bytevector-pointer sec)
       (bytevector-pointer pub)
       (opaque-ids-pointer ids)
       (bytevector-pointer reg-rec)
       (if export-key (bytevector-pointer export-key) 0))))

  ;; Step 4: Server stores final record
  ;;
  ;; opaque_StoreUserRecord(sec, recU, rec) -> void
  ;;
  ;; sec  - bytevector: server secret from step 2
  ;; recU - bytevector: registration record from step 3
  ;; rec  - bytevector: output, OPAQUE_USER_RECORD_LEN
  (define %opaque-store-user-record
    (lazy-foreign-procedure libopaque "opaque_StoreUserRecord"
                       (void* void* void*)
                       void))

  (define (opaque-store-user-record sec recU rec)
    (with-lock (list sec recU rec)
      (%opaque-store-user-record
       (bytevector-pointer sec)
       (bytevector-pointer recU)
       (bytevector-pointer rec))))

  ;; ============================================================
  ;; AKE / Online authentication (RFC 9807 Section 6)
  ;; ============================================================

  ;; Step 1: Client -> Server: KE1
  ;;
  ;; opaque_CreateCredentialRequest(pwdU, pwdU_len, sec, ke1) -> int
  ;;
  ;; pwdU - bytevector: user password
  ;; sec  - bytevector: output, OPAQUE_USER_SESSION_SECRET_LEN + pwdU_len
  ;; ke1  - bytevector: output, OPAQUE_USER_SESSION_PUBLIC_LEN
  (define %opaque-create-credential-request
    (lazy-foreign-procedure libopaque "opaque_CreateCredentialRequest"
                       (void* unsigned-16 void* void*)
                       int))

  (define (opaque-create-credential-request pwdU sec ke1)
    (with-lock (list pwdU sec ke1)
      (%opaque-create-credential-request
       (bytevector-pointer pwdU)
       (bytevector-length pwdU)
       (bytevector-pointer sec)
       (bytevector-pointer ke1))))

  ;; Step 2: Server -> Client: KE2
  ;;
  ;; opaque_CreateCredentialResponse(ke1, rec, ids, ctx, ctx_len,
  ;;                                 ke2, sk, authU) -> int
  ;;
  ;; ke1   - bytevector: client message from step 1
  ;; rec   - bytevector: stored user record
  ;; ids   - opaque-ids handle
  ;; ctx   - bytevector or #f: application context (e.g. "MyAppv1.0")
  ;; ke2   - bytevector: output, OPAQUE_SERVER_SESSION_LEN
  ;; sk    - bytevector: output, OPAQUE_SHARED_SECRETBYTES (shared secret)
  ;; authU - bytevector: output, 64 bytes (or #f if no explicit auth)
  (define %opaque-create-credential-response
    (lazy-foreign-procedure libopaque "opaque_CreateCredentialResponse"
                       (void* void* void* void* unsigned-16
                        void* void* void*)
                       int))

  (define (opaque-create-credential-response ke1 rec ids ctx ke2 sk authU)
    (with-lock (append (list ke1 rec ke2 sk)
                       (if ctx (list ctx) (list))
                       (if authU (list authU) (list)))
      (%opaque-create-credential-response
       (bytevector-pointer ke1)
       (bytevector-pointer rec)
       (opaque-ids-pointer ids)
       (if ctx (bytevector-pointer ctx) 0)
       (if ctx (bytevector-length ctx) 0)
       (bytevector-pointer ke2)
       (bytevector-pointer sk)
       (if authU (bytevector-pointer authU) 0))))

  ;; Step 3: Client recovers credentials, produces KE3
  ;;
  ;; opaque_RecoverCredentials(ke2, sec, ctx, ctx_len, ids,
  ;;                           sk, authU, export_key) -> int
  ;;
  ;; ke2        - bytevector: server response from step 2
  ;; sec        - bytevector: client secret from step 1
  ;; ctx        - bytevector or #f: application context
  ;; ids        - opaque-ids handle
  ;; sk         - bytevector: output, OPAQUE_SHARED_SECRETBYTES
  ;; authU      - bytevector: output, 64 bytes (or #f)
  ;; export-key - bytevector: output, 64 bytes (or #f)
  (define %opaque-recover-credentials
    (lazy-foreign-procedure libopaque "opaque_RecoverCredentials"
                       (void* void* void* unsigned-16 void*
                        void* void* void*)
                       int))

  (define (opaque-recover-credentials ke2 sec ctx ids sk authU export-key)
    (with-lock (append (list ke2 sec sk)
                       (if ctx (list ctx) (list))
                       (if authU (list authU) (list))
                       (if export-key (list export-key) (list)))
      (%opaque-recover-credentials
       (bytevector-pointer ke2)
       (bytevector-pointer sec)
       (if ctx (bytevector-pointer ctx) 0)
       (if ctx (bytevector-length ctx) 0)
       (opaque-ids-pointer ids)
       (bytevector-pointer sk)
       (if authU (bytevector-pointer authU) 0)
       (if export-key (bytevector-pointer export-key) 0))))

  ;; Step 4 (optional): Server verifies client auth
  ;;
  ;; opaque_UserAuth(authU0, authU) -> int
  ;;
  ;; authU0 - bytevector: server's copy from CreateCredentialResponse
  ;; authU  - bytevector: client's copy from RecoverCredentials
  ;; Returns 0 if authentication succeeds.
  (define %opaque-user-auth
    (lazy-foreign-procedure libopaque "opaque_UserAuth"
                       (void* void*)
                       int))

  (define (opaque-user-auth authU0 authU)
    (with-lock (list authU0 authU)
      (%opaque-user-auth
       (bytevector-pointer authU0)
       (bytevector-pointer authU))))

  ;; ============================================================
  ;; Tests
  ;; ============================================================

  (define (string->bv s)
    (string->bytevector s (make-transcoder (utf-8-codec))))

  ;; One-step registration + full AKE login
  (define ~check-000-one-step-register-and-login
    (lambda ()
      (let* ((pwdU (string->bv "asdf"))
             (ctx (string->bv "test"))
             (ids (make-opaque-ids (string->bv "user") (string->bv "server")))
             (rec (make-user-record))
             (export-key (make-export-key)))
        (assert (= 0 (opaque-register pwdU #f ids rec export-key)))
        (let* ((sec (make-user-session-secret (bytevector-length pwdU)))
               (ke1 (make-user-session-public)))
          (assert (= 0 (opaque-create-credential-request pwdU sec ke1)))
          (let* ((ke2 (make-server-session))
                 (sk-server (make-shared-secret))
                 (authU0 (make-auth-tag)))
            (assert (= 0 (opaque-create-credential-response
                          ke1 rec ids ctx ke2 sk-server authU0)))
            (let* ((sk-client (make-shared-secret))
                   (authU1 (make-auth-tag))
                   (ek2 (make-export-key)))
              (assert (= 0 (opaque-recover-credentials
                            ke2 sec ctx ids sk-client authU1 ek2)))
              (assert (bytevector=? sk-server sk-client))
              (assert (= 0 (opaque-user-auth authU0 authU1)))
              (opaque-ids-free ids)
              #t))))))

  ;; Four-step (private) registration + full AKE login
  (define ~check-001-four-step-register-and-login
    (lambda ()
      (let* ((pwdU (string->bv "asdf"))
             (ctx (string->bv "test"))
             (ids (make-opaque-ids (string->bv "user") (string->bv "server"))))
        (let* ((usr-sec (make-register-user-secret (bytevector-length pwdU)))
               (request (make-bytevector 32 0)))
          (assert (= 0 (opaque-create-registration-request pwdU usr-sec request)))
          (let* ((srv-sec (make-register-secret))
                 (pub (make-register-public)))
            (assert (= 0 (opaque-create-registration-response request #f srv-sec pub)))
            (let* ((reg-rec (make-registration-record))
                   (export-key (make-export-key)))
              (assert (= 0 (opaque-finalize-request usr-sec pub ids reg-rec export-key)))
              (let ((rec (make-user-record)))
                (opaque-store-user-record srv-sec reg-rec rec)
                (let* ((sec (make-user-session-secret (bytevector-length pwdU)))
                       (ke1 (make-user-session-public)))
                  (assert (= 0 (opaque-create-credential-request pwdU sec ke1)))
                  (let* ((ke2 (make-server-session))
                         (sk-server (make-shared-secret))
                         (authU0 (make-auth-tag)))
                    (assert (= 0 (opaque-create-credential-response
                                  ke1 rec ids ctx ke2 sk-server authU0)))
                    (let* ((sk-client (make-shared-secret))
                           (authU1 (make-auth-tag))
                           (ek2 (make-export-key)))
                      (assert (= 0 (opaque-recover-credentials
                                    ke2 sec ctx ids sk-client authU1 ek2)))
                      (assert (bytevector=? sk-server sk-client))
                      (assert (= 0 (opaque-user-auth authU0 authU1)))
                      (opaque-ids-free ids)
                      #t))))))))))

  ;; Wrong password must fail authentication
  (define ~check-002-wrong-password-fails
    (lambda ()
      (let* ((pwdU (string->bv "correct-password"))
             (wrong (string->bv "wrong-password"))
             (ctx (string->bv "test"))
             (ids (make-opaque-ids (string->bv "user") (string->bv "server")))
             (rec (make-user-record))
             (export-key (make-export-key)))
        (assert (= 0 (opaque-register pwdU #f ids rec export-key)))
        (let* ((sec (make-user-session-secret (bytevector-length wrong)))
               (ke1 (make-user-session-public)))
          (assert (= 0 (opaque-create-credential-request wrong sec ke1)))
          (let* ((ke2 (make-server-session))
                 (sk-server (make-shared-secret))
                 (authU0 (make-auth-tag)))
            (assert (= 0 (opaque-create-credential-response
                          ke1 rec ids ctx ke2 sk-server authU0)))
            (let* ((sk-client (make-shared-secret))
                   (authU1 (make-auth-tag))
                   (ek (make-export-key)))
              (let ((rc (opaque-recover-credentials
                         ke2 sec ctx ids sk-client authU1 ek)))
                (opaque-ids-free ids)
                (assert (not (= 0 rc)))
                #t)))))))

  ;; Default ids (pass #f for both)
  (define ~check-003-default-ids
    (lambda ()
      (let* ((pwdU (string->bv "asdf"))
             (ctx (string->bv "ctx"))
             (ids (make-opaque-ids #f #f))
             (rec (make-user-record))
             (export-key (make-export-key)))
        (assert (= 0 (opaque-register pwdU #f ids rec export-key)))
        (let* ((sec (make-user-session-secret (bytevector-length pwdU)))
               (ke1 (make-user-session-public)))
          (assert (= 0 (opaque-create-credential-request pwdU sec ke1)))
          (let* ((ke2 (make-server-session))
                 (sk-server (make-shared-secret))
                 (authU0 (make-auth-tag)))
            (assert (= 0 (opaque-create-credential-response
                          ke1 rec ids ctx ke2 sk-server authU0)))
            (let* ((sk-client (make-shared-secret))
                   (authU1 (make-auth-tag))
                   (ek (make-export-key)))
              (assert (= 0 (opaque-recover-credentials
                            ke2 sec ctx ids sk-client authU1 ek)))
              (assert (bytevector=? sk-server sk-client))
              (assert (= 0 (opaque-user-auth authU0 authU1)))
              (opaque-ids-free ids)
              #t))))))

  ;; Export key matches between registration and login
  (define ~check-004-export-key-consistent
    (lambda ()
      (let* ((pwdU (string->bv "export-key-test"))
             (ctx (string->bv "test"))
             (ids (make-opaque-ids (string->bv "alice") (string->bv "server"))))
        (let* ((usr-sec (make-register-user-secret (bytevector-length pwdU)))
               (request (make-bytevector 32 0)))
          (assert (= 0 (opaque-create-registration-request pwdU usr-sec request)))
          (let* ((srv-sec (make-register-secret))
                 (pub (make-register-public)))
            (assert (= 0 (opaque-create-registration-response request #f srv-sec pub)))
            (let* ((reg-rec (make-registration-record))
                   (ek-reg (make-export-key)))
              (assert (= 0 (opaque-finalize-request usr-sec pub ids reg-rec ek-reg)))
              (let ((rec (make-user-record)))
                (opaque-store-user-record srv-sec reg-rec rec)
                (let* ((sec (make-user-session-secret (bytevector-length pwdU)))
                       (ke1 (make-user-session-public)))
                  (assert (= 0 (opaque-create-credential-request pwdU sec ke1)))
                  (let* ((ke2 (make-server-session))
                         (sk (make-shared-secret))
                         (authU0 (make-auth-tag)))
                    (assert (= 0 (opaque-create-credential-response
                                  ke1 rec ids ctx ke2 sk authU0)))
                    (let* ((sk2 (make-shared-secret))
                           (authU1 (make-auth-tag))
                           (ek-login (make-export-key)))
                      (assert (= 0 (opaque-recover-credentials
                                    ke2 sec ctx ids sk2 authU1 ek-login)))
                      (assert (bytevector=? ek-reg ek-login))
                      (opaque-ids-free ids)
                      #t))))))))))

)
