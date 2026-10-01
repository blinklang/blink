[< All Decisions](../DECISIONS.md)

# Opaque-Handle Audit Round-Trip and Completeness — Design Rationale

Resolves br `qpnx94`. Completes the `opaque-ffi-handle` audit boundary that the
[mint-boundary decision](opaque-handle-mint-boundary.md) left half-defined, and replaces its
"the audit runs pre-typecheck" clause for site classification.

**The gap.** §9.1.4 said a round-trip is "a handle handed back to a raw pointer" inside an FFI
region, but named no form. The audit tags mints, but its pre-typecheck walker finds a
`Ptr[opaque]` receiver only when the receiver is a binder with a `Ptr[X]` annotation or a binder
set from a pointer intrinsic. It misses field, index and call-result receivers, and `match` and
`for` binders. The ticket also asked whether a `fn` in a `handler E { }` expression inherits the
region. The walker reset the region to 0 for it, the same as for a named nested `fn` item.

Facts the moderator measured and gave to the panel:

- `Ptr[CFile].write(h)` typechecks.
- The audit's signature pass records each `@ffi` declaration slot once. It does not record calls.
- E0811 checks only signatures, so `let p: Ptr[Int] = alloc_ptr[Int]()` then `p.deref()` in an
  ordinary `pub fn` compiles.
- A comment in `src/cli.bl` calls the walker's region predicate "intentionally broader than
  E0811's signature gate".
- Named nested `fn` items do not parse, so handler methods are the only `fn` written in a body.
- §9.1.1 lists "passed to an effect handler" as a dynamic escape for E0601.

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated in
independent-proposal → debate → vote rounds. Phase B ran one round. All six sent READY. Phase C
used fresh agents. No question was closer than 5-1, so Phase D did not run.

#### Phase A — Independent proposals

All six proposed the same Q1 core: a round-trip is a `.write(v)` on a `Ptr[opaque]` receiver in
a region, and a handle passed by value to an `@ffi` call is not one. All six proposed that
handler methods inherit the region. They split on Q2.

- **Systems:** *"S1: a round-trip crossing is a `.write(v)` call, lexically inside an FFI region,
  whose receiver is a `Ptr[O]` or an `@ffi.struct` field projection of declared type `O`, where `O`
  is an `@ffi.opaque` type. [...] It is the exact dual of a mint: a mint reads a handle out of raw
  memory and a round-trip writes one into it."* On Q2 (S2): *"the no-tids lock covers the region
  predicate only [...] Deciding whether an expression is `Ptr[opaque]` is a type question, and the
  audit answers it from the typechecker's resolved receiver type, not from a binder map."* On Q3
  (S3): *"A handler lowers to a function-pointer table plus a captured environment, which is the
  same machine shape as a closure. Two lowerings with identical cost and different region rules
  would be an inconsistency with no reason behind it."*

- **Web/Scripting:** *"W1: 'Read mints, write round-trips' [...] A developer can learn this in one
  sentence ('deref mints, write round-trips'), and a reviewer reading the audit sees two kinds of
  site that pair up."* On Q2 (W2): *"The walker today guesses types from annotations (F4). Every
  new spelling then becomes a known gap and a Stack Overflow question ('why didn't audit list my
  deref?')."* On Q3 (W3): *"Saying 'this `fn` is inside the braces but outside the region' would
  surprise every reader and earn its own FAQ entry."*

- **PLT:** *"Framing. The locked 'no tids' point covers the **region predicate**: *where* a site
  is. Whether the receiver of `.deref()` or `.write()` is a `Ptr[opaque]` is a different question:
  *what* the site is, and that is a typing judgment. Reading the lock as covering both is a
  category error."* P1: *"any call `e.write(v)` whose receiver `e` has type `Ptr[H]` or
  `Ptr[Option[H]]` for an `@ffi.opaque` type `H` [...] Mint is the matching elimination: `deref :
  Ptr[H] -> H`. Round-trip is `write : Ptr[H] × H -> ()`."* P2: *"Completeness then becomes a
  theorem, not a heuristic [...] The `ptr_env` seeding heuristic is retired."* P3: *"Not
  inheriting would be **inconsistent**: `|x| cell.write(x)` would be legal, but the same body
  written as a handler clause would not."*

- **DevOps:** *"Framing: the audit is a security inventory. Its worst failure is a silent false
  negative, because a reviewer trusts what is listed."* T1: *"Any future `Ptr` store op
  (`write_at`, indexed store on `alloc_n` cells) is a round-trip by the same rule."* T2: *"The
  audit runs on a program that typechecks, or refuses (an audit of a non-compiling program is
  meaningless; `go vet` needs type-checked packages, clippy runs on typed HIR)."* Also: *"`.write(v)`
  on a `Ptr[S]` where `S` is an `@ffi.struct` with an opaque field (or `.deref()` of such a cell)
  also moves a handle through raw memory. With tids the rule is 'the stored/loaded type contains
  an opaque handle' — a one-line test."* T3: *"Resetting the region gives `E0811 PtrOutsideFFI` on
  a line visibly inside `with ffi.scope()` — a message that is false on its face and whose fix is
  not discoverable."*

- **AI/ML:** *"I use one test for every choice: can a model that reads only §9.1.1 and §9.1.4
  predict, for a given site, (1) whether it compiles and (2) whether the audit tags it?"* AI-1:
  *"The spec's phrase 'to hand to another C call' should get one sentence: the C call takes the
  cell, and the `.write` is the crossing."* AI-2: *"A partial inventory is the worst outcome for AI
  tooling. An agent that reads 'audit: 3 crossings' will reason as if that is all of them [...]
  Exact beats over-approximate, and over-approximate beats silent."* AI-3: *"Resetting the region
  at a handler's `fn` gives an E0811 on code that is visibly inside `with ffi.scope()`. The only
  fix would be to annotate a method, which the grammar does not allow, or to move the code."*

- **Minimalism:** *"the audit needs no new syntax or diagnostics, no type ids (tids), and only one
  new rule."* M1 matched the others on Q1. M2: *"inside an FFI region, the walker tags every
  `.deref()`, `.read()` and `.write(v)` call whose receiver it cannot classify [...] with handle
  `?` [...] The completeness contract is then **sound, not precise**."* Min listed the typed
  option as an alternative it did not prefer, *"because it adds a pipeline dependency to buy
  precision in a report."* M3: *"The rule 'a named nested fn item does not inherit' has only one
  subject today: handler methods (F6). The spec should drop it."* Min also asked to *"file the
  body-level E0811 gap as its own bug. Do not paper over it with audit features."*

#### Phase A.5 — Dedupe

Q1 came down to one option with six variations: V1 `@ffi.struct` field `.write`, V2 `.offset(i)`
receivers, V3 field `.read()` as a mint, V4 `Ptr[Option[H]]`, V5 a struct pointee that holds an
opaque field, and V6 a sentence on "to hand to another C call". Q2 split into **T** (typed
classification, exact contract) and **O** (stay pre-typecheck, tag unknown receivers with `?`).
Q3 came down to one option with two variations: H1 (keep or drop the nested-fn sentence) and H2
(the walker passes the enclosing env).

#### Phase B — Debate highlights (one round)

- **Minimalism** changed from O to T: *"Under T the minimal option also removes code, which is why
  I switched: The ptr_env seeding heuristic goes away. [...] E1 is required either way, and
  body-level E0811 needs a typed answer to 'is this expression a Ptr' [...] So the tid split comes
  anyway, and T reuses it instead of keeping a second, heuristic classifier."* To plt: *"Agreed. My
  Phase A treated T as the costlier option, but it is cheaper once E1 is counted."*
- **Systems** to min: *"The dependency costs nothing new. `blink build` already runs typecheck
  [...] In a security inventory, a pile of `?` rows teaches reviewers to skip them, and then the
  inventory is unsound in practice."* Systems also stated the general rule: *"the loaded or stored
  type contains an opaque handle, directly, through Option, or through `@ffi.struct` fields,
  transitively. [...] Tag once per site for each distinct handle type."*
- **PLT** to min: *"It is soundness, not just precision. O-b's proof that a receiver is not opaque
  is syntactic, and it breaks on aliases. Given `type H2 = CFile`, a binder `let p: Ptr[H2]` looks
  non-opaque, so O-b skips it and the audit misses a real crossing."* And: *"The CI property test
  also becomes trivial: if every unknown receiver gets a tag, 'every site is tagged' cannot
  fail."* On H1: *"keep the sentence, restated by its principle: a term that closes over its
  lexical environment (a closure literal or handler clause) inherits the region; an item does
  not."*
- **DevOps** to min: *"The precision is the report's whole job. Under O, every `.deref()` on a
  struct field in a region is listed with handle '?', including `Ptr[Int]` and `@ffi.struct`
  reads."* On E1: *"Make it a blocker of the audit ticket."*
- **AI/ML** proposed one sentence for V1-V5: *"A mint is a .deref()/.read() that loads a value
  whose type is or contains an @ffi.opaque type, in a region. A round-trip is a .write(v) that
  stores one."* On H1: *"if we drop the sentence, the spec is silent when brwa0a lands. Models that
  learned this spec will then generalize from closures and handlers ('everything inherits')."*
- **Web/Scripting** changed on H1 to drop the sentence: *"A spec rule with no subject makes readers
  ask 'what nested fn?'. brwa0a can add the rule if it adds the feature."*
- **Minimalism** yielded on H1: *"Keep the sentence, but only if the spec says in plain words that
  handler methods are outside it (plt's wording). I will not block over dead text."*

#### Phase C — Final vote

- **Q1: what is a round-trip, and how far the site rule reaches** — **Q1-B, 6-0.** V6 yes, 6-0.
  - **Systems:** Q1-B — *"At the machine level, a mint is a load of handle bits from raw memory
    and a round-trip is a store of handle bits to raw memory. [...] Q1-A tags one shape of that
    store and misses the others that are the same machine operation."* Concern: *"A transitive
    walk into `@ffi.struct` fields could tag one load several times, unless the 'one tag per site
    per distinct H' rule is implemented exactly and tested on a struct that holds two fields of
    the same handle type."*
  - **Web/Scripting:** Q1-B — *"One rule to learn: 'a load that brings a handle out of raw memory
    is a mint, a store that puts one in is a round-trip.'"* Concern: *"the docs must show one
    example per shape (Option, struct field, `.offset(i)`), or users will not know what a tag on a
    struct deref means."*
  - **PLT:** Q1-B — *"Q1-B states one rule over the stored/loaded type ('is or contains H'), so
    V1-V5 follow from it and need no case list."* Concern: *"'contains, transitively' must stop at
    `Ptr` (a `Ptr[H]` field inside a struct is not itself an H load) and must resolve aliases."*
  - **DevOps:** Q1-B — *"'Load or store of a type that contains H' is one rule for docs, hover
    text and the audit, and the 'one tag per site per distinct H' rule keeps the output stable for
    a JSON consumer to diff."* Concern: *"A site whose struct holds several opaque types emits
    several rows on one line. The text output must group them, or the report looks duplicated."*
  - **AI/ML:** Q1-B — *"Q1-A leaves field, offset, Option and struct-pointee loads untagged, and a
    model cannot predict those gaps from the spec."* Concern: *"the spec must say that the walk
    stops at a `Ptr` and goes only through `Option` and `@ffi.struct` fields."*
  - **Minimalism:** Q1-B — *"Q1-A looks smaller, but it leaves a handle that is loaded through an
    `@ffi.struct` field or `Option` with no tag. A small rule that is unsound does not save
    anything."* Concern: *"The spec must say 'one tag per site per distinct H' so that the output
    stays one row for each crossing."*

- **Q2: completeness contract against the no-tids lock** — **Q2-T, 6-0.** E1, E2 and E3 yes, 6-0.
  - **Systems:** Q2-T — *"T has no runtime cost and no codegen change. The audit pays for one
    typecheck that `blink build` runs anyway, and in exchange the inventory is exact."* Concern:
    *"The E1 implementation ticket must land before the property test is called a gate."*
  - **Web/Scripting:** Q2-T — *"Refusing an ill-typed program is what tsc and mypy users already
    expect. E1 must block the property test, or the test checks a gate that does not exist."*
    Concern: *"If E1 (body-level E0811) slips, T ships with an exact audit over a region rule the
    compiler does not enforce in fn bodies."*
  - **PLT:** Q2-T — *"With classification from checked types, completeness is a theorem over
    well-typed programs and not a seeding heuristic, and Q1-B's 'contains H' can be decided at
    all."* Concern: *"E1 may slip as a separate ticket while the audit ships."*
  - **DevOps:** Q2-T — *"`blink audit` on an ill-typed program must print the type errors and exit
    non-zero with 'audit needs a program that typechecks', not print a partial inventory that CI
    reads as green."* Concern: *"The audit ticket must be blocked on it, not shipped beside it."*
  - **AI/ML:** Q2-T — *"An exact contract is the only one a model can reason from. 'N crossings'
    means N."* Concern: *"the blocker link must be real in br, not only in prose."*
  - **Minimalism:** Q2-T — *"Under Q2-T we remove code: the ptr_env seeding heuristic goes, and
    there is no '?' marker or extra section."* Concern: *"E1 can slip as 'its own ticket', and then
    the property test lands green but tests nothing."*

- **Q3: handler-method region** — **Q3-H, 6-0.** H1-keep **5-1, Web/Scripting dissent.**
  - **Systems:** Q3-H, H1-keep — *"Keep the nested-fn sentence because a 6-0 vote put it there and
    brwa0a needs it."* Concern: *"If a handler value escapes the region, E0601 must actually catch
    it."*
  - **Web/Scripting:** *(dissent on H1)* Q3-H, H1-drop — *"A spec sentence about a feature that
    does not exist (named nested fn items) makes readers ask 'what nested fn?', and then needs a
    second sentence to explain that it does not cover handler methods. brwa0a can state its own
    rule when it adds the feature."* Concern: *"If H1-keep wins, the clarifying line must say
    plainly that handler methods are expression members."*
  - **PLT:** Q3-H, H1-keep — *"A handler clause closes over its lexical environment (§06 lets it
    capture `let mut`), so it is a closure in denotation."* Concern: *"The walker must pass the
    enclosing ptr_env/region (H2) and E0811 must use the same propagation."*
  - **DevOps:** Q3-H, H1-keep — *"One lexical rule also keeps LSP region highlighting simple, with
    no special case per expression kind."* Concern: *"The walker must pass the enclosing env into
    handler bodies (H2)."*
  - **AI/ML:** Q3-H, H1-keep — *"Keeping the nested-fn sentence, and naming handler methods as
    outside it, gives brwa0a a fixed rule."* Concern: *"the wording must say that they do not exist
    today."*
  - **Minimalism:** Q3-H, H1-keep — *"On H1 my domain prefers to remove dead text. But the
    nested-fn sentence came from a 6-0 vote, and removing it reopens a decided point."* Concern:
    *"If brwa0a rejects nested fns, delete the sentence then."*

H1 was 5-1, so Phase D did not run. AI-first review: 5/5 pass. The user signed off on the tally.

### Final Spec

```blink
@ffi.opaque(header: "stdio.h", name: "FILE")
type CFile

@ffi("shim", "register_stream")
@trusted(audit: "P-2")
fn c_register(cell: Ptr[CFile]) -> Int ! IO   // declaration record: produce (out-cell)

pub fn hand_back(h: CFile) -> CFile ! IO {
    with ffi.scope() as scope {
        let cell = scope.alloc[CFile]()
        cell.write(h)             // round-trip: CFile stored into raw memory
        c_register(cell)          // no body tag: the declaration record covers it
        cell.deref()              // mint: CFile loaded from raw memory
    }
}
```

Locked design points (§9.1.1 *Pointer Operations*, §9.1.4 *Audit category `opaque-ffi-handle`*):

- **One rule for body sites.** In a region, a **mint** is a `.deref()` or `.read()` that loads a
  value whose type is or contains an `@ffi.opaque` type `H`. A **round-trip** is a `.write(v)`
  that stores one.
- **"Contains"** means `H`, `Option[H]`, or an `@ffi.struct` with a field that contains `H`, at
  any depth. Aliases resolve first. The walk stops at `Ptr`. The form of the receiver does not
  matter. A site gets one tag for each distinct `H`.
- **A handle passed by value to an `@ffi` call is not a round-trip.** The declaration record
  covers it, once per declaration. The `.write` into the cell is the crossing, not the C call that
  takes the cell.
- **The region stays syntactic. Classification is typed.** The no-tids lock covers only the
  region predicate. The audit classifies sites from checked types after typecheck. The contract
  is exact. The `ptr_env` heuristic goes. This replaces "the audit runs pre-typecheck" in the
  mint-boundary decision for classification.
- **`blink audit` typechecks first.** It refuses a program that fails, prints the errors and exits
  non-zero.
- **E0811 covers bodies.** Every expression whose checked type is a `Ptr[T]` must be in a region.
  The implementation is a separate ticket that blocks the audit's property test. The `src/cli.bl`
  comment "intentionally broader" goes.
- **Handler clauses inherit the region**, the same as closure literals. The audit and E0811 walk
  them with the enclosing env. A handler that escapes is E0601's concern. The named nested `fn`
  rule stays and says that such items do not parse today and that handler clauses are not items.

Facts found after the vote, while writing the spec. These do not change the decision:

- §9.1.3 rejects an `@ffi.opaque` field in an `@ffi.struct` (`FfiStructGcField`).
- `Ptr[Option[H]]` is not a valid `Ptr` type (E0810).

So today only the plain `H` case of "contains" can occur. The spec keeps the `Option` and struct
cases so that a later change to those rules cannot open a gap in the audit.
