[< All Decisions](../DECISIONS.md)

# CPU Intrinsics and Target Features — Design Rationale

**Resolution:** Blink has no CPU surface: no intrinsics, no inline assembly, no per-function target-feature annotation, no CPU-detection API, no CPU-feature effect or budget, no new escape hatch and no `@cfg`. Code that needs a CPU-specific instruction is C in a native dependency, bound with `@ffi` and `@trusted(audit: K)`. Each target triple has a CPU baseline, the default CPU of the C toolchain for that triple. `blink build` never raises it and never passes a flag that changes an IEEE 754 result of a `Float` operation. The `@trusted` claim covers the CPU: on every CPU that the baseline admits, the foreign code runs only instructions that CPU has. A CPU-specific `std.*` path has a portable path, and every path gives the same result bit for bit.

**Vote:** Q1 6-0; Q2 6-0; Q3 4-1-1 in Phase C (S1, S2, S0), 6-0 for S1 in Phase D. AI-First 5/5 pass.

## The Gap

Blink code cannot reach CPU-specific instructions. The spec has no text on intrinsics, target features or CPU detection: `rg -n -i "simd|target_feature|cpuid|\basm\b|cpu_supports|immintrin"` over `sections/`, `DECISIONS.md` and `OPEN_QUESTIONS.md` returns nothing. The word "intrinsic" in the spec means compiler-known functions such as `assert_matches`, `#embed` and `prop_check`. The only route to a CPU instruction today is C behind `@ffi`. Facts the panel started from:

- The escape-hatch list in §9.1 is closed, and a new entry needs a panel vote. There is no general `unsafe` block (§1.3).
- There is no `FFI` effect. The row of an `@ffi` decl is the author's claim, and the compiler assumes it (§4.5).
- A user package can ship C through a `vendored` native dependency. A cross build compiles that C with `zig cc -target <triple>`. No manifest key picks per-target flags or sources.
- The language has no conditional compilation on the target.
- `blink build` passes no `-march` or `-mcpu` flag today. The four release targets use the default CPU of the C toolchain.
- The gate builds an arm64 binary and never runs it, and no macOS binary runs in it either.
- The runtime relies on C built without `-ffast-math` (`bootstrap/runtime_core.h:3125`).
- Measured on SHA-256 of a 6.1 MB file at `-O2`: Blink 27 ms, portable C 13.6 ms, libcrypto with SHA-NI 2.3 ms. 81% of the Blink time is bounds checks and overflow checks, which a codegen change removes. Only the CPU instruction closes the rest.

## Panel Deliberation

The ticket, in part, verbatim:

> **spec: CPU intrinsics, per-function target features, and runtime CPU detection**
>
> Blink code cannot reach CPU-specific instructions (SHA-NI, AES-NI, SIMD). The spec has nothing on intrinsics, target_feature, or CPU detection (rg simd/target_feature/cpuid/asm over sections/ and DECISIONS.md: no hits). Today the only route is C behind @ffi.
>
> Measured 2026-10-17, SHA-256 of a 6.1 MB file at -O2: Blink 27 ms, plain portable C 13.6 ms, libcrypto with SHA-NI 2.3 ms. [...] Only the CPU's own instructions close the rest.
>
> Prior art:
> - Go: hand-written assembly per arch, with run-time selection through internal/cpu.
> - Rust: core::arch intrinsics, #[target_feature(enable=...)] on an unsafe fn, and is_x86_feature_detected!. The sha2 crate falls back to portable code.
>
> Questions for the panel:
> - Should Blink users write such code at all, or should std and the runtime own every accelerated path?
> - If users can: what surface (intrinsic module per arch, target-feature annotation, detection API)?
> - How does it interact with effects/@trusted, since calling an instruction the CPU lacks is SIGILL?
> - How does it interact with cross-compilation (-T targets, zig cc) and with code paths that ci never runs (arm64)?
> - What is the fallback rule?

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated in four phases. Quoted text is each panelist's own words. "[...]" marks a cut inside one paragraph or list item.

Questions:

- Q1: the wording of the CPU part of the `@trusted` claim. **C1** (baseline-scoped): "On every CPU that the target triple's baseline admits, the foreign code runs only instructions that CPU has." **C2** (running CPU): "The foreign code runs only instructions the running CPU has."
- Q2: **F1**, the baseline rule also says that the build never passes a flag that changes floating-point semantics; or **F0**, no such clause.
- Q3: a runtime SIGILL message. **S0**: not in this decision. **S1**: a runtime chore named in the decision, no spec text. **S2**: S1 plus one spec sentence on the message.

#### Phase A — Independent proposals (excerpts)

All six first choices had one shape: no CPU surface in the language; std and the runtime own accelerated `std.*` paths; user code reaches CPU instructions only through escape hatch 1. Excerpts of each first choice:

- **Systems** (sys-1, no CPU-intrinsic surface; accelerated code is C behind `@ffi`):

  > **Baseline rule.** `blink build` compiles the generated C and every vendored C source for the baseline CPU of the target triple. It never passes `-march=native`, `-mcpu=native` or a feature flag such as `-msha` for the whole unit. A binary built for `x86_64-linux-gnu` runs on every x86_64 CPU; one built for `aarch64-macos` runs on every Apple arm64 CPU. This makes builds reproducible and makes a cross build equal to a host build for the same triple.

- **Web/Scripting** (web-1):

  > **Rule.** The language has no CPU intrinsics, no per-function target-feature annotation, no CPU detection API and no inline assembly. Every path that uses a CPU-specific instruction lives in the runtime C behind a std function. The std function has the same contract on every target and every CPU. A user who needs an instruction std does not cover writes C and binds it with `@ffi` (escape hatch 1, which exists today). No new escape hatch, no new effect, no new annotation.

- **PLT** (plt-1):

  > 1. **Observational equivalence.** When a `std.*` function or the runtime has more than one implementation selected by CPU (or by target), every implementation returns the same result for every input, bit for bit, and has the same effect row and the same panics. The function's meaning is its portable definition. Only timing may differ. A program cannot tell which path ran.

- **DevOps** (devops-1), proposed spec text:

  > Each target triple has a CPU baseline: the default CPU of the C toolchain for that triple. `blink build` never passes a flag that raises it. Generated code and `std.*` run on every CPU of the baseline. Code that uses an instruction above the baseline is foreign code: it lives in a native dependency, and its `@trusted(audit: K)` claim includes that it checks the CPU at run time and keeps a portable path. `std.*` follows the same rule and adds no accelerated path for an architecture that ci does not run.

- **AI/ML** (aiml-1):

  > 1. Blink has no CPU intrinsics, no vector type, no inline assembly, no target-feature annotation and no CPU-detection API. This is a decision, not a gap.

  > Decision points per call site: zero. The model writes `digest.sha256_hex(data)` and gets SHA-NI where the CPU has it.

- **Minimalism** (min-1):

  > Position in one line: add no language surface. The existing escape hatch 1 (`@ffi` + `@trusted(audit: K)` over a `vendored` C source) already reaches every CPU instruction on every target. The spec gap is a missing *statement*, not a missing feature. Close it with three sentences of spec text, not with syntax.

Other proposals on the record:

- **plt-2, the sound Rust-shaped surface** (PLT votes no):

  > I write it out so that, if the panel goes this way, it goes with a typing rule and not with a convention.

  Its six rules are the bar for any later user-facing CPU surface (see *Project Policy*).
- **devops-2, a SIGILL message** (the add-on that became Q3):

  > Whatever the panel picks, SIGILL will reach users: a wrong `__builtin_cpu_supports` string, a vendored library built with `-march=native` by its upstream Makefile, a baseline mismatch. The diagnostic surface for that event is today the OS default: `Illegal instruction (core dumped)`. Proposal: the runtime installs a SIGILL handler (async-signal-safe: `write(2)` a fixed message, then restore the default action and re-raise, so the exit status and the core dump stay the same, and `blink test` still records `"signal": "SIGILL"` per 06_tooling.md:1566).

- **Rejected on the record:** a Blink-side CPU query (web-2 `std.cpu` report; aiml-2 `std.cpu.has(Feature)`) and the Rust shape (`std.arch.<arch>` intrinsics, a target-feature annotation and `cpu.has(...)`: web-3, sys-3, devops-3, plt-2).
- **Possible later ticket:** portable vector types (sys-2, plt-3).

#### Phase B — Debate highlights (1 round; all six "ready to vote")

The moderator merged the shared points and put nine items to the seats. The key shifts:

- **Baseline rule added.** Three seats had not proposed it in Phase A. All six accepted it. Web: "It is one sentence and it is something users can depend on, so it goes in the spec. I did not write it in Phase A. I should have."
- **Float flags (sys).** Sys added a clause to the baseline rule:

  > I support devops-1's wording, with one addition: the build never passes a flag that changes floating-point semantics (`-ffast-math`, `-ffp-contract=fast` and similar). Evidence that this already matters: bootstrap/runtime_core.h:3125 relies on "C without -ffast-math" for IEEE behaviour of two helpers.

- **Claim wording.** Plt withdrew the per-run wording for the baseline-scoped merge:

  > "Every CPU of every target the package builds for" (min-1, aiml-1) quantifies over a set nothing defines: a package does not declare its targets. A claim must have a fixed meaning at the audit site.

  Devops dropped its own "checks the CPU at run time" clause from the claim and put it in guidance. Plt: "devops-1's addition (the C checks the CPU at run time and keeps a portable path) is the usual *means* of meeting the claim, not the claim itself."
- **Bit for bit.** All six took plt's rule: same result bit for bit, including `Float`, same effect row, same panics. Plt: "'Same result for every input' is ambiguous for `Float`. A reordered SIMD sum gives a result that is 'the same up to rounding', and someone will read the rule that way." Min: "It adds a few words, and it closes a gap that will be real once anyone touches `std.math`: a reordered SIMD sum is a different function."
- **The ci rule moves to the rationale.** Web, aiml and sys conceded to plt and min. Web: "My web-1 put rules 4–5 in the spec. plt's argument is right: the spec states the observable rule (V3, bit for bit), and the test switch plus "no path for an arch ci does not execute" are *how std checks* that rule." Aiml: "I proposed it as spec text (aiml-1 rule 3). I withdraw that. The spec describes the language for its users, and a user cannot see or rely on this repo's ci." Plt and min held their Phase A position. Devops conceded too, and asked that the rationale make the policy binding on every accelerated std path, not only SHA-256.
- **Vector types.** Sys, plt and devops asked to keep portable vector types out of the non-goal line. Min conceded: "**Concession: drop "no SIMD or vector types" from the non-goal line.**" Aiml: "I change my position here." Min still opposed a "future direction" note in the spec. The text says nothing about vector types.
- **Withdrawn proposals.** Aiml: "**withdraw aiml-2**, oppose web-2." Web: "**Oppose, including my own web-2.**" Plt on its own proposal: "plt-2 stays in the record as the shape a future panel must meet *if* it ever reopens this: the feature set Φ in the typing context, flow refinement only on the intrinsic guard, no coercion of gated functions to plain `fn` types, no inheriting through closures, no `@target_feature` on trait impls, and target-conditional modules. Each is a soundness obligation. Today the need is one std function, so no."
- **An example with an operation that does not exist.** Devops on the sys-1 example:

  > **sys-1 example:** `s.bytes_ptr(data)` is not an `FfiScope` operation (07:610-616 lists `alloc`, `cstr`, `take`). The 07:488-496 `data.with_ptr(fn(p) -> ... { ... })` pattern inside a `@trusted` body, as in plt-1, aiml-1, min-1 and devops-1, is the spec form. Whoever writes the decision should use that one, since examples in the spec become training data.

  The example in *Final Spec* uses the `with_ptr` form.
- **The SIGILL message.** Sys raised the cause problem: "`__builtin_trap()` and trap-mode sanitizers compile to `ud2` on x86_64 / `brk`/`udf` on arm64, which raise SIGILL (or SIGTRAP)." Plt: "A diagnostic that blames the user for our bug is wrong." Min opposed the handler in this decision.
- **Binding form.** No seat wanted text on how std binds its runtime C. The pending decision on FFI signature types governs it, and this decision does not re-decide it.

#### Phase C — Final vote

Each panelist voted alone on a written ballot. The carried points had no vote. No seat objected to any of them.

##### Q1 — Wording of the CPU part of the claim — **C1, baseline-scoped** (6-0)

Web and min moved from C2 to C1 between Phase B and Phase C.

- **Systems:** "The build sees a triple, not a machine, so the claim must be scoped to what the build can name: every CPU the triple's baseline admits."
- **Web/Scripting:** "In B1 I backed the running-CPU wording because it is shorter. But C2 makes an honest author's claim false on a CPU below the baseline, where the generated Blink code itself would already crash. That author did nothing wrong."
- **PLT:** "A claim at an audit site needs a fixed meaning there. C1 quantifies over a set the toolchain defines for the triple, and that set is the same one the carried baseline rule uses, so the two rules talk about the same CPUs."
- **DevOps:** "The reviewer of audit record K must be able to check the claim against a fixed set, and "every CPU of the target triple's baseline" is one fixed set per build."
- **AI/ML:** "C1 is my B1 merge in tighter words: it names the triple's baseline, which a reviewer and a model can check against the build, and it still says what must hold on each CPU."
- **Minimalism:** "In B1 I backed C2 because it is shorter, but C2 claims too much. On a CPU below the triple's baseline, the generated Blink code itself may stop with SIGILL. C2 would blame the foreign author for that, because their claim covers "the running CPU" with no limit."

##### Q2 — Floating-point build flags — **F1** (6-0)

- **Systems:** "The bit-for-bit rule for `Float` (carried) is only enforceable if the build also cannot change float semantics; `-ffast-math` or `-ffp-contract=fast` lets the C compiler reassociate or fuse operations, so the same Blink code gives different `Float` results across compilers and targets."
- **Web/Scripting:** "A `-ffast-math` build flag would break that promise for every program, not just for std, and the user would see a sum that differs between machines with no way to find the cause."
- **PLT:** "`-ffast-math` and `-ffp-contract=fast` let the C compiler change the value of a `Float` expression, so without F1 the build itself breaks the rule that std has to keep."
- **DevOps:** "A `-ffast-math` or `-ffp-contract=fast` build breaks that rule as surely as a reordered SIMD sum, and no test on the host shows it, because the host build and the user's build would differ only in flags."
- **AI/ML:** "'Make it faster' makes a model reach for `-ffast-math` next after `-march=native`, so the spec should close both with one sentence."
- **Minimalism:** "It is a promise *not* to do something, so it adds no construct, and the bit-for-bit rule depends on it."

##### Q3 — Runtime SIGILL message — **S1 4, S2 1, S0 1**

The result was closer than 5-1, so Phase D ran one more round on Q3.

- **Systems: S1.** "Zero hot-path cost, and it turns `Illegal instruction (core dumped)` into a pointer at the cause, so it is worth a ticket."
- **Web/Scripting: S1.** "The readable message is the part users feel, and S1 gets it built with the conditions that keep it safe: exit status, core dump and the `blink test` record stay the same, and it chains to any prior handler."
- **PLT: S1.** "The message changes no value, row or exit status a program can see, so it is runtime behaviour, not language semantics, and it does not belong in the spec."
- **DevOps: S1.** "I accept the point raised in Phase B: on x86_64, `__builtin_trap()` compiles to `ud2`, which raises SIGILL, so a SIGILL is not always "foreign code without a CPU check". A message that names one cause would send users to `blink audit` when the bug is in the runtime."
- **AI/ML: S2 (dissent).** "The message is what a model that debugs a crash reads first, so its content (it names the signal and points to `blink audit`) is user-visible behavior that a model should be able to learn from the spec, not only from the runtime source."
- **Minimalism: S0 (dissent).** "The decision makes SIGILL from std impossible and makes SIGILL from foreign code a broken audit claim. That leaves a rare event, and a process-wide signal handler is runtime surface that we would have to own forever (chaining with Boehm, with user handlers, with the `blink test` signal record)."

#### Phase D — One focused round (Q3 only) — **S1** (6-0; aiml and min moved)

Each seat wrote a reply of at most 150 words, then voted alone. The Phase D text of S1 added these conditions: an alternate signal stack (`sigaltstack`); a test that forces a SIGILL and checks that the process ends by the signal; and the handler ships only on targets where the gate runs that test.

What moved aiml and min was the `ud2` fact, first raised by sys in Phase B and accepted by devops in Phase C.

- **AI/ML** moved from S2 to S1: "devops and sys give the fact that decides it: on x86_64 `__builtin_trap()` is `ud2`, so a SIGILL can come from a runtime trap, not only from foreign code. S2's sentence points to `blink audit`. A model that reads that sentence will trust it and audit the wrong code. A spec sentence that is sometimes false teaches worse than no sentence."
- **Minimalism** moved from S0 to S1: "devops and sys break my main premise. I said SIGILL becomes rare, but on x86_64 `__builtin_trap()` lowers to `ud2`. So C traps and runtime bugs also raise SIGILL, apart from any CPU feature. The event is not rare enough to leave as a bare core dump. S1 adds no spec text and no language surface, which was my real objection."

Votes:

- **Systems: S1.** "The handler costs one `sigaction` at start and nothing on the hot path, and it turns the hardest crash to debug in this space into one that lists its possible causes."
- **Web/Scripting: S1.** "A user who sees a bare `Illegal instruction (core dumped)` has nothing to search for, and S1 fixes that without freezing words in the spec that are not always true (`ud2` from `__builtin_trap()` is also SIGILL)."
- **PLT: S1.** "S2's sentence points every SIGILL to `blink audit`, which is false for a `ud2` trap or a runtime bug."
- **DevOps: S1.** "In place of a bare core dump, the user gets a named signal and a list of possible causes. Exit status, the core dump and the `blink test` record, which tools parse, do not change."
- **AI/ML: S1.** "S1 gives the model a message at crash time that lists the possible causes, and puts no unstable text in the spec."
- **Minimalism: S1.** "S1 fixes it in the runtime with no spec text and no language surface, which was my only objection. I accept the gated-target condition: the handler ships only on targets where the gate runs the forced-SIGILL test, so we do not promise behaviour that we never execute."

Priority: aiml asked the decision to record a priority or to state that owner triage sets it. Min: "Owner triage sets the priority, not this decision." The decision records that **owner triage sets the priority**.

**The handler ships only where the gate runs the test.** The release targets that the gate does not run keep the bare OS message for now. Those are arm64 and macOS. This decision gives no promise that the message exists there.

#### AI-First Review

Learnability: one subsection holds the baseline, the claim and the std rule, and the text in §1.3 links to it, so a reader who searches for `@target_feature` finds "use C behind `@ffi`". Consistency: no new escape hatch, effect, annotation or error code; the claim is the existing `@trusted` claim with its scope stated. Generability: the guidance example compiles under the current spec and a model that follows it keeps a portable path. Debuggability: a SIGILL is a broken claim of a named audit record, or a bug in std or the runtime; the runtime message chore lists the causes. Token efficiency: zero new tokens in Blink code, and one binding, one wrapper and one manifest line for the rare user who needs C. 5/5 pass.

### Final Spec

The normative text is §9.1 *CPU Baseline and Accelerated Code*. Escape hatch 1 in the table and the first sentence of *`@trusted` — Audit Trail* name the CPU, and §1.3 and §9.1.2 link to the subsection. The guidance example:

```blink
@ffi("fastcrc", "fastcrc_crc32c")
@trusted(audit: "CRC-001")
fn raw_crc32c(data: Ptr[U8], len: U64) -> U32 ! ()

@trusted(audit: "CRC-002")
pub fn crc32c(data: Bytes) -> U32 {
    // the closure inherits the region of the @trusted body
    data.with_ptr(fn(p) -> U32 { raw_crc32c(p, data.len().to_u64()) })
}
```

The `blink.toml` entry is `fastcrc = { type = "vendored", path = "vendor/fastcrc.c" }`. The C file has a portable path and an x86-64 path in a function marked `__attribute__((target("sse4.2")))`, chosen with `__builtin_cpu_supports("sse4.2")`.

Locked points:

- **No CPU surface.** Blink has no CPU intrinsics, no inline assembly, no per-function target-feature annotation and no CPU-detection API. There is no CPU-feature effect or budget, no new escape hatch and no `@cfg`. The spec says nothing about vector types. Code that needs a CPU-specific instruction is C in a native dependency, bound with `@ffi` and `@trusted(audit: K)`.
- **Baseline.** Each target triple has a CPU baseline: the default CPU of the C toolchain for that triple. `blink build` never passes a flag that raises it. Generated code, `std.*` and vendored C are built for the baseline. A program built for a triple runs on every CPU that the baseline admits.
- **Floating point.** `blink build` passes no flag that changes an IEEE 754 result of a `Float` operation. The two flags in the text are examples, not a list.
- **The claim.** "On every CPU that the target triple's baseline admits, the foreign code runs only instructions that CPU has." Foreign code that runs an instruction the CPU lacks breaks the claim, the same as foreign code that writes out of bounds. This clarifies escape hatch 1. The list stays at four entries.
- **Means, not claim.** The usual way to meet the claim is a run-time CPU check and a portable path. Code that uses only baseline instructions needs no check. The text and the example are guidance.
- **`std.*` same-result rule.** A CPU-specific `std.*` path has a portable path, and the runtime picks the path at run time. Every path gives the same result bit for bit (including `Float`), the same effect row and the same panics. A pure std function stays pure. A `std.*` call never runs an instruction that the running CPU lacks, and a SIGILL from `std.*` is a bug in std or the runtime.
- **No error code.** The decision adds no E or W code.
- **No SIGILL text.** The spec has no text on a SIGILL message.

### Project Policy (not spec)

These rules bind the project. They are not in `sections/`.

- **Every accelerated std path, not only SHA-256.** A test switch forces the portable path. The gate runs both paths against the same vectors. No CPU-specific std path ships for an architecture that the gate does not execute. Devops asked for this scope; web: "it is *binding* policy for std, so the rationale must state it as a rule, not a hope."
- **Portable vector types** (sys-2, plt-3) are a possible later ticket with its own vote. The lowering would be to the target baseline, with no per-arch surface and no SIGILL. Plt: "It only declines to rule out a sound design in a decision that is not about it."
- **The bar for a later user-facing CPU surface** is plt-2, in plt's words: "the feature set Φ in the typing context, flow refinement only on the intrinsic guard, no coercion of gated functions to plain `fn` types, no inheriting through closures, no `@target_feature` on trait impls, and target-conditional modules. Each is a soundness obligation."
- **Rejected on the record:** a Blink-side CPU query (web-2, aiml-2) and the Rust shape (web-3, sys-3, devops-3, plt-2).

### Concerns for implementation

- **The toolchain default can move** (sys, devops). The baseline is the default CPU of the C toolchain. Sys: "`The toolchain's default CPU for that triple` can move when zig or the C compiler changes its default, so the baseline (and with it this claim) should be pinned per release target in the build docs, or a toolchain bump silently raises it." Devops: "the set that every K record refers to changes too, with no notice to the authors of those records."
- **Contraction is on by default** (plt, sys). Plt: "GCC in GNU C mode defaults to `-ffp-contract=fast`, and clang defaults to `-ffp-contract=on`, so on aarch64 (FMA is in the baseline) `a * b + c` can fuse with no flag at all and give a result that differs from x86_64. The implementation chore must pin contraction off (`-ffp-contract=off`), not only avoid adding flags, or F1 holds in words but not on arm64." Sys asked for the same.
- **"And similar" is the IEEE 754 property** (min, devops, aiml, web). Min: "The text should say "any flag that changes IEEE 754 semantics", with `-ffast-math` and `-ffp-contract=fast` as examples". Aiml: "give the two flags only as examples, or a model will treat the list as complete." The spec text states the property.
- **One subsection, one definition** (aiml, min, web). Min: "If the §9.1 text does not fix that definition in one place (the C toolchain's default CPU for the triple), readers will each guess a different baseline." Aiml: "the claim and the baseline rule must sit in the same §9.1 subsection, with a cross-reference from escape hatch 1's table row." Web: the claim sentence should link to the baseline rule next to it.
- **The guidance example shows a run-time check** (plt). Plt: "A reader may take C1 to mean the foreign code may assume the baseline *and nothing more*, and miss that a run-time check is how it may use more; the guidance example next to the claim must show that."
- **SIGILL chore conditions.** Async-signal-safe: only `write(2)`, no allocation, no GC (plt). Chains to any prior handler and re-raises with the default action (all). Lists the possible causes and asserts none (sys, plt, devops). Uses an alternate signal stack: sys, "A SIGILL handler that runs on the faulting thread's stack fails on a stack overflow or a corrupted stack, so the chore must use `sigaltstack` or accept that the message sometimes does not print." Has a test that forces a SIGILL and checks that the process ends by the signal: plt, "A handler that chains badly (to a handler that returns, or to `SIG_IGN`) re-executes the faulting instruction in a loop". Ships only on targets where the gate runs that test.
- **The handler is a per-target choice** (sys): "the chore must make the handler a per-target compile-time choice in the runtime and must not quietly turn it on there."
- **Users on arm64 and macOS see the bare message** (web, plt, devops, min). Devops: "the arm64 and macOS release targets get no message until ci runs them, and those are the targets most likely to SIGILL." Min: "Users on those targets will see different crash output from x86_64 Linux users until ci runs those targets."
- **Text outside the spec** (aiml, Phase C): the message wording lives only in runtime C, and a later change will not show up in the spec that models learn from. Aiml accepted S1 in Phase D.

### Follow-ups

- A runtime chore for the SIGILL message, with the conditions above. Owner triage sets the priority.
- A build chore to pin `-ffp-contract=off` in the C compile command and to record the CPU baseline of each release target in the build docs.
- `lib/std` still writes `! FFI {}` on its runtime bridges, though the spec has no `FFI` effect (§9.1, *The Effect Row*). This decision does not change that. The bridge migration of the pending FFI signature types decision may cover it.
