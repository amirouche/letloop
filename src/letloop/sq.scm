(library (letloop sq)

  (export sq-new
          sq-split
          sq-min
          sq-add!
          sq-empty?
          sq-for-each)

  (import (chezscheme) (letloop r999))

  (define-record-type* <sq>
    (make-sq box)
    sq?
    (box sq-unbox sq-setbox!))

  (define sq-for-each
    (lambda (sq proc)
      (for-each proc (sq-unbox sq))))
  
  (define sq-new
    (lambda ()
      (make-sq '())))

  (define sq-empty?
    (lambda (sq)
      (null? (sq-unbox sq))))

  (define sq-min
    (lambda (sq)
      (if (sq-empty? sq)
          #f
          (car (sq-unbox sq)))))

  (define sq-add!
    (lambda (sq k v)
      (define new (sort (lambda (a b) (< (car a) (car b)))
                        (cons (cons k v) (sq-unbox sq))))
      (sq-setbox! sq new)))

  (define sq-split
    (lambda (sq k)
      (let loop ((kv* (sq-unbox sq))
                 (before-or-equal '()))
        (if (null? kv*)
            (values (make-sq (reverse before-or-equal)) (make-sq '()))
            (if (<= (caar kv*) k)
                (loop (cdr kv*) (cons (car kv*) before-or-equal))
                (values (make-sq (reverse before-or-equal)) (make-sq kv*))))))))
      
  
