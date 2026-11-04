[< All Decisions](../DECISIONS.md)

# What a Clean `blink check` Promises — Design Rationale

**Gap:** `blink check` ran the compiler from lex to mono and stopped. A program could pass it and then fail in `blink build`, with an error that `blink check` never showed. The spec did not say which build failures a clean check rules out, which exit codes check and build use, or what an agent should do on each. W0501 (a method call on an unknown receiver) hid some of these failures as a warning. The panel also had to say what happens to a missing `@ffi` header.

**Result:** 6-0 on Q1 to Q7 (settled in Phase B round 1), 5-1 on Q3a (Minimalism dissented; Systems moved from A to B). After a clean `blink check`, with the same inputs and the same strict flags, a build stops only on a cause outside the Blink source. Any other stop is a compiler bug. Check need not run lowering, and gives no proof of run-time behavior. `blink check` and `blink build` exit 0, 1 or 101; 101 is a compiler bug. W0501 goes. `blink build` and `blink test` test each `@ffi` header before the unit compile; a missing header is E0859 at the `@ffi` line, exit 1.

| Q | Result | Tally |
|---|---|---|
| Q1 | Exit codes are 0, 1 and 101 for check and build. There is no exit 3. A program panic under `run` also exits 101, so 101 means a compiler bug for check and build only | 6-0 |
| Q2 | W0501 goes. A poison receiver gets no diagnostic. A truly unknown receiver is E0505, or E0301 if that fires first. The ICE for the code generation backstop replaces the E0505 backstop there | 6-0 |
| Q3 | One I0017 for a C compiler failure. No parsing of `cc` text, no split by program. The `@ffi` note prints only if the program has its own `@ffi` or native dependency, and says a wrong `@ffi` prototype also gives this code | 6-0 |
| Q3a | `blink build` and `blink test` test each `@ffi` header before the unit compile. A missing header is a named E-code (E0859) at the `@ffi` line, exit 1. A `cc` failure that remains is I0017, exit 101. This changes the §8.10.5 row | 5-1 |
| Q4 | `blink build` uses E0857 and E0858 for linker and native failures | 6-0 |
| Q5 | `fn g[T](x: T) -> Int { h(x) }` with `h[U: Sh]` is E0306 at `h(x)`, called or not, with help `[T: Sh]`. It needs a Breaking Changes line. `g[T: Sized]` with `g(1)` and `x.len()` is E0306 at the call | 6-0 |
| Q6 | The gate and the tracker hold the known-failure list. The spec states the requirement and keeps no list | 6-0 |
| Q7 | The promise covers any supported target. `--strict` and `--strict-struct-layout` must match. `--debug`, `--release` and `--trace` need no match | 6-0 |

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated in independent-proposal → debate → vote rounds. The excerpts below are verbatim. Each cut is marked `…`. Code names for probes, ticket numbers and scratch paths are cut.

#### Phase A — Independent proposals

- **Systems:**
  > Position: a clean check closes all language questions. If a build then fails, the cause is the world outside Blink or a compiler bug, never the Blink code.
  > …
  > Same source, same compiler, same `--strict` setting: check exits 0, so `blink build` gives no language diagnostic.
  > …
  > Outside the promise does not mean raw C text. The first case is the correct shape, and the other two should match it. E0857 LinkFailed has the words, and `blink build` can use it too. The build tests each named header before the unit compile. A `cc` failure that remains is I0017, with a note to check any `@ffi` text.
  > …
  > A program that check accepts and build refuses, with no cause from the outside list, is a compiler defect. The compiler team fixes it, and the diagnostic does not ask the user to change code. The fix is what the spec requires: build accepts the program, or check rejects it if a spec rule does. "Documented limitation" is not a result, so the known-failure list may only shrink.
  > …
  > A generic body is checked once, at its definition, with `T` opaque except for its declared bounds. Mono never finds a type error. Dead code gets the full check. This is the rule that `[T: Sh]` has today (§3c.4 *Resolution is fixed where the call is checked*): zero bounds means zero methods.
  > …
  > **Should check also run lowering? No.** On `src/cli.bl`: check 1.43 s, 312 MB; `--emit c` 2.07 s, 394 MB, so up to 45% more on each LSP and daemon check. Cost is not the main reason. A rule that only lowering can see is what rule 2 forbids, and lowering in check would hide it. It would catch no C error (w3, w4), and an earlier ICE gives the user nothing to act on.

- **Web/Scripting:**
  > **Position.** A dev must get one sentence: "If `blink check` is clean, your Blink code is right. If the build then fails, the cause is outside Blink or it is our bug, and the message says which." That is the `tsc --noEmit` mental model. Do not copy the `cargo check` gap (post-mono and link errors after a clean check).
  > …
  > **One rule: every fn body gets checked, called or not, generic or not.** In a generic body, `T` has only what its bounds declare. No C++ template duck typing. TS, Kotlin and Rust devs expect this.
  > …
  > Only a bare `T` escapes, through warning W0501. §6.3.3 says the compiler "never accepts the call without a check", so W0501 contradicts it. **Retire W0501; both its cases become E0505.** Help for a bare `T` adds a bound; help for an unresolved receiver adds an annotation. Each repair exists (rule 1).
  > …
  > Tradeoff. The promise is false today. The gate row and a known-failure list that can only get shorter make it true. A weaker "build may still fail in ways we do not list" makes devs and agents run the build each time, and then check has no value.

- **PLT:**
  > State a property of the compiler, not a list of stages. For one source set (entry, imports, config, `#embed`) and one compiler: if `blink check` exits 0, then `blink build`, on any target with any flags, ends in one of:
  >
  > - **A.** Exit 0 and a binary.
  > - **B. Foreign refusal.** A named error about a fact outside Blink source.
  > - **C. Environment stop.** The machine or toolchain cannot do the work.
  >
  > Any other result is a compiler defect. `@ffi` declarations are axioms: the promise holds relative to them. The promise says nothing about the run: a panic or a failed contract is outside it.
  > …
  > A failure outside B and C is a **conformance defect in the compiler**, type:bug. The user owes no edit, even if an edit avoids it. So the E0505 backstop in `src/cg_call.bl` must become an I-code: an E-code tells the user they are wrong, but this stage has found a front-end hole.
  > …
  > **A function is typed once, at its definition. Reachability is not part of the judgment.** Adding a call cannot change whether a body is well typed. This makes the rule compose.
  > …
  > - **Rejected:** "check promises only what it ran". This restates the pipeline and makes each ICE look acceptable.

- **DevOps/Tooling:**
  > Exit 0 means: **`blink build` of the same inputs does not stop because of your Blink code.** If it stops, the setup is at fault (the build says so) or the compiler has a bug. An agent then has three branches: edit code, fix setup, report a bug. Today it cannot tell them apart: w3 prints raw C text and exits 1, the same as a typo. "Same inputs" means sources, `blink.toml`, dependencies, compiler version and shared flags.
  > …
  > It is a **compiler bug, always**, and the compiler team fixes it. A user may work around it but owes no change. This follows from Diagnostic Discipline rule 2, whether the front-end rule is missing or the lowering is not built. The spec states the promise as a requirement. Today's gaps go in Known Limits and on a list with one fix per row, which only gets shorter. The gate row builds each check-clean corpus file and fails on any new E or I code.
  > …
  > **Every body is checked once, reached or not. A type parameter has only the methods its bounds declare.** This holds today for a bound that lacks the method:
  > …
  > This retires W0501 for a type parameter. §6.3.3 says the compiler "never accepts the call without a check", and a warning with exit 0 is such an acceptance. The bound is the repair (rule 1).
  > …
  > Reachability must not change the verdict: w6 and w7 get the same answer. Typing rules are judged per declaration. Per-instance rules (the pointee of `Ptr[T]`) are judged on instances that exist, and a generic with no instance emits nothing.
  > …
  > **Not proposed: lowering inside check.** Measured on `src/blinkc_main.bl`: check 0.9 s, `build --emit c` 1.3 s. That is fine for a CLI and not for an LSP on each edit. It also changes no ownership: a lowering failure is still a compiler bug. Rules move forward (rule 2) and the corpus gate catches the rest. The header of `src/check_pipeline.bl` ("none of them can stop short of a stage the build runs") is false today and must change.

- **AI/ML:**
  > > After `blink check` exits 0, `blink build` of the same source makes a binary, or stops for a cause outside Blink source: a foreign name, a header, a library, or the host. Any other stop is a compiler bug. The source stays as it is.
  > …
  > The outside list is closed; a new row needs a panel vote. The stdlib's own `@ffi` counts as compiler. `blink build` must use E0857 and E0858, which only `blink test` uses today. I0017 today also covers a bad `@ffi` header; that must split, because an agent cannot act on one code with two meanings.
  > …
  > Do not run lowering in check. w2, w3 and w4 are valid programs that lowering fails on; running it in check only moves the ICE earlier and slows check. A gate row holds the promise.
  > …
  > Exit 101, which I0021 already uses. Today w2 exits 1, the same as a typo, so an agent starts to edit correct code. This exit code is the largest benefit here for the smallest change. Known failures go on a list that only gets shorter.
  > …
  > Every body gets every typing rule, once, at its definition, with or without a caller. In a generic body `T` is opaque: only methods from its bounds exist. A call that passes the bounds (E0306) gives no new diagnostic at any instance. (Instance limits are the other ticket.)

- **Minimalism:**
  > Add one promise. Add no flag, no mode, no new error code. Delete one warning.
  >
  > **The promise.** Check exit 0 means: `blink build` of the same inputs with the same strictness flags reports nothing wrong with the Blink code. It can stop only on something outside the Blink code. Any other stop is a compiler defect.
  >
  > Rule 2 of Diagnostic discipline already says most of this. We only state the corollary, and name the outside.
  >
  > What if we just don't? Then every agent must treat a clean check as a guess and run the full build anyway, and `blink check` has no reason to exist. So I vote yes, and at the smallest size.
  > …
  > The test for a C or link error is one question: did Blink code or foreign text cause it? The boundary is `@ffi` and sidecar C. Check never reads those, and the C compiler of the target is their only judge. Section 07 already says so for foreign constants ("The front end sees the type and never the value").
  > …
  > It is a compiler defect, the same kind as an ICE. Compiler maintainers fix it. The user owes no change to the program, though a workaround is fine.
  >
  > The fix is one of two: make check refuse the program with the right code, or make the build accept it. The spec picks which. Example: `3.max(4)`. If the spec has `Int.max`, build it. If not, it is E0505 in check. Either way the promise picks no side on the feature.
  >
  > A break is not a spec exception. No known-failure list goes in `sections/`. That list lives in `br` and in the gate row, and it shrinks to zero.

#### Phase B — Debate (round 1)

All six seats replied to a digest of Phase A. Each reply follows in full, less its header and its "Stable" line.

- **Systems:**
  > Q1: B (0, 1, 101, for check and build). `check_exit_code` and I0021 already use 101, so A means removing it from check, and a build ICE at exit 1 sends an agent to edit correct code. No exit 3: the E-code name separates code from setup. Exit 2 for a bad command is a separate question. Risk for the writer: `blink run` of a program that panics also exits 101 (measured), and a `run` ICE exits 1 today. Scope 101-as-compiler-bug to check and build. For `run`, read the diagnostic.
  >
  > Q2: A, with an order. §6.3.3 says "If the compiler cannot find the type of the receiver, it reports an error", so W0501 has no spec basis. But the digest's sites look like valid code: `Slot.Param(0)`, `LimitValueError.UnknownUnit("k")`, `telemetry.record("mem", 42)`. A severity change would reject those programs if the path fires. I could not reproduce the hits: gen1 from the repo root prints `ok:` with no warning on all three, also `--strict` on the second file. Someone must find how the sweep got them. Fix the false hits first, then delete.
  >
  > Q3: A. A split by program (C) gives exit 1 to a real bug in any program with one `@ffi`. Attribution (B) must parse cc text. Raw text (D) tells nobody who owns it. Tradeoff: a typo in a user's header gets I0017 and 101, so the note must name the header first.
  >
  > Q4: A. E0857 and E0858 already exist.
  >
  > Q5: A, and … It breaks a program that builds and prints 2 today, so it needs a Breaking Changes line. I also hold devops's B. Measured: `fn g[T: Sized](x: T) -> Int { x.len() }`, `g(1)` gives check 0, then ICE `Int.len`. E0306 at the call. Both are the one bound rule. I found no ticket for B in a filtered `br` search; it needs a sweep and a ticket if none exists.
  >
  > Q6: B. `br` plus the gate row. The spec states the requirement and does not record today's gaps.
  >
  > Q7: A for target, B for flags. Typing has no target input, so one clean check covers each supported target, with foreign causes outside. `--strict` and `--strict-struct-layout` must match. `--debug`, `--release`, `--trace` need no match.
  >
  > Changes from Phase A:
  > - Header preflight comes off my proposal. It is a later improvement, and it would edit the §8.10.5 text, so it is not needed for the promise. Reason: Q3 works without it.
  > - I added the call-site E0306 shape, from devops's probe, which I reproduced.
  > - My help text keeps "Check runs no C compiler", which is a promise about foreign input. It says nothing about lowering, as min asks.
  >

- **Web/Scripting:**
  > **Q1: B (changed from A).** `check_exit_code` in src/check_pipeline.bl already returns 101 on an ICE, and I measured w2 build at exit 1. So "unchanged" keeps check and build in disagreement. 101 means "stop editing". Against C: `blink test` can keep its 2, but exit 3 is one more code a dev must learn, and the E-code name already says setup or code.
  >
  > **Q2: A, delete, now with data.** The digest's three corpus hits are cascades. Run from tests/, test_cross_module_effects.bl and test_layout_children_typedefs_binders.bl stop on `error[OrphanFile]`, exit 1. W0501 then fires on the poison receiver, beside `undefined variable `telemetry``. Run from the repo root, those two give `ok`, and all three named files give zero `UnknownMethod`. My probes with no type variable also fire W0501 only beside a real error (`fn(x) { x.frob() }` with CannotInferType, `Nope.frob(1)` with UndefinedVariable). §6.3.5 already says a poison receiver stays silent. I found no exit-0 program where this warning does a job. So the remaining case is noise, not a guard. If the sweep from the repo root finds one such program, it becomes E0505 with "annotate the receiver".
  >
  > **Q3: A.** One I0017, with the `@ffi` note. C is too coarse: one `@ffi` line flips who owns a compiler bug. D leaves `redefinition of 'b_a'` for a dev who never wrote C. B is fine only where the build knows for sure (a named header that is missing); no parsing of `cc` text.
  >
  > **Q4: A.** E0857 and E0858 exist, so min's "no new code" holds. `.units.M13QDL/obj/__main__.o` is not an error message.
  >
  > **Q5: A (new position).** E0306 at `h(x)`, with help `[T: Sh]`. It is the same dev story as w1: the body's own bounds decide. Today's check 0, build ICE breaks the promise, and "prints 2 today" goes under Breaking Changes. The open P1 ticket "Unbounded typevar passed to a bounded generic fn is not E0306" carries it; this panel only classifies it inside. I also hold devops's shape: `g[T: Sized]`, `g(1)` is E0306 at the call.
  >
  > **Q6: B.** The gate owns the list. The spec states the promise only.
  >
  > **Q7: B.** Same flags. `tsc` against `tsc --strict`. Targets: one check answer, a target changes only the outside rows.
  >
  > **Other changes from Phase A.**
  > - I was wrong that the spec is silent on w3 and w4: sections/02_syntax.md:1330 allows them. Check 0, build 0, program runs.
  >
  > **For the writer.** Rerun the W0501 sweep from the repo root. Side finding: from tests/, a relative path gives `OrphanFile` "no enclosing blink.toml", though blink.toml is one level up. So check's answer depends on the working directory, and "same inputs" must say so or this needs a bug ticket.
  >

- **PLT:**
  > **Q1: B (changed from A).** `check_exit_code` (src/check_pipeline.bl:195) already returns 101 on an ICE, and I0021 exits 101. So "unchanged" is two meanings of an ICE today: check 101, build 1 (w2). B makes build match. The promise has one defect class, and it should have one signal. Against C: the E-code already separates setup from source.
  >
  > **Q2: A, with one rule for poison.** §6.3.3 says the compiler "reports an error". A warning is not that. I ran the three live W0501 files from tests/. Each exits 1 with other errors (53, 96, 3), and the sites read as cascades (`telemetry.record`, `Slot.Param(0)`). I did not trace each one to its root error. If so, §6.3.5 suppression should cover them:
  > - Poison receiver: no diagnostic.
  > - Unsolved, not poison: an error (E0505, or E0301 if that fires first).
  > Then W0501 has no case left. Lower bound only, so the sweep still runs.
  >
  > **Q3: A plus sys's preflight (changed from B).** Parsing cc text for blame is unsound, and aiml is right about that. Attribute by construction: test each named header before the unit compile, which gives a named E-code. A cc failure that remains is one I0017 with a note naming `@ffi`. This keeps the §8.10.5 vote. Limit: a wrong `@ffi` prototype gets a "compiler bug" code. The note must state this. Against C: a program with one `@ffi` loses the defect signal for every real bug.
  >
  > **Q4: A.** Measured: a missing `@ffi` symbol gives raw ld text and no code.
  >
  > **Q5: A. Do not split it from P0.** "Typed once at the definition" fails if `h(x)` is judged at each instance. Measured:
  > - `g[T]` forwards to `h[U: Sh]`, called with `P`: builds, prints 2.
  > - The same `g` called with `g(1)`: check 0, then ICE inside `h`.
  > A verdict that depends on the caller is the C++ model. So E0306 at `h(x)`, called or not, with help `[T: Sh]`. The first program breaks, and that needs a release note. …
  >
  > Also hold devops's shape. Measured: `g[T: Sized]`, `g(1)`: check 0, then ICE `Int.len`. That is E0306 at the call. It is a separate hole in the bound check, not a new rule, and I found no ticket for it in a title search.
  >
  > **Q6: B.** The spec states the requirement. `br` and the gate hold the list.
  >
  > **Q7: A for target, B for flags (changed in part).** My "any flags" was wrong: min's probe (check 0, `build --strict` 1) is correct behavior. `--strict` and `--strict-struct-layout` must match. Debug, release and trace do not matter. Every target is covered, because typing takes no target input.
  >

- **DevOps/Tooling:**
  > **Q1: B (0, 1, 101). Changed from C.** I drop exit 3: `@ffi("typo")` is a source edit, so "setup" is the wrong word for a link failure, and E0857 already names it. 101 is not new at check (`check_exit_code`); only a build ICE moves from 1 to 101. Exit 2 for a bad command leaves this ballot. It matches `blink test`, but the promise does not need it, so it gets its own chore.
  >
  > **Q2: A, delete W0501. Changed: I named only a type parameter before.** §6.3.3 says the compiler "never accepts the call without a check", and a warning with exit 0 is such an acceptance. Precondition: a legal program must not get the new error, or rule 1 breaks. See the fact below.
  >
  > **Q3: A, plus sys's header test before the unit compile, so a missing header gets a named code.** C is too coarse, and D leaves an agent no branch. **Changed:** my note "your code is not the cause" is false when the program has its own `@ffi`, so it prints only when the program has no `@ffi` of its own or native dependency.
  >
  > **Q4: A.** Measured: `blink build` gives raw `ld` text today.
  >
  > **Q5: A, E0306 at `h(x)`.** Measured both forms. `h[U: Sh]` with `impl Sh for Int` and `g(1)`: check 0, build 0, prints 2, so this breaks a working program and needs a release note. No impl: check 0, build ICE `Int.frob`. Rule 2 and the promise both require it. … **I also hold my B:** `fn g[T: Sized](x: T) -> Int { x.len() }`, `g(1)` is E0306 at the call. Measured: check 0, build ICE `Int.len`. The gate list needs that row, or a ticket of its own, since …
  >
  > **Q6: B. Changed.** No list in `sections/`: the spec states the rule. The gate owns the list. The release Known Limits text in `llms.md` stays as the user-facing report, and its line "A clean check means no error from lex through mono" must change.
  >
  > **Q7: B, same flags.** One answer across targets, with foreign causes outside.
  >
  > **Fact to re-measure.** The digest's W0501 hits did not reproduce for me. On all three named test files, by absolute path from my probe directory, `check --json` gives rc 0 and no `W0501` or `UnknownMethod`. Plain `check` on `test_cross_module_effects.bl` prints only `ok:`, and `--strict` also gives rc 0. A copy outside the tree gives E1010, so those files are sensitive to where they sit. If the sweep's hits are real, they are legal calls (`LimitValueError.UnknownUnit("k")`, `telemetry.record`), and the precondition in Q2 blocks the deletion until they resolve. Either way, the sweep needs to run again before landing.
  >

- **AI/ML:**
  > **Q1: B (0, 1, 101).** Exit code is what an agent's loop reads for free. A forces it to parse `--json` for an `I` prefix, and `check_exit_code` already uses 101. Against C: the E-code name already tells setup from source, so exit 3 adds a branch and no new action. Exit 2 is a separate topic.
  >
  > **Q2: A, changed from Phase A.** I held "keep it for a truly unknown receiver". I now say delete W0501, because neither use has value. On an invalid program it is the hole. On a valid program it is false noise an agent cannot act on. Measured: `telemetry.record("mem", 42)` in test_cross_module_effects.bl warns "receiver's type is not known", and that test passes. So do not flip it blindly: those 3 measured files, and any the sweep adds, are front-end faults in receiver resolution and must resolve first. Then a call with a truly unknown receiver is an error, as §6.3.3 says. Probe: `let f = fn(x) { x.frob() }` already has E0301 beside the warning, so that case loses nothing.
  >
  > **Q3: A, changed from C, with one condition.** My by-program split gives a real compiler bug exit 1 in any program with its own `@ffi`, and the agent then edits correct code. That was the failure I wanted to stop. Take sys's form: test each named header before the unit compile, and give a missing one a named error. A remaining `cc` failure is I0017, exit 101. The condition: the "check your `@ffi`" note prints only if the program has its own `@ffi` or native dependency, and it names them. A program with none gets a pure "stop" signal. The §8.10.5 vote sends a bad header to I0017 in `blink test`; if the pretest lands, it must apply to both commands and say that it changes that row.
  >
  > **Q4: A.** Raw ld text costs tokens and has no stable code to branch on.
  >
  > **Q5: A.** Measured: `g[T]` forwarding to `h[U: Sh]`, with `g(1)`, builds and prints 2; with `g("s")`, check 0 and build ICE. A body-typed-once rule with this hole leaves P0 false: an instance still gives a new failure. E0306 at `h(x)`, help `[T: Sh]`, machine-applicable. Release note for the form that works today. The open P1 ticket carries the work; this panel only records that the shape is inside the promise. I also hold devops's shape B (`g[T: Sized]`, `g(1)`: E0306 at the call): same class.
  >
  > **Q6: B.** The spec states the requirement. The gate and `br` hold the list. Spec text that lists current compiler faults goes stale and teaches a model that a bug is a rule.
  >
  > **Q7: B.** Same `--strict` flags; min's measurement settles it. For target, the front-end answer is one answer: supported targets change only the outside rows.
  >

- **Minimalism:**
  > No objection to P0 or P8.
  >
  > **Q1: B (changed from A).** My Phase A text was wrong. Check already exits 101 on an ICE (`check_exit_code`, src/check_pipeline.bl:195), and the I0021 row already says 101. So B adds no code. Only `blink build` disagrees (w2 exits 1). Align it. Reject C: exit 3 and exit 2 are new surface, and the error name already gives the cause.
  >
  > **Q2: A, with an order (refined).** W0501 goes. Both cases become E0505, as §6.3.3 requires. But the three sweep hits look like valid programs: `LimitValueError.UnknownUnit("k")`, `Slot.Param(0)`, `telemetry.record("mem", 42)`. The same variant shape in a package with no test block gives check 0 and build 0, with no warning, and a wrong name there is `NoSuchVariant`, not W0501. So these hits are front-end misses on a receiver, or sweep artifacts. I did not find which. E0505 must not land on them while they are valid. Order: stop the type-parameter case now (P0), resolve each remaining hit, then delete the row. I reject B: a "truly unknown receiver" warning keeps a hole in the promise. I have no probe of a W0501 program that is check 0 and build 1 outside type parameters, so the delete is a spec-consistency argument, not a measured failure.
  >
  > **Q3: A (changed from D).** I0017 and its §8.10.5 vote exist. `blink test` uses them. My "no new diagnostic" still holds, because this adds none. It makes one failure read the same in two commands. B and C add a classifier, and a classifier is new work with new wrong answers.
  >
  > **Q4: A (changed from B).** E0857 and E0858 exist, with one thing to change: "only `blink test` reports" goes. No new code. The raw `undefined reference` text I kept in Phase A then moves to `notes`.
  >
  > **Q5: A.** E0306 at the forwarding call, reached or not. It breaks a program that prints 2 today, and parametricity already forbids what that program does. … Devops' form (`T: Sized`, `g(1)`) is plain E0306 at a concrete argument, so I hold it too, as existing rule, with no ruling needed here.
  >
  > **Q6: B.** The gate owns the list. The spec states a requirement, and a list of its breaks goes stale in the file that training data reads as true.
  >
  > **Q7: B on flags; "any supported target" on target.** Section 07 already says check gives one result on every target, so the promise covers each target and the outside causes vary per target. `--strict` flags must match (measured).
  >
  > **Facts I accept.** w3 and w4 are legal under sections/02_syntax.md:1330, so they are lowering bugs. w2, w6 and w7 are in the spec (03_types.md:1764), so the fix is to build `Int.max`. My "either answer" text no longer applies to these.
  >
  > Surface result: no new exit code, no new error code, no new flag, W0501 removed, one paragraph of spec.
  >

#### Phase C — Silent ballot

Phase C put one question to a vote, Q3a, and listed the other items as settled. The ballot text for Q3a:

> **A** (sys, min): no test before the compile. The `cc` failure is I0017, exit 101, and the note names the header first.
> sys: "Header preflight comes off my proposal. It is a later improvement, and it would edit the §8.10.5 text, so it is not needed for the promise." sys: "a typo in a user's header gets I0017 and 101, so the note must name the header first."
> **B** (plt, devops, aiml): the build tests each named header before the unit compile, and a missing one gets a named E-code, exit 1. A `cc` failure that remains is I0017. aiml: "if the pretest lands, it must apply to both commands and say that it changes that row."
> web: "B is fine only where the build knows for sure (a named header that is missing); no parsing of `cc` text." Web, say A or B here.
>

Each seat voted alone. Tally: B from Systems, Web/Scripting, PLT, DevOps/Tooling and AI/ML; A from Minimalism. The ballots follow in full.

- **Systems:**
  > Q3a: B
  > Reasoning: This changes my round 1 position. I dropped the pretest because the promise does not need it, but A gives a missing header exit 101, and we settled that 101 means a compiler bug, so an agent stops and files a false report on a one-character typo. The build can know this fact for sure with no parsing of `cc` text, and `src/foreign_const_probe` shows that the compiler already has a probe for foreign constants, which gives the correct shape (`ForeignConstInvalid`, with a span). A rough `cc -E` run took about 10 ms or less here (I did not confirm it read a large header), so it is small against the C compile that follows it. The §8.10.5 I0017 text must change to match, for both `build` and `test`.
  > Concern: A pretest that runs with other include paths or flags than the unit compile gives a false E-code on a legal program, so it must use the exact `-I` set and target of that compile.
  > Objections: none

- **Web/Scripting:**
  > Q3a: B
  > Reasoning: A typo in `header: "sqlite.h"` is the most common FFI mistake a new dev makes, and under A it exits 101, whose settled meaning is "compiler bug, stop editing, report it". That sends the dev and any agent to the wrong branch for a one-word fix, and the bug tracker gets the Stack Overflow question. The build can know this case for sure with no parsing of `cc` text, because the header either resolves or does not, so a named E-code at the `@ffi` line, exit 1, is the same shape as E0855. A wrong prototype stays I0017, which is the honest limit.
  > Concern: The pretest can disagree with the real compile if it does not use the same include paths and flags per target and per native dependency, and then a valid program gets a false error; it must use the unit compile's exact flags and must state that it changes the §8.10.5 row.
  > Objections: none

- **PLT:**
  > Q3a: B
  > Reasoning: The promise splits failures into a foreign refusal and a compiler defect, and exit 101 means "do not edit your source". A missing named header is a foreign fact that the build can decide with no parsing of `cc` text, so a 101 here gives a false verdict where a true one costs little. This is attribution by construction, not a guess. The wrong-prototype case stays under I0017 because the build cannot decide it, so the note carries that limit.
  > Concern: The pretest can disagree with the real compile unless it uses the same C compiler, target and include paths, and it must apply to both `blink build` and `blink test`, with the §8.10.5 row changed to match.
  > Objections: none

- **DevOps/Tooling:**
  > Q3a: B
  > Reasoning: A missing header is a setup fault that the build can know for sure, so it should get a named code with a span on the `@ffi` line and exit 1. Under A, a typo in a user's own header path exits 101, and an agent reads 101 as "compiler bug, do not edit", which sends it the wrong way on the most common `@ffi` mistake. `ForeignConstInvalid` already gives this shape on a foreign `let`, so B makes one foreign form match another. B needs no parsing of `cc` text, because the test asks the compiler about one header and reads only pass or fail.
  > Concern: The test must use the same compiler, target and include paths as the unit compile (vendored `-I` dirs and the `--target` sysroot included), or it reports a false missing header on a program that builds, which is worse than the I0017 it replaces.
  > Objections: none

- **AI/ML:**
  > Q3a: B
  > Reasoning: A missing header is a setup fact, and exit 101 tells an agent "do not change your source, report a bug". Under A, a typo in `header:` gets that signal, so the agent's one stop rule is wrong in a common generated-code error, and a note must overrule the exit code. Models often guess header names, so this case is not rare. B keeps the branch clean: exit 1 with a named code that points at the declaration, and 101 means stop.
  > Concern: The test can disagree with the compile if it does not use the same C compiler, include paths and target, so a usable header gets a false error; it must ask the same `cc` with the same flags, and it must state its change to the §8.10.5 row and apply to `blink test` too.
  > Objections: none

- **Minimalism:**
  > Q3a: A
  > Reasoning: The promise does not need a header pretest, because a missing header is outside it under either option. B adds a second compile path that must find the same include dirs, per target and for vendored dependencies, or it gives its own wrong answers. It also reopens the §8.10.5 vote and adds a code for a case that has no reported user pain. If users hit the problem, B can land later as a pure narrowing of I0017.
  > Concern: A missing or misspelled header gets exit 101, so the "101 means compiler bug" reading is false for this one case, and an agent may file a bug and stop unless the note names the header first.
  > Objections: none

**Systems moved.** In Phase A and Phase B Systems chose A (no header test). Its ballot says: "This changes my round 1 position." Systems gave as the reason that exit 101 means a compiler bug, so a one-character typo in a header would send an agent to file a false report.

**Minimalism dissents.** Minimalism voted A and gave as the reason: "B adds a second compile path that must find the same include dirs, per target and for vendored dependencies, or it gives its own wrong answers. It also reopens the §8.10.5 vote and adds a code for a case that has no reported user pain. If users hit the problem, B can land later as a pure narrowing of I0017."

#### Phase D

Did not run. Q3a closed 5-1 in Phase C, and no seat objected to any settled item in its ballot ("Objections: none" in all six).

### Points Left Open

- §8.16.1 gives no clear rule for two changes in this decision: E0306 on a forwarded bound, and E0505 in place of W0501. The affected programs ran as written, which points to a warning first. The spec also says a generic body never had a method beyond its declared bounds, which points to an error at once. E0505 has no machine-applicable fix. The panel did not decide this. The owner of the Breaking Changes line must.
- A missing header is E0859, and E0855 also covers a bad foreign constant. The text says the header test runs first, so a missing header is E0859. The panel did not discuss `@ffi.opaque` and `@ffi.struct` headers.
- The panel did not decide whether the promise covers the build step inside `blink run`.
- No code or exit is set for a missing C compiler, a full disk or a removed file. A missing `cc` under I0017 would conflict with "101 means a compiler bug".
- The panel did not name the ICE for the code generation backstop. The catalog uses I0022.

### Facts From Other Languages

- Rust checks a generic body once, at its definition, against the declared bounds. A method call on an unbounded `T` is an error whether or not the function is called. Blink takes the same rule.
- `rustc` exits 101 on an internal compiler error and 1 on a program error. Blink uses the same split for check and build.
