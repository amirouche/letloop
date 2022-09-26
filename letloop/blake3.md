## `(import (letloop blake3))`

### Abstract

blake3 cryptographic hash

### `(make-blake3)`

Return a handle over the hasher.

### `(blake3-update! blake3 bytevector)`

Update `BLAKE3` with the given `BYTEVECTOR`.

### `(blake3-finalize blake3 length)`

Return representation of the hash as a bytevector of the given
`LENGTH`.

### `(blake3 bytevector)`

Return the blake3 hash of `BYTEVECTOR` as a bytevector of length 32.
