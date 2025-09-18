#!chezscheme
(library (binink untangle)

  (export untangle-new
          untangle-abort
          untangle-log
          untangle-run
          untangle-jiffy
          untangle-parallel
          untangle-sleep-nanoseconds
          untangle-spawn
          untangle-spawn-threadsafe
          untangle-stop
          untangle-tcp-serve

          ~check-untangle-000
          ~check-untangle-2001
          ~check-untangle-002
          )

  (import (chezscheme)
          (binink r999)
          (binink cffi))

  (define stdlib (load-shared-object #f))

  (define epoll-event-direction-in #x001)
  (define epoll-event-direction-out #x004)

  (define-ftype epoll-type-data
    (union (ptr void*)
           (fd int)
           (u32 unsigned-32)
           (u64 unsigned-64)))

  (define-ftype epoll-type-event
    (struct (events unsigned-32)
            (data epoll-type-data)))

  (define (epoll-event-new)
    ;; TODO: free
    (make-ftype-pointer epoll-type-event
                        (foreign-alloc
                         (ftype-sizeof epoll-type-event))))

  ;; TODO: IIRC epoll-type-event expire for some reason... and are
  ;; replaced with new ones.  Instead of mutating existing in, out, or
  ;; both both in and out, when necessary the expired event is
  ;; replaced with a new event that is both.

  (define epoll-event-both-new
    (lambda (fd)
      (define fptr
        (make-ftype-pointer epoll-type-event
                            (foreign-alloc
                             (ftype-sizeof epoll-type-event))))
      (ftype-set! epoll-type-event (events) fptr
                  (logior epoll-event-direction-in epoll-event-direction-out))
      (ftype-set! epoll-type-event (data fd) fptr fd)
      fptr))

  (define epoll-event-in-new
    (lambda (fd)
      (define fptr
        (make-ftype-pointer epoll-type-event
                            (foreign-alloc
                             (ftype-sizeof epoll-type-event))))
      (ftype-set! epoll-type-event (events) fptr epoll-event-direction-in)
      (ftype-set! epoll-type-event (data fd) fptr fd)
      fptr))

  (define epoll-event-out-new
    (lambda (fd)
      (define fptr
        (make-ftype-pointer epoll-type-event
                            (foreign-alloc (ftype-sizeof epoll-type-event))))
      (ftype-set! epoll-type-event (events) fptr epoll-event-direction-out)
      (ftype-set! epoll-type-event (data fd) fptr fd)
      fptr))

  (define (epoll-event-fd event)
    (ftype-ref epoll-type-event (data fd) event))

  (define (epoll-event-in? event)
    ;; smaller that (most-positive-fixnum)
    (fx=? (fxlogand (ftype-ref epoll-type-event (events) event)
                    epoll-event-direction-in)
          epoll-event-direction-in))

  (define (epoll-event-out? event)
    ;; idem.
    (fx=? (fxlogand (ftype-ref epoll-type-event (events) event)
                    epoll-event-direction-out)
          epoll-event-direction-out))

  (define epoll-create1
    (let ((func (foreign-procedure "epoll_create1" (int) int)))
      (lambda (flags)
        (func flags))))

  (define epoll-ctl
    (let ((func (foreign-procedure "epoll_ctl" (int int int void*) int)))
      (lambda (epoll op fd event)
        (func epoll op fd (ftype-pointer-address event)))))

  (define epoll-ctl-op=add 1)
  (define epoll-ctl-op=delete 2)
  (define epoll-ctl-op=modify 3)
  
  (define epoll-wait
    (let ([func (foreign-procedure "epoll_wait" (int void* int int) int)])
      (lambda (epoll events max-events timeout)
        ;; TODO: error handling related to errno
        ;; TODO: increase the number of max-events
        (func epoll (ftype-pointer-address events) max-events timeout))))

  ;;
  ;; inspired from https://stackoverflow.com/a/51777980/140837
  ;;
  ;; single thread, single event-loop
  ;;

  ;; TODO: why there is a global mutex like that? it is ugly, and
  ;; forbids the use of several untanglements.
  (define mutex (make-mutex))

  (define pk
    (lambda args
      ;; TODO: replace this with logging
      (when (getenv "BININK_DEBUG_UNTANGLE")
        (display "#;(binink untangle) " (current-error-port))
        (write args (current-error-port))
        (newline (current-error-port))
        (flush-output-port (current-error-port)))
      (car (reverse args))))

  (define untangle-log
    (lambda (level message . objects)
      ;; ah
      (pk level message objects)))

  ;; TODO: that should not be necessary
  (define untangle-current (make-parameter #f))

  (define untangle-prompt-current #f)

  (define socket-error-would-block 11) ;; EWOULDBLOCK
  (define socket-error-try-again)

  (define untangle-prompt-singleton '(untangle-prompt-singleton))

  (define-record-type* <untangle>
    (untangle-base-new jiffy sleeping running epoll events thunks others readable writable)
    untangle?
    ;; current iteration jiffies
    (jiffy untangle-jiffy untangle-jiffy!)
    ;; continuations that sleep until jiffies
    (sleeping untangle-sleeping untangle-sleeping!)
    (running untangle-running? untangle-running!)
    (epoll untangle-epoll)
    ;; split into todo-read, and todo-write
    (events untangle-events)
    ;; continuations that must be run next iteration
    (thunks untangle-thunks untangle-thunks!)
    ;; continuations coming from other POSIX threads
    (others untangle-others untangle-others!)
    ;; readable pipe to notify main thread of new continuations
    (readable untangle-readable)
    ;; the other side of the pipe
    (writable untangle-writable))

  ;; XXX: not sure prompt is the correct wording
  (define call-with-untangle-prompt
    (lambda (thunk handler)
      (call-with-values (lambda ()
                          (call/1cc
                           (lambda (k)
                             ;; XXX: The continuation K aliased as
                             ;; untangle-prompt-current may be called
                             ;; in THUNK during the extent of this
                             ;; lambda.
                             (set! untangle-prompt-current k)
                             (thunk))))
        (lambda out
          (cond
           ((and (pair? out) (eq? (car out) untangle-prompt-singleton))
            (apply handler (cdr out)))
           (else (apply values out)))))))

  (define untangle-abort
    (lambda (untangle . args)
      (call/cc
       (lambda (k)
         ;; XXX: Capture the continuation and call it later, hence
         ;; call/cc instead of call/1cc.
         (let ((prompt untangle-prompt-current))
           (set! untangle-prompt-current #f)
           (apply prompt (cons untangle-prompt-singleton (cons k args))))))))

  (define untangle-event-new cons)
  (define untangle-event-continuation car)
  (define untangle-event-mode cdr)

  (define untangle-apply
    (lambda (untangle thunk)
      ;; log exception, do not bubble up
      (guard (ex (else (pk (apply format #f
                                  (condition-message ex)
                                  (condition-irritants ex)))))
        (call-with-untangle-prompt
         thunk
         (lambda (k handler)
           (handler k))))))

  (define hashtable-empty?
    (lambda (h)
      (fx=? (hashtable-size h) 0)))

  (define current-jiffy
    (lambda ()
      (let* ((time (current-time 'time-monotonic))
             (seconds (time-second time))
             (nanoseconds (time-nanosecond time)))
        (+ (* seconds (expt 10 9)) nanoseconds))))

  (define untangle-run-once
    (lambda (untangle)

      ;; all thunks that were added by main thread in previous
      ;; iteration, that must be run as soon as possible ie. now
      (let ((thunks (untangle-thunks untangle)))
        (untangle-thunks! untangle '())
        (for-each (lambda (thunk) (untangle-apply untangle thunk)) thunks))

      ;; cached for current iteration
      (untangle-jiffy! untangle (current-jiffy))

      ;; continuations sleeping for jiffies
      (call-with-values (lambda ()
                          (sq-split (untangle-sleeping untangle)
                                    (untangle-jiffy untangle)))
        (lambda (before after)
          (unless (sq-empty before)
            (untangle-sleeping! untangle after)
            (skids-for-each (lambda (jiffy thunk) (untangle-apply untangle thunk))))))

      (let ((timeout (if (sq-empty? (untangle-sleeping untangle))
                         -1
                         (- (car (sq-min (untangle-sleeping untangle)))
                            (untangle-jiffy untangle)))))
        ;; Wait for ONE event...
        (let* ((event (make-epoll-event))
               ;; TODO: increase max events from 1 to 1024?
               (count (epoll-wait (untangle-epoll untangle) event 1 timeout)))
          (if (fxzero? count)
              (foreign-free (ftype-pointer-address event))
              (let* ((mode (if (epoll-event-in? event) 'read 'write))
                     (k (hashtable-ref (untangle-events untangle)
                                       (cons (epoll-event-fd event) mode)
                                       #f)))
                (foreign-free (ftype-pointer-address event))
                (hashtable-delete! (untangle-events untangle) event)
                ;; TODO: remove the associated event mode from epoll
                ;; instance?  check man pages for details, it think
                ;; the registred event auto-expired.
                (untangle-apply untangle k)))))))

  (define untangle-watcher
    ;; that will watch for a readable byte in a pipe, the pipe is
    ;; written with the help of a mutex by other threads but the
    ;; mainthread. Then, registred continuations from
    ;; (untangle-others) are appended together to (untangle-thunks) to
    ;; be executed asap.
    (lambda (untangle)
      (when (untangle-running? untangle)
        ;; consume the byte, but do not store, or use it because the
        ;; byte value is meaningless, what matters is that
        ;; untangle-watcher was woked up via epoll because there is
        ;; *something* to read.
        (untangle-read (untangle-readable untangle))

        (let ((new (with-mutex mutex
                     (let ((new (untangle-others (untangle-current))))
                       (untangle-others! (untangle-current) '())
                       new))))
          (untangle-thunks! untangle
                            (append new
                                    (untangle-thunks untangle))))
        ;; loop it
        (untangle-watcher untangle))))

  (define untangle-stop
    (lambda (untangle)
      (untangle-running! untangle #f)))

  (define untangle-run
    (lambda (untangle)
      (untangle-spawn untangle untangle-watcher)
      (let loop ()
        (when (untangle-running? untangle)
          (guard (ex (else (untangle-log 'error
                                         (format #f "Procedure untangle-run, exception: ~a" (condition-message ex))
                                         (condition-irritants ex))
                           (untangle-running! untangle #f)))
            (untangle-run-once untangle))
          (loop)))))

  (define untangle-spawn
    (lambda (untangle thunk)
      (untangle-thunks! untangle
                        (cons thunk (untangle-thunks untangle)))))

  (define untangle-sleep-nanoseconds
    (lambda (untangle nanoseconds)
      (untangle-abort untangle
                      (lambda (k)
                        (untangle-sleeping! untangle
                                            (sq-add (untangle-sleeping untangle)
                                                    (fx+ (untangle-jiffy untangle) nanoseconds)
                                                    k))))))

  (define untangle-spawn-threadsafe
    (lambda (untangle thunk)
      (with-mutex mutex
        (untangle-others! untangle
                          (cons thunk (untangle-others untangle))))
      ;; notify mainthread that there is something to read
      (untangle-write (untangle-writable untangle)
                      (bytevector 26 00))))

  (define untangle-parallel
    ;; execute THUNK in a POSIX thread, and return, and continue in
    ;; mainthread with the result
    (lambda (untangle thunk)
      (untangle-abort untangle
                      (lambda (k)
                        (fork-thread (lambda () (call-with-values thunk
                                                  (lambda args
                                                    (untangle-spawn-threadsafe
                                                     (lambda () (apply k args)))))))))))

  (define fcntl!
    (let ((func (foreign-procedure "fcntl" (int int int) int)))
      (lambda (fd command value)
        (func fd command value))))

  (define fcntl
    (let ((func (foreign-procedure "fcntl" (int int) int)))
      (lambda (fd)
        (func fd untangle-get-flag))))

  (define-ftype <pipe>
    (array 2 int))

  (define untangle-get-flag 3)
  (define untangle-set-flag 4)
  (define untangle-nonblock 2048)

  (define untangle-nonblock!
    (lambda (fd)
      (fcntl! fd untangle-set-flag
              (fxlogior untangle-nonblock
                        (fcntl fd)))))

  (define make-pipe
    (let ((func (foreign-procedure "pipe" (void* int) int)))
      (lambda ()
        (define pointer (foreign-alloc (ftype-sizeof <pipe>)))
        (call-with-errno (lambda () (func pointer 0))
          (lambda (out errno)
            (when (fx=? out -1)
              (error 'letloop-untangle-make-pipe (strerror errno)))))
        (let ((pipe (make-ftype-pointer <pipe> pointer)))
          (let ((readable (ftype-ref <pipe> (0) pipe))
                (writable (ftype-ref <pipe> (1) pipe)))
            (foreign-free pointer)
            (values readable writable))))))

  (define untangle-new
    (lambda ()
      (untangle-log 'notice "Making an untanglement...")
      (call-with-values make-pipe
        (lambda (readable writable)
          (untangle-nonblock! readable)
          (untangle-nonblock! writable)
          ;; zero just means no flag in particular.
          (let ((epoll (epoll-create1 0))
                (events (make-hashtable equal-hash equal?)))
            (untangle-base-new (current-jiffy)
                               (fxmapping)
                               #t
                               epoll
                               events
                               '()
                               '()
                               readable
                               writable))))))

  (define untangle-socket
    (let ((untangle-socket-foreign (foreign-procedure "socket" (int int int) int)))
      (lambda (domain type protocol)
        (define out (untangle-socket-foreign domain type protocol))
        (untangle-nonblock! out)
        out)))

  (define untangle-accept-base
    (let ((untangle-socket-accept4 (foreign-procedure "accept4" (int void* void* int) int))
          ;; using the following flags value will save extra calls to
          ;; fcntl to make the accepted fd non blocking.
          (flags=SOCK_NONBLOCK 2048))
      (lambda (fd)
        (untangle-socket-accept4 fd 0 0 flags=SOCK_NONBLOCK))))

  (define untangle-update-epoll
    (let ((op=EPOLL_CTL_ADD 1)
          (op=EPOLL_CTL_DEL 2)
          (op=EPOLL_CTL_MOD 3))
      ;; TODO: I think this code or the calling code is buggy
      (lambda (untangle fd mode)
        (if (hashtable-ref untangle
                           (cons fd (if (eq? mode 'read) 'write 'read))
                           #f)
            (epoll-ctl untangle
                       op=EPOLL_CTL_MOD
                       fd
                       (make-epoll-event-out fd))
            (epoll-ctl untangle
                       op=EPOLL_CTL_DEL
                       fd
                       (make-epoll-event-out fd))))))

  (define untangle-accept
    (lambda (untangle fd)

      (define accept-handler
        (lambda (k)
          (hashtable-set! (untangle-events untangle)
                          (cons fd 'read)
                          k)
          (epoll-ctl (untangle-epoll untangle)
                     1
                     fd
                     (epoll-event-in-new fd))))

      (let loop ()
        (let-values ((out errno) (call-with-errno (lambda () (untangle-accept-base fd))))
          (cond
           ;; it would block, then try again later thanks to epoll
           ((and (fx=? out -1) (fx=? errno socket-error-would-block))
            (untangle-abort accept-handler)
            (loop))
           ;; some kind of error, b
           ((fx=? out -1)
            (untangle-log 'error
                          (format #f "Procedure untangle-accept, errno: ~a"
                                  (strerror errno)
                                  fd))
            #f)
           ;; success, out is a valid file description for a client connection
           (else out))))))

  (define untangle-close
    (let ((untangle-close-foreign (foreign-procedure "close" (int) int)))
      (lambda (fd)
        ;; TODO: error handling
        (untangle-close-foreign fd))))

  (define untangle-socket-option!
    (let ((untangle-socket-option-foreign! (foreign-procedure "setsockopt" (int int int void* int) int)))
      (lambda (fd level optname optval)

        (define (doit opt-int)
          (let* ((size (ftype-sizeof int))
                 (pointer (foreign-alloc size)))
            (foreign-set! 'int pointer 0 (if optval 1 0))
            (call-with-errno (lambda () (untangle-socket-option-foreign! fd level opt-int pointer size))
              (lambda (out errno)
                (foreign-free pointer)
                (if (fxzero? out)
                    #t
                    (error 'untangle
                           (format #f "Procedure untangle-socket-option! errno ~a" (strerror errno))
                           fd))))))

        (case optname
          ;; based on /usr/include/asm-generic/socket.h
          ((socket-option/debug) (bool 1))
          ((socket-option/reuseaddr) (bool 2))
          ((socket-option/dontroute) (bool 5))
          ((socket-option/broadcast) (bool 6))
          ;;((socket-option/sndbuf) (int 7))
          ;;((socket-option/rcvbuf) (int 8))
          ((socket-option/keepalive) (bool 9))
          ((socket-option/oobinline) (bool 10))
          ((socket-option/reuseport) (bool 15))
          ;;((socket-option/rcvlowat) (int 18))
          ;;((socket-option/sndlowat) (int 19))
          (else (error 'untangle "Procedure untangle-socket-option! unknown socket option" fd level optname optval))))))

  (define untangle-bind
    (let ((untangle-bind-foreign (foreign-procedure "bind" (int void* size_t) int)))
      (lambda (fd ip port)

        (define string->ipv4
          (lambda (string)

            (define (ipv4 one two three four)
              (+ (* one 256 256 256)
                 (* two 256 256)
                 (* three 256)
                 four))

            (define make-char-predicate
              (lambda (char)
                (lambda (other)
                  (char=? char other))))

            ;; taken from https://cookbook.scheme.org/split-string/
            (define (string-split char-delimiter? string)
              (define (maybe-add a b parts)
                (if (= a b) parts (cons (substring string a b) parts)))
              (let ((n (string-length string)))
                (let loop ((a 0) (b 0) (parts '()))
                  (if (< b n)
                      (if (not (char-delimiter? (string-ref string b)))
                          (loop a (+ b 1) parts)
                          (loop (+ b 1) (+ b 1) (maybe-add a b parts)))
                      (reverse (maybe-add a b parts))))))

            (apply ipv4 (map string->number
                             (string-split (make-char-predicate #\.)
                                           string)))))

        (define-ftype <socket-address-in>
          (struct (family unsigned-short)
                  (port (endian big unsigned-16))
                  (address (endian big unsigned-32))
                  (padding (array 8 char))))

        (define (socket-address-in-new ip port)
          (let* ((pointer (foreign-alloc (ftype-sizeof <socket-address-in>)))
                 (address (make-ftype-pointer <socket-address-in> pointer)))
            ;; create socket FAMILY=inet
            (ftype-set! <socket-address-in> (family) address 2)
            (ftype-set! <socket-address-in> (port) adress port)
            (ftype-set! <socket-address-in> (address) address (string->ipv4 ip))
            (values pointer address)))

        ;; configure socket to reuse ip adress, and port
        (untangle-socket-option! fd 1 'socket-option/reuseaddr #t)
        (untangle-socket-option! fd 1 'socket-option/reuseport #t)

        ;; convert ip string, and port into a <socket-address-in>, and
        ;; bind socket fd
        (call-with-values (lambda () (socket-address-in-new ip port))
          (lambda (pointer address)
            (call-with-errno (lambda ()
                               (untangle-bind-foreign fd
                                                      address
                                                      (ftype-sizeof <socket-address-in>)))
              (lambda (out errno)
                (foreign-free pointer)
                (unless (fxzero? out)
                  (error 'untangle (format #f "Procedure untangle-bind, errno ~a" (strerror errno)))))))))))

  (define untangle-listen
    (let ((untangle-listen-foreign (foreign-procedure "listen" (int int) int)))
      (lambda (fd backlog)
        (call-with-errno (lambda () (untangle-listen-foreign fd backlog))
          (lambda (out errno)
            (unless (fxzero? out)
              (error 'untangle (format #f "Procedure untangle-listen, errno ~a" (strerror errno)))))))))

  (define subbytevector
    (case-lambda
     ((bv start end)
      (assert (bytevector? bv))
      (unless (<= 0 start end (bytevector-length bv))
        (error 'subbytevector "Invalid indices: ~a ~a ~a" bv start end))
      (if (and (fxzero? start)
               (fx=? end (bytevector-length bv)))
          bv
          (let ((ret (make-bytevector (fx- end start))))
            (bytevector-copy! bv start
                              ret 0 (fx- end start))
            ret)))
     ((bv start)
      (subbytevector bv start (bytevector-length bv)))))
  
  (define untangle-read
    (let ((untangle-read-foreign
           (foreign-procedure "read" (int void* size_t) ssize_t)))
      (lambda (untangle fd)

        (define func
          (lambda (fd bytevector)
            (with-lock (list bytevector)
              (call-with-errno
                  (lambda ()
                    (untangle-read-foreign fd
                                           (bytevector-pointer bytevector)
                                           (bytevector-length bytevector)))
                (lambda args (apply values args))))))

        (define bv (make-bytevector 1024))

        (define handler
          (lambda (k)
            (hashtable-set! (untangle-events untangle)
                            (cons fd 'read)
                            k)
            ;; TODO: replace with epoll-ctl-update, because the fd
            ;; might always be registred
            (epoll-ctl (untangle-epoll untangle)
                       epoll-ctl-op=add
                       fd
                       (epoll-event-in-new fd))))

        (let loop ()
          (let-values ((out errno) (func fd bytevector))
            (cond
             ;; that would block, then retry later via epoll
             ((and (fx=? out -1) (fx=? errno socket-error-would-block))
              (untangle-abort handler)
              (loop))
             ((fx=? out -1)
              ;; XXX: TODO: implement better error handling to be able
              ;; to make a difference between several errnos
              (untangle-log 'error
                            (format #f "Procedure untangle-read, errno: ~a"
                                    (strerror errno)
                                    fd))
              #f)
             ;; end of file
             ((fxzero? out) #t)
             (else (subbytevector bv 0 out))))))))

  (define untangle-write
    (let ((untangle-write-foreign
           (foreign-procedure "write" (int void* size_t) ssize_t)))
      (lambda (untangle fd bytevector)
        
        (define func
          (lambda (fd bytevector)
            (with-lock (list bytevector)
              (untangle-write fd
                              (bytevector-pointer bytevector)
                              (bytevector-length bytevector)))))

        (define handler
          (lambda (k)
            (hashtable-set! (untangle-events untangle)
                            (cons fd 'write)
                            k)
            ;; fix this, because epoll-ctl-op=mod depends on whether
            ;; the fd was already in epoll, see man pages for actual
            ;; knowledge. Also it is different for untangle-read
            (epoll-ctl (untangle-epoll untangle)
                       epoll-ctl-op=modify
                       fd
                       ;; TODO: it should be epoll-event-both-new?
                       (epoll-event-out-new fd))))
        
        (let loop ((bytevector bytevector)
                   (remaining (bytevector-length bytevector)))
          (let-values ((out errno) (call-with-errno (lambda () (untangle-write-base fd bv))
                                     (lambda (out errno) (values out errno))))
            (cond
             ((and (fx=? out -1) (fx=? errno socket-error-would-block))
              (untangle-abort handler)
              (loop bytevector))
             ((fx=? out -1)
              ;; XXX: TODO: implement better error handling to be able
              ;; to make a difference between several errnos
              (untangle-log 'error
                            (format #f "Procedure untangle-read, errno: ~a"
                                    (strerror errno)
                                    fd))
              #f)
             (else (if (fx=? out (bytevector-length bytevector))
                       #t
                       (loop (subbytevector bytevector
                                            out
                                            (bytevector-length bytevector)))))))))))

  (define untangle-tcp-serve
    (lambda (untangle ip port)
      (define SOCKET-DOMAIN=AF-INET 2)
      (define SOCKET-TYPE=STREAM 1)
      (define fd (untangle-socket SOCKET-DOMAIN=AF-INET SOCKET-TYPE=STREAM 0))

      (define accept
        (lambda ()
          (define client (untangle-accept untangle fd))
          (if (not client)
              ;; XXX: TODO: here having a reason for the error, would be useful?
              (values #f #f #f)
              (values (lambda () (untangle-read untangle client))
                      (lambda (bv) (untangle-write untangle client bv))
                      (lambda () (untangle-close client))))))

      (untangle-bind fd ip port)
      ;; XXX: magic number 128
      (untangle-listen fd 128)

      (values accept (lambda () (untangle-close fd)))))

  (define ~check-untangle-000
    (lambda ()
      (< 3 (with-jiffies
            (make-untangle)
            (untangle-spawn (lambda ()
                              (untangle-sleep-jiffies (* 4 (expt 10 9)))
                              (untangle-stop)))
            (untangle-run)))))

  (define fib
    (lambda (n)
      (cond
       ((= n 0) 0)
       ((= n 1) 1)
       (else (+ (fib (- n 1))
                (fib (- n 2)))))))

  (define ~check-untangle-001
    (lambda ()
      ;; check that untangle-parallel let other lambda to run in the
      ;; main thread.
      (> (let ()
           (define inc 0)
           (define a #f)
           (define b #f)
           (make-untangle)
           (untangle-spawn
            (lambda ()
              (let loop ()
                (set! inc (+ inc 1))
                (untangle-sleep-jiffies (expt 10 3))
                (loop))))
           (untangle-spawn
            (lambda ()
              (set! a (untangle-parallel (lambda () (fib 21))))
              (set! b (untangle-parallel (lambda () (fib 21))))
              (untangle-stop)))
           (untangle-run)
           inc)
         (let ()
           (define inc 0)
           (define a #f)
           (define b #f)
           (make-untangle)
           (untangle-spawn
            (lambda ()
              (let loop ()
                (set! inc (+ inc 1))
                (untangle-sleep-jiffies (expt 10 6))
                (loop))))
           (untangle-spawn
            (lambda ()
              (set! a (fib 21))
              (set! b (fib 21))
              (untangle-stop)))
           (untangle-run)
           inc))))

  (define ~check-untangle-002
    (lambda ()
      (define expected (bytevector 1 2 3 4 5 6 7 8 9 10 11 12 13))
      (make-untangle)
      (untangle-spawn
       (lambda ()
         (define fd (untangle-open "check-untangle-002-0" (list 'untangle-file-create 'untangle-file-read-write)))
         (assert (= 0 (untangle-bytes fd)))
         (assert (= 0 (bytevector-length (untangle-pread fd 0 13))))
         (untangle-pwrite fd 0 expected)
         (untangle-sync fd 0 13)
         (assert (= 13 (untangle-bytes fd)))
         (assert (equal? expected (untangle-pread fd 0 13)))
         (untangle-stop)))
      (untangle-run)
      #t))

  )
