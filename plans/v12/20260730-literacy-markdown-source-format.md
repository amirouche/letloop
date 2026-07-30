# Task: `(letloop literacy)` — a markdown-first source format

Add a literate source format: a `.md` file of prose interleaved with
fenced code blocks, tangled into the `.scm` files letloop already
compiles. Markdown becomes the thing a human edits; `.scm` becomes a
build product.

This is new capability. It must not change how libraries are resolved,
compiled, amalgamated, or discovered — the tangler runs *before* all of
that and hands the existing pipeline exactly the files it expects today.

## The constraint that decides the design

Chez resolves libraries itself. `library-directories` locates the file,
`library-extensions` picks the suffix pair, and the source is read with
the standard reader — there is no hook for supplying a different one.
So `.md` **cannot** be appended to `library-extensions` and handed to
Chez: the first time `compile-whole-program`, `environment`, or an
`import` goes looking for `(letloop foo)`, it will `read` markdown and
raise.

Everything below follows from that. `literacy` is a **one-way
preprocessor**. There is no untangle, no round-trip, no markdown at any
point downstream of tangling.

## Verified repo context

- **`maybe-read-library` (`src/letloop/base.scm:1354`)** reads only the
  *first* datum: `(call-with-input-file file read)`, then checks it is
  `(library (name ...) ...)` and scans exports for the `~check-` prefix.
  Tangled output must therefore have the `library` form as the first
  datum in the file. It already fails softly on a non-Scheme file —
  `guard (ex (else #f))` → returns `'()` — so today a stray `.md` under
  `./src/` is skipped silently rather than crashing `letloop check`.
- **`ftw` (`src/letloop/base.scm:~440`)** returns *every* file under a
  directory, not just `.scm`; the filtering is done downstream by
  `maybe-read-library` (for checks) and `maybe-library?` (for
  discovery). So `.md` files are already reachable by a walk that exists.
- **`maybe-library?` (`src/letloop/base.scm:301`)** tests suffixes against
  `(map car (library-extensions))` — the seam where a `.md` would have to
  be declared if it were a library, and precisely what we must *not* do.
- **`letloop-discover-libraries` (`src/letloop/base.scm:494`)** walks
  `(library-directories)` and keeps what `maybe-library-name` validates
  *by importing it*. Generated `.scm` must be on disk before this runs.
- **`guess` (`src/letloop/base.scm:453`)** classifies each CLI argument as
  `directory` / `file` / `extension` / `unknown`. An existing `.md`
  classifies as `file`, so `letloop check src/foo.md` currently sets
  `library.scm` to the markdown and fails later. This needs handling.
- **The three-file convention already exists.** `src/letloop/aql/morton.scm`
  is a bare `(library ...)` header whose body is two includes:

  ```scheme
  (include "letloop/aql/morton.body.scm")
  (include "letloop/aql/morton.check.scm")
  ```

  Both `src/letloop/aql/` and `src/letloop/tea/` follow it throughout.
  Markdown maps onto this split exactly, so the tangler emits the shape
  the repo already uses rather than inventing one.
- **Include paths are root-relative, not sibling-relative** —
  `"letloop/aql/morton.body.scm"`, resolved against `(source-directories)`,
  which the makefile sets to `./src/` (`makefile:31`, `:210`, `:222`) and
  `letloop-check`/`-compile`/`-exec` set from their directory arguments
  (`base.scm:804`, `:1203`, `:1285`, `:1475`). The tangler must know the
  discovery root to emit a correct include, and cannot just use a basename.

## The format

````markdown
# Morton codes

Prose. Any amount of it, any markdown constructs — headings, lists,
tables, links. None of it is parsed beyond finding fences.

```scheme imports
(chezscheme)
(letloop r999)
(letloop byter)
```

```scheme
(define morton-encode
  (lambda (x y) ...))
```

```scheme private
(define %interleave
  (lambda (n) ...))
```

```scheme check
(define ~check-morton-roundtrip
  (lambda () ...))
```
````

**Info strings.** The fence language is `scheme`; the word after it is
the role.

| Fence | Goes to | Exported |
| --- | --- | --- |
| ` ```scheme ` | `NAME.body.scm` | yes — every top-level binding it defines |
| ` ```scheme private ` | `NAME.body.scm` | no |
| ` ```scheme check ` | `NAME.check.scm` | yes, `~check-*` and `~benchmark-*` only |
| ` ```scheme imports ` | the `(import ...)` clause | n/a |
| ` ```scheme library (letloop foo) ` | overrides the derived name | n/a |
| anything else — ` ```text `, ` ```console `, bare ` ``` ` | nothing | n/a |

Unknown info strings on a `scheme` fence are an **error**, not a silent
skip: ` ```scheme privte ` must not quietly export a private binding.

**Export inference.** A public block exports every top-level
`define`, `define-syntax`, `define-record-type`, and `define-record-type*`
name it introduces. `define-record-type*` is letloop's own
(`src/letloop/r999.scm`) and expands to a set of names; the tangler
scans the *form*, so it exports the constructor/predicate/accessor names
the form declares, not a guess. Nested defines inside a `lambda` body are
not top-level and are not exported.

**Check blocks** contribute only `~check-*` / `~benchmark-*` names to the
export list. A helper defined in a check block stays internal — this is
what makes the generated header match the hand-written ones, which export
`~check-morton-000` but not their local fixtures.

**Library name** derives from the file path relative to the discovery
root: `src/letloop/aql/morton.md` under root `./src/` → `(letloop aql morton)`.
This mirrors what `letloop-discover-libraries` already assumes. The
`library` info string overrides it for the odd case.

## Tangling contract

`src/letloop/aql/morton.md` with root `./src/` produces three files, all
siblings of the source:

```
src/letloop/aql/morton.scm         (library (letloop aql morton) (export ...) (import ...) (begin (include ...) (include ...)))
src/letloop/aql/morton.body.scm    public + private blocks, in document order
src/letloop/aql/morton.check.scm   check blocks, in document order
```

`morton.check.scm` and its `include` are omitted entirely when the
document has no check blocks.

**Line numbers must be preserved.** `morton.body.scm` pads with blank
lines so that a form on line 214 of the markdown sits on line 214 of the
body. Chez's error positions and the coverage profile then point straight
at the markdown with no source-map machinery anywhere. `morton.scm` is
generated content and cannot preserve anything, which is fine — it holds
no user code.

This padding is the single detail that decides whether the format is
pleasant to debug or infuriating. It is nearly free. Do not skip it.

**Generated `.scm` is committed to git, not ignored.** Two reasons:

- `.gitignore` cannot express "generated `.scm`" — `*.scm` is the tracked
  source of this entire repo, and renaming generated files to something
  matchable (`foo.md.scm`) breaks the path → library-name derivation.
- **Bootstrap.** `(letloop literacy)` ships inside letloop. If letloop's
  own libraries were markdown, building letloop would require a letloop.
  Committed output keeps `make letloop` working from a clean checkout
  with nothing but Chez.

Generated files carry a header comment marking them as such and naming
the `.md` they came from.

**Staleness.** Tangle when the `.md` mtime is newer than any of its
outputs. On rewrite, delete the sibling `.so` and `.wpo` for every file
touched — a deleted code block otherwise leaves a stale `.so` still
exporting the removed binding, which is a known failure mode in this repo
and is invisible until something imports the ghost.

## Implementation shape

**`src/letloop/literacy.scm`** — the library, with
`src/letloop/literacy.body.scm` and `src/letloop/literacy.check.scm`
following the local convention. Hand-written, not self-hosted, for the
bootstrap reason above.

```scheme
(literacy-parse port)          ; -> list of block records, in document order
(literacy-tangle md root)      ; -> list of paths written (empty if up to date)
(literacy-tangle-directory dir) ; -> walks for .md, tangles each, returns paths
```

The parser is a **line-oriented fence scanner**, not a markdown parser.
It tracks one piece of state — inside a fence or not — and the opening
fence's marker length and indentation, so that a ` ```` ` fence can quote
a ` ``` ` block in prose. Do not reach for `(letloop html)` or anything
that parses markdown structure; nothing outside the fences is ever
inspected.

Export scanning walks the top-level forms of each public block with plain
list operations. `(letloop match)` is available and appropriate here —
`literacy` is a normal library and, unlike `(letloop base)`, is under no
import restriction.

**Hooks into `base.scm`:**

- A `literacy-tangle-directory` pass at the top of `letloop-check`,
  `letloop-compile`, and `letloop-exec`, over the directory arguments,
  before `source-directories` / `library-directories` are set and before
  any discovery walk.
- `guess` gains a `.md` case, so `letloop check src/foo.md` tangles and
  then substitutes the generated `.scm`.
- A `letloop tangle [DIRECTORY ...] [FILE.md ...]` subcommand in
  `letloop-main`'s `case`, plus a line in `src/letloop-usage.md`.

Resolve `literacy` from `base.scm` the way `cli-read` and `letloop-root`
are resolved — through `lazy` / `letloop-library-path!`, at first use.
`(letloop base)` imports nothing from letloop, deliberately: a direct
import would fold `(letloop literacy)` into the amalgamated letloop
program and make it invisible to user programs, and would add its load
cost to every startup. CLAUDE.md documents both consequences.

## Testing

- `literacy.check.scm`: fence scanning (nested fences, indented fences,
  unterminated fence, CRLF, a fence inside a list item), role dispatch,
  unknown-role rejection, export inference over each `define` form
  including `define-record-type*`, path → library-name derivation, and
  line-number preservation asserted as an exact equality on the emitted
  body.
- Round-trip one real library end to end: convert
  `src/letloop/aql/morton.{scm,body.scm,check.scm}` to `morton.md`, tangle,
  and assert the generated body is byte-identical to the file it replaced.
  That is the proof the format is expressive enough for code that already
  exists, rather than for code written to fit the format.
- `make check` afterwards, reporting the pass count.

## Out of scope

- Untangling, or any markdown-from-Scheme direction.
- Documentation rendering — extracting the prose to HTML is a separate
  concern and must not be smuggled in here.
- Markdown as a `library-extensions` entry, for the reason at the top.
- Converting any existing letloop library to markdown. The round-trip
  test above generates `morton.md` as a *fixture*; `morton.scm` and its
  fragments stay the tracked source.
