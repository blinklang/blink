[< All Decisions](../DECISIONS.md)

# A Trait-Qualified Method Named With No Call — Design Rationale

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) voted independently on 5 questions. The question: what do `Clone.clone`, `Display.display` and `From.from` mean when a program names them with no argument list, as in `xs.map(Clone.clone)`? Before the vote, `Trait.m` with no call gave an internal compiler error at build, or a type error that named the wrong site, depending on the method. All five votes are 6-0. Two of them are 6-0 after a 4-2 split in Phase C and a Phase D debate.

### Phase A: Positions

Five seats proposed that the answer depends on the method. Minimalism proposed O2, "an error for every shape", under a new code for `Trait.m` and `(Trait for T).m`.

- **Systems:** "A value form must not be more permissive than its own call form." The seat also measured that the value and the closure lower to the same shape: "Same shape, same cost: one static thunk, no env, a direct call into the mono'd impl method, which gcc inlines."
- **Web/Scripting:** "The rule for users: "if you can call it as `Trait.m(x, ...)`, you can pass it as `Trait.m`." That is one sentence, and it has no exceptions to learn."
- **PLT:** "A name written with no call is legal exactly when its eta-expansion is a legal closure at the same place, and it then has the type of that closure."
- **DevOps/Tooling:** "`Trait.m` with no call is a value exactly when `Trait.m(...)` is a legal call that gets `Self` from its arguments."
- **AI/ML:** "`Trait.m` with no call is legal exactly when `Trait.m(...)` is a legal call. The value form gets `Self` from the same place as the call form: the receiver slot."
- **Minimalism:** "Option (A) adds a new kind of value whose `Self` is solved by the expected type. §3c.4 *No inference of `Self`* refused exactly that inference for `Alpha.make()`." Position: O2, an error for every shape.

### Phase B: Highlights

Minimalism moved from O2 to O1 in the first round:

- "In `Same.same`, `Self` is in a **parameter** slot. The expected type `fn(Int, Int) -> Bool` fixes it from the same slot that the receiver argument fixes in `Same.same(1, 1)`. The value does not infer more than the call."
- "§3c.4 refused `Self` from a **return** slot (`Alpha.make()`), and O1 keeps that refusal: `From.from` with no call is an error, as the call is."
- "Under that criterion, O2 is the addition: it needs a new code and a new exception to the §3.4 rationale for the one qualified form §3c.4 calls "the normal form". O1 needs no new code. Burden of proof goes against O2, so I move."

The first round also fixed two measured facts. Two shapes of `Trait.m` with no call passed `blink check` and then failed in the build. A call and a read of one name already give one code (§3.4).

### Phase C: Final Vote

| Question | Sys | Web | PLT | DevOps | AI/ML | Min | Result |
|---|---|---|---|---|---|---|---|
| **Q1** `Trait.m` with no call depends on the method (O1) | O1 | O1 | O1 | O1 | O1 | O1 | **6-0 O1** |
| **Q2** Code for `From.from` with no call, and for the call | new | new | new | new | E0300 | E0300 | 4-2, then **6-0 new code** (Phase D) |
| **Q3** `W.from` help is a machine fix, with a guard | yes | yes | yes | yes | yes | yes | **6-0 yes** |
| **Q4** E0567 no-call help adds a `Trait.m` line | yes | yes | yes | yes | yes | yes | **6-0 yes** |
| **Q5** A code for `(Alpha for Widget).make` with no call | code | none | code | none | none | none | 4-2 for no code, then **6-0 no change** (Phase D) |

**Q1: `Trait.m` with no call depends on the method (6-0)**

- **Systems:** "The rule is one sentence: the value is legal when its eta-expansion is legal."
- **Web:** "`xs.map(Clone.clone)` and `xs.map(Display.display)` are the first pipeline shapes a Rust, Python or Kotlin user writes, and §3.4 already ruled twice (`Some`, generic fns) that a name and its closure are one term."
- **PLT:** "O1 adds no machinery: `Self` is one more binder on the generic-fn-as-value path (fresh var, unify, E0301 if unfixed, E0306 if no impl)."
- **DevOps:** "The value is legal when the call is legal, so a user never meets "you can call it but you cannot pass it"."
- **AI/ML:** "B adds a split that no training data teaches (legal as a call, an error as a value) and costs one more round trip for each of those sites."
- **Minimalism:** "For a method with `self`, `Self` comes from the receiver parameter slot, the same slot the call reads, so the value never infers more than the call; `From.from` stays an error, which keeps the §3c.4 refusal of `Self` from a return slot."

**Q2: one new named code for the call and the reference (6-0 after 4-2)**

- **Systems:** "The call `From.from(3)` and the reference must move together so that adding `()` does not change the code."
- **Web:** "E0300 is the catch-all that `blink explain`, editors and lint filters cannot key on."
- **PLT:** "The fault is "an associated fn names no type whose impl to run". It is not a mismatch of two types, so TypeError (E0300) gives it the wrong name."
- **DevOps:** "E0300 is the catch-all code. Editor code actions, `blink explain` and lint filters key on the code, and this fault has one cause and one repair (`W.from`)."
- **AI/ML (A):** "A named code would be a little better for a model than the broad E0300, but it changes the call form too, which is outside this ticket's gap; file it as a chore."
- **Minimalism (A):** "A new named code may be worth having, but it changes the call form too, and that is not this ticket's gap. File it as a chore if wanted."

**Q3: the `W.from` help is a machine fix, with a guard (6-0)**

- **Systems:** "The site is an error, so the fix cannot change an existing meaning; `W.from` is a §3.4 value that names its type, and after the rewrite its meaning comes from the text, not from inference."
- **PLT:** "The guard (one `Self`, one impl of the name, the rewritten site passes with no new diagnostic, as in E0505) keeps the fix sound."
- **Minimalism:** "The guard (one type, one impl, the rewritten site passes with no new diagnostic) is the E0505 rule, so no new fix rule enters the language."

**Q4: the E0567 no-call help adds a `Trait.m` line (6-0)**

- **DevOps:** "It needs no parameter name, so it is the one E0567 help that tools can paste as written."
- **AI/ML:** "...it is two tokens against about nine for the closure, with no parameter name to choose."
- **PLT:** "`Sized.len` stays out of the help but stays legal."

**Q5: `(Alpha for Widget).make` with no call (4-2 for no code, then 6-0 no change)**

- **Systems (A):** "A decided error with no catalog row has no `blink explain` page; give the impl-qualified head its own code now, not shared with `Trait.m`."
- **PLT (A):** "The code must cover the impl-qualified head only ("an impl-qualified head is a callee only"). It must not be shared with `Trait.m`, which is legal under O1."
- **Web (B):** "The behavior is decided, and a catalog code for it is diagnostics hygiene, not this ticket's question."
- **Minimalism (B):** "A missing catalog row is a catalog chore, not a spec question, and the impl-qualified head is not implemented yet, so its code can land with the head."

### Phase D: Debate on Q2 and Q5

**Q2 (4-2, then 6-0).** AI/ML and Minimalism moved to a new code.

- **AI/ML:** "My only reason for A was the size of the ticket. That is a weak reason before 1.0, where a change to a diagnostic ships at once."
- **Minimalism:** "This ticket creates the reference diagnostic. Under V1a it ships on E0300, and the chore later moves both sites. That is two CHANGELOG lines and two rounds of test and llms churn for one fault. V1b does it once."
- **Systems:** "Under V1b both sites move once, in one change, which is also the condition every seat put on Q2."
- Condition, from every seat: the call and the reference move to the new code in one change.

**Q5 (4-2, then 6-0).** Systems and PLT moved to no change.

- **Systems:** "A code with no reachable emit site is a constant that no test can prove, and a catalog row that may claim more than the parser accepts. That is worse than no row."
- **PLT:** "A row we cannot test is worse than no row, because it can drift from the behavior the head finally gets. The code belongs in the change that makes the head parse, where a test can prove it."
- **DevOps:** (the head does not parse today, even for a non-generic trait: `UnexpectedToken: expected ), got for`) "A catalog row with no emit site and no corpus row is a row that no gate can check."
- Condition, from the seats that moved: a separate chore gives the impl-qualified head its code, covers that head only, and is never shared with `Trait.m`.

### Final Spec

```blink
trait Same {
    fn same(self, o: Self) -> Bool
}

let f: fn(Int, Int) -> Bool = Same.same     // OK: Self = Int
let g = Same.same                           // E0301 at `Same.same`; help: annotate `g`
let ys = xs.map(Clone.clone)                // OK: Self = U from map's fn(U) -> R; R = U
let ss = xs.map(Display.display)            // OK: ss: List[Str]
let ws: List[W] = [1, 2].map(From.from)     // E0568 at `From.from`; help: `W.from`
let ok = [1, 2].map(W.from)                 // OK (§3.4)
let w: W = From.from(3)                     // E0568 (was TypeError E0300)
let ns = words.map(Str.len)                 // E0567, as before; no `Sized.len` line
let cs = us.map(U.clone)                    // E0567; help: closure and `Clone.clone`
```

- **Q1.** `Trait.m` with no argument list is legal exactly when its closure form is legal at that place. A method with `self` is a function value of type `fn(Self, ..) -> R`. The expected type fixes `Self` through the receiver parameter, and fixes the trait and method type parameters. Nothing fixes `Self`: E0301 at the reference, with an annotation help. The fixed `Self` has no impl of the trait: E0306 at the reference. An associated function, such as `From.from`, with no call is an error with the code of the call, span on the reference, and a help that names `W.from` first when the expected type fixes `Self`.
- **Q2.** One new code, E0568 `AssociatedFnThroughTrait`, covers the call `From.from(3)` and the reference `From.from`. It replaces TypeError E0300 at both sites, in one change. The head stays "`From.from` takes no `self`, so the call names no type whose impl to run".
- **Q3.** The `W.from` help is machine-applicable only when the expected type fixes `Self` to one type that has one impl of the name, and the rewritten site passes the checker with no new diagnostic (the E0505 rule). Otherwise it is help only.
- **Q4.** The E0567 no-call help adds a `Trait.m` line (`Clone.clone`) next to the closure, only for one owner that a program can write and that is not sealed, with the owner filter of the E0567 call help. `words.map(Str.len)` gets no `Sized.len` line.
- **Q5.** No change for `(Alpha for Widget).make` with no call: it stays "not a value" (§3c.4). No code and no catalog row in this change. A separate chore gives it a code with the impl-qualified head, never shared with E0568.
- No help names the form `(Trait for T).m`: that head does not parse yet.
