[< All Decisions](../DECISIONS.md)

# A Trait Default Body Under an Impl-Chosen Row — Design Rationale

The impl-chosen-rows ruling lets a trait method write `! _`, so that each impl declares its own row. That ruling
said nothing about a method that has `! _` and a default body. The gap has two parts. First: which effects may the
default body perform, when its `_` has no source? Second: a type whose impl does not override the method keeps the
default, so what row does a call charge for it, and what does the type-argument join of §4.15.3 add? This ruling
answers both, and it answers `final` with `! _`.

## Summary

| Q | Question | Result | Vote |
|---|---|---|---|
| Q1 | What may a default body under `! F, _` perform, and what row does a type that keeps the default get? | 1A: in a default body `_` is empty. The body may perform only the fixed effects `F` beside `_`. A type that keeps the default is charged `F`. A call of a `_` method on `self` in a default body is E0500 | 1A 5 (sys, web, devops, aiml, min), 1B 1 (plt) |
| Q2 | `final` with `! _` | 2E: E0551. Under 1A the `_` of a `final` method can never stand for an effect | 6-0 |
| Q3 | Is the "remove `_`" edit on that E0551 machine-applicable? | 3H: help text only, not a `fix:` | 6-0 |

Shared by all six seats, and not put to a vote:

- The charge reads signatures only. No row is read from a default body.
- An effect in a default body with no source is E0500 at the operation. No new code.
- The E0500 help in a default body has no machine-applicable `fix:`.
- A concrete call `A { }.m()` on a type that does not override `m` is charged `F`. The interim text of the ticket,
  "charged nothing", is wrong when `F` is not empty.
- A move from 1A to 1B later is a breaking change, so 1A is the permanent rule.
- A subtrait cannot redeclare the method (E0733). The §4.15.3 join for `T: Sub` reaches the method of the supertrait.

The panel took three rounds: independent proposals (Phase A), a dedupe and one round of debate (Phase A.5 and
B), and a silent vote (Phase C). All six seats said "ready to vote" after one round of Phase B, so there was no
Phase D.

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated in
independent-proposal, debate, vote rounds. The ticket, verbatim:

> Title: "Spec: a trait default body with an impl-chosen row ! _: what may it perform, and what is a
> non-overriding impl charged"
>
> "Spec 04_effects.md 4.15.2 (Impl-chosen rows, Source of _) exempts a _ in a trait-method
> DECLARATION from the source rule, and says each impl chooses its row. It is silent on a method that
> has ! _ AND a default body: (1) which effects may the default body perform (its _ has no source);
> (2) a type whose impl does not override that method: what row does a call through T: Tr, and the
> type-arg join at a ! _ callee (4.15.3), charge for it. Example:
> ```
> trait Tr { fn m(self) ! _ { io.println("x") } }
> type A { }
> impl Tr for A { }
> fn g[T: Tr](t: T) ! _ { t.m() }
> fn main() { g(A { }) }   // is main charged IO.Print? may the default body print at all?
> ```
> Interim in the impl-chosen-rows work: the default body is checked with _ as empty (it may perform
> only the row's fixed effects), so a non-overriding impl is charged nothing; that stays sound. Found
> while planning the impl-chosen rows implementation."

The text below is excerpted from each panelist's own text. `[...]` marks a cut inside a quote. `1A`, `1B`, `1C`,
`2E`, `2W`, `3M` and `3H` are the labels of the ballot.

#### Phase A — Independent proposals

Three seats chose 1A first (AI/ML, Web/Scripting, Minimalism). Three chose 1B first (Systems, PLT, DevOps/Tooling).
Every seat rejected a row read from the default body. The first choice of each seat, with its answer for `final`
and for a supertrait default:

- **AI/ML** (`A/aiml.md`):

> ## aiml-1 (FIRST CHOICE): in a default body `_` is empty; the default's effects go in the fixed part
>
> **Behavior.**
> 1. A default body of a `! _` method checks against the trait row with `_` = empty set. It may perform only the effects written beside `_`.
> 2. An effect outside the fixed part is E0500 at the call. Message: the default body may not perform it (the catalog row already says this). `help:` "add `<Eff>` beside `_` in the trait row". Machine-applicable fix: `! _` becomes `! <Eff>, _`. No new code.
> 3. A call of a `_` method on `self` inside such a default is E0500 too, because `_` has no source there. `help:` write it as a free generic fn with `! _`.
> 4. If a type does not override the method, its impl row for that method is the fixed part of the trait row. A concrete call is charged that row. The §4.15.3 type-argument join adds that row as the impl row of the type argument. The signature-only rule holds: the fixed part sits in the trait signature, and nothing reads the body.
> 5. The fixed part still limits no override (§4.15.2 Q1 F1 stays as is).
>
> **`final`.** A `final fn m(self) ! IO.Print, _ { .. }` has one body for each type, so the `_` can never stand for any effect. It is a warning (new lint code, name to pick): "`_` on a `final` method stands for no effect; write `! IO.Print`". Its fix removes `_`. No error, because the program is sound.
>
> **Supertrait.** No new rule. `trait Sub: Tr`: if a type does not override `Tr.m`, its impl row for `m` is the fixed part of `Tr.m`. The join for `T: Sub` adds that row through the supertrait walk of §4.15.3. A `Sub` default that calls `self.m()` gets E0500 (rule 3).

- **Web/Scripting** (`A/web.md`):

> ## web-1 (FIRST CHOICE): the default body is one impl, and its row is the fixed part
>
> Rule in one line: **a default body gets the row you can read in the trait, which is the row with `_` taken out.**
>
> 1. Inside a default body, `_` is empty. The body may perform only the effects written beside `_`. Any other effect is E0500 at the call in the body. No new code. The help says where to put the effect:
>    `help: a default body cannot use `_`; name `IO.Print` beside it: `! IO.Print, _``
> 2. An impl that does not override the method has the fixed part as its impl row. Every rule in §4.15.3 then reads that row unchanged: a concrete call is charged it, and the type-argument join adds it. It is still a signature-only fact, because the trait signature holds it. The join does not read the body.
> 3. An empty default under `! _` is legal and charges nothing. This is the 90% case for cleanup traits ("most types need no `enter`").
>
> ## `final` with `! _`
>
> The row is well defined under web-1: every impl gets the fixed part. But `_` then does nothing except force every generic caller to write `! _`. Proposal: compile it, with a **warning** (new code): "`_` on a `final` method has no effect; every impl uses this body", with a fix that removes `_`. The call rules stay uniform; no special case for `final`.
>
> ## Supertrait default
>
> Nothing new. `trait Sub: Base`, where `Base.m` is `! IO.Log, _ { .. }`: an `impl Base for X` that does not override `m` has the row `IO.Log`. `T: Sub` brings `Base.m` into the join (supertraits are included, §4.15.3), and the join adds `IO.Log` for `X`. A subtrait cannot redeclare `m` to give it a new default (E0733).

- **Minimalism** (`A/min.md`):

> ## min-1 (FIRST CHOICE): keep the interim rule as the rule. In a default body, `_` holds no effect
>
> **Behavior.**
> 1. A trait method may have `! _` and a default body. The default body may perform only the fixed part of the row (for `! IO.Log, _`, only `IO.Log`). Any other effect in the body is E0500 at the trait definition, with the message that a default body may not perform the effects `_` stands for, and no `fix:`. ERROR_CATALOG E0500 already says this, and llms-full.md already tells users so.
> 2. This includes a call of a `_` method on `self` (another one, or the same one). That call is charged `_`, and `_` holds nothing here, so it is E0500.
> 3. For an impl that does not override `m`, the impl row of `m` is the fixed part of the trait row. A concrete call is charged that row. At the §4.15.3 type-argument join, that row is what joins `_`. It is read from the signature, so the body is never read.
> 4. An impl that overrides `m` picks any row, as §4.15.2 says.
> 5. No new code and no new syntax.
>
> **`final`.** A `final fn m(self) ! _ { ... }` is legal. Its row is its fixed part for every type, because no impl can override it. A call through `T` is still charged `_` (signature rule), which costs only the extra `! _` in the caller. Same answer as Q1 F1 of the impl-chosen-rows panel: legal, no error, no lint. If the panel wants an error, I would not object, but it is a new code for a form no one has written.
>
> **Supertrait.** No change. The default is checked once in the supertrait that declares it. A subtrait cannot redeclare it (E0733). An impl of the supertrait that does not override it has the fixed-part row. Through `T: Sub`, the join adds that row as for any supertrait `_` method.

- **Systems** (`A/sys.md`):

> ## Proposal S1 (my pick): a default body is a generic fn over `Self`; its `_` is sourced by `Self`'s own `_` methods; the non-overriding row comes from signatures only
>
> **Behavior.**
>
> 1. Check a default body of a `! F, _` method as if it were `fn m[Self: Tr](self: Self, ...) ! F, _`. The body may perform the fixed part `F`, and it may call `_` methods of `Self` (the trait's and its supertraits' methods, and the bounds of the method's own type parameters). Those calls are charged the opaque `_`. This is the existing *Source of `_`* rule, applied to the implicit `Self` parameter.
> 2. A concrete effect in the body that `F` does not hold is E0500 at the operation. `_` never stands for a concrete effect. The help names both fixes: "add `IO.Print` beside `_`", or "remove the default body".
> 3. For an impl of `A` that does not override `m`, `m`'s row is `F` plus the rows of `A`'s impls of every *other* `_` method in `Tr` and its supertraits. When some of those are also inherited defaults, take the least fixed point. It is a finite union, so it ends. This is the §4.15.3 type-argument join with `Self = A`, and the body is not read.
> 4. A concrete call `a.m()` is charged that row. A call through `T: Tr` is charged `F, _`, and the §4.15.3 join adds the row from rule 3 for `A`.
>
> **`final`.** Rules 1-4 apply unchanged, since no impl can override the method. One more rule: a `final` method with `_` and no `_` method of `Self` to source it has an `_` that is always empty. Treat that as E0551, because the reason for the trait-declaration exemption ("each impl chooses") does not hold for `final`. Error text: "`_` in the row of final `Tr.m` has no source".
>
> **Supertraits.** `trait Sub: Super`. A `! _` default on `Super.m` is checked in `Super`'s scope (only `Super`'s `_` methods and the supertraits of `Super`). `Sub` cannot redeclare it (E0733). For a call through `T: Sub`, the §4.15.3 join already brings `Super.m`, and for `A` it adds the row from rule 3, computed over `Super`'s methods.

- **PLT** (`A/plt.md`):

> ## plt-1 (FIRST CHOICE): in a default body, `_` is sourced by `Self` and opaque
>
> 1. **Checking the body.** Let the trait row be `! F, _`. The default body may perform `F`, and may call any `_`-row method of the guarantee set on `self` (own trait and supertraits, `m` itself included). Each such call is charged `_`, as a call through `T: Tr` is. A concrete effect not in `F` is E0500 at the operation. The message says that in a default body `_` holds only the rows of `Self`'s `_` methods. Help: "add `IO.Print` beside `_` in the row of `Tr.m`"; `fix:` adds it. (Today's catalog text says "no `fix:`"; plt-1 gives one, because the fixed part is the right fix.)
> 2. **Charge for a non-overriding impl.** It reads the signature only, like the §4.15.3 type-argument join with `Self := A`:
>    `ε(A, m) = F ∪ ⋃ ε(A, m')` over every `_`-row method `m'` of the guarantee set.
>    When defaults refer to each other, take the least fixed point. It exists: the rows form a finite lattice and the union is monotone. `m' = m` adds nothing.
> 3. A concrete call `a.m()` is charged `ε(A, m)`. A call through `T: Tr` is charged `F, _`, and the join at a `! _` callee adds `ε(A, m)`. An override replaces the default (§3.6), and its row is the row it writes, as today.
>
> **`final` default with `! _`.** Same rule. No impl can override it, so `ε(A, m)` always comes from point 2. If the guarantee set has no other `_` method, then `ε(A, m) = F` for every `A`, and the `_` is a dead parameter. I want a lint here (W-class, help "write `! F`"), not an error. A future supertrait may add a `_` method and make the `_` live.
>
> **Supertrait.** `trait Sub: Tr { fn n(self) ! _ { self.m() } }` is legal: `Tr.m` is in `Sub`'s guarantee set. `ε(A, n) = ε(A, m) ∪ …`. Point 2 computes `Tr.m`'s own inherited default for `A` from `impl Tr for A`. `impl Sub for A` does not change it (no redeclaration, E0733). The join for `T: Sub` includes `Tr.m` (supertraits included).

- **DevOps/Tooling** (`A/devops.md`):

> ## devops-1 (FIRST CHOICE): the default's `_` is the join of Self's other `_` methods; a non-overriding impl's row is that join for its type, plus the fixed part
>
> Behavior:
> 1. Inside a default body, `Self` is a type parameter bounded by the guarantee set (§3.6). The `_` of the default has a source when that set has another method with a `_` row. That is the existing *Source of `_`* rule with `Self` as the type parameter. The default may call those methods, and it may perform the fixed part of its own row. It may not perform anything else.
> 2. For an impl `A` that does not override `m`, the row of `A.m` is the fixed part of `Tr.m`, plus the rows of `A` for each other `_` method in the guarantee set. This comes from signatures only, the same way as the §4.15.3 type-argument join. A method that `A` also does not override adds its own join, so the computation stops (it is a union over a finite set).
> 3. A concrete call `a.m()` is charged that row. A call through `T: Tr` is charged the fixed part plus `_`, as today. At a `! _` callee, the type-argument join adds the computed row of `A.m`.
> 4. A default that performs an effect outside its source: E0500. The message names the default and the help gives a fix.
>
> `final`: same rule. The row is the join, and no impl can change it. A `final` default with `! _` whose guarantee set has no other `_` method has a `_` that is always empty. That is E0551 (`UnsourcedEffectWildcard`), and the help says "a `final` default cannot be overridden, so its `_` has no source; name the effects". A non-final default with no source is legal, because overrides are the source (it must stay legal for impls).
>
> Supertrait: `trait Sub: Res { fn tidy(self) ! _ { self.shut() } }` has a source (`Res.close`, `Res.shut`). If `F` does not override `Res.shut`, `F.shut` is `F.close`'s row in every context: one row per (type, method), whatever bound reaches it.

Fallback (from the dedupe of Phase A.5): no default body on a method whose row has an impl-chosen `_` (1C: web-3,
min-2). Each author who named it ranked it below the first choice, and plt and devops rejected it by name.

#### Phase A.5 and Phase B — Dedupe and debate, round 1

The moderator listed the points that all six seats shared (above), three options for Q1 (1A, 1B, 1C) and two
variations (V1, `final` with `! _`; V2, a machine-applicable `fix:` on the E0500 help). All six seats sent "ready to
vote" after this round. The positions that changed:

- **Q1, a correction by every seat.** Phase A said that a later move from 1A to 1B breaks no program. Min, plt,
  aiml, sys, devops and web each wrote in round 1 that it does. Sys:

> **Correction to "relax 1A to 1B later with no break" (plt-2, min).** That claim is false. Moving from 1A to 1B widens the row of every existing non-overriding impl whose trait has another `_` method. The `quiet()` example above compiles under 1A and fails under 1B. So a vote for 1A is a vote for 1A as the permanent rule. A later opt-in needs new syntax, not a relaxed check. The ballot should say so.

  Web:

> **This fact affects the vote: going from 1A to 1B later is a breaking change.** min ("We can lift this later with no break") and plt-2 ("Later relaxing it to plt-1 does not break any program") are wrong. `tick` above compiles under 1A and fails under 1B, because 1B makes the non-overriding row bigger. So 1A is not "1B deferred"; we must pick one now. E0900 means no user program depends on either yet, so now is the cheap time to pick.

- **Q1, Systems moved from 1B to 1A.**

> ## Q1: I move to 1A. 1B is now my second choice
>
> min's `Hook` example changed my mind. Under 1B, the signature-only join charges an empty default with every sibling `_` row:
>
> ```blink
> trait Hook {
>     fn before(self) ! _ { }
>     fn run(self) ! _
> }
> type Job { }
> impl Hook for Job { fn run(self) ! IO.Log { io.log("run") } }
> fn quiet() { Job { }.before() }
> ```
> ```
> 1A: compiles. Job.before has the row (nothing).
> 1B: error[UndeclaredEffect] at Job { }.before(): missing IO.Log
>     (Job.before = F ∪ Job.run = IO.Log, for a body that does nothing)
> ```
>
> So 1B over-charges the common case (the empty hook) to make the rare case work (a forwarding default). The only fix that keeps the join signature-only is to charge every sibling. A charge that names effects no code performs is what I object to most from the sys seat. Under 1A every row is exact: what the default may do is `F`, and what it is charged is `F`. The forwarding default has a free generic fn as its workaround (aiml), at the same cost.

- **Q1, DevOps/Tooling moved from 1B to 1A.**

> ## Q1: I switch from 1B to 1A
>
> I read min's `Hook` example under 1B and do not like the error it gives. `Scoped` takes the same shape: `enter` gets an empty default, and `exit` does the work.
>
> ```blink
> trait Hook {
>     fn before(self) ! _ { }
>     fn run(self) ! _
> }
> type Loud { }
> impl Hook for Loud { fn run(self) ! IO.Log { io.log("run") } }
> fn quiet() { Loud { }.before() }
> ```
> 1B (signature only, every sibling joins):
> ```
> error[UndeclaredEffect]: call to `Loud.before` needs effect `IO.Log`
>   = note: `Loud.before` uses the default of `Hook.before`, whose row includes the row of `Loud.run`
> ```
> The default body is empty, but the call is charged `IO.Log`. A user cannot fix that from the call site, and they cannot remove it from the trait without losing the forwarding default. I will not ship a diagnostic whose true answer is "the rule over-charges". Through `T: Hook` the join already charges `run`, so 1B only hurts concrete calls like this one, and it hurts them every time.
>
> Under 1A, `quiet` compiles, and every charge can be read from the trait text: the fixed part. That is the best diagnostic surface on the table.

- **Q1, PLT held 1B** and said what it costs:

> So 1A followed by 1B is a breaking change. We pick one now, and "start small, relax later" is not available. (1B followed by 1A only lowers charges, and E0500 at a self-call in a default rejects only bodies that 1B accepted, so that direction breaks too.)
>
> Both rules are sound. The type theory picks 1B: a default is a generic fn over `Self: Tr`, so the Source rule and the §4.15.3 join already give its row. 1A adds a special case: `Self` is the one type parameter whose `_` methods source nothing. The 1B cost is the over-charge above. It hits only a concrete call of the defaulted method. A call through `T` already pays for every `_` method of the bound, and a concrete `with` already pays for both `enter` and `exit`. I accept that cost. 1A stays my second choice. Its charges are exact, and it is sound.
>
> Against 1C: it bans the `F`-only default, which is sound under both rules.

- **V1, `final` with `! _`.** AI/ML, Minimalism, PLT and Web/Scripting moved to E0551. AI/ML:

> ## V1 (`final`): I concede to E0551 (sys, devops)
>
> Under 1A, the `_` of a `final` default can never stand for any effect. That is the definition of "no source", and E0551 already exists for it. One code for "`_` with nothing behind it" is fewer things to learn than a new lint. I withdraw my new-lint proposal. (Under 1B, use E0551 only when no other `_` method of `Self` can supply the `_`, as sys and devops say.)
>
> ```blink
> trait Tr { final fn m(self) ! IO.Print, _ { io.println("x") } }
> ```
> ```
> error[UnsourcedEffectWildcard]: `_` in the row of final `Tr.m` has no source
>   = help: name the effects: `! IO.Print`
> ```

  DevOps/Tooling moved the other way, to a warning:

> ## V1, `final` with `! _`: I switch from E0551 to a warning
>
> Under 1A, a `final` `_` is always empty. The program is sound, so it should not be an error. A warning (new lint code) works: "`_` on final `Tr.m` stands for no effect; every impl runs this body". Help only, no machine-applicable fix. Removing `_` can leave a generic caller's own `_` with no source (E0551 in another file), so a tool must not do it on its own.

- **V2, `fix:` on the E0500 help.** AI/ML and PLT moved from "yes" to "help only". The reason of PLT:

> ## V2 (`fix:`): I concede to devops and min. Help only, no `fix:`
>
> Adding `IO.Print` beside `_` widens the charge at every call through `T: Tr` in every downstream package. A machine fix must not change a public contract without a person deciding it.

#### Phase C — Silent vote

Result: Q1 1A 5 (sys, web, devops, aiml, min), 1B 1 (plt). Q2 2E 6-0. Q3 3H 6-0. DevOps/Tooling moved from a warning
(V1) to 2E, and AI/ML moved from 3M to 3H.

**Q1 — What may a default body under `! F, _` perform, and what row does a type that keeps the default get?**

- **Systems** (`C/sys.md`):

> **Vote:** 1A
>
> **Reasoning:** Under 1A, the row of a non-overriding impl is exactly what the default can do: `F`, no more and no less. 1B must charge every sibling `_` row to keep the join signature-only. So an empty hook default, the common case, charges effects that no code performs (`Loud { }.before()` would need `IO.Log`). A free generic fn gives the forwarding default at the same cost after monomorphization, so 1B gains no expressive power that matters.
>
> **Concern:** This rule is permanent, so a std trait that later needs a forwarding default (for example `close_quietly` on `Closeable`) can only get one through new syntax.

- **Web/Scripting** (`C/web.md`):

> **Vote:** 1A
> **Reasoning:** Under 1A, the row a user reads in the trait is the row the call costs. An empty `before()` is free, and you see `IO.Print` written above a default that prints. 1B charges an empty method for siblings it never calls, which a user will report as a bug. The forwarding default is a free generic fn of the same length that every user already knows. 1C kills the empty hook, the main reason to have a default here.
> **Concern:** Users from Rust or Python will write `self.close()` in a `! _` default and hit E0500, so the help must point them to the free-fn form, or this becomes the common question.

- **PLT** (`C/plt.md`):

> **Vote:** 1B
>
> **Reasoning:** A default body is a generic fn over `Self: Tr`. The Source-of-`_` rule and the §4.15.3 signature join already give its row, with `Self := A`. 1B is that rule with no exception. 1A makes `Self` the one type parameter whose `_` methods source nothing, and that special case is permanent, because the move is breaking. Both rules are sound, so the tie goes to the rule that composes: the default `shut` and the free fn `shut[T: Res]` then type the same way.
>
> **Concern:** Under 1B, a concrete call of an empty default (`Loud { }.before()`) is over-charged by its sibling rows. Users will meet this as an E0500 that reads as wrong. The writer must explain it with an example.

- **DevOps/Tooling** (`C/devops.md`):

> **Vote:** 1A
> **Reasoning:** You can read every charge from the trait text: the fixed part. So an E0500 at a call site always points to a row the user can see. 1B charges an empty `before` default with the row of `run`. The user can fix that error neither at the call nor in the trait. 1C bans the empty hook default, which is the one real use.
> **Concern:** Users will write the forwarding default `fn shut(self) ! _ { self.close() }`. The E0500 help must show the free-fn form, or they will copy the body into each impl.

- **AI/ML** (`C/aiml.md`):

> **Vote:** 1A
>
> **Reasoning:** Under 1A the charge is what the trait method's own row says. A user or a model can predict it from one line, with no need to walk the guarantee set or compute a fixed point. Under 1B, an empty `before` default is charged `IO.Log` from a sibling method. That is a hidden row, and it causes E0500s that a model cannot explain from the code in front of it. The forwarding case has a free-fn form that already works and costs about the same tokens. Because this choice is permanent, I pick the rule with fewer decision points.
>
> **Concern:** Trait authors will want `fn shut(self) ! _ { self.close() }` as a default, and they will hit E0500. If the help does not point clearly to the free-fn form, they will copy the body into each impl.

- **Minimalism** (`C/min.md`):

> **Vote:** 1A
>
> **Reasoning:** 1A adds no rule. The catalog, llms-full.md and gen1 already do it. It keeps the one use we know of, the empty hook, and it charges that hook nothing. 1B adds a second source of `_` and a fixpoint. It also charges too much in the hook case (`quiet()` above) only to help the forwarding default, and a free generic fn already does that job. This is the permanent rule, so the smaller one should win.
>
> **Concern:** A user who wants a forwarding default (`shut` calls `close`) gets E0500 and must learn the free-fn form. The help must show that form, or users will copy the body into each impl.

**Q2 — `final` with `! _`**

- **Systems** (`C/sys.md`):

> **Vote:** 2E
>
> **Reasoning:** Under 1A the `_` of a `final` method is always empty. Each generic caller must still write `! _`, and that `! _` spreads up the call chain to no purpose. Reusing E0551 adds no code and states the true fact: nothing can choose this row. A warning would let the dead `_` ship in a public trait, and removing it later is an API change.
>
> **Concern:** A trait author who adds `_` "for later" gets a hard error instead of a nudge, and might drop `final` to silence it, which opens the method to overrides they did not want.

- **Web/Scripting** (`C/web.md`):

> **Vote:** 2E
> **Reasoning:** Under 1A, a `final` default's `_` can never hold an effect. That is the same case as `fn g() ! _ {}`, and that case is already E0551. One rule ("a `_` nothing can fill is E0551") is less to learn than a new lint code for a form almost no one writes.
> **Concern:** E0551's current text speaks of "no `! _` parameter, and no type parameter", which does not explain the `final` case, so the message needs its own line about `final`.

- **PLT** (`C/plt.md`):

> **Vote:** 2E
>
> **Reasoning:** A trait declaration is exempt from the Source rule only because "each impl chooses". `final` makes that premise false, so the general rule applies, and an unsourced `_` is E0551. A warning would mark a definite contradiction in the contract as only a matter of style.
>
> **Concern:** Under 1B, adding or removing a sibling `_` method changes whether a `final` default is E0551. A trait edit can then raise an error at a line the edit did not touch.

- **DevOps/Tooling** (`C/devops.md`):

> **Vote:** 2E
> **Reasoning:** In round 1 I said a warning. I change to E0551 to be consistent: `fn g() ! _ {}` is also sound, and it is E0551 today. One code for "this `_` can never stand for an effect" is a smaller and more predictable diagnostic surface than a new lint for one case. A user or agent who meets E0551 learns the same fix: name the effects.
> **Concern:** The E0551 message today says "no `! _` parameter, and no type parameter whose bound has a `_` method". It needs a `final`-specific reason line, or the user will not see why a trait method is checked at all.

- **AI/ML** (`C/aiml.md`):

> **Vote:** 2E
>
> **Reasoning:** A `_` that can never stand for any effect is exactly "a `_` with no source", and E0551 already names that case. One code for one idea is easier to learn than a new lint code that means nearly the same thing. The program is sound either way, but a `_` that is always empty misleads every reader and every model that generates calls through `T: Tr` (they would add `! _` for nothing).
>
> **Concern:** If 1B wins, the E0551 condition ("no other `_` method of `Self` can source it") is harder to state and to learn than the unconditional 1A form.

- **Minimalism** (`C/min.md`):

> **Vote:** 2E
>
> **Reasoning:** Under 1A, `_` on a `final` method can never hold an effect, so the form is dead. E0551 already names "a `_` with no source", so this costs no new code. A warning would add a lint for a form that has no meaning. It would also leave every generic caller paying for a `! _` that is always empty.
>
> **Concern:** A trait author who later wants a non-final version must remove `final` and add `_` back. That is a small edit, and it is honest.

**Q3 — Is the "remove `_`" edit on the Q2 diagnostic machine-applicable?**

- **Systems** (`C/sys.md`):

> **Vote:** 3H
>
> **Reasoning:** devops is right. A generic fn `fn g[T: Tr](t: T) ! _` may get its only source from `Tr.m`'s `_`. Removing that `_` makes `g` E0551 in another file, and maybe in another package. A machine-applicable fix must not create new errors at a distance, so the edit goes in the help text only.
>
> **Concern:** Agents that act only on `fix:` fields will stall at this error, so the help text must name the edit and its knock-on effect clearly.

- **Web/Scripting** (`C/web.md`):

> **Vote:** 3H
> **Reasoning:** devops is right that the edit is not local. Once `_` is gone, `Tr` may have no `_` method left, and a generic caller's own `! _` in another file becomes E0551. A fix that an agent can apply in a loop should not cause a new error somewhere else. Help text that names the edit is enough for a one-line change.
> **Concern:** Without a machine fix, an LLM may "fix" E0551 by removing `final` instead of `_`, so the help must say which edit to make.

- **PLT** (`C/plt.md`):

> **Vote:** 3H
>
> **Reasoning:** Removing `_` changes the trait's signature, and so the source set of every generic caller. A caller `fn g[T: Tr](t: T) ! _` whose only source was `Tr.m` becomes E0551 in another file. A machine-applicable fix must keep the program well-typed across its whole scope. This one does not.
>
> **Concern:** If 3M wins, a tool applies the fix and breaks callers in downstream packages that the fix did not show.

- **DevOps/Tooling** (`C/devops.md`):

> **Vote:** 3H
> **Reasoning:** Removing `_` from `Tr.m` does not change a concrete charge. But a generic caller `fn g[T: Tr](t: T) ! _ { t.m() }` loses its only source, so the edit causes an E0551 in another file, and possibly in another package. A machine-applicable fix must not cause new errors at sites the user did not touch.
> **Concern:** Agents that apply only machine-applicable fixes will leave the error in place and loop. The help text must name both edits: remove `_` and the `! _` on each generic caller.

- **AI/ML** (`C/aiml.md`):

> **Vote:** 3H (I change my round 1 position)
>
> **Reasoning:** devops is right. Removing `_` from `final Tr.m` takes a `_` method out of the bound `T: Tr`. A generic caller elsewhere (`fn g[T: Tr](t: T) ! _ { t.m() }`) can then get E0551 in another file. A fix that an agent applies on its own must not break code it cannot see. A help line costs the model one more step, but it stops a fix from breaking other files.
>
> **Concern:** Without a machine fix, an agent may "fix" the E0551 by deleting `final` instead of removing `_`. That keeps the dead `_` and loses the seal, so the help must name `! IO.Print` explicitly.

- **Minimalism** (`C/min.md`):

> **Vote:** 3H
>
> **Reasoning:** Removing `_` from `Tr.m` changes a public signature. If `m` was the only `_` method of `Tr`, then a caller `fn g[T: Tr](t: T) ! _` in another module loses its source and gets E0551. An edit that can break code the tool did not touch must stay a human choice. The help prints the text to copy.
>
> **Concern:** Agents lose a one-step repair. The help text must give the exact row to write, so that the manual edit stays one step.

**The dissent on Q1, in full.** PLT voted 1B. The whole Q1 reply of PLT (`C/plt.md`), and the Phase B text that it
rests on:

> **Vote:** 1B
>
> **Reasoning:** A default body is a generic fn over `Self: Tr`. The Source-of-`_` rule and the §4.15.3 signature join already give its row, with `Self := A`. 1B is that rule with no exception. 1A makes `Self` the one type parameter whose `_` methods source nothing, and that special case is permanent, because the move is breaking. Both rules are sound, so the tie goes to the rule that composes: the default `shut` and the free fn `shut[T: Res]` then type the same way.
>
> **Concern:** Under 1B, a concrete call of an empty default (`Loud { }.before()`) is over-charged by its sibling rows. Users will meet this as an E0500 that reads as wrong. The writer must explain it with an example.
>
> Both rules are sound. The type theory picks 1B: a default is a generic fn over `Self: Tr`, so the Source rule and the §4.15.3 join already give its row. 1A adds a special case: `Self` is the one type parameter whose `_` methods source nothing. The 1B cost is the over-charge above. It hits only a concrete call of the defaulted method. A call through `T` already pays for every `_` method of the bound, and a concrete `with` already pays for both `enter` and `exit`. I accept that cost. 1A stays my second choice. Its charges are exact, and it is sound.
>
> Against 1C: it bans the `F`-only default, which is sound under both rules.

Why the majority did not follow PLT is in the Q1 replies above. The shared fact is that 1B charges an empty default
with the rows of its sibling `_` methods, so a concrete call of a default that does nothing needs effects that no
code performs. Sys:

> **Concern:** This rule is permanent, so a std trait that later needs a forwarding default (for example `close_quietly` on `Closeable`) can only get one through new syntax.

### Final Spec

```blink
trait Hook {
    fn before(self) ! _ { }                  // OK: an empty default, the intended use
    fn run(self) ! _
}

type Loud { }
impl Hook for Loud {
    fn run(self) ! IO.Log { io.log("run") }
}

fn quiet() {
    Loud { }.before()                        // OK: charged nothing; the row of Loud.run does not join it
}

trait Tr {
    fn m(self) ! _ {
        io.println("x")                      // ERROR E0500: the default body may not perform `IO.Print`
    }                                        // help: `! IO.Print, _`, or override `m` in each impl, or remove the default
}

type A { }
impl Tr for A { }

fn g[T: Tr](t: T) ! _ {
    t.m()
}

fn main() {
    g(A { })                                 // main is charged nothing: the fixed part of `Tr.m` is empty
}

trait Res {
    fn close(self) ! _
    fn shut(self) ! _ {
        self.close()                         // ERROR E0500: `_` holds no effect in a default body
    }                                        // help: fn shut[T: Res](t: T) ! _ { t.close() }
}

trait Fx {
    final fn m(self) ! IO.Print, _ {         // ERROR E0551: `_` in the row of final `Fx.m` has no source
        io.println("x")                      // help: name the effects: `! IO.Print`; remove `_` and keep `final`
    }
}
```

- In a default body under `! F, _`, `_` is empty and `Self` is not a source of `_`. The body may perform only `F`.
  An effect that `F` does not hold is E0500 at the operation, with two `help:` lines (name it beside `_`; or
  override the method in each impl, or remove the default body) and no `fix:`.
- A call of a `_` method on `self` in a default body, `m` itself included, is E0500. The `help:` points to the
  free-function form `fn shut[T: Res](t: T) ! _ { t.close() }`.
- A type whose impl does not override the method has `F` as its row for the method. A concrete call is charged `F`.
  A call through `T: Tr` is charged `F` and `_`. The §4.15.3 type-argument join adds `F` for that type. Nothing reads
  the body, and the rows of the other `_` methods of the type do not join.
- At a caller that lacks the effect, the E0500 for a type that keeps a default carries the note "`A.m` uses the
  default of `Tr.m`, whose row is `IO.Print`".
- An empty default under `! _` is legal and charges nothing. It is the intended use: a hook.
- `final` with `! _` and no source is E0551, under 1A always (`Self` is not a source). The label says that `final` means
  no impl chooses the row. A first `help:` is "name the effects". A second `help:` is the edit: remove `_` and keep
  `final`; a generic caller whose only source of `_` was that method must then name its effects. It is not a `fix:`.
- A supertrait default has the same rules. A subtrait cannot redeclare the method (E0733). The join for `T: Sub`
  reaches the method of the supertrait and adds its fixed part for a type that keeps the default.
- No new code.

Governing text: §3.6 *The `final` Modifier*, *Effect-row subtype for trait impls*, *Operations on `Self` in a Default Body*,
§3b.2 *Default methods*, §4.15.2 *Source of `_`* and *Default bodies under an impl-chosen `_`*, §4.15.3,
`ERROR_CATALOG.md` (E0500, E0551).

### Concerns

Phase C, Q1:

- **Systems** (`C/sys.md`):

> **Concern:** This rule is permanent, so a std trait that later needs a forwarding default (for example `close_quietly` on `Closeable`) can only get one through new syntax.

- **Web/Scripting** (`C/web.md`):

> **Concern:** Users from Rust or Python will write `self.close()` in a `! _` default and hit E0500, so the help must point them to the free-fn form, or this becomes the common question.

- **PLT** (`C/plt.md`):

> **Concern:** Under 1B, a concrete call of an empty default (`Loud { }.before()`) is over-charged by its sibling rows. Users will meet this as an E0500 that reads as wrong. The writer must explain it with an example.

- **DevOps/Tooling** (`C/devops.md`):

> **Concern:** Users will write the forwarding default `fn shut(self) ! _ { self.close() }`. The E0500 help must show the free-fn form, or they will copy the body into each impl.

- **AI/ML** (`C/aiml.md`):

> **Concern:** Trait authors will want `fn shut(self) ! _ { self.close() }` as a default, and they will hit E0500. If the help does not point clearly to the free-fn form, they will copy the body into each impl.

- **Minimalism** (`C/min.md`):

> **Concern:** A user who wants a forwarding default (`shut` calls `close`) gets E0500 and must learn the free-fn form. The help must show that form, or users will copy the body into each impl.

Phase C, Q2:

- **Systems** (`C/sys.md`):

> **Concern:** A trait author who adds `_` "for later" gets a hard error instead of a nudge, and might drop `final` to silence it, which opens the method to overrides they did not want.

- **Web/Scripting** (`C/web.md`):

> **Concern:** E0551's current text speaks of "no `! _` parameter, and no type parameter", which does not explain the `final` case, so the message needs its own line about `final`.

- **PLT** (`C/plt.md`):

> **Concern:** Under 1B, adding or removing a sibling `_` method changes whether a `final` default is E0551. A trait edit can then raise an error at a line the edit did not touch.

- **DevOps/Tooling** (`C/devops.md`):

> **Concern:** The E0551 message today says "no `! _` parameter, and no type parameter whose bound has a `_` method". It needs a `final`-specific reason line, or the user will not see why a trait method is checked at all.

- **AI/ML** (`C/aiml.md`):

> **Concern:** If 1B wins, the E0551 condition ("no other `_` method of `Self` can source it") is harder to state and to learn than the unconditional 1A form.

- **Minimalism** (`C/min.md`):

> **Concern:** A trait author who later wants a non-final version must remove `final` and add `_` back. That is a small edit, and it is honest.

Phase C, Q3:

- **Systems** (`C/sys.md`):

> **Concern:** Agents that act only on `fix:` fields will stall at this error, so the help text must name the edit and its knock-on effect clearly.

- **Web/Scripting** (`C/web.md`):

> **Concern:** Without a machine fix, an LLM may "fix" E0551 by removing `final` instead of `_`, so the help must say which edit to make.

- **PLT** (`C/plt.md`):

> **Concern:** If 3M wins, a tool applies the fix and breaks callers in downstream packages that the fix did not show.

- **DevOps/Tooling** (`C/devops.md`):

> **Concern:** Agents that apply only machine-applicable fixes will leave the error in place and loop. The help text must name both edits: remove `_` and the `! _` on each generic caller.

- **AI/ML** (`C/aiml.md`):

> **Concern:** Without a machine fix, an agent may "fix" the E0551 by deleting `final` instead of removing `_`. That keeps the dead `_` and loses the seal, so the help must name `! IO.Print` explicitly.

- **Minimalism** (`C/min.md`):

> **Concern:** Agents lose a one-step repair. The help text must give the exact row to write, so that the manual edit stays one step.

### Gap raised, not decided

Sys raised it in the Q1 concern above: because 1A is permanent, a std trait that needs a forwarding default, a
default that calls another `_` method of `Self` (`close_quietly` on `Closeable` is the example), can only get one
through new syntax later. The panel did not decide that syntax, and no trait in the spec or std needs it today. The
free-function form is the answer until a panel decides otherwise.

### Follow-ups

1. Implementation: check the effects of a default body against the fixed part of its row, with the E0500 `help:`
   lines of the final spec; charge the fixed part to a type that keeps a default, at a concrete call and in the
   type-argument join; add the `note:` that names the default at a caller that lacks the effect; check the `_` of a
   `final` trait method (E0551) with its `final`-specific label and `help:`. E0500 does not check builtin namespace
   calls (`io.println`) yet, so the ticket example needs that check too.
2. A compiler fact found while the panel worked: an impl that omits any default method of a user trait is rejected
   today (E0900, a bug filed), so no user program meets this rule until that bug is fixed.
3. Llms text: the line "A trait default body may not perform the effects its `_` stands for" needs the new rule
   (the fixed part is allowed, `Self` is not a source of `_`, a type that keeps the default is charged the fixed part,
   `final` with `! _` is E0551).
