[< All Decisions](../DECISIONS.md)

# Display.fmt Has No Effect Row; Impls May Not Widen a Trait Method's Row — Design Rationale

**Gap:** the Display trait shape (see [display-trait-shape.md](display-trait-shape.md), locked point 4) declared `fn fmt(self, sb: StringBuilder) ! StringBuilderPure` and §3 said `fmt` "is declared with the `StringBuilderPure` effect (§4.x)". §4 never defined that effect. The only declaration of the name was an unused `pub trait StringBuilderPure` in `lib/std/sb.bl`, whose `write_char(self, ch: Char)` had drifted from the sealed `StringBuildOps` surface. `lib/std/traits.bl` declared `fmt` with no row and a comment that the naming was "still open".

**Fact surfaced during deliberation:** §3.6 and §4.5 stated the rule `R_o ⊆ R_d` only for overrides of open default methods. With gen1 (current src), this program passed `blink check` with no diagnostic, so an impl of a required method could widen the trait's row:

```blink
trait Shout {
    fn shout(self) -> Int
}

type Box { n: Int }

impl Shout for Box {
    fn shout(self) -> Int ! IO {
        io.println("side")
        self.n
    }
}

type Pt { x: Int }

impl Display for Pt {
    fn fmt(self, sb: StringBuilder) ! IO {
        io.println("side")
        sb.write("pt")
    }
}
```

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated
in independent-proposal → debate → vote rounds. Phase A text for Systems, DevOps and Minimalism is excerpted in the panelist's own words; the other three are quoted in full. Phase B, C and D text is quoted in full.

#### Phase A — Independent proposals

All six proposed the same primary option: delete the name, leave `fmt` with no effect row, and delete the orphan trait.

- **Systems** (excerpted):

> Sys A (primary): "`StringBuilderPure` should not exist. `fmt` has an empty effect row."
> 1. "An effect row is a grant, not a limit (§4.1)..." 2. "Writing to `sb` needs no effect." 3. Delete orphan trait — "Keeping it lets people think it is the effect."
> 4. "Close a gap in the spec. The rule that an override may not widen the row (§4.5 line 938, §3 line 2221) covers only *open default* methods. `fmt` is a *required* method. Extend the rule: for every trait method, required or default, the impl row must be a subset of the trait row. Without this, the empty row on `fmt` is not enforced."
> 5. Rewrite: "`fmt` has no effect row. Impls may write to the supplied builder and can use no capability. Writes to module-level `let mut` fall under §4.16."
> 6. Strike "allocate observably", "referentially transparent", "cache-friendly" — "The spec must not promise an optimization that no pass performs."
> Tradeoffs: "An effect with no operations has no handle, no dispatch and no handler, so it compiles to nothing. All of its cost is spec text and typechecker surface, and it pays back nothing in codegen or at runtime."
> B (optional, leans against): fmt write set must be empty. "Against it: it is a special case for one trait in the typechecker, and nothing needs it. ... YAGNI: add it when an optimization needs it. It could also fairly be a lint".
> Vote intent: A yes. B no for v1.

- **Web/Scripting**:

> WEB/SCRIPTING PANELIST — Phase A proposals (ticket zqeyay)
>
> ## Core finding
> `! StringBuilderPure` is backwards under our own model. A row is a GRANT (§4.1, brief fact 24), and a trait row is an UPPER BOUND on every impl (§3 line 2221, §4.5 line 938: impls may narrow, never widen). So the tightest possible contract is the EMPTY row. `fn fmt(self, sb: StringBuilder)` with no `!` already guarantees, compiler-proved, that no impl does IO, DB, Net, Async, etc. Writing to `sb` is a method call on a parameter (StringBuildOps), which needs no effect. Locked point 4's intent is ALREADY MET by the current lib/std/traits.bl. The phantom effect adds nothing and would, if made real, be a capability that grants "may write to a builder" — which every fn can do anyway.
>
> ## Proposal W1 (primary): Delete the name. Pure = no row.
> - Spec §3 (lines 2063, 2266, 2908): `fn fmt(self, sb: StringBuilder)` — drop `! StringBuilderPure`.
> - Replace the §3 ~2965 paragraph with "**`fmt` has no effect row.** A trait row bounds every impl (§4.5), so no `fmt` impl may perform IO or any other effect. It may write into `sb`, which is a method call on a parameter and needs no effect. Module-level `let mut` access is tracked by mutation analysis (§4.16), not by effects."
> - Amend DECISIONS.md row + display-trait-shape.md point 4 the same way, with a note that the intent is kept and the mechanism is the empty row.
> - Delete the orphan `pub trait StringBuilderPure` in lib/std/sb.bl (zero implementors, zero users, duplicates StringBuildOps). Remove the "still open" comment in traits.bl.
> - Close the blocked "add row to Display.fmt" ticket as not needed.
>
> (code: Point impl with no row; Logged impl with `! IO` -> error: override widens trait row (§4.5))
>
> DX tradeoffs: A JS/Python dev reads the first impl in 5 seconds. `! StringBuilderPure` would generate a steady stream of "what is this effect, do I need to import it, why can't I write `! StringBuilderPure` on my helper fn" questions — and the answer "it's a keyword that means nothing" is the worst kind of Stack Overflow answer. Also: every user who writes a Display impl would copy the row; making it mandatory ceremony with zero semantic content is exactly what we removed for `main` (§4.6 "pure ceremony").
>
> Honest cost: the §3 claim "cannot read external state / mutate state outside the builder / allocate observably" is NOT fully delivered. Module `let mut` reads/writes and mutation of collections reachable from `self` remain possible (§4.16.2 defers param-mutation to v2). I say: say so plainly in the spec rather than promise it. "referentially transparent" and "cache-friendly" should be struck — nobody caches interpolation results across calls, and a promise the compiler doesn't enforce is a latent-bug magnet.
>
> Cross-language: Kotlin `toString()`, Python `__str__`/`__format__`, Rust `fmt::Display::fmt(&self, f)` — none carry a purity marker; Rust gets "no IO" only by convention. Blink's empty row is strictly stronger than all of them at zero syntax cost.
>
> ## Proposal W2 (fallback): lint, not effect
> If "no module `let mut` access in fmt" matters, enforce it through the existing §4.16 inferred write/read set: a diagnostic when a `fmt` impl's inferred module-state set is non-empty (warning in v1). No new syntax, no new effect, no user-facing name.
>
> ## Rejected by me: make StringBuilderPure a real effect / keep the sb.bl trait
> A real effect inverts the capability model (a grant that restricts) and needs a new "restrictive effect" concept — clever, unfamiliar, 0 users asked for it. Keeping the sb.bl trait keeps two traits describing one type's methods; the write_char drift this ticket found is proof it rots.
>
> Vote preference: W1 (with the honesty edit), W2 as optional add-on.

- **PLT**:

> PLT Phase A proposal (zqeyay): StringBuilderPure should not be an effect. The empty row on fmt already gives the guarantee.
>
> **Diagnosis.** Blink's effect rows are upper bounds on capability (§4.1, §4.5; §4.15.1: "pure is a subtype of effectful"). If you add a label to a row, you grant more, never less. So a "restriction effect" such as `! StringBuilderPure` has no consistent typing rule. It can mean one of two things, and both are wrong:
> - (a) A real capability with operations. Then `display()`, `"{x}"` and `sb.write(x)` would all need the effect to be granted or handled. Every function that interpolates a string would carry the row or need a handler, so fmt becomes less pure than a plain fn.
> - (b) A marker with no operations. Then it grants nothing. Under row subtyping it is the same as the empty row, and it is only a name that looks like a guarantee.
>
> The "Pure" in the name also collides with a stdlib convention: ListPure, MapPure, SetPure and FloatPure are method-group traits. The orphan `trait StringBuilderPure` in lib/std/sb.bl is one of those. It has no impls and no refs, and StringBuildOps already covers it. The spec's "§4.x" then read that trait's name as an effect.
>
> **P1 (primary): fmt has an empty row, and that row is the contract.**
> ```blink
> pub trait Display {
>     fn fmt(self, sb: StringBuilder)
> }
>
> impl Display for Point {
>     fn fmt(self, sb: StringBuilder) {
>         sb.write("(")
>         sb.write(self.x)
>         sb.write(", ")
>         sb.write(self.y)
>         sb.write(")")
>     }
> }
>
> impl Display for Temp {
>     fn fmt(self, sb: StringBuilder) {
>         let ts = time.now()  // ERROR: `fmt` is pure (Display.fmt has no effect row); `Time` not granted
>         sb.write(self.c)
>     }
> }
> ```
> Typing rule, which already exists (§4.5 / §3.6 R_o ⊆ R_d): an impl row must be a subset of the trait row. With R_d = ∅, every impl is effect-free. That gives "no IO, no external capability" with no new concept. It also composes: a `fmt` for List[T] that calls `elem.fmt(sb)` stays pure by induction, and the cached/derived `display` is sound for all T: Display.
> Writing into `sb` is parameter mutation. §4.16.2 puts that outside both the effect and write-set tracking (v2), so it is allowed with no special case.
> Spec changes:
> - §3 ~2063/2266/2908 and decisions/display-trait-shape.md point 4: drop `! StringBuilderPure`.
> - Replace the §3 ~2965 paragraph with: "`fmt` has an empty effect row. By the override rule (§4.5), no impl may perform effects. It may write to `sb`."
> - Strike "allocate observably". Under a GC that is not observable, and no mechanism enforces it.
> - Strike "cache-friendly" and the "referentially transparent" claim, or weaken both (see P2).
> - Delete the orphan trait from sb.bl.
> Record in DECISIONS.md that point 4 is now "fmt is pure (empty row)". This closes zqeyay and unblocks the Display ticket, because there is no row to add.
>
> **P2 (optional add-on): make fmt state-independent.** The claim that fmt cannot read external state is false under P1, because reads of module `let mut` are free (§4.16.1). If the panel wants that part of point 4 to hold, add a checked rule: every `fmt` impl must have an empty write set, and it must not read module-level `let mut` bindings, directly or transitively within the module. Violations raise a new diagnostic, `FmtReadsMutableState`. This uses the existing §4.16 analysis plus a read set, which §4.16.3 already implies for its internal "truly pure" classification. Tradeoff: this is the only way the "referentially transparent given (self, sb)" sentence becomes a theorem instead of a hope. The cost is a second analysis, and cross-module transitivity stays unsound until §4.16 goes cross-module. My view: adopt the write-set half now (it is sound, and the analysis already exists). Adopt the read half only when cross-module read sets exist. Until then, strike "cannot read external state" from the spec so that the spec never claims more than the compiler proves.
>
> **P3 (rejected, for the record): define `effect StringBuilderPure { }` in §4.** This fails on (a)/(b) above. It also sets a precedent for "negative effects", which breaks the capability lattice: rows would stop being monotone, and effect projection (§4.7.1) and `! _` forwarding (§4.15.2) would need a second, contravariant kind of label.
>
> **Cross-language note.** Koka treats `total` (the empty row) as the purity marker, and it has no "pure-except" effect. Haskell's `Show` is pure by type, and `ShowS` is the push form with no special monad. Rust's `Display::fmt(&self, f: &mut Formatter)` gets the "only write to f" guarantee from the borrow checker, not from an effect. Blink's parallel is the empty row plus the §4.16 analysis.
>
> Vote intent: P1 required; P2 write-set half yes, read half deferred; P3 no.

- **DevOps** (excerpted):

> DevOps P1 (primary): "drop the row, keep the rule. `fmt` is pure by signature." Error must name the trait contract:
>   error[E0xxx]: `fmt` declares effects the trait `Display` does not allow ... ^^^^^^ `Display.fmt` is pure
>   = note: "{x}", x.display() and sb.write(x) call fmt with no handlers in scope
>   = help: format the data only; log at the call site
> Spec: remove row; §3 ~2965 rename to "**`fmt` is pure.**"; erratum under point 4, "Do not re-vote it."; "If the spec does not already say it, add a general rule: an impl method's row must be a subset of the trait method's row."
> Tradeoffs: "Zero new concepts. The LSP hover shows `fn fmt(self, sb: StringBuilder)`, and that signature is the whole truth."
> P2 (add-on, separate question): lint W0552 "`Display.fmt` writes module state `counter`"; severity config like W0550/W0551; "warn for writes and off for reads. Reading a module-level config such as a locale is legitimate." "this is a lint, not a proof."
> P3: delete orphan trait + stale traits.bl:5 comment; "puts a second, conflicting `write_char` into LSP completion and `blink doc`"; blocked ticket becomes "remove the row from the spec".
> Rejected: real effect — "`"{x}"` would need a handler installed at every interpolation site ... the LSP inlay hints fill with noise on every `"{x}"`. The name also contradicts itself: "Pure" as a *grant* means nothing."
> Vote intent: P1 + P3 as one package. P2 as a separate question.

- **AI/ML**:

> AI/ML panelist, Phase A proposal (zqeyay)
>
> ## Proposal A (my pick): delete `StringBuilderPure`; `fmt` has an empty effect row, and the empty row is the guarantee
>
> The language can already express locked point 4. You just leave out the `!`.
>
> - §4.1 says: "A function with no `!` in its signature cannot perform side effects. The compiler proves it." That rules out IO, reading external state and any other capability.
> - Writing into the `sb` parameter needs no capability. `StringBuildOps` methods take no `!`, and §4.16.2 tracks writes to a parameter through the type system, not through effects.
> - §4.4 (04_effects.md:938) says an impl row must be a subset of the trait row (`R_o ⊆ R_d`). With an empty trait row, every `fmt` impl in the ecosystem must also be empty, so the compiler enforces the contract at each impl site today. We need no new mechanism.
>
> Spec edits:
> 1. In §3 Display (lines 2063, 2266, 2908), remove `! StringBuilderPure`. Replace the 2965 paragraph with: "**`fmt` has no effect row.** Under §4.1 an impl can write only to values it receives. Under §4.4 no impl may widen the row. `fmt` can therefore change the supplied builder and nothing else that the effect system tracks."
> 2. Amend locked point 4 in decisions/display-trait-shape.md and in the DECISIONS.md row the same way: the point stays, and the empty row is how the language states it.
> 3. Delete the orphan `pub trait StringBuilderPure` in lib/std/sb.bl. Nothing implements it or refers to it, and it copies `StringBuildOps`. Remove the comment in traits.bl. zqeyay closes, and the blocked ticket turns into "confirm fmt stays row-free".
> 4. State the known gap: `fmt` can still read or write module `let mut`. §4.16 tracks that with inferred write sets, not effects. If the panel wants a stronger rule, write a narrow one ("an impl of `fmt` whose inferred write set is non-empty is a warning/error"). Do not invent an effect for it.
>
> **AI/ML tradeoffs**
> - Learnability: an LLM that writes `impl Display` copies what it sees. `! StringBuilderPure` is the only place in the spec where an effect limits instead of granting. That inverts the §4.1 model, and a model trained on it will spread the confusion ("does `! Foo` add or remove powers?"). Leaving out the row gives the same rule as every other pure fn.
> - Decision points: zero. There is nothing to remember, spell or import. With a named row, every impl has a token that models will leave out or misspell. With the subset rule, leaving it out would still compile, so the token would carry no information anyway.
> - Token cost: about 3 tokens saved on each of the most common impls in any codebase.
> - Spec-alone learnability: today a reader follows "§4.x" and finds nothing. That is the worst case for spec-driven generation, because a model fills the hole with guesses.
> - Diagnostics: an `fmt` impl that reaches for `io` gets the usual subset-rule error. Models already know how to repair that error.
>
> **Cross-language**: Haskell's `Show` is pure because it has no IO in its type. Rust's `Display::fmt(&self, f: &mut Formatter)` limits writes to the formatter the same way. Neither language names a "pure" effect. Koka writes a pure fn as the empty row `<>`, not as a named effect.
>
> ## Proposal B (fallback, I oppose it): define `StringBuilderPure` as a real effect
>
> For example `effect StringBuilderPure {}` in §4, with the checker treating it as "no other effects". This adds a restricting effect to a system built from grants, which is a special case that every learner (human or model) must memorize, and it gives nothing the empty row does not already give. If the panel wants a name for documentation, use a doc phrase ("fmt is effect-free"), not a keyword.
>
> ## Orphan trait (whichever proposal wins)
> Delete it. Its method set duplicates `StringBuildOps` (the write_char mismatch this ticket found is a symptom of that), and a trait in the prelude with no users is a trap: models will find it with `blink doc` and try to implement it.

- **Minimalism** (excerpted):

> Min (Minimalism) Phase A — M1 (primary): delete `StringBuilderPure`. `fmt` gets no effect row, because "no row" already means what locked point 4 asks for.
> Key quotes:
> - "The language already has the guarantee point 4 describes. We only have to name it."
> - Changes: delete orphan trait in sb.bl; "Also make the `sb_write_char(ch: Str)` FFI shim take `Char`, to match StringBuildOps."; §3 ~2965 -> "**`fmt` is effect-free.** `fmt` declares no effect row. By §4.1 and the no-widening rule for impl rows, no implementation may perform IO or any other effect. It may write only into the `sb` it receives."; amendment note to point 4: "Realized as the empty effect row. No new effect is introduced."; close blocked ticket as moot.
> - Gives up: "Cannot read external state" (a lint on Display impls can use the inferred read set later — "a tooling change, not a language change"); "Allocate observably" — "means nothing in a GC'd language with no allocation effect. Drop it."; "Cache-friendly interpolation" — "Drop the promise and let the optimizer earn it."
> - "this adds zero concepts and removes one: a ghost effect that §4 never defined."
> - Cross-language: "Blink's empty row is already stronger than Rust's. Haskell's `Show` is pure only because the whole language is pure. It needed no special marker, which is the same argument as M1."
> M2 (fallback, voted against): StringBuilderPure as a spec prose term, not a declaration. "a name with no syntax is a trap for readers and for LLM training data ("where is it declared?")".
> Rejected: real effect; keep+fix sb.bl trait ("gives dead code a correct signature"); `@pure` attribute ("§4.16.3 already rejected a user-facing purity annotation").
> Vote intent: M1.

#### Phase B — Debate (one round)

The moderator grouped the proposals into Q1 (what `StringBuilderPure` is: 1A delete the name / 1B real effect / 1C prose-only term), Q2 (orphan trait), Q3 (unenforced claims), Q4 (scope of the impl-row rule, with the probe above as a fact), Q5 (module-level `let mut` in `fmt`: 5a no check / 5b lint / 5c error) and two single-panelist items (the `sb_write_char` shim, the diagnostic text). Five of six replied "STABLE — ready to vote" after round 1.

- **Systems:**

> Sys round 1: 1A yes. Delete the orphan trait. Strike the claims. Q4 is a capability hole in every trait, not only Display, so the spec must extend the rule. 5b (devops variant) is OK; 5c no.
>
> **Q1:** 1A. A named effect grants capabilities and cannot restrict them. 1B would add an effect with zero operations, which compiles to nothing and means nothing. 1C adds a term for a reader to learn and gives nothing back. No to both.
>
> **Q2:** Delete the trait and the traits.bl:5 comment. I also back min's fix: `sb_write_char` should take `Char`. A shim that takes Str behind a method that takes Char costs a conversion on every call, and it is the same mismatch that started this ticket.
>
> **Q3:** Strike all four claims. Keep a claim only if a check enforces it (plt/devops point).
>
> **Q4:** The moderator's probe settles it: today an impl of a required method can widen the trait's row. That is not about Display. It is a hole in the capability model. A generic `fn f[T: Shout](x: T) -> Int` has no row, and with a `Box` impl it does IO that no caller granted. §4.1's "the compiler proves it" is false for every generic call through a trait today. The four who said §3:2221 already covers this read text that says "open default" and nothing else. Fix:
> - Spec: generalize both passages (§3:2221, §4.5:938) to "every trait method, required or default: impl row ⊆ trait row".
> - Checker: add the check. It is a compile-time set compare, with no codegen or runtime cost.
> - Log a type:bug with the probe as the MVCE. It blocks the Display effect-row ticket, since an empty row on fmt means nothing without the check.
> Also yes to devops's wording: the error names the trait contract and says that `"{x}"`, `x.display()` and `sb.write(x)` run fmt with no handler in scope.
>
> **Q5:** I move from 5a to **5b, devops variant**: warn on writes, off for reads, severity configurable. The write sets already exist (§4.16.1), so the lint is free to run and adds no syntax. A write in fmt is almost always a bug: output that changes with call count and differs between `"{x}"` and `x.display()`. People who do it on purpose, like a debug counter, can silence the warning.
> - Against web's merged variant: reads of config or module constants in fmt are normal (a precision setting, for example). Warning on them is noise, and noise teaches people to turn a lint off.
> - Against 5c as an error: it makes one trait a special case in the typechecker, and it blocks the debug-counter case with no optimization that needs the purity. If a future pass memoizes or constant-folds interpolation, it can promote the write lint to an error then. The write-set data will already be there.
>
> STABLE — ready to vote

- **Web/Scripting:**

> Q1: 1A. Oppose 1B and 1C. A prose-only term (1C) is the worst DX: a name in the docs that users can't write, import or grep for is a guaranteed "what is StringBuilderPure?" FAQ.
>
> Q2: Delete it, and remove the traits.bl:5 comment. Agree with min's side item: make the `sb_write_char` FFI shim take `Char` so no `Str` write_char is left anywhere in sb.bl.
>
> Q3: Strike the unenforced claims. The spec should promise only what a check enforces. "Referentially transparent" and "cache-friendly" go. What's left: "fmt performs no effects; it may write into sb."
>
> Q4: The fact changes things, and it is the most important item. My W1 assumed §3:2221 covered required methods. The probe shows it does not, and today `fmt(...) ! IO` compiles. So without Q4, 1A promises nothing. I now say Q4 is REQUIRED, not optional: extend R_o ⊆ R_d to EVERY trait method, required or default. §3:2221 and §4.5:938 should state one general rule ("an impl method's row must be a subset of the trait method's row"), and the default-override wording becomes a special case. This is a bug fix to trait soundness and not Display-specific. `fn show[T: Shout](x: T)` with no row can call `x.shout()` and do IO today, which is a capability leak. A JS/TS dev already expects this: in TS a class method that doesn't match the interface signature fails to compile. Also back devops's diagnostic wording. The error must name the trait contract and show a fix. For Display, the fix line should be "format the data in fmt; do the IO at the call site".
>
> The Q4 fix breaks any impl that widens today. Someone should grep lib/std and tests for impls with `!` on required methods before the fix lands. I expect few hits, but it is a migration.
>
> Q5: I'm changing my position. I now prefer 5a (no check in v1). Second choice: devops P2 (warn on writes only, reads off). Oppose 5c.
> Reasoning: my W2 flagged reads and writes the same way, and that is wrong for the 90% case. Reading a module config in fmt (a precision or locale setting) is normal Python/JS practice, and a warning there is noise people will learn to silence. Writes in fmt are rare. The Q4 rule already blocks every serious case (IO, Net, DB). An error (5c) is a new rule tied to one trait, and its read half is deferred anyway. That leaves a half-rule to explain. Ship 1A + Q4 and add the lint later if real code shows the need (YAGNI).
>
> Other: support devops's diagnostic note, see Q4.
>
> STABLE — ready to vote

- **PLT:**

> PLT round 1 reply: Q4 is a soundness hole that 1A depends on; I move from 5c to 5b on Q5.
>
> **Q1.** 1A. Against 1B, for the reasons in my P3: a "negative" effect has no monotone typing rule. Against 1C: a prose term with no declaration and no check is a name that pretends to be a guarantee.
>
> **Q2.** Delete. Also yes to min's change: make the `sb_write_char` shim take `Char`. The FFI shim type should match the surface signature. A `Str` there is a latent mismatch at the C boundary.
>
> **Q3.** Strike every claim that no check enforces. The rule is that the spec states only what the compiler proves.
>
> **Q4 (the most important item this round).** The probe shows that my P1 rested on a rule that does not cover this case. §3:2221 and §4.5:938 cover only overrides of defaults. As things stand, an impl of a required method can widen the trait's row. That is unsound. Take `fn show_all[T: Display](xs: List[T]) -> Str`, typed pure. It calls `x.fmt(sb)`, and under monomorphization it runs `io.println` with no grant and no handler in scope. That breaks the capability thesis in §4.1: effects escape through a trait bound. The same hole exists for every trait, not only Display.
>
> So I side with sys and devops: generalize the rule. For every trait method m, whether required, open default, or overridden, and for every impl of m: R_impl ⊆ R_trait(m). This is the standard rule. It is what makes a bound `T: Tr` give a sound upper bound on effects, and Koka's and OCaml-with-effects' module signatures work the same way. Put the rule in §4.5 as a general statement, and have §3:2221 point to it.
>
> 1A without Q4 is unsound, so this is a precondition, not a side item. It is also a bug in today's gen1, which accepts the probe. Once the spec is fixed, file it as `type:bug`. I also support devops's wording for the diagnostic: name the trait contract and say that `"{x}"` / `display()` / `sb.write(x)` call fmt with no handlers in scope.
>
> **Q5.** I change from 5c to 5b. My P2 argued for a hard error because the spec claimed referential transparency and cacheability. Q3 strikes those claims, so no language rule and no compiler transformation depends on fmt leaving module state alone. An error should guard an invariant that something relies on. Without such an invariant, this is a style hazard. The hazard is real: `display()` called twice changes program state, and interpolation order becomes observable. So devops's P2 is the right size: warn on a non-empty write set, and leave reads off, because reads are free by §4.16 and cross-module read sets do not exist yet.
>
> If a later feature relies on fmt being state-free (memoized interpolation, reordering), upgrade the warning to an error at that time, together with the claim it protects. Against 5a: the analysis already exists and costs nothing, so skipping the warning gains nothing.
>
> OPEN (only on whether the panel adopts Q4 as a general rule; my position on the rest is fixed).

- **DevOps:**

> DEVOPS Phase B round 1: Q4 is load-bearing. Without it, 1A promises a purity that the compiler does not check.
>
> Q1: 1A. 1C (a prose term with no declaration) is worse than nothing for tooling: the LSP hover and `blink doc` would find no definition for the name, and users would search for a symbol that does not exist. Against 1B, for the reasons in my Phase A text.
>
> Q2: Delete it. I also back min's shim fix: `sb_write_char(ch: Str)` should take `Char`. That mismatch is where the ticket started.
>
> Q3: Strike the claims. The spec should promise only what a check enforces. If Q5 ends in a check, keep one sentence and cite its code.
>
> Q4: The facts settle it. §3:2221 and §4.5:938 cover only open defaults. The probe shows `impl Display for Pt { fn fmt(...) ! IO }` compiles today. So under 1A alone, "the empty row is the contract" holds for nobody: any impl can widen the row and the build stays green. The four panelists who cite 2221/938 are relying on text that does not reach required methods. Extend the rule to every trait method, required or default: R_impl ⊆ R_trait. This is a general soundness hole, not only a Display one. Generic code over `T: Shout` sees a pure signature and can call an IO-performing body in a context that holds no IO handler. Spec: one sentence in §4.5 and a pointer from §3:2221. Before the fix, write a failing test with the probe above. The diagnostic must name the trait's declared row and point at the widened effect. For `Display.fmt`, add the note that "{x}", x.display() and sb.write(x) run fmt with no handlers in scope. Without that note, users will see only "effect mismatch" and not know why.
>
> Q5: I keep 5b and refine it. One lint code reports writes at warn by default. Reads are off by default, and the user can turn them on. Against web's unsplit version: reading a module-level locale or config is legitimate, and a warning that fires on correct code gets turned off wholesale, so it then catches nothing. On plt's 5c: an error on the write half is sound, but it needs its own error code, cannot be tuned per project, and a later relaxation would be a breaking change. With 5b the user can already set `W0552 = "error"` in config, using the same mechanism as W0550 and W0551, so it gives 5c's strength to anyone who wants it. Against 5a: mutation analysis already computes the write set, so the lint costs almost nothing and catches the one real leak left after Q4. If the panel prefers 5c, I accept the write half as my second choice. It still beats 5a.
>
> STABLE — ready to vote

- **AI/ML:**

> **Q1: 1A.** 1B was only a fallback for me and I withdraw it. I oppose 1C, because a prose term with no declaration is exactly what an LLM will try to write as `! StringBuilderPure` and then get an unknown-effect error.
>
> **Q2: delete it.** I agree.
>
> **Q3: strike them.** A claim that no check enforces is worse than no claim. Models copy the spec's promises into generated code comments and into their reasoning about programs ("fmt is cached, so I can…"). Keep only what the compiler checks.
>
> **Q4: the facts change my position. I now support the general rule (sys/devops).** In Phase A I claimed that §4:938 already enforces the empty row at every `fmt` impl. The moderator's probe shows that claim was wrong. The rule covers only overrides of open defaults, and gen1 accepts `fn fmt(...) ! IO`. Without an extension, 1A is a contract nobody enforces. The rule must be general. For every trait method, required or default, an impl's row must be a subset of the row the trait declares.
> - Correctness: without it, the widening hole affects every trait, not only Display. Generic code over `T: Shout` performs IO while its own signature shows no `!`. That breaks §4.1's "the compiler proves it" for all generic code.
> - Learnability: one rule ("an impl can never declare more effects than its trait") is simpler to learn from the spec than "defaults are checked, required methods are not". A split rule is one more decision point, and nobody can guess it.
> - Write it once, in §4 near line 938, and have §3:2221 point to it. Rename the paragraph to "Effect rows on trait method impls".
> - Diagnostic: I support devops's wording. Name the trait's row and the widened effect, and add a Display-specific note because it is the most common case.
>
> **Q5: 5a for v1.** I oppose 5c, and 5b is acceptable only as a warning on writes.
> - 5c creates a rule that applies to one trait only ("fmt, and only fmt, may not assign module `let mut`"). Such a rule is special knowledge that no model can derive from the general effect model, and it adds a diagnostic name for a rare pattern. It also depends on read sets that do not exist yet.
> - 5b as a writes-only warning costs nothing in generated code, because models do not write module state in fmt. I will not block it, but I prefer that a later general lint ("trait impl mutates module state") covers it instead of a fmt-only lint. Severity-configurable reads add another setting to learn, so I say no to that part.
> - Whichever variant wins, the spec text must not say fmt "cannot mutate state outside the builder" unless 5c passes.
>
> **Other items:**
> - Change the `sb_write_char` shim to take `Char`: yes. Its type must match `StringBuildOps.write_char`, otherwise the mismatch this ticket found comes back one layer down.
> - devops's diagnostic note: yes.
>
> STABLE — ready to vote

- **Minimalism:**

> Q1: 1A. I withdraw my M2 fallback. With six votes for 1A it has no job left.
>
> Q2: Delete it. I also keep my small add-on: fix the `sb_write_char(ch: Str)` FFI shim in sb.bl to take `Char`. This is an stdlib fix, not a spec change. Log it as a chore if the panel prefers.
>
> Q3: Strike every claim the compiler does not enforce. Spec text that promises more than the checker proves is a latent bug, and it is also bad training data.
>
> Q4: The facts change my view. I cited §3:2221 and §4:938 as enough, and they are not. They cover open defaults only, and gen1 accepts `impl Display for Pt { fn fmt(...) ! IO }`. Without a general rule, 1A leaves `Display.fmt` with no guarantee at all. So I now support sys's and devops's extension. State it once: "Every impl of a trait method, required or default, declares a row R_o ⊆ R_d, where R_d is the trait's declared row (empty if none)."
>
> This passes my own test for additions. It adds no syntax and no concept. It turns a rule that only covered defaults into one uniform rule, and it closes a soundness hole: a generic `fn f[T: Shout](x: T)` with no row can call `x.shout()` and do IO without a grant. That breaks §4.1's "the compiler proves it" for every trait, not only Display, which makes the rule foundational. It also needs a compiler `type:bug` with the MVCE above, and the fix must come before the Display row work closes.
>
> devops's diagnostic wording is fine as the error's text. It is implementation detail, so it gets no spec vote.
>
> Q5: 5a, no check in v1.
>
> - Against 5c (a checked error): it makes Display the one trait with purity rules beyond its effect row. That is a second purity system inside a single trait, which is the thing we just deleted in Q1. plt's write-only half is an odd split to teach ("you may read the counter but not bump it"). §4.16 says module state is not an effect, and one trait should not overturn that.
> - Against 5b (a lint) as a spec item: it is harmless, but YAGNI. We have zero reported bugs from module-state access in fmt. Lints are tooling, and a lint can ship later without a panel. I would not oppose one tooling ticket at severity "off by default". I oppose writing it into §3 now.
> - For 5a: the empty effect row blocks IO, network, DB and FFI. A `fmt` that reads a module-level config flag is legitimate. A `fmt` that writes module state is odd but visible to mutation analysis, and the LSP shows it already.
>
> STABLE — ready to vote

#### Phase C — Final vote

- **Q1: what `StringBuilderPure` is** — **1A, 6-0**: delete the name; `Display.fmt` has no effect row; the empty row is the contract.
- **Q2: orphan `pub trait StringBuilderPure`** — **DELETE, 6-0**.
- **Q3: unenforced claims** ("cannot read external state", "allocate observably", "referentially transparent", "cache-friendly") — **STRIKE, 6-0**.
- **Q4: impl effect-row rule** — **GENERAL, 6-0**: `R_impl ⊆ R_trait` for every trait method, required or default.
- **Q5: module-level `let mut` in `fmt`** — **3-3** (5b: DevOps, Systems, PLT; 5a: Web, Minimalism, AI/ML). Went to Phase D.
- **Q6: `sb_write_char` shim takes `Char`** — **YES, 6-0**.

Each ballot in full:

- **Systems:**

> Sys ballot (Phase C): Q1 1A, Q2 DELETE, Q3 STRIKE, Q4 GENERAL, Q5 5b, Q6 YES.
>
> Q1 — 1A
> Reasoning: An effect row grants capabilities and cannot restrict them. A "purity" effect with zero operations compiles to nothing: no handle, no dispatch, no handler. The empty row states the contract with a mechanism that already exists, and costs nothing in codegen.
> Concern: 1A holds only if Q4 lands and is enforced. Once the spec text changes, the empty row reads as a guarantee while gen1 still accepts `fmt(...) ! IO`, and it stays that way until the checker fix ships.
>
> Q2 — DELETE
> Reasoning: Nothing implements the trait or refers to it. It copies part of StringBuildOps and misleads readers into thinking it is the effect. Dead declarations in lib/std become training data.
> Concern: None of substance. A grep before the delete confirms that no user of the name remains in tests.
>
> Q3 — STRIKE
> Reasoning: No pass memoizes or constant-folds interpolation, and reads of module `let mut` are untracked. So "referentially transparent" and "cache-friendly" promise an optimization the compiler cannot legally perform. "Allocate observably" is wrong on its face, because the builder grows.
> Concern: A future optimization author may want these back. They must come back together with the check that makes them true, not as prose.
>
> Q4 — GENERAL
> Reasoning: The probe shows that effects escape through a trait bound today. A monomorphized `f[T: Shout]` that is typed pure runs IO with no grant, which breaks §4.1 for all generic code. The fix is a set compare at compile time for each impl method, with zero runtime or codegen cost.
> Concern: Any existing impl that widens today breaks. Grep lib/std and tests (including FFI-backed impls that carry `! FFI` under a pure trait method) before the check lands, or the gate turns red with no clear cause.
>
> Q5 — 5b
> Reasoning: mutation analysis already computes write sets, so the lint is free to run and adds no syntax. A write in fmt makes `"{x}"` and `x.display()` depend on call count, which is almost always a bug. Reads stay off because reading a precision or locale setting is normal, and noise trains people to turn the lint off.
> Concern: If 5a wins, the write case stays silent, but nothing depends on it, so the risk is low. If 5b wins, keep it as a tooling item and do not add a purity sentence to §3 that the lint does not enforce.
>
> Q6 — YES
> Reasoning: A Str shim behind a Char method adds a conversion on every call at the C boundary. It is the same mismatch this ticket was opened for, one layer down.
> Concern: The Char ABI at the shim must match the runtime's C type for Char (int32 vs int64). Check blink_sb_write_char's C signature when changing it.

- **Web/Scripting:**

> WEB — Phase C ballot
>
> Q1: 1A
> Reasoning: Dropping the row gives the 90% case a Display impl that looks like Kotlin toString / Python __str__, with no mystery keyword to copy. A name users can't declare, import or look up (1B with zero operations, or 1C in prose only) just makes a FAQ.
> Concern: Users coming from Rust or Haskell may think "no row" means "unchecked". The Display docs must say in one line that the empty row IS the check.
>
> Q2: DELETE
> Reasoning: Nothing uses it, it duplicates StringBuildOps, and it has already drifted once (the bug in this ticket). Dead public API in stdlib gets found by autocomplete and confuses people.
> Concern: None real. Grep tests/ for any reference before deleting so the corpus does not lose a file.
>
> Q3: STRIKE
> Reasoning: A spec promise the compiler does not keep is a latent bug for users and bad training data. Keep only "fmt performs no effects; it may write into sb."
> Concern: Someone later adds memoized interpolation, relying on the struck claims being implied. That feature must bring its own check.
>
> Q4: GENERAL
> Reasoning: Without it, 1A promises nothing: gen1 accepts `fmt(...) ! IO` today, and any trait bound leaks capabilities. One rule ("an impl can never declare more effects than its trait") is what a TS/Kotlin dev already expects from interface conformance, and it is easier to learn than "checked for defaults only".
> Concern: Migration. Existing impls in lib/std, tests and user code that widen a required method's row break at once. Grep for them first, and make the diagnostic show the fix ("do the IO at the call site; fmt only formats"), or this becomes the new top Stack Overflow question.
>
> Q5: 5a
> Reasoning: After Q4, the empty row already blocks every serious case (IO, Net, DB, FFI). Writes to module state in fmt are rare, and a lint is tooling that can ship later without a spec vote if real code shows the need (YAGNI). I would not fight a writes-only, reads-off lint, but it doesn't belong in §3 now.
> Concern: If 5b wins, keep it strictly writes-only by default. A warning on config reads trains users to disable the whole lint.
>
> Q6: YES
> Reasoning: The FFI shim should match `StringBuildOps.write_char(c: Char)`. A `Str` there is the same mismatch this ticket found, one layer down, plus a conversion on every call.
> Concern: The C side (blink_sb_write_char) must change its parameter type in step with it, or it hits an ABI mismatch that compiles and then gives wrong output.

- **PLT:**

> PLT ballot: Q1 1A, Q2 DELETE, Q3 STRIKE, Q4 GENERAL, Q5 5b, Q6 YES.
>
> **Q1: 1A**
> - Reasoning: Effect rows are upper bounds on capability, and a row is monotone under subtyping. A label cannot remove a capability, so "StringBuilderPure" has no typing rule as an effect. The empty row is already the least element of the lattice and says "pure" with no new concept.
> - Concern: 1A is a guarantee only if the Q4 rule is in force. If Q4 slips, "fmt has an empty row" is decoration.
>
> **Q2: DELETE**
> - Reasoning: The trait has no impls and no references, and StringBuildOps already covers it. Its name caused the spec to invent an effect. Keeping it keeps the confusion.
> - Concern: Almost none. Someone must also remove the traits.bl:5 comment, so the "naming is still open" note does not outlive the decision.
>
> **Q3: STRIKE**
> - Reasoning: A spec claim with no check behind it is an axiom the implementation does not model. Anyone who reasons from it (a user, an optimization, a model trained on the spec) reasons unsoundly. What remains is exact: "fmt has an empty effect row; it may write to sb."
> - Concern: A later feature (memoized interpolation) could bring back "cache-friendly" as an assumption without first adding the check that would justify it.
>
> **Q4: GENERAL**
> - Reasoning: For every trait method, required or default, R_impl ⊆ R_trait. This is the rule that makes the bound `T: Tr` a sound upper bound on effects. Without it, effects escape through generic calls, which breaks §4.1's "the compiler proves it" for every trait. It is standard in Koka and in effect-typed module signatures, and it unifies two rules into one.
> - Concern: The fix may break existing lib/std or test impls that widen today. Grep for them and put a failing probe test in first, so the gate does not surprise anyone.
>
> **Q5: 5b** (warn on a non-empty write set, reads off, severity configurable)
> - Reasoning: Once Q3 strikes the transparency claim, no invariant depends on fmt leaving module state alone, so a hard error (5c) guards nothing. But a write in fmt makes the number of `display()` calls and the order of interpolation observable. That is a real semantic hazard, and the write-set analysis (§4.16) detects it at no cost. Reads stay off because §4.16 makes them free and cross-module read sets do not exist.
> - Concern: If a later feature starts to rely on fmt being state-free, the lint must become an error with a new claim in the spec. It must not stay a warning that someone quietly depends on.
>
> **Q6: YES**
> - Reasoning: The FFI shim's type must match the surface signature `write_char(self, c: Char)`. A `Str` at the C boundary is a latent type mismatch and the same drift that started this ticket.
> - Concern: The C side (`blink_sb_write_char`) must change in step with the shim (encode the Char as a code point, not a string pointer), or the ABI breaks silently.

- **DevOps:**

> DEVOPS ballot: 1A, DELETE, STRIKE, GENERAL, 5b, YES.
>
> Q1: 1A
> Reasoning: The tooling has to be able to explain every name in a signature. An empty row explains itself on hover. 1B puts a zero-operation effect into every `"{x}"` site's inlay hints. 1C leaves a name that hover, `blink doc` and go-to-definition cannot resolve.
> Concern: Old docs, the decision record and model training data will still say `! StringBuilderPure`. If a user writes it, they get a bare "unknown effect" error. That error should suggest "remove the row; Display.fmt is pure".
>
> Q2: DELETE
> Reasoning: An unused public trait still shows up in completion lists and `blink doc`, and it offers a second `write_char` that conflicts with the real one. Tooling surfaces should not advertise dead API.
> Concern: None from my side. It has no references, so deleting it breaks nothing.
>
> Q3: STRIKE
> Reasoning: The spec text becomes LSP hover docs and training data. A claim that no diagnostic backs is a promise the toolchain cannot keep, and a user cannot find out it is false until runtime.
> Concern: If the rewritten paragraph goes too far and drops "fmt may write into sb", users lose the one thing fmt is for.
>
> Q4: GENERAL
> Reasoning: The probe shows `fmt(...) ! IO` compiles today, so without this rule 1A is a promise nobody checks. One uniform rule gives one diagnostic, one fix-it and one sentence of spec text. A rule that covers defaults only would be a hole users cannot predict. The error must name the trait's declared row and point at the widened effect. The Display case gets a note that "{x}", x.display() and sb.write(x) run fmt with no handlers in scope.
> Concern: It is a breaking check. Before it lands, grep lib/std, the tests and pkg for impls that widen a required method's row, and start the rollout with a failing test that uses the probe.
>
> Q5: 5b
> Reasoning: Mutation analysis already computes the write set, so this lint is almost free. It catches the one leak Q4 leaves: display() output that changes with call count. It uses the same severity config as W0550/W0551, so a project can raise it to error without a new language rule. Reads stay off because reading a locale or config setting is correct code, and a lint that fires on correct code gets turned off entirely.
> Concern: If 5a wins, the leak stays silent until a user files a bug. It should then at least be logged as a tooling ticket so it is not lost.
>
> Q6: YES
> Reasoning: The FFI shim type should match the surface `StringBuildOps.write_char(c: Char)`. A `Str` shim hides the same mismatch this ticket was filed for, and `blink query` and the tooling that reads the shim would show the wrong type.
> Concern: The C side (blink_sb_write_char) must take the same argument type. Check it at the C boundary, not only in the .bl signature.

- **AI/ML:**

> AI/ML ballot, Phase C
>
> **Q1: 1A**
> - Reasoning: The empty row reuses the one rule models already learn from §4.1 ("no `!` means no effects"), so fmt adds zero decision points and zero tokens. 1B brings in a restricting effect that inverts the grant model. 1C names something a model will try to write and cannot.
> - Concern: Training data and older docs still contain `! StringBuilderPure`, so models will keep emitting it for a while. The unknown-effect error should suggest "remove the row; Display.fmt has no effects".
>
> **Q2: DELETE**
> - Reasoning: A public trait with no users that duplicates StringBuildOps is a trap. `blink doc`/LSP will surface it, and models will try to implement it or bound on it.
> - Concern: None worth noting. Just grep tests/ and lib/ for stray references before removing it.
>
> **Q3: STRIKE**
> - Reasoning: Models copy the spec's promises into their reasoning ("fmt is cached, so…"). A claim no check enforces generates wrong code with confidence. State only "fmt performs no effects; it may write into sb".
> - Concern: Striking too much can hide the one true point. Keep the sentence saying the empty row is the contract, and point to the Q4 rule.
>
> **Q4: GENERAL**
> - Reasoning: One uniform rule ("an impl never declares more effects than its trait method") is learnable from the spec alone. A rule for defaults only is a hidden split that no model can guess. Without GENERAL, 1A is unenforced, and effects leak through every trait bound.
> - Concern: The fix breaks any existing impl that widens a required method's row. The migration needs a sweep of lib/std and tests, and a diagnostic whose fix-it text an LLM can apply mechanically.
>
> **Q5: 5a**
> - Reasoning: After Q4, the empty row blocks every capability that matters. Module-state writes in fmt are rare in generated code. A lint that applies to fmt only is special knowledge, not derivable from the general effect model. A tooling lint can ship later without a spec clause if real code shows the need (YAGNI).
> - Concern: If 5b wins, it could harden into a fmt-only spec rule with read/write severity knobs. Keep it a tooling lint over trait impls in general, out of §3's normative text.
>
> **Q6: YES**
> - Reasoning: The FFI shim type must match `StringBuildOps.write_char(c: Char)`. Otherwise the mismatch this ticket found survives one layer down, and readers of sb.bl (human or model) learn two signatures for one operation.
> - Concern: The C side (`blink_sb_write_char`) must take the Char's ABI type too. Changing only the Blink declaration would create a silent ABI mismatch.

- **Minimalism:**

> Min ballot (Phase C): Q1 1A | Q2 DELETE | Q3 STRIKE | Q4 GENERAL | Q5 5a | Q6 YES
>
> Q1 — 1A
> Reasoning: no new concepts. The empty row, together with §4.1, already says what locked point 4 meant. A named effect that restricts instead of grants would be a new semantic category (1B). A name with no declaration is a trap for readers and for models (1C).
> Concern: someone later reads "fmt has no row" as an oversight and adds one. The §3 paragraph must say plainly that the empty row is the contract.
>
> Q2 — DELETE
> Reasoning: it has zero users and duplicates the sealed StringBuildOps trait, and its name collides with the concept we just removed. Dead code in lib/std becomes training data.
> Concern: none worth noting. Grep confirms no references.
>
> Q3 — STRIKE
> Reasoning: the spec must promise only what the checker proves. "Allocate observably" means nothing in a GC'd language, and "cache-friendly" guards an optimization nobody has built.
> Concern: without the claims, a future memoizing pass has no stated invariant to lean on. That pass must bring its own rule and its own panel, which is correct but will be slower.
>
> Q4 — GENERAL
> Reasoning: this closes a soundness hole in every trait bound (`fn f[T: Shout](x: T)` does IO with no grant), and it adds no syntax or concept. It replaces a rule for defaults only with one uniform rule, so this is subtraction of special cases. Without it, 1A guarantees nothing.
> Concern: the fix breaks any existing impl that widens a required method's row. Grep lib/std, tests and src before the checker change lands, and log the checker fix as a type:bug with the probe as the failing test first.
>
> Q5 — 5a
> Reasoning: after Q3 strikes the purity claims, nothing in the language or compiler relies on fmt leaving module state alone, and §4.16 says module state is not an effect. A lint aimed at fmt only is a per-trait rule, the first of its kind, and nobody has reported a real bug from this pattern. Mutation analysis and the LSP already make write sets visible. A general "trait impl mutates module state" lint can ship later as tooling without a spec change (aiml's point).
> Concern: if 5b wins, it sets a precedent for trait-specific lints (why fmt and not eq or hash?). Scope it in the ticket as a tooling lint, not spec text in §3, so that it can be widened or dropped without a panel.
>
> Q6 — YES
> Reasoning: the FFI shim type must match the StringBuildOps surface signature. A Str behind a Char method is the mismatch this ticket started from, one layer down.
> Concern: the C runtime `blink_sb_write_char` must accept the Char representation (a codepoint int) at the ABI. Check the runtime header, not only the .bl declaration, or the change compiles and writes garbage.

#### Phase D — Round 2 on Q5

The moderator relayed each panelist's Q5 reasoning and concern verbatim and asked for one reply per panelist, which counted as the Phase D ballot.

**Q5 result: 6-0 for a refined 5a** — no Q5 text in the spec, and one tooling ticket (`type:feature`) for a lint that warns when an impl of a trait method has a non-empty module write set. The lint is writes only, reads off, warn by default, severity configurable like W0550/W0551, and it ships, widens or drops without a panel. The scope of the lint is a ticket detail, not spec, and split three ways: Display.fmt, Eq.eq, Hash.hash and Ord.cmp (Systems, Web, DevOps, PLT); any trait impl method (AI/ML); any impl of a trait method whose declared row is empty (Minimalism). The ticket is filed with the four-trait scope and records the other two.

- **Systems:**

> Sys Phase D, Q5: I move to 5a for the spec, plus one tooling ticket for a general write-set lint. If you need a binary count, record me as 5a.
>
> Response: the 5a side's best point is min's "why fmt and not eq or hash?", and from a systems view it is stronger than they stated. A module-state write inside `hash` or `eq` is worse than one inside `fmt`. It breaks Map and Set invariants: the same key hashes to two buckets, and lookups fail silently. That is a correctness failure in the runtime data structures, not merely odd output. So a lint aimed at fmt alone is aimed at the least harmful case. Also, the two sides now agree on everything that matters. All six say reads stay off and no normative text goes into §3. The only difference left is whether to open a tooling ticket, and both concerns on the 5b side ("log it so it is not lost", "no purity sentence in §3") are met by 5a plus that ticket.
>
> Final vote: 5a (refined). §3 gets no module-state rule for fmt. Log one tooling ticket: a lint that warns when an impl of a compiler-dispatched prelude trait method (Display.fmt, Eq.eq, Hash.hash, Ord.cmp) has a non-empty inferred write set, with reads off and severity configurable like W0550/W0551.
> Reasoning: The write set is already computed (§4.16.1), so the lint is free to run and adds no syntax. Scoping it to the traits the runtime and codegen call implicitly (interpolation, map keys, sorting) targets real hazards and not one trait by accident. It stays tooling, so it can widen or drop without a panel.
> Concern: The ticket may sit unworked, and a real hash-inconsistency bug then shows up first in user code as a "map lost my key" report, not as a warning.

- **Web/Scripting:**

> WEB — Phase D, Q5
>
> Response: The two sides disagree less than the tally shows. All six keep it out of §3's normative text (sys, min, aiml, and me say so outright; devops and plt frame it as tooling config). All six want writes only and reads off. Nobody wants an error. The real gap is whether the panel commits to a lint now. The 5b side has a fair point: the write-count hazard is real and costs almost nothing to detect (plt's "display() twice changes state"). The 5a side also has a fair point: a lint for fmt only is a new kind of per-trait rule (min: "why fmt and not eq or hash?"). Both points are true, and together they give one answer. The lint should target the hazard, not the trait. The hazard is the same for eq, hash, cmp and fmt: the compiler and stdlib call them implicitly, often more than once and in an order the user doesn't control.
>
> Final vote: refined 5a+ (spec: 5a; tooling: a ticket).
> - Spec: no Q5 text in §3 or §4. The struck claims stay struck.
> - Tooling: log one ticket for a writes-only lint (reads off, severity configurable like W0550/W0551). It fires when an impl of a method that the compiler calls implicitly (Display.fmt, Eq.eq, Hash.hash, Ord.cmp) has a non-empty module write set. No panel needed to ship, widen or drop it.
>
> Reasoning: This gives devops what they asked for: the leak is logged and doesn't depend on someone filing a bug. It gives min and aiml a lint that follows from a general rule ("implicitly-called methods shouldn't bump globals") instead of Display-only knowledge. A Python dev would find `__eq__` or `__hash__` that increments a global exactly as surprising as `__str__`, so one rule over all four matches what users expect.
>
> Concern: If the ticket sits unimplemented, this is 5a in practice. It should get a priority, and its MVCE should be the `display()`-twice case.
>
> If the moderator must count this as a binary, count it as 5a.

- **PLT:**

> PLT Phase D ballot on Q5: I vote 5a′. If only the listed labels count, count me as 5a.
>
> **Response.** The two sides disagree less than the 3-3 tie suggests. All six agree on four points:
> - No normative text goes in §3.
> - Writes only; reads stay off.
> - The analysis already exists.
> - The hazard is real but rare.
>
> What is left is scope and timing: a lint for fmt only now, or a general lint later. On scope, min and aiml are right, and it is a PLT argument, not only a minimalism one. The call-count hazard is not specific to fmt. It is worse for `Eq.eq`, `Hash.hash` and `Ord.cmp`. A hash that writes module state breaks Map and Set invariants, and an eq that does so makes equality depend on call history. Those are correctness failures. A fmt that writes is only an odd output. A lint for fmt alone would be the first trait-specific rule and would protect the least critical member of the family. That is the wrong precedent. Unlike Q4, this is not a soundness issue: §4.16 puts module state outside the effect system by design, so no typing rule is broken either way. I withdraw my support for a fmt-only lint.
>
> **Final vote: 5a′ (refined 5a).**
> - Spec: no check and no §3 text in v1, as in 5a.
> - In the same decision record: file one tooling ticket for a general lint. It warns when an impl of a compiler-known prelude trait method (Display.fmt, Eq.eq, Hash.hash, Ord.cmp) has a non-empty inferred write set. Reads stay off, and severity is configurable like W0550 and W0551.
> - The lint ships as tooling, with no panel needed to widen or drop it.
>
> This keeps devops's point: the hazard gets logged and is not lost. It also keeps min's and aiml's point: no fmt-special rule and no spec clause.
>
> **Reasoning.** Once Q3 strikes the claims, no invariant depends on fmt leaving module state alone, so the question belongs to tooling, not the spec. The same hazard applies with more force to eq, hash and cmp, where the collection laws do depend on it. So the right unit is one lint over the prelude trait family, not a rule for fmt only. Logging it now closes devops's concern at no cost to the spec.
>
> **Concern.** If a later feature, such as memoized interpolation or hash caching, starts to rely on these methods being state-free, the lint must become a checked error with a matching spec claim. It must not stay a warning that code quietly depends on.

- **DevOps:**

> DEVOPS Phase D (Q5): I switch to a refined variant, 5a' = 5a plus a tracked tooling ticket.
>
> Response to the 5a side: both sides want the same outcome. All six ballots accept a writes-only, reads-off lint, and all six keep it out of §3's normative text (sys and I said so too). So the tie is about where the lint lives, not whether it may exist. min's precedent point persuades me: a lint aimed at fmt alone is the wrong scope. eq, hash and cmp carry the same hazard (a HashMap whose hash writes a counter is worse than a fmt that does), so a fmt-only warning code would be the first of a family built one trait at a time. That is bad diagnostic design. One lint over trait impls gives one code, one config key and one explain page, where per-trait codes multiply for the same hazard.
>
> Where I still disagree: "YAGNI, ship later" only works if "later" is written down. A lint that nobody tracks never ships, so the case stays silent.
>
> Final vote: 5a' —
> - Spec: no Q5 text in §3. §4.16 stays the authority on module state.
> - Tooling: log one type:feature ticket for a general lint: "impl of a method of a compiler-consumed trait (Display, Eq, Hash, Ord) writes module-level `let mut`". It is writes-only, reads off, warns by default and is configurable like W0550/W0551, and it needs no panel.
>
> Reasoning: this closes the tie on the substance everyone already accepts. The spec stays free of a trait-specific rule, and the tooling gap is recorded instead of forgotten. The lint's scope follows the hazard (traits the compiler calls for you), not one trait.
>
> Concern: if the ticket is not logged at decision close, 5a' collapses into plain 5a and the write leak stays silent. The moderator should log it as part of recording the decision.

- **AI/ML:**

> AI/ML, Phase D ballot on Q5
>
> **Response to the 5b side.** The two sides agree on more than the tally shows. All six ballots say the check should not be spec text in §3. Sys says it outright ("keep it as a tooling item"), and the three 5a votes say it too. Nobody wants reads flagged, and nobody wants an error. So the real split is only this: does the panel's decision list a lint as part of this ticket, or not? Devops's concern ("log it as a tooling ticket so it is not lost") and plt's hazard (display() call count and interpolation order become observable) are both fair. Neither needs the language spec, though. Plt's own argument settles it: once Q3 strikes the claim, no rule of the language depends on this, and a spec vote should record rules of the language.
>
> On scope, I keep the point min and I raised. A lint for fmt only is the first rule tied to one trait, and it invites the question "why not eq or hash?", which applies just as much. A write in `eq` or `hash` breaks Map and Set in ways that are worse than a changing display string. If the lint is worth building, it covers writes from any trait impl.
>
> **Final Q5 vote: 5a, refined.**
> - No normative text in the spec, and no lint written into §3.
> - The moderator files one tooling ticket (type:feature, not type:spec). It asks for a warning when any trait impl method has a non-empty module write set, with reads off, using the existing W05xx severity config.
> - It would ship without a panel vote, as devops wants, and would not hard-code one trait into the language.
>
> **Reasoning.** For LLM generation and learnability, spec text is what models train on. A rule that holds for fmt only is special knowledge, and no model can derive it from the general effect model. A general tooling warning over trait impls is learnable from the diagnostic itself, needs no spec reading, and costs zero tokens in correct code. This variant gives the 5b side its safeguard (the leak is caught, and the ticket is not lost) and keeps the spec minimal.
>
> **Concern.** If the lint stays unbuilt, models and users will have nothing in the tooling to tell them that a write in fmt is suspect. The ticket needs a real owner and should not sit in the backlog.

- **Minimalism:**

> Min Phase D (Q5): refined variant "5a-spec + tooling ticket". §3 gets no Q5 text; log one writes-only lint ticket outside the spec.
>
> Response to the 5b side:
> - Their facts hold. A write in fmt makes the number of display() calls and the order of interpolation observable. The write set is already computed, so the lint costs almost nothing. I concede this.
> - Read the six ballots closely and the disagreement is smaller than 3-3 suggests. All six agree on these points:
>   (1) no normative text in §3;
>   (2) writes only, reads off;
>   (3) warning severity, not an error;
>   (4) scope it as tooling so it can widen or drop without a panel.
>   sys says so ("keep it as a tooling item"), and so do plt ("must become an error with a new claim" only later), web ("wouldn't fight writes-only"), aiml ("keep it a tooling lint") and devops ("log it as a tooling ticket so it is not lost").
> - So the one real question is whether we log the ticket now or wait for a bug report. devops's concern is fair: a leak we find, decide on, and then do not record is waste. Logging a ticket costs nothing and changes no spec.
> - My remaining objection is scope. It should not be a lint for fmt only. Every trait method whose declared row is empty has the same hazard: eq, hash, cmp. A write in hash is worse than one in fmt, because it breaks Map. The tooling ticket should state the general shape: "an impl of a trait method with an empty declared row has a non-empty module write set". That shape also removes the precedent problem I raised.
>
> Final Q5 vote: the refined variant "5a-spec + tooling ticket". I accept this as equivalent to a 5b with a narrow scope.
> - Spec: Q5 adds no text to §3 or §4. The panel records that module state in fmt is not a language rule.
> - Tooling: log one `type:feature` ticket for a lint. It warns by default on a non-empty module write set in any impl of a trait method whose declared row is empty. Reads are off. Severity uses the W0550/W0551 config. It may land after Display without blocking it.
> Reasoning: it keeps the language surface unchanged, which is my domain's hard line. It still records the real hazard the 5b side found. The general "empty-row trait impl" scope derives from the effect model, so no trait-specific rule is invented (aiml's learnability point).
> Concern: a tooling ticket with no deadline may never land. If a later feature relies on fmt or hash being state-free, it must promote the lint to an error together with its spec claim, as plt says. It must not rely on the warning quietly.

### Final Spec

```blink
trait Display {
    fn fmt(self, sb: StringBuilder)
    final fn display(self) -> Str {
        let sb = StringBuilder.new()
        self.fmt(sb)
        sb.to_str()
    }
}
```

**Locked design points:**

1. **`fmt` has no effect row, and the empty row is the contract.** There is no `StringBuilderPure` effect. Writing into the supplied `sb` mutates a parameter and needs no effect (§4.16.2). This replaces locked point 4 of [display-trait-shape.md](display-trait-shape.md); its intent (no IO, no capability in `fmt`) stands.
2. **Impls may not widen a trait method's row.** For every trait method, required or open default, an impl's row `R_i` must satisfy `R_i ⊆ R_t`. A widening impl is `error[TraitContractEffectMismatch]` (E0904). Stated in §3.6 *Effect-row subtype for trait impls* and §4.5 *Effect rows on trait impls*.
3. **The spec promises only what the checker proves.** "Cannot read external state", "allocate observably", "referentially transparent" and "cache-friendly" are struck. A later feature that needs them brings its own check and its own panel.
4. **Module-level `let mut` in `fmt` is not a language rule.** §4.16 governs it. A writes-only tooling lint over the prelude traits the compiler calls implicitly is tracked as a separate feature ticket.
5. **Delete the orphan trait** in `lib/std/sb.bl` and the "still open" comment in `lib/std/traits.bl`.
6. **The `sb_write_char` FFI shim takes `Char`**, and the C function `blink_sb_write_char` changes to match the runtime's C type for `Char`.

**Implementation concerns the panel raised:**

- Grep lib/std, tests, src and pkg for impls that widen a required method's row today (including `! FFI` impls under pure trait methods) before the check lands, and start from a failing test built from the probe.
- The E0904 message names the trait's declared row and points at the widened effect; for `Display.fmt` it notes that `"{x}"`, `x.display()` and `sb.write(x)` run `fmt` with no handler in scope.
- A `! StringBuilderPure` row (from old docs or training data) gets an unknown-effect error that suggests removing the row.
