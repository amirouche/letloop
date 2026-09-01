#!chezscheme
(library (letloop store derivation)

  (export derivation-read
          derivation-parse
          derivation?

          derivation-name
          derivation-build-environment
          derivation-inputs
          derivation-fetches
          derivation-script
          derivation-output
          derivation-expected-output-hash

          build-environment?
          build-environment-directory?
          build-environment-derivation?
          build-environment-package?
          build-environment-directory

          input-derivation-reference?
          input-derivation-path
          input-package-reference?
          input-package-name

          fetch?
          fetch-name
          fetch-url
          fetch-hash-algorithm
          fetch-hash-hex

          store-name-valid?

          ~check-derivation-000
          ~check-derivation-001
          ~check-derivation-002
          ~check-derivation-003
          ~check-derivation-004/fetch-only
          ~check-derivation-005/script-without-build-environment
          ~check-derivation-006/build-environment-without-script
          ~check-derivation-007/fetch-only-needs-a-fetch)

  (import (chezscheme)
          (letloop r999))

  (begin
    (include "letloop/store/derivation.body.scm")
    (include "letloop/store/derivation.check.scm")))
