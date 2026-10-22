[< All Decisions](../DECISIONS.md)

# Impl-Chosen Effect Rows for Cleanup Traits — Design Rationale

The spec gave `Closeable.close` and `Scoped.exit` an empty effect row, and it also gave their impls rows
(`FileHandle.close ! FS`, `Timer.exit ! Time.Read, IO.Log`). The trait-impl rule of §3.6 (E0904) forbids an impl
row that is wider than the trait row, so the examples of the spec broke the rule of the spec. A function with no `!`
could also call `close` through a type parameter and do IO. This ruling gives the cleanup methods a row that each
impl chooses, and it states what a call is charged.

## Summary

| Q | Question | Result | Vote |
|---|---|---|---|
| Uncontested | How do `close`, `enter` and `exit` get a row, and what does a call pay? | `Closeable.close`, `Scoped.enter` and `Scoped.exit` declare `! _`. On a trait method with no `! _` callback or handler parameter, `_` means each impl declares its own row, and E0904 does not bound it. A concrete call is charged that impl's row. A call through a type parameter is charged `_`, and the enclosing function needs `_` in its row (E0500, help "add `! _`"). At a generic call, the type arguments' impl rows join `_`, from signatures only. A `_` in a function or impl-method row needs a source. Any trait may write `! _` on a callback-free method; the empty row stays the default | All six, no vote |
| Q1 | A fixed part beside `_` on a callback-free trait method (`! IO.Log, _`) | F1: legal. The fixed part limits no impl. A call through `T` is charged the fixed part plus `_`; a concrete call is charged that impl's row. No error, no lint. The spec says plainly that only a row with no `_` bounds impls | F1 3 (sys, min, devops), F3 2 (plt, aiml), F2 1 (web) |
| Q2 | The code for a `_` with no source | A new code, `UnsourcedEffectWildcard` (E0551), for the impl-method case and for `fn g() ! _ {}` | 6-0 |

Q1 has no majority for one label. "Legal" (F1 or F2) leads "reject" (F3) 4-2, and F1 is the plurality, so F1 ships
with the dissent recorded below. The owner reviews this split.

The panel took four rounds: independent proposals (Phase A), a dedupe and one round of debate (Phase A.5 and B), a
silent vote (Phase C), and a focused re-vote on Q1 (Phase D).

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated in
independent-proposal, debate, vote rounds. The ticket, verbatim, without its cross-references:

> Title: Spec: Closeable.close and Scoped.exit have empty rows, but spec impls give them rows (E0904 contradiction)
>
> Desc: Found by the sys and plt seats on the open-socket rows panel. Closeable.close (03_types.md:4614, 05_memory_compile_errors.md:215) and Scoped.exit (04_effects.md:2349) declare no effect row. §3.6 says an impl row must be a subset of the trait row, else E0904 TraitContractEffectMismatch. The spec's own examples break this: FileHandle.close ! FS (03_types.md ~:4626) and Timer's Scoped.exit ! Time.Read, IO.Log (04_effects.md ~:2437). Any socket type that implements Closeable (std.net close rows) meets the same conflict. Question for the panel: how does a trait method whose impls have side effects get its row (effect-polymorphic row on the trait method, a fixed wide row, or an exemption)?

The text below is excerpted from each panelist's own text. `[...]` marks a cut inside a quote. `F<n>` in a quote
names a numbered fact of the fact brief that the moderator gave to the panel.

#### Phase A — Independent proposals

All six seats chose the same first option: the trait method declares `! _`, and each impl declares its own row.
The first rule of each proposal:

- **Systems** (`A/sys.md`), first choice `sys-1`:

> sys-1 (FIRST CHOICE): the trait method row is `! _`; each impl declares its own concrete row; generic code forwards it with `! _`
>
> **Impl row.** When a trait method's row is `_` and the method has no `! _` callback or handler parameter, `_` stands for "the row of the impl". Each impl writes a concrete row (or none). E0904 does not apply to that `_`.

- **Web/Scripting** (`A/web.md`), first choice `web-1`:

> web-1 (FIRST CHOICE): the trait method row is `! _`; each impl picks its row; callers pay the impl's row
>
> On a trait method, `! _` means "each impl declares its own row." Any impl row satisfies `R_i ⊆ _`. E0904 does not change: it still fires for every trait method that has a fixed row (empty `Display.fmt`, `Eq.eq`, `Shout.shout`, and so on). There is no exemption list and no special trait.

- **PLT** (`A/plt.md`), first choice `plt-1`:

> plt-1 (FIRST CHOICE): `! _` on a trait method is a per-impl row
>
> A trait method whose row contains `_` declares an **impl-chosen row**. For one impl, the row of that method is the row the impl writes. For a type parameter `T: Trait`, the row is opaque and a caller forwards it with its own `_`.

- **DevOps/Tooling** (`A/devops.md`), first choice `devops-1`:

> devops-1 (FIRST CHOICE): `! _` on the trait method means "each impl names its row"
>
> In a trait method row, `_` stands for the union of the rows of the method's `! _` parameters (as today, F18) and a row that each impl names. An impl of a `_` method writes a concrete row (or none). E0904 still checks the fixed part of `R_t`. It does not limit what an impl adds in place of `_`.

- **AI/ML** (`A/aiml.md`), first choice `aiml-1`:

> aiml-1 (FIRST CHOICE): `! _` on a trait method means "each impl declares its own row", and that row flows through `_` like a callback row
>
> A trait method may declare `! _` with no callback parameter. Then each impl of that method declares its own concrete row (or no `!`). E0904 does not compare an impl row with `_`: `_` is not a fixed upper bound, so there is nothing to widen. E0904 stays as it is for every trait method with a concrete row or no `!` (Display, Eq, Hash, Ord, Shout).

- **Minimalism** (`A/min.md`), first choice `min-1`:

> min-1 (FIRST CHOICE): `close` and `exit` take `! _`; `_` on a trait method means "the row the impl chose"
>
> When a trait method's row has `_`, each impl declares its own row for that method. E0904 is unchanged: every row is a subset of `_`, so every impl row passes.

Fallback (from the dedupe of Phase A.5): a ban on calls of a `_`-row trait method through a type parameter in v1,
ranked below the first choice by each author who named it.

> Ban calls of a `_`-row trait method through a type parameter in v1 (min-2, web-2, plt-4). Each author ranks it below its first choice.

All six seats opposed a fixed wide row on the trait, an exemption list for E0904, and "close needs no effects".

#### Phase A.5 and Phase B — Dedupe and debate, round 1

The moderator listed the points that every seat raised (no vote unless a seat objected) and five variations:
V1 (`Scoped.enter`), V2 (what a generic call site is charged), V3 (`_` in an impl row), V4 (who may write `! _` on a
callback-free method), V5 (a fixed part beside `_`). The moderator gave one fact:

> sections/07_trust_modules_metadata.md:60, verbatim: "**There is no `FFI` effect.** A foreign call is not an effect of its own. The row of an `@ffi` decl names the Blink effects the foreign code has: `Net`, `IO`, `Crypto` and so on (§4.3). ... `! FFI` is not a valid row: `FFI` is not a declared effect, so it is rejected with `UnknownEffect` (E0538, §4.3)." Several Phase A files say the std impls (`DbConnection.close`, `Stmt.close`) should write `! FFI`; lib/std/db_sqlite.bl:36 declares `pub fn sqlite_close(handle: Sqlite3) -> Int ! FFI {}` today.

All six seats sent "ready to vote" after this round. The positions that changed:

- **V1, `Scoped.enter`.** Minimalism (`B1/min.md`) conceded:

> **V1 `Scoped.enter`: I concede. `! _` on `enter` too.** My YAGNI case was weak. `Connection.enter` (F8) builds a handler from an FFI handle, so a real `enter` with effects already exists in the spec. Adding `_` later would break generic callers. One mark on both methods is one rule (web's point), and an empty `enter` stays legal with no row.

- **V2, the charge at a generic call.** Minimalism (`B1/min.md`) took the signature rule:

> **V2 What a generic call site pays: I switch to aiml rule 4 / devops rule 5 (signature only).** That is the smaller rule. It keeps §4.15.2 rule 5 ("the row is never reduced") with no exception. The charge reads from the signature, so it does not change when the body changes, and neither tooling nor a reader has to look at the body to know the cost. My rule 4 and plt (b) charge only "the methods it calls", so they read from the body. That is a second resolution mode. The over-charge (a fn that holds `T: Scoped` and never enters it still pays for `enter`) is small and honest. I withdraw my wording.

  PLT (`B1/plt.md`) withdrew its body rule:

> I withdraw my plt (b) ("methods the callee calls") and take the signature rule. My reason is type-theoretic. A caller's typing must depend only on the callee's type, not on its body. Otherwise `_` is not a type, and editing a body changes what its callers must declare. That breaks modular checking, the same way it would for type inference. It also matches §4.15.2 rule 5 ("the row is never reduced"), so callbacks and type arguments follow one rule. The precise text: for each type parameter `T` of the callee and each `_`-row method `m` of `T`'s bounds, supertraits included (so `T: Closeable` brings `Scoped.enter/exit` through the bridge), add `ε(A, m)` for the type argument `A`. If the callee's row has no `_`, the type arguments add nothing. Such a callee cannot call those methods anyway.

- **V3, `_` in an impl row.** DevOps (`B1/devops.md`) revised its rule 2 to allow the forwarding `Guard[T]`:

> min's `Guard[T]` is a real case. My rule 2 was too narrow. New rule: an impl, like a fn, may write `_` only when the row has a source, which is a `! _` parameter or a type parameter whose bound has a `_` method. `impl[T: Closeable] Closeable for Guard[T] { fn close(self) ! _ }` is legal. `impl Closeable for Res { fn close(self) ! _ }` is rejected: "`_` here has nothing to resolve from; name the effects `close` performs". Use the same rule and message for `fn g() ! _ {}`, which parses today (F22). It is not an effect mismatch, so it should not be E0904. It should get its own code.

  Systems (`B1/sys.md`) took the same side:

> Wrappers are a core systems pattern: `BufWriter[File]`, `Guard[T]`, `Pooled[Conn]`. Under a ban, `Guard[T]` cannot be Closeable at all, or it must take a fixed wide row, which all six seats rejected. Rule: an impl may write `_` in its row only if the impl has a type parameter whose bound has a `_` method. Then `ε(Guard[A], close) = ε(A, close)` per instance, resolved by mono like any generic fn. With no such parameter, `_` in an impl row is E0904 (devops is right about that case).

- **V5, a fixed part beside `_`.** Web (`B1/web.md`) was the first to ask for a rejection:

> sys and min agree that `! IO.Log, _` adds no constraint to impls. A form that is legal but means nothing is a trap: people will think it is a floor or a ceiling, and Stack Overflow will need to explain that it is neither. I prefer an error: "a fixed effect next to `_` adds nothing here; write `! _`". A warning is my second choice. Methods with callback parameters keep today's meaning (fixed part plus forwarded callbacks).

#### Phase C — Silent vote

Process note: web said in Phase D that it had voted in Phase C without reading `B1/*.md`. The moderator asked web
to read them before Phase D.

**Q1 — a fixed part beside `_` (F1: legal, no lint; F2: legal, with a lint; F3: rejected).** Result: F1 3 (sys, plt,
min), F2 1 (devops), F3 2 (web, aiml).

- **Systems** (`C/sys.md`):

> **Vote:** F1
>
> **Reasoning:** `! IO.Log, _` follows from the existing union rule and costs nothing after mono. Each instance's charge is fixed ∪ the impl row, known at codegen. A ban (F3) adds a special case to the parser or checker to forbid a form that is sound and has a clear meaning. A lint (F2) adds tooling surface for a form no std trait writes. If misuse shows up in real code, a lint can come later with no spec change.

- **Web/Scripting** (`C/web.md`):

> **Vote:** F3
>
> **Reasoning:** Every seat agrees that `! IO.Log, _` limits no impl. A form that compiles and looks meaningful, but means nothing, is the worst kind for a learner. Readers will take it as a floor ("every impl does IO.Log") or a ceiling, and both readings are wrong. An error with "write `! _`" teaches the rule the first time someone tries it. A lint (F2) only reaches the people who run `blink lint`.

- **PLT** (`C/plt.md`):

> **Vote:** F1
>
> **Reasoning:** `! IO.Log, _` has a well-defined meaning under the rules we agreed on. It places no bound on impls, and every generic call is charged `IO.Log ∪ ε(A, m)`. That is the same reading `! IO.Log, _` already has on a function (§4.15.2, "Wildcard with explicit effects"), so one row syntax keeps one meaning everywhere. A rejection (F3) would add a special case to the row grammar for no gain in soundness. A lint (F2) would call a row that has a meaning "useless", which is a style judgment, not a typing fact.

- **DevOps/Tooling** (`C/devops.md`):

> **Vote:** F2
>
> **Reasoning:** `! IO.Log, _` has one grammar on a fn, on a callback trait method and on a callback-free trait method. Keeping it legal means the parser, `blink fmt` and the LSP need no special case. F3 needs a rule that depends on whether the method has a callback, and that rule needs its own error. But the text looks like a bound and is not one, so a reader who trusts it is wrong. A lint warning tells them so, and the language rule stays uniform.

- **AI/ML** (`C/aiml.md`):

> **Vote:** F3
>
> **Reasoning:** A form that parses but puts no limit on an impl is a trap for a model. It will read `! IO.Log, _` as "impls may do only IO.Log plus a little more", or as "every impl must log", and both readings are wrong. F1 and F2 keep the form legal but empty of meaning, and a model learns from examples, so legal forms spread. When the form is rejected, there is one way to write the trait method (`! _`), and a model has one less choice to make.

- **Minimalism** (`C/min.md`):

> **Vote:** F1
>
> **Reasoning:** `! IO.Log, _` is already a legal row on fns (§4.15.2). Rejecting it on one kind of method adds a special case and a new diagnostic. The form still means something: a generic caller pays the fixed part plus `_`. A lint (F2) is one more rule that guards a form nobody writes; std writes bare `! _`. The smallest option is to change nothing.

**Q2 — the code for a `_` with no source (C1: E0904; C2: a code of its own).** Result: C2, 6-0.

- **Systems** (`C/sys.md`):

> **Vote:** C2
>
> **Reasoning:** In B1 I said "stays E0904". I change that vote: `fn g() ! _ {}` has no trait in it, so the name TraitContractEffectMismatch would be wrong for that case. One code for "`_` with no source", used for fns and impl methods alike, keeps E0904 at one meaning, an impl that widens a fixed trait row. That one-to-one map is what a reader of a diagnostic and the error catalog needs.

- **Web/Scripting** (`C/web.md`):

> **Vote:** C2
>
> **Reasoning:** E0904 is named TraitContractEffectMismatch. `fn g() ! _ {}` has no trait and no mismatch, so that code name points users at the wrong concept and the wrong catalog entry. A code of its own, with "name the effects this function performs", is what a JS/Python dev can search for and understand. One code for both the impl case and the fn case keeps it to a single lesson.

- **PLT** (`C/plt.md`):

> **Vote:** C2
>
> **Reasoning:** E0904 is TraitContractEffectMismatch: an impl row is not a subset of the trait row. A `_` with no source is a different fault. It is an effect variable that nothing can instantiate, and it occurs just as well in a plain `fn g() ! _ {}` where no trait exists. Reusing E0904 would make one code mean two unrelated judgments, and a code that does not name the rule it enforces gives no help with the fix.

- **DevOps/Tooling** (`C/devops.md`):

> **Vote:** C2
>
> **Reasoning:** Users and tools search by error code. E0904 means "the impl widens the trait's row" (ERROR_CATALOG.md:207), and its help says to remove the effect or add it to the trait. Neither fix applies to a `_` with no source. The same error also fires on a plain `fn g() ! _ {}`, where there is no trait, so an E0904 code would point the user to §3.6 for a fn that has no trait contract. One code with one message ("`_` here has nothing to resolve from; name the effects") covers both sites.

- **AI/ML** (`C/aiml.md`):

> **Vote:** C2
>
> **Reasoning:** E0904 means "an impl row widens its trait row". `fn g() ! _ {}` has no trait, and an impl that writes `! _` with no source does not widen anything. When a model or a repair loop sees E0904, it applies one fix: remove effects or add them to the trait. If one code carries two problems, the model applies the wrong fix. A code of its own, with help "name the effects", maps to one edit.

- **Minimalism** (`C/min.md`):

> **Vote:** C2
>
> **Reasoning:** E0904 means "an impl widens its trait method's row". `fn g() ! _ {}` has no trait and no impl, so filing it under E0904 makes one code carry two meanings. That costs more over time than one catalog row. A single new code for "`_` has nothing to resolve from" covers fns and impl methods with one rule. That code also matches the V3 wording, which states one rule for both.

#### Phase D — Focused re-debate and re-vote on Q1

Q2 was decided. Only Q1 was open. Each seat answered the strongest argument for an option it did not vote for.
Result: F1 3 (sys, min, devops), F3 2 (plt, aiml), F2 1 (web). Three seats moved: plt from F1 to F3, devops from F2
to F1, and web from F3 to F2.

Majority, F1:

- **Systems** (`D/sys.md`):

> The strongest case for F3 (web, aiml) is that the form looks like a contract and is not one, so learners and models will copy it as one. I take the risk seriously, but the premise is wrong: the form is not empty of meaning. At a generic call it sets a floor on the charge. `fn f[T: C](t: T) ! _` that calls `t.m()` pays `IO.Log` for every `T`, even one whose impl row is empty. That is a real, checkable, conservative fact, and it is the same fact `! IO.Log, _` already states on a fn (§4.15.2). F3 cannot forbid it everywhere, because the fn form is decided and the callback trait-method form is in use. So F3 bans it on one kind of method only, decided by whether the method has a `! _` parameter. That rule is invisible in the text: two signatures that look the same, one legal and one an error. A rule you can only see by counting parameters is a worse trap for a model than one row syntax with one meaning. The fix for the misreading is the one sentence that plt, min and aiml all ask for: "only an empty or fixed row (no `_`) bounds impls."
>
> **Vote:** F1
>
> **Reasoning:** One row syntax, one meaning, on fns and on both kinds of trait method. The charge is fixed ∪ the impl row per instance, known at codegen, with no cost and no special case in the checker. The misreading is a documentation problem, so the fix is one spec sentence, not a grammar exception. If real code shows misuse, a lint can come later with no spec change.

- **Minimalism** (`D/min.md`):

> The strongest case against my vote comes from web and aiml: a form that compiles and looks like a contract will spread through examples, and a model or a learner will copy it. That cost is real. But the form is not empty of meaning. Every generic caller pays `IO.Log`, which is the same reading the row has on a fn (§4.15.2). The misreading web and aiml describe ("impls may do only IO.Log") comes from not knowing what `_` means beside fixed effects. A ban on one kind of method does not teach that. Every fn with `! IO.Log, _` still shows the form. F3 also makes the row grammar depend on whether the method has a callback parameter. That means one more rule, one more error, and one more fact for the model to learn. Forms spread from examples, and no std trait or spec example will write this one, so the trait the learner copies writes bare `! _`. I keep F1 and add the one sentence every seat asked for.
>
> **Vote:** F1
>
> **Reasoning:** F1 keeps one row syntax with one meaning in every place it appears. F3 and F2 each add surface (an error, or a lint) to guard a form that std never writes. One sentence of spec text closes the misreading at lower cost: "Only an empty or fixed row (no `_`) bounds impls; effects beside `_` add to the charge at a generic call and limit no impl."

- **DevOps/Tooling** (`D/devops.md`):

> The strongest case for F3 is web's: a form that compiles and looks like a contract, but limits nothing, misleads, and a lint reaches only people who run `blink lint`. I agree that the form misleads. But F3 replaces one surprise with another. `! IO.Log, _` stays legal on a fn and on `ListOps.map`, so an error on `close` makes the user ask "why is this row legal there and not here?". The error must then explain the callback-free case, which is a harder message to write and to read than the rule it enforces. The case against my own F2 also holds: plt is right that the fixed part has a meaning, because it adds to the charge at a generic call, so a lint that calls it useless is a style judgment on a form that no std trait writes. The tool that reaches every reader is hover, not lint. The LSP can show "effects beside `_` do not limit impls" on the trait method, and that needs no spec rule. I move to F1, on the condition that the spec sentence all three F1 seats asked for is in the decision text.
>
> **Vote:** F1
>
> **Reasoning:** One row grammar with one meaning everywhere keeps the parser, fmt, and the E0904 and E0500 messages free of a special case. The fixed part has a defined meaning, a charge at generic calls, so there is nothing for a checker to reject. LSP hover and the spec sentence cover the misreading at less cost than a lint rule or a new error.

Dissent, F3 (reject):

- **PLT** (`D/plt.md`):

> The strongest case against my Phase C vote is web's and aiml's: the fixed part looks like a contract and is not one. I answered that it does carry meaning, namely the charge at a generic call. When I check that meaning against the typing rules, it fails. At a concrete call `a.close()` the charge is the impl row `R_A` (agreed point: "a call on a concrete type is charged that impl's row"). At a generic call `t.close()` with `T := A` the charge becomes `IO.Log ∪ R_A`. So the same call, after substitution, has two different rows. That breaks the substitution property: instantiating a type parameter must not change the effect of a call. The repair would be to charge `IO.Log` at concrete sites too. That makes `IO.Log` a phantom effect that no body needs and that every caller must hold, which is exactly the false capability grant that DECISIONS.md:372 rejects ("an effect row grants capabilities"). Neither reading is sound and precise. On a function, or on a trait method with a `! _` callback, the fixed part does bound the body, so those forms keep their meaning. Only here does it bound nothing, and here it should be rejected. I change my vote.
>
> **Vote:** F3
>
> **Reasoning:** On a callback-free trait method, a fixed part beside `_` either makes the generic and concrete rows of the same call differ, or charges an effect that no code needs. Both break a property the effect system relies on. Rejecting it leaves one form, `! _`, with one meaning (the impl's row, the same at every call site). The rule is narrow and has a clear typing reason: a fixed part is rejected where `_` is chosen by the impl, because there it bounds nothing.

- **AI/ML** (`D/aiml.md`):

> The strongest case for F1 is plt's: "one row syntax keeps one meaning everywhere", since `! IO.Log, _` is already legal on a function. I do not accept that the meaning is the same. On a function, `! IO.Log, _` bounds the body: the body may do `IO.Log` plus what the callbacks do, and nothing else. On a callback trait method such as `ListOps.map`, it bounds every impl in the same way. Only on a callback-free trait method does the same text stop bounding anything. F1 keeps the syntax uniform but makes the meaning a special case, and the meaning is what a model or a reader acts on. Every seat's Phase C concern, F1 voters included, is the same failure: a reader takes the fixed part as a bound. When five of six concerns name one misreading, the form is the problem, and a sentence in the spec does not reach a model that learns from code. F3 is a check, not a grammar change. The parser, `blink fmt` and the LSP keep one grammar, and the new check sits next to the C2 "no source" check that we just adopted 6-0. If F3 loses, I prefer F2 to F1, because F2 at least puts the warning where the code is.
>
> **Vote:** F3
>
> **Reasoning:** The form reads as a bound and is not one, and every seat agrees on that. If the compiler rejects it, there is one way to write a callback-free trait method (`! _`), and a model makes one fewer choice. The error is easy to fix by machine ("remove the effects beside `_`"), and it uses the same check as the C2 source rule.

Dissent, F2 (legal, with a warning):

- **Web/Scripting** (`D/web.md`):

> The strongest case against my F3 is uniformity (plt, min, devops). `! IO.Log, _` already means "fixed part plus forwarded" on a fn (§4.15.2). If F3 rejects it only on a trait method that has no callback, the rule depends on context: one row is legal in one place and an error in another. That makes its own Stack Overflow question ("why can I write this on a fn but not on my trait?"). I argued against that same kind of rule when I opposed the exemption list. There is a second point. The form does have a meaning: a generic caller is charged the fixed part. With an open default body that logs, the fixed part even describes real effects. So F3 bans a form that is sound and sometimes useful, only to stop a misreading. My real concern was the misreading, not the form. A warning at the trait method answers the misreading where it happens, and it keeps one grammar. I move to F2.
>
> **Vote:** F2
>
> **Reasoning:** One row syntax with one meaning everywhere is easier to learn than a ban that applies only to callback-free trait methods. The misreading ("IO.Log bounds the impls") is the real hazard. A warning that says "the effects beside `_` do not limit impls of this method", plus one sentence in §3.6, removes it at the line where it happens. F1 leaves the misreading with no answer at all.

#### AI-first review

1. Learnability — PASS. One rule: `! _` on a callback-free trait method means each impl names its row. A function with no `!` still performs no effects, except through a type parameter, where the missing `_` is an error with a fix.
2. Consistency — PASS. `_` keeps one reading, "a row that the call site fixes", in callbacks, handlers and impls. The reading of `_` in a trait method depends on whether the method has a callback; §4.15.2 says so in one sentence, and the Q1 dissent rests on this point.
3. Generability — PASS. A model writes `! _` on `close` and a concrete row on the impl, which is the shape of the examples it has seen.
4. Debuggability — PASS. E0500 says "add `! _`" and E0551 says "name the effects"; each code has one fix, and E0904 keeps one meaning.
5. Token efficiency — PASS. `! _` is three tokens, and no syntax is new.

0 of 5 fail. No flags.

### Final Spec

```blink
trait Closeable {
    fn close(self) ! _
}

trait Scoped {
    type Context

    fn enter(self) -> Self.Context ! _
    fn exit(self, ok: Bool) ! _
}

impl Closeable for FileHandle {
    fn close(self) ! FS {
        fs.close_fd(self.fd)
    }
}

type Guard[T] {
    inner: T
}

impl[T: Closeable] Closeable for Guard[T] {
    fn close(self) ! _ {            // OK: the bound `T: Closeable` is a source for `_`
        self.inner.close()
    }
}

fn shut[T: Closeable](t: T) {
    t.close()                      // ERROR E0500: `T.close` has an impl-chosen row; help: add `! _`
}

fn shut_ok[T: Closeable](t: T) ! _ {
    t.close()
}

fn main() ! FS {
    let f = FileHandle { fd: 3, path: "a.txt" }
    shut_ok(f)                     // _ = FS, the row of FileHandle.close
}

impl Closeable for Res {
    fn close(self) ! _ {            // ERROR E0551: no source for `_`; help: name the effects
        fs.close_fd(self.fd)
    }
}

fn g() ! _ {}                       // ERROR E0551
```

- `Closeable.close`, `Scoped.enter` and `Scoped.exit` declare `! _`.
- On a trait method with no `! _` callback or handler parameter, `_` means each impl declares its own row. E0904 does not bound that row. E0904 is unchanged for every trait method with a fixed or empty row. A method whose `_` comes from a callback parameter (`ListOps`, `StrOps`, `MapOps`) keeps its meaning (§4.15.2).
- A call on a concrete type, including the `with` desugar and the `Closeable` to `Scoped` bridge, is charged that impl's row. The synthesized `exit` has the row of `close`.
- A call through a type parameter, including `with t` for `t: T`, is charged `_`. The enclosing function needs `_` in its row, else E0500 at the call, with the help "add `! _`" (§4.15.3).
- At a call of a generic function whose row has `_`, for each type parameter of the callee and each `_`-row method of its bounds (supertraits included), the impl row of the type argument joins `_`. The body is not read. If the row of the callee has no `_`, type arguments add nothing (§4.15.3).
- A `_` in the row of an impl method or a function needs a source: a `! _` callback or handler parameter, or a type parameter whose bound has a `_`-row method. A `_` in a trait-method declaration is the impl-chosen contract and has no such need. A `_` with no source is `UnsourcedEffectWildcard` (E0551), with the help "name the effects"; it fires instead of E0904 on the same method (§4.15.2).
- Any trait may write `! _` on a callback-free method. The empty row stays the default contract; spec examples show `! _` only on `Closeable` and `Scoped`.
- A fixed part beside an impl-chosen `_` is legal and limits no impl. Only a row with no `_` bounds the impls of a trait method (§3.6, §4.15.2).
- `FFI` is not an effect (§9.1, E0538). An impl of `close` or `exit` names real Blink effects.

Governing text: §3.6 *Effect-row subtype for trait impls*, §4.5 *Effect rows on trait impls*, §4.7.2, §4.15.2, §4.15.3, §5.5, `ERROR_CATALOG.md` (E0551, E0904).

### Concerns

Phase C, Q1:

- **Systems** (`C/sys.md`):

> **Concern:** If F1 wins, an author can read `! IO.Log, _` as an upper bound on impls and think that a generic caller is protected by it, when the fixed part only adds to the charge.

- **Web/Scripting** (`C/web.md`):

> **Concern:** If F1 wins, std or user traits will write `! IO.Log, _` as documentation, and that will start a run of "why does my impl without IO.Log compile?" questions with no diagnostic to answer them.

- **PLT** (`C/plt.md`):

> **Concern:** A trait author may read the fixed part as an upper bound on impls ("every close only logs"), and the spec text must say plainly that only an empty or fixed row (no `_`) bounds impls.

- **DevOps/Tooling** (`C/devops.md`):

> **Concern:** If F1 wins, nothing tells the trait author that `IO.Log` does not bound the impls. The first user who expects it to will file a bug saying E0904 does not fire.

- **AI/ML** (`C/aiml.md`):

> **Concern:** If F1 wins, the spec must state plainly that the fixed part does not limit the impl and only adds to the charge at a generic call. Without that sentence, models will copy `! IO.Log, _` as if it were a contract.

- **Minimalism** (`C/min.md`):

> **Concern:** a reader may take `IO.Log` beside `_` as an upper bound on impls. One sentence of spec text should say it is not.

Phase C, Q2:

- **Systems** (`C/sys.md`):

> **Concern:** If C2 wins, the new code must be emitted before E0904 at an impl method that has both faults, or the user gets two diagnostics for one edit.

- **Web/Scripting** (`C/web.md`):

> **Concern:** If C2 wins, the new code's message must say *why* `_` has nothing to resolve from (no callback or bound type parameter); otherwise users will read it as "`_` is never allowed here" and drop the generic `Guard[T]` pattern.

- **PLT** (`C/plt.md`):

> **Concern:** `fn g() ! _ {}` and `trait Tw { fn f(self) ! _ }` are accepted today (F22, probe p12), so the new error breaks existing code that must be found and fixed in the same change, or the gate goes red.

- **DevOps/Tooling** (`C/devops.md`):

> **Concern:** If C1 wins, E0904 gets two unrelated meanings. `blink explain E0904` and the LSP quick-fix for it must then branch on which one fired, and the quick-fix "add the effect to the trait" will be offered where it is wrong.

- **AI/ML** (`C/aiml.md`):

> **Concern:** If C2 wins and the new code is a generic "invalid row" code, it loses the one-code-one-fix property. The message must name the missing source (a `! _` parameter or a type parameter whose bound has a `_` method).

- **Minimalism** (`C/min.md`):

> **Concern:** the new code must fire at every place `_` can appear (fn rows, impl rows, `Handler[E ! _]` types). If one place is missed, a sourceless `_` passes silently as the empty row.

Phase D, Q1:

- **Systems** (`D/sys.md`):

> **Concern:** If F1 wins without the spec sentence "the fixed part beside `_` adds to the charge at a generic call and does not bound impls", the misreading web and aiml predict will happen.

- **Web/Scripting** (`D/web.md`):

> **Concern:** If the warning lives only in `blink lint` and not in `blink check` and the LSP, most users will never see it. I ask that it surface wherever other warnings do.

- **PLT** (`D/plt.md`):

> **Concern:** The F3 rule depends on whether the method has a `! _` callback, so adding a callback parameter to a trait method changes which rows are legal. The spec text and the diagnostic must state that dependence plainly ("beside an impl-chosen `_`, `IO.Log` limits nothing; write `! _`").

- **DevOps/Tooling** (`D/devops.md`):

> **Concern:** If the spec sentence ("only an empty or fixed row with no `_` bounds impls") is left out of §3.6, nothing in the toolchain or the spec tells a trait author that `IO.Log` does not bound the impls.

- **AI/ML** (`D/aiml.md`):

> **Concern:** If F1 wins, std or user traits will write `! IO.Log, _` as documentation, and models trained on those traits will copy it as a contract that no tool checks.

- **Minimalism** (`D/min.md`):

> **Concern:** if the spec sentence is left out of the §3.6 rule text, the misreading web and aiml expect will happen, and nothing will correct it.

Web's concern in Phase D: if a warning is added later, it must show in `blink check` and the LSP, and not only in `blink lint`.

### Follow-ups

1. Implementation: the E0904 check is not wired in the compiler today, so a widening impl passes. This ruling needs the E0904 check, impl-chosen rows (an impl row is not compared with the `_` of the trait), the charge of a call through a type parameter, `_` resolution from the type arguments of a call, and E0551 (emitted before E0904 on the same method, at every place a `_` can appear in a row). Each point needs a test. `fn g() ! _ {}` and `trait Tw { fn f(self) ! _ }` parse today, so the corpus is searched for code that E0551 now rejects.
2. Std chore: the std impls of `Closeable` and `Scoped`, and the foreign declarations that they call, name real effects and not `! FFI` (`lib/std/db_sqlite.bl:36` and `:124`).
3. Codegen of an effectful `close` or `exit`: the guard runner must pass the effect vector to the call.
