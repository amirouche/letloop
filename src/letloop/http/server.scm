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
;;  - (DISPATCH app state method path params req [rctx])
;;      → (values status (body-bytevector . content-type) extra-headers)
;;    RCTX, the request context below, is passed only to a DISPATCH
;;    that takes seven arguments; a six-argument one still works.
;;    where the response pair usually comes from the json/html/xml/
;;    response helpers.
(library (letloop http server)

  (export transparent
          response json html xml
          status-code->reason
          http-response-write*
          uri-parse/range
          try-parse-http-request

          ;; Per-request cancellation, added 2026-08-14: DISPATCH now
          ;; receives an extra REQUEST-CONTEXT argument. Its NEEDED?
          ;; field starts #t and is flipped to #f by the server itself
          ;; when it gives up on the request (timeout or the
          ;; connection dying mid-dispatch) -- a handler doing
          ;; long-running fanned-out work (e.g. multiple upstream
          ;; fetches) should check it periodically and stop spawning/
          ;; waiting on more work once it reads #f, rather than
          ;; running to completion for a response nobody will ever
          ;; receive.
          request-context? request-context-needed?

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
          ~check-http-server-005
          ~check-http-server-006)

  (import (chezscheme)
          (letloop aql shims)
          (letloop picohttpparser)
          (letloop json)
          (letloop html base)
          (letloop xml)
          (letloop http)
          (rename (only (letloop www) www-percent-decode www-query-read)
                  (www-percent-decode percent-decode))
          ;; flow2's exports and nothing below them: the listener,
          ;; accept, reads, writes, closes, the per-request dispatch
          ;; race and the idle reaper are all flow2 events and fibers.
          (letloop flow2))

  (begin
    (include "letloop/http/server.body.scm")
    (include "letloop/http/server.check.scm")))
