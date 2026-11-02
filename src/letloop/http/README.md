# (letloop http server)

An HTTP/1.1 server over io_uring, running on [flow2](../flow2/README.md).
It parses requests with picohttpparser, gives each connection a fiber,
and calls your `dispatch` procedure as a fiber of its own, so a handler
can wait on I/O, timers and channels without holding up any other
connection.

The server runs on one core: one OS thread drives the ring and every
fiber. Scale out across cores with several processes sharing a port
(`SO_REUSEPORT`), not with threads.

## Running a server

From the command line, with a library that exports the three
procedures described under [The contract](#the-contract):

```sh
letloop http serve [--port=PORT] [DIRECTORY ...] LIBRARY.SCM
```

The port defaults to 8080 and the server binds `0.0.0.0`. `DIRECTORY`
arguments are added to the library path; put `./src/` first to run
against a working tree instead of the installed copy.

From Scheme:

```scheme
(import (letloop http server))

(transparent 8080 application context dispatch)
(transparent 8080 "127.0.0.1" application context dispatch)
```

`transparent` returns when SIGINT or SIGTERM stops the server.

To ship a server, compile it into one self-contained executable. This
is how `benchmarks/scheme/bench-server.scm` is built:

```sh
letloop compile --optimize-level=3 ./examples ./benchmarks/scheme \
    ./benchmarks/scheme/bench-server.scm main
```

`./a.out` is then the whole deliverable; see the top-level `CLAUDE.md`
for what `letloop compile` folds into it.

## The contract

```scheme
(library (my-web-library)
  (export application context dispatch)
  (import (chezscheme) (letloop match) (letloop http server))

  ;; once, at startup
  (define (application) (box 0))

  ;; once per connection, on its first request
  (define (context application client req) client)

  (define (dispatch application state method path params req)
    (match (cons method path)
      ((GET)
       (values 200 (html `(html (body (h1 "hello")))) '()))
      ((GET "api")
       (values 200 (json `((who . ,(cond ((assq 'who params) => cdr)
                                         (else "world")))))
               '()))
      (,_ (values 404 (html '(html (body (h1 "Not Found")))) '())))))
```

### `(application)`

Called once, before the server accepts anything. Its result is handed
to every `context` and `dispatch` call. If it raises, the process
prints the error and **exits with status 1**. A server that failed to
build its state must not sit there looking healthy to a supervisor
while nothing listens on the port.

### `(context application client req)`

Called on a connection's first request. `CLIENT` is the peer's IP
address and `REQ` that first request. The result is the connection's
state, passed to every `dispatch` call on that connection.

### `(dispatch application state method path params req [request-context])`

Called once per request, and returns three values:

```scheme
(values STATUS (BODY-BYTEVECTOR . CONTENT-TYPE) EXTRA-HEADERS)
```

| argument | what it is |
|---|---|
| `METHOD` | the request method as a symbol: `GET`, `POST`, … |
| `PATH` | the path as a list of percent-decoded strings: `/` is `()`, `/a/b/` is `("a" "b")`. In a path, `+` stays `+` |
| `PARAMS` | the query string as an alist of `(SYMBOL . STRING)`, with `+` read as a space. `()` if there is none |
| `REQ` | the parsed request, read with the `phr-request-*` accessors below |
| `REQUEST-CONTEXT` | see [Deadlines and the request context](#deadlines-and-the-request-context) |

`EXTRA-HEADERS` is an alist of `(SYMBOL . STRING)`, for example
`'((location . "/"))`. The server adds `content-type`, `date` and
`content-length` itself.

The server checks `dispatch`'s arity once, at startup. A seven-argument
procedure gets the request context. A six-argument one is called
without it, which is the contract from before the context existed. Any
other arity is refused before the server takes a connection.

Paths and query strings may contain raw UTF-8, as in `GET /日本`; both
are decoded as UTF-8.

### Building a response

| procedure | result |
|---|---|
| `(html SXML)` | `(BYTES . "text/html")` |
| `(json OBJ)` | `(BYTES . "application/json")` |
| `(xml SXML)` | `(BYTES . "application/xml")` |
| `(response 'text STRING)` | `(BYTES . "text/plain")` |
| `(response TYPE OBJ)` | any of the above, by symbol |

Or build the pair yourself: `(cons bytevector "image/png")`.

### Reading the request

| procedure | result |
|---|---|
| `(phr-request-method-symbol req)` | the method symbol, as passed to `dispatch` |
| `(phr-request-header-ref req name)` | a header's value as a string, case-insensitive; `#f` if absent |
| `(phr-request-header-count req)` | how many headers |
| `(phr-request-header-name req i)` / `(phr-request-header-value req i)` | the `I`th header |
| `(phr-request-body req)` | the body, as a bytevector; empty without `content-length` |

## What a handler may do

`dispatch` runs as a flow2 fiber on the loop thread, so anything a
flow2 fiber may do, a handler may do. It can sleep (`flow-sleep`), use
channels and latches, start fibers of its own (`flow-spawn`), race
events with `flow-choice`, and do I/O on other descriptors
(`flow-read`, `flow-write`, `flow-open`, …).

What a handler must **not** do is block the thread. A blocking syscall,
a `sleep`, or a long CPU-bound loop stops every connection on the
server until it returns. The server starts no compute pool
(`flow-run`'s worker count is 0), so there is nowhere to hand CPU-bound
work to yet.

## Deadlines and the request context

A handler that suspends is raced against two things:

- **A deadline of 28 seconds.** If it passes, the client gets
  `504 Gateway Timeout` and the connection closes.
- **The connection itself.** If a read on it fails (a reset, or a close
  under the server), the response is abandoned and the connection
  closes.

Either way the handler keeps running: flow2 has no cancellation. The
request context is how it finds out it should stop:

```scheme
(define (dispatch application state method path params req rctx)
  (let loop ((pages '()))
    (if (or (done? pages) (not (request-context-needed? rctx)))
        (values 200 (json (summarise pages)) '())
        (loop (cons (fetch-next-page) pages)))))
```

`(request-context-needed? rctx)` is `#t` until the server gives up on
the request, then `#f`. It is safe to read from another OS thread. A
handler that fans work out should check it before starting more, and
stop waiting on stragglers once it reads `#f`.

## Connections

**Keep-alive** is the default. A request with `Connection: close` gets
its response, and then the connection closes.

**Pipelining** works. A client may send its next request before the
current response arrives, in the same packet or a later one, and the
responses come back in request order. Bytes that arrive while a handler
runs are kept for after its response, and the rest waits in the socket.

**Half-close** works. A client that sends a request and then shuts
down its write side still gets its response; the connection closes
after it.

**Idle connections** are reaped. A sweep every 5 seconds closes any
connection with no read or write activity in the last 30 seconds, so
an idle connection is closed 30 to 35 seconds after it went quiet. The
dispatch deadline (28 s) is shorter on purpose, so a slow request gets
a 504 and not a silent reset from the reaper.

**Request bodies** need `Content-Length`. Chunked request bodies
(`Transfer-Encoding: chunked`) are not supported.

**Malformed requests** get `400 Bad Request`, and the connection
closes.

## Errors and logging

The server logs through flow2's log. Unless the program has taken the
log over, that is stderr, one `(TIMESTAMP . ENTRY)` per line (see
flow2's *Diagnostics*). A connection fiber that dies on an error
nothing caught appears as `(flow2 uncaught fiber CONDITION)`, and the
server carries on.

A **raising `dispatch`** closes its connection without a response, and
nothing is logged; see [Known issues](#known-issues). Catch inside the
handler and return a 500 yourself:

```scheme
(define (dispatch application state method path params req)
  (guard (ex (#t (values 500 (response 'text "internal error") '())))
    (route application state method path params req)))
```

## Shutdown

SIGINT or SIGTERM prints a line to stdout and fires a stop latch. The
accept loop, which races every accept against that latch, closes the
listening socket and ends the run with `flow-stop`. This is a
shutdown, not a drain. Requests in flight are not finished and open
connections are not closed gracefully; the process simply stops
serving, and `transparent` returns.

The port is bound before the run starts, and before `(application)`
is called, so a port that cannot be had raises from `transparent` with
the reason.

## Performance

`bench-server`, compiled at `--optimize-level=3` with the server pinned
to one core and `wrk -t7 -c64 -d10s` on seven others, serves about
285k requests per second on the machine this was last measured on.
Absolute numbers depend on the machine. To compare two versions, build
both and run them back to back on the same machine.

The server is written against flow2's exports alone: it reads with
`flow-read`, writes with `flow-write-all!`, closes with `flow-close`,
and listens with `flow-listen`. Nothing reaches under flow2 into the
ring layer. That costs throughput on this benchmark, whose handler
answers without waiting. Before, the server read with the ring layer's
`loop-read`, and let `dispatch` run before arming the deadline and the
read, so an answer that was already there cost no timer and no recv
to cancel. That version served about 374k on the same machine.

A handler that does I/O suspends either way, so the deadline and the
read are armed for it regardless; the gap is narrower for real
handlers than for this one.

What closed part of the gap went into flow2, where every program gets
it: the 28 s deadline is a heap entry rather than a kernel timer, so
arming and cancelling it costs no syscall (+11%); the dispatch outcome
travels in a latch that takes no OS mutex (+7%); and a perform with
nothing to cancel skips the cancel pass (+1.5%). The server on flow2
alone measured 249k before those.

## Lower-level exports

| procedure | use |
|---|---|
| `(try-parse-http-request buf out [req-vec])` | parse one request from `BUF`: `(values req remainder)`, `(values #f #f)` when more bytes are needed, `(values 'bad-request #f)` |
| `(uri-parse/range buf offset len)` | `(values path params)` for a request target inside a bytevector |
| `(http-response-write* write status reason headers body)` | write one response through `WRITE` |
| `(status-code->reason code)` | the reason phrase for a status code |

## Known issues

- **A raising `dispatch` is silent.** The connection closes with no
  response and no log entry. Guard in the handler, as shown above.
- **`status-code->reason` knows 12 codes.** Any other status, 503 for
  instance, goes out as `503 OK`.
- **No compute pool.** A handler has nowhere to send CPU-bound work.

## Tests

| what | how |
|---|---|
| unit checks | `letloop check src/ src/letloop/http/server.scm` |
| half-close and pipelining, end to end | `./venv $(pwd)/local/ bash checks/check-http-keepalive-semantics.sh` |
| the example app, end to end (installed copy) | `checks/check-transparenturing.sh` |
| load and leaks | `checks/stress-transparenturing.sh` |
