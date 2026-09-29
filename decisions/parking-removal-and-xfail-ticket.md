[< All Decisions](../DECISIONS.md)

# Parking Removal + Opaque Xfail Ticket — Design Rationale

Revisits §8.10.5 (parking fixtures that cannot build) and the tracker coupling in §8.10.6 (`test.failing` `ticket:` and the closed-ticket lint) from [Expected-Failure Tests + Parking](xfail-and-parking.md). That decision's Q2 (ship xfail) and Q3 (boolean `expected_fail` encoding) stay decided and were not reopened.

Facts given to the panel: `--parked` had no implementation; the runner's cancel-on-first-failure cascade had been removed; `.tmp/` is gitignored; the closed-ticket lint existed only as a local task and did not run in `task ci`; `test.failing` with a mandatory `ticket:` was shipped and used in 48 files. The earlier option labels were not given to the panel. The user ruled a new optional NDJSON field in scope during Phase B.

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated
in independent-proposal → debate → vote rounds. Text below is verbatim from each panelist.

#### Phase A — Independent proposals

##### Systems

Start from what ships to the hardware and the wire. `--parked` has no code, and the cascade it was meant to suppress is gone, so it would add a runner code path, a CLI flag and a second NDJSON schema for zero users. `test.failing` does ship, and its one tracker leak is on the wire: src/cg.bl:634 bakes `"br:{ticket} — {reason}"` into every `xfail_reason`. A user's CI log now names a tool they do not have. Each proposal below removes something. None adds anything.

###### S1 (rank 1): Delete §8.10.5. Make `ticket:` an optional opaque string. Move tracker policy out of the spec.

**Parking, normative:**
- Remove §8.10.5 in full: the `--parked` flag, the `parked_file` event, the `.tmp/<ticket>/` store and the `.tmp/` lint. The runner has no concept of parking. The NDJSON stream keeps one record schema.
- Four-case table, row 1 becomes: "The fixture does not build → it is not a test yet. Keep it outside the test roots, or express it as a test that builds (see below)." No runner mechanism.
- Informative note: a project whose tests drive a compiler (such as the Blink repo) can turn row 1 into row 2. The test compiles the source string and asserts that it builds, wrapped in `test.failing`. Then the red fixture builds, runs and inverts, and its strict unexpected-pass rule flags it when the feature lands. The repo already has the helper (`compile_test_helpers`).

```blink
test.failing("? propagates in test bodies", reason: "needs ? in test bodies") {
    expect_compiles(#"test "t" { let x = f()? }"#)
}
```

**`test.failing`, normative:**
- Signature: `test.failing(name, reason: Str, ticket: Str?)`. `reason:` stays mandatory and non-empty. `ticket:` is optional. If present, it must be non-empty (E0835). It is an opaque tracker reference, such as `"GH-1234"`, a URL or a local id. The spec gives it no meaning.
- NDJSON: `xfail_reason` = `"<ticket> — <reason>"` if a ticket is present, else `"<reason>"`. No `br:` prefix.
- Remove the "Closed-ticket lint" subsection from the spec. A project may lint `ticket:` values against its own tracker. The Blink repo keeps scripts/xfail_tickets.sh as repo policy. It already flags a row that names no ticket, so the repo's rule stays unchanged.

```json
{"name":"...","status":"passed","expected_fail":true,"xfail_reason":"GH-88 — trait elaboration not done"}
```

**Tradeoffs (systems view):**
- Runtime cost is unchanged, still one `const char*` per record. We save a runner walker, a flag parser, a second event schema that every NDJSON consumer must branch on, and a lint that forks a process per CI run.
- Correctness stays in the runner. The strict unexpected-pass rule already catches the case that matters (the feature landed, the row is stale). The ticket lint catches only "red, but points at a closed ticket", which is tracker bookkeeping, not test semantics. That belongs to the project, not the language.
- Honest spec. Today the spec says the lint runs in `task ci`, and the code says it does not. S1 makes the spec match the shipped behavior.

**Cross-language:** pytest `xfail(reason=, strict=True)`, Rust `#[ignore = "..."]` and Go `t.Skip` all take a reason and no tracker. None has a "parked" state. A file that does not compile is a compile error in every one of them.

**Migration:** No source change for the 42–48 files. They keep `ticket:`, and it is still legal. The parser accepts a missing `ticket:`, and E0835 applies only to an empty value that is present. The codegen format string changes, so the NDJSON `xfail_reason` strings lose `br:`. Any consumer that parsed out `br:` breaks, but the spec already said "no regex parsing", so none should exist. Bootstrap: gen0 requires `ticket:`, and repo tests keep it, so this needs no two-step. No `--parked` code exists to remove.

###### S2 (rank 2): S1, but `ticket:` stays mandatory and opaque

Same as S1, except `ticket:` stays required, non-empty and opaque (no `br` meaning, no `br:` prefix). Zero parser change. Cost: a user with no tracker writes `ticket: "none"`. A mandatory field that people fill with junk carries no information and teaches AI generators to invent ids. I rank it below S1 for that reason.

###### S3 (rank 3): S1, plus a structured `xfail_ticket` field

Emit `xfail_ticket: Str` as its own optional field and keep `xfail_reason` as the bare reason. This is best on the wire: a consumer reads a field and never splits a string on " — ". It does add a third optional field to the Q3 encoding the panel already decided, so I offer it only if the panel reads Q3 as open to a field that is purely additive. It is still better than string concatenation, which is the same "parse two things out of one" smell I objected to in Q3.

###### Dissent note
In 1c2zr6 I voted for `--parked` because the cascade was the real cost. The cascade is fixed. With nothing left to suppress, the flag is an abstraction with no payload. PLT was right.

##### Web/Scripting

I checked how things stand today. The `br:` prefix comes from a single line, `src/cg.bl:634` (`"br:{ticket} — {reason}"`). No script in the repo parses `xfail_reason`. `ticket:` is used in 48 test files.

---

###### Rank 1 — W1: "Parking leaves the spec; `ticket:` becomes an optional, uninterpreted label"

**§8.10.5, normative:** Delete the section: the `--parked` flag, the `parked_file` event, the `.tmp/<ticket>/` store and the `.tmp/` lint. In its place:

> A file that does not build is not a test. `blink test` reports it as a build failure for that file and runs the other files. The runner has no concept of parked or pending files.

Move the `.tmp/<ticket>/` habit into a repo contributor doc (for example `docs/contributing/red-fixtures.md`). The spec does not reference it.

**§8.10.6, normative:**

> `test.failing(name, reason: Str, ticket: Str = "")`. `reason:` is mandatory and non-empty (unchanged). `ticket:` is optional. If present, it must be non-empty (E0835). The compiler and runner never interpret it. It is a label: an issue number, a URL, or any project reference. `xfail_reason` is `"<ticket> — <reason>"` when a ticket is given, else `"<reason>"`. Tooling that checks tickets against a tracker is project policy and is not part of the language.

Delete the "Closed-ticket lint" subsection from the spec. The repo keeps `scripts/xfail_tickets.sh` / `task xfail-tickets` as its own policy, which is what already happens.

```blink
test.failing("parses unicode escapes", reason: "lexer lacks \\u{...}") {
  assert_eq(lex("\"\\u{41}\""), ["A"])
}

test.failing(
  "retries on 503",
  reason: "retry middleware not written",
  ticket: "https://github.com/acme/api/issues/88",
) {
  // ...
}
```

```json
{ "name": "retries on 503", "status": "passed", "expected_fail": true,
  "xfail_reason": "https://github.com/acme/api/issues/88 — retry middleware not written" }
```

**Four-case table, parking row becomes:** "The file does not build → it is not a test yet. Keep it out of the test directory. To assert *on* a diagnostic, write an ordinary test that compiles a source string and checks the error." (The repo does this with `compile_test_helpers.expect_compile_error`.)

**Tradeoffs (DX):**
- The 5-minute test. A JS or Python developer reads `ticket: "a1b2c3"` and asks "which tracker? do I need to install something?" That question goes on Stack Overflow straight away. The optional label answers itself.
- Requiring a ticket for a solo scripting developer produces `ticket: "none"` / `ticket: "TODO"` noise. That is worse than no field, because it looks tracked and is not.
- Friction still does its job: `reason:` stays mandatory, and an unexpected pass still fails the suite (strict). The rot protection comes from strictness, not from a tracker id.
- `--parked` was a fix for a cascade bug that no longer exists. Shipping a public flag and an event class with nothing left to do adds a documentation cost with no benefit.

**Cross-language:**
- pytest: `xfail(reason=, strict=)`, no ticket argument.
- Jest/Vitest: `test.failing(name, fn)`, no reason at all.
- JUnit: `@Disabled("reason")`.
- Rust: `#[ignore = "reason"]`.
- None of them builds a tracker into the syntax, and none has a "parked file" concept. Developers from those languages already expect a file that does not compile to be a build error.

**Migration:**
- All 48 files compile unchanged, because `ticket:` is still accepted.
- The `xfail_reason` text loses the `br:` prefix (a one-line change at `cg.bl:634`). No consumer parses it.
- The E0835 empty check is relaxed to "empty if present".
- `--parked` was never implemented, so its impl ticket is closed as won't-fix.
- After this change the repo can drop `ticket:` from its tests if it wants to enforce the no-br-ids rule. That is repo policy, not spec.

---

###### Rank 2 — W2: "Mandatory `ticket:`, but not tied to a tracker"

Same parking removal as W1. `ticket:` stays **mandatory and non-empty**, but becomes an opaque reference such as `"#88"`, `"JIRA-12"` or a URL. The `br:` prefix is dropped. The closed-ticket lint leaves the spec as in W1.

- **For:** it keeps the 1c2zr6 "friction is load-bearing" argument (which I made last time). Nothing changes at any call site.
- **Against:** it still fails the scripting case above and invites filler tickets. I rank it second because it keeps the traceability discipline, just without the dependence on `br`.
- **Migration:** zero source changes.

---

###### Rejected by me (for the dedupe step)

Adding a separate `xfail_ticket` NDJSON field would be cleaner to consume. But it reopens the locked Q3 rule that `expected_fail` and `xfail_reason` are the only new fields. I don't push it. Putting the ticket inside the string, as W1 does, avoids reopening Q3.

---

**Position on the old vote:** I voted Aγ in 1c2zr6 because pytest xfail and Rust `#[ignore]` felt familiar. That comparison was wrong for parking. Neither of them lets a test file that does not compile take part in a test run. The PLT dissent was right.

##### PLT

**PLT seat: Phase A proposals (ranked)**

---

###### P1 (preferred): Take parking out of the spec, and make `ticket:` an optional, opaque reference

**§8.10.5 normative text:** delete the section. Put in its place:

> A source file that does not build is not a test. The runner reports it as a build failure and defines no mechanism to hold such files outside the test roots. How a project stores work that does not build yet is project policy, not language behavior.

- Remove `--parked`, the `parked_file` event class and the `.tmp/` lint from the spec.
- The blink repo's own practice (`.tmp/<ticket>/`, `br`) moves to repo docs (docs/ or CONTRIBUTING) as repo policy only.
- The cascade clause goes too. The runner no longer cascades, so the clause has nothing left to suppress.

**§8.10.6 normative text:**

> `test.failing(name, reason: Str, ticket?: Str)`. `reason` is mandatory and non-empty. `ticket` is optional. If present it must be non-empty, and it is an opaque tracker reference (a URL, `GH-123`, any id). The compiler and runner give it no meaning. The spec defines no ticket lint. A project may lint `ticket:` values with its own tooling.

```blink
test.failing("alias chain resolves", reason: "trait elaboration not built") {
  assert_eq(resolve("A"), "C")
}
test.failing("alias chain resolves 2", reason: "trait elaboration not built",
  ticket: "https://github.com/acme/app/issues/88") { ... }
```

**NDJSON:** `xfail_reason` carries `reason` verbatim, with no `br:` prefix. If `ticket` is present, emit it as an optional `xfail_ticket: Str` field:

```json
{"name":"alias chain resolves 2","status":"passed","expected_fail":true,
 "xfail_reason":"trait elaboration not built","xfail_ticket":"https://github.com/acme/app/issues/88"}
```

Fallback if the panel treats a third optional field as reopening Q3: keep two fields and use the format `"<ticket> — <reason>"` without `br:`. I rank that lower because it packs a structured value into a string that consumers must then parse.

**Four-case table, row 1:** "Does not build → not a test. Keep it outside the test roots until it builds (project policy). The spec defines no mechanism."

**Rationale (PLT):**
- **The rule for mandatory arguments:** an argument should be mandatory only if the semantics use it. `reason` passes that test, because the runner emits it. A mandatory `ticket` does not. The checker can only enforce that it is non-empty, so `ticket: "x"` satisfies it. That is a vacuous obligation. It trains users (and AI generators) to write filler, and filler is worse than absence.
- **Absence is encoded by omission, not by `""`,** so E0835 keeps one clear meaning: an empty string that you wrote is always an error.
- **Parking is about artifacts that are not programs.** A runner event that reports on a non-program (`parked_file`) sits outside the test-record algebra. It is a second, unrelated schema that exists to serve one repo's workflow. It does not compose with anything else in §8.10.
- **The store is not reproducible.** `.tmp/` is gitignored, so a normative mechanism would rest on state that is not versioned. Another reader cannot reproduce it from the repo.

**Migration:**
- Zero source breakage. All 48 files keep `ticket:` and stay valid.
- Parser: make the `ticket:` clause optional (src/parser.bl ~1975).
- Typecheck: E0835 fires only when a written field is empty.
- Codegen: drop the `br:` prefix at src/cg.bl:634 and emit `xfail_ticket`.
- The formatter already prints `ticket:` only from the node; it must skip the field when it is absent.
- `--parked` was never built, so nothing to remove.
- scripts/xfail_tickets.sh stays as repo tooling. The spec stops saying it runs in `task ci`, which also fixes the current mismatch between spec and implementation.

**Cross-language:**
- pytest `xfail(reason=, strict=)` has no ticket field. Tracker links sit in the reason text.
- Rust `#[ignore = "..."]`: free text only.
- Rust's `compile_fail` doctests and `trybuild` handle "does not build yet" as a compile-fail *test* that asserts a diagnostic. They never use a parking area.

---

###### P2: Keep `ticket:` mandatory but tracker-neutral

This is P1 with `ticket` still required, as an opaque non-empty `Str`, and the `br:` prefix removed.

- **Pro:** no parser change. Keeps the rot-mitigation friction that swung Minimalism in 1c2zr6.
- **Con:** users who have no tracker get the vacuous-obligation problem above. I accept P2 over the status quo, not over P1.

---

###### P3 (rejected, listed to show why): Generalize parking

This would keep `--parked` but add a configurable directory, tracker-neutral ids and the NDJSON event.

It fixes none of the problems above. The runner would still learn a concept that has no language meaning, and a spec flag would sit on a directory convention that is not versioned. I vote against.

---

###### Note for a future ticket (not proposed now; YAGNI)

The sound, language-level answer to "a fixture that does not build" is a **compile-fail test form**: a test that asserts a static judgement ("this source is rejected with E####"). Rust's `compile_fail` and `trybuild` work this way. The repo's `compile_test_helpers.expect_compile_error` already has this shape, but users cannot reach it. If users ask for it, open a separate spec ticket. It must not come back through a parking area.

**Summary:** P1 > P2 >> status quo > P3.

##### DevOps/Tooling

**DevOps/Tooling: Phase A proposals for 9he2qv**

---

**P1 (first choice): Take parking out of the spec, keep `ticket:` but make it optional and not tied to any tracker, and leave the lint to each project.**

*§8.10.5, new normative text:*
> A test file that does not build is a build failure. `blink test` reports a file-level build diagnostic for that file on the NDJSON stream, then runs the other files. The runner has no parking concept. It walks only the test paths it is given. How a project stores fixtures that do not build yet is that project's own process, not part of the language.

Remove these from the spec: the `--parked` flag, the `parked_file` event class, the `.tmp/<ticket>/` layout, the `.tmp/` lint, and the cascade clause. The cascade bug is fixed, so that clause no longer does anything.

*§8.10.6, new normative text:*
> `test.failing(name, reason: Str, ticket: Str?)`. `reason:` is mandatory and non-empty (E0835). `ticket:` is optional. It holds any tracking reference (an issue URL, `GH-412`, `JIRA-88`). If `ticket:` is present it must be non-empty (E0835: an empty `ticket:` is a typo, not an opt-out). The runner never reads or checks what `ticket:` says.
>
> `xfail_reason` is `"<ticket> — <reason>"` when a ticket is given, and `<reason>` alone when it is not. The `br:` prefix is removed.
>
> Spec-level lint: none. A project that wants a closed-ticket check owns it (CI script, tracker hook).

```blink
test.failing("alias chain resolves", reason: "trait elaboration not done") {
    assert_eq(resolve("A"), "C")
}

test.failing(
    "alias chain resolves",
    reason: "trait elaboration not done",
    ticket: "https://github.com/acme/app/issues/412",
) {
    assert_eq(resolve("A"), "C")
}
```

```json
{"name":"alias chain resolves","status":"passed","expected_fail":true,
 "xfail_reason":"https://github.com/acme/app/issues/412 — trait elaboration not done"}
```

```
error[E0835]: test.failing `ticket:` is empty
  --> tests/test_alias.bl:3:5
   | remove `ticket:`, or give a tracking reference
```

*Four-case table, parking row:*
> Fixture does not build → it is not a test yet. If the point of the test is a compiler diagnostic, write a test that builds and asserts the diagnostic (in the compiler repo: `expect_compile_error`). Otherwise keep the fixture out of the test tree until it builds. Where it waits is project process.

*Tooling:*
- LSP signature help shows `ticket?: Str`.
- `blink fmt` prints the `ticket:` line only when the source has one.
- The runner and the NDJSON schema do not grow at all.
- A spec-level lint would need a tracker protocol, and the spec cannot name one. `br` is not shipped, so today the spec requires a lint that no user can run. Even the repo does not run it in `task ci` (scripts/xfail_tickets.sh says "local only"). The spec already disagrees with the code; P1 makes the spec describe what can actually work.

*Tradeoff:* the rot guard is weaker for users who leave out `ticket:`. The strict unexpected-pass rule and the mandatory `reason:` still hold, and those are the checks that fire without anyone keeping up discipline. The ticket lint was never going to run for users anyway.

*Cross-language:* pytest `xfail(reason=, strict=)` has no ticket field. Rust `#[ignore = "..."]` takes free text. Go's toolchain gives machine-readable output and lets projects set policy. All three leave the link to a tracker to the project.

*Migration:*
- The 48 files do not change. `ticket:` stays valid.
- One codegen line changes: `src/cg.bl:634` drops `br:` and branches on whether a ticket is present.
- E0835 changes from "missing or empty" to "empty if present". The parser stops requiring `ticket:` (src/parser.bl ~1984).
- The compiler repo keeps its own rules. `scripts/xfail_tickets.sh` still requires a `br` id on every row and checks it is open. The repo's "no br ids" exception for `ticket:` becomes a documented repo convention, not language spec.
- Parking was never built, so removing it breaks nothing. The ~820 local `.tmp/` dirs stay a personal scratch habit. Close the `--parked` impl ticket as won't-do. `tests/pinned/` is not affected.

---

**P2 (fallback): Same as P1, but `ticket:` stays mandatory and free-form.**

Everything in P1 applies, except `ticket:` stays required and non-empty. Its value is treated as opaque text with no `br` meaning.

- *For:* no parser or E0835 change, and every xfail row names an owner.
- *Against:* it forces a tracker on users who have none. They will fill it with `ticket: "none"`, which is noise that looks like data and that the LSP and lints cannot tell apart from a real reference. I rank it below P1 for that reason.

---

**Rejected by me (listed so the dedupe step sees them):**
- A separate `xfail_ticket` NDJSON field. It would be cleaner than packing ticket and reason into one string, but it reopens the locked "only two new fields" encoding. If a consumer reports it has to parse that string, that is the path to reopen it.
- Keeping `--parked` but making the directory configurable. The runner would carry a workflow concept with no user demand behind it (YAGNI). The failure it was built to prevent, the cascade, is gone.

##### AI/ML

I read brief.md, §8.10.5–§8.10.6 of sections/06_tooling.md and decisions/xfail-and-parking.md, and checked the shipped code.

**Shipped facts that bear on this:**
- `src/cg.bl:634` hard-codes `"br:{ticket} — {reason}"` into `xfail_reason`, so the `br` coupling is in the NDJSON wire format as well as in the lint.
- 48 files use `test.failing`, each with its own 6-char `br` id.
- `tests/test_value_callee_single_arg_call_crash.bl` uses `test.failing` for a *bug*. That breaks row 3 of the four-case rule. It shows that even this repo applies the rule loosely.

---

###### P1 (rank 1): Take parking out of the spec, make `ticket:` an optional opaque reference, and move the lint to repo tooling

**Normative text:**

§8.10.5: delete it. Remove `--parked`, `parked_file`, `.tmp/<ticket>/` and the `.tmp/` lint from the spec. The runner does not know about files that do not build. A file under the test root that does not build is a build failure, reported as today.

§8.10.6:
- `test.failing(name, reason: Str)` with an optional `ticket: Str`. The compiler and runner treat `ticket` as opaque text: an issue URL, `"GH-412"`, `"PROJ-9"`, anything.
- E0835 still fires on an empty `reason:`, and on `ticket: ""` when `ticket:` is given.
- Records carry `xfail_reason` = the `reason` text, unchanged. When a ticket is given, records also carry `xfail_ticket: Str`, which is optional and absent otherwise.
- Remove the "br:" prefix.
- The closed-ticket lint leaves the spec. Any project, including the Blink repo, may lint `ticket:` against its own tracker.

Four-case table, row 1 becomes: "The fixture does not build → not a runner concern. Do not commit it to the test tree. If the diagnostic *is* the behavior under test, write a test that builds and asserts the diagnostic." The other three rows stay as they are.

```blink
test.failing("alias chain resolves", reason: "trait elaboration not implemented") {
  assert_eq(resolve("A"), "C")
}

test.failing(
  "alias chain resolves",
  reason: "trait elaboration not implemented",
  ticket: "https://github.com/acme/app/issues/412",
) {
  assert_eq(resolve("A"), "C")
}
```

```json
{ "name": "alias chain resolves", "status": "passed", "expected_fail": true,
  "xfail_reason": "trait elaboration not implemented",
  "xfail_ticket": "https://github.com/acme/app/issues/412" }
```

**Tradeoffs (AI/ML):**
- **Hallucination.** A mandatory `ticket:` in a project with no tracker makes the model invent one: `"TODO"`, `"0000"`, or a plausible fake 6-char id. This is the largest accuracy risk in the current design. With an optional field the rule is "include `ticket:` only if you have a real id; never invent one." That rule is easy to learn and a model can follow it.
- **Learnability from the spec alone.** Today a model has to know what `br` is to understand §8.10.6, and no user has `br`. §8.10.5 teaches a flag, an event class, a store layout and a lint that a user can never exercise. That is spec text a model will produce wrongly, for example by emitting `--parked` in a user's CI.
- **Consumer parsing.** Separate fields (`xfail_reason` + `xfail_ticket`) mean no split on `" — "` and no `br:` prefix to strip. The "no regex parsing" point locked in 1c2zr6 now also applies on the wire.
- **Decision points.** Remove one CLI flag and one NDJSON event class, add one optional argument: net fewer.
- **Cost.** One more optional record field. Status and cause enums stay closed, so the Q3 decision is kept.

**Cross-language:** pytest `xfail(reason=..., strict=True)` has no ticket field. Rust `#[ignore = "..."]` has one free-form string. Neither runner knows a tracker, and neither has a "parked" concept. Links to a tracker are a project convention in both.

**Migration:**
- All 48 files keep compiling unchanged, because `ticket:` is still accepted.
- The parser makes `ticket:` optional (`src/parser.bl` ~1984).
- `cg.bl:634` emits `reason`, plus `xfail_ticket` when a ticket is given.
- The runtime (`bootstrap/runtime_test.h`) prints one more field.
- `scripts/xfail_tickets.sh` reads source, not NDJSON, so it stays unchanged as repo policy. The repo may still require `ticket:` through that repo-only lint.
- Nothing to delete for `--parked`, because it was never implemented.
- Repo parking (`.tmp/`) becomes a CONTRIBUTING/docs convention. PLT's 1c2zr6 dissent wins in full.

###### P2 (rank 2): Same as P1, but `ticket:` stays mandatory and becomes free-form

Mandatory, non-empty, opaque, same wire fields as P1.

- **For:** it keeps the rot defence that "every xfail points somewhere".
- **Against (AI/ML):** it keeps the fabrication risk. A user with no tracker writes junk, and the junk teaches future models that junk is idiomatic. I rank it below P1.
- **Migration:** zero source changes.

###### P3 (rank 3, listed only to reject): Keep `--parked`, keyed on a path instead of a ticket

`blink test --parked <dir>` over any directory, emitting `parked_file`.

- **Against:** the cascade it was built to suppress is gone. It adds a flag and an event class for a workflow no user has. Every added surface is one more thing a model can misuse.
- **I vote against.**

---

###### Recommendation
**P1.**

Separate note for the repo, outside this spec decision: the 48 opaque `br` ids in committed tests teach models that random 6-char strings are the idiomatic `ticket:` value. That argues for repo policy to prefer descriptive tickets or no ticket, but the choice is the repo's, not the spec's.

##### Minimalism

I'm going back on my 1c2zr6 concession. I accepted parking only "if the lint is mechanical, ticket-coupled, and runs in `task ci`". None of that happened: the lint needs `br`, so it can't run in `task ci` (scripts/xfail_tickets.sh header). The cascade that justified `--parked` is gone. `--parked` was never built. The condition I voted on is void, so my vote goes with it.

###### P1 (rank 1): "Subtract both". Delete §8.10.5; `ticket:` leaves the language

**Normative text:**
- **§8.10.5 is removed.** `--parked`, the `parked_file` event, `.tmp/<ticket>/` and the `.tmp/` lint all go. The runner walks only the test paths it is given.
- **Four-case table, parking row replaced by:** "The fixture does not build → not a runner concern. A file that does not compile is not a test. Keep it outside the test paths until it compiles. To assert that code is *rejected*, write an ordinary test that checks the diagnostic." The table keeps three runner rows.
- **§8.10.6:** the form becomes `test.failing(name, reason: Str) { ... }`. `reason:` stays mandatory and non-empty (already decided). `xfail_reason` holds `reason` verbatim, with no `br:` prefix.
- **The closed-ticket lint section is removed from the spec.** The rot guard that stays is the strict unexpected pass (already decided): when the test goes green, the suite fails.

```blink
test.failing("trait impl resolves through alias chain", reason: "alias-chain elaboration not implemented") {
    assert_eq(resolve_alias_impl(), 3)
}
```

```json
{"name":"trait impl resolves through alias chain","status":"passed","expected_fail":true,"xfail_reason":"alias-chain elaboration not implemented"}
```

**Repo side (outside the spec):** the test-to-ticket link goes in a `br note`, or in a gitignored sidecar that maps test name to ticket id, which scripts/xfail_tickets.sh reads. This also ends the one exception to the rule that keeps `br` ids out of source. Red fixtures that don't build stay in `.tmp/` as a private habit, or in `expect_compile_error` tests. Neither needs spec text.

**Tradeoffs:** This removes one flag, one NDJSON event class, one lint contract and one mandatory argument, and adds nothing. The cost is that the repo's ticket check loses its in-source key and must use the sidecar. That is the right direction: the tracker is a workflow tool, and the language should not know about it.

**Cross-language:** pytest `xfail(reason=)`, Jest `test.failing`, Rust `#[should_panic]`/`#[ignore = "..."]` and Go have no ticket field. None of them has a runner mode for files that do not compile. Rust handles compile-fail through libraries (trybuild), not the runner. This is the Lua/Go posture: the core ships the test primitive, and projects bring their own process.

**Migration:** 48 files, all repo-internal. Use the 3-step dance:
1. Make `ticket:` optional in the parser, relax the E0835 check to `reason` only, and drop the `br:` prefix in the cg.bl:634 string. Regen.
2. Move the 48 ticket ids into the sidecar or br notes, and delete `ticket:` from the files. The formatter can fold it out mechanically.
3. Reject `ticket:` with a targeted diagnostic ("test.failing no longer takes ticket:; use reason:"). Regen.

Nothing user-facing breaks except code that passes `ticket:`, which is new. §8.10.5 has no implementation, so deleting it costs zero code.

###### P2 (rank 2): "Opaque optional reference". Delete §8.10.5; keep `ticket:` optional and uninterpreted

- §8.10.5 and the parking row are removed, as in P1.
- `ticket:` becomes **optional**. If present it must be a non-empty static `Str`, and the spec calls it "an opaque tracking reference (issue URL, id, anything)". The runner never interprets it. No lint is specified.
- `xfail_reason` becomes `"<ticket> — <reason>"` when `ticket:` is given, and `"<reason>"` otherwise. No `br:` prefix, and no new NDJSON field.

```blink
test.failing("utf16 surrogate round-trip", reason: "decoder drops lone surrogates", ticket: "gh-412") {
    assert_eq(decode_utf16(encode_utf16("\u{D800}")), "\u{D800}")
}
```

**Tradeoffs:** Zero migration: all 48 files stay valid. But it keeps an argument the runner does nothing with. A field that exists "for tools" with no specified tool is how C++ picks up clutter. It also leaves `br` ids in repo test source, which conflicts with the repo's own rule.

**Migration:** step 1 of P1 only. Stop there.

###### P3 (rank 3, floor): "Unbind br, change nothing else"

`ticket:` stays mandatory. Every mention of `br` in §8.10.6 becomes "the project's tracker id". The lint becomes "a project MAY check ids against its tracker". §8.10.5 is still deleted.

This is the least I would accept. It requires every Blink user to have a tracker id before they can mark a test expected-red, and no mainstream framework asks for that.

###### Where I stand on the whole scope

Deleting §8.10.5 does not depend on the `ticket:` question. It is unbuilt, its reason (the cascade) is gone, and its store (`.tmp/`, gitignored) cannot survive a clone. On `ticket:` I rank P1 > P2 > P3. My vote is P1, because it is the only option that removes what exists only for the repo's own workflow.

#### Phase A.5 — Mechanical dedupe (moderator)

Full proposal texts, verbatim, are in the same directory: phaseA_sys.md, phaseA_web.md,
phaseA_plt.md, phaseA_devops.md, phaseA_aiml.md, phaseA_min.md. Read all six.

###### Parking (§8.10.5)
- **P-DEL** — Delete §8.10.5 (`--parked`, `parked_file`, `.tmp/<ticket>/` store, `.tmp/` lint,
  cascade clause). Proposed by: Sys S1, Web W1, PLT P1, DevOps P1, AI/ML P1, Min P1/P2/P3.
  (Rejected-by-proposer variants that keep parking: PLT P3, AI/ML P3.)
- **Variation V1 — what replaces the parking row / section text:**
  - V1a: a file that does not build is not a test; where it waits is project policy; spec defines
    no mechanism (PLT P1, Min P1, AI/ML P1, Web W1).
  - V1b: normative: "`blink test` reports a file-level build diagnostic for that file on the NDJSON
    stream, then runs the other files" (DevOps P1).
  - V1c: informative note that a project whose tests drive a compiler can express the red fixture as a
    `test.failing` that compiles a source string (Sys S1; Web/DevOps/Min mention asserting a diagnostic
    with a test that builds).
  - Fact (moderator, from the spec): §8.10 today specifies no NDJSON output for a test file that fails
    to build.

###### `test.failing` ticket: (§8.10.6)
- **T1 — remove `ticket:`** from `test.failing` (3-step migration; repo link moves to br note / sidecar).
  Proposed by: Min P1.
- **T2 — `ticket:` optional, opaque**; if present must be non-empty (E0835); runner never interprets it.
  Proposed by: Web W1, Sys S1, PLT P1, DevOps P1, AI/ML P1, Min P2.
- **T3 — `ticket:` mandatory, opaque** (no br meaning). Proposed by: Web W2, Sys S2, PLT P2,
  DevOps P2, AI/ML P2, Min P3.
- **Variation V2 — NDJSON encoding of a ticket (applies to T2/T3):**
  - V2a: `xfail_reason` = `"<ticket> — <reason>"` when a ticket is given, else `"<reason>"`; no `br:`
    prefix; no new field (Web W1, Sys S1, DevOps P1, Min P2; PLT fallback).
  - V2b: `xfail_reason` = reason only; new optional `xfail_ticket: Str` field (PLT P1, AI/ML P1;
    Sys S3 conditional on Q3 being open to a purely additive field).

###### Closed-ticket lint
- Remove from spec; projects own tracker checks; repo keeps scripts/xfail_tickets.sh.
  Proposed by all six. No variation.

#### Phase B — Debate, round 1

##### Systems

**P-DEL: FOR.** Six of six agree. Nothing more to add.

**T1 vs T2 vs T3. To Min (T1):** I agree the runner does nothing with `ticket:`. But T1 costs more than it saves:
- It needs a 3-step migration across 48 files.
- It moves the ticket link into a gitignored sidecar or a `br note`. That is the same unversioned store PLT faulted `.tmp/` for: a fresh clone cannot see which ticket owns which row.
- T2 costs one parser branch and zero runtime work (one nullable `const char*`).
- T2 does not stop the repo from dropping `ticket:` later. A repo could still move to T1 under T2, but T1 closes the door for every user.

**To Web/DevOps/PLT/AI/ML (T3):** Everyone ranks T3 second, for the same reason. A mandatory field that the checker can only test for non-empty yields `"none"`. It is an operation with no payload.

**Position: T2. T3 is my fallback. Against T1.**

**V1. To DevOps (V1b):** The moderator's fact is right: §8.10 defines no NDJSON output for a test file that does not build. That is a real gap, but it is a different gap. V1b would add a file-level event schema with its own path and diagnostic fields, which is `parked_file` under a new name. It would also need its own schema decision:
- Does it carry a status?
- How does a consumer count it?
- Does it abort the suite exit code?

Deciding that here, as a side effect of deleting parking, is how we got `parked_file` in the first place. Log a separate ticket for "NDJSON for a test file that fails to build".

**Position:** V1a normative, plus V1c as an informative note only. For V1c I accept Web/DevOps wording: "a test that builds and asserts the diagnostic, or asserts that it compiles."

**V2. To Web and DevOps (V2b reopens Q3):** The decision file does lock "`expected_fail` and `xfail_reason` are the only new NDJSON fields". But the `"br:<ticket> — <reason>"` format is the br coupling this ticket is scoped to fix. V2a keeps that coupling, just without the prefix, so a consumer that wants the ticket must still split on " — ".

Q3 decided the status/cause enums and the boolean field. The string format was part of the ticket mechanism, and the moderator put that mechanism in scope. V2b adds one optional field, changes no enum, and costs the runtime one `if` and one `printf`.

**To PLT and AI/ML:** agreed.

**Position:** V2b preferred. I accept V2a if the moderator rules that the field set is locked.

**Closed-ticket lint out of spec: FOR.** Unanimous.

STABLE, READY TO VOTE. On V2, the moderator must rule on one scope question before the vote: is the V2b field in scope, or locked by Q3?

##### Web/Scripting

**P-DEL: yes.** All six seats agree. No more on it.

**V1 (what replaces the parking row)**
- **V1a: yes, my first choice.** "A file that does not build is not a test" is one sentence, and every pytest or Jest user already believes it.
- **V1b (DevOps): half yes.** "Runs the other files" is fine as normative text. It states the fixed behavior, so a user never again sees one bad file hide the rest. But the moderator's fact holds: §8.10 has no NDJSON shape for a build failure today. Specifying a file-level build event is a new schema. That is `parked_file` again under a new name, and this ticket is about removing surface. My answer to DevOps: put the event shape in its own ticket, with a user request behind it.
- **V1c (Sys): yes, as one informative line, with a fix.** Sys's example calls `expect_compiles`, and PLT's note cites `expect_compile_error`. Both are repo-internal (src/compile_test_helpers.bl), not stdlib. A JS developer reads the example, tries to import the helper, and fails. That is the Stack Overflow question I want to avoid. So the note says "a project whose tests drive a compiler may...", names no helper, and shows no code that users cannot run.

**T1 / T2 / T3**
- **T2: my vote.** Zero source migration, and it covers the common case: "link this red test to the GitHub issue."
- **To Min (T1):** you say a field "for tools" with no tool is clutter. The reader is a human: the CI log line and the IDE hover. pytest users paste issue URLs into `reason=` all the time. A named slot is the same habit made tidier, not C++ clutter. T1 also costs a 3-step migration over 48 files for no gain to users. I agree that the repo's `br` ids in source clash with the repo's own rule. The repo can fix that under T2 by dropping `ticket:` from its tests. The spec does not need to forbid the argument to get that.
- **T3: I drop my own W2.** AI/ML's point about invented ids and PLT's point that a mandatory field which only has to be non-empty (so `ticket: "x"` passes) enforces nothing are both correct. `ticket: "none"` is the result, and it is worse than leaving the argument out.

**V2a / V2b**
In Phase A I rejected V2b because I read it as reopening Q3. PLT, AI/ML and Sys have moved me. The Q3 lock was about keeping the status and cause enums closed. V2b adds one optional string and does not touch either enum. On DX, V2b wins clearly:
- A JS developer expects `record.xfail_ticket`, not a split on `" — "`.
- The em dash is non-ASCII, and people will paste it wrong in grep and jq filters.
- "How do I get the ticket out of xfail_reason?" is a question V2a creates and V2b never does.

**Position:**
- V2b if the moderator rules it inside scope.
- V2a if not. Either way, drop `br:`.

**Summary:** P-DEL; V1a, plus V1c as one line with no repo helper named; V1b's "runs the other files" sentence only; T2; V2b > V2a.

NOT STABLE: need a moderator ruling on whether V2b (a new optional `xfail_ticket` field, enums untouched) reopens the locked Q3 encoding. Everything else is ready to vote.

##### PLT

**P-DEL: for.** All six of us agree. Sys and Web: thank you. One more point for the record: the parking store is gitignored, so the spec would rest on state that does not survive a clone.

**V1 (what replaces the parking row)**
- **V1a: for.** A file that does not build is not a test.
- **V1b (DevOps): against, in this ticket.** The moderator's fact settles it: §8.10 today gives no NDJSON shape for a file that does not build. V1b would add a new file-level event in the same place we are removing `parked_file`. It is build-failure reporting in general, not parking. If it is wanted, open a separate ticket with its own schema. The first sentence ("reports a build failure, runs the other files") is fine without the NDJSON clause.
- **V1c (Sys): for, if informative and generic.** It must not name `compile_test_helpers`. That module is internal to the repo, and the spec must not point at a helper that users cannot import. Suggested wording: "A project whose tests drive a compiler can make the fixture build by compiling a source string inside the test."

**T and V2 must be judged together.** This is the main point of my reply, to Min, Web and DevOps. A field earns a place in the language if its value is observable in the output as its own datum.
- **T2+V2b:** `ticket` has a meaning. It flows to its own NDJSON field that consumers can read without parsing. That is principled.
- **T1 (Min):** also principled. No field and no meaning.
- **T2+V2a:** unprincipled. It concatenates `ticket` into `xfail_reason`, so writing `ticket: "GH-1"` is observably the same as writing `reason: "GH-1 — ..."`. The argument is sugar for a string convention, and consumers must split on `" — "`. That split is the same "no regex parsing" smell we locked out of the source in 1c2zr6, now moved onto the wire.

**V2b and Q3, to Web and DevOps.** You both declined V2b as "reopening Q3". What Q3 decided was that the status and cause enums stay closed. V2b keeps them closed and adds one optional, purely additive field. The literal "only two fields" wording served that decision. It was not the decision itself. Q3's "separate `Str` fields, no regex parsing" point argues *for* V2b. Also, the `br:` format string is exactly the coupling this ticket is scoped to fix, so we are already changing that field's content.

**T1 vs T2, to Min.** T1 is sound, and I prefer it to T2+V2a. But the BDFL shipped `test.failing` because users asked for it. T1 breaks any user code that passes `ticket:`, and it needs the 3-step dance. T2 breaks no one. Putting the repo's link in a sidecar is repo policy, which T2 also permits.

**T3: against** (Web, DevOps, AI/ML, Min and I all agree). A mandatory field that the checker can only test for non-emptiness makes users write filler, and AI/ML showed it trains models to invent ids.

**Current positions:**
- P-DEL: yes.
- V1: V1a, plus generic V1c.
- Ticket option: T2+V2b > T1 > T2+V2a > T3.

STABLE, READY TO VOTE

##### DevOps/Tooling

**P-DEL.** All six seats agree. Nothing to debate.

**V1 (what replaces §8.10.5). Moving from V1b to V1a plus one sentence on behavior.**
The moderator's fact settles this: §8.10 specifies no NDJSON output for a file that does not build. My V1b would make this ticket invent a build-failure schema. That is a real gap, but it is a different gap, and it deserves its own ticket, not a rider on a deletion. I now back V1a with one behavioral sentence and no schema: "the runner reports the file as a build failure and runs the other files." Web W1 and PLT P1 already say this. It pins down the fixed cascade behavior, so a regression is a spec violation and not only a bug.
I will log the build-failure event schema as a separate ticket.

**V1c: yes, as an informative note, with one fix.** Sys, your example calls `expect_compiles`, which does not exist, and `compile_test_helpers` is repo-internal, not stdlib. An informative note in the user spec must not show an API that users cannot import; a model will copy it. Word it in general terms: "a project whose tests drive a compiler can assert the diagnostic, or assert that the source builds, in a test that builds." Do not name the helper.

**T1 vs T2 vs T3. Holding T2.**
- *Min (T1):* your sidecar is gitignored, or it is a br note. Either way it has the same flaw that killed `.tmp/`: state that no fresh clone can rebuild. PLT's reproducibility argument cuts against the sidecar too.
  T1 also costs a 3-step gen0 dance for zero user gain.
  The no-br-ids rule is a repo rule. Under T2 the repo can enforce it (drop `ticket:` from its own tests) without the language taking the argument away from users who have a real URL to put there.
  LSP view: an optional, typed `ticket:` gives signature help, go-to-link (hover a URL) and a stable key for project lints. Free text inside `reason:` gives none of that.
- *T3:* PLT's rule is right: a mandatory argument the semantics never read is a vacuous obligation. AI/ML's fabrication risk is the tooling cost of it, because no lint can tell `ticket: "none"` from a real reference.

**V2a vs V2b. Moving to V2b.**
In Phase A I rejected a separate field only to keep Q3 closed. PLT, AI/ML and Sys S3 are right that string packing is the same "parse two things out of one" smell Q3 was meant to avoid. The tooling cost is concrete. Every consumer must split on `" — "`, and a reason that contains an em dash breaks the split. My own original shape is the one that forces regex parsing.
V2b does not touch the status or cause enums, which were the load-bearing part of Q3. It adds one optional field, present only when `ticket:` is present.
The `br:` prefix already put tracker data on the wire, and this ticket's scope is the br coupling of `ticket:`. So how `ticket:` is encoded is in scope. I read V2b as fixing that coupling, not reopening Q3. I want the moderator to confirm that reading.

**Current positions:** P-DEL yes. V1a plus the behavioral sentence. V1c informative, without naming a repo-internal helper. T2 > T3 > T1. V2b > V2a.

NOT STABLE: need a moderator ruling on whether V2b (an additive optional `xfail_ticket` field) is in scope under the br-coupling mandate or reopens locked Q3. If it is ruled out of scope, I vote V2a and am stable.

##### AI/ML

**P-DEL: yes.** All six agree. Nothing to add.

**V1 (to DevOps, on V1b): I hold V1a, add V1c as an informative note, and oppose V1b in this ticket.**
- The moderator says §8.10 specifies no NDJSON output today for a file that does not build. V1b would add a new file-level record schema to the spec. That is the same kind of cost as `parked_file`, which we are deleting.
- An NDJSON build-diagnostic event may well be useful to agents that read the stream. It needs its own ticket and its own schema discussion, not a clause added to a deletion.
- V1c (Sys) is worth keeping as a note. It gives a model a concrete way to handle row 1 in a compiler-driving project. It is informative, so it adds no decision point for users.

**T (to Min, on T1): T2 > T1 > T3.**
- Min, T1 is the strongest AI/ML case on paper: no argument, so no decision. But it has two costs:
  1. Your repo-side replacement, a gitignored sidecar or `br note`, is state that is not versioned. That is the exact objection that sank parking (PLT: "not reproducible from the repo").
  2. It needs a 3-step migration across 48 files for a gain that T2 mostly gets with zero migration.
- T2's decision rule has one line: "give `ticket:` only when you have a real reference." A model applies that rule reliably, because the default is to leave it out.
- T3 keeps the fabrication risk. Every seat that ranked it named `ticket: "none"`/`"TODO"` as the failure. I rank it last.

**V2 (to Web, DevOps and Sys, on V2a): I hold V2b. The case now rests on correctness, not taste.**
- Under V2a with an optional ticket, `xfail_reason` has two formats. A consumer cannot tell `"<ticket> — <reason>"` from a reason that itself contains " — ". For example:
  - `reason: "parser — needs ? support"` with no ticket gives `"parser — needs ? support"`.
  - Is `"parser"` a ticket?
  - The encoding cannot be read back without ambiguity. Once a model writes a consumer that splits on " — ", it will get this wrong sometimes, and no one will notice.
- Web, DevOps and Sys reject V2b as "reopening Q3". Q3 decided the *status/cause enums stay closed* and chose a record-level boolean over a new status (4-2). An optional additive field touches neither enum.
  - The one sentence "the only new NDJSON fields" was written when `ticket` was mandatory and `br`-typed, so the combined string could be parsed back. We are changing that premise now, so the consequence reopens with it.
  - Sys already said S3 is best on the wire. PLT and I proposed it.
- Token cost: one field that appears only when a ticket is present. The reason-only record is identical to Min's T1 record.
- **If the panel still reads Q3 as locking V2b out, my fallback is V2a with a normative rule that `xfail_reason` is display text only and consumers MUST NOT parse it.** Then the ticket is not machine-readable at all. That is worse, but honest.

**My positions now:**
- P-DEL: yes.
- V1: V1a + V1c note; V1b to a separate ticket.
- T: T2 > T1 > T3.
- V2: V2b > V2a (V2a only with "display-only, do not parse").
- Lint out of the spec: yes.

STABLE, READY TO VOTE

##### Minimalism

**P-DEL: yes.** All six seats agree. Nothing more to debate.

**V1: V1a yes, V1b no, V1c only as repo docs.**
- **DevOps, on V1b:** your text adds a normative NDJSON record for a file that fails to build. The moderator notes that §8.10 specifies nothing for this today. So V1b is new surface, brought in under a ticket that exists to remove surface. It may be a good idea. It then needs its own ticket, with a schema (fields, and whether it is a `parked_file` under a new name). Here it would mean deciding a schema as an aside. Keep the spec silent on the build-failure wire shape until someone files for it.
- **Sys, on V1c:** your example calls `expect_compiles`, which does not exist, and `compile_test_helpers` is repo-internal. A user-facing spec that points at a helper users cannot import will lead AI/ML's model to generate calls that do not resolve. Put it in the repo's contributor doc, not in §8.10.

**T1 / T2 / T3: I withdraw T1 and move to T2. I oppose T3.**
- **Web** made the point that moves me: under T2 the repo can drop `ticket:` from its own tests to enforce its no-`br`-ids rule. That was T1's only unique gain, and repo policy can get it without a 3-step language migration. Five seats back T2, and T1 would cost 48 edits plus two regens. The subtraction is not worth the churn.
- **PLT's** rule ("mandatory only if the semantics use it") and **AI/ML's** fabrication point both kill T3. A mandatory field that people fill with `"none"` looks like data and is not.
- On my 1c2zr6 concession: I traded the ticket for the lint. The lint leaves the spec, so the ticket loses its mandatory status with it. The rot guard that stays is strict unexpected-pass plus mandatory `reason:`, and both work with no tracker.

**V2: V2a over V2b.**
- **PLT / AI/ML / Sys-S3:** V2b is cleaner on the wire. But Q3 locked "`expected_fail` and `xfail_reason` are the only new NDJSON fields", and the brief marks it as not to be relitigated. Sys's own 1c2zr6 dissent is the recorded path to reopen it: "if NDJSON consumers report ambiguity". No consumer parses `xfail_reason` today (Web checked). Add `xfail_ticket` when one does, not before.
- **For whoever sees the tension:** under V2a the " — " join is lossy only if a consumer needs to split it. Nobody does. If the panel prefers a clean string, V2a' is acceptable: emit reason only and do not put the ticket on the wire at all. `ticket:` is then a source-level label for tooling that reads source, and that is the only kind of tooling that checks tickets today (scripts/xfail_tickets.sh). I rank V2a ≥ V2a' > V2b.

**Positions:** P-DEL yes · V1a · T2 · V2a (V2a' acceptable, V2b no) · lint out of spec.

STABLE, READY TO VOTE

#### Phase C — Final vote

- **Q1: Parking (§8.10.5)** — DEL, 6-0
- **Q2: Behavioral sentence in place of the parking row** — YES, 5-1 (Minimalism dissent)
- **Q3: Informative note on testing source that does not build** — SPEC-NOTE, 5-1 (Minimalism dissent)
- **Q4: `ticket:` in `test.failing`** — T2 (optional, opaque), 6-0
- **Q5: Wire encoding of a ticket** — V2b (separate `xfail_ticket` field), 6-0
- **Q6: Closed-ticket lint** — OUT of the spec, 6-0

Phase D did not run: no result was closer than 5-1.

##### Systems ballot

###### Q1: Parking (§8.10.5)
**Vote:** DEL
**Reasoning:** `--parked` has no code, and the cancel cascade it was built to suppress is gone. Keeping it would add a CLI flag, a directory walker and a second NDJSON record schema that every consumer must branch on, and no user would get anything from it. Its store (`.tmp/`) is gitignored, so it cannot survive a clone. That is not a base on which to build a spec mechanism.
**Concern:** The repo's ~820 local `.tmp/` fixtures lose their only spec anchor, so the repo must write its own habit into contributor docs or the habit will drift.

###### Q2: Behavioral sentence in place of the parking row
**Vote:** YES
**Reasoning:** The sentence costs no runtime and adds no schema. It pins the fixed cascade behavior, so if one bad file ever again stops the other files from running, that is a spec violation and not only a bug. It states only what the runner already does.
**Concern:** "Reports it as a build failure" with no wire shape means NDJSON consumers still see that failure only as unstructured text until the separate schema ticket lands. That ticket must not stall.

###### Q3: V1c informative note
**Vote:** SPEC-NOTE
**Reasoning:** Row 1 of the four-case table is the one row with no runner mechanism. A single generic line shows the one pattern that turns "does not build" into a real, strict red test at zero runtime cost. It must name no repo-internal helper and show no code users cannot run. Written like that, it adds no API surface.
**Concern:** A model may still invent a helper name to make the note concrete, so the wording must stay generic and have no code example.

###### Q4: `ticket:` in `test.failing`
**Vote:** T2
**Reasoning:** T2 costs one parser branch and one nullable `const char*` per record. It breaks none of the 48 files and needs no bootstrap dance. T3 is a mandatory field that the checker can only test for non-empty. Users fill it with `"none"`, so it carries no information. T1 closes the slot for every user and pushes the repo's link into unversioned state, which is the same flaw that sank parking.
**Concern:** With `ticket:` optional, the repo must enforce its own rule (require it, or remove it everywhere) through scripts/xfail_tickets.sh. If it does neither, the repo tests will mix both styles.

###### Q5: Wire encoding of a ticket
**Vote:** V2b
**Reasoning:** A consumer should read a field, not split a string on a non-ASCII " — ". Under V2a a reason that itself contains " — " cannot be read back without ambiguity. V2b costs the runtime one `if` and one `printf`, touches neither closed enum, and the record is byte-identical to today's shape when no ticket is given. V2a' throws away data the user wrote, and a tool that reads the stream would have to go back to the source to get it.
**Concern:** The runtime must JSON-escape `xfail_ticket` exactly as it escapes `xfail_reason`. A URL with a quote or backslash that goes out raw would corrupt the NDJSON line.

###### Q6: Closed-ticket lint
**Vote:** OUT
**Reasoning:** The lint forks a tracker process, and no user has that tracker. Even the repo does not run it in `task ci`, so the spec already disagrees with the code. The strict unexpected-pass rule catches the case that matters at no extra cost. A closed-ticket check is tracker bookkeeping, not test semantics.
**Concern:** Without a spec-level lint, red rows whose ticket closed as won't-fix can sit in a project for a long time. Only the project's own tooling will catch them.

##### Web/Scripting ballot

**Q1 — Parking (§8.10.5)**
1. **Vote:** DEL
2. **Reasoning:** A JS or Python developer expects a file that does not compile to be a build error. pytest, Jest, JUnit and Rust have no "parked file" state. `--parked` was a fix for a cascade that no longer exists, and it has no code. So it would be a public flag and event class with nothing left to do. Its store is `.tmp/`, which is gitignored, so nobody who clones the repo can use it.
3. **Concern:** The repo's own red-fixture habit loses its spec anchor, and it may drift if nobody writes the contributor doc.

**Q2 — Behavioral sentence in place of the parking row**
1. **Vote:** YES
2. **Reasoning:** "One bad file does not hide the others" is the one promise a scripting user cares about here, and the cascade bug showed that it can break. If the spec says it, a regression is a spec violation, not only a bug. The sentence adds no NDJSON shape, so it does not decide the build-failure schema that has its own ticket.
3. **Concern:** Until the separate schema ticket lands, users can read "reports it as a build failure" but cannot know what that looks like in NDJSON, so tool authors may each guess a different shape.

**Q3 — V1c informative note**
1. **Vote:** SPEC-NOTE
2. **Reasoning:** A reader who sees "does not build → not a test" will ask next "then how do I test that my code is rejected?". One line that answers this saves a Stack Overflow question. It must name no repo-internal helper and show no code that users cannot import, because a developer (or a model) will copy it and fail.
3. **Concern:** Somebody later "improves" the note with an example that calls `compile_test_helpers`, and users then try to import a module they do not have.

**Q4 — `ticket:` in `test.failing`**
1. **Vote:** T2
2. **Reasoning:** The common case, "link this red test to the GitHub issue", gets a named slot, and a solo scripting developer can leave it out. A mandatory field makes people write `ticket: "none"` or `"TODO"`, which looks tracked but is not (T3). T1 costs a 3-step migration over 48 files and takes the slot away from users who have a real URL. Under T2 the repo can still drop `ticket:` from its own tests to follow its no-br-ids rule.
3. **Concern:** With no lint, some projects will let `ticket:` values go stale, and nobody will see that a link points at a closed issue.

**Q5 — Wire encoding of a ticket**
1. **Vote:** V2b
2. **Reasoning:** A JS developer expects `record.xfail_ticket`, not a split on `" — "`. The em dash is non-ASCII, people paste it wrong into grep and jq filters, and a reason that contains " — " makes V2a ambiguous. With the BDFL ruling that V2b is in scope, the only argument against it is gone. V2a' drops data that a CI dashboard would want to show as a link.
3. **Concern:** Consumers that read only `xfail_reason` lose the ticket from their display, so the spec must say clearly that the ticket is in its own field now.

**Q6 — Closed-ticket lint**
1. **Vote:** OUT
2. **Reasoning:** A spec-level lint needs a tracker protocol, and the spec cannot name one that users have. The repo does not even run it in `task ci` today, so the spec describes something no one can run. The strict unexpected-pass rule and the mandatory `reason:` give rot protection with no tracker.
3. **Concern:** Without a spec example, each project writes its own check, and those checks will not agree on the form of a ticket reference.

##### PLT ballot

###### Q1: Parking (§8.10.5)
1. **Vote:** DEL
2. **Reasoning:** A file that does not build is not a program, so a runner event about it (`parked_file`) is a second schema outside the test-record set. It does not combine with anything else in §8.10. The store is `.tmp/`, which git ignores, so the spec would rest on state that a fresh clone cannot rebuild. The cascade clause has nothing left to suppress now that the runner no longer cascades. This is the 1c2zr6 PLT dissent, now with the evidence behind it.
3. **Concern:** The repo's own red-phase habit (`.tmp/<ticket>/`) must move to contributor docs in the same change, or the spec and the repo will drift apart again with no written policy.

###### Q2: Behavioral sentence in place of the parking row
1. **Vote:** YES
2. **Reasoning:** The sentence states a runner property that users can observe: one file that does not build cannot hide the results of the others. That is a real guarantee, and it adds no new concept or schema. It makes the cascade bug we fixed a spec violation, not only a bug, so it cannot return quietly. It names no wire shape, so it does not lock in anything the separate build-failure ticket must decide.
3. **Concern:** "Reports it as a build failure" has no specified shape until the separate NDJSON ticket lands, so implementations may differ on exit code and counts in the meantime.

###### Q3: V1c informative note
1. **Vote:** SPEC-NOTE
2. **Reasoning:** The sound answer to "a fixture that does not build yet" is a test that builds and states a static judgement about a source string (the `compile_fail`/`trybuild` shape). Saying this in one informative line points users to the right shape, and away from inventing their own parking areas. It must name no repo-internal helper, because a spec must not refer to a symbol that users cannot import.
3. **Concern:** Readers may take the note as a promise of a stdlib compile-fail API that does not exist. The wording must stay generic, and a real compile-fail test form needs its own spec ticket if users ask for it.

###### Q4: `ticket:` in `test.failing`
1. **Vote:** T2
2. **Reasoning:** An argument should be mandatory only if the semantics use it. A mandatory `ticket:` that the checker can only test for non-empty is a vacuous obligation, so T3 fails. T1 is sound but breaks existing user code and costs a 3-step migration, while T2 breaks no one. With V2b, T2 gives `ticket:` a real meaning: its own datum in the output. Absence stays encoded by omission, so E0835 keeps one meaning: an empty string that you wrote is always an error.
3. **Concern:** T2 is principled only together with V2b. If Q5 goes V2a, `ticket:` becomes sugar for a string convention in `reason:`, and the argument no longer earns its place.

###### Q5: Wire encoding of a ticket
1. **Vote:** V2b
2. **Reasoning:** A structured value must go on the wire as its own field, not packed into a string that consumers must split. V2a joins with `" — "`, and a reason can contain that same text, so the encoding cannot be read back without ambiguity. V2a' drops the datum completely, which makes `ticket:` unobservable, so T2 would collapse into T1 with extra syntax. V2b is purely additive, leaves the status and cause enums closed, and is what the Q3 principle ("separate `Str` fields, no regex parsing") asks for.
3. **Concern:** The spec must say that `xfail_ticket` is present if and only if `ticket:` is given, and never `""` or `null`. Otherwise consumers get three encodings of absence.

###### Q6: Closed-ticket lint
1. **Vote:** OUT
2. **Reasoning:** The spec cannot define "closed" for an opaque reference with no fixed tracker, so a spec-level lint has no semantics to check. Tracker checks are project tooling, and the repo keeps scripts/xfail_tickets.sh for its own use. This also fixes the current mismatch: the spec says `task ci` runs the lint, but the implementation does not.
3. **Concern:** Without any rot guard tied to a tracker, only strict unexpected-pass stops old `test.failing` rows from collecting. A red test that stays red forever for a changed reason goes unnoticed.

##### DevOps/Tooling ballot

**Q1: Parking (§8.10.5)**
- **Vote:** DEL
- **Reasoning:** `--parked` has no code, the cascade it was built to stop is fixed, and its store (`.tmp/`) is gitignored, so no CI job or fresh clone can see it. A CLI flag plus a second NDJSON event class means one more branch in every consumer, one more help-text entry and one more LSP/test-explorer case, all for a workflow no user has. Deleting it also brings the spec back in line with the code.
- **Concern:** the `--parked` impl ticket and any docs, `blink llms` topics or help text that mention the flag or `parked_file` must be closed or cleaned up at the same time, or models will keep generating a flag that does not exist.

**Q2: Behavioral sentence in place of the parking row**
- **Vote:** YES
- **Reasoning:** "Reports it as a build failure for that file and runs the other files" makes the fixed cascade behavior normative. A regression then breaks the spec, not just a test, and CI authors can rely on one broken file not hiding the rest. It specifies no NDJSON shape, so it does not prejudge the separate build-failure-event ticket.
- **Concern:** until that ticket lands, "reports it as a build failure" has no defined wire shape, so tools that read the stream (test explorers, agents) may each guess differently at how to detect and count a file that did not build.

**Q3: V1c informative note**
- **Vote:** SPEC-NOTE
- **Reasoning:** Row 1 of the four-case table needs a pointer to what to do instead, or users will ask the question the deleted section used to answer. One generic informative line with no helper named gives no import a model can hallucinate, and adds no decision point.
- **Concern:** a later edit may "helpfully" add a code example that names `compile_test_helpers` or an invented `expect_compiles`, and the spec would then point users at an API they cannot import.

**Q4: `ticket:` in `test.failing`**
- **Vote:** T2
- **Reasoning:** An optional, typed argument gives the LSP a named slot for signature help and link hover, and gives project lints a stable key to read. None of that works if the reference is buried in `reason:` text. A mandatory ticket (T3) produces `ticket: "none"`, which no lint can tell apart from a real reference. T1 costs a 3-step gen0 migration over 48 files and removes a slot users with a real issue URL want. T2 breaks no source, and the repo can still apply its no-br-ids rule by dropping `ticket:` from its own tests.
- **Concern:** relaxing E0835 to "empty if present" needs the parser, typecheck, formatter (omit the field when absent) and LSP signature changes to land together; if one lags, `blink fmt` or hover could print `ticket: ""` for a row that has none.

**Q5: Wire encoding of a ticket**
- **Vote:** V2b
- **Reasoning:** With an optional ticket, V2a gives `xfail_reason` two formats that nobody can reliably tell apart (a reason may itself contain " — "), and every jq filter or CI dashboard would have to split on a non-ASCII em dash. A separate optional `xfail_ticket` field reads with no parsing, leaves `xfail_reason` identical whether or not a ticket is given, and changes neither locked enum. The BDFL ruled it in scope, and that settled my only open question.
- **Concern:** the NDJSON schema docs, the runtime printer (bootstrap/runtime_test.h) and codegen at src/cg.bl:634 must agree that the field is absent, not `""` or `null`, when there is no ticket, or consumers will have to handle three shapes of "no ticket".

**Q6: Closed-ticket lint**
- **Vote:** OUT
- **Reasoning:** A spec-level lint would need a tracker protocol the spec cannot name, and `br` is not shipped, so today the spec demands a check no user can run. Even the repo runs `scripts/xfail_tickets.sh` outside `task ci`. Taking the lint out makes the spec describe what CI can actually do, and each project can add its own check against `xfail_ticket` or the source.
- **Concern:** with no lint in the spec and `ticket:` optional, stale expected-fail rows that point at closed tickets will go unnoticed in user projects; strict unexpected-pass catches only rows whose tests turn green, not rows whose ticket was abandoned.

##### AI/ML ballot

###### Q1 — Parking (§8.10.5)
1. **Vote:** DEL
2. **Reasoning:** A model that learns Blink from the spec will copy `--parked <ticket>` and `.tmp/<ticket>/` into user projects that have no `br` and no such layout. Those instructions cannot work outside this repo, so they are negative training data. The flag also has no implementation and nothing left to suppress now that the cascade is fixed. Deleting it removes a decision point and costs no user anything.
3. **Concern:** Stale copies of §8.10.5 in `blink llms` output, in decisions/, and in old model training sets can still teach `--parked`; the llms topics must drop it in the same change.

###### Q2 — Behavioral sentence in place of the parking row
1. **Vote:** YES
2. **Reasoning:** A model that writes CI scripts or reads test output must be able to predict what `blink test` does when one file does not build. "Reports a build failure for that file and runs the other files" is one sentence that fixes that answer, and it adds no schema. Without it (V1a only), the model has to guess, and a regression back to the cascade would not be a spec violation.
3. **Concern:** With no NDJSON shape given, a model that parses the stream may invent a record shape for the build failure; the follow-up schema ticket must not wait long.

###### Q3 — V1c informative note
1. **Vote:** SPEC-NOTE
2. **Reasoning:** Once the parking row is gone, a model that drives a compiler in its tests has no pattern for "the fixture does not build yet". One informative line ("compile a source string inside a test that builds") gives it a pattern it can apply, and it adds no new rule. If it lives only in repo contributor docs, `blink llms` will not show it, so models will not see it.
3. **Concern:** The note names no helper, so a model may invent one (for example `expect_compile_error` from std); the wording must say plainly that the project supplies the compile step.

###### Q4 — `ticket:` in `test.failing`
1. **Vote:** T2
2. **Reasoning:** The decision rule is one line, "give `ticket:` only when you have a real reference", and the default is to leave it out, so a model applies it reliably. T3 makes models fill the argument with made-up ids or `"none"`, which no check can catch. T1 needs a 3-step migration of 48 files for a gain that T2 mostly gives, and it breaks users who already pass real issue URLs.
3. **Concern:** Models trained on the 48 repo files, which all pass `ticket:`, will keep adding `ticket:` with made-up ids unless the repo drops `br` ids from its own tests and the spec examples show `test.failing` without a ticket first.

###### Q5 — Wire encoding of a ticket
1. **Vote:** V2b
2. **Reasoning:** With an optional ticket, V2a gives `xfail_reason` two formats, and a consumer cannot tell `"<ticket> — <reason>"` from a reason that contains " — ". A model that writes a consumer will split on the em dash and fail on some inputs, and no one will see it fail. V2b gives one field per datum: `record.xfail_ticket` is present only when a ticket is given, and the record without a ticket is the same as under V2a'. The BDFL ruled it in scope, and it touches neither locked enum.
3. **Concern:** Consumers written against the shipped `"br:<ticket> — <reason>"` format will break quietly; the changelog must state the format change, and the runtime must not keep the old prefix anywhere.

###### Q6 — Closed-ticket lint
1. **Vote:** OUT
2. **Reasoning:** A spec-level lint that queries one tracker is a rule no model can apply outside this repo, and the shipped code already does not run it in `task ci`. Strict unexpected-pass and a mandatory `reason:` keep the rot guard, and neither needs a tracker. Projects can lint `ticket:` against their own tracker, and the repo keeps scripts/xfail_tickets.sh.
3. **Concern:** With no lint in the spec, `test.failing` rows whose ticket closed long ago can rot in user projects; strict unexpected-pass catches only the rows that start to pass, not the rows that someone should delete.

##### Minimalism ballot

###### Q1: Parking (§8.10.5)
1. **Vote:** DEL
2. **Reasoning:** No code implements §8.10.5, the cascade it was built to suppress is gone, and its store (`.tmp/`, gitignored) does not survive a clone. My 1c2zr6 concession depended on a ticket-coupled lint that runs in `task ci`, and that lint cannot run there. Deleting unbuilt surface costs nothing and removes one flag, one event class, one store layout and one lint.
3. **Concern:** The repo's private `.tmp/` habit could creep back into the spec later under a new name, unless the next "park it" request first shows real user demand.

###### Q2: Behavioral sentence in place of the parking row
1. **Vote:** NO
2. **Reasoning:** "Reports it as a build failure" is half of a contract. The other half (the record shape, how it counts, the exit code) now goes to its own ticket. If this ticket sets the behavior and a different ticket sets the wire shape, one concern gets split across two decisions, and the second ticket starts out constrained by wording nobody designed for it. V1a says what the parking row needs to say. Leave runner behavior on build failure to the ticket that will specify all of it.
3. **Concern:** If YES wins, the vague "reports it as a build failure" will be read as a settled contract, and the follow-up schema ticket will add surface to satisfy it instead of asking whether it needs any.

###### Q3: V1c informative note
1. **Vote:** REPO-DOC
2. **Reasoning:** Only a project whose tests drive a compiler can use this note, and in practice that means the Blink repo. User-facing spec text for a single repo's workflow is how §8.10.5 got in. Even with no helper named, a model will try to invent one, so the note belongs in contributor docs next to `compile_test_helpers`.
3. **Concern:** If SPEC-NOTE wins, the line will pull in follow-up requests for a public `expect_compile_error` without any user asking for it; that belongs to PLT's separate compile-fail-test ticket.

###### Q4: `ticket:` in `test.failing`
1. **Vote:** T2
2. **Reasoning:** I withdrew T1 in round 1. The repo can enforce its no-`br`-ids rule by dropping `ticket:` from its own tests, and that needs no 3-step language migration over 48 files and no breaking change for users. T3 is the worst outcome for surface: a mandatory argument that the checker can only test for non-emptiness makes people write filler. Optional with omission meaning absence is the smallest form that breaks no one.
3. **Concern:** An optional argument with no specified consumer attracts features over time (URL validation, tracker lookups, a `--ticket` filter), so each one needs its own ticket and its own proof of demand.

###### Q5: Wire encoding of a ticket
1. **Vote:** V2b
2. **Reasoning:** I change from V2a here. With T2 winning, PLT's test decides it: an argument earns a place only if its value is observable as its own datum. V2a makes `ticket:` equal to a string prefix on `reason:`, which is sugar that consumers must split on " — ", and AI/ML showed that split is ambiguous. V2a' leaves `ticket:` as an argument the language does nothing with, which is the clutter I argued against in Phase A. V2b is one optional field, present only when the source has a ticket, with the enums untouched. It is the smallest encoding under which the argument means something.
3. **Concern:** `xfail_ticket` on the wire gives tools a place to hang tracker semantics, so the spec must say plainly that the value is opaque and that no runner or lint behavior depends on it.

###### Q6: Closed-ticket lint
1. **Vote:** OUT
2. **Reasoning:** A spec-level lint needs a tracker protocol, and the spec cannot name one. The implementation already keeps the lint out of `task ci` because `br` is local-only. Taking it out of the spec makes the spec describe what ships, and strict unexpected-pass plus mandatory `reason:` stay as rot guards that need no tracker.
3. **Concern:** Once the lint leaves the spec the repo may stop running `task xfail-tickets` at all, so stale rows that point at closed tickets could pile up unnoticed unless the repo gates on it somewhere.

### Final Spec

```blink
test.failing(
  "trait impl resolves through alias chain",
  reason: "Phase 3 trait elaboration not yet implemented",
) {
  // ... test body, expected to fail today
}

test.failing(
  "trait impl resolves through alias chain",
  reason: "Phase 3 trait elaboration not yet implemented",
  ticket: "https://example.com/issues/412",
) {
  // ... test body, expected to fail today
}
```

- §8.10.5 parking is removed: no `--parked` flag, no `parked_file` event, no `.tmp/<ticket>/` store, no `.tmp/` lint.
- A test file that does not build is not a test. `blink test` reports it as a build failure for that file and runs the other files. Its NDJSON shape is left to a separate ticket.
- One informative note: test rejected source through a compile step the project supplies; the standard library supplies none.
- `reason:` stays mandatory and non-empty. `ticket:` is optional; if given it must be non-empty (E0835). Its value is opaque; no runner or lint behavior depends on it.
- NDJSON: `xfail_reason` holds the reason only (no `br:` prefix). New optional `xfail_ticket: Str`, present if and only if `ticket:` is given, never `""` or `null`, JSON-escaped like `xfail_reason`.
- The closed-ticket lint is not spec. Projects may check tickets in their own tooling.
- Status and cause enums stay closed. Strict unexpected-pass stays.
