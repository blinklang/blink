[< All Decisions](../DECISIONS.md)

# Partial Handler Lint and Derived Operations — Design Rationale

**Gap:** "Spec: general lint for partial handlers that auto-delegate ops. The Rand panel ([decisions/random-stdlib-module.md](random-stdlib-module.md), Q7a, 5-1 no in Phase D) rejected a Rand-only PartialRandHandler warning because §4.7.1 auto-delegation applies to every effect; plt/min/web/sys/devops all conditioned that vote on this general ticket being filed. Hazard: a mock that overrides only rand.int silently sends float/bytes to the enclosing handler (CSPRNG or suite seed), so a 'deterministic' test is flaky; same for any effect. Questions: which handlers it fires on (all? only in tests? only when the omitted op reaches a nondeterministic default?), the silencer (explicit default.op(args) call), naming/code, interaction with j5bf0h unseeded_rand_in_test. devops: must exist before the --seed + MockRand implementation ships."

The panelist texts below quote two local tracker IDs. `phs1td` is this gap. `j5bf0h` is the planned `unseeded_rand_in_test` lint from [decisions/test-seed-determinism.md](test-seed-determinism.md).

**Facts given to the panel** (summary): §4.7.1 says an omitted operation forwards "as if `default.op(args)` were written", and the type system does not tell partial from total handlers. A handler does not handle its own operations while an operation body runs. `Net.Connect` declares `request` with no body and verb operations with bodies, and the spec's `mock_net` implements only `request`. The §4.4.7 `always_low()` example implements only `int`. §8.10.4 did not say whether the runner installs a seeded `Rand` handler around each test.

**Result:**

- **Q1a (6-0, YES):** an operation with a body in the effect declaration is a derived operation. If the innermost handler omits it, that body runs at the call site, with the same handlers in force. Only an omitted primitive operation (no body) forwards to the enclosing handler. All six found the old text unsound: read literally, the spec's own `mock_net` sent `net.get` to the real network.
- **Q1b (6-0, INNERMOST):** the innermost handler of the effect owns its derived operations. The program does not search outer handlers for a clause.
- **Q1c (5-1, THIS; Min dissent for a separate ticket):** the rule is written in this change, as its own paragraph in §4.7.1.
- **Q2 (5-1, L3; Min dissent for no lint):** an opt-in marker on the effect declaration. The warning fires on every handler expression of a marked effect that omits a primitive operation, in all code. Second choices: Sys L4, Web L0, PLT L1, DevOps L4, AI/ML L1, Min L1.
- **Q2b (6-0):** the marker is `@handle_all`.
- **Q2c (6-0):** the stdlib marks `Rand` and `Time` only.
- **Q3 (6-0, R-YES):** the runner installs a seeded `Rand` handler, outermost, around each `test` block body. Its seed derives from the suite seed and the test name. `prop_check` keeps its own stream.
- **Q4 (6-0, J-CLOSE):** the planned `unseeded_rand_in_test` lint is closed. Under Q3 no `rand.*` call in a test reaches the OS random source.
- **Q5 (6-0 name, 5-1 code; Min dissent for W0705):** `PartialHandler`, W0545.
- **Q6a (6-0):** writing the operation with any body silences the warning. `@allow` and `[lints]` also work. No `@trusted` gate.
- **Q6b (6-0):** the diagnostic carries a machine-applicable fix that adds the missing operations with their exact signatures and the body `default.op(args)`.
- **Q6c (5-1, CHANGE; Min voted change-only-if-a-lint-passes, which gives the same result):** the `always_low()` example forwards `float` and `bytes` explicitly.

**Spec note on Q3:** the ballot said "the test's full name". The spec uses the bare test name, derived the same way as the existing per-property sub-seed (§8.10.4). Sys asked for this in Phase B ("derives from (suite seed, bare test name), like the property sub-seed"). Both give the `--filter` replay that the panel wanted.

**Follow-ups taken from the Phase C concerns:**

- A test where `net.get` inside a `request`-only mock must not reach the real network (Min, Q1a).
- The spec shows an outer handler that overrides `get` being bypassed by an inner mock (Sys, DevOps, AI/ML, Min, Q1b). Done in §4.7.1.
- The diagnostic note says the omitted operation reads the runner's seeded stream in a test, not the mock's seed (DevOps, AI/ML, Q3).
- The fix-it prints generic and sub-effect signatures exactly, and uses the operation signature, not the stdlib wrapper (DevOps, AI/ML, Q6b).
- `blink doc` shows the marker on the effect page (DevOps, Q2).
- If the runner's `Rand` handler ever gets an opt-out, the `unseeded_rand_in_test` case comes back (Min, DevOps, AI/ML, Q4).

**AI-first review:** 5/5 pass. Learnability, generability and debuggability pass: the rule is one sentence, the warning names the marker in its note, and the fix-it makes the silencer one edit. Token efficiency passes: stubs appear only for `Rand` and `Time` handlers. Consistency passes weakly: `@handle_all` is the first annotation on an effect declaration, but annotations on other declarations are an existing pattern.

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated in independent-proposal → debate → vote rounds. The texts below are the panelists' own, verbatim.

#### Phase A — Independent proposals

##### Systems

Claims checked against §4.4.1 (l.389), §4.4.7 (l.1148–1184), §4.7.1 (l.2112–2210), §4.12 (l.2579), §8.10.4 (l.1141–1295).

###### Proposal S1 (preferred): `PartialHandler` warns only where an omitted op can reach a real-world handler

**Rule.** The compiler warns at a handler literal or `handler E { ... }` declaration when BOTH are true:

1. **The handler omits an op that has no body in the effect declaration.** An op with an in-effect default body (the `Net.Connect` verbs, l.389) is not "omitted": its body runs and calls back into this handler. So the `mock_net` example that implements only `request` stays clean. That answers web's Http concern without a special case.
2. **The effect is a built-in effect.** Only built-in effects have a root handler that talks to the world (OS CSPRNG, real disk, real clock, real network, real DB; l.2579). A user-declared effect has no default handler. An omitted op there reaches an outer handler the user wrote, or panics with `<handle>.<op>`. Both are already loud.

Both conditions are syntactic. The compiler already has the op set and the effect origin when it desugars auto-delegation. The check is one set difference per handler, with zero runtime cost.

**Silencer.** Write the op as `default.op(args)`. Per l.2128 that is exactly what the compiler emits anyway, so the generated C is byte-identical. The silencer costs a source line and nothing at run time. `@allow(PartialHandler)` on the enclosing fn also works, as for every warning.

```blink
handler Rand {
    fn int(lo: Int, hi: Int) -> Int { lo }
}
```
```
warning[W0620]: PartialHandler: handler for `Rand` omits `float`, `bytes`
  --> tests/dice_test.bl:4:1
   |
 4 | handler Rand {
   | ^^^^^^^^^^^^ `float` and `bytes` go to the enclosing `Rand` handler
   = note: the enclosing handler can be the OS random source; a test that calls rand.float() is not repeatable
   = help: to delegate on purpose, write the op: `fn float() -> Float { default.float() }`
```

Clean form:

```blink
handler Rand {
    fn int(lo: Int, hi: Int) -> Int { lo }
    fn float() -> Float { default.float() }
    fn bytes(n: Int) -> Bytes { default.bytes(n) }
}
```

**Scope: all code, not only tests.** The compiler cannot see which handler is dynamically outside this one. A "read-only DB" handler built in `lib/` gets used from a test. The same bug exists in production: a "log reads" DB handler that forgets `write` sends writes to the real DB. A test-only rule needs a definition of "test context" that also covers helper factories in other files. That is more spec text and a weaker check.

**Spec/stdlib fallout.** `always_low` (l.1184) and the §4.7.1 `Handler[DB]` example would warn. Fix both with explicit `default.*`. That makes the delegation visible in the text we teach from. `mock_env` writes `default.args()` / `default.cwd()` explicitly (its `exit` already panics). `MockRand` and `mock_clock` implement every op and stay clean.

**Name/code.** `PartialHandler`. No W range covers effects today. I propose W062x ("effect/handler lints") inside the W06xx linting block, W0620 first. The code is free (W0600–W0604 and W0610–W0611 are used).

**j5bf0h interaction.** Separate. `PartialHandler` is about the handler's shape, at its definition site. `unseeded_rand_in_test` is about reach: a test block whose `Rand` calls reach the root handler. They do not overlap, so keep two names. A user who silences one must not silence the other.

**Tradeoffs (systems).**
- Plus: static, precise to the op, zero cost. The silencer is free in the generated code. That is the strongest argument for this form.
- Minus: mocking one op of a large built-in effect (Fs) needs a line for each other op. I accept that. Those extra lines are exactly the ops that would otherwise hit the real disk from a test, and a test that writes the real disk is a worse bug than a flaky one.
- Minus: this narrows web's noise concern but does not remove it. Ops with in-effect default bodies remove the Http case completely.

**Cross-language.** OCaml 5: unhandled effects propagate, which is visible because you match on effects explicitly. Koka requires all ops, and you write forwarding by hand. Rust mockall panics on an unexpected call by default, a strict-by-default stance. Blink chose implicit forwarding. A site warning is the cheapest way to make it visible again.

###### Proposal S2 (required alongside S1, or as a fallback): close fact 7 in the spec

Whatever we decide on the lint, §8.10.4 must state in plain words: **the test runner installs a `Rand` handler seeded from the test's sub-seed around each test block.** Then a delegated `rand.float()` in a test is reproducible with `--seed` (the seed prints on failure) and does not reach the OS. The cost is one seeded PRNG state per test block, a few words of memory. This turns the original Rand hazard from "flaky forever" into "flaky but replayable".

If the panel rejects S1, S2 alone fixes the Rand case but not Fs/Net/DB/Time. My vote still needs S1 for those.

###### Rejected: opt-in marker on the effect declaration (devops's form)

Every built-in effect would carry the marker, and user effects never need it (condition 2). The marker would be a syntax feature with one fixed value per effect: new grammar that tells the compiler nothing it does not already know.

##### Web/Scripting

In the Rand Phase D I argued that "a general lint would fire on the legitimate Http case and teach users to ignore it." I still hold that, so each proposal below is built to stay quiet on intended patterns. Ask the panel's test question: can a Python dev who writes `mock.patch` explain why this warning fired in 5 minutes? If not, they will turn it off.

###### W1 (my pick): seeded Rand in every test, plus a lint scoped to tests that skips derived ops

This proposal has three parts.

**(a) Fix the root cause in §8.10.4.** Say it plainly: the runner installs a seeded `Rand` handler around each `test` block. Its seed comes from the suite seed and the test name, the same way the property sub-seed does. A delegated `rand.float()` in a test then reaches a reproducible stream, and the failure output already prints the rerun line. This converts the worst case, a flaky test you cannot reproduce, into one you can reproduce from a printed seed, for every partial mock. It needs no warning. It also settles j5bf0h: no test ever reaches the OS CSPRNG, so `unseeded_rand_in_test` has nothing to detect. Close it, or narrow it to `prop_check` misuse.

**(b) Add the lint `ImplicitDelegation` (W0705, Linting).** It fires on a `handler E { ... }` written inside a `test` block body when the handler omits an op that has no body in the effect declaration. Ops with an in-effect body, such as the `Net.Connect` verbs, never count. The effect author already said those ops derive safely from the primitive op, so `mock_net` with only `request` stays clean.

```blink
test "low rolls lose" {
    with handler Rand {
        fn int(lo: Int, hi: Int) -> Int { lo }
    } {
        assert_eq(play_round(), Outcome.Lose)
    }
}
```

```
warning[ImplicitDelegation]: handler for `Rand` does not implement `float`, `bytes`
 --> game_test.bl:2:10
  |
2 |     with handler Rand {
  |          ^^^^^^^^^^^^ calls to `float` and `bytes` go to the enclosing handler
  |
  = note: in a test, the enclosing `Rand` handler is seeded from the suite seed (§8.10.4)
  = help: to delegate on purpose, write `fn float() -> Float { default.float() }`
```

**(c) Silencers.** There are two, and both already exist as concepts:
- An explicit `default.op(args)` silences that op and states the intent where the reader looks.
- `@allow(PartialHandler...)` would be a new name, so use `@allow(ImplicitDelegation)` on the enclosing fn. That covers the "I wrap only one op on purpose" case without boilerplate.

**Why tests only:** the hazard the ticket names is a test that is supposed to be deterministic and is not. Production decorators like §4.7.1's `logging_db` delegate on purpose, and the spec shows them as the intended pattern. A warning on the spec's own example is noise. The scope is lexical (inside a `test` block), so a user can predict it without knowing how the compiler works.

**Tradeoff:** a partial mock built in a helper fn and used from a test is not caught. I accept that miss. Part (a) still makes it reproducible, and a helper fn is a place where the author made a choice on purpose.

###### W2 (fallback if the panel wants the lint everywhere): primitive ops only, with a fn-level silencer

Same name, code and rule as W1(b), but it fires on every handler literal, not only in tests. The exclusion for ops with an in-effect body still applies. Production decorators add `@allow(ImplicitDelegation)` once per factory fn:

```blink
@allow(ImplicitDelegation)
fn logging_db(label: Str) -> Handler[DB] {
    handler DB {
        fn read(query: Template[DB]) -> Result[List[Row], DBError] {
            io.log("{label}: read {query}")
            default.read(query)
        }
    }
}
```

**Tradeoff:** every decorator handler pays one line, and the spec's own examples (`logging_db`, `always_low`, `mock_env`'s args/cwd) must change. This is acceptable only because the silencer is one line and the exclusion keeps Http quiet.

**Cross-language:** Kotlin needs `class X(b: B) : B by b` to opt in to delegating everything. Java's `default` interface methods are the precedent for "derived ops do not need overriding". TypeScript's `Partial<T>` mocks are a well-known source of `undefined is not a function` questions. Blink's silent version is worse because it does not crash, it just gives a wrong-stream value.

###### Rejected options

- **"Only when the omitted op reaches a nondeterministic default."** We cannot decide this statically, because the enclosing handler is dynamic. Any approximation is magic that users cannot predict.
- **An opt-in marker on the effect declaration (devops's form).** It is a second concept users must learn, and user effects will never set it. The in-effect-body rule already tells primitive ops from derived ops with no new syntax.
- **A warning per effect (`PartialRandHandler`).** Already rejected, and correctly.

###### A spec ambiguity this ticket must fix

§4.4.1 says verb ops are "default implementations that construct a `Request` and delegate". It also says omitted ops "auto-delegate" to the enclosing handler. These two rules disagree on what an omitted `get` does in `mock_net`:
- If the in-effect body runs and its `net.request` reaches the same mock, `mock_net` works.
- If `get` auto-delegates to the enclosing handler, `mock_net` sends real HTTP from a test.

§4.7.1 must state the rule: an omitted op with an in-effect body runs that body, and only an omitted op with no body auto-delegates. W1 and W2 both depend on this rule. Without it, the exclusion has no meaning.

###### Summary

| Question | W1 position |
|---|---|
| Where it fires | Partial handler literals in `test` blocks, primitive ops only |
| Silencer | Explicit `default.op(args)`, or `@allow(ImplicitDelegation)` on the fn |
| Name/code | `ImplicitDelegation`, W0705 |
| j5bf0h | Made moot by runner-seeded Rand. Close it or narrow it |
| Before `--seed` + MockRand ship | Part (a) must ship with `--seed`. The lint can come with them or right after |

##### PLT

###### Precondition (any option): pin the meaning of an omitted op that has an in-effect body

The spec is unsound today for its own Http example. §4.7.1 says an omitted op acts "as if `default.op(args)` were written". `mock_net` (§4.4.1) implements only `request`. So under the literal rule, `net.get(url)` inside `with mock_net(...)` skips `get`'s in-effect body and delegates to the *enclosing* handler: the real network. That is the exact hazard of this ticket, in the spec's flagship mock. Splicing the in-effect body into the handler does not save it either. By fact 3, `net.request(...)` inside that body, while the handler's op runs, also reaches the outer handler.

The only sound reading treats an op with an in-effect body as a **derived op**: a function over the primitive ops that a handler *may* intercept (Koka, Eff and Haskell class defaults work this way). Rule:

> When op `f` runs, the innermost handler's clause for `f` answers if it has one. If it does not, and the effect declares a body for `f`, that body runs at the call site, under the full handler stack. Only an omitted op **with no in-effect body** (a *primitive* op) delegates to the enclosing handler.

Now `mock_net` mocks every verb, and the sentence "implement `request()` only" becomes true. This also removes web's Phase D objection: the Http case never omits a primitive op, so no lint below fires on it. File it as its own spec ticket that blocks phs1td.

###### Proposal 1 (my vote): opt-in marker on the effect + `PartialHandler` warning

Which ops a handler must implement is a property of the **effect**, not of the call site. In Rand, `int`, `float` and `bytes` are three views of one stream. In Time, `now` and `sleep` are views of one clock. If a handler answers some views and delegates the rest, it mixes two interpretations of one resource, and that breaks a coherence rule the effect carries. DB is different: a decorator that overrides `read` and forwards the rest keeps one interpretation. Only the effect author knows which kind of effect they wrote, so the effect author opts in:

```blink
@whole_handler
pub effect Rand {
    fn int(lo: Int, hi: Int) -> Int
    fn float() -> Float
    fn bytes(n: Int) -> Bytes
}

test "low rolls" {
    with handler Rand {
        fn int(lo: Int, hi: Int) -> Int { lo }
    } {
        assert_eq(roll(), 1)
    }
}
```

```
warning[PartialHandler]: handler for `Rand` does not implement `float`, `bytes`
 --> dice.bl:3:10
  |
3 |     with handler Rand {
  |          ^^^^^^^^^^^^ `Rand` is marked `@whole_handler`
  |
  = note: omitted operations go to the enclosing handler, which can use a different random stream
  = help: implement them, or forward on purpose: `fn float() -> Float { default.float() }`
```

- **Fires on:** a handler expression for an effect marked `@whole_handler` (or one of its sub-effects) that omits a *primitive* op of the effect the handler names. It never fires for derived ops (see the precondition). A sub-effect handler counts only that sub-effect's ops, so `capture_log` stays clean.
- **Silencer:** write the op, even as `default.op(args)`. This is the same as an explicit `_ =>` arm: the author states the fall-through, and the language does not infer it. `@allow(PartialHandler)` per fn and `[lints]` per project work through the normal §4.16.8 channels. No `@trusted` channel, because suppression hides no record the language promises.
- **Name/code:** `PartialHandler`, in the effects range (E05xx/W05xx; W0501 already lives there): the next free W05xx outside W055x. Not W07xx.
- **Stdlib marks:** `Rand` and `Time`. Not `Net.Connect`, `DB`, `IO` or `Env` (`mock_env` stays partial by design).

Tradeoffs: the rule is fully static and local, a check over the handler expression and the effect declaration. It does not depend on the dynamic handler stack, so it composes: a handler factory in a library gets the same verdict wherever it is used. It never fires on decorators or on Http. The cost is one attribute on effect declarations, and user effects get no protection until their authors opt in. I accept that, because the hazard lives with stateful effects, and their authors know it.

###### Proposal 2 (second choice): general `ImplicitDelegation` on every effect

The same rule with no marker. It still needs the precondition, or every Http mock fires. It is uniform, but it fires on §4.7.1's own example (`logging_db`) and on `mock_env` (partial by spec). Every decorator then pays one forwarding line per omitted op. That teaches users that a supported pattern is suspect, and the type system explicitly does not treat partiality as suspect (§4.7.1). Better than nothing; worse than Proposal 1.

###### Rejected scopes

- **"Only in tests":** a handler is a value, often built in a library fn. Whether it reaches a test is a fact about the call site, not about the handler expression. The lint would give different verdicts for one handler depending on where it is used.
- **"Only when the omitted op reaches a nondeterministic default":** handlers are dynamically scoped. Which handler encloses a handler is not known statically in general, so the check cannot be decided.

###### Interaction with j5bf0h (`unseeded_rand_in_test`)

The two are separate, and neither one covers the other. `PartialHandler` is a static property of a handler expression (a partial mock leaks some ops). j5bf0h is a property of a test's handler stack at the call site (no mock at all). Both depend on fact 7. The spec must say plainly whether the runner installs a suite-seeded Rand handler around each test block:
- **If it does:** a leaked `rand.float()` is reproducible for a given `--seed`, but its stream is still independent of the `mock_rand` seed. `PartialHandler` still matters, and j5bf0h shrinks to code outside the runner.
- **If it does not:** the leak reaches the OS CSPRNG, and both lints matter.

Fix fact 7 in the same pass, since devops wants this in place before `--seed` and `MockRand` ship.

**Cross-language note:** Koka and Eff resolve derived ops as the precondition does. OCaml 5 handlers re-raise unhandled effects outward silently, which is the hazard here. OCaml's exhaustiveness warning plus an explicit wildcard is the model for this silencer.

##### DevOps

###### DevOps/tooling: Phase A proposals for phs1td

My test for each option is what the warning prints, what the LSP can do with it, and whether users will learn to ignore it.

###### One fact the brief leaves out, which changes the scope

Two kinds of ops can be left out of a handler:

- **An op with a default body in the effect declaration.** Examples are the verb ops of `Net.Connect` (§4.4.1). `mock_net` works only if an omitted `get` runs its own body, which calls `net.request`, and so reaches the mock's own `request`.
- **An op with no body.** Examples are `Rand.float` and `DB.write`. Leaving one out sends the call to the outer handler. This is the only case with the hazard.

§4.7.1 does not say which of these an omitted default-bodied op does. If it is sent to the outer handler, `get` runs in the outer handler's scope and `mock_net` does not catch it. The spec must say plainly that an omitted op with a default body runs that body inside the handler. Any lint should skip those ops. That alone removes web's Http objection, because the legitimate Http case never fires.

###### Proposal A (my choice): an opt-in effect marker, and a warning keyed to it

An effect can be marked `@handle_all`. A handler for a marked effect must write out every op that has no default body. An op it leaves out gets the warning. The stdlib marks `Rand` and `Time`. It does not mark `Env`, because `mock_env` is partial by design. Users can mark their own effects.

```blink
@handle_all
effect Rand {
    fn int(lo: Int, hi: Int) -> Int
    fn float() -> Float
    fn bytes(n: Int) -> Bytes
}

fn always_low() -> Handler[Rand] {
    handler Rand {
        fn int(lo: Int, hi: Int) -> Int { lo }
    }
}
```

```
warning[ImplicitDelegation]: handler for `Rand` does not give `float`, `bytes`
  --> src/dice.bl:9:5
   |
 9 |     handler Rand {
   |     ^^^^^^^^^^^^ `float` and `bytes` go to the enclosing handler
   = note: `Rand` is marked `@handle_all`: the enclosing handler can give a different value on each run
   = help: to delegate on purpose, write the op: `fn float() -> Float { default.float() }`
   = help: for a seeded mock, use `std.testing.mock_rand(seed).as_handler()`
```

- **Silencer.** Write `default.op(args)` for each op you leave to the outer handler. That is one line per op, and it records the intent at the place it applies. `@allow(ImplicitDelegation)` and `[lints]` also work in the usual way. It is not audit-gated, because no promised record is lost (§9.1 does not apply).
- **Name and code.** `ImplicitDelegation` is named for what the silencer removes. The code is `W0705`, the next free code in W070x misc linting. I do not want to open an effects W range for one warning.
- **Where it fires.** On every handler of a marked effect, not only in tests. A rule limited to tests cannot work at the handler, because the handler is often built in a library helper such as `fn always_low()` and only installed in a test. A seeded production handler, for example a game world seed, has the same bug.
- **LSP.** A quick fix, "Write missing ops as explicit delegation", adds the `default.op(args)` stubs with the full signatures. This is the same as rust-analyzer's "Implement missing members". Inside `handler Rand { }`, completion lists the missing ops first. Hover on the effect shows `@handle_all`, so the reason for the warning shows where the user looks.
- **`blink fmt`.** It formats the marker like any other declaration attribute. No new rules.
- **Spec changes that follow.** The §4.4.7 example `always_low()` would now warn. Change it to write `default.float()` and `default.bytes(n)`, which also teaches the silencer. The `logging_db` example in §4.7.1 stays clean, because `DB` is not marked.
- **Tradeoffs.**
  - Cost: new language surface, an attribute on effect declarations, which does not exist today.
  - Benefit: the rule is the same for every effect, users can extend it, and plt and min can derive it from the declaration alone. Nothing about Rand is hard-coded.
  - Noise is zero on legitimate partial handlers (`DB`, `Net`, `Env`). This matters most: a warning that fires on correct code trains users to put `@allow` everywhere.

###### Proposal B (fallback): a fixed list of effects, no marker

The same warning, but the compiler fires it only for a fixed list (`Rand`, `Time`). There is no new syntax, and the diagnostic is the same. It is weaker: user effects with the same hazard, such as a `Clock` or `Uuid` effect, get nothing. Also, the list lives only in the compiler, so it fails min's "derivable from the spec" test. Use it only if the panel refuses new attribute surface.

###### Rejected: one lint on every partial handler

It fires on `logging_db`, the spec's own example of good use. Go vet and ESLint both show what follows: users turn the rule off for the whole project, and then it catches nothing.

###### Interaction with j5bf0h (`unseeded_rand_in_test`)

These are different hazards:

- **This warning** is about the *wrong stream*. A `mock_rand(42)` test whose delegated `float` reads the suite stream passes or fails depending on `--seed`.
- **j5bf0h** is about *no seed*.

The spec must first say plainly whether the runner installs a suite-seeded `Rand` handler around every test block. §8.10.4 hints at this ("`--seed`-derived runner handlers") but does not say it, which is fact 7.

- **If the runner does install one:** j5bf0h has nothing left to catch. Every draw reproduces from the printed seed. Close j5bf0h as superseded.
- **If the runner does not:** j5bf0h stays a separate warning about direct `rand.*` use in tests. It does not overlap `ImplicitDelegation`.

My vote is for the runner to install one. The printed seed is the one tool we promised for reproducing a failure, so no draw in a test should go around it.

###### Sequencing (my Phase D condition, restated)

`ImplicitDelegation`, or Proposal B if the marker loses, must ship before `--seed` and `MockRand`. Without it, the first partial mock users write gives a flaky test and no diagnostic.

###### Cross-language note

- **rust-analyzer:** a trait impl that leaves out required items is an error, and the "implement missing members" quick fix makes that cheap to fix. Our case is a warning, but the quick fix is the same.
- **TypeScript:** `Partial<T>` mocks in Jest (`jest.Mocked`) have the same silent-fallthrough bug. The community answer is strict mock libraries that throw on a call nobody mocked. That is the same idea as opting in per effect.

##### AI/ML

###### aiml: Phase A proposals for phs1td (partial-handler lint)

###### Proposal 1 (preferred): one syntactic warning, `PartialHandler` (W0545), on every handler

**Rule.** A `handler E { ... }` expression gets a warning when it omits an operation of `E` (or of a sub-effect it covers) and that operation has **no body in the effect declaration**. The check looks only at the handler's text. It does not depend on the context, on the outer handler, or on whether the code is a test.

**Operations with a body in the effect are never "omitted".** The `Net.Connect` verbs (`get`, `post`, ...) have default bodies in the effect, so `mock_net`, which implements only `request`, stays clean. This removes web's Phase D objection ("fires on the legitimate Http case") at the rule level. Users do not have to learn to ignore the warning there.

**Silencer.** Write the forwarding op explicitly. There is no new syntax and no new annotation.

```blink
fn always_low() -> Handler[Rand] {
    handler Rand {
        fn int(lo: Int, hi: Int) -> Int { lo }
    }
}
```

```
warning[PartialHandler]: handler for `Rand` omits `float`, `bytes`
 --> src/dice_test.bl:3:5
  |
3 |     handler Rand {
  |     ^^^^^^^^^^^^ these operations go to the enclosing handler (§4.7.1)
  = note: in a test, the enclosing `Rand` handler may not be seeded, so this mock can give different results on each run
  = help: implement each operation, or forward it on purpose:
        fn float() -> Float { default.float() }
        fn bytes(n: Int) -> Bytes { default.bytes(n) }
  = help: `@allow(PartialHandler)` turns this off for the function
```

The fix-it is machine-applicable: the compiler knows each op's signature, so it can emit the exact stubs. With that, an LLM fixes the warning in one edit with no guessing. Clean forms:

```blink
handler Rand {
    fn int(lo: Int, hi: Int) -> Int { lo }
    fn float() -> Float { 0.0 }
    fn bytes(n: Int) -> Bytes { Bytes.zeroed(n) }
}

handler DB {
    fn read(query: Str) -> Rows {
        log.info("read {query}")
        default.read(query)
    }
    fn write(query: Str) -> Int { default.write(query) }
    fn admin(query: Str) -> Int { default.admin(query) }
}
```

**Stdlib consequence.** `mock_env` must write `fn args() -> List[Str] { default.args() }` and the same for `cwd`. That is a good result: the spec sentence "does not currently mock `env.args()`" then shows in the code where a reader looks for it. (I did not check the real signatures of `args` and `cwd`.)

**Why this shape, from the aiml side:**
- **No hidden context.** A model sees the handler text and knows if the warning fires. Rules based on scope ("only in tests", "only when it reaches a nondeterministic default") need knowledge the generator does not have at the handler: who installs it, and what is outside it. Models get context-dependent rules wrong. Rust's `#[must_use]` and Go vet's `copylocks` are effective because the site alone decides them.
- **One way to say "on purpose".** `default.op(args)` already exists, is documented in §4.7.1, and is what the compiler desugars to. A second marker (an attribute or an effect flag) adds a choice point with no gain.
- **The training corpus improves.** Today the spec's own `always_low` example teaches the hazard. Code that passes the lint documents its delegation. Future models learn from text that states its intent.
- **Token cost** is about 1 line for each forwarded op, and the compiler writes it. The worst case is a logging wrapper over a large effect, where `@allow(PartialHandler)` on the factory fn is one line.

**Required spec edits beyond the lint:**
1. §4.7.1 must state that an op with a body in the effect declaration runs that body when a handler omits it, and that the body does **not** go to the enclosing handler. The spec does not say this today. If an omitted `get` went to the outer handler, `mock_net` would reach the real network. The `mock_net` example only works under my reading. I ask plt to confirm.
2. Fix the `always_low` example (§4.4.7) to forward on purpose, or make it a counter-example that shows the warning.

**Code.** W0545 places it next to the handler errors (E0539, E0544). It is free today, but it starts a new W05xx sub-range for effects. If the panel prefers no new range, W0705 in "misc linting" is the fallback.

###### Proposal 2 (second choice): same warning, but only in test context

The warning fires only on handlers written inside `test` blocks, `*_test.bl` files, or fns whose return value flows into a test `with`. This produces less noise in production.

**Against:** sys's Rand Phase C case (a production `seeded` wrapper that omits `float` draws from the CSPRNG) stays silent. The rule "in test context" also needs a definition that the generator must know. I rank it below Proposal 1 but above doing nothing.

###### Rejected: opt-in marker on the effect declaration (devops Phase D idea)

```blink
@strict_handlers
effect Rand { ... }
```

Whether a handler gets the warning would then depend on an annotation in another file, often in the stdlib, where the model cannot see it. Every new effect also gets a new decision point ("mark it or not?"), and user effects will mostly stay unmarked, which hides the hazard where it is least visible. I vote against it unless Proposal 1 fails.

###### Interaction with j5bf0h (`unseeded_rand_in_test`)

Keep the two separate. `PartialHandler` is about one handler's text. j5bf0h is about a test that reaches the real Rand with no mock at all. Both depend on a gap in the spec (fact 7): **§8.10.4 must state in plain words whether the runner installs a suite-seeded `Rand` handler around each test block.**
- If it does, a delegated `rand.float()` in a test is deterministic for a given `--seed`. j5bf0h is then mostly unnecessary, and `PartialHandler`'s test note should say "seeded from the suite seed, not from your mock seed".
- If it does not, both lints matter.

I recommend the runner install a seeded handler. A model cannot predict nondeterminism that the spec does not state, and this choice makes the default case reproducible. Whichever way the panel decides, the note text in the diagnostic must match it.

**Cross-language note.** Kotlin/MockK `relaxed = false` and Mockito strict stubs fail on unstubbed calls, and teams like strict stubs because a silent fall-through hides test bugs. Koka and Eff have no partial-handler delegation, so Blink has no precedent to copy. The silencer-by-explicit-forwarding shape is closest to Rust's requirement to write each trait method when no default body exists.

##### Minimalism

###### Minimalism (min): Phase A

###### What the hazard really is

The hazard is not that a handler is partial. Partial handlers are a decided feature (5-0), and the spec uses them on purpose in three places: `mock_net` implements only `request`, `mock_env` leaves out `args`/`cwd`, and the `always_low()` Rand example says "float and bytes omitted". The real hazard is narrower: **inside a test, an op that the mock leaves out reaches a handler that is not deterministic.** A partial mock is only one way to get there. A test with no mock at all that calls `rand.float()` has the same problem. A lint on partial handlers points at the wrong thing.

A general "partial handler" warning has these costs:
- It fires on stdlib's own `mock_env` and on the spec's `mock_net` pattern, so stdlib ships `@allow`s on day one.
- It fires on the logging/caching handler shape in §4.4.1, which the spec says is the intended pattern. web is right that users learn to ignore it.
- Its silencer is `default.op(args)` stubs for each omitted op. That is the code auto-delegation exists to remove. A lint whose fix is "write the desugaring by hand" takes the feature back without saying so.

###### Proposal M1 (my first choice): no lint. Close the gap at the root, and subtract j5bf0h

1. **State one rule in §8.10.4 in plain words:** "The test runner installs a `Rand` handler around each `test` block. It seeds this handler from the test's sub-seed, which comes from the suite seed." The spec already says every handler installation "derives a deterministic sub-seed" and mentions "`--seed`-derived runner handlers". This only makes the existing sentence explicit (fact 7).
2. With that rule, an omitted op in a partial Rand mock reaches a seeded handler. The test is deterministic for a given seed, and the runner prints the seed on failure. That is the same promise every other test that uses `rand` gets. It is not silent flakiness.
3. **Close j5bf0h `unseeded_rand_in_test` as obsolete.** No test block can reach the OS CSPRNG, so the lint has nothing to detect. That removes a planned warning, which counts in this proposal's favour.
4. Docs only, in §4.7.1: "In a mock, write each op you depend on. An op you leave out goes to the enclosing handler." This becomes a convention, not language surface.

```blink
test "dice always low" {
    let low = handler Rand {
        fn int(lo: Int, hi: Int) -> Int { lo }
        // float and bytes go to the runner's seeded handler
    }
    with low {
        assert_eq(roll(), 1)
        let jitter = rand.float()   // same value for the same --seed
    }
}
```

There is no diagnostic. A failure prints `seed: 0x9f3a…`, and `--seed 0x9f3a… --filter "dice always low"` replays it.

**What about Time and Env?** A partial `Time` mock that leaves out `sleep` sleeps for real. That makes the test slow, not wrong. A real-clock read is the same hazard as an unmocked test that reads the clock, and no lint covers that case either. `mock_env.exit` already panics in place of delegating. No case left needs a compiler warning.

**Tradeoff:** the runner owns a little more (one handler per test block, and that work is already implied). In return we get zero new warnings, zero new names and one less planned lint. Cross-language: Go's `testing` relies on convention and `-shuffle`/seed printing, not on lints. Hypothesis and proptest seed the whole run and print the seed. Neither language warns about partial fakes.

###### Proposal M2 (fallback only, if the panel insists on a warning)

Keep it as narrow as possible:
- **Scope:** fires only on a `handler` expression written directly inside a `test` block, and only for an omitted op that has **no default body in the effect declaration**. Under this rule `mock_net`-style handlers that implement only `request` never fire (fact 4). Stdlib mocks never fire because they are not inside test blocks.
- **Silencer:** write the op. Any body counts: `default.float()`, `panic("unused")`, or a constant. Also `@allow(PartialHandlerInTest)` per fn.
- **Name/code:** `PartialHandlerInTest`, W07xx (misc linting). No new W range for effects.
- **No effect-declaration marker** (devops's opt-in). That adds an attribute to the effect grammar for one lint, and every effect author has to decide on it. That cost is too high.

```blink
test "clock frozen" {
    with handler Time.Read { fn now() -> Instant { Instant.epoch() } } {
        check_expiry()
    }
}
```
```
warning[PartialHandlerInTest] (W07xx): handler for `Time.Read` in a test omits `monotonic`
  --> tests/expiry_test.bl:2:10
   = note: `monotonic` goes to the enclosing handler, which may not be deterministic
   = help: write `fn monotonic() -> Instant { default.monotonic() }` to delegate on purpose
```
(The op names in this sketch are only an illustration. I did not check that `Time.Read` has these ops.)

If M2 passes, j5bf0h is still obsolete under M1's runner rule. Ship the two together, or close j5bf0h.

###### Vote position
M1. Second choice M2 only with the exact scope above (test blocks only, ops without a body only, no effect-declaration marker). I oppose a lint on every partial handler and an effect-declaration marker. Both add surface and fight a 5-0 decision.

#### Phase B — Debate (one round; all six sent STABLE: yes)

##### Systems

###### Q1 — omitted op with an in-effect body: P1, with plt's "at the call site" wording

**Position:** P1. I take plt's wording and drop my Phase A phrase "its body runs and calls back into this handler".

**Strongest argument against my old wording (plt):** "Splicing the in-effect body into the handler does not save it either. By fact 3, `net.request(...)` inside that body, while the handler's op runs, also reaches the outer handler."

**Answer:** plt is right. If the body ran as an op of `mock_net`, `mock_net` would be suspended, and `net.request` would go past it. The only correct reading is a derived op: when the innermost handler has no clause, the effect's body runs at the call site, under the full stack. The cost model also gets simpler. A derived op that no handler intercepts is an ordinary function call over the primitive op, with no extra handler frame.

**Where to file it:** I am indifferent, as long as it lands before or with phs1td. The lint's exclusion has no meaning without it. A separate blocking ticket is fine.

###### Q2 — scope: I move from L2 to L3

**Ranking:** L3 > L4 > L2 > L1. I oppose L5 and L0.

**Strongest argument against my L2 (plt):** "DB is different: a decorator that overrides `read` and forwards the rest keeps one interpretation." devops adds that L2 "fires on `logging_db`, the spec's own example of good use".

**Answer:** I accept this. L2 fires on DB, IO and Env decorators, which are correct code. The hazard plt names is mixing two interpretations of one stateful resource: one stream (Rand), one clock (Time). That is a property of the effect, and only its author knows it. My Phase A objection to the marker ("every built-in effect would carry it") was wrong. Only `Rand` and `Time` get marked. The marker costs nothing at run time and the check stays local: one set difference per handler expression against one declaration flag. I also concede the real-disk Fs case. A partial Fs mock is an isolation problem, and `MockFs` solves it, not this lint.

**Against L5:** plt says "The lint would give different verdicts for one handler depending on where it is used." A handler factory in `lib/` escapes it, and a production seeded handler (game world seed) gets nothing. **Against L0:** R-yes makes a delegated draw reproducible, but devops's "wrong stream" case remains. A test that uses `mock_rand(42)` still reads `float` from the suite stream, so it passes or fails depending on `--seed`. Outside tests, R-yes does nothing.

**Marker name:** `@handle_all`. It is a plain verb phrase that says what a handler must do. `@whole_handler` is a noun phrase that reads like a type.

**L4** is my fallback if the panel refuses new attribute surface. It gives the same codegen and the same check, but user effects cannot opt in.

###### Q3 — R-yes

**Position:** R-yes, with no change.

**Strongest argument against:** none was proposed. Even min backs it.

**Addition:** the spec should say the handler's seed derives from (suite seed, bare test name), like the property sub-seed, so that `--filter` replays it. The cost is one PRNG state per test block.

###### Q4 — j5bf0h: I change to J-close

**Strongest argument against my J-keep (devops):** "If the runner does install one: j5bf0h has nothing left to catch. Every draw reproduces from the printed seed."

**Answer:** correct. Under R-yes, no draw in a `test` block can reach the OS CSPRNG, so `unseeded_rand_in_test` has no case left. plt's "shrinks to code outside the runner" contradicts the lint's own name. Close j5bf0h as superseded, conditional on R-yes passing. If R-yes fails, I go back to J-keep.

###### Q5 — name and code

**Name:** I move to `ImplicitDelegation`. The strongest argument against `PartialHandler` is plt's own: a warning that fires on "partial" handlers "teaches users that a supported pattern is suspect", and §4.7.1 calls partial handlers a decided feature. `ImplicitDelegation` names the event the silencer removes.

**Code:** W0545. The check sits next to its errors, E0538 (unknown effect), E0539 (unhandled effect) and E0544 (default outside an op). No W054x code is in use; the only W05xx codes in use are W0501 and W0550–W0552. I drop W0620, because a new range for one warning is waste. W0705 is acceptable, but I do not prefer it.

###### "No disagreement" points

I confirm the silencer: any written body counts, plus `@allow` and `[lints]`, and no `@trusted`. I also confirm the `always_low` rewrite.

**Addition (from devops):** the diagnostic help should give the exact `default.op(args)` stubs, so that an LSP quick fix can apply them mechanically.

STABLE: yes

##### Web/Scripting

###### Q1 — omitted op with an in-effect body: P1, and the body runs at the call site (plt's form)

**Position:** P1. The body runs at the call site, under the full handler stack.

**Strongest against (variation):** devops: "runs that body inside the handler"; sys: "its body runs and calls back into this handler".

**Answer:** plt is right, and fact 3 settles it. While a handler's op runs, that handler does not handle its own ops. So if `get`'s body ran "inside the handler", its `net.request(...)` would skip the mock and reach the real network. That is the bug we are trying to stop, in the spec's flagship mock. Only the call-site reading makes "implement `request()` only" true. A JS dev's model is "a base-class method calls `this.request()`", and the call-site rule gives exactly that. Where it is filed does not matter to me. A separate spec ticket that blocks phs1td is fine.

###### Q2 — scope: I move from L5 to L3 (`@handle_all`). L0 is my second choice

**Strongest against my L5:** devops: "A rule limited to tests cannot work at the handler, because the handler is often built in a library helper such as `fn always_low()` and only installed in a test." plt: "The lint would give different verdicts for one handler depending on where it is used."

**Answer:** I concede, and the failure is in my own domain. Under L5, a user writes an inline mock in a test and gets the warning. Then they extract it into `fn low_rand() -> Handler[Rand]` for reuse, and the warning goes away. "Why did my warning disappear when I moved the code?" is exactly the Stack Overflow question I am supposed to prevent. A rule whose verdict changes when you refactor is not a rule a user can learn in 5 minutes.

L3 keeps what I wanted from L5, which is zero warnings on code the spec calls correct:
- `logging_db` and other DB decorators stay clean.
- `mock_net` with only `request` stays clean.
- `mock_env`'s args/cwd stay clean.

It also gives one verdict per handler, wherever it is used. Users almost never write the marker. They meet it only through the diagnostic note ("`Rand` is marked `@handle_all`"), which explains itself.

**Against L3 (aiml):** "an annotation in another file, often in the stdlib, where the model cannot see it." **Answer:** the diagnostic note and hover show the marker at the handler. That is the same as a `@deprecated` that lives in another file, and nobody finds that confusing.

**Marker name:** `@handle_all`. It reads as a plain instruction. `@whole_handler` needs a sentence to explain it.

**Required with L3:** devops's LSP quick fix that writes the missing ops as `default.op(args)` stubs. With it, the boilerplate cost is one keystroke.

**L0 second:** with R-yes, the worst case (a failure you cannot replay) is already gone. I would rather have no lint than a noisy one.

**I oppose:**
- **L1:** it fires on `logging_db` and `mock_env`, so users learn to put `@allow` everywhere.
- **L2:** it fires on DB decorators over a built-in effect. sys's Fs argument (a partial Fs mock writes to the real disk) is real, but stdlib can mark Fs `@handle_all` if the panel wants that. That is the marker doing its job.

###### Q3 — R-yes

**Position:** R-yes. No one argues against it.

**Nearest objection:** plt: "a leaked `rand.float()` is reproducible for a given `--seed`, but its stream is still independent of the `mock_rand` seed." **Answer:** true, and that is why I keep a lint (L3). Under any scope, the diagnostic note must say "seeded from the suite seed, not your mock's seed" (aiml's point).

###### Q4 — J-close

**Strongest against:** sys: "They do not overlap, so keep two names. A user who silences one must not silence the other." **Answer:** under R-yes, j5bf0h's target (a test that reaches the real Rand) cannot happen. A warning with nothing to detect is dead surface. plt's remaining case, "code outside the runner", is not a test, so `unseeded_rand_in_test` does not describe it. Close j5bf0h as superseded.

###### Q5 — name and code

**Position:** `ImplicitDelegation`, weakly held. It names what the silencer removes. `PartialHandler` names the shape, and the spec calls that shape correct, so a user reads the warning as "partial handlers are bad". Under L3 I can live with `PartialHandler`.

**Code:** not a user-facing concern. I accept W0545 (plt and aiml), which sits next to the handler errors E0539 and E0544, so I drop W0705.

###### "No disagreement" points

I confirm both:
- The silencer is to write the op. Any body counts. `@allow` and `[lints]` work, and the lint is not audit-gated.
- `always_low` changes to forward on purpose. Under L3 it must change, because `Rand` is marked.

STABLE: yes

##### PLT

###### Q1 — P1, with the place of evaluation pinned

**Position:** P1. I drop "file it as its own ticket". Put it in this ticket's spec edit, but make it a separate vote item.

**Strongest other argument:** devops: the body "runs inside the handler". sys: "its body runs and calls back into this handler".

**Answer:** the result sys describes is the right one. devops's wording gives a different result. Fact 3 says that while a handler's op body runs, the handler does not handle its own ops. So if `get`'s body runs *as the mock's op*, `net.request` goes past the mock to the real network. The rule must say where the body runs. Spec wording: "The body runs where the operation was called, with the same handlers installed. Its calls to the effect's operations reach the handler that took the call." A second variation needs a ruling too. Say an outer handler overrides `get` (a cache), and an inner `mock_net` implements only `request`. My rule: the **innermost handler of the effect** owns its derived ops. The body runs over the mock's `request`, and the program does not search outward for a `get` clause. Haskell class defaults work this way, and it keeps each handler's meaning local. If the program searched outward, an inner mock could leak to an outer real handler again, which is the hazard of this ticket.

###### Q2 — L3 first, then L1. Against L2, L5 and L0

**Strongest other argument (sys, against L3):** "The marker would be a syntax feature with one fixed value per effect: new grammar that tells the compiler nothing it does not already know." aiml adds that the marker sits "in another file … where the model cannot see it".

**Answer:**
- **To sys:** L2 uses "built-in" as a stand-in for "a hazard", and the stand-in is wrong. `DB` is built-in, and `logging_db`, the spec's own example of partial handlers, would warn under L2. A user `Clock` or `Uuid` effect has the Rand hazard, and L2 is silent on it. Where an effect was declared is not a semantic property, so L2 has the same flaw as the rejected `PartialRandHandler`, only one level up. The marker records a fact the compiler cannot derive: the ops share one resource.
- **To aiml:** a handler author already reads the effect declaration to get the op signatures. The diagnostic and hover show the marker as well.

L3 is the only option that fires exactly where implicit delegation is incoherent. I see that sys, aiml, web and min reject it. If L3 loses, my second choice is **L1, not L2**. L1 is uniform, purely syntactic, and composes, and with Q1 fixed it is quiet on Http. Its cost is one line per forwarded op on decorators, which aiml's machine-applicable fix-it makes cheap.

**L5 stays rejected.** A handler is a value. "Inside a `test` block" is a fact about where the expression is written, not about what the handler means. web admits the helper-fn miss, and helper fns are the usual way to write mocks.

**L0 (min):** min's strongest point is that the silencer "takes the feature back without saying so". For a marked effect that is the intent: there, implicit delegation is the bug. R-yes does not close the hazard. It makes the leak *reproducible*, but the leaked `float` still reads the suite stream and not the `mock_rand(42)` stream. A test that passes with one `--seed` and fails with another is still a wrong test. So L0 is the fallback I like least.

###### Q3 — R-yes

**Position:** R-yes. My Phase A text gave no direction; I now state one.

**Strongest other argument:** none proposed R-no.

**Answer:** state the scope precisely. The runner installs the handler outermost around the test body, with its seed taken from the test's sub-seed. Every user `with` therefore nests inside it. `prop_check` keeps its own per-property stream.

###### Q4 — I change from J-keep to J-close

**Strongest other argument (min, web, devops):** under R-yes, no test block can reach the OS CSPRNG.

**Answer:** that is correct. Under R-yes, the only case left for j5bf0h is code outside tests, and that is not what its name or rationale covers. Close it as superseded by R-yes. If R-yes fails, I go back to J-keep.

###### Q5 — `PartialHandler`, W05xx

**Strongest other argument (devops):** do not "open an effects W range for one warning"; use W0705.

**Answer:** the E05xx range is the effects range, and W0501 already shares that block, so the warning goes next to the handler errors it relates to. The spec's own word is "partial", so `PartialHandler` matches §4.7.1. I can accept `ImplicitDelegation`, which names what the silencer removes. I do not accept `PartialHandlerInTest`, because it names a scope I reject.

###### No-disagreement points

I confirm the silencer as listed: any written body counts; `@allow` and `[lints]` work; there is no `@trusted` gate. I confirm the `always_low` change. I add one point: the fix-it (stubs with the effect's exact signatures) should be machine-applicable under any lint option.

STABLE: yes

##### DevOps

###### Q1 — omitted op with an in-effect body

**Position:** P1, using plt's version: the body runs at the call site, under the full handler stack. I withdraw my wording "runs that body inside the handler".

**Strongest argument against my old wording (plt):** "Splicing the in-effect body into the handler does not save it either. By fact 3, `net.request(...)` inside that body, while the handler's op runs, also reaches the outer handler."

**Answer:** plt is right. Under my wording, `mock_net` sends real HTTP. Here is the tooling consequence: `go to definition` on `net.get` inside a handler that omits `get` must jump to the body in the effect declaration. `blink query` must show the op as "derived" (it has a body) or "primitive" (no body). I do not mind if this lives in its own ticket, but that ticket must block phs1td. Every lint option depends on it.

###### Q2 — scope

**Position:** L3 (an opt-in marker). Second choice L2, then L1, then L5, then L0.

**Strongest argument against (sys):** "The marker would be a syntax feature with one fixed value per effect: new grammar that tells the compiler nothing it does not already know." aiml adds that the warning "would then depend on an annotation in another file … where the model cannot see it."

**Answer:** P1 does not remove the whole Http case. It removes only the `mock_net` half. §4.4.1 also blesses "a handler overriding `get` directly (e.g., for caching GET responses)". That handler omits `request`, which is primitive, and on purpose. L1 and L2 both fire on it. They also fire on `logging_db`, because `DB` is a built-in effect (§4.4, l.139), so L2 does not spare it. So L1 and L2 fire on two patterns the spec shows as correct. That is web's "teach users to ignore it" with a spec citation.

The marker tells the compiler what it cannot work out: which effects are one resource seen through several ops (Rand, Time) and which are a set of separate ops (DB, Net). That is the thing the compiler does not already know.

On the marker being "in another file": the diagnostic names the marker in its `note:` line, and hover on the effect shows it. The user does not need to open the declaration to understand the warning. A model reads the warning text, and the warning states the reason.

sys's best point is that an FS mock that omits `write` hits the real disk. That is a real hazard, but it is a different hazard from this ticket's, which is a wrong random stream. I would accept marking `Fs` as well if sys wants it. The marker lets us pick per effect. L2 cannot.

**Against L5:** the spec's own failing shape is a factory fn (`always_low`, `mock_*`), and L5 misses exactly that.

###### Q3 — runner seeds Rand per test block

**Position:** R-yes. Nobody argued against it.

**Addition:** the diagnostic note must match the decision. Under R-yes, use aiml's wording: "in a test, `float` reads the suite-seeded stream, not this mock's seed". It must not say "the OS random source". The note must not describe a case the runner makes impossible.

###### Q4 — j5bf0h

**Position:** J-close.

**Strongest argument against (sys):** "They do not overlap, so keep two names. A user who silences one must not silence the other." plt adds: "j5bf0h shrinks to code outside the runner".

**Answer:** j5bf0h's name and rule are "*in test*". Under R-yes, no draw in a test reaches the OS, so the rule has nothing to detect. "Code outside the runner" is not a test, so it is not j5bf0h's case either. A warning name that cannot fire is a dead row in ERROR_CATALOG and a dead entry in `blink explain`. Close it, and file a new ticket if someone finds a real case.

###### Q5 — name and code

**Position change:** I take `PartialHandler`, not `ImplicitDelegation`. "Partial" is the word §4.7.1 uses ("Handlers may be **partial**"), so users search the spec for the term the warning prints, and they find the section. Three panelists already chose it.

**Code:** W0545, next to E0544 DefaultOutsideHandlerOp. The silencer is a `default.op(args)` call, and `blink explain W0545` sits next to the error that limits where `default` may appear. W05xx is not themed today (W0501 is method resolution), so this starts nothing new. W0705 is an acceptable fallback. I drop my W0705 preference.

###### "No disagreement" points

I confirm both: any written body silences the warning, and it is not audit-gated. The `always_low` example changes. I add one point for confirmation: the LSP quick fix that writes the `default.op(args)` stubs is part of the warning's contract, as aiml also said. It is not optional polish. A silencer that costs one line per op is only acceptable if the tool writes those lines.

STABLE: yes

##### AI/ML

###### Q1 — omitted op with an in-effect body

**Position: P1, plt's variation (the body runs at the call site, under the full handler stack).** I change my Phase A wording. "Runs inside the handler" (devops, sys, my own text) breaks on fact 3: while a handler's op runs, that handler is not in force, so `net.request(...)` inside a spliced `get` would reach the outer handler. That is the same leak again.

**Strongest argument against:** none on the substance. The only split is where to file it. plt says: "File it as its own spec ticket that blocks phs1td."

**Answer:** Either filing works. The panel should vote on the rule text here, because each lint option depends on it. If it goes in its own ticket, that ticket must block phs1td. A model learns "derived op = function over primitives, handler may intercept" from one sentence. Java `default` methods and Haskell class defaults teach the same thing, so models already have it in training.

###### Q2 — scope

**Position: I move from L1 to L3 (opt-in effect marker) first. L1 second, L2 third, L5 last. I reject L0.**

**Strongest argument against L1 (my Phase A pick)**, from min: "Its silencer is `default.op(args)` stubs for each omitted op. That is the code auto-delegation exists to remove." plt adds that L1 "teaches users that a supported pattern is suspect". I accept both. Under L1 the corpus fills with forwarding stubs and `@allow` on correct decorators (`logging_db`, `mock_env`). Models then learn that partial handlers are suspect, and that `@allow` is a reflex. Both lessons are wrong.

**Strongest argument against L3**, my own Phase A one, which sys, web and min share: the warning depends on "an annotation in another file ... where the model cannot see it". Why I now weigh it lower:
- The diagnostic names the marker ("`Rand` is marked `@handle_all`"), so the context comes to the model when it is needed. The model does not have to recall it in advance.
- The stdlib list (Rand, Time) is short and in the spec, so a model can learn it from the spec alone.
- Only effect authors get a new decision point, and they are rare. Handler writers, who are common, get none.
- plt's coherence argument is the correct one: "the hazard is a property of the effect". Rand ops are views of one stream. DB ops are not.

**Against L0 (min):** even under R-yes, a partial mock's leaked `float` reads the runner stream, not the mock's stream. A test that passes for one suite seed fails for another. Without `--seed`, each run gets a new suite seed, so the test is still flaky, even if it is replayable. A model writing `always_low` gets no signal. The spec's own example writes exactly this.

**Against L5:** scope that depends on context. A factory fn in a helper file gets no verdict.

**Against L2:** it fires on `logging_db` and `mock_env`, which brings back L1's noise for built-ins.

**Marker name:** `@handle_all`. It tells the handler writer what to do. `@whole_handler` describes, but does not tell.

###### Q3 — runner seeds `Rand`

**Position: R-yes.** No panelist argues against it. One addition: the sub-seed must come from the suite seed plus the test's full name, as web proposes. That way a `--filter` replay of one test gets the same stream as the full run, and the printed rerun line works as written. The note text in the `PartialHandler` diagnostic must match this rule.

###### Q4 — j5bf0h

**Position: I change to J-close.**

**Strongest argument against:** plt: "j5bf0h shrinks to code outside the runner."

**Answer:** outside the runner, a real `Rand` is production use, which is correct. It is not a hazard to warn about. Under R-yes, a test block cannot reach the OS CSPRNG, so the lint has nothing to detect. Leaving a planned warning that never fires is a fake decision point.

###### Q5 — name and code

**Position: `PartialHandler`, W0545.**

**Strongest argument against:** devops: `ImplicitDelegation` "is named for what the silencer removes".

**Answer:** §4.7.1 uses the words "partial" and "auto-delegation". "Implicit delegation" appears nowhere in the spec. A name that matches the spec section maps the warning to its documentation with no lookup. That is the cheapest path for a model reading the diagnostic. For the code, I agree with plt: put it in W05xx next to the handler errors E0539/E0544, outside W055x. It is not a hill for me. W0705 is acceptable.

###### "No disagreement" points

I confirm both. One addition: the diagnostic carries a machine-applicable fix-it that writes the missing ops with full signatures as `default.op(args)` stubs. This is the same as devops's LSP quick fix. It makes the silencer a single edit for a model, with no guessing.

STABLE: yes

##### Minimalism

###### Q1 — omitted op with an in-effect body (P1)

**Position: P1, with plt's wording ("that body runs at the call site, under the full handler stack").** This is not an addition. It repairs an unsound sentence, and it makes the spec's own `mock_net` example true. I support it whatever happens to the lint.

**Against (plt):** "Splicing the in-effect body into the handler does not save it either. By fact 3, `net.request(...)` inside that body, while the handler's op runs, also reaches the outer handler."

**Answer:** plt is right, and that is why devops's "inside the handler" and sys's "calls back into this handler" are the wrong words. An in-effect body is a plain function over the primitive ops. It runs where the call is, and the full stack answers its `net.request`. The spec text must not say "inside the handler". On placement, I agree with plt: file it as its own spec ticket. It holds under every Q2 option, including L0, so it must not depend on the lint vote.

###### Q2 — lint scope

**Position: L0 (no lint), unchanged. My ranking: L0 > L1 > L5 > L2 > L4 > L3.**

**Against (sys):** "a 'log reads' DB handler that forgets `write` sends writes to the real DB." Also devops: "a `mock_rand(42)` test whose delegated `float` reads the suite stream passes or fails depending on `--seed`."

**Answer:**
- The DB case: the compiler cannot tell "forgot `write`" from "chose to forward `write`". The 5-0 decision accepted that cost when it said the type system "does not distinguish partial from total handlers". A warning on every omission says that the feature is suspect, and that is what we decided not to say.
- The seed case: under R-yes the test fails for some seeds, and the runner prints the seed and the replay line. That is the same promise any test that calls `rand` gets. It is reproducible, so it is not silent flakiness.
- Note what every lint option shares. Its silencer is `default.op(args)`, which is the desugaring, written by hand. A lint whose fix is to write out what the feature removes takes the feature back. If the panel thinks omission is the hazard, it should say so openly and reopen auto-delegation for primitive ops. It should not keep the feature and warn on each use of it. I do not propose that. I name it so the vote is honest about what L1 means.

**Why L1 is my second choice, above L5 now:** with P1 in place, L1 no longer fires on Http. It needs no new syntax and no list of effects, and the reader decides it from the handler text alone. plt and devops showed that L5 gives different answers for one handler factory depending on where someone installs it. That is a real flaw, and I take it.

**Why L2, L4 and L3 rank last:** L2 and L4 each add a list in the compiler (all built-ins, or `Rand` and `Time`). That is the per-effect special case we rejected in the Rand panel, made larger. L3 adds grammar to effect declarations so that one warning can work. I keep my objection: new syntax, a choice for every effect author, and user effects that stay unmarked.

###### Q3 — runner seeds `Rand` around each test block

**Position: R-yes.**

**Against (plt):** "a leaked `rand.float()` is reproducible for a given `--seed`, but its stream is still independent of the `mock_rand` seed."

**Answer:** true, and it does not matter. A test needs to be deterministic for a given run seed, and the printed seed gives that. The draw does not need to come from the stream the author was thinking of. R-yes also fixes the test with no mock at all, which no lint option covers.

###### Q4 — j5bf0h

**Position: J-close.**

**Against (sys):** "They do not overlap, so keep two names. A user who silences one must not silence the other."

**Answer:** they do not overlap, but under R-yes j5bf0h has zero true cases left. Its rule is "a test block reaches the real Rand handler", and the runner rule makes that impossible. plt says it "shrinks to code outside the runner". But its name and its decision text are about tests, and outside tests no determinism is promised. A warning that cannot fire costs a name, a code and spec text. Close it as superseded.

###### Q5 — name and code (only if a lint passes)

**Position:** name `PartialHandler`. It describes what the reader sees, and three panelists picked it. `ImplicitDelegation` is also acceptable. Code: **W0705** in W070x misc linting. I object to opening a new W range (W062x or W05xx) for one warning. Open a range when a second effect lint exists. YAGNI.

**Against (aiml):** "W0545 places it next to the handler errors." **Answer:** the code number is not where users look. A range that holds one entry is structure that nothing needs.

###### "No disagreement" points

- Silencer (write the op; `@allow`/`[lints]`; not `@trusted`): agree, if a lint passes.
- `always_low()` example: change it only if a lint passes. Under L0 its comment ("auto-delegate to the enclosing handler") is correct. Add one sentence that in a test the enclosing handler is the runner's seeded `Rand`.

STABLE: yes

#### Phase C — Final vote

The Minimalism ballot was cast by a fresh Minimalism agent. The first agent failed three times on an API error. The fresh agent read Minimalism's own Phase A and Phase B text before it voted.

##### Systems

###### Q1a — YES
**Reasoning:** A derived op is a plain function over the primitive ops. Run at the call site, it costs one direct call and no handler frame, and the codegen is fully static when no handler intercepts it. Fact 3 rules out every other reading: a body run "inside the handler" sends `net.request` past the mock.
**Concern:** the lowering must resolve "does the innermost handler have a clause for `f`" per handler value, not per call site. A handler factory returning `Handler[Net]` hides its clause set, so this may need a per-op slot or flag in the handler record. That is cheap, but it must be designed and not assumed.

###### Q1b — INNERMOST
**Reasoning:** One lookup: the innermost handler of the effect either has the clause or the in-effect body runs over that handler. An outward search turns every derived-op call into a walk of the stack, and an inner mock can leak to an outer real handler again, which is the hazard this ticket fixes.
**Concern:** a user who stacks a caching `get` handler outside a `mock_net` will find the cache skipped. The spec needs one example that shows this.

###### Q1c — THIS
**Reasoning:** The rule is small, every lint option depends on it, and voting on it here as its own item costs nothing. A separate ticket adds a sequencing dependency with no gain.
**Concern:** if it is buried inside the lint edit, a later reader may think it depends on the lint vote. Write it in §4.7.1 as its own paragraph.

###### Q2 — L3 (second choice: L4)
**Reasoning:** The hazard is a property of the effect (several ops that are views of one stream or one clock), and only the effect author knows it. The check is one set difference per handler expression against one flag on the declaration: static, local, zero runtime cost. L4 is the same check with a compiler-fixed list. It is my fallback if the panel refuses the attribute.
**Concern:** user effects with the same hazard (a `Uuid` or `Clock` effect) stay unmarked unless their authors learn the marker exists.

###### Q2b — `@handle_all`
**Reasoning:** A plain verb phrase that says what a handler must do. It reads correctly in the diagnostic note.
**Concern:** a reader may think it makes omission an error. The spec must say it controls a warning.

###### Q2c — RT
**Reasoning:** Fs decorators (logging, caching) are correct partial handlers, and marking Fs would bring back the noise L3 avoids. The real-disk hazard is test isolation, and `MockFs` is the tool for it, not this lint.
**Concern:** a partial Fs mock in a test still writes to the real disk with no warning.

###### Q3 — R-YES
**Reasoning:** One seeded PRNG state per test block, installed outermost, seed from suite seed + full test name. It costs a few words of memory and makes every draw in a test replayable from the printed seed. It also covers tests with no mock at all, which no lint does.
**Concern:** if the runner's PRNG algorithm changes between compiler versions, old printed seeds stop replaying. §8.10.4 already limits the promise to one compiler version; keep that sentence.

###### Q4 — J-CLOSE
**Reasoning:** Under R-yes, no draw in a test block can reach the OS CSPRNG, so `unseeded_rand_in_test` has zero cases. A warning that cannot fire is a dead catalog row. (Conditional on R-yes; if R-yes fails, J-KEEP.)
**Concern:** none beyond the condition.

###### Q5a — `PartialHandler`
**Reasoning:** I move from `ImplicitDelegation`. Under L3 the warning says "this effect must not be partial", so the spec's own word is accurate, and it maps straight to §4.7.1. The "partial is suspect" objection weakens once the lint fires only on marked effects.
**Concern:** under L1 or L2 the same name would teach that a decided feature is bad.

###### Q5b — W0545
**Reasoning:** It sits next to E0539 and E0544, the handler errors the silencer relates to. W054x is unused, so this needs no new range.
**Concern:** W05xx has no theme in the catalog table today. Add a row for W054x so that the next effect lint goes there.

###### Q6a — YES
**Reasoning:** `default.op(args)` is the exact desugaring, so the silencer is byte-identical in the generated C. No promised record is lost, so `@trusted` does not apply.
**Concern:** none.

###### Q6b — YES
**Reasoning:** The compiler has each op's exact signature, so the stubs are mechanical. Under L3 the cost of the silencer is then one edit.
**Concern:** the fix-it must print parameter names exactly as declared, or the generated code needs a second edit.

###### Q6c — CHANGE
**Reasoning:** Under L3 with `Rand` marked, `always_low` warns as written. The spec example should show the delegation the program depends on.
**Concern:** none.

##### Web/Scripting

###### Q1a — YES
**Reasoning:** A JS or Python dev already has this model: a base-class method calls `this.request()`, and a subclass may override it. Only the call-site rule makes "implement `request()` only" true. Under any other reading, `mock_net` sends real HTTP from a test.
**Concern:** The spec text must not say "inside the handler" anywhere, or users and LSP authors will reason from the wrong model.

###### Q1b — INNERMOST
**Reasoning:** One rule to learn: the nearest handler answers, either through its own clause or through the effect's body over its own primitive ops. With OUTWARD, an inner mock can leak to an outer cache or real handler, and that is the bug this ticket exists to stop. "Why did my mock call the outer handler's `get`?" is a question I do not want on Stack Overflow.
**Concern:** A user who stacks a caching `get` handler outside a mock may expect the cache to apply. The spec needs one example that shows it does not.

###### Q1c — THIS
**Reasoning:** Every lint option and the `mock_net` example depend on this rule. Voting it here as its own item avoids a second ticket that only exists to block this one.
**Concern:** If it ships in the same edit as the lint, the larger diff could hide the soundness fix. The spec edit should keep it in its own paragraph in §4.7.1.

###### Q2 — L3 (second choice: L0)
**Reasoning:** L3 is the only option that stays quiet on every pattern the spec calls correct:
- `logging_db`
- `mock_net`
- the caching-`get` handler, which omits `request` on purpose (devops's point)
- `mock_env`

Its verdict also stays the same when a mock is extracted into a helper fn. Users meet the marker only through a self-explaining note. L0 is second: with R-yes the failure is replayable, and no lint beats a noisy lint. L1 and L2 fire on correct spec code, and that teaches users to reach for `@allow` without thinking.
**Concern:** User effects with a shared resource (a `Clock` or `Uuid` effect) stay unmarked unless the docs teach effect authors when to add `@handle_all`.

###### Q2b — `@handle_all`
**Reasoning:** It reads as a plain instruction to the handler writer. A dev understands it from the diagnostic note with no lookup.
**Concern:** None worth a vote. It is one more attribute name to document.

###### Q2c — RT
**Reasoning:** The hazard is a wrong stream or a wrong clock: one resource seen through several ops. A partial Fs decorator (for example, log writes and forward reads) is correct code, and real-disk isolation is `MockFs`'s job, as sys conceded. Mark only what is clearly incoherent when split.
**Concern:** Someone will ask why a partial Fs mock does not warn. The docs should point to `MockFs`.

###### Q3 — R-YES
**Reasoning:** This is the root fix for the 90% case: every draw in a test is replayable from the printed rerun line, with or without a mock. Seeding from the suite seed plus the full test name makes `--filter` replay work as printed.
**Concern:** Users may read "seeded" as "deterministic across runs" and be surprised when a partial mock passes with one suite seed and fails with another. The diagnostic note and the §8.10.4 text must say the seed is new each run unless `--seed` is given.

###### Q4 — J-CLOSE
**Reasoning:** Under R-yes, a test cannot reach the OS random source, so the warning has nothing to detect. A dead warning name in `blink explain` is confusing surface.
**Concern:** If R-yes is later weakened, j5bf0h's case comes back. The close note should say so.

###### Q5a — PartialHandler (changed from ImplicitDelegation)
**Reasoning:** devops and aiml are right that users search the spec for the word the warning prints, and §4.7.1 says "partial". Under L3 the warning fires only for marked effects, so the name no longer implies that every partial handler is suspect.
**Concern:** If the scope ever widens to L1, the name will read as "partial handlers are bad", against the 5-0 decision.

###### Q5b — W0545
**Reasoning:** It sits next to E0544, the error that governs `default`, which is the silencer. Users do not pick codes by range, so the location does not matter much.
**Concern:** None that affects users.

###### Q6a — YES
**Reasoning:** Any written body states intent, and the usual `@allow`/`[lints]` channels mean nothing new to learn. No promised record is lost, so it is not audit-gated.
**Concern:** None.

###### Q6b — YES
**Reasoning:** A silencer that costs one line per op is acceptable only if the tool writes those lines. With the fix-it, the fix is one keystroke in an editor and one edit for a model.
**Concern:** The fix-it must use the effect's exact signatures. A stub with a wrong parameter name or type turns a warning into an error.

###### Q6c — CHANGE
**Reasoning:** The spec's teaching example should show the delegation it relies on. Explicit `default.float()` lines make the behavior visible to the reader whatever Q2 decides.
**Concern:** If L0 wins, the explicit lines may read as required. Add one sentence saying they are optional and shown for clarity.

##### PLT

###### Q1a — YES
**Reasoning:** An op with a body in the effect is a derived op: a function over the primitive ops that a handler may intercept. Under the current §4.7.1 text, and under the "spliced into the handler" reading, `mock_net` sends real HTTP (fact 3). Only the call-site reading makes "implement `request()` only" true. All six panelists now accept this wording.
**Concern:** the spec text must not slip back to "runs inside the handler". If it does, fact 3 brings the leak back.

###### Q1b — INNERMOST
**Reasoning:** The innermost handler of an effect gives that effect its meaning, so derived ops come from that handler's primitives. Haskell class defaults work the same way: they are local to an instance. If the program searched outward for a clause, an inner mock could reach an outer real handler's `get`. That is this ticket's hazard over again, and the reader could no longer tell a handler's behavior from its text.
**Concern:** a user who stacks a caching `get` handler outside a `request`-only mock may expect the cache to answer. The spec should state this case in one example.

###### Q1c — THIS
**Reasoning:** The rule is its own vote item here, and every lint option and the L0 docs text depend on it. Writing it in this spec edit ships both together, so no window opens where the lint's "primitive ops only" clause has no meaning. min's point, that the rule holds under L0, is true. It is already met because Q1a is voted on its own.
**Concern:** if the edit lands in pieces, §4.4.1 and §4.7.1 can disagree for a time. Edit both sections in one commit.

###### Q2 — L3 (second choice: L1)
**Reasoning:** Whether implicit delegation is incoherent depends on the effect. Rand's and Time's ops are views of one resource, so mixing two interpretations breaks them. DB, Net and Env ops can be forwarded one by one. L3 records exactly that fact, and the check stays local and static: one set difference per handler expression. L2 and L4 use a compiler-side stand-in for the same fact, and L5 is non-compositional. If L3 loses, L1 is the uniform syntactic rule, and I prefer it to any list or context rule.
**Concern:** user effects that share a hidden resource stay unmarked unless their authors know the marker exists. The §4.7.1 text must teach it next to auto-delegation.

###### Q2b — `@handle_all`
**Reasoning:** I yield on the name. An imperative tells the handler writer what to do, and four panelists read it more easily. The semantics do not change.
**Concern:** "all" must be defined as "every primitive op". Otherwise users will write stubs for derived ops too.

###### Q2c — RT
**Reasoning:** The marker records "one resource seen through several ops". Fs ops act on one disk, but a partial Fs mock is an isolation problem (a real write), not a coherence problem, and `MockFs` is the right tool. sys conceded this in round 1.
**Concern:** users may read the stdlib marks as a full list of "dangerous" effects, which they are not.

###### Q3 — R-YES
**Reasoning:** This makes the default context of a test a total, reproducible interpretation of `Rand`, derived from (suite seed, full test name). The handler is installed outermost, so every user `with` nests inside it, and the order composes.
**Concern:** the per-test sub-seed derivation must be specified once and shared with `prop_check`'s derivation, so the two do not drift.

###### Q4 — J-CLOSE
**Reasoning:** Under R-yes, a draw in a test block cannot reach the OS source, so the lint has no case left. Production use of the real `Rand` is correct and needs no warning. This vote depends on R-yes passing.
**Concern:** if R-yes is later weakened, someone must reopen j5bf0h.

###### Q5a — `PartialHandler`
**Reasoning:** It matches §4.7.1's term ("Handlers may be partial"), so the warning maps to its section. Under L3 the warning means "partial on an effect that asks for whole handlers", so the name does not condemn partial handlers in general.
**Concern:** under L1, the name would read as "partial handlers are bad". Revisit the name if L1 wins.

###### Q5b — W0545
**Reasoning:** It belongs to the handler semantics next to E0539/E0544 in the effects block, and no W054x is in use.
**Concern:** none of substance. The code number is not where users look.

###### Q6a — YES
**Reasoning:** Writing the op with any body states the interpretation in the handler's text, which is all the lint asks for. No `@trusted` gate, because suppression destroys no record the language promises.
**Concern:** a `panic` body silences the warning, and it can hide an op that a test does use. That is the author's explicit choice, so I accept it.

###### Q6b — YES
**Reasoning:** The stubs are determined by the effect's signatures, so the fix is mechanical and exact. That makes the silencer cheap, and it answers min's "writes the desugaring by hand" cost.
**Concern:** for generic or sub-effect ops, the fix-it must print signatures after substitution, or the stubs will not compile.

###### Q6c — CHANGE
**Reasoning:** Under L3, `Rand` is marked, so the example must change. Even without a lint, the spec's teaching example should state its delegation and not rely on it silently.
**Concern:** none.

##### DevOps

###### Q1a — Derived ops rule
**Vote:** YES
**Reasoning:** This is the only reading under which `mock_net` does what the spec says it does. It also gives the tools one clear fact per op: "derived" (it has a body) or "primitive" (no body). `go to definition` on an omitted `get` jumps to the effect body, and hover can say "derived from `request`".
**Concern:** The spec text must say "at the call site", not "inside the handler", or implementers will build the leaking version.

###### Q1b — Who owns a derived op
**Vote:** INNERMOST
**Reasoning:** The user can predict the result from one handler: the handler they wrote answers everything its effect does. If the program searched outward, the result would depend on the dynamic stack, and no diagnostic or hover could explain it. That brings back the leak this ticket exists to stop.
**Concern:** An outer caching `get` handler goes quiet under an inner mock, and users may report this as a bug. The spec needs one example that shows it.

###### Q1c — Where the rule is written
**Vote:** THIS
**Reasoning:** The lint's diagnostic text ("omitted primitive ops") and the fix-it both depend on the rule. One spec edit keeps the words the same. It still gets its own vote item, so it does not depend on the lint passing.
**Concern:** If the lint vote stalls, the derived-op fix must not wait for it.

###### Q2 — Lint scope
**Vote:** L3. Second choice: L4.
**Reasoning:**
- L3 is the only option with zero warnings on code the spec calls correct: `logging_db`, a caching `get` handler that omits `request`, `mock_net` and `mock_env`. A warning that fires on correct code teaches users to put `@allow` everywhere.
- The note names the marker, and hover shows it, so the reason is visible where the user looks.
- L4 gives the same diagnostic with no new grammar, which is why it is my fallback over L1. L1 fires on DB decorators.
**Concern:** User effects with the Rand hazard stay unmarked until their authors learn about the marker. `blink doc` must show the marker on the effect page.

###### Q2b — Marker name
**Vote:** `@handle_all`
**Reasoning:** It is a plain instruction to the handler writer, and it reads well in the diagnostic note: "`Rand` is marked `@handle_all`". `@whole_handler` needs an explanation.
**Concern:** Users may read it as "every op, including derived ones". The docs must say that it covers primitive ops only.

###### Q2c — Stdlib marks
**Vote:** RT
**Reasoning:** The hazard here is one resource seen through several ops: one stream, one clock. Fs is a set of separate ops, and a logging or read-only Fs decorator is correct code. Real-disk isolation is `MockFs`'s job, as sys conceded.
**Concern:** Someone will ask for Fs later. That should be a new decision based on real reports, not scope creep.

###### Q3 — Runner seeds Rand per test block
**Vote:** R-YES
**Reasoning:** The printed seed and rerun line are the one way we promised to reproduce a failure. No draw in a test should go around them. Deriving the seed from the full test name makes the `--filter` replay line in the failure output true.
**Concern:** The PartialHandler note must say "suite-seeded stream, not this mock's seed". If it says "OS random source", it describes a case the runner makes impossible.

###### Q4 — j5bf0h
**Vote:** J-CLOSE
**Reasoning:** Under R-yes, it cannot fire in a test, and code outside tests is not its case. A warning that never fires is a dead row in ERROR_CATALOG and a dead `blink explain` page.
**Concern:** If R-yes is later weakened (for example, opt-out per test), j5bf0h must be reopened.

###### Q5a — Name
**Vote:** `PartialHandler`
**Reasoning:** §4.7.1 uses the word "partial", so a user who searches the spec for the warning's name finds the section that explains it. Under L3, the note line already says why this partial handler is the problem, so "partial handlers are bad" is not the lesson users take away.
**Concern:** Under L1 or L4 the name reads more like "partial handlers are suspect". The note must carry the reason.

###### Q5b — Code
**Vote:** W0545
**Reasoning:** `blink explain W0545` sits next to E0544 DefaultOutsideHandlerOp, the rule that limits where the silencer's `default` may appear. W05xx is not themed today, so this opens no new structure.
**Concern:** None worth a fight. W0705 is fine too.

###### Q6a — Silencer
**Vote:** YES
**Reasoning:** Writing the op is visible, local, and leaves no trace in the output code. `@allow` and `[lints]` follow §4.16.8, and nothing about this warning needs an audit record.
**Concern:** Users may silence it with a constant body when they meant to delegate. That is their choice, and the code shows it.

###### Q6b — Fix-it in the warning's contract
**Vote:** YES
**Reasoning:** A silencer that costs one line per op is acceptable only if the tool writes those lines. The compiler has the exact signatures, so the fix-it is machine-applicable. The LSP and `blink fix` both apply it.
**Concern:** Generic or sub-effect signatures must print with their exact spelling, or the stub does not compile.

###### Q6c — `always_low()` example
**Vote:** CHANGE
**Reasoning:** Under L3 or L4 it must change, because `Rand` warns. Under any option, the example people copy most should show delegation that is on purpose.
**Concern:** None.

##### AI/ML

###### Q1a — Derived-op rule
**Vote:** YES
**Reasoning:** This is the only reading under which the spec's own `mock_net` works. Models already know the shape from Java `default` methods and Haskell class defaults: a derived op is a function over primitives. The rule takes one sentence, and a model can learn it from the spec alone.
**Concern:** If the spec text keeps any "inside the handler" wording, models will generate splice-style mental models and mis-predict which handler answers `net.request`.

###### Q1b — Owner of a derived op
**Vote:** INNERMOST
**Reasoning:** A model can predict the outcome by looking at one handler: the clause if it exists, otherwise the in-effect body over this handler's primitives. An outward search makes the answer depend on the dynamic stack, which the generator cannot see. It would also bring back the leak this ticket exists to stop.
**Concern:** An outer cache handler that overrides `get` is silently bypassed by an inner mock. The spec needs one example that shows this.

###### Q1c — Where the rule is written
**Vote:** THIS
**Reasoning:** The panel is voting the rule text now. Making it a separate item in this edit keeps it independent of the lint vote, which was min's goal, without extra ticket churn. Every lint option uses this rule to define "omitted".
**Concern:** The derived-op rule may get buried in the lint text. It must land in §4.7.1 as normative text, not as a note on the warning.

###### Q2 — Lint scope
**Vote:** L3. **Second choice:** L1.
**Reasoning:** Handler writers, who are common, get zero new decision points. Effect authors, who are rare, get one. The diagnostic `note:` names the marker, so the context comes to the model when it needs it. L3 is the only option that stays silent on all three patterns the spec calls correct (`logging_db`, the caching `get` override, `mock_env`). That keeps the training corpus free of reflexive `@allow` and forwarding boilerplate on correct code. L1 is my fallback because it is uniform and local, with the fix-it carrying its cost.
**Concern:** User effects with a shared-resource hazard (a `Clock` or `Uuid` effect) will mostly stay unmarked, so the protection reaches stdlib only in practice.

###### Q2b — Marker name
**Vote:** `@handle_all`
**Reasoning:** It is a verb phrase that tells the handler writer what to do. A model reading `@handle_all` on an effect generates every op without needing a definition. `@whole_handler` needs an explanation.
**Concern:** "all" is slightly loose, because derived ops are exempt. The spec sentence must say "every operation with no body".

###### Q2c — Stdlib marks
**Vote:** RT
**Reasoning:** Rand and Time are each one resource seen through several ops, which is the coherence hazard this ticket is about. A partial Fs mock is an isolation problem that `MockFs` addresses, and sys conceded this. Marking Fs would force forwarding stubs on legitimate Fs decorators.
**Concern:** A partial Fs test mock can still write to the real disk with no warning.

###### Q3 — Runner seeds Rand
**Vote:** R-YES
**Reasoning:** It turns an unpredictable outcome into one that is stated in the spec and can be replayed from the printed seed. Deriving the seed from the suite seed plus the full test name makes the printed `--filter` rerun line exact. A model can then trust the line as written.
**Concern:** The diagnostic note text and the docs must say "suite-seeded stream, not your mock's seed", or users will conclude the mock seed covers delegated ops.

###### Q4 — j5bf0h
**Vote:** J-CLOSE
**Reasoning:** Under R-yes the lint has no true case left. A warning name that cannot fire is a dead entry that models will still cite and try to `@allow`.
**Concern:** If R-yes slips in implementation, the ticket must reopen, not stay closed on a promise.

###### Q5a — Name
**Vote:** `PartialHandler`
**Reasoning:** §4.7.1 uses the word "partial", so the warning name maps directly to its spec section. Most panelists (aiml, plt, devops, min) now prefer it.
**Concern:** Users may read it as "partial handlers are bad". The `note:` line must say that the effect is marked, which is what makes this partial handler a problem.

###### Q5b — Code
**Vote:** W0545
**Reasoning:** It sits next to E0539 and E0544 (the `default` rule the silencer uses), so `blink explain` lookups land near related entries. W05xx is already shared with W0501, so it opens no new themed range.
**Concern:** None of substance. W0705 would also work.

###### Q6a — Silencer
**Vote:** YES
**Reasoning:** "Write the op" is one rule with no new syntax, and it records the intent at the site.
**Concern:** None.

###### Q6b — Fix-it in the warning's contract
**Vote:** YES
**Reasoning:** With exact-signature stubs, a model fixes the warning in one edit with zero guessing. That is what makes the silencer's line cost acceptable.
**Concern:** The stubs must use the op's signature (`int(lo, hi)`), not the user-facing wrapper (`rand.int(range)`), or the fix-it will teach the wrong form.

###### Q6c — `always_low()`
**Vote:** CHANGE
**Reasoning:** It is the example models copy. Showing explicit `default.float()` teaches the intent, and under L3 the current version would warn.
**Concern:** None.

##### Minimalism

###### Q1a: Derived ops rule
**Vote:** YES

**Reasoning:** This is not a new feature. It repairs a sentence that is unsound today and makes the spec's own `mock_net` example true. An in-effect body is a plain function over the primitive ops, so "at the call site, under the full handler stack" is the only wording that holds under fact 3. It is needed under every Q2 option, L0 included.

**Concern:** Implementers may still lower the body as a spliced handler clause, so the spec needs a test where `net.get` inside a `request`-only mock must not reach the real network.

###### Q1b: Who owns a derived op
**Vote:** INNERMOST

**Reasoning:** The innermost handler's meaning stays local: you read one handler and know what `get` does. An outward search adds a lookup rule and brings back the leak this ticket exists to stop, because an inner mock could send `get` to an outer real handler. Haskell class defaults work this way, so it costs no new idea.

**Concern:** A user who stacks a caching `get` handler outside a `request`-only mock may expect the cache to answer, and the spec must show that case in an example.

###### Q1c: Where the rule is written
**Vote:** SEPARATE

**Reasoning:** The rule fixes the semantics of auto-delegation and is true whatever happens to the lint. If it rides in the lint ticket, a later change to the lint (or its removal) puts a core semantics rule in the wrong place. A small spec ticket that blocks phs1td costs nothing and keeps the history readable.

**Concern:** If THIS wins, the derived-op text must still land in §4.7.1 and not in the lint's section, or readers will think the rule exists only to serve a warning.

###### Q2: Lint scope
**Vote:** L0. **Second choice:** L1.

**Reasoning:** I hold L0. Partial handlers are a 5-0 decided feature, and every lint option's silencer is `default.op(args)`, which is the desugaring written by hand. With R-yes, a leaked draw in a test reads a seeded stream and the runner prints the replay line, which is the same promise every test that calls `rand` gets. The mock_rand(42) "wrong stream" case is real, but it is a test that fails for some seeds and tells you which, not a silent bug, and it does not justify new grammar on effect declarations. L1 is my fallback because it adds no syntax and no compiler list, and the reader decides it from the handler text alone.

**Concern:** L3 looks likely to win, and its marker adds a decision to every effect author and grammar to the effect declaration for one warning; once it exists, people will propose marking more effects until it means "the stdlib authors were nervous here".

###### Q2b: Marker name (if L3 wins)
**Vote:** `@handle_all`

**Reasoning:** It is a short verb phrase that tells the handler author what to do. `@whole_handler` reads like a type and needs a sentence to explain it.

**Concern:** `@handle_all` can read as "this handler handles every effect", so the diagnostic note must name the effect it applies to.

###### Q2c: Stdlib marks (if L3 wins)
**Vote:** RT

**Reasoning:** The hazard the panel agreed on is one resource seen through several ops: one stream, one clock. A partial Fs mock is an isolation problem that `MockFs` already solves, and sys conceded it is a different hazard. Mark the fewest effects; add Fs later if a real case shows up.

**Concern:** Once Fs is argued in, Net and Env will follow, and the marker drifts back to L2 with extra grammar.

###### Q3: Runner seeds Rand around each test block
**Vote:** R-YES

**Reasoning:** It makes explicit what §8.10.4 already implies with its "`--seed`-derived runner handlers" and per-installation sub-seeds. It closes the hazard at the root, including the test with no mock at all, which no lint option covers. Seeding from suite seed plus the full test name makes `--filter` replay match the full run.

**Concern:** The runner handler must be outermost and must not wrap `prop_check`'s own stream, or property replays will drift.

###### Q4: j5bf0h `unseeded_rand_in_test`
**Vote:** J-CLOSE

**Reasoning:** Under R-yes no test block can reach the OS CSPRNG, so the lint has zero true cases. Code outside tests has no determinism promise, so it is not this lint's case. A warning that cannot fire costs a name, a code, a catalog row and spec text for nothing.

**Concern:** If R-yes is later weakened (an opt-out from the runner handler), j5bf0h's case comes back and nobody will remember to reopen it.

###### Q5a: Name (if a lint passes)
**Vote:** `PartialHandler`

**Reasoning:** It is the word §4.7.1 uses, so the warning maps to its own section with no lookup. "Implicit delegation" appears nowhere in the spec, and adding a second term for one concept is surface we do not need.

**Concern:** Under L3 the name says "partial handlers are suspect" in general, so the note must say why this effect is marked.

###### Q5b: Code (if a lint passes)
**Vote:** W0705

**Reasoning:** W070x is the existing misc-lint range. W0545 starts an effects warning group with one entry; open it when a second effect lint exists. The number is not where users look, so the choice should cost the least structure.

**Concern:** If W0545 wins, it should not be read as a reserved W054x range that invites more effect warnings.

###### Q6a: Silencer
**Vote:** YES

**Reasoning:** Writing the op with any body is the only silencer that needs no new mechanism. `@allow` and `[lints]` already exist for warnings, and an audit gate would be far too heavy for a style warning.

**Concern:** People will write `panic("unused")` stubs by reflex, which hides real calls as test panics in place of warnings.

###### Q6b: Machine-applicable fix-it is part of the contract
**Vote:** YES

**Reasoning:** If a lint passes, a silencer that costs one line per op is acceptable only when the tool writes the lines. The stubs come from signatures the compiler already has, so this adds no language surface.

**Concern:** The fix-it will make forwarding stubs cheap enough that the corpus fills with them, which teaches readers that auto-delegation is something to undo.

###### Q6c: §4.4.7 `always_low()`
**Vote:** IF-LINT

**Reasoning:** Under L0 the existing comment ("auto-delegate to the enclosing handler") is correct; one added sentence says that in a test the enclosing handler is the runner's seeded `Rand`. Under any lint that covers Rand, the example must change, so IF-LINT gives the right result in both cases. Changing it unconditionally would show the spec undoing its own feature.

**Concern:** If a lint passes and the example changes, the spec loses its only plain demonstration of auto-delegation for Rand; another example must show it.


#### Phase D

Not triggered: no result was closer than 5-1.

### Final Spec

```blink
@handle_all
effect Rand {
    fn int(lo: Int, hi: Int) -> Int
    fn float() -> Float
    fn bytes(n: Int) -> Bytes
}

// warning[PartialHandler]: handler for `Rand` does not implement `float`, `bytes`
fn always_low_partial() -> Handler[Rand] {
    handler Rand {
        fn int(lo: Int, hi: Int) -> Int { lo }
    }
}

// OK: each primitive operation has a body; two forward on purpose
fn always_low() -> Handler[Rand] {
    handler Rand {
        fn int(lo: Int, hi: Int) -> Int { lo }
        fn float() -> Float { default.float() }
        fn bytes(n: Int) -> Bytes { default.bytes(n) }
    }
}
```

- An operation with a body in the effect declaration is a derived operation. If the innermost handler omits it, the body runs at the call site with the same handlers in force. Only an omitted primitive operation goes to the enclosing handler (§4.7.1).
- `@handle_all` on an effect declaration also covers its sub-effects. The stdlib marks `Rand` and `Time` (§4.3, §4.4.7, §11.1).
- `PartialHandler` (W0545) fires in all code, on a handler expression for a marked effect that omits a primitive operation. A handler for a sub-effect counts only the operations of that sub-effect (§4.7.1, ERROR_CATALOG.md).
- Silencers: write the operation with any body, or use `@allow(PartialHandler)` or `[lints]`. No `@trusted` gate. The diagnostic carries a machine-applicable fix with exact-signature `default.op(args)` stubs.
- The test runner installs a seeded `Rand` handler outermost around each `test` block body. The seed derives from the suite seed and the test name, so `--seed --filter` replays the stream. `prop_check` keeps its own stream. The planned `unseeded_rand_in_test` lint is closed (§8.10.4).
