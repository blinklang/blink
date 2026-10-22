[< All Decisions](../DECISIONS.md)

# Foreign Function Declared `-> Never` — Design Rationale

The `Never` ruling ([never-bottom-type.md](never-bottom-type.md)) left one follow-up: "State in the
FFI section whether the compiler trusts a foreign function declared `-> Never`." C can declare a
function `_Noreturn`, and a function so declared that returns is undefined behaviour in C. A
`-> Never` binding makes the call diverge in Blink's type system (§3.3), so a false claim breaks
the typing rule. The panel decided whether such a binding is legal, what gate covers it, and what
the compiler emits after the call.

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated
in independent-proposal → debate → vote rounds.

Facts surfaced to the panel by the moderator:

- **F1:** the compiler does not yet implement nameable `Never` nor the `! ()` row. The spec leads
  the compiler. No binding in lib/std declares an `@ffi` fn `-> Never`; `env.exit` is a compiler
  intrinsic.
- **F2:** the loop-tail ruling ([loop-tail-fallthrough.md](loop-tail-fallthrough.md) Q4, 6-0)
  allows `__builtin_unreachable()` only after a tail that the compiler proves diverges.
- **F3:** §4.6.3: outside a test, an uncaught panic ends the process and bypasses
  `exit()`/`close()`. Inside a test, the per-test boundary catches it, and `assert_panics` can
  match it. A *fatal runtime error* is "a fault the runtime cannot recover from: OOM, stack
  overflow, or foreign code that ends the process". §2.20: `unreachable()` is a panic.
- **F4 (given before the vote):** `Ptr[T]` takes a closed list that excludes `Never` (E0810,
  §9.1.1). An `@ffi.struct` field takes a closed list that excludes `Never` (E0812, §9.1.3).
  `Void` outside `Ptr[_]` is E0828, a rule for one type. The moderator found no general rule that
  limits `@ffi` parameter types to an FFI-compatible list. `H` and `Option[H]` (opaque handles)
  are legal `@ffi` parameters and returns.

#### Phase A — Independent proposals

All six proposed the same core, independently: `-> Never` is legal, the existing audit record and
pin cover it, and the compiler emits a trap after each call in every build. They differed on what
the trap is, on `_Noreturn`, on other positions of `Never`, and on tooling.

- **Systems:** "The Q4 rider (`__builtin_unreachable()` after a diverging tail) is safe because the
  *compiler proves* the divergence. An `@ffi -> Never` is a different case: the author claims it,
  and nothing proves it. Our own precedent gives `__builtin_unreachable()` only to proven
  divergence, so it must not apply here." Sys proposed a noreturn, cold runtime routine that "does
  not unwind and does not run a Blink `panic`, because the foreign side may have left the process
  in a broken state", printing `fatal[FfiNeverReturned]`. "Blink does **not** put `_Noreturn` or
  `__attribute__((noreturn))` on the C prototype it emits. If it did, gcc and clang would delete
  the trap as dead code." Rejected trap-only-in-debug: "a binding is often right on one libc and
  wrong on another ... That failure shows up in production, not in debug."
- **Web/Scripting:** "Rejecting `-> Never` only moves the trap into user code. ... If the language
  rejects a pattern and the fix is always the same two lines, the language should write those two
  lines itself." Proposed a panic that names the binding and its audit record, and a rule for
  binding authors: "Declare `-> Never` only when the function returns on no path. `execv` returns
  on failure, so it is `-> I32`, not `-> Never`."
- **PLT:** "Every `@ffi` signature is a postulate in the Agda sense ... A wrong `-> Int` gives a
  garbage value. A wrong `-> Never` breaks the typing rule itself." With a trap after the call,
  "`call; trap` diverges on every execution. The typing judgment `call : Never` is then true by
  construction." "An assumption must never feed `__builtin_unreachable()`." Rider: "In an `@ffi`
  signature, `Never` is legal only as the whole return type (E-`FfiNeverPosition`)."
- **DevOps:** "A false `-> Never` claim is the one FFI error that UB turns into an impossible bug
  report: the symptom shows up in code the compiler removed." Proposed a W0800 note, a
  `blink audit` category `ffi-never`, LSP hover text `diverges (foreign claim, audit LIBC-ABORT)`,
  and a companion `FfiNeverParameter` error.
- **AI/ML:** "Learnability, zero new decision points ('copy the C header': `_Noreturn void
  abort(void)` becomes `-> Never`)." Proposed `fatal[FfiNeverReturned]`, and proposed that "the
  compiler also emits the C prototype as `_Noreturn`. If the symbol really does not return, the C
  compiler removes the trap as dead code, so the check costs nothing."
- **Minimalism:** "The trap in this proposal is that wrapper, built in." "Defined behaviour is
  simpler to state than UB." "What this proposal does not add: no `@noreturn` attribute (the type
  says it), no new E/W code, no `audits.toml` field, and no change to the effect-row rules." If
  teaching text is wanted, a note on the existing W0800, "not a new code".

#### Phase B — Debate highlights

Phase A.5 left one core option (P) and five variations: V1 `_Noreturn` on the emitted prototype,
V2 panic or fatal stop, V3 `Never` in other foreign positions, V4 tooling surface, V5 guidance for
binding authors.

**V1.** Five panelists answered AI/ML. Sys: "cc cannot know whether the symbol really returns. It
only sees the attribute. With `_Noreturn` on the prototype, gcc and clang delete the trap whether
the claim is true or false." AI/ML moved: "sys, web, plt and devops are right, and I was wrong. My
claim that 'cc removes the trap as dead code' is the bug."

**V2.** The positions crossed over in round 1. Sys and AI/ML moved to panic; web, PLT and DevOps
moved to fatal.

- Sys: "I checked that argument and it does not hold. A C function that returns through the normal
  ABI keeps the callee-saved registers and the stack intact. ... §4.6.3's 'fatal runtime error' is
  for 'foreign code that ends the process'. This case is the opposite."
- AI/ML: "The process state is not the broken part. The foreign function returned normally; the
  broken part is our *claim*."
- Minimalism: "The whole case for P is 'the compiler writes the `unreachable()` the user would
  write by hand.' It follows that the trap should mean exactly that."
- PLT (round 1, later withdrawn): "Cleanup assumes the runtime's invariants hold, and a broken
  foreign axiom voids that assumption."
- Web (round 1, later withdrawn): "A lying binding is a bug at the foreign boundary, not program
  logic. Nobody should write `assert_panics` around it."
- DevOps (round 1, later withdrawn): "As a panic, the test runner would catch it and run cleanup
  over that state."

At the vote, all six chose panic. PLT: "In round 1, my case for a fatal stop rested on 'the process
state is broken', and sys has since shown that this premise is false."

**V3.** In round 1 sys, web, PLT, DevOps and AI/ML backed one `FfiNeverPosition` code. Minimalism
answered with F4-type facts: "`Ptr[Never]` is already E0810 ... An `@ffi.struct` field of type
`Never` is already E0812 ... `Str` or `List[U8]` as a parameter is the same gap. ... fix it with
one general rule." The moderator then gave F4 to all six, and four moved to B.

#### Phase C — Final vote

- **Q1: Option P core: legal, covered by the existing audit record and pin, trap after every call
  in every build; the compiler never treats code after the call as dead on the claim alone** (6-0)
  - **Systems:** A — "A trap after the call costs nothing on the correct path. The trap routine is
    noreturn, so the basic block still ends at the call and the optimizer learns the same fact it
    would get from trusting the claim." Concern: "a later 'perf' change could swap the trap for
    `__builtin_unreachable()` in release because it looks like the Q4 pattern. The ruling must say
    that Q4 does not apply here."
  - **Web/Scripting:** A — "Blink should write the trap that users would otherwise write by hand."
    Concern: "the spec must state 'trap in every build' plainly, so that a later optimization pass
    does not bring back `__builtin_unreachable()` on the claim alone."
  - **PLT:** A — "Emitting a trap after the call makes `call : Never` true by construction. The
    well-typedness of the program then no longer depends on the author being honest." Concern:
    "Codegen must emit the trap at every call path, including indirect calls through a function
    value whose type came from an `@ffi` binding."
  - **DevOps:** A — "A false foreign claim gives a stop that names the binding, not UB that shows
    up in code the compiler removed." Concern: "The rule needs a codegen test that checks the trap
    is in the release binary."
  - **AI/ML:** A — "A false claim fails loudly at the call site and does not cause silent UB far
    from the cause." Concern: "A model may read 'legal' as 'always fine' and declare `-> Never` on
    functions that return on some path, so Q8 must pass alongside this."
  - **Minimalism:** A — "The trap is the `unreachable()` every user would otherwise write by hand
    in a wrapper, built in once. A defined result is simpler to state than UB."

- **Q2: the C prototype Blink writes never carries `_Noreturn`** (6-0)
  - **Systems:** A — "cc reads the attribute, not the libc." Concern: "A test should check that the
    trap survives `-O2` against a stub that returns."
  - **Web/Scripting:** A — "A developer who reads 'Blink checks this' expects the check to be in
    the binary."
  - **PLT:** A — "`_Noreturn` lets cc delete the trap in exactly that case, which brings back the UB
    that Q1 removes." Concern: "The spec must say plainly that this is the C library's claim and
    outside Blink's guarantee."
  - **DevOps:** A — "With `_Noreturn` it deletes the trap whether the claim is true or false, which
    turns the check off in the one case it exists for."
  - **AI/ML:** A — "I withdrew my Phase A position."
  - **Minimalism:** A — "Keep this out of the spec text: it is a codegen chore, not language
    surface."

- **Q3: the trap is a panic, as `unreachable()`** (6-0)
  - **Systems:** A — "§4.6.3 uses 'fatal runtime error' for foreign code that *ends* the process,
    and here the foreign code did not." Concern: "a binding whose foreign side really does corrupt
    state before it returns would run `with` cleanup on that state."
  - **Web/Scripting:** A — "For developer experience the deciding fact is that a panic fails one
    test, while a fatal stop kills the whole test run."
  - **PLT:** A — "the uniform rule is the principled one: the compiler inserts the `unreachable()`
    the author would otherwise write by hand." Concern: "The panic message must name the binding as
    the fault."
  - **DevOps:** A — "a panic gives a stack trace and blames one test." Concern: "Someone may wrap a
    lying binding in `assert_panics` and treat that as proof the binding is fine."
  - **AI/ML:** A — "'A false `-> Never` acts as if `unreachable()` were written after the call'
    reuses a concept models already know."
  - **Minimalism:** A — "with no second kind of stop for one rare case."

- **Q4: the panic message starts with the stable name `FfiNeverReturned`** (5-1, Minimalism
  dissent)
  - **Systems:** A — "the name costs a few bytes of `.rodata`, and it gives crash logs and CI greps
    a fixed key."
  - **Web/Scripting:** A — "a stable name gives people something to search for in CI logs, crash
    reports and forums." Concern: "The spec should say whether other runtime panics may carry a
    code."
  - **PLT:** A — "the name labels the panic and adds no new run-time category."
  - **DevOps:** A — "A stable name is what people grep for in CI logs, crash reports and issue
    trackers."
  - **AI/ML:** A — "It can be the leading text of a panic message, so it does not conflict with
    Q3=A."
  - **Minimalism:** *(dissent)* B — "Panic messages have no stable codes today. One named runtime
    message for this case starts a new namespace for one rare fault. ... If runtime messages get
    stable names later, give them all names under one rule."

- **Q5: `Never` in other foreign positions: no `Never`-specific code; a general FFI-compatible rule
  goes to a separate ticket** (5-1, PLT dissent)
  - **Systems:** B — "From a codegen view, it is one missing rule, 'an `@ffi` parameter must lower
    to a C type', not a rule about one type." Concern: "a bare `Never` parameter could reach layout
    and produce an ICE where the user should get a diagnostic. The follow-up ticket must be filed
    before this ruling closes."
  - **Web/Scripting:** B — "A user is far more likely to pass a `Str` or `List[U8]` parameter by
    mistake than to write a `Never` parameter."
  - **DevOps:** B — "One general 'an `@ffi` parameter must be FFI-compatible' rule with one help line
    is a better diagnostic surface than a code for each type."
  - **AI/ML:** B — "A code that covers only one type is a second rule a model must learn."
  - **Minimalism:** B — "A bare `Never` parameter introduces no value, because the caller would
    have to supply one, so the function cannot be called but nothing is unsound." Concern: "codegen
    must decline it cleanly and not crash."
  - **PLT:** *(dissent)* A — "a type argument in return position, such as `-> Option[Never]`
    (opaque-handle `Option[H]` is legal per line 1512), lets C produce `Some(x)` with `x : Never`.
    That is an introduction form, which §3.2 forbids. Option B leaves this hole open until a
    general ticket lands. A rule for one type has precedent in E0828 for `Void`."

- **Q6: a note on the existing W0800 that states the claim; no new code** (6-0)
  - **Systems:** A — "The note must say 'if it returns, the program stops at the call', not
    devops's 'treats code after each call as dead'. That wording describes the UB model we
    rejected."
  - **Web/Scripting:** A — "an unaudited binding is where a wrong `-> Never` claim is most likely."
  - **PLT:** A — "If the note keeps the 'dead code' wording, it teaches the UB model that this
    ruling rejects."
  - **DevOps:** A — "Proposed wording: '`-> Never` claims `c_abort` never returns; if it does, the
    program panics at the call (`FfiNeverReturned`)'."
  - **AI/ML:** A — "it appears exactly when the author is about to write the audit claim."
  - **Minimalism:** A — "It adds text to a warning that already fires, at no surface cost."

- **Q7: leave the `blink audit` `ffi-never` category and the LSP hover out of the spec** (5-1,
  DevOps dissent)
  - **Systems:** B — "these are tooling choices with no effect on codegen or language meaning."
  - **Web/Scripting:** B — "they have no spec content, so they belong in a tooling chore."
  - **PLT:** B — "spec text should define meaning, not tool output." Concern: "tools may describe a
    foreign `-> Never` as 'diverges' with no sign that it rests on an assumption."
  - **AI/ML:** B — "nothing yet shows they are needed (YAGNI)."
  - **Minimalism:** B — "If a need appears, file them as a chore."
  - **DevOps:** *(dissent)* A — "§9.1 already specifies `blink audit` categories (`bytes-bridge`,
    `opaque-ffi-handle`, `ptr-store-param`), so there is precedent for this in the spec. ... If it
    does [lose], it should still be filed as a tooling chore and not dropped."

- **Q8: guidance for binding authors: declare `-> Never` only when the function returns on no
  path; bind `execv` with its real return type and wrap it in `Result[Never, E]`** (6-0)
  - **Systems:** A — "`execv` is the most common false claim, because it returns `-1` on failure."
  - **Web/Scripting:** A — "One sentence plus the pattern ... stops a whole class of bugs and costs
    almost nothing." Concern: "users may read the example as covering only `execv` and miss other
    functions that return on failure, such as `pthread_exit` stubs or a hooked `exit`."
  - **PLT:** A — "That uses `Never` as a type argument, as §3.2 intends, so one example teaches both
    points." Concern: "Readers may take the example to mean that any function that can fail returns
    `Result[Never, E]`, even when it returns a real value on success."
  - **DevOps:** A — "The same short form should go in the W0800 note."
  - **AI/ML:** A — "`execv` is the binding a model will get wrong: it is famous for not returning,
    yet it returns `-1` on failure." Concern: "A single example may not cover other conditional
    non-returners (`longjmp`-style or `pthread_exit` edge cases)."
  - **Minimalism:** A — "The example must stay short, or §9.1 grows a tutorial."

#### Phase D

Not triggered. Every result was 6-0 or 5-1.

#### User sign-off

The user approved the tally and widened the Q5 follow-up: the general FFI-compatible rule must
cover `@ffi` parameters, return types and type arguments, so that it closes PLT's `-> Option[Never]`
case.

#### AI-first review

5/5 pass. Learnability: one sentence ("as if `unreachable()` came after the call") reuses a known
concept. Consistency: the result type is a claim, as every other part of the signature is.
Generability: copy the C header, with one stated exception (`execv`). Debuggability: the panic
names the binding, the C symbol, the audit key and the call site. Token efficiency: no new
attribute or annotation.

### Final Spec

```blink
@ffi("c", "abort")
@trusted(audit: "LIBC-ABORT")
fn c_abort() -> Never ! ()

@ffi("c", "execv")
@trusted(audit: "LIBC-EXECV")
fn c_execv(path: Ptr[U8], argv: Ptr[Ptr[U8]]) -> I32 ! Process.Spawn, Env.Exit
```

- `-> Never` on an `@ffi` fn is legal. The existing `@trusted(audit: K)` record and pin cover it;
  no other gate applies.
- The compiler does not assume the claim. If the foreign function returns, the program panics at
  the call in every build mode, as if `unreachable()` came after the call. The loop-tail
  `__builtin_unreachable()` rule does not apply.
- The panic message starts with `FfiNeverReturned` and names the binding, the C symbol, the audit
  key and the call site. It is a panic, not a fatal runtime error.
- A noreturn declaration in a `header:` is the C library's claim, and Blink does not check it.
- W0800 adds a note when the binding declares `-> Never`.
- Declare `-> Never` only when the function returns on no path. `execv` keeps its real return
  type; its wrapper returns `Result[Never, E]`.
- `Never` is not FFI-compatible: `Ptr[Never]` is E0810 and a `Never` field is E0812.

### Open gap

PLT's `-> Option[Never]` case stays open until the general FFI-compatible rule lands. `Option[H]`
is a legal `@ffi` return for an opaque handle `H`, and §9.1 has no rule that rejects `Never` as the
type argument. Such a binding would let C produce `Some(x)` with `x : Never`, an introduction form
that §3.2 forbids. The follow-up covers `@ffi` parameters, return types and type arguments.

The general rule landed: see [FFI Signature Types](ffi-signature-types.md).
