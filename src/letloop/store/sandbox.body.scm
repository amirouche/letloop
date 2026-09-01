;; Runs a derivation's build.sh inside a bwrap sandbox, extending the
;; bwrap invocation `letloop root exec` uses (src/letloop/root.scm's
;; root-exec) with three deliberate changes:
;;
;;  - --unshare-net instead of --share-net: a build gets no network at
;;    all; reproducibility depends on it. Fixed-output fetches are a
;;    separate, host-side step (see (letloop store fetch)).
;;  - --ro-bind instead of --dev-bind for the toolchain rootfs: a
;;    shared, cached rootfs must stay immutable across builds, or two
;;    builds against the same cache stop being independent.
;;  - a writable scratch directory is bound at /build; root-exec's
;;    bind of the invoker's own cwd at /mnt/host is dropped entirely
;;    -- a build has no business touching the invoker's cwd.
;;
;; root-exec itself is untouched by any of this.

(define (bwrap-available?)
  (file-exists? "/usr/bin/bwrap"))

;; bwrap cannot create a new mountpoint (e.g. /build) under a path
;; that is itself already read-only-bound, since that requires a
;; mkdir on a read-only filesystem. So the rootfs is not bound as one
;; single --ro-bind onto "/" (which would make all of "/" read-only
;; before /build, /proc, /dev etc. get created on top of it); instead
;; each of the rootfs's own top-level entries (usr, bin, lib, ...) is
;; individually ro-bound at the same name, leaving the sandbox's
;; implicit root itself writable so later --dir/--bind/--proc/--dev
;; mountpoints can still be created.
(define (rootfs-entry-binds rootfs-directory)
  (apply string-append
         (map (lambda (name)
                (string-append " --ro-bind "
                                (shell-single-quote (string-append rootfs-directory "/" name))
                                " /" name))
              (directory-list rootfs-directory))))

;; ROOTFS-DIRECTORY and SCRATCH-DIRECTORY are host paths. INPUTS is a
;; list of existing store paths, read-only bind-mounted at the same
;; absolute path inside the sandbox as outside. SCRATCH-DIRECTORY must
;; already contain build.sh, written by the caller.
;; SESSION-KEY, when given, reaches the build as $LETLOOP_SESSION_KEY
;; and $SOURCE_DATE_EPOCH -- the two things a build needs to be
;; reproducible. The first pins Chez's gensym naming, without which two
;; compiles of the same source differ byte for byte; the second is the
;; reproducible-builds convention for anything that would otherwise
;; reach for the wall clock. Both are derived from what identifies the
;; build, so the same inputs give the same bytes.
;;
;; SOURCE_DATE_EPOCH is 0 rather than the key: it has to be a Unix
;; timestamp, and any fixed one will do, since what matters is only
;; that it does not vary between builds of the same thing.
(define (sandbox-build! rootfs-directory scratch-directory inputs session-key)
  (unless (bwrap-available?)
    (error 'sandbox-build! "/usr/bin/bwrap not found"))
  (let* ((reproducible-env
          (if session-key
              (string-append " --setenv LETLOOP_SESSION_KEY " (shell-single-quote session-key)
                             " --setenv SOURCE_DATE_EPOCH 0")
              ""))
         (input-binds
          (apply string-append
                 (map (lambda (input)
                        (string-append " --ro-bind "
                                        (shell-single-quote input) " "
                                        (shell-single-quote input)))
                      inputs)))
         (command
          (string-append
           "/usr/bin/bwrap"
           " --die-with-parent --as-pid-1 --clearenv"
           " --setenv PATH /usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
           " --setenv HOME /build --setenv USER build"
           reproducible-env
           " --unshare-uts --unshare-ipc --unshare-pid --unshare-cgroup --unshare-net"
           " --cap-add ALL --uid 0 --gid 0"
           (rootfs-entry-binds rootfs-directory)
           " --proc /proc --dev /dev --ro-bind /sys /sys --tmpfs /tmp"
           " --dir /build"
           " --bind " (shell-single-quote scratch-directory) " /build"
           input-binds
           " --chdir /build --hostname letloop-build"
           " -- sh -e /build/build.sh")))
    (system! command)))
