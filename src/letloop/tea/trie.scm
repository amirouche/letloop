#!chezscheme
;; (letloop tea trie) — prefix trie for terminal escape-sequence matching.
;;
;; Built once at tea-open from the active cap-set's input-keys + modifier
;; table.  Fed byte-by-byte at runtime; reports continue / match / no-match
;; so the input parser can decide:
;;
;;   continue  — bytes consumed; need more before a verdict
;;   match v   — sequence matched, v is the value (key symbol) to emit
;;   no-match  — current path is a dead end; the bytes consumed so far
;;               must be redriven through a different path (typically:
;;               first byte = literal ESC, rest = re-fed as fresh input)
;;
;; Trie nodes are records.  Children are stored as alists keyed by byte —
;; per-node fanout is small (a handful of digits + a couple of letters)
;; so linear scan is fine and avoids a hash-table per node.
(library (letloop tea trie)
  (export
   make-trie
   trie?
   trie-state?
   make-trie-state
   trie-state-reset!
   trie-state-bytes
   trie-feed!)
  (import (chezscheme))

  ;; ----- node type --------------------------------------------------------

  (define-record-type trie-node
    (fields (mutable value)
            (mutable children))   ; alist of (byte . trie-node)
    (protocol (lambda (new) (lambda () (new #f '())))))

  ;; ----- trie wrapper -----------------------------------------------------

  (define-record-type (trie %make-trie trie?)
    (fields root))

  ;; ----- build -----------------------------------------------------------

  (define (trie-insert! root byte-string value)
    (let loop ((i 0) (node root))
      (cond
       ((fx=? i (string-length byte-string))
        (when (trie-node-value node)
          (error 'make-trie
                 "duplicate key in trie"
                 byte-string (trie-node-value node)))
        (trie-node-value-set! node value))
       (else
        (let* ((b (char->integer (string-ref byte-string i)))
               (next (cond
                      ((assv b (trie-node-children node)) => cdr)
                      (else
                       (let ((n (make-trie-node)))
                         (trie-node-children-set!
                          node
                          (cons (cons b n) (trie-node-children node)))
                         n)))))
          (loop (fx+ i 1) next))))))

  (define (make-trie pairs)
    ;; pairs : list of (byte-string . value)
    (let ((root (make-trie-node)))
      (for-each (lambda (p) (trie-insert! root (car p) (cdr p))) pairs)
      (%make-trie root)))

  ;; ----- runtime state ----------------------------------------------------

  (define-record-type trie-state
    (fields parent
            (mutable node)
            (mutable bytes))   ; bytes consumed since last reset, in order
    (protocol
     (lambda (new)
       (lambda (t)
         (new t (trie-root t) '())))))

  (define (trie-state-reset! state)
    (trie-state-node-set!  state (trie-root (trie-state-parent state)))
    (trie-state-bytes-set! state '()))

  (define (trie-feed! state byte)
    (let* ((node (trie-state-node state))
           (children (trie-node-children node)))
      (cond
       ((assv byte children) =>
        (lambda (pair)
          (let* ((next (cdr pair))
                 (val  (trie-node-value next)))
            (trie-state-node-set!  state next)
            (trie-state-bytes-set! state (cons byte (trie-state-bytes state)))
            (cond
             (val
              ;; matched a complete key; auto-reset for next sequence
              (trie-state-reset! state)
              (list 'match val))
             ((null? (trie-node-children next))
              ;; matched a leaf with no value — degenerate; treat as no-match
              (trie-state-reset! state)
              'no-match)
             (else 'continue)))))
       (else
        ;; Dead end at this byte.  Caller is expected to call
        ;; trie-state-reset! (or feed bytes through a fallback decoder
        ;; using trie-state-bytes for what was consumed).
        'no-match))))
  )
