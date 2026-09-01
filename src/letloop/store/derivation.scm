#!chezscheme
(library (letloop store derivation)

  (export derivation-read
          derivation?

          derivation-name
          derivation-build-environment
          derivation-inputs
          derivation-fetches
          derivation-script
          derivation-output
          derivation-expected-output-hash

          build-environment?
          build-environment-rootfs?
          build-environment-directory?
          build-environment-distribution
          build-environment-version
          build-environment-machine
          build-environment-directory

          fetch?
          fetch-name
          fetch-url
          fetch-hash-algorithm
          fetch-hash-hex

          store-name-valid?

          ~check-derivation-000
          ~check-derivation-001
          ~check-derivation-002
          ~check-derivation-003)

  (import (chezscheme)
          (letloop r999))

  (begin
    (include "letloop/store/derivation.body.scm")
    (include "letloop/store/derivation.check.scm")))
