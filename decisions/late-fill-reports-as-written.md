[< All Decisions](../DECISIONS.md)

# A Late Fill Reports as if the Type Were Written — Design Rationale

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated
in independent-proposal → debate → vote rounds. Ticket IDs in the quoted text are replaced with `[ticket]`.

#### Phase A — Independent proposals

- **Systems:** (excerpt, section `G4 ([ticket]): where a late fill's conflict is reported`)

>
> **Facts.** Late dispatch reports one E0300 at `.debug()` with a note at `l.push(...)`; in-place typing reported at `takes(s)`.
>
> ### G4-P1 (preferred): one rule in §3.4: the error is at the use that waited on the unknown type, with notes at the fill and at the other constraint
>
> When a use depended on a type that a later use fixed, and the fixed type conflicts with a constraint already placed on that use's result, the error (E0300) is at the use that waited (the `.debug()` call). A `note:` names the use that fixed the type (`l.push(S { a: 1 })`), and a second `note:` names the use that set the other side (`takes(s)` expects `Str`). This generalizes the §3b template rule. With the lines in the other order (push first), nothing waits, and the error is at `takes(s)` as before.
>
> ```blink
> fn main() {
>     let mut l = []
>     if l.len() > 0 {
>         let s = l.get(0).unwrap().debug()   // error[E0300]: `debug()` on `S` returns `Int`, `Str` expected
>         takes(s)                            //   note: `takes` expects `Str` here
>     }
>     l.push(S { a: 1 })                      //   note: the element type of `l` is set to `S` here
> }
> ```
>
> Tradeoffs (systems): one pass over the body plus a deferred-constraint queue; no second walk, so check time stays linear in body size. The report names all three sites, so a reader (AI or human) sees the fix choices: annotate `l`, change `takes`, or convert the result. The site depends on line order, but the notes make the set of sites the same in both orders.
>
> ### G4-P2: report at the in-place site (re-walk after the fill)
>
> Needs a second typing pass of every body that had a late fill. Cost in compile time and a second code path that must agree with the first. The diagnostic gains little: the notes in P1 already show `takes(s)`.
>
> ### G4-P3: a method call on a not-yet-known receiver is E0301 at the call
>
> Rust's rule (E0282 "type annotations needed" at `v[0].debug()`). Simplest and cheapest, but it contradicts "later use still determines the type" for method calls, which the late-method-dispatch change just built. I note it only as the cross-language reference.

- **Web/Scripting:** (excerpt, section `G4 — where a late fill that conflicts with an earlier use is reported`)

>
> **Facts today.** Same bug, two reports by line order. Push first: `argument 1 of takes expects
> Str, got Int` at `takes(s)`. Push last: `method .debug returns Int, but its use expects Str` at
> `.debug()`.
>
> ### G4-P1 (preferred): the report does not depend on line order
>
> A conflict that a late fill reveals is reported at the same site, with the same code and message,
> as if the type had been known in place. A `note:` names the use that fixed the type. Cost: the
> checker re-checks the uses that waited on the type (a second walk) — compiler work, not user work.
>
> ```blink
> fn takes(x: Str) {}
> fn main() {
>     let mut l = []
>     if l.len() > 0 {
>         let s = l.get(0).unwrap().debug()
>         takes(s)            // error[E0300]: argument 1 of `takes` expects Str, got Int
>     }
>     l.push(S { a: 1 })      // note: the element type of `l` is `S`, fixed here
> }
> ```
>
> Moving `l.push` above the `if` gives the same error at `takes(s)`, without the note.
>
> Tradeoffs. For: the mistake is at `takes(s)` — the user passes an Int where a Str goes. Pointing
> at `.debug()` makes a reader, human or AI, "fix" a correct method call, or change the trait. An
> error that moves when you reorder two unrelated lines looks like a compiler bug and is hard to
> search for. Against: compiler cost and a second walk. That cost is paid once by us, not by every user.
>
> ### G4-P2: the §3b rule for every late fill (error at the dependent use)
>
> State once in §3.4: error at the use that depended on the unknown type, `note:` at the use that
> fixed it. Cheap and uniform. To be tolerable for users it must add a second note at the consumer
> that wanted the other type ("`s` is used as Str here", at `takes(s)`), so the reader sees both ends.
> Acceptable fallback, but the primary span still sits on code that has no bug. Not preferred.
>
> Cross-language: TypeScript and Kotlin report at the consuming call; Rust's "type annotations
> needed" reports at the binding and then at the consumer. None of them move the error by line order.

- **PLT:** (excerpt, section `G4: where a late fill that conflicts with an earlier use is reported`)

>
> Principle: **a diagnostic must not move when the user adds the annotation that inference found.** The type of a program with under-determined bindings is the type of the same program with the solution written in. HM is order-independent in what it accepts. Its error site should be order-independent too, where that costs us nothing in soundness.
>
> ### G4-P1 (preferred): report as if the solved type were written at the binding
>
> - After the late fill fixes `l : List[S]`, the body is checked again with that type (the "second walk", only for bodies that had a deferred use). The error is the one that `let mut l: List[S] = []` would give: E0300 at `takes(s)` (Int is not Str).
> - A `note:` names the use that fixed the type (`l.push(S { a: 1 })`). Then the reader sees both the conflict and why the type is `S`.
> - The result is the same whatever the order of the lines: with `push` first, it is in-place today and the site is the same.
> - The §3b template rule (error at the second use, note at the first) is the special case where the two uses are the conflict itself. It agrees with P1, because an annotation with the first use's context also errors at the second use. State the rule once in §3.4 and have §3b cite it.
>
> ```blink
> trait Dbg { fn debug(self) -> Int }
> type S { a: Int }
> impl Dbg for S { fn debug(self) -> Int { self.a } }
> fn takes(x: Str) {}
>
> fn main() {
>     let mut l = []
>     if l.len() > 0 {
>         let s = l.get(0).unwrap().debug()
>         takes(s)                    // error[E0300]: expected Str, found Int
>                                     // note: `l` is List[S] from `l.push(...)` at line 11
>     }
>     l.push(S { a: 1 })
> }
> ```
>
> Tradeoffs. The site is where the fix goes (`takes(s)` or `.debug()` -> something that gives `Str`). `.debug()` is not wrong, and an error there tells an AI to change a correct call. The cost is a second check of a body with a deferred use. That cost is bounded and affects only those bodies. A cheaper equal result: keep the result variable of each deferred use, with its consuming span, and report at that span. Either is an implementation choice.
>
> ### G4-P2: the late site, with notes (generalize the §3b rule as it is written)
>
> E0300 at `.debug()`, a note at `takes(s)` (the consumer), and a note at `push` (the fill). It is cheaper, but the site depends on line order (`push` first gives `takes(s)`), and adding the inferred annotation moves the error. That fails the principle above. Accept only if P1 is shown to be too costly to build.
>
> Cross-language: OCaml and GHC report at the unification failure in traversal order, and their error site is known to move with order. That is the classic complaint about HM errors. Elm and modern GHC work to attribute the conflict to the consuming site, which is the P1 direction.

- **DevOps:** (excerpt, section `G4: where a late fill's downstream conflict is reported`)

>
> **Today (probed):** source order 1 (use, then `l.push`): "error[TypeError]: method `.debug`
> returns Int, but its use expects Str" at `.debug()` (7:30), note "the use at 8:7 first gave it
> the type Str" (that is `takes(s)`, not the push). Lines reversed (push first): "argument 1 of
> `takes` expects Str, got Int" at `takes(s)` (9:13). Same program, two messages, two sites. No
> note names `l.push`, so the reader cannot see why `.debug` means `S.debug`.
>
> ### G4-P1 (preferred): two cases, one site rule each
>
> 1. Conflict over the late-filled type itself (`l.push(1)` then `l.push("a")`; two template
>    contexts): error at the second use in source order, note at the use that set it. This is the
>    §3b rule; state it once in §3.4 for every late fill.
> 2. A conflict downstream of the fill (G4): reported exactly as and where the in-place check
>    would report it, so the code and the message do not depend on line order. Add one note at
>    the fill site: "`l` got type `List[S]` from `l.push(...)` at line 9".
>
> ```blink
> fn main() {
>     let mut l = []
>     if l.len() > 0 {
>         let s = l.get(0).unwrap().debug()
>         takes(s)                     // error[E0300]: argument 1 of `takes` expects Str, got Int
>     }                                //   note: `l` is `List[S]` from `l.push` at line 7
>     l.push(S { a: 1 })
> }
> ```
>
> Tradeoffs: reordering lines never moves or rewords an error, which matters for the LSP
> (diagnostics stay put while a user edits above them) and for an AI fix loop (the same defect
> gives the same text). The message names the real mismatch, not a method that is correct.
> Cost: a second walk of the deferred region after the fill; that is compiler work, invisible
> to users.
>
> ### G4-P2: the §3b rule for every late fill
>
> Error at the use that depended on the unknown type, note at the fill. Cheaper. Tradeoff: the
> site and text flip with line order, and the primary span sits on `.debug()`, which invites
> a wrong fix (change `debug`'s return type). At minimum the note must name the fill site,
> which today's note does not.
>
> Cross-language: Rust refuses a method call on a not-yet-known type (E0282 "type annotations
> needed" at `.debug()`), so it never meets this case; Blink's late dispatch goes further than
> Rust, so it owes the user the same stable site an eager checker gives.

- **AI/ML:** (excerpt, section `G4 — where a late fill that conflicts with an earlier use is reported`)

>
> **Facts today (gen1):** with the push after the use: `error[TypeError]: method .debug returns
> Int, but its use expects Str` at `.debug()`, `note: the use at 8:2 first gave it the type Str`
> (the note names `takes(s)`, not `l.push`). With the push first: `argument 1 of takes expects
> Str, got Int` at `takes(s)`. So the primary site moves with line order.
>
> ### G4-P1 (PREFERRED): one rule for every late fill, stated once in §3.4, with both ends named
>
> The error goes at the use that depended on the unknown type (`.debug()`), as §3b already does
> for templates. It carries two notes: the use that fixed the type (`l.push(...)`: `l` is
> `List[S]`, so `.debug` is `S.debug`) and the use that set the conflicting expectation
> (`takes(s)`). No second walk.
>
> ```blink
> fn main() {
>     let mut l = []
>     if l.len() > 0 {
>         let s = l.get(0).unwrap().debug()   // error[E0300]: `.debug` returns Int, its use expects Str
>         takes(s)                            //   note: `takes(s)` expects Str
>     }
>     l.push(S { a: 1 })                      //   note: this push makes `l` a `List[S]`
> }
> ```
>
> Tradeoffs: a model fixes a type conflict by editing one of the two ends; it needs both
> locations and the reason the method resolved as it did. With all three spans in the diagnostic,
> the site of the primary label matters less than its contents. One rule (late fill: error at the
> dependent use) is easy to state and learn. Cost: one more note line.
>
> ### G4-P2: re-walk so the site matches the in-place report (`takes(s)`)
>
> Order-independent primary site, which is good for consistent training data. Cost: a second body
> walk after every fill, and the in-place message ("argument 1 expects Str, got Int") does not
> say why `.debug` gave Int unless it also adds the fill note. Acceptable if the panel weighs site
> stability above compile cost; this seat ranks it second.

- **Minimalism:** (excerpt, section `G4 — where a late fill that conflicts with an earlier use is reported`)

>
> ### G4-P1 (PREFERRED): state the §3b template rule once in §3.4 for every late fill
>
> - When a use needs a type that is not yet fixed, and a later use fixes it to a type that conflicts, there is one E0300, at the use that depended on the unknown type (here `.debug()`), with a `note:` at the use that fixed it (`l.push(...)`) and a `note:` at the demand it fails (`takes(s)` wants `Str`).
> - When the fixing use comes first in the text, nothing is late and the normal in-place report applies (`takes(s)`: `Int` is not `Str`). The site depends on the order of the lines. That is fine: each report names all the sites that matter, and the rule is one sentence.
> - §3b.5's template sentence becomes a pointer to §3.4. One rule in place of a special case.
>
> ```blink
> trait Dbg { fn debug(self) -> Int }
> type S { a: Int }
> impl Dbg for S { fn debug(self) -> Int { self.a } }
> fn takes(x: Str) {}
>
> fn main() {
>     let mut l = []
>     if l.len() > 0 {
>         let s = l.get(0).unwrap().debug()   // error[TypeError] (E0300): `S.debug` gives `Int`, `takes` needs `Str`
>         takes(s)                            // note: needs `Str` here
>     }
>     l.push(S { a: 1 })                      // note: the element type of `l` is fixed as `S` here
> }
> ```
>
> Tradeoffs: no second walk of the body, no extra compiler machinery. A reader (human or AI) gets every relevant site in one diagnostic, so either fix — annotate `l`, change `takes`, or convert — is visible. Matching the in-place site would cost a re-check pass to make the report look as if the type had been known, which buys a cosmetic gain.
>
> ### G4-P2: do nothing — the site is not specified
>
> Spec says one E0300 and a note naming the fixing use; which use carries the primary span is quality of implementation (as §10.5 already leaves "which binding continues after the error" open). Least text, but tests and training data want one stable site. Second choice.

#### Phase B — Debate highlights

- **Systems:** (excerpt, section `G4: G4-IN (changed from G4-R)`)

> I move to IN. My objection to it was cost (a second walk). plt shows an equal result without one:
> keep each deferred use's result variable with the span of the use that consumes it, and report a
> later conflict at that span. That is one pass plus a side table, linear in the body. Given that,
> the arguments for IN win: the site does not move with line order (stable LSP and AI fix loop), and
> it does not point at a correct call (`.debug()`). R puts the primary span on code with no bug.
> H gives the same output as IN for this case; its case 1 (two uses that fix the filled type
> differently: second use, as §3b) is what IN gives too, since the annotation from the first use
> errors at the second. So IN and H agree; I prefer IN as the one-sentence rule with §3b citing it.
> Writer note: the spec should not require a second walk; it states the site, the implementation
> picks the method.
>
> ready to vote

- **Web/Scripting:** (excerpt, section `G4: G4-IN (no change); G4-H is acceptable (same output here)`)

> Against G4-R:
> - The primary span is what editors jump to, what LSP quick-fixes act on, and what an AI agent
>   edits first. Under R it sits on `.debug()`, a call with no bug in it. The notes help, but they are
>   secondary.
> - Under R the site and text still change when two unrelated lines swap order (push before `if`
>   gives the in-place error at `takes(s)`, push after gives the error at `.debug()`). The same bug
>   gives two errors. That looks like a compiler bug and splits search results.
> - The cost of R's alternative is a second walk in the compiler. We pay it once, and every user is
>   spared the cost.
>
> G4-H gives the IN result for downstream mismatches, and puts a conflict over the filled type
> itself at the second use, which is the in-place site anyway. I rank IN > H >> R.
>
> ready to vote

- **PLT:** (excerpt, section `G4: G4-IN, and I accept G4-H as the same rule stated in full`)

>
> - G4-H is G4-IN with the fill-against-fill case made explicit. When two uses fix the type differently, no single solution can be written at the binding, so the §3b second-use rule is what G4-IN means there too. I vote IN or H. They give the same result.
> - **Against G4-R:** the error site depends on line order (the probes confirm it moves today when the lines swap). Adding the annotation that inference found also moves the error, from `.debug()` to `takes(s)`. A diagnostic should be a function of the program's meaning, not of the order the checker walked it. R also points at `.debug()`, a correct call. A model that fixes "the error line" then edits correct code. The cost argument for R (no second walk) does not hold up: recording each deferred use's consuming span gives the same site with no second walk.
>
> **Ready to vote.**

- **DevOps:** (excerpt, section `G4: G4-IN (I merge G4-H into it)`)

>
> G4-H gives the same output as G4-IN for this example. The difference is the case where two
> uses fix the filled type itself to different types (`l.push(1)` then `l.push("a")`). In that
> case IN also reports at the use that conflicts with the solved type, and that is the §3b
> behavior. I drop H as a separate option. Writer note: state the self-conflict case in one
> sentence.
>
> Against G4-R:
> 1. The error site and text change with line order (probed). An LSP diagnostic that jumps to
>    another line and changes its words when an unrelated line moves above it looks like a
>    checker bug. An AI fix loop that sees a different message for the same defect makes a
>    different edit.
> 2. The primary span is on `.debug()`, which is correct code. The quick fixes the LSP offers at
>    a span ("change the return type", "convert to Str") then target the wrong expression. R's
>    two notes help a human who reads all the notes, but a tool acts on the primary span.
> 3. A second walk of the body is compile time spent once per late fill, not a cost to users.
>    R saves the implementation work and moves the cost onto every reader of the error.
>
> ready to vote

- **AI/ML:** (excerpt, section `G4: switch from R to IN (H is the same option for this case)`)

> Phase A preferred R. plt and web convinced me:
> - **R puts the primary span on correct code (`.debug()`).** A fix loop edits the primary span first. A model will change `debug`'s return type or the trait, which is the wrong fix. The defect is at `takes(s)`.
> - **Stability.** Under R, the same defect gets a different site and text when two lines change order. Worse, adding the annotation that inference found (`let mut l: List[S] = []`) moves the error. Then the "add a type annotation" repair, the most common one a model tries, changes the diagnostic without fixing it. A model then thinks it made progress or made things worse. Under IN, the diagnostic stays the same.
> - Cost: compiler work (a second check, or plt's cheaper form: keep each deferred use's consuming span). The compiler pays this cost once. Every user pays the cost of a wrong site.
> - G4-H gives the same output as IN for this example. Its rule for a conflict on the filled type itself (error at the second use) is what IN gives anyway, as plt shows. I count IN and H as one option. If they stay separate on the ballot, I rank IN, then H, then R.
>
> Keep the fill note ("`l` is `List[S]` from `l.push(...)` at line N") in every option.
>
> **Ready to vote.**

- **Minimalism:** (excerpt, section `G4: changed from G4-R to G4-IN`)

> PLT's principle is the minimal one: a late-filled type is checked as if the user had written it at the binding. That makes the late fill the same case as an annotation, so the spec needs no new concept and no rule about which use "depended" on the unknown type. Under R the site moves when the lines swap and when the user adds the annotation that inference found. The §3b template sentence is the case where the two uses are the conflict, so it agrees with IN and can become a pointer to §3.4. A second walk, or keeping the consuming span of each deferred use, is compiler work. It is not language surface, and I gave it too much weight in Phase A.
> Against G4-H (devops): it gives two cases (a conflict over the filled type vs. downstream of it) where IN gives one, and for this example its output is the same as IN.
> Against G4-R (my Phase A pick): the site depends on line order. It also puts the error on `.debug()`, a correct call, so a reader can "fix" the wrong line.
>
> ready to vote

#### Phase C — Final vote

- **G4-Q1: a late fill is checked as if its type were written at the binding (6-0, IN; the other option, R, reported at the use that depended on the unknown type)**

- **Systems:**

> ## G4-Q1
> **Vote:** IN
> **Reasoning:** The error stays at the same site whatever the line order, and it does not point at the correct `.debug()` call. With plt's side table (each deferred use keeps its consuming span), the cost is one linear pass, so there is no compile-time reason to take R. The fill-against-fill case reduces to the §3b second-use rule, so one sentence in §3.4 covers both.
> **Concern:** If the implementation takes the full re-walk route instead of the side table, check time on large bodies with many late fills could grow. The writer must leave the method free and give only the site.

- **Web/Scripting:**

> ## G4-Q1
> **Vote:** IN
> **Reasoning:** The error goes on the line with the bug (`takes(s)`). That line is where editors jump, where quick-fixes act and what an AI edits first, and it does not move when unrelated lines swap or when the user adds the annotation that inference found. Keeping each deferred use's consuming span costs the compiler once and spares every user.
> **Concern:** If the note at the fill is left out, the in-place message ("expects Str, got Int") does not say why `s` is Int. The note naming `l.push(...)` must be required, not optional.

- **PLT:**

> ## G4-Q1
> **Vote:** IN
> **Reasoning:** A diagnostic should depend on what the program means, not on the order the checker walks it. Under IN, adding the annotation that inference found does not move the error, and swapping lines does not move it either. A conflict between two fills reduces to the §3b second-use rule, so §3.4 states the rule once and §3b cites it.
> **Concern:** The implementation must link the conflict to the consuming use's span: a side table per deferred use, or a second check. A shortcut that reports at the deferred call brings R back in silence.

- **DevOps:**

> ## G4-Q1
> **Vote:** IN
> **Reasoning:** The primary span is on the defect (`takes(s)`), not on a correct call, so LSP quick fixes and AI fix loops act on the right expression. The site and text do not change when lines are reordered or when the user adds the annotation that inference found.
> **Concern:** The fill note must name the fill site (`l.push` at line N), which today's note does not, or the reader cannot see why `l` is `List[S]`.

- **AI/ML:**

> ## G4-Q1
> **Vote:** IN
> **Reasoning:** The primary span is what a fix loop edits first. IN puts it on the real defect (`takes(s)`), not on a correct `.debug()`. The error does not move when lines change order. It also does not move when the user adds the annotation that inference found, which is the most common repair a model tries.
> **Concern:** If the fill note is dropped, the reader cannot see why `.debug()` returned `Int`. The note naming `l.push` must be part of the rule, not optional.

- **Minimalism:**

> ## G4-Q1
> **Vote:** IN
> **Reasoning:** "Check as if the solved type were written at the binding" reduces a late fill to the annotated case, so the spec needs no new concept and the site does not move with line order. The §3b template sentence becomes a pointer to it. The second walk, or a side table of consuming spans, is compiler work, not language surface.
> **Concern:** The spec must not prescribe a second walk. It should state only the site, or the implementation will grow a second pass that a side table could avoid.

### Final Spec

```blink
fn early() {
    let mut l = []
    if l.len() > 0 {
        let s = l.get(0).unwrap().debug()
        takes(s)             // error[TypeError] (E0300): expects Str, got Int
                             // note: `l` is List[S] because of `l.push(S { a: 1 })` at line N
    }
    l.push(S { a: 1 })
}
```

- When a later use fixes the type of `[]`, `None` or `Map.new()`, every earlier use is checked as if that type had been written at the binding. An error goes where the written type would put it.
- The `note:` at the use that fixed the type is required.
- The site and the text do not change with line order, and the site does not move when the user writes the inferred annotation.
- The error is at the use that consumes the value (`takes(s)`), never at the deferred call (`.debug()`).
- When two later uses fix the type itself to different types, the error is at the second use, with a note at the first, as the template rule says. §3.4 states the rule once and §3b.5 cites it.
- The text states the site and the note. It does not say how the compiler finds the site.
- Spec text: §3.4 *Under-Determined Types*, *A late fill is checked as if its type were written at the binding*; §3b.5 *The Context Parameter `C`*.
