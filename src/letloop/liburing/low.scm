#!chezscheme
(library (letloop liburing low)
  (export

   ;; shared object
   liburing-ffi

   ;; struct sizes
   io-uring-size
   io-uring-sqe-size
   io-uring-cqe-size
   io-uring-params-size
   kernel-timespec-size

   ;; helpers
   make-timespec
   make-io-uring
   make-io-uring-params
   make-cqe-pointer

   ;; queue lifecycle
   io-uring-queue-init
   io-uring-queue-init-params
   io-uring-queue-exit
   io-uring-queue-mmap

   ;; sqe acquisition
   io-uring-get-sqe

   ;; submission
   io-uring-submit
   io-uring-submit-and-wait
   io-uring-submit-and-wait-timeout
   io-uring-submit-and-get-events

   ;; completion waiting
   io-uring-wait-cqe
   io-uring-wait-cqe-nr
   io-uring-wait-cqe-timeout
   io-uring-wait-cqes
   io-uring-peek-cqe
   io-uring-peek-batch-cqe

   ;; completion processing
   io-uring-cqe-seen
   io-uring-cq-advance
   io-uring-cqe-get-data
   io-uring-cqe-get-data64
   io-uring-cqe-get-res
   io-uring-cqe-get-flags

   ;; sqe configuration
   io-uring-sqe-set-data
   io-uring-sqe-set-data64
   io-uring-sqe-set-flags
   io-uring-sqe-set-buf-group

   ;; ring state queries
   io-uring-sq-ready
   io-uring-sq-space-left
   io-uring-cq-ready
   io-uring-cq-has-overflow
   io-uring-get-events

   ;; prep: nop
   io-uring-prep-nop

   ;; prep: read/write
   io-uring-prep-read
   io-uring-prep-write
   io-uring-prep-readv
   io-uring-prep-writev
   io-uring-prep-readv2
   io-uring-prep-writev2
   io-uring-prep-read-fixed
   io-uring-prep-write-fixed
   io-uring-prep-read-multishot

   ;; prep: socket operations
   io-uring-prep-socket
   io-uring-prep-socket-direct
   io-uring-prep-socket-direct-alloc
   io-uring-prep-connect
   io-uring-prep-bind
   io-uring-prep-listen
   io-uring-prep-accept
   io-uring-prep-accept-direct
   io-uring-prep-multishot-accept
   io-uring-prep-multishot-accept-direct
   io-uring-prep-shutdown

   ;; prep: send/recv
   io-uring-prep-send
   io-uring-prep-send-bundle
   io-uring-prep-send-set-addr
   io-uring-prep-sendto
   io-uring-prep-send-zc
   io-uring-prep-send-zc-fixed
   io-uring-prep-recv
   io-uring-prep-recv-multishot
   io-uring-prep-sendmsg
   io-uring-prep-sendmsg-zc
   io-uring-prep-recvmsg
   io-uring-prep-recvmsg-multishot

   ;; prep: file operations
   io-uring-prep-openat
   io-uring-prep-openat-pointer
   io-uring-prep-openat-direct
   io-uring-prep-open
   io-uring-prep-open-direct
   io-uring-prep-close
   io-uring-prep-close-direct
   io-uring-prep-read-fixed
   io-uring-prep-write-fixed
   io-uring-prep-fsync
   io-uring-prep-sync-file-range
   io-uring-prep-fallocate
   io-uring-prep-ftruncate
   io-uring-prep-statx
   io-uring-prep-fadvise
   io-uring-prep-madvise
   io-uring-prep-splice
   io-uring-prep-tee

   ;; prep: filesystem operations
   io-uring-prep-renameat
   io-uring-prep-rename
   io-uring-prep-unlinkat
   io-uring-prep-unlink
   io-uring-prep-mkdirat
   io-uring-prep-mkdir
   io-uring-prep-symlinkat
   io-uring-prep-symlink
   io-uring-prep-linkat
   io-uring-prep-link

   ;; prep: xattr
   io-uring-prep-getxattr
   io-uring-prep-setxattr
   io-uring-prep-fgetxattr
   io-uring-prep-fsetxattr

   ;; prep: timeout
   io-uring-prep-timeout
   io-uring-prep-timeout-remove
   io-uring-prep-timeout-update
   io-uring-prep-link-timeout

   ;; prep: cancel
   io-uring-prep-cancel
   io-uring-prep-cancel64
   io-uring-prep-cancel-fd

   ;; prep: poll
   io-uring-prep-poll-add
   io-uring-prep-poll-multishot
   io-uring-prep-poll-remove
   io-uring-prep-poll-update

   ;; prep: msg ring
   io-uring-prep-msg-ring
   io-uring-prep-msg-ring-cqe-flags
   io-uring-prep-msg-ring-fd
   io-uring-prep-msg-ring-fd-alloc

   ;; prep: provide/remove buffers
   io-uring-prep-provide-buffers
   io-uring-prep-remove-buffers

   ;; prep: epoll
   io-uring-prep-epoll-ctl

   ;; prep: misc
   io-uring-prep-files-update
   io-uring-prep-fixed-fd-install
   io-uring-prep-cmd-sock
   io-uring-prep-waitid
   io-uring-prep-futex-wait
   io-uring-prep-futex-wake
   io-uring-prep-futex-waitv

   ;; prep: low-level
   io-uring-prep-rw

   ;; registration
   io-uring-register-buffers
   io-uring-unregister-buffers
   io-uring-register-buffers-sparse
   io-uring-register-buffers-tags
   io-uring-register-buffers-update-tag
   io-uring-register-files
   io-uring-unregister-files
   io-uring-register-files-sparse
   io-uring-register-files-tags
   io-uring-register-files-update
   io-uring-register-files-update-tag
   io-uring-register-eventfd
   io-uring-register-eventfd-async
   io-uring-unregister-eventfd
   io-uring-register-probe
   io-uring-register-personality
   io-uring-unregister-personality
   io-uring-register-restrictions
   io-uring-enable-rings
   io-uring-register-iowq-max-workers
   io-uring-register-ring-fd
   io-uring-unregister-ring-fd
   io-uring-close-ring-fd
   io-uring-register-buf-ring
   io-uring-unregister-buf-ring
   io-uring-register-sync-cancel
   io-uring-register-file-alloc-range
   io-uring-register-napi
   io-uring-unregister-napi

   ;; buf ring helpers
   io-uring-setup-buf-ring
   io-uring-free-buf-ring
   io-uring-buf-ring-init
   io-uring-buf-ring-add
   io-uring-buf-ring-advance
   io-uring-buf-ring-cq-advance
   io-uring-buf-ring-mask
   io-uring-buf-ring-available

   ;; probe
   io-uring-get-probe
   io-uring-get-probe-ring
   io-uring-free-probe
   io-uring-opcode-supported

   ;; misc
   io-uring-ring-dontfork
   io-uring-sqring-wait
   io-uring-check-version
   io-uring-major-version
   io-uring-minor-version

   ;; syscalls
   io-uring-setup
   io-uring-enter
   io-uring-enter2
   io-uring-register

   ;; recvmsg helpers
   io-uring-recvmsg-validate
   io-uring-recvmsg-name
   io-uring-recvmsg-payload
   io-uring-recvmsg-payload-length
   io-uring-recvmsg-cmsg-firsthdr
   io-uring-recvmsg-cmsg-nexthdr

   ;; constants: sqe flags
   IOSQE_FIXED-FILE
   IOSQE-IO-DRAIN
   IOSQE-IO-LINK
   IOSQE-IO-HARDLINK
   IOSQE-ASYNC
   IOSQE-BUFFER-SELECT
   IOSQE-CQE-SKIP-SUCCESS

   ;; constants: setup flags
   IORING-SETUP-IOPOLL
   IORING-SETUP-SQPOLL
   IORING-SETUP-SQ-AFF
   IORING-SETUP-CQSIZE
   IORING-SETUP-CLAMP
   IORING-SETUP-ATTACH-WQ
   IORING-SETUP-R-DISABLED
   IORING-SETUP-SUBMIT-ALL
   IORING-SETUP-COOP-TASKRUN
   IORING-SETUP-TASKRUN-FLAG
   IORING-SETUP-SQE128
   IORING-SETUP-CQE32
   IORING-SETUP-SINGLE-ISSUER
   IORING-SETUP-DEFER-TASKRUN
   IORING-SETUP-NO-MMAP
   IORING-SETUP-REGISTERED-FD-ONLY
   IORING-SETUP-NO-SQARRAY

   ;; constants: cqe flags
   IORING-CQE-F-BUFFER
   IORING-CQE-F-MORE
   IORING-CQE-F-SOCK-NONEMPTY
   IORING-CQE-F-NOTIF
   IORING-CQE-F-BUF-MORE

   ;; constants: timeout flags
   IORING-TIMEOUT-ABS
   IORING-TIMEOUT-UPDATE
   IORING-TIMEOUT-BOOTTIME
   IORING-TIMEOUT-REALTIME
   IORING-TIMEOUT-ETIME-SUCCESS
   IORING-TIMEOUT-MULTISHOT

   ;; constants: async cancel flags
   IORING-ASYNC-CANCEL-ALL
   IORING-ASYNC-CANCEL-FD
   IORING-ASYNC-CANCEL-ANY
   IORING-ASYNC-CANCEL-FD-FIXED
   IORING-ASYNC-CANCEL-USERDATA
   IORING-ASYNC-CANCEL-OP

   ;; constants: fsync
   IORING-FSYNC-DATASYNC

   ;; constants: accept
   IORING-ACCEPT-MULTISHOT
   IORING-ACCEPT-DONTWAIT
   IORING-ACCEPT-POLL-FIRST

   ;; constants: recv/send
   IORING-RECVSEND-POLL-FIRST
   IORING-RECV-MULTISHOT
   IORING-RECVSEND-FIXED-BUF
   IORING-RECVSEND-BUNDLE

   ;; constants: msg ring
   IORING-MSG-RING-CQE-SKIP
   IORING-MSG-RING-FLAGS-PASS

   ;; constants: poll
   IORING-POLL-ADD-MULTI
   IORING-POLL-UPDATE-EVENTS
   IORING-POLL-UPDATE-USER-DATA
   IORING-POLL-ADD-LEVEL

   ;; constants: splice
   SPLICE-F-FD-IN-FIXED

   ;; constants: file index alloc
   IORING-FILE-INDEX-ALLOC

   ;; constants: sync_file_range
   SYNC-FILE-RANGE-WRITE-AND-WAIT

   ;; C stdlib + FFI helpers
   stdlib bytevector-pointer with-lock strerror pointer->string memcpy

   ;; socket constants
   AF-INET SOCK-STREAM F-GETFL F-SETFL O-NONBLOCK POLLIN POLLOUT

   ;; fcntl / non-blocking
   fcntl fcntl! loop-nonblock!

   ;; sockaddr_in ftype and helpers
   <sockaddr-in> string->ipv4 make-sockaddr-in

   ;; socket syscall wrappers
   loop-socket-new loop-socket-option! loop-socket-error?
   loop-bind loop-listen loop-getpeername

   ;; bytevector utility
   subbytevector

   ;; event loop record type
   <loop>

   ;; time
   jiffy-current

   ;; event loop lifecycle
   loop-new loop-run loop-run-once loop-stop loop-spawn

   ;; loop internals, for libraries extending the loop with new
   ;; operations (e.g. (letloop dns)): current loop, its ring, the
   ;; completion-handler table, id allocation, coroutine abort
   loop-current loop-ring loop-handlers loop-alloc-id! loop-abort
   loop-running? loop-active-connections loop-get-sqe

   ;; provided-buffer-ring accessors, for libraries (e.g. (letloop
   ;; flow)'s flow-read) that want the zero-per-call-allocation recv
   ;; path loop-read already uses instead of a private bytevector
   loop-buf-ring-bgid loop-buf-ring-buf-size loop-buf-data-take!

   ;; per-tick cached timestamp: refreshed once per loop-run-once
   ;; iteration (one jiffy-current syscall per tick) rather than once
   ;; per caller, for libraries (e.g. (letloop flow)'s flow-log) that
   ;; want a "when, roughly" timestamp far more often than once per
   ;; tick
   loop-jiffy

   ;; async I/O operations
   loop-connect loop-connect-timeout-seconds
   loop-read loop-write loop-close loop-sleep
   loop-accept loop-tcp-serve loop-poll-wait

   ;; accept split into its non-blocking poll and its multishot
   ;; registration, for libraries (e.g. (letloop flow)) that need to
   ;; race accept against other events instead of always suspending
   ;; the caller until a client arrives
   loop-accept-try loop-accept-block

   ;; the same backlog, for the recv side: a payload whose waiter lost
   ;; its choice cannot be handed back to the kernel, so it is stashed
   ;; per fd and purged with the fd
   loop-recv-backlog-put! loop-recv-backlog-take!

   ;; the per-fd operation index loop-close-prep! tears down, for
   ;; libraries that build their own SQEs instead of calling loop-read
   ;; and loop-write -- a socket operation NOT in this index outlives
   ;; the close of its fd
   loop-fd-op-add! loop-fd-op-remove!

   ;; close split the same way, for libraries that need close to be an
   ;; event they can compose rather than an unconditional suspension
   loop-close-block

   ~check-low-000/resumed-return-does-not-rerun-sibling
   ~check-low-001/two-suspends-then-return
   ~check-low-002/non-suspending-fibers-run-once
   ~check-low-003/resumed-return-does-not-rerun-late-spawn
   ~check-low-004/handlerless-buffered-cqe-not-retained
   )

  (import (chezscheme)
          (only (letloop cffi) define-shared-object lazy-foreign-procedure
                with-lock bytevector-pointer strerror)
          (letloop r999))

  ;;------------------------------------------------------------
  ;; Load shared object
  ;;------------------------------------------------------------

  (define-shared-object liburing-ffi "liburing-ffi.so.2" "liburing-ffi.so")

  ;;------------------------------------------------------------
  ;; Struct sizes (x86_64)
  ;;------------------------------------------------------------

  (define io-uring-size 216)
  (define io-uring-sqe-size 64)
  (define io-uring-cqe-size 16)
  (define io-uring-params-size 120)
  (define kernel-timespec-size 16)

  ;;------------------------------------------------------------
  ;; Ftype definitions
  ;;------------------------------------------------------------

  (define-ftype <kernel-timespec>
    (struct
     (seconds long-long)
     (nanoseconds long-long)))

  (define-ftype <cqe>
    (struct
     (user-data unsigned-64)
     (res integer-32)
     (flags unsigned-32)))

  ;;------------------------------------------------------------
  ;; Allocation helpers
  ;;------------------------------------------------------------

  (define make-timespec
    (lambda (seconds nanoseconds)
      (define out (make-ftype-pointer
                   <kernel-timespec>
                   (foreign-alloc (ftype-sizeof <kernel-timespec>))))
      (ftype-set! <kernel-timespec> (seconds) out seconds)
      (ftype-set! <kernel-timespec> (nanoseconds) out nanoseconds)
      out))

  (define make-io-uring
    (lambda ()
      (foreign-alloc io-uring-size)))

  (define make-io-uring-params
    (lambda ()
      (let ((p (foreign-alloc io-uring-params-size)))
        ;; zero-initialize
        (let loop ((i 0))
          (when (< i io-uring-params-size)
            (foreign-set! 'unsigned-8 p i 0)
            (loop (+ i 1))))
        p)))

  (define make-cqe-pointer
    (lambda ()
      (foreign-alloc 8)))

  ;;------------------------------------------------------------
  ;; Constants: sqe flags
  ;;------------------------------------------------------------

  (define IOSQE_FIXED-FILE       (bitwise-arithmetic-shift-left 1 0))
  (define IOSQE-IO-DRAIN         (bitwise-arithmetic-shift-left 1 1))
  (define IOSQE-IO-LINK          (bitwise-arithmetic-shift-left 1 2))
  (define IOSQE-IO-HARDLINK      (bitwise-arithmetic-shift-left 1 3))
  (define IOSQE-ASYNC            (bitwise-arithmetic-shift-left 1 4))
  (define IOSQE-BUFFER-SELECT    (bitwise-arithmetic-shift-left 1 5))
  (define IOSQE-CQE-SKIP-SUCCESS (bitwise-arithmetic-shift-left 1 6))

  ;; constants: setup flags
  (define IORING-SETUP-IOPOLL          (bitwise-arithmetic-shift-left 1 0))
  (define IORING-SETUP-SQPOLL          (bitwise-arithmetic-shift-left 1 1))
  (define IORING-SETUP-SQ-AFF          (bitwise-arithmetic-shift-left 1 2))
  (define IORING-SETUP-CQSIZE          (bitwise-arithmetic-shift-left 1 3))
  (define IORING-SETUP-CLAMP           (bitwise-arithmetic-shift-left 1 4))
  (define IORING-SETUP-ATTACH-WQ       (bitwise-arithmetic-shift-left 1 5))
  (define IORING-SETUP-R-DISABLED      (bitwise-arithmetic-shift-left 1 6))
  (define IORING-SETUP-SUBMIT-ALL      (bitwise-arithmetic-shift-left 1 7))
  (define IORING-SETUP-COOP-TASKRUN    (bitwise-arithmetic-shift-left 1 8))
  (define IORING-SETUP-TASKRUN-FLAG    (bitwise-arithmetic-shift-left 1 9))
  (define IORING-SETUP-SQE128          (bitwise-arithmetic-shift-left 1 10))
  (define IORING-SETUP-CQE32           (bitwise-arithmetic-shift-left 1 11))
  (define IORING-SETUP-SINGLE-ISSUER   (bitwise-arithmetic-shift-left 1 12))
  (define IORING-SETUP-DEFER-TASKRUN   (bitwise-arithmetic-shift-left 1 13))
  (define IORING-SETUP-NO-MMAP         (bitwise-arithmetic-shift-left 1 14))
  (define IORING-SETUP-REGISTERED-FD-ONLY (bitwise-arithmetic-shift-left 1 15))
  (define IORING-SETUP-NO-SQARRAY      (bitwise-arithmetic-shift-left 1 16))

  ;; constants: cqe flags
  (define IORING-CQE-F-BUFFER       (bitwise-arithmetic-shift-left 1 0))
  (define IORING-CQE-F-MORE         (bitwise-arithmetic-shift-left 1 1))
  (define IORING-CQE-F-SOCK-NONEMPTY (bitwise-arithmetic-shift-left 1 2))
  (define IORING-CQE-F-NOTIF        (bitwise-arithmetic-shift-left 1 3))
  (define IORING-CQE-F-BUF-MORE     (bitwise-arithmetic-shift-left 1 4))

  ;; constants: timeout flags
  (define IORING-TIMEOUT-ABS           (bitwise-arithmetic-shift-left 1 0))
  (define IORING-TIMEOUT-UPDATE        (bitwise-arithmetic-shift-left 1 1))
  (define IORING-TIMEOUT-BOOTTIME      (bitwise-arithmetic-shift-left 1 2))
  (define IORING-TIMEOUT-REALTIME      (bitwise-arithmetic-shift-left 1 3))
  (define IORING-TIMEOUT-ETIME-SUCCESS (bitwise-arithmetic-shift-left 1 5))
  (define IORING-TIMEOUT-MULTISHOT     (bitwise-arithmetic-shift-left 1 6))

  ;; constants: fsync
  (define IORING-FSYNC-DATASYNC (bitwise-arithmetic-shift-left 1 0))

  ;; constants: async cancel
  (define IORING-ASYNC-CANCEL-ALL      (bitwise-arithmetic-shift-left 1 0))
  (define IORING-ASYNC-CANCEL-FD       (bitwise-arithmetic-shift-left 1 1))
  (define IORING-ASYNC-CANCEL-ANY      (bitwise-arithmetic-shift-left 1 2))
  (define IORING-ASYNC-CANCEL-FD-FIXED (bitwise-arithmetic-shift-left 1 3))
  (define IORING-ASYNC-CANCEL-USERDATA (bitwise-arithmetic-shift-left 1 4))
  (define IORING-ASYNC-CANCEL-OP       (bitwise-arithmetic-shift-left 1 5))

  ;; constants: accept
  (define IORING-ACCEPT-MULTISHOT   (bitwise-arithmetic-shift-left 1 0))
  (define IORING-ACCEPT-DONTWAIT    (bitwise-arithmetic-shift-left 1 1))
  (define IORING-ACCEPT-POLL-FIRST  (bitwise-arithmetic-shift-left 1 2))

  ;; constants: recv/send
  (define IORING-RECVSEND-POLL-FIRST (bitwise-arithmetic-shift-left 1 0))
  (define IORING-RECV-MULTISHOT      (bitwise-arithmetic-shift-left 1 1))
  (define IORING-RECVSEND-FIXED-BUF  (bitwise-arithmetic-shift-left 1 2))
  (define IORING-RECVSEND-BUNDLE     (bitwise-arithmetic-shift-left 1 4))

  ;; constants: poll
  (define IORING-POLL-ADD-MULTI       (bitwise-arithmetic-shift-left 1 0))
  (define IORING-POLL-UPDATE-EVENTS   (bitwise-arithmetic-shift-left 1 1))
  (define IORING-POLL-UPDATE-USER-DATA (bitwise-arithmetic-shift-left 1 2))
  (define IORING-POLL-ADD-LEVEL       (bitwise-arithmetic-shift-left 1 3))

  ;; constants: msg ring
  (define IORING-MSG-RING-CQE-SKIP   (bitwise-arithmetic-shift-left 1 0))
  (define IORING-MSG-RING-FLAGS-PASS  (bitwise-arithmetic-shift-left 1 1))

  ;; constants: splice
  (define SPLICE-F-FD-IN-FIXED (bitwise-arithmetic-shift-left 1 31))

  ;; constants: file index alloc
  (define IORING-FILE-INDEX-ALLOC #xFFFFFFFF)

  ;; constants: sync_file_range
  (define SYNC-FILE-RANGE-WRITE-AND-WAIT 7)

  ;;------------------------------------------------------------
  ;; Queue lifecycle
  ;;------------------------------------------------------------

  (define io-uring-queue-init
    (let ((func (lazy-foreign-procedure liburing-ffi "io_uring_queue_init"
                                   (unsigned void* unsigned) int)))
      (lambda (entries ring flags)
        (func entries ring flags))))

  (define io-uring-queue-init-params
    (let ((func (lazy-foreign-procedure liburing-ffi "io_uring_queue_init_params"
                                   (unsigned void* void*) int)))
      (lambda (entries ring params)
        (func entries ring params))))

  (define io-uring-queue-exit
    (let ((func (lazy-foreign-procedure liburing-ffi "io_uring_queue_exit" (void*) void)))
      (lambda (ring)
        (func ring))))

  (define io-uring-queue-mmap
    (let ((func (lazy-foreign-procedure liburing-ffi "io_uring_queue_mmap"
                                   (int void* void*) int)))
      (lambda (fd params ring)
        (func fd params ring))))

  ;;------------------------------------------------------------
  ;; SQE acquisition
  ;;------------------------------------------------------------

  (define io-uring-get-sqe
    (let ((func (lazy-foreign-procedure liburing-ffi "io_uring_get_sqe" (void*) void*)))
      (lambda (ring)
        (func ring))))

  ;;------------------------------------------------------------
  ;; Submission
  ;;------------------------------------------------------------

  (define io-uring-submit
    (let ((func (lazy-foreign-procedure liburing-ffi "io_uring_submit" (void*) int)))
      (lambda (ring)
        (func ring))))

  (define io-uring-submit-and-wait
    (let ((func (lazy-foreign-procedure liburing-ffi "io_uring_submit_and_wait"
                                   (void* unsigned) int)))
      (lambda (ring wait-nr)
        (func ring wait-nr))))

  (define io-uring-submit-and-wait-timeout
    (let ((func (lazy-foreign-procedure liburing-ffi "io_uring_submit_and_wait_timeout"
                                   (void* void* unsigned void* void*) int)))
      (lambda (ring cqe-ptr wait-nr ts sigmask)
        (func ring cqe-ptr wait-nr ts sigmask))))

  (define io-uring-submit-and-get-events
    (let ((func (lazy-foreign-procedure liburing-ffi "io_uring_submit_and_get_events"
                                   (void*) int)))
      (lambda (ring)
        (func ring))))

  ;;------------------------------------------------------------
  ;; Completion waiting
  ;;------------------------------------------------------------

  (define io-uring-wait-cqe
    (let ((func (lazy-foreign-procedure liburing-ffi "io_uring_wait_cqe"
                                   (void* void*) int)))
      (lambda (ring cqe-ptr)
        (func ring cqe-ptr))))

  (define io-uring-wait-cqe-nr
    (let ((func (lazy-foreign-procedure liburing-ffi "io_uring_wait_cqe_nr"
                                   (void* void* unsigned) int)))
      (lambda (ring cqe-ptr wait-nr)
        (func ring cqe-ptr wait-nr))))

  (define io-uring-wait-cqe-timeout
    (let ((func (lazy-foreign-procedure liburing-ffi __collect_safe "io_uring_wait_cqe_timeout"
                                   (void* void* void*) int)))
      (lambda (ring cqe-ptr ts)
        (func ring cqe-ptr (ftype-pointer-address ts)))))

  (define io-uring-wait-cqes
    (let ((func (lazy-foreign-procedure liburing-ffi "io_uring_wait_cqes"
                                   (void* void* unsigned void* void*) int)))
      (lambda (ring cqe-ptr wait-nr ts sigmask)
        (func ring cqe-ptr wait-nr ts sigmask))))

  (define io-uring-peek-cqe
    (let ((func (lazy-foreign-procedure liburing-ffi "io_uring_peek_cqe"
                                   (void* void*) int)))
      (lambda (ring cqe-ptr)
        (func ring cqe-ptr))))

  (define io-uring-peek-batch-cqe
    (let ((func (lazy-foreign-procedure liburing-ffi "io_uring_peek_batch_cqe"
                                   (void* void* unsigned) unsigned)))
      (lambda (ring cqes count)
        (func ring cqes count))))

  ;;------------------------------------------------------------
  ;; Completion processing
  ;;------------------------------------------------------------

  (define io-uring-cqe-seen
    (let ((func (lazy-foreign-procedure liburing-ffi "io_uring_cqe_seen"
                                   (void* void*) void)))
      (lambda (ring cqe)
        (func ring cqe))))

  (define io-uring-cq-advance
    (let ((func (lazy-foreign-procedure liburing-ffi "io_uring_cq_advance"
                                   (void* unsigned) void)))
      (lambda (ring nr)
        (func ring nr))))

  (define io-uring-cqe-get-data
    (let ((func (lazy-foreign-procedure liburing-ffi "io_uring_cqe_get_data"
                                   (void*) void*)))
      (lambda (cqe)
        (func cqe))))

  (define io-uring-cqe-get-data64
    (let ((func (lazy-foreign-procedure liburing-ffi "io_uring_cqe_get_data64"
                                   (void*) unsigned-64)))
      (lambda (cqe)
        (func cqe))))

  (define io-uring-cqe-get-res
    (lambda (cqe)
      (ftype-ref <cqe> (res)
                 (make-ftype-pointer <cqe> cqe))))

  (define io-uring-cqe-get-flags
    (lambda (cqe)
      (ftype-ref <cqe> (flags)
                 (make-ftype-pointer <cqe> cqe))))

  ;;------------------------------------------------------------
  ;; SQE configuration
  ;;------------------------------------------------------------

  (define io-uring-sqe-set-data
    (let ((func (lazy-foreign-procedure liburing-ffi "io_uring_sqe_set_data"
                                   (void* void*) void)))
      (lambda (sqe data)
        (func sqe data))))

  (define io-uring-sqe-set-data64
    (let ((func (lazy-foreign-procedure liburing-ffi "io_uring_sqe_set_data64"
                                   (void* unsigned-64) void)))
      (lambda (sqe data)
        (func sqe data))))

  (define io-uring-sqe-set-flags
    (let ((func (lazy-foreign-procedure liburing-ffi "io_uring_sqe_set_flags"
                                   (void* unsigned) void)))
      (lambda (sqe flags)
        (func sqe flags))))

  (define io-uring-sqe-set-buf-group
    (let ((func (lazy-foreign-procedure liburing-ffi "io_uring_sqe_set_buf_group"
                                   (void* int) void)))
      (lambda (sqe bgid)
        (func sqe bgid))))

  ;;------------------------------------------------------------
  ;; Ring state queries
  ;;------------------------------------------------------------

  (define io-uring-sq-ready
    (let ((func (lazy-foreign-procedure liburing-ffi "io_uring_sq_ready"
                                   (void*) unsigned)))
      (lambda (ring)
        (func ring))))

  (define io-uring-sq-space-left
    (let ((func (lazy-foreign-procedure liburing-ffi "io_uring_sq_space_left"
                                   (void*) unsigned)))
      (lambda (ring)
        (func ring))))

  (define io-uring-cq-ready
    (let ((func (lazy-foreign-procedure liburing-ffi "io_uring_cq_ready"
                                   (void*) unsigned)))
      (lambda (ring)
        (func ring))))

  (define io-uring-cq-has-overflow
    (let ((func (lazy-foreign-procedure liburing-ffi "io_uring_cq_has_overflow"
                                   (void*) boolean)))
      (lambda (ring)
        (func ring))))

  (define io-uring-get-events
    (let ((func (lazy-foreign-procedure liburing-ffi "io_uring_get_events"
                                   (void*) int)))
      (lambda (ring)
        (func ring))))

  ;;------------------------------------------------------------
  ;; Prep: low-level
  ;;------------------------------------------------------------

  (define io-uring-prep-rw
    (let ((func (lazy-foreign-procedure liburing-ffi "io_uring_prep_rw"
                                   (int void* int void* unsigned unsigned-64) void)))
      (lambda (op sqe fd addr len offset)
        (func op sqe fd addr len offset))))

  ;;------------------------------------------------------------
  ;; Prep: nop
  ;;------------------------------------------------------------

  (define io-uring-prep-nop
    (let ((func (lazy-foreign-procedure liburing-ffi "io_uring_prep_nop" (void*) void)))
      (lambda (sqe)
        (func sqe))))

  ;;------------------------------------------------------------
  ;; Prep: read/write
  ;;------------------------------------------------------------

  (define io-uring-prep-read
    (let ((func (lazy-foreign-procedure liburing-ffi "io_uring_prep_read"
                                   (void* int void* unsigned unsigned-64) void)))
      (lambda (sqe fd buf nbytes offset)
        (func sqe fd buf nbytes offset))))

  (define io-uring-prep-write
    (let ((func (lazy-foreign-procedure liburing-ffi "io_uring_prep_write"
                                   (void* int void* unsigned unsigned-64) void)))
      (lambda (sqe fd buf nbytes offset)
        (func sqe fd buf nbytes offset))))

  (define io-uring-prep-readv
    (let ((func (lazy-foreign-procedure liburing-ffi "io_uring_prep_readv"
                                   (void* int void* unsigned unsigned-64) void)))
      (lambda (sqe fd iovecs nr-vecs offset)
        (func sqe fd iovecs nr-vecs offset))))

  (define io-uring-prep-writev
    (let ((func (lazy-foreign-procedure liburing-ffi "io_uring_prep_writev"
                                   (void* int void* unsigned unsigned-64) void)))
      (lambda (sqe fd iovecs nr-vecs offset)
        (func sqe fd iovecs nr-vecs offset))))

  (define io-uring-prep-readv2
    (let ((func (lazy-foreign-procedure liburing-ffi "io_uring_prep_readv2"
                                   (void* int void* unsigned unsigned-64 int) void)))
      (lambda (sqe fd iovecs nr-vecs offset flags)
        (func sqe fd iovecs nr-vecs offset flags))))

  (define io-uring-prep-writev2
    (let ((func (lazy-foreign-procedure liburing-ffi "io_uring_prep_writev2"
                                   (void* int void* unsigned unsigned-64 int) void)))
      (lambda (sqe fd iovecs nr-vecs offset flags)
        (func sqe fd iovecs nr-vecs offset flags))))

  (define io-uring-prep-read-fixed
    (let ((func (lazy-foreign-procedure liburing-ffi "io_uring_prep_read_fixed"
                                   (void* int void* unsigned unsigned-64 int) void)))
      (lambda (sqe fd buf nbytes offset buf-index)
        (func sqe fd buf nbytes offset buf-index))))

  (define io-uring-prep-write-fixed
    (let ((func (lazy-foreign-procedure liburing-ffi "io_uring_prep_write_fixed"
                                   (void* int void* unsigned unsigned-64 int) void)))
      (lambda (sqe fd buf nbytes offset buf-index)
        (func sqe fd buf nbytes offset buf-index))))

  (define io-uring-prep-read-multishot
    (let ((func (lazy-foreign-procedure liburing-ffi "io_uring_prep_read_multishot"
                                   (void* int unsigned unsigned-64 int) void)))
      (lambda (sqe fd nbytes offset buf-group)
        (func sqe fd nbytes offset buf-group))))

  ;;------------------------------------------------------------
  ;; Prep: socket operations
  ;;------------------------------------------------------------

  (define io-uring-prep-socket
    (let ((func (lazy-foreign-procedure liburing-ffi "io_uring_prep_socket"
                                   (void* int int int unsigned) void)))
      (lambda (sqe domain type protocol flags)
        (func sqe domain type protocol flags))))

  (define io-uring-prep-socket-direct
    (let ((func (lazy-foreign-procedure liburing-ffi "io_uring_prep_socket_direct"
                                   (void* int int int unsigned unsigned) void)))
      (lambda (sqe domain type protocol file-index flags)
        (func sqe domain type protocol file-index flags))))

  (define io-uring-prep-socket-direct-alloc
    (let ((func (lazy-foreign-procedure liburing-ffi "io_uring_prep_socket_direct_alloc"
                                   (void* int int int unsigned) void)))
      (lambda (sqe domain type protocol flags)
        (func sqe domain type protocol flags))))

  (define io-uring-prep-connect
    (let ((func (lazy-foreign-procedure liburing-ffi "io_uring_prep_connect"
                                   (void* int void* unsigned) void)))
      (lambda (sqe fd addr addrlen)
        (func sqe fd addr addrlen))))

  (define io-uring-prep-bind
    (let ((func (lazy-foreign-procedure liburing-ffi "io_uring_prep_bind"
                                   (void* int void* unsigned) void)))
      (lambda (sqe fd addr addrlen)
        (func sqe fd addr addrlen))))

  (define io-uring-prep-listen
    (let ((func (lazy-foreign-procedure liburing-ffi "io_uring_prep_listen"
                                   (void* int int) void)))
      (lambda (sqe fd backlog)
        (func sqe fd backlog))))

  (define io-uring-prep-accept
    (let ((func (lazy-foreign-procedure liburing-ffi "io_uring_prep_accept"
                                   (void* int void* void* int) void)))
      (lambda (sqe fd addr addrlen flags)
        (func sqe fd addr addrlen flags))))

  (define io-uring-prep-accept-direct
    (let ((func (lazy-foreign-procedure liburing-ffi "io_uring_prep_accept_direct"
                                   (void* int void* void* int unsigned) void)))
      (lambda (sqe fd addr addrlen flags file-index)
        (func sqe fd addr addrlen flags file-index))))

  (define io-uring-prep-multishot-accept
    (let ((func (lazy-foreign-procedure liburing-ffi "io_uring_prep_multishot_accept"
                                   (void* int void* void* int) void)))
      (lambda (sqe fd addr addrlen flags)
        (func sqe fd addr addrlen flags))))

  (define io-uring-prep-multishot-accept-direct
    (let ((func (lazy-foreign-procedure liburing-ffi "io_uring_prep_multishot_accept_direct"
                                   (void* int void* void* int) void)))
      (lambda (sqe fd addr addrlen flags)
        (func sqe fd addr addrlen flags))))

  (define io-uring-prep-shutdown
    (let ((func (lazy-foreign-procedure liburing-ffi "io_uring_prep_shutdown"
                                   (void* int int) void)))
      (lambda (sqe fd how)
        (func sqe fd how))))

  ;;------------------------------------------------------------
  ;; Prep: send/recv
  ;;------------------------------------------------------------

  (define io-uring-prep-send
    (let ((func (lazy-foreign-procedure liburing-ffi "io_uring_prep_send"
                                   (void* int void* size_t int) void)))
      (lambda (sqe sockfd buf len flags)
        (func sqe sockfd buf len flags))))

  (define io-uring-prep-send-bundle
    (let ((func (lazy-foreign-procedure liburing-ffi "io_uring_prep_send_bundle"
                                   (void* int size_t int) void)))
      (lambda (sqe sockfd len flags)
        (func sqe sockfd len flags))))

  (define io-uring-prep-send-set-addr
    (let ((func (lazy-foreign-procedure liburing-ffi "io_uring_prep_send_set_addr"
                                   (void* void* unsigned-16) void)))
      (lambda (sqe dest-addr addr-len)
        (func sqe dest-addr addr-len))))

  (define io-uring-prep-sendto
    (let ((func (lazy-foreign-procedure liburing-ffi "io_uring_prep_sendto"
                                   (void* int void* size_t int void* unsigned) void)))
      (lambda (sqe sockfd buf len flags addr addrlen)
        (func sqe sockfd buf len flags addr addrlen))))

  (define io-uring-prep-send-zc
    (let ((func (lazy-foreign-procedure liburing-ffi "io_uring_prep_send_zc"
                                   (void* int void* size_t int unsigned) void)))
      (lambda (sqe sockfd buf len flags zc-flags)
        (func sqe sockfd buf len flags zc-flags))))

  (define io-uring-prep-send-zc-fixed
    (let ((func (lazy-foreign-procedure liburing-ffi "io_uring_prep_send_zc_fixed"
                                   (void* int void* size_t int unsigned unsigned) void)))
      (lambda (sqe sockfd buf len flags zc-flags buf-index)
        (func sqe sockfd buf len flags zc-flags buf-index))))

  (define io-uring-prep-recv
    (let ((func (lazy-foreign-procedure liburing-ffi "io_uring_prep_recv"
                                   (void* int void* size_t int) void)))
      (lambda (sqe sockfd buf len flags)
        (func sqe sockfd buf len flags))))

  (define io-uring-prep-recv-multishot
    (let ((func (lazy-foreign-procedure liburing-ffi "io_uring_prep_recv_multishot"
                                   (void* int void* size_t int) void)))
      (lambda (sqe sockfd buf len flags)
        (func sqe sockfd buf len flags))))

  (define io-uring-prep-sendmsg
    (let ((func (lazy-foreign-procedure liburing-ffi "io_uring_prep_sendmsg"
                                   (void* int void* unsigned) void)))
      (lambda (sqe fd msg flags)
        (func sqe fd msg flags))))

  (define io-uring-prep-sendmsg-zc
    (let ((func (lazy-foreign-procedure liburing-ffi "io_uring_prep_sendmsg_zc"
                                   (void* int void* unsigned) void)))
      (lambda (sqe fd msg flags)
        (func sqe fd msg flags))))

  (define io-uring-prep-recvmsg
    (let ((func (lazy-foreign-procedure liburing-ffi "io_uring_prep_recvmsg"
                                   (void* int void* unsigned) void)))
      (lambda (sqe fd msg flags)
        (func sqe fd msg flags))))

  (define io-uring-prep-recvmsg-multishot
    (let ((func (lazy-foreign-procedure liburing-ffi "io_uring_prep_recvmsg_multishot"
                                   (void* int void* unsigned) void)))
      (lambda (sqe fd msg flags)
        (func sqe fd msg flags))))

  ;;------------------------------------------------------------
  ;; Prep: file operations
  ;;------------------------------------------------------------

  (define io-uring-prep-openat
    (let ((func (lazy-foreign-procedure liburing-ffi "io_uring_prep_openat"
                                   (void* int string int unsigned) void)))
      (lambda (sqe dfd path flags mode)
        (func sqe dfd path flags mode))))

  ;; Same C entry point as io-uring-prep-openat, but PATH is a raw
  ;; pointer the caller owns instead of an FFI `string`. Preparing an
  ;; SQE only *records* the path pointer; the kernel dereferences it at
  ;; submit time, which — for anything built on the event loop rather
  ;; than a private submit-and-wait ring — is a later tick entirely. The
  ;; C copy an FFI `string` argument allocates is freed the moment the
  ;; prep call returns, so it would be dangling by then; callers of this
  ;; variant keep the path alive themselves (a locked bytevector, or
  ;; foreign-alloc'd memory) until the completion arrives.
  (define io-uring-prep-openat-pointer
    (let ((func (lazy-foreign-procedure liburing-ffi "io_uring_prep_openat"
                                   (void* int void* int unsigned) void)))
      (lambda (sqe dfd path flags mode)
        (func sqe dfd path flags mode))))

  (define io-uring-prep-openat-direct
    (let ((func (lazy-foreign-procedure liburing-ffi "io_uring_prep_openat_direct"
                                   (void* int string int unsigned unsigned) void)))
      (lambda (sqe dfd path flags mode file-index)
        (func sqe dfd path flags mode file-index))))

  (define io-uring-prep-open
    (let ((func (lazy-foreign-procedure liburing-ffi "io_uring_prep_open"
                                   (void* string int unsigned) void)))
      (lambda (sqe path flags mode)
        (func sqe path flags mode))))

  (define io-uring-prep-open-direct
    (let ((func (lazy-foreign-procedure liburing-ffi "io_uring_prep_open_direct"
                                   (void* string int unsigned unsigned) void)))
      (lambda (sqe path flags mode file-index)
        (func sqe path flags mode file-index))))

  (define io-uring-prep-close
    (let ((func (lazy-foreign-procedure liburing-ffi "io_uring_prep_close"
                                   (void* int) void)))
      (lambda (sqe fd)
        (func sqe fd))))

  (define io-uring-prep-close-direct
    (let ((func (lazy-foreign-procedure liburing-ffi "io_uring_prep_close_direct"
                                   (void* unsigned) void)))
      (lambda (sqe file-index)
        (func sqe file-index))))

  (define io-uring-prep-fsync
    (let ((func (lazy-foreign-procedure liburing-ffi "io_uring_prep_fsync"
                                   (void* int unsigned) void)))
      (lambda (sqe fd fsync-flags)
        (func sqe fd fsync-flags))))

  (define io-uring-prep-sync-file-range
    (let ((func (lazy-foreign-procedure liburing-ffi "io_uring_prep_sync_file_range"
                                   (void* int unsigned unsigned-64 int) void)))
      (lambda (sqe fd len offset flags)
        (func sqe fd len offset flags))))

  (define io-uring-prep-fallocate
    (let ((func (lazy-foreign-procedure liburing-ffi "io_uring_prep_fallocate"
                                   (void* int int unsigned-64 unsigned-64) void)))
      (lambda (sqe fd mode offset len)
        (func sqe fd mode offset len))))

  (define io-uring-prep-ftruncate
    (let ((func (lazy-foreign-procedure liburing-ffi "io_uring_prep_ftruncate"
                                   (void* int unsigned-64) void)))
      (lambda (sqe fd len)
        (func sqe fd len))))

  (define io-uring-prep-statx
    (let ((func (lazy-foreign-procedure liburing-ffi "io_uring_prep_statx"
                                   (void* int string int unsigned void*) void)))
      (lambda (sqe dfd path flags mask statxbuf)
        (func sqe dfd path flags mask statxbuf))))

  (define io-uring-prep-fadvise
    (let ((func (lazy-foreign-procedure liburing-ffi "io_uring_prep_fadvise"
                                   (void* int unsigned-64 unsigned-32 int) void)))
      (lambda (sqe fd offset len advice)
        (func sqe fd offset len advice))))

  (define io-uring-prep-madvise
    (let ((func (lazy-foreign-procedure liburing-ffi "io_uring_prep_madvise"
                                   (void* void* unsigned-32 int) void)))
      (lambda (sqe addr length advice)
        (func sqe addr length advice))))

  (define io-uring-prep-splice
    (let ((func (lazy-foreign-procedure liburing-ffi "io_uring_prep_splice"
                                   (void* int integer-64 int integer-64
                                          unsigned unsigned) void)))
      (lambda (sqe fd-in off-in fd-out off-out nbytes splice-flags)
        (func sqe fd-in off-in fd-out off-out nbytes splice-flags))))

  (define io-uring-prep-tee
    (let ((func (lazy-foreign-procedure liburing-ffi "io_uring_prep_tee"
                                   (void* int int unsigned unsigned) void)))
      (lambda (sqe fd-in fd-out nbytes splice-flags)
        (func sqe fd-in fd-out nbytes splice-flags))))

  ;;------------------------------------------------------------
  ;; Prep: filesystem operations
  ;;------------------------------------------------------------

  (define io-uring-prep-renameat
    (let ((func (lazy-foreign-procedure liburing-ffi "io_uring_prep_renameat"
                                   (void* int string int string unsigned) void)))
      (lambda (sqe olddfd oldpath newdfd newpath flags)
        (func sqe olddfd oldpath newdfd newpath flags))))

  (define io-uring-prep-rename
    (let ((func (lazy-foreign-procedure liburing-ffi "io_uring_prep_rename"
                                   (void* string string) void)))
      (lambda (sqe oldpath newpath)
        (func sqe oldpath newpath))))

  (define io-uring-prep-unlinkat
    (let ((func (lazy-foreign-procedure liburing-ffi "io_uring_prep_unlinkat"
                                   (void* int string int) void)))
      (lambda (sqe dfd path flags)
        (func sqe dfd path flags))))

  (define io-uring-prep-unlink
    (let ((func (lazy-foreign-procedure liburing-ffi "io_uring_prep_unlink"
                                   (void* string int) void)))
      (lambda (sqe path flags)
        (func sqe path flags))))

  (define io-uring-prep-mkdirat
    (let ((func (lazy-foreign-procedure liburing-ffi "io_uring_prep_mkdirat"
                                   (void* int string unsigned) void)))
      (lambda (sqe dfd path mode)
        (func sqe dfd path mode))))

  (define io-uring-prep-mkdir
    (let ((func (lazy-foreign-procedure liburing-ffi "io_uring_prep_mkdir"
                                   (void* string unsigned) void)))
      (lambda (sqe path mode)
        (func sqe path mode))))

  (define io-uring-prep-symlinkat
    (let ((func (lazy-foreign-procedure liburing-ffi "io_uring_prep_symlinkat"
                                   (void* string int string) void)))
      (lambda (sqe target newdirfd linkpath)
        (func sqe target newdirfd linkpath))))

  (define io-uring-prep-symlink
    (let ((func (lazy-foreign-procedure liburing-ffi "io_uring_prep_symlink"
                                   (void* string string) void)))
      (lambda (sqe target linkpath)
        (func sqe target linkpath))))

  (define io-uring-prep-linkat
    (let ((func (lazy-foreign-procedure liburing-ffi "io_uring_prep_linkat"
                                   (void* int string int string int) void)))
      (lambda (sqe olddfd oldpath newdfd newpath flags)
        (func sqe olddfd oldpath newdfd newpath flags))))

  (define io-uring-prep-link
    (let ((func (lazy-foreign-procedure liburing-ffi "io_uring_prep_link"
                                   (void* string string int) void)))
      (lambda (sqe oldpath newpath flags)
        (func sqe oldpath newpath flags))))

  ;;------------------------------------------------------------
  ;; Prep: xattr
  ;;------------------------------------------------------------

  (define io-uring-prep-getxattr
    (let ((func (lazy-foreign-procedure liburing-ffi "io_uring_prep_getxattr"
                                   (void* string void* string unsigned) void)))
      (lambda (sqe name value path len)
        (func sqe name value path len))))

  (define io-uring-prep-setxattr
    (let ((func (lazy-foreign-procedure liburing-ffi "io_uring_prep_setxattr"
                                   (void* string string string int unsigned) void)))
      (lambda (sqe name value path flags len)
        (func sqe name value path flags len))))

  (define io-uring-prep-fgetxattr
    (let ((func (lazy-foreign-procedure liburing-ffi "io_uring_prep_fgetxattr"
                                   (void* int string void* unsigned) void)))
      (lambda (sqe fd name value len)
        (func sqe fd name value len))))

  (define io-uring-prep-fsetxattr
    (let ((func (lazy-foreign-procedure liburing-ffi "io_uring_prep_fsetxattr"
                                   (void* int string string int unsigned) void)))
      (lambda (sqe fd name value flags len)
        (func sqe fd name value flags len))))

  ;;------------------------------------------------------------
  ;; Prep: timeout
  ;;------------------------------------------------------------

  (define io-uring-prep-timeout
    (let ((func (lazy-foreign-procedure liburing-ffi "io_uring_prep_timeout"
                                   (void* void* unsigned unsigned) void)))
      (lambda (sqe ts count flags)
        (func sqe ts count flags))))

  (define io-uring-prep-timeout-remove
    (let ((func (lazy-foreign-procedure liburing-ffi "io_uring_prep_timeout_remove"
                                   (void* unsigned-64 unsigned) void)))
      (lambda (sqe user-data flags)
        (func sqe user-data flags))))

  (define io-uring-prep-timeout-update
    (let ((func (lazy-foreign-procedure liburing-ffi "io_uring_prep_timeout_update"
                                   (void* void* unsigned-64 unsigned) void)))
      (lambda (sqe ts user-data flags)
        (func sqe ts user-data flags))))

  (define io-uring-prep-link-timeout
    (let ((func (lazy-foreign-procedure liburing-ffi "io_uring_prep_link_timeout"
                                   (void* void* unsigned) void)))
      (lambda (sqe ts flags)
        (func sqe ts flags))))

  ;;------------------------------------------------------------
  ;; Prep: cancel
  ;;------------------------------------------------------------

  (define io-uring-prep-cancel
    (let ((func (lazy-foreign-procedure liburing-ffi "io_uring_prep_cancel"
                                   (void* void* int) void)))
      (lambda (sqe user-data flags)
        (func sqe user-data flags))))

  (define io-uring-prep-cancel64
    (let ((func (lazy-foreign-procedure liburing-ffi "io_uring_prep_cancel64"
                                   (void* unsigned-64 int) void)))
      (lambda (sqe user-data flags)
        (func sqe user-data flags))))

  (define io-uring-prep-cancel-fd
    (let ((func (lazy-foreign-procedure liburing-ffi "io_uring_prep_cancel_fd"
                                   (void* int unsigned) void)))
      (lambda (sqe fd flags)
        (func sqe fd flags))))

  ;;------------------------------------------------------------
  ;; Prep: poll
  ;;------------------------------------------------------------

  (define io-uring-prep-poll-add
    (let ((func (lazy-foreign-procedure liburing-ffi "io_uring_prep_poll_add"
                                   (void* int unsigned) void)))
      (lambda (sqe fd poll-mask)
        (func sqe fd poll-mask))))

  (define io-uring-prep-poll-multishot
    (let ((func (lazy-foreign-procedure liburing-ffi "io_uring_prep_poll_multishot"
                                   (void* int unsigned) void)))
      (lambda (sqe fd poll-mask)
        (func sqe fd poll-mask))))

  (define io-uring-prep-poll-remove
    (let ((func (lazy-foreign-procedure liburing-ffi "io_uring_prep_poll_remove"
                                   (void* unsigned-64) void)))
      (lambda (sqe user-data)
        (func sqe user-data))))

  (define io-uring-prep-poll-update
    (let ((func (lazy-foreign-procedure liburing-ffi "io_uring_prep_poll_update"
                                   (void* unsigned-64 unsigned-64
                                          unsigned unsigned) void)))
      (lambda (sqe old-user-data new-user-data poll-mask flags)
        (func sqe old-user-data new-user-data poll-mask flags))))

  ;;------------------------------------------------------------
  ;; Prep: msg ring
  ;;------------------------------------------------------------

  (define io-uring-prep-msg-ring
    (let ((func (lazy-foreign-procedure liburing-ffi "io_uring_prep_msg_ring"
                                   (void* int unsigned unsigned-64 unsigned) void)))
      (lambda (sqe fd len data flags)
        (func sqe fd len data flags))))

  (define io-uring-prep-msg-ring-cqe-flags
    (let ((func (lazy-foreign-procedure liburing-ffi "io_uring_prep_msg_ring_cqe_flags"
                                   (void* int unsigned unsigned-64
                                          unsigned unsigned) void)))
      (lambda (sqe fd len data flags cqe-flags)
        (func sqe fd len data flags cqe-flags))))

  (define io-uring-prep-msg-ring-fd
    (let ((func (lazy-foreign-procedure liburing-ffi "io_uring_prep_msg_ring_fd"
                                   (void* int int int unsigned-64 unsigned) void)))
      (lambda (sqe fd source-fd target-fd data flags)
        (func sqe fd source-fd target-fd data flags))))

  (define io-uring-prep-msg-ring-fd-alloc
    (let ((func (lazy-foreign-procedure liburing-ffi "io_uring_prep_msg_ring_fd_alloc"
                                   (void* int int unsigned-64 unsigned) void)))
      (lambda (sqe fd source-fd data flags)
        (func sqe fd source-fd data flags))))

  ;;------------------------------------------------------------
  ;; Prep: provide/remove buffers
  ;;------------------------------------------------------------

  (define io-uring-prep-provide-buffers
    (let ((func (lazy-foreign-procedure liburing-ffi "io_uring_prep_provide_buffers"
                                   (void* void* int int int int) void)))
      (lambda (sqe addr len nr bgid bid)
        (func sqe addr len nr bgid bid))))

  (define io-uring-prep-remove-buffers
    (let ((func (lazy-foreign-procedure liburing-ffi "io_uring_prep_remove_buffers"
                                   (void* int int) void)))
      (lambda (sqe nr bgid)
        (func sqe nr bgid))))

  ;;------------------------------------------------------------
  ;; Prep: epoll
  ;;------------------------------------------------------------

  (define io-uring-prep-epoll-ctl
    (let ((func (lazy-foreign-procedure liburing-ffi "io_uring_prep_epoll_ctl"
                                   (void* int int int void*) void)))
      (lambda (sqe epfd fd op ev)
        (func sqe epfd fd op ev))))

  ;;------------------------------------------------------------
  ;; Prep: misc
  ;;------------------------------------------------------------

  (define io-uring-prep-files-update
    (let ((func (lazy-foreign-procedure liburing-ffi "io_uring_prep_files_update"
                                   (void* void* unsigned int) void)))
      (lambda (sqe fds nr-fds offset)
        (func sqe fds nr-fds offset))))

  (define io-uring-prep-fixed-fd-install
    (let ((func (lazy-foreign-procedure liburing-ffi "io_uring_prep_fixed_fd_install"
                                   (void* int unsigned) void)))
      (lambda (sqe fd flags)
        (func sqe fd flags))))

  (define io-uring-prep-cmd-sock
    (let ((func (lazy-foreign-procedure liburing-ffi "io_uring_prep_cmd_sock"
                                   (void* int int int int void* int) void)))
      (lambda (sqe cmd-op fd level optname optval optlen)
        (func sqe cmd-op fd level optname optval optlen))))

  (define io-uring-prep-waitid
    (let ((func (lazy-foreign-procedure liburing-ffi "io_uring_prep_waitid"
                                   (void* int int void* int unsigned) void)))
      (lambda (sqe idtype id infop options flags)
        (func sqe idtype id infop options flags))))

  (define io-uring-prep-futex-wait
    (let ((func (lazy-foreign-procedure liburing-ffi "io_uring_prep_futex_wait"
                                   (void* void* unsigned-64 unsigned-64
                                          unsigned-32 unsigned) void)))
      (lambda (sqe futex val mask futex-flags flags)
        (func sqe futex val mask futex-flags flags))))

  (define io-uring-prep-futex-wake
    (let ((func (lazy-foreign-procedure liburing-ffi "io_uring_prep_futex_wake"
                                   (void* void* unsigned-64 unsigned-64
                                          unsigned-32 unsigned) void)))
      (lambda (sqe futex val mask futex-flags flags)
        (func sqe futex val mask futex-flags flags))))

  (define io-uring-prep-futex-waitv
    (let ((func (lazy-foreign-procedure liburing-ffi "io_uring_prep_futex_waitv"
                                   (void* void* unsigned-32 unsigned) void)))
      (lambda (sqe futex nr-futex flags)
        (func sqe futex nr-futex flags))))

  ;;------------------------------------------------------------
  ;; Registration
  ;;------------------------------------------------------------

  (define io-uring-register-buffers
    (let ((func (lazy-foreign-procedure liburing-ffi "io_uring_register_buffers"
                                   (void* void* unsigned) int)))
      (lambda (ring iovecs nr-iovecs)
        (func ring iovecs nr-iovecs))))

  (define io-uring-unregister-buffers
    (let ((func (lazy-foreign-procedure liburing-ffi "io_uring_unregister_buffers"
                                   (void*) int)))
      (lambda (ring)
        (func ring))))

  (define io-uring-register-buffers-sparse
    (let ((func (lazy-foreign-procedure liburing-ffi "io_uring_register_buffers_sparse"
                                   (void* unsigned) int)))
      (lambda (ring nr)
        (func ring nr))))

  (define io-uring-register-buffers-tags
    (let ((func (lazy-foreign-procedure liburing-ffi "io_uring_register_buffers_tags"
                                   (void* void* void* unsigned) int)))
      (lambda (ring iovecs tags nr)
        (func ring iovecs tags nr))))

  (define io-uring-register-buffers-update-tag
    (let ((func (lazy-foreign-procedure liburing-ffi "io_uring_register_buffers_update_tag"
                                   (void* unsigned void* void* unsigned) int)))
      (lambda (ring off iovecs tags nr)
        (func ring off iovecs tags nr))))

  (define io-uring-register-files
    (let ((func (lazy-foreign-procedure liburing-ffi "io_uring_register_files"
                                   (void* void* unsigned) int)))
      (lambda (ring files nr-files)
        (func ring files nr-files))))

  (define io-uring-unregister-files
    (let ((func (lazy-foreign-procedure liburing-ffi "io_uring_unregister_files"
                                   (void*) int)))
      (lambda (ring)
        (func ring))))

  (define io-uring-register-files-sparse
    (let ((func (lazy-foreign-procedure liburing-ffi "io_uring_register_files_sparse"
                                   (void* unsigned) int)))
      (lambda (ring nr)
        (func ring nr))))

  (define io-uring-register-files-tags
    (let ((func (lazy-foreign-procedure liburing-ffi "io_uring_register_files_tags"
                                   (void* void* void* unsigned) int)))
      (lambda (ring files tags nr)
        (func ring files tags nr))))

  (define io-uring-register-files-update
    (let ((func (lazy-foreign-procedure liburing-ffi "io_uring_register_files_update"
                                   (void* unsigned void* unsigned) int)))
      (lambda (ring off files nr-files)
        (func ring off files nr-files))))

  (define io-uring-register-files-update-tag
    (let ((func (lazy-foreign-procedure liburing-ffi "io_uring_register_files_update_tag"
                                   (void* unsigned void* void* unsigned) int)))
      (lambda (ring off files tags nr-files)
        (func ring off files tags nr-files))))

  (define io-uring-register-eventfd
    (let ((func (lazy-foreign-procedure liburing-ffi "io_uring_register_eventfd"
                                   (void* int) int)))
      (lambda (ring fd)
        (func ring fd))))

  (define io-uring-register-eventfd-async
    (let ((func (lazy-foreign-procedure liburing-ffi "io_uring_register_eventfd_async"
                                   (void* int) int)))
      (lambda (ring fd)
        (func ring fd))))

  (define io-uring-unregister-eventfd
    (let ((func (lazy-foreign-procedure liburing-ffi "io_uring_unregister_eventfd"
                                   (void*) int)))
      (lambda (ring)
        (func ring))))

  (define io-uring-register-probe
    (let ((func (lazy-foreign-procedure liburing-ffi "io_uring_register_probe"
                                   (void* void* unsigned) int)))
      (lambda (ring p nr)
        (func ring p nr))))

  (define io-uring-register-personality
    (let ((func (lazy-foreign-procedure liburing-ffi "io_uring_register_personality"
                                   (void*) int)))
      (lambda (ring)
        (func ring))))

  (define io-uring-unregister-personality
    (let ((func (lazy-foreign-procedure liburing-ffi "io_uring_unregister_personality"
                                   (void* int) int)))
      (lambda (ring id)
        (func ring id))))

  (define io-uring-register-restrictions
    (let ((func (lazy-foreign-procedure liburing-ffi "io_uring_register_restrictions"
                                   (void* void* unsigned) int)))
      (lambda (ring res nr-res)
        (func ring res nr-res))))

  (define io-uring-enable-rings
    (let ((func (lazy-foreign-procedure liburing-ffi "io_uring_enable_rings"
                                   (void*) int)))
      (lambda (ring)
        (func ring))))

  (define io-uring-register-iowq-max-workers
    (let ((func (lazy-foreign-procedure liburing-ffi "io_uring_register_iowq_max_workers"
                                   (void* void*) int)))
      (lambda (ring values)
        (func ring values))))

  (define io-uring-register-ring-fd
    (let ((func (lazy-foreign-procedure liburing-ffi "io_uring_register_ring_fd"
                                   (void*) int)))
      (lambda (ring)
        (func ring))))

  (define io-uring-unregister-ring-fd
    (let ((func (lazy-foreign-procedure liburing-ffi "io_uring_unregister_ring_fd"
                                   (void*) int)))
      (lambda (ring)
        (func ring))))

  (define io-uring-close-ring-fd
    (let ((func (lazy-foreign-procedure liburing-ffi "io_uring_close_ring_fd"
                                   (void*) int)))
      (lambda (ring)
        (func ring))))

  (define io-uring-register-buf-ring
    (let ((func (lazy-foreign-procedure liburing-ffi "io_uring_register_buf_ring"
                                   (void* void* unsigned) int)))
      (lambda (ring reg flags)
        (func ring reg flags))))

  (define io-uring-unregister-buf-ring
    (let ((func (lazy-foreign-procedure liburing-ffi "io_uring_unregister_buf_ring"
                                   (void* int) int)))
      (lambda (ring bgid)
        (func ring bgid))))

  (define io-uring-register-sync-cancel
    (let ((func (lazy-foreign-procedure liburing-ffi "io_uring_register_sync_cancel"
                                   (void* void*) int)))
      (lambda (ring reg)
        (func ring reg))))

  (define io-uring-register-file-alloc-range
    (let ((func (lazy-foreign-procedure liburing-ffi "io_uring_register_file_alloc_range"
                                   (void* unsigned unsigned) int)))
      (lambda (ring off len)
        (func ring off len))))

  (define io-uring-register-napi
    (let ((func (lazy-foreign-procedure liburing-ffi "io_uring_register_napi"
                                   (void* void*) int)))
      (lambda (ring napi)
        (func ring napi))))

  (define io-uring-unregister-napi
    (let ((func (lazy-foreign-procedure liburing-ffi "io_uring_unregister_napi"
                                   (void* void*) int)))
      (lambda (ring napi)
        (func ring napi))))

  ;;------------------------------------------------------------
  ;; Buffer ring helpers
  ;;------------------------------------------------------------

  (define io-uring-setup-buf-ring
    (let ((func (lazy-foreign-procedure liburing-ffi "io_uring_setup_buf_ring"
                                   (void* unsigned int unsigned void*) void*)))
      (lambda (ring nentries bgid flags err-ptr)
        (func ring nentries bgid flags err-ptr))))

  (define io-uring-free-buf-ring
    (let ((func (lazy-foreign-procedure liburing-ffi "io_uring_free_buf_ring"
                                   (void* void* unsigned int) int)))
      (lambda (ring br nentries bgid)
        (func ring br nentries bgid))))

  (define io-uring-buf-ring-init
    (let ((func (lazy-foreign-procedure liburing-ffi "io_uring_buf_ring_init" (void*) void)))
      (lambda (br)
        (func br))))

  (define io-uring-buf-ring-add
    (let ((func (lazy-foreign-procedure liburing-ffi "io_uring_buf_ring_add"
                                   (void* void* unsigned unsigned-16
                                          int int) void)))
      (lambda (br addr len bid mask buf-offset)
        (func br addr len bid mask buf-offset))))

  (define io-uring-buf-ring-advance
    (let ((func (lazy-foreign-procedure liburing-ffi "io_uring_buf_ring_advance"
                                   (void* int) void)))
      (lambda (br count)
        (func br count))))

  (define io-uring-buf-ring-cq-advance
    (let ((func (lazy-foreign-procedure liburing-ffi "io_uring_buf_ring_cq_advance"
                                   (void* void* int) void)))
      (lambda (ring br count)
        (func ring br count))))

  (define io-uring-buf-ring-mask
    (let ((func (lazy-foreign-procedure liburing-ffi "io_uring_buf_ring_mask"
                                   (unsigned-32) int)))
      (lambda (ring-entries)
        (func ring-entries))))

  (define io-uring-buf-ring-available
    (let ((func (lazy-foreign-procedure liburing-ffi "io_uring_buf_ring_available"
                                   (void* void* unsigned-16) int)))
      (lambda (ring br bgid)
        (func ring br bgid))))

  ;;------------------------------------------------------------
  ;; Probe
  ;;------------------------------------------------------------

  (define io-uring-get-probe
    (let ((func (lazy-foreign-procedure liburing-ffi "io_uring_get_probe" () void*)))
      (lambda ()
        (func))))

  (define io-uring-get-probe-ring
    (let ((func (lazy-foreign-procedure liburing-ffi "io_uring_get_probe_ring"
                                   (void*) void*)))
      (lambda (ring)
        (func ring))))

  (define io-uring-free-probe
    (let ((func (lazy-foreign-procedure liburing-ffi "io_uring_free_probe" (void*) void)))
      (lambda (probe)
        (func probe))))

  (define io-uring-opcode-supported
    (let ((func (lazy-foreign-procedure liburing-ffi "io_uring_opcode_supported"
                                   (void* int) int)))
      (lambda (probe op)
        (func probe op))))

  ;;------------------------------------------------------------
  ;; Misc
  ;;------------------------------------------------------------

  (define io-uring-ring-dontfork
    (let ((func (lazy-foreign-procedure liburing-ffi "io_uring_ring_dontfork"
                                   (void*) int)))
      (lambda (ring)
        (func ring))))

  (define io-uring-sqring-wait
    (let ((func (lazy-foreign-procedure liburing-ffi "io_uring_sqring_wait"
                                   (void*) int)))
      (lambda (ring)
        (func ring))))

  (define io-uring-check-version
    (let ((func (lazy-foreign-procedure liburing-ffi "io_uring_check_version"
                                   (int int) boolean)))
      (lambda (major minor)
        (func major minor))))

  (define io-uring-major-version
    (let ((func (lazy-foreign-procedure liburing-ffi "io_uring_major_version" () int)))
      (lambda ()
        (func))))

  (define io-uring-minor-version
    (let ((func (lazy-foreign-procedure liburing-ffi "io_uring_minor_version" () int)))
      (lambda ()
        (func))))

  ;;------------------------------------------------------------
  ;; Syscalls
  ;;------------------------------------------------------------

  (define io-uring-setup
    (let ((func (lazy-foreign-procedure liburing-ffi "io_uring_setup"
                                   (unsigned void*) int)))
      (lambda (entries params)
        (func entries params))))

  (define io-uring-enter
    (let ((func (lazy-foreign-procedure liburing-ffi "io_uring_enter"
                                   (unsigned unsigned unsigned unsigned void*) int)))
      (lambda (fd to-submit min-complete flags sig)
        (func fd to-submit min-complete flags sig))))

  (define io-uring-enter2
    (let ((func (lazy-foreign-procedure liburing-ffi "io_uring_enter2"
                                   (unsigned unsigned unsigned unsigned
                                             void* size_t) int)))
      (lambda (fd to-submit min-complete flags arg sz)
        (func fd to-submit min-complete flags arg sz))))

  (define io-uring-register
    (let ((func (lazy-foreign-procedure liburing-ffi "io_uring_register"
                                   (unsigned unsigned void* unsigned) int)))
      (lambda (fd opcode arg nr-args)
        (func fd opcode arg nr-args))))

  ;;------------------------------------------------------------
  ;; Recvmsg helpers
  ;;------------------------------------------------------------

  (define io-uring-recvmsg-validate
    (let ((func (lazy-foreign-procedure liburing-ffi "io_uring_recvmsg_validate"
                                   (void* int void*) void*)))
      (lambda (buf buf-len msgh)
        (func buf buf-len msgh))))

  (define io-uring-recvmsg-name
    (let ((func (lazy-foreign-procedure liburing-ffi "io_uring_recvmsg_name"
                                   (void*) void*)))
      (lambda (o)
        (func o))))

  (define io-uring-recvmsg-payload
    (let ((func (lazy-foreign-procedure liburing-ffi "io_uring_recvmsg_payload"
                                   (void* void*) void*)))
      (lambda (o msgh)
        (func o msgh))))

  (define io-uring-recvmsg-payload-length
    (let ((func (lazy-foreign-procedure liburing-ffi "io_uring_recvmsg_payload_length"
                                   (void* int void*) unsigned)))
      (lambda (o buf-len msgh)
        (func o buf-len msgh))))

  (define io-uring-recvmsg-cmsg-firsthdr
    (let ((func (lazy-foreign-procedure liburing-ffi "io_uring_recvmsg_cmsg_firsthdr"
                                   (void* void*) void*)))
      (lambda (o msgh)
        (func o msgh))))

  (define io-uring-recvmsg-cmsg-nexthdr
    (let ((func (lazy-foreign-procedure liburing-ffi "io_uring_recvmsg_cmsg_nexthdr"
                                   (void* void* void*) void*)))
      (lambda (o msgh cmsg)
        (func o msgh cmsg))))


  ;;------------------------------------------------------------
  ;; C stdlib + FFI helpers
  ;;------------------------------------------------------------

  (define stdlib (load-shared-object #f))

  ;; with-lock, bytevector-pointer, strerror are imported from
  ;; (letloop cffi) and re-exported, so importing both libraries
  ;; unrestricted stays legal (same binding, no collision).

  (define %strlen (foreign-procedure "strlen" (void*) size_t))

  (define (pointer->string p)
    (if (zero? p)
        #f
        (let* ((len (%strlen p))
               (bv (make-bytevector len)))
          (let loop ((i 0))
            (when (< i len)
              (bytevector-u8-set! bv i (foreign-ref 'unsigned-8 p i))
              (loop (+ i 1))))
          (utf8->string bv))))

  (define memcpy
    (let ((func (foreign-procedure "memcpy" (void* void* size_t) void*)))
      (lambda (dest src n) (func dest src n))))

  ;;------------------------------------------------------------
  ;; Socket constants
  ;;------------------------------------------------------------

  (define AF-INET 2)
  (define SOCK-STREAM 1)
  (define F-GETFL 3)
  (define F-SETFL 4)
  (define O-NONBLOCK 2048)
  (define POLLIN 1)
  (define POLLOUT 4)

  ;;------------------------------------------------------------
  ;; fcntl / non-blocking
  ;;------------------------------------------------------------

  (define fcntl!
    (let ((func (foreign-procedure __atomic "fcntl" (int int int) int)))
      (lambda (fd cmd arg) (func fd cmd arg))))

  (define fcntl
    (let ((func (foreign-procedure __atomic "fcntl" (int int) int)))
      (lambda (fd cmd) (func fd cmd))))

  (define loop-nonblock!
    (lambda (fd)
      (fcntl! fd F-SETFL
              (fxlogior O-NONBLOCK (fcntl fd F-GETFL)))))

  ;;------------------------------------------------------------
  ;; sockaddr_in ftype and helpers
  ;;------------------------------------------------------------

  (define-ftype <sockaddr-in>
    (struct (family unsigned-short)
            (port (endian big unsigned-16))
            (address (endian big unsigned-32))
            (padding (array 8 char))))

  (define string->ipv4
    (lambda (str)
      (define (ipv4 a b c d)
        (+ (* a 256 256 256) (* b 256 256) (* c 256) d))
      (define (split-dots s)
        (define (maybe-add a b parts)
          (if (= a b) parts (cons (substring s a b) parts)))
        (let ((n (string-length s)))
          (let loop ((a 0) (b 0) (parts '()))
            (if (< b n)
                (if (char=? (string-ref s b) #\.)
                    (loop (+ b 1) (+ b 1) (maybe-add a b parts))
                    (loop a (+ b 1) parts))
                (reverse (maybe-add a b parts))))))
      (apply ipv4 (map string->number (split-dots str)))))

  ;; Returns (values foreign-ptr addrlen)
  (define make-sockaddr-in
    (lambda (a b c d port)
      (let* ((ptr (foreign-alloc (ftype-sizeof <sockaddr-in>)))
             (addr (make-ftype-pointer <sockaddr-in> ptr)))
        (ftype-set! <sockaddr-in> (family) addr 2)
        (ftype-set! <sockaddr-in> (port) addr port)
        (ftype-set! <sockaddr-in> (address) addr
                    (string->ipv4 (format #f "~a.~a.~a.~a" a b c d)))
        (values ptr (ftype-sizeof <sockaddr-in>)))))

  ;;------------------------------------------------------------
  ;; bytevector utility
  ;;------------------------------------------------------------

  (define subbytevector
    (case-lambda
     ((bv start end)
      (assert (bytevector? bv))
      (unless (<= 0 start end (bytevector-length bv))
        (error 'subbytevector "Invalid indices" bv start end))
      (if (and (fxzero? start) (fx=? end (bytevector-length bv)))
          bv
          (let ((ret (make-bytevector (fx- end start))))
            (bytevector-copy! bv start ret 0 (fx- end start))
            ret)))
     ((bv start)
      (subbytevector bv start (bytevector-length bv)))))

  ;;------------------------------------------------------------
  ;; Socket syscall wrappers
  ;;------------------------------------------------------------

  (define loop-socket-new
    (let ((func (foreign-procedure __atomic __disable_interrupts __errno
                                   "socket" (int int int) int)))
      (lambda (domain type protocol)
        (call-with-values (lambda () (func domain type protocol))
          (lambda (out errno)
            (if (fx=? out -1) #f out))))))

  (define loop-socket-option!
    (let ((func (foreign-procedure __atomic __disable_interrupts __errno
                                   "setsockopt" (int int int void* int) int)))
      (lambda (fd level optname optval)
        (define (doit opt-int)
          (let* ((size (ftype-sizeof int))
                 (ptr (foreign-alloc size)))
            (foreign-set! 'int ptr 0 (if optval 1 0))
            (call-with-values (lambda () (func fd level opt-int ptr size))
              (lambda (out errno)
                (foreign-free ptr)
                (if (fxzero? out)
                    #t
                    (error 'loop-socket-option!
                           (format #f "setsockopt errno ~a" (strerror errno))
                           fd))))))
        (case optname
          ((socket-option/debug)     (doit 1))
          ((socket-option/reuseaddr) (doit 2))
          ((socket-option/dontroute) (doit 5))
          ((socket-option/broadcast) (doit 6))
          ((socket-option/keepalive) (doit 9))
          ((socket-option/oobinline) (doit 10))
          ((socket-option/reuseport) (doit 15))
          ((tcp-option/nodelay)      (doit 1))
          (else (error 'loop-socket-option! "Unknown socket option"
                       fd level optname optval))))))

  (define loop-socket-error?
    (let ((func (foreign-procedure __atomic __disable_interrupts __errno
                                   "getsockopt" (int int int void* void*) int)))
      (lambda (fd)
        (let* ((val-size (ftype-sizeof int))
               (val-ptr (foreign-alloc val-size))
               (len-ptr (foreign-alloc (ftype-sizeof int))))
          (foreign-set! 'int val-ptr 0 0)
          (foreign-set! 'int len-ptr 0 val-size)
          (call-with-values (lambda () (func fd 1 4 val-ptr len-ptr))
            (lambda (out errno)
              (let ((so-error (foreign-ref 'int val-ptr 0)))
                (foreign-free len-ptr)
                (foreign-free val-ptr)
                (not (fxzero? so-error)))))))))

  (define loop-bind
    (let ((func (foreign-procedure __atomic __disable_interrupts __errno
                                   "bind" (int void* size_t) int)))
      (lambda (fd ip port)
        (loop-socket-option! fd 1 'socket-option/reuseaddr #t)
        (loop-socket-option! fd 1 'socket-option/reuseport #t)
        (let* ((ptr (foreign-alloc (ftype-sizeof <sockaddr-in>)))
               (addr (make-ftype-pointer <sockaddr-in> ptr)))
          (ftype-set! <sockaddr-in> (family) addr 2)
          (ftype-set! <sockaddr-in> (port) addr port)
          (ftype-set! <sockaddr-in> (address) addr (string->ipv4 ip))
          (call-with-values
              (lambda () (func fd ptr (ftype-sizeof <sockaddr-in>)))
            (lambda (out errno)
              (foreign-free ptr)
              (unless (fxzero? out)
                (error 'loop-bind
                       (format #f "bind errno ~a" (strerror errno))))))))))

  (define loop-listen
    (let ((func (foreign-procedure __atomic __disable_interrupts __errno
                                   "listen" (int int) int)))
      (lambda (fd backlog)
        (call-with-values (lambda () (func fd backlog))
          (lambda (out errno)
            (unless (fxzero? out)
              (error 'loop-listen
                     (format #f "listen errno ~a" (strerror errno)))))))))

  (define loop-getpeername
    (let ((func (foreign-procedure __atomic __disable_interrupts __errno
                                   "getpeername" (int void* void*) int)))
      (lambda (fd)
        (let* ((ptr (foreign-alloc (ftype-sizeof <sockaddr-in>)))
               (addr (make-ftype-pointer <sockaddr-in> ptr))
               (len-ptr (foreign-alloc (foreign-sizeof 'unsigned-32))))
          (foreign-set! 'unsigned-32 len-ptr 0 (ftype-sizeof <sockaddr-in>))
          (call-with-values (lambda () (func fd ptr len-ptr))
            (lambda (out errno)
              (let ((ip (if (fxzero? out)
                            (let ((raw (ftype-ref <sockaddr-in> (address) addr)))
                              (format #f "~a.~a.~a.~a"
                                      (fxsrl raw 24)
                                      (fxand (fxsrl raw 16) #xff)
                                      (fxand (fxsrl raw 8) #xff)
                                      (fxand raw #xff)))
                            #f)))
                (foreign-free len-ptr)
                (foreign-free ptr)
                ip)))))))

  ;;------------------------------------------------------------
  ;; Event loop globals
  ;;------------------------------------------------------------

  (define %loop #f)
  (define %multishots (make-eqv-hashtable))
  (define %multishot-ids (make-eqv-hashtable))
  (define %buf-ring-nentries 4096)
  (define %buf-ring-buf-size 4096)
  (define %buf-ring-bgid 0)
  (define %buf-ring #f)
  (define %buf-ring-base 0)
  (define %buf-ring-mask 0)
  (define %buf-data (make-eqv-hashtable))
  (define %fd-handlers (make-eqv-hashtable))
  (define %active-connections (make-eqv-hashtable))
  ;; listen fd → FIFO list of client fds accepted by the multishot
  ;; while no loop-accept waiter was parked; loop-accept pops from
  ;; here before parking, so already-accepted clients are not leaked.
  (define %accept-backlog (make-eqv-hashtable))
  ;; fd → FIFO list of payloads a recv completed for a waiter that had
  ;; already lost its choice. The accept side has had %accept-backlog
  ;; from the start for exactly this reason; recv needs it more, because
  ;; a dropped payload is data the kernel has already taken off the
  ;; socket and nobody can ask for again. Kept here rather than in the
  ;; caller so loop-close-prep! purges it with everything else the fd
  ;; owns — a stash keyed by an fd number that outlives the fd would
  ;; hand a stale payload to whatever reopens that number.
  (define %recv-backlog (make-eqv-hashtable))
  (define ECANCELED 125)
  (define %read-timeout-seconds 5)
  (define %read-timeout-ts #f)
  (define %wait-timeout #f)

  ;;------------------------------------------------------------
  ;; Event loop record
  ;;------------------------------------------------------------

  (define-record-type* <loop>
    (loop-base-new jiffy sleeping running ring cqe-ptr handlers next-id thunks)
    loop?
    (jiffy %loop-jiffy %loop-jiffy!)
    (sleeping loop-sleeping loop-sleeping!)
    (running loop-running? loop-running!)
    (ring loop-ring)
    (cqe-ptr loop-cqe-ptr)
    (handlers loop-handlers)
    (next-id loop-next-id loop-next-id!)
    (thunks loop-thunks loop-thunks!))

  (define loop-alloc-id!
    (lambda ()
      (let ((id (loop-next-id %loop)))
        (loop-next-id! %loop (fx+ id 1))
        id)))

  ;; io_uring_get_sqe returns NULL when the submission queue is full
  ;; (256 entries; loop-run-once runs every queued thunk to its first
  ;; suspension before submitting, so >256 operations queued in one
  ;; tick exhaust the ring). Flush with io_uring_submit and retry once
  ;; before giving up, so prep helpers never write through NULL.
  (define loop-get-sqe
    (lambda (ring)
      (let ((sqe (io-uring-get-sqe ring)))
        (if (eqv? sqe 0)
            (begin
              (io-uring-submit ring)
              (let ((sqe (io-uring-get-sqe ring)))
                (if (eqv? sqe 0)
                    (error 'loop "submission queue full")
                    sqe)))
            sqe))))

  ;; The loop installed by the latest loop-new, #f outside loop-run.
  (define loop-current
    (lambda ()
      %loop))

  ;; The current loop's cached per-tick timestamp -- refreshed once per
  ;; loop-run-once iteration (see there), not on every call. One real
  ;; jiffy-current syscall per event-loop tick instead of one per
  ;; caller, for anything (e.g. flow-log) that wants to timestamp far
  ;; more often than once per tick.
  (define loop-jiffy
    (lambda ()
      (%loop-jiffy %loop)))

  ;; fd → jiffy of last read/write activity, maintained by the read
  ;; and write paths; lets callers reap idle connections.
  (define loop-active-connections
    (lambda ()
      %active-connections))

  ;; Provided-buffer-ring accessors, for libraries (e.g. (letloop
  ;; flow)'s flow-read) that want the zero-per-call-allocation recv
  ;; path loop-read already uses instead of a private bytevector.
  ;; %buf-ring-bgid/%buf-ring-buf-size/%buf-data can't be exported
  ;; directly -- R6RS forbids exporting an assigned variable, and
  ;; loop-new mutates all three -- so these wrap them the same way
  ;; loop-current wraps %loop.
  (define loop-buf-ring-bgid (lambda () %buf-ring-bgid))
  (define loop-buf-ring-buf-size (lambda () %buf-ring-buf-size))

  ;; Look up and remove ID's completion bytevector in one step: every
  ;; loop-read/flow-read call site immediately deletes what it reads,
  ;; across all three outcomes (error, EOF, data).
  (define loop-buf-data-take!
    (lambda (id)
      (let ((bv (hashtable-ref %buf-data id #f)))
        (hashtable-delete! %buf-data id)
        bv)))

  ;;------------------------------------------------------------
  ;; Continuation machinery
  ;;------------------------------------------------------------

  (define loop-prompt-current #f)
  (define loop-prompt-singleton '(loop-prompt-singleton))

  (define call-with-loop-prompt
    (lambda (thunk handlery)
      (call-with-values
          (lambda ()
            (call/1cc
             (lambda (k)
               (set! loop-prompt-current k)
               (call-with-values thunk
                 (lambda out
                   (let ((prompt loop-prompt-current))
                     (set! loop-prompt-current #f)
                     (cond
                      ;; Still our own prompt: the fiber never
                      ;; suspended, so this frame is the live one and a
                      ;; plain return lands exactly where invoking k
                      ;; would. Keep the cheap path — and keep the
                      ;; one-shot k unshot — for the common case.
                      ((eq? prompt k) (apply values out))
                      ;; The fiber suspended at some point and is being
                      ;; resumed by another loop-apply: hand the values
                      ;; to *that* prompt rather than falling into this
                      ;; frame's stale continuation.
                      (prompt (apply prompt out))
                      ;; No prompt at all (should not happen: every
                      ;; fiber body runs under loop-apply). Degrade to
                      ;; the pre-fix behaviour rather than erroring
                      ;; inside the scheduler.
                      (else (apply values out)))))))))
        (lambda out
          (cond
           ((and (pair? out) (eq? (car out) loop-prompt-singleton))
            (apply handlery (cdr out)))
           (else (apply values out)))))))

  (define loop-abort
    (lambda args
      (call/1cc
       (lambda (k)
         (let ((prompt loop-prompt-current))
           (set! loop-prompt-current #f)
           (apply prompt (cons loop-prompt-singleton (cons k args))))))))

  ;; The catch-all guard keeps a fiber's crash from killing the whole
  ;; scheduler, but swallowing it *silently* turns any unguarded-fiber
  ;; bug into an undebuggable hang: the dead fiber's channel peers park
  ;; forever with zero CPU and zero output (the exact signature of a
  ;; lost-wakeup, which it is not). Report what died on stderr — the
  ;; fiber is still gone (loop-spawn-monitored is the eventual real
  ;; answer for delivery to supervisors), but the failure is at least
  ;; visible and attributable.
  (define loop-apply
    (lambda (thunk)
      (guard (ex (else
                  (display "loop-apply: fiber died: " (current-error-port))
                  (if (condition? ex)
                      (display-condition ex (current-error-port))
                      (display ex (current-error-port)))
                  (newline (current-error-port))
                  (flush-output-port (current-error-port))
                  (void)))
        (call-with-loop-prompt thunk (lambda (k handler) (handler k))))))

  ;;------------------------------------------------------------
  ;; Time
  ;;------------------------------------------------------------

  (define jiffy-current
    (lambda ()
      (let* ((time (current-time 'time-monotonic))
             (seconds (time-second time))
             (nanoseconds (time-nanosecond time)))
        (+ (* seconds (expt 10 9)) nanoseconds))))

  ;;------------------------------------------------------------
  ;; Event loop lifecycle
  ;;------------------------------------------------------------

  (define loop-run-once
    (lambda ()
      ;; Refresh the cached per-tick timestamp before any thunk or
      ;; handler runs this iteration -- one jiffy-current syscall per
      ;; tick, not one per loop-jiffy caller (see loop-jiffy above).
      (%loop-jiffy! %loop (jiffy-current))

      (let ((thunks (loop-thunks %loop)))
        (loop-thunks! %loop '())
        (for-each (lambda (thunk) (loop-apply thunk)) thunks))

      (let ((ring (loop-ring %loop))
            (cqe-ptr (loop-cqe-ptr %loop)))
        (let ((has-handlers? (not (fxzero? (hashtable-size (loop-handlers %loop)))))
              (has-pending?  (not (fxzero? (io-uring-sq-ready ring))))
              ;; Thunks queued *during* this tick: a fiber spawned work
              ;; and then parked. They are runnable right now, so this
              ;; tick must not block waiting for completions -- doing so
              ;; delayed every spawned fiber by up to %wait-timeout
              ;; (100ms), which is what a fan-out pays before any of its
              ;; workers start. The drain below uses a non-blocking peek,
              ;; so completions that are already there are still taken.
              (has-thunks?   (pair? (loop-thunks %loop))))
          (cond
           (has-thunks?
            (when has-pending? (io-uring-submit ring)))
           (has-handlers?
            (io-uring-submit ring)
            (io-uring-wait-cqe-timeout ring cqe-ptr %wait-timeout))
           (has-pending?
            (io-uring-submit ring))
           (else
            (io-uring-wait-cqe-timeout ring cqe-ptr %wait-timeout))))

        (let drain ()
          (when (fxzero? (io-uring-peek-cqe ring cqe-ptr))
            (let* ((cqe   (foreign-ref 'void* cqe-ptr 0))
                   (id    (io-uring-cqe-get-data64 cqe))
                   (res   (io-uring-cqe-get-res cqe))
                   (flags (io-uring-cqe-get-flags cqe)))
              (io-uring-cqe-seen ring cqe)
              (let ((ms-fd (hashtable-ref %multishot-ids id #f)))
                (when (and ms-fd (fxzero? (fxlogand flags IORING-CQE-F-MORE)))
                  (hashtable-delete! %multishot-ids id)
                  (hashtable-delete! %multishots ms-fd))
                (when (and (fx>? res 0)
                           (not (fxzero? (fxlogand flags IORING-CQE-F-BUFFER))))
                  (let* ((bid      (fxsrl (fxlogand flags #xFFFF0000) 16))
                         (buf-addr (+ %buf-ring-base (* bid %buf-ring-buf-size)))
                         (bv       (make-bytevector res)))
                    (with-lock (list bv)
                      (memcpy (bytevector-pointer bv) buf-addr res))
                    (io-uring-buf-ring-add %buf-ring buf-addr %buf-ring-buf-size
                                           bid %buf-ring-mask 0)
                    (io-uring-buf-ring-advance %buf-ring 1)
                    (hashtable-set! %buf-data id bv)))
                (let ((handler (hashtable-ref (loop-handlers %loop) id #f)))
                  (hashtable-delete! (loop-handlers %loop) id)
                  (cond
                   (handler
                    (loop-apply (lambda () (handler res))))
                   ((and ms-fd (fx>=? res 0))
                    ;; Multishot-accept CQE with no waiter parked: the
                    ;; kernel already accepted this client, so queue the
                    ;; fd for the next loop-accept instead of leaking it.
                    (hashtable-set! %accept-backlog ms-fd
                                    (append (hashtable-ref %accept-backlog ms-fd '())
                                            (list res))))
                   (else
                    ;; No handler claims this id — loop-close-prep!
                    ;; already resumed the fd's parked reads with
                    ;; -ECANCELED and deleted their handlers, but a
                    ;; recv that completed with data before the async
                    ;; cancel landed still delivers a CQE with
                    ;; F_BUFFER, and the stash above just ran. Drop
                    ;; the orphan or it stays in %buf-data forever.
                    (hashtable-delete! %buf-data id))))))
            (drain)))

        (when (not (fxzero? (io-uring-sq-ready ring)))
          (io-uring-submit ring)))))

  (define loop-run
    (lambda ()
      (let lp ()
        (when (loop-running? %loop)
          (guard (ex (else (loop-running! %loop #f)))
            (loop-run-once))
          (lp)))))

  (define loop-spawn
    (lambda (thunk)
      (loop-thunks! %loop (cons thunk (loop-thunks %loop)))))

  (define loop-new
    (lambda ()
      ;; Tear down the previous ring, if any, so repeated loop-new does
      ;; not leak the ring, cqe pointer, buffer ring, and buffer base.
      (when %loop
        (when %buf-ring
          (io-uring-free-buf-ring (loop-ring %loop) %buf-ring
                                  %buf-ring-nentries %buf-ring-bgid)
          (foreign-free %buf-ring-base)
          (set! %buf-ring #f)
          (set! %buf-ring-base 0))
        (io-uring-queue-exit (loop-ring %loop))
        (foreign-free (loop-ring %loop))
        (foreign-free (loop-cqe-ptr %loop))
        (set! %loop #f))
      (let ((ring     (make-io-uring))
            (cqe-ptr  (make-cqe-pointer))
            (handlers (make-eqv-hashtable)))
        (let ((ret (io-uring-queue-init 512 ring 0)))
          (unless (fxzero? ret)
            (error 'loop-new
                   (format #f "io_uring_queue_init failed: ~a"
                           (strerror (fx- 0 ret))))))
        (set! %loop
          (loop-base-new (jiffy-current) '() #t ring cqe-ptr handlers 0 '()))
        (set! %read-timeout-ts  (make-timespec %read-timeout-seconds 0))
        ;; LETLOOP_WAIT_TIMEOUT_MS: the loop's idle CQE-wait tick.
        ;; Default 100ms, the historical constant; env-tunable so an
        ;; A/B benchmark (e.g. atlas-stoa 0x0042's serve runs) can try
        ;; a shorter tick without a source edit.
        (set! %wait-timeout
          (let* ((env (getenv "LETLOOP_WAIT_TIMEOUT_MS"))
                 (ms (or (and env (string->number env)) 100)))
            (make-timespec (div ms 1000) (* (mod ms 1000) 1000000))))
        (set! %multishots       (make-eqv-hashtable))
        (set! %multishot-ids    (make-eqv-hashtable))
        (set! %buf-data         (make-eqv-hashtable))
        (set! %fd-handlers      (make-eqv-hashtable))
        (set! %active-connections (make-eqv-hashtable))
        (set! %accept-backlog   (make-eqv-hashtable))
        (set! %recv-backlog     (make-eqv-hashtable))
        (let ((err-ptr (foreign-alloc 4)))
          (foreign-set! 'integer-32 err-ptr 0 0)
          (let ((br (io-uring-setup-buf-ring ring %buf-ring-nentries
                                             %buf-ring-bgid 0 err-ptr)))
            (let ((err (foreign-ref 'integer-32 err-ptr 0)))
              (foreign-free err-ptr)
              (when (eqv? br 0)
                (error 'loop-new
                       (format #f "io_uring_setup_buf_ring failed: ~a"
                               (strerror (fx- 0 err))))))
            (let ((base (foreign-alloc (* %buf-ring-nentries %buf-ring-buf-size)))
                  (mask (io-uring-buf-ring-mask %buf-ring-nentries)))
              (let fill ((i 0))
                (when (fx<? i %buf-ring-nentries)
                  (io-uring-buf-ring-add br (+ base (* i %buf-ring-buf-size))
                                          %buf-ring-buf-size i mask i)
                  (fill (fx+ i 1))))
              (io-uring-buf-ring-advance br %buf-ring-nentries)
              (set! %buf-ring      br)
              (set! %buf-ring-base base)
              (set! %buf-ring-mask mask))))
        %loop)))

  (define loop-stop
    (lambda ()
      (loop-running! %loop #f)
      (let-values (((keys vals) (hashtable-entries %multishots)))
        (vector-for-each
          (lambda (fd id)
            (let ((sqe (loop-get-sqe (loop-ring %loop))))
              (io-uring-prep-cancel64 sqe id 0)
              (io-uring-sqe-set-data64 sqe (loop-alloc-id!))))
          keys vals))
      (when (not (fxzero? (io-uring-sq-ready (loop-ring %loop))))
        (io-uring-submit (loop-ring %loop)))))

  ;;------------------------------------------------------------
  ;; Async I/O operations
  ;;------------------------------------------------------------

  ;; loop-close's teardown and submission, shared by loop-close (which
  ;; parks the caller's continuation on the close CQE) and
  ;; loop-close-block (which registers a supplied handler instead, for
  ;; libraries — e.g. (letloop flow) — that must not suspend the
  ;; calling fiber here), the same split loop-accept-try/
  ;; loop-accept-block already provides for accept. Returns the close
  ;; op's id; the caller registers its handler/continuation against it
  ;; as its very next step — safe, because nothing here is submitted
  ;; until the next loop tick and no drain can run in between.
  ;;
  ;; Deliberately NOT called from inside loop-abort's callback:
  ;; everything below runs on the *caller's* stack, so a loop-get-sqe
  ;; failure (submission queue full even after a flush — this preps up
  ;; to 2+N SQEs) raises into the caller, catchable by the established
  ;; guard-wrapped-loop-close error-path idiom (tls/uring, postgresql).
  ;; Run under loop-abort it would instead be swallowed by loop-apply's
  ;; catch-all guard, leaving the fiber parked forever with no error.
  ;;
  ;; Nothing below is socket-specific: a file fd simply has no entry in
  ;; %fd-handlers, %accept-backlog or %active-connections (every lookup
  ;; defaults to '() and every delete of an absent key is a no-op).
  ;; Its IORING_OP_ASYNC_CANCEL is not necessarily a no-op, though: it
  ;; also matches file ops other fibers still have in flight on this fd
  ;; ((letloop flow)'s flow-read-at/flow-write-at). Those register in
  ;; loop-handlers only, never %fd-handlers, so the synthetic-resume
  ;; pass below skips them — their -ECANCELED CQEs still find their
  ;; handlers, which unlock their buffers and resume their parked
  ;; fibers through the normal error path. Either way regular files
  ;; need no separate teardown.
  (define loop-close-prep!
    (lambda (fd)
      ;; Resume every coroutine parked on this fd with a synthetic
      ;; failed completion (-ECANCELED), mimicking the CQE drain, so
      ;; each one unlocks its buffers and takes its normal error path
      ;; instead of being abandoned mid-suspension. The real CQEs for
      ;; the cancelled operations find no handler and are dropped.
      (let ((ids (hashtable-ref %fd-handlers fd '())))
        (for-each (lambda (id)
                    (let ((parked (hashtable-ref (loop-handlers %loop) id #f)))
                      (hashtable-delete! (loop-handlers %loop) id)
                      (when parked
                        (loop-spawn (lambda () (parked (fx- 0 ECANCELED)))))))
                  ids)
        (hashtable-delete! %fd-handlers fd))
      ;; Clients accepted by the multishot but never claimed by
      ;; loop-accept: close them too, fire-and-forget.
      (for-each (lambda (client)
                  (let* ((sqe (loop-get-sqe (loop-ring %loop)))
                         (id  (loop-alloc-id!)))
                    (io-uring-prep-close sqe client)
                    (io-uring-sqe-set-data64 sqe id)))
                (hashtable-ref %accept-backlog fd '()))
      (hashtable-delete! %accept-backlog fd)
      ;; Payloads nobody claimed: dropping them here is correct and is
      ;; the whole reason the stash lives at this level. The fd is going
      ;; away, so there is no one left to deliver them to, and leaving
      ;; them keyed by a number the kernel is about to reissue is how a
      ;; stash becomes a cross-connection data leak.
      (hashtable-delete! %recv-backlog fd)
      (hashtable-delete! %active-connections fd)
      (let* ((cancel-sqe (loop-get-sqe (loop-ring %loop)))
             (cancel-id  (loop-alloc-id!)))
        (io-uring-prep-cancel-fd cancel-sqe fd IORING-ASYNC-CANCEL-ALL)
        (io-uring-sqe-set-data64 cancel-sqe cancel-id))
      (let* ((sqe (loop-get-sqe (loop-ring %loop)))
             (id  (loop-alloc-id!)))
        (io-uring-prep-close sqe fd)
        (io-uring-sqe-set-data64 sqe id)
        id)))

  (define loop-close-block
    (lambda (fd handler)
      (let ((id (loop-close-prep! fd)))
        (hashtable-set! (loop-handlers %loop) id handler))))

  ;; Teardown and prep run on the caller's stack, before the abort —
  ;; see loop-close-prep!'s comment: an SQ-full error must raise here,
  ;; into the caller, not vanish inside loop-apply's guard.
  (define loop-close
    (lambda (fd)
      (let ((id (loop-close-prep! fd)))
        (loop-abort
         (lambda (k)
           (hashtable-set! (loop-handlers %loop) id k))))))

  (define loop-accept-client-setup!
    (lambda (client)
      (loop-socket-option! client 6 'tcp-option/nodelay  #t)
      (loop-socket-option! client 1 'socket-option/keepalive #t)
      (hashtable-set! %active-connections client (jiffy-current))
      client))

  ;; Non-blocking: pop a client the multishot already accepted while
  ;; nobody was parked, or #f if the backlog is empty. Never arms the
  ;; multishot itself — only loop-accept-block does that.
  (define loop-accept-try
    (lambda (fd)
      (let ((backlog (hashtable-ref %accept-backlog fd '())))
        (and (pair? backlog)
             (begin
               (if (null? (cdr backlog))
                   (hashtable-delete! %accept-backlog fd)
                   (hashtable-set! %accept-backlog fd (cdr backlog)))
               (loop-accept-client-setup! (car backlog)))))))

  ;; The recv counterpart of the accept backlog, for a caller whose
  ;; recv handler completed with data that its own waiter can no longer
  ;; take — it lost a flow-choice, or its scope was cancelled, in the
  ;; same tick the CQE arrived. Both CQEs sit in the completion queue
  ;; together whenever the loop is late draining, which is under load,
  ;; which is exactly when an idle timeout races a read.
  ;;
  ;; Unlike a declined accept there is no way to put a payload back:
  ;; the kernel has already taken those bytes off the socket, so
  ;; dropping them is silent data loss for the connection. Push it here
  ;; instead and the next recv on the fd finds it.
  ;;
  ;; Nothing here can tell a live fd from one loop-close-prep! has
  ;; already purged, and a put after that purge is a cross-connection
  ;; data leak once the kernel reissues the number. What keeps that
  ;; from happening is upstream: a recv registered through
  ;; loop-fd-op-add! has its handler deleted by the purge, so the late
  ;; CQE never reaches the code that would call this. A caller that
  ;; skips that registration reopens the leak.
  (define loop-recv-backlog-put!
    (lambda (fd payload)
      (hashtable-set! %recv-backlog fd
                      (append (hashtable-ref %recv-backlog fd '())
                              (list payload)))))

  ;; Register/unregister ID as an operation in flight on FD, so
  ;; loop-close-prep! can resume it with a synthetic -ECANCELED and
  ;; take its handler out of loop-handlers. Two things follow from
  ;; being in this index, and both matter for a socket:
  ;;
  ;; - the parked fiber wakes on the close instead of on the CQE, and
  ;; - the operation's REAL completion then finds no handler and is
  ;;   dropped by the drain -- which is the only thing that stops a
  ;;   recv that completed with data just before the cancel landed
  ;;   from running its handler after the fd is gone.
  ;;
  ;; Every registration must be undone on every completion path, or
  ;; the list grows for the life of the connection.
  (define loop-fd-op-add!
    (lambda (fd id)
      (hashtable-set! %fd-handlers fd
                      (cons id (hashtable-ref %fd-handlers fd '())))))

  ;; Deletes the key when the last operation goes, rather than leaving
  ;; an empty list behind under an fd number the kernel will reissue.
  (define loop-fd-op-remove!
    (lambda (fd id)
      (let ((ids (remq id (hashtable-ref %fd-handlers fd '()))))
        (if (null? ids)
            (hashtable-delete! %fd-handlers fd)
            (hashtable-set! %fd-handlers fd ids)))))

  ;; Non-blocking: pop the oldest stashed payload for FD, or #f.
  (define loop-recv-backlog-take!
    (lambda (fd)
      (let ((backlog (hashtable-ref %recv-backlog fd '())))
        (and (pair? backlog)
             (begin
               (if (null? (cdr backlog))
                   (hashtable-delete! %recv-backlog fd)
                   (hashtable-set! %recv-backlog fd (cdr backlog)))
               (car backlog))))))

  ;; Arms fd's multishot accept if it isn't already running, then
  ;; registers HANDLER against its next completion. HANDLER is called
  ;; with a set-up client fd, or #f on an error (which always tears
  ;; the multishot down first, same as before this was split out).
  ;; HANDLER returns #t to claim the client, #f to decline (e.g. lost
  ;; a race to a sibling event); a declined client is pushed onto the
  ;; backlog exactly like a multishot completion nobody was waiting
  ;; for, rather than being leaked.
  ;;
  ;; Returns the id HANDLER was registered under, so a caller that must
  ;; UNregister it can — a composed accept whose sibling event wins, or
  ;; whose scope is cancelled, has to take its handler back out of
  ;; loop-handlers or the slot stays occupied and the very next
  ;; loop-accept-block on that fd hits the concurrent-accept error
  ;; below, permanently poisoning the listener. Deleting the handler is
  ;; enough and loses nothing: a client the multishot accepts with no
  ;; handler registered lands on %accept-backlog, exactly as it does
  ;; for any other unwaited-for completion. (Previously the return
  ;; value was hashtable-set!'s, which no caller used.)
  (define loop-accept-block
    (lambda (fd handler)
      (let ((active-id (hashtable-ref %multishots fd #f)))
        (unless active-id
          (let* ((sqe (loop-get-sqe (loop-ring %loop)))
                 (id  (loop-alloc-id!)))
            (io-uring-prep-multishot-accept sqe fd 0 0 0)
            (io-uring-sqe-set-data64 sqe id)
            (hashtable-set! %multishots fd id)
            (hashtable-set! %multishot-ids id fd)
            (set! active-id id)))
        ;; A single continuation slot is keyed by active-id; a second
        ;; concurrent waiter would silently overwrite the first one,
        ;; abandoning its coroutine.
        (when (hashtable-ref (loop-handlers %loop) active-id #f)
          (error 'loop-accept-block "concurrent accept on fd" fd))
        (hashtable-set! (loop-handlers %loop) active-id
          (lambda (res)
            (if (fx<? res 0)
                (begin
                  (let ((mid (hashtable-ref %multishots fd #f)))
                    (when mid
                      (hashtable-delete! %multishots fd)
                      (hashtable-delete! %multishot-ids mid)))
                  (handler #f))
                (let ((client (loop-accept-client-setup! res)))
                  (unless (handler client)
                    (hashtable-set! %accept-backlog fd
                      (append (hashtable-ref %accept-backlog fd '())
                              (list client))))))))
        active-id)))

  (define loop-accept
    (lambda (fd)
      (or (loop-accept-try fd)
          (loop-abort
           (lambda (k)
             (loop-accept-block fd (lambda (client) (k client) #t)))))))

  (define loop-read
    (lambda (fd)
      (let* ((sqe (loop-get-sqe (loop-ring %loop)))
             (id  (loop-alloc-id!)))
        (io-uring-prep-recv sqe fd 0 %buf-ring-buf-size 0)
        (io-uring-sqe-set-flags sqe IOSQE-BUFFER-SELECT)
        (io-uring-sqe-set-buf-group sqe %buf-ring-bgid)
        (io-uring-sqe-set-data64 sqe id)
        (loop-fd-op-add! fd id)
        (let ((res (loop-abort
                     (lambda (k)
                       (hashtable-set! (loop-handlers %loop) id k)))))
          (loop-fd-op-remove! fd id)
          (cond
           ((fx<? res 0)
            (hashtable-delete! %buf-data id)
            #f)
           ((fxzero? res)
            (hashtable-delete! %buf-data id)
            #t)
           (else
            (hashtable-set! %active-connections fd (jiffy-current))
            (let ((bv (hashtable-ref %buf-data id #f)))
              (hashtable-delete! %buf-data id)
              bv)))))))

  (define loop-write
    (lambda (fd bv)
      (let write-loop ((bv bv))
        (lock-object bv)
        (let* ((sqe (loop-get-sqe (loop-ring %loop)))
               (id  (loop-alloc-id!)))
          (io-uring-prep-send sqe fd (bytevector-pointer bv)
                              (bytevector-length bv) 0)
          (io-uring-sqe-set-data64 sqe id)
          (loop-fd-op-add! fd id)
          (let ((res (loop-abort
                       (lambda (k)
                         (hashtable-set! (loop-handlers %loop) id k)))))
            (loop-fd-op-remove! fd id)
            (unlock-object bv)
            (cond
             ((fx<=? res 0) #f)
             ((fx=? res (bytevector-length bv)) #t)
             (else (write-loop (subbytevector bv res)))))))))

  ;; A stalled connect (peer or a middlebox silently drops the SYN, no
  ;; RST ever arrives) has no other timeout anywhere in the io_uring
  ;; path -- unlike a poll wait, io_uring gives a bare connect no
  ;; built-in deadline, so the fiber (and the whole single-threaded
  ;; reactor behind it) would park forever. Race an IORING_OP_TIMEOUT
  ;; against the IORING_OP_CONNECT exactly as %tls-poll-wait races one
  ;; against a poll: whichever completes first cancels the other and
  ;; resumes the fiber.
  (define loop-connect-timeout-seconds (make-parameter 30))

  (define loop-connect
    (lambda (addr addrlen)
      (let ((fd (loop-socket-new AF-INET SOCK-STREAM 0)))
        (unless fd (error 'loop-connect "socket() failed"))
        (loop-nonblock! fd)
        (let* ((ring (loop-ring %loop))
               (connect-sqe (loop-get-sqe ring))
               (connect-id  (loop-alloc-id!)))
          (io-uring-prep-connect connect-sqe fd addr addrlen)
          (io-uring-sqe-set-data64 connect-sqe connect-id)
          (let* ((timeout-sqe (loop-get-sqe ring))
                 (timeout-id  (loop-alloc-id!))
                 (ts (make-timespec (loop-connect-timeout-seconds) 0)))
            (io-uring-prep-timeout timeout-sqe (ftype-pointer-address ts) 0 0)
            (io-uring-sqe-set-data64 timeout-sqe timeout-id)
            (let ((res (loop-abort
                         (lambda (k)
                           (let ((handlers (loop-handlers %loop)))
                             ;; The drain deletes the fired id's own
                             ;; handler before calling it; each winner
                             ;; deletes the loser's handler and preps a
                             ;; cancel for it, so the loser's eventual
                             ;; CQE (-ECANCELED or the race's late
                             ;; completion) finds no handler and is
                             ;; dropped.
                             (hashtable-set! handlers connect-id
                               (lambda (res)
                                 (hashtable-delete! handlers timeout-id)
                                 (let ((sqe (loop-get-sqe ring)))
                                   (io-uring-prep-cancel64 sqe timeout-id 0)
                                   (io-uring-sqe-set-data64 sqe (loop-alloc-id!)))
                                 (k res)))
                             (hashtable-set! handlers timeout-id
                               (lambda (_res)
                                 (hashtable-delete! handlers connect-id)
                                 (let ((sqe (loop-get-sqe ring)))
                                   (io-uring-prep-cancel64 sqe connect-id 0)
                                   (io-uring-sqe-set-data64 sqe (loop-alloc-id!)))
                                 (k 'timeout))))))))
              (foreign-free (ftype-pointer-address ts))
              (if (or (eq? res 'timeout) (fx<? res 0))
                  (begin (loop-close fd) #f)
                  fd)))))))

  (define loop-sleep
    (lambda (seconds)
      (let* ((ns  (exact (round (* seconds 1000000000))))
             (sqe (loop-get-sqe (loop-ring %loop)))
             (id  (loop-alloc-id!))
             (ts  (make-timespec (div ns 1000000000)
                                 (mod ns 1000000000))))
        (io-uring-prep-timeout sqe (ftype-pointer-address ts) 0 0)
        (io-uring-sqe-set-data64 sqe id)
        (let ((res (loop-abort
                     (lambda (k)
                       (hashtable-set! (loop-handlers %loop) id k)))))
          (foreign-free (ftype-pointer-address ts))
          res))))

  (define loop-tcp-serve
    (lambda (ip port)
      (define SOCKET-DOMAIN=AF-INET 2)
      (define SOCKET-TYPE=STREAM 1)
      (define fd (loop-socket-new SOCKET-DOMAIN=AF-INET SOCKET-TYPE=STREAM 0))
      (define accept
        (lambda ()
          (define client (loop-accept fd))
          (if (not client)
              (values #f #f #f #f #f)
              (let ((peer-ip (loop-getpeername client)))
                (values (lambda ()      (loop-read client))
                        (lambda (bv)    (loop-write client bv))
                        (lambda ()      (loop-close client))
                        peer-ip
                        client)))))
      (loop-bind fd ip port)
      (loop-listen fd 128)
      (values accept (lambda () (loop-close fd)))))

  (define loop-poll-wait
    (lambda (fd poll-mask)
      (let* ((sqe (loop-get-sqe (loop-ring %loop)))
             (id  (loop-alloc-id!)))
        (io-uring-prep-poll-add sqe fd poll-mask)
        (io-uring-sqe-set-data64 sqe id)
        (loop-abort
          (lambda (k)
            (hashtable-set! (loop-handlers %loop) id k))))))

  (include "letloop/liburing/low.check.scm")

  ) ;; end library
