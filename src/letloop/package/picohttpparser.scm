#!chezscheme
(library (letloop package picohttpparser)
  (export package)
  (import (chezscheme))

  ;; libpicohttpparser, built from source against the bootstrap
  ;; toolchain, as a static archive -- for (letloop picohttpparser),
  ;; which dlopen's libpicohttpparser.so at runtime.
  ;;
  ;; picohttpparser ships no build system that produces an archive on
  ;; its own -- src/letloop/picohttpparser_wrapper.c does
  ;; #include "picohttpparser.c" directly and is the only thing this
  ;; chain actually needs compiled, so the whole build is one gcc -c
  ;; and one ar rcs, matching the repo's own `make picohttpparser`
  ;; target.
  ;;
  ;; The wrapper has no store path of its own to fetch (it lives beside
  ;; letloop's own source, not upstream), so it is inlined into the
  ;; build script verbatim, the same way v1's own store-static-hello
  ;; smoke test inlined a Scheme program -- there is no derivation
  ;; input kind yet for "a file from this checkout" to fetch instead.
  ;; If it drifts from src/letloop/picohttpparser_wrapper.c, this copy
  ;; is what is stale.
  ;;
  ;; No tagged release exists upstream for the version this repo
  ;; already builds against (git clone of the default branch, in the
  ;; makefile) -- v1.2 is the newest tag, and is what is pinned here
  ;; instead, for a reproducible fetch. wrapper.c's #include of
  ;; picohttpparser.c is what actually needs to agree with v1.2's
  ;; struct phr_header shape; nothing here has broken against it.
  ;;
  ;; Source tarball fetched 2026-08-24 from the v1.2 tag, 18,672 bytes.
  (define package
    '(derivation
     (name "bootstrap-picohttpparser")
     (build-environment (root (package (letloop package rootfs-final))))
     (fetch (picohttpparser.tar.gz
             (url "https://github.com/h2o/picohttpparser/archive/refs/tags/v1.2.tar.gz")
             (hash (blake3 "cf02b9d2d8388affa149a97f27455c01d2afd573d7b8a5bf047a01297b0cd820"))))
     (script
      "set -e\n"
      "mkdir -p /build/out/lib /build/out/include\n"
      "tar xzf fetch/picohttpparser.tar.gz --no-same-owner\n"
      "cat > picohttpparser-1.2/picohttpparser_wrapper.c <<'PICOHTTPPARSER_WRAPPER_EOF'\n"
      "/*\n"
      " * picohttpparser wrapper for Chez Scheme FFI\n"
      " *\n"
      " * Converts absolute pointers returned by phr_parse_request/phr_parse_response\n"
      " * into buffer-relative offsets, making them trivial to read from Scheme using\n"
      " * bytevector-u64-ref / bytevector-s32-ref.\n"
      " *\n"
      " * Output buffer layout (all offsets relative to input buf):\n"
      " *\n"
      " *   Bytes   Field\n"
      " *   [0..7]  method_offset (size_t)\n"
      " *   [8..15] method_len (size_t)\n"
      " *   [16..23] path_offset (size_t)\n"
      " *   [24..31] path_len (size_t)\n"
      " *   [32..35] minor_version (int32)\n"
      " *   [36..39] padding\n"
      " *   [40..47] num_headers (size_t)\n"
      " *   [48..]  per-header entries, each 32 bytes:\n"
      " *           [+0..+7]   name_offset (size_t)\n"
      " *           [+8..+15]  name_len (size_t)\n"
      " *           [+16..+23] value_offset (size_t)\n"
      " *           [+24..+31] value_len (size_t)\n"
      " *\n"
      " * For response parsing:\n"
      " *   [0..3]  status (int32)\n"
      " *   [4..7]  minor_version (int32)\n"
      " *   [8..15] msg_offset (size_t)\n"
      " *   [16..23] msg_len (size_t)\n"
      " *   [24..31] num_headers (size_t)\n"
      " *   [32..]  per-header entries (same 32-byte layout)\n"
      " */\n"
      "\n"
      "#include \"picohttpparser.c\"\n"
      "\n"
      "#define PHR_MAX_HEADERS 100\n"
      "\n"
      "int phr_parse_request_wrapper(const char *buf, size_t len,\n"
      "                               char *out, size_t max_headers,\n"
      "                               size_t last_len)\n"
      "{\n"
      "    const char *method, *path;\n"
      "    size_t method_len, path_len;\n"
      "    int minor_version;\n"
      "    struct phr_header headers[PHR_MAX_HEADERS];\n"
      "    size_t num_headers;\n"
      "\n"
      "    if (max_headers > PHR_MAX_HEADERS)\n"
      "        max_headers = PHR_MAX_HEADERS;\n"
      "    num_headers = max_headers;\n"
      "\n"
      "    int ret = phr_parse_request(buf, len,\n"
      "                                 &method, &method_len,\n"
      "                                 &path, &path_len,\n"
      "                                 &minor_version,\n"
      "                                 headers, &num_headers,\n"
      "                                 last_len);\n"
      "\n"
      "    if (ret > 0) {\n"
      "        /* method */\n"
      "        *(size_t *)(out + 0) = (size_t)(method - buf);\n"
      "        *(size_t *)(out + 8) = method_len;\n"
      "        /* path */\n"
      "        *(size_t *)(out + 16) = (size_t)(path - buf);\n"
      "        *(size_t *)(out + 24) = path_len;\n"
      "        /* minor version */\n"
      "        *(int *)(out + 32) = minor_version;\n"
      "        /* padding at 36..39 is left as-is */\n"
      "        /* num_headers */\n"
      "        *(size_t *)(out + 40) = num_headers;\n"
      "        /* headers */\n"
      "        for (size_t i = 0; i < num_headers; i++) {\n"
      "            size_t base = 48 + i * 32;\n"
      "            if (headers[i].name != NULL) {\n"
      "                *(size_t *)(out + base + 0) = (size_t)(headers[i].name - buf);\n"
      "                *(size_t *)(out + base + 8) = headers[i].name_len;\n"
      "            } else {\n"
      "                *(size_t *)(out + base + 0) = 0;\n"
      "                *(size_t *)(out + base + 8) = 0;\n"
      "            }\n"
      "            *(size_t *)(out + base + 16) = (size_t)(headers[i].value - buf);\n"
      "            *(size_t *)(out + base + 24) = headers[i].value_len;\n"
      "        }\n"
      "    }\n"
      "\n"
      "    return ret;\n"
      "}\n"
      "\n"
      "int phr_parse_response_wrapper(const char *buf, size_t len,\n"
      "                                char *out, size_t max_headers,\n"
      "                                size_t last_len)\n"
      "{\n"
      "    int minor_version, status;\n"
      "    const char *msg;\n"
      "    size_t msg_len;\n"
      "    struct phr_header headers[PHR_MAX_HEADERS];\n"
      "    size_t num_headers;\n"
      "\n"
      "    if (max_headers > PHR_MAX_HEADERS)\n"
      "        max_headers = PHR_MAX_HEADERS;\n"
      "    num_headers = max_headers;\n"
      "\n"
      "    int ret = phr_parse_response(buf, len,\n"
      "                                  &minor_version, &status,\n"
      "                                  &msg, &msg_len,\n"
      "                                  headers, &num_headers,\n"
      "                                  last_len);\n"
      "\n"
      "    if (ret > 0) {\n"
      "        *(int *)(out + 0) = status;\n"
      "        *(int *)(out + 4) = minor_version;\n"
      "        *(size_t *)(out + 8) = (msg != NULL) ? (size_t)(msg - buf) : 0;\n"
      "        *(size_t *)(out + 16) = msg_len;\n"
      "        *(size_t *)(out + 24) = num_headers;\n"
      "        for (size_t i = 0; i < num_headers; i++) {\n"
      "            size_t base = 32 + i * 32;\n"
      "            if (headers[i].name != NULL) {\n"
      "                *(size_t *)(out + base + 0) = (size_t)(headers[i].name - buf);\n"
      "                *(size_t *)(out + base + 8) = headers[i].name_len;\n"
      "            } else {\n"
      "                *(size_t *)(out + base + 0) = 0;\n"
      "                *(size_t *)(out + base + 8) = 0;\n"
      "            }\n"
      "            *(size_t *)(out + base + 16) = (size_t)(headers[i].value - buf);\n"
      "            *(size_t *)(out + base + 24) = headers[i].value_len;\n"
      "        }\n"
      "    }\n"
      "\n"
      "    return ret;\n"
      "}\n"
      "PICOHTTPPARSER_WRAPPER_EOF\n"
      "cd picohttpparser-1.2\n"
      "gcc -c -O3 picohttpparser_wrapper.c\n"
      "ar rcs libpicohttpparser.a picohttpparser_wrapper.o\n"
      "cp libpicohttpparser.a /build/out/lib/\n"
      "cp picohttpparser.h /build/out/include/\n"
      "cp picohttpparser_wrapper.c /build/out/include/\n"
      ;; the two entry points (letloop picohttpparser) resolves must be
      ;; there, or letloop links fine and fails at its first parse
      "nm /build/out/lib/libpicohttpparser.a > /build/symbols\n"
      "grep -q ' T phr_parse_request_wrapper' /build/symbols\n"
      "grep -q ' T phr_parse_response_wrapper' /build/symbols\n")
     (output "out"))))
