;; Copyright © 2026 Amirouche A. BOUBEKKI <amirouche at hyper dev>
;;
;; HTTP server over the io_uring loop, parsing requests with
;; picohttpparser. Extracted from examples/picotransparenturing.scm
;; section 13.
;;
;; (transparent PORT APPLICATION CONTEXT DISPATCH) serves until
;; SIGINT/SIGTERM:
;;  - (APPLICATION) → app-wide state, once at startup
;;  - (CONTEXT app client req) → per-connection state, first request
;;  - (DISPATCH app state method path params req)
;;      → (values status (body-bytevector . content-type) extra-headers)
;;    where the response pair usually comes from the json/html/xml/
;;    response helpers.
(library (letloop http server)

  (export transparent
          response json html xml
          status-code->reason
          http-response-write*
          uri-parse/range
          try-parse-http-request

          ;; re-exports for dispatch procedures inspecting REQ
          phr-request-body
          phr-request-method-symbol
          phr-request-header-ref
          phr-request-header-count
          phr-request-header-name
          phr-request-header-value

          ~check-http-server-000
          ~check-http-server-001
          ~check-http-server-002
          ~check-http-server-003
          ~check-http-server-004
          ~check-http-server-005)

  (import (chezscheme)
          (letloop aql shims)
          (letloop picohttpparser)
          (letloop json)
          (letloop html base)
          (letloop xml)
          (letloop http)
          (rename (only (letloop www) www-percent-decode www-query-read)
                  (www-percent-decode percent-decode))
          (letloop liburing low)
          (letloop flow))

  (begin
    (include "letloop/http/server.body.scm")
    (include "letloop/http/server.check.scm")))
