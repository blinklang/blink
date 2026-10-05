[< All Decisions](../DECISIONS.md)

# `todo()` and `unreachable()` Built-ins — Design Rationale

The spec used `todo()` in the E0004 fix (§5, `Cancelled => todo()`), but no section defined it.
§2.20 gave `panic(msg)` as the only diverging built-in, and §3.3 listed only `panic(msg)` and
`env.exit(code)` as untracked divergence. The panel decided which built-ins to add, where the
`todo` warning fires, how they interact with the library-panic lint, how to write the optional
message, how §3.3 covers them, and what the message text must contain.

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated
in independent-proposal → debate → vote rounds.

Facts surfaced to the panel by the moderator:

- **F1:** a positional parameter cannot have a default value; defaults exist only on keyword
  parameters after `--` (§2.13).
- **F2:** the `assert` signature already shows an optional positional message, and its notation
  differs between §2.20 and §7.

#### Phase A — Independent proposals

Five panelists proposed `todo` and `unreachable` (TU). Web and Min proposed `todo` only (T).
Excerpts, each in the panelist's own words:

- **Systems:** "**`unreachable()` is a checked panic in every build mode. It is never UB.** This
  is the key systems point. Zig's `unreachable` and C's `__builtin_unreachable` let the optimizer
  assume the branch is dead. That is a memory-safety hole in a language with no `unsafe`."
- **Web/Scripting:** "**Stubbing is the 90% case.** Every web developer already knows the move:
  Kotlin `TODO()`, Python `raise NotImplementedError`, JS `throw new Error(\"TODO\")`." And:
  "There is no `unreachable()`. You write impossible branches as `panic(\"...\")`."
- **PLT:** "**Divergence.** §3.3 must define divergence by type: any call whose result type is
  Never diverges. A list of names such as \"panic, env.exit…\" breaks each time we add a builtin,
  and it does not compose with user functions that return Never." And: "`unreachable()` must stay
  a checked panic in every build mode. It must never lower to `__builtin_unreachable()`."
- **DevOps:** "The E0004 fix stays as written ... This is the strongest reason to keep `todo`:
  auto-fixes need a placeholder that type-checks and that tools can still find."
- **AI/ML:** "Models see `todo!()` and `unreachable!()` from Rust ... A model writing Blink will
  produce `todo()` and `unreachable()` whatever the spec says." And: "invariant: `unreachable`;
  unfinished: `todo`; anything else: `Result`."
- **Minimalism:** "**Preferred: P1. Add `todo` only. Reject `unreachable` and `unimplemented`.**"
  And: "The warning is the whole value. Without the warning, `todo` is only sugar, and I would
  vote no." Of `unreachable`: "It is `panic` with a fixed word in front."

#### Phase B — Debate highlights

One round. All six reported stable.

- **Systems** on the main split: "Under Option T, a library author who guards an invariant has two
  choices. They write `panic(\"unreachable\")`, which trips the library-panic lint, so they add
  @allow noise. Or they delete the check to quiet the lint, which is the worst outcome for a
  systems language."
- **Systems** switched to the type rule: "I switch to PLT's rule: any call whose result type is
  `Never` diverges. One rule keyed on the type is simpler for codegen ... My list form was a
  shortcut."
- **Systems** withdrew a codegen point from spec text: "cold/noreturn is a codegen choice and
  belongs in a codegen chore, not in sections/. The only normative part I keep: `unreachable` is a
  checked panic in every build mode and never UB."
- **Web** moved toward TU: "I still prefer T, but I accept TU. What decides it for me is the
  \"never UB, always a checked panic\" rule ... Rust and TS users (through `assertNever`) will
  expect it, and AI tools will generate it. I won't block TU."
- **PLT** dropped the test exemption: "I change my position to \"every call site, tests included\"
  (DevOps, AI/ML). A lint that depends on the context it sits in is one more rule to specify and
  test."
- **PLT** corrected a Phase A claim after F1: "I correct my Phase A claim. F1 shows Blink does have
  defaults, on keyword params after `--`. A positional `msg: Str = \"\"` is still not a signature
  a user could legally write."
- **PLT** on why a closed list fails: "Read as a closed list, it says nothing about a user
  `fn fail(m: Str) -> Never { panic(m) }`, so `fn f() -> Int { fail(\"x\") }` would raise a false
  E0311."
- **DevOps:** "\"panic already covers unreachable states\" is true at runtime and false for tools.
  Every tool that reads intent ... needs to know whether a panic is a stub, an invariant, or a
  real error."
- **AI/ML:** "If the spec writes `msg: Str = \"\"`, a model learning from the spec will infer that
  positional defaults are legal and generate invalid user signatures."
- **Minimalism** *(dissent on the main split)*: "In practice the library-panic lint then turns
  into \"rename `panic` to `unreachable`\", and the fix carries no new information. Either the
  lint is wrong or the exemption is. A second name should not exist only to get past a lint."
- **Minimalism** withdrew the double lint on `todo`: "I withdraw my position that the
  library-panic lint also applies to `todo`. `todo` already raises its own coded warning, so a
  second lint on the same call is noise."
- **Minimalism** preferred a required message: "**Preferred: make the message required** and
  change the §5 fix to `Cancelled => todo(\"Cancelled\")`. This removes V3, removes V5 (no default
  text exists), keeps the F1 rule clean, and makes the fix more informative."

#### Phase C — Final vote

- **Q1: Which built-ins to add: `todo` and `unreachable` (TU) or `todo` only (T)?**
  (4-2 in R1, Web and Minimalism dissent → Phase D, 5-1 in R2)
  - **Systems:** TU — "Runtime cost is zero, since it is the same panic entry with a different
    prefix. The gain is that the library-panic lint can tell an invariant guard apart from lazy
    error handling. Without it, authors either add @allow at every invariant site or delete the
    checks, and deleted checks are the worst outcome for a safe systems language."
  - **PLT:** TU — "It turns the claim \"this path is dead\" from a string into a name that a lint,
    a tool, or a later verifier can find. Never being UB keeps the system sound: a false claim
    gives a checked panic, not a hole in memory safety."
  - **DevOps:** TU — "Tools need to tell three intents apart: a stub, an invariant and a real
    error. Only TU gives each one its own name the compiler can see."
  - **AI/ML:** TU — "Models trained on Rust write `unreachable()` for dead branches whatever the
    spec says. Under T, each of those is an unknown-name error plus a repair round-trip. Under TU
    the first guess compiles."
  - **Web/Scripting:** *(dissent in R1)* T — "Since every option agrees `unreachable` must be a
    checked panic, it adds no behavior beyond `panic(\"...\")`, just a second spelling to learn.
    Fewer names means fewer \"which one do I use?\" questions."
  - **Minimalism:** *(dissent)* T — "If the lint cannot tell an invariant from misuse, fix the
    lint; do not add a name to get past it. `todo` passes the bar because a tool reads it (its
    warning). `unreachable` does not."

- **Q2: Where does the `todo` warning fire?** (6-0, ALL: every call site, tests included)
  - **Systems:** ALL — "One rule with no context exception is less to specify and test. A test
    stub has @skip, so the help line should point there."
  - **Web/Scripting:** ALL — "One rule with no context exceptions is easier to teach than \"warns
    except in tests\"."
  - **PLT:** ALL — "a lint that depends on context is a non-compositional rule that must be
    specified, tested and taught."
  - **DevOps:** ALL — "In a test, the help line points to `@skip(\"reason\")`, so each case gets
    one channel and CI can see every stub."
  - **AI/ML:** ALL — "One rule with no context exception is easier to learn from the spec and
    gives agents one signal to filter in `--json` output."
  - **Minimalism:** ALL — "A `todo` in a test is unfinished work, and `@skip` is the tool already
    sanctioned for that case."

- **Q3a: Does the library-panic lint fire on `todo` and `unreachable`?** (6-0, EXEMPT: neither)
  - **Systems:** EXEMPT — "todo already has its own coded warning, and a second diagnostic on the
    same span trains users to ignore both. unreachable is the sanctioned invariant form."
  - **Web/Scripting:** EXEMPT — "Two warnings on one call for one cause is noise that trains users
    to ignore warnings."
  - **PLT:** EXEMPT — Concern: "if the exemption keys on the name and not on resolution to the
    builtin, a user `fn unreachable` becomes a way around the lint. Key it on resolution."
  - **DevOps:** EXEMPT — Concern: "The exemption must key on the resolved builtin, not the name,
    or a user `fn todo` could slip panics past the lint."
  - **AI/ML:** EXEMPT — "Two diagnostics with different fixes on one span lead an agent to
    suppress one by reflex."
  - **Minimalism:** EXEMPT — Concern: "The exemption makes `unreachable` an escape hatch from the
    lint (see Q1)."

- **Q3b: Give the library-panic lint a name and code in this pass?** (5-1, LATER; AI/ML dissent)
  - **Systems:** LATER — "Assigning that lint a code is real design work (what counts as \"library
    code\", its default level), and it does not block this ticket."
  - **Web/Scripting:** LATER — "The exemption can refer to \"the §2.20 library-panic lint\" without
    a code."
  - **PLT:** LATER — Concern: "\"later\" may mean never. File the ticket in the same pass."
  - **DevOps:** LATER — "Naming and coding that lint touches the whole library-code definition
    (what counts as \"library\"?), and that is out of scope."
  - **Minimalism:** LATER — "The lint has open design questions (what counts as \"library code\",
    whether bare panic is ever fine), and this ticket should not grow to settle them."
  - **AI/ML:** *(dissent)* NOW — "A lint with no name or code cannot be filtered, suppressed with
    a named `@allow`, or cited in an agent's fix loop. Naming it in the same pass makes the rule
    precise and costs one row."

- **Q4: Is the message optional or required?** (5-1, OPT; Minimalism dissent)
  - **Systems:** OPT — "Bare todo() keeps the §5 E0004 fix valid as written and costs nothing at
    run time."
  - **Web/Scripting:** OPT — "Placeholders must be cheap to type, and a required message only
    produces `todo(\"todo\")`."
  - **PLT:** OPT — "With Q7 = SUBSTR, a bare call is still testable through its stable substring."
  - **DevOps:** OPT — "Bare `todo()` is the stub form users and agents type first."
  - **AI/ML:** OPT — "Making the message required would turn the common first guess into an
    error."
  - **Minimalism:** *(dissent)* REQ — "A required message removes Q5 and Q7 for `todo` and keeps
    F1 clean, with no builtin special case for optional arguments. It follows
    `skip(reason: Str)`."

- **Q5: How does the spec write the optional message?** (5-1, ARITY: two forms, builtin-only;
  DevOps dissent)
  - **Systems:** ARITY — "Two forms describe exactly what the compiler checks, and they never show
    a positional-default signature that F1 makes illegal for users."
  - **Web/Scripting:** ARITY — "F1 makes `msg: Str = \"\"` a signature users cannot write, and spec
    text should not teach illegal syntax."
  - **PLT:** ARITY — "only two arities avoids showing a positional default that F1 makes illegal
    ... Bring `assert` to the same form under a separate friction ticket."
  - **AI/ML:** ARITY — "The spec is the training data. Writing `msg: Str = \"\"` (or the `assert`
    form, which is the same) shows a positional default that F1 makes illegal, and models will
    copy it into user signatures."
  - **Minimalism:** ARITY — Concern: "Two forms read like overloading, which Blink does not have.
    The spec text should say this is builtin-only."
  - **DevOps:** *(dissent)* ASSERT — "Builtins with an optional positional message should have one
    notation, so LSP signature help shows the same form, such as `msg?: Str`, everywhere."

- **Q6: How does §3.3 cover the new built-ins?** (6-0, TYPE: a call whose result type is `Never`
  diverges)
  - **Systems:** TYPE — "PLT is right that my by-name list, read as closed, gives a false E0311."
    Concern: "the text must keep \"inference never chooses Never\" (§3.4) next to it."
  - **Web/Scripting:** TYPE — "\"Returns Never means it never returns\" is understood in seconds
    and never goes out of date."
  - **PLT:** TYPE — "Γ ⊢ f(ē) : Never already follows from the ordinary typing rule, so divergence
    keyed on that type is one compositional rule." Concern: "The rule needs a test with a user
    `fn fail(m: Str) -> Never`."
  - **DevOps:** TYPE — Concern: "The text must keep panic and env.exit as examples, so readers do
    not lose the concrete cases."
  - **AI/ML:** TYPE — "One general rule beats a list of names."
  - **Minimalism:** TYPE — "One rule keyed on the type replaces a list of names ... This is
    subtraction."

- **Q7: What does the spec fix about the panic message?** (5-1, SUBSTR: a stable substring per
  built-in, exact text left to the panic-message ticket; Minimalism dissent)
  - **Systems:** SUBSTR — "The substrings should be short (\"not yet implemented\", \"entered
    unreachable code\")."
  - **Web/Scripting:** SUBSTR — "Users will write `assert_panics(matching: \"not yet
    implemented\")` on day one, and that test must not break when [the panic-message work]
    rewords the text around it."
  - **PLT:** SUBSTR — "`assert_panics(matching:)` is the only normative contract on panic messages."
  - **DevOps:** SUBSTR — "A stable, documented substring per primitive is part of the tooling
    contract, and changing it is a breaking change."
  - **AI/ML:** SUBSTR — "Whatever substring we pick is frozen in effect, so it needs to be chosen
    with care now."
  - **Minimalism:** *(dissent)* DEFER — "Message text, including any stable-substring guarantee,
    is exactly the scope of [the panic-message ticket]. Splitting that contract across two tickets
    invites drift."

#### Phase D — Round 2 (Q1 only)

Focused replies to the other side's strongest point:

- **PLT:** "Whether a path is dead is a fact about the program's invariants. In general the
  compiler cannot decide it, so no lint can work it out from `panic(\"...\")`. The author is the
  only source of that information."
- **Systems:** "A rename from panic to unreachable is also not a silent bypass. It shows in the
  diff as an explicit \"this path is dead\" claim that a reviewer can challenge, while `@allow` on
  a panic says nothing about why."
- **DevOps:** "a fired `unreachable` writes a stable, documented substring to production logs ...
  Ops can then alert on \"a proven-dead path ran\" ... Q3b moved the lint to a later ticket, so the
  case for `unreachable` does not depend on the lint at all."
- **AI/ML:** "Any lint about intent can be silenced by stating the intent. So the real question is
  whether the stated intent is explicit and searchable, and only TU gives that."
- **Web/Scripting** (changed T → TU): "AI/ML's \"the first guess compiles\" is the \"just works\"
  test I apply to everything else ... Min's rename risk is real, but it is a docs and help-text
  problem, not a reason to drop the name."
- **Minimalism:** "TU therefore adds a permanent name to serve a lint we deferred. Adding a builtin
  later is cheap and breaks nothing, while removing one is a breaking change."

Re-vote (5-1, TU; Minimalism dissent):

- **Systems:** TU — "Only the author knows whether a panic is an invariant guard or an error path,
  so the language needs a name for that claim."
- **Web/Scripting:** TU — "The first guess compiles. Rust and TS users write `unreachable()` for
  dead branches whether we bless it or not."
- **PLT:** TU — "T leaves the claim in a string, or in an `@allow` that does not say which claim
  was made."
- **DevOps:** TU — "The case for it does not depend on the deferred library-panic lint."
- **AI/ML:** TU — "Under TU that statement is a claim reviewers can check and a grep can find."
- **Minimalism:** *(dissent)* T — "The case for TU rests on the §2.20 library-panic lint, and Q3b
  deferred that lint to its own ticket, so it has no defined scope ... Removing it after we ship
  it is a breaking change."

Conditions every panelist backed, Minimalism included ("If TU still passes, I endorse the
conditions"):

- `unreachable` is a checked panic in every build mode, never undefined behavior.
- The spec states that `unreachable` is for dead paths only.
- The library-panic lint's help names `Result` for error paths and never proposes a plain rename.

#### AI-first review

Learnability, Consistency, Generability, Debuggability, Token Efficiency: 5/5 pass.

### Final Spec

```blink
todo() -> Never
todo(msg: Str) -> Never
unreachable() -> Never
unreachable(msg: Str) -> Never
```

- Both built-ins are a `panic` at run time: untracked divergence, not an effect (§2.20).
- The two forms belong to these built-ins only; positional defaults stay illegal (§2.13).
- `unreachable` is a checked panic in every build mode. No mode, level or flag removes it.
- `todo` messages contain `not yet implemented`; `unreachable` messages contain
  `entered unreachable code`. Both substrings are stable for `assert_panics(matching:)`. The rest
  of the text is left to the panic-message work.
- `TodoInCode` (W0703) fires on each call that resolves to the built-in `todo`, test blocks
  included. In a test, the help names `@skip("reason")`. `unreachable` has no warning.
- The library-panic lint skips calls that resolve to either built-in, not calls by name. Its help
  names `Result` for errors and never proposes a plain rename. Its own name and code come later.
- §3.3: a call whose result type is `Never` diverges. The rule reads the callee's declared type,
  never its name, and inference never chooses `Never` (§3.4).
