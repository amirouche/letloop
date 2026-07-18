;; Copyright © 2026 Amirouche A. BOUBEKKI <amirouche at hyper dev>

;; Deterministic pseudo-random keys (LCG, fixed seed) so failures
;; reproduce.
(define %heap-check-keys
  (lambda (n)
    (let loop ((i 0) (state 42) (out '()))
      (if (fx=? i n)
          (reverse out)
          (let ((state (mod (+ (* state 1103515245) 12345) 2147483648)))
            (loop (fx+ i 1) state (cons (mod state 10000) out)))))))

(define %heap-drain
  (lambda (h)
    (let loop ((out '()))
      (if (heap-empty? h)
          (reverse out)
          (loop (cons (car (heap-pop-min! h)) out))))))

(define ~check-heap-000
  (lambda ()
    ;; Fresh heap is empty; heap-min returns #f. Popping an empty heap
    ;; raises without corrupting it: the heap stays empty and usable.
    (let ((h (heap-new)))
      (let ((raised? (guard (ex (else #t))
                       (heap-pop-min! h)
                       #f)))
        (check #t (and (heap-empty? h)
                       (not (heap-min h))
                       raised?
                       (begin
                         (heap-add! h 1 'one)
                         (equal? '(1) (%heap-drain h)))))))))

(define ~check-heap-001
  (lambda ()
    ;; Pop order matches a sorted-list oracle.
    (let ((keys (%heap-check-keys 100))
          (h (heap-new)))
      (for-each (lambda (k) (heap-add! h k (* k 2))) keys)
      (check (sort < keys) (%heap-drain h)))))

(define ~check-heap-002
  (lambda ()
    ;; Growth past the initial 64-slot vector.
    (let ((keys (%heap-check-keys 500))
          (h (heap-new)))
      (for-each (lambda (k) (heap-add! h k #f)) keys)
      (check (sort < keys) (%heap-drain h)))))

(define ~check-heap-003
  (lambda ()
    ;; heap-split: BEFORE gets keys <= pivot, H keeps the rest.
    (let ((h (heap-new)))
      (for-each (lambda (k) (heap-add! h k (number->string k)))
                '(5 1 9 3 7))
      (call-with-values (lambda () (heap-split h 5))
        (lambda (before h)
          (check #t (and (equal? '(1 3 5) (%heap-drain before))
                         (equal? '(7 9) (%heap-drain h)))))))))

(define ~check-heap-004
  (lambda ()
    ;; heap-for-each visits every entry exactly once, values intact.
    (let ((h (heap-new))
          (seen '()))
      (for-each (lambda (k) (heap-add! h k (- k))) '(4 2 8 6))
      (heap-for-each h (lambda (k v) (set! seen (cons (cons k v) seen))))
      (check '((2 . -2) (4 . -4) (6 . -6) (8 . -8))
             (sort (lambda (a b) (< (car a) (car b))) seen)))))
