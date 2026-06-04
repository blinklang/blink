[< All Decisions](../DECISIONS.md)

# `assert_panics` Semantics & Form — Design Rationale

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated
in independent-proposal → debate → vote rounds. Resolves spec gap `q9cv25` — the deferred Q4
from the std.testing-user-api panel (`decisions/std-testing-user-api.md`), whose `cbk2wq`
follow-up was closed without a decision file ever landing. Error codes E0831–E0834 had been
pre-allocated by chore `pt1f33` anticipating a block form with `matching:`; this deliberation
is what actually resolved the semantics those codes presume.

**A verified codegen fact reframed the entire question and was surfaced to the panel during
Phase B (as a fact, not a vote):** real `panic()` today lowers to inline
`fprintf(stderr, "panic:..."); exit(1)` — a hard process termination. Only *assertion-failure*
panics `longjmp` to the runner's `setjmp` frame (`bootstrap/runtime_test.h`). So the per-test
runner frame does **not** catch real panic; "reuse the existing frame" was impossible, and any
in-process `assert_panics` requires retargeting `panic()` to a conditional longjmp. This fact
moved both PLT and Minimalism off their Phase A positions.

#### Phase A — Independent proposals

- **Systems:** Two proposals. Primary SYS-1: `assert_panics` as a compiler-recognized block that installs a nested `setjmp` frame and retargets `panic()` to `longjmp` via a thread-local `__blink_panic_armed` counter — *"today panic emits `fprintf; exit(1)` unconditionally. SYS-1 makes that emission conditional on a thread-local depth counter... Outside tests: literally zero overhead... `__builtin_expect(__blink_panic_armed, 0)`... gcc `-O2` will hoist the armed check."* On cleanup: *"any `with` binding opened inside the body has its `__attribute__((cleanup))` destructor fire during the longjmp unwind... Resources opened inside the body are cleaned up with ok=false; the panic is then consumed as test success."* Fallback SYS-2: tests-only `__blink_test_catch` intrinsic (but *"passing the body as a `fn() -> Unit` closure value means it monomorphizes/heap-allocates a closure env per call and defeats the inline-cleanup story... I prefer SYS-1"*). Rejected SYS-3 (subprocess): *"~1000x the cost of SYS-1's inline setjmp."*
- **Web/Scripting:** Primary W1: *"`assert_panics` as a compiler-recognized BLOCK form, tests-only, NOT an expression that returns the panic value... the moment a dev can name the captured `PanicInfo`, they will try to `return` it, store it, branch on it — and then we're in (c)/(d) territory."* Cross-language: *"pytest: `with pytest.raises(ValueError, match='divide by zero')`... even pytest's common use ignores the bound `excinfo`; `match=` covers most needs."* Rejected (c)/(d)/(e): *"The status quo is a real wart. Every mainstream framework has `toThrow`/`raises`/`assertThrows`."*
- **PLT:** Three proposals; primary P1 with a formal typing rule. *"The deciding criterion is not 'is there a second catch frame at runtime'... but 'does any user-written expression acquire a type that is inhabited by 'panic happened'.' If no user expression's type witnesses the panic, `panic: Never` survives verbatim."* On the construct: *"The whole construct has type `Void`... no `Result`, no `Bool`, no `PanicInfo` handed back."* Disqualified (c) on PLT grounds: *"It is `catch_unwind` with a Blink hat on... `let r = catch_panic(fn() { panic('x') })` binds `r: Result[T, PanicInfo]`, a typed witness of divergence in ordinary scope."*
- **DevOps:** Primary Proposal 1, block form, honoring the catalog. Decisive parsing fact: *"Blink has NO trailing-closure sugar. Closures are explicit `fn() { }` values... A bare `{ }` is a block, not a closure... A closure here would be the ONLY place in the language where `{ }` immediately after a `(` is a closure rather than a block."* Substring matching: *"Rust `#[should_panic(expected='...')]` is substring; its known weakness is that a too-loose substring silently passes on the WRONG panic... I deliberately pick Rust's substring over pytest's regex: the failure output mitigates Rust's weakness by ALWAYS printing the full actual message."* Ship-gate: *"the test suite must include a golden-output test showing the actual power-assert rendering... If the rendering is just 'assertion failed', we have a regression dressed as a feature."*
- **AI/ML:** Primary Proposal 1, block form with optional `matching:`. *"The block form maps 1:1 onto the two dominant patterns in the training corpus: pytest `with pytest.raises(ValueError): ...` and Rust `#[should_panic(expected = '...')]`."* On decision-point minimization: *"the decision tree the LLM faces collapses to: 'wrap the panicking statements in `assert_panics { }`; if you care about the message, add `matching: 'substr''.' That's it. ~2 nodes."* On the fence: *"(c)/(d) don't just risk unsoundness; they actively teach the LLM the wrong idiom and that idiom will metastasize through the training-data-as-this-codebase loop."* Reversed an earlier "magic module precedent" worry from the std.testing panel.
- **Minimalism:** Primary MIN-1: reject in-process, ship `testing.expect_panic(fn)` over `process_run`. *"the language CAN already express it, and our own suite proves it... `src/compile_test_helpers.bl` already captures panics."* Identified the load-bearing fact: *"in-process panic capture... requires a second catch site inside the test — that is a new R3 boundary, full stop. Polling cannot give you that."* Fallback MIN-2: document raw `process_run`, ship nothing. Hard NO on (b): *"this is the maximal spend... and it requires the second in-process catch site, i.e. it breaches the R3-fence the panel spent a whole deliberation building."* Noted the pre-allocated codes were *"cart before horse"* and should be deleted under a reject.

#### Phase A.5 — Mechanical dedupe

Distinct options: **B** (compiler-recognized block, valueless, test-only, no-nest, optional `matching:`, in-process) proposed by 5; **A** (same surface, named `__blink_test_catch` intrinsic) as several fallbacks; **E-sub** (stdlib `expect_panic(fn)` over `process_run`, delete E0831–34) by min; **E-doc** (reject, document `process_run`) min fallback. **C** (`catch_panic -> Result`) and **D** (panic as effect) proposed by nobody and explicitly rejected by all six. Flagged variations for debate: V1 block-vs-closure; V2 does B breach the fence; V3 `matching:` present/semantics; V4 exit()/close() on expected-panic.

#### Phase B — Debate highlights

- **Systems** conceded V1 and refined the fence position: *"min is RIGHT about the mechanism, WRONG about the conclusion... Arming `panic()` to conditionally `longjmp` adds a real, second `setjmp` landing pad... I won't pretend otherwise. [But] the fence is a statement about what user code can rely on and reach, not about how many `setjmp`s exist in the emitted binary."* Made the §4.6.3 sentence a hard condition: *"I will not vote for B without [PLT's explicit clarifying] sentence — min's reading is too defensible to leave to intent."* Added a concrete spec item: *"the trace `unwind_reason` enum needs a new value — `panic_caught` — distinct from `panic_uncatchable`."*
- **PLT** conceded the Phase A premise was false and corrected the soundness argument: *"My Phase A leaned on 'the per-test frame already catches panic, so assert_panics adds an instance, not a kind.' The verified codegen fact refutes the premise... I withdraw the 'same kind, new instance' claim. It was built on a false premise about the codegen, and I will not defend a soundness argument whose load-bearing step is factually wrong."* Held the line on types: *"the fence is a TYPING fence... Rust's `Drop`-on-unwind and `catch_unwind` use the same underlying unwind runtime. The mechanism is shared. Yet `Drop` keeps `!` reasoning sound and `catch_unwind` breaks it. The difference is not the mechanism — it is that `catch_unwind` has type `-> Result<R, Box<dyn Any>>`... P1 is the `Drop` side of that line."* Corrected the exit()/close() re-evaluation: *"the re-evaluation clause DOES fire... must be written into §4.6.3 as a new row... I was wrong in Phase A to call it vacuous."*
- **Minimalism** moved from dissent to a conditional yes: *"This is NOT a hill. I move my vote."* Conceded soundness: *"I authored the 'we don't ship sugar' line in that very decision; I can't now pretend an analogous compiler-internal mechanism is illegitimate. If it's sound there, it's sound here."* Retracted the cost claim against B: *"my subprocess re-entry plumbing is NOT smaller than B... closures over a live DB handle/temp dir can't be reconstructed across a process boundary (Blink has no closure serialization)... B wins on cost for the common case."* Set conditions: honest fence amendment (*"NOT the false claim 'the runner already caught panic''*), the V4 cleanup row (*"non-negotiable; else we reintroduce the transaction-leak bug the blockhandler decision killed"*), no-nest + per-test concurrency scope, substring-only, and wire (not delete) E0831–34.
- **Web/DevOps/AI-ML** accepted the conditions. DevOps added a precedence refinement: *"a panic raised by exit(false) during that unwind is a HANDLER fault and should surface as a SEPARATE failure record (top-level `panicked`, not folded into the assert_panics assertion record)."* AI/ML withdrew its B-minimal fallback: *"sys and min convinced me... a panic-presence-only assert is a false-negative generator... Substring-only means the LLM's most natural generation (`matching: 'division by zero'`, a literal copy of the panic text) is exactly right every time. The simplest semantics is also the most generable one."*

#### Phase C — Final vote

All four questions **6-0**. No Phase D (no result closer than 5-1).

**Q1 — Top-line form (6-0 for A = Option B-full):**
- **Systems:** A — *"the only in-process option, and in-process is the systems-correct answer — `setjmp` per assertion is ~20 register stores on the cold path versus subprocess fork+exec at ~1000x the cost."*
- **Web/Scripting:** A — *"only in-process block form gives pytest.raises/toThrow parity — assert this expression panics in this test, no subprocess/fixture."*
- **PLT:** A — *"the only form that keeps `panic: Never` sound while delivering in-process expressivity — divergence is never reified into a user-typed value, the boundary is runner-owned, and the user-extensible catch set stays empty."*
- **DevOps:** A — *"Only A gives a structured, in-process failure with power-assert-grade rendering... C/D (process_run) yield an exit code, not a structured failure."*
- **AI/ML:** A — *"maps 1:1 onto the dominant corpus patterns... collapses to ~2 decision nodes... stays syntactically inert outside `test` (E0833)."*
- **Minimalism:** A — *"I was the lone E-sub dissenter, but the verified codegen fact dismantled my cost argument... the in-process block adds bounded, test-only surface and is the only option that actually covers the common case."*

**Q2 — Body surface (6-0 for bare compiler-recognized BLOCK, not a reified `fn` value):**
- **Systems:** *"A `fn()` closure forces the longjmp through a real activation record and materializes a closure env per assertion for zero benefit, whereas a bare block puts the `setjmp` landing pad in the same frame as the `with` bindings."*
- **PLT:** *"a user could bind it (`let g = the_fn`) and hold a value whose invocation is panic-catchable, which leaks the recovery capability... This is load-bearing for soundness, not aesthetics."*
- **DevOps:** *"a closure form would be the language's only `({ })`-is-a-closure exception, breaking fmt/LSP/reader disambiguation."*
- **Web/AI-ML/Min** concurred — block reads as a directive (web), carries no first-class-catch connotation (aiml), removes a degree of freedom (min).

**Q3 — `matching:` (6-0 for (a) optional substring keyword):**
- **Systems:** *"our panic messages are compiler-emitted strings with volatile `at file:line` suffixes; substring matches the stable part and ignores the suffix, while exact match would force users to encode locations and regex drags an engine into the test runtime header."*
- **AI/ML:** *"a literal substring is exactly what the model naturally copies from the panic text — most-generable AND most-correct. Regex is a hallucination magnet."*
- **Minimalism:** *"Substring is the minimal form that adds zero grammar — it's an ordinary `Str` arg, not a sub-language... If it grows grammar, I revert to dissent."*
- **Web/PLT/DevOps** concurred (substring is the dominant mental model; binds nothing into scope; needs no engine).

**Q4 — V4 / R3-fence combined resolution (6-0 YES):**
- **PLT:** *"states plainly that the catchable-unwind set is EXTENDED (conceding the new mechanism min correctly identified) while proving `panic: Never` survives because the construct is Void and the body is not reified... I endorse it without reservation."*
- **Systems:** *"states plainly that the construct EXTENDS the catchable-unwind set rather than pretending the runner already caught panic, which is false at the C level."*
- **Minimalism:** *"the honesty preserves the fence's meaning for future deliberations, and the handler-runs rule prevents re-introducing the transaction-leak bug... With this YES I do not revert to dissent."*
- **Web/DevOps/AI-ML** concurred — cleanup parity with `with pytest.raises` (web), worse-than-subprocess surface without it (devops), intra-corpus-consistent with `with mock_db` (aiml).

**Concerns flagged (carried into the implementation ticket):** thread-local armed state (flagged by sys, plt, web, aiml, min); `__builtin_expect` zero-cost CI guard (sys); cleanup asymmetry documentation (plt); E0824 handler-fault as a separate record (devops, plt); `panic_caught` trace reason (sys, devops, aiml); substring-only spec sentence (min, aiml, devops, web); golden-output ship-gate for E0831/E0832 (devops); pass-consumes-panic status (devops, web).

### Final Spec

```blink
test "division by zero panics" {
    assert_panics {
        let _ = 10 / 0
    }
}

test "unwrap on empty list panics with the expected message" {
    assert_panics(matching: "index out of bounds") {
        let xs: [Int] = []
        let _ = xs.get(0).unwrap()
    }
}

test "rolls back on the expected panic" {
    assert_panics(matching: "insufficient funds") {
        with db.transaction() {
            force_withdraw(acct, 9999)   // transaction.exit(ok=false) runs → rollback
        }
    }
}
```

Locked design points:

- `assert_panics` is the fifth test assertion — a **compiler-recognized block**, not a function and not a closure value. The body is a `{ ... }` block (operand-only), never a reified `fn`.
- The construct is **valueless** (type `()`). No `PanicInfo`/`Result`/`Bool` is bound; you cannot write `let x = assert_panics { ... }`.
- Optional `matching: Str` is a **literal substring** test on the panic message — not a pattern/regex language, and it will not grow metacharacters.
- **Test-only** (E0833 outside a test) and **non-nestable** (E0834), enforced at parse/typecheck. Like `skip()`.
- Runtime failures: **E0831** (body returned without panicking — includes a `?`-propagated `Err` that exits without panicking) and **E0832** (message lacks the substring; renders expected substring + full actual message + panic-origin location).
- A passing `assert_panics` **consumes** the panic: test status `"pass"`, not `"panicked"`. Top-level `"panicked"` is reserved for unexpected escapes.
- The expected panic is a **catchable unwind** (§4.6.3): in-scope `with`/`Closeable` resources opened inside the block run `exit(false)`/`close()` before the runner records the pass. This is the only place a `panic` unwind runs cleanup; an unexpected (unarmed) panic still terminates and bypasses cleanup.
- **R3-fence (honest framing):** `assert_panics` *extends* the catchable-unwind set with a compiler-managed, test-only, no-user-nameable-symbol boundary. It does NOT extend the *user-reachable* set (still empty); `panic: Never` is preserved because the construct is `()` and the body is not reified. Armed state is **per-test (thread-local)** — normative.
- E0831–E0834 are wired (not deleted); the catalog was minted for exactly this shape.

### AI-First Review

Scored against the five criteria:

1. **Learnability** — Pass. Block form maps 1:1 onto pytest `raises` / Rust `#[should_panic]`; extends the `assert_*` family and the test-only `skip()` precedent.
2. **Consistency** — Pass. Same operand-only discipline as `assert_matches`; test-only like `skip()`; `matching:` keyword mirrors the optional-message precedent.
3. **Generability** — Pass. ~2 decision nodes; literal substring is what an LLM copies from the panic text; test-only gate stops it leaking into production generations.
4. **Debuggability** — Pass. E0831/E0832 render expected-vs-actual + panic-origin location; `panic_caught` trace reason distinguishes consumed from fatal panics.
5. **Token Efficiency** — Pass. Far cheaper than the subprocess status quo; `matching:` is pay-for-what-you-assert.

0 fails — proceed.
