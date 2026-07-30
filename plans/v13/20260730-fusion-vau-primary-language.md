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
| **Möbius / bb** | `/mnt/src/scheme/mobius` (`hello-weaver`), `/mnt/src/scheme/bb.scm` | the surface, the predicate story, the store |
| **letloop** | this repo, branch `dev-feature-literacy` | the host, the toolchain, the shipping vehicle |

Sizes, verified 2026-07-30:

- seed3 — `seed/src/src/seed3/seed3.scm`, 2 631 lines; already an R6RS
  `(seed3)` library (`seed/src/seed3.scm`) whose body is a single `include`.
  81 ground bindings at `seed3.scm:2449`; the compiler knows four special forms.
- SINK — 5 403 lines across `subfiles/*.scm` + `sink.scm`; ~146 primitives;
  `subfiles/library.snk` is **718 lines and 128 `$define!`s** of R-1RK's derived
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

This reverses R⁰RM's deliberate exclusion of `vau` (named as a design decision in
`mobius/manual.md:206`, and sought after in open question 13 at `:2532`, which
hunts for metaprogramming *"without reintroducing `vau`"*).

The reason is asymmetry of what survives layering:

- `gamma` **can** be derived over `vau` + `match`. seed's own README already
  frames catamorphic `match` inside `vau` as the payoff. Nothing is lost at the
  surface.
- Content addressing **can** be a library over the compiled form. De Bruijn
  normalisation and SHA-256 apply to any tree.
- R-1RK **can** be a library target rather than a core.
- **Compilation cannot be a layer.** If the matcher is primitive, the partial
  evaluator must analyse a pattern matcher rather than an operative — strictly
  harder. seed's one falsifiable claim, native parity with `syntax-case`, dies
  if `vau` is not the foundation.

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

Fix this before anything else in this document.

### 1.2 Port seed3 into letloop as `(letloop seed)`

seed3 is already an R6RS library with an `include`d body, so it drops into this
repo's three-file convention (`NAME.scm` header + `NAME.body.scm` +
`NAME.check.scm`) nearly unchanged. Its 152 ported unit tests become
`~check-seed-*` procedures discovered by `letloop check`.

`(letloop seed)` must be resolved from `base.scm` the way `cli-read` and
`letloop-root` are — lazily, via `lazy` / `letloop-library-path!`. A direct
import folds it into the amalgamated letloop program and makes it invisible to
user programs, and adds its load cost to every startup. See CLAUDE.md.

### 1.3 Run `library.snk` as the conformance target

Do not write a feature checklist. Take
`kernel-sink/subfiles/library.snk` — 718 lines, 128 `$define!`s of R-1RK's
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

### 1.4 Encapsulations should compile to nothing

`kernel-sink/subfiles/encapsulation.scm` implements encapsulations as
closure-based message dispatch with a per-type counter:

```scheme
(lambda (message)
  (case message
    ((type)    'encapsulation)
    ((counter) counter)
    ((value)   value)))
```

Every input is static: the message is a literal symbol at each call site, the
counter is a compile-time constant per `make-encapsulation-type` call. So the
`case` folds, the counter comparison in `this-type?` folds wherever both types
are known, and what survives is a one-slot box that then unboxes.

This is the cheapest early demonstration that the partial evaluator is strong
enough to make R-1RK's *ergonomics* free. Assert it on the emitted Chez, not on
a benchmark.

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
programmer's hint. `assume` already exists as primitive #40 in
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
| capsule | opacity (Annex C) |
| environment | **immutability** (decision 3) |

Two barriers, one result. Neither source document states the pairing, because
neither language has both constructs. Environments are also the alist that
matters most in practice, so this is where the alist → struct/hashtable
inference actually earns its keep.

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

Two couplings to respect:

- **Overflow.** Dropping the numeric tower needs an answer — trap, wrap, or
  promote — and that is Möbius open question 4 (`manual.md:2514`, the error
  model). *Promote-on-overflow* is the interesting one: start narrow, observe the
  overflow, re-specialise wider. That is a polymorphic inline cache under another
  name, and it is the legitimate form of "fix it at runtime."
- **GC.** Tags also tell the collector what is a pointer. Untagged integers
  inside heap objects need a static layout map — which Annex C's fixed-offset
  structs already supply. It composes, but representation choice and GC map
  become a single decision rather than two.

## Part 5 — The foundation set and the hash namespace

Reducing below Kernel's ~146 is ordinary derivation work. Reducing below
Möbius's 43 runs into the freeze: primitive indices are baked into stored hashes,
and `bb/CLAUDE.md` permits only appending.

So a reduced foundation set is **a new foundation set in a new hash namespace**,
not an edit to the existing one. That is the shape of Möbius open question 15
(`manual.md:2542`): parameterise the hash, let the store record what was used.
Removing `gamma` from the foundations (decision 1) is the first entry, which
makes this question live immediately rather than eventually.

The design question open question 15 already flags stays open here: two stores
with different foundation sets produce different hashes for the same logic. The
plan does not close it.

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

**E1 — Derived-versus-primitive cost.** Take `library.snk`, derive it over a
minimal core, compile it, and benchmark against the version calling Chez
primitives directly.

*This is the central bet of the whole programme.* seed is fast because Chez's
thousands of native primitives are one call away; cut to a small core and the
partial evaluator has to claw back by inference what Chez gets for free. If BTA
claws it back, everything downstream is viable. If it does not, this is where
surface reduction stops — learned for the price of a week, before a year is built
on the assumption.

**E2 — Encapsulations compile to nothing.** §1.4. Assert on the emitted Chez that
the `case` folded, the counter comparison folded, and the box is gone.

**E3 — Environment representation selection.** Take an environment-as-alist out
of `library.snk`. Assert that field access is constant-offset and the alist is
never allocated. Benchmark against a hand-written Chez `define-record-type`.
Parity is the claim; a gap locates the missing inference.

**E4 — Monomorphic zero-tag.** A kernel of small-integer arithmetic, proven
monomorphic. Assert untagged 64-bit values in registers, no shift/untag/retag in
the emitted code, and measure against Chez's 61-bit fixnum path.

## Staging

Ordered so that every stage leaves something that runs and is in the benchmark
table. The time constants differ by more than an order of magnitude, and running
these concurrently is the single most likely way for the programme to produce
nothing.

| stage | content | order of magnitude |
| --- | --- | --- |
| 0 | first-class dispatch fix (§1.1) | days |
| 1 | `(letloop seed)` ported, checks discovered (§1.2) | weeks |
| 2 | literacy seam shared with seed sources (§decision 4) | weeks |
| 3 | E1, E2 — the bet and the cheap demo | weeks |
| 4 | `library.snk` conformance, idiom worklist (§1.3) | months |
| 5 | `gamma` as library form (Part 2) | months |
| 6 | BTA × predicate lattice (Part 3), E3 | months |
| 7 | representation regions, tagging (Part 4), E4 | quarters |
| 8 | foundation set / hash namespace (Part 5) | quarters |
| 9 | runtime feedback → re-specialisation, then the verified LLM loop (Part 6) | open-ended |

Stage 3 gates 4 onward. Stage 6 gates 7.

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
- **Whether E1 succeeds.** The entire staging from 4 onward is conditional on it.
