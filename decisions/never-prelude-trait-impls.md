[< All Decisions](../DECISIONS.md)

# Prelude Trait Impls for `Never` — Design Rationale

The `Never` ruling ([never-bottom-type.md](never-bottom-type.md)) put this sentence in §3.2: "`Never`
implements no trait unless the prelude declares an impl of that trait for `Never`." It left open
which impls the prelude declares. Without any, `r.unwrap()`, `r == s` and `assert_eq` fail on a
`Result[Int, Never]`, and the spec's own `process.exec(...).unwrap_err()` example (§4.10) fails on
`Result[Never, ProcessError]`. The panel decided which traits `Never` gets, how the spec states the
list, what the error says when a bound on `Never` fails, and whether the spec seals the impls with a
sentence of its own.

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated
in independent-proposal → debate → vote rounds.

Facts surfaced to the panel by the moderator:

- **F1:** `Result` has no `Display` impl (§3.6 *Debug vs Display*). The ticket's example `"{r}"` on
  a `Result[Int, Never]` fails for every error type, not because of `Never`.
- **F2:** `Result.unwrap` and `unwrap_err` need `Debug` on the arm they panic on.
- **F3:** `assert_eq` needs `Eq` and `Debug`; `==` on a `Result[Int, Never]` needs `Never: Eq`
  through the conditional container impl.
- **F4:** the signatures of the derivable traits. `Deserialize.from_json` is static and returns
  `Result[Self, JsonError]`.
- **F5:** the stdlib already writes `Never` as a type argument: `process.exec -> Result[Never,
  ProcessError]`.
- **F6:** the compiler does not yet accept `Never` in source. The spec leads the compiler here.
- **F7:** `?` in a test body needs `Display[E]` at each `?` site (E0514).
- **F8:** the §4.10 example `process.exec(tool, args).unwrap_err()` needs `Never: Debug` today.
- **F9:** §3.6 states no conditional `Ord` or `Clone` impl for `Result` or `Option`, and the JSON
  type mapping has no row for `Result`.
- **F10:** the spec has no `{r:?}` form. The form that works is `"{r.debug()}"`.
- **F11:** §3.6 *Orphan Rule*: for compiler-known traits "the compiler is considered the 'defining
  package'", with no exception for prelude types. §3.6 *No Impl Overlap* also rejects two impls
  that match one type.

#### Phase A — Independent proposals

- **Systems:** seven traits, "every self-consuming derivable trait except Deserialize". "Each body
  lowers to one cold trap." And: "I want the body to be a defined trap (`__builtin_trap()`, or the
  panic dispatch path), not `__builtin_unreachable()`. If FFI or a miscompile ever forges a `Never`
  value, a trap fails loudly." And: "The spec text should be an explicit list in §3.2, not a rule
  like 'every trait whose methods take Self'."
- **Web/Scripting:** the same seven (W1). "The user-facing rule fits in one sentence: '`Never` has
  every derivable trait except `Deserialize`, because you cannot build a `Never` from JSON.'" On
  the always-`Err` option: "A web developer who writes `Result[User, Never]` in a request type would
  get a runtime JSON error where a compile-time error was possible."
- **PLT:** all eight derivable traits (P1), under an admissibility rule: "(a) It takes a `Never`
  input" or "(b) Its return type is inhabited when `Self := Never`." `Deserialize` passes (b) with a
  body that always returns `Err`. "The laws hold vacuously. Each law is a ∀ over the values of
  `Never`, and that set is empty." And: "a user cannot write `impl Eq for Never`, because the
  prelude owns these impls (coherence)."
- **DevOps:** six traits, no `Hash` (Proposal 1). "`Hash`: §3.6 has a closed list ('cannot gain
  one'), and `Result` is not hashable anyway. ... YAGNI." On diagnostics: "The `help:` for that
  error tells the user to 'derive `Debug` for `Never`', which they cannot do. That breaks rule §3
  #1". Proposed the E0306 `note:` that lists the impls, "from the same table the checker uses", and
  said "The spec does not state a rendering for `Never`."
- **AI/ML:** the same seven (P1). "'Never has every derivable trait except Deserialize' is one fact
  with one exception, and the exception has a reason a model can rebuild". And: "`@derive(Hash)` on
  `Job[E]` with `E = Never` must not fail at mono time. Each trait left out is a hole where a
  generic type compiles for every `E` but `Never`."
- **Minimalism:** `Eq` and `Debug` only (M1), plus a growth rule: "The prelude adds an impl for
  `Never` only when a stdlib conditional instance or a stdlib API bound puts that trait's demand on
  a `Never` type argument. Each such impl holds only methods that take a `Never` argument." And:
  "Adding an impl later breaks nothing; removing one does. Start small."

#### Phase B — Debate highlights

- **Systems** **(changed A to A6)**: "I picked Hash only for a tuple key that holds `Never`. A tuple
  that holds `Never` has no values, so that key can never exist." Against B: "`Deserialize for
  Never` is the only impl in the set whose body *runs*."
- **PLT** **(changed B to A)**: "by F9, `Result` has no JSON mapping, so that field fails no matter
  what `Never` has." Kept Hash and Ord: "If `Never` had Eq but not Ord, generic code bounded by `T:
  Ord` would reject an instance whose behaviour is fully defined. That is an arbitrary gap in the
  instance lattice". Proposed min's second sentence "as a **constraint on the list**, not as a rule
  that generates it".
- **DevOps** held A6, A second: "B ... takes a compile-time error and turns it into a run-time
  `JsonError`."
- **AI/ML** **(changed A to B)**: "B gives one rule with no exception: **`Never` implements every
  derivable trait.**" Against A6: "With `@derive(Hash, Eq) type Key[E] { id: Int, tag: E }`,
  `Key[Never]` fails at mono time."
- **Minimalism** **(changed C to C3, adding Display)**: "What moved me was F7". And on the list:
  "sys convinced me: 'A list keeps the "no rule derives an impl" sentence true.'"
- **Web/Scripting:** a safety classifier stopped web's round 1 reply twice. web asked that its
  Phase A position (W1, the same as A) stand as its round 1 position.

#### Phase C — Silent vote

- **Q1: which traits** (no majority: A 2, A6 2, B 1, C3 1)
  - **Systems:** A6 — "Hash would cost a spec edit to the closed §3.6 list for a key that can never
    exist. Deserialize (B) would be the only impl whose body runs".
  - **Web/Scripting:** A — "users learn one short list in place of a series of tickets."
  - **PLT:** A — "Ord and Hash refine Eq. If `Never` had Eq but not Ord or Hash, generic code bounded
    by `T: Ord` would reject an instance whose behaviour is fully defined."
  - **DevOps:** A6 — "Hash would mean reopening a closed list in §3.6 to support a map key that can
    never exist."
  - **AI/ML:** B — "'`Never` implements every derivable trait' is one rule with no exception."
  - **Minimalism:** C3 — "By F9, `Ord`, `Clone` and `Serialize` make no program compile today".
- **Q2: normative form** (4-2, L1; AI/ML and Minimalism for L2)
  - **Systems:** L1 — "plt's sentence is not min's growth rule. It does not depend on what lib/std
    holds, so it is a stable language rule."
  - **Web/Scripting:** L1 — "The list tells you what exists, and the sentence tells you why. A spec
    reader never opens decisions/."
  - **PLT:** L1 — "With it, a later addition that is unsound (one with a static constructor) is
    visibly against the spec, not only against a decision record that nobody reads."
  - **DevOps:** L1 — "A rule in the decision record does not bind the next spec edit. A rule in
    §3.2 does."
  - **AI/ML:** L2 — "L1's sentence says each method takes a `Never` argument, and that contradicts
    the Deserialize impl that B adds."
  - **Minimalism:** L2 — "Fewer normative sentences means less for users and implementers to read."
- **Q3: diagnostic** (6-0, D1)
  - **Systems:** D1 — "If the checker's own table generates the note, the note and the checker
    cannot disagree."
  - **Web/Scripting:** D1 — "'derive Debug for Never' is advice no one can follow".
  - **PLT:** D1 — "The correct elimination form is `match`, which the E0300 help already teaches".
  - **DevOps:** D1 — "Today's E0306 help tells the user to derive or implement the trait, and for
    `Never` that repair does not exist." Concern: "For a bare generic `T = Never`, it must name the
    bound instead, or the help points at nothing."
  - **AI/ML:** D1 — "A 'derive X for Never' suggestion gives it one that can never compile."
  - **Minimalism:** D1 — Concern: "Show it only when it gives a type that satisfies the bound."
- **Q4: sealing** (3-3 tie: S1 Systems, Web, AI/ML; S2 PLT, DevOps, Minimalism)
  - **Systems:** S1 — "A user impl that silently shadowed the prelude impl, or was silently skipped,
    would make codegen hard to predict."
  - **Web/Scripting:** S1 — "One explicit sentence prevents a confused search through orphan-rule
    text."
  - **PLT:** S2 — "§3.6 *Orphan Rule* already makes the compiler the defining package of every
    compiler-known trait."
  - **DevOps:** S2 — "A second sentence about the same case is a second rule that can drift away
    from the first."
  - **AI/ML:** S1 — "When a model gets a bound error on `Never`, its first reflex is to write `impl
    Eq for Never`."
  - **Minimalism:** S2 — "It also suggests that other prelude types need their own sealing
    sentence."

Consensus items (no objection from any panelist):

- The ruling says that `"{r}"` on a `Result[Int, Never]` still fails, because `Result` has no
  `Display`, and that `"{r.debug()}"` works.
- The spec states no `Display` or `Debug` text for `Never`.
- Codegen lowers each impl body to a defined trap, not `__builtin_unreachable()`. This is a codegen
  note, not spec text.
- F9 is a separate gap. It does not narrow this ruling.

#### Phase D — Round 2

Q1, Q2 and Q4 split in Phase C. The panel ran one focused debate on them, then re-voted.

Debate highlights:

- **Systems** **(changed A6 to A)**: "My only objection to Hash was the cost of the spec edit, not a
  runtime cost." **(changed S1 to S2)**: "F11 shows that §3.6 *No Impl Overlap* already gives that
  guarantee, so a sentence just for `Never` adds nothing for codegen."
- **Web/Scripting** **(changed S1 to S2)**: "A JS developer reading §3.2 would then ask why `Int`
  has no such sentence."
- **PLT** **(changed A to A6)**: "§3.6 already makes Hash sparse on purpose: `List`, `Map`, `Set`,
  `Option` and `Result` are Eq and not Hash. A hole at `Never` is the same shape the spec chose for
  every container, so it is not arbitrary."
- **DevOps** **(changed A6 to A)**: "Without `Never: Hash`, the error does not show up at the user's
  derive. It shows up at a mono-time instantiation, sometimes in a different module". Proposed that
  "the OrphanImpl error on a prelude trait for `Never` carries the same generated note as D1."
- **AI/ML** **(changed B to A, L2 to L1, S1 to S2)**: "A model's fix loop sees compile errors. It
  never sees a run-time error that only fires on a decode path." And: "`blink llms` serves
  sections/, not decisions/."
- **Minimalism** **(changed C3 to A6, L2 to L1)**: "A generic user type that takes a phantom error
  parameter, instantiated at `Never`, is a real program, not a hypothetical one." And: "I stop at
  A6, not A."

Re-vote:

- **Q1: which traits** (4-2, A; PLT and Minimalism dissent)
  - **Systems:** A — "§3.6 leaves the containers without Hash for real reasons: a stable hash of a
    `Map` is costly, and the order of its entries is not defined. `Never` has neither problem, so a
    hole there exists only because of how the list is edited, not because of the type."
  - **Web/Scripting:** A — carried forward from web's Phase D reply (a safety classifier stopped
    web's ballot; web asked that its Phase D positions count): "A user who wrote that type did
    nothing wrong, and the error shows up far from where they wrote the derive."
  - **DevOps:** A — "Under A, a user who instantiates a hashable generic type at `Never` gets no
    E0306 at all. That is better than any note the D1 diagnostic could give, and the cost is one
    clause in §3.6."
  - **AI/ML:** A — "A model already knows from training that a list is not a map key. Nothing
    teaches it that `Never` is not one, and `Never` is the type argument it writes for 'no error'".
  - **PLT:** *(dissent)* A6 — "a type parameter that carries an error, as in the phantom-error case,
    almost always sits inside `Result[_, E]` or `Option[E]`, and that field is unhashable whatever
    `E` is." And: "Hash is the one trait here whose set of types §3.6 closed on purpose."
  - **Minimalism:** *(dissent)* A6 — "`@derive(Hash, Eq) type Key[E]` also fails for
    `Key[List[Int]]`, and in the same far-off way. That is a general fact about derives with a
    bound on a type parameter, not a defect that is specific to `Never`". Concern: "The text must
    also make clear that `Never` is the only non-scalar exception, so that no one reads it as an
    opening for containers."
- **Q2: normative form** (6-0, L1)
  - **Systems:** L1 — "It belongs in the spec, which binds the next edit, and not only in a decision
    record."
  - **Web/Scripting:** L1 — "The sentence also explains *why* `Never` has no `Default`".
  - **PLT:** L1 — "Three parts of the ruling follow from it: codegen emits a trap, the spec states
    no rendering, and `Default` and `Deserialize` are absent."
  - **DevOps:** L1 — "It is in sections/, so `blink llms` serves it to users and models".
  - **AI/ML:** L1 — "the sentence lets a model work out why `Default` and `Deserialize` are missing
    without memorizing a list of exclusions."
  - **Minimalism:** L1 — "One sentence that does the job of three is a good trade for surface."
  - Every panelist's concern: the text must say the list is closed and the sentence only limits it.
- **Q4: sealing** (6-0, S2)
  - **Systems:** S2 — "A sentence only for `Never` would add a second rule that can drift from the
    first."
  - **Web/Scripting:** S2 — "That is message text, not a spec rule."
  - **PLT:** S2 — "The OrphanImpl message for this case should carry the D1 note".
  - **DevOps:** S2 — "What the S1 voters wanted belongs in the message."
  - **AI/ML:** S2 — "A sentence for `Never` alone would lead a model to infer that `impl Eq for Int`
    is legal."
  - **Minimalism:** S2 — "The real need is for the `OrphanImpl` error to name `Never`'s prelude
    list."

The user approved the tally.

AI-first review: learnability, consistency, generability, debuggability and token efficiency all
pass (5/5).

### Final Spec

```blink
// Prelude (normative list; each body is `self`, which has type Never)
impl Eq for Never { fn eq(self, other: Never) -> Bool { self } }
impl Ord for Never { fn cmp(self, other: Never) -> Ordering { self } }
impl Hash for Never { fn hash(self) -> U64 { self } }
impl Clone for Never { fn clone(self) -> Never { self } }
impl Debug for Never { fn debug(self) -> Str { self } }
impl Display for Never { fn fmt(self, mut sb: StringBuilder) { self } }
impl Serialize for Never { fn to_json(self) -> JsonValue { self } }

fn first(r: Result[Int, Never]) -> Int {
    assert_eq(r, r)              // Eq and Debug on Result[Int, Never]
    let shown = "{r.debug()}"    // "{r}" is still E0523: Result has no Display
    r.unwrap()
}
```

- `Never` has exactly seven prelude impls: `Eq`, `Ord`, `Hash`, `Clone`, `Debug`, `Display`,
  `Serialize`. The list is closed (§3.2).
- §3.2 states: "Each prelude impl for `Never` holds only methods that take a `Never` argument." The
  sentence limits the list and grants nothing. So `Never` has no `Deserialize`, `Default`,
  `From`/`TryFrom` or numeric operator impls.
- §3.6 lists `Never` among the types that implement `Hash`, and the built-in trait table has a
  `Never` row.
- The spec states no `debug()` or `display()` text for `Never`. The laws that tie `Ord`, `Hash` and
  `Debug` to `Eq` hold with nothing to check.
- A failed bound on `Never` (E0306) gives a `note:` that lists the impls, generated from the
  checker's table, and a `help:`. The help names the §3.2 `match` rewrite only when `Never` is a
  type argument of a value's type and the rewritten type meets the bound. Otherwise it names the
  failed bound. It never suggests deriving or implementing the trait for `Never`. No new lint.
- No sealing sentence. The orphan rule and *No Impl Overlap* already reject `impl Eq for Never` in
  user code. The `OrphanImpl` error for a prelude trait on `Never` carries the same generated note
  as E0306 (message text, not a spec rule).
- Codegen lowers each impl body to a defined trap, never `__builtin_unreachable()`.

### Follow-ups

- Implement the seven impls, the E0306 note and help, and the `OrphanImpl` note.
- F9: §3.6 states no conditional `Ord` or `Clone` impl, and no JSON mapping, for `Result` and
  `Option`. Decide them in their own ruling.
