[< All Decisions](../DECISIONS.md)

# Bounds on a Type Declaration — Design Rationale

**Gap:** §3b.2 and §3.6 let a type declaration carry a bound, as in `type S[T: Tr]`. The spec did not say where the compiler checks that bound. A call to a generic fn checks the bound on its binder (E0306), but `S { v: Bad { x: 1 } }`, `fn f(s: S[Bad])` and `fn f[U](s: S[U])` named an `S[X]` with no check. The panel also had to say what a body can call through such a bound, how many errors a rigid parameter gives, and what the error shows.

**Result:** 6-0 on every question (Q1 to Q4). A bound written on a type declaration holds at each place a program writes or infers the type. The error code is E0306 (E0523 for `Display`). Q1 and Q4 were settled in Phase B round 1. Phase A split on Q2 and Q3 (Systems and Minimalism chose A); both moved to B in Phase C. No Phase D (all votes were unanimous).

| Q | Result | Tally |
|---|---|---|
| Q1 | The error at a value points at the head: `S` in `S { v: Bad { x: 1 } }`, `E.L` for a variant. A note says `T := Bad` | 6-0 |
| Q2 | A rigid type parameter reports once per binder and trait, at the first occurrence in source order. A concrete argument reports per site | 6-0 |
| Q3 | After E0306 on (U, Tr), the checker goes on as if `U: Tr` were written, in a program that is already rejected. A method outside `Tr` still reports. A concrete argument shows both errors | 6-0 |
| Q4 | E0306 carries `note: S declares T: Tr at a.bl:5:8`, in JSON too, and on the call form of E0306 | 6-0 |

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated in independent-proposal → debate → vote rounds. The excerpts below are verbatim. Code names for probes and ticket numbers are cut.

#### Phase A — Independent proposals

All six seats voted to keep the form and to check it at every place that names the type.

- **Systems:**
  > Keep the form. Treat the bound as a condition on the type `S[X]`, not on a construction. `S[Bad]` is not a type, so no program has it in any position. There is no run-time check, no dictionary, and no layout change: the bound exists only in the type checker, and mono sees the same code as today.

- **Systems, on why not construction only:**
  > `let x: Option[S[Bad]] = None` and `fn f(s: S[Bad])` make no `S` value, so a construction check does not see them. Their instances still reach mono and layout.

- **Web/Scripting:**
  > Keep the form and enforce it everywhere. **A bound on a type's parameter holds at every place a type argument for that parameter is written or inferred.** Use the same code as calls (E0306, E0523 for Display). The bound adds no implied bounds and no new method lookup.

- **Web/Scripting, on the span of a value (the Phase A position on Q1, later withdrawn):** the Phase A table said `E.L(Bad { x: 1 })` gives "E0306 on the argument", and `let s = S { v: Bad { x: 1 } }` gives "E0306 on `Bad { x: 1 }`".

- **PLT:**
  > Keep the form. The bound restricts the type constructor, so `S[Bad]` is not a type. One judgement: `Γ ⊢ τ wf`, where Γ is the binders in scope with their written bounds. `S[τ]` is well formed when τ is well formed and `Γ ⊢ τ : Tr`, by the judge that E0306 uses at a call. Every type must be well formed: each written type, and each type that inference solves (judged at the end of inference). Reachability does not matter, so an uncalled fn with a bad signature is an error.

- **DevOps/Tooling:**
  > Keep the form. A bound on a type declaration is a rule on the **type**, not on the value. Check it at every place that names or infers an instantiation. Use E0306 at the place the user can repair. Grant no implied bounds.

- **AI/ML:**
  > `S[X]` must satisfy the bounds of `S`, wherever the program writes or infers it. A failure is E0306 (E0523 for `Display`). The bound gives no body any method. There are no new codes, no new syntax and no new decision for the writer of code.

- **Minimalism:**
  > Keep the form. A bound on a type binder follows the fn binder rule: the argument satisfies the bound or the program is rejected, with E0306. No new code, no implied bounds, no new power in bodies. Second choice: remove the form. Last: status quo, where a written bound does nothing.

- **Minimalism, on removal (a Phase A fallback; no seat proposed it after Phase B):**
  > **Remove the form.** Haskell removed `DatatypeContexts` because it forced repetition and gave nothing back. Rust guidance avoids bounds on structs. But `@invariant` is the only body a type declaration owns, and it has no other place to write a bound. `SortedList[T]` becomes unwritable, a `where` on the invariant would be new syntax, and removal needs a new error code. If the panel drops generic invariants that call a trait method, I vote for removal.

#### Phase B — Debate highlights

**Q1 (the span at a value).** Web/Scripting moved from the argument to the head. Every seat then voted for the head.

- **Web/Scripting (changed from Phase A):**
  > I withdraw "E0306 on the argument". The head works in every case; the argument does not: `type P[T: Tr] { xs: List[T] }` with `P { xs: [Bad { x: 1 }] }`: no argument has type `T`. `type Q[T: Tr] { a: T, b: T }`: two arguments, so I would have to pick one. It also matches the span a generic call has today. The message still says "`Bad` does not satisfy", so the reader sees the cause.

- **PLT:**
  > A parameter can get its argument from two fields, from an expected type, or from no field at all, as in `E.N` or a phantom. Only the head exists in each case. Keep the note `T := Bad`; when one field fixed `T`, add a secondary label there.

- **DevOps/Tooling:**
  > A value argument does not always exist: `Ph { n: 1 }` has none for a phantom parameter, and `P { a: Good {...}, b: Bad {...} }` has two candidates. A head always exists, so the caret rule stays one rule.

**Q2 (how many reports for a rigid parameter).** Phase B split: PLT, DevOps/Tooling, AI/ML and Web/Scripting chose B (once per binder); Systems and Minimalism chose A (per site).

- **PLT:**
  > B for a rigid parameter, keyed on (binder, trait). One report is enough to reject the program. Three reports of one binder edit also give three machine fixes that collide (`U: Tr: Tr`). Report at the first occurrence in source order. A concrete argument stays per site.

- **Web/Scripting:**
  > One edit clears all four sites, so four reports add only noise. I key on the binder, not the item, so a method signature inside `impl[T] Q for S[T]` does not repeat the header's report. A concrete `S[Bad]` stays per site, because each site can have its own repair (`S[Good]` here, `S[Other]` there).

- **Systems (A):**
  > Per site needs no state and no normative dedupe rule. aiml's point is real, but the form is rare. Dedupe can come later and breaks no program.

- **Minimalism (A):**
  > Each site reports. Dedupe by item + parameter + trait is a new rule and new checker state, and it hides sites from an LSP. The one machine-applicable repair clears all sites at once, so the extra lines cost no extra fix.

**Q3 (what a body sees after the error).**

- **PLT:**
  > Rigid gives one error, concrete gives two. One mechanism gives this, with no poison type. After E0306 on (U, Tr), the checker continues with `U: Tr` in Γ, which is the exact state after the repair.

- **Systems (A):**
  > Web's one error for `fn d[U]` holds today only because the body check gives nothing and E0306 stops the build before mono. Once the rule on unbounded use lands, it is two true errors, cleared by one edit. What I need: no error reaches mono, so no ICE. A poison state adds a type-checker state to save one line.

- **Minimalism (A):**
  > No poison type, no suppression rule. The checker reports what is true.

- **DevOps/Tooling:**
  > Concrete: both errors, source order, no poison type. The second error stays true if the user writes `S[Good]` only in the signature and keeps a `Bad` elsewhere, so nothing permits its removal.

**Q4 (the note).** Every seat voted for the note in round 1. Minimalism changed from Phase A.

- **Minimalism (changed from Phase A):**
  > My reason for omitting it was that the message names `S`, `T` and `Tr`. It does not say where, and the declaration can be in another module. A note adds no language surface. Use plt's one-line form, not a second source snippet. One judge gives one message, so the call form gets the note too. Today's call E0306 has none (measured).

- **AI/ML:**
  > The binder is often in another file, and a model with no such file open needs it.

**Field defaults.** AI/ML withdrew its Phase A claim that field defaults sit under the binder.

- **AI/ML (changed from Phase A):**
  > I withdraw "field defaults are under the binder". sections/02_syntax.md requires a const expression, so a default has no use for a trait method. Only `@invariant` remains, as P0 says.

#### Phase C — Final vote

Q1 and Q4 were settled in round 1. Phase C asked Q2 (B: once per binder and trait for a rigid parameter) and Q3 (B: continue as if `U: Tr` were written). Every seat voted B on both, with no objection to the cases listed in the ballot.

Two seats moved. Both moves came from PLT's mechanism.

- **Systems (Q2, changed from round 1):**
  > I held A because a dedupe rule looked like new checker state. plt's mechanism removes that cost: after E0306 on (U, Tr), add `U: Tr` to the binder's environment, and later occurrences pass with no dedupe set and no extra judge path. The collision is also real: three machine fixes on one binder can give `U: Tr + Tr`, so per site needs a group-fix rule that B does not.

- **Systems (Q3, changed from round 1):**
  > I rejected a poison type, and this is not one: the state after the report is the exact state after the repair, and it costs one entry in an environment that exists already. It adds no run-time or codegen risk, because E0306 is an error and the build stops before mono, so the assumed bound never reaches an instance. `s.v.nope()` still reports, so the checker hides nothing that the repair would not clear.

- **Systems, concern:**
  > The assumed bound must stay scoped to its binder and out of any memo keyed by type id, or a cached "satisfied" from one rejected item can let a later item with its own unbounded `U` pass with no error.

- **Minimalism (Q2, changed from round 1):**
  > I chose A because I thought per site cost nothing and dedupe needed new state. Both points fail. Per site gives three machine fixes on one binder that collide (`U: Tr + Tr`), so A needs a rule to group fixes anyway. plt's recovery needs no dedupe table: it uses the bound environment that the judge already reads, and the first report adds `U: Tr` there, so later sites pass. My LSP objection also fails, because no hidden site remains after the one repair.

- **Minimalism (Q3, changed from round 1):**
  > I rejected B as a suppression rule, but plt's mechanism is not one: there is no poison type and no list of errors to hide. The checker continues in the exact state that the repair gives, so what it reports is what the user would still see after the fix, and `s.v.nope()` still reports. One recovery answers both Q2 and Q3, which is less surface than two separate answers. This changes which errors a rejected program shows and no program's acceptance, so it adds nothing to the language.

- **Minimalism, concern:**
  > The recovery could be read as an implied bound, or a bug could add the bound without first emitting E0306 and so accept an ill-typed program, so the assumption must come only after the error is emitted, the spec must describe it as error recovery in a rejected program, and a test must pin that the program still fails.

- **PLT, concern:**
  > Recovery can depend on check order: a body that calls `u.m()` and then, on a later line, has the literal `S { v: u }` with no `S[U]` in its signature judges the call before the end-of-inference judge sees the literal, so it gives two reports, and the spec must not promise one report for that shape.

- **Web/Scripting (Q3):**
  > `U: Tr` is the repair we already print, so going on as if it were written shows the dev the program they get after that edit. `fn d` gives one error, and `fn g` still shows `nope`, which is a separate mistake that the repair does not clear.

- **Web/Scripting, concern:**
  > If a dev repairs the first site by changing that type (`a: Int`) and does not add the bound, the next `S[U]` reports only on the next compile, so the error seems to move; the help must keep the binder edit as the plain first choice.

- **AI/ML, concern:**
  > If an author repairs by another edit, for example by changing the first `S[U]` to a different type, a report on a later site appears only after that edit, so one program can take two passes to reach a clean check.

- **DevOps/Tooling, concern:**
  > If the user repairs by removing `S[U]` and does not add `U: Tr`, the assumption goes away and body errors that were hidden appear on the next run, so the count can rise after a repair; the assumption must also stay inside the checker and its item, or it could hide a real error in another item.

#### Phase D

Not triggered. Every question passed 6-0.

### Points Left Open

- The panel did not decide `Map`. A separate question is whether the key condition of `Map` is a declared bound. This decision covers bounds written on a declaration and implies nothing about `Map`.
- `@invariant` bodies are neither typed nor run in the current compiler. The reason to keep the form rests on the spec, and this decision does not rely on an invariant that compiles as proof of any bound.
- The repair `type A[U: Tr] = S[U]` for a generic alias needs the compiler to accept a generic alias in a `let`.
- The rigid-parameter results depend on the judge that checks the use of a method on an unbounded parameter. That judge and this rule share one path.

### Facts From Other Languages

- Haskell removed `DatatypeContexts` because a bound on a data declaration gave a body nothing and forced repetition. Here the declaration's own `@invariant` sits under the bound, so the form stays.
- Rust guidance puts bounds on the impl, not on the struct. Blink keeps the bound on the declaration because the invariant needs it.
