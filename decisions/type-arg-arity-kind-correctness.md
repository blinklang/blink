[< All Decisions](../DECISIONS.md)

# Kind-Correctness of Type Expressions (`TypeArgArity`, E0303) — Design Rationale

Resolves br `m6ptme`: *"Bare `Channel` annotation carries no element: `relay(src: Channel, dst: Channel)` type-checks across element types."* The ticket offered three candidates — (1) reject bare `Channel`, require `Channel[T]`; (2) treat bare `Channel` as an implicit generic `Channel[T]`; (3) keep it as an untyped escape hatch (status quo). The panel adopted Option 1 and generalized it: the defect is not `Channel`-specific but the general absence of kind-checking on type expressions.

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated in independent-proposal → debate → vote rounds.

> **Transcript-fidelity note.** The Phase A proposals of `sys`, `web`, `aiml`, `devops`, and `min`, and `web`'s Phase B ballot, are quoted verbatim from the session transcript. `plt`'s Phase A proposal, the Phase B ballots of `sys`/`aiml`/`devops`/`min`/`plt`, and the six Phase C ballots were delivered to the moderator via `SendMessage` during background subagent turns and were **not persisted verbatim** to any transcript on disk. Where only the moderator's contemporaneous relay survives, it is quoted **as a moderator relay** and marked as such — the panelists' own words are not reconstructed or invented.

#### Phase A — Independent proposals

All six converged on Option 1 (reject). Five independently widened the scope beyond `Channel`.

- **Systems** *(verbatim excerpt)*: "**Option 1, and it is not a new rule — it is the already-ratified arity rule.** `Channel` has arity 1. DECISIONS #347 already binds every type-argument list to **all-or-none, exact arity**, and binds Blink to **no implicit generics**." On why this is more than an inference nicety: "`src/codegen_methods.bl:4925-5010` has **two different wire formats for the same queue**, selected on whether the element is known … That is a wrong-shape read of a live object, not merely a missing diagnostic." On Option 2: "An undeclared binder has no source name to key on, so the mangler must order anonymous binders positionally by occurrence — adding or reordering a parameter then silently renames C symbols and invites exactly the ODR collapse #347 was written to block."

- **Web/Scripting** *(verbatim excerpt)*: "**The hole is NOT Channel-specific.** `build/blink check` accepts all of these today, methods and all, with zero diagnostics … Channel is just the instance the ticket happened to trip over." On Option 2: "**Option 2 is that conjuring** — it re-legalizes implicit generics through a side door, and only for builtin type constructors, so `Channel` would infer a binder that `T` cannot. Two rules for one concept is exactly the thing that generates Stack Overflow questions." On the tax: "Python's post-695 syntax is **character-for-character** Blink's. The tax is 3 characters, paid once per generic function." On the message: "This must **not** surface as `E0301 CannotInferType` at `let val = src.recv()`. That's the symptom three lines from the cause." **VOTE: Option 1.**

- **PLT** *(moderator relay — verbatim ballot not persisted)*: moderator's Phase-B relay records plt as the author of the decisive strike against Option 2 and of the drafting guard adopted into the spec. From the moderator's Phase E summary (index 304, verbatim): "plt added the critical drafting guard (state the rule over *type expressions*, explicitly excluding trait references in bounds/impl-headers, which E0910 governs)." From the tally (index 321, verbatim): "**plt's decisive strike: as literally specified (fresh binder per occurrence) it yields `relay[T,U]` and *still* type-checks the mismatched relay — it renames the bug.**"

- **DevOps** *(verbatim excerpt)*: "The hole is **not Channel-specific** … I also found who actually uses the bare spelling on purpose — `lib/std` FFI externs … Ten declarations … Bare `Channel` in a type position appears in exactly one place outside a comment: `tests/test_channel_param.bl:1,5`. Total migration surface: ~12 lines." On severity: "No call site can supply the element of a *parameter's own* annotation — an annotation is what inference reads **from**, not a place inference can reach. So: declaration site, error severity. This also explains why E0301 is the wrong code to reuse." On Option 2's diagnostic surface: "It has two sub-variants and both produce an error whose repair does not exist." **Vote: Option 1, generalized.** *(devops proposed the number `E0302`; the moderator surfaced the codebase fact that `E0302` is already `NOT_ITERABLE`, and the panel converged on `E0303` in Phase B.)*

- **AI/ML** *(verbatim excerpt)*: "**no clause of this rule may mention `Channel`.** It is the existing §3.4 arity rule applied to a type constructor that happens to be built in." On why Option 2 fails the bug: "Option 2 as written produces: *a fresh binder per occurrence*. `fn relay(src: Channel, dst: Channel)` becomes `relay[T, U](src: Channel[T], dst: Channel[U])` — the two-different-element-types relay **still type-checks with no diagnostic**. Option 2 does not fix the reported defect; it only renames it." **Vote: Option 1, with the refinement that the diagnostic is an arity error (not `E0301`) reported at the annotation, carries the binder-declaring repair in its `help:` text, and is worded in §3.4 over all type constructors with no mention of `Channel`.**

- **Minimalism** *(verbatim excerpt)*: "**Position: Option 1. Reject bare `Channel` in a type position. Do not replace it with anything.** This is the only one of the three candidates that makes the language *smaller*." On the lone witness: "that test passes *because of* the defect … The single existing use of bare `Channel` is a latent-miscompile carrier. Deleting the form deletes the carrier." On Option 3: "'Untyped escape hatch' is `any` wearing a different name. The panel voted 6-0 that under-determined types are a hard error." **Vote: Option 1. Reject bare `Channel`; no replacement form; reuse the existing type-arg arity diagnostic; keep the reject rule as a consequence of §3.4.** *(min's Phase-A preference to reuse E0910 was withdrawn in Phase B — see below.)*

#### Phase B — Debate highlights

Phase B ran because Phase A left two live sub-questions: **Q2** (what diagnostic, and where) and **Q3** (scope of the rule). Q1 (reject) was unanimous going in.

- **Web/Scripting** *(verbatim excerpt from its Phase B ballot)* established the fact that settled Q3's shape: "**over-application is silently accepted too** … `build/blink check` passes all three of these with ZERO diagnostics … `fn g(l: List[Int, Str])` … `ok:`. So the hole is **bidirectional**, not just under-application." web then fixed the code number against the codebase: "**`TypeArgArity`** (suggest **E0303**; E0302 is `NOT_ITERABLE`, E0310 is `TEMPLATE_MISMATCH`, so E0303 is free and adjacent to E0301 where it belongs)," and against reusing E0910: "Two-topic explain pages are how a diagnostic system stops being trusted." web formally **withdrew its Q3-B** (Channel-only) fallback: "a Channel-only fix would leave `List[Int, Str]` compiling clean. Shipping a kind-correctness rule that lets you over-apply `List` is not a partial fix, it's an advertisement that the rule is arbitrary."

- **AI/ML** *(moderator relay, index 247, verbatim)*: "**Q2-A** (new code E0303, type family, help names both edits) … **Q3-A**. Correction noted: `Map[Str]` is *under*-application (I mislabeled it 'over' in the broadcast); over-application is `List[Int, Str]`. Both are errors under one code."

- **Minimalism** *(moderator relay, index 259, verbatim)*: "**withdraws Q2-B → Q2-A**, with the amendment that there be exactly **one** new code (E0303 `TypeArgArity`) covering both directions and all constructors, at the annotation, E0910 left untouched (E0910 still wins on an impl header). **Q3-A whole**, rejects Q3-B, and adds a two-step bootstrap sequencing note (make stdlib arity-correct → then turn on E0303)." *(min withdrew Q2-B after the moderator surfaced that E0910's explain text is entirely impl/trait-specific.)*

- **DevOps** *(moderator relay, index 270, verbatim)*: "**Q2-A** (E0303 `TypeArgArity`, at annotation, pre-inference; binder-minting help only in the n=0 case), **Q3-A** both directions. Confirmed labeling: `Map[Str]` = under-application, `List[Int,Str]` = over-application."

- **Systems** withdrew **Q2-C** (reuse E0301) → Q2-A after re-reading E0301's own explain text; **(dissent resolved)** the moderator's Phase E summary records "sys conceded Q2-C→Q2-A."

- **PLT (drafting guard)** *(moderator relay, index 304, verbatim)*: "state the rule over *type expressions*, explicitly excluding trait references in bounds/impl-headers, which E0910 governs" — otherwise `fn sort[T: Ord](xs: List[T])` collides with E0910.

New load-bearing findings surfaced in Phase B *(moderator relay, index 304/321, verbatim)*: "the hole leaks to raw `cc` on user generics (`type Pair[A,B]; fn takes(p: Pair)` → gcc error on safe Blink, no I0001 backstop), over-application silently *discards* a written type argument, and it spans struct fields and `let` annotations, not just parameters."

#### Phase C — Final vote

*(Recorded as the moderator's tally, index 321, verbatim. Individual Phase C ballots were delivered via `SendMessage` in background turns and not persisted verbatim; the per-panelist reasoning above is from Phase A/B, which are the ballots that survive.)*

| # | Question | Result | Tally |
|---|----------|--------|-------|
| Q1 | Bare / under-applied `Channel` annotation | **Reject** (Option 1) | **6-0** |
| Q2 | What diagnostic, and where | **Q2-A**: new dedicated code `error[TypeArgArity]` **E0303**, reported *at the annotation* (pre-inference), one code for both directions | **6-0** (sys withdrew Q2-C; min withdrew Q2-B) |
| Q3 | Scope of the rule | **Q3-A**: general kind-correctness rule — every type expression in a type position must have kind `*`; under- **and** over-application are errors; all builtins + user generics | **6-0** (web withdrew its Q3-B fallback) |

No Phase D — unanimous on every question, no ties.

**Why Options 2 and 3 died** *(moderator tally, verbatim):*
- **Option 2 (implicit `Channel[T]`)** — "as literally specified (fresh binder per occurrence) it yields `relay[T,U]` and *still* type-checks the mismatched relay — it renames the bug. Any fix requires implicit universal quantification at a parameter, which contradicts the 6-0 'no implicit generics' vote."
- **Option 3 (status quo)** — "a surface `unknown` under another name; a live violation of the 6-0 §3.4 under-determined-types vote … and the source of a real two-wire-format channel miscompile."

#### AI-First Review

5/5 pass. Learnability (generalization of a rule already learned for `List`/`Map`/`Set`/`Option`, no new special case), Consistency (subtraction — removes the lone outlier), Generability (`fn relay[T](src: Channel[T], dst: Channel[T])` is the canonical HM shape), Debuggability (dedicated E0303 at the annotation, pre-inference, case-specific machine-applicable help), Token Efficiency (~8 tokens once per genuinely-generic declaration; eliminates downstream annotation churn from untyped `recv()`).

### Final Spec

`Channel` stops being special. A generic type constructor named in a **type position** must be applied to exactly its declared number of arguments.

```blink
fn relay(src: Channel, dst: Channel) { }        // error[TypeArgArity]: `Channel` takes 1 type argument, 0 were given
fn relay[T](src: Channel[T], dst: Channel[T]) { // OK -- element-agnostic by parametricity
    let val = src.recv()
    dst.send(val)
}

fn f(m: Map[Str]) { }          // error[TypeArgArity]: `Map` takes 2 type arguments, 1 was given (under-application)
fn g(xs: List[Int, Str]) { }   // error[TypeArgArity]: `List` takes 1 type argument, 2 were given (over-application)
fn sort[T: Ord](xs: List[T]) -> List[T] { xs }  // OK -- `Ord` is a bound, not a type expression
```

Locked design points:

- A type expression in a type position (parameter, return, field, binding annotation, nested type argument, struct-literal head, impl receiver) must denote a complete type — a constructor of arity *n* applied to exactly *n* arguments.
- Under-application (of which the bare name, *k* = 0, is the extreme) and over-application are **one failure, one code**: `error[TypeArgArity]` (E0303).
- Uniform across builtins (`Channel`/`List`/`Map`/`Set`/`Option`/`Result`/`Iterator`/`Handle`) and user generics; arity is read from the declaration, so user types need no per-type work.
- Decided at **name resolution, before inference** — distinct from `error[CannotInferType]` (E0301); the two never co-fire on one type expression.
- Case-specific normative repair: bare + type param in scope → apply it; bare + none in scope → declare a binder and apply it; under-applied → supply the missing argument; over-applied → remove the extra. Binder-declaring repair offered only when bare *and* no param in scope can fill the slot.
- **Trait references are outside the rule.** A trait name in a bound or impl header does not occupy a type position; its arity is governed by `error[TraitArgArity]` (E0910), the impl-header specialization of the same principle — one concept, two codes.
- Migration (separate impl ticket): two-step bootstrap — add `[T]` binders to the ~10-12 bare `List`/`Map`/`Set` FFI externs in `lib/std` (a no-op under today's lenient checker) and fix `tests/test_channel_param.bl`, then enable E0303. Step two unlocks deleting the erased channel codegen lanes (`elem_ct == -1`, `get_var_channel_inner`).

Governs: §3.4 *Kind-Correctness of Type Expressions*; §3.1 *Diagnostic Discipline*; §3.6 impl-binder rule; catalog E0303. Related: [under-determined-types.md](under-determined-types.md), [explicit-type-application.md](explicit-type-application.md).
