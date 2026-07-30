# Task: the fused language — `vau` as foundation, Möbius at the surface

Make letloop's primary language the fusion of three existing bodies of work:
Kernel (Shutt, R-1RK, SINK), seed (the compiled `vau` with an immutable dynamic
environment), and Möbius (R⁰RM / bb.scm — `gamma`, predicates, content
addressing).

This is not three languages merged. It is one language with a decided
foundation, and two of the three sources contribute layers rather than cores.

## Where the sources live

| | path | what it contributes |
| --- | --- | --- |
| **seed** | `/mnt/src/scheme/seed` (branch `hello-seeder`) | the spine: `vau` that compiles |
| **SINK / R-1RK** | `/mnt/src/scheme/kernel-sink` (branch `xp`) | the conformance target and the derived library |
| **Möbius / bb** | `/mnt/src/scheme/mobius` (`hello-weaver`), `/mnt/src/scheme/bb.scm-upstream` | the surface, the predicate story, the store |
| **letloop** | this repo, branch `dev-feature-literacy` | the host, the toolchain, the shipping vehicle |

Sizes, verified 2026-07-30:

- seed3 — `seed/src/src/seed3/seed3.scm`, 2 631 lines; already an R6RS
  `(seed3)` library (`seed/src/seed3.scm`), though its header also imports a
  local `(match)` (a second SRFI-241 copy that the port must reconcile with
  `(letloop match)`). 81 ground bindings at `seed3.scm:2449`; the parser
  recognises `if`, `begin`, `let`, `let*`, `letrec`, `lambda`, `vau`, `define`,
  `quote` (`seed3.scm:151-221`).
- SINK — 5 403 lines across `subfiles/*.scm` + `sink.scm`; ~146 primitives;
  `subfiles/library.snk` is **718 lines and 131 `$define!`s** of R-1RK's derived
  layer, written in Kernel itself.
- bb — 12 264 lines under `src/bb/`; 43 primitives at
  `src/bb/evaluator.scm:884-896`, indices 0–42.
- Chez — `local/src/chezscheme/s/cmacros.ss`: `typemod 8` (`:470`),
  `primary-type-bits` 3 (`:471`), eight primary tags (`:821-828`),
  `fixnum-bits` (`:918`). Measured on this machine: `(fixnum-width)` = 61,
  `most-positive-fixnum` = 1152921504606846975.

## Decisions taken

These are settled, and the rest of the document follows from them.

**1. `vau` is the foundation. `gamma` is a library form.**

This reverses R⁰RM's deliberate exclusion of `vau` (motivated by the economy
argument, and confirmed as a standing decision by open question 13 at
`mobius/manual.md:2532`, which hunts for metaprogramming *"without
reintroducing `vau`"*).

The reason is an asymmetry of derivability — which directions are demonstrated
and which are open:

- `gamma` from `vau` + `match` is **demonstrated**: seed's own README frames
  catamorphic `match` inside `vau` as the payoff, and seed compiles it. The
  reverse direction — recovering `vau`'s power without `vau` — is exactly what
  open question 13 is still hoping "trees all the way down" turns out to
  provide. One direction is running code; the other is an open question.
- Content addressing **can** be a library over the compiled form. De Bruijn
  normalisation and SHA-256 apply to any tree.
- R-1RK **can** be a library target rather than a core.
- Compilation is the layer that must be designed in from the start: seed's
  falsifiable claim — native parity with `syntax-case` — is a claim about
  compiling `vau`, and it is the one result in the three sources that already
  exists and must not be forfeited by the fusion.

Immediate dividend: `gamma` stops being foundation #0. The surface-reduction
programme begins by removing the thing Möbius currently calls its sole
mechanism, while keeping it verbatim for the programmer.

**2. Chez is the prototype, not the target.** Its role in this construction is
*semantics oracle* and *performance floor*. The benchmark table remains
meaningful across a backend change, because parity-with-Chez is the claim being
made.

**3. Immutable dynamic environments, permanently.** R-1RK's `$define!` mutates
the caller's environment; seed forbids it, and that prohibition is the entire
reason seed compiles. The fused language is therefore **R-1RK minus mutable
dynamic environments, plus a static replacement for every idiom that used one.**
Enumerating those idioms and answering them individually is the bulk of Part 1.

Caveat, and a gating work item (§1.2): seed3 does not currently *enforce* this.
The interpreter's ground environment ships a `set!` operative that does
`set-cdr!` on whatever environment alist is in scope (`seed3.scm:2531-2538`),
including a received dynamic environment; and the codegen's `define`
sub-expression fallback emits `set-car!`/`set-cdr!` on the target environment
(`seed3.scm:2219-2223`). In compiled code the caller's bindings are Chez lambda
parameters and the received alist is a fresh materialisation
(`build-operative-environment-extension`, `seed3.scm:834`), so mutation hits a
copy — immutability holds *by accident of materialisation*, while interpreted
code mutates for real. Compiled and interpreted code therefore disagree today,
which is exactly the kind of divergence the conformance oracle of §1.4 exists to
catch.

**4. The language is literacy-compatible from the start.** See
`plans/v12/20260730-literacy-markdown-source-format.md`. Seed sources are
markdown with fenced blocks, through the same tangling seam. bb has already
built this — `bb/src/bb/transcript.scm`, 654 lines, runs fenced blocks in
`src/tests/*.md` as tests. Read it before writing `(letloop literacy)`; the
tangler and the transcript runner want to be one mechanism.

## Part 1 — The spine: `vau` that compiles

### 1.1 Fix the first-class dispatch hole

Operatives bound as `lambda` parameters do not emit operative/applicative
dispatch at their call sites (reported by datarama, acknowledged in seed's
README). In an experiment this is a known issue. In a language whose premise is
first-class combiners it is unsound, and it is *also* load-bearing for Part 4:
unknown operative call sites are exactly the escape that forces a fallback
representation everywhere.

Fix this before anything else in this document. It is a calling-convention
change at every unknown call site — it interacts with seed2's
`(values news out)` convention — not a local patch, and the staging table costs
it accordingly.

### 1.2 Enforce environment immutability

Decision 3 is currently a convention, not an invariant (see the caveat there).
This section makes it one. The invariant that survives contact with the code is
not "environments are immutable" — it is **ownership**: *code may only mutate an
environment whose bindings the compiler can see it owns.*

**Inventory.** Every mutation site in seed3, verified 2026-07-30. Two distinct
operations hide under "mutation" and need separate verdicts:

- **Rebinding** — changing an existing binding's value. Exactly **one** site:
  the interpreter's ground `set!` does `(set-cdr! cell v)` on whatever `assq`
  finds (`seed3.scm:2537`), with no check of where the binding came from.
- **Extension** — adding a binding. **Seven** sites, all using the same
  *head-swap* idiom, which prepends by mutating the head cell so every holder
  of the reference observes the new binding:

  ```scheme
  (set-cdr! target (cons (car target) (cdr target)))   ; push old head down
  (set-car! target (cons name v))                       ; new binding at head
  ```

  Codegen: the `%news` merge fallback when defines have dynamic names
  (`:1766-1767`), the 3-arg `define` sub-expression fallback (`:2222-2223`).
  Interpreter: 3-arg define in `seed-evaluate-statement` (`:2291-2292`), local
  defines (`:2399-2400`, `:2406-2407`), 3- and 4-arg defines into a target
  environment (`:2414-2415`, `:2424-2425`).
- **Sanctioned** — `(set! env (cons ...))` at `:2217-2218` rebinds the *local
  variable* `env`: extension of the operative's own view plus `%news`
  accumulation, no shared structure touched. This is the seed2 convention and
  the model everything else converges to.

**The ownership taxonomy.** Three classes of environment, three verdicts:

| environment | lookup | extension | rebinding |
| --- | --- | --- | --- |
| own local frame | yes | yes — sequential `define` / `letrec`, compiles to `let`/`letrec` | yes — `set!` on an owned binding, compiles to Chez `set!` |
| received dynamic | yes — `vau`'s whole point | only via `(values news out)`: statically-known names, landing as the caller's own bindings | **error** |
| first-class created (`make-environment`, the `get-module` pattern) | yes | before escape: yes, it is `letrec` in disguise; after escape: not in v13 | same rule |

**The conformance target already obeys this — measured, not hoped.** Auditing
`library.snk`: 86 of its `$define!`s are top-level (sequential program
structure), 42 are nested in an operative's own local frame, and all three
`$set!` uses target environments the mutating code itself created — `local`
bound to `(get-current-environment)` twice in `guard-dynamic-extent`, and
`get-module`'s freshly made `env` (`library.snk:713-718`). The single
`$provide!` exports a statically-known list, which is exactly the news
convention. **Nothing in R-1RK's derived library rebinds through a received
dynamic environment.** The subtraction in decision 3 costs the conformance
target nothing on this axis; `$set!` itself survives as sugar, because the
ownership check — not a syntactic ban — is what decides each use.

**Enforcement.**

- *Interpreter `set!`:* record the identity of the environment's head cell at
  operative entry. A binding found by `assq` is owned iff it sits strictly above
  that entry mark in the alist spine; otherwise it is the caller's, and `set!`
  errors. Cost is O(own frame) and only on the residual path — a binding BTA
  resolved statically compiles to a Chez `set!` of a local and never walks.
- *Extension sites:* replace head-swap with local-variable rebinding
  (`(set! env (cons pair env))`) wherever the target is the flowing `env` —
  same visibility for every subsequent lookup through `env`, no shared cell
  touched. Where the target is a received or escaped first-class environment,
  **error**, in both the interpreter and the emitted code — the codegen fallback
  at `:2222-2223` and the `%news` merge at `:1766-1767` are the two to repair.
- *Checks:* a `~check` asserting that `set!` through a received dynamic
  environment errors identically in compiled and interpreted code — today they
  disagree (real mutation interpreted, shadow mutation of the materialised copy
  compiled), and that divergence is precisely what §1.4's oracle exists to
  catch. Plus a check that the news convention still passes, and the
  `library.snk` suite.

**What BTA may then assume.** Between operative entry and exit, caller bindings
are frozen — no rebinding, no insertion into the caller's frame — so
substitution and inlining are sound; and every extension is statically visible
(news lists or own-frame defines), so the alist→struct flattening of E3 is sound
at monomorphic sites. This gates Part 4: nothing there may be built while the
invariant is accidental.

### 1.3 Port seed3 into letloop as `(letloop seed)`

seed3 is already an R6RS library with an `include`d body, so it drops into this
repo's three-file convention (`NAME.scm` header + `NAME.body.scm` +
`NAME.check.scm`) nearly unchanged. Its 152 ported unit tests become
`~check-seed-*` procedures discovered by `letloop check`.

`(letloop seed)` must be resolved from `base.scm` the way `cli-read` and
`letloop-root` are — lazily, via `lazy` / `letloop-library-path!`. A direct
import folds it into the amalgamated letloop program and makes it invisible to
user programs, and adds its load cost to every startup. See CLAUDE.md.

### 1.4 Run `library.snk` as the conformance target

Do not write a feature checklist. Take
`kernel-sink/subfiles/library.snk` — 718 lines, 131 `$define!`s of R-1RK's
derived layer — compile it, and run SINK's `test/*.krn` against the result.

**The forms that fail are the worklist.** This discovers the mutable-environment
idioms rather than guessing them. Known candidates: `$let-redirect`,
`$remote-eval`, `make-environment` + `eval` into it, `$binds?`, `$provide!`, and
the SINK REPL itself. Each gets a static replacement or an explicit *not
supported*.

seed2's `(values news out)` convention (`seed/src/src/seed2/README.md`) is the
existing answer for the `$provide!` / `define-record-type` shape: exported names
land as lambda parameters, immutably, with no alist mutation. It generalises to
any case where the export list is statically known.

### 1.5 Encapsulations should compile to nothing

`kernel-sink/subfiles/encapsulation.scm` implements encapsulations as
closure-based message dispatch with a per-type counter:

```scheme
(lambda (message)
  (case message
    ((type)    'encapsulation)
    ((name)    name)        ; name = (list #t), fresh per instance
    ((counter) counter)
    ((value)   value)))
```

The message is a literal symbol at each call site and the counter is a constant
per `make-encapsulation-type` call, so the `case` folds, the counter comparison
in `this-type?` folds wherever both types are known, and what survives is a
one-slot box that then unboxes.

Two honest limits on "to nothing":

- **`eq?`-identity.** Each instance allocates a fresh `(list #t)` precisely so
  that instances are `eq?` only to themselves. Full elision is therefore
  per-site, licensed by an `eq?`-escape analysis: the box disappears only where
  no `eq?` on the capsule can observe it.
- **The counter is shared mutable state** (`set!` inside
  `make-encapsulation-type`). "Compile-time constant per call" holds only where
  call sites are statically enumerable; a first-class use of
  `make-encapsulation-type` falls back to the runtime counter.

Still the cheapest early demonstration that the partial evaluator makes R-1RK's
*ergonomics* free at monomorphic sites. Assert it on the emitted Chez, not on a
benchmark.

## Part 2 — The surface: `gamma`, predicates, literacy

`gamma` is a library form over `vau` + `match`. It must be
indistinguishable, at the surface, from bb's primitive: `,x` binds, `,(x)` binds
catamorphically, `,_` wildcards, `(? pred ,x)` guards. bb's
`src/bb/reader.scm` (619 lines) and `src/bb/pattern.scm` (276 lines) are the
reference for the surface syntax; `bb/src/bb/base-library.scm` shows what
`gamma` must be able to express (`list`, `not`, `equal?`, capsule operations).

Ellipsis (`manual.md:2557`, Annex A) is explicitly *not* in scope for the first
pass, but the `gamma` implementation should not foreclose it.

## Part 3 — One analysis, not two

Möbius open question 1 (`manual.md:2508`) specifies predicate inference:
predicates propagate from foundation signatures (`car` ⇒ `pair?`, `+` ⇒
`integer?`/`float?`) through `gamma` clause structure, with `assume` as the
programmer's hint. `assume` already exists as a primitive (index 39 in bb's
0-based vector) in
`bb/src/bb/evaluator.scm:893`. The interaction between capsule-level inference
and tree-level predicates is listed as open.

seed3 already runs a binding-time analysis. Its lattice is at
`seed3.scm:611-613` — `static-syntax`, `static-eval`, `dynamic`. Specialisation
already eliminates most environment lookups; the comment at `seed3.scm:887`
records that only the survivors get a residual `environment-lookup`, and that
residual (`seed3.scm:2233`) is a linear alist scan.

**These are one pass.** Run binding-time and predicate inference as separate
analyses and the cases Annex C names become unreachable: *"a list of `uint8?`
values with known length → contiguous bytes"* requires **dynamic value, static
shape, static length simultaneously**. That is a product lattice
(binding-time × predicate × extent), not two passes composed.

This is the concrete contribution the fusion makes to open question 1, and it is
comparatively cheap because the pass already exists and is tested.

## Part 4 — Representation

Annex C (`manual.md:2632`) already specifies the target: byte vectors for
`uint8?` lists of known length, flat arrays for homogeneous known-length lists,
structs with fixed offsets for fixed-position pairs with known types, and hash
tables for association lists consistently accessed by key. Annex B (`:2618`)
specifies the optimisations predicates unlock: representation narrowing, tag-bit
recovery, dead clause elimination, check elimination, specialisation.

Three things the fusion has to add, because they arise only when `vau` and
capsules are in the same language.

### 4.1 Two barriers, not one

Annex C rests its soundness on **capsule opacity** — no external code depends on
internal layout, so the compiler may change it freely.

Kernel's *environments are not capsules*. `vau` hands the caller's environment
over as a first-class value; that is the whole point of `vau`. So the guarantee
splits:

| construct | what licenses representation freedom |
| --- | --- |
| capsule | opacity (Annex C) — unconditional: no external interface exists |
| environment | **immutability** (decision 3) — conditional: see below |

The pairing is not symmetric, and saying so precisely matters. Opacity licenses
change because no interface exists to depend on the layout. Immutability freezes
*contents*, but the environment's interface — symbol-keyed lookup, `$binds?`,
`eval` into it — remains first-class and inspectable; that is `vau`'s whole
point. So environment representation freedom requires immutability **plus** one
of: every lookup through the environment resolved statically at the site, or a
materialise-to-alist coercion on escape. seed3's residual `environment-lookup`
(`seed3.scm:2232`, a linear alist scan) is exactly that escape hatch, already in
place. One barrier and one conditional analysis — but environments are still the
alist that matters most in practice, so this is where the alist → struct
inference earns its keep.

### 4.2 Representation belongs to an inlining site, not to a combiner

The content store is an unusual boundary: a stored combiner is callable by any
caller, in any store, forever. Its calling convention cannot depend on a
whole-program analysis that a different program will not repeat.

Two ways out, and only one is admissible:

- **Fold representation assumptions into the hash.** This breaks *same logic,
  same hash*, which is the multilingual identity property and the reason the
  project exists. Not admissible.
- **Store-boundary calls use the uniform tagged form; specialisation happens at
  inlining time.** Admissible, and it means representation is a property of a
  *site*, not of a combiner.

State this explicitly in the design, because the first option is the tempting
one and its cost is not local.

**Hashing a `vau` operative.** The store's identity story rests on closed,
symbol-free de Bruijn trees, and an operative receives its operands as a tree of
symbols — an apparent conflict. It dissolves under one constraint: **the fused
foundation set contains neither `symbol->string` nor `string->symbol`.**
Symbols are then opaque tokens — `eq?`-comparable, usable as environment keys,
nothing else. No program can fabricate a name (`(string->symbol (string-append
... ".43"))` is inexpressible), so BTA inside a `vau` cannot be fooled by
manufactured bindings, bound names normalise positionally as before, and a
literal symbol matched in a pattern is *logic* and hashes as such — the same
stance Möbius already takes for string tags. The captured static environment
normalises to content references (bb's `mobius-constant-ref` already does
this); the received dynamic environment is a runtime value and is never hashed.

Verified: seed3's ground environment exposes neither procedure, and both are
absent from bb's 43 primitives. The one hole is **`xeno`** (bb primitive #2),
which reaches any Chez procedure by string name — `(xeno "string->symbol" ...)`
would reopen it. The guarantee therefore requires `xeno` to be excluded or
allowlisted in the fused foundation set.

More generally: the uniform-representation boundary does not disappear, it moves.
What you get is representation *regions* with coercions at their edges —
Leroy-style unboxing analysis, well understood, whose known failure mode is
regions small enough that coercion cost dominates the win. Capsules give
naturally large regions, which is presumably why Annex C nominated them as where
representation stabilises.

### 4.3 Tagging

Chez must distinguish eight primary types dynamically because a Scheme with
`eval`, separate compilation and first-class everything **requires** a uniform
representation at every boundary. That is a requirement, not an oversight — and
it is precisely the requirement the fused language does not carry, given
predicate inference plus the two barriers of §4.1.

| disjoint types reaching a site | tag bits | payload |
| --- | --- | --- |
| 8 (Chez, always) | 3 | 61-bit fixnum |
| 2 | 1 | 63-bit |
| **1 — proven monomorphic** | **0** | **full 64-bit, untagged, in registers** |

The third row is the prize, and it is qualitatively different from wider
fixnums: no shift/untag/retag around arithmetic, values resident in registers in
machine form, and Annex C's byte vectors and arrays as genuinely flat memory
rather than arrays of tagged cells. The constant factors there dominate the two
extra bits.

**The scarce resource is per-site, not global.** It is not the number of
disjoint types in the program but the maximum number that can reach one site
after inference. A program with 500 capsule types is still zero-tag everywhere
if every site is monomorphic. As a global budget "few disjoint types" would be a
straitjacket; as a per-site property it is exactly what Part 3 computes.

**The Chez backend cannot express the third row.** Compiled output is Chez
Scheme source, and Chez cannot hold untagged 64-bit integers in registers from
Scheme source — 61-bit fixnums or heap bignums are what there is, and unboxing
in Chez 10 is essentially flonum-local. Zero-tag emission therefore requires a
native backend, which contradicts decision 2 as long as decision 2 stands. The
analysis in this section (what monomorphism proves, per-site scarcity) is
backend-independent and worth doing; the *emission* is deferred until the
backend question is reopened deliberately. What is reachable through Chez today:
fixnum-proof arithmetic (eliminating overflow checks the predicates discharge),
flonum unboxing, and Annex C's flat representations via bytevectors and
fxvectors.

Two couplings to respect:

- **Overflow.** Dropping the numeric tower needs an answer — trap, wrap, or
  promote — and that is Möbius open question 4 (`manual.md:2514`, the error
  model). *Promote-on-overflow* is the interesting one — start narrow, observe,
  re-specialise wider — but it is not cheap: unlike an inline cache, which
  dispatches at call boundaries, overflow fires mid-arithmetic with live
  untagged state, so it needs deoptimisation metadata to reconstruct the tagged
  world at that point. A quarters-scale subsystem in its own right, priced as
  such in the staging table.
- **GC.** Tags also tell the collector what is a pointer. Untagged integers
  inside heap objects need a static layout map — which Annex C's fixed-offset
  structs supply — and untagged values live across GC points need stack and
  register maps, which is native-backend territory again. Representation choice
  and GC map are a single decision rather than two.

## Part 5 — The foundation set and the hash namespace

Reducing below Kernel's ~146 is ordinary derivation work. Reducing below
Möbius's 43 runs into the freeze: primitive indices are baked into stored hashes,
and `bb/CLAUDE.md` permits only appending.

So a reduced foundation set is **a new foundation set in a new hash namespace**,
not an edit to the existing one. That follows the pattern of Möbius open
question 15 (`manual.md:2542`) — parameterise the choice, let the store record
what was used — though open question 15 itself covers only the anchor chain, the
hash algorithm and the proof format; extending it to foundation sets is **this
plan's own move**, not something the source flags. Removing `gamma` from the
foundations (decision 1) is the first entry, which makes the question live
immediately rather than eventually.

Two constraints on the fused set are already fixed by this plan: no
`symbol->string` / `string->symbol` (§4.2 — the hashing story depends on it),
and `xeno` excluded or allowlisted.

The open difficulty stays open here: two stores with different foundation sets
produce different hashes for the same logic. The plan does not close it.

## Part 6 — Verification, and where LLM generation is admissible

There is a coherent version of LLM-assisted optimisation and a catastrophic one,
and the distance between them is verification.

- **Catastrophic:** a model proposes optimised code and the system runs it.
- **Coherent:** the runtime profile is a *specification*; a model proposes an
  alternative combiner; it ships only after passing the check suite.

The coherent version is available only because bb already built the
infrastructure: content-addressed combiners, check suites as the specification,
Z3 for symbolic properties (`bb/src/bb/z3.scm`, 1 352 lines), refactor as hash
substitution. An LLM-proposed optimisation is just another combiner claiming the
same behavioural identity — verifiable, attributable, revertible.

This is also the second job for Z3: open question 14 (`manual.md:2534`) positions
`assume` as Agda's `postulate`, honest about where the proof ends. Constraints
that drive representation choice (Part 4) are memory-safety-relevant, so each one
needs either a Z3 discharge or a runtime guard. An unverified `assume` that
selects a representation is a wild access waiting to happen.

State plainly in the design: **no representation decision may rest on an
unverified, unguarded `assume`.**

## The experiments, in order

Each is cheap, falsifiable, and decides whether the work after it is worth
doing. None should be skipped for being obvious.

**E1 — Derived-versus-primitive cost.** Declare a subset of `library.snk` that
avoids the mutable-environment idioms (most of its 131 `$define!`s qualify —
`$sequence`, `list`, `list*`, the combiner utilities), derive it over a minimal
core, compile it, and benchmark against the version calling Chez primitives
directly. The subset must be declared up front, because the *full* file needs
stage 4's idiom replacements — E1 cannot wait for those. Workloads: the four
benchmarks already in seed's table (n-queens, collatz, abacus, abacus2),
rewritten against the derived subset. Success criterion: **within 15% of the
primitive-calling version** on each workload; anything worse is a fail, not a
judgement call.

*This is the central bet of the whole programme.* seed is fast because Chez's
thousands of native primitives are one call away; cut to a small core and the
partial evaluator has to claw back by inference what Chez gets for free. If BTA
claws it back, everything downstream is viable. If it does not, this is where
surface reduction stops — learned cheaply, before a year is built on the
assumption.

**E2 — Encapsulations compile to nothing.** §1.5. Assert on the emitted Chez
that the `case` folded, the counter comparison folded, and — at sites the
`eq?`-escape analysis clears — the box is gone.

**E3 — Environment representation selection.** Take an environment-as-alist out
of `library.snk`. At **monomorphic inlined sites**, assert that field access is
constant-offset and the alist is never allocated; benchmark against a
hand-written Chez `define-record-type`. Parity there is the claim. An
environment escaping to an unknown operative site legitimately falls back to the
materialised alist and does not count against the experiment — that fallback is
the design (§4.1), not a failure of it. Gated on §1.2: the invariant must be
enforced, not accidental, before flattening is sound.

## Staging

Ordered so that every stage leaves something that runs and is in the benchmark
table. The time constants differ by more than an order of magnitude, and running
these concurrently is the single most likely way for the programme to produce
nothing.

| stage | content | order of magnitude |
| --- | --- | --- |
| 0 | first-class dispatch fix (§1.1) — a calling-convention change, not a patch | weeks |
| 1 | immutability enforced (§1.2); `(letloop seed)` ported, checks discovered (§1.3) | weeks |
| 2 | literacy seam shared with seed sources (§decision 4) | weeks |
| 3 | E1 on the declared subset, E2 — the bet and the cheap demo | weeks |
| 4 | `library.snk` conformance, idiom worklist (§1.4); E1 re-run on the full file | months |
| 5 | `gamma` as library form (Part 2) | months |
| 6 | BTA × predicate lattice (Part 3), E3 | months |
| 7 | representation regions (Part 4); tagging analysis, emission deferred with the backend question | quarters |
| 8 | foundation set / hash namespace (Part 5) | quarters |
| 9 | runtime feedback → re-specialisation, then the verified LLM loop (Part 6) | open-ended |

Stage 3 gates 4 onward. Stage 1's invariant (§1.2) gates stage 6's E3. Stage 6
gates 7.

## Out of scope

- Migrating letloop's own libraries to the fused language. The bootstrap argument
  from the literacy plan applies with more force: letloop's own source cannot be
  written in a language whose compiler ships inside letloop unless the generated
  Chez output is committed. *Primary language* means primary for user programs
  first.
- Ellipsis (Annex A).
- Oblivious execution, ZKP, Atlas Stoa — Möbius Part V. Orthogonal to the
  language.
- Replacing letloop's library system. The R6RS `library` form is retained and the
  fused language lives inside it; `library-directories`, `compile-whole-program`,
  the `.wpo` cache and `~check-` discovery all keep working unchanged. A
  Kernel-native module form may be added later as a desugaring, using the same
  seam as literacy.
- Effects, concurrency, the I/O model — Möbius open questions 2, 6, 8.

## What this plan does not close

- **Open question 15's core difficulty.** Two stores with different foundation
  sets hash the same logic differently. Part 5 names the mechanism, not the
  resolution.
- **Open question 4.** The error model is a precondition for §4.3's overflow
  story, and is specified nowhere yet.
- **Open question 1's capsule/tree interaction.** Part 3 unifies binding-time
  with predicate inference; it does not settle how capsule-level inference and
  tree-level predicates interact.
- **The backend.** Decision 2 stands, and §4.3 shows what it forecloses:
  zero-tag emission, untagged values across GC points, promote-on-overflow with
  deoptimisation. Reopening the backend question is a deliberate future act,
  priced at quarters, not a side effect of stage 7.
- **`gamma` surface fidelity across the symbol gap.** Part 2 says
  "indistinguishable at the surface", but Möbius has no quote and no
  symbols-as-values while Kernel is symbol-full; what "indistinguishable"
  covers below the pattern syntax is not yet scoped.
- **Whether E1 succeeds.** The entire staging from 4 onward is conditional on it.
