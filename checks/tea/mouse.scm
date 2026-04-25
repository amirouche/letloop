(library (tea mouse)

  (export
   ~check-mouse-x10-left-press
   ~check-mouse-x10-release
   ~check-mouse-x10-with-mods
   ~check-mouse-x10-motion
   ~check-mouse-sgr-left-press
   ~check-mouse-sgr-release
   ~check-mouse-sgr-wheel-up
   ~check-mouse-sgr-with-mods
   ~check-mouse-urxvt-middle-press
   ~check-mouse-zero-indexed-coords)

  (import (chezscheme)
          (letloop tea mouse))

  (define (~check-mouse-x10-left-press)
    (let ((e (decode-mouse-x10 (fx+ 0 32) (fx+ 1 32 1) (fx+ 1 32 1))))
      (and (mouse-event? e)
           (eq? (mouse-event-button e) 'left)
           (mouse-event-pressed? e)
           (not (mouse-event-motion? e))
           (null? (mouse-event-mods e)))))

  (define (~check-mouse-x10-release)
    ;; X10 release encodes as button low bits = 3
    (let ((e (decode-mouse-x10 (fx+ 3 32) (fx+ 5 32) (fx+ 5 32))))
      (and (eq? (mouse-event-button e) 'release)
           (not (mouse-event-pressed? e)))))

  (define (~check-mouse-x10-with-mods)
    ;; left + shift (4) + ctrl (16) = 20
    (let ((e (decode-mouse-x10 (fx+ 20 32) (fx+ 33 32) (fx+ 33 32))))
      (and (eq? (mouse-event-button e) 'left)
           (equal? (mouse-event-mods e) '(shift ctrl)))))

  (define (~check-mouse-x10-motion)
    ;; motion bit (32) + left (0) = 32
    (let ((e (decode-mouse-x10 (fx+ 32 32) (fx+ 11 32) (fx+ 22 32))))
      (and (eq? (mouse-event-button e) 'motion)
           (mouse-event-motion? e))))

  (define (~check-mouse-sgr-left-press)
    (let ((e (decode-mouse-sgr '(0 5 5) #\M)))
      (and (eq? (mouse-event-button e) 'left)
           (mouse-event-pressed? e)
           (= (mouse-event-x e) 4)
           (= (mouse-event-y e) 4))))

  (define (~check-mouse-sgr-release)
    (let ((e (decode-mouse-sgr '(0 5 5) #\m)))
      (and (eq? (mouse-event-button e) 'release)
           (not (mouse-event-pressed? e)))))

  (define (~check-mouse-sgr-wheel-up)
    ;; button=64 in SGR -> wheel-up
    (let ((e (decode-mouse-sgr '(64 10 10) #\M)))
      (eq? (mouse-event-button e) 'wheel-up)))

  (define (~check-mouse-sgr-with-mods)
    ;; left=0 + meta=8 = 8
    (let ((e (decode-mouse-sgr '(8 1 1) #\M)))
      (and (eq? (mouse-event-button e) 'left)
           (equal? (mouse-event-mods e) '(meta)))))

  (define (~check-mouse-urxvt-middle-press)
    ;; urxvt encodes button+32, so 33 = middle (1) + 32
    (let ((e (decode-mouse-urxvt '(33 7 8))))
      (and (eq? (mouse-event-button e) 'middle)
           (= (mouse-event-x e) 6)
           (= (mouse-event-y e) 7))))

  (define (~check-mouse-zero-indexed-coords)
    ;; Smallest valid coord (1) -> 0
    (and (let ((e (decode-mouse-sgr '(0 1 1) #\M)))
           (and (= (mouse-event-x e) 0) (= (mouse-event-y e) 0)))
         (let ((e (decode-mouse-x10 (fx+ 0 32) 33 33)))
           (and (= (mouse-event-x e) 0) (= (mouse-event-y e) 0))))))
