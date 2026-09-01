/* letloop's C host.
 *
 * It exists to do two things Chez's own c/main.c will not.
 *
 * First, it does NOT parse the command line. c/main.c reads argv before
 * any Scheme runs and claims --help, --version, -b/--boot,
 * --optimize-level, --libdirs and a dozen more, at any position on the
 * line -- so a letloop that is the scheme binary under another name can
 * never see those arguments. Here argc and argv reach Sscheme_start
 * untouched, and every flag arrives at letloop-main.
 *
 * Second, it can carry its own boot image, appended to the executable.
 * That is what makes `letloop compile` produce a single self-contained
 * file without a C compiler: it copies this binary and concatenates a
 * standalone boot file and a trailer onto it. Bytes past the end of an
 * ELF image are ignored by the loader, so the result still runs.
 *
 * The layout, at the very end of the file:
 *
 *     [ boot image ][ 8-byte little-endian length ][ 8-byte magic ]
 *
 * With no trailer -- which is how letloop itself is installed -- the
 * binary falls back to Sbuild_heap(argv[0]), which loads <name>.boot
 * where <name> is the last component of argv[0]. So one binary serves
 * both roles: named letloop it runs letloop.boot, and with a payload
 * appended it runs that instead.
 */

/* pipe2 and signalfd are behind _GNU_SOURCE on glibc; musl exposes
 * them regardless. */
#define _GNU_SOURCE

#include <dlfcn.h>
#include <fcntl.h>
#include <signal.h>
#include <sys/ioctl.h>
#include <sys/signalfd.h>
#include <termios.h>
#include <netdb.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/eventfd.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <unistd.h>


#include "scheme.h"

extern char **environ;

/* (load-shared-object #f) -- dlopen(NULL, ...), "hand me the main
 * program's own handle" -- is how nearly every (foreign-procedure
 * ...) call in this codebase reaches ordinary libc functions: one
 * file calls it eagerly at library-instantiation time (e.g. cffi.scm,
 * imported almost everywhere) and every other file's bare
 * foreign-procedure calls, with no load-shared-object of their own,
 * ride on that as a process-wide side effect. There is no dynamic
 * linker to service dlopen(NULL, ...) in a statically-linked binary,
 * so it fails there, and Chez's own error-formatting code for that
 * failure crashes on the NULL path it was given (see
 * src/letloop/store/README.md's Issues section for the full trace).
 *
 * Rather than convert every call site (tried, and it breaks: it loses
 * the "one eager call unlocks everything else" side effect even for
 * ordinary dynamic builds, since a site that already resolves its own
 * symbol via Sforeign_symbol never falls back to load-shared-object
 * for anything ELSE that used to ride along with it), this probes
 * once, safely, in C, before any Scheme runs, and exposes the result:
 * letloop_self_dlopen_safe() is always registered (so callers can
 * always ask), and reports 1 only when dlopen(NULL, ...) actually
 * works here. Scheme-side code (see cffi.scm's ensure-self-loaded!)
 * calls (load-shared-object #f) eagerly, exactly as before, only when
 * this says it is safe -- preserving today's behavior byte for byte
 * on a dynamic build. When it is not safe, the small, hand-audited
 * set of libc symbols below -- exactly what (letloop store build)'s
 * own dependency chain needs (root.scm, and tls/base.scm for the
 * fixed-output fetch step's HTTPS client) -- is registered instead,
 * via Sforeign_symbol, a public Chez embedding API independent of
 * dlopen that (foreign-procedure ...) and foreign-entry already
 * search first.
 *
 * The list is not exhaustive by construction -- a static build
 * exercising a file outside that chain needs its own entry here -- and
 * a missing one shows up only as "no entry for X" the first time that
 * code path runs, which is a poor way to find them one at a time. To
 * get the whole set instead, list every eagerly-resolved symbol in the
 * tree and subtract what is already registered:
 *
 *   grep -rhoE '\(foreign-procedure[^"]*"([a-zA-Z_][a-zA-Z0-9_]*)"' \
 *        src/letloop --include='*.scm' | grep -v lazy-foreign-procedure
 *
 * Symbols reached through lazy-foreign-procedure do not belong here:
 * those probe first and fall back to their own dlopen, which is how
 * optional shared objects (blake3, picohttpparser, liburing) stay
 * optional. Nor do the Windows/macOS spellings in environment.scm.
 */
static int letloop_self_dlopen_safe_result = 0;

static int letloop_self_dlopen_safe(void) {
  return letloop_self_dlopen_safe_result;
}

#ifdef LETLOOP_LIBURING_STATIC
/* liburing's own "-ffi" build variant exists because liburing.h leans
 * heavily on `static inline` functions (io_uring_prep_*, the sqe/cqe
 * accessors, io_uring_cq_advance, ...) -- several of those
 * (io_uring_cq_advance, io_uring_cqe_seen, the ring-index bookkeeping
 * in general) internally call the barrier primitives in
 * liburing/barrier.h (io_uring_smp_load_acquire /
 * io_uring_smp_store_release), which enforce the ordering the kernel
 * relies on between userspace and the SQ/CQ ring's shared memory.
 * liburing ships a dedicated ffi.c to get real, addressable symbols
 * for these, compiled with IOURINGINLINE defined empty so every
 * IOURINGINLINE-guarded function in the header becomes an ordinary,
 * externally-linked definition instead of `static inline`; Alpine's
 * liburing-ffi.a is exactly that object file, pre-built by upstream.
 *
 * An earlier version of this file took each `static inline`
 * function's address directly (default liburing.h, no IOURINGINLINE
 * override), reasoning that address-taking forces the compiler to
 * materialize an equivalent out-of-line copy in this translation
 * unit. That is a *different* compiled instantiation of the barrier
 * code than the one upstream ships and tests -- not provably wrong,
 * but a real, unresolved gap during (letloop liburing low)'s
 * still-uninvestigated runtime crash. A later attempt to close that
 * gap by defining IOURINGINLINE here directly (so this file compiles
 * the exact same real definitions liburing-ffi.c does) failed at
 * link time instead: liburing.a's own queue.ol already carries real,
 * non-inline definitions of a handful of these names (io_uring_get_sqe,
 * io_uring_get_events -- kept for ABI back-compat from before they
 * became header-only), and duplicating them here collides with
 * -luring ("multiple definition of io_uring_get_sqe").
 *
 * The fix that actually avoids both problems: reference the
 * pre-built liburing-ffi.a symbols directly, under a distinct local C
 * name aliased to the real linker symbol via GCC's asm-label
 * extension, so this translation unit never defines or re-inlines
 * any of these functions itself -- it only takes the address the
 * archive already provides, identical to what a dynamic FFI consumer
 * would dlopen. No liburing.h inclusion is needed for this: only a
 * matching symbol name, resolved by the linker.
 *
 * The dlopen path (liburing-ffi.so) is what does not work here
 * (see the big comment above): confirmed empirically against a real
 * static build, dlopen("liburing-ffi.so.2", RTLD_NOW) fails with
 * musl's own "Dynamic loading not supported" -- a stronger limitation
 * than the dlopen(NULL, ...) case, this is *any* dlopen, named or
 * not, on this static libc. So liburing-ffi.a is linked statically
 * instead (LETLOOP_LIBURING_STATIC pairs with -luring-ffi in the
 * makefile, replacing plain -luring: liburing-ffi.a is a strict
 * superset -- setup.ol, queue.ol, register.ol, syscall.ol, version.ol,
 * plus ffi.ol -- so nothing else needs to change).
 *
 * The list is every io_uring_* symbol src/letloop/liburing/low.scm
 * resolves via lazy-foreign-procedure, mechanically extracted, minus
 * io_uring_prep_ftruncate, which this liburing version (2.9) does not
 * have -- low.scm's own corresponding wrapper was already unreachable
 * on any build using this liburing version, static or dynamic; this
 * does not change that.
 */
#define LETLOOP_URING_SYM(name) \
  do { \
    extern void name##_letloop_ffi_stub(void) __asm__(#name); \
    Sforeign_symbol(#name, (void *)name##_letloop_ffi_stub); \
  } while (0)

static void letloop_register_liburing_symbols(void) {
  LETLOOP_URING_SYM(io_uring_buf_ring_add);
  LETLOOP_URING_SYM(io_uring_buf_ring_advance);
  LETLOOP_URING_SYM(io_uring_buf_ring_available);
  LETLOOP_URING_SYM(io_uring_buf_ring_cq_advance);
  LETLOOP_URING_SYM(io_uring_buf_ring_init);
  LETLOOP_URING_SYM(io_uring_buf_ring_mask);
  LETLOOP_URING_SYM(io_uring_check_version);
  LETLOOP_URING_SYM(io_uring_close_ring_fd);
  LETLOOP_URING_SYM(io_uring_cq_advance);
  LETLOOP_URING_SYM(io_uring_cq_has_overflow);
  LETLOOP_URING_SYM(io_uring_cq_ready);
  LETLOOP_URING_SYM(io_uring_cqe_get_data);
  LETLOOP_URING_SYM(io_uring_cqe_get_data64);
  LETLOOP_URING_SYM(io_uring_cqe_seen);
  LETLOOP_URING_SYM(io_uring_enable_rings);
  LETLOOP_URING_SYM(io_uring_enter);
  LETLOOP_URING_SYM(io_uring_enter2);
  LETLOOP_URING_SYM(io_uring_free_buf_ring);
  LETLOOP_URING_SYM(io_uring_free_probe);
  LETLOOP_URING_SYM(io_uring_get_events);
  LETLOOP_URING_SYM(io_uring_get_probe);
  LETLOOP_URING_SYM(io_uring_get_probe_ring);
  LETLOOP_URING_SYM(io_uring_get_sqe);
  LETLOOP_URING_SYM(io_uring_major_version);
  LETLOOP_URING_SYM(io_uring_minor_version);
  LETLOOP_URING_SYM(io_uring_opcode_supported);
  LETLOOP_URING_SYM(io_uring_peek_batch_cqe);
  LETLOOP_URING_SYM(io_uring_peek_cqe);
  LETLOOP_URING_SYM(io_uring_prep_accept);
  LETLOOP_URING_SYM(io_uring_prep_accept_direct);
  LETLOOP_URING_SYM(io_uring_prep_bind);
  LETLOOP_URING_SYM(io_uring_prep_cancel);
  LETLOOP_URING_SYM(io_uring_prep_cancel64);
  LETLOOP_URING_SYM(io_uring_prep_cancel_fd);
  LETLOOP_URING_SYM(io_uring_prep_close);
  LETLOOP_URING_SYM(io_uring_prep_close_direct);
  LETLOOP_URING_SYM(io_uring_prep_cmd_sock);
  LETLOOP_URING_SYM(io_uring_prep_connect);
  LETLOOP_URING_SYM(io_uring_prep_epoll_ctl);
  LETLOOP_URING_SYM(io_uring_prep_fadvise);
  LETLOOP_URING_SYM(io_uring_prep_fallocate);
  LETLOOP_URING_SYM(io_uring_prep_fgetxattr);
  LETLOOP_URING_SYM(io_uring_prep_files_update);
  LETLOOP_URING_SYM(io_uring_prep_fixed_fd_install);
  LETLOOP_URING_SYM(io_uring_prep_fsetxattr);
  LETLOOP_URING_SYM(io_uring_prep_fsync);
  LETLOOP_URING_SYM(io_uring_prep_futex_wait);
  LETLOOP_URING_SYM(io_uring_prep_futex_waitv);
  LETLOOP_URING_SYM(io_uring_prep_futex_wake);
  LETLOOP_URING_SYM(io_uring_prep_getxattr);
  LETLOOP_URING_SYM(io_uring_prep_link);
  LETLOOP_URING_SYM(io_uring_prep_link_timeout);
  LETLOOP_URING_SYM(io_uring_prep_linkat);
  LETLOOP_URING_SYM(io_uring_prep_listen);
  LETLOOP_URING_SYM(io_uring_prep_madvise);
  LETLOOP_URING_SYM(io_uring_prep_mkdir);
  LETLOOP_URING_SYM(io_uring_prep_mkdirat);
  LETLOOP_URING_SYM(io_uring_prep_msg_ring);
  LETLOOP_URING_SYM(io_uring_prep_msg_ring_cqe_flags);
  LETLOOP_URING_SYM(io_uring_prep_msg_ring_fd);
  LETLOOP_URING_SYM(io_uring_prep_msg_ring_fd_alloc);
  LETLOOP_URING_SYM(io_uring_prep_multishot_accept);
  LETLOOP_URING_SYM(io_uring_prep_multishot_accept_direct);
  LETLOOP_URING_SYM(io_uring_prep_nop);
  LETLOOP_URING_SYM(io_uring_prep_open);
  LETLOOP_URING_SYM(io_uring_prep_open_direct);
  LETLOOP_URING_SYM(io_uring_prep_openat);
  LETLOOP_URING_SYM(io_uring_prep_openat_direct);
  LETLOOP_URING_SYM(io_uring_prep_poll_add);
  LETLOOP_URING_SYM(io_uring_prep_poll_multishot);
  LETLOOP_URING_SYM(io_uring_prep_poll_remove);
  LETLOOP_URING_SYM(io_uring_prep_poll_update);
  LETLOOP_URING_SYM(io_uring_prep_provide_buffers);
  LETLOOP_URING_SYM(io_uring_prep_read);
  LETLOOP_URING_SYM(io_uring_prep_read_fixed);
  LETLOOP_URING_SYM(io_uring_prep_read_multishot);
  LETLOOP_URING_SYM(io_uring_prep_readv);
  LETLOOP_URING_SYM(io_uring_prep_readv2);
  LETLOOP_URING_SYM(io_uring_prep_recv);
  LETLOOP_URING_SYM(io_uring_prep_recv_multishot);
  LETLOOP_URING_SYM(io_uring_prep_recvmsg);
  LETLOOP_URING_SYM(io_uring_prep_recvmsg_multishot);
  LETLOOP_URING_SYM(io_uring_prep_remove_buffers);
  LETLOOP_URING_SYM(io_uring_prep_rename);
  LETLOOP_URING_SYM(io_uring_prep_renameat);
  LETLOOP_URING_SYM(io_uring_prep_rw);
  LETLOOP_URING_SYM(io_uring_prep_send);
  LETLOOP_URING_SYM(io_uring_prep_send_bundle);
  LETLOOP_URING_SYM(io_uring_prep_send_set_addr);
  LETLOOP_URING_SYM(io_uring_prep_send_zc);
  LETLOOP_URING_SYM(io_uring_prep_send_zc_fixed);
  LETLOOP_URING_SYM(io_uring_prep_sendmsg);
  LETLOOP_URING_SYM(io_uring_prep_sendmsg_zc);
  LETLOOP_URING_SYM(io_uring_prep_sendto);
  LETLOOP_URING_SYM(io_uring_prep_setxattr);
  LETLOOP_URING_SYM(io_uring_prep_shutdown);
  LETLOOP_URING_SYM(io_uring_prep_socket);
  LETLOOP_URING_SYM(io_uring_prep_socket_direct);
  LETLOOP_URING_SYM(io_uring_prep_socket_direct_alloc);
  LETLOOP_URING_SYM(io_uring_prep_splice);
  LETLOOP_URING_SYM(io_uring_prep_statx);
  LETLOOP_URING_SYM(io_uring_prep_symlink);
  LETLOOP_URING_SYM(io_uring_prep_symlinkat);
  LETLOOP_URING_SYM(io_uring_prep_sync_file_range);
  LETLOOP_URING_SYM(io_uring_prep_tee);
  LETLOOP_URING_SYM(io_uring_prep_timeout);
  LETLOOP_URING_SYM(io_uring_prep_timeout_remove);
  LETLOOP_URING_SYM(io_uring_prep_timeout_update);
  LETLOOP_URING_SYM(io_uring_prep_unlink);
  LETLOOP_URING_SYM(io_uring_prep_unlinkat);
  LETLOOP_URING_SYM(io_uring_prep_waitid);
  LETLOOP_URING_SYM(io_uring_prep_write);
  LETLOOP_URING_SYM(io_uring_prep_write_fixed);
  LETLOOP_URING_SYM(io_uring_prep_writev);
  LETLOOP_URING_SYM(io_uring_prep_writev2);
  LETLOOP_URING_SYM(io_uring_queue_exit);
  LETLOOP_URING_SYM(io_uring_queue_init);
  LETLOOP_URING_SYM(io_uring_queue_init_params);
  LETLOOP_URING_SYM(io_uring_queue_mmap);
  LETLOOP_URING_SYM(io_uring_recvmsg_cmsg_firsthdr);
  LETLOOP_URING_SYM(io_uring_recvmsg_cmsg_nexthdr);
  LETLOOP_URING_SYM(io_uring_recvmsg_name);
  LETLOOP_URING_SYM(io_uring_recvmsg_payload);
  LETLOOP_URING_SYM(io_uring_recvmsg_payload_length);
  LETLOOP_URING_SYM(io_uring_recvmsg_validate);
  LETLOOP_URING_SYM(io_uring_register);
  LETLOOP_URING_SYM(io_uring_register_buf_ring);
  LETLOOP_URING_SYM(io_uring_register_buffers);
  LETLOOP_URING_SYM(io_uring_register_buffers_sparse);
  LETLOOP_URING_SYM(io_uring_register_buffers_tags);
  LETLOOP_URING_SYM(io_uring_register_buffers_update_tag);
  LETLOOP_URING_SYM(io_uring_register_eventfd);
  LETLOOP_URING_SYM(io_uring_register_eventfd_async);
  LETLOOP_URING_SYM(io_uring_register_file_alloc_range);
  LETLOOP_URING_SYM(io_uring_register_files);
  LETLOOP_URING_SYM(io_uring_register_files_sparse);
  LETLOOP_URING_SYM(io_uring_register_files_tags);
  LETLOOP_URING_SYM(io_uring_register_files_update);
  LETLOOP_URING_SYM(io_uring_register_files_update_tag);
  LETLOOP_URING_SYM(io_uring_register_iowq_max_workers);
  LETLOOP_URING_SYM(io_uring_register_napi);
  LETLOOP_URING_SYM(io_uring_register_personality);
  LETLOOP_URING_SYM(io_uring_register_probe);
  LETLOOP_URING_SYM(io_uring_register_restrictions);
  LETLOOP_URING_SYM(io_uring_register_ring_fd);
  LETLOOP_URING_SYM(io_uring_register_sync_cancel);
  LETLOOP_URING_SYM(io_uring_ring_dontfork);
  LETLOOP_URING_SYM(io_uring_setup);
  LETLOOP_URING_SYM(io_uring_setup_buf_ring);
  LETLOOP_URING_SYM(io_uring_sq_ready);
  LETLOOP_URING_SYM(io_uring_sq_space_left);
  LETLOOP_URING_SYM(io_uring_sqe_set_buf_group);
  LETLOOP_URING_SYM(io_uring_sqe_set_data);
  LETLOOP_URING_SYM(io_uring_sqe_set_data64);
  LETLOOP_URING_SYM(io_uring_sqe_set_flags);
  LETLOOP_URING_SYM(io_uring_sqring_wait);
  LETLOOP_URING_SYM(io_uring_submit);
  LETLOOP_URING_SYM(io_uring_submit_and_get_events);
  LETLOOP_URING_SYM(io_uring_submit_and_wait);
  LETLOOP_URING_SYM(io_uring_submit_and_wait_timeout);
  LETLOOP_URING_SYM(io_uring_unregister_buf_ring);
  LETLOOP_URING_SYM(io_uring_unregister_buffers);
  LETLOOP_URING_SYM(io_uring_unregister_eventfd);
  LETLOOP_URING_SYM(io_uring_unregister_files);
  LETLOOP_URING_SYM(io_uring_unregister_napi);
  LETLOOP_URING_SYM(io_uring_unregister_personality);
  LETLOOP_URING_SYM(io_uring_unregister_ring_fd);
  LETLOOP_URING_SYM(io_uring_wait_cqe);
  LETLOOP_URING_SYM(io_uring_wait_cqe_nr);
  LETLOOP_URING_SYM(io_uring_wait_cqe_timeout);
  LETLOOP_URING_SYM(io_uring_wait_cqes);
}
#endif /* LETLOOP_LIBURING_STATIC */

static void letloop_register_foreign_symbols(void) {
  void *probe = dlopen(NULL, RTLD_LAZY);
  if (probe != NULL) {
    letloop_self_dlopen_safe_result = 1;
    dlclose(probe);
  }

  Sforeign_symbol("letloop_self_dlopen_safe", (void *)letloop_self_dlopen_safe);
  Sforeign_symbol("strerror", (void *)strerror);
  Sforeign_symbol("mkdtemp", (void *)mkdtemp);
  Sforeign_symbol("readlink", (void *)readlink);
  Sforeign_symbol("unsetenv", (void *)unsetenv);
  Sforeign_symbol("getaddrinfo", (void *)getaddrinfo);
  Sforeign_symbol("freeaddrinfo", (void *)freeaddrinfo);
  Sforeign_symbol("socket", (void *)socket);
  Sforeign_symbol("connect", (void *)connect);
  Sforeign_symbol("setsockopt", (void *)setsockopt);
  Sforeign_symbol("getsockopt", (void *)getsockopt);
  Sforeign_symbol("bind", (void *)bind);
  Sforeign_symbol("listen", (void *)listen);
  Sforeign_symbol("getpeername", (void *)getpeername);
  Sforeign_symbol("close", (void *)close);
  Sforeign_symbol("execve", (void *)execve);
  Sforeign_symbol("strlen", (void *)strlen);
  Sforeign_symbol("memcpy", (void *)memcpy);
  Sforeign_symbol("fcntl", (void *)fcntl);
  Sforeign_symbol("eventfd", (void *)eventfd);
  Sforeign_symbol("write", (void *)write);
  Sforeign_symbol("read", (void *)read);
  Sforeign_symbol("open", (void *)open);
  Sforeign_symbol("pipe2", (void *)pipe2);
  Sforeign_symbol("ioctl", (void *)ioctl);
  Sforeign_symbol("isatty", (void *)isatty);
  Sforeign_symbol("mmap", (void *)mmap);
  Sforeign_symbol("mprotect", (void *)mprotect);
  Sforeign_symbol("getsockname", (void *)getsockname);
  Sforeign_symbol("tcgetattr", (void *)tcgetattr);
  Sforeign_symbol("tcsetattr", (void *)tcsetattr);
  Sforeign_symbol("cfmakeraw", (void *)cfmakeraw);
  Sforeign_symbol("sigemptyset", (void *)sigemptyset);
  Sforeign_symbol("sigaddset", (void *)sigaddset);
  Sforeign_symbol("sigprocmask", (void *)sigprocmask);
  Sforeign_symbol("signalfd", (void *)signalfd);
  /* Deliberately NOT registering "environ": doing so broke
   * environment-variables (letloop/environment.scm) even on an
   * ordinary dynamic build, reproducibly, with an otherwise
   * unexplained "invalid memory reference" -- some ELF data-symbol
   * aliasing subtlety between this registration's &environ and
   * dlsym(handle, "environ") on a later, separate (load-shared-object
   * "libc.so.6"), not fully root-caused. Not needed for the store
   * build path either way: root.scm's execve!/environ lookup backs
   * `letloop root exec` (interactive use), not
   * `letloop store build`'s sandbox-build!, which shells out to
   * /usr/bin/bwrap directly and never touches this code path. A
   * static `letloop root exec` remains unsupported until this is
   * understood properly.
   */

#ifdef LETLOOP_LIBURING_STATIC
  letloop_register_liburing_symbols();
#endif
}

#define LETLOOP_MAGIC "LETLOOP\1"
#define LETLOOP_MAGIC_SIZE 8
#define LETLOOP_TRAILER_SIZE 16 /* length + magic */

/* Find the appended boot image, if there is one. Returns a pointer to
   its bytes and sets *size, or returns NULL.
 *
 * The file is mapped rather than read: reading it cost a 3.3MB malloc
 * and memcpy on every single start, which measured ~0.8ms against the
 * separate-boot-file arrangement this replaces -- 3% of a 27ms startup.
 * mmap hands Sregister_boot_file_bytes a pointer into the page cache
 * instead, and the pages the boot loader never touches are never read.
 * The whole file is mapped because mmap offsets must be page-aligned
 * and the payload begins wherever the host binary happens to end; the
 * mapping is deliberately never unmapped, since Chez keeps the pointer.
 */
static void *appended_boot(const char *path, iptr *size) {
  int fd;
  struct stat info;
  unsigned char *base;
  unsigned long long length = 0;
  int i;

  if (path == NULL) return NULL;
  if ((fd = open(path, O_RDONLY)) < 0) return NULL;

  if (fstat(fd, &info) != 0 || info.st_size <= LETLOOP_TRAILER_SIZE) {
    close(fd);
    return NULL;
  }

  base = mmap(NULL, (size_t)info.st_size, PROT_READ, MAP_PRIVATE, fd, 0);
  close(fd); /* the mapping keeps its own reference */
  if (base == MAP_FAILED) return NULL;

  if (memcmp(base + info.st_size - LETLOOP_MAGIC_SIZE,
             LETLOOP_MAGIC, LETLOOP_MAGIC_SIZE) != 0) {
    munmap(base, (size_t)info.st_size);
    return NULL;
  }

  for (i = 7; i >= 0; i--)
    length = (length << 8) | base[info.st_size - LETLOOP_TRAILER_SIZE + i];

  if (length == 0
      || length > (unsigned long long)info.st_size - LETLOOP_TRAILER_SIZE) {
    munmap(base, (size_t)info.st_size);
    return NULL;
  }

  *size = (iptr)length;
  return base + info.st_size - LETLOOP_TRAILER_SIZE - length;
}

int main(int argc, const char *argv[]) {
  void *boot;
  iptr size = 0;
  int status;

  Sscheme_init(0);

  /* /proc/self/exe rather than argv[0]: argv[0] is whatever the caller
     put there, and a program invoked through PATH or a symlink would
     otherwise fail to find itself. */
  if ((boot = appended_boot("/proc/self/exe", &size)) == NULL)
    boot = appended_boot(argv[0], &size);

  if (boot != NULL) {
    Sregister_boot_file_bytes("program", boot, size);
    Sbuild_heap(NULL, letloop_register_foreign_symbols);
  } else {
    Sbuild_heap(argv[0], letloop_register_foreign_symbols);
  }

  status = Sscheme_start(argc, argv);
  Sscheme_deinit();

  exit(status);
}
