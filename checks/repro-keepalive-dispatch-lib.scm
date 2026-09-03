;; Server half of a reproducer for the letloop TODO.md open item:
;; "verify under concurrent load whether the fixed call-with-loop-
;; prompt bug ... ever actually fired in handle-connection" -- and,
;; more broadly, a regression guard for any future bug of that shape
;; (a resumed fiber whose normal return re-runs stale sibling work),
;; exercised through the REAL server code path (transparent ->
;; handle-connection) rather than the synthetic two-fiber tests in
;; src/letloop/liburing/low.check.scm.
;;
;; No downstream-application dependency: this isolates whether a
;; duplicate-dispatch regression or a "connection gets slower the
;; longer it stays open" latency signature lives in letloop's server
;; layer itself, independent of a downstream application's heavier
;; per-request work (scoring, storage fetches) -- see that
;; application's own bench-server tracking notes, which reported
;; exactly that signature against its search-serving endpoint and
;; traced the suspicion here.
;;
;; Serve with (paired client: repro-keepalive-dispatch-client.scm):
;;
;;   cd submodules/letloop
;;   LD_LIBRARY_PATH=$PWD/local/lib local/bin/letloop http serve \
;;     --port=18080 checks/ checks/repro-keepalive-dispatch-lib.scm
;;
;; Every GET /echo/<token> request is appended to a log, in arrival
;; order, with its token untouched. The paired client gives every
;; request a token unique across the whole run (connection-id "-"
;; position, or "fresh-" request-index). If any token is ever
;; dispatched more than once, handle-connection re-ran work it should
;; only have done once -- the exact symptom the fixed bug produced (a
;; duplicate IORING_OP_CLOSE, per the fix commit's own repro).
;;
;;   GET /echo/<token>  -- log TOKEN, respond 200 "ok"
;;   GET /dump           -- every logged token, one per line, in
;;                          arrival order (plain text, not JSON: the
;;                          client needs no JSON parser to read it)
;;   GET /reset          -- clear the log, so one server instance can
;;                          serve many reproducer runs
(library (repro-keepalive-dispatch-lib)
  (export application context dispatch)
  (import (chezscheme)
          (letloop http server))

  ;; App-wide state: the log, oldest-last (cons is O(1); /dump
  ;; reverses once at read time).
  (define (application) (box '()))

  (define (context application client req) client)

  ;; PATH arrives as a list of already-split segments (confirmed by
  ;; hand-tracing a real request through it: "/echo/warmup" comes in
  ;; as ("echo" "warmup"), not the string "echo/warmup" -- matches how
  ;; examples/my-web-library.scm's (match (cons method path) ((GET
  ;; "sleep") ...)) only makes sense if path is ("sleep")).
  (define (dispatch application request-state method path params req request-context)
    (guard (ex (else
                (let ((port (open-file-output-port "/tmp/repro-dispatch-error.log"
                                                    (file-options no-fail)
                                                    (buffer-mode block)
                                                    (native-transcoder))))
                  (display-condition ex port)
                  (newline port)
                  (close-port port))
                (values 500 (response 'text "dispatch error, see /tmp/repro-dispatch-error.log") '())))
      (cond
        ((not (eq? method 'GET))
         (values 404 (response 'text "not found") '()))
        ((equal? path '("dump"))
         (values 200
                 (response 'text
                   (apply string-append
                          (map (lambda (token) (string-append token "\n"))
                               (reverse (unbox application)))))
                 '()))
        ((equal? path '("reset"))
         (set-box! application '())
         (values 200 (response 'text "ok") '()))
        ((and (pair? path) (string=? (car path) "echo") (pair? (cdr path)))
         (let ((token (cadr path)))
           (set-box! application (cons token (unbox application)))
           (values 200 (response 'text "ok") '())))
        (else
         (values 404 (response 'text "not found") '()))))))
