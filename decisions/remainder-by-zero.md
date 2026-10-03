[< All Decisions](../DECISIONS.md)

# Integer Remainder by Zero — Design Rationale

**Gap:** "sections/03_types.md:2282 says only 'Division by zero on integers is a runtime panic'; % desugars to Rem (03_types.md:2244) and the spec never names it. The compiler already panics with 'division by zero' for x % 0 (src/cg_expr.bl x_operator_needs_guard) and tests/test_assert_panics.bl pins that. MVCE: let z = 0; let r = 7 % z. Decide and state it in 03_types.md Integer Division, including the message text."

**Result:** Q1 6-0 for A (`/` and `%` panic on a zero divisor; the message contains `division by zero`; the rest is not specified). Q2 6-0 for D (a divisor known at compile time to be 0 goes to its own ticket). Q3 5-1 for YES (back-pointer in the `%` paragraph; Min dissent). Q4 4-1-1 for E1 in Phase C and again in Phase D (AI/ML voted E2, Min voted E0). AI-first review: 5/5 pass.

**Context:** decisions/signed-min-remainder.md defined `%` for a non-zero divisor and left the zero divisor to this ticket. The compiler already panics with `{Type} division by zero` for both `/` and `%`, so the decision needs no code change.

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated in independent-proposal → debate → vote rounds.

#### Phase A — Independent proposals

All six put the same option first: `%` by zero panics like `/`, with one shared message, and the spec pins only the substring `division by zero`. Min also offered a behavior-only variant (M2). On a constant zero divisor, four panelists proposed a separate ticket, Min proposed rejecting a compile error, and DevOps proposed a warning. Excerpts, verbatim.

- **Systems:**
  > **We cannot leave it undefined.** C makes `a % 0` undefined behavior. x86 `idiv` faults with SIGFPE, while ARM `sdiv` and RISC-V `rem` return a value and do not trap. If the spec said nothing, results would differ by target. A defined panic gives the same behavior on every target.

  > **No made-up value.** RISC-V gives `a % 0 == a`, which would let us drop the check. But it breaks the identity `a == (a/b)*b + a%b` where `/` panics, and it hides bugs. That is a bad trade for one predicted branch.

  On a constant zero divisor: "When the divisor of an integer `/` or `%` is a constant expression equal to 0, the compiler rejects the program." — kept out of this ticket: "It changes `/` as well as `%`. It breaks the §2.20 example `assert_panics { let _ = 10 / 0 }` [...]. It needs a new diagnostic code."
- **Web/Scripting:**
  > **Python users already know it.** Python raises one error for `/`, `//` and `%`: `ZeroDivisionError: integer division or modulo by zero`. Go's runtime error is `integer divide by zero` for both. Nobody will be surprised that `%` reuses the division message.

  > **Users can rely on it.** `assert_panics(matching: ...)` is a literal substring test, so users will match on this text. If the spec leaves the text open, every such test is fragile. Fixing three words gives users a stable hook.

  Proposed the back-pointer "For a non-zero `b` (a zero `b` panics, as above), `a % b` is ..." and the example line `let m = 7 % z       // RUNTIME PANIC: Int division by zero`.
- **PLT:**
  > `%` is defined by `a - b * q`, where `q` is the exact quotient truncated toward zero. When `b == 0` there is no `q`, so `a % 0` has no value. Integer `/` and `%` are partial on the same domain, `b != 0`, and the spec should treat them as one partial operation.

  > Making `%` total by typing the divisor as `NonZero[T]`, the way Agda and Idris use refinements, is the sound extreme. It needs refinement types on every `%`, which goes against the YAGNI decision already made. I reject it too.

  > **Cross-language.** [...] OCaml raises `Division_by_zero` for both `/` and `mod`. Haskell throws `DivideByZero` for both `div` and `mod`. The ML family names one failure for both operators, which supports one shared message.
- **DevOps:**
  > One string works with grep in logs, in CI output and in `assert_panics`. A user needs to remember only one pattern, whichever operator failed.

  > The cost: the message says "division" when the operator was `%`. When a line has both `/` and `%`, the message does not tell you which one failed. The source location tells you that, and so do operands if we add them later.

  Proposed a warning (not an error) for a literal `0` divisor: `warning[W0xxx]: this divisor is always zero; this expression always panics`, and "If the panel does not want a new warning now, record that the spec does not require one, so the §3.2 text does not suggest a compile error."
- **AI/ML:**
  > **One string to match.** `assert_panics(matching:)` is a literal substring test, so the model must guess the exact text. If the spec names the substring, a model can write a correct test from the spec alone. If it does not, the model guesses, and it guesses wrong at some rate.

  > Rust uses two messages, "attempt to divide by zero" and "attempt to calculate the remainder with a divisor of zero". Models that copy Rust will reach for a "remainder" substring. Our spec sentence must say outright that `%` uses the same text.
- **Minimalism:**
  > The compiler already does the right thing, and so do the tests. Only the spec is silent. The smallest fix is to add words to the spec and nothing to the language.

  > We fix only the substring that a user's `assert_panics(matching:)` can depend on. This follows the §4 handler-op rule ("contains `<handle>.<op>`; the rest is not specified"). It does not lock in the `{ty}` prefix (`Int`, `U8`), the word order, or the ` at file:line` suffix.

  M2 (behavior only): "On every integer type, if `b` is 0, `a / b` and `a % b` panic." On a compile error for a constant zero divisor: "A lint can add this later without a spec change. Removing a compile error later is a breaking change."

Rejected in Phase A by their own proposers: a separate `remainder by zero` message (AI/ML, Web, Sys, DevOps); `a % 0` returning a value (PLT, Sys, Web); a `NonZero[T]` divisor or an `Option` result (PLT, Sys).

#### Phase B — Debate highlights

One round. All six reported "stable, ready to vote". All six moved to wording (a) for Q1, including Web and DevOps, who had proposed (b).

- **Min** dropped M2: "Five other panelists want the substring fixed, and the §4 handler-op rule is good precedent." Min opposed both of Web's additions: "If the zero-divisor sentence comes right before the `%` definition, 'for a non-zero `b`' already reads correctly. The pointer repeats the sentence above it." On the example line: "Readers copy example comments as if they were the rule. This one shows the full text, `Int` prefix included, right after we said only the substring is fixed. If the panel wants an example anyway, I accept `// panics: division by zero`."
- **AI/ML** asked for the example comment to show only the pinned part: "Write it as `// RUNTIME PANIC: ... division by zero`, or keep `Int division by zero` and note that only the substring is normative. I prefer the first."
- **DevOps** withdrew the warning: "A warning is a lint and needs no spec text, so it does not belong in this decision. I will file it as a tooling ticket." DevOps asked that the separate ticket "handle the §2.20 example `assert_panics { let _ = 10 / 0 }`."
- **Sys** and **Min** answered the §3.2 concern. Sys: "§3.2 covers overflow in constant expressions, and a zero divisor is not overflow, so §3.2 does not imply a compile error." Min: "§3.2 covers *overflow*, and division by zero is not overflow, so the text needs no change."
- **Min** accepted deferral over rejection: "For this ticket, Q2-D and my Q2-R have the same effect: the spec stays silent and the compiler does not change." **PLT:** "a compile error makes fewer programs well-formed, and a later lint does not make anything sound. That argument belongs in the other ticket, though."

#### Phase C — Final vote

- **Q1: Behavior and message** (6-0, A)
  - **Systems:** A — "One predicted branch, already paid for `/`, gives the same behavior on every target, where C leaves `a % 0` undefined, x86 traps and ARM/RISC-V return a value. Fixing the substring costs nothing at run time and gives `assert_panics(matching:)` a stable target that existing tests already use." *Concern:* "Readers may treat the `{Type}` prefix as normative and match "Int division by zero", which breaks if codegen changes the prefix."
  - **Web/Scripting:** A — "`assert_panics(matching:)` is a substring test, so users will lean on the message text no matter what the spec says. Pinning three words gives them a stable hook and leaves the rest open." *Concern:* "users may match on the full `Int division by zero` that they see in practice, and those tests break if we later change the prefix."
  - **PLT:** A — "`/` and `%` share one domain, `b != 0`, so one sentence should state one rule for both. Pinning only the substring is the smallest contract that lets the spec's own `assert_panics(matching:)` examples work on any compiler." *Concern:* "someone may later read "contains `division by zero`" as freezing the whole current message, so reviewers should hold to "the rest is not specified"."
  - **DevOps:** A — "Pinning only `division by zero` gives one pattern for both operators to use in grep and tests, and leaves the compiler free to add the type, operands or location later. This matches the §4 handler-op precedent." *Concern:* "Users may match the full current text (`Int division by zero`) in tests, and those tests break if the compiler changes the prefix."
  - **AI/ML:** A — "When the spec names the substring, a model can write a correct panic test from the spec alone, with no guessing. One shared text for `/` and `%` means one fact to learn, not two." *Concern:* "models trained on Rust may still write `matching: "remainder"` for `%`, unless the examples clearly show the shared text."
  - **Minimalism:** A — "One rule covers both operators and adds no new string, and the compiler and tests already follow it. [...] M2 is smaller, but it leaves the most common use of `matching:` resting on behavior the spec does not promise." *Concern:* "Someone may later read "contains `division by zero`" as permission to add a separate remainder message that still contains that substring."
- **Q2: A divisor known at compile time to be 0** (6-0, D)
  - **Systems:** D — "Deferring keeps both directions open, and rejecting now would close one." *Concern:* "The follow-up ticket could sit forever while `7 / 0` compiles silently."
  - **Web/Scripting:** D — "A compile error also breaks the §2.20 `10 / 0` example and makes users write `let z = 0` to test a panic, which is a real learning-curve cost." *Concern:* "§3.2's "constant expressions" wording keeps making readers think a literal `/ 0` is already a compile error."
  - **PLT:** D — "it covers `/` as much as `%`. It needs its own deliberation, and it also needs a decision about the §2.20 `10 / 0` example." *Concern:* "the follow-up ticket may never get filed or decided, and literal `x / 0` then stays a silent runtime panic for good."
  - **DevOps:** D — "A lint warning needs no spec text, so tooling can add it at any time. Rejecting now decides that other ticket with no debate." *Concern:* "§3.2 ("catches overflow in constant expressions at compile time") will continue to suggest that `7 % 0` is a compile error."
  - **AI/ML:** D — "Rejecting the error now (R) is still a decision, made here without the proper review." *Concern:* "until that ticket closes, a model reading the §3.2 sentence on constant-expression overflow may expect `7 % 0` to be a compile error."
  - **Minimalism:** D — "For this ticket, D and R have the same effect: no new rule and no compiler change. D keeps this ticket on its single question. I will argue against a compile error in the later ticket." *Concern:* "The deferred ticket may pass a compile error through momentum alone."
- **Q3: Back-pointer in the `%` paragraph** (5-1, YES; Min dissent)
  - **Systems:** YES — "The zero case gets answered where the reader meets the "non-zero" condition." *Concern:* ""as above" could go stale if the paragraphs get reordered."
  - **Web/Scripting:** YES — "a reader who jumps straight to the `%` paragraph sees "for a non-zero `b`" and is left asking what 0 does. That is the exact question this ticket exists to answer."
  - **PLT:** YES — ""For a non-zero `b`" alone makes `%` look partial with the zero case left undefined. The pointer shows that the zero case is defined and that it is the same rule as for `/`."
  - **DevOps:** YES — "Readers (and an LSP hover that shows one paragraph) often land on the `%` paragraph directly."
  - **AI/ML:** YES — "Without the pointer, "for a non-zero `b`" reads as if a zero `b` were undefined behavior. It costs eight words and removes a wrong inference."
  - **Minimalism:** *(dissent)* NO — "The zero-divisor sentence comes right before the `%` definition, so "for a non-zero `b`" already reads correctly. The pointer repeats the sentence above it."
- **Q4: Example line** (4-1-1, E1; AI/ML E2, Min E0)
  - **Systems:** E1 — "It matches the format of the existing overflow line in the same block (`RUNTIME PANIC: I32 overflow in division ...`), and it shows what the compiler really prints." *Concern:* "Users may copy the full line into `assert_panics(matching:)` and fail if the prefix changes."
  - **Web/Scripting:** E1 — "E2's `...` looks like syntax to a newcomer. E3 breaks the format of the block. E0 hides the case the ticket is about." *Concern:* "a reader may take the `Int` prefix as normative."
  - **PLT:** E1 — "that line is an example of a full message, not a contract. Matching that format avoids a second comment style in one block." *Concern:* "readers may copy the `Int` prefix into `matching:` strings."
  - **DevOps:** E1 — "The example should show what the user actually sees, in the same format as the overflow line next to it." *Concern:* "Readers may treat the `Int ` prefix in the example as normative."
  - **AI/ML:** *(dissent)* E2 — "models copy example text exactly. E1 shows `Int division by zero`, which teaches the type prefix as if the spec pinned it, and that contradicts Q1-A."
  - **Minimalism:** *(dissent)* E0 — "E1 shows `Int division by zero` right after we said only the substring is fixed, so it teaches the opposite of the decision."

#### Phase D — Round 2 (Q4 only)

Triggered by the 4-1-1 result. No votes changed: 4-1-1 for E1.

- **PLT:** E1 — "The `MIN / -1` line in the same block already shows a full message the spec does not pin [...]. If that is a defect, the fix is one convention across all panic example comments, decided as its own chore. Giving one line in one block a different style does not fix it." *Concern:* "A follow-up should set one convention for every panic example comment."
- **Systems:** E1 — "If E1 teaches the wrong lesson, that line teaches it already, and E2 or E3 would make the two lines in one block disagree in format [...]. A model may copy E2's `...` into `matching:` exactly as written, and that never matches."
- **Web/Scripting:** E1 — "The first time a user runs `7 % z`, the terminal prints `Int division by zero`. People and models copy from real output far more than from the spec. Hiding the prefix in the spec does not stop that copying."
- **DevOps:** E1 — "the block already teaches "comments show sample output" and does not mean "comments are the contract". [...] The right defence is the normative sentence, which states the pinned part, and we have that."
- **AI/ML:** *(dissent)* E2 — "every E1 ballot names the same concern I have: readers will copy `Int ` into `matching:` strings. Precedent does not fix that, and models weigh the example more than the prose above it. [...] I hold my vote, and I will accept E1 if it wins."
- **Minimalism:** *(dissent)* E0 — "the overflow message has no fixed substring, and this one now does. A full example line placed right after "only `division by zero` is fixed" shows readers exactly the text they should not match on. [...] If E1 wins, I accept it."

### Final Spec

```blink
let z = 0
let m = 7 % z       // RUNTIME PANIC: Int division by zero

test "remainder by zero panics" {
    let z = 0
    assert_panics(matching: "division by zero") {
        let _ = 7 % z
    }
}
```

- On every integer type, `a / b` and `a % b` panic when `b` is 0.
- The panic message contains `division by zero`, for both operators. The rest of the message and the source location are not specified.
- The `%` definition reads "for a non-zero `b` (a zero `b` panics, as above)".
- The spec does not decide whether a divisor known at compile time to be 0 is a compile error. That question has its own ticket. §3.2's constant-expression check covers overflow, and a zero divisor is not overflow.
- No compiler change: codegen already emits `{Type} division by zero` for both operators.
