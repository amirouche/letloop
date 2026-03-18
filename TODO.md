# TODO

References:
- https://bun.com/reference
- https://codeberg.org/amirouche/letloop

## Builtin Core Features

- [ ] **Node.js compatibility** — drop-in replacement for Node.js apps
- [ ] **Web Standard APIs** — fetch, URL, EventTarget, Headers, etc.
- [ ] **Native Addons / C interop** — call C-compatible native code from JavaScript
- [ ] **TypeScript** — first-class support, including "paths" enum namespace
- [ ] **JSX** — first-class support without configuration
- [ ] **Module loader plugins** — plugin API for importing/requiring custom file types
- [ ] **Async I/O** — bug-free epoll transparent async with network I/O (untangle), tested against httpbin

## Builtin APIs

- [ ] **PostgreSQL, MySQL, SQLite, and LMDB drivers** — fast, unified SQL/KV API
- [ ] **S3 Cloud Storage driver** — upload/download from S3-compatible storage
- [ ] **Redis client** — built-in with Pub/Sub support
- [ ] **WebSocket server** — including pub/sub and backpressure handling
- [ ] **HTTP server** — lightning-fast, built-in; robust reader and writer with full error handling
- [ ] **HTTP router** — dynamic paths and wildcards
- [ ] **Single-file executables** — compile to a standalone executable
- [ ] **YAML** — first-class support, like JSON
- [ ] **JSON** — parser review and improvements: correctness, readability, CLI
- [ ] **Cookies API** — parse and set cookies with a Map-like API
- [ ] **Encrypted Secrets Storage** — OS-native keychain integration

## Builtin Tooling

- [ ] **npm package management** — install, manage, and publish npm-compatible dependencies
- [ ] **Bundler** — production-ready code for frontend & backend, works with packages
- [ ] **Cross-platform $ shell API** — native bash-like shell for scripting
- [ ] **Jest-compatible test runner** — compatible with Jest
- [ ] **Hot reloading (server)** — reload backend without disconnecting connections
- [ ] **Monorepo support** — workspaces and cross-workspace commands
- [ ] **Frontend Development Server** — fully-featured dev server
- [ ] **Formatter & Linter** — built-in
- [ ] **Error messages** — source code locations, snippets, and explanations
- [ ] **Language server** — IDE integration (go-to-definition, completions, etc.)
- [ ] **Documentation source** — canonical reference that most libraries link to
- [ ] **Project generator** — scaffold new projects
- [ ] **Online playground** — run and share code in the browser
- [ ] **Version manager** — install and switch between language versions

## Builtin Utilities

- [ ] **Password & Hashing APIs** — bcrypt, argon2, and non-cryptographic hashes
- [ ] **String Width API** — calculate terminal display width of a string
- [ ] **Glob API** — glob patterns for file matching
- [ ] **Semver API** — compare and sort semver strings
- [ ] **CSS color conversion API** — convert between CSS color formats
- [ ] **CSRF API** — generate and verify CSRF tokens

## Ecosystem Libraries

- [ ] **Data structures** — standard collections beyond arrays and maps
- [ ] **Serialization** — formats beyond JSON/YAML (MessagePack, CBOR, Protobuf, etc.)
- [ ] **HTML parser** — with SXPath and CSS selector support, based on justhtml (https://github.com/EmilStenstrom/justhtml/)
- [ ] **TLS / HTTP client** — openssl/libtls bindings for Chez Scheme, or libcurl bindings
- [ ] **Authentication** — OAuth, sessions, JWT, etc.
- [ ] **Error handling** — structured errors, result types, stack enrichment
- [ ] **Regexes** — extended regex support or a dedicated library
- [ ] **Cryptography** — symmetric/asymmetric encryption beyond hashing

## Web Development

- [ ] **Template engine** — server-side HTML rendering (Mustache/Jinja-style); composable, escapable, streaming-friendly
- [ ] **Multipart / form-data** — parse `multipart/form-data` requests for file uploads and HTML form submissions
- [ ] **Email (SMTP client)** — send transactional email; support TLS, AUTH, attachments
- [ ] **Background jobs / task queues** — async workers, retry logic, scheduling, dead-letter queues
- [ ] **Database migrations** — schema versioning tool; up/down migrations, state tracking
- [ ] **Structured logging** — JSON log output, log levels, request-scoped context propagation
- [ ] **Metrics + tracing** — OpenTelemetry-compatible instrumentation; counters, histograms, spans
- [ ] **Config management** — TOML and dotenv parsing, layered config (env > file > defaults)
- [ ] **Middleware pipeline** — composable request/response middleware with `next` chaining
- [ ] **Rate limiting** — per-IP, per-user, and global limits; token-bucket and sliding-window algorithms
- [ ] **i18n / l10n** — internationalization: message catalogs, plural rules, locale-aware formatting
- [ ] **GraphQL** — server (schema + resolvers) and client (query execution)
- [ ] **gRPC** — Protobuf code generation and streaming RPC over HTTP/2
- [ ] **SSE (Server-Sent Events)** — lightweight alternative to WebSocket for server-push streams
- [ ] **WASM target** — compile Scheme to WebAssembly for in-browser execution
- [ ] **Headless browser control** — drive a browser via CDP/Playwright protocol for E2E and functional tests

## Desktop Development

- [ ] **GUI — webview** — embed a browser engine (Tauri/Electron model) for cross-platform HTML/CSS UI
- [ ] **GUI — native toolkit** — GTK, Qt, or SDL2 bindings for native look-and-feel
- [ ] **2D graphics** — Cairo or Skia bindings for custom rendering, canvas-style drawing
- [ ] **Audio / media** — SDL_mixer, PipeWire, or PortAudio bindings for playback and recording
- [ ] **File system watching** — unified abstraction over inotify (Linux), FSEvents (macOS), kqueue (BSD)
- [ ] **IPC** — pipes, Unix domain sockets, named pipes; D-Bus on Linux
- [ ] **System tray** — OS tray icon with context menu (libappindicator / systray)
- [ ] **Native dialogs** — file picker, message boxes, color picker via OS-native APIs
- [ ] **Clipboard** — read and write text/image data from the system clipboard
- [ ] **Notifications** — OS push notifications (libnotify on Linux, UNUserNotificationCenter on macOS)
- [ ] **App packaging** — produce .deb/.rpm, .dmg, .msi, AppImage, and Flatpak bundles
- [ ] **Auto-updater** — delta updates with cryptographic signature verification
- [ ] **OAuth2 PKCE** — desktop-specific auth flow using loopback redirect URI
- [ ] **D-Bus** — Linux system/session bus integration for IPC with system services
- [ ] **Hardware access** — camera, microphone, and GPU compute (OpenCL/Vulkan) bindings
