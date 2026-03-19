#!chezscheme
(library (letloop tls low)

  (export
   ;; Constants
   TLS_API
   TLS_PROTOCOL_TLSv1_0
   TLS_PROTOCOL_TLSv1_1
   TLS_PROTOCOL_TLSv1_2
   TLS_PROTOCOL_TLSv1_3
   TLS_PROTOCOL_TLSv1
   TLS_PROTOCOLS_ALL
   TLS_PROTOCOLS_DEFAULT
   TLS_WANT_POLLIN
   TLS_WANT_POLLOUT
   TLS_OCSP_RESPONSE_SUCCESSFUL
   TLS_OCSP_RESPONSE_MALFORMED
   TLS_OCSP_RESPONSE_INTERNALERROR
   TLS_OCSP_RESPONSE_TRYLATER
   TLS_OCSP_RESPONSE_SIGREQUIRED
   TLS_OCSP_RESPONSE_UNAUTHORIZED
   TLS_OCSP_CERT_GOOD
   TLS_OCSP_CERT_REVOKED
   TLS_OCSP_CERT_UNKNOWN
   TLS_CRL_REASON_UNSPECIFIED
   TLS_CRL_REASON_KEY_COMPROMISE
   TLS_CRL_REASON_CA_COMPROMISE
   TLS_CRL_REASON_AFFILIATION_CHANGED
   TLS_CRL_REASON_SUPERSEDED
   TLS_CRL_REASON_CESSATION_OF_OPERATION
   TLS_CRL_REASON_CERTIFICATE_HOLD
   TLS_CRL_REASON_REMOVE_FROM_CRL
   TLS_CRL_REASON_PRIVILEGE_WITHDRAWN
   TLS_CRL_REASON_AA_COMPROMISE
   TLS_MAX_SESSION_ID_LENGTH
   TLS_TICKET_KEY_SIZE

   ;; Init
   tls-init

   ;; Error
   tls-config-error
   tls-error

   ;; Config lifecycle
   tls-config-new
   tls-config-free
   tls-config-clear-keys

   ;; Default CA
   tls-default-ca-cert-file

   ;; Config CA/certs/keys (file variants)
   tls-config-set-ca-file
   tls-config-set-ca-path
   tls-config-set-cert-file
   tls-config-set-key-file
   tls-config-set-keypair-file
   tls-config-set-crl-file
   tls-config-set-ocsp-staple-file
   tls-config-add-keypair-file
   tls-config-add-keypair-ocsp-file
   tls-config-set-keypair-ocsp-file

   ;; Config CA/certs/keys (mem variants)
   tls-config-set-ca-mem
   tls-config-set-cert-mem
   tls-config-set-key-mem
   tls-config-set-keypair-mem
   tls-config-set-ocsp-staple-mem
   tls-config-add-keypair-mem
   tls-config-add-keypair-ocsp-mem
   tls-config-set-keypair-ocsp-mem

   ;; Config protocols/ciphers
   tls-config-set-alpn
   tls-config-set-ciphers
   tls-config-set-dheparams
   tls-config-set-ecdhecurve
   tls-config-set-ecdhecurves
   tls-config-set-protocols
   tls-config-parse-protocols
   tls-config-prefer-ciphers-client
   tls-config-prefer-ciphers-server

   ;; Config verification
   tls-config-verify
   tls-config-insecure-noverifycert
   tls-config-insecure-noverifyname
   tls-config-insecure-noverifytime
   tls-config-ocsp-require-stapling
   tls-config-verify-client
   tls-config-verify-client-optional
   tls-config-set-verify-depth

   ;; Config session
   tls-config-set-session-fd
   tls-config-set-session-id
   tls-config-set-session-lifetime
   tls-config-add-ticket-key

   ;; Context lifecycle
   tls-client
   tls-server
   tls-configure
   tls-reset
   tls-free

   ;; Client connect
   tls-connect
   tls-connect-fds
   tls-connect-servername
   tls-connect-socket

   ;; Server accept
   tls-accept-fds
   tls-accept-socket

   ;; I/O
   tls-handshake
   tls-read
   tls-write
   tls-close

   ;; Peer cert inspection
   tls-peer-cert-provided
   tls-peer-cert-contains-name
   tls-peer-cert-hash
   tls-peer-cert-issuer
   tls-peer-cert-subject
   tls-peer-cert-notbefore
   tls-peer-cert-notafter
   tls-peer-cert-chain-pem

   ;; Connection info
   tls-conn-alpn-selected
   tls-conn-cipher
   tls-conn-cipher-strength
   tls-conn-servername
   tls-conn-session-resumed
   tls-conn-version

   ;; File utilities
   tls-load-file
   tls-unload-file

   ;; OCSP
   tls-ocsp-process-response
   tls-peer-ocsp-cert-status
   tls-peer-ocsp-crl-reason
   tls-peer-ocsp-next-update
   tls-peer-ocsp-response-status
   tls-peer-ocsp-result
   tls-peer-ocsp-revocation-time
   tls-peer-ocsp-this-update
   tls-peer-ocsp-url)

  (import (chezscheme) (letloop cffi))

  ;; Load libtls (pulls in libssl/libcrypto as dependencies)
  (define libtls (load-shared-object "libtls.so"))

  ;; Helper: read a NUL-terminated C string from a pointer address.
  ;; Returns #f if pointer is 0 (NULL).
  (define %strlen (foreign-procedure "strlen" (void*) size_t))

  (define (pointer->string p)
    (if (zero? p)
        #f
        (let* ((len (%strlen p))
               (bv (make-bytevector len)))
          (let loop ((i 0))
            (when (< i len)
              (bytevector-u8-set! bv i (foreign-ref 'unsigned-8 p i))
              (loop (+ i 1))))
          (utf8->string bv))))

  ;; ============================================================
  ;; Constants
  ;; ============================================================

  (define TLS_API 20200120)

  ;; Protocol versions (deprecated versions map to minimum supported)
  (define TLS_PROTOCOL_TLSv1_0 (bitwise-arithmetic-shift-left 1 3))
  (define TLS_PROTOCOL_TLSv1_1 (bitwise-arithmetic-shift-left 1 3))
  (define TLS_PROTOCOL_TLSv1_2 (bitwise-arithmetic-shift-left 1 3))
  (define TLS_PROTOCOL_TLSv1_3 (bitwise-arithmetic-shift-left 1 4))

  (define TLS_PROTOCOL_TLSv1
    (bitwise-ior TLS_PROTOCOL_TLSv1_2 TLS_PROTOCOL_TLSv1_3))
  (define TLS_PROTOCOLS_ALL TLS_PROTOCOL_TLSv1)
  (define TLS_PROTOCOLS_DEFAULT
    (bitwise-ior TLS_PROTOCOL_TLSv1_2 TLS_PROTOCOL_TLSv1_3))

  ;; Want poll sentinels
  (define TLS_WANT_POLLIN -2)
  (define TLS_WANT_POLLOUT -3)

  ;; RFC 6960 Section 2.3 - OCSP response status
  (define TLS_OCSP_RESPONSE_SUCCESSFUL 0)
  (define TLS_OCSP_RESPONSE_MALFORMED 1)
  (define TLS_OCSP_RESPONSE_INTERNALERROR 2)
  (define TLS_OCSP_RESPONSE_TRYLATER 3)
  (define TLS_OCSP_RESPONSE_SIGREQUIRED 4)
  (define TLS_OCSP_RESPONSE_UNAUTHORIZED 5)

  ;; RFC 6960 Section 2.2 - OCSP cert status
  (define TLS_OCSP_CERT_GOOD 0)
  (define TLS_OCSP_CERT_REVOKED 1)
  (define TLS_OCSP_CERT_UNKNOWN 2)

  ;; RFC 5280 Section 5.3.1 - CRL reasons
  (define TLS_CRL_REASON_UNSPECIFIED 0)
  (define TLS_CRL_REASON_KEY_COMPROMISE 1)
  (define TLS_CRL_REASON_CA_COMPROMISE 2)
  (define TLS_CRL_REASON_AFFILIATION_CHANGED 3)
  (define TLS_CRL_REASON_SUPERSEDED 4)
  (define TLS_CRL_REASON_CESSATION_OF_OPERATION 5)
  (define TLS_CRL_REASON_CERTIFICATE_HOLD 6)
  (define TLS_CRL_REASON_REMOVE_FROM_CRL 8)
  (define TLS_CRL_REASON_PRIVILEGE_WITHDRAWN 9)
  (define TLS_CRL_REASON_AA_COMPROMISE 10)

  ;; Session limits
  (define TLS_MAX_SESSION_ID_LENGTH 32)
  (define TLS_TICKET_KEY_SIZE 48)

  ;; ============================================================
  ;; Init
  ;; ============================================================

  (define tls-init
    (foreign-procedure "tls_init" () int))

  ;; ============================================================
  ;; Error
  ;; ============================================================

  ;; Returns string or #f (NULL maps to #f via void* check)
  (define tls-config-error
    (let ((func (foreign-procedure "tls_config_error" (void*) void*)))
      (lambda (config)
        (pointer->string (func config)))))

  (define tls-error
    (let ((func (foreign-procedure "tls_error" (void*) void*)))
      (lambda (ctx)
        (pointer->string (func ctx)))))

  ;; ============================================================
  ;; Config lifecycle
  ;; ============================================================

  (define tls-config-new
    (foreign-procedure "tls_config_new" () void*))

  (define tls-config-free
    (foreign-procedure "tls_config_free" (void*) void))

  (define tls-config-clear-keys
    (foreign-procedure "tls_config_clear_keys" (void*) void))

  ;; ============================================================
  ;; Default CA
  ;; ============================================================

  (define tls-default-ca-cert-file
    (foreign-procedure "tls_default_ca_cert_file" () string))

  ;; ============================================================
  ;; Config CA/certs/keys - file variants
  ;; ============================================================

  (define tls-config-set-ca-file
    (foreign-procedure "tls_config_set_ca_file" (void* string) int))

  (define tls-config-set-ca-path
    (foreign-procedure "tls_config_set_ca_path" (void* string) int))

  (define tls-config-set-cert-file
    (foreign-procedure "tls_config_set_cert_file" (void* string) int))

  (define tls-config-set-key-file
    (foreign-procedure "tls_config_set_key_file" (void* string) int))

  (define tls-config-set-keypair-file
    (foreign-procedure "tls_config_set_keypair_file" (void* string string) int))

  (define tls-config-set-crl-file
    (foreign-procedure "tls_config_set_crl_file" (void* string) int))

  (define tls-config-set-ocsp-staple-file
    (foreign-procedure "tls_config_set_ocsp_staple_file" (void* string) int))

  (define tls-config-add-keypair-file
    (foreign-procedure "tls_config_add_keypair_file" (void* string string) int))

  (define tls-config-add-keypair-ocsp-file
    (foreign-procedure "tls_config_add_keypair_ocsp_file"
                       (void* string string string) int))

  (define tls-config-set-keypair-ocsp-file
    (foreign-procedure "tls_config_set_keypair_ocsp_file"
                       (void* string string string) int))

  ;; ============================================================
  ;; Config CA/certs/keys - mem variants
  ;; ============================================================

  (define tls-config-set-ca-mem
    (foreign-procedure "tls_config_set_ca_mem" (void* void* size_t) int))

  (define tls-config-set-cert-mem
    (foreign-procedure "tls_config_set_cert_mem" (void* void* size_t) int))

  (define tls-config-set-key-mem
    (foreign-procedure "tls_config_set_key_mem" (void* void* size_t) int))

  (define tls-config-set-keypair-mem
    (foreign-procedure "tls_config_set_keypair_mem"
                       (void* void* size_t void* size_t) int))

  (define tls-config-set-ocsp-staple-mem
    (foreign-procedure "tls_config_set_ocsp_staple_mem"
                       (void* void* size_t) int))

  (define tls-config-add-keypair-mem
    (foreign-procedure "tls_config_add_keypair_mem"
                       (void* void* size_t void* size_t) int))

  (define tls-config-add-keypair-ocsp-mem
    (foreign-procedure "tls_config_add_keypair_ocsp_mem"
                       (void* void* size_t void* size_t void* size_t) int))

  (define tls-config-set-keypair-ocsp-mem
    (foreign-procedure "tls_config_set_keypair_ocsp_mem"
                       (void* void* size_t void* size_t void* size_t) int))

  ;; ============================================================
  ;; Config protocols/ciphers
  ;; ============================================================

  (define tls-config-set-alpn
    (foreign-procedure "tls_config_set_alpn" (void* string) int))

  (define tls-config-set-ciphers
    (foreign-procedure "tls_config_set_ciphers" (void* string) int))

  (define tls-config-set-dheparams
    (foreign-procedure "tls_config_set_dheparams" (void* string) int))

  (define tls-config-set-ecdhecurve
    (foreign-procedure "tls_config_set_ecdhecurve" (void* string) int))

  (define tls-config-set-ecdhecurves
    (foreign-procedure "tls_config_set_ecdhecurves" (void* string) int))

  (define tls-config-set-protocols
    (foreign-procedure "tls_config_set_protocols" (void* unsigned-32) int))

  ;; tls_config_parse_protocols takes uint32_t* out param
  ;; Caller should allocate with (foreign-alloc 4), pass pointer,
  ;; then read result with (foreign-ref 'unsigned-32 ptr 0)
  (define tls-config-parse-protocols
    (foreign-procedure "tls_config_parse_protocols" (void* string) int))

  (define tls-config-prefer-ciphers-client
    (foreign-procedure "tls_config_prefer_ciphers_client" (void*) void))

  (define tls-config-prefer-ciphers-server
    (foreign-procedure "tls_config_prefer_ciphers_server" (void*) void))

  ;; ============================================================
  ;; Config verification
  ;; ============================================================

  (define tls-config-verify
    (foreign-procedure "tls_config_verify" (void*) void))

  (define tls-config-insecure-noverifycert
    (foreign-procedure "tls_config_insecure_noverifycert" (void*) void))

  (define tls-config-insecure-noverifyname
    (foreign-procedure "tls_config_insecure_noverifyname" (void*) void))

  (define tls-config-insecure-noverifytime
    (foreign-procedure "tls_config_insecure_noverifytime" (void*) void))

  (define tls-config-ocsp-require-stapling
    (foreign-procedure "tls_config_ocsp_require_stapling" (void*) void))

  (define tls-config-verify-client
    (foreign-procedure "tls_config_verify_client" (void*) void))

  (define tls-config-verify-client-optional
    (foreign-procedure "tls_config_verify_client_optional" (void*) void))

  (define tls-config-set-verify-depth
    (foreign-procedure "tls_config_set_verify_depth" (void* int) int))

  ;; ============================================================
  ;; Config session
  ;; ============================================================

  (define tls-config-set-session-fd
    (foreign-procedure "tls_config_set_session_fd" (void* int) int))

  ;; session_id is unsigned char* + size_t
  (define tls-config-set-session-id
    (foreign-procedure "tls_config_set_session_id" (void* void* size_t) int))

  (define tls-config-set-session-lifetime
    (foreign-procedure "tls_config_set_session_lifetime" (void* int) int))

  ;; key is unsigned char* + size_t, keyrev is uint32_t
  (define tls-config-add-ticket-key
    (foreign-procedure "tls_config_add_ticket_key"
                       (void* unsigned-32 void* size_t) int))

  ;; ============================================================
  ;; Context lifecycle
  ;; ============================================================

  (define tls-client
    (foreign-procedure "tls_client" () void*))

  (define tls-server
    (foreign-procedure "tls_server" () void*))

  (define tls-configure
    (foreign-procedure "tls_configure" (void* void*) int))

  (define tls-reset
    (foreign-procedure "tls_reset" (void*) void))

  (define tls-free
    (foreign-procedure "tls_free" (void*) void))

  ;; ============================================================
  ;; Client connect
  ;; ============================================================

  (define tls-connect
    (foreign-procedure "tls_connect" (void* string string) int))

  (define tls-connect-fds
    (foreign-procedure "tls_connect_fds" (void* int int string) int))

  (define tls-connect-servername
    (foreign-procedure "tls_connect_servername"
                       (void* string string string) int))

  (define tls-connect-socket
    (foreign-procedure "tls_connect_socket" (void* int string) int))

  ;; ============================================================
  ;; Server accept
  ;; ============================================================

  ;; cctx is struct tls** (out param). Caller allocates pointer-sized
  ;; block with (foreign-alloc (foreign-sizeof 'void*)), passes it,
  ;; then reads back with (foreign-ref 'void* ptr 0).
  (define tls-accept-fds
    (foreign-procedure "tls_accept_fds" (void* void* int int) int))

  (define tls-accept-socket
    (foreign-procedure "tls_accept_socket" (void* void* int) int))

  ;; ============================================================
  ;; I/O
  ;; ============================================================

  (define tls-handshake
    (foreign-procedure "tls_handshake" (void*) int))

  ;; buf is void* - caller passes (bytevector-pointer bv) with
  ;; (with-lock (list bv) ...) to pin during call
  (define tls-read
    (foreign-procedure "tls_read" (void* void* size_t) ssize_t))

  (define tls-write
    (foreign-procedure "tls_write" (void* void* size_t) ssize_t))

  (define tls-close
    (foreign-procedure "tls_close" (void*) int))

  ;; ============================================================
  ;; Peer cert inspection
  ;; ============================================================

  (define tls-peer-cert-provided
    (foreign-procedure "tls_peer_cert_provided" (void*) int))

  (define tls-peer-cert-contains-name
    (foreign-procedure "tls_peer_cert_contains_name" (void* string) int))

  (define tls-peer-cert-hash
    (let ((func (foreign-procedure "tls_peer_cert_hash" (void*) void*)))
      (lambda (ctx)
        (pointer->string (func ctx)))))

  (define tls-peer-cert-issuer
    (let ((func (foreign-procedure "tls_peer_cert_issuer" (void*) void*)))
      (lambda (ctx)
        (pointer->string (func ctx)))))

  (define tls-peer-cert-subject
    (let ((func (foreign-procedure "tls_peer_cert_subject" (void*) void*)))
      (lambda (ctx)
        (pointer->string (func ctx)))))

  (define tls-peer-cert-notbefore
    (foreign-procedure "tls_peer_cert_notbefore" (void*) long))

  (define tls-peer-cert-notafter
    (foreign-procedure "tls_peer_cert_notafter" (void*) long))

  ;; Returns uint8_t* (PEM data) and writes length to size_t* out param.
  ;; Caller allocates (foreign-alloc (foreign-sizeof 'size_t)) for len,
  ;; then reads with (foreign-ref 'size_t ptr 0).
  (define tls-peer-cert-chain-pem
    (foreign-procedure "tls_peer_cert_chain_pem" (void* void*) void*))

  ;; ============================================================
  ;; Connection info
  ;; ============================================================

  (define tls-conn-alpn-selected
    (let ((func (foreign-procedure "tls_conn_alpn_selected" (void*) void*)))
      (lambda (ctx)
        (pointer->string (func ctx)))))

  (define tls-conn-cipher
    (let ((func (foreign-procedure "tls_conn_cipher" (void*) void*)))
      (lambda (ctx)
        (pointer->string (func ctx)))))

  (define tls-conn-cipher-strength
    (foreign-procedure "tls_conn_cipher_strength" (void*) int))

  (define tls-conn-servername
    (let ((func (foreign-procedure "tls_conn_servername" (void*) void*)))
      (lambda (ctx)
        (pointer->string (func ctx)))))

  (define tls-conn-session-resumed
    (foreign-procedure "tls_conn_session_resumed" (void*) int))

  (define tls-conn-version
    (let ((func (foreign-procedure "tls_conn_version" (void*) void*)))
      (lambda (ctx)
        (pointer->string (func ctx)))))

  ;; ============================================================
  ;; File utilities
  ;; ============================================================

  ;; Returns uint8_t* (allocated buffer). Caller must free with tls-unload-file.
  ;; len is size_t* out param, password is char* (or pass 0 for NULL).
  (define tls-load-file
    (foreign-procedure "tls_load_file" (string void* void*) void*))

  (define tls-unload-file
    (foreign-procedure "tls_unload_file" (void* size_t) void))

  ;; ============================================================
  ;; OCSP
  ;; ============================================================

  (define tls-ocsp-process-response
    (foreign-procedure "tls_ocsp_process_response" (void* void* size_t) int))

  (define tls-peer-ocsp-cert-status
    (foreign-procedure "tls_peer_ocsp_cert_status" (void*) int))

  (define tls-peer-ocsp-crl-reason
    (foreign-procedure "tls_peer_ocsp_crl_reason" (void*) int))

  (define tls-peer-ocsp-next-update
    (foreign-procedure "tls_peer_ocsp_next_update" (void*) long))

  (define tls-peer-ocsp-response-status
    (foreign-procedure "tls_peer_ocsp_response_status" (void*) int))

  (define tls-peer-ocsp-result
    (let ((func (foreign-procedure "tls_peer_ocsp_result" (void*) void*)))
      (lambda (ctx)
        (pointer->string (func ctx)))))

  (define tls-peer-ocsp-revocation-time
    (foreign-procedure "tls_peer_ocsp_revocation_time" (void*) long))

  (define tls-peer-ocsp-this-update
    (foreign-procedure "tls_peer_ocsp_this_update" (void*) long))

  (define tls-peer-ocsp-url
    (let ((func (foreign-procedure "tls_peer_ocsp_url" (void*) void*)))
      (lambda (ctx)
        (pointer->string (func ctx)))))

)
