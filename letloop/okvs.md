# `(import (letloop okvs))`

![3d cube made of smaller cubes. 3x3x3. All small cubes are blue except one. The big cube is floating in an anaytical space.](okvs-cover-by-c-lee.jpg)

## Status

**draft**

## Issues

None, at this time.

## Abstract

`(letloop okvs)` extends the OKVS interface inherited from BerkeleyDB
to make the implementation of efficient extensions easier thanks to
the ability to estimate the count of keys, and the count of bytes.

## Rationale

There is several existing databases that expose an interface similar
to `okvs`, and even more that use an Ordered Key-Value Store (OKVS) as
their backing storage.

While `okvs` interface is lower-level than the mainstream SQL, it also
has the advantage of having less moving pieces, and stems from a
well-known datastructure, part of every software engineering
curriculum, namely binary trees, it makes `okvs` a good teaching
material that has immediate useful applications, including building
your own SQL database. Last but not least, `okvs` pin the current
practice of building databases on top of a similar tool.

`okvs` can be used to build many datastructures, called
*extensions*. Possible extensions of `okvs` are counter, bag, set, and
multi-mapping. Higher level extensions include
[Entity-Attribute-Value](https://en.wikipedia.org/wiki/Entity%E2%80%93attribute%E2%80%93value_model)
possibly supported by datalog, Generic Tuple Store (nstore) inspired
from [Resource Description
Framework](https://en.wikipedia.org/wiki/Resource_Description_Framework)
that can match the query capabilities of
[SPARQL](https://www.w3.org/TR/rdf-sparql-query/), and
[RDF-star](https://w3c.github.io/rdf-star/cg-spec/), or the Versioned
Generic Tuple Store (vnstore), that ease the implementation of
bitemporal databases. Also, it is possible to implement a property
graph database, ranked set, leaderboard, priority queue. It is
possible to implement efficient geometric queries with the help of
xz-ordered curves.

## Reference

### `(make-okvs)`

Returns a handle for the database.

### `(okvs? obj)`

Returns `#t` if `OBJ` is an instance of `<okvs>`. Otherwise, returns
`#f`.

### `(okvs-close okvs)`

Close `okvs`.

### `(okvs-transaction? obj)`

Returns `#t` if `OBJ` is an `<okvs-transaction>` instance. Otherwise,
returns `#f`.

### `(okvs-cursor? obj)`

Returns `#t` if `OBJ` is an `<okvs-cursor>` instance. Otherwise,
returns `#f`.

### `(okvs-handle? obj)`

Returns `#t` if `OBJ` satisfy either `okvs?`, `okvs-transaction?`, or
`okvs-cursor?`. Otherwise, returns `#f`.

### `(okvs-key-max-size handle)`

Returns the maximum size of a key for the database associated with
`HANDLE`.

### `(okvs-value-max-size handle)`

Returns the maximum size of a value of the database associated with
`HANDLE`.

### `(make-okvs-transaction-variable init)`

Returns a procedure that may take one or two arguments:

- One argument: the procedure takes a transaction as first argument
and returns the current value for the given transaction. `INIT` is the
initial value.

- Two arguments: the procedure takes a transaction as first argument,
and a new value for the associated transaction. It returns no values.

In the following example, `okvs-in-transaction` will return `#f`:

```scheme
(define read-only? (make-okvs-transaction-parameter #t))

(define (proc tx)
  (display (read-only? tx)) ;; => #t
  (okvs-set tx #u8(42) #u8(13 37))
  (read-only? tx #f)
  ...
  (read-only? tx))

(okvs-in-transaction okvs proc) ;; => #f
```

### `(okvs-transaction-parametrize ((parameter value) ...) expr ...)`

Similar to `parametrize`.

### `(okvs-begin-hook handle)`

Returns SRFI-173 hook associated with the beginning of a transaction.
This hook gives a chance to extension libraries to initialize their
internal states. The procedures associated with this hook must execute
just after the transaction is started.

### `(okvs-pre-commit-hook handle)`

Returns SRFI-173 hook associated with the end of a transaction.  This
hook gives a chance to extension libraries to execute triggers.

### `(okvs-post-commit-hook handle)`

Returns SRFI-173 hook associated with the success of a transaction.
This hook may be used to implement features such as notify or watches.

### `(okvs-rollback-hook handle)`

Returns SRFI-173 hook associated with the rollback of a transaction.

### `(okvs-in-transaction okvs proc [failure [success]])`

Begin a transaction against the database, and execute `PROC`. `PROC`
is called with first and only argument an object that satisfy
`okvs-transaction?`. In case of error, rollback the transaction and
execute `FAILURE` with the error object as argument. The default value
of `FAILURE` re-raise the error with `raise`. Otherwise, executes
`SUCCESS` with the returned values of `PROC`.  The default value of
`SUCCESS` is the procedure `values`.

When the transaction begin, `okvs-in-transaction` must call the
procedures associated with `okvs-begin-hook`.

Just before the transaction commit, `okvs-in-transaction` must
call the procedures associated with `okvs-pre-commit-hook`.

Just after the transaction commit is a success,
`okvs-in-transaction` must call the procedures associated with
`okvs-post-commit-hook`.

Just before calling `FAILURE`, `okvs-in-transaction` must call
the procedures associated with `okvs-rollback-hook`.

`okvs-in-transaction` describes the extent of the atomic property, the
A in [ACID](https://en.wikipedia.org/wiki/ACID), of changes against
the underlying database. A transaction will apply all database
operations in `PROC` or none: all or nothing. When
`okvs-in-transaction` returns successfully, the changes will be
visible for future transactions, and implement durability, D in
ACID. In case of error, changes will not be visible to other
transactions in all cases. Regarding isolation, and consistency,
respectively the I and C in ACID, TODO...

### `(okvs-call-with-cursor handle proc)`

Open a cursor against `HANDLE` and call `PROC` with it. When `PROC`
returns, the cursor is closed.

If `HANDLE` satisfy `okvs?`, `okvs-call-with-cursor` must wrap the
call to `PROC` with `okvs-in-transaction`.

If `HANDLE` satisfy `okvs-cursor?`, `okvs-call-with-cursor` must pass
a cursor positioned at the same position as `HANDLE`.

The cursor is stable: the cursor will see a snapshot of keys of the
database taken when `okvs-call-with-cursor` is called. During the
extent of `PROC`, `okvs-set` and `okvs-remove`  will not
change the position of the cursor, and the cursor will not see removed
keys, and not see added keys. Keys which value was changed during
cursor navigation, that exist when `okvs-call-with-cursor` is
called, can also be seen.

### `(okvs-approximate-key-count handle [key other [offset [limit]]])`

Returns an approximate count of keys between `KEY` and `OTHER`. If `KEY`
and `OTHER` are omitted return the approximate count of keys in the
whole database.

If `OFFSET` integer is provided, `okvs-approximate-key-count` will
skip the first `OFFSET` keys from the count.

If `LIMIT` integer is provided, `okvs-approximate-key-count` will
consider `LIMIT` keys from the count.

Rationale: It is helpful to know how big is a range to be able to tell
which index to use as seed. Imagine a query against two attributes,
each attribute with their own index and no compound index: being able
to tell which subspace contains less keys, can speed up significantly
query time.

### `(okvs-approximate-byte-count handle [key [other [offset [limit]]]])`

Returns an approximation of the number of bytes making the key and
value pairs in the subspace described by `KEY` and `OTHER`. If `OTHER`
is omitted, return the approximate size of the key-value pair
associated with `KEY`. When both `KEY` and `OTHER` are omitted return
the approximated size of the whole database associated with `HANDLE`.

If `OFFSET` integer is provided, `okvs-approximate-byte-count` will
skip the first `OFFSET` keys from the count.

If `LIMIT` integer is provided, `okvs-approximate-byte-count` will
consider `LIMIT` keys from the count.

Rationale: That is useful in cases where the size of a transaction is
limited.

### `(okvs-set handle key value)`

Associate the bytevector `KEY`, with the bytevector `VALUE`.

### `(okvs-remove handle key)`

Removes the bytevector `KEY`, and its associated value.

### `(okvs-cursor-search cursor key)`

Position `CURSOR` on `KEY` or an adjacent key. Returns a symbol
describing the position of the cursor:

- Return `'cursor-exact-key`, when `KEY` is found;

- Returns `'cursor-before-key`, when `KEY` is not found, and the cursor is
  positioned on a key, before `KEY`;

- If there is no key before `KEY`, but there is a key after, returns
  `'cursor-after-key`;

- If the the database is empty, returns `'cursor-empty`;

### `(okvs-cursor-next? cursor)`

Move the `CURSOR` to the next key if any, and returns `#t`. Otherwise,
if there is no next key returns `#f`. `#f` means the cursor reached
the end of the key space.

### `(okvs-cursor-previous? cursor)`

Move the `CURSOR` to the previous key if any, and returns
`#t`. Otherwise, if there is no previous key returns `#f`. `#f` means
the cursor reached the begining of the key space.

### `(okvs-cursor-key cursor)`

Returns the key bytevector on the position of the `CURSOR`.

It is an error to call `okvs-cursor-key`, when `CURSOR` reached
the begining or end of the key space.

### `(okvs-cursor-value cursor)`

Returns the value bytevector on the position of the `CURSOR`.

It is an error to call `okvs-cursor-key`, when `CURSOR` reached
the begining or end of the key space.

### `(okvs-query handle key [other [offset [limit]]])`

`OKVS-QUERY` will query the associated database.

If only `KEY` is provided it will return the associated value
bytevector; or `#f` if `KEY` is not present.

If `OTHER` is provided there is two cases:

- `KEY < OTHER` then `okvs-query` returns a list with all the
  key-value pairs present in the database between `KEY` and `OTHER`
  excluded ie. without the key-value pair associated with `OTHER` if
  any;

- `OTHER < KEY` then `okvs-query` returns a list with all the key-value
  pairs present in the database between `OTHER` and `KEY` starting at `OTHER`
  in reverse lexicographic order, any key-value pair associated with `KEY`
  is excluded;

If `OFFSET` integer is provided, `okvs-query` will skip as much
key-value pairs from the start of the described subspace.

If `LIMIT` integer is provided the `okvs-query` will produce a
list with at most `LIMIT` key-value pairs.

### `(okvs-bytevector-next-prefix bytevector)`

Returns the first bytevector that follows `BYTEVECTOR` according to
lexicographic order that is not prefix of `BYTEVECTOR` and for which
`BYTEVECTOR` is not a prefix, such as the following code iterates over
all keys that have `key` as prefix:

```scheme
(okvs-query handle key (okvs-bytevector-next-prefix key))
```
