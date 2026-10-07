[< All Decisions](../DECISIONS.md)

# `default` Outside a Handler Operation — Design Rationale

`default.op(args)` written outside any handler operation body reported `error[UnresolvedMethod]` (E0505) with the message "`default` is only valid inside a handler operation body". E0505 is the unresolved-method code. The problem is a context rule, not a missing method. §4.7.1 did not say what happens to `default` outside an operation. MVCE:

```blink
effect Audit {
    effect Log {
        fn record(msg: Str)
    }
}

fn log_it() ! Audit.Log {
    default.record("x")
}
```

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated
in independent-proposal → debate → vote rounds.

Facts the moderator gave the panel from the codebase:

- **F1.** `default` is not a lexer keyword. The compiler treats it as a contextual name: a local binding named `default` shadows it.
- **F2.** Three messages share E0505 today: `default` outside an operation (this ticket); `default` in a closure inside an operation (a separate open ticket, out of scope); `default` in a handler of a built-in effect with no handler operations ("not supported yet", out of scope).
- **F3.** Existing context-rule codes: SkipOutsideTest E0827, AssertPanicsOutsideTest E0833, ResultOutsideEnsures E1304, OldOutsideEnsures E1305, PtrOutsideFfiContext E0811. E0544 is the first free code after the effect block E0541-E0543.
- **F4 (Phase B).** §4.4: effect operations are called only through a handle, "always the lowercase form of the top-level effect name". For the MVCE the direct call is `audit.record("x")`. `Audit.Log.record("x")` and `Log.record("x")`, used in some Phase A help lines, are not valid Blink. The `handler Name for Effect { }` form used in some Phase A examples does not appear in the spec.

#### Phase A — Independent proposals

All six proposed a dedicated code, E0544. All six kept `default` a contextual name, kept shadowing by a local binding, rejected a machine fix-it, and left the built-in-effect case on its current code.

- **Systems:** "`default.op(args)` inside a handler operation compiles to an indirect call through the saved outer-handler slot. That slot exists only in the frame of a running handler operation. Outside such a frame there is no slot to call, so the compiler must reject the program. ... This is a static context rule, not name resolution. E0505 gives the wrong reason and sends the user to look for a missing method." Proposed `E0544 DefaultOutsideHandlerOp`.
- **Web/Scripting:** "A JS/Python developer who writes this has almost always mistaken `default` for 'the default implementation'. The help line corrects that belief. Without it, this error will generate Stack Overflow questions." Proposed `DefaultOutsideHandlerOp`, with "Proposal 2 (legal fallback): keep E0505, improve the message only", which web rejected.
- **PLT:** "`default` is not a value or a keyword. It is a distinguished form that is well-typed only when the typing context carries a delegation capability. ... Handler operation bodies introduce `δ_E`. No other construct introduces it. A `default.op(args)` form without `δ_E` in context is ill-formed (E0544)." On closures: "Do not merge the closure case into E0544. ... Reserve E0545 now and leave the decision to ph65bh."
- **DevOps:** "E0505 means 'method not found'. An LSP, or any tool that groups diagnostics by code, would treat this error as a typo or missing import. Its code action would be 'did you mean `x.method`?'. That is wrong here, because the fix is to move the call." Proposed `DefaultOutsideHandlerOp`; "offer no automatic fix. Replacing `default.op(...)` with a direct effect call changes semantics, because it re-dispatches to the innermost handler."
- **AI/ML:** "E0505 sends the AI to look for a missing method. This is a wrong lead, and the AI may then add a `record` method that already exists. A dedicated code removes that failure mode." Proposed `DefaultOutsideHandler`, E0544.
- **Minimalism:** "Keeping E0505 would be a valid 'do nothing' option. I reject it for one reason: E0505 sends the user to look for a missing method, and nothing there is missing. The codebase already has the precedent ... so a new code adds no new concept to the language." "Keep the existing message and help text. Only the code changes."

#### Phase B — Debate highlights

One round. All six reported "STABLE, ready to vote".

- **Name:** aiml moved to `DefaultOutsideHandlerOp`: "It is longer, but it says exactly what the rule is." plt: "A handler body can hold more than operations, and `default` is not valid in those other parts."
- **Help line:** aiml, devops, web and plt withdrew their Phase A snippets after F4. sys: "The handle call is not a guess, though. It is the only legal call form outside a handler. ... The snippet must be derived from the effect name in the diagnostic, or left out." min revised: "The two-way hint is a fact about what is valid, not a guess about intent, so I drop my objection."
- **Closures:** devops: "Outside any operation, `default` has no meaning. Inside a closure in an operation, `default` has meaning, but the closure may outlive the operation. That is a capture-lifetime rule, and a different fix applies." min: "I reject plt's proposal to reserve E0545 now, because YAGNI says to reserve nothing." plt set conditions: "It records nothing about the closure case except 'out of scope, see ph65bh'. It does not state that closures reuse E0544. E0545 is not claimed in the catalog."
- **Spec sentence:** plt offered the merged text that won Q4. sys and min rejected plt's extra note on E0505 for a shadowed binding in the spec: "That is normal member access on the user's binding and needs no spec text."

#### Phase C — Final vote

- **Q1: Code** (6-0 for A, E0544 `DefaultOutsideHandlerOp`)
  - **Systems:** A — "The rule is a static context rule. The compiler needs a saved outer-handler slot that exists only in an operation frame. The name should say 'Op', because the rule is about the operation body."
  - **Web/Scripting:** A — "The code should name the context rule, and the op body is the rule, not just any handler. A dedicated code gives `blink explain` and search a single hit."
  - **PLT:** A — "This is a static context rule, not a lookup failure, so it needs its own code. 'Op' states the scope exactly."
  - **DevOps:** A — "The name stays accurate when `default` appears in a handler but outside an operation."
  - **AI/ML:** A — "Keeping E0505 (C) points the AI at a missing method, which sends it the wrong way."
  - **Minimalism:** A — "A dedicated context-rule code matches the existing E0827 and E1305 pattern and adds one catalog row."
- **Q2: Help text** (C 4, B 2; went to Phase D)
- **Q3: Closure case** (A 4, B 1 sys, C 1 devops; went to Phase D)
- **Q4: Spec text** (5-1 for C, Minimalism dissent)
  - **Systems:** C — "It names the delegation form, says what `default` is not (a keyword), and states the shadowing rule in one place." Concern: "'Installed before it' can be unclear. It should refer to the handler that was installed over, in line with the existing help text."
  - **Web/Scripting:** C — "A reader sees the valid case before the error case, which matches how developers learn a feature." Concern: "'installed before it' is loose wording that could be read as lexical order and not as the dynamically enclosing handler."
  - **PLT:** C — "C states the positive rule first ..., then the error, then shadowing. That order matches how a typing rule is read. ... B restricts `default` to a receiver of an operation call, which the current compiler does not check."
  - **DevOps:** C — "It states what `default` does inside an operation, what happens elsewhere, and the shadowing rule, so the explain text can quote it."
  - **AI/ML:** C — "An AI can learn the whole rule from this one passage. B is close, but it leaves out what `default` does."
  - **Minimalism:** *(dissent)* A — "It is the shortest text that states the contextual-name fact, the valid scope, the error, and shadowing (through 'unshadowed'). C repeats the delegation rule that the spec already states."
- **Q5: Shadowed-binding note** (A 3, B 2, C 1; went to Phase D)

#### Phase D — Round 2

Q2, Q3 and Q5 were closer than 5-1. The moderator relayed each panelist's Phase C reasoning verbatim; each panelist gave a rebuttal and a final vote in one reply. Four Q4 voters had flagged "installed before it", so sys's fix went on the same ballot as amendment Q4-AM.

- **Q2: Help text** (4-2 for C: existing help + a snippet built from the real handle and op, prose fallback)
  - **Systems:** C — "The devops concern about nested effects is real, but it is a test of the builder, not a reason to drop the snippet."
  - **Web/Scripting:** C — "'through its handle' does not tell a new user what to type, and that is the case where a snippet helps most."
  - **PLT:** C — "A new user who does not know the handle form gets a concrete example from C, and B gives them only a description."
  - **AI/ML:** C — "the compiler builds the snippet only when the handle name comes straight from the call. In every other case it uses the prose from B. That keeps the failure path small and testable."
  - **DevOps:** *(dissent)* B — "Static text needs no compiler logic. It cannot go stale, and a wrong snippet is a worse result than no snippet." "I accept that C with a fallback to B is workable, so I will not block it."
  - **Minimalism:** *(dissent)* B — "Static prose is the easiest text to keep correct and test, and it guesses nothing about intent." "If C wins, I ask for one condition: the snippet code must have a test that checks the fallback to B."
- **Q3: Closure case** (6-0 for A: record nothing beyond "ph65bh decides, including the code"; reserve no code)
  - **Systems:** A, moved from B — "I treated 'closure' and 'outside' as one rule, and that may not hold if closures become legal or get a different capture rule. Recording nothing costs us no work."
  - **DevOps:** A, moved from C — "The closure case may turn out legal, and then a reserved code is dead."
  - **Web/Scripting, PLT, AI/ML, Minimalism:** A, unchanged. plt: "If ph65bh allows closures, that cause disappears, and the closure case needs no code. If ph65bh forbids them, it can choose then whether to reuse E0544."
- **Q5: Shadowed-binding note** (4-2 for A: one line in the E0544 explain text; no spec text)
  - **AI/ML:** A, moved from C — "The spec text of Q4 C already says a local binding shadows `default`, so the rule is in the spec."
  - **Minimalism:** A, moved from B — "web's concern is correct: the user who shadows `default` meets E0505, so one line in the E0544 explain text is the only place that can reach them."
  - **DevOps:** A — "I would also support adding the same line to E0505."
  - **PLT:** A — "That is a reason to put the one line in the E0505 explain text too, if the panel wants it."
  - **Web/Scripting:** *(dissent)* B, moved from A — "a note in E0544's explain would not be read by a user who sees E0505."
  - **Systems:** *(dissent)* B — "`default.x` on a user binding is ordinary member access with the ordinary E0505."
- **Q4-AM: "installed over"** (6-0 Yes) — plt: "'Installed before it' could be read as lexical order, which would be unsound."

The user signed off on the tally as voted.

### AI-First Review

Learnability, consistency (the `XOutsideY` context-rule family), generability, debuggability and token efficiency: 5/5 pass.

### Final Spec

```blink
fn log_it() ! Audit.Log {
    default.record("x")   // E0544 DefaultOutsideHandlerOp
}

fn log_it_fixed() ! Audit.Log {
    audit.record("x")     // the call through the handle
}
```

- `default` is a contextual name, not a keyword. In the body of a handler operation, `default.op(args)` delegates to the handler that this operation's handler was installed over. Elsewhere, an unshadowed use is `DefaultOutsideHandlerOp` (E0544). A local binding named `default` shadows it.
- The message stays "`default` is only valid inside a handler operation body". The first help line stays. A second help line shows the call through the handle, built from the call; where the compiler cannot build it, a prose line says to call through the handle or move the call into a handler operation. No machine-applicable fix.
- `blink explain E0544` has one bad and one good example in the spec's real forms, and one line: with a `default` binding in scope, `default.x` is ordinary member access, and a missing member is E0505.
- `default` in a closure inside a handler operation is not decided here. Its own ticket picks the rule and the code. No code is reserved.
- `default` in a handler of a built-in effect with no handler operations keeps its current code.
