(require :hunchentoot)

(defvar *count* 0)

(hunchentoot:define-easy-handler (handle-root :uri "/") ()
  (setf (hunchentoot:content-type*) "text/html; charset=utf-8")
  (format nil "<html><body>
<h1>Count: ~a</h1>
<p>Press Ctrl-C for graceful shutdown</p>
<form method=\"POST\" action=\"/increment\">
<button type=\"submit\">Increment</button>
</form>
<footer><small>Common Lisp | Hunchentoot | SBCL ~a | thread-per-connection</small></footer>
</body></html>" *count* (lisp-implementation-version)))

(hunchentoot:define-easy-handler (handle-increment :uri "/increment") ()
  (when (eq (hunchentoot:request-method*) :post)
    (incf *count*)
    (hunchentoot:redirect "/")))

(hunchentoot:define-easy-handler (handle-sleep :uri "/sleep") ()
  (setf (hunchentoot:content-type*) "text/html; charset=utf-8")
  (sleep 1)
  "<html><body><h1>Slept 1 second (via sleep)</h1></body></html>")

(defun main ()
  (let* ((args sb-ext:*posix-argv*)
         (port (parse-integer (car (last args)))))
    (setf hunchentoot:*show-lisp-errors-p* nil)
    ;; No custom taskmaster: Hunchentoot's acceptor forces
    ;; persistent-connections-p to nil under single-threaded-taskmaster
    ;; (acceptor.lisp), i.e. it disabled HTTP keep-alive — one request
    ;; per TCP connection, a ~3x handicap no other implementation in
    ;; the suite pays. The default one-thread-per-connection taskmaster
    ;; keeps connections alive; bench.sh's taskset -c 0 already pins
    ;; the whole process to one core, which is the fairness constraint
    ;; that matters.
    (let ((acceptor (make-instance 'hunchentoot:easy-acceptor
                                   :port port
                                   :address "127.0.0.1"
                                   :access-log-destination nil
                                   :message-log-destination nil)))
      (hunchentoot:start acceptor)
      (loop (sleep 3600)))))
