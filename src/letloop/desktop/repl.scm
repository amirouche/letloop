;; M2.4: graphical REPL.
;;
;; start-repl! attaches a line-handler to a window that:
;;
;;   1. parses the typed line as a Scheme datum (via read on a
;;      string-input-port — multi-token expressions are fine, but we
;;      don't support multi-line entry yet)
;;   2. evals against (interaction-environment) so the user sees the
;;      same bindings letloop's own libraries expose
;;   3. appends both the input and its result (or "ERROR: ...") into a
;;      bounded history rendered below the prompt
;;
;; PLAN.md targets per-line color (errors in red); for v0 we keep a
;; single foreground color and prefix errors with "ERROR: ". Adding a
;; per-instance color attribute is a small shader / pipeline tweak,
;; deferred so the deliverable's first turn-of-the-crank hits the
;; minimum eval path.
(library (letloop desktop repl)
  (export
   start-repl!)
  (import
   (chezscheme)
   (letloop desktop window))

  (define HISTORY-CAP 12)        ; how many input/result pairs to keep
  (define HISTORY-LINE-HEIGHT 32)

  ;; Given a window, attach a REPL line-handler. The window must
  ;; already have a keyboard attached by the caller — this is just a
  ;; behaviour shim, not a full setup procedure.
  (define (start-repl! w)
    (define history '())              ; list of (text x y) — latest first
    (define base-x (* 1 40))          ; same column as the prompt
    (define base-y 240)               ; just below the default prompt y=200
    (define (refresh-display!)
      ;; Rewrite pending-text from scratch each time history changes.
      ;; Greeting / static lines that desktop.scm wrote earlier are
      ;; preserved by the caller; we own the lines below base-y.
      (window-clear-text! w)
      (window-draw-text! w "letloop desktop" 40 40)
      (window-draw-text! w "press Ctrl-C to exit" 40 80)
      (window-draw-text! w "REPL: type Scheme + Enter, results below" 40 120)
      ;; History — newest at the top. Each entry is (text . red?).
      (let loop ((h history) (i 0))
        (cond
         ((null? h) (void))
         (else
          (let* ((entry (car h))
                 (txt   (car entry))
                 (red?  (cdr entry))
                 (y     (+ base-y (* i HISTORY-LINE-HEIGHT))))
            (if red?
                (window-draw-text/color! w txt base-x y 1.0 0.3 0.3 1.0)
                (window-draw-text!       w txt base-x y))
            (loop (cdr h) (+ i 1)))))))
    (define (push-history! line red?)
      (set! history (cons (cons line red?) history))
      (when (> (length history) HISTORY-CAP)
        (set! history (list-head history HISTORY-CAP)))
      (refresh-display!))
    ;; Initial render.
    (refresh-display!)
    (window-set-prompt! w "letloop> ")
    (window-set-line-handler!
     w
     (lambda (line)
       (cond
        ((zero? (string-length line))
         (push-history! "letloop> " #f))
        (else
         (push-history! (string-append "letloop> " line) #f)
         (let* ((error? #f)
                (result
                 (guard (e (#t (set! error? #t)
                               (string-append "ERROR: " (format-error e))))
                   (let* ((p (open-string-input-port line))
                          (datum (read p)))
                     (cond
                      ((eof-object? datum) "")
                      (else
                       (format #f "~a"
                               (eval datum (interaction-environment)))))))))
           (unless (zero? (string-length result))
             (push-history! result error?))))))))

  (define (format-error e)
    (cond
     ((message-condition? e) (condition-message e))
     (else (format #f "~a" e)))))
