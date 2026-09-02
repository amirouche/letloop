#!chezscheme
(library (letloop package ca-certificates)
  (export package)
  (import (chezscheme))

  ;; A CA bundle, fetch-only -- for (letloop package letloop) to ship
  ;; alongside the binary it produces, at lib/letloop/cert.pem, where
  ;; (letloop tls base)'s bundled-ca-file looks for it.
  ;;
  ;; Exists because LibreSSL's own default CA path is a compile-time
  ;; constant baked into libtls.a at ./configure time -- inside this
  ;; chain's sandbox, /build/out/etc/ssl/cert.pem, a path that exists
  ;; nowhere once the binary is copied out. See
  ;; src/letloop/store/README.md's cold-start section for the failure
  ;; this closes: a relocated, statically-linked letloop's own HTTPS
  ;; fetches (fetch-verify!, https-request, ...) otherwise fail with
  ;; "failed to open CA file", not a linking or symbol error -- the
  ;; static tls wiring itself works, it just has nothing to point at.
  ;;
  ;; curl's own extraction of Mozilla's CA root list, republished
  ;; specifically for exactly this purpose (bundling into an
  ;; application, per https://curl.se/docs/caextract.html) -- not
  ;; Mozilla's raw certdata.txt, which needs its own parser, and not
  ;; this host's own /etc/ssl/certs/ca-certificates.crt, which is
  ;; Debian's build, not something this store controls or can pin by
  ;; content the way a fetch needs to.
  ;;
  ;; Fetched 2026-08-24, 188,900 bytes, 121 certificates, dated by
  ;; curl.se itself to 2026-08-13. This is the one input in the whole
  ;; chain that is expected to go stale on purpose -- CA lists change
  ;; as roots are added and revoked -- and re-pinning it later is a
  ;; deliberate, reviewable update, not a maintenance chore to
  ;; automate away.
  (define package
    '(derivation
     (name "bootstrap-ca-certificates")
     (fetch (cert.pem
             (url "https://curl.se/ca/cacert.pem")
             (hash (blake3 "e18dfa44c027bbfc1f0ecc9d8fee766096492a2921b38e13b45688db87f91d93"))))
     (output "out"))))
