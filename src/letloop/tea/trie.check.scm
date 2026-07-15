;; Checks for (letloop tea trie), driving the module through its exported
;; API the way a caller would.  Included at the tail of the library;
;; discovered by `make check` via the ~check- exports.


  (define-syntax expect
    (syntax-rules ()
      ((_ a b)
       (let ((a* a) (b* b))
         (or (equal? a* b*)
             (begin (display (list 'expected b* 'got a*)) (newline) #f))))))

  (define (feed* trie-state bytes)
    (let loop ((bs bytes) (last 'continue))
      (if (null? bs)
          last
          (loop (cdr bs) (trie-feed! trie-state (car bs))))))

  (define (~check-trie-single-key-match)
    (let* ((t (make-trie '(("AB" . hi))))
           (s (make-trie-state t)))
      (and (eq? (trie-feed! s 65) 'continue)
           (equal? (trie-feed! s 66) '(match hi)))))

  (define (~check-trie-multiple-keys)
    (let* ((t (make-trie '(("\x1b;[A" . up)
                           ("\x1b;[B" . down)
                           ("\x1b;[C" . right))))
           (s (make-trie-state t)))
      (and
       (eq? (trie-feed! s #x1b) 'continue)
       (eq? (trie-feed! s (char->integer #\[)) 'continue)
       (equal? (trie-feed! s (char->integer #\B)) '(match down)))))

  (define (~check-trie-prefix-continue)
    ;; A prefix that has continuation must report continue, not match
    (let* ((t (make-trie '(("AB" . x))))
           (s (make-trie-state t)))
      (eq? (trie-feed! s 65) 'continue)))

  (define (~check-trie-no-match)
    (let* ((t (make-trie '(("AB" . x))))
           (s (make-trie-state t)))
      (and (eq? (trie-feed! s 65) 'continue)
           (eq? (trie-feed! s 67) 'no-match))))      ; expected B, got C

  (define (~check-trie-state-reset)
    ;; After a match, state is auto-reset to root and another sequence works.
    (let* ((t (make-trie '(("AB" . one) ("CD" . two))))
           (s (make-trie-state t)))
      (and (eq? (trie-feed! s 65) 'continue)
           (equal? (trie-feed! s 66) '(match one))
           (eq? (trie-feed! s 67) 'continue)
           (equal? (trie-feed! s 68) '(match two)))))

  (define (~check-trie-bytes-tracked)
    ;; Bytes consumed since reset are accessible — input.scm uses these to
    ;; redrive when a prefix turns out to be no-match.
    (let* ((t (make-trie '(("ABC" . val))))
           (s (make-trie-state t)))
      (trie-feed! s 65) (trie-feed! s 66)
      ;; bytes are stored most-recent-first
      (equal? (trie-state-bytes s) '(66 65))))

  (define (~check-trie-real-xterm-arrows)
    (let* ((t (make-trie '(("\x1b;[A"  . arrow-up)
                           ("\x1b;OA"  . arrow-up)
                           ("\x1b;[5~" . pg-up))))
           (s (make-trie-state t)))
      (and (eq? (trie-feed! s #x1B) 'continue)
           (eq? (trie-feed! s (char->integer #\[)) 'continue)
           (equal? (trie-feed! s (char->integer #\A)) '(match arrow-up))
           (eq? (trie-feed! s #x1B) 'continue)
           (eq? (trie-feed! s (char->integer #\O)) 'continue)
           (equal? (trie-feed! s (char->integer #\A)) '(match arrow-up)))))

  (define (~check-trie-shared-prefix-disambiguation)
    ;; \e[5~ vs \e[5;... — only the tilde form is a key here.
    (let* ((t (make-trie '(("\x1b;[5~" . pg-up))))
           (s (make-trie-state t)))
      (and (eq? (trie-feed! s #x1B) 'continue)
           (eq? (trie-feed! s (char->integer #\[)) 'continue)
           (eq? (trie-feed! s (char->integer #\5)) 'continue)
           (eq? (trie-feed! s (char->integer #\;)) 'no-match))))
