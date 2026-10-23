[< All Decisions](../DECISIONS.md)

# Escape-Hatch List and `_raw` Dispatch — Design Rationale

Spec ticket: the philosophy says Blink has "no escape hatches", but the spec has several: the `_raw` output operations bypass handlers (§4.4), and `@ffi`/`@trusted`, FFI regions, `Raw(s)` and `@verify(fallback: "trust")` each ask the compiler to take a claim on trust. The panel decided whether to change the philosophy text, remove the features, or both, and what the `_raw` operations do.

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated in independent-proposal → debate → vote rounds. Panelist text below is verbatim; "…" marks a cut.

#### Phase A — Independent proposals

##### Systems

**sys-1 (my preference): dispatch `_raw` through `IO.Print`; name the closed hatch list in §1.1**

**Effects change (§4.4).** The `_raw` ops stop bypassing handlers. They keep what the `_raw` name means today (decided in duplicate-apis.md Q4, 6-0): `Str`/`Bytes` argument only, every byte written, flushed before return, call order with `print`/`println` under the default handler. Only the dispatch changes.

…

##### Web/Scripting

**web-1 (my preference): stdout `_raw` ops dispatch through `IO.Print`; philosophy names a closed list**

`io.print_raw(s)` and `io.print_raw_bytes(b)` become `IO.Print` handler operations. They keep the full contract
already voted 6-0 in decisions/duplicate-apis.md Q4: every byte, flushed before return, call order with
`print`/`println` under the default handler. They get traced. The table rows become Yes / Yes / Yes.

…

##### PLT

**plt-1 (preferred): make the `_raw` writes handler operations of `IO.Print`; give `io.eprint*` a real effect**

**Rule.** Every `io.*` operation is a handler operation of the effect in its row. Nothing in `io` bypasses dispatch.

…

##### DevOps/Tooling

**devops-R1 (recommended for Q-raw): `_raw` ops become handler operations. No bypass.**

Keep the three names and their contract: `Str`/`Bytes` only, no `Display`, every byte written, flushed before
return under the default handler, call order with `io.print` under the default handler (04_effects.md:249, and
decisions/duplicate-apis.md L63: "The contract (exact bytes, flushed) must survive"). Remove only the bypass: each
`_raw` op performs a handler operation and emits a trace effect, like `io.print`.

…

##### AI/ML

**aiml-1 (preferred): state the true rule, list the marked hatches, close the `_raw` hole**

**Part 1 — philosophy text.** Replace the false absolute with a rule a model can test.

…

##### Minimalism

**min-1 (my pick): `_raw` ops dispatch through `IO.Print`; philosophy names the marked claims**

**1. No output op bypasses its handler.** `io.print_raw(s)` and `io.print_raw_bytes(b)` become `IO.Print` operations like `io.print`. They are handler-dispatched, handler-interceptable and traced. The decided contract (decisions/duplicate-apis.md Q4: every byte, flushed before return, call order with `print`/`println`) moves to the default `IO.Print` handler, unchanged. That decision file already says (L63) "if `_raw` is later removed ... the contract (exact bytes, flushed) must survive" — it does.

…

#### Phase B — Debate highlights

##### Systems

> All six seats put Q1-A first. I withdraw sys-2 (Q1-B) as a fallback: nobody needs it, and it adds a root-only effect to keep a bypass that saves one indirect call against a flush syscall. Q1-C leaves the false row from my Phase A probe (`quiet() ! Env.Read` writes stdout), so I oppose it in any form.

> New evidence: §4.7.1 *Completeness and auto-delegation* (04_effects.md:2146-) says an omitted **primitive** op forwards to the enclosing handler, and an omitted **derived** op runs its declared body against the same innermost handler. That decides V1:

> One normative list in §9.1; §1.1 says "no hidden escape hatches" and points to it. The spec already uses this pattern (§4.5 L1684, "the one normative statement"), and two copies will drift. I drop my "list in §1.1" text. I also ask that the list carry the definition from my Phase A: a hatch is a construct where the compiler assumes a fact it neither proves nor checks at run time. That gives V8 a test to apply.

##### PLT

> I concede: the `_raw` ops are traced like every other dispatched op. Trace is an observability property, and one rule for all ops is simpler.

> - **V6 L100:** I move to web-1's wording: keep "no `unsafe` escape hatch" and add one sentence that FFI regions (§9.1.1) are the one place where `Ptr[T]` is used without a check, and that each is marked. That meets my point (do not deny the region) with less change to the text.

##### Web/Scripting

> **Concessions**
>
> - Q1-C (my web-2) withdrawn.
> - V5: list in §9.1, not §1.1.
> - V6: plt-3's L100 rewording over mine.

##### DevOps/Tooling

> I concede my R1 left the derived/primitive status open, and that matters. Facts from the spec:

> - `IO.Print` is not `@handle_all` (07_trust_modules_metadata.md:2910: the stdlib marks `Rand`, `Time`, `IO.Read`).

##### Minimalism

> **Concessions this round**
> - V1: (a) → (b).
> - V4: add FFI regions as their own entry.
> - V6: keep → plt's rewording.

##### AI/ML

> Facts from the spec:

> - `IO.Print` is **not** `@handle_all` (04_effects.md:2304: the stdlib marks only `Rand`, `Time` and `IO.Read`).

> - An omitted **primitive** op forwards to the enclosing handler. An omitted **derived** op runs its body against the same innermost handler (04_effects.md:2148, 2164).

> Under (a), `io.print_raw(s)` performs the one primitive `print_bytes`. A text handler like `capture_print` (lib/std/testing.bl:16) omits that op, so the op forwards to the root and goes to the real stdout. **The test in my Phase A still fails under (a)**, and with no warning, because `IO.Print` has no `@handle_all`. Every user-written print handler in the wild has the same problem. (a) moves the hole; it does not close it.

#### Phase C — Final vote

##### Q1 `_raw` ops

**Q1: A 6-0.**

- **Systems**: A
  **Reasoning:** The bypass saves one indirect call per write, and each write already costs a flush syscall, so it buys nothing on the hardware. My Phase A probe showed it makes a row false: `quiet() ! Env.Read` writes to stdout. Dispatch through `IO.Print` keeps the codegen to one vtable call per write, the same as `io.print`.
  **Concern:** Bytes need a new `(ptr, len)` vtable slot in the runtime, and that slot needs the add-alongside / migrate regen dance. If the slot is skipped, `print_raw_bytes` would have to stay a direct C call.
- **Web/Scripting**: A
  **Reasoning:** A dev who wraps code in `capture_print` expects every stdout write to land in the list; Python `capsys` and Node stdout mocks work that way, and the raw write is the one they capture most surely. A keeps the byte contract the `_raw` use cases need (exact bytes, flushed) and removes the one property nobody asked for. B and C keep a mode a dev must learn and a test that pins a surprise.
  **Concern:** Until [the delegation-row ticket] lands, a user mock that omits a primitive op still leaks through delegation, so a dev may read "fixed" in the ruling and still see output on the terminal.
- **PLT**: A
  **Reasoning:** Today `IO.Print` has operations that no handler can intercept, so a `with` removes the effect from the row while the write still reaches stdout. That makes a proven row false. Under A, every operation of `IO.Print` goes to the innermost handler. Discharge then needs no exception, and the byte contract moves to the default handler unchanged. B is also sound, but it adds a special case to discharge and to the hierarchy that A does not need.
  **Concern:** A is sound only after [the delegation-row ticket]: until the `with` site's row includes the effects of the handler's clauses, a forwarding handler still writes `_raw` output past the sandbox.
- **DevOps/Tooling**: A
  **Reasoning:** A is the only option that adds no diagnostic and no new kind of row need for the LSP, `blink query` and hover to model. It also removes the one item that no tool reports today. The test gap and trace gap close at the same time.
  **Concern:** The two tests that assert the bypass (tests/test_std_testing.bl:52, :100) must be inverted and renamed, not deleted. A careless slice might delete them.
- **AI/ML**: A
  **Reasoning:** One handler rule with no exception: a `with` of `Handler[E]` sees every op of `E` in its block. A model can learn that from the spec alone and apply it. Today a test that uses `capture_print` passes while output leaks, and nothing in the source shows it. The choice between `print` and `print_raw` becomes a bytes-and-flush question, which a model can decide. It stops being "is interception harmful?", which it cannot.
  **Concern:** The tests that assert `_raw` is not captured must invert in the same change, or the corpus will teach the old rule.
- **Minimalism**: A
  **Reasoning:** A deletes a dispatch mode: the "No / No / No" rows and the bypass sentence at 04_effects.md:247 leave the spec. B keeps the mode and adds a second kind of row requirement to the one normative row rule. C writes a proven capability leak into the philosophy. A keeps the decided byte contract (duplicate-apis Q4) and the user-facing names, so the src/cli.bl call sites do not change.
  **Concern:** The root handler must keep the flush and order rule exactly. If the chore puts the flush in the wrapper and not in the default handler, a user handler that forwards could lose it without anyone seeing.

##### Q2 op shape

**Q2: b 6-0.**

- **Systems**: b
  **Reasoning:** Under §4.7.1 an omitted primitive op forwards to the enclosing handler, so under (a) `capture_print` would let `_raw` text reach the real stdout. A derived `print_raw` over `print_no_nl` reaches every existing capture handler with no edit. `print_raw_bytes` must be primitive, because `Bytes` can hold NUL and non-UTF-8 bytes.
  **Concern:** The flush and every-byte contract must be written on the root handler's ops, not on the declared body, or a reader will think a user handler owes a flush.
- **Web/Scripting**: b
  **Reasoning:** Under §4.7.1 an omitted derived op runs its body against the same innermost handler, so the first mock a dev writes (`print` + `print_no_nl` only) catches `io.print_raw` with no edit. The `Str` case is the 90% case (all 20 src/cli.bl sites). Binary output stays primitive because folding non-UTF-8 bytes into a `Str` op would be a silent wrong answer.
  **Concern:** A mock that omits `print_raw_bytes` still sends binary output outward, and the spec must say so plainly in the op table.
- **PLT**: b
  **Reasoning:** A derived `print_raw` runs at the call site against the innermost handler (§4.7.1), so each existing text handler, `std.testing.capture_print` included, catches `_raw` text with no change. A primitive `print_raw_bytes` is right for binary output, where a text handler has no correct default. Under (a), each existing handler leaves `print_bytes` out, so `_raw` output in tests goes to the outer handler and the captured list misses it with no warning.
  **Concern:** If (a) wins, `capture_print` must gain a `print_bytes` clause in the same change, or `std.testing` loses `_raw` output with no warning.
- **DevOps/Tooling**: b
  **Reasoning:** `IO.Print` is not `@handle_all`. Under (a), every existing text handler, `capture_print` included, omits `print_bytes` and silently forwards `_raw` text to the real stdout, with no warning. Under (b), the derived `print_raw` reaches each existing text handler with no edit. The remaining leak is `print_raw_bytes` under a text-only handler, and the handler table must state it.
  **Concern:** Hover and docs must show that `print_raw_bytes` forwards when it is omitted. If they do not, a host that writes binary through its sandbox will not know.
- **AI/ML**: b
  **Reasoning:** `IO.Print` is not `@handle_all`. Under (a), each existing text handler (including `capture_print`) omits `print_bytes`, so the op forwards to the root and the hole stays open. Under (b), the derived `print_raw` reaches `print_no_nl` on the same handler, so every existing text handler captures it with no change. The shape is the same as `IO.Read` (a primitive bytes op plus derived text ops), so a model learns it by analogy.
  **Concern:** `std.testing.capture_print` must also implement `print_raw_bytes`, or the stdlib capture still lets binary output reach the real stdout.
- **Minimalism**: b
  **Reasoning:** With a derived `print_raw` whose default body calls `print_no_nl`, every existing `IO.Print` handler, `capture_print` included, catches Str `_raw` output with no edit. With (a), each of those handlers would forward Str output past itself until someone edits it. One more op name is a small cost for closing the leak on day one.
  **Concern:** A handler that omits `print_raw_bytes` forwards it to the enclosing handler with no warning, because `IO.Print` is not `@handle_all`. Readers may expect W0545 there, and the spec text must not claim it fires.

##### Q3 trace

**Q3: yes 6-0.**

- **Systems**: yes
  **Reasoning:** When tracing is off the cost is one predictable branch. One rule for all `IO.Print` ops removes a hole in what a trace shows, and that hole bought nothing.
  **Concern:** A tight progress loop adds one trace record per fragment when tracing is on. That is noise, not a fault.
- **Web/Scripting**: yes
  **Reasoning:** Every other `IO.Print` op emits a trace record; a dev reading `--trace all` who finds the progress writes missing files a bug. No special case is cheaper to learn than one.
  **Concern:** A tight progress loop can flood the trace; the trace filters must stay good enough to hide it.
- **PLT**: yes
  **Reasoning:** Trace is an observability property, not a typing property. One rule for every dispatched operation is simpler to state and to learn than an exception for one family.
  **Concern:** None from the type side. The trace record must carry the bytes or their length in a form that keeps the "exact bytes" contract.
- **DevOps/Tooling**: yes
  **Reasoning:** A CLI that streams JSON with `_raw` is the program I most need to trace, and trace is opt-in at run time. Every output op then has the same trace column, which makes the table one rule and not two.
  **Concern:** High-rate progress output can flood a `--trace all` stream. The existing `fn:`/`module:` filters must be enough, and we must not add a special case for it.
- **AI/ML**: yes
  **Reasoning:** "Dispatched means traced" is one rule. A third combination in the §4.4 table is one more fact to look up and get wrong.
  **Concern:** A trace of a large binary stream could be big. The trace format should record a length, not the bytes.
- **Minimalism**: yes
  **Reasoning:** "Every handler-dispatched op is traced" is a rule with no exceptions. The reason for "no trace" (decisions/io-print-vtable-dispatch.md) went away with the bypass. Trace is opt-in at run time, so a program that does not ask for it pays nothing.
  **Concern:** High-rate progress output can flood a `--trace all` stream. The trace filters handle that; it is not a reason for an exception row.

##### Q4 stderr

**Q4: b 4-2** (devops, min: a). Settled in Phase D.

- **Systems**: b
  **Reasoning:** The invariant costs one sentence and holds whatever [the stderr row ticket] decides. Without it, `eprint*` keeps writing with no stated row until another vote, and nothing stops a new op from bringing back the hole.
  **Concern:** The sentence must not read as if it fixes the delegation-row hole ([the delegation-row ticket]). Q10 covers that.
- **Web/Scripting**: b
  **Reasoning:** One sentence in §4.5, "no Blink operation skips a handler that its row names; only an `@ffi` call does", is the rule a dev and an AI can hold in their head, and it tells the stderr ticket ([the stderr row ticket]) what it must not break. It adds no name and no placeholder effect.
  **Concern:** The sentence is false in practice until [the delegation-row ticket] fixes delegation, so it must ship with the Q10 dependence note.
- **PLT**: b
  **Reasoning:** The sentence states the invariant that this ruling restores, in the one normative place for row rules (§4.5). The spec is a blueprint: a stated invariant gives [the stderr row ticket] and [the delegation-row ticket] a target to meet, and gives reviewers a rule to check new operations against. Without it, the next unhandleable operation can come in with no rule against it.
  **Concern:** Until [the stderr row ticket] rules on stderr, `io.eprint*` break the new sentence. The ruling must name [the stderr row ticket] as the open exception, so the spec does not contradict itself with no explanation.
- **DevOps/Tooling**: a
  **Reasoning:** Stderr has its own open ticket ([the stderr row ticket]), and lib/std/testing.bl and 06_tooling.md disagree with §4 about `IO.Eprint`. A §4.5 sentence written now would make a claim that `io.eprint*` does not meet until that ticket lands. That is the same contradiction this ticket exists to remove.
  **Concern:** [the stderr row ticket] could stay at friction priority while the same false-proof hole stays open on stderr. It should be raised to this ticket's priority.
- **AI/ML**: b
  **Reasoning:** The sentence states, in the place a model reads for the rule, the invariant this ruling restores, and it gives the stderr ticket ([the stderr row ticket]) a fixed target. It adds no behavior. The spec does not yet name a row for `io.eprint`, so the sentence contradicts no current text.
  **Concern:** When [the stderr row ticket] gives stderr a handler-named row, it must make `io.eprint*` dispatch through it in the same change. If it does not, the new sentence becomes false.
- **Minimalism**: a
  **Reasoning:** Ticket [the stderr row ticket] owns stderr. Sys's invariant is the right end state, but stated now it is false on the same page: `io.eprint` and `io.eprintln` skip a handler today (my probe). A normative sentence that the spec itself breaks is the kind of drift this ticket exists to remove. Put the sentence in the stderr ruling, which makes it true.
  **Concern:** If [the stderr row ticket] sits as friction and is not promoted to type:spec, `io.eprint*` keeps the hole and the §1.1 text over-promises. The moderator should promote it.

##### Q5 philosophy

**Q5: A 6-0.**

- **Systems**: A
  **Reasoning:** Each of the four entries marks a fact the compiler assumes, in source, and a tool reports it. That makes "no hidden escape hatches" true and checkable. An FFI region gets its own entry because `with ffi.scope()` needs no `@trusted` and assumes facts about memory.
  **Concern:** The §1.1 names and the §9.1 list can drift. §1.1 must defer to §9.1 in so many words.
- **Web/Scripting**: A
  **Reasoning:** No language a web dev knows claims zero hatches; TS, Python and Rust claim theirs are visible and searchable, and that is the claim Blink can keep. One closed list in §9.1 with a pointer from §1.1 removes the contradiction an AI meets today between §1.1 and the heading "The Escape Hatch" in §3b.5, without two copies that drift.
  **Concern:** §1.1 "names them" plus the §9.1 list is still two places; if a later vote adds an entry and edits only §9.1, the drift returns.
- **PLT**: A
  **Reasoning:** "No hidden escape hatch, and here is the closed list" is a statement a reviewer or an AI can check. "No escape hatches" is false, and the spec breaks it in four places. One normative list in §9.1, with §1.1 pointing to it, follows the single-source pattern of §4.5 and stops the two copies from drifting apart.
  **Concern:** §1.1 may grow its own copy of the list over time. The edit should make §1.1 name the entries and point to §9.1, not state the rules again.
- **DevOps/Tooling**: A
  **Reasoning:** The spec already calls `Raw` "The Escape Hatch", so P2 is word games. P3 removes FFI, which line 100 sends users to. A keeps one normative table in §9.1 to edit. Each of the four entries already has a site report and a CI gate (`blink audit`, which lists FFI, pointer and `Raw()` sites (07:823), and `blink verify --deny trust`).
  **Concern:** The §1.1 names and the §9.1 table can drift. The commit that adds an entry must edit both.
- **AI/ML**: A
  **Reasoning:** A false absolute in §1.1 teaches a model to distrust the spec's stated rules everywhere. A closed list of four searchable marks is true and short, and a model can check each feature against it. One normative copy in §9.1 stops two lists drifting apart.
  **Concern:** §1.1 must name the four entries in exactly the §9.1 spelling. If the names differ, a model learns two vocabularies.
- **Minimalism**: A
  **Reasoning:** It makes the sentence true without adding a mechanism. One normative list in §9.1 avoids two copies that drift, and the four entries are exactly the places where the compiler takes the author's word. P2 fails on `with ffi.scope()`. P3 removes interop.
  **Concern:** §1.1 naming the entries is a second copy. It must say "listed in §9.1" so that §9.1 stays the definition when an entry changes.

##### Q6 L100

**Q6: i 4-2** (aiml, plt: ii). Settled in Phase D.

- **Systems**: i
  **Reasoning:** "No general `unsafe` block" says exactly what is true: no construct turns checks off for a whole block. Each hatch is narrow and named.
  **Concern:** A `with ffi.scope()` block is a block, so the text must say that it relaxes only `Ptr[T]` rules (E0811), not every check.
- **Web/Scripting**: i
  **Reasoning:** "No `unsafe` escape hatch" one paragraph above a list that contains `with ffi.scope()`, a block where `Ptr[T]` deref is unchecked with no `@trusted`, is the same contradiction this ticket removes. "No general `unsafe` block" is true and still tells a Rust dev what Blink does not have. ii keeps a sentence that a reader must reconcile with its own next sentence.
  **Concern:** "General" is a soft word; a reader may ask what a non-general `unsafe` block is, so the sentence must name FFI regions as the answer at once.
- **PLT**: ii
  **Reasoning:** The sentence must not deny that `with ffi.scope()` exists. It is a block where a `Ptr[T]` is used with no check and no `@trusted` record. Option ii makes the text true with the smallest change and keeps the line's real point: Blink has no general unsafe mode.
  **Concern:** The added sentence must name every FFI region kind of §9.1.1 (`@ffi` body, `@trusted` body, `with ffi.scope()`), or it will become stale when [the @trusted split ticket] rules.
- **DevOps/Tooling**: i
  **Reasoning:** A `with ffi.scope()` block is a narrow block where pointer checks are off. "No `unsafe` escape hatch" denies it, and option ii keeps that denial and adds a sentence that contradicts it. Option i says what is true and points at the list.
  **Concern:** The reword must not read as an invitation to write FFI regions. It should keep the "use a different language" steer for low-level systems work.
- **AI/ML**: ii
  **Reasoning:** "No `unsafe` escape hatch" next to an unchecked `Ptr[T]` reads as a contradiction to a model that has not reached §9.1.1 yet. One sentence that names FFI regions as the one marked place removes that contradiction at the point where a model first reads the claim.
  **Concern:** The added sentence must point to §9.1, not restate the region rules, or it becomes a second copy.
- **Minimalism**: i
  **Reasoning:** "No `unsafe` escape hatch" is false while `with ffi.scope()` is a block with unchecked dereferences. Option ii keeps the false clause and adds a sentence that contradicts it. Option i is one sentence and is true.
  **Concern:** "General" carries the meaning. The text must make clear that the narrow form is the FFI region, or readers will take "no general" as an evasion.

##### Q7 adding a list entry

**Q7: a 4-2** (devops, sys: b).

- **Systems**: b
  **Reasoning:** A stated test makes V8 something you can check, the same way 07:209 governs the audit list. devops's three criteria are concrete and match what I asked for. [the zero-copy Bytes ticket] (zero-copy Bytes FFI) is the first entry that would face the test.
  **Concern:** The test should also say what makes a construct a hatch (the compiler assumes a fact it neither proves nor checks at run time). Without that, someone can argue that a new bypass is not on the list at all.
- **Web/Scripting**: a
  **Reasoning:** A panel vote is the gate that matters, and the membership test in b is three conditions a future panel will argue over at the edges (does a lint count as "can fail CI"?). The closed audit list (scoped-value-trusted-channel.md Q2) already works with a vote and a short criterion.
  **Concern:** Without a stated test, a later panel may admit an entry that has no command to list its sites, which hurts the "searchable" promise of Q5.
- **PLT**: a
  **Reasoning:** A stated membership test is good in principle, but the devops test has not been checked against the four entries we are about to admit. A `with ffi.scope()` block, for one, has no `blink` command today that lists every site and can fail CI. A rule that a founding member fails makes the spec contradict itself. I would support the test as a follow-up once each entry has been checked against it.
  **Concern:** Without a test, membership turns on how each vote goes, and a later panel could admit an entry that has no mark and no report.
- **DevOps/Tooling**: b
  **Reasoning:** A stated test lets a reviewer or agent check a proposal before it reaches the panel, the same way 07:209 does for the audit list. All four current entries pass the test, and `_raw` as it is today fails it. That is the reason this ticket exists.
  **Concern:** "A `blink` command lists every site" must name the command per entry in §9.1, or the test becomes a claim that nobody checks.
- **AI/ML**: a
  **Reasoning:** A panel vote is enough, and it is easy to state. I am not sure every current entry passes devops's three-part test (for example, "a `blink` command lists every site" for `with ffi.scope()` blocks). A stated test that a current entry fails would itself be a contradiction in the spec.
  **Concern:** With no stated test, a later panel may add an entry with no searchable spelling. The panel must keep "one fixed token at the site" as an unwritten rule.
- **Minimalism**: a
  **Reasoning:** A panel vote is the guard that matters, and it matches the closed-list rule already voted 6-0. Option b's test adds three criteria that the list's own entries must then be audited against now (for example, today no single `blink` command lists `Raw(s)` sites and fails CI). That is new work and new surface with no bug behind it.
  **Concern:** A future panel could admit an entry with no tool to find its sites. The panel vote has to ask that question even with no written test.

##### Q8 other uses of "escape hatch"

**Q8: yes 6-0.**

- **Systems**: yes
  **Reasoning:** A broad row and a version pin assume no fact. If the word has a definition, it must mean one thing.
  **Concern:** None worth a vote. It is a wording chore.
- **Web/Scripting**: yes
  **Reasoning:** Once the term is defined, a broad row (`! FS`) and a stdlib version pin called "escape hatch" teach the wrong meaning to every reader and to the AI that trains on the spec. A small chore fixes it.
  **Concern:** The chore may miss uses in docs/ and `blink llms` text, which are outside sections/.
- **PLT**: yes
  **Reasoning:** Once the term means "an entry on the closed list", the other uses (a broad row, a stdlib version pin) mislead. A reader who sees "escape hatch" in §4 will look for it in §9.1 and will not find it. This is a wording chore with no change to the language.
  **Concern:** The chore must also cover "Escape hatch" in headings (03b_contracts.md:858 for `Raw`), so the term means the same thing in every place.
- **DevOps/Tooling**: yes
  **Reasoning:** If the term means only list entries, a search for "escape hatch" in the spec gives the reviewer the list and nothing else. This is a reword chore with no behavior change.
  **Concern:** None worth a vote. The chore must keep the `Raw` heading in 03b, since `Raw` is on the list.
- **AI/ML**: yes
  **Reasoning:** One term, one meaning. After this ruling, "escape hatch" means a §9.1 list entry. The broad-row and stdlib-pin uses would teach a model a looser sense of the term.
  **Concern:** None from my seat. It is a text-only chore.
- **Minimalism**: yes
  **Reasoning:** Once §1.1 gives the term one meaning, a use at 04_effects.md:212 that means "broad row" will mislead readers and AI. Two sites, one chore.
  **Concern:** The chore must not rename `Raw`'s "The Escape Hatch" heading. Under Q5-A that heading is accurate, and other sections cross-reference it.

##### Q9 `@verify(fallback: "trust")` audit record

**Q9: none 6-0.**

- **Systems**: none
  **Reasoning:** It is marked in source and reported by `blink verify --deny trust`, so it meets "not hidden". Whether it also needs an `audit:` record like `@trusted` is a separate consistency vote.
  **Concern:** If nobody files the follow-up ticket, the gap between `@trusted` and `trust` (one with a record, one without) stays in place.
- **Web/Scripting**: none
  **Reasoning:** The mark is searchable, the verify report shows `assumes: ... trust`, and `blink verify --deny trust` gives CI a hard gate. Adding an `audit:` record now raises the cost of the exact path 03b_contracts.md:615-621 warns pushes people toward bad workarounds, and it belongs in its own ticket.
  **Concern:** It stays the one list entry with no record, which a reader will see as an inconsistency until the follow-up ticket decides it.
- **PLT**: none
  **Reasoning:** The entry is on the list either way, and requiring a record would change a contracts ruling and every use of `"trust"`. That needs its own deliberation. The inconsistency is real: it is the only list entry with no recorded claim.
  **Concern:** If nobody files the follow-up ticket, the list will keep one entry that needs less than the others for no stated reason.
- **DevOps/Tooling**: none
  **Reasoning:** It already passes the membership test through `blink verify --deny trust` and the report's "assumes: ... trust" marker. An `audit:` record adds a surface and a pin workflow with no reviewer gain over the CI flag.
  **Concern:** The asymmetry with `@trusted` may confuse readers. §9.1 should say in one line why one entry has a record and the other has a report.
- **AI/ML**: none
  **Reasoning:** The annotation is already a fixed searchable token, `blink verify` reports it, and `--deny trust` gates it. A second spelling with `audit:` adds a decision point for little gain. A follow-up ticket can look at consistency.
  **Concern:** A model may still treat `@verify(fallback: "trust")` as the easy path for any contract the solver cannot prove (03b:615-621 already says so). An audit requirement would have made that path cost more.
- **Minimalism**: none
  **Reasoning:** `trust` suppresses no diagnostic, so the §9.1 membership rule (L209) does not cover it. Its mark is already searchable and reported (`blink verify --deny trust`). A record requirement is new surface with no lost information behind it.
  **Concern:** The asymmetry with `Raw` (audited) and `trust` (not audited) will look arbitrary to a reader. §9.1's list should state why each entry has the mark it has.

##### Q10 delegation-row dependency

**Q10: yes 5-1** (min: no).

- **Systems**: yes
  **Reasoning:** Under Q2-b, `print_raw_bytes` is primitive. A handler that omits it forwards to the outer handler, which a `with` has discharged from the row. That is the [the delegation-row ticket] hole. Claiming that Q1 closes the hole on its own would repeat the false-row error this ruling sets out to fix.
  **Concern:** If [the delegation-row ticket] is decided far later, the spec carries a known caveat. Being honest is still better than a false claim.
- **Web/Scripting**: yes
  **Reasoning:** Honest text beats a ruling that claims a fix the compiler does not yet give; a dev who hits the delegation leak must find the reason in the spec, not on a forum.
  **Concern:** If [the delegation-row ticket] stalls, the note stays in the spec for a long time and reads as an open defect in the language.
- **PLT**: yes
  **Reasoning:** I showed in Phase B that `default.op` delegation lets a function with no row reach the root handler (gen1, package build). If the Q1 text says nothing, readers will take Q1-A as closing the sandbox hole, and it does not do so alone. Naming [the delegation-row ticket] makes the dependency something a reviewer can check.
  **Concern:** The cross-reference can go stale. When [the delegation-row ticket] lands, the note in the Q1 text must be removed in the same change.
- **DevOps/Tooling**: yes
  **Reasoning:** Q1-A closes the hole only once an omitted operation cannot discharge a row that it forwards past ([the delegation-row ticket]). Saying so keeps the spec honest and gives the implementing slice a dependency it can check. Saying nothing would mean claiming a fix that is not true yet.
  **Concern:** The sentence must cite the rule by section once [the delegation-row ticket] lands, not by ticket ID. br IDs must not appear in spec text.
- **AI/ML**: yes
  **Reasoning:** If the text says the hole is closed while [the delegation-row ticket] is still open, a model trusts a claim that is false. A stated dependency keeps the spec honest, and it tells the reader which ticket closes the rest of the hole.
  **Concern:** The caveat must be removed when [the delegation-row ticket] lands, or it will outlive the fix as stale text.
- **Minimalism**: no
  **Reasoning:** The spec is a blueprint that states rules, not the status of other rulings. A conditional "this holds only once the delegation-row rule holds" is a status note in normative text, and it goes stale when [the delegation-row ticket] lands. [the delegation-row ticket] fixes §4.7 partial handlers for every effect, and Q1-A does not make that hole worse.
  **Concern:** Until [the delegation-row ticket] lands, a partial `IO.Print` handler that omits `print_raw_bytes` still forwards past itself. The Q1 chore should add a test that pins the Str case (`io.print_raw` under `capture_print` lands in the list), so the part we did close stays closed.

#### Phase D — Round 2

Q4 (4-2) and Q6 (4-2) were close, so the panel had one focused round on those two questions. Each panelist read the others' Phase C text, wrote a reply (D1), then voted alone (D). A fact from web's probe: the compiler today dispatches `io.eprintln` through an `IO.Eprint` handler (`capture_eprint` captures it) in a fn with no row, while the table in 04_effects.md said "not dispatched".

Options. Q4: **a** `io.eprint_raw` follows `io.eprint`, no further text; **b1** a, plus the §4.5 rule, open cases named in the decision file only; **b2** b1, plus the spec text names the open cases without ticket IDs. Q6: **i** reword to "no general `unsafe` block" and name FFI regions at once; **ii** keep "no `unsafe` escape hatch" plus one sentence on FFI regions.

##### Systems (D1, proposed text)

> No Blink operation skips a handler that its row names; only an `@ffi` call does. The stderr operations (`io.eprint`, `io.eprintln`, `io.eprint_raw`) have no stated row yet; §4.4 and [the stderr row ruling] will give them one that meets this rule.
> There is no ownership model, no manual memory management, and no general `unsafe` block that turns checks off. The one narrow form is an FFI region (§9.1.1), where a `Ptr[T]` may be used without a null or lifetime check; it relaxes only that rule, and each region is marked in source (§9.1). If you need to control individual cache lines, use a different language and call it via FFI.

##### Web/Scripting (D1, proposed text)

> **Not a systems language.** Blink does not compete with Rust or C for kernel development, embedded systems, or
> bare-metal programming. There is no ownership model, no manual memory management, and no general `unsafe` block:
> the FFI regions of §9.1.1 relax only the `Ptr[T]` rules, and only where Blink calls foreign code (§9.1 lists each
> marked bypass). If you need to control individual cache lines, use a different language and call it via FFI.

##### PLT (D1, proposed text)

> There is no ownership model, no manual memory management, and no general `unsafe` block. Raw pointers (`Ptr[T]`) are legal only in FFI regions (§9.1.1), and each region is marked in source; outside them, every check stays on. If you need to control individual cache lines, use a different language and call it via FFI.
> **No operation skips its handler.** No Blink operation skips a handler that its row names; only an `@ffi` call does (see *Proven and assumed rows*). Two open questions bound this rule today: the row of `io.eprint`, `io.eprintln` and `io.eprint_raw` (stderr), and the row that a handler's delegation adds at its `with` site.

##### DevOps/Tooling (D1, proposed text)

> There is no ownership model, no manual memory management, and no general `unsafe` block. Unchecked pointer use
> happens only in FFI regions (§9.1.1), each marked in the source and listed in §9.1.

##### AI/ML (D1, proposed text)

> There is no ownership model, no manual memory management, and no general `unsafe` block. The one place a `Ptr[T]` is used without a check is an FFI region (§9.1.1), and each is marked at its site (§9.1).
> No Blink operation skips a handler that its row names; only an `@ffi` call does. The stderr operations `io.eprint` and `io.eprintln` are the open exception (§4.4 table) until the stderr ruling.

##### Minimalism (D1, proposed text)

> **Not a systems language.** Blink does not compete with Rust or C for kernel development, embedded systems, or bare-metal programming. There is no ownership model, no manual memory management, and no general `unsafe` block. The one place a `Ptr[T]` is used without a check is an FFI region, and each FFI region is marked where it occurs and listed in §9.1. If you need to control individual cache lines, use a different language and call it via FFI.

##### Round 2 votes

**Systems**

###### Q4 stderr
**Vote:** b1
**Reasoning:** I move from b2 to b1. The spec is a blueprint: it states the rule, and the decision file tracks which cases do not meet it yet. As written, the spec gives `io.eprint*` no row and says they are not dispatched, so the rule holds for them. It is not false on the page. web's probe shows the compiler differs from the table (an `IO.Eprint` dispatch with no row). That is a compiler and stdlib mismatch for [the stderr row ticket] to settle, not a reason to put status text in §4.5. b1 keeps the rule I asked for and joins devops and min.
**Concern:** If [the stderr row ticket] and [the delegation-row ticket] are not promoted and scheduled, the stated rule and the shipped compiler stay apart, and only the decision file records that.

###### Q6 L100
**Vote:** i (sys D1 text; any i text is fine if it names FFI regions (§9.1.1) and says they relax only the `Ptr[T]` rules)
**Reasoning:** "No `unsafe` escape hatch" is false while `with ffi.scope()` permits unchecked `Ptr[T]` use. Option i makes the line true. The next clause defines "general" by naming the one narrow form.
**Concern:** A text that says only "no general `unsafe` block" and does not limit FFI regions to the `Ptr[T]` rules lets a reader assume that a region turns off other checks too.

**Web/Scripting**

###### Q4 stderr
**Vote:** b1
**Reasoning:** The §4.5 rule is the one line a dev and an AI need, and the spec is the blueprint, not a status page. A note in the spec text that lists open cases teaches readers that the rule has exceptions, and they will copy the exception, not the rule. The open stderr and delegation cases belong in the decision file and on their tickets, where the people who fix them look.
**Concern:** A reader who hits the delegation leak or the `IO.Eprint` mismatch before those tickets land finds a rule the compiler breaks and no hint in the spec why.

###### Q6 L100
**Vote:** i — web D1 text
**Reasoning:** It drops the false clause, names FFI regions at once after the colon so "general" is never a riddle, says they relax only the `Ptr[T]` rules, points at §9.1.1 and §9.1 instead of copying them, and keeps the "use a different language" steer word for word. A Rust or TS dev reads it in ten seconds and knows what Blink does not have and where the one narrow form lives.
**Concern:** If [the @trusted split ticket] splits `@trusted`'s region job, "relax only the `Ptr[T]` rules" must still be true of each region kind, or this line needs an edit with that ruling.

**PLT**

###### Q4 stderr
**Vote:** b2
**Reasoning:** The §4.5 rule states the invariant that this ruling restores, in the one normative place for row rules, and it gives [the stderr row ticket] and [the delegation-row ticket] a target to meet. web's probe shows the stderr text has drifted already: the compiler sends `io.eprintln` to an `IO.Eprint` handler, while the table says "not dispatched". A normative rule whose known exceptions appear only in a decision file repeats that drift, because a reader of the spec sees a rule the compiler breaks and no word on why. Naming the two open cases next to the rule, without ticket IDs, keeps the spec honest about its own gaps.
**Concern:** Each open-case clause must be removed in the same change that settles it ([the stderr row ticket], [the delegation-row ticket]). Otherwise the spec keeps an exception that no longer exists.

###### Q6 L100
**Vote:** i (text: plt, or any that names FFI regions at once and points to §9.1.1)
**Reasoning:** "No `unsafe` escape hatch" is false while `with ffi.scope()` is a block where pointers are not checked. Option ii keeps that false clause and then contradicts it. Option i states the true property, that no construct turns off checks for a whole block, and names the narrow form in the next clause. My D1 text also keeps the "use a different language" steer and does not repeat the region kinds, so it stays correct whichever way [the @trusted split ticket] goes.
**Concern:** If the final text lists the region kinds and does not point to §9.1.1, it becomes a second copy that drifts when [the @trusted split ticket] changes what an FFI region is.

**DevOps/Tooling**

###### Q4 stderr
**Vote:** b1
**Reasoning:** The rule gives a reviewer something to check each new operation against, and it belongs in §4.5. A note in the spec that lists open cases is a statement of current state. It goes stale the day [the stderr row ticket] or [the delegation-row ticket] lands, and nobody has a tool that flags the stale text. The decision file is the right home for "what is still open". web's probe shows that the compiler already dispatches `io.eprintln` through `IO.Eprint`, so the stderr case is a spec gap for [the stderr row ticket] to close, not a reason to qualify the rule.
**Concern:** If [the stderr row ticket] is not promoted to type:spec, the rule can stay unmet on stderr with nothing in the spec pointing at it.

###### Q6 L100
**Vote:** i (devops D1 text; any text that points at §9.1.1 and §9.1 and keeps the "use a different language" steer is acceptable)
**Reasoning:** Option ii keeps a clause ("no `unsafe` escape hatch") that the next sentence must contradict. Option i is true, and naming FFI regions at once answers "what is a non-general one?". A pointer and no list of region kinds keeps one copy of the rules, and it stays true whatever [the @trusted split ticket] decides.
**Concern:** A text that lists the region kinds inline makes a second copy of §9.1.1, which drifts when [the @trusted split ticket] rules.

**AI/ML**

###### Q4 stderr
**Vote:** b2
**Reasoning:** A model reads the spec, not the decision file. A rule that the spec states as absolute while known cases break it teaches the model a false fact, and that is this ticket's defect. Naming the open cases next to the rule keeps the statement closed and true. web's probe changes the stderr part. `io.eprintln` does dispatch through `IO.Eprint`, but from a fn with no row, so it does not skip a handler its row names. The note must therefore name the stderr case as "dispatched with no stated row" (the §4.4 table is wrong), not as a skip. That correction applies to my D1 text. The delegation case is still a true exception.
**Concern:** The open-case note must be worded from the probe facts, not from the D1 texts (mine included). It must also be deleted when each case closes, or it becomes stale text that a model learns as a rule.

###### Q6 L100
**Vote:** i, aiml D1 text (plt's is also acceptable if the region kinds stay a pointer to §9.1.1, not an inline list)
**Reasoning:** Option i says one true thing, and its second sentence answers "what is a non-general `unsafe`?" at once. A pointer to §9.1.1 and §9.1 keeps one normative copy of the region kinds, so [the @trusted split ticket] cannot make this line stale.
**Concern:** A model may read "the one place a `Ptr[T]` is used without a check" as an invitation to write FFI regions. The "use a different language" steer must stay right after it.

**Minimalism**

###### Q4 — stderr
**Vote:** b1
**Reasoning:** The rule gives [the stderr row ticket] and every future op one target in the one normative place for row rules, and it costs one sentence. Web's probe shows the compiler already dispatches `io.eprintln` through an `IO.Eprint` handler. So the stderr case is drift between spec and compiler that [the stderr row ticket] must settle, and the decision file is where that open case belongs. Naming open cases next to a normative rule (b2) puts status text in a blueprint, and it goes stale as soon as [the stderr row ticket] or [the delegation-row ticket] lands. Then someone has to remember to delete it.
**Concern:** If [the stderr row ticket] is not promoted and voted soon, a reader of §4.5 meets a rule that the stderr table (04_effects.md:241-242, "not dispatched") seems to break. The [the stderr row ticket] ruling must fix the table and the dispatch in the same change.

###### Q6 — L100
**Vote:** i — text: min (D1); I accept any i text that points to §9.1 and does not list the region kinds in §1.3.
**Reasoning:** "No `unsafe` escape hatch" is false while `with ffi.scope()` exists, and ii keeps that clause. The min text says the region relaxes only `Ptr[T]` checks, answers "general" in the next sentence, and points to §9.1. So it cannot go stale when [the @trusted split ticket] changes the region kinds.
**Concern:** A text that lists the region kinds inline makes a second copy of §9.1.1 that will drift after [the @trusted split ticket].

**Round 2 result.** Q4: **b1 4-2** (web, devops, min, sys; plt and aiml: b2). Q6: **i 6-0**.

### Final Spec

**`IO.Print` operations (§4.4).** `io.print_raw` and `io.print_raw_bytes` are handler operations of `IO.Print`. They are dispatched, interceptable and traced. The default (root) handler keeps the byte contract: it writes every byte, flushes before it returns, and takes `Str` or `Bytes` only.

```blink
fn print_raw(s: Str)          // derived; the default body calls print_no_nl(s)
fn print_raw_bytes(b: Bytes)  // primitive
```

**§4.5 rule.** "No Blink operation skips a handler that its row names; only an `@ffi` call does." The spec carries no list of open exceptions next to it (b1).

**The closed list (§9.1).** An escape hatch is a marked construct where the compiler takes a claim on trust that it cannot check. The four entries:

1. `@ffi` binding with `@trusted(audit: K)`.
2. FFI region (an `@ffi` or `@trusted` body, or `with ffi.scope()`).
3. `Raw(s)`.
4. `@verify(fallback: "trust")`.

Locked points:

- Q1 A, Q2 b: `print_raw` is derived and `print_raw_bytes` is primitive. A handler that omits `print_raw_bytes` forwards it to the enclosing handler. `IO.Print` is not `@handle_all`, so W0545 does not fire.
- Q3: the `_raw` operations emit trace records.
- Q4: `io.eprint_raw` has the same dispatch as `io.eprint`. The §4.5 sentence is in the spec (b1).
- Q5: §1.1 says "no hidden escape hatches" and points to §9.1. §9.1 holds the one normative list.
- Q6: §1.3 says "no general `unsafe` block" and names the FFI region at once (sys D1 text).
- Q7: a new entry needs a design-panel vote.
- Q8: "escape hatch" in the `! FS` paragraph (§4.3) and the stdlib pin line (§10.7) no longer uses the term. The `Raw` heading and the historic vote text in §3 stay.
- Q9: `@verify(fallback: "trust")` gets no `audit:` record in this ruling.
- Q10: the `_raw` text says that a handler that delegates to the enclosing `default` can still send output outward, and that the row added by that delegation is an open question.

### Open cases and follow-ups

- **Stderr row and dispatch.** `io.eprint`, `io.eprintln` and `io.eprint_raw` have no stated row in §4. The §4.4 table says "not dispatched". Web's probe shows the compiler dispatches `io.eprintln` through an `IO.Eprint` handler (`capture_eprint` captures it) in a fn with no row. The stderr ruling must settle the row, the table and the dispatch in one change, so the §4.5 rule holds for stderr. devops, min and web asked that it move from friction to `type:spec` at this ticket's priority.
- **Delegation row.** A handler that delegates to the enclosing `default`, or that omits a primitive operation, can send output outward after a `with` has removed the effect from the row. The spec text states this as an open question by section name. When the delegation-row rule lands, that sentence goes in the same change.
- **`@verify(fallback: "trust")` audit record.** It is the one list entry with no recorded claim. Q9 left it unchanged (6-0); the follow-up ruling decides whether it needs an `audit:` record.
- **Q7 membership test.** devops and sys wanted a stated test (one fixed spelling; a `blink` command that lists every site and can fail CI; no `@allow` hides it). plt held that a founding member such as `with ffi.scope()` fails the test today. Soft consensus: a test is a follow-up once each entry is checked against it.
- **Q6 text pick.** The moderator picked the sys D1 text. Every seat accepts any `i` text that names FFI regions at once, points to §9.1.1 and §9.1, lists no region kinds, and keeps "use a different language".
- **Split of the `@trusted` region and record jobs** remains open and does not change this list: the list names FFI regions and `@trusted` as separate entries.
