[< All Decisions](../DECISIONS.md)

# Signed `MIN % -1` and the Remainder Definition — Design Rationale

**Gap:** "The true result is 0, which is in range, so the overflow rule at sections/03_types.md:781 does not reach it, but C leaves INT_MIN % -1 undefined and x86 raises SIGFPE. MVCE: let a: I32 = -2147483648; let b: I32 = -1; let r = a % b. Options: answer 0 (needs a guard in C) or panic like MIN / -1. The spec is silent."

**Result:** Q1 6-0 for A (`MIN % -1` is 0, no panic). Q2 6-0 for S-in (define `%` in the same edit). Phase B skipped (one option plus one rejected alternative after dedupe). No Phase D. AI-first review: 5/5 pass, so the unanimous fast path applied.

**Out of scope:** remainder by zero (`x % 0`) belongs to a sibling spec ticket. The new text is scoped to a non-zero divisor so it neither decides nor contradicts that ruling.

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated in independent-proposal → debate → vote rounds.

#### Phase A — Independent proposals

All six put the same option first: `MIN % -1` is 0. All six also stated the sign of the remainder (truncated, sign of the dividend). Every panelist listed "panic like `MIN / -1`" as the alternative; five rejected it, and Systems kept it as a fallback. Excerpts, verbatim.

- **Systems:**
  > **Our own rule already answers this.** §3 says an operation panics when its result "exceeds the type's range". The true result is 0, so no panic. A panic here would be a carve-out that exists only because x86 `idiv` faults. That lets one ISA's quirk into the language.
  >
  > **Only x86 is odd.** ARM64 `sdiv` gives MIN and does not trap, and `msub` then gives 0. WASM defines `i32.rem_s(MIN, -1) = 0` even though `div_s` traps. RISC-V `rem` gives 0.
  >
  > **Cost:** the backend needs a guard on x86 either way, so 0 and a panic cost the same. [...] If the divisor is a constant other than 0 or -1, which is most `%` in real code (`i % 2`, `h % 16`), there is no guard.

- **Web/Scripting:**
  > **Least surprise.** A JS or Python developer has never seen a remainder crash when the divisor is non-zero. The true answer is 0, and 0 fits in the type. A panic here would fail the "explain it in 5 minutes" test: "the math is fine, but it crashes because C's `idiv` traps?"
  >
  > **Proposal 1b (rider, I strongly recommend it): state the sign of the remainder.** The spec does not say whether `-7 % 3` is `-1` or `2`. For Python developers this is the biggest open question here, because Python floors and gives `2`.

- **PLT:**
  > **Denotation.** Each checked operator is the partial function `Z -> T` restricted to the inputs where the exact result is in range. That one rule gives `+ - * / abs pow`, and `%` follows with no exceptions. Under a panic answer, `%` would be the only operator that panics on an in-range result. Its domain would then depend on how the machine computes it, not on what it means.
  >
  > Rust panics, but its own `wrapping_rem` documents 0. The panic comes from LLVM's `srem` being undefined here, not from the semantics.

- **DevOps:**
  > **The message stays honest.** All Blink overflow messages say "result exceeds range". A panic for `MIN % -1` would need a message like "I32 overflow in remainder (-2147483648 % -1)", and that message would be false: 0 is in range.
  >
  > **The constant folder, LSP hover and runtime agree.** `const R: I32 = I32.MIN % -1` folds to 0 with no compile error.

- **AI/ML:**
  > **You can derive it from the rule that exists.** [...] A model that reads only the spec gets 0 today. A panic would need a special case on top of the general rule, and a special case is the kind of thing a model gets wrong unless it saw it in training data.
  >
  > **The real gap is wider than MIN % -1.** The spec never says which sign the remainder takes. [...] Models carry Python habits into new languages. If the spec does not pin this, models generate `% n` for indexing or wrap-around and get wrong answers on negative input, silently.

- **Minimalism:**
  > The answer comes from rules we already need, so we should not write a special case. The spec does have to define what `%` means, which it does not do yet. [...] Once `%` is defined, MIN % -1 needs no separate rule.
  >
  > **Things we should not add (YAGNI):** `wrapping_rem`, `checked_rem`: remainder cannot overflow, so these have nothing to do. `rem_euclid` or Python-style floored `%`: nobody has asked for them.

Cross-language facts cited by the panel: Go, Java (JLS 15.17.3), Python, WASM and Zig `@rem` give 0; Rust panics; C# throws `OverflowException`; C leaves it undefined.

#### Phase A.5 — Dedupe

- **Option A** (`MIN % -1` is 0): all six.
- **Option B** (panic like `MIN / -1`): listed as rejected by five, as a fallback by Systems.
- **Sub-point S-in / S-out:** state the remainder definition in this edit, or log it as a separate gap (DevOps: "If the panel thinks the sign rule is out of scope, keep only the `MIN % -1` sentence and log the sign rule as a separate gap").
- **Wording variation, flagged for the spec writer:** anchor `%` on the identity `a == (a / b) * b + a % b` (Sys, Web, DevOps, AI/ML) or define it directly as `a - b * trunc(a / b)` (PLT, Min).

#### Phase C — Final vote

- **Q1: `MIN % -1` is 0 (A) or panics (B)** — 6-0 for A
  - **Systems:** A — "ARM64, RISC-V and WASM all give 0 for this case. x86 alone faults, so a panic would build one ISA's fault into the language." *Concern:* "It must add the -1 guard only for a signed divisor that is not a constant. If it adds the guard to every `%`, hot paths pay for it. If it leaves the guard out, the current SIGFPE stays in the build."
  - **Web/Scripting:** A — "Python, JS, Java, and Go all return 0 here. A developer coming from any of them will not expect `%` to crash when the divisor is non-zero." *Concern:* "Users who know Rust may expect a panic [...]. The spec should name this case explicitly so nobody reads the 0 as a compiler bug."
  - **PLT:** A — "a checked integer operator must give its exact mathematical result, and panic only when that result is out of range. [...] Option B would make the rule for `%` depend on whether `/` overflows on the same operands." *Concern:* "if the spec writer anchors `%` on the identity [...], the text must still define the result at MIN, -1 directly, where `/` panics."
  - **DevOps:** A — "Each overflow panic says the result is out of range. With `MIN % -1`, the result is 0, which is in range, so a panic message for it would be false." *Concern:* "The spec change needs a corpus test that runs `MIN % -1` for I8, I16, I32 and Int, plus a const-fold test."
  - **AI/ML:** A — "Option B needs an exception clause that a model cannot derive. [...] With A, generated code also needs no `b == -1` guards and no extra `assert_panics` cases." *Concern:* "The spec example must show `I32.MIN % -1 == 0` explicitly so models learn this from the spec rather than from those habits."
  - **Minimalism:** A — "The overflow rule at line 828 already decides this case. [...] Option B would add an exception to that rule because of a C hardware trap." *Concern:* "Someone may read Option A as needing its own special-case sentence. It should not need one."

- **Q2: Define `%` in this edit (S-in) or split it off (S-out)** — 6-0 for S-in
  - **Systems:** S-in — "You cannot state '`%` never overflows' until you define what `%` computes [...]. Write the definition directly as `a - b * trunc(a / b)` over the mathematical integers. Do not anchor it to the `/` identity, because that identity has a hole exactly at MIN / -1." *Concern:* "Keep the phrase 'for a non-zero divisor' so that ticket stays open."
  - **Web/Scripting:** S-in — "Fixing `MIN % -1` while the basic sign rule stays unstated would be an odd half-fix, and it costs one sentence. For the anchor, I now prefer the direct definition." *Concern:* "The spec writer should include a negative-dividend example, such as `-7 % 3 == -1`, so the difference from Python is visible."
  - **PLT:** S-in — "'the true result is 0' means nothing until the spec defines what `%` computes. [...] The identity can then follow as a consequence that holds wherever `a / b` is defined." *Concern:* "Scope the definition to `b != 0` so it neither decides nor contradicts that ticket."
  - **DevOps:** S-in — "Splitting it off means a second ticket and a second panel for text that every panelist already agrees on." *Concern:* "Mixing the two could leave the divide-by-zero case unclear before [the remainder-by-zero ticket] rules on it."
  - **AI/ML:** S-in — "Python habits (`-7 % 3 == 2`) carry silently into generated code, and nothing panics to show the bug." *Concern:* "The spec writer should use the direct form [...] or give the identity only as a note 'where a / b is in range.' That is a change from the identity form I proposed in Phase A."
  - **Minimalism:** S-in — "One sentence that defines `%` is less spec surface than a special case now plus a second gap ticket later." *Concern:* "Leave out PLT's general sentence about every integer operator unless it replaces the text at line 828 instead of repeating it."

### Final Spec

```blink
let a: I32 = -2147483648
let b: I32 = -1
let r = a % b       // 0
let q = a / b       // RUNTIME PANIC: I32 overflow in division (-2147483648 / -1)
let s = -7 % 3      // -1: the sign of the dividend (Python gives 2)
let t = 7 % -3      // 1
```

- For a non-zero `b`, `a % b` is `a - b * q`, `q` the exact quotient truncated toward zero, over the mathematical integers (direct form, per the Q2 concerns).
- The remainder has the sign of the dividend, or is 0, and `|a % b| < |b|`. It is always in range; `%` never overflows.
- The identity `a == (a / b) * b + a % b` is a consequence where `a / b` does not panic, not the definition.
- `MIN / -1` still panics; `MIN % -1` is 0. Constant folding gives the same 0.
- No `wrapping_rem`, `checked_rem`, `rem_euclid`, or floored modulo (YAGNI).
- Remainder by zero stays with its own ticket.
- Where it lives: §3.6 *Integer Division*, with a pointer from §3.2 *Overflow behavior*.
