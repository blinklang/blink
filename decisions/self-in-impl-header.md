[< All Decisions](../DECISIONS.md)

# `Self` in an Impl Header — Design Rationale

The spec says `Self` is valid in trait declarations and in impl blocks. It does not say whether an impl header is part of
the impl block. The header holds the trait, the target type, the type arguments of both, the binders with their bounds,
and the `where` clause. The compiler gave a different answer at each position:

```blink
trait Tr { fn m(self) -> Int }
type X { n: Int }

impl Tr for Self { fn m(self) -> Int { 1 } }   // internal error (open type after check)
impl Self for X { fn m(self) -> Int { 1 } }    // "trait `Self` is not defined", under a code that belongs to another row
impl Tr[Self] for X { fn m(self) -> Int { 1 } } // header passes; a method that writes `u: X` then fails: expected `Self`
impl Tr for X where Self: Eq { fn m(self) -> Int { 1 } } // passes
```

## Summary

| Q | Question | Result | Vote |
|---|---|---|---|
| Q1 | Which header positions refuse `Self` | `Hdr-all`: an impl's `Self` binds at the `{` of the body. Every `Self` in the header is refused. A trait declaration's own header keeps `Self` | 6-0 |
| Q2 | Which code | `E0569` `SelfOutsideTraitOrImpl`, one error at each `Self` token, no follow-on error. The catalog adds "an impl header". A header site gets a header-specific help | 6-0 |
| Q3 | `impl Self for X` | `E0569` at the `Self` token and nothing else | 6-0 |

### Compiler behavior before the decision

The seats ran probes with the gen1 compiler.

- `impl Tr for Self` gives I0024 OpenTypeAfterCheck, an internal error (DevOps).
- `impl Self for X` gives TraitContract "trait `Self` is not defined" (DevOps). The constant for that error is E0904, which the catalog gives to TraitContractEffectMismatch (PLT).
- `impl Tr[Self] for X` and `impl Tr for X where Self: Eq` pass the header (PLT). With `impl Tr[Self] for X`, a method that writes `u: X` gets TraitContractParamMismatch "expected `Self`" (DevOps).
- `impl From[Self] for X` reads `Self` as the trait's `Self`, then gives TraitContractParamMismatch and OverlappingImpls (AI/ML).

### Reading gaps

- The ballot named a new code `SelfInImplTarget`. Phase A also named `SelfInImplHeader`. No seat voted for a new code in Phase C.
- `impl Int for X` (a real type in trait position) gives "trait `Int` is not defined" under the same wrong code. This decision does not cover it. A separate ticket tracks it.

## Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated in independent-proposal →
debate → vote rounds. There was no Phase D: all three questions passed 6-0 in Phase C.

### Phase A — Independent proposals

- **Systems** (E0569, whole header outside):
  > `Self` is the type that the header *defines*. A token in the header cannot refer to the thing it is defining. So for E0569 the impl block starts at its `{`. Every `Self` token in the header is E0569 with the existing label: the target type (`for Self`), any type argument of it (`for Box[Self]`), the trait position (`impl Self for X`), the trait's type arguments (`impl From[Self] for X`), and the impl's binder bounds / where clause. One error per token, no second error from its uses (so the I0024 ICE goes away: the type is never left open).

  > Systems tradeoff: this is decided in name resolution with a flag "inside impl body yes/no" — one bit, no type inference needed, no cycle (`Self` resolving to a target that is still being resolved).

- **Web/Scripting** (E0569, a header help line; `Self` valid in the `where` clause):
  > The header is where the impl *says which type* it is for; `Self` cannot name that type before the header names it. So for E0569 the header (the trait position, the for-type, and every type argument in either) counts as outside the impl block.

  > `Self` stays valid where the header has already named the type: the impl's `where` clause and the impl body.

- **PLT** (new code `SelfInImplTarget`; `Self` valid in the trait arguments and the `where` clause):
  > `Self` in an impl is an alias for the impl's target type (the type after `for`). An alias is in scope where its definition is complete. So `Self` is in scope in: the trait's type arguments (`impl Tr[Self] for X`), the `where` clause, and the body. It is **not** in scope inside the target type itself, at any depth, because there `Self` would be defined in terms of itself.

  > A label that contradicts the source is the worse cost, for a human and for a model that learns from the diagnostics.

- **DevOps** (E0569, whole header outside):
  > `Self` binds at the `{` of the impl body. Every `Self` token in the header (the trait name, the trait's type arguments, the self type and its type arguments, a header `where` clause) is E0569 SelfOutsideTraitOrImpl. There is one error per token, and the label is unchanged. The help changes with position:

- **AI/ML** (E0569, whole header outside):
  > The impl block is the body between `{ }`. The header (`impl`, binders, trait, trait type arguments, target type, any bound or `where` clause in the header) defines what `Self` means, so it cannot use `Self`. Every `Self` token in the header is E0569 SelfOutsideTraitOrImpl, one error per token, no follow-up error.

- **Minimalism** (E0569, whole header outside):
  > `Self` binds only once the header is complete. Any `Self` token in the header is E0569 SelfOutsideTraitOrImpl. One rule covers every header position: the implemented type, the trait, a type argument of either, an impl binder's bound, and an impl `where` clause. Inside the body (method signatures, bodies) `Self` is the implemented type, as now.

### Phase B — Debate highlights

The Phase B digest split Q1 into three options: `Hdr-all` (Systems, Minimalism, DevOps, AI/ML), `Hdr-all-but-where` (Web) and
`Hdr-target` (PLT).

- **PLT, on Q1 (changes to `Hdr-all`):**
  > Every header `Self` that Hdr-target would accept can be rewritten as the target type written out, which is in plain view on the same line (`From[X]`, `where X: Eq`, `Tr[Box[T]] for Box[T]`). So Hdr-all refuses no meaning and loses no expressiveness.

  > Hdr-all has one binding point: the impl's `Self` binds at the body `{`, the same way a `let` binds after its initializer.

  > One point for the writer. A **trait** declaration is different and must stay as it is. There, `Self` is the bound variable that the declaration itself introduces, so it is in scope in the trait's own header (supertraits, `where Self: ...`). Hdr-all applies to impl headers only.

- **Web, on Q1 (drops the `where` exception):**
  > "`Self` starts at the `{`" is a rule a dev learns in five seconds. "Except in a `where` clause" is a footnote that someone forgets.

- **AI/ML, on Q1:**
  > **"It works today" is not true.** plt's `impl Tr[Self] for X` checks clean only while the impl has no method that uses the type. devops and I both probed a method in it.

- **Minimalism, on Q1:**
  > **Hdr-all loses nothing.** A header `Self` always equals a type written in that same header, so the user can write that type: `Tr[X]`, `From[X]`, `where X: Eq`, or `Tr[Box[T]]` for a generic impl.

- **PLT, on Q2 (moves from the new code):**
  > Under Hdr-all, the "impl block" is the body, so a header `Self` *is* outside it, and the code name and label are literally true. The objection goes away with Q1. I ask only for the writer note that all seats already made: a header-specific help that names what to write (`impl Tr for Point`, `From[X]`).

- **PLT, on Q3 (moves to `Self-rule`):**
  > Under Hdr-all, `Self` is not in scope in the trait slot, so the token names nothing, and E0569 is the right and complete answer.

- **Web, on Q3:**
  > Under Hdr-all, `impl Self for X` gives E0569 at the `Self` token, and nothing else, which is the "no follow-on errors" rule. That answers this ticket.

The Phase B digest also listed writer notes: the label or help at a header site must not say "only valid inside ... impl
blocks" with no header-specific line, and the help must say which name to write (`impl Tr for Point`, `From[X]`).

### Phase C — Silent ballot

| Question | Sys | Web | PLT | DevOps | AI/ML | Min | Result |
|----------|-----|-----|-----|--------|-------|-----|--------|
| Q1. Header positions | Hdr-all | Hdr-all | Hdr-all | Hdr-all | Hdr-all | Hdr-all | Hdr-all, 6-0 |
| Q2. Code | E0569 | E0569 | E0569 | E0569 | E0569 | E0569 | E0569, 6-0 |
| Q3. `impl Self for X` | Self-rule | Self-rule | Self-rule | Self-rule | Self-rule | Self-rule | Self-rule, 6-0 |

##### Q1. Header positions — `Hdr-all`, 6-0

- **Systems:**
  > **Reasoning:** One rule: `Self` binds at the body `{`. The fix is always to write the target's name, which is on the same line, so no program loses anything. The header forms that check today already break in the body (aiml, devops probes), so Hdr-target is new behavior, not behavior we keep.
  >
  > **Concern:** Users coming from Rust will expect `impl PartialEq[Self] for Foo` and `where Self: ...` to work, so the label must name the type to write, or the refusal reads as arbitrary.
- **Web:**
  > **Reasoning:** The rule "`Self` starts at the `{`" takes five seconds to learn, and it has no exceptions to remember. A probe already showed the compiler misreads `impl From[Self] for X`, so people will misread it too. Writing `From[X]` costs one word.
  >
  > **Concern:** Rust users who write `where Self: Eq` will hit an error that Rust does not give them. The help must show the bound on the type parameter instead.
- **PLT:**
  > **Reasoning:** One binding point: the impl's `Self` binds at the body `{`. Every refused header `Self` can be rewritten as the target type, which is written out on the same line, so no meaning is lost. The probes showed that a header `Self` in the trait arguments is misread as the trait's own `Self`. Hdr-all-but-where adds a second rule for no expressive gain.
  >
  > **Concern:** The writer could let the rule leak into trait declarations, where `Self` is the declaration's own bound variable and must stay in scope in supertraits and where clauses.
- **DevOps:**
  > Reasoning: One scope edge ("Self binds at the body `{`") gives one message, one machine fix (write the target's name), and no forward resolution in the LSP. The shapes it refuses gain nothing when accepted: `impl From[Self] for X` overlaps the reflexive `From[T] for T` anyway (03c :282).
  >
  > Concern: Rust users write `where Self: Eq` by habit. The help at a where-clause `Self` must show the rewritten clause, not only the generic label.
- **AI/ML:**
  > Reasoning: The rule is one sentence: "an impl's `Self` is valid only inside its `{ }`". It has no position list and no scope that runs against the text order. Today's compiler reads `Self` in a trait argument two ways, which shows a model would too. Each refused case can be written with the type's name.
  >
  > Concern: Users who come from Rust will write `impl PartialEq[Self] for Foo` or `where Self: ...`. The help must give the exact rewrite (`PartialEq[Foo]`), or it costs them a turn.
- **Minimalism:**
  > **Reasoning:** "Self binds at `{`" is one point that anyone can see. A header `Self` always equals a type written in that same header, so refusing it removes no power. The positions Hdr-target would accept fail today with TraitContractParamMismatch and OverlappingImpls, so nobody relies on them, and keeping them means new compiler work.
  >
  > **Concern:** A user who writes `where Self: Eq` out of habit from trait declarations gets an error. The help must give the rewrite in place (`where X: Eq`, or a bound on the binder).

##### Q2. Code — `E0569`, 6-0

- **Systems:**
  > **Reasoning:** Same token, same phase (name resolution), same fix, so a second code adds catalog surface and nothing else. One error per token with no follow-on also removes the I0024 ICE path.
  >
  > **Concern:** The existing label "only valid inside trait declarations and impl blocks" reads as false at a header site. Without a header-specific label line, users will think the compiler is wrong.
- **Web:**
  > **Reasoning:** "`Self` names no type here" is one mistake, and one code makes it easy to search for. A header-specific help line gives the user the same text that a new code would.
  >
  > **Concern:** If the writer does not add the header help line, the label "only valid inside ... impl blocks" reads as wrong to a user whose cursor is in an impl.
- **PLT:**
  > **Reasoning:** Under Hdr-all the impl block is the body, so a header `Self` is outside it, and the code name and label are true. A new code would only rename the same scope error.
  >
  > **Concern:** A help that does not name the type to write (`impl Tr for Point`, `From[X]`) would leave the user guessing why `Self` "inside the impl" is refused.
- **DevOps:**
  > Reasoning: Same fault, same fix, so one code. A second code splits `blink explain` and `--json` matchers for no gain. The position precision goes in a header-specific help line.
  >
  > Concern: The fixed label "only valid inside trait declarations and impl blocks" can read as wrong for a token that sits on the impl line. The writer must add the header help line so users do not argue with the compiler.
- **AI/ML:**
  > Reasoning: One mistake with one fix (write the type's name) gets one code. A second code doubles what a model must learn from `--json` output, for no new repair.
  >
  > Concern: The catalogued label "only valid inside trait declarations and impl blocks" reads as false at a site that looks like it is in an impl. The header-specific help line is required, not optional.
- **Minimalism:**
  > **Reasoning:** The refusal is the same as E0569's: `Self` names no type at this spot. Use a header-specific label, not a new code. A new code would be a row for a mistake nobody makes on purpose.
  >
  > **Concern:** If the writer keeps the generic label "only valid inside ... impl blocks" at a header site, it will read as false. The header label is required, not optional.

##### Q3. `impl Self for X` — `Self-rule`, 6-0

- **Systems:**
  > **Reasoning:** Under Hdr-all, it is a header `Self` like any other, so special-casing it adds a rule. The separate catalog bug (`impl Int for X` reported under E0904) still needs its own ticket and code.
  >
  > **Concern:** If the not-a-trait ticket stalls, `impl Int for X` keeps its wrong code. The tally should file that ticket at once.
- **Web:**
  > **Reasoning:** The `Self` token is the first fault and the cheapest to explain: one error, and no errors that follow from it. The fact that `impl Int for X` reports under the wrong code (E0904) is a real bug, but it needs its own ticket and does not change this answer.
  >
  > **Concern:** If the not-a-trait follow-up ticket is never filed, `impl Int for X` keeps reporting under TraitContractEffectMismatch's code.
- **PLT:**
  > **Reasoning:** Under Hdr-all, `Self` is not in scope in the trait slot, so the token names nothing, and E0569 alone is complete. A second error would break E0569's "no follow-on" rule.
  >
  > **Concern:** `impl Int for X` still prints "trait `Int` is not defined" under constant TRAIT_CONTRACT_904 = "E0904", which the catalog gives to TraitContractEffectMismatch. That needs its own ticket.
- **DevOps:**
  > Reasoning: `impl Self for X` is one more header `Self` token, so it gets E0569 with nothing else. Today's E0904 under the wrong name is a separate wrong-code bug for `impl Int for X`, and it does not compete with this rule.
  >
  > Concern: Unless the not-a-trait ticket gets filed and fixed, `impl Int for X` keeps emitting under TraitContractEffectMismatch's code. That will mislead `blink explain` users.
- **AI/ML:**
  > Reasoning: The `Self` token gets E0569 at name resolution and no second error, so a user sees one clear fault. `impl Int for X` still needs its own not-a-trait code, and that is a separate ticket. The two do not conflict.
  >
  > Concern: If the not-a-trait ticket is not filed, `impl Int for X` keeps giving a message under E0904, a code that belongs to another row.
- **Minimalism:**
  > **Reasoning:** Under Hdr-all, the token is refused before anyone asks whether it names a trait, so the user sees one error with a specific help. The not-a-trait code is still needed for `impl Int for X`, but that is a separate ticket and does not change this case.
  >
  > **Concern:** Until the not-a-trait ticket lands, `impl Int for X` still reports under the wrong constant, E0904. The follow-up ticket must not be dropped.

## Final Spec

The rule is in `sections/03_types.md`, under *The `Self` Type* in §3.6. `ERROR_CATALOG.md` adds "an impl header" to the position list of E0569.

```blink
trait Tr { fn m(self) -> Int }
type Point { x: Int }
type Box[T] { v: T }

impl Tr for Point {
    fn m(self) -> Int { self.x }                 // OK: Self is Point inside the body
}

impl Tr for Self { fn m(self) -> Int { 1 } }     // E0569 at `Self`: write `impl Tr for Point`
impl Tr for Box[Self] { fn m(self) -> Int { 1 } } // E0569 at `Self`: write `Box[Point]`
impl Self for Point { fn m(self) -> Int { 1 } }  // E0569 at `Self`, and no other error
impl From[Self] for Point { /* ... */ }          // E0569 at `Self`: write `From[Point]`
impl Tr for Point where Self: Eq { /* ... */ }   // E0569 at `Self`: write `where Point: Eq`
```

Locked points:

- An impl's `Self` binds at the `{` of its body. The header is outside the body. Every `Self` token in an impl header is refused: the trait, the target type, the type arguments of both, a binder, a bound and a `where` clause.
- A trait declaration keeps `Self` in its own header: a supertrait clause and a `where` clause. The rule is about impl headers only.
- The error is E0569 `SelfOutsideTraitOrImpl`. There is one error at each `Self` token, and the refused `Self` gets no second error. The catalog adds "an impl header" to the position list.
- A header site gets a header-specific help. It says that the header names the type. It says what to write: `impl Tr for Point`, `From[Point]`, and for a `where` clause the rewritten clause (`where Point: Eq`, or a bound on a binder).
- `impl Self for X` is E0569 at the `Self` token and nothing else.
- `impl Int for X`, a real type in trait position, is not a `Self` case. This decision does not cover it.
