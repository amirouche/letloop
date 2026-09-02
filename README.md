# letloop

```

                ≠≠≠≠≠≠≠≠≠≠
             ≠≠≠≠≠≠≠≠≠≠≠≠≠≠≠≠≠                          ≠
            ≠≠≠≠≠≠≠≠≠≠≠≠≠≠≠≠≠≠≠≠                        ≠≠
           ≠≠≠≠≠≠       ≠≠≠≠≠≠≠≠≠≠                      ≠≠
           ≠≠≠≠≠           ≠≠≠≠≠≠≠≠                    ≠≠≠
           ≠≠≠≠             ≠≠≠≠≠≠≠≠≠                 ≠≠≠≠
           ≠≠≠≠≠              ≠≠≠≠≠≠≠≠≠≠           ≠≠≠≠≠≠
            ≠≠≠≠≠               ≠≠≠≠≠≠≠≠≠≠≠≠≠≠≠≠≠≠≠≠≠≠≠
             ≠≠≠≠≠≠≠≠≠≠≠≠          ≠≠≠≠≠≠≠≠≠≠≠≠≠≠≠≠≠≠
                 ≠≠≠≠                 ≠≠≠≠≠≠≠≠≠≠≠≠

  ,,                  ,,
`7MM           mm   `7MM
  MM           MM     MM
  MM  .gP"Ya mmMMmm   MM  ,pW"Wq.   ,pW"Wq.   ,pW"Wq.`7MMpdMAo.
  MM ,M'   Yb  MM     MM 6W'   `Wb 6W'   `Wb 6W'   `Wb MM   `Wb
  MM 8M""""""  MM     MM 8M     M8 8M     M8 8M     M8 MM    M8
  MM YM.    ,  MM     MM YA.   ,A9 YA.   ,A9 YA.   ,A9 MM   ,AP
.JMML.`Mbmmd'  `Mbmo.JMML.`Ybmd9'   `Ybmd9'   `Ybmd9'  MMbmmd'
                                                       MM
                                                     .JMML.
```

**letloop** is a Scheme compiler, runtime, and batteries-included
standard library built on Chez Scheme. It compiles R6RS libraries into
standalone executables, and ships a test runner, a REPL, an io_uring
event loop, an HTTP server, a terminal UI framework, and bindings for
the usual production plumbing — all importable as plain R6RS
libraries.

## Getting started

Requires `uuid` headers for using `letloop compile`, and `libtls-dev`
(LibreTLS) for the TLS module that `(letloop www)` and friends pull in
transitively. On Debian / Ubuntu:

```shell
sudo apt install uuid-dev libtls-dev libtls28t64
```

On Fedora / RHEL: `sudo dnf install libuuid-devel libretls libretls-devel`.
On Arch: `sudo pacman -S util-linux-libs libretls`. On Alpine:
`apk add util-linux-dev libretls libretls-dev`.

```shell
./venv
make chezscheme
make letloop
make check
```

Every other shared object (`libsodium`, `libargon2`, `libblake3`,
`liburing-ffi`, `libpicohttpparser`, `libopaque`, `libtls`) is
optional: binding libraries dlopen it lazily on the **first foreign
call**, so building letloop and importing any library requires none of
them installed. Checks that need a missing shared object or service
print a `** SKIP` note and pass.

## The `letloop` command

```
letloop check [--fail-fast] [DIRECTORY ...] LIBRARY.SCM ...
letloop compile [DIRECTORY ...] LIBRARY.SCM PROCEDURE [-- CC-FLAGS ...]
letloop exec [DIRECTORY ...] LIBRARY.SCM PROCEDURE [-- ARGUMENT ...]
letloop http serve [--port=PORT] [DIRECTORY ...] LIBRARY.SCM
letloop repl
letloop review [DIRECTORY ...]
```

- **check** — discovers and runs `~check-*` procedures exported by
  libraries; `~benchmark-*` procedures are benchmarks.
- **compile** — standalone executable from a library and an entry-point
  procedure. The program and every library it imports are compiled as a
  single unit, so that calls across library boundaries can be inlined;
  `--visible-libraries` compiles them separately and leaves them
  importable at run time instead.
- **exec** — compile and run in one step, forwarding arguments after `--`.
- **http serve** — serve a web library exporting `application`,
  `context`, and `dispatch` over the io_uring HTTP server (see
  `examples/my-web-library.scm`).
- **repl** — an interactive prompt with every letloop library on the
  library path.
- **review** — a terminal UI for reviewing a source tree: file tree,
  syntax highlighting, jump-to-definition via `git grep`, and per-line
  annotations persisted to `REVIEW.md`.
- **root** — container-like isolated execution environments built from
  distribution images.

Key flags: `--dev` (debug, profile, instruction counts),
`--optimize-level=0..3`, `--disable-garbage-collector`,
`--visible-libraries`, `--boot=PATH`, `--static`.

`--static` links the C libraries a program imports rather than
dlopening them at run time, working out which ones from the import
closure and pulling each package's own C dependencies along with it.

## Libraries in tree

### Language and data structures

| Library | Description |
| --- | --- |
| `(letloop match)` | Pattern matching (SRFI 241) |
| `(letloop r999)` | `define-record-type*` extended record types |
| `(letloop generator)` | Generators and coroutines |
| `(letloop sq)` | Priority queue |
| `(letloop heap)` | Binary min-heap |
| `(letloop byter)` / `(letloop bytevector)` | Bytevector utilities, ordered-key encoding |
| `(letloop hook)` | Hooks (SRFI 173) |
| `(letloop environment)` | Environment variables (SRFI 98) |

### Web and protocols

| Library | Description |
| --- | --- |
| `(letloop http)` | HTTP request/response reading and writing |
| `(letloop http server)` | HTTP server on the io_uring event loop |
| `(letloop www)` | Web client utilities, URL and form handling |
| `(letloop html)` | HTML parsing (htmlprag) |
| `(letloop xml)` | XML generation with escaping |
| `(letloop sxpath)` | XML/SXML queries (SXPath) |
| `(letloop json)` | JSON reading and writing |
| `(letloop dns)` | DNS resolution over UDP |
| `(letloop tls ...)` | TLS via LibreTLS, including async TLS over io_uring |
| `(letloop postgresql base)` | PostgreSQL wire-protocol v3 client with SCRAM-SHA-256 authentication |
| `(letloop picohttpparser)` | Bindings for the picohttpparser HTTP parser |

### Async I/O

| Library | Description |
| --- | --- |
| `(letloop liburing low)` | io_uring event loop with coroutines: accept, read, write, connect, sleep, poll, buffer rings |

### Storage and queries

| Library | Description |
| --- | --- |
| `(letloop aql)` | Ordered key-value store (OKVS) with key/byte count estimation; see `src/letloop/aql/README.md` |
| `(letloop aql lbst)` | Log-balanced search tree |
| `(letloop aql morton)` | Morton-encoded spatial keys |
| `(letloop aql nstore)` | Tuple store on top of the OKVS |
| `(letloop aql eavt)` | Entity-attribute-value-time index |

### Cryptography

| Library | Description |
| --- | --- |
| `(letloop sodium)` | libsodium: XChaCha20-Poly1305 AEAD, hashing, random |
| `(letloop argon2)` | Argon2id password hashing |
| `(letloop blake3)` | BLAKE3 hashing |
| `(letloop opaque)` | OPAQUE asymmetric password-authenticated key exchange |
| `(letloop srp)` | Secure Remote Password — hand-rolled, unaudited, experimental |

### Terminal UIs

| Library | Description |
| --- | --- |
| `(letloop tea)` | Terminal UI framework — a pure-Scheme termbox2 port: cell grid with damage-diff rendering, terminfo, SGR colors, UTF-8 and East Asian width, keyboard/mouse/paste input parsing, SIGWINCH resize, driven by io_uring |
| `(letloop termbox)` | Compatibility shim preserving the legacy libtermbox2 binding surface |
| `(letloop review)` | The `letloop review` TUI, built on tea |

### System

| Library | Description |
| --- | --- |
| `(letloop cffi)` | C FFI helpers: lazy `dlopen` on first call, locking, errno |
| `(letloop desktop ...)` | Experimental Vulkan + DRM/KMS seat management — not wired into the v12 CLI |

## Testing

Test procedures live **with their library**: a library exports its
`~check-*` procedures and `include`s a sibling `NAME.check.scm`
fragment. `make check` discovers everything under `src/`, and
`letloop check` runs any library the same way:

```shell
letloop check src/ src/letloop/tea/input.scm
```

Checks that need an absent shared object or service (for example
PostgreSQL) print `** SKIP` and pass, so the suite is green on a
minimal machine and exhaustive on a provisioned one.

## Beyond v12: seed

v12 is the last release written in R6RS Scheme. In v13, what exists in
this tree will be **rewritten** to match the syntax and semantics of
**[seed](https://github.com/amirouche/seed)**, letloop's main language
going forward: a dialect of Kernel that brings John Shutt's `vau`
operative to Chez Scheme with an immutable dynamic environment. `vau` unifies procedures and macros into a single
mechanism — no separate expansion-time language — while the immutable
dynamic environment restores enough static knowledge for efficient
compilation.
