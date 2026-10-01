[< All Decisions](../DECISIONS.md)

# `unwrap` / `unwrap_err` Panic Bound: `Debug` — Design Rationale

**Gap:** Nothing requires a Result's error arm to be showable, so the panic message of `unwrap` has no value to name. The spec states no signature or bound for `Result.unwrap` or `Result.unwrap_err`. Both are compiler intrinsics. E0514 requires Display only for a test body's `?`, and its help text names `.unwrap()` as the escape hatch. The compiler now prints a `<TypeName>` placeholder when the arm has no Display impl. That placeholder is an interim behavior, not a voted rule. The assert panel (6-0) set failure output to `debug()` with no placeholder, and left the `.unwrap()` payload to this panel.

**Supersedes:** [unwrap-panic-message-format.md](unwrap-panic-message-format.md).

**Result:** 6-0 on all three questions. Confirmation items N1-N6 confirmed 6-0. No Phase D (all votes were unanimous). AI-first review: 5/5 pass (Generability passes with the noted risk that Rust-trained models write `.expect(...)`, which a follow-up ticket decides).

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated in independent-proposal → debate → vote rounds.

Moderator fact correction, made before the vote: the brief said `Option.expect` and `Result.expect` exist. They do not. The tree has 0 `.expect(` calls in src/, lib/, tests/, examples/ and sections/. The compiler handles only `unwrap` and `unwrap_err` for Result. `expect_err` does not exist either.

#### Phase A — Independent proposals

All six put the same option first: a `Debug` bound on the arm that panics, rendering with `debug()`, no placeholder, and E0306 for a missing bound. Excerpts follow, verbatim.

- **Systems:**
  > **What the hardware sees.** On the success path, `r.unwrap()` is a tag load, a compare and a branch that is almost never taken. The bound does not change that. It only decides what the cold path can print. The compiler should put the cold path in one `noinline`, `cold`, `noreturn` function per arm type (`__blink_unwrap_fail_<E>(e, loc)`), not per call site. Code size then grows with the number of error types, not with the number of unwraps. All dispatch is monomorphized, with no vtables and no runtime type information.
  >
  > - `Result.unwrap()` needs `E: Debug` and `Result.unwrap_err()` needs `T: Debug`. If the bound is missing, the compiler reports E0306 at the call site, which is the code the assert vote chose.
  > - `Option.unwrap()` has no bound, because `None` carries no payload. The channel idiom `.recv().unwrap()` stays as it is.

- **Web/Scripting:**
  > The gap is a DX trap with two sides. If we keep the `<MyErr>` placeholder, users get a panic that tells them nothing, and that is a Stack Overflow question. If we require a hand-written Display, users must write `fmt` just to call `.unwrap()` in a script. Two facts decide it for me:
  >
  > 1. **No stdlib error type derives Debug.** `FsError`, `DBError` and `ConversionError` have a hand-written `impl Display`. `NetError` and `TestError` have neither Debug nor Display. Today, a user who unwraps a `NetError` gets the placeholder.
  > 2. **Display is never derived, and Debug is.** A Debug bound costs the user one word, `@derive(Debug)`. A Display bound costs a hand-written impl.

- **PLT:**
  > **Diagnosis.** Today `.unwrap()` has no type. It is an intrinsic whose behavior depends on whether an impl *exists* at the instance. Option (c), "drop the value if there is no impl", is a typecase on impl presence. It breaks parametricity. In `fn get[T, E](r: Result[T, E]) -> T { r.unwrap() }` the body is checked once, but what it does would then change per monomorphic instance. That is specialization through a back door. It is also the silent fallback the Container Debug vote banned ("relocates the banned silent fallback one level down"). Reject (c). The fix is to give the intrinsic a real signature.
  >
  > - **Typing rule.** The bound applies only to the arm the call panics on (E for `unwrap`, T for `unwrap_err`). That is the least the failure path needs. Rust does the same with `E: fmt::Debug`.

- **DevOps:**
  > A panic message gets read from a CI log, a crash report or an AI agent's terminal. The developer reads it, not the end user. Debug is the trait for that reader. The assert vote (6-0) already gave failure output to Debug and banned placeholders. If unwrap uses a second rule, a dev needs two traits to read one failing test.
  >
  > - **The fix is one line.** The LSP can apply the quick fix automatically: insert `@derive(Debug)`. Display can never be derived, so with option (a) every fix is a hand-written `impl Display`, and no tool can produce it.

- **AI/ML:**
  > **P1 (first choice): the panicked-on arm needs Debug, the message renders it with `debug()`, and there is no placeholder.**
  >
  > The rules:
  > - `Result[T, E].unwrap()` and `.expect(msg)` need `E: Debug`.
  > - `.unwrap_err()` needs `T: Debug`.
  > - Only the arm that can panic carries the bound.
  > - `Option.unwrap()` and `.expect()` need no bound, because None has no payload.
  >
  > 3. **`unwrap_err` breaks under Display.** The arm it panics on is `T`, often a List, Map or tuple. Those are Debug but never Display. Under option (a), `parse(..).unwrap_err()` on a `List[Int]` result fails, and no fix is possible.

- **Minimalism:**
  > The 6-0 assert decision already set a rule: developer-facing failure output renders with `debug()` and never uses a placeholder. An unwrap panic is the same kind of output. My proposal adds no new rule. It applies the existing one to two more call sites.
  >
  > The minimalism principle here: one trait (Debug), one code (E0306) and one no-placeholder rule, now covering asserts and unwrap alike.

Minimalism ranked "never print the value" second. The other five ranked a Display bound second. All six rejected ticket option (c), "drop the value when there is no impl".

#### Phase A.5 — the deduped option space

The moderator merged the six proposals into one option space.

**Q1: bound on the arm that `Result.unwrap` / `unwrap_err` panics on.**
- A. Debug bound. `unwrap` needs `E: Debug`, `unwrap_err` needs `T: Debug`. The message renders with `debug()`. No placeholder (`<TypeName>` and `<error>` are removed). A missing bound is E0306. `Option.unwrap` has no bound. First choice of all six.
- B. Display bound (ticket option a). Second choice of sys, web, plt, devops and aiml.
- C. No bound. The message never prints the value (`unwrap called on Err at file:line`). Second choice of min.
- Ticket option (c), "drop the value when there is no impl". Proposed by no one. All six reject it.

**V1: `Result.expect(msg)` and `expect_err`.**
- V1-a: state it now with the same bound as `unwrap`; message `<msg>: <debug>`.
- V1-b: leave it unspecified unless something needs it.

**V2: normative status of the panic text.**
- V2-a: pin the prefix only.
- V2-b: pin the prefix followed by `debug(value)`.
- V2-c: text non-normative, except the rendered value must appear.
- V2-d: informative only; the only normative contract stays the `assert_panics matching:` substring.

**Items no one opposed, listed for confirmation.**
- N1. Stdlib error types (ConversionError, FsError, DBError, NetError, TestError) get `@derive(Debug)` in the same change, before the bound is enforced.
- N2. E0514's help text, which names `.unwrap()` as the escape hatch, changes in the same commit.
- N3. A follow-up ticket asks whether test-body `?` / prop_check `?` (E0514) moves from Display to Debug. Not decided here.
- N4. `unwrap_or`, `unwrap_or_else`, `match`, `?` carry no bound. E0306 help points to them / to `match` + `panic`.
- N5. decisions/unwrap-panic-message-format.md is superseded.

#### Phase B — Debate highlights

Round 1. Four seats checked the tree and found no `expect`. Three changed V1. Four changed V2. All six marked "stable, ready to vote".

**V1: sys, web and aiml moved from V1-a to V1-b.**

- **Systems:**
  > I checked the tree. `.expect(` has zero uses in src/, lib/ and tests/. No compiler intrinsic handles `expect`, no stdlib fn declares it, and sections/ never names it. The context file said "Option.unwrap/expect exist". For `expect`, the tree does not support that. So V1-a would not "state an existing method". It would add a new method (and `expect_err`) to the language in a ticket about a bound. That is new surface area: a spec section, a lowering, and a test. Keep this ticket to its gap.
  >
  > My position is V1-b. Do not add `expect` here. Record one rule so that a later ticket inherits it: any Result method that panics on an arm needs Debug on that arm. If `expect` is added later, it follows that rule and prints `<msg>: <debug>`. I ask the seats who chose V1-a to check this fact before they vote.
- **Web/Scripting:**
  > My Phase A answer was V1-a. Given the fact above, I now hold V1-b: this ticket does not add `expect`. Add one sentence to the spec: "a future `expect(msg)` on Result takes the same bound as `unwrap`." A JS or Python developer writes `.expect("port")` in Rust out of habit. That is a real convenience, but it is a feature request, so it belongs in its own `type:feature` ticket, which I would support. A bound decision should not add a method in passing. YAGNI.
- **AI/ML:**
  > In Phase A I assumed `expect` existed and only needed its bound stated. It does not. Adding it is new API surface, and this ticket is a bound gap, not an API addition.
  >
  > The AI cost of adding it is real. It is a second way to unwrap, and so a new decision point at every call site: `unwrap` or `expect`? Rust-trained models will reach for `.expect("...")`. Today they get an unknown-method error, which is clear and costs one correction.
- **Minimalism:**
  > So the context line "Option.unwrap/expect exist" is wrong, and V1-a does not "state" something that already exists. It adds two to four new methods (`Result.expect`, `Result.expect_err`, `Option.expect`, and the message format for each) inside a ticket about a bound. Nothing in the corpus, the stdlib or the compiler calls them. Adding methods that nothing calls breaks YAGNI, and it is new surface, which should go through its own ticket with its own justification.
- **PLT** and **DevOps** held V1-a in round 1. PLT: "State `Result.expect(msg)` now, with `E: Debug`, message `<msg>: <debug(e)>`." DevOps: "State `Result.expect(msg)` now, with `E: Debug`, and `expect_err(msg)` with `T: Debug`." Both moved to V1-b in Phase C, after the moderator fact correction.

**V2: web moved from V2-c to V2-b, aiml from V2-d to V2-b, devops from V2-a to V2-b, and min moved from V2-b to V2-a.**

- **Web/Scripting:**
  > Min's argument convinced me. Users write `assert_panics(matching: "unwrap called on Err: NotFound")`, and that test is only stable if the spec pins the text. Under A, `debug()` output is itself specified: §3.6.1 sets the derive format, and strings are quoted. So the whole string `unwrap called on Err: <debug(e)>` is deterministic and costs nothing to pin.
- **AI/ML:**
  > A model writing a test will naturally write `assert_panics(matching: "unwrap called on Err: Empty")`. Under V2-a or V2-d, that test passes or fails depending on text the spec does not promise. A model cannot learn a non-normative format from the spec, so it will either over-match (fragile) or under-match (weak test).
  >
  > Pinning the value part costs nothing extra under Q1-A:
  > - The bound guarantees `debug()` exists.
  > - Debug's format is already normative (derive format, quoted Str, sorted Set).
  > - So `<debug(e)>` is fully determined by the spec.
- **DevOps:**
  > I move from V2-a to V2-b. [...] Reason: derived Debug output is already normative (sections/03_types.md:3112 and §3.6.1 Container Debug Rendering). So once the trait is pinned, the text after the colon is already fixed, and calling it non-normative only makes `assert_panics matching: "BadDigit(120)"` an unsupported use.
- **Systems:**
  > Pin `unwrap called on Err: <debug(e)>`, `unwrap_err called on Ok: <debug(v)>` and `unwrap called on None`. Leave the location suffix (` at <file>:<line>`) non-normative.
- **PLT:**
  > Normative: the message contains `unwrap called on Err: ` followed by exactly `debug(e)` (`unwrap_err called on Ok: ` + `debug(v)`; `unwrap called on None`).
  >
  > That is V2-b with the location left free. It is stronger than V2-a: under V2-a, a conforming compiler could print the type name after the colon, and that is the banned placeholder again.
- **Minimalism:**
  > I move from V2-b to V2-a. My reason for pinning was so that `assert_panics matching:` can match on the text, and the prefix already gives that. The part after the colon is `debug(payload)`, and the Debug format is specified elsewhere (§3.6.1), so pinning it here would state the same thing twice.

**Q1: PLT ranking A > C > B.**

- **PLT:**
  > **aiml's `unwrap_err` point decides A over B on soundness, not only on cost.** Under B, `unwrap_err` on `Result[List[Int], E]` needs `List[Int]: Display`. That impl does not exist and the user cannot write it (orphan rule). So B rejects a well-formed program, and the user has no fix except `match`.
  >
  > C (min P2): sound, but it throws away information the type system can give for free. I rank it above B now. A > C > B.
- **Minimalism:**
  > I withdraw C. All six rank A first, and A adds no rule: it reuses the 6-0 assert rule (Debug, `debug()`, no placeholder, E0306).

**Where the bound lives (PLT).**

- **PLT:**
  > It is checked at each call site. With a concrete receiver, the check is an impl lookup. In a generic body, the bound must be stated on the enclosing fn's binder. **Bounds are never inferred from a body.** If they were, adding an `.unwrap()` inside a function would silently change that function's signature. That is the non-local change this ticket exists to remove.

**Diagnostic detail (DevOps).**

- **DevOps:**
  > when the missing Debug is on a type parameter (`fn f[T, E](r: Result[T, E]) { r.unwrap() }`), E0306's primary span is the `.unwrap()` call. A secondary label goes on the binder `E`, and the fix-it inserts `: Debug` there. Point the fix-it at `@derive(Debug)` only when the innermost type is a concrete user type, so that the LSP quick fix never edits a stdlib or foreign type.

**N6 proposal: audit spec examples.** Sys, devops, min and aiml each proposed an N6 from PLT's knock-on item 2 (spec examples that call `.unwrap()` inside `@ensures`).

- **Systems:**
  > Spec examples that call `.unwrap()` inside `@ensures` / `@requires` need `E: Debug` too. The bound is part of typing, so it applies even where contracts are erased in a release build. Audit sections/ for `.unwrap()` on a Result whose error type is not Debug, and fix those examples in the same spec edit. I propose this as a confirmation item, not a vote.
- **DevOps:**
  > audit the spec examples that call `.unwrap()` inside `@ensures` and in other sample code. Each such error type must derive Debug, or the example must use `match`. Otherwise the spec's own examples fail E0306. The assert vote broke on this exact shape. Do it in the same edit.
- **Minimalism:**
  > The spec edit must audit every `.unwrap()` / `.unwrap_err()` in sections/ and add the derive or rewrite each one. I propose that the panel confirm N6 the same way as N1–N5.
- **AI/ML:**
  > Spec examples are the training set. Every spec example that unwraps a Result must type-check under the new bound, so either its E derives Debug or it uses `match`. Add "audit every `.unwrap()`/`.unwrap_err()` in sections/ and in `blink llms` output" to the spec-edit checklist, in the same commit as the bound.

**N4 ordering of help text.** AI/ML asked for `match` + `panic(...)` before `unwrap_or`: "`unwrap_or` changes behavior (no panic), so it is not a drop-in fix, and a model that applies the first suggestion it reads must not silently drop the panic." Web asked for `@derive(Debug)` first. The Phase C ballot settled on `@derive(Debug)` first, `match` + `panic` second, and `unwrap_or` only as a no-panic alternative.

#### Phase C — Final vote

- **Q1: Bound on the arm `.unwrap()` / `.unwrap_err()` panic on.** (6-0 for A)
  - *Option* A: Debug bound. `unwrap` needs `E: Debug`, `unwrap_err` needs `T: Debug`; message renders with `debug()`; no placeholder; missing bound = E0306 at the call; bounds never inferred from a body. Option.unwrap: no bound.
  - *Option* B: Display bound.
  - *Option* C: No bound; the message never prints the value.
  - **Systems:** A. — Reasoning: The bound does not change the success path, which stays a tag test and a branch. The failure path becomes one cold, noreturn renderer per arm type, monomorphized, with no vtable and nothing decided at run time. Debug is the only trait that works for every arm, because `unwrap_err` panics on `T`, and `T` is often a List, Map or tuple, which have no Display. A also gives one rule for all failure output, the same as `assert_eq`.
  - **Web/Scripting:** A. — Reasoning: The fix costs one word, `@derive(Debug)`, and the compiler can suggest it. A JS or Python developer gets it working in under a minute. The panic shows the real value with strings quoted, so `Err("")` and `Err(" ")` never look the same. It is the same rule as `assert_eq`, so users learn one rule for "show the value that failed". B cannot compile `unwrap_err()` when T is a List, Map or tuple. C throws away the value the developer needs most.
  - **PLT:** A. — Reasoning. A gives the intrinsic a real typing rule: a `where` constraint on the receiver's own type parameter, checked at each call and never inferred from a body. Behavior then depends only on the type, not on which impls happen to exist. That keeps parametricity. B rejects well-formed programs that cannot be fixed: `unwrap_err` on a container T needs a Display impl that the orphan rule forbids. C is sound but discards information the type system can supply.
  - **DevOps:** A. — Reasoning: Debug can be derived, so the fix is a one-line `@derive(Debug)` (or `: Debug` on a binder), and the LSP can apply it as a quick fix. A Display bound means a hand-written impl that no tool can generate. Debug quotes strings, so a panic log shows `Err("")` and `Err(" ")` differently. It also uses the same code (E0306) and the same rule as assert_eq, so one diagnostic pattern covers all failure output.
  - **AI/ML:** A. — Reasoning: One rule covers all failure output: "a value the compiler shows on failure must be Debug." asserts already follow it. The fix is one word, `@derive(Debug)`, so a model fixes the error in one mechanical edit. Under Display (B), it would have to write a `fmt` impl, and `unwrap_err` on a container `T` could not be fixed at all. Debug quotes strings, so a model that reads the panic sees the exact value it must correct. The rule matches Rust's `E: Debug`, but the spec states it in full.
  - **Minimalism:** A. — Reasoning: A adds no new rule. It applies the 6-0 assert rule (Debug, `debug()`, no placeholder, E0306) to two more call sites. The fix is a one-word derive. B costs a hand-written `fmt` per error type and cannot be satisfied for container `T` in `unwrap_err`. C is smaller on paper, but it throws away the one fact the reader needs, and A costs nothing extra.
  - Concerns:
    - **Systems:** Generic code that unwraps a type parameter must now carry `E: Debug`. That bound spreads up through callers, and some users will switch to `match` + `panic` only to avoid it.
    - **Web/Scripting:** Generic helpers that unwrap (`fn f[T, E](r: Result[T, E])`) will hit E0306 until users learn to write `E: Debug`. The help text must spell out that fix at the binder, or this will become a common question.
    - **PLT:** Generic code that unwraps must carry `E: Debug` on every binder up the call chain, and users may answer that with `match` + `panic("failed")`, which loses the value again.
    - **DevOps:** generic code that unwraps a type parameter must now carry `E: Debug`. If E0306 does not point a secondary label and fix-it at the binder, users will see an error at `.unwrap()` with no clear place to fix it.
    - **AI/ML:** Generic code that unwraps must now write `E: Debug` on the binder. A model that copies a bound-free generic example from old docs or old corpus code will hit E0306 until every example is updated (N6).
    - **Minimalism:** Every generic function that unwraps must now carry `E: Debug`, and if the stdlib derives (N1) land late, much of the corpus breaks at once.

- **Q2: `Result.expect(msg)`.** (6-0 for V1-b). DevOps and PLT moved from V1-a to V1-b after the moderator fact correction.
  - *Option* V1-a: state `Result.expect(msg)` in this decision, with `E: Debug`, message `<msg>: <debug(e)>`.
  - *Option* V1-b: do not add `expect` here. Record the rule that any Result/Option method that panics on an arm needs Debug on that arm; a later ticket decides whether `expect` exists.
  - **Systems:** V1-b. — Reasoning: `expect` does not exist anywhere in the tree, so V1-a adds a new method, with a lowering and a test, inside a ticket about a bound. Recording the rule "a method that panics on an arm needs Debug on that arm" makes sure a later `expect` gets the right bound without deciding now whether it should exist.
  - **Web/Scripting:** V1-b. — Reasoning: `expect` does not exist today, and a decision about a bound should not add a method in passing. The general rule ("a method that panics on an arm needs Debug on that arm") already settles what `expect` would need, so a later feature ticket only decides whether to add it. I would back that ticket. Scripting developers coming from Rust will look for `.expect("context")`.
  - **PLT:** V1-b. — Reasoning. The moderator's correction removes my premise. `expect` does not exist, and a bound decision should not add a method. The general rule ("a method that panics on an arm needs Debug on that arm") is the right abstraction. It fixes the typing of any future `expect` without deciding that `expect` should exist.
  - **DevOps:** V1-b. — Reasoning: my round 1 vote for V1-a assumed `expect` exists. The moderator's correction shows that it does not. Speccing a method with no implementation would put a signature in hover and completion that then fails at codegen, which is worse tooling than no entry at all. The general rule ("a method that panics on an arm needs Debug on that arm") keeps any future `expect` consistent at no extra cost.
  - **AI/ML:** V1-b. — Reasoning: `expect` does not exist, so adding it here is new API, not a bound fix. Every unwrap site would also gain a decision point: `unwrap` or `expect`? The general rule ("any method that panics on an arm needs Debug on that arm") already fixes the bound if `expect` comes later, so no future ticket can pick a second rule.
  - **Minimalism:** V1-b. — Reasoning: `expect` does not exist in the compiler, the stdlib, the tests or the spec, so V1-a adds a new method in a ticket about a bound. Burden of proof is on additions, and nothing calls `expect` today. V1-b records the general rule ("a method that panics on an arm needs Debug on that arm"), so a later `expect` ticket has nothing left to decide about bounds.
  - Concerns:
    - **Systems:** The rule could stay recorded only in this decision file and be forgotten, so a later `expect` ticket must cite it.
    - **Web/Scripting:** Until `expect` lands, users who want context in the message write `match` + `panic`, which is longer. Some may write `unwrap()` and lose that context.
    - **PLT:** A later `expect` ticket could reopen the bound rather than inherit it. The decision text must state the rule as binding on future panicking methods.
    - **DevOps:** users and models trained on Rust will write `.expect("...")` and get an unknown-method error. That error should suggest `.unwrap()` or `match`, and the later ticket should not stall.
    - **AI/ML:** Rust-trained models will keep writing `.expect("...")` and get an unknown-method error. The follow-up ticket must decide soon, or that correction loop stays a steady token tax.
    - **Minimalism:** A later ticket could add `expect` without citing the recorded rule, so the rule must sit in the spec text and not only in the decision file.

- **Q3: Normative status of the panic text.** (6-0 for V2-b). Min moved from V2-a to V2-b.
  - *Option* V2-a: pin the prefixes only (`unwrap called on Err:`, `unwrap_err called on Ok:`, `unwrap called on None`).
  - *Option* V2-b: pin the prefix followed by exactly `debug(value)` (`unwrap called on Err: <debug(e)>`, `unwrap_err called on Ok: <debug(v)>`, `unwrap called on None`); the `panic: ` lead-in and ` at <file>:<line>` suffix stay non-normative.
  - **Systems:** V2-b. — Reasoning: The spec already defines what `debug()` prints, so pinning the value after the prefix adds no new contract. It does make `assert_panics matching: "unwrap called on Err: NotFound"` a sound test. The location suffix stays free, because codegen changes it, for example to add a column or to strip it in a release build.
  - **Web/Scripting:** V2-b. — Reasoning: People write `assert_panics(matching: "unwrap called on Err: NotFound")`. That test only stays green across releases if the spec pins the text after the colon. `debug()` output is already specified, so pinning it adds no new rule and gives users a stable string to match.
  - **PLT:** V2-b. — Reasoning. The panic text is observable through `assert_panics matching:`, so it is part of the semantics whether we pin it or not. Pinning "prefix + exactly `debug(value)`" adds no new text, because `debug` is already specified. Under V2-a, a conforming compiler could print `<TypeName>` after the colon, and that is the banned placeholder.
  - **DevOps:** V2-b. — Reasoning: derived Debug output is already fixed by the spec (03_types.md:3112), so the text after the colon is fixed in practice. Making it normative lets `assert_panics matching: "BadDigit(120)"` and golden test logs rely on it. Leaving the `panic: ` lead-in and the location suffix out keeps the general panic format free for its own decision.
  - **AI/ML:** V2-b. — Reasoning: A model writing `assert_panics(matching: ...)` can only rely on text the spec promises. Under Q1-A, `debug(value)` is already fully set by the spec, so pinning it costs nothing and makes `matching: "unwrap called on Err: Empty"` a stable test. Under V2-a, that same test depends on text with no contract.
  - **Minimalism:** V2-b. — Reasoning: I move from V2-a to V2-b. Under V2-a, a compiler that drops the value still conforms, so the Debug bound would have no normative effect, and a rule that changes nothing is dead weight in the spec. V2-b makes the bound pay for itself in one clause: the payload appears, rendered by `debug()`. Leaving the `panic: ` lead-in and the location suffix non-normative keeps the pinned text minimal.
  - Concerns:
    - **Systems:** When the Debug format of a type changes, panic-text tests change with it, so a Debug format change becomes visible to users in two places.
    - **Web/Scripting:** If a later change edits the derived Debug format, it also changes pinned panic text and breaks users' `assert_panics` tests. Anyone who changes the Debug format must know this coupling exists.
    - **PLT:** Debug output for a type then becomes indirectly normative in panic tests, so a future change to Debug formatting breaks `assert_panics matching:` substrings.
    - **DevOps:** a later change to the Debug format, such as Set ordering or float printing, now also changes normative panic text, and that coupling must be kept in mind.
    - **AI/ML:** Any later change to Debug's format, such as Map key order, now also changes the pinned unwrap text. Spec edits to Debug must cross-reference this section.
    - **Minimalism:** Users may write `assert_panics matching:` against the non-normative `at file:line` suffix and then break when it changes.

- **Confirmation items N1-N6.** (6-0 confirm on each; no objection)
  - N1: stdlib error types (ConversionError, FsError, DBError, NetError, TestError) get `@derive(Debug)`, landing before the bound is enforced (two-step bootstrap).
  - N2: E0514 help text changes in the same commit.
  - N3: follow-up ticket: should test-body / prop_check `?` move from Display to Debug.
  - N4: `unwrap_or`, `unwrap_or_else`, `match`, `?` carry no bound; E0306 help names `@derive(Debug)` (or `: Debug` on a binder) and `match` + `panic`.
  - N5: decisions/unwrap-panic-message-format.md is superseded.
  - N6: audit every `.unwrap()` / `.unwrap_err()` in sections/ (and `blink llms` output) so each example type-checks under the bound, in the same spec edit.
  - Notes:
    - **Systems:** N1: confirm. The stdlib derives must be committed and regenerated before the compiler enforces the bound, or gen1 fails at str.bl:57.
    - **Web/Scripting:** N1: confirm. The derives must land before the bound is enforced. N4: confirm. The help line should list `@derive(Debug)` first.
    - **PLT:** N3: confirm (I favor moving to Debug in that ticket)
    - **DevOps:** N2: confirm. The new help must say that the `.unwrap()` escape needs `E: Debug`. N6: confirm. Include `blink llms` output, because AI users learn the rule from it.
    - **AI/ML:** N1: confirm. Order matters: the derives land first, and ConversionError, FsError and DBError keep their Display impls. N4: confirm. E0306's help should list `@derive(Debug)` (or `: Debug` on the binder) first, `match` + `panic` second, and `unwrap_or` only as a "no panic" alternative, because it changes behavior. N6: confirm. For my domain this matters most, because the spec examples are what models learn from.
    - **Minimalism:** N1 to N6: confirm.

#### Phase D

Not triggered. Every question passed 6-0.

### Final Spec

```blink
impl[T, E] Result[T, E] where E: Debug {
    fn unwrap(self) -> T
}

impl[T, E] Result[T, E] where T: Debug {
    fn unwrap_err(self) -> E
}

impl[T] Option[T] {
    fn unwrap(self) -> T
}
```

Panic texts:

```
unwrap called on Err: <debug(e)>
unwrap_err called on Ok: <debug(v)>
unwrap called on None
```

- The compiler checks the bound at the call. A missing bound is `E0306 TraitBoundNotSatisfied`. The compiler never infers a bound from a function body. A generic function that calls `unwrap` states `E: Debug` on its own binder.
- There is no placeholder. The `<TypeName>` and `<error>` fallbacks are removed.
- Any Result or Option method that panics on an arm needs `Debug` on that arm. This rule binds future methods, such as `expect`.
- The text after the prefix is exactly `debug(value)`. The `panic: ` lead-in and the ` at <file>:<line>` suffix are non-normative.
- `unwrap_or`, `unwrap_or_else`, `match`, `?` and `??` carry no bound.
- E0306 help order: `@derive(Debug)` (or `: Debug` on the binder) first, `match` + `panic` second, `unwrap_or` only as a no-panic alternative.
- The primary span is the call. A secondary label and the fix-it go at the binder. The `@derive(Debug)` fix-it appears only when the innermost type is a concrete user type.
- The stdlib error types (ConversionError, FsError, DBError, NetError, TestError) derive `Debug` and keep their Display impls. This lands before enforcement (two-step bootstrap).
- The E0514 help text changes. It no longer calls `.unwrap()` an escape hatch without a bound.
- `expect` is not added. A follow-up ticket decides whether Blink wants it.
- Follow-up ticket: whether test-body `?` moves from Display to Debug.
- Spec: §7.5 in sections/05_memory_compile_errors.md.
