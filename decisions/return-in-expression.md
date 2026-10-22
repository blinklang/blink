[< All Decisions](../DECISIONS.md)

# Jumps as the Right Operand of `??` — Design Rationale

**Resolution:** `return`, `return e`, `break` and `continue` are **jumps**. A jump has type `Never` and is not an expression. A jump stands in four positions and in no other: as a statement, as the tail of a block, as the body of a braceless match arm, and as the right operand of `??`. So `o ?? return e`, `o ?? break` and `o ?? continue` are legal. A jump in any other position, with or without parentheses, is the new parse error `JumpNotAllowedHere` (E1133). `blink fmt` writes a `??` operand that is one jump without braces.

**Vote:** Q1 6-0; Q2 5-1 (web dissent); Q3 6-0. AI-First 5/5 pass.

## The Gap

The spec writes `?? return Err(NotFound)` three times in §8 (tooling), but `blink check` rejected it. Measured on the compiler at the time:

| Program | `blink check` |
|---|---|
| `let w = o ?? return 0` | parse error: "`return` is a keyword and cannot be used as an identifier" |
| `let w = o ?? (return 0)` | the same error |
| `for x in xs { let v = o ?? continue }` | the same error, for `continue` |
| `match o { Some(n) => n  None => return 0 }` | ok |
| `let w = o ?? { return 0 }` | ok |

The `??` operator is defined as `a ?? d` means `match a { Some(n) => n  None => d }`. With `d = return 0` the right side of that equivalence was legal and the left side was not.

### Panel Deliberation

The ticket, verbatim:

> **Spec writes x ?? return e and x ?? panic(...); check rejects both**
>
> sections/06_tooling.md:137 writes `db.query_one(...) ?? return Err(NotFound)`; 04_effects.md:833 writes `env.var(...) ?? panic("...")`; 02_syntax.md:1850 says a panic call fits in any expression position. Under gen1 (worktree build, file inside the repo): `let w = o ?? return 0` is a parse error (KeywordAsIdentifier `return`); `let v = o ?? panic("x")` reports UndefinedFunction panic, and even a bare `panic("x")` statement in main does; `fn die() -> Never` reports UnknownType Never. Triage: is `return e` an expression (spec 02_syntax.md:50 says return is for early exit only), and why does `blink check` not see panic/Never here.

The `panic` and `Never` half was fixed in another change. This decision covers the first half: whether `x ?? return e` parses.

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated in independent-proposal → one debate round → vote rounds. Phase D did not run.

The moderator grouped the Phase A proposals into three options:

- **J1:** the right operand of `??` is an expression or a jump.
- **J2:** `return`, `break` and `continue` are expressions of type `Never` in every position.
- **J3:** no grammar change; jumps are statements; the examples change to `?? { return e }`; a new error offers a fix that adds braces.

#### Phase A — Independent proposals (excerpts)

First choices: J1 for systems, PLT, DevOps and AI/ML; J2 for web; J3 for minimalism.

- **Systems (J1):**

  > The answer for `??` alone: nothing new. F7 says `x ?? d` desugars to `match x { Some(n) => n  None => d }`. With `d = return e`, the `None` arm is `None => return e`, which already parses and runs (F6, p5). In C it is one tag test and one branch: the jump edge lowers to the same epilogue (cleanups, then `return`) that `?? { return e }` (p7) and `if ... else { return e }` (p3) use today. No new IR node, no runtime cost, codegen we can predict. The gap is a parser gap, not a semantic one

- **PLT (J1):**

  > A desugaring is a specification only if it is an equivalence. Today it is not: the right side is legal with `d = return 0` and the left side is a parse error. Either the desugaring is wrong or the parser is wrong. The spec examples (06_tooling.md:137, 321, 336) say the parser is wrong.

- **DevOps (J1):**

  > Rule: the right operand of `??` is an expression, or one of the three jump forms `return [e]`, `break`, `continue`. Nothing else becomes legal. This follows the decided desugar (F7): `x ?? rhs` is `match x { Some(n) => n  None => rhs }`, and `None => return 0` is already legal there. The rule adds no new idea; it makes the sugar agree with what it desugars to.

- **AI/ML (J1):**

  > The idiom has a large prior from other languages: Kotlin `val u = find(id) ?: return null` is very common; Swift `guard let ... else { return }` and Rust `let Some(u) = x else { return }` teach the same "unwrap or leave" shape. An LLM will write `?? return` whether or not we allow it.

- **Web/Scripting (J2):**

  > Rule: `return`, `return e`, `break` and `continue` may stand where an expression goes. Each has type `Never` (§3.2, §3.3 already lists them as diverging constructs). They still carry no value out of a loop: `break e` stays out of v1.

  And on the cost: "It lets silly code through: `f(return 1)`, `1 + return 2`, `return return 1`. Rust and Kotlin allow all of these and nobody writes them. An unreachable-code warning on the code after a `Never` operand covers it; I would not add grammar to forbid them."

- **Minimalism (J3):**

  > So the gap is in the text, not in the language. The question for the panel is whether three illustrative lines justify a grammar change.

  And on the error: "Today `o ?? return 0` reports "`return` is a keyword and cannot be used as an identifier" (F6, p1). That text is wrong for this input, and we must fix it whatever the panel decides."

Every seat agreed that the `KeywordAsIdentifier` message is wrong for this input under every option.

#### Phase B — Debate (1 round; all six ended on "ready to vote")

Shifts:

- **Web/Scripting** moved from J2 to J1:

  > J1 covers every case a user really writes: `?? return e`, `?? return`, `?? continue`, `?? break`. The forms J2 adds and J1 rejects (`f(return 1)`, `1 + return 2`, `let x = return 3`) are forms no JS, Python or Kotlin dev reaches for on purpose.

  And: "J1 is also easy to explain, which was my main test: "the right side of `??` works like a match arm body, because that is what it is." One sentence, it falls out of the desugar (F7), and users already know the arm form."

- **Minimalism** moved from J3 to J1:

  > The argument that counts for my seat: the spec defines `??` with one sentence, "`a ?? d` is `match a { Some(n) => n  None => d }`" (05_memory_compile_errors.md:741-760). Under J3 that sentence is false. To keep it, we must add a caveat ("the `None` arm body is an expression, not a jump", as plt-3 says), and the error note must explain the caveat. So J3 is not zero rules. It is zero grammar plus one exception to the desugar. J1 deletes that exception

  And: "What I keep from min-1: J1 must stay closed. A jump stands in four places only: a statement, a block tail, a braceless arm body, the right operand of `??`. No other position. That closed list is what keeps J1 from becoming J2."

- **PLT** made two findings. The first fixes the wording of the rule:

  > The parser reads a braceless arm body with `parse_stmt()` (src/parser.bl, `parse_match_arm`, the `body = parse_stmt()` branch). So a braceless arm body admits every statement form, and an assignment works there today. [...] If J1 is worded "the right operand of `??` takes the forms of a braceless arm body", then `o ?? n += 10` and `o ?? let y = 1` become grammar.

  So the rule reads "an expression or a jump". The second finding is a separate bug:

  > `parse_nullcoalesce` loops `while at(TokenKind.DoubleQuestion)` and builds `BinOp(left, right)` with `right = parse_or()`. That makes `??` left-associative, but 02_syntax.md:1704 says it is right-associative. [...] The chain `a ?? b ?? return e` (plt-1, aiml-1) works only under right associativity. A ticket already covers this

  PLT also withdrew its parentheses-legal position: "I concede to aiml-1 and devops-1: **reject** `o ?? (return 0)`, with a machine fix that drops the parentheses. Under the wording in point 1, a jump is not an expression, and parentheses wrap an expression. So the rejection follows from the rule; it is not a special case. My plt-1 rule 5 added a second spelling for no gain. I withdraw it."

- **Moderator carried points** (no seat objected): one new parse error code for every jump in a rejected position, with the keyword as data; default help "put the jump in its own statement before this line"; `blink fmt` has one spelling for a one-jump operand; the 06_tooling.md examples stay as written, and the leading-`??` continuation fix and the `??` associativity fix are separate bugs.

#### Phase C — Final vote

Each panelist voted alone on a written ballot.

##### Q1 — The rule — **J1** (6-0)

- **Systems:** "The `??` lowering already puts its right operand in the `else` branch of a C `if` statement (checked with build/blinkc on p7: `else { return 0; }`), so J1 is a parser change with no new IR and no change to the generated code."
- **Web/Scripting:** "J1 makes the idiom users already type work: Kotlin's `?: return` and the spec's own `?? return Err(NotFound)`, which the spec authors wrote three times by reflex."
- **PLT:** "J1 is the one option that keeps that equivalence true with no caveat. Typing needs no new rule: the jump has type `Never`, `Never <: T`, and `T` comes from the left side alone, so inference never picks `Never`."
- **DevOps:** "J1 keeps a closed list of jump positions, so the new error can give every legal position in one note, and the LSP knows which edit to offer at each rejected site."
- **AI/ML:** "Models write the Kotlin form `?? return e` first: the spec's own three examples use it. Our compiler source shows the demand under another spelling, with 35 four-line `match` sites in src/ of the form `Some(x) => x` / `None => return ...`."
- **Minimalism:** "J1 adds no new concept. It makes the existing desugar `a ?? d ≡ match a { Some(n) => n  None => d }` true, where J3 keeps it true only with a caveat."

##### Q2 — Parentheses around a jump — **P2** (5-1)

P1: `o ?? (return 0)` is legal and means `o ?? return 0`. P2: it is the jump error, and the machine fix drops the parentheses.

- **Web/Scripting: P1 (dissent).** "Parentheses must never decide whether code compiles. JS and TS devs add parens around `??` and `||` operands "to be safe" out of habit. An error on `o ?? (return 0)` would make parens a trap in exactly one place in the language. fmt drops them, so the codebase still has one spelling."
- **Systems: P2.** "The parser decides by the token after `??`, which is a plain rule with no lookahead. If parentheses are transparent, `(return 0)` is a parenthesized expression, and the rule must then explain why `(return 0) + 1` is not legal."
- **PLT: P2.** "Under J1 a jump is not an expression, and parentheses wrap an expression. So the rule itself rejects `(return 0)`; P2 needs no extra clause."
- **DevOps: P2.** "If `(return 0)` is legal, the parser and the error note must also decide about `((return 0))` and `o ?? (return 0) + 1`, and the closed list stops being closed."
- **AI/ML: P2, moved from P1.** "I said P1 in B1, but that was before the S2 wording existed. If §2 says "a jump is not an expression", then parentheses, which wrap an expression, cannot hold one. P1 would need a second exception that a model has to remember."
- **Minimalism: P2, moved from P1.** "Under P2 the grammar needs no extra rule: parentheses wrap an expression, a jump is not an expression, so `(return 0)` falls under the general jump error with no special case. P1 needs a rule that a parenthesized jump is legal only where the parenthesized form itself stands in one of the four positions. That is a position-dependent paren rule, which is more surface."

##### Q3 — What §2 calls `return`, `break`, `continue` — **S2, "jumps"** (6-0)

S1: "statements", with the right operand of `??` named as the one exception. S2: "jumps", a class of its own that is not an expression.

- **Systems: S2, moved from S1.** "I proposed S1 in B1, but S2 is more exact. "A statement that stands where an expression goes" contradicts itself, while "a jump, with a closed list of positions" does not."
- **Web/Scripting:** "A user (or an LLM) needs one sentence that answers "where can I write `return`?", and S2 is that sentence: a closed list of four places."
- **PLT:** "§3.3 can then say "a jump, in any position §2 admits one", and the list of `Never` constructs stays closed by one definition, not by two lists that can drift apart."
- **DevOps:** "A named class gives the diagnostic, the catalog entry and the spec one word: the error says "a jump cannot stand here", and the note copies the §2 list word for word."
- **AI/ML:** "S2 is the closed list I asked for, in one sentence that stands on its own: a model can learn every legal position from that sentence alone."
- **Minimalism:** "S1 says "statement" and then admits a statement-only form in one expression position. A reader would then ask why other statements (`let`, `x += 1`, `while`) cannot stand there too, and the spec would need a second rule to say no."

### Final Spec

```blink
fn demo(o: Int?, p: Int?, xs: List[Int?], ok: Bool) -> Int {
    let a = o ?? return 0               // legal: jump as the right operand of `??`
    for x in xs {
        let n = x ?? continue           // legal
        let m = x ?? break              // legal
    }
    let b = o ?? return p ?? 1          // legal: means `o ?? return (p ?? 1)`
    let c = o ?? p ?? return 2          // legal: chain, right-associative

    let d = o ?? (return 0)             // error[JumpNotAllowedHere]: parentheses wrap an expression
    f(return 1)                         // error[JumpNotAllowedHere]
    let e = return 3                    // error[JumpNotAllowedHere]
    let g = ok && return 4              // error[JumpNotAllowedHere]
    a
}
```

Locked points:

- A **jump** is `return`, `return e`, `break` or `continue`. A jump has type `Never` and is not an expression. §2 defines the term once (§2.11 *Jumps*) and the rest of the spec uses it (Q3).
- A jump stands as a statement, as the tail of a block, as the body of a braceless match arm, or as the right operand of `??`. It stands nowhere else (Q1). The list is closed.
- The right operand of `??` is an expression or a jump. The reason: `a ?? d` means `match a { Some(n) => n  None => d }`, and `None => return e` is a legal arm. The wording is not "the forms of a braceless arm body", so `o ?? n += 10` stays outside the grammar.
- The type of `o ?? return e` comes from the left operand. The jump has type `Never`. Only the right operand of `??` takes a jump: not the left operand, not an operand of `&&` or `||`, not a call argument, not a `let` initializer written directly.
- The operand of `return` takes as much as it can: `o ?? return a ?? b` means `o ?? return (a ?? b)`.
- Parentheses wrap an expression. A jump in parentheses is the jump error, and the machine-applicable fix drops the parentheses (Q2).
- New parse error `JumpNotAllowedHere` (E1133) for a jump in any other position. It replaces the "`return` is a keyword and cannot be used as an identifier" message for this input. The keyword is data in the message. The note lists the four legal positions word for word from §2. Default help: put the jump in its own statement before this line. For an operand of `&&` or `||`, the help shows the `if !cond { return e }` form.
- `blink fmt` writes a `??` right operand that is a block with only one jump without braces (`?? { return e }` becomes `?? return e`). It keeps a braceless one-jump arm (`None => return 0`) on one line.
- §3.3 and the `Never` definition name a jump and point to §2.11 *Jumps* for its positions, in place of a separate list of `return`, `break` and `continue`.
- The `?? return Err(NotFound)` examples in 06_tooling.md stay as written.

### Concerns for implementation

- The unreachable store after the jump (`_cg_x381 = _cg_val382;`, a read of a never-set temp) now appears on the common path. The lowering should skip the result store for a `Never` right operand before `-Wall` users or sanitizers flag it (Systems).
- The leading-`??` continuation fix and the `??` associativity fix must land with or soon after the parser change. Without them the 06_tooling.md examples and the chain `a ?? b ?? return e` still fail (Web, DevOps, PLT).
- The error text and the llms docs must use the word "jump", as §2 does (Web, DevOps, AI/ML, Minimalism).
- The machine fix must drop the parentheses itself, not only report the error (AI/ML, Minimalism, Web).
- The fmt chore must land with the parser change. If it slips, both spellings stay in the corpus (AI/ML, Minimalism).
- The list of positions stays closed. A later proposal to add `&&`, `||` or an unbraced `if` must bring a desugar argument as strong as this one (Minimalism).
- Tests must cover `f((return 0))` and `(return 0) + 1` (Systems, DevOps).

### Follow-ups

- Parser change and E1133 with its fixes.
- Formatter chore: bare `?? return e`, and keep one-line jump arms.
- The `??` associativity bug and the leading-infix-operator continuation bug are prerequisites for the 06_tooling.md examples.
- Codegen chore: skip the result store for a `Never` right operand.

### AI-first review

- **Learnability:** one sentence in §2 lists every place a jump may stand, and the `??` case follows from the `match` desugar the spec already states.
- **Consistency:** `?? return e` and `None => return e` are one rule, and §3.3 points to §2 for the list of positions.
- **Generability:** the Kotlin-style form that models write first (`?? return e`, `?? continue`) compiles, and formatting gives it one spelling.
- **Debuggability:** one error code names the keyword and the four legal positions, and defensive parentheses have a machine fix.
- **Token efficiency:** `let user = lookup(id) ?? return None` replaces a four-line `match`.
