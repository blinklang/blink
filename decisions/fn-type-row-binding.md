[< All Decisions](../DECISIONS.md)

# Which fn Owns a Row in a Fn-Type Result

**Decision:** A bare `!` directly after a fn-type result is a parse error with a fix-it. `-> (fn(A) -> B ! R)` gives `R` to the returned fn. `-> (fn(A) -> B) ! R` gives `R` to the declaring fn. Elsewhere a fn type takes a bare row of one effect or `_`. A row of two or more effects is wrapped, `! (A, B)`. `blink fmt` keeps every parenthesis that decides ownership.

## Context

A fn type can carry an effect row (§4.15.1). A declaration can return a fn type and can carry its own row. In `fn f() -> fn(A) -> B ! R` the `! R` fits two readings: the row of the returned fn type, or the row of `f`. The compiler binds it to `f`. The examples in §4.5 (`with_logging`) and §4.12 (`static_files`) meant the returned fn, so the text compiled and gave the wrong type.

Two more points came up. A row of two or more effects in a comma-delimited place, such as a parameter list, is unclear: `f: fn(Row) -> Row ! DB.Read, IO.Log` can end the row at the comma or continue it. And a parenthesis can decide who owns a row, so `blink fmt` must handle it with care.

In the panel files, `p01` to `p08` name scratch programs that the panel ran against the compiler. They show these facts: the compiler rejects a row on any fn type that is not a declaration's return type (p03, p04, p05, p08); it binds a bare return row to the declaring fn (p01, p02, p07); and `handler` is a keyword (p06).

Six panelists took part: Systems (sys), Web/Scripting (web), PLT (plt), DevOps/Tooling (devops), AI/ML (aiml) and Minimalism (min).

## Summary

| Q | Question | Result | Vote |
|---|----------|--------|------|
| Q1 | A bare `!` directly after a declaration's return type, when that type is a fn type | **B**: parse error. The writer parenthesizes. | 5-1 (min: A) |
| Q2 | A bare row on a fn type outside Q1's position | **B**: bare is legal with one effect or `_`. | 5-1 (min: A) |
| Q3 | A fn type whose result is a fn type, in a type position | **A**: parse error, the same as Q1. | 6-0 |
| Q4 | A row of two or more effects in a comma-delimited place | **B**: `fn(Row) -> Row ! (DB.Read, IO.Log)`. | 5-1 after Phase D (min: A); 3-3 in Phase C |
| Q5 | `blink fmt` and parentheses | **B**: rewrites `! (A)` to `! A`; keeps every parenthesis that decides ownership. | 5-1 after Phase D (min: A); 3-3 in Phase C |

Agreed by all six, not put to a vote: parentheses around a fn type are grouping (§3.8); `-> (fn(A) -> B ! R1) ! R2` gives `R1` to the returned fn and `R2` to the declaring fn; the diagnostics are a parse error with a fix-it plus a note on `UndeclaredEffect` when the return type is a fn type, with no new lint; in `Handler[E ! R]` the `]` ends the row. Minimalism withdrew its option min-2 (outer binding only) in Phase B.

### Panel Deliberation

The panel ran in phases. Phase A: each seat wrote a proposal alone. Phase B: each seat read all six proposals and replied. Phase C: a silent ballot on five questions. Phase D: the seats debated the two questions that tied 3-3, then voted again.

#### Phase A: proposals

Each seat wrote its own rule and examples. The text below is an excerpt; "…" marks a cut.

**AI/ML (aiml-1): a bare trailing `!` after a fn-type return is an error. Parentheses say which fn owns the row.**

> 1. A row follows a fn type and binds to that fn type only. The text `fn(A) -> B ! R` is a fn type with row `R`.
> 2. In a declaration, `-> T ! R` gives `R` to the declaration. If `T` is a fn type, `T` must be in parentheses when a row follows. Without parentheses the compiler reports an error. It does not guess.
> …
> 4. In a comma-delimited place (parameter list, type arguments, tuple type, `Handler[...]`), a row with 2 or more effects is written `! (A, B)`. A row with 1 effect stays bare: `! A`. … `blink fmt` rewrites `! (A)` to `! A`. A declaration keeps the bare list (`! A, B {`), because `{` ends it.
>
> The writer never has to remember a default. Without the parentheses the compiler reports the error and names the fix. A wrong guess cannot compile and bind silently. … It is one way to write each meaning (Principle 2).

**DevOps/Tooling (devops-1): a trailing `!` binds to the innermost fn type; parentheses move it outward.**

> `! R` binds to the innermost function type whose return type has just ended. … A declaration's own row is read only when the return type has closed, either because it is not a function type or because it is in parentheses. `(T)` is grouping (§3.8), so no new syntax appears.
> …
> A row on a function type extends over the comma list that follows it. In a comma-separated context …, a function type with a row must be last or be wrapped … I reject lookahead for `ident :`. It fails in tuple types, where `Int` could be an effect name, and one rule beats two.

DevOps also wrote a fallback, devops-2: "Make it a parse error whenever the return type is a function type and a `!` follows … Parens are always required for the combined case, so there is no silent default."

**Minimalism (min-1): a trailing `!` always binds to the enclosing declaration. A row on a fn type needs parentheses.**

> 1. A bare `! R` after a return type is the row of the declaration. Never of a fn type inside the signature. This is what gen1 does today (p01, p02, p07).
> 2. A fn type carries a row only when it is parenthesized: `(fn(A) -> B ! R)`. Parentheses are grouping (§3.8 already decides this). They are legal around any type. They are required exactly when a fn type has a row.
> 3. A fn-type row ends at the closing `)`. No `,` ambiguity arises, because the row is always the last thing in its group.
>
> Minimalism: no lookahead, no precedence table, no new token, no new type form. It reuses grouping, which is already in the language.

Minimalism also wrote a fallback, min-2: state only rule 1 and fix the two examples to be pure outer fns.

**PLT (plt-1): the row binds to the innermost arrow; parentheses move it outward.**

> A `!` row is part of an arrow, not of a declaration's tail. `-> T ! R` reads as "result T, effect R" for the nearest arrow. The row is parsed greedily (maximal munch) … So in `-> fn(A) -> B ! R`, the row `R` is on the returned fn type `fn(A) -> B`. The outer fn has no row. …
>
> Soundness check: a writer who meant the outer row and wrote it bare gets `UndeclaredEffect` in the outer body (it performs the effect and has no row). No silent unsoundness.
> …
> In a type-argument list or tuple type, a multi-effect row on a fn type must be written `! (A, B)`, because `X` after the comma could be a type. … `Handler[E ! R]` uses the same row parser: R ends at `]`; several effects use `! (A, B)`.

PLT also wrote a fallback, plt-2: "Require parentheses whenever a fn return type is followed by `!` … Sound and unambiguous, but it breaks the two spec examples and forces a second way to spell the common middleware case."

**Systems (sys-1): a bare `!` always belongs to the declaration. A fn type that carries a row is always in parentheses.**

> 1. In a fn declaration, a trailing `! R` after the return type is the row of the declaration. Nothing else.
> 2. A fn type that carries a row is written `(fn(A) -> B ! R)`. The row ends at the `)`. …
> 3. A fn type without a row never needs parentheses. `blink fmt` removes redundant ones.
> 4. Bare `fn(A) -> B ! R` outside parentheses is a parse error in every position except a declaration's own row. …
>
> Effect rows are erased before codegen. A fn type with or without a row lowers to the same closure struct. This rule costs nothing at run time and needs no mono change.

**Web/Scripting (web-1): a trailing `!` always belongs to the declaration. A row on a fn type needs parentheses.**

> In a `fn` declaration, the `!` after the return type is the row of the declaration, however the return type is spelled. A fn type that carries its own row is written in parentheses: `(fn(A) -> B ! R)`.
> …
> A row on a fn type always sits inside parentheses, so the `)` ends it. … No comma rule is needed, because a comma is never inside a bare row.
> …
> A JS/TS dev knows this. TS writes `(() => void) | null` and `() => (() => void)`, and parentheses are the normal way to resolve fn-type ambiguity.

#### Phase B: replies

Each seat read all six proposals and replied. The digest shows five positions: outer binding (sys-1, web-1, min-1), innermost binding (plt-1, devops-1) and an error with parentheses (aiml-1). The position changes follow. The digest listed six open points: V1 (a bare row on a fn type outside the return position), V2 (a row of two or more effects in a comma list), V3 (`Handler[E ! R]`), V4 (what `blink fmt` does with parentheses), V5 (diagnostics) and V6 (the §4.15.1 and `06_tooling.md` examples). The text below is an excerpt; "…" marks a cut.

**aiml** held aiml-1 and ranked outer binding second and innermost third:

> The only place where a bare row has two readings is directly after a declaration's fn return type. Only that place needs parentheses. Everywhere else a bare row with one effect is legal, so the 42 `! _` rows do not change. This is the smallest set of rewrites that removes the ambiguity.
> …
> **V2.** `! (A, B)` is one token pair after `!`. Wrapping the whole fn type (sys, web, min) reads as a tuple when a comma follows (`(fn() -> Int ! IO.Log, FS.Read)` is also a tuple type). I prefer `! (A, B)`.

**devops** moved from devops-1 to aiml-1:

> every silent default (outer or innermost) produces a signature that compiles and means the other thing. The spec examples at :642 and :822 and p01 show that this mistake already happened once. An error with a fix-it cannot be misread by a human, an LSP hover or a model. It costs two parentheses in a rare shape.
> …
> **V4.** `blink fmt` rewrites `! (A)` to `! A`, never adds or removes parentheses a rule needs, and keeps `(fn(A) -> B ! R)`. Idempotent.

**plt** moved from plt-1 to aiml-1, with one extension:

> Innermost binding is the standard typing rule, but it flips what gen1 does today (p01) and moves `iter.bl:13` with no error. Both readings are sound; a silent default that changes meaning is the weak point. An error on the ambiguous text removes the choice from the type system.
> …
> 2. Where an arrow's result type is itself a fn type, a bare `!` after it is an error. This covers a declaration's return type and a fn type's result alike, so `fn(A) -> fn(B) -> C ! R` as a parameter type is also an error.

**web** moved to the aiml-1 shape, with a wrapper for several effects:

> The new fact decides it: 42 of the 45 bare fn-type rows in sections/ are `! _` in a parameter, such as `fn(self, fn(T) -> U ! _) -> List[U] ! _`. That is the 90% case of effectful callbacks. My web-1 would wrap every one of them in parentheses. That adds noise to the most common form, and every JS/Python dev who reads a `map` signature pays for it.
> …
> 3. A fn type with two or more effects is wrapped in parentheses: `f: (fn(Row) -> Row ! DB.Read, IO.Log)`. The `)` ends the row. This reuses §3.8 grouping.

**sys** held sys-1 unchanged:

> The decl row is the common case and should be the unmarked one.
> …
> Option 3 (aiml-1) is my second choice. It has no silent default, which is a real gain. But it makes `-> fn(A) -> B ! R` an error where today it compiles with a clear meaning …

**min** held min-1, ranked aiml-1 second, and withdrew min-2:

> I hold min-1. It is the only option that changes no compiler semantics (p01, p02, p07) and no existing text except two doc examples. `iter.bl:13` keeps its text and meaning.
> …
> min-2 is withdrawn. plt-1 and devops-1 are right that rows on fn types are decided, so return position must be expressible.
> …
> **V5.** One parse error with a fix-it for a bare row inside a fn type. Optionally one note on the existing `UndeclaredEffect`, as in web-1 and plt-1. I oppose sys-1's lint hint: it is a new lint to specify, and the note covers the case with no new check.

#### Phase C: silent ballot

The ballot had five questions (see the Summary). The seats voted alone. Each vote is quoted in full below, one seat at a time. Result: Q1 B 5-1 (min: A), Q2 B 5-1 (min: A), Q3 A 6-0, Q4 B 3-3, Q5 B 3-3 (sys, web, min voted A; plt, devops, aiml voted B).

**AI/ML (aiml)**

> **Q1. Vote: B** (error; the writer parenthesizes)
> - Reasoning: A silent default binds a row to one of two fns, and the model that learned the other reading gets a program that compiles and means something else. The spec examples at 04_effects.md:642 and :822 already made this mistake once (p01). An error with a fix-it turns a wrong guess into a message, at a cost of two parentheses in a rare shape.
> - Concern: A model may learn "always parenthesize a fn return type" and add parentheses where none are needed; this is harmless but costs tokens.
>
> **Q2. Vote: B** (bare is legal with one effect or `_`)
> - Reasoning: 42 of the 45 bare rows in sections/ are `! _` in method tables. These are the higher-order signatures a model copies most. Option A would require parentheses on every one, and it would make `fn(A) -> B ! R` legal as a declaration row but a parse error as a type. That is a decision point a model must memorize.
> - Concern: A bare row has two legal spellings in some places (`! A` and, with Q4 = B, `! (A)`), and a model may use either; fmt normalizes this.
>
> **Q3. Vote: A** (error, same as Q1)
> - Reasoning: One rule: a bare `!` after a fn type whose result is a fn type is an error, in every position. Option B adds a second rule ("the row binds to the nearest fn type here, but not after a declaration return") that a model has to learn as a position-dependent exception. Fewer decision points win.
> - Concern: Curried fn types with a row in a parameter need parentheses, which makes a rare shape slightly longer.
>
> **Q4. Vote: B** (`! (A, B)` in a comma-delimited place)
> - Reasoning: `(fn() -> Int ! IO.Log, FS.Read)` is also a tuple type (aiml B1 fact, 03_types.md:6534), so wrapping the fn type invites a misread by model and human. `! (A, B)` keeps the row attached to the `!`, so the model sees where the row starts and ends, and a comma never has two readings. It needs no lookahead.
> - Concern: A declaration keeps its bare list (`! A, B {`) while a type uses `! (A, B)`, so a model may write the wrong form in one of the two places; the parse error with fix-it names the correct one.
>
> **Q5. Vote: B** (fmt rewrites `! (A)` to `! A`, keeps every parenthesis that decides ownership)
> - Reasoning: One spelling for each meaning (Principle 2). Training data written by `blink fmt` will then show a single form, which helps models learn it. The rule is small: strip only parentheses around a single effect.
> - Concern: fmt must tell a parenthesis that decides ownership from a redundant one; a bug there would change the meaning of a program.

**DevOps/Tooling (devops)**

> **Q1. Vote: B**
> Reasoning: Both silent defaults give a signature that compiles and means the other thing. Gen1 already did this once (p01) and the spec examples at :642 and :822 read the opposite way. An error with two fix-its gives the same message to a person, a hover and a model. It costs two parentheses in a rare shape. Option C moves `iter.bl:13` with no error.
> Concern: Option A keeps `-> fn(A) -> B ! R` legal, so a writer who means the returned fn type gets no parse error. They get only a later `UndeclaredEffect` far from the cause.
>
> **Q2. Vote: B**
> Reasoning: 42 of the 45 bare rows are `! _` in method signature tables and parameters. They are the signatures people and tools read most. Forcing parentheses on all of them adds noise to every hover and every `blink doc` line. It also makes "same `!` syntax as a declaration" (§4.15.1) false. Only one position has two readings, and Q1 handles it.
> Concern: Option A would give one uniform rule, and B means a bare row is legal in some places and an error in one place. The error text must name the place so the parse error is clear.
>
> **Q3. Vote: A**
> Reasoning: `f: fn(A) -> fn(B) -> C ! R` has the same two readings as Q1. It is only the same text in another place. If it is legal, the formatter, the LSP hover and the error catalog need a second explanation for the same shape. One rule, "a bare row after a fn-type result is an error", is easier to document and to detect.
> Concern: Option B is a rule a writer must remember, so a writer who moves a signature from a return position to a parameter gets a different meaning with no error.
>
> **Q4. Vote: B**
> Reasoning: With `! (A, B)` the row has its own delimiter, so the parser needs no lookahead on `ident :` and no rule for the position in the list. A tuple type `(fn() -> Int ! IO.Log, FS.Read)` is also a valid tuple of two types, so wrapping the fn type reads wrong to a person and to the parser. The error "effect row in a comma list needs parentheses: `! (A, B)`" is simple to emit and to fix by machine.
> Concern: Option A reuses only grouping, so B adds a row-list form next to the `! ()` rule at 04_effects.md:97, and `! (A)` becomes a second spelling that the formatter must handle.
>
> **Q5. Vote: B**
> Reasoning: One spelling for each meaning, and `blink fmt` must be idempotent. Rewriting `! (A)` to `! A` is a local, safe change. The formatter keeps every parenthesis that decides ownership, such as `(fn(A) -> B ! R)` and `(fn(A) -> B) ! R`. Option C also strips redundant parentheses around a pure fn type, which is a separate change that I do not need.
> Concern: A rewrite rule adds one more case to specify and test, and a bug in it would change meaning only if it removed an ownership parenthesis.

**Minimalism (min)**

> **Q1. Vote: A**
> Reasoning: A bare `!` after a return type is the declaration's row. gen1 already does this (p01, p02, p07), and lib/std/iter.bl:13 keeps its text and meaning. It adds no rule to the grammar, only one sentence to the spec. Option B turns a form that compiles and has one meaning today into an error. Option C reverses gen1 and rewrites iter.bl:13.
> Concern: A writer who copies the old :642 and :822 examples gets the row on the outer fn, and only the existing effect error plus its note catches it.
>
> **Q2. Vote: A**
> Reasoning: One spelling for a row on a fn type in every position: parentheses, with `)` ending the row. This needs no lookahead and no "last in list" rule. It also avoids a bare form that is legal in one place and a parse error in another, which is what B would create next to Q1-A. The 42 `! _` rows are doc edits, and no code in lib/, src/ or tests/ uses them today.
> Concern: Method signature tables get noisier, for example `fn(self, (fn(T) -> U ! _)) -> List[U] ! _`, and readers see this on the most common effectful callback.
>
> **Q3. Vote: A**
> Reasoning: Q3 applies only if Q1 = B and Q2 = B. If it applies, a bare row after a fn-type result must be an error, so the rule is the same in a type position as in a declaration. A different rule for the same text by position would add a second special case.
> Concern: If B wins Q1 and Q2, this vote adds a second place where bare `!` is an error, and that grows the special-case list.
>
> **Q4. Vote: A**
> Reasoning: Wrapping the fn type reuses grouping (§3.8) that is already in the language. `! (A, B)` adds a new row-list form, makes `! (A)` a second spelling, and sits next to the `! ()` rule at 04_effects.md:97 (`! (), IO` is a parse error). Under Q2-A the row always ends at `)`, so no comma rule is needed.
> Concern: `(fn(Int) -> Int ! IO.Log, FS.Read)` reads like a tuple type at first glance, which aiml's B1 flags.
>
> **Q5. Vote: A**
> Reasoning: Parentheses decide ownership of a row, so `blink fmt` must not add or remove them. A rule for which parentheses are redundant is more spec text and more formatter code. Keeping what it finds is the smallest rule and is idempotent.
> Concern: Redundant parentheses such as `-> (fn(A) -> B)` stay in code, so two spellings of one type survive in the wild.

**PLT (plt)**

> **Q1. Vote: B**
> Reasoning: Outer and innermost binding are both sound typing rules. Each gives one meaning to text that the other reading also fits, so a writer who guesses wrong gets a program that compiles and has the wrong type (p01 shows this already happened in the spec examples). A parse error with two fix-its removes the choice from the type system, so no reading can be wrong silently. It costs two parentheses in a rare shape.
> Concern: Option A (outer binding) keeps a silent default, so a model or human that reads `-> fn(A) -> B ! R` as the returned fn's row compiles and mis-types.
>
> **Q2. Vote: B**
> Reasoning: §4.15.1 already decided that a fn type carries a row with the same `!` syntax as a declaration. Forcing parentheses everywhere (A) breaks that rule for every fn type to fix a clash that exists in one position only. A single effect or `_` ends itself, so no comma problem arises and the 42 `! _` rows stay valid.
> Concern: Bare is legal in some places and a parse error in one place (Q1), and a writer must learn that position.
>
> **Q3. Vote: A**
> Reasoning: The ambiguity is the same in both positions: a row after a result type that is itself a fn type has two owners. One rule, "a bare `!` after an arrow whose result is a fn type is an error", covers declaration and fn-type results alike and has a plain typing reading. Option B would add a greedy-binding rule for type positions and a no-default rule for declarations, which are two rules for one shape.
> Concern: Parentheses in type positions like `f: fn(A) -> (fn(B) -> C ! R)` make nested callback types heavier to read.
>
> **Q4. Vote: B**
> Reasoning: `! (A, B)` puts the delimiter on the row itself, so the row is the only thing that changes and the fn type keeps its shape. Wrapping the fn type (A) gives `(fn() -> Int ! IO.Log, FS.Read)`, which is also a valid tuple type of a fn type and an effect-looking path, and this reads as a different type by the §3.8 and tuple rules. Option B has no lookahead and no tuple clash.
> Concern: A row now has two forms (bare list in a declaration, parenthesized list in a comma context), and `! (A)` is a redundant spelling.
>
> **Q5. Vote: B**
> Reasoning: One spelling per meaning requires fmt to turn `! (A)` into `! A`. Parentheses that decide ownership, such as `-> (fn(A) -> B) ! R` and `-> (fn(A) -> B ! R)`, change the type and fmt must keep them. This rule is idempotent and never changes meaning.
> Concern: fmt must tell grouping parentheses that decide ownership from redundant ones, and a bug there changes the type of a signature.

**Systems (sys)**

> **Q1. Vote: B** (a bare `!` after a fn-type return is an error).
> Reasoning: Rows are erased before codegen, so all three options lower to the same closure struct. Cost to the hardware is zero. The difference is only the cost of a wrong guess. Under A the old spec examples (:642, :822) already meant one thing and compiled as another (p01). Under B the same text cannot compile, and the error names the fix. I move from sys-1 because B gives each meaning one spelling and no silent default, at no run-time cost.
> Concern: `lib/std/iter.bl:13` and every `@ffi` decl that returns a fn type must be rewritten to `-> (fn() -> ...) ! FFI`, and a missed one becomes a hard error in the stdlib build.
>
> **Q2. Vote: B** (bare row legal with one effect or `_`, outside Q1's position).
> Reasoning: The 42 `! _` rows are the common higher-order signatures. Forcing parentheses there adds tokens and a second rule (legal in one place, error in another) for no codegen or soundness gain. With Q1 = B the only place with two readings is already an error, so bare elsewhere has one reading.
> Concern: A one-effect bare row and a parenthesized one are two spellings, and fmt must treat them under Q5.
>
> **Q3. Vote: A** (an error, the same as Q1-B).
> Reasoning: `fn(A) -> fn(B) -> C ! R` in a type position has the same two readings as a declaration return type, nested one level. Allowing it bare would make one rule (bind to the fn type it follows) hold in type positions and fail in declarations. One error rule for "fn result is a fn type followed by a bare row" is simpler to implement and to explain. This also keeps p07-style nesting from binding silently.
> Concern: A writer of a curried callback type pays two parentheses on a shape that the type grammar could have read unambiguously.
>
> **Q4. Vote: A** (wrap the fn type: `f: (fn(Row) -> Row ! DB.Read, IO.Log)`; the `)` ends the row).
> Reasoning: It adds no new row form. It reuses grouping (§3.8) and never puts `(` after `!`, so it stays clear of the `! ()` and `! (), IO` rules at 04_effects.md:97. The parser needs no lookahead: inside the parentheses the row runs to `)`. It also costs nothing at run time.
> Concern: `(fn() -> Int ! IO.Log, FS.Read)` looks like a tuple type to a reader, so the diagnostic must say that a row follows `!` up to `)`.
>
> **Q5. Vote: A** (fmt keeps the parentheses it finds; adds or removes none).
> Reasoning: With Q1 = B, `-> (fn(A) -> B) ! R` carries ownership in a parenthesis around a fn type with no row. Option C would strip it and turn a valid signature into the Q1 error. So I withdraw C from sys-1. A is the one rule that cannot change meaning, and fmt stays idempotent.
> Concern: Redundant parentheses stay in the code base, so two spellings of the same meaning can exist in user code without fmt removing them.

**Web/Scripting (web)**

> **Q1.** Vote: B
> Reasoning: A bare `!` after a fn return type has two readings, and the spec examples at 04_effects.md:642 and :822 show the mistake already happened once (gen1 binds outer, the examples meant inner). An error with a fix-it means a JS/Python dev or a model never guesses wrong silently, and the cost is two parentheses in a rare shape. Neither silent default (A or C) survives that test, since each reverses the other's meaning without a message.
> Concern: `lib/std/iter.bl:13` and every `@ffi` decl that returns a fn type needs an edit, and the error must name both fixes or users will bounce off it.
>
> **Q2.** Vote: B
> Reasoning: 42 of the 45 bare rows are `! _` on callback parameters in method tables, which is the most common effectful-callback form and the one a newcomer reads first. Forcing `(fn(T) -> U ! _)` on all of them taxes the 90% case to fix a problem that only exists after a return type. One effect ends itself, so no comma problem arises.
> Concern: "Bare is legal here but an error there" is a position-dependent rule, and learners will hit the Q1 error before they understand why.
>
> **Q3.** Vote: A
> Reasoning: `fn(A) -> fn(B) -> C ! R` as a parameter type has the same two readings as Q1 (row on the inner fn or on the outer). One rule, "a bare row after a fn-typed result is an error", is easier to teach than one rule for declarations and another for types. Currying types with rows are rare, so the parentheses cost almost nothing.
> Concern: The rule now needs wording that covers "result type is a fn type" in both declarations and types, and a parser that checks it in both places.
>
> **Q4.** Vote: A
> Reasoning: Wrapping the fn type reuses §3.8 grouping, which every dev already knows from TS `(() => void) | null`. `! (A, B)` adds a second parenthesized row form next to the bare declaration list and a `! (A)` spelling that fmt must rewrite. The tuple-look concern is real but small, because `(fn() -> Int ! IO.Log, FS.Read)` has a `!` inside, which no tuple type element has at the top level.
> Concern: `(fn(Row) -> Row ! DB.Read, IO.Log)` can read as a tuple type to a skimming reader, and the parser must still pick the grouping reading.
>
> **Q5.** Vote: A
> Reasoning: Under Q4-A the parentheses that carry a row change meaning, so fmt must keep them. A formatter that keeps what it finds and adds or removes nothing is the easiest rule to explain and the least surprising for users. Redundant-paren stripping (C) is a second rule I do not need.
> Concern: Redundant parentheses around a pure fn type will survive fmt, so two spellings of one type can exist in a codebase.

Phase C settled Q1 to Q3. Q4 and Q5 tied 3-3, so the panel went to Phase D.

#### Phase D: debate on Q4 and Q5

Each seat read all six Phase C votes and replied. Each stated its position, answered the strongest point from the other side, and said whether it would accept the other option. Excerpts follow; "…" marks a cut.

**devops** (holds B) found that a decided question changes the Q4 argument:

> Q2 = B (decided 5-1) removes that argument. Q2-B makes a bare one-effect row legal in a tuple element. So `(fn() -> Int ! IO.Log, FS.Read)` has two valid parses: a grouped fn type with a two-effect row, and a tuple of `fn() -> Int ! IO.Log` and the type `FS.Read`. Under Q4-A the parser or a rule must pick one and the reader cannot tell which. Under Q4-B a comma after a bare row always starts the next element, so the text has one reading and `! (A, B)` has one reading.

**plt** (holds B):

> I accept that this is a real saving in the grammar. But the saving is in the grammar, not in the reader. … With `! (A, B)` the row has its own delimiter and the fn type keeps its shape. The `! ()` rule at 04_effects.md:97 covers the empty row on `@ffi` only, so a non-empty list after `!` does not clash with it.
> If A wins I accept it. Both options are sound and need no lookahead.

**aiml** (holds B):

> Under Q4-A a row on a fn type has a different shape by effect count: bare for one effect, a wrapped fn type for two or more. Under Q4-B the shape of the fn type never changes; only the row grows, and `! (A, B)` starts right at the `!`.

**sys** (held A) said how its Q5 vote depends on Q4:

> If Q4 = B wins, I vote Q5-B. Then `! (A)` is a redundant second spelling, and fmt should remove it and keep every ownership parenthesis. I do not accept Q5-C under any Q4 result (it strips `-> (fn(A) -> B) ! R`).

**web** (held A) set a condition for accepting B:

> **If B wins:** I accept it. It needs no lookahead and the error text "effect row in a comma list needs parentheses: `! (A, B)`" is clear. I ask that the spec show one worked example per place (parameter, type argument, tuple).

**min** (held A) set a condition for accepting B:

> If B wins I accept it. It needs no lookahead, and the cost is one new form. I would then want the spec to say that `! (A, B)` is legal only in a comma-delimited type place, and that a declaration keeps its bare list.
> …
> If Q4 = B and Q5-B wins, I accept it. The rule is small: strip only parentheses around a single effect, and keep every parenthesis that decides ownership.

All six accepted the other option if it won. Q5-B applies only if Q4 = B.

#### Phase D: second silent ballot on Q4 and Q5

The seats voted alone again. Each vote is quoted in full. Q4 went B 5-1 and Q5 went B 5-1. aiml, plt and devops held B. sys and web moved from A to B after devops's point on the tuple reading. Minimalism held A on both.

**AI/ML (aiml)**

> **Q4. Vote: B** (`f: fn(Row) -> Row ! (DB.Read, IO.Log)`; a declaration keeps its bare list)
> - Reasoning: Q2 = B lets a bare one-effect row sit in a tuple element or type argument. So `(fn() -> Int ! IO.Log, FS.Read)` has two readings: a grouped fn type with a two-effect row, or a tuple of a fn type and the path `FS.Read`. Under B a comma after a bare row always starts the next element, and `! (A, B)` has one reading. A model learns one rule: a row in a comma place with two or more effects goes in parentheses right after `!`, and the parse error with fix-it names it.
> - Concern: A model may write the bare list `! A, B` in a type place or the parenthesized list in a declaration, so the two error messages must each show the correct form.
>
> **Q5. Vote: B** (fmt rewrites `! (A)` to `! A`; keeps every parenthesis that decides ownership)
> - Reasoning: One spelling per meaning (Principle 2), so fmt output, which becomes training data, shows one form for a single-effect row. The rule is local: it touches only parentheses that directly follow `!` and enclose one effect, never parentheses around a fn type. If Q4 = A this vote counts as A, and I accept that.
> - Concern: If fmt confuses an ownership parenthesis with a redundant one, it changes the type of a signature, so the rule needs tests for both shapes.

**DevOps/Tooling (devops)**

> **Q4. Vote: B** (wrap the row: `f: fn(Row) -> Row ! (DB.Read, IO.Log)`; a declaration keeps its bare list)
> - Reasoning: Q2 = B lets a bare one-effect row sit in a tuple element, so `(fn() -> Int ! IO.Log, FS.Read)` has two parses (a grouped fn type with two effects, or a tuple of a fn type and a type). With B, a comma after a bare row always starts the next element, and `! (A, B)` has one reading. The diagnostic is one line with a machine fix: "effect row in a comma list needs parentheses: `! (A, B)`". The LSP hover and `blink doc` show the same fn type shape for one effect or many.
> - Concern: A row has two forms (bare in a declaration, parenthesized in a comma place), and the error text must say where each applies or users bounce off it.
>
> **Q5. Vote: B** (fmt rewrites `! (A)` to `! A`; keeps every parenthesis that decides ownership)
> - Reasoning: One spelling per meaning, and the rewrite is local: it touches only parentheses that follow `!` and enclose one effect. These never decide ownership, so the rewrite cannot change a type or break idempotence. If Q4 = A, this vote counts as A and I accept that.
> - Concern: If the rewrite ever matches a parenthesis around a fn type instead of around a row, it turns a valid signature into the Q1 error, so the fmt golden tests must cover `-> (fn(A) -> B) ! R`.

**Minimalism (min)**

> **Q4. Vote: A** (wrap the fn type: `f: (fn(Row) -> Row ! DB.Read, IO.Log)`; the `)` ends the row)
> Reasoning: A reuses grouping (§3.8), which is already in the language, and adds no row form. B adds `! (A, B)`, a second row-list form and a `! (A)` spelling, beside the `! ()` rule at 04_effects.md:97. plt's tuple-ambiguity point is real, but a fixed rule settles it with no lookahead: inside the wrapping parentheses a row runs from `!` to `)`. A tuple of an effectful fn type and another type then needs its own parentheses, `((fn() -> Int ! IO.Log), Int)`, which is rare.
> Concern: `(fn() -> Int ! IO.Log, FS.Read)` still reads like a tuple type to a skimming reader, so the diagnostic must say that a row runs to `)`.
>
> **Q5. Vote: A** (fmt keeps the parentheses it finds; adds or removes none)
> Reasoning: Under Q4 = A no redundant row parenthesis exists, so B has no target and counts as A. A parenthesis can decide row ownership, so the smallest safe rule is that fmt neither adds nor removes any. It is idempotent and cannot change meaning.
> Concern: Redundant parentheses such as `-> (fn(A) -> B)` survive fmt, so two spellings of one type can stay in user code.

**PLT (plt)**

> **Q4. Vote: B** (`f: fn(Row) -> Row ! (DB.Read, IO.Log)`; a declaration keeps its bare list)
> **Reasoning:** The row is an attribute of the fn type. B changes only the row, and the type keeps its shape when a second effect is added. A wraps the whole type and gives `(fn() -> Int ! IO.Log, FS.Read)`. Q2 = B makes a bare one-effect row legal in a tuple element, so that text has two valid parses: a grouped fn type with a two-effect row, and a tuple of `fn() -> Int ! IO.Log` and the type `FS.Read`. A needs a tie-break rule to pick one parse. Under B a comma after a bare row always starts the next element, and `! (A, B)` has one reading, with no lookahead. The `! ()` rule (04_effects.md:97) covers only the empty row on `@ffi`, so it does not clash.
> **Concern:** A row has a bare form in a declaration and a parenthesized form in a type, and a writer may use the wrong one; the parse error with a fix-it must name the right form.
>
> **Q5. Vote: B** (fmt rewrites `! (A)` to `! A`; it keeps every parenthesis that decides ownership)
> **Reasoning:** One spelling per meaning (Principle 2), and the rule is local: it touches only parentheses that directly follow `!` and enclose one effect. These never decide ownership, so fmt cannot change a type or turn `-> (fn(A) -> B) ! R` into the Q1 error. If Q4 = A, this vote counts as A, and I accept that.
> **Concern:** fmt must tell an ownership parenthesis from a redundant one, and a bug there would change the type of a signature.

**Systems (sys)**

> **Q4. Vote: B** (wrap the row: `f: fn(Row) -> Row ! (DB.Read, IO.Log)`; a declaration keeps its bare list)
> Reasoning: Rows are erased before codegen, so both options cost nothing at run time; I judge only the parse. I held A because it adds no row form and claimed `!` makes the grouping reading the only one. devops D1 shows the claim fails once Q2 = B: a bare one-effect row is legal in a tuple element, so `(fn() -> Int ! IO.Log, FS.Read)` parses as a grouped fn type with two effects and as a tuple of two types. Under B a comma after a bare row always starts the next element, so every text has one reading and the parser needs no rule to choose.
> Concern: A row has two forms (bare list in a declaration, `! (A, B)` in a comma place), so a writer can put the wrong form in the wrong place; the parse error must name the correct one.
>
> **Q5. Vote: B** (fmt rewrites `! (A)` to `! A`; keeps every parenthesis that decides ownership)
> Reasoning: With Q4 = B, `! (A)` is a redundant second spelling of a one-effect row. The rewrite touches only parentheses that directly follow `!` and enclose one effect, so it never touches `-> (fn(A) -> B) ! R` and cannot change meaning. It keeps fmt idempotent and gives one spelling per meaning. This matches my D1 statement.
> Concern: fmt must separate a parenthesis after `!` from one around a fn type; a bug there would change the type of a signature.

**Web/Scripting (web)**

> ## Q4
> **Vote:** B
> **Reasoning:** I held A in D1, and devops's point moves me. Q2 = B (5-1, including my vote) makes a bare one-effect row legal on a fn type in any position. So `(fn() -> Int ! IO.Log, FS.Read)` now has two valid readings: a grouped fn type with a two-effect row, or a tuple of a fn type and the type `FS.Read`. My D1 answer ("no tuple element has a top-level `!`") no longer holds once a bare row may sit inside a tuple element. A JS/Python dev or a model cannot tell which reading wins. With `! (A, B)` a comma after a bare row always starts the next element, so each text has one reading. I accept the cost that a row grows a parenthesized form at two effects; the fix-it error "effect row in a comma list needs parentheses: `! (A, B)`" makes that cost small.
> **Concern:** A declaration keeps `! A, B` while a type needs `! (A, B)`, so devs will hit the parse error when they copy a row between the two places.
>
> ## Q5
> **Vote:** B
> **Reasoning:** Q5-B has force only when Q4 = B, and then `! (A)` is a redundant spelling. fmt rewrites only parentheses directly after `!` around one effect, and keeps every ownership parenthesis, so it cannot change meaning or turn `-> (fn(A) -> B) ! R` into the Q1 error. One spelling gives users and models one form in fmt output. If Q4 = A wins, this vote counts as A and I accept that.
> **Concern:** fmt must tell an ownership parenthesis from a redundant one, and a bug there silently changes a signature's type.

Q4 B 5-1 and Q5 B 5-1. Minimalism's dissent stands in its own words above. No owner tiebreak was used.

### Points the ruling does not settle

The panel did not vote on these points. The spec text takes the reading below, and a later ruling can change it.

- The spec wraps a row of two or more effects wherever a fn type appears, not only in a comma place. This reads "everywhere else a fn type takes a bare row of one effect or `_`" at its plain meaning.
- The ruling does not say whether `! (A, B)` is legal or an error on a declaration. Minimalism asked in Phase D that the spec limit it to a comma-delimited type place. The spec says only that a declaration keeps its bare list.
- A fn type in the result of a fn type takes its parentheses on the result: `f: fn(A) -> (fn(B) -> C ! R)` for the inner fn type, `f: fn(A) -> (fn(B) -> C) ! R` for the outer one.
- In a tuple or a type argument list, `FS.Read` after a comma can read as a type name. The catalog says `RowListNeedsParens` fires where the item after the comma names an effect. How the parser tells the two apart is left to the implementation.
- The two error codes are one per message: `RowOwnerAmbiguous` for the owner, `RowListNeedsParens` for the list.
- `lib/std/iter.bl` must change to `-> (fn() -> fn() -> Option[T]) ! FFI`. This is an implementation task and not part of this change.

### Final Spec

```blink
// A bare `!` right after a fn-type result is a parse error. The writer chooses the owner.
fn with_logging(next: fn(Request) -> Response) -> (fn(Request) -> Response ! IO.Log) { ... }   // the returned fn has the row
fn open_reader(path: Str) -> (fn(Int) -> Int) ! FS.Read { ... }                              // the declaration has the row
fn make(path: Str) -> (fn(Int) -> Int ! IO.Log) ! FS.Read { ... }                            // both

// Elsewhere a fn type takes a bare row of one effect or `_`.
fn pick(f: fn(Row) -> Row ! DB.Read, n: Int) -> Int ! DB.Read { n }

// Two or more effects on a fn type are wrapped. A declaration keeps its bare list.
fn transform(f: fn(Row) -> Row ! (DB.Read, IO.Log)) -> List[Row] ! DB.Read, IO.Log { ... }
```

- A bare `!` directly after a fn-type result is the parse error `RowOwnerAmbiguous` (E1135), with a fix-it, in a declaration and in a type alike.
- `-> (fn(A) -> B ! R)` gives `R` to the returned fn. `-> (fn(A) -> B) ! R` gives `R` to the declaring fn. `-> (fn(A) -> B ! R1) ! R2` gives `R1` to the returned fn and `R2` to the declaring fn.
- Parentheses around a fn type are grouping (§3.8).
- Elsewhere a fn type takes a bare row of one effect or `_`. The `! _` rows stay.
- A row of two or more effects on a fn type is written `! (A, B)`. A bare list after a comma is the parse error `RowListNeedsParens` (E1136), with a fix-it. A declaration keeps its bare list.
- In `Handler[E ! R]` the `]` ends the row. Several effects are written `Handler[E ! (A, B)]`.
- `blink fmt` rewrites `! (A)` to `! A`. It keeps every parenthesis that decides ownership.
- `UndeclaredEffect` (E0500) gets a note when the return type of the declaration is a fn type. No new lint.
- An `@ffi` declaration that returns a fn type is written `-> (fn() -> T) ! FFI`.
