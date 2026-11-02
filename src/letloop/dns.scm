;; Copyright © 2026 Amirouche A. BOUBEKKI <amirouche at hyper dev>
(library (letloop dns)

  (export dns-resolve-a

          ~check-dns-000
          ~check-dns-001
          ~check-dns-002
          ~check-dns-003
          ~check-dns-004
          ~check-dns-005)

  (import (chezscheme)
          (letloop aql shims)
          (letloop liburing low))

  (begin
    (include "letloop/dns.body.scm")
    (include "letloop/dns.check.scm")))
