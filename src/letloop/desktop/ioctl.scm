#!chezscheme
;; Low-level Linux syscall bindings for the desktop module.
;;
;; ioctl's third argument is variadic in C; Chez Scheme's foreign-procedure
;; needs a fixed arity per binding, so we expose two flavors: one taking an
;; unsigned-long arg (for KDSETMODE etc.) and one taking a pointer (for the
;; DRM mode ioctls that read/write struct buffers).
;;
;; Return convention mirrors letloop cffi's call-with-errno: every FFI entry
;; point returns (values result errno). Callers decide whether to raise.
(library (letloop desktop ioctl)
  (export
   ;; syscalls
   sys-open
   sys-close
   sys-read
   sys-write
   sys-ioctl-int
   sys-ioctl-ptr

   ;; open flags (Linux x86_64 / generic)
   O_RDONLY O_WRONLY O_RDWR O_NONBLOCK O_CLOEXEC

   ;; _IOC encoding
   _IO _IOR _IOW _IOWR

   ;; diagnostics
   errno-raise
   errno-check)
  (import (chezscheme) (letloop cffi))

  ;; Load libc's dynamic namespace. load-shared-object with #f returns a handle
  ;; to the default globals — open/close/ioctl/read/write are resolvable from
  ;; libc which is already mapped into every Linux process.
  (define stdlib (load-shared-object #f))

  (define sys-open
    (let ((f (foreign-procedure "open" (string int int) int)))
      (lambda (path flags)
        ;; mode is ignored unless O_CREAT is set; pass 0.
        (call-with-errno (lambda () (f path flags 0)) values))))

  (define sys-close
    (let ((f (foreign-procedure "close" (int) int)))
      (lambda (fd)
        (call-with-errno (lambda () (f fd)) values))))

  ;; On Linux x86_64, size_t is unsigned-long and ssize_t is long.
  (define sys-read
    (let ((f (foreign-procedure "read" (int uptr unsigned-long) long)))
      (lambda (fd buf count)
        (call-with-errno (lambda () (f fd buf count)) values))))

  (define sys-write
    (let ((f (foreign-procedure "write" (int uptr unsigned-long) long)))
      (lambda (fd buf count)
        (call-with-errno (lambda () (f fd buf count)) values))))

  (define sys-ioctl-int
    (let ((f (foreign-procedure "ioctl" (int unsigned-long unsigned-long) int)))
      (lambda (fd request arg)
        (call-with-errno (lambda () (f fd request arg)) values))))

  (define sys-ioctl-ptr
    (let ((f (foreign-procedure "ioctl" (int unsigned-long uptr) int)))
      (lambda (fd request ptr)
        (call-with-errno (lambda () (f fd request ptr)) values))))

  (define (errno-raise who errno)
    (error who (strerror errno) errno))

  (define (errno-check who ret errno)
    (when (negative? ret) (errno-raise who errno))
    ret)

  ;; Open flags. Linux generic values (identical on x86_64, aarch64, riscv64).
  (define O_RDONLY   #o0)
  (define O_WRONLY   #o1)
  (define O_RDWR     #o2)
  (define O_NONBLOCK #o4000)
  (define O_CLOEXEC  #o2000000)

  ;; _IOC bit layout (Linux generic). See include/uapi/asm-generic/ioctl.h.
  (define _IOC_NRSHIFT   0)
  (define _IOC_TYPESHIFT 8)
  (define _IOC_SIZESHIFT 16)
  (define _IOC_DIRSHIFT  30)

  (define _IOC_NONE  0)
  (define _IOC_WRITE 1)
  (define _IOC_READ  2)

  (define (_IOC dir type nr size)
    (bitwise-ior
     (bitwise-arithmetic-shift-left dir _IOC_DIRSHIFT)
     (bitwise-arithmetic-shift-left type _IOC_TYPESHIFT)
     (bitwise-arithmetic-shift-left nr _IOC_NRSHIFT)
     (bitwise-arithmetic-shift-left size _IOC_SIZESHIFT)))

  (define (_IO   type nr)        (_IOC _IOC_NONE  type nr 0))
  (define (_IOR  type nr size)   (_IOC _IOC_READ  type nr size))
  (define (_IOW  type nr size)   (_IOC _IOC_WRITE type nr size))
  (define (_IOWR type nr size)   (_IOC (bitwise-ior _IOC_READ _IOC_WRITE) type nr size)))
