[< All Decisions](../DECISIONS.md)

# Overflow in Literal Arithmetic Outside Const Contexts — Design Rationale

**Gap:** "Spec: is a constant expression in a let initializer a compile error when it overflows (let bad: I8 = 127 + 1)? §3.2 says 'the compiler also catches overflow in constant expressions at compile time' and marks 'let bad: I8 = 127 + 1' COMPILE ERROR, while the constant-zero-divisor decision makes 'let a = 10 / 0' compile (runtime panic + W0704). Decide what 'constant expression' means outside the four §2.21 const contexts. Keep two cases apart: 'let b: U8 = 300' (a literal that does not fit the type: a typing question) and 'let bad: I8 = 127 + 1' (an evaluation question). Related bug: [the literal-binop typing bug] (the checks are spec-only today). Panel side item S2, 6-0."

**Result:**

- **Meaning of "const expression":** it has meaning only in the four contexts of §2.21. E0546 stays there. `let b: U8 = 300` stays E0318.
- **Q1 (6-0, A):** outside the const contexts, overflow in literal-only arithmetic compiles, panics at run time, and gets the warning `LiteralArithmeticOverflow` (W0708).
- **Q2 (5-1, A; DevOps dissent):** a unary `-` over a literal tree is a node of the tree, so `-(-128)` at `I8` warns. A negative literal is matched first, so `-128` is a leaf.
- **Q3 (4-2 for B in Phase C; 6-0 B in Phase D):** W0708 is defined at the type the checker gives each operation. The operand typing of a literal tree has its own record.
- **Scope rules (common ground):** the rules of W0704. A `const` reference or a `let` binding stops the tree; no flow analysis; not inside an `assert_panics` body. One warning for each tree, at the first operation that fails, in evaluation order. A literal 0 divisor is W0704 only. `<<` and `>>` are out. W0708 does not fire in the four const contexts.
- **Level:** suppress with `@allow(LiteralArithmeticOverflow)`; set the level with `W0708` under `[lints]`. `W0708 = "error"` makes it a build error.

**AI-First review:** 5/5 pass.

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated in independent-proposal → debate → vote → focused-debate rounds. Each panelist's text below is a verbatim excerpt; `[...]` marks a cut.

#### Phase A — Independent proposals

- **Systems:**

> **Rule.** "Constant expression" is a §2.21 term only. Outside the four contexts, the compiler evaluates nothing at compile time as part of the semantics. An integer operation that overflows panics at run time, as every other overflow does.

- **Web/Scripting:**

> - "Const expression" (§2.21) is a term for the four const contexts only. Outside them the compiler does not evaluate anything and an expression has no "constant" status. `let bad: I8 = 127 + 1` type-checks as `I8 + I8` (both literals take `I8` from the expected type, §3.2 *Operator operands*) and compiles.
> - At run time the `+` panics, as every overflowing `+` does (§3.2 *Overflow behavior*).

- **PLT:**

> My position: **"const expression" is a §2.21 term, and it means something only in the four contexts.** Outside them, `127 + 1` is an ordinary expression: an `I8` addition, evaluated at run time, with the §3.2 overflow panic. The compiler may *warn* about it, as it does for `10 / 0`. It must not reject it.

- **DevOps:**

> The check applies to the largest literal-only subtree. In `x + (127 + 1)` with `x: I8`, the subtree `127 + 1` is checked at `I8`. [...]
> - A literal 0 divisor is W0704, not W0708. One expression gets one warning: the first operation that fails, in evaluation order.
> - In the four const contexts it does not fire. There the same evaluation is E0546 (§2.21), and one fault gets one diagnostic.

- **AI/ML:**

> 1. **"Constant expression" is the §2.21 set and has an effect only in the four const contexts.** The term does not name a second, wider category in `let` or any other expression position. In the four contexts, overflow stays E0546 `ConstEvalPanic` (settled).
> 2. **Outside the four contexts, overflow in a literal expression is not a compile error.** The expression compiles and panics at run time (§3.2 checked arithmetic, settled).

- **Minimalism:**

> Outside the four const contexts, integer overflow in any expression panics at run time, the same as every other overflow. The compiler does not fold or check it. This is the rule the panel already chose 6-0 for a known zero divisor (Constant zero divisor, Q2), minus the warning.

Five seats put a literal-only warning first (Systems, Web, PLT, DevOps, AI/ML). Minimalism put "run-time panic, no new diagnostic" first and the warning second. Three seats listed a hard compile error as an option they oppose.

#### Phase B — Debate (1 round)

The moderator grouped the proposals into four options and eight variations.

- **O1:** compile, panic at run time, plus a literal-only warning W0708 with the W0704 scope rules.
- **O2:** compile, panic at run time, no new diagnostic.
- **O3:** the same warning with default level "error".
- **O4:** a hard compile error for literal-only overflow.
- **V1** name. **V2** unary `-` over a tree. **V3** reach into a literal subtree of a larger expression. **V4** one warning for each tree. **V5** zero divisor. **V6** shifts. **V7** const contexts. **V8** place in the spec.

All six replies agreed that O3 and O4 are withdrawn, and the name is `LiteralArithmeticOverflow`. Key shifts, verbatim:

- *min (B1):* moved from O2 to O1.

> That cuts against min-1 too. Under min-1, `let a = 10 / 0` warns and `let a: I8 = 127 + 1` is silent. I removed one asymmetry (error vs panic) and kept another (warning vs silence). sys raised exactly this in the zero-divisor Phase C. O1 removes both.

- *web (B1):* dropped the name `ConstantOverflow` and the fallback O3.

> My `ConstantOverflow` uses the word "constant", and this whole ticket exists because "constant" outside §2.21 was a confusing term. A user who sees `ConstantOverflow` will ask "but I did not write `const`". I withdraw it.

- *devops (B1):* dropped O3.

> `W0708 = "error"` under `[lints]` gives the same result to a team that asks for it. I vote O1.

- *plt (B1):* moved on V2, and asked for a side item on operand typing.

> My plt-1 grammar copied the negative-literal grammar of E0318, but W0708 is an evaluation check over the built-in integer operations, not a literal check. For a built-in integer type, unary `-` is a fixed total-or-panic operation like `+`, and its one overflow case is real: `-(-128)` at `I8`.

> Read strictly, `x + (127 + 1)` is `I8 + Int`, a type error, before W0708 has anything to check. So W0708 must be defined as "at the type the checker gave the subtree", and the gap in §3.2 is a typing question for its own record.

- *sys (B1):* moved to a negative-literal-only grammar on V2 (this later reversed, see Q2).

> The only case that loses is negating a tree whose value is MIN, such as `-(-100 - 28)` at `I8`. That gap is tiny, and plt's grammar reuses a form the spec already defines.

- *aiml (B1):* moved the same way on V2.

> One grammar, reused, is easier to learn. Nothing is lost in practice: in `let v: I8 = -(127 + 1)` the inner `127 + 1` is a literal tree and V3 catches it. Only `-(-128)` in I8 is missed, and that is rare.

After round 1, V2 split the panel and V3 had an open point on typing. Both went to Phase C.

#### Phase C — Final vote

Each seat voted alone. Tallies:

- **Q1: outcome outside the const contexts** — 6-0 A (compile, run-time panic, warning W0708).
- **Q2: unary `-` over a literal tree** — 5-1 A (DevOps B).
- **Q3: a literal-only subtree inside a larger expression** — 4-2 B (Sys, PLT, DevOps, Min B; Web, AI/ML A).

**Q1 — all A.**

- *Systems:* "Codegen is the same under A and B: the checked builtin goes out, and C folds a literal-only overflow to a direct jump to the panic path, so the run-time cost is zero either way. The difference is the policy." Concern: "[the literal-binop typing bug] must fix the contextual typing of literal binops first. Today `let a: I8 = 127 + 1` gives a false TypeError, and W0708 is only as correct as the types it reads."
- *Web:* "Literal size math in sized types is real code, for example `let max_upload: I32 = 1024 * 1024 * 1024 * 4`. Under B the user finds that bug as a crash at start-up. Under A the editor marks it as they type." Concern: "A user can ignore a warning, so a certain overflow can still ship. The docs should show `W0708 = "error"` for teams that want the stricter level."
- *PLT:* "The compiler runs one evaluator over §2.21-shaped trees. Its result is an error in the four contexts and a warning outside them, so no compile error depends on an unstated folding judgment." Concern: "Implementers may reuse the E0546 evaluator for W0708 without the W0704 scope limits (no `const` refs, no `assert_panics` bodies). The warning would then grow into the general constant folding that this decision rejects."
- *DevOps:* "An overflow in literal-only arithmetic always panics, so the warning never fires on correct code. It costs one catalog row and one AST pass next to W0704." Concern: "If W0708 ships before [the literal-binop typing bug], users see the wrong `TypeError` for `let a: I8 = 127 + 1` and never the warning, so the implementation ticket must depend on [the literal-binop typing bug]."
- *AI/ML:* "A model learns one rule for every literal-only certain panic outside the four const contexts: it compiles, panics at run time, and warns." Concern: "A warning is easy to miss in a long build log, so a generated program with a certain overflow can still ship unless the team sets `W0708 = "error"`."
- *Minimalism:* "The language rule stays small: outside §2.21 the compiler does not evaluate, and "constant expression" gets no second meaning." Concern: "The lint list grows one row at a time by the "it is cheap and exact" argument; the next literal-only check (shift counts, say) must still prove it is worth a row, not ride in on W0708's precedent."

**Q2 — A: 5, B: 1 (DevOps).**

- *Systems (A):* "I move back from my B1 position, because plt's B1 correction is right. W0708 checks evaluation, not literals. For a built-in integer, unary `-` is a fixed operation that panics in one case, just as `+` is, and `-(-128)` at `I8` is a certain panic that B lets through with no warning." Concern: "The spec text must say that a negative literal `N` is matched before `"-" K`, or `-128` at `I8` reads as `-(128)` and 128 fails E0318."
- *Web (A):* "The rule a JS or Python developer can hold in their head is "every leaf is an integer literal, and the operators are `+ - * / %` and unary `-`". Under B the user must know how a negative literal differs from a `Neg` call before they can predict the warning." Concern: "If B wins, the spec must give an example such as `-(-128)` that shows the silent case."
- *PLT (A):* "Under A, `-(1 + 2)` is still a `Neg` call, just as `127 + 1` is still an `I8` addition. W0708 evaluates the built-in integer operations, and on a built-in integer type `Neg` is one of them, the same as `Add`." Concern: "If B wins, the spec text must say clearly that `-(K)` ends the tree at the `Neg` node while `K` inside it is still checked [...]."
- *DevOps (B, dissent):* "§3.2 already states that `-(1 + 2)` is a call to `Neg` and that `-` is part of a literal only in the `N ::= "-" L` form. If W0708 reads the same `-` as a tree node, the spec reads one token two ways in two adjacent rules." Concern: "If A wins, the W0708 paragraph must say plainly that its `-` node is a wider reading than the §3.2 negative-literal grammar, or readers will apply the grammar from one rule to the other."
- *AI/ML (A):* "I move from B. My B1 worry was two readings of one token sequence, but plt's corrected grammar matches a negative literal first, so `-128` stays a leaf (as E0318 reads it) and `-(…)` is a node; the two readings never disagree." Concern: "The §3.6 text must show `-128` (a leaf, no warning) and `-(-128)` (a node, warns) side by side, or a model will read "unary `-` is a node" as "every negative literal is evaluated" and expect a warning on `-128`."
- *Minimalism (A):* "W0708 is an evaluation check, and every node in the tree is already an operator call (`127 + 1` is an `Add` call on a built-in type). So "§3.2 says `-(1 + 2)` is a `Neg` call" does not set `-` apart from `+`; it is true of both." Concern: "If B wins, the spec text must say outright that `-(-128)` is silent, or users will file it as a bug."

**Q3 — 4-2 B in Phase C.**

- *Systems (B):* "Whether `(127 + 1)` in operand position takes the type of the other operand is a typing rule. It changes which programs type-check and which C types the compiler emits, and it interacts with the [the literal-binop typing bug] fix and with §3.4 *Under-Determined Types*. That needs its own record, not a clause added to a lint decision." Concern: "If the side item is not logged and decided soon, `x + (127 + 1)` stays a type error in the spec, and the W0708 example in §3.6 must not show that case until the typing record settles it."
- *Web (A):* "Under the §3.2 text as it stands, `(127 + 1)` with no expected type is `Int`, so `x + (127 + 1)` with `x: I8` would read as `I8 + Int`. That is a type error for code that any JS, Python or Kotlin developer expects to work as `x + 128`. The same bug hits correct code too, such as `x + (2 * 3)`." Concern: "This adds a typing rule from a lint ticket. Check the wording against bidirectional checking in §3.4, so it does not conflict with how an expected type already reaches a parenthesized expression."
- *PLT (B):* "The typing of a literal tree in operand position is a typing rule with its own interactions: nested trees, the expected type of a comparison, `<<`/`>>`, and type variables that nothing has solved yet (§3.4). It deserves its own record, not a sentence added inside a warning decision." Concern: "Under B, the §3.6 text must not use `x + (127 + 1)` as a W0708 example until the side item settles."
- *DevOps (B):* "The typing sentence changes what compiles: today `x + (1 + 2)` with `x: I8` is, by the text, an `I8 + Int` type error. Widening that is a typing rule with its own diagnostics (E0318 and TypeError reach), and it belongs in its own record with its own examples, not as a rider on a lint vote." Concern: "If the side item sits unresolved, the W0708 example `x + (127 + 1)` reads as a type error in the spec, so the §3.6 paragraph must not use that example until the typing record lands."
- *AI/ML (A):* "The W0708 example `x + (127 + 1)` with `x: I8` is only well-typed if the literal tree takes `I8`; under today's §3.2 text it is `I8 + Int`, a type error. A spec whose own example depends on an unstated typing rule teaches a model nothing it can apply, [...]" Concern: "The typing sentence reaches beyond W0708 (it also changes which programs type-check, such as `x + (1 + 2)` at `I8`), so the writer must state its scope exactly and add it to [the literal-binop typing bug]'s tests, or it will drift from the implementation."
- *Minimalism (B):* "This ticket asks an evaluation question. "A literal-only tree in operand position takes the type of the other operand" is a typing rule: it changes which programs type-check (`x + (1 + 2)` with `x: I8`) far beyond overflow, and it deserves its own record with its own examples." Concern: "If A wins, a typing rule lands with no separate check of how it interacts with comparisons, shifts and nested trees, and the next panel inherits it as "already decided"."

#### Phase D — Q3 only

Q3 went to one focused round. Result: **6-0 B.** Web and AI/ML moved from A.

- *Web (B):* "I accept the scope argument. min says "This ticket asks an evaluation question", and devops says the sentence "changes what compiles". Both are true. I wanted A for the user who writes `x + (2 * 3)` at `I8` and gets a type error. But that user is not helped by this lint vote. They are helped by a typing record that also covers comparisons, shifts and nested trees, which plt names." Conditions: the side item is logged at once as its own `type:spec` ticket with `x + (2 * 3)` at `I8` as the MVCE; the §3.6 paragraph uses only top-level trees as examples until that record lands. Concern: "If the side item stays in the backlog, users keep hitting an `I8 + Int` type error on `x + (2 * 3)`."
- *AI/ML (B):* "My A argument was that the spec must not show an example whose typing it does not state. sys, plt and devops each solve that under B: "the §3.6 text must not use `x + (127 + 1)` as a W0708 example until the side item settles." With that condition, B leaves no example a model could misread, and W0708 "at the type the checker gives each operation" stays correct under either typing outcome. I move to B." Concern: "If the side item is not logged as a `type:spec` ticket with [the literal-binop typing bug] depending on it, `x + (2 * 3)` at `I8` stays a type error by the text, and models and users meet that error on correct code."
- *PLT (B):* a new point from the text. "§3.2 states an invariant: "A literal does not wait for a later line to fix its type ... Its type is known at the literal, so it never leaves a type variable that would need a default (§3.4)." Today the operand rule keeps that invariant local: a literal looks only at its sibling operand. Under A, the type of `127` in `(127 + 1) + x` depends on `x`, a sibling of an *enclosing* operator. When the literal tree is on the left, the checker must either synthesize `x` first (the order of checking becomes part of the spec) or hold a variable for the tree until `x` is known (what the invariant forbids)." Concern: "If the side item is not filed with the cases above (left-side tree, nesting, comparison, shift) and linked to [the literal-binop typing bug], the §3.2 gap stays open and implementers will settle it by accident in the checker."
- *Systems (B):* "With `x: U8`, `x + (200 + 100)` today reads as `U8 + Int`, a type error found at compile time. Under A the inner `+` is `U8`, so the program compiles, gives W0708, and emits a `uint8_t` checked add that panics at run time. That may well be the correct trade (I think it is, as plt does), but it moves a case from "does not compile" to "compiles and panics". The panel should vote on that with the examples in front of it." Concern: "The side item must be logged as a type:spec ticket linked to [the literal-binop typing bug] at once, and the §3.6 text must leave out the `x + (127 + 1)` example until it is decided."
- *DevOps (B):* "To answer web's point about delay: file the side item now, link it to [the literal-binop typing bug], and make the [the literal-binop typing bug] fix depend on it. That way the typing gap gets fixed in the same work as the literal-binop typing bug." Concern: "If the side item is not filed and linked to [the literal-binop typing bug] at once, the gap stays open and the implementer of [the literal-binop typing bug] picks a typing rule alone."
- *Minimalism (B):* "W0708 examples then use only whole literal trees in a typed position (`let a: I8 = 127 + 1`), which are well-typed under §3.2 as it stands. The W0708 rule text stays "at the type the checker gives each operation", which is correct whatever the typing record decides." Concern: "If the side item is not logged and scheduled, `x + (2 * 3)` at `I8` stays a type error in the spec text for longer than anyone intends."

### Final Spec

```blink
const LIMIT: I8 = 127

fn main() {
    let bad: I8 = 127 + 1       // warning[LiteralArithmeticOverflow]; RUNTIME PANIC
    let n: I8 = -128            // ok: a negative literal
    let m: I8 = -(-128)         // warning[LiteralArithmeticOverflow]; RUNTIME PANIC
    let d: I8 = (127 + 1) / 0   // W0708 at 127 + 1, W0704 at 0
    let b: U8 = 300             // error[IntLiteralOutOfRange] (E0318)
    let e = LIMIT + 1           // no warning: a const reference stops the tree
}

test "overflow panics" {
    assert_panics {
        let _: I8 = 127 + 1     // no warning inside assert_panics
    }
}
```

- "Const expression" has meaning only in the five contexts of §2.21. E0546 applies there. W0708 does not fire there. (A later panel changed the count from four to five; see [Module-Level Initializer Is a Const Context](module-init-const-eval.md). The rule is the same.)
- Outside those contexts, overflow in literal-only arithmetic compiles and panics at run time. The compiler gives `LiteralArithmeticOverflow` (W0708).
- The tree is `K ::= N | L | "(" K ")" | "-" K | K op K`, with `op` in `+ - * / %`. A negative literal `N` is matched first, so `-128` is a leaf and E0318 governs it. `-(-128)` at `I8` is a unary `-` node over a tree and warns. The spec says that this grammar is wider than the negative-literal rule of §3.2.
- W0708 checks the largest literal-only tree, at the type the checker gives each operation. The spec states no rule for the type of a literal tree in operand position.
- One warning for each tree, at the first operation that fails, in evaluation order.
- A literal 0 divisor is W0704 only. `(127 + 1) / 0` at `I8` gets both warnings, each at its own operation.
- `<<` and `>>` are not part of the tree.
- A `const` reference or a `let` binding stops the tree. There is no flow analysis. The warning does not fire inside an `assert_panics` body; this rule belongs to W0704 and W0708 only.
- Suppress with `@allow(LiteralArithmeticOverflow)`; set the level with `W0708` under `[lints]`. `W0708 = "error"` is the way to make it a build error.
- §3.2 *Overflow behavior* and *Integer literal range* no longer claim a compile-time check outside const contexts. The new rule is in §3.6, *Literal arithmetic overflow*.

### Side items

- The operand typing of a literal tree (`x + (2 * 3)` at `I8`, a left-side tree such as `(127 + 1) + x`, comparisons, the right operand of `<<` and `>>`, nested trees, unsolved type variables) is filed as its own spec record. The fix for the literal-binop typing bug depends on it.
- A narrower warning for a certain panic from an empty literal range is related and separate.

### Concerns for implementation

- W0708 must not ship before the literal range check and the contextual typing of literal binops are fixed (DevOps, Systems). Until then `let a: I8 = 127 + 1` gives a false `TypeError` and never reaches the warning.
- Keep the check from growing into general constant folding (PLT). It reads the expression as written, and it follows the W0704 scope rules.
- A future lint must not cite W0708 to skip its own justification (Minimalism).
- The docs show `W0708 = "error"` for teams that want a stricter level (Web, AI/ML).
