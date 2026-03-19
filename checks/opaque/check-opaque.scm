(library (check-opaque)

  (export
   ~check-000-one-step-register-and-login
   ~check-001-four-step-register-and-login
   ~check-002-wrong-password-fails
   ~check-003-default-ids
   ~check-004-export-key-consistent)

  (import (chezscheme) (letloop opaque))

  ;; Helper: convert a string to a bytevector for use as password/context
  (define (string->bv s)
    (string->bytevector s (make-transcoder (utf-8-codec))))

  ;; --------------------------------------------------------
  ;; Test 1: One-step registration + full AKE login
  ;; --------------------------------------------------------
  (define ~check-000-one-step-register-and-login
    (lambda ()
      (let* ((pwdU (string->bv "asdf"))
             (ctx (string->bv "test"))
             (ids (make-opaque-ids (string->bv "user") (string->bv "server")))
             (rec (make-user-record))
             (export-key (make-export-key)))
        ;; Register
        (assert (= 0 (opaque-register pwdU #f ids rec export-key)))
        ;; AKE step 1: client
        (let* ((sec (make-user-session-secret (bytevector-length pwdU)))
               (ke1 (make-user-session-public)))
          (assert (= 0 (opaque-create-credential-request pwdU sec ke1)))
          ;; AKE step 2: server
          (let* ((ke2 (make-server-session))
                 (sk-server (make-shared-secret))
                 (authU0 (make-auth-tag)))
            (assert (= 0 (opaque-create-credential-response
                          ke1 rec ids ctx ke2 sk-server authU0)))
            ;; AKE step 3: client recovers credentials
            (let* ((sk-client (make-shared-secret))
                   (authU1 (make-auth-tag))
                   (ek2 (make-export-key)))
              (assert (= 0 (opaque-recover-credentials
                            ke2 sec ctx ids sk-client authU1 ek2)))
              ;; Shared secrets must match
              (assert (bytevector=? sk-server sk-client))
              ;; Explicit user auth must pass
              (assert (= 0 (opaque-user-auth authU0 authU1)))
              (opaque-ids-free ids)
              #t))))))

  ;; --------------------------------------------------------
  ;; Test 2: Four-step (private) registration + full AKE login
  ;; --------------------------------------------------------
  (define ~check-001-four-step-register-and-login
    (lambda ()
      (let* ((pwdU (string->bv "asdf"))
             (ctx (string->bv "test"))
             (ids (make-opaque-ids (string->bv "user") (string->bv "server"))))
        ;; Registration step 1: client creates request
        (let* ((usr-sec (make-register-user-secret (bytevector-length pwdU)))
               (request (make-bytevector 32 0)))
          (assert (= 0 (opaque-create-registration-request pwdU usr-sec request)))
          ;; Registration step 2: server responds
          (let* ((srv-sec (make-register-secret))
                 (pub (make-register-public)))
            (assert (= 0 (opaque-create-registration-response request #f srv-sec pub)))
            ;; Registration step 3: client finalizes
            (let* ((reg-rec (make-registration-record))
                   (export-key (make-export-key)))
              (assert (= 0 (opaque-finalize-request usr-sec pub ids reg-rec export-key)))
              ;; Registration step 4: server stores record
              (let ((rec (make-user-record)))
                (opaque-store-user-record srv-sec reg-rec rec)
                ;; Now run the AKE
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
                      ;; Shared secrets must match
                      (assert (bytevector=? sk-server sk-client))
                      ;; Explicit user auth must pass
                      (assert (= 0 (opaque-user-auth authU0 authU1)))
                      (opaque-ids-free ids)
                      #t)))))))))))

  ;; --------------------------------------------------------
  ;; Test 3: Wrong password must fail authentication
  ;; --------------------------------------------------------
  (define ~check-002-wrong-password-fails
    (lambda ()
      (let* ((pwdU (string->bv "correct-password"))
             (wrong (string->bv "wrong-password"))
             (ctx (string->bv "test"))
             (ids (make-opaque-ids (string->bv "user") (string->bv "server")))
             (rec (make-user-record))
             (export-key (make-export-key)))
        ;; Register with correct password
        (assert (= 0 (opaque-register pwdU #f ids rec export-key)))
        ;; AKE with wrong password
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
              ;; RecoverCredentials should fail (return non-zero)
              (let ((rc (opaque-recover-credentials
                         ke2 sec ctx ids sk-client authU1 ek)))
                (opaque-ids-free ids)
                (assert (not (= 0 rc)))
                #t)))))))

  ;; --------------------------------------------------------
  ;; Test 4: Default ids (pass #f for both)
  ;; --------------------------------------------------------
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

  ;; --------------------------------------------------------
  ;; Test 5: Export key matches between registration and login
  ;; --------------------------------------------------------
  (define ~check-004-export-key-consistent
    (lambda ()
      (let* ((pwdU (string->bv "export-key-test"))
             (ctx (string->bv "test"))
             (ids (make-opaque-ids (string->bv "alice") (string->bv "server"))))
        ;; Four-step registration to get export_key
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
                ;; AKE to get export_key again
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
                      ;; Export keys from registration and login must match
                      (assert (bytevector=? ek-reg ek-login))
                      (opaque-ids-free ids)
                      #t)))))))))))

)
