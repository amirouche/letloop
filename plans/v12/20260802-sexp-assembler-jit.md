# sexp assembler JIT — `(assembly->procedure (sexp->assembly ...))`

2026-08-02

At this time there is only one way to speed up Scheme code with SIMD
or assembly in general: write C, compile a shared object, load it with
`foreign-procedure`. Two production kernels already live on that path:

- **base64 (AVX2)** — `invvv/apps/letloop/b64simd.c`, the
  Mula/Lemire reshuffle kernel. Took city-explorer from 1974 to
  4555 req/s single-core (within ~10% of bun); scalar base64 was 80%
  of per-request CPU.
- **LOUDS rank/select (POPCNT/BMI2)** —
  `atlas-stoa/benchmarks/louds-simd/louds-simd.c`: `ls_select0`
  (directory-guided select0 via `pdep`+`tzcnt`) and `ls_payload_rank`
  (`popcnt`). Point lookups 2.21 → 1.21 µs, range scans 1.41 → 0.94
  µs/key over optimized pure Scheme.

The long-term line of thought is

```scheme
(assembly->procedure (sexp->assembly (dubito (sum proc))))
```

— *sum*: recover a compilable representation of a procedure;
*dubito*: the doubting pass that proves a restricted subset (fixnums,
flonums, bytevector loads/stores, no allocation, no `call/cc`) can be
pinned to machine types and possibly vectorized; then assemble
in-image and wrap the code address as a callable procedure. This plan
is **the bottom half only** (stages 0–3 below): kernels hand-written
as sexp assembly. The top half (`sum`/`dubito`, stages 4–6) belongs
to v13 — see "The second half lives in v13" at the end.

## Design principle — dubito verifies, it does not optimize

Sharpened by discussion, recorded here so the eventual v13 work
inherits it. `dubito` is not a hint system coaxing Chez's compiler —
that would be another level of indirection bolted on, and Chez would
still be bound by its runtime obligations (tagged fixnums, event
checks in loops, GC maps at every point, continuation capture). What
makes the interface not-indirection is that it changes the
**contract**, not the codegen: a kernel promises no allocation, no
calls back into Scheme, no continuation capture, bounded runtime,
arguments are machine words and bytevector spans. That is exactly
what a leaf FFI call already promises — which is why the output can
be raw instructions with no GC maps, tags, or event checks.
`dubito`'s job is to *prove* (or reject) that the source satisfies
the contract; `assert`/`assume` forms are the surface syntax of the
proof. Assumptions too expensive to check per-operation become O(1)
guards at the call boundary, amortized over the O(n) loop — a
boundary ordinary Scheme code does not have. Rejection is a
compile-time error naming the offending expression; the fallback is
the scalar Scheme version (the pattern both existing kernels ship).

Why Chez does not already do this: its x86_64 backend supports
exactly one exotic instruction — POPCNT — and it cost a
`define-instruction` form, an asm op, and a linker-mediated fallback
to `popcount-slow` (`s/x86_64.ss:500`, `:1492-1530`). Each intrinsic
is threaded per-architecture through the nanopass backend with a
portability story; vector support would additionally need register
classes, spilling, and calling conventions times every backend. And
for *ordinary* procedures the obligations above are non-negotiable —
Chez cannot emit this code without breaking its own runtime model.
The subset where it is possible is "C written in Scheme", hence the
status quo: write C.

**Goal:** replace both `.so` files with the same kernels written as
sexp assembly, assembled and mapped in-image — zero C toolchain — at
the same benchmark numbers.

## Decisions (defaults, unconfirmed)

- Home: `north/src/letloop/asm.scm` + `asm.check.scm`.
- Operand order: Intel (dst, src) — reads like the manuals the
  encodings come from.
- x86-64 only. ARM/NEON out of scope.
- Code pages leak (no reclamation); fine until `assembly->procedure`
  is called in a loop.

## Step 1 — executable memory + `assembly->procedure`

FFI `mmap`/`mprotect`/`munmap` from libc (nothing in `cffi.scm`
covers these; its `lazy-foreign-procedure` is the pattern to follow).

`(assembly->procedure code-bv arg-types ret-type)`:
mmap RW → copy bytes → mprotect RX (W^X) → `(foreign-procedure addr
...)` over the address. Chez's `u8*` foreign type passes bytevector
data pointers directly, so kernels keep the same `(u8* unsigned-64
u8*)`-style signatures as the current `.so` imports. No icache
concern on x86-64.

Validate first with ~5 hand-assembled bytes
(`mov rax,rdi; add rax,rsi; ret`) before any assembler exists.

## Step 2a — GPR encoder, first customer: LOUDS

A deliberately tiny x86-64 assembler — prior art:
[Sassy](https://sassy.sourceforge.net/), the portable sexp x86
assembler in Scheme (32-bit only; we borrow the idea, not the code,
and target x86-64 + AVX2). Two-pass (labels then bytes),
REX prefixes, ModRM/SIB memory operands, `jcc`, and exactly the
instructions the LOUDS kernels need: `mov`, `add`, `sub`, `cmp`,
`shr`, `and`, `imul`, `popcnt`, `tzcnt`, `pdep`. Maybe 30
instructions of surface total. Not a general assembler.

**Test strategy is the load-bearing part.** `asm.check.scm` does
differential assembly: for every supported instruction form, emit GNU
`as` syntax, assemble with the system `as`, compare bytes against our
encoder. Encoding bugs die there, not in a segfault.

Then port `ls_select0` / `ls_payload_rank` (and the child-rank
helper) to asm sexps and slot in as a fourth tier (`scheme jit`) in
the atlas-stoa `run.sh` benchmark next to `scheme simd`. That harness
already has cross-tier correctness gates (selftests, checksum
agreement across languages and tiers).

**Pass:** all correctness gates green; µs numbers match the C tier
(1.21 µs/lookup, 0.94 µs/key) within run-to-run variance (~5–15% on
this machine).

Wrinkle: atlas-stoa consumes letloop via its own submodule. Do not
touch the submodule; add north's `src/` to `--libdirs` in a `run`
variant for the jit tier.

## Step 2b — VEX/AVX2 extension, second customer: base64

Extend the encoder with VEX encoding and the AVX2 subset the base64
kernel uses (enumerate from `objdump -d libb64simd.so`): `vpshufb`,
`vpermd`, `vpmaddubsw`, `vpmulhuw`, `vpand`, `vpor`, `vpaddb`,
`vpsubusb`, `vpcmpgtb`, loads/stores. Same differential-vs-`as`
testing.

Port the AVX2 encode loop from `b64simd.c`. AVX2-only + scalar-Scheme
fallback; drop the SSSE3 path for this milestone. Reuse the C
version's self-test: byte-identical output vs the scalar Scheme
encoder for every input size 0–4096.

**Pass:** in invvv, wire the jit encoder into city-explorer as a
third mode next to `.so` and scalar; run the pinned-Paris `bench.sh`
single-core config; req/s within noise of the `.so` tier (~4555 at
c=4). Same FFI stub, same instructions — any gap means the pipeline
itself leaks overhead.

## Out of scope for this plan

`dubito`/`sum` (v13), ARM/NEON, SSSE3 fallback, code-page
reclamation, any DSL above raw mnemonics, general-assembler
completeness.

## The path — bytes → mnemonics → typed loops → proofs → vectors

Each stage is independently shippable: stopping after any of them
still leaves a win. Branch: `dev-dubito-ergo-cogito` (from `dev`).

- **Stage 0 — proof of life** (half a day). Step 1 above. Artifact:
  a REPL transcript where ~10 hand-written bytes become a callable
  procedure and `(f 1 2)` returns `3`. No assembler exists yet.
- **Stage 1 — GPR assembler** (2–3 days). Step 2a's encoder: ~15
  scalar mnemonics + `popcnt`/`tzcnt`/`pdep`. Artifact:
  `asm.check.scm` green — every form byte-compared against system
  `as`. Pass/fail is mechanical.
- **Stage 2 — first customer: LOUDS** (1–2 days). Fourth tier in the
  atlas-stoa benchmark. **Exit: 1.21 µs/lookup, 0.94 µs/key,
  checksum gates green.** Stop here forever: LOUDS no longer needs a
  C toolchain.
- **Stage 3 — VEX + base64** (3–5 days). Step 2b. **Exit: ~4555
  req/s pinned-Paris.** Stop here: zero C in the production kernels;
  the assembler pays for itself even if `dubito` never happens.

——— **decision gate: above is engineering with hard numbers; below
is language design, planned for v13** ———

- **Stage 4 — `sum`** (a week). See "The second half lives in v13":
  SINK's `meta` operative already does essence recovery. For plain
  Chez/letloop code the alternative surface is a `define-kernel`
  macro capturing source at definition time with **explicit**
  type/shape declarations — no inference, no doubt yet — compiling a
  tiny typed loop language *naively* to Stage-1 mnemonics. Artifact:
  the LOUDS kernels as Scheme-looking loops, same numbers.
- **Stage 5 — `dubito` v1 = contract checker** (a week). Verifies
  what Stage 4 declared (no allocation, no escape, no calls out,
  bounds provable from entry guards), per the design principle
  above.
- **Stage 6 — vectorization** (open-ended, optional forever). The
  doubting pass learns to recognize vectorizable loops. Base64 stays
  hand-written mnemonics until then — it already runs at C speed
  from Stage 3.

Through Stage 3 there is no design ambiguity: the target output is
known instruction-for-instruction from the two `.so` files, and
every exit criterion is a number already measured. The gate is where
the DSL question gets decided, with the full assembler in hand
either way.

## The second half lives in v13

`sum` already exists. On the `xp` branch of
`/mnt/src/scheme/kernel-sink` (commit `10471e6`, "add operative
'meta' to retrieve definitions"), `(meta combiner)` returns an
operative's `static` environment, `parameters`, `dynamic` parameter,
and `body` — essence recovery as a language primitive, no macro
capture needed. Since v13's plan
(`v13/20260730-fusion-vau-primary-language.md`) makes the
vau/Kernel/SINK fusion letloop's primary language, stages 4–6 land
there naturally: `(assembly->procedure (sexp->assembly (dubito (sum
proc))))` with `sum` = `meta` on an operative, and `dubito` checking
the contract over the recovered body. `define-kernel` remains the
migration surface for kernels written in plain Chez Scheme.
