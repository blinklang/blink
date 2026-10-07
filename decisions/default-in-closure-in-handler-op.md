[< All Decisions](../DECISIONS.md)

# `default` in a Closure in a Handler Operation — Design Rationale

A closure written in a handler operation body could not use `default`. The compiler rejected it with `error[UnresolvedMethod]` (E0505), "`default` cannot be used inside a closure within a handler operation". §4.7.1 did not cover this case, and the panel on [`default` outside a handler operation](default-outside-handler-op.md) left it open, including the code. MVCE:

```blink
effect Audit { effect Log { fn record(msg: Str) } }

with handler Audit {
    fn record(msg: Str) {
        let f = fn() { default.record(msg) }
        f()
    }
} {
    audit.record("x")
}
```

The panel also had a measured fact with no spec rule (F3). In an op body of an inner `Audit` handler installed over an outer one, a direct `audit.record(...)` reached the outer handler. The same call in a closure that the body called reached the inner handler again, which gave unbounded recursion.

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated
in independent-proposal → debate → vote rounds.

#### Phase A — Independent proposals

- **Systems:** "Summary: keep the rejection with a new code E0545 `DefaultInClosure`. Also add a rule for F3 (handle calls inside an op body). The F3 fix removes a special case from codegen." On F3: "While a handler operation body runs, the effects that the handler handles are resolved as if that handler were not installed. A perform of effect E in the body, or in any code the body calls, uses the nearest handler of E installed outside this handler." Open question: "if Proposal 2 holds, is the 'installed over' slot only needed for `default` (depth 0, lexical)? I think yes, which means no closure ever needs the slot."
- **Web/Scripting:** "A closure inside an op body may use `default`. It captures the delegate when the closure is created." "A rule that bans `default` in every closure, escaping or not, will become a Stack Overflow question titled 'why can't I use default in a callback'." On F3: "A handle call to the effect root being handled, written in an operation body or in a closure within it, is equivalent to `default.<op>(...)`." Alternative B: "new `E0545 DefaultInClosureInHandlerOp`" … "B has no workaround that keeps the delegate reachable, so users are stuck."
- **PLT:** "Inside a handler operation body, `default` is an implicit binding of type `Delegate[E]`. Each call of the operation binds it to the handler this installation was installed over. Closures capture it like any other binding (§2.8)." "Let-extracting `default.record(msg)` into a closure, η-expanding it, or passing it to `list.for_each` must not change whether the program typechecks." Proposal A2: "For the dynamic extent of an operation body, the handler for that effect is masked. … This applies to direct performs, closures called during the body, and callee functions alike." "Masking must be pushed on op-body entry and popped on exit, including on panic and unwind." Fallback B: E0545 `DefaultInClosure`, "I do not recommend B."
- **DevOps:** "Keep the rejection and reuse E0544 with a closure-specific message." "The E0505 `UnresolvedMethod` code is wrong today. It tells the user that a method is missing, and `default.record` is not missing." On F3: "While a handler operation body runs, the handler being run is not in force for its own effect. … A closure that outlives the operation resolves its handle calls where it is called (§4.15.4)." P3: "I would add W-lint `handle-call-in-own-op` … The help says 'use `default.record(...)`; it states that you delegate'." *(DevOps resent P3 after a cut-off; it said the resend's cross-language note was condensed and the summary was new, not verbatim with the first send.)*
- **AI/ML:** "Add a new code, E0545, named `DefaultInClosure`. Do not reuse E0544 and do not keep E0505." "Capturing the enclosing handler adds decision points. Models must then know that `default` in a closure is lexically bound, while a handle call in the same closure is dynamic (§4.15.4)." On F3: "A handle call (`audit.record(...)`) performs the operation on the handler in force where the call is evaluated, in every position, including inside the body of an operation of that same handler."
- **Minimalism:** "Position: keep the rejection. Add no new code, no capture rule, no new surface." "A closure body, including a closure written inside a handler operation body, is not a handler operation body. `default` inside it is E0544, whether or not the closure escapes." On F3: "While a handler operation body runs, the handler's own effect resolves to the handler this one was installed over (or to none; see unhandled operations). This applies to every call that runs during the operation, including through closures." "Do not add a diagnostic for P2."

#### Phase B — Debate highlights

One round. Five of six reported stable after it.

- **Systems** moved Q2 from E0545 to E0544: "plt's framing is that `default` is well-typed only when the typing context carries δ_E. A closure body does not carry it. That is the same judgment E0544 already makes, so one rule gets one code." On Q1: "My objection is irreversibility. Rejecting now and allowing later is a compatible change. Capture first and rejecting later breaks code."
- **Web/Scripting** moved Q3 from Lexical to Mask: "My Q3-Lexical rule left callees uncovered, so `helper()` called from the op body that does `audit.record` would still recurse." Not stable: "I would move to Q1-R with Q2-Reuse only if the panel shows a workaround that keeps `lines.each(fn(l) { default.record(l) })` possible."
- **AI/ML** withdrew Q3-Uniform: "Recursion from a handler into itself is almost always a bug, and an unbounded loop is a poor result for a model's mistake." On Q2: "I accept E0544 as a fallback if the panel wants no new code. The condition would be that the message and help name the closure and show the hoist fix."
- **DevOps** dropped the lint: "Under Mask, `audit.record` and `default.record` in the op body mean the same thing, so a lint that tells people to rewrite one to the other is churn. I drop Q4-Lint, unless Mask loses."
- **Minimalism:** "Splitting codes by syntactic parent grows without bound (nested fn, spawn, loop body...)." "plt, your unwind point on Mask is correct. The spec should state that masking is popped on panic and unwind too."

#### Phase C — Final vote

- **Q1: `default` in a closure in an op body** (5-1, PLT dissent): reject in every closure (Q1-R)
  - **Systems:** Q1-R — "Under Mask, a closure called during the op body already reaches the outer handler through a plain handle call, so web's `lines.each(fn(l) { audit.record(l) })` stays possible."
  - **Web/Scripting:** Q1-R — "my condition for moving was a workaround that keeps `lines.each(fn(l) { default.record(l) })` possible. Q3-Mask gives one. The closure writes `audit.record(l)`, which reaches the outside handler while the op body runs." Concern: "an escaped closure that needs real delegation is still impossible to write."
  - **PLT:** *(dissent)* Q1-C — "Rejection makes `default` non-abstractable, because `lines.each(fn(l) { default.record(l) })` and let-extraction both fail, and `default` is not a value, so there is no hoist workaround." Concern: "I concede that Q1-R is the safe, compatible choice if the panel weights reversibility over compositionality."
  - **DevOps:** Q1-R — "Capture would type-check an escaped closure (F4) that panics later, and the LSP has no escape analysis to warn about it. Rejecting now and allowing capture later is compatible; the reverse breaks code."
  - **AI/ML:** Q1-R — "rejection is additive. It can be relaxed later without breaking code, but capture cannot be withdrawn without breaking code." Concern: "users who write `default` in a closure inside `each` will hit the error first and must learn that the plain handle call does the same thing there. The help text must say this."
  - **Minimalism:** Q1-R — "Capture also makes `default` the only lexically bound handler reference, and it needs a spec rule for how long the outer handler stays alive after both `with` blocks exit." Concern: "an escaped closure that wants to delegate has no way to do it, and users will ask for capture."
- **Q2: code** (6-0): reuse E0544 `DefaultOutsideHandlerOp` with a message that names the closure
  - **Systems:** "Splitting codes by syntactic parent grows without bound (nested fn, spawn, loop body)." Concern: "the current 'outside a handler operation' wording is false for a closure inside an op body, so the message and help must name the closure and show the fix, as aiml asked."
  - **Web/Scripting:** "a closure body has no delegation context, which is the same typing judgement E0544 already makes, so one rule gets one code."
  - **PLT:** "a closure body does not carry δ_E, which is the same typing judgement E0544 already makes." Concern: "If no fix exists, the message must say so."
  - **DevOps:** "One code gives one `blink explain` page and one place for the LSP to match." Concern: "If the E0544 message stays generic, users move the call instead of fixing the closure. Test the rendered text with a closure case."
  - **AI/ML:** "I move from E0545 to E0544. … My Phase B condition holds: the message and help must name the closure and not say only 'outside a handler operation'."
  - **Minimalism:** "A closure body does not carry the delegation context. That is the same typing judgement E0544 already makes, so one rule gets one code."
- **Q3: which handler a handle call on the op's own effect reaches** (6-0): Mask
  - **Systems:** "Direct calls, closures called during the body and callees then take one dispatch path, and the `slot_read` special case in `src/cg_eff.bl` goes away." Concern: "a closure that escapes the op resolves where it is called, so Mask does not cover it."
  - **Web/Scripting:** "one dynamic rule covers direct calls, closures called during the body, and callees."
  - **PLT:** "an op body runs in the context of the handler's installation point, as in Koka and OCaml 5 deep handlers." Concern: "a missed restore path would silently leave the handler masked after the op."
  - **DevOps:** "Q3-Lexical misses callees. Q3-Uniform leaves a trap with no diagnostic." Concern: "It needs a test for panic and for spawn."
  - **AI/ML:** "the rule is one sentence a model predicts correctly ('an op body does not see its own handler for its own effect')."
  - **Minimalism:** "It turns the F3 recursion into a codegen bug." Concern: "a missed pop path (async, spawn inside the body) would leave the handler hidden."
- **Q4: lint for a same-root handle call in its own op body** (6-0): none
  - **Systems:** "A lint that says to rewrite one as the other is churn." Concern: "the spec needs one sentence stating the equivalence."
  - **Web/Scripting:** "under Mask the two spellings are equivalent, so a lint that tells people to switch between them is churn."
  - **PLT:** Concern: "if Mask loses, the equivalence breaks and the question must be reopened."
  - **DevOps:** "One sentence in the spec stating the equivalence is enough (aiml)."
  - **AI/ML:** "One spec sentence stating the equivalence is enough."
  - **Minimalism:** "A lint would tell people to rewrite correct code."

#### Phase D — Round 2

Not triggered. Q1 was 5-1. The user approved the tally.

### AI-First Review

Pass on all five criteria (learnability, consistency, generability, debuggability, token efficiency). Debuggability passes only if the E0544 message names the closure and the help gives the handle-call fix, which the spec text shows.

### Final Spec

```blink
with handler Audit {
    fn record(msg: Str) {
        msg.split("\n").for_each(fn(l) { default.record(l) })   // E0544: inside a closure
        msg.split("\n").for_each(fn(l) { audit.record(l) })     // ok: reaches the outer handler
    }
} {
    audit.record("a\nb")
}
```

- `default` is valid only in a handler operation body itself. In any closure, escaping or not, it is E0544 `DefaultOutsideHandlerOp`. The message names the closure. There is no machine-applicable fix.
- While an operation body runs, its handler is not in force for the effect it handles. Every handle call made while the body runs (direct, from a closure the body calls, or from a function the body calls) reaches the handler that this one was installed over. Handlers of other effects stay in force.
- In an operation body, `audit.op(...)` and `default.op(...)` do the same thing.
- When the operation returns or panics, the handler is in force again. A closure that runs after the operation has returned uses the handlers in force where it is called (§4.15.4).
- No lint.
- Rejecting now leaves room to allow lexical capture later as a compatible change.
