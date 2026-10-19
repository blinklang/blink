[< All Decisions](../DECISIONS.md)

# Integer Literal Range — Design Rationale

The spec did not say whether an integer literal above the `Int` maximum, such as `9223372036854775808` (2^63), is valid under an expected `U64` type, or what happens with no expected type. The Float Bits panel (Q7) asked for this decision, because `x.to_bits() == 9223372036854775808` is the first sign-mask line a user writes after §3.6 *Float Bits*.

Measured with the compiler before the decision (gen1): `let x = 9223372036854775808` became the `Int` minimum with no diagnostic, `let n: U64 = -1` and `let u: U8 = -1` wrapped with no diagnostic, `let v: U8 = 300` gave no error, `t + 9223372036854775808` with `t: U64` panicked with the wrong value, and `x.to_bits() & 9223372036854775808` failed with `incompatible types U64 and Int`.

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated in independent-proposal → debate → vote rounds. Quoted text is each panelist's own, verbatim; only local ticket IDs are replaced with a short name.

#### Phase A — Independent proposals

All six proposed the same core rule: a literal is its exact value and must fit the type it gets, with one new code. They differed on a unary `-` under an unsigned type, on operator operands, and on when the check runs. Excerpts:

- **Systems:**

> **Proposal S1: a literal is an exact integer, checked once against its final type**
>
> Rules:
>
> 1. **Value.** An integer literal, written in any base the literal-grammar ticket allows, stands for an exact mathematical integer. A unary `-` written directly before a literal (parentheses allowed, as W0704 and W0706 already read it) makes one *negative literal*. Its value is the negated magnitude. It is not `Neg.neg(MAX+1)`. This is the only way to write Int MIN, and it matches what §2.19 already treats as one literal.
> 2. **Type.** Same as today: the context gives the type, and with no context the type is Int. The range check runs on the literal's *final* type, after inference settles it, and not at the first hint. A metavar that later resolves to U64 still gets the right check.
> 3. **Range.** The value must lie in that type's range: Int, I8..I32, U8..U64. Outside the range it is a compile error, with one code for every integer type. That also closes the sized-int range bug (`let v: U8 = 300`) under the same rule.
> 4. **Unsigned and minus.** A negative literal under an unsigned type is the same error. It is not a `Neg` trait error, because the user sees a literal and not a call.
> 5. **Codegen.** Emit a typed C constant from the checked value: `UINT64_C(9223372036854775808)` for U64, `INT64_MIN` for the Int minimum, and `(int8_t)-128` style casts for narrow types. Never emit the source text.

- **Web/Scripting:**

> **Rule.** An integer literal's value is the exact integer its digits spell, with no wrap. The literal takes its type from context, or `Int` when there is no context, as decided. The literal is valid only when its value is in that type's range. Otherwise the compiler gives a compile error. The rule has no special case for U64, for hex, or for "large" literals. A JS or Python developer already believes this rule, because Python ints are unbounded and JS `BigInt` is too.

- **PLT:**

> **Rule 1 (meaning).** An integer literal stands for an exact mathematical integer *n*, computed from its full digit text in any base (decimal now, plus hex/bin/oct if the literal-grammar ticket adds them). The compiler never cuts it to 64 bits before typing.
>
> **Rule 2 (typing, bidirectional):**
> - *Check mode*, `n ⇐ T`, where T is an integer type: the literal is accepted at T only if `n ∈ range(T)`. Otherwise the error is **`IntLiteralOutOfRange`** (new code; I suggest E0318, the next free E03xx).
> - *Synth mode*, `n ⇒ Int`: with no expected type, the literal is `Int`, and the same range check runs against Int. This is literal defaulting, which is already decided (4-1). It is not inference defaulting, which §3.4 forbids. The literal picks its type at the literal and never leaves an open variable behind.
> - When a literal is checked against an unsolved type variable, it binds that variable to `Int`, as the compiler does today.
>
> One judgment covers U8 and U64, decimal and hex, with or without an expected type. A U64 value above Int max is not a special case. `range(U64)` simply holds it.
>
> **Rule 3 (negative literals).** `-` placed directly on a literal (parentheses around the literal allowed, as W0704 and §2.19 already read it) forms one **negative literal** with value `-n`.
> - Under a signed T, it is range-checked as `-n`. So `-9223372036854775808 ⇐ Int` holds, and `-128 ⇐ I8` holds. The elaboration agrees with `Neg.neg(n)` for every n where that call is defined, and adds Int MIN, which `Neg` cannot reach.
> - Under an unsigned T, `Neg` has no impl, so the existing sealed-`Neg` error fires. That includes `-0`. The trait system already rejects `-` on unsigned types, and the literal rule must not punch a hole in it.

- **DevOps:**

> **A1. A literal holds its exact value until it gets a type.** The parser already keeps the digit text (`str_val`). Typecheck reads that text as an exact integer and checks it against the literal's *final* type, after inference, at the literal's span. A literal fits type T when its value is in T's range. Nothing else counts. This also covers any hex, binary or octal literal that the literal-grammar ticket adds: `0x8000_0000_0000_0000` is the value 2^63, never a bit pattern.

- **AI/ML:**

> **Rule L1 — value.** An integer literal denotes the exact whole number its digits spell, in any base. The compiler never folds it to 64 bits before it knows the type.
>
> **Rule L2 — type.** The literal takes its type from context (unchanged; `Int` with no context).
>
> **Rule L3 — fit.** The value must be in the range of that type. If not: `error[IntLiteralOutOfRange]` (proposed E0318, the next free E03xx). The same code covers `U8 = 300`, `I8 = -129`, `U64 = 2^64` and a bare `9223372036854775808`, so the sized-int range bug and this ticket close with one rule.
>
> **Rule L4 — negative literal.** A unary `-` directly before an integer literal forms one negative literal for L3. This is the same shape §2.19 already calls "a number literal with a unary `-`". So `-9223372036854775808` fits `Int`, and `-1` under `U64` is E0318 ("-1 is below the U64 minimum 0"), not a confusing `Neg` trait error.

- **Minimalism:**

> **Proposal M1: one rule and one code.**
>
> 1. **Value, not spelling.** An integer literal is valid when its exact math value is in the range of the type it receives. With no context, that type is `Int` (already decided). This holds for any base that the literal-grammar ticket adds. There is no "bit pattern" exception for hex.
> 2. **A minus sign right before a literal is part of the literal.** This applies only to the range check and its message. A unary `-` written directly before an integer literal, with optional parentheses, counts as part of the literal for this check. §2.19, W0704 and W0706 already read "a literal with a unary `-`" as written, so this is the same reading, not a new idea.
> 3. **One code:** `error[IntLiteralOutOfRange]` (next free E03xx, for example E0318). It covers every sized type, every base, and the no-context case.

#### Phase B — Debate highlights

One round. Phase B used the round-1 digest numbers: Q3 was operator operands and Q4 was when the type is fixed. The ballot added the parentheses question as Q3 and moved the rest down one. Five seats signed "stable, ready to vote". PLT stayed open on when the type is fixed and on `-0`, and the vote settled both its way.

- **Systems** (Q2, moves to 2a with `-0` included):

> **Q2: I move to a narrowed 2a.** PLT is right that 2a as written opens a hole. `let u: U8 = -0` has the value 0, which is in range, so plain 2a accepts it, while `-x` on a U8 is rejected. My fix: under an unsigned type, *any* negative literal (`-` directly on a literal, parentheses allowed), `-0` included, is `IntLiteralOutOfRange`, with the note "unsigned types hold no negative values". This keeps PLT's property: no `-` ever type-checks on an unsigned type. It also keeps my codegen point. A negative literal is one constant and never a `Neg` call, so the error belongs to the literal and should point at the literal, not at a trait the user never named. PLT's 2b help line names `U8.MAX`, which the spec does not define (Min also declined to add it). That is one more reason to use E0318 with a value-only message. Measured: `let u: U8 = -0` compiles today.

- **Web/Scripting** (Q3, adds the outer-T variation):

> ## Q3: 3a, and I move to add PLT's outer-T variation
>
> Min's M2 says this is a bug and not a gap. The measurement above shows it is more than the bitwise hole. With no rule for "both operands are literals under an expected type", `let x: U64 = 1 + 2` is legal to reject under today's text. The spec must say it. AI/ML and DevOps are right to leave if-branches and assignment targets to the §3.4 hint-list ticket. But the operator rule is what the sign-mask line needs, so it belongs here. the §3.4 hint-list ticket can link to it. I accept Min's ask that we write it in §3.2 *Literal syntax*, one place, and that the §3.4 hint-list ticket points there rather than repeating it.
>
> So: 3a for all listed operators, either side. PLT's variation applies: with an outer expected integer type T and a T×T→T operator, both operands are checked against T. Shift amounts are `U32`.

- **PLT** (Q2, moves from 2b to 2a with a condition):

> **Q2. I move to 2a, with one condition.** Sys, DevOps and AI/ML are right on one point: the user wrote a value, so the message should talk about the value and not about a trait. My concern was soundness, not wording. Under 2a, `let u: U64 = -0` has value 0, so it is "in range" and would get through. That lets a literal bypass the sealed `Neg`. So the condition is:
>
> > A negative literal is valid only at a signed type. At an unsigned type it is E0318 for every value, `-0` included.
>
> The message is "unsigned types hold no negative values". This keeps the typing rule a single judgment, with no `Neg` exemption, and gives the error the majority wants.
>
> Parentheses: Web W1b makes `-(128)` a `Neg` call. Sys, DevOps and the digest allow parentheses. Parentheses carry no meaning anywhere else in the spec (W0704, W0706), and a rule that changes a value's type because of parentheses does not compose. I side with "parentheses allowed".

- **DevOps** (Q2, holds 2a and closes the `-0` case):

> **Q2: I hold 2a, with one change that answers PLT.** PLT is right that `-` must never work on an unsigned type. But 2a does not let a literal get past `Neg`. The program is rejected either way, and only the message differs. "`Neg` is not implemented for U8" tells the user about traits when they wrote a wrong value. It also sends them to look for an impl they cannot add, because `Neg` is sealed. PLT's own help line, "write U8.MAX", names a constant that does not exist (see digest facts). The edge case PLT raises is `-0`, whose value 0 is in range. I close it like this: **under an unsigned type, a written negative literal is always E0318, whatever its value.**

- **AI/ML** (Q4, moves to 4a):

> ## Q4: move to 4a (PLT)
>
> Sys and DevOps want 4b so that `xs.push(9223372036854775808)` into a list that later becomes `List[U64]` works. For learnability, 4a is the better rule: the type of a literal depends only on what is written around it, and the error always shows at the literal. Under 4b, whether a line compiles depends on a later line and on the order in which the solver runs. A model writes code top to bottom and cannot see that. The fix under 4a is one annotation where the list is made (`List[U64].new()` or `let mut xs: List[U64]`), which a help line can name. Go behaves this way too: an untyped constant gets its type at the use, not later. DevOps's `[2^63]` into `List[U64]` case works under 4a once the hint reaches list elements (bug above).

- **Minimalism** (Q3, moves from a bug-only answer to the operator rule):

> **Q3: I move to 3a, with one condition.** My objection was where the rule lives, not the rule itself. Sys showed that `z.to_bits() & 9223372036854775807` fails even though that value fits in Int. So the ticket's own first example does not work without an operand rule, and filing only a bug leaves the spec gap open. My condition: the spec text goes into the single §3.4 hint list that the §3.4 hint-list ticket also edits. That puts one list in the spec, not a second list in §3.2. the §3.4 hint-list ticket then keeps only if-branches and assignment targets, as AI/ML and DevOps ask.
>
> I also accept PLT's variation (outer T with a T×T→T operator checks both operands against T). It is not new surface. It is what "context gives the type" already means in check mode, and without it the plainest mask line fails:
>
> ```blink
> let m: U64 = 1 << 63   // needs the outer U64 to reach `1`; `63` is U32
> ```
>
> Today this line compiles only by accident (the C conversion). Under 1A without the variation, it is `Int` overflow.

#### Phase C — Final vote

Every question passed 6-0, so Phase D did not run. Each entry is the panelist's ballot text.

- **Q1: Core literal rule** (6-0, 1A)

  - **Systems:**

    > **Vote:** 1A
    > **Reasoning:** Today an out-of-range literal becomes digit text pasted into C, and that text has an implementation-defined meaning. No program value can stand behind an `@allow`, so the error must be hard. The text for a literal above U64 max is accurate: no integer type holds that value, so a "fix" help line would be a lie.
    > **Concern:** If the implementation folds the digits to 64 bits before the check, it will wrap without a report. The check must read `str_val` with an overflow flag, and the emitted constant must come from the checked value, never from the source text.

  - **Web/Scripting:**

    > **Reasoning:** When a value is above U64 max, a help line that offers `U64` sends the user to a fix that fails on the next build, and that costs more trust than having no help line. "No `@allow`" is right because no program needs a literal that cannot hold its value, and an allow escape would show up in copy-pasted snippets. One code with one span at the literal gives one search result.
    > **Concern:** If the no-context help line is not written well, a new user will read "does not fit in Int" and not know that `Int` was a default they never chose.

  - **PLT:**

    > **Reasoning.** A literal stands for its exact value, and one judgment, `n ⇐ T iff n ∈ range(T)`, covers every base and every integer type. E0318 is a typing error in the same class as E0300, so an `@allow` that turns it off would let a program run where its typed value differs from its written value. That is unsound by design. The text for values above U64 max is correct: no type holds the value, so a "fix" that names a type would be false.
    > **Concern.** If the literal-grammar ticket later adds a bit-pattern reading for hex, it breaks the base-free rule, and the spec text must forbid that in so many words.

  - **DevOps:**

    > **Vote:** 1A
    > **Reasoning:** If E0318 could be suppressed, the program would run with a value the user never wrote. That is the silent wrap this decision removes, so the error must have no `@allow`. Above U64 max, an "annotate as U64" help would be a fix that does not compile. So the message must say that no integer type holds the value and offer nothing.
    > **Concern:** The no-context help may show up on an annotated binding or a call argument where `let x: U64` is not the edit. The help must check the site before it offers a machine-applicable fix.

  - **AI/ML:**

    > 1. **Vote:** 1A
    > 2. **Reasoning:** One rule with one code, the same for every base, type and sign, is a fact a model can learn from the spec alone. If you can switch a range error off with `@allow`, the silent wrap comes back, and a generated program would then compile with a wrong value that no test shows. A separate message above U64 max stops the help line from offering a fix that cannot work, and a model applies a wrong fix as readily as a right one.
    > 3. **Concern:** The help line must offer `U64` only on a `let` with no annotation. If it fires in other places (an argument, a field), models will apply an edit that does not parse there.

  - **Minimalism:**

    > **Reasoning:** Both of DevOps's additions are message text, not new rules.
    > - The text for a value above U64 max stops the help line from suggesting a fix that cannot work.
    > - "No `@allow`" only restates that an error has no level.
    >
    > They cost a few words and add no concepts, so I accept them.
    >
    > **Concern:** An implementer could read "no `@allow`" as a new mechanism that needs code, when it should need nothing.

- **Q2: Unary `-` on a literal under an unsigned type** (6-0, 2a-strict)

  - **Systems:**

    > **Vote:** 2a-strict
    > **Reasoning:** A negative literal compiles to one constant, not to a `Neg` call, so the error belongs to the literal and must point at it. Checking by sign and not only by value closes the `-0` hole PLT found: no `-` form type-checks on an unsigned type. That matches what `Neg` gives for a variable, and the rule needs only one AST check.
    > **Concern:** The implementation could test the value (`< 0`) and not the written `-`, which would let `-0` through. A corpus test for `let u: U8 = -0` must pin this.

  - **Web/Scripting:**

    > **Reasoning:** "-1 does not fit in U64" uses the words the user wrote. A `Neg` trait error makes a JS dev learn about sealed traits to fix a typo. I do not care much about `-0`, but strict gives one short rule ("unsigned types hold no negative literals"), and that is easier to teach than a value rule with a zero exception. Writing `-0` for an unsigned type is noise, so rejecting it costs nothing.
    > **Concern:** A user may see E0318 on `-x` in one place and a `Neg` error on `-x` in another, and wonder why the same minus sign gives two different codes.

  - **PLT:**

    > **Reasoning.** A negative literal is a syntactic class, and that class is valid only at a signed type. Under 2a-value, `let u: U64 = -0` would get past the sealed `Neg`, and the literal rule must not punch a hole in a sealed trait. 2a-strict keeps the error about the value, as the majority wants, and keeps the trait seal sound.
    > **Concern.** The spec text must say plainly that the check is by sign class and not by value, or an implementer will write a value check and let `-0` through.

  - **DevOps:**

    > **Vote:** 2a-strict
    > **Reasoning:** One code and one span on the value the user wrote is the clearest message. It also keeps PLT's invariant that no `-` on an unsigned type ever compiles, `-0` included. The note "unsigned types hold no negative values" tells the user why `-0` fails without sending them to look for a sealed `Neg` impl they cannot add.
    > **Concern:** The `-0` case needs its own message test, or the note may disappear and leave "-0 does not fit in U8 (0..=255)", which reads as nonsense.

  - **AI/ML:**

    > 1. **Vote:** 2a-strict
    > 2. **Reasoning:** "An unsigned type takes no `-` literal" is one rule with no value test, so the model has nothing to check. It keeps PLT's coverage, because no `-` form gets through a sealed trait, and it keeps a range message that names the fix. Under 2a-value, `-0` becomes a strange valid edge that models would copy from examples.
    > 3. **Concern:** The note must say plainly that unsigned types have no unary `-`. Otherwise a model reads E0318 on `-0` as a range bug and tries a wider type.

  - **Minimalism:**

    > **Reasoning:** A strict reading is one sentence with no arithmetic: "an unsigned type has no negative literals." That matches `-x` on an unsigned variable, which also fails for every value, 0 included. So the literal rule and the trait rule give the same answer, and nobody has to learn that `-0` is a special case. A value-only reading would accept code (`let u: U8 = -0`) that no one should write.
    >
    > **Concern:** The error for `-0` must not say "does not fit in range", because 0 is in range. The note about negative values carries the whole message, so it must be on that error.

- **Q3: Parentheses around the literal (`-(128)`)** (6-0, 3-yes)

  - **Systems:**

    > **Vote:** 3-yes
    > **Reasoning:** W0704 and W0706 already read "a `-` before a literal, parentheses allowed" as written. One AST shape for three checks gives predictable tools and codegen. With 3-no, `-(128)` at I8 is an error while `-128` is fine, and the two print the same constant.
    > **Concern:** "Parentheses allowed" must stop at parentheses. `-(127 + 1)` must stay an expression, so that it never becomes a back door into constant folding (that is the const-overflow ticket's case).

  - **Web/Scripting:**

    > **Reasoning:** A JS or Python dev expects `-(128)` and `-128` to mean the same thing, and parentheses that change whether code compiles would get a Stack Overflow question. Four seats and the existing W0704/W0706 reading already treat a parenthesized literal as the literal. One reading across warnings, power-assert and range checks is easier to learn than my narrower rule.
    > **Concern:** The tooling (fmt, hover, LSP) must treat `-(128)` as one literal everywhere, or users will see the two forms behave differently in the editor.

  - **PLT:**

    > **Reasoning.** Parentheses carry no meaning anywhere else in the spec (W0704, W0706, §2.19). If `-(128)` and `-128` typed differently, a meaning-free edit would change whether a program compiles, which breaks compositionality.
    > **Concern.** "Parentheses allowed" must mean only parentheses around the literal, so `-(-5)` and `-(1 + 2)` stay ordinary `Neg` calls, and the text has to pin that.

  - **DevOps:**

    > **Vote:** 3-yes
    > **Reasoning:** W0704 and W0706 already read "a unary `-` over a literal, with optional parentheses" this way. One AST check across three diagnostics keeps the LSP and the linter consistent. If `-(128)` and `-128` gave different results at `I8`, the user would see an error they cannot explain from the text.
    > **Concern:** `blink fmt` must not remove those parentheses as part of some other rewrite, because a later rule change could then make the formatter change how a program types.

  - **AI/ML:**

    > 1. **Vote:** 3-yes
    > 2. **Reasoning:** W0704 and W0706 already read `-(0)` as a negative literal. If one more rule reads it otherwise, the spec has two meanings of "negative literal", and a model must learn which rule uses which. With one reading everywhere, a model has one fact to learn.
    > 3. **Concern:** The spec must give the shape in one place (a `-`, then any parentheses, then an integer literal) and point to it from §2.19, W0704 and W0706. If not, the four texts will drift apart.

  - **Minimalism:**

    > **Reasoning:** W0704, W0706 and §2.19 already read a parenthesized literal under `-` as one literal. If this decision reads it differently, the spec gets a second meaning of "literal". Choosing 3-no would mean one spelling of the same value gets a different answer, which is a rule that users have to learn.
    >
    > **Concern:** None worth noting. The parentheses rule is already in the spec three times.

- **Q4: A literal operand of a binary operator** (6-0, 4a+T)

  - **Systems:**

    > **Vote:** 4a+T
    > **Reasoning:** The ticket's first sign-mask line, `bits & 9223372036854775808`, is a bitwise operand, so the rule has to be decided here. If it is not, the spec still cannot say that the mask idiom compiles. The outer-T clause also makes `let m: U64 = 1 << 63` type the `1` as U64, so the compiler does not shift an Int and then convert it. That gives the code the user meant, with no hidden widening.
    > **Concern:** Interaction with the const-overflow ticket. Once both literals of `let m: U8 = 200 + 100` take U8, the sum overflows. Until the const-overflow ticket decides, that must be a run-time panic (checked arithmetic), never a silent wrap in the emitted C.

  - **Web/Scripting:**

    > **Reasoning:** `let x: U64 = 1 + 2` fails today, and a beginner writes that on day one. Without the outer-T clause, the spec still allows that rejection. `z.to_bits() & 1` is the first line the Float Bits section leads to, so the operator rule must ship with this decision, not wait on a bug ticket. It goes in one place, §3.2, and the §3.4 hint-list ticket links to it.
    > **Concern:** Users will take "two literals with no expected type are Int" one step further and expect `let x = 1 + 2` to infer from a later use, which it does not do.

  - **PLT:**

    > **Reasoning.** This is plain bidirectional checking of a homogeneous operator: synthesize the operand that is not a literal and check the literal against its type, whichever side it is on. With an outer T and a T×T→T operator, check both operands against T. Without the outer-T clause, `let m: U64 = 1 + 9223372036854775808` fails, even though every literal in it fits the type the program asked for. That is an artifact of the rule, not of the program. Putting the text in §3.2, one place with the §3.4 hint-list ticket cross-referencing it, gives the rule one owner.
    > **Concern.** The outer-T clause must stop at operators of type T×T→T. Comparisons give `Bool`, and a shift has a `U32` right operand, so neither may pass T to both sides.

  - **DevOps:**

    > **Vote:** 4a+T
    > **Reasoning:** The motivating line, `x.to_bits() & 9223372036854775808`, must compile under the spec text this decision ships. An LSP or a second compiler needs the hint positions written in one place. Today's `incompatible types U64 and Int` points at correct code, and this rule removes that error at its source.
    > **Concern:** If the §3.4 hint-list ticket later restates these positions in its own words instead of cross-referencing §3.2, the two texts will drift and the implementations will disagree.

  - **AI/ML:**

    > 1. **Vote:** 4a+T
    > 2. **Reasoning:** After *Float Bits*, people first write `x.to_bits() & 9223372036854775808`. Without the rule, that line fails, and each mask costs an extra annotated `let` (about 8 tokens). The outer-T clause costs one sentence, and it makes `let m: U64 = 1 << 63` work as a model expects. Putting the text in one place, with the §3.4 hint-list ticket pointing to it, answers Min's worry that the hint rules would be split up.
    > 3. **Concern:** Until the §3.4 hint-list ticket lands, list elements and constructor payloads still get no type hint (`let a: List[U64] = [1, 2]` fails today). So models will see the operator rule work while the same idea fails one level deeper, and they will make up a reason for the difference. That bug must be fixed with this one.

  - **Minimalism:**

    > **Reasoning:** Without an operator rule, the ticket's own first example (`to_bits() & mask`) does not compile, so the gap does not close. The outer-T clause is what check mode already means, not new surface, and `let m: U64 = 1 << 63` needs it. My Phase A objection was about where the text lives. 4a+T puts it in one place, with the §3.4 hint-list ticket pointing to it, so the objection is met.
    >
    > **Concern:** the §3.4 hint-list ticket could still grow a second list of operand positions. The moderator should write the cross-reference into the §3.4 hint-list ticket now.

- **Q5: When the literal's type is fixed** (6-0, 5a)

  - **Systems:**

    > **Vote:** 5a
    > **Reasoning:** Codegen needs one concrete type for each literal before mono, and 5a gives that with no new constraint kind and no errors that depend on solve order. The `[2^63]` into `List[U64]` motive is a missing check-mode hint, and an annotated list literal must pass its element type down. (Today that fails even for in-range elements: `let xs: List[U64] = [9223372036854775808, 1]` gives `got List[Int]`.)
    > **Concern:** If the implementation ticket does not list annotated list-literal elements (and other check-mode positions) as hint positions, 5a will look like it rejects code that obviously should compile.

  - **Web/Scripting:**

    > **Reasoning:** The same code shape should behave the same way whatever the size of the literal. Today `xs.push(5)` already fixes `List[Int]`, so a late type for big literals only would give two behaviors. The fix is an annotation, and the help line can show it. Deferred literal typing is a real feature request, and it belongs in its own ticket.
    > **Concern:** Users from Rust or TypeScript will expect `List.new()` plus `push` to infer the element type from a later annotation and will see the error as a bug, so the help line must name the annotation fix.

  - **PLT:**

    > **Reasoning.** Today a literal never leaves a type variable open, and I measured this: `xs.push(5)` then `let y: List[U64] = xs` is a type error. 5b is a new inference feature, a constrained `{integer}` variable that must default at the end. §3.4 forbids exactly that defaulting, and with it the error's position would depend on solve order. A range rule should not quietly bring in a change to inference, so if the panel wants that change it deserves its own ticket and vote.
    > **Concern.** Users who come from Rust will expect push-then-annotate to type as U64, and the help on that E0318 must point at the annotation that fixes it.

  - **DevOps:**

    > **Vote:** 5a
    > **Reasoning:** The type is decided at the literal, so the error appears at the literal, once and in a fixed order. With 5b, the place and wording of the error would depend on solve order. The `List.new()` / `push(big)` case gets a clear note ("the element type is not known here, so the literal is Int") and a machine-applicable annotation help.
    > **Concern:** Users coming from Rust will expect `push(big)` to infer `U64`, so that note and help are required, not optional, or this becomes a friction report.

  - **AI/ML:**

    > 1. **Vote:** 5a
    > 2. **Reasoning:** Under 5a, a literal's type depends only on what is written around it, and the error shows at the literal. A model writes code top to bottom and can predict that. Under 5b, whether a line compiles depends on later lines and on the order the solver runs. The fix under 5a is one annotation where the value is made, and a help line can name it.
    > 3. **Concern:** Users who come from Rust will expect `xs.push(big)` to infer `List[U64]` from a later line. The E0318 help at the push must name the annotation on the list, not only the literal.

  - **Minimalism:**

    > **Reasoning:** A deferred literal type variable is the largest addition on the ballot.
    > - It is a new kind of constraint, and its errors depend on solve order.
    > - It conflicts with §3.4's rule against defaulting.
    > - It buys one case: an empty `List.new()` that nothing hints, which one annotation fixes.
    >
    > Check mode already reaches `let xs: List[U64] = [2^63]`. Today's failure on that line is a propagation bug, not a reason to defer.
    >
    > **Concern:** If the element-hint bug and the bitwise-hint bug ship after E0318, users will see new E0318 errors on lines that 5a says are valid, and they will blame the rule.

- **Q6: Literal patterns and range-pattern bounds** (6-0, 6-yes)

  - **Systems:**

    > **Vote:** 6-yes
    > **Reasoning:** `300 =>` on a U8 scrutinee is dead code that the compiler emits today. One rule for each position where a literal gets a type keeps the check in one place. Patterns already get the scrutinee hint (DevOps measured this), so the cost is only the range check.
    > **Concern:** A range-pattern bound at the edge (`0..=255` on U8) must use the exact value, or the exhaustiveness check and the range check will disagree about the edge.

  - **Web/Scripting:**

    > **Reasoning:** A `match` on a `U64` with a big literal arm is the same intent as `==` with that literal. Giving it a different rule, or no rule, would surprise users. DevOps measured that the hint already reaches patterns, so this costs one sentence.
    > **Concern:** A range-pattern bound like `0..=18446744073709551615` reads oddly without constants, so users will ask for `U64.MAX`.

  - **PLT:**

    > **Reasoning.** A literal pattern is a literal checked against the scrutinee type, so it is the same judgment and gets the same code. Leaving it out would give two typing rules for one syntactic form.
    > **Concern.** A range pattern whose bound is a negative literal on an unsigned scrutinee must follow 2a-strict as well, and the text should say so.

  - **DevOps:**

    > **Vote:** 6-yes
    > **Reasoning:** The scrutinee hint already reaches patterns today, so this only adds the check, with the same code and span. Without it, `match b { 300 => ... }` on a `U8` would be the one place a literal still wraps silently or is silently never reached.
    > **Concern:** An out-of-range pattern can also make the exhaustiveness or unreachable-arm checks report on the same arm. Only E0318 should appear for that arm.

  - **AI/ML:**

    > 1. **Vote:** 6-yes
    > 2. **Reasoning:** A pattern literal is the same token as an expression literal. A second rule for it would be a decision point with no benefit. The scrutinee hint already reaches patterns today, so this rule only puts the current behavior in the spec and adds the range check.
    > 3. **Concern:** None of note. The text must say "scrutinee type", so that a pattern on an `Int` scrutinee with a U64-sized literal gets E0318 and is not silently unreachable.

  - **Minimalism:**

    > **Reasoning:** A literal pattern is a literal, and the scrutinee already gives it its type, as DevOps measured. Leaving patterns out would create the only kind of literal with no range check. This needs no new text beyond saying that the rule covers patterns.
    >
    > **Concern:** A range-pattern bound that is out of range could also trigger the exhaustiveness checker. That would give the user two errors for one fault.

- **Q7: An out-of-range literal in a const context** (6-0, 7-E0318)

  - **Systems:**

    > **Vote:** 7-E0318
    > **Reasoning:** Nothing is evaluated, so `ConstEvalPanic` names the wrong cause. One code at one span for a literal, in every context, keeps the diagnostic predictable. `127 + 1` stays with the const-overflow ticket, so the two codes never fire on the same span.
    > **Concern:** The const evaluator can see the literal before typecheck has reported, and give a second, wrapped value or a duplicate E0546. E0318 must run first and stop const evaluation of that expression.

  - **Web/Scripting:**

    > **Reasoning:** The user wrote a number that does not fit. Nothing ran, so "const evaluation panicked" describes something that did not happen. One code for one mistake, whatever the context.
    > **Concern:** Users may expect `const M: I8 = 127 + 1` to give the same E0318 and be confused when the const-overflow ticket gives it another code.

  - **PLT:**

    > **Reasoning.** A literal out of range is a typing failure, not an evaluation failure. Nothing runs, so E0546 would put the error in the wrong phase. This keeps the boundary with the const-overflow ticket clean: E0318 judges a literal's value, and E0546 judges evaluation.
    > **Concern.** A const whose right-hand side is `-(9223372036854775808)` must take the negative-literal path and not trip E0546 by evaluating `Neg` on an out-of-range magnitude.

  - **DevOps:**

    > **Vote:** 7-E0318
    > **Reasoning:** Nothing is evaluated, and the span is the literal. E0546 keeps its one meaning, "evaluation would panic", so `blink explain` stays honest and a CI grep for E0318 finds every bad literal.
    > **Concern:** A `const` with a sized annotation and an arithmetic right-hand side could raise both E0318 and E0546. The implementation must report only E0318 when the bad value is a lone literal.

  - **AI/ML:**

    > 1. **Vote:** 7-E0318
    > 2. **Reasoning:** One fault should get one code wherever it occurs. A model that has learned E0318 for `let` must not have to learn that `const` reports the same literal as an evaluation panic. Nothing is evaluated, so E0546 would also mislead about the cause.
    > 3. **Concern:** Readers can mix up `const M: I8 = 128` (E0318) and `const M: I8 = 127 + 1` (the const-overflow ticket, E0546). The spec must show both lines next to each other.

  - **Minimalism:**

    > **Reasoning:** Nothing is evaluated, so E0546 is the wrong family. One code for every out-of-range literal, in every context, is less to learn than a rule that depends on the context. `127 + 1` stays with the const-overflow ticket.
    >
    > **Concern:** Users may expect `const M = 9223372036854775807 + 1` to give E0318 too. The E0318 help text could point to E0546 for computed values.

### Final Spec

```blink
fn is_sign_negative_bits(x: Float) -> Bool {
    (x.to_bits() & 9223372036854775808) != 0   // OK: both literals are U64
}

fn main() {
    let mask: U64 = 9223372036854775808     // OK: 2^63 fits in U64
    let top: U64 = 1 << 63                  // OK: 1 is U64, 63 is U32
    let sum: U64 = 1 + 2                    // OK: both literals are U64
    let low = -9223372036854775808          // OK: the Int minimum, one negative literal
    let b: I8 = -(128)                      // OK: the same literal as -128

    let big = 9223372036854775808           // error[IntLiteralOutOfRange] (E0318); help: let big: U64 = ...
    let huge: U64 = 18446744073709551616    // E0318: no integer type holds the value
    let n: U64 = -1                         // E0318; note: unsigned types hold no negative values
    let z: U8 = -0                          // E0318; note: unsigned types hold no negative values
}
```

- **Value (Q1).** An integer literal is the exact integer its digits spell, in every base. A literal in any base is a value, never a bit pattern. It must be in the range of its type, else `IntLiteralOutOfRange` (E0318) at the literal: one code for every integer type, with no `@allow`. With no expected type, the message names the default `Int` and a help offers a `U64` annotation when the value fits. Above the `U64` maximum, no help.
- **Negative literals (Q2, Q3).** One unary `-` directly on an integer literal, with optional parentheses around the literal, is one negative literal. Under a signed type it is checked by its negative value. Under an unsigned type it is E0318 for every value, `-0` included. `-(-5)`, `-(1 + 2)` and `-x` stay `Neg` calls.
- **Operators (Q4).** For `+ - * / % & | ^ == != < <= > >=`, a literal operand takes the other operand's integer type, on either side. An expected type `T` on `+ - * / % & | ^` reaches both operands. Comparisons pass no expected type to their operands. Two literals with no type are `Int`. The right operand of `<<`/`>>` is `U32`; the left gets the expected type. §3.2 *Literal syntax* is the one statement of these positions.
- **Timing (Q5).** The type is fixed at the literal. A literal checked against an unsolved type variable binds it to `Int`. No deferred literal type; that would need its own type:spec decision.
- **Patterns (Q6).** Literal patterns and range-pattern bounds take the scrutinee type and use E0318.
- **Const contexts (Q7).** An out-of-range literal in a const context is E0318, not E0546. Overflow in evaluation (`127 + 1`) is a separate question.

Spec: §3.2 *Literal syntax* (*Integer literal range*), §3.3 *Numeric literals*, ERROR_CATALOG E0318.
