# `(import (letloop aql))`

## Status

**draft**

## Issues

## Abstract

`aql` extends the OKVS interface inherited from BerkeleyDB to make
the implementation of efficient extensions easier thanks to the
ability to estimate the count of keys, and the count of bytes.

The key space starts at `(bytevector 0)` and ends at `(bytevector
255)` there is no value associated with `(bytevector 255)` or any
bytevector bigger than that.

## Reference

### `(make-aql filepath [key-maximum-bytes value-maximum-bytes])`

Returns a handle for the database. If `KEY-MAXIMUM-BYTES` and
`VALUE-MAXIMUM-BYTES` are not provided then the default values are
respectively 1024 bytes, and 65536 bytes. If there is a database at
`filepath` then `key-maximum-bytes` and `value-maximum-bytes` are
taken from the existing database file.

### `(aql? obj)`

Returns `#t` if `OBJ` is an instance of `<aql>`. Otherwise, returns
`#f`.

### `(aql-close! aql)`

Close `aql`.

### `(aql-transaction? obj)`

Returns `#t` if `OBJ` is an `<aql-transaction>` instance. Otherwise,
returns `#f`.

### `(aql-handle? obj)`

Returns `#t` if `OBJ` satisfy either `aql?`, `aql-transaction?`. Otherwise, returns `#f`.

### `(aql-key-maximum-size handle)`

Returns the maximum size of a key for the database associated with
`HANDLE`.

### `(aql-value-maximum-size handle)`

Returns the maximum size of a value of the database associated with
`HANDLE`.

### `(make-aql-transaction-variable init)`

Returns a procedure that may take one or two arguments:

- One argument: the procedure takes a transaction as first argument
and returns the current value for the given transaction. `INIT` is the
initial value.

- Two arguments: the procedure takes a transaction as first argument,
and a new value for the associated transaction. It returns no values.

In the following example, `aql-in-transaction` will return `#f`:

```scheme
(define read-only? (make-aql-transaction-variable #t))

(define (proc tx)
  (display (read-only? tx)) ;; => #t
  (aql-set! tx #u8(42) #u8(13 37))
  (read-only? tx #f)
  ...
  (read-only? tx))

(aql-in-transaction aql proc) ;; => #f
```

### `(aql-transaction-parametrize ((parameter value) ...) expr ...)`

Similar to `parametrize`.

### `(aql-begin-hook handle)`

Returns SRFI-173 hook associated with the beginning of a transaction.
This hook gives a chance to extension libraries to initialize their
internal states.

### `(aql-pre-commit-hook handle)`

Returns SRFI-173 hook associated with the end of a transaction.  This
hook gives a chance to extension libraries to execute triggers.

### `(aql-post-commit-hook handle)`

Returns SRFI-173 hook associated with the success of a transaction.
This hook may be used to implement features such as notify or watches.

### `(aql-rollback-hook handle)`

Returns SRFI-173 hook associated with the rollback of a transaction.

### `(aql-in-transaction aql proc [failure [success]])`

Begin a transaction against the database, and execute `PROC`. `PROC`
is called with first and only argument an object that satisfy
`aql-transaction?`. In case of error, rollback the transaction and
execute `FAILURE` with the error object as argument. The default value
of `FAILURE` re-raise the error with `raise`. Otherwise, executes
`SUCCESS` with the returned values of `PROC`.  The default value of
`SUCCESS` is the procedure `values`.

When the transaction begin, `aql-in-transaction` must call the
procedures associated with `aql-begin-hook`.

Just before the transaction commit, `aql-in-transaction` must
call the procedures associated with `aql-pre-commit-hook`.

Just after the transaction commit is a success,
`aql-in-transaction` must call the procedures associated with
`aql-post-commit-hook`.

Just before calling `FAILURE`, `aql-in-transaction` must call
the procedures associated with `aql-rollback-hook`.

`aql-in-transaction` describes the extent of the atomic property, the
A in [ACID](https://en.wikipedia.org/wiki/ACID), of changes against
the underlying database. A transaction will apply all database
operations in `PROC` or none: all or nothing. When
`aql-in-transaction` returns successfully, the changes will be
visible for future transactions, and implement durability, D in
ACID. In case of error, changes will not be visible to other
transactions in all cases. Regarding isolation, and consistency,
respectively the I and C in ACID, TODO...

### `(aql-approximate-key-count handle [key other [offset [limit]]])`

Returns an approximate count of keys between `KEY` and `OTHER`. If `KEY`
and `OTHER` are omitted return the approximate count of keys in the
whole database.

If `OFFSET` integer is provided, `aql-approximate-key-count` will
skip the first `OFFSET` keys from the count.

If `LIMIT` integer is provided, `aql-approximate-key-count` will
consider `LIMIT` keys from the count.

Rationale: It is helpful to know how big is a range to be able to tell
which index to use as seed. Imagine a query against two attributes,
each attribute with their own index and no compound index: being able
to tell which subspace contains less keys, can speed up significantly
query time.

### `(aql-approximate-byte-count handle [key [other [offset [limit]]]])`

Returns an approximation of the number of bytes making the key and
value pairs in the subspace described by `KEY` and `OTHER`. If `OTHER`
is omitted, return the approximate size of the key-value pair
associated with `KEY`. When both `KEY` and `OTHER` are omitted return
the approximated size of the whole database associated with `HANDLE`.

If `OFFSET` integer is provided, `aql-approximate-byte-count` will
skip the first `OFFSET` keys from the count.

If `LIMIT` integer is provided, `aql-approximate-byte-count` will
consider `LIMIT` keys from the count.

Rationale: That is useful in cases where the size of a transaction is
limited.

### `(aql-set! handle key value)`

Associate the bytevector `KEY`, with the bytevector `VALUE`.

### `(aql-remove! handle key)`

Removes the bytevector `KEY`, and its associated value.

### `(aql-query handle key [other [offset [limit]]])`

`AQL-QUERY` will query the associated database.

If only `KEY` is provided it will return the associated value
bytevector; or `#f` if `KEY` is not present.

If `OTHER` is provided there is two cases:

- `KEY < OTHER` then `aql-query` returns a list with all the
  key-value pairs present in the database between `KEY` and `OTHER`
  excluded ie. without the key-value pair associated with `OTHER` if
  any;

- `OTHER < KEY` then `aql-query` returns a list with all the key-value
  pairs present in the database between `OTHER` and `KEY` starting at `OTHER`
  in reverse lexicographic order, any key-value pair associated with `KEY`
  is excluded;

If `OFFSET` integer is provided, `aql-query` will skip as much
key-value pairs from the start of the described subspace.

If `LIMIT` integer is provided the `aql-query` will produce a
list with at most `LIMIT` key-value pairs.

### `(aql-keys handle key [other [offset [limit]]])`

Similar to `aql-query` but returns one or more keys.

If `OTHER` is not provided then it returns key or the next biggest key
smaller than `(bytevector 255)`, otherwise if there isn't any, it
returns the biggest key smaller than `key` bigger than the empty
bytevector.

If `OTHER` is provided and `KEY` is smaller than `OTHER` they it
returns a ordered list of keys between `KEY` and `OTHER` but not
`OTHER`. if `OTHER` is smaller than `KEY` than it return the ordered
list of keys starting from `OTHER` until `KEY` but not `KEY`.


### `(aql-bytevector-next-prefix bytevector)`

Returns the first bytevector that follows `BYTEVECTOR` according to
lexicographic order that is not prefix of `BYTEVECTOR` and for which
`BYTEVECTOR` is not a prefix, such as the following code iterates over
all keys that have `key` as prefix:

```scheme
(aql-query handle key (aql-bytevector-next-prefix key))
```
