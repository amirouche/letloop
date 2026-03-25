;; Copyright © 2019-2023 Amirouche BOUBEKKI <amirouche at hyper dev>

(define triplestore (make-nstore (bytevector 101) 3))

(define ~check-nstore-000
  (lambda ()
    (check (not
            ;; ask an empty database
            (let* ((okvs (make-aql)))
              (aql-in-transaction okvs
                (lambda (tx)
                  (nstore-ref tx triplestore '("P4X432" blog/title "hyper.dev")))))))))

(define ~check-nstore-001
  (lambda ()
    (check (bytevector 42)
           (let ((okvs (make-aql)))
             ;; add
             (aql-in-transaction okvs
               (lambda (tx)
                 (nstore-add! tx triplestore '("P4X432" blog/title "hyper.dev") (bytevector 42))))
             (aql-in-transaction okvs
               (lambda (tx)
                 (nstore-ref tx triplestore '("P4X432" blog/title "hyper.dev"))))))))

(define ~check-nstore-002
  (lambda ()
    (check
     (not
      (let ((okvs (make-aql)))
        (aql-in-transaction okvs
          (lambda (tx)
            ;; add!
            (nstore-add! tx triplestore '("P4X432" blog/title "hyper.dev") (bytevector 42))
            ;; clear!
            (nstore-clear! tx triplestore '("P4X432" blog/title "hyper.dev"))
            ;; ref
            (nstore-ref tx triplestore '("P4X432" blog/title "hyper.dev")))))))))

(define ~check-nstore-003
  (lambda ()
    (check '("DIY a database" "DIY a full-text search engine")
      (let ((okvs (make-aql)))
        (aql-in-transaction okvs
          (lambda (tx)
            ;; add hyper.dev blog posts
            (nstore-add! tx triplestore '("P4X432" blog/title "hyper.dev") (bytevector))
            (nstore-add! tx triplestore '("123456" post/title "DIY a database") (bytevector))
            (nstore-add! tx triplestore '("123456" post/blog "P4X432") (bytevector))
            (nstore-add! tx triplestore '("654321" post/title "DIY a full-text search engine") (bytevector))
            (nstore-add! tx triplestore '("654321" post/blog "P4X432") (bytevector))
            ;; add dthompson.us blog posts
            (nstore-add! tx triplestore '("1" blog/title "dthompson.us") (bytevector))
            (nstore-add! tx triplestore '("2" post/title "Haunt 0.2.4 released") (bytevector))
            (nstore-add! tx triplestore '("2" post/blog "1") (bytevector))
            (nstore-add! tx triplestore '("3" post/title "Haunt 0.2.3 released") (bytevector))
            (nstore-add! tx triplestore '("3" post/blog "1") (bytevector))))
        ;; query
        (aql-in-transaction okvs
          (lambda (tx)
            (map (lambda (x) (cdr (assq 'post/title x)))
                 (nstore-query tx triplestore
                               (list (list (nstore-var 'blog/uid)
                                           'blog/title
                                           "hyper.dev")
                                     (list (nstore-var 'post/uid)
                                           'post/blog
                                           (nstore-var 'blog/uid))
                                     (list (nstore-var 'post/uid)
                                           'post/title
                                           (nstore-var 'post/title)))))))))))

(define ~check-nstore-004
  (lambda ()
    (check '("hyper.dev" "hyperdev.fr" "hypermove.net")
           (let ((okvs (make-aql)))
             (aql-in-transaction okvs
               (lambda (tx)
                 ;; add!
                 (nstore-add! tx triplestore '("P4X432" blog/title "hyper.dev") (bytevector))
                 (nstore-add! tx triplestore '("P4X433" blog/title "hyperdev.fr") (bytevector))
                 (nstore-add! tx triplestore '("P4X434" blog/title "hypermove.net") (bytevector))))
             (aql-in-transaction okvs
               (lambda (tx)
                 (map (lambda (item) (cdr (assq 'title item)))
                      (nstore-query tx triplestore
                                    (list (list (nstore-var 'uid)
                                                'blog/title
                                                (nstore-var 'title)))))))))))

;; nstore-query* tests

(define ~check-nstore-005
  (lambda ()
    ;; Number range constraint
    (let* ((okvs (make-aql))
           (store (make-nstore (bytevector 60) 3)))
      (aql-in-transaction okvs
        (lambda (tx)
          (nstore-add! tx store '(10 "person" "Alice") (bytevector))
          (nstore-add! tx store '(25 "person" "Bob") (bytevector))
          (nstore-add! tx store '(30 "person" "Carol") (bytevector))
          (nstore-add! tx store '(50 "person" "Dave") (bytevector))))
      (check '("Bob" "Carol")
             (aql-in-transaction okvs
               (lambda (tx)
                 (map (lambda (b) (cdr (assq 'name b)))
                      (nstore-query* tx store
                        (list (list (nstore-var 'age (nstore-gte 18) (nstore-lte 35))
                                    "person"
                                    (nstore-var 'name)))))))))))

(define ~check-nstore-006
  (lambda ()
    ;; String range constraint
    (let* ((okvs (make-aql))
           (store (make-nstore (bytevector 61) 3)))
      (aql-in-transaction okvs
        (lambda (tx)
          (nstore-add! tx store '("Alpha" "book" "Author1") (bytevector))
          (nstore-add! tx store '("Beta" "book" "Author2") (bytevector))
          (nstore-add! tx store '("Gamma" "book" "Author3") (bytevector))))
      (check '("Author1")
             (aql-in-transaction okvs
               (lambda (tx)
                 (map (lambda (b) (cdr (assq 'author b)))
                      (nstore-query* tx store
                        (list (list (nstore-var 'title (nstore-gte "A") (nstore-lt "B"))
                                    "book"
                                    (nstore-var 'author)))))))))))

(define ~check-nstore-007
  (lambda ()
    ;; Morton spatial query — binds decoded coordinates
    (let* ((okvs (make-aql))
           (store (make-nstore (bytevector 62) 3))
           (enc (lambda (x y) (morton-interleave 2 32 (list x y)))))
      (aql-in-transaction okvs
        (lambda (tx)
          (nstore-add! tx store (list (enc 1 1) "person" "Alice") (bytevector))
          (nstore-add! tx store (list (enc 5 5) "person" "Bob") (bytevector))
          (nstore-add! tx store (list (enc 3 3) "place" "Park") (bytevector))
          (nstore-add! tx store (list (enc 8 8) "person" "Carol") (bytevector))))
      ;; Query rectangle [2,2]-[6,6] — should find Bob(5,5) and Park(3,3)
      (check '("Park" "Bob")
             (aql-in-transaction okvs
               (lambda (tx)
                 (map (lambda (b) (cdr (assq 'name b)))
                      (nstore-query* tx store
                        (list (list (nstore-var 'pos (nstore-morton 2 32 '(2 2) '(6 6)))
                                    (nstore-var 'category)
                                    (nstore-var 'name)))))))))))

