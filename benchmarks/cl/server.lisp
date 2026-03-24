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
<footer><small>Common Lisp | Hunchentoot | SBCL ~a | single-threaded</small></footer>
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
    (let ((acceptor (make-instance 'hunchentoot:easy-acceptor
                                   :port port
                                   :address "127.0.0.1"
                                   :access-log-destination nil
                                   :message-log-destination nil
                                   :taskmaster (make-instance 'hunchentoot:single-threaded-taskmaster))))
      (hunchentoot:start acceptor)
      (loop (sleep 3600)))))
