[< All Decisions](../DECISIONS.md)

# Annotation List (One Normative Table) — Design Rationale

The spec, the llms docs and the compiler each listed a different set of annotations (14, 15 and about 20 names). The `@derive` lists also differed on `Display`. Unknown annotation names compiled silently.

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated in independent-proposal → debate → vote rounds. Each panelist's text is below as written, with headings moved down a level.

#### Phase A — Independent proposals

<details><summary><b>Systems</b></summary>

###### Systems panelist: Phase A proposals

####### Proposal S1: one closed table, and unknown names are a hard error

**Where the list lives.** §11.1 holds the only normative table. Every other place points to it and does not copy it: §2.17, the ordering rule at 07:2938, the line about "all 13 annotation types", and DECISIONS.md:13 (which spells it `@mod`). The `blink llms` docs get their list from §11.1, so they cannot drift again.

The table has these columns: name, target(s), argument form, canonical order rank, and **codegen effect**. The codegen effect is one of:
- **none**: metadata or tooling only.
- **check**: emits a runtime check.
- **layout**: changes C layout or ABI.
- **synth**: generates functions.

From my seat that last column matters most. A reader must see which annotations put code in the binary.

| Annotation | Target | Codegen effect |
|---|---|---|
| module | file | none |
| capabilities | module | none (static check) |
| derive | type | synth |
| handle_all | effect | none (W0545) |
| src | fn, type, module | none |
| requires / ensures | fn | check (removable via verify) |
| where | type alias | check |
| invariant | type | check |
| pure | fn | none (static E1307) |
| perf | fn | none (tooling) |
| ffi, ffi.struct, ffi.opaque | fn / type | layout |
| trusted | fn | none (claim, audit: required) |
| alt | fn | none (tooling) |
| verify | fn | check-or-none |
| allow | fn, type | none |
| deprecated | fn, type | none |
| tags, skip, expect_panic | test / fn | none (test harness) |

**Unknown names are an error.** A new `UnknownAnnotation` error fires on any name not in the table and gives a did-you-mean hint. Today this compiles silently:

```blink
@inline
fn hot_path(xs: List[Int]) -> Int {
    xs.len() * 2
}
```

The author thinks they asked for inlining and got nothing. An annotation that compiles and does nothing lies about what the hardware sees, which is the worst outcome for a systems user. The `@effects` decision already chose a targeted error over silence. This makes the same choice in general and closes the ticket the panel deferred at DECISIONS.md:395.

**Freeze.** The set is closed. Users cannot define annotations: no proc macros and no decorators. Each of those hides codegen, costs compile time, and breaks the property that a reader can predict the output C. Adding a name needs a panel vote and an edition.

*Cross-language:*
- Rust errors on unknown attributes (`E0658` / `unknown attribute`).
- Go's `//go:` directives fail silently when misspelled, which is a known footgun.
- Zig has no attributes at all.

Blink should act like Rust here, not Go.

**Tradeoff:** an unknown name now breaks a build where it used to pass, so code that relied on silent acceptance stops compiling. I accept that: the corpus has exactly one such use (`@inline`).

####### Proposal S2: no silent no-ops for annotations that are specified but not implemented

The spec is a blueprint, so `@perf`, `@alt`, `@src`, `@invariant`, `@skip`, `@verify(fallback: "error")` and the structured fields of `@deprecated` stay in the table. A compiler that does not yet support one must reject it with a "specified, not supported by this compiler" error. This is the same pattern `@derive(Display)` already uses with E1402. It must never parse the annotation and throw it away.

```blink
type Account {
    balance: Int
    @invariant(self.balance >= 0)   // must error today, not vanish
}
```

`@invariant` today is the worst case. The user writes a safety check, the compiler deletes it, and the binary has no check. A discarded `@perf(p99: 5ms)` is the same false promise: the user believes a performance contract exists when none does.

**Tradeoff:** the two `@src` uses fail until the compiler supports `@src`. That is fine. Two broken uses are better than silent loss of meaning.

####### Proposal S3: the fate of each stray annotation

- **@pure:** add to the table. It is already specified in §3b.2 and §4.16.3, and it is a zero-cost static check.
- **@tags and @ffi.struct / @ffi.opaque:** add to the table. All three are decided already and used heavily (162 and 136 uses for the FFI forms).
- **@skip:** add to the table and implement it, as already decided (3-2).
- **@expect_panic:** add it as a test annotation. It has 29 uses and desugars to `assert_panics` with no runtime cost outside tests. The other choice is to delete it from code; leaving it unspecified is not an option.
- **@modifies:** remove it from the language and make it a **reserved name** that gets its own error ("reserved for future verification"). Today it validates its arguments (E1308) and has no semantics. That is a no-op that looks like a check, and decisions/module-state-effect.md already replaced the write-set use with a State effect. Reserving the name keeps the future SMT path open without a false promise now.
- **@inline, @cold, @packed and similar codegen hints:** do not add them. gcc and clang at `-O2` make better inlining choices than users do. If a layout hint is ever needed, it goes through `@ffi.struct`, where the C header defines the layout. This keeps codegen predictable and the surface small.

####### Proposal S4: seven @derive targets, drop Display

The list is Eq, Ord, Hash, Clone, Debug, Serialize, Deserialize, which is what the compiler accepts. Remove Display from 03_types.md:4390 and from §11.1.

```blink
@derive(Eq, Hash, Debug)
type Point {
    x: Int
    y: Int
}

impl Display for Point {
    fn to_string(self) -> Str {
        "({self.x}, {self.y})"
    }
}
```

**Why:** each derive produces a monomorphic function with a field-wise structure the compiler can predict. Display is the user-facing form, and no single structural rendering is correct for it. A derived Display would either copy Debug or pick a format that users will override anyway. Rust refuses `#[derive(Display)]` for the same reason, and it lives in third-party crates there.

**Tradeoff:** code already written as `@derive(Display)` breaks. It already gets E1402 today, so in practice nothing changes.

####### Ordering

The canonical order is the rank column of the table. Drop `effects` from `annotation_order` in src/formatter.bl. Unknown names cannot reach the formatter, because they are now errors.

####### Summary of the systems position

There is one table, it says what each annotation costs in the binary, and the set is closed. An annotation is either checked or rejected, never silently dropped. Derive is limited to traits that have a single predictable structural form.

</details>

<details><summary><b>Web/Scripting</b></summary>

###### Web/Scripting panelist — Phase A

Lens: a Python/TS dev types `@inline`, `@require`, or `@derive(Display)`. They expect either "it works" or "a clear error". Today Blink does a third thing: compiles and silently does nothing. That is the worst DX outcome, and for an AI-first language it is poison training data — models learn `@bogus` is fine.

####### P1 — One table, one place, everything else derived (core)

§11.1 (sections/07_trust_modules_metadata.md) becomes the single normative list. Every other list (§2.17, llms-full.md, DECISIONS.md ordering line) either links to it or is regenerated from it — never hand-maintained. §2.17's "all 13 annotation types" becomes "see §11.1". The canonical-ordering sentence lives in the same section and must name exactly the table's rows.

Table columns: **Name | Target | Arguments | Meaning | Status** where Status ∈ {`active`, `reserved`}. Nothing else. Missing rows added: `@module`, `@pure`, `@tags`, `@skip`, `@ffi.struct`, `@ffi.opaque`.

```blink
@module("billing")
@capabilities(DB)

@derive(Eq, Debug)
type Invoice {
    id: Int
    total: Int
}

@pure
@requires(items.len() > 0)
fn total(items: List[Int]) -> Int {
    items.fold(0, fn(a, b) { a + b })
}
```

Tradeoff: hand lists drift — the brief shows five disagreeing ones. A dev searching "blink annotations" lands on a random one. One table = one Stack Overflow answer.
Cross-language: Java's annotation set is discoverable in one place (`java.lang`); Python decorators are scattered and nobody can list them.

####### P2 — Unknown annotation is a compile error with "did you mean"

New `UnknownAnnotation` (E-code TBD). Fires for any name not in the table; suggests the nearest name by edit distance.

```blink
@require(x > 0)      // error UnknownAnnotation: no annotation `@require`. Did you mean `@requires`?
@inline              // error UnknownAnnotation: no annotation `@inline`. Blink has no user or hint annotations.
fn f(x: Int) -> Int { x }
```

Tradeoff: strict; a JS dev used to decorator libraries might feel boxed in. But the spec already says annotations are "compiler-checked — not decorators". A silent typo on `@requires` means a contract the user believes in never runs — a correctness bug disguised as flexibility. The `@effects` decision explicitly deferred this general error; this closes it. `EffectsAnnotationRemoved` stays as the more specific diagnostic.
Cross-language: TypeScript errors on an unknown decorator (unresolved name); Python raises `NameError`; Rust errors on unknown attributes. Only C `#pragma` silently ignores unknowns — nobody wants that model.

####### P3 — A listed annotation is never silently ignored

Normative rule: an annotation either has its specified effect, or the program is rejected with a clear "not yet supported" diagnostic. Parse-and-discard is forbidden. Today `@invariant` is parsed and thrown away — users think their bank balance is protected.

For tool-consumed annotations (`@perf`, `@alt`, `@src`), "has its effect" means the compiler checks shape (target, argument names, argument types); the tool consumes them later. `@src(req: 5)` must fail even with no `blink trace` installed.

####### P4 — Fate of each problem name

| Name | Proposal | Reason (DX) |
|---|---|---|
| `@pure`, `@tags`, `@ffi.struct`, `@ffi.opaque`, `@module` | add to table, active | used hundreds of times; just undocumented in the table |
| `@skip` | add, active (decided 3-2) | pairs with `skip()` as decided |
| `@invariant`, `@perf`, `@alt`, `@src` | keep active per spec; P3 applies | spec is the blueprint; no silent no-ops |
| `@modifies` | `reserved`; use is an error ("reserved for a future verifier") | a recorded decision rejected it in favour of State; 14 meaningless uses teach a lie |
| `@expect_panic` | remove; use `assert_panics` | in no doc; two ways to test a panic = two SO questions; "one obvious way" beats saving one line |
| `@deprecate_override` | add a row or delete the text — panel picks | half-specified is not an option |

Detail conflicts: the decided form wins — `@trusted` requires `audit:`; `@deprecated` is the structured form; `@allow` targets fn and type. `@verify`: I lean toward the spec's three values (`runtime | error | trust`) since the spec leads the compiler, but llms-full and spec must say the same thing; weakly held, defer to PLT.

####### P5 — `@derive` is seven traits; drop `Display`

Normative list: `Eq, Ord, Hash, Clone, Debug, Serialize, Deserialize`.

```blink
@derive(Debug)
type Point {
    x: Int
    y: Int
}

impl Display for Point {
    fn fmt(self) -> Str { "(${self.x}, ${self.y})" }
}
```

Tradeoff: one more impl for users who want pretty output. But "derive Debug or Display?" is a classic beginner trap. Display is user-facing text; a derived one is never the format you actually want, and Debug already covers "just show me the thing". Fewer choices, fewer wrong ones — and it matches the compiler today.
Cross-language: Rust refuses `#[derive(Display)]` for exactly this reason. Python dataclasses give `__repr__` (Debug), not a custom `__str__`. Kotlin data class `toString` is Debug-shaped.

####### P6 — Freeze the set

The set is closed. Adding a name requires a panel vote and a table row in the same change. No user-defined annotations in v1; revisit only with a concrete macro/plugin story.

Tradeoff: frameworks cannot do `@get("/users")` routing. Fine — Blink's web story should be plain functions, which are easier for humans and LLMs to read than decorator magic. A closed set is also what makes P2's "did you mean" possible.

####### Vote intent

P1 + P2 + P3 are must-haves. P4–P6 are my preferred positions.

</details>

<details><summary><b>PLT</b></summary>

###### PLT Panel: Phase A proposals

**Core problem.** §2.17 and §11 say annotations are "compiler-checked, not optional metadata." But the compiler accepts unknown names without a word, and it parses `@invariant` and then discards it. So the spec makes a claim that the implementation does not meet. If a user writes `@invarient(self.balance >= 0)` or `@pur`, they lose a check and nothing tells them. When a property is claimed but not checked, the error is in the type system, not in the docs. My proposals fix the semantics first. The list follows from them.

####### P1. One normative table in §11.1, closed-world (the main proposal)

§11.1 becomes the single source of truth. Each row gives:

- the name
- the target sort: fn, type, type-alias, effect, module, test, or field
- the argument grammar
- the static meaning: which phase checks it and which diagnostic it raises
- the status: **checked**, **tool-checked**, or **reserved**
- its rank in the canonical order

§2.17, the ordering text, DECISIONS.md:13 and llms-full refer to this table or are generated from it. They do not copy it. The formatter's `annotation_order` and the `blink llms` catalog come from the table, and a ci row checks that they agree.

**Typing rule for annotations.** For `@a(args)` attached to a declaration `d` of sort `s`:

1. `a` must be in the table. If not: a new error, `UnknownAnnotation`.
2. `s` must be in the target set for `a`. If not: E1110 (already exists).
3. `args` must match the grammar for `a`.
4. `a` must not occur twice on `d`, unless its row says it may repeat (requires, ensures, invariant, allow).

```blink
@module("bank")
@capabilities(Db)

@derive(Eq, Debug)
type Account {
    @invariant(self.balance >= 0)
    balance: Int
}

@pure
fn fee(amount: Int) -> Int {
    amount / 100
}

@requires(amount > 0)
@ensures(result.balance == acct.balance - amount - fee(amount))
fn withdraw(acct: Account, amount: Int) -> Account {
    Account { balance: acct.balance - amount - fee(amount) }
}

@pur          // error: UnknownAnnotation "pur" (did you mean "pure"?)
fn g() -> Int { 1 }
```

`EffectsAnnotationRemoved` stays as a more specific case of `UnknownAnnotation`. This is the general error that Minimalism asked for and that was deferred to "a separate ticket."

**Tradeoffs.** A closed world means adding an annotation needs a spec change, and that is the intent. It costs nothing in soundness. The one migration cost is `@inline` in one test.

**Cross-language.**
- Rust rejects an unknown `#[attr]` (E0658, "cannot find attribute").
- Python decorators are open, but they are functions.
- Java lets unknown annotations through only because they must be declared types.

Blink has no user annotations, so silence has no reason to exist.

####### P2. Never accept a specified-but-unchecked claim

Each annotation states something about the program. The status column decides what the compiler does:

- **checked**: full semantics.
- **tool-checked** (`@perf`, `@alt`, `@src`): the compiler checks only the argument grammar. The meaning belongs to `blink bench`, `blink alt` and `blink trace`, and the table says this. These do not claim a semantic property, so a compiler that does not run them is still sound.
- **property claims that the compiler cannot yet check** (`@invariant`, `@verify(fallback: error)`, `@deprecated(removal:)`): the compiler gives a hard error, "specified, not yet supported." This is the same pattern as `@derive(Display)` and E1402. The spec text stays, because the spec is a blueprint. Today `@invariant` is parsed and dropped, and that is the worst possible state, because the spec at 03b:193 promises a check at every construction site.

####### P3. Remove `@modifies` from the accepted set (status: reserved)

A frame condition that nothing checks is an unchecked claim. decisions/module-state-effect.md chose a State effect over write sets. The table lists `modifies` as **reserved**, so using it is an error ("reserved for the verification backend"). This keeps the name free for later without letting it tell lies now.

**Cross-language.** In Dafny, `modifies` has meaning only because the verifier checks it.

####### P4. Spec `@pure`; replace `@expect_panic`

- **`@pure`** has a typing role: E1307, and the rule that contract predicates may call only `@pure` functions (E1302). It already has a spec section in 03b and §4.16.3, so it gets a row in the table.
- **`@expect_panic`** rewrites the function body into `assert_panics`. That is a macro posing as an annotation, and it duplicates an expression form that already exists. The expression composes better: you can scope it, nest it, and run it more than once in one test. The annotation cannot do any of that. I propose to replace its 29 uses with `assert_panics` in a 3-step migration, then delete it. If the panel wants to keep it, its row must give its meaning as that exact desugaring, so that the two forms cannot drift apart.

####### P5. `@derive`: seven targets, with stated laws

`@derive(T)` is sound only if the derived instance is canonical, meaning it follows from the structure alone:

| Trait | Canonical derived instance |
|---|---|
| Eq | componentwise equality |
| Ord | lexicographic order on fields, then variant order |
| Hash | structural hash |
| Clone | structural copy |
| Debug | structural rendering |
| Serialize / Deserialize | structural, as the spec's format defines |

**Display has no canonical structural form.** Its whole purpose is a rendering that the author picks. A derived Display is either Debug under another name or an arbitrary choice that the spec freezes. Haskell derives `Show`, which is the Debug analogue, but not a pretty-printer. Rust refuses `#[derive(Display)]`. So I propose to drop Display from 03_types.md:4390 and §11.1, which leaves seven targets.

The table must also state the coherence laws that a derivation guarantees:

- `a == b` implies `hash(a) == hash(b)`
- derived Ord is a total order that agrees with derived Eq
- `deserialize(serialize(x)) == x`

Deriving `Ord` or `Hash` without `Eq` is an error. Without these laws, a user-written Eq next to a derived Hash can silently break Map.

####### P6. What "freeze" means

"Freeze" should not mean that nothing can change. It should mean the table is closed: any new row, removed row or change of status needs a panel vote recorded in DECISIONS.md. Tooling must never add annotations of its own. A table that only the panel can change, where every row has a checked meaning, is the one sound way to read "one source of truth."

####### Conflicts to resolve as part of this ticket (my picks)

- `@verify` fallback: `runtime | trust | error`. `error` follows P2.
- `@trusted`: `audit:` is required, as already decided.
- `@allow`: target sorts fn and type.
- `@src`: target sorts fn, type and module.
- `@skip`: gets a row, status checked, per the 3-2 decision.
- `@tags`, `@ffi.struct`, `@ffi.opaque`, `@module`: each gets a row.
- `@deprecate_override`: must get a row, or the spec must remove it.

</details>

<details><summary><b>DevOps</b></summary>

###### DevOps/Tooling — Phase A

My test for each option: what does the user see when they get it wrong? Today the answer is "nothing." `@bogus(IO)` and `@inline` compile silently. Silent acceptance is the worst result a diagnostic can give, and for an AI-first language it does real harm. An LLM that writes `@inline`, `@test`, `@json` or `@cfg` from Rust or Python habit gets no signal, so the bad pattern spreads through generated code. Six other lists disagreeing is a symptom. The real gap is that no single registry exists for the compiler, `blink fmt`, the LSP and `blink llms` to share.

####### Proposal 1: One closed registry, and an unknown name is an error

§11.1 becomes the only normative table. Each row has these columns: name, targets, argument shape, status (`active` | `specified`), and the section that defines it. The other places derive from it or point to it:
- §2.17 drops its own list and its "13 annotation types" count.
- DECISIONS.md:13 is history only.
- llms-full is generated from the table.
- The formatter order, `annotation_is_local` and the LSP completion list come from one compiler table (`annotations.bl`), and a ratchet checks that table against §11.1.

A name that is not in the table is a new error, `UnknownAnnotation`, with a nearest-name `help:`. It uses the same rule and the same "refused, not ignored" wording as E0842:

```blink
@requiers(x > 0)
fn sqrt_int(x: Int) -> Int {
    x
}
```
```
error[UnknownAnnotation]: `@requiers` is not an annotation
 --> math.bl:1:1
  |
1 | @requiers(x > 0)
  | ^^^^^^^^^
  = help: did you mean `@requires`?
  = note: Blink has no user-defined annotations; see `blink llms --topic annotations`
```

`@effects` keeps its own `EffectsAnnotationRemoved`, because a retired annotation gets a dedicated message, the same as retired codes. A name that is in the table but on the wrong target stays E1110, and the message names the targets the table allows ("`@where` attaches to a type alias, not a fn").

Tradeoffs:
- One table feeds the error, completion, hover docs, formatter order and the docs. The LSP autocompletes `@` with exact targets, because the table knows them.
- An error, not a warning. A warning would let a misspelled `@requires` drop a contract without notice. That is the same reasoning that made E0842 an error.
- Cost: every speculative annotation must enter the spec first. That is good.

Cross-language: Rust rejects unknown attributes outside tool namespaces (`#[rustfmt::skip]`). TypeScript rejects unknown decorators by name resolution. Python silently accepts unknown decorators only because they are runtime values, and Blink's spec forbids that model.

####### Proposal 2: Fix each row by what it does today, not by deleting it

The spec is a blueprint, so a `specified` row stays when the compiler lags. But a `specified` annotation must not compile silently either. When a user writes it, the compiler gives a warning, `AnnotationNotEnforced`, that says the annotation has no effect yet:

```
warning[AnnotationNotEnforced]: `@invariant` is specified (§3b.2) but this compiler does not check it
```

This is the same honest "not yet" surface as E1402 for `@derive(Display)`. It makes the gap visible in the toolchain, not only in the ticket tracker. Per row:

- **Add to §11.1 (they exist in the spec or the compiler):** `@module`, `@pure`, `@tags`, `@skip`, `@ffi.struct`, `@ffi.opaque`, `@deprecate_override`.
- **`@expect_panic`:** the compiler implements it, 29 tests use it, and no spec text covers it. Do not let tooling run without a spec. I propose to remove it in favour of `assert_panics` in the body. The test-skip vote already chose a function form (`skip()`), and an annotation that rewrites a body is a bad target for "go to definition". If the panel wants to keep it, it gets a spec row. It does not stay in limbo.
- **`@modifies`:** decisions/module-state-effect.md rejected it as a write-set mechanism and only reserved it for an SMT backend. A reserved name that validates its arguments (E1308) but has no meaning teaches LLMs a feature that does not exist. Remove it from llms-full and the compiler, and use it in the future through a new vote. E1308 retires.
- **`@perf`, `@alt`, `@src`, `@invariant`, `@verify(error)`, `@deprecated` removal/fix:** these rows stay `specified` and get the warning. Fix the details that conflict to the spec text (`@trusted` needs `audit:`, `@allow` targets fn, `@verify` takes runtime|error|trust).
- **`effects` in formatter.bl:** delete that dead entry.

####### Proposal 3: The @derive list is part of the same table

The `@derive` row lists all 8 targets, `Display` included, and marks `Display` as `specified`. The compiler keeps E1402's "not synthesized yet" message until it can synthesize `Display`. llms-full shows all 8 with that note, so the 7-item list stops existing.

```blink
@derive(Eq, Hash, Debug)
type Point {
    x: Int
    y: Int
}
```

####### Proposal 4: Close the set, but don't freeze it

"Freeze" should mean closed: adding a name needs a panel vote and a §11.1 row in the same change. It should not mean "no new annotations ever". A ratchet in `task ci` fails when the compiler table and §11.1 disagree, so the drift that caused this ticket cannot return. If tool-specific metadata is ever needed, reserve a namespace prefix now (`@tool.name`, like Rust's `#[tool::...]`) so that the closed set does not block later tools. I state that as a reservation only. YAGNI applies to its semantics.

####### Summary vote position

1. A closed registry in §11.1, with the compiler table generated or checked by ratchet.
2. `UnknownAnnotation` is an error with a nearest-name hint.
3. `AnnotationNotEnforced` is a warning for rows that are specified but not implemented.
4. Remove `@modifies`. Remove `@expect_panic`, or else specify it. Add the 7 missing rows.
5. The `@derive` row has 8 targets, and `Display` is marked `specified`.

My error-code names are proposals. The moderator should map them into the catalog's code ranges (E11xx parser/annotation, a W-code for the warning).

</details>

<details><summary><b>AI/ML</b></summary>

###### AI/ML panelist — Phase A proposals

Framing: today the annotation surface is hostile to code generation. An LLM that writes `@inline`, `@override`, `@json("x")`, `@test`, or `@cfg(...)` (all common in Rust/Python/Java/TS training data) gets a silent compile — the worst signal a model can get, because it reads as "correct." And three disagreeing docs mean the model learns a blend. Proposals below, ordered by generation-accuracy impact.

---

######## P1 — Unknown or misplaced annotation is a hard error, with did-you-mean (highest priority)

A new diagnostic `UnknownAnnotation` fires on any name not in the normative table, with nearest-name suggestion and a curated hint for well-known foreign names.

```blink
@module("billing")

@inline
fn fast_total(items: List[Int]) -> Int {
    items.len()
}
// error[UnknownAnnotation]: `@inline` is not a Blink annotation
//   help: Blink has no inlining hint; the C backend decides. Remove it.

@derive(Eq, Debug)
type Invoice {
    id: Int
    total: Int
}

@pure
type Bad { x: Int }
// error[UnexpectedAnnotation]: `@pure` attaches to fn, not type
```

- **AI tradeoff:** single biggest accuracy win. Hallucinated foreign annotations are a small, predictable set (`@inline`, `@override`, `@test`, `@async`, `@json`, `@cfg`, `@dataclass`, `@staticmethod`); curated hints turn a silent bug into a one-shot repair. Agents in a compile-fix loop converge fast on precise errors, never on silence.
- **Cost:** zero for correct code. Subsumes the narrow `EffectsAnnotationRemoved` (keep it as a curated hint inside the general error) — this is the "separate ticket" DECISIONS.md:395 deferred, and it vindicates Minimalism's dissent.
- **Cross-language:** Rust rejects unknown attributes (`cannot find attribute`); Python/TS decorators are values, so they fail at runtime; Java silently accepts unknown annotations only if they resolve. Blink's spec already says annotations "are compiler-checked" — silence violates its own text.

######## P2 — One normative table in §11.1; everything else is derived

§11.1 becomes the only list: one row per name with target(s), argument shape, one-line meaning, owning section link. All other places link to it instead of restating: §2.17 drops its "13 annotation types" count; DECISIONS.md `@mod` ordering line is corrected; the `llms-full.md` annotation table and the formatter's `annotation_order` are generated from (or checked against) that table in `task ci`.

- **AI tradeoff:** `blink llms` output is training data. If it can drift from the spec, models learn the drift. A ci check makes the docs mechanically true — worth more than any prose fix.
- Canonical ordering lives in the same table (row order or a column), so there is one artifact, not two.

######## P3 — Specified-but-unimplemented: error, never accept silently

`@perf`, `@alt`, `@src`, `@invariant`, `@verify(fallback: "error")`, `@deprecated` removal/fix stay in the spec (spec is blueprint). But the compiler must reject them with an explicit "specified, not yet supported by this compiler" error — same pattern as `@derive(Display)` → E1402. `@invariant` is the worst offender: it is parsed and DISCARDED, so a model (or human) writing a type invariant believes it is enforced. That is a correctness hole, not a docs nit.

- **AI tradeoff:** generated llms docs omit (or mark as unavailable) these rows until shipped, so models don't learn to write annotations that do nothing.

######## P4 — Fate of the disputed names (one way to do each thing)

| Name | Proposal | Reason |
|---|---|---|
| `@pure`, `@tags`, `@ffi.struct`, `@ffi.opaque`, `@module`, `@skip` | add to §11.1 table | already decided/specified elsewhere |
| `@skip` | implement (decision 3-2 says both forms exist) | spec row without compiler = P3 error until then |
| `@modifies` | **reserved**: name in table, use is an error "reserved for future verifier" | today it validates args and does nothing — models will copy it from 14 uses and believe it constrains writes. State-effect decision already replaced it |
| `@expect_panic` | **remove** in favour of `assert_panics` (3-step migration; 29 uses) | it only desugars into `assert_panics`: two ways to write one test = a decision point, and it is in no spec section so no model can learn it from spec. If the panel keeps it, it must be specified and given a row |
| `@verify` fallback | spec wins: `runtime \| trust \| error`; docs regenerated | one value set |
| `@trusted` | `audit:` required everywhere (matches compiler E0836) | bare form in old docs teaches the wrong shape |
| `@allow`, `@src`, `@deprecated` targets | table states targets once; follow compiler where spec is silent | |

######## P5 — `@derive` targets: seven, drop Display (secondary, moderate confidence)

Recommend `Eq, Ord, Hash, Clone, Debug, Serialize, Deserialize`. Remove `Display` from the derivable set.

- **AI tradeoff:** Display is a human-chosen format; a derived Display either duplicates `Debug` (redundant choice) or invents a format the user then overrides. Rust deliberately omits `#[derive(Display)]`, so the dominant training corpus already expects hand-written `impl Display`. Seven names = zero spec/compiler/model-prior mismatch.
- If the panel keeps Display, P3 applies: E1402 until shipped, and llms docs omit it.

######## P6 — Freeze

The table is closed: adding, removing, or retargeting a name requires a panel vote and a table edit in the same change. No user-defined annotations in v1.

- **AI tradeoff:** a closed set of ~20 names with one target set each is fully learnable from the spec alone. An open/macro-extensible set is not.
- **Cross-language:** Go has a fixed directive set (`//go:` pragmas) and models handle it well; Python/TS decorator ecosystems are where models hallucinate the most.

---

**Vote I would cast:** P1 + P2 are must-haves; P3 follows from P1; P4 `@expect_panic` removal and `@modifies` reservation are the contested picks; P5 moderate; P6 locks in the gain.

</details>

<details><summary><b>Minimalism</b></summary>

**Minimalism: Phase A proposals**

The real defect is not that the lists disagree. It is that the set has no boundary. Right now the compiler accepts `@bogus(IO)` without a word, which breaks the spec's own claim that annotations "are compiler-checked, not optional metadata". If we merge the lists and leave that hole open, a sixth list will appear within a year. So the boundary comes first and the list second.

---

######## Proposal M1 (primary): one closed table, unknown names are an error, and the set shrinks

**1. Single source.** §11.1 becomes the only normative list. It gets one row per annotation with name, target, arguments, meaning and order rank. Every other place points to it: §2.17, the llms docs, `formatter.bl annotation_order` and `emit_record.bl`. A CI check compares the compiler's recognizer table with the §11.1 rows and fails on any difference. The "13 annotation types" sentence in §2.17 and the `@mod` line in DECISIONS.md:13 go away.

**2. Closed set, with an error for unknown names.** A new diagnostic, `UnknownAnnotation`, fires on any name not in the table and offers a did-you-mean suggestion. Annotations that already have a removal error, such as `EffectsAnnotationRemoved`, keep their own diagnostic. This is the general error that was deferred in DECISIONS.md:395. I dissented then for exactly this reason.

```blink
@inline              // error[UnknownAnnotation]: `@inline` is not a Blink annotation
fn add(a: Int, b: Int) -> Int {
    a + b
}

@requries(x > 0)     // error[UnknownAnnotation]: did you mean `@requires`?
fn half(x: Int) -> Int {
    x / 2
}
```

**3. What each annotation becomes.** The test I applied: does it change what the compiler checks or emits? If yes, it stays. If no, it is tooling metadata and it leaves the language.

| Keep (17) | Why |
|---|---|
| module, capabilities, derive, handle_all, requires, ensures, where, invariant, pure, verify, ffi, ffi.struct, ffi.opaque, trusted, allow, deprecated, tags | Each one changes checking, codegen or test selection. `@invariant` stays because it is a contract and the spec is the blueprint, but the compiler must stop silently discarding it. Until it is implemented, the compiler should give a "not yet supported" error. |

| Cut | Replacement |
|---|---|
| `@perf` | This is a benchmark assertion that the compiler never checks (§11.2 says so). Put it in a bench file or in `blink.toml [bench]`. |
| `@alt` | Pure tooling, with no compile-time meaning. A naming convention or a `blink alt` manifest can do the same job. |
| `@src` | Provenance metadata. Move it into a `///` doc-comment field (`/// src: AUTH-001`), the same way `@i` was folded into `///` (5-0). `blink trace` can read doc comments. |
| `@modifies` | The panel already rejected it in favour of the State effect, and today it only validates its arguments. "Reserved for a future SMT backend" is the textbook YAGNI case. When that backend exists, it can bring a ticket. |
| `@expect_panic` | It appears in no spec section and duplicates `assert_panics`, which is specified. Migrate its 29 uses, then make it an `UnknownAnnotation` error. |
| `@skip` | Re-open the 3-2 vote. `skip()` is implemented and does the same job. Two ways to do one thing is the cost minimalism exists to refuse. |
| `@deprecate_override` | Fold it into `@deprecated`, through a target rule on trait methods, or cut it. One deprecation annotation is enough. |

The 17 kept names fit on one screen. An LLM can learn the whole set and the compiler can reject everything else. The cut list removes three tooling-only annotations that compile-time code never reads, and that is the class that drifts first.

**4. @derive targets.** Seven: Eq, Ord, Hash, Clone, Debug, Serialize, Deserialize. Drop `Display`. A derived Display has to pick a user-facing format, which is a design choice and not a mechanical one. Debug already covers the mechanical rendering. Rust has never derived Display, for the same reason.

```blink
@derive(Eq, Hash, Debug)
type Point {
    x: Int
    y: Int
}

impl Display for Point {
    fn display(self) -> Str {
        "({self.x}, {self.y})"
    }
}
```

**5. Freeze rule.** Adding a row to §11.1 needs a panel vote, as a `type:spec` change, plus the CI check above. No user-defined annotations and no macro escape hatch. If someone wants a new annotation, they must show that a stdlib function, a `///` field or a `blink.toml` key cannot do the job.

**Tradeoffs.**
- (+) One list, one diagnostic and a smaller surface. LLM training data stops teaching ghost annotations like `@inline` or `@perf`.
- (+) Tooling metadata (`@src`, `@alt`, `@perf`) stops getting language-level stability guarantees that it does not need.
- (−) It cuts features that are specified but were never built. `blink trace` and `blink alt` lose their syntax hooks and must read doc comments or manifests.
- (−) `@expect_panic` users need a migration, but the compiler is the only real user.

---

######## Proposal M2 (fallback): merge, but cut nothing

If the panel wants to keep `@perf`, `@alt` and `@src`, do points 1, 2, 4 and 5 of M1 anyway. Then mark each specified-but-unimplemented row in §11.1 with a status. The compiler gives a "not yet supported" error for those rows, never silent acceptance.

This fixes the drift, but the surface stays at about 22 names, and three of them carry no meaning in the compiler. I would vote for M2 over doing nothing, and for M1 over M2.

---

######## Proposal M0: do nothing, or merge the lists without the unknown-name error

I reject this. A merged list with silent acceptance of unknown names will diverge again, because nothing enforces it. The error is what keeps the list true.

---

**Cross-language notes**
- Go has no annotations. Struct tags are strings and `go vet` checks them, which shows that metadata can live outside the grammar.
- Rust rejects unknown attributes (`#[inlin]` is an error, `unknown attribute`), and its derive set is closed for `std`. Both match M1.
- Java and Python let unknown annotations and decorators pile up, and every library adds its own. That is the C++-committee outcome we should avoid.
- Lua and Scheme show that a small set nobody can grow ages well.

</details>

#### Phase A.5 — Deduped option-space (moderator, mechanical)

###### Phase A.5 — deduped option-space

Full Phase A texts: A_sys.md, A_web.md, A_plt.md, A_devops.md, A_aiml.md, A_min.md in this directory. Read them.

####### Shared by all six proposals (listed for the vote; no debate needed unless you object)
- S1. §11.1 is the one normative annotation table. §2.17, the ordering text, DECISIONS.md:13, llms-full and the compiler's tables point to it or come from it; a ci check compares the compiler's table with §11.1. Canonical order is part of the table. (all six)
- S2. A name not in the table is a new error, `UnknownAnnotation`, with a nearest-name hint. (all six) Variation: `EffectsAnnotationRemoved` stays a separate diagnostic (sys, web, plt, devops, min) vs becomes a curated hint inside `UnknownAnnotation` (aiml).
- S3. The set is closed: no user-defined annotations; adding, removing or changing a row needs a panel vote and a table edit in the same change. (all six)
- S4. Add rows for `@module`, `@pure`, `@tags`, `@ffi.struct`, `@ffi.opaque`. (all six)

####### Contested questions

**Q1. What does the compiler do with a listed annotation it does not yet implement?**
- 1a. Hard error "specified, not supported by this compiler" for every such row (incl. @perf, @alt, @src) — sys, aiml.
- 1b. Tool-consumed rows (@perf, @alt, @src): compiler checks target and argument shape only, then accepts; property claims it cannot yet check (@invariant, @verify(fallback: "error"), @deprecated removal/fix): hard error — plt, web.
- 1c. Warning `AnnotationNotEnforced` for every specified-but-unimplemented row — devops.
- (min: hard error for @invariant; cuts @perf/@alt/@src under Q2.)

**Q2. Fate of @perf, @alt, @src.**
- 2a. Keep in the table (spec is blueprint) — sys, web, plt, devops, aiml.
- 2b. Cut from the language: @perf → bench file / blink.toml [bench]; @alt → manifest/convention; @src → `///` doc-comment field — min (M1). min's fallback M2 = keep with status + "not yet supported" error.

**Q3. @modifies.**
- 3a. Reserved: name stays in the table with status reserved; any use is an error "reserved for a future verifier" — sys, plt, web, aiml.
- 3b. Removed: delete from compiler and llms docs, retire E1308; any use is `UnknownAnnotation` — devops, min.

**Q4. @expect_panic (implemented, 29 uses, in no spec).**
- 4a. Remove; migrate uses to `assert_panics`; then it is `UnknownAnnotation` — web, plt, devops, aiml, min.
- 4b. Specify it as a test annotation (row whose meaning is the `assert_panics` desugaring) — sys.

**Q5. @skip (decided 3-2: both @skip and skip() exist; only skip() implemented).**
- 5a. Keep, add a row, implement — sys, web, plt, devops, aiml.
- 5b. Re-open the 3-2 vote and cut @skip; `skip()` alone — min.

**Q6. @derive targets.**
- 6a. Seven: Eq, Ord, Hash, Clone, Debug, Serialize, Deserialize; drop Display from 03_types.md:4390 and §11.1 — sys, web, plt, aiml, min.
- 6b. Eight incl. Display, Display marked specified, E1402 until synthesized — devops.
- Variation: plt adds stated coherence laws (Eq⇒Hash agreement, Ord agrees with Eq, serialize round-trip) and "deriving Ord or Hash without Eq is an error" (compiler today: deriving Ord or Hash also derives Eq).

**Q7. @deprecate_override (03_types.md:3336, W0731; no code).**
- 7a. Add a row — devops.
- 7b. Fold into @deprecated via a target rule on trait methods, or cut — min.
- (plt, web: "add a row or delete the text"; no pick.)

**Q8. Detail conflicts between lists.**
- @verify fallback values: `runtime | error | trust` (spec) — plt, devops, aiml, web (weak). No one proposed `runtime | trust` only.
- @allow targets: fn, type — sys, plt, web; fn only (spec text) — devops.
- @src targets: fn, type, module — plt, sys.
- @trusted needs `audit:`; @deprecated is the structured form — all who addressed it.

**Q9. Extra table columns / rules proposed by one panelist (accept or reject each).**
- 9a. "Codegen effect" column (none / check / layout / synth) — sys.
- 9b. Duplicate-annotation rule: a name may not occur twice on one declaration unless its row says it may repeat (requires, ensures, invariant, allow) — plt.
- 9c. Reserve a tool namespace prefix (`@tool.name`) now, semantics deferred — devops.
- 9d. Status column values: active/specified (devops), active/reserved (web), checked/tool-checked/reserved (plt).

#### Phase B — Debate (one round)

<details><summary><b>Systems</b></summary>

###### Systems: Phase B round 1

**S1-S4:** agree.

**S2 variation:** `EffectsAnnotationRemoved` stays a separate diagnostic. A retired name gets a message that says what replaced it. A nearest-name hint cannot say that.

**Q1: I move from 1a to 1b, with one condition.** PLT is right that `@src`, `@alt` and `@perf` claim nothing about the program the compiler emits. They do not change the C output, and the compiler is sound if it accepts them after a shape check. My condition: a tool-checked row gets accepted only when the tool that reads it ships in the same toolchain. If `blink bench --check-contracts` does not exist, `@perf(p99: 5ms)` is a contract that no one checks. That is the same false promise as a dropped `@invariant`, so it is a hard error until the tool lands. Property claims (`@invariant`, `@verify(fallback: "error")`, `@deprecated` removal/fix) are a hard error until the compiler implements them.

I reject 1c (a warning). Warnings scroll past in CI logs and LLM fix loops ignore them. A dropped `@invariant` means a binary that has no check the author asked for. That must fail the build.

**Q2: 2a (keep).** Min's cut is a fair design argument. `@src` as a `///` field has precedent in the `@i` fold. But this ticket is about consistency. Cutting specified features is a separate design change, and it should have its own ticket. With Q1 as stated, keeping them costs nothing at runtime and creates no silent no-ops.

**Q3: 3a (reserved), weakly held.** DevOps worries that a reserved name teaches LLMs a feature that does not exist. But every use of it is an error that says "reserved", so a model learns that it cannot write it. Removal (3b) gives the same error with a worse message. Either option is fine with me, as long as E1308's silent acceptance ends.

**Q4: I move from 4b to 4a (remove `@expect_panic`).** PLT's point wins: an expression scopes, nests and repeats, and an annotation that rewrites a body cannot. It also hides the desugared code from the reader, which is the class of thing I object to elsewhere. Migrate the 29 uses, then it becomes `UnknownAnnotation`.

**Q5: 5a.** The 3-2 vote stands. Re-opening it is out of scope for a consistency ticket.

**Q6: 6a (seven, drop Display).** I accept PLT's coherence laws. I also support "deriving Ord or Hash without Eq is an error". Today the compiler derives Eq without being asked, which generates code the user did not request, so the explicit form is better for predictable codegen. DevOps's 6b keeps a target that has no canonical structural form. E1402 forever is not a plan.

**Q7: 7b (fold into `@deprecated`).** `@deprecated` on a trait method that has a default body can mean "overriding this is deprecated" through a target rule. That gives one deprecation annotation and one table row. The W0731 behavior stays.

**Q8:**
- `@verify` fallback values: `runtime | error | trust`.
- `@allow` targets: fn and type.
- `@src` targets: fn, type and module.
- `@trusted` needs `audit:`, and `@deprecated` takes the structured form.

**Q9:**
- **9a (codegen-effect column):** I still want it, but I will not die on it. If the panel rejects a separate column, the Meaning column must say in words when an annotation emits code: a runtime check (requires, ensures, where, invariant, verify), synthesized functions (derive), or a layout or ABI change (ffi.*). Users must be able to see cost from the table.
- **9b (no duplicates unless the row allows it):** accept. It is cheap and closes another silent case: two `@capabilities` today would mean what?
- **9c (`@tool.name` namespace):** reject. YAGNI. Unknown names are already errors, so adding a namespace later breaks nothing. A reserved namespace that has no semantics is the same kind of half-feature as `@modifies`.
- **9d (status values):** use PLT's `checked | tool-checked | reserved`. I reject `active | specified`, because "this compiler does not do it yet" is implementation state. Our rules keep implementation detail out of sections/. A spec row never describes what a compiler has built. That belongs in the diagnostic (E1402-style) and in the generated llms docs, not in §11.1.

**Stable:** yes. My positions are 1b (with the tool-ships condition), 2a, 3a, 4a, 5a, 6a with PLT's laws, 7b, 9a (soft), 9b, no 9c, and 9d as PLT's values.

</details>

<details><summary><b>Web/Scripting</b></summary>

###### Web/Scripting — Phase B round 1

S1, S3, S4: agree.

**S2 variation.** Keep `EffectsAnnotationRemoved` separate. That was decided, and a retired name deserves its own message. I do take aiml's idea: `UnknownAnnotation` carries curated hints for the foreign names devs and models actually type (`@inline`, `@override`, `@test`, `@async`, `@json`, `@dataclass`, `@staticmethod`). "Blink has no X; do Y" fixes the code in one shot. Edit distance alone cannot do that.

**Q1: 1b (unchanged).**
- Against 1c (warning): CI logs bury warnings. A warning on `@invariant` means a user ships a type they think is guarded. A dropped safety claim must stop the build.
- Against 1a (error on `@perf`/`@alt`/`@src`): those rows claim nothing the compiler owes. If the compiler checks their shape and the table says "consumed by `blink bench`/`alt`/`trace`", that is honest. Rejecting `@src(req: "AUTH-1")` until some trace tool ships punishes the users who adopt the docs we wrote.

**Q2: 2a.** Min's replacements create more questions than they remove. A magic `/// src:` field in a doc comment is a second hidden syntax, and a `blink.toml [bench]` entry sits far from the function it describes. A Python dev knows "metadata on a function goes on the function". Keep all three, under 1b.

**Q3: I move to 3b (remove).** I read the table as a dev would: a `reserved` row in the one list everyone learns from prompts the question "how do I use `@modifies`?". Out of the table, a curated `UnknownAnnotation` hint can still say "Blink has no `@modifies`; module state uses the State effect". A future verifier brings its own vote. Either way it is an error, so the risk is low.

**Q4: 4a.** Remove. One way to test a panic.

**Q5: 5a.** `@skip` is the most familiar test annotation there is (`pytest.mark.skip`, `it.skip`, JUnit `@Disabled`). A decision made 3-2 should not be re-opened inside a list-merging ticket. Min can file it on its own.

**Q6: 6a.** I accept plt's laws. Put them in the derive section and link that section from the table row. On "Ord or Hash without Eq": I accept the error, if it comes with a fix ("add `Eq` to this `@derive`"). An implicit Eq is a trap. A user writes a manual `impl Eq` next to `@derive(Hash)` and gets a conflict whose cause they cannot see. An explicit `@derive(Eq, Hash)` reads clearly in 5 seconds.

**Q7: fold into `@deprecated` (7b, fold branch).** Two deprecation annotations make a "which one do I use?" question. If `@deprecated` on a trait method can carry the override meaning, fold it in. If the meaning differs (it warns implementers, not callers), then it gets a row. I won't cut it outright without reading 03:3336 against the fold.

**Q8.**
- `@verify`: `runtime | error | trust`. The spec leads, and llms-full gets regenerated to match.
- `@allow`: fn, type. Suppressing a warning on a whole type is the 90% case for derive- and impl-heavy code.
- `@src`: fn, type, module.
- `@trusted`: `audit:` is required.
- `@deprecated`: the structured form.

**Q9.**
- 9a (codegen-effect column): reject. That is implementation detail, and the spec must not hold it. If users need "does this add runtime checks?", the Meaning column can say so in words.
- 9b (duplicate rule): accept. `@pure @pure` should be an error, and the repeatable rows are obvious.
- 9c (`@tool.` prefix): reject (YAGNI). A reserved prefix without semantics invites "how do I make my own `@tool.x`?" and weakens S3.
- 9d (Status values): `checked | tool-checked`. "Specified but not implemented" describes the compiler, not the language. Since the spec is the blueprint, that state belongs in compiler diagnostics and generated `blink llms` notes, not in a spec column. With Q3 = remove, no `reserved` value is needed.

Stable: ready to vote.

</details>

<details><summary><b>PLT</b></summary>

###### PLT: Phase B round 1

**S1, S3, S4:** agree.

**S2 variation:** keep `EffectsAnnotationRemoved` as its own diagnostic. The panel decided it 5-1, and a removed feature deserves a stable code that names the migration. A curated hint inside `UnknownAnnotation` would do the same job, but it reopens a settled vote for no gain.

**Q1: I refine 1b, and the result moves close to 1a.** The rule I propose: an annotation is accepted only when its checker exists, whether that checker is the compiler or a named tool. Otherwise it is a hard error, "specified, not supported by this toolchain." aiml and sys are right that `@perf(p99 < 5ms)` is a claim too: it says that `blink bench` enforces it. If that tool does not check it, the claim is false, just like `@invariant`. Today no consumer exists for `@perf`, `@alt` or `@src`, so all three are errors now. They become accepted per row when their tool ships. That is 1a's behaviour today, with a principled rule for later.

**Against 1c (warning):** a warning can be silenced with `@allow` or `[lints]`. Then a program compiles while it states a property that nobody checks. That is exactly the hole this ticket exists to close. A warning is fine for "deprecated", never for "unchecked claim."

**Q2: 2a for `@perf` and `@alt`.** `@alt` states an equivalence between functions, and `@perf` states a bound. Both are semantic claims, so they belong in the language next to the contracts. **`@src` is different:** it states no property, it is only provenance. min's move of it into `///` matches the 5-0 `@i` precedent. I would accept cutting `@src`, but I do not demand it.

**Q3: I change to 3b (remove).** devops convinced me. A "reserved" row shows up in the table and in llms docs, so it teaches a feature that does not exist. And in practice it errors just as `UnknownAnnotation` does. Bringing the name back needs a vote either way. Removing it also takes the third status value out of the table (see Q9d). E1308 retires.

**Q4: 4a.** sys's 4b is acceptable only if the row is defined as that exact desugaring. But two surfaces for one meaning is the defect we are fixing.

**Q5: 5a, against min.** `@skip` and `skip()` do not mean the same thing:
- `@skip` is static. Tooling can list skipped tests without running anything, and the skip is unconditional.
- `skip()` is dynamic and can depend on a condition.

These are two different points in the semantics, not a redundancy. The row must state this difference.

**Q6: 6a, plus the coherence laws, against devops's 6b.** Display has no canonical derivation, so a "specified" Display target fixes in the spec a choice that should never be made.

I correct my own rule: the hazard is a hand-written `Eq` next to a derived `Hash` or `Ord`. The compiler's present behaviour, where deriving Ord or Hash also derives Eq, is coherent. So the rule becomes: deriving `Hash` or `Ord` derives `Eq`, and it is an error if the type also has a hand-written `Eq` impl. The table states the laws: Eq⇒Hash agreement, Ord total and agreeing with Eq, Serialize/Deserialize round-trip.

**Q7: 7b (fold).** One annotation, `@deprecated`, with a meaning that depends on the target: on a trait method it deprecates overriding it, and W0731 stays. A second name for a target-dependent variant of the same idea is not compositional.

**Q8:**
- `@verify` fallback: `runtime | error | trust`. `error` stays an error until a static prover exists, per my Q1 rule.
- `@allow` targets: fn and type. One rule across declaration sorts; a type-level `allow` has an obvious scope.
- `@src` targets: fn, type and module, if `@src` is kept.
- `@trusted` needs `audit:`, and `@deprecated` uses the structured form.

**Q9:**
- **9a: reject.** "Codegen effect" is an implementation detail. It belongs in docs/build, not in the spec. The fact that matters to users ("adds a runtime check") is already in the meaning column.
- **9b: accept** (my proposal). Without it, `@requires(a) @requires(b)` has an implicit meaning (conjunction) while `@module("a") @module("b")` has none.
- **9c: reject.** A reserved prefix with no semantics is the same mistake as reserved `@modifies`. When a tool needs it, it brings a ticket.
- **9d: two statuses, `active` and `specified`** (devops's names). The meaning of `specified` is my Q1 rule: an error until its checker exists. With `@modifies` removed, `reserved` is not needed, and my `tool-checked` folds into "active once its tool exists."

</details>

<details><summary><b>DevOps</b></summary>

###### DevOps/Tooling — Phase B round 1

**S1–S4:** agree.
**S2 variation:** keep `EffectsAnnotationRemoved` separate. It was voted 5-1 and has its own message. I take aiml's idea of curated `help:` lines for known foreign names (`@inline`, `@test`, `@json`, `@override`, `@cfg`) inside `UnknownAnnotation`. Edit distance alone gives a bad hint for `@inline` (`@invariant`?), so a curated hint is a better diagnostic.

**Q1 — I change from 1c to 1b.** A warning was the weak choice. A warning on `@invariant` still lets the binary ship without the check, and warnings get muted in CI logs. plt and web drew the right line: a property claim the compiler cannot check is a hard error, and a tool-consumed row gets a target and argument-shape check and is then accepted. That shape check is real diagnostic value: `@src(req: 5)` fails at `blink check` and the LSP underlines it, without waiting for `blink trace` to exist. 1a (a hard error on `@perf`/`@alt`/`@src`) breaks code that is correct per spec only because a separate tool has not shipped yet. That is the wrong layer.

**Q2 — 2a, keep.** Against min's `/// src: AUTH-001`: a doc-comment field is free text. `/// scr: AUTH-001` compiles, the LSP cannot complete it, and `blink fmt` cannot order it. That is the silent-typo class this ticket exists to kill. An annotation with a checked shape gives a better error surface than a convention. The same holds for `@perf` in a bench file: it moves the claim away from the function it describes, so hover on the fn no longer shows it.

**Q3 — I change from 3b to 3a, reserved.** Diagnostic reason: if it is removed, `@modifies` falls into `UnknownAnnotation`, and the nearest-name hint suggests something meaningless. A reserved row gives one exact message: "`@modifies` is reserved for a future verifier; write effects go through the State effect (see …)". Condition: the generated llms docs list reserved names only in a short "reserved, do not use" line, never as a usable row.

**Q4 — 4a, remove `@expect_panic`.** Unchanged. Against sys's 4b: an annotation that rewrites a body breaks "go to definition", and the failure span lands on a desugared node, not on the expression that should panic. `assert_panics(...)` puts the span on the real call.

**Q5 — 5a.** The 3-2 vote stands. min gives no new evidence to re-open it. Tooling note: `@skip` on a non-test is E1110, and the test runner reports it as a skip with its reason.

**Q6 — I change from 6b to 6a, seven.** The arguments from plt, sys and web are sound: Display has no canonical structural form. My 6b would leave a row that permanently errors, which is a docs lie that LLMs learn. With seven targets, `@derive(Display)` gets E1402 with `help: implement Display by hand; @derive(Debug) gives a structural rendering`.

**Q7 — 7a, keep a separate row; reject the cut.** The spec's deprecate-then-seal migration depends on it. Folding it into `@deprecated` on a trait method is ambiguous: does it deprecate calling the method or overriding it? Those are two different diagnostic sites (call site vs impl site). One name for each meaning gives clear errors. I would accept a structured field (`@deprecated(override: ...)`) only if the panel prefers fewer names, but separate is clearer.

**Q8:**
- `@verify`: `runtime | error | trust`, where `error` is a hard error until supported (Q1).
- `@allow`: I change to fn, type. Warnings on derived or type-level code need a place to be suppressed, and three panelists agree.
- `@src`: fn, type, module.
- `@trusted` needs `audit:`. `@deprecated` uses the structured form.

**Q9:**
- 9a codegen-effect column: reject. It is implementation detail (lowering), which spec text must not hold. sys can keep it in docs/build/.
- 9b duplicate rule: accept. It gives a precise error ("`@pure` appears twice") where today the second one is silent.
- 9c `@tool.name` prefix: I withdraw it. YAGNI, and nobody needs it now.
- 9d status values: plt's `checked | tool-checked | reserved`. "Specified but not implemented" is compiler state, not spec state. The spec is a blueprint, so implementation status belongs in the compiler's diagnostics and the release notes, not in a §11.1 column.

**written; stable**

</details>

<details><summary><b>AI/ML</b></summary>

###### AI/ML — Phase B round 1

**S1–S4:** agree.

**S2 variation:** I drop mine. `EffectsAnnotationRemoved` was voted 5-1 as its own diagnostic. Keeping it separate costs nothing. The thing that matters for generation is that both carry a precise fix-it. Separate is fine.

**Q1 — I move from 1a to 1b.** PLT and web draw the right line. The model-safety harm is a *property claim the compiler silently drops*: `@invariant` today, `@verify(fallback: "error")`, `@deprecated` removal/fix. Those must hard-error until built. `@src` is pure metadata, so accepting it after a shape check misleads no one. `@perf` and `@alt` are claims checked by a named tool, not by the compiler, and the table says so in a "tool-checked" status. A hard error on them would only push models away from annotations the spec wants them to write.
- **Against 1c (warning):** agents in a fix loop and humans skimming CI both ignore warnings. A warning on a silently dropped `@invariant` is the same trap as silence. It also violates "annotations are compiler-checked, not optional metadata."

**Q2 — 2a.** Keep @perf/@alt/@src. Minimalism's @src → `///` field has precedent (`@i` merged into `///`), and I would not fight it. But that needs a structured doc-comment field syntax, which is a separate spec question. Cutting @perf to a bench file splits the contract from the fn, and the model then has to keep two files in sync. Co-location is better for generation.

**Q3 — I move from 3a to 3b.** Remove `@modifies` and retire E1308. A "reserved" row still puts the name in the one table models read, which teaches that it exists. Removal gives the same user-facing result with less surface: `UnknownAnnotation` can carry a curated hint ("reserved for a future verifier; see the State effect"). It also removes a status value that only one name would use.

**Q4 — 4a.** Remove `@expect_panic`. Sys's 4b gives two spellings of one test, and every duplicate is a coin-flip for the model. `assert_panics` is the general form. It also composes with code after the panic, which the annotation cannot.

**Q5 — 5a.** The 3-2 vote stands. Re-opening it is out of scope for a list-consistency ticket. I note Minimalism's point (two spellings) as a fair future ticket.

**Q6 — 6a, seven targets, no Display.** On PLT's variation:
- **Accept the coherence laws** as spec text. They tell a model what a hand-written impl must satisfy, which is useful training signal.
- **Reject "Ord/Hash without Eq is an error"**:
  - Today the compiler auto-includes Eq, and the meaning is unambiguous: Eq is a supertrait, so a fn cannot have Ord without Eq.
  - An error forces a failed compile plus a retry to arrive at the same program. That is pure token cost with no new information.
  - The spec should state the auto-include once, in the derive row.

**Q7 — 7b.** Fold into `@deprecated` with a target rule for trait methods (meaning: overriding this method warns). One name, one row, one fewer thing to learn. A separate `@deprecate_override` is exactly the near-duplicate name models confuse.

**Q8:**
- `@verify`: `runtime | error | trust`. The spec wins, and "error" hard-errors until built (Q1).
- `@allow`: fn, type. The compiler already accepts type, and models will put it on types.
- `@src`: fn, type, module.
- `@trusted` needs `audit:`, and `@deprecated` takes the structured form: agree.

**Q9:**
- **9a, reject.** A "codegen effect" column is implementation detail, and the spec must not hold it. It belongs in docs/build if anywhere.
- **9b, accept.** The duplicate rule, with the repeatable set stated per row, removes an ambiguity models will otherwise guess at (two `@derive` lines? two `@verify`?).
- **9c, reject.**
  - It is YAGNI.
  - A reserved `@tool.*` prefix invites models to invent `@tool.whatever` names that then need their own error path.
  - We add the prefix when a tool needs it, by panel vote (S3).
- **9d:** status values `checked | tool-checked`. Reject `active/specified`: it encodes current compiler state, which is implementation detail and goes stale. With 3b there is no `reserved` row, so that value is not needed. The generated llms docs may still mark rows the toolchain does not yet support. That belongs in the derived doc, not the spec table.

</details>

<details><summary><b>Minimalism</b></summary>

**Minimalism: Phase B round 1**

I accept S1, S3 and S4. On S2's variation, `EffectsAnnotationRemoved` stays a separate diagnostic. The 5-1 vote already settled that, and folding it into a hint reopens the vote for no gain.

**Q1: 1b (changed from my M1 stance on @invariant only, and stated as my fallback for Q2).**
plt's split is correct. An annotation that claims a property the compiler cannot check (`@invariant`, `@verify(fallback: "error")`, `@deprecated` removal/fix) must be a hard error. Silently dropping it is the exact defect that sys named. A tool row claims nothing about the binary, so checking its shape and accepting it is sound.
- Against 1a: it turns `@perf`, `@alt` and `@src` into rows that nobody can write. A row you can never use is surface with no value, which is the worst of both options.
- Against 1c: a warning for an unchecked safety claim is silence with extra noise. Warnings get suppressed, and `@invariant` would ship with no check.

**Q2: hold 2b, but I yield to 1b if I lose.**
"Spec is blueprint" protects language semantics that the compiler has not built yet. `@perf`, `@alt` and `@src` have no language semantics: by 1b's own definition the compiler only parses them. That makes them tool configuration in grammar form, and every row added under S3 is permanent surface that needs a panel vote to remove. `@i` went into `///` 5-0 on this exact argument, and `@src` is the same case. If the panel keeps them, 1b is the correct treatment and 1a is not.

**Q3: 3a, changed.**
A reserved row costs one table line and gives a better error than `UnknownAnnotation` for a name that 14 existing uses and llms-full have already taught. Retire E1308's argument checks either way. I do not want the reserved status to grow into a general parking lot: `modifies` should be the only reserved row.

**Q4: 4a.** sys's 4b specifies a second spelling of `assert_panics`. Two forms for one job is what S3 should prevent.

**Q5: hold 5b, but it is a re-vote and I will not block on it.**
`skip()` is implemented and covers every case. `@skip` is unimplemented, so cutting it costs zero migration, and no future cut will ever be this cheap. If the panel declines to re-open the 3-2, 5a stands.

**Q6: 6a, plus both parts of plt's variation.**
The coherence laws are spec text the vote needs (Eq⇒Hash agreement, Ord agrees with Eq, serialize round-trip). Making Eq an explicit requirement, so that deriving Ord or Hash without Eq is an error, removes an implicit derive. Fewer hidden behaviours is the minimal choice. Against 6b: a listed derive that always errors is the 1a problem again.

**Q7: 7a, changed.**
I read 03_types.md:3336. `@deprecate_override` deprecates overriding, not calling, and it is the documented migration path to `final`. Folding it into `@deprecated` would add a mode field to `@deprecated`, which is no smaller. Add the row.

**Q8.**
- `@verify`: `runtime | error | trust` (spec), and `"error"` is a hard error until supported, per 1b.
- `@allow`: fn only. Widening it to type adds a target, and nobody has shown a use that needs it. Add the target when one appears.
- `@src`: moot under 2b. If it is kept: fn, type, module.
- `@trusted` needs `audit:`, and `@deprecated` uses the structured form: agree.

**Q9.**
- 9a, reject. A codegen column is implementation detail, and the spec must not carry it.
- 9b, accept. It is cheap, catches real mistakes (two `@derive` on one type), and stops future argument about repeats.
- 9c, reject. A tool namespace with deferred semantics is a reserved hole with no user, and it reopens the unknown-name gap S2 closes. Add it when a third-party tool exists.
- 9d: use the fewest values the rules need. Under 1b that is plt's three (checked / tool-checked / reserved). If 2b wins, two are enough (active / reserved). "Specified" as a status is a 1c artifact: I reject it.

Stable apart from Q2 and Q5, where I state my position and the fallback I accept.

</details>

#### Phase C — Ballot (moderator)

###### Phase C ballot (silent vote)

Option labels and attributions come from Phase A and Phase B round 1 (A_*.md, B1_*.md in this directory).

####### Facts from the codebase, for the vote
- F1. sections/03_types.md:3151, 3155: `trait Hash: Eq` and `trait Ord: Eq` (Eq is a supertrait of both).
- F2. sections/03_types.md:5070-5075 already specifies derive of a supertrait: "1. If the supertrait is already implemented (explicit `impl` or prior `@derive`), use the existing implementation. 2. If not, the compiler auto-derives the supertrait. This means `@derive(Ord)` implicitly derives `Eq` if not already present. ... Redundant listing like `@derive(Eq, Ord)` is allowed — no error, no warning."

####### Questions

**V0. Shared core (S1-S4).** S1 one normative §11.1 table, all other lists point to it or derive from it, ci check; S2 `UnknownAnnotation` error with nearest-name hint, `EffectsAnnotationRemoved` stays its own diagnostic, `UnknownAnnotation` may carry curated hints for known foreign names (web, devops, aiml in B1); S3 closed set, every row change needs a panel vote and a table edit in the same change; S4 add rows for @module, @pure, @tags, @ffi.struct, @ffi.opaque.
- Accept / Reject.

**Q1. A listed annotation the toolchain does not yet implement.**
- 1a. Accepted only when its checker (the compiler, or the named tool for @perf/@alt/@src) exists; otherwise hard error "specified, not supported by this toolchain" (sys B1, plt B1).
- 1b. Property claims the compiler cannot yet check (@invariant, @verify(fallback: "error"), @deprecated removal/fix): hard error. Tool-consumed rows (@perf, @alt, @src): target and argument-shape check, then accepted (web, devops, aiml, min in B1).
- 1c. Warning `AnnotationNotEnforced` (devops A; withdrawn in B1).

**Q2. @perf, @alt, @src.**
- 2a. Keep all three (sys, web, devops, aiml; plt for @perf/@alt).
- 2b. Cut all three (min).
- 2c. Keep @perf and @alt; cut @src into a `///` field (plt B1: "would accept cutting @src, but I do not demand it").

**Q3. @modifies.**
- 3a. Reserved row; any use is an error naming the State effect (sys, devops, min in B1).
- 3b. Removed from the table and the llms docs; any use is `UnknownAnnotation`, which may carry a curated hint (web, plt, aiml in B1).
- (Both: E1308's argument checks retire.)

**Q4. @expect_panic.**
- 4a. Remove; migrate the 29 uses to `assert_panics` (all six in B1).
- 4b. Specify it as a test annotation (sys A; withdrawn in B1).

**Q5. @skip.**
- 5a. Keep per the 3-2 decision; add a row whose text states static @skip vs dynamic skip() (sys, web, plt, devops, aiml).
- 5b. Re-open and cut @skip; skip() alone (min).

**Q6. @derive targets.** Seven: Eq, Ord, Hash, Clone, Debug, Serialize, Deserialize; Display dropped from 03_types.md and §11.1 (all six in B1). Coherence laws stated in spec text (Eq⇒Hash agreement, Ord total and agrees with Eq, Serialize/Deserialize round-trip).
- Q6 main: Accept / Reject.
- Q6-Eq sub-question (deriving Ord or Hash when Eq is not listed; see F2):
  - 6x. Keep F2 as written: auto-derive Eq when absent; use an existing impl when present (aiml B1).
  - 6y. Auto-derive Eq; error if the type also has a hand-written `Eq` impl (plt B1).
  - 6z. Error unless Eq is listed or implemented, with a fix hint "add `Eq` to this `@derive`" (sys, web, min in B1).

**Q7. @deprecate_override.**
- 7a. Its own row (devops, min in B1).
- 7b. Fold into `@deprecated` with a target rule: on a trait method it deprecates overriding (sys, plt, aiml; web conditional in B1).

**Q8. Targets and argument details.**
- Q8 bundle (all who addressed agree): @verify fallback `runtime | error | trust`; @src targets fn, type, module (if kept); @trusted requires `audit:`; @deprecated uses the structured form. Accept / Reject.
- Q8-allow: @allow targets
  - fn, type (sys, web, plt, devops, aiml in B1)
  - fn only (min)

**Q9. Extra rules.**
- 9a. "Codegen effect" column in §11.1 (sys): Accept / Reject.
- 9b. Duplicate rule: a name may not occur twice on one declaration unless its row says it may repeat: Accept / Reject.
- 9c. Reserve a `@tool.name` prefix now: Accept / Reject.
- 9d. Status column values:
  - (i) checked | tool-checked | reserved (sys, devops, min)
  - (ii) checked | tool-checked (web, aiml)
  - (iii) active | specified (plt B1)
  - You may state a conditional vote (e.g. "(i) if 3a wins, else (ii)").

####### Vote format, per question
1. Vote: option label.
2. Reasoning: 2-4 sentences anchored in your domain.
3. Concern: one sentence on what could go wrong with the option you expect to win, from your point of view.

#### Phase C — Silent vote

Tally: V0 6-0; Q1 1b 4-2 (Systems, PLT for 1a); Q2 2a 4-1-1 (Minimalism 2b, PLT 2c); Q3 3-3 (3a: Systems, DevOps, Minimalism; 3b: Web, PLT, AI/ML); Q4 6-0; Q5 5-1 (Minimalism); Q6 6-0; Q6-Eq 6y 4-1-1 (AI/ML 6x, Minimalism 6z); Q7 7b 4-2 (DevOps, Minimalism for 7a); Q8 6-0; Q8-allow 5-1 (Minimalism: fn only); 9a reject 5-1 (Systems); 9b 6-0; 9c reject 6-0.

<details><summary><b>Systems</b></summary>

###### Systems: Phase C ballot

####### V0: shared core
1. **Vote:** Accept.
2. **Reasoning:** Today an annotation that compiles and does nothing lies about the binary. One closed table plus an error for unknown names ends that, and the ci check stops the lists drifting again. Curated hints inside `UnknownAnnotation` cost nothing at runtime.
3. **Concern:** someone will hand-write the ci check against a hand-written compiler table, and the two will drift while both still pass.

####### Q1: listed annotations not yet implemented
1. **Vote:** 1a.
2. **Reasoning:** `@perf(p99: 5ms)` is a performance contract. If no `blink bench --check-contracts` exists to read it, the user believes in a bound that nothing checks. That is the same false promise as a dropped `@invariant`. A shape check proves only the spelling, not the claim.
3. **Concern:** if 1b wins, `@perf` and `@alt` will spread through code and llms training data for years before their tools exist, and every one of those uses is an unchecked claim.

####### Q2: @perf, @alt, @src
1. **Vote:** 2a.
2. **Reasoning:** Cutting specified features is a design change that needs its own ticket, not a consistency fix. None of the three affects codegen, so keeping them costs nothing in the binary, provided Q1 stops silent acceptance.
3. **Concern:** if 1b wins, keeping all three means three permanent rows that do nothing.

####### Q3: @modifies
1. **Vote:** 3a.
2. **Reasoning:** An error that names the State effect sends the user to the right mechanism in one step. A generic "unknown" message leaves them guessing. Either option kills E1308's silent acceptance, which is the part I care about.
3. **Concern:** a reserved row tempts someone to "just implement" it later without a panel vote.

####### Q4: @expect_panic
1. **Vote:** 4a.
2. **Reasoning:** An annotation that rewrites a body hides the code it generates. `assert_panics` is an expression that a reader can see, scope and nest.
3. **Concern:** a 29-use migration done carelessly could change which statements sit inside the panic scope. Each test must stay as narrow as it is now.

####### Q5: @skip
1. **Vote:** 5a.
2. **Reasoning:** The 3-2 vote stands, and the cost is test-harness only. Static `@skip` lets the runner skip a test without compiling its body, while `skip()` decides at run time. The row must state that difference.
3. **Concern:** none from my seat.

####### Q6: @derive targets
- **Q6 main:**
  1. **Vote:** Accept.
  2. **Reasoning:** Each derive emits one monomorphic function with a structure the compiler can predict. Display has no such structure.
  3. **Concern:** the round-trip law for Serialize/Deserialize needs care with floats (NaN) and lossy formats. The spec must define equality there.
- **Q6-Eq sub-question:**
  1. **Vote:** 6y. This changes my B1 vote of 6z.
  2. **Reasoning:** F2 already specifies the auto-derive, so overturning it is out of scope. The real hole is a hand-written Eq next to a derived Hash or Ord, because that silently breaks Map and Set lookup at run time. 6y closes exactly that hole. 6z does not close it, because it accepts any existing Eq impl.
  3. **Concern:** 6y blocks a hand-written Eq that is in fact structural. The fix hint must say "derive Eq, or implement Hash by hand".

####### Q7: @deprecate_override
1. **Vote:** 7b.
2. **Reasoning:** This gives one deprecation annotation with a target rule and no extra name. W0731 keeps its behavior.
3. **Concern:** the target rule must be unambiguous: it applies to trait methods that have a default body, not to a deprecation of the method itself.

####### Q8: targets and argument details
- **Q8 bundle:**
  1. **Vote:** Accept.
  2. **Reasoning:** These values match the decided forms. `fallback: "error"` is the only option that guarantees no runtime check gets silently dropped.
  3. **Concern:** none.
- **Q8-allow:**
  1. **Vote:** fn, type.
  2. **Reasoning:** Warnings fire on type declarations too, such as derive or layout warnings. Allowing fn only forces users to suppress at module scope, which is wider than they need.
  3. **Concern:** none.

####### Q9: extra rules
- **9a: codegen-effect column**
  1. **Vote:** Accept.
  2. **Reasoning:** A reader must see from the table which annotations put code or layout changes in the binary.
  3. **Concern:** if this is rejected, the Meaning column must still say it in words.
- **9b: duplicate rule**
  1. **Vote:** Accept.
  2. **Reasoning:** It closes another silent case. Two `@capabilities` or two `@ffi` on one declaration have no defined meaning.
  3. **Concern:** none.
- **9c: reserved `@tool.name` prefix**
  1. **Vote:** Reject.
  2. **Reasoning:** YAGNI. Unknown names already error, so adding a namespace later breaks nothing.
  3. **Concern:** none.
- **9d: status column values**
  1. **Vote:** (i) if 3a wins, else (ii). Never (iii).
  2. **Reasoning:** Values like "specified" describe what a compiler has built, and the spec must not hold implementation state. That belongs in the diagnostic and the generated llms docs.
  3. **Concern:** "tool-checked" is only honest if Q1 resolves to 1a.

</details>

<details><summary><b>Web/Scripting</b></summary>

###### Web/Scripting — Phase C ballot

**V0. Accept.**
Reasoning: one list, a loud error on typos, and curated hints for `@inline`, `@override` and `@test` cover the 90% case for humans and models. These are the must-haves.
Concern: curated hints could grow into a second, unmaintained list; keep them in the same table or file as the rows.

**Q1. 1b.**
Reasoning: a dropped safety claim (`@invariant`) must stop the build. Metadata that only a tool reads (`@src`) should not punish users who follow our own docs. A shape check keeps typos loud.
Concern: users may read an accepted `@perf` as "checked on build"; the table row must say plainly that only `blink bench` checks it.

**Q2. 2a.**
Reasoning: "metadata about a function goes on the function" is what every Python and TS dev expects. A magic `/// src:` field is a second hidden syntax that generates questions.
Concern: three rows with no shipped tool become dead weight if `blink trace`, `alt` or `bench` never ship.

**Q3. 3b.**
Reasoning: a `reserved` row in the one list everyone learns from invites "how do I use @modifies?". A curated `UnknownAnnotation` hint that points to the State effect gives the same help without advertising the name.
Concern: if 3a wins, the row text must say clearly "not usable" so the list does not mislead.

**Q4. 4a.**
Reasoning: one way to test a panic. `assert_panics` is specified and composes better.
Concern: the 29-use migration must land before the name turns into an error, or the corpus breaks.

**Q5. 5a.**
Reasoning: `@skip` is the most familiar test annotation in every ecosystem (pytest, Jest, JUnit), and it was decided 3-2. Stating static vs dynamic in the row answers the obvious "which one?" question.
Concern: without that row text, two skip forms will generate exactly the confusion min predicts.

**Q6 main. Accept.**
Reasoning: no derived Display, which matches Rust and avoids the "Debug or Display?" trap. The laws make the derived behavior predictable.
Concern: users from Python dataclasses will try `@derive(Display)`; the error must say "derive Debug or write `impl Display`".

**Q6-Eq. 6y** (I change from 6z after F2).
Reasoning: F2 already specifies auto-derive, and in the common case that "just works": `@derive(Hash)` should not fail on a missing word. The real trap is a hand-written Eq next to a derived Hash, which silently breaks Map. 6y errors in exactly that case and nowhere else.
Concern: the 6y error message must tell the user to write Hash/Ord by hand to agree with their Eq, not just "conflict".

**Q7. 7b.**
Reasoning: one deprecation annotation; the target (trait method) decides the meaning. That is one fewer name to learn.
Concern: "deprecates overriding" vs "deprecates calling" on a trait method must be stated without ambiguity, or users will guess wrong.

**Q8 bundle. Accept.**
Reasoning: the decided forms win, and the spec leads with the docs regenerated to match.
Concern: `@verify(fallback: "error")` errors under 1b until it is implemented; docs must flag it.

**Q8-allow. fn, type.**
Reasoning: suppressing a warning across a whole type is the common case in impl-heavy code; fn-only forces repetition.
Concern: none significant.

**Q9a. Reject.** Codegen detail does not belong in the spec. The Meaning column can say "adds a runtime check" in words.
Concern: none.

**Q9b. Accept.** `@pure @pure` should be an error. The repeatable rows are obvious.
Concern: the repeat list must be in the table, not in prose elsewhere.

**Q9c. Reject.** A prefix with no semantics invites "how do I make my own?" and weakens S3 (YAGNI).
Concern: none.

**Q9d. (ii) if 3b wins; (i) if 3a wins.** "Not yet implemented" describes the compiler, not the language, so it does not belong in a spec column (that rules out iii).
Concern: without any status column for implementation state, `blink llms` must still say clearly which rows the current compiler rejects.

</details>

<details><summary><b>PLT</b></summary>

###### PLT ballot: Phase C

**V0. Shared core (S1 to S4)**
1. Vote: Accept.
2. Reasoning: Annotations claim to be "compiler-checked." That is true only if the set is closed and every name has a checked meaning. One table, one error for an unknown name, and a closed set together make the spec's claim true.
3. Concern: The ci check might compare only names. It must also compare target sorts and argument grammar.

**Q1**
1. Vote: 1a.
2. Reasoning: `@perf(p99 < 5ms)` states a property in the same way `@invariant` does. A claim that no checker enforces is unsound, whether the missing checker is the compiler or a tool. 1a gives one uniform rule: a row is active only when its checker exists.
3. Concern: Under 1b, users and LLMs will write `@perf` and `@alt` and believe a tool enforces them, when nothing does.

**Q2**
1. Vote: 2c.
2. Reasoning: `@perf` states a bound and `@alt` states an equivalence, so both are semantic claims that belong next to the contracts. `@src` claims no property; it is provenance. The 5-0 `@i` precedent puts provenance in `///`.
3. Concern: If 2a wins, `@src` stays a row with no checkable meaning. That weakens the rule "an annotation is a checked claim."

**Q3**
1. Vote: 3b.
2. Reasoning: A reserved row puts a feature that does not exist into the normative table and into the llms docs. In practice it behaves like `UnknownAnnotation` anyway. Bringing it back needs a vote either way, and removing it drops a third status value.
3. Concern: The `UnknownAnnotation` hint for `@modifies` must name the State effect, or users lose the migration path.

**Q4**
1. Vote: 4a.
2. Reasoning: A body-rewriting annotation is a macro that does not compose. The expression form `assert_panics` can be scoped, nested and repeated.
3. Concern: The migration must keep the span and message behaviour that E0832 tests lock in today.

**Q5**
1. Vote: 5a.
2. Reasoning: `@skip` is static and unconditional, so tools can list skipped tests without running them. `skip()` is dynamic and can depend on a condition. These are two different meanings, not two syntaxes for one meaning.
3. Concern: If the row does not state this static/dynamic difference, the two will look redundant and the vote will be reopened.

**Q6 main**
1. Vote: Accept.
2. Reasoning: A derivation is sound only if the structure alone fixes it. Display has no canonical structural form. The stated laws are what make derived instances safe to use as Map and Set keys.
3. Concern: The laws must be normative ("a derived instance satisfies..."), not a passing remark.

**Q6-Eq**
1. Vote: 6y.
2. Reasoning: The real hazard is a structural Hash or Ord paired with a hand-written Eq, which is usually coarser. That breaks a == b ⇒ hash(a) == hash(b), and silently corrupts Map. F2 rule 1 and 6z both permit exactly that pairing. 6y forbids it and keeps the convenient auto-derive.
3. Concern: Under 6x or 6z, the coherence law becomes an obligation on the user that nothing checks. That is the same unchecked-claim defect this ticket fixes.

**Q7**
1. Vote: 7b.
2. Reasoning: One annotation whose meaning depends on the target sort is compositional. A separate name for "deprecated, but on an override" adds a row with no new concept.
3. Concern: The target rule must define what happens when the trait method itself is deprecated, as opposed to deprecating overrides of it.

**Q8 bundle**
1. Vote: Accept.
2. Reasoning: `error` as a `@verify` fallback is meaningful: it says "a static proof is required." Under Q1 it is an error until a prover exists. Requiring `audit:` keeps `@trusted` a recorded claim.
3. Concern: None significant.

**Q8-allow**
1. Vote: fn, type.
2. Reasoning: One scope rule across declaration sorts is simpler than a special case for fn only. The scope of a type-level allow is obvious: the type's declaration and its body.
3. Concern: The table must say whether a type-level allow reaches into impl blocks declared elsewhere. I say it must not.

**Q9a**
1. Vote: Reject.
2. Reasoning: Lowering is an implementation detail and belongs in docs/build. The meaning column already says when an annotation adds a runtime check.
3. Concern: None.

**Q9b**
1. Vote: Accept.
2. Reasoning: Without the rule, repeating an annotation has an implicit meaning for some names (conjunction for `requires`) and no meaning for others (`@module` twice). The table must define it.
3. Concern: Each repeatable row must state its combining meaning (conjunction, union), not just "may repeat."

**Q9c**
1. Vote: Reject.
2. Reasoning: A reserved prefix with no semantics is the same mistake as a reserved `@modifies`. When a tool needs it, it brings a ticket.
3. Concern: None.

**Q9d**
1. Vote: (iii) active | specified, where `specified` means an error until its checker exists. Conditional: if 1b wins, vote (ii). If 3a wins, vote (i).
2. Reasoning: With 1a and 3b, a row is either enforced or rejected. Two states express that exactly, and "tool-checked" becomes "active once its tool exists."
3. Concern: The status labels must describe this toolchain only. The spec text of a `specified` row must still read as the normative meaning.

</details>

<details><summary><b>DevOps</b></summary>

###### DevOps/Tooling — Phase C ballot

**V0. Accept.**
Reasoning: one table drives the error, LSP completion, hover, `blink fmt` order and the llms docs. The ci check is what keeps that true. `UnknownAnnotation` with curated foreign-name hints turns today's silent no-op into a fix in one step.
Concern: the ci check may compare names only and miss targets or argument shapes, so drift comes back one column lower.

**Q1. 1b.**
Reasoning: a property claim that nothing checks must stop the build. A warning or silent acceptance ships a binary without the check the user wrote. Tool-consumed rows still get a real diagnostic surface (target and shape errors at `blink check` and in the LSP) without waiting for a separate tool to ship. 1a makes code that is correct per spec fail for reasons outside the compiler's job.
Concern: "shape check" may be implemented loosely, for example accepting any arguments, and so turn into a silent no-op again.

**Q2. 2a.**
Reasoning: a checked annotation shape is better for tooling than a free-text `///` field. `/// scr: X` compiles silently, cannot be completed and cannot be ordered. Keeping all three keeps the claim on the declaration it describes, where hover shows it.
Concern: the tools (`blink bench`, `blink alt`, `blink trace`) may never ship, so the rows stay accepted and inert for a long time.

**Q3. 3a.**
Reasoning: a reserved row gives one exact message that points to the State effect. `UnknownAnnotation` would give an edit-distance hint that has no meaning for this name. The generated llms docs should show reserved names only in a "do not use" line.
Concern: a reserved row can look like a promise of a future feature, so the docs must say plainly that nothing has been decided.

**Q4. 4a.**
Reasoning: an annotation that rewrites a body puts failure spans on desugared nodes and breaks "go to definition". `assert_panics` puts the span on the real call, and it leaves one way to do the job.
Concern: the 29-use migration must follow the 3-step protocol, or the self-host build breaks part way through.

**Q5. 5a.**
Reasoning: the 3-2 vote stands, and nobody gave new evidence to re-open it. The row text that separates static `@skip` from dynamic `skip()` gives the LSP and the test runner a clear rule, and the runner reports both with a reason.
Concern: users and LLMs may still mix up the two forms unless both the row text and the runner output say which form applies.

**Q6 main. Accept.**
Reasoning: `@derive(Display)` gets E1402 with a help line pointing to a hand-written impl or `@derive(Debug)`. The docs stop listing a target that always errors.
Concern: none in my domain beyond making sure the E1402 help line names the fix.

**Q6-Eq. 6y.**
Reasoning: the real hazard is a hand-written `Eq` next to a derived `Hash`, which silently breaks Map lookups. Only 6y turns that into a compile error. 6z still accepts that case because Eq is "implemented". 6y keeps F2's ergonomic auto-derive and redundancy rule, and the error help can say "derive `Eq` as well, or implement `Hash` by hand".
Concern: 6y may reject a hand-written Eq that is in fact structural, so the error must explain why and give both fixes.

**Q7. 7a.**
Reasoning: deprecating a call and deprecating an override fire at different sites (the call site vs the impl site). Two names give two clear messages and two clear hover texts. Folding both into `@deprecated` on a trait method makes the reader, and the LSP, guess which meaning applies.
Concern: under 7b, `@deprecated` on a trait default method can no longer deprecate calls, and users will not expect that.

**Q8 bundle. Accept.**
Reasoning: each item follows the decided or spec form, and one value set per annotation makes completion and error messages exact.
Concern: `@verify(fallback: "error")` must get the Q1 hard error until it is supported, not silent acceptance.

**Q8-allow. fn, type.**
Reasoning: warnings in derived code and in type-level code need a place to be suppressed that sits close to their source. Without one, users fall back to a module-wide `[lints]` setting, which is too broad.
Concern: precedence between a type-level `@allow` and a method-level one inside it needs one stated rule.

**Q9a. Reject.**
Reasoning: lowering detail must not appear in spec text. It belongs in docs/build/.
Concern: none.

**Q9b. Accept.**
Reasoning: a precise "`@pure` appears twice" error is better than silently accepting the second one, and the table decides which rows may repeat.
Concern: the repeat flag must be set on every row that needs it, `@tags` included if it may repeat.

**Q9c. Reject.**
Reasoning: YAGNI. I withdrew it.
Concern: none.

**Q9d. (i) if 3a wins, else (ii).**
Reasoning: whether something is implemented is compiler state, not spec state. The status column only has to say who checks the row, plus a reserved status if reserved rows exist.
Concern: none.

</details>

<details><summary><b>AI/ML</b></summary>

###### AI/ML — Phase C ballot

**V0. Accept.**
Reasoning: one generated table plus an error for unknown names is the single largest accuracy gain for code generation. Silent acceptance of `@inline`/`@json` teaches models that the code was correct. Curated hints for known foreign names turn the most common hallucinations into one-shot repairs.
Concern: if the llms-doc table is not generated from §11.1 (only checked by hand), drift returns and models learn the drift.

**Q1. 1b.**
Reasoning: the model-safety harm is a property claim the compiler silently drops, and 1b hard-errors exactly those. @src is metadata, and @perf/@alt are tool claims that the "tool-checked" status already labels. Accepting them after a shape check lets models write what the spec wants without a compile failure.
Concern: if `blink bench`/`blink alt` never ship, @perf/@alt become long-lived annotations that do nothing. The llms docs must flag that the tool does not exist yet.

**Q2. 2a.**
Reasoning: co-locating the contract with the fn is easier to generate and keep in sync than a separate bench file or manifest. Moving @src into `///` needs a structured doc-field syntax that does not exist yet. That belongs in its own ticket.
Concern: three tool-checked rows with no tool make the "every annotation is checked" claim look hollow.

**Q3. 3b.**
Reasoning: a reserved row still puts `@modifies` in the one table models read, which teaches that the name is usable. Removal plus a curated hint in `UnknownAnnotation` gives the user the same message with less surface, and it removes a status value that only one name needs.
Concern: if 3a wins, the generated llms docs must leave out the reserved row, or models will emit `@modifies`.

**Q4. 4a.**
Reasoning: two spellings of one test is a coin-flip decision point. `assert_panics` is the general form and composes with code after the panic.
Concern: the 29-use migration must keep each test's message-substring check, or coverage silently drops.

**Q5. 5a.**
Reasoning: the 3-2 vote stands, and this ticket is about list consistency, not relitigating. A row text that states "static @skip vs dynamic skip()" gives models a clear rule for which spelling to pick.
Concern: two skip spellings stay a decision point. If models split between them at random, revisit in a later ticket.

**Q6 main. Accept.**
Reasoning: seven targets match the compiler, the spec and model priors (Rust has no derive Display). The coherence laws tell a model what a hand-written impl must satisfy.
Concern: the laws must stay prose rules for implementers; if they turn into compiler checks, that scope belongs on its own ticket.

**Q6-Eq. 6x.**
Reasoning: F2 already specifies this, and it is unambiguous because Eq is a supertrait. 6z forces a failed compile plus a retry to reach the identical program, which is pure token cost with no new information. Models often write `@derive(Ord, Hash)`, and erroring on it buys nothing.
Concern: a type with a hand-written Eq plus derived Hash can break Eq⇒Hash agreement. The coherence-law text must say the user owns that, or 6y's check is needed.

**Q7. 7b.**
Reasoning: one name with a target rule is less to learn than a near-duplicate name. Models will confuse `@deprecated` and `@deprecate_override` and use one where the other belongs.
Concern: the target rule must say clearly whether `@deprecated` on a trait method deprecates calling it, overriding it, or both. Otherwise the folded name becomes ambiguous.

**Q8 bundle. Accept.**
Reasoning: one value set for each argument removes guesswork. The spec wins where the docs disagreed.
Concern: `@verify(fallback: "error")` must hard-error until built (Q1), not fall back silently.

**Q8-allow. fn, type.**
Reasoning: the compiler already accepts type, and models will put `@allow` on types by analogy with Rust's `#[allow]`. Rejecting it would be a needless failure.
Concern: none of note.

**Q9a. Reject.**
Reasoning: a codegen-effect column is implementation detail, which the spec must not contain. Put it in docs/build.
Concern: n/a.

**Q9b. Accept.**
Reasoning: the duplicate rule removes ambiguity models would otherwise guess at (two `@derive` lines? two `@verify`?). Repeatable rows are stated per row.
Concern: `@derive` split across two lines may appear in existing code; check the corpus before making it an error.

**Q9c. Reject.**
Reasoning: YAGNI. A reserved `@tool.*` prefix invites models to invent names under it. Add it by panel vote when a real tool needs it.
Concern: n/a.

**Q9d. (ii) checked | tool-checked; (i) if 3a wins.**
Reasoning: (iii) encodes current compiler state, which is implementation detail and goes stale. "reserved" is needed only if `@modifies` keeps a row.
Concern: the generated llms docs need their own "not yet available" marker, and it must come from the compiler/tool state, not the spec table.

</details>

<details><summary><b>Minimalism</b></summary>

###### Phase C ballot: Minimalism

**V0. Shared core (S1-S4)**
1. Vote: Accept.
2. Reasoning: One table and an error for unknown names give the set a boundary. Without that boundary, any list we merge drifts again. The closed set with a vote for each row is the main subtraction tool of this decision.
3. Concern: The curated hints in `UnknownAnnotation` for foreign names (`@inline`, `@override`, and so on) can grow into a second, informal list. Keep that list short and outside the spec table.

**Q1**
1. Vote: 1b.
2. Reasoning: The compiler cannot silently drop a property claim, so that claim must be a hard error until the compiler can check it. A tool row claims nothing about the binary, so a shape check is sound. Under 1a, a row stays unusable until its tool ships, which is surface with no value.
3. Concern: People will read "tool-checked" as "checked". The table text must state that the compiler gives no guarantee for those rows.

**Q2**
1. Vote: 2b.
2. Reasoning: Under 1b the compiler only parses these three, so they are tool configuration written as grammar. Each one becomes permanent language surface that needs a vote to remove. `@i` went into `///` 5-0 on this argument. I prefer 2c to 2a: `@src` is the clearest case for a doc-comment field.
3. Concern: If 2a wins, `blink bench`, `blink alt` and `blink trace` stay unbuilt, and three rows teach LLMs annotations that do nothing for years.

**Q3**
1. Vote: 3a.
2. Reasoning: Fourteen existing uses and llms-full have already taught this name. A reserved row costs one line and gives an exact error that points to the State effect. It must be the only reserved row.
3. Concern: Once one reserved row exists, every abandoned idea will want one too. Hold the line at `modifies`.

**Q4**
1. Vote: 4a.
2. Reasoning: `assert_panics` is specified and does the same job. A second spelling for one job is what S3 exists to stop.
3. Concern: None of note. The migration is mechanical, and the compiler is the only user.

**Q5**
1. Vote: 5b.
2. Reasoning: `skip()` is implemented and covers the static case: call it at the top of the test. `@skip` has zero uses, so this is the cheapest cut we will ever get. After it ships, removing it needs an edition.
3. Concern: If 5a wins, the row text must give one rule for when to use each form. Otherwise users and LLMs will pick at random.

**Q6 main**
1. Vote: Accept.
2. Reasoning: A derived Display would force a user-facing format that is really a design choice, and Debug covers the mechanical rendering. The coherence laws are short spec text that gives each derive a meaning.
3. Concern: Without a conformance test, the round-trip law is only words. Add a test with the row.

**Q6-Eq**
1. Vote: 6z.
2. Reasoning: F2 is an implicit derive with two branches, and redundant listing is allowed, so the same thing has two spellings. 6z keeps one rule: list what you derive. The fix hint makes the error cost one edit. For an AI-first language, the explicit form is also the one models copy correctly.
3. Concern: 6z changes text in 03_types.md that already exists, and existing `@derive(Ord)` uses break. The fix hint must be applicable by a machine.

**Q7**
1. Vote: 7a.
2. Reasoning: Deprecating a call and deprecating an override are different acts. With 7b, `@deprecated` on a trait method would have to mean one of them, and the other would need a new field or no spelling at all. One name for each meaning is smaller than one name with a meaning that depends on the target.
3. Concern: If 7b wins, nothing can express "deprecate calling this trait default" unless someone adds a mode field later. That field is the surface 7b claimed to save.

**Q8 bundle**
1. Vote: Accept.
2. Reasoning: These match the spec and remove the conflicts between lists. Under 1b, `"error"` is a hard error until it is supported.
3. Concern: The `@src` targets get specified for a row I would cut, which is harmless if it is cut.

**Q8-allow**
1. Vote: fn only.
2. Reasoning: Nobody showed a warning that needs suppression on a type. Add the target when a real case appears.
3. Concern: If the vote is fn, type, the spec must define the scope on a type: the fields only, or every method in every impl.

**Q9a**
1. Vote: Reject.
2. Reasoning: A codegen column is implementation detail, and the spec must not carry it.
3. Concern: None.

**Q9b**
1. Vote: Accept.
2. Reasoning: It costs one rule and catches real mistakes, for example two `@derive` lines on one type. It also ends arguments about repeats.
3. Concern: Each row must state whether it repeats, or the rule is ambiguous for new rows.

**Q9c**
1. Vote: Reject.
2. Reasoning: A namespace with deferred semantics has no user, and it opens a hole in the unknown-name boundary that S2 closes.
3. Concern: None.

**Q9d**
1. Vote: (i) if 3a wins, else (ii). If 2b wins, drop "tool-checked" from whichever option applies.
2. Reasoning: Use the fewest status values that the winning rules need.
3. Concern: (iii) "specified" brings back the silent-acceptance state that Q1 rejected.

</details>

#### Phase D — Round 1 (focused debate on Q1, Q2, Q3, Q6-Eq, Q7)

<details><summary><b>Systems</b></summary>

###### Systems: Phase D round 1

####### Q1: I hold 1a
Min says a tool row "claims nothing about the binary". `@perf(p99: 5ms)` is a claim about the binary: how fast it runs. That is the one property my seat cares about most. DevOps says 1a fails correct code "for reasons outside the compiler's job". But the rule is about the toolchain, and `blink bench` ships in the same binary as `blink build`. If that toolchain cannot check the claim, it should not take the claim.

I agree with min and aiml that `@src` is different. It is provenance and claims no property. I would accept a split: `@src` gets a shape check and is accepted, while `@perf` and `@alt` are an error until their tool exists. Every other panelist's concern on 1b is the same as mine: "nothing checks it for years". 1a is the only option that removes that concern, not just documents it.

####### Q2: I hold 2a, and 2c is a fine second choice
Cutting features is a design change, not a consistency fix. PLT's reason for 2c is sound: `@src` is provenance, and the `@i` precedent covers it. AIML's objection also holds, though: no structured `///` field syntax exists yet, so 2c needs a follow-up ticket before anyone can migrate. If 2c wins, I have no cost objection. Neither option touches codegen.

####### Q3: I hold 3a
3b does not remove the name. It moves it into a curated hint list inside `UnknownAnnotation`. Min and web both warned that this hint list could grow into a second, unmaintained list, and that is this ticket's exact defect. A reserved row keeps every name the compiler knows in the one table that ci checks.

AIML worries that models will learn the name. The generated llms docs can list reserved rows only on a "do not use" line, or leave them out; that is a doc generator rule. `EffectsAnnotationRemoved` already shows that retired names want an exact message. A `reserved` status gives that through the table instead of one bespoke diagnostic per name. Min's guard, "the only reserved row", is fine with me.

####### Q6-Eq: I hold 6y
AIML: 6y does not error on `@derive(Ord, Hash)`. It auto-derives Eq exactly as F2 says. It errors only when a hand-written Eq sits next to a derived Hash or Ord, and that pairing silently corrupts Map and Set lookups at run time. AIML's own concern names that case and says "or 6y's check is needed".

Min: 6z adds an edit for every `@derive(Ord)` and still accepts the dangerous pairing, because Eq is "implemented". 6z costs more and protects less. The "one spelling" point is fair, but F2's redundancy rule is already decided text.

####### Q7: I change to 7a
DevOps and min are right, and I missed this. Deprecating a call fires at the call site. Deprecating an override fires at the impl site. With 7b, `@deprecated` on a trait default method must pick one meaning, and the other then needs a mode field, which is the extra surface 7b claimed to save. "Deprecate calls but keep overrides working" and "keep calls but stop overrides" are both real migrations. Two meanings at two sites take two names. The cost is one row.

</details>

<details><summary><b>Web/Scripting</b></summary>

###### Web/Scripting — Phase D step 1

**Q1: I move to 1a.**
Sys and plt are right, and by my own Phase A test. A dev writes `@perf(p99 < 200ms)`, the build passes, and they assume something checks it. That is the silent no-op I opened this panel against. A row label "tool-checked" doesn't fix it, because nobody reads the table before writing code. They read the compiler's answer. Under 1b the answer for `@perf` is "fine". Under 1a it is "not supported by this toolchain yet", which is honest and ends the search in five seconds. My earlier worry was that 1a punishes users who follow our docs. That only holds if the docs advertise rows with no tool, and the generated llms docs must not. The cost is two `@src` uses in tests. 1a also gives one rule to teach ("a row works when its checker exists"), where 1b gives two.

**Q2: 2a (unchanged).**
Under 1a, keeping a row with no tool costs nothing: it errors honestly until the tool ships. To min: cutting specified features is a design change, not list merging, and the `///` replacements (structured doc fields, a `[bench]` section) do not exist yet. To plt on `@src`: I agree it is the weakest row, but moving it needs structured `///` field syntax first. That is its own ticket, so it should not ride along here.

**Q3: 3b (unchanged, low stakes).**
Devops says a plain edit-distance hint means nothing for `@modifies`. True, but S2 already allows curated hints, and the `@modifies` hint names the State effect. Users get the same message with no row. Min's own concern ("hold the line at one reserved row") is exactly why I won't open the reserved status at all. I can live with 3a only if the generated llms docs leave the row out.

**Q6-Eq: 6y (unchanged).**
To aiml: 6y keeps F2's auto-derive. `@derive(Ord, Hash)` compiles with no retry, so the token cost you cite appears only in the hazard case, where it pays for itself. To min: 6z does not close the hazard. It accepts a hand-written Eq next to a derived Hash, which is the pairing that silently corrupts Map. Explicit listing is a style rule. Coherence is a correctness rule, and correctness wins.

**Q7: I move to 7a.**
Devops and min convinced me, and 03_types.md:3329-3334 confirms it. `@deprecate_override` is a migration hop toward `final`: it fires at impl sites, not call sites. A dev who reads `@deprecated` on a trait method will think "don't call this", which is what every language means by it. Folding the two makes that common reading wrong, and it leaves no way to deprecate calling a trait default. Two names, each meaning one thing, is the 5-second-readable choice. `@deprecate_override` says what it does on the label.

</details>

<details><summary><b>PLT</b></summary>

###### PLT: Phase D round 1

**Q1: hold 1a.**
min says that a tool row "claims nothing about the binary." That is true of `@src`. It is false of `@perf(p99 < 5ms)`, which bounds how the binary behaves, and of `@alt`, which states that two functions are equivalent. All four 1b voters name the same concern: users will read an accepted `@perf` as checked. When every supporter of an option names the same failure, that is the defect, and docs do not fix it. devops says 1a fails correct code "for reasons outside the compiler's job." But the error comes from the toolchain, it is temporary, and it is exactly the E1402 pattern we already use for `@derive(Display)`. If 1b wins, I ask that the row text say "the compiler does not check this", not "tool-checked."

**Q2: change to 2a.**
aiml is right: 2c needs a structured `///` field syntax that does not exist yet. A cut that needs new surface is not a cut. `@src` claims no property, so it is harmless under any Q1 outcome. Moving provenance into `///` can come back as its own ticket once doc-comment fields exist.

**Q3: hold 3b, and accept 3a with conditions.**
The case for 3a is "one exact message that points to the State effect." The curated hints in `UnknownAnnotation`, which V0 already accepted 6-0, give exactly that message without a table row. So the one advantage of 3a is already in place. A reserved row also adds a third status that only one name uses, and it puts the name in the table that models read. min's point about 14 existing uses is a reason for the curated hint, not for a row. If the vote stays tied, I can accept 3a only on two conditions: the llms docs never list the reserved row, and min's limit holds, so `modifies` is the only reserved row.

**Q6-Eq: hold 6y.**
min wants an explicit `Eq`. But 6z still accepts the dangerous program: a hand-written, coarser `Eq` next to a derived `Hash`, because Eq "is implemented". So 6z costs an edit and still leaves the Map hole open. aiml's own concern grants that this case needs 6y's check, or else the user carries a law that nothing enforces. devops's concern has a cheap answer. If a hand-written Eq is in fact structural, the fix is to delete it and derive Eq, which is a one-step change with no loss.

**Q7: change to 7a.**
devops and min are right, and my "compositional" argument was wrong. A meaning that depends on the target is clean only when the target sorts differ. Here both meanings apply to the same sort, the trait method: "calling this is deprecated" and "overriding this is deprecated." So 7b must either pick one meaning and lose the other, or add a mode field, which is the surface it claimed to save. Two names keep both meanings, each with its own use site (the call vs the impl) and its own diagnostic.

</details>

<details><summary><b>DevOps</b></summary>

###### DevOps/Tooling — Phase D step 1

**Q1 — hold 1b.**
To sys and plt: under 1b, a tool-checked `@perf` makes no claim that the compiler enforces it. The row and the hover text say "checked by `blink bench`". Under 1a, code written exactly as the spec says fails with "not supported by this toolchain". For an AI-first language that is the worst signal: the model follows the docs and gets punished. A model then learns to avoid the spec'd form. 1a also ties a compile error to whether a separate binary is installed or shipped, which makes `blink check` output depend on things outside the compiler. I accept plt's concern as a doc obligation: the llms docs and hover must say "no checker ships yet" for each tool-checked row until one does.

**Q2 — hold 2a.**
To plt and min (`@src` into `///`): no structured `///` field syntax exists. Adding one is new grammar that needs its own vote, so 2c does not reduce surface. It moves the surface into comments, where typos compile silently and the LSP cannot complete. `@i` folded into `///` because it was prose. `@src` is a key-value reference that a tool must parse, which is exactly what a checked annotation shape is for. I agree with min's concern that these rows can rot. The answer is a ticket per tool, not a cut.

**Q3 — I change to 3b.**
My 3a reason was that `UnknownAnnotation` would give a meaningless edit-distance hint. S2 now includes curated hints, so `@modifies` can get "removed; write effects go through the State effect" inside `UnknownAnnotation`. That is the same diagnostic text with no reserved row, no third status value, and nothing in the table that LLMs read as usable. web, plt and aiml are right that a row in the one normative table advertises the name. Condition: the curated hint for `@modifies` is required, not optional.

**Q6-Eq — hold 6y.**
To aiml (6x): agreed that 6z is a pointless retry loop. But 6x leaves the one real hazard (hand-written Eq plus derived Hash) unchecked, and an unchecked coherence law is the defect this ticket removes. 6y costs nothing in the common case: `@derive(Ord, Hash)` still compiles. To min (6z): 6z breaks the existing F2 text and still accepts that hazard. The 6y error must give both fixes: "derive `Eq`, or implement `Hash` by hand to agree with your `Eq`".

**Q7 — hold 7a, with a fallback.**
Every 7b voter's concern is the same ambiguity: on a trait method, does `@deprecated` deprecate calling or overriding? That ambiguity shows up in diagnostics. W0731 fires at the impl site, a call deprecation fires at the call site, and the hover cannot say which one applies without guessing. 7b also leaves "deprecate calling a trait default" with no spelling. If the panel still prefers one name, I would accept an explicit field (`@deprecated(override: ...)`) over a meaning that depends on the target: the shape check and the LSP can see a field, but they cannot see an intent.

</details>

<details><summary><b>AI/ML</b></summary>

###### AI/ML — Phase D step 1

**Q1: I move from 1b to 1a.**
Sys and PLT's concern is squarely my domain, and I under-weighted it. Under 1b, `@perf` and `@alt` compile, so they spread through user code and then into training data, and models learn to write a contract no tool reads. That is the same harm P3 targeted for `@invariant`: a claim that looks enforced and is not.

Devops says 1a fails code that is correct per spec. It fails it with an exact message ("specified, not supported by this toolchain"), which is a one-step repair and teaches the truth. Min's "surface with no value" point argues for 2b, not for accepting silently. Web's and min's mitigation (row text says "the compiler gives no guarantee") does not reach a model that only sees the code compile.

One uniform rule, "a row is usable when its checker exists", is also simpler to learn than a two-class rule.

**Q2: stay 2a.**
PLT's 2c is coherent (provenance is not a claim). But devops is right that a `///` field is free text: it is unchecked, it cannot be completed, and a typo in it is silent. With 1a, `@src` errors until `blink trace` exists, so it is not a hollow row either. I do not oppose 2c strongly.

**Q3: stay 3b, but the two options are close to equivalent.**
Min's point is real: 14 uses plus llms-full have already taught the name, so models will emit it. Both options must therefore return one exact message naming the State effect. Devops is right that edit-distance alone is meaningless for this name, so under 3b the curated hint is required, not optional.

Given that, the only difference is whether the name appears in the table that models read. I still prefer that it does not. If 3a wins, the generated llms docs must leave out the row, or show it only in a "do not use" line, as devops proposes.

**Q6-Eq: I move from 6x to 6y.**
My own Phase C concern was exactly the hand-written Eq plus derived Hash case. PLT, web and devops showed that F2 rule 1 lets that case corrupt Map silently. 6y errors only there and keeps the auto-derive that makes `@derive(Ord, Hash)` succeed on the first try.

Against min's 6z: the common case (`@derive(Hash)` with no Eq at all) is not a hazard. Failing it costs a retry for no new information. The 6y error must offer both fixes (derive Eq, or hand-write Hash/Ord), as devops says.

**Q7: I move from 7b to 7a.**
The devops and min argument is decisive for generation. Every language in model priors (Java `@Deprecated`, Rust `#[deprecated]`, Python `warnings.deprecated`) reads deprecated-on-a-method as "do not call this". Under 7b, `@deprecated` on a trait method would mean "do not override this", which is the opposite of what a model expects. Calling-deprecation of a trait method would then have no spelling at all.

Two names with two fixed meanings beat one name whose meaning flips by target. The "one fewer name" saving I claimed is outweighed by the misread it invites.

</details>

<details><summary><b>Minimalism</b></summary>

###### D1: Minimalism

**Q1: hold 1b.**
plt and sys say `@perf` states a property just as `@invariant` does, so an unchecked `@perf` is unsound. I accept the premise but reject the conclusion. If no checker exists, 1a makes the row unwritable, and a row nobody can write is pure surface. The consistent answer to "it is a claim with no checker" is to cut the row, not to keep it and forbid it. With 2a winning, 1b is the only option that lets the rows do their job, which is to give a tool the input it reads. The cost is the one everyone named: "tool-checked" must say in the table and in the llms docs that the build guarantees nothing. devops's concern also applies: the shape check must reject wrong targets and wrong argument names, and must not degrade to "any args".

**Q2: change to 2c.**
2b has no support left, and plt's split is right. `@perf` and `@alt` at least state a bound or an equivalence. `@src` claims nothing, so it is provenance, and the 5-0 `@i` precedent already put that class in `///`. web says a `/// src:` field is "hidden syntax", and devops says it cannot be completed. That is an argument for a structured doc field, and the `@i` merge already committed us to one. aiml says the field syntax does not exist yet: then the cut lands with that ticket, and nothing about `@src` here blocks it. One fewer row for zero lost semantics is still worth having.

**Q3: change to 3b.**
plt, web and aiml are right. A reserved row puts a non-feature into the one table models learn from, and it adds a third status value that only one name uses. That is the parking-lot risk I raised against 3a myself. A curated `UnknownAnnotation` hint that names the State effect gives sys and devops the exact message they want with no table row. The hint is a diagnostic detail and not language surface, which is the right side of the line.

**Q6-Eq: change to 6y.**
sys, web and plt found the hazard I missed. My 6z still accepts a hand-written `Eq` next to a derived `Hash`, because Eq is "implemented", and that pairing silently breaks Map. 6y keeps F2's single rule for the common case and adds one error for that one unsound case. aiml's 6x leaves the coherence law as an obligation nothing checks, which is the defect this ticket exists to remove. The error must give both fixes: derive `Eq`, or write `Hash`/`Ord` by hand.

**Q7: hold 7a.**
Every 7b voter listed the same concern. web, plt and aiml each say the target rule must define whether `@deprecated` on a trait method deprecates calling it, overriding it, or both. That ambiguity is the cost of 7b, not a detail to settle later. The two acts fire at different sites (call site vs impl site), and both are real needs for a trait default. To express both, 7b must eventually add a mode field to `@deprecated`, which is more surface than one extra name. aiml fears that models will confuse the two names. A name that says "override" in it is harder to confuse than one name whose meaning changes with the target.

</details>

#### Phase D — Round 2 (silent re-vote)

Tally: Q1 1a 6-0; Q2 2a 5-1 (Minimalism: 2c); Q3 3b 6-0; Q6-Eq 6y 6-0; Q7 7a 6-0; 9d (ii) `checked | tool-checked` 5-1 (PLT: active | specified). The user signed off on every result.

<details><summary><b>Systems</b></summary>

###### Systems: Phase D vote

####### Q1
1. **Vote:** 1a.
2. **Reasoning:** `@perf` bounds how fast the binary runs, and `@alt` states that two functions are equivalent. A toolchain that accepts either claim without a checker ships a false guarantee. 1a gives one rule: a row is usable when its checker exists. It reuses the E1402 pattern we already have.
3. **Concern:** if `blink bench` and `blink alt` never ship, these rows stay unusable for good, and someone must then cut them in their own ticket.

####### Q2
1. **Vote:** 2a.
2. **Reasoning:** Cutting features is a design change, not a consistency fix. 2c depends on a structured `///` field syntax that does not exist yet. Under 1a, keeping all three rows costs nothing and creates no silent no-op.
3. **Concern:** `@src` stays the weakest row. Moving provenance into `///` should come back as its own ticket once doc fields exist.

####### Q3
1. **Vote:** 3b. This changes my vote from 3a.
2. **Reasoning:** My one reason for 3a was an exact message that names the State effect. V0 already accepted curated hints inside `UnknownAnnotation`, so 3b gives that message without a table row or a third status value. My worry about a "second hint list" applies under V0 whatever happens here, so it does not separate the two options.
3. **Concern:** the `@modifies` hint must be required and must name the State effect. A bare edit-distance hint does not count.

####### Q6-Eq
1. **Vote:** 6y.
2. **Reasoning:** It keeps F2's auto-derive, so `@derive(Ord, Hash)` compiles on the first try. It errors only on a hand-written Eq next to a derived Hash or Ord, which silently corrupts Map and Set lookups at run time.
3. **Concern:** the error must give both fixes: derive `Eq`, or write `Hash`/`Ord` by hand so that it agrees with your `Eq`.

####### Q7
1. **Vote:** 7a.
2. **Reasoning:** Deprecating calls and deprecating overrides are two acts that fire at two sites: the call site and the impl site. Folding them into one name leaves one act with no spelling, or else needs a mode field. One extra row is the smaller cost.
3. **Concern:** the `@deprecate_override` row must state its target (trait methods that have a default body) and must not overlap with `@deprecated`.

####### 9d (restated)
1. **Vote:** (ii) `checked | tool-checked` if 3b wins, (i) if 3a wins. Never (iii).
2. **Reasoning:** Status records who checks a row, not what a compiler has built so far. Under 1a, "tool-checked" is honest, because a tool-checked row errors until its tool exists.
3. **Concern:** the generated llms docs need their own "no checker ships yet" marker. That marker must come from toolchain state, not from the spec table.

</details>

<details><summary><b>Web/Scripting</b></summary>

###### Web/Scripting — Phase D step 2 vote

**Q1**
1. Vote: 1a.
2. Reasoning: a dev who writes `@perf(p99 < 200ms)` and sees the build pass assumes something checks it, and no row label reaches them. "Not supported by this toolchain yet" is honest and ends the search in five seconds. It is also one rule to teach: a row works when its checker exists. I'd welcome sys's split (accept `@src` after a shape check, since it claims nothing) as a refinement, if the moderator treats it as within 1a.
3. Concern: the error text must not read as "you did it wrong". It must say plainly that the spec allows this and the tool has not shipped, or users and models will learn to avoid the spec form.

**Q2**
1. Vote: 2a.
2. Reasoning: moving `@src` into `///` needs structured doc-field syntax that does not exist yet, so 2c is a promise, not a cut. Metadata about a function belongs on the function, where it is checked, completable and visible on hover.
3. Concern: under 1a, three rows may error for a long time if `blink bench`, `alt` and `trace` never ship; each needs its own ticket.

**Q3**
1. Vote: 3b.
2. Reasoning: the curated `UnknownAnnotation` hint gives the exact "use the State effect" message with no row. That keeps a non-feature out of the one table devs and models learn from. It also avoids a third status value that only one name would use.
3. Concern: the `@modifies` curated hint must be required by the decision text, not left optional, or the 14 existing uses lose their migration path.

**Q6-Eq**
1. Vote: 6y.
2. Reasoning: the common case (`@derive(Ord, Hash)`) compiles first try under F2's auto-derive. The single error lands on a hand-written Eq next to a derived Hash or Ord, which silently corrupts Map, and a correctness rule beats convenience there.
3. Concern: the error must give both fixes ("derive `Eq`, or write `Hash`/`Ord` by hand to agree with your `Eq`"), or it reads as an arbitrary conflict.

**Q7**
1. Vote: 7a.
2. Reasoning: in every language devs know, `@deprecated` on a method means "don't call this". Folding override-deprecation into it would flip that meaning on trait methods and leave call-deprecation of a trait default with no spelling. `@deprecate_override` says what it does on the label.
3. Concern: two deprecation names could still confuse beginners; the `@deprecated` row should cross-link `@deprecate_override` in one line.

**9d**
Vote: (ii) checked | tool-checked if 3b wins; (i) if 3a wins. With 1a, "not yet shipped" is toolchain state reported by diagnostics and the generated llms docs, not a spec column.

</details>

<details><summary><b>PLT</b></summary>

###### PLT: Phase D vote

**Q1**
1. Vote: 1a.
2. Reasoning: Each row is a claim, and the rule "a row is usable when its checker exists" applies to compiler-checked rows and tool-checked rows alike. min is right that a claim nobody can write is surface with no use yet. But an unchecked claim that still compiles is unsound, and the error is temporary and states exactly what is wrong.
3. Concern: The generated llms docs must leave out `specified` rows, or mark them clearly, so that models do not learn forms that always fail.

**Q2**
1. Vote: 2a.
2. Reasoning: 2c needs a structured `///` field syntax that does not exist yet, so the cut would add surface, not remove it. Under 1a, `@src` is honest until `blink trace` ships. Moving provenance into `///` can come back with its own ticket.
3. Concern: Rows whose tools never ship stay in the table for good. Each one needs a tool ticket.

**Q3**
1. Vote: 3b.
2. Reasoning: A required curated hint in `UnknownAnnotation` that names the State effect gives the exact message that the case for 3a wanted. It does that without a non-feature in the normative table and without a third status value.
3. Concern: The curated-hint list must itself come from data that ci checks, or it becomes a second list that drifts.

**Q6-Eq**
1. Vote: 6y.
2. Reasoning: The coherence laws (Eq⇒Hash agreement, Ord agreeing with Eq) are enforced only if the one unsound pairing is rejected: a hand-written Eq with a derived Hash or Ord. Every other case keeps F2's auto-derive.
3. Concern: The error must give both fixes: derive Eq, or hand-write Hash/Ord to agree with the user's Eq.

**Q7**
1. Vote: 7a.
2. Reasoning: Both meanings apply to the same target sort, the trait method. So a meaning that depends on the target is ambiguous, not compositional. Two names, each with its own use site and diagnostic, keep both meanings.
3. Concern: `@deprecate_override` must state how it combines with `@deprecated` on the same method (both may apply).

**9d**
1. Vote: (iii) active | specified, given 1a and 3b. If 1b wins: (ii). If 3a wins: (i).
2. Reasoning: Under 1a and 3b, every row is either enforced or rejected. Two states express that exactly.
3. Concern: `specified` must describe this toolchain only. The row's spec text stays normative.

</details>

<details><summary><b>DevOps</b></summary>

###### DevOps/Tooling — Phase D step 2

**Q1. 1a (changed from 1b).**
2. Reasoning: web's point is in my own domain, and I have no answer to it. Users and models read the compiler's answer, not the table, so a passing build is the diagnostic, and under 1b it says "fine" for a claim nothing checks. "Specified, not supported by this toolchain yet" is exact, a one-step repair, and true. My "punished for following docs" objection goes away if the generated llms docs do not list rows whose checker has not shipped, which I now ask for as a condition. I would also accept sys's split, where `@src` gets a shape check and is accepted because it claims no property.
3. Concern: the "not supported" error must name the row and the missing tool (e.g. "`@perf` needs `blink bench --check-contracts`, which has not shipped"), not a generic message.

**Q2. 2a.**
2. Reasoning: no structured `///` field syntax exists, so 2c moves `@src` into free text where typos compile and the LSP cannot complete. Under 1a, a kept row with no tool errors honestly, so keeping it costs nothing. A cut, if anyone wants one, should come back as its own ticket once doc-comment fields exist.
3. Concern: the rows can stay unusable for years if nobody files a ticket for each tool.

**Q3. 3b.**
2. Reasoning: S2's curated hints give the same exact message that names the State effect, with no table row and no third status value. Nothing in the normative table advertises a name nobody may use.
3. Concern: the `@modifies` curated hint must be required by the decision text, not left optional, or it falls back to an edit-distance hint with no meaning.

**Q6-Eq. 6y.**
2. Reasoning: it keeps F2's auto-derive for the common case and turns the one unsound pairing (a hand-written Eq next to a derived Hash or Ord) into a compile error, not silent Map/Set corruption.
3. Concern: the error must give both fixes: "derive `Eq`, or implement `Hash`/`Ord` by hand to agree with your `Eq`".

**Q7. 7a.**
2. Reasoning: a call deprecation fires at the call site and an override deprecation fires at the impl site. Two names give two fixed meanings, two clear messages and two clear hover texts. Both migrations stay expressible.
3. Concern: the `@deprecate_override` row must say it targets only trait methods that have a default body, so it does not drift into a second general `@deprecated`.

**9d. (ii) checked | tool-checked** (3b leaves no reserved row). If 3a wins, (i).

</details>

<details><summary><b>AI/ML</b></summary>

###### AI/ML — Phase D vote

**Q1**
1. Vote: 1a.
2. Reasoning: an annotation that compiles but has no checker becomes training data for a false claim. Models then reproduce `@perf`/`@alt` for years believing something enforces them. The exact "not supported by this toolchain" error is a one-step repair and teaches the truth. One rule, "usable when its checker exists", is simpler to learn than two classes.
3. Concern: the error must name the missing tool, so a user does not read it as a typo and delete a valid contract.

**Q2**
1. Vote: 2a.
2. Reasoning: devops is right that no structured `///` field exists. Moving `@src` there would put it in free text, where typos compile silently and nothing can complete it. Under 1a, `@src` is not a hollow row, because it errors until `blink trace` exists.
3. Concern: rows whose tools never ship stay as permanent errors, so each needs its own tool ticket.

**Q3**
1. Vote: 3b.
2. Reasoning: V0 already gives `UnknownAnnotation` curated hints, so the exact State-effect message needs no table row. Leaving the name out of the table models read is the stronger guard against them emitting it. Sys's worry about a second hint list is real but already accepted under V0. The fix is to keep the hints in the same source as the table.
3. Concern: the `@modifies` hint must name the State effect, not fall back to an edit-distance guess.

**Q6-Eq**
1. Vote: 6y.
2. Reasoning: it keeps the auto-derive, so `@derive(Ord, Hash)` succeeds on the first try. It errors only on a hand-written Eq paired with a derived Hash/Ord, which is the one case that silently corrupts Map.
3. Concern: the error must offer both fixes (derive Eq, or write Hash/Ord by hand) in a form a machine can apply.

**Q7**
1. Vote: 7a.
2. Reasoning: every language in model priors reads deprecated-on-a-method as "do not call". Making it mean "do not override" on trait methods inverts that. It would also leave calling-deprecation with no spelling at all. Two names with fixed meanings beat one name whose meaning flips by target.
3. Concern: models may confuse the two near-identical names, so the `@deprecate_override` error help must say which act each one deprecates.

**9d**
Vote: (ii) checked | tool-checked if 3b wins; (i) if 3a wins.

</details>

<details><summary><b>Minimalism</b></summary>

###### D2: Minimalism

**Q1**
1. Vote: 1a (changed from 1b).
2. Reasoning: aiml has the stronger argument. My "surface with no value" point argues for cutting the rows, not for accepting them without a check. 1a gives one rule, "a row works when its checker exists", where 1b gives two classes, and one rule is smaller. It also reuses the E1402 pattern that already exists, so it adds no new mechanism.
3. Concern: Rows that error until their tool ships may stay that way for years. The panel should treat a long-dead row as grounds to cut it, not as a permanent placeholder.

**Q2**
1. Vote: 2c.
2. Reasoning: `@src` claims no property: it is provenance, and the 5-0 `@i` precedent covers it. Under 1a, a kept `@src` would also error until `blink trace` ships, so cutting it now loses nothing. `@perf` and `@alt` at least state a bound or an equivalence, so I no longer press to cut them.
3. Concern: If 2a wins, `@src` stays the one row that is neither a checked claim nor needed by the compiler, which weakens the rule "an annotation is a checked claim".

**Q3**
1. Vote: 3b.
2. Reasoning: A curated `UnknownAnnotation` hint, already accepted 6-0 under V0, gives the exact message that names the State effect, and it needs no table row. That also drops a status value that only one name would use. Diagnostic text is not language surface.
3. Concern: The curated hint list must stay a short list outside the spec, or it becomes a shadow table.

**Q6-Eq**
1. Vote: 6y (changed from 6z).
2. Reasoning: 6z still accepts a hand-written `Eq` next to a derived `Hash`, the one pairing that silently breaks Map. 6y keeps F2's single auto-derive rule and adds one error for exactly that unsound case.
3. Concern: The error must give both fixes (derive `Eq`, or write `Hash`/`Ord` by hand), or users will add `@allow`-style workarounds.

**Q7**
1. Vote: 7a.
2. Reasoning: Deprecating a call and deprecating an override fire at different sites, and both are real needs for a trait default. One name for each meaning avoids a target rule that later needs a mode field.
3. Concern: The two rows must cross-reference each other, so that a reader of `@deprecated` finds `@deprecate_override`.

**9d**
Vote: (ii) checked | tool-checked if 3b wins, else (i). Under 1a, the status tells the reader which checker must exist for the row to work. Do not add a "specified" value: the error message already carries that state.

</details>

### Final Spec

The normative text is the table in §11.1 *Complete Annotation Reference*. §2.17 and §3.6.1 point to it.

```blink
@derive(Eq, Hash, Debug)
type UserId {
    value: Int
}

@requires(amount > 0)
fn deposit(balance: Int, amount: Int) -> Int {
    balance + amount
}

@inline                      // error: UnknownAnnotation (not a Blink annotation)
@modifies(balance)           // error: UnknownAnnotation; help names the `State` effect
@perf(p99 < 5ms)              // error: AnnotationNotSupported until `blink bench --check-contracts` exists
@requires(amount > 0)
@requires(amount > 0)        // allowed: the @requires row repeats
@deprecated(since: "0.9", replacement: "deposit")
@deprecated(since: "1.0")    // error: DuplicateAnnotation
fn old_deposit(balance: Int, amount: Int) -> Int {
    deposit(balance, amount)
}
```

- §11.1 is the one list. Each row gives the target, whether the name repeats, the meaning and the status. The row order is the canonical order.
- The set is closed. A change to a row needs a panel vote and a table edit in the same change.
- A name that is not in the table is `UnknownAnnotation`. It gives the nearest name or a fixed hint. The `@modifies` hint names the `State` effect. `@effects` keeps `EffectsAnnotationRemoved`.
- A wrong target is `UnexpectedAnnotation` (E1110). A repeat is `DuplicateAnnotation`, unless the row says the name repeats.
- Status is `checked` (the compiler checks the row) or `tool-checked` (a named tool checks it: `@perf`, `@alt`, `@src`). A row works only when its checker exists. Otherwise, the error is `AnnotationNotSupported`, which names the row and the missing tool.
- `@modifies` and `@expect_panic` are removed. Tests use `assert_panics`.
- `@skip` and `@deprecate_override` have rows.
- `@derive` takes seven traits: Eq, Ord, Hash, Clone, Debug, Serialize, Deserialize. `@derive(Display)` is E1402. Derive laws are normative, and hand-written impls must obey them too.
- `@derive(Ord)` or `@derive(Hash)` auto-derives `Eq`. A hand-written `Eq` with a derived `Hash` or `Ord` is `DeriveOverHandWrittenEq`. The help gives both fixes.
- `@verify` fallback is `runtime | error | trust`. `@trusted` needs `audit:`. `@deprecated` uses the structured form. `@src` targets fn, type and module. `@allow` targets fn and type. A type-level `@allow` does not reach impl blocks declared apart from the type.
- Rejected: a codegen column, a `@tool.` name prefix, and a `reserved` status.
