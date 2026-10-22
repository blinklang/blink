[< All Decisions](../DECISIONS.md)

# One Call Form for Handle Operations — Design Rationale

### Panel Deliberation

The ticket (verbatim):

> Title: Spec: may a handle op be called with method syntax (child.wait() for process.wait(child))?
> Desc: From the effect-tracked builtins panel: Q4a passed 4-2 for process.wait(child) only; Systems and Web wanted child.wait() as sugar for the same op. §4.4.2 already shows both server.serve() and net.serve(server) for serve, so the spec is not consistent. Decide one rule for method-call syntax on handle ops and fix §4.4.2 to match. See decisions/effect-tracked-builtins.md.

Moderator triage found that the ticket speaks of one rule, but its text raises four more questions. The released `std.process` `Pid` type has `kill` and `send_signal` methods that the op name `signal` cannot reach. Several spec lines contradict any one rule: the `fs` file-handle text, the §4.7 examples, the §4.4.2 prose, and the `.await` rows in §4.13. Route registration (`server.route`, `.get`, `.post`) raises a separate question about rule 3 of §4.4. Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated in three phases, with two rounds in Phase B. Phase D was not triggered. Quoted text is each panelist's own words. Each quote is a whole paragraph or list item of the panel record, or a line range of one; "…" marks a cut.

Questions:

- Q1: the rule. A handle op has one spelling, `handle.op(value, ...)`. `v.op(...)` is trait-method lookup only. When lookup fails, E0505 gives the handle form if a visible effect has an op of that name whose declared first parameter type equals the receiver type.
- Q2: applicability of the fix when one op matches. **R:** the rewrite is machine-applicable whatever the row; the missing-effect diagnostic owns the row edit. **G:** machine-applicable only when the enclosing row grants the op. **T:** two edits, the rewrite and the row addition, both machine-applicable, in the shape of the removed-function rows.
- Q3: rows keyed by `Child` for `child.kill(sig)` and `child.send_signal(sig)`, with a literal `0` argument to `kill` mapped to `SIGKILL`. Q3b: a sentence in §3.2 that keys rows for a replaced type by the replacement type.
- Q4: text that contradicts the rule. Q4a: the `fs` file-handle text, the §4.7 examples and a note on the old Net.Listen vote. Q4b: the §4.4.2 prose.
- Q5: `.await`. Q5a: reword the §4.13 rows so `.await` is a postfix keyword, not a method call. Q5b: one sentence in the rule that excludes `.await`.
- Q6: one sentence beside the §4.4.2 example that route registration is not a `Net.Listen` operation.

#### Phase A — Independent proposals

Every seat proposed the handle form as the one spelling, with a general E0505 help built from the declared ops. Systems and Web/Scripting withdrew their earlier vote for `child.wait()` as sugar (see the effect-tracked builtins decision). The seats differed on whether the fix is machine-applicable when the row lacks the effect.

- **Systems:**

  > **Rule.** A handle operation is called only through its handle: `handle.op(args)`. A value that a handle op made is an
  > ordinary argument. `v.op(args)` is always trait-method lookup on the type of `v` (§3c.4); it never reaches a handler.
  > When that lookup fails and some effect op `op` takes the type of `v` as its first parameter, the `UnresolvedMethod`
  > error (E0505) carries a machine-applicable fix to `handle.op(v, args)`. The fix is table-free: the compiler builds it from
  > the declared effect ops (stdlib and user effects alike), so it covers every op, not a hand-kept list.

- **Web/Scripting:**

  > **Rule (§3c.4 *Effect Handle Operations*, new paragraph).** You call a handle operation only through its handle: `handle.op(args)`. Dot on a value never reaches a handle operation. This is true also when the first parameter of the op is a value that a handle op made (§4.4 rule 3). `child.wait()` and `server.serve()` go through method lookup as usual. If no trait method matches, the call is `UnresolvedMethod` (E0505).

  > **Diagnostic rule (§3c.4, after rule 2 *No match*).** Method lookup fails for `recv.foo(args)`, and `recv` has type `T`. If an effect that the program can see has an op `foo` whose first parameter has type `T`, E0505 gets a help line and a machine-applicable fix. The fix rewrites the call to `h.foo(recv, args)`, where `h` is the handle of that effect. The rewrite keeps the evaluation order: the receiver is first and the arguments follow it, as before. If the enclosing function does not declare the op's effect, the help also names the effect to add. The help comes before the missing-effect error. The fix does not depend on the effects that the function declares.

- **PLT:**

  > > **A handle op has one spelling.** A handle op is called only through its handle: `process.wait(child)`,
  > > `net.serve(server)`. A value is never the receiver of a handle op. `x.op(args)` is a method call and resolves
  > > through trait lookup only (§3c.4 *Trait Method Lookup*), also when the type of `x` is a value that a handle op made.
  > >
  > > When method lookup for `x.op(args)` fails, and an effect declares an op `op` whose first parameter has the type
  > > of `x`, the error is E0505 (UnresolvedMethod) with a machine-applicable fix that rewrites the call to
  > > `h.op(x, args)`, where `h` is the handle of that effect. The compiler derives this fix from the effect
  > > declarations. It needs no row in a removed-names table.

- **DevOps/Tooling:**

  > > A handle operation is called only through its handle: `process.wait(child)`, `net.serve(server)`. A value that a handle op made has no methods for the operations of that effect. `child.wait()` is a method call (§3c.4: dot means method), so it is resolved by trait lookup. When that lookup fails and the effects in scope declare an operation `wait` whose first parameter has the type of the receiver, the error E0505 (`UnresolvedMethod`) carries a machine-applicable fix that rewrites the call to `process.wait(child)`. The compiler derives this fix from the effect declarations, so it needs no row in a removed-names table. If the function row does not include the effect, the fix also says which effect to add.

- **AI/ML:**

  > **Rule.** A handle operation has exactly one call form: `handle.op(args)`, where `handle` is the effect's reserved handle name (`net`, `process`, `fs`, ...). A value never takes a handle op with dot syntax. `x.op(args)` on a value is always a trait-method call (§3c.4), and when no trait method `op` exists for the type of `x`, the call is `UnresolvedMethod` (E0505), as for every other missing method.

- **Minimalism:**

  > > A handle operation has one call form: the handle name, a dot, the operation, and its arguments, as in `process.wait(child)` or `net.serve(server)`. The handle is the receiver, and a value that the operation consumes is an argument. `x.op(args)` where `x` is a value is always a trait method call (§3c.4 *Trait Method Lookup*). It never reaches a handle operation, even when the first parameter of an operation named `op` has the type of `x`.

#### Phase B — Debate highlights

Two rounds. All six seats ended each round ready to vote.

Round 1, applicability of the fix (Q2). Systems, Web/Scripting, DevOps/Tooling and AI/ML held that the rewrite is machine-applicable whatever the row says. PLT and Minimalism each changed side from their Phase A text: PLT to the row-dependent text, Minimalism to the always-applicable text.

- **Systems (round 1):**

  > The rewrite `child.wait()` → `process.wait(child)` is correct whatever the row says. The row is a second, separate
  > fault with its own error and its own fix. Tying applicability of fix 1 to the row (min's text) makes `blink fix`
  > stop at a call that it knows how to rewrite, for a reason that fix 1 does not touch. Two steps, one reason each, is
  > the predictable shape. I withdraw my sys-1 wording ("a second note says which effect to add") only as far as it
  > implied one combined diagnostic; a note on E0505 that names the effect is fine, but it must not gate the edit.

- **Web/Scripting (round 1):**

  > I change my web-1 text to plt's. The rewrite `v.op(args)` → `h.op(v, args)` is correct whatever the function's row is. It keeps the same op, argument order and evaluation order. So the fix is machine-applicable. If the row lacks the effect, the fixed call gives the usual missing-effect error, and that error has its own fix. `blink fix` then takes two steps, and each step has one reason. A user who reads the first error still sees the effect in a note ("`wait` is an operation of the `Process` effect"), so nothing hides from them.

- **PLT (round 1):**

  > My A text made the call rewrite machine-applicable in all cases and let the missing-effect error follow. I withdraw
  > that. §3.1 rule 1 (sections/03_types.md:23) says a machine-applicable fix must lead to a legal program, and the
  > rewrite alone does not when the row lacks the effect. The second step (add `! Process.Spawn` to the signature) is not
  > safe for a tool to apply on its own: it changes the function's type, every caller's row, and can break a module
  > budget. So:

- **Minimalism (round 1):**

  > My Phase A text made the fix depend on the enclosing row. plt's form is simpler and I take it: the fix is machine-applicable no matter what the row holds. If the row lacks the effect, the fixed call gives the usual missing-effect error with its own fix. Each error has one reason and one fix, and no diagnostic needs to read the row to choose its own form. That is less spec text than mine.

Round 2. PLT read §3.1 again and returned to the rewrite-only fix; Minimalism went back to its Phase A text:

- **PLT (round 2):**

  > I read §3.1 again and my B1 reading was too strict. Rule 1 asks that "some edit the diagnostic names must make the
  > program legal". The help names the rewrite and, when the row lacks the effect, a note names the effect to add. Those
  > two edits together make the program legal, so rule 1 holds. Rule 1 does not say that the machine-applicable part
  > alone must compile.

- **Minimalism (round 2):**

  > plt is right, and §3.1 decides it. Rule 1 (sections/03_types.md:18-26) says a machine-applicable fix must lead to a legal program. Rule 3 says the repair named first must discharge every diagnostic at that point. When the row lacks the effect, `process.wait(child)` alone is not legal, and the next step (add `! Process.Spawn`) changes the function's type and every caller's row, so a tool must not apply it on its own. My B1 concession to "always machine-applicable" broke §3.1. I withdraw it.

AI/ML then raised the removed-function shape at 04_effects.md:374 as a third choice, T:

- **AI/ML (round 2):**

  > plt is right that §3.1 rule 1 forbids a machine-applicable fix that does not lead to a legal program, so my B1 text ("the rewrite alone, then a second error") is not enough. But plt's claim that a tool must never add the effect to the row contradicts the spec we already have:
  >
  > - sections/04_effects.md:374 (removed-functions table, voted 6-0): "the fix carries two edits: the call rewrite and the addition of the effect to the enclosing row. Both are machine-applicable when the replacement takes the same arguments."
  > - sections/04_effects.md:3467 (E0552): "The fix adds `State` to the row, and it is machine-applicable (§8.6)."
  > - sections/01_philosophy.md:82 gives `{kind: "missing_effect", fix: {insert: " ! IO"}}` as the model case of a machine-applicable fix.
  >
  > So the rule that fits both §3.1 and the existing tables is the :374 shape. **Changed position:** the E0505 handle-op fix carries two edits, the call rewrite and, when the enclosing row lacks the op's effect, the addition of that effect to the row. Both are machine-applicable. The fix then gives a legal program at that point in one step (rule 1). It is also the first repair named, so it discharges both diagnostics (rule 3). That a caller's row may then need the effect is the normal missing-effect cascade, and each caller gets its own fix, as for every other row addition. The rows that §4.4 excludes stay excluded: an `@ffi` decl row (:206) is never written by a tool. Where the enclosing function has no row a tool may write, the row edit is a suggestion and the rewrite is too.

Systems and Web/Scripting found that a row keyed by `Pid` can never fire after the rename, so the rows key by `Child`:

- **Systems (round 2):**

  > The facts in the digest change my view: sections/ has no `Pid` type, and the §4.4 table already has the
  > `process_pid_*` rows (04_effects.md:351-352). The spec side is consistent today; the gap is the `PidOps` methods in
  > lib/std, which is migration work for the effect-tracked-builtins follow-up. I keep one point for that chore: `kill` and
  > `send_signal` do not match the op name `signal`, so the generic H1 fix does not cover them on any receiver type; the
  > chore must add rows (or foreign-spelling hints keyed on `Child`) for them. Web's point is correct and belongs in the
  > same chore: `kill(0)` meant SIGKILL, so only a literal argument gets a machine-applicable fix.

- **Web/Scripting (round 2):**

  > sys and min are right, and I was wrong. sections/ has no `Pid` type. A migrated program gets a `Child` from `process.spawn`, so a row keyed by `Pid` never fires. Code that names `Pid` gets an unknown-type error first. The free-function rows that already exist (04_effects.md:351-352) cover `process_pid_*`.
  >
  > What remains:
  > - `child.wait()`: the generic H1 fix covers it, so no row is needed.
  > - `child.kill(sig)` and `child.send_signal(sig)`: the op is named `signal`, so the generic fix does not match. These need rows keyed by receiver type `Child` → `process.signal(child, sig)` (sys). My `0` point carries over. `child.kill(0)` → `process.signal(child, SIGKILL)`. `kill(s)` with a non-literal `s` is not machine-applicable, because `0` changes meaning.

Web/Scripting also found that the released `kill` method used `0` to mean `SIGKILL`:

- **Web/Scripting (round 1):**

  > - `pid.kill(sig)` used `0` to mean SIGKILL (process.bl:47). So the fix for `pid.kill(0)` is `process.signal(child, SIGKILL)`, and for `pid.kill(s)` with a non-literal `s` it is not machine-applicable, because the meaning of `0` changes. `pid.send_signal(s)` → `process.signal(child, s)` is machine-applicable apart from the Result change. "Result changes: yes" covers the `Int` → `Result` change in all three rows.

PLT found that `.await` at 04_effects.md:2951 and :2999 states the pattern that the rule forbids; Minimalism agreed after it checked the text:

- **PLT (round 2):**

  > min says "the spec already defines it as a postfix suspension point". I searched: no line in sections/ calls `.await`
  > a postfix operator or a suspension point (`rg -i postfix sections/ | rg -i await` is empty). The only definitions are
  > 04_effects.md:2952 "Method on `Handle[T]`" and :2999 "method syntax for *consuming* results ... the operation belongs to
  > the handle". `async.spawn` is a handle op and makes the `Handle[T]`. As written, :2999 states the exact pattern that
  > H1 forbids, and gives a "data flow" reason that would apply equally to `child.wait()`. A model that reads the spec
  > will cite it.
  >
  > So "drop" leaves the spec contradicting the rule it just adopted. My position, unchanged from B1:
  > - In this ticket: one sentence in the rule text ("`.await` is a postfix operator, not a method call; this rule does
  >   not apply to it"), and reword :2952 to "Postfix operator on `Handle[T]`" and :2999 to "postfix syntax for
  >   *consuming* results". Wording only; no semantics change.
  > - Separate type:spec ticket: whether the `Async` handler that made a `Handle[T]` answers `.await` (rule 3 coherence).

- **Minimalism (round 2):**

  > I said the spec already calls `.await` postfix. It does not. sections/04_effects.md:2951 (the digest says :2952; the row is at :2951) reads "Method on `Handle[T]`", and :2999 states "method syntax for *consuming* results (`handle.await`) … the operation belongs to the handle". `async.spawn` is a handle op that makes the `Handle[T]`, so :2999 states, as a design principle, the exact pattern H1 forbids. Leave it, and it is the counter-precedent the next ticket cites.

#### Phase C — Silent vote

| Question | Result |
|---|---|
| Q1 one call form | **yes 6-0** |
| Q2 applicability of the fix | **T 5-1** (PLT *(dissent)*: R; sys, web, devops, min moved to T) |
| Q3 `Child`-keyed rows | **I (this ticket) 6-0** |
| Q3b §3.2 replaced-type sentence | **yes 6-0** |
| Q4a file-handle text, §4.7 examples, DECISIONS.md note | **yes 6-0** |
| Q4b §4.4.2 prose | **yes 6-0** |
| Q5a reword the `.await` rows | **yes 6-0** |
| Q5b `.await` sentence in the rule | **yes 5-1** (Minimalism *(dissent)*) |
| Q6 route-registration sentence | **yes 5-1** (Minimalism *(dissent)*) |

Each seat's vote, reasoning and concern:

- **Systems:**

  - Q1 one call form (H1) — **Yes**

    > **Reasoning:** Under H1 the source shows the dispatch kind: `x.f()` is always a static, monomorphized trait call, and
    > `h.f()` always goes through the handler that is in scope. No later import or trait impl can silently move a call off the
    > handler, which is the mock-bypass failure that rule 3 forbids. The fix runs only in the error path and is an exact
    > lookup by (op name, type), so it adds nothing to the success path of the checker or to run time.
    > **Concern:** The new E0505 help scans visible effect ops on each failed method lookup; if that is not indexed by type it
    > becomes a slow path in large programs with many failed lookups (such as an LSP typing session).

  - Q2 applicability of the fix — **T**

    > **Reasoning:** I change from G. My B2 reason for G was that a tool must not add an effect to a row, and the ballot facts
    > show the spec already does exactly that: 04_effects.md:374 (both edits machine-applicable) and E0552 at :3467. T meets
    > §3.1 rule 1 in one step (the named edits give a legal program) and rule 3 (the first repair discharges both errors), and
    > it gives one fix shape for "this call needs an effect" across the spec. The :2510 precedent does not apply: there no
    > single edit is correct; here the edit is fully determined by the op's declared effect.
    > **Concern:** If T wins, the writer must reuse the :374 exclusions word for word (for example `@ffi` rows, which a tool never
    > writes), or a batch `blink fix` may add effects in places the spec elsewhere forbids.

  - Q3 `Child`-keyed rows — **I**

    > **Reasoning:** I drop my B2 "chore" preference. The rows close the one hole in the generic help (the op is named `signal`,
    > so name matching cannot reach `kill` or `send_signal`), and they sit beside the help this ticket adds. Only a literal
    > `0` maps to `SIGKILL`; a non-literal argument stays a suggestion, which is correct.
    > **Concern:** A row keyed by `Child` for names that `Child` never had needs Q3b, or it breaks §3.2's own rule.

  - Q3b §3.2 replaced-type sentence — **Yes**

    > **Reasoning:** §3.2 keys a row by receiver type and admits only released names; `Pid.kill` was released, `Child.kill` was
    > not. One sentence keeps the Q3 rows legal under the spec's own rule and covers later type renames the same way.
    > **Concern:** The sentence must say "replaced" precisely (a rename or successor type named by a removed-type row), or it
    > could be read as permission to key rows on any related type.

  - Q4a file-handle text, §4.7 examples, DECISIONS.md note — **Yes**

    > **Reasoning:** :1076 promises `file.read_line()`, which under rule 3 and H1 is the forbidden form. Leaving it means the spec
    > contradicts the rule on the day we adopt it.
    > **Concern:** None from my seat beyond keeping :1076 free of op names, as min asked.

  - Q4b §4.4.2 prose — **Yes**

    > **Reasoning:** These are the lines the ticket asks us to fix; `listen` is an op too and registers no route.
    > **Concern:** None.

  - Q5a `.await` rewording — **Yes**

    > **Reasoning:** `.await` compiles to a suspension point (yield to the scheduler, then a join), not a call to a method
    > symbol. Calling it a method hides that cost and, at :2999, states the exact pattern H1 forbids.
    > **Concern:** The separate type:spec ticket on which handler answers `.await` must be filed, or rule 3 stays open for `Async`.

  - Q5b `.await` sentence in the rule — **Yes**

    > **Reasoning:** One sentence costs nothing and stops `.await` being cited as a counter-precedent from the rule's own text.
    > **Concern:** None.

  - Q6 route-registration sentence — **Yes**

    > **Reasoning:** Route registration builds data and has no observable effect; making it a handler call would add an indirect
    > call per registration for no gain. The sentence matches what the §4.4.2 mock already does (it reads `server.routes`).
    > **Concern:** The sentence settles the rule-3 reading for `route` that the panel sent to a separate ticket, so that ticket
    > must take it as a given rather than reopen it.

- **Web/Scripting:**

  - Q1 one call form (H1) — **Yes**

    > **Reasoning:** A JS or Python dev can learn this in one sentence: "if a handler can answer it, it starts with the handle name". That sentence is what makes a mock test readable, because every line that the mock answers starts with `net.` or `process.`. The fix-it makes the familiar first guess (`child.wait()`) a one-step error, not a search on Stack Overflow. Sugar would give two spellings, and the meaning of the call would change when some dependency adds a trait method. Users find that bug only by debugging.
    > **Concern:** The first thing every newcomer types is `child.wait()`. If the help line is weak or missing in an edge case (a chained receiver or an alias), the rule feels hostile, so the fix-it must ship with the rule, not after it.

  - Q2 applicability of the fix — **T**

    > **Reasoning:** I change from G. In B2 I argued that a tool must not add the effect to a row, but the spec already does exactly that for the same kind of repair. 04_effects.md:374 (6-0) makes the call rewrite to a handle op plus the row edit both machine-applicable. E0552 (:3467) is also machine-applicable. With T, a user who writes `child.wait()` gets the same one-click fix as a user who writes `read_file(p)`. That is one fix shape for "this call needs an effect", with no gray button that the user cannot explain, and it gives a legal program in one step (§3.1 rules 1 and 3). G would add a third behavior for no gain.
    > **Concern:** In a `pub fn`, the row edit changes a public signature, and every caller's row then needs the effect. That is the existing cascade, but the help must say that the row changed, so that the user sees it in review.

  - Q3 `Child`-keyed rows — **I**

    > **Reasoning:** These are the two released method names that the general fix cannot reach, because the op is named `signal`. Without the rows, old code gets a plain E0505 with no help. They close the hole in this ticket's own rule, so they belong here. The `0` → `SIGKILL` detail keeps the fix from changing the meaning of `kill(0)`.
    > **Concern:** `kill(s)` with a non-literal `s` is a suggestion only, and users will apply it without reading it. The help must say in plain words that `0` meant SIGKILL.

  - Q3b §3.2 replaced-type sentence — **Yes**

    > **Reasoning:** Migrated code holds the replacement type, so a row keyed by the old type never fires. One general sentence stops the next table author from making the same mistake that I made in B1.
    > **Concern:** "Replaced" needs a clear test (renamed, or reached through the replacement op). Otherwise authors will argue about which rows qualify.

  - Q4a file-handle text, §4.7 examples, DECISIONS.md note — **Yes**

    > **Reasoning:** If :1076 still promises `file.read_line()`, users will cite it against the rule on the day that streaming lands. The examples are the first thing that people copy, so they must not show a form that is an error.
    > **Concern:** `fs.read_all(file)` in the §4.7 examples names an op that does not exist yet, and readers may think that it does. The post-v1 mark must stay next to the examples.

  - Q4b §4.4.2 prose — **Yes**

    > **Reasoning:** The prose beside the changed lines tells users that `serve` is the only op and that `listen` registers routes. Neither is true. These are three small edits in the section that the ticket asks us to fix.
    > **Concern:** None of substance. The edits must not change the route-method lines that Q6 leaves for the chore.

  - Q5a `.await` rewording — **Yes**

    > **Reasoning:** :2999 is the exact argument for `child.wait()` that Q1 rejects ("the operation belongs to the handle"). If it stays, the first question users ask is "why `.await` and not `.wait()`?". A postfix keyword with no parentheses is a different thing from a method call, and the spec must say so.
    > **Concern:** If the separate ticket later decides that the `Async` handler answers `.await`, users get one handler-answered dot form, so that ticket must keep it a keyword and not let it become a precedent.

  - Q5b `.await` sentence in the rule — **Yes**

    > **Reasoning:** A reader who meets the rule will test it against `.await` at once. One sentence in the rule text answers that question where the reader asks it.
    > **Concern:** None. It is one line.

  - Q6 route-registration sentence — **Yes**

    > **Reasoning:** After this ticket, the example shows `server.get(...)` beside `net.serve(server)` with no reason given. The sentence gives that reason. It stays true whatever the chore decides about traits or free functions.
    > **Concern:** If the chore turns route registration into free functions, the sentence must be updated in the same change, or it will describe a form that no longer exists.

- **PLT:**

  - Q1 one call form (H1) — **Yes**

    > **Reasoning:** Dot after a value has one judgment (trait lookup) and dot after a handle has one judgment (effect op), so no new resolution rule, no precedence rule and no ambiguity between user effects enter the language. Handler coherence (§4.4 rule 3) holds by construction, because the only path to a handle-made value's consumer op walks the handler chain. Type equality after inference and alias expansion gives the matcher one answer, and a type parameter matching nothing keeps the fix out of generic code where it would be unsound.
    > **Concern:** The matcher must use the receiver's type after inference; an implementation that matches before inference finishes will offer fixes on the wrong op or miss them.

  - Q2 applicability of the fix — **R** *(dissent)*

    > **Reasoning:** Each diagnostic owns one edit: E0505 owns the respelling, and the missing-effect diagnostic owns the row change and its applicability rules. That composes: if the policy for adding an effect to a row ever changes (module budgets, public API rows), it changes in one place, not in every diagnostic that copies the row edit. The rewrite is a step on every path to a legal program, so §3.1 rules 1 and 3 hold, and `blink fix` reaches the same program as T in two passes.
    > **Concern:** R differs in shape from the removed-function rows at 04_effects.md:374, which carry both edits in one fix, so the writer should state why handle-op respelling is not a removed-name row.

  - Q3 `Child`-keyed rows — **I**

    > **Reasoning:** `kill` and `send_signal` are the names a former `std.process` user or a model writes on a `Child`, and the derived fix cannot reach them because the op is `signal`. Without the rows those calls get a bare E0505, which contradicts the help that H1 promises for this exact case.
    > **Concern:** The literal-`0` → `SIGKILL` special case is a semantic mapping, not a respelling; it must stay limited to the literal or the fix changes behavior.

  - Q3b §3.2 replaced-type sentence — **Yes**

    > **Reasoning:** It states the general rule behind Q3 once, so the next replaced type does not need its own panel. A row keyed by a type no program can hold is dead text; keying by the replacement type is the only form that can fire.
    > **Concern:** The sentence must not imply that the replacement type inherits the old methods; it only keys the error rows.

  - Q4a file-handle text, §4.7 examples, DECISIONS.md note — **Yes**

    > **Reasoning:** Under rule 3 a handle that `fs` makes is consumed only by `fs` ops, so the :1076 promise of `file.read_line()` methods is already false. Leaving it means the spec states a rule and then promises its violation, and post-v1 examples are still examples a model learns from.
    > **Concern:** The post-v1 streaming design may later want names other than `fs.read_all`; the example must stay marked post-v1 so it does not lock the name.

  - Q4b §4.4.2 prose — **Yes**

    > **Reasoning:** `listen` is an op too, so "one core operation" is false, and a comment on the wrong declaration misleads a reader about which op builds what. These lines are inside §4.4.2, which the ticket names.
    > **Concern:** None from my seat.

  - Q5a `.await` rewording — **Yes**

    > **Reasoning:** :2999 as written states the exact pattern H1 forbids and gives a "data flow" reason that applies equally to `child.wait()`. Calling `.await` a postfix keyword makes it a separate syntactic form, like `?`, and removes the counter-precedent without changing semantics; the coherence question goes to its own ticket where it belongs.
    > **Concern:** Until the separate ticket decides it, nothing in the spec says which handler answers `.await` under a mock `Async` handler.

  - Q5b `.await` sentence in the rule — **Yes**

    > **Reasoning:** The rule says "`v.op(...)` is trait-method lookup only"; `.await` has the same dot shape, so one sentence closes the obvious misreading at the place a reader checks.
    > **Concern:** None from my seat.

  - Q6 route-registration sentence — **Yes**

    > **Reasoning:** It answers devops's literal reading of rule 3 at the point of use without editing rule 3 itself. A pure method with an empty row needs no handler, and the sentence names the one op that does.
    > **Concern:** The route methods still lack a trait under No Inherent Methods; the sentence must not read as if the spec has settled how they are declared.

- **DevOps/Tooling:**

  - Q1 one call form (H1) — **Yes**

    > **Reasoning:** One spelling gives one target for go-to-definition, find-references and rename, and `rg 'process\.'` still finds every `Process` site for review and audit. The fix is built from the effect declarations by an exact (op name, type) match, so it needs no table and the LSP can compute it with one lookup. The poison/type-parameter clause stops a cascade of wrong fixes after an earlier error.
    > **Concern:** Users from Python, Go and Node will hit E0505 often at first, so the help text must be short and name the handle form in its first line, or it reads as a wall of noise.

  - Q2 applicability of the fix — **T**

    > **Reasoning:** The ballot facts change my B2 view: 04_effects.md:374 already gives the removed-table fix two edits, the call rewrite and the effect addition, both machine-applicable, and E0552 (:3467) makes the row edit machine-applicable too. T makes this diagnostic match those, so `blink fix` in batch reaches a compiling program in one pass, and an agent loop needs one round-trip, not two. R is my second choice; G is last, because it removes the batch fix in the most common case (a new function with no row yet) and leaves the user looking at "no method" in place of the real problem.
    > **Concern:** An auto-added effect changes the function's row and its callers' rows, so `blink fix` output must list each row it changed, or a user ships an API change without seeing it.

  - Q3 `Child`-keyed rows — **I**

    > **Reasoning:** The rows follow directly from this rule, and they sit next to the `process_pid_*` rows already in the §4.4 table. Without them, `child.kill(9)` gets a plain E0505 with no fix, which is the case `blink fix` and upgrades exist for.
    > **Concern:** The `kill(0)` → `SIGKILL` special case is easy to get wrong in the implementation; it needs its own test row.

  - Q3b §3.2 replaced-type sentence — **Yes**

    > **Reasoning:** It turns the `Child` decision into a rule the next type replacement can follow, so nobody keys a row by a type that a migrated program can no longer hold. One sentence, and it removes a question from every later migration.
    > **Concern:** None from tooling.

  - Q4a file-handle text, §4.7 examples, DECISIONS.md note — **Yes**

    > **Reasoning:** Spec examples feed `blink llms`, hover text and training data; a `file.read_all()` example left in place teaches the form this vote forbids. Adding a note to DECISIONS.md:237, without rewriting the old vote, keeps the record honest.
    > **Concern:** None.

  - Q4b §4.4.2 prose — **Yes**

    > **Reasoning:** The edit already touches those lines, and correct examples next to wrong prose leave the reader with two answers. `listen` is in the effect block, so the prose must say so.
    > **Concern:** None.

  - Q5a `.await` rewording — **Yes**

    > **Reasoning:** As written, :2999 is the exact pattern H1 forbids, and spec text that contradicts the rule gets cited against it. `h.await` has no parentheses, so the parser already treats it as its own node; the text should say so. The handler question goes to its own ticket, which is the right scope.
    > **Concern:** `h.await()` must get an error that says `.await` takes no parentheses, not "no method `await`".

  - Q5b `.await` sentence in the rule — **Yes**

    > **Reasoning:** One line in the rule text stops `.await` being raised as a counter-precedent in every later debate, and it costs nothing.
    > **Concern:** None.

  - Q6 route-registration sentence — **Yes**

    > **Reasoning:** The sentence matches the effect declaration (`route` is not in the `Net.Listen` block) and tells the reader, and a mock writer, which call a handler answers. That is what the example needs once `server.serve()` is gone.
    > **Concern:** The separate rule-3 ticket could later read "consumes" more widely, and then this sentence must change with it; that ticket should cite this line.

- **AI/ML:**

  - Q1 one call form (H1) — **Yes**

    > **Reasoning:** One rule, keyed on the token left of the dot: a handle name means an effect op, a value means a trait method. A model can learn that from the spec alone, with no per-op exception list, and all six seats reached it on their own. The E0505 fix-it absorbs the one predictable cost, that models trained on Go/Python write `child.wait()` first, in one round trip.
    > **Concern:** If the help is built so it fires only when the effect is in the row, the most common model error (a helper with no row yet) gets a bare E0505, and the rule looks arbitrary to the model.

  - Q2 applicability of the fix — **T**

    > **Reasoning:** The spec already has a shape for "a call that must become a handle op": 04_effects.md:374 gives two edits, the call rewrite and the row addition, both machine-applicable (6-0). E0552 (:3467) and 01_philosophy.md:82 use the same shape. Q3 adds `kill`/`send_signal` rows to that same :374 table, so under G `child.kill(9)` would get an applicable two-edit fix while `child.wait()` in the same function gets none. One fix shape for "this call needs an effect" is one thing a model learns, and an agent loop reaches a legal program in one step. My second choice is R: its rewrite is always applicable, and the row edit follows on the next diagnostic. G is last: batch `blink fix` leaves the wrong-reason error (`no method wait`) in place and hides the true one. The 03_types.md:2510 case does not apply: there the two edits (`?` vs `.unwrap()`) change meaning, but here the rewrite is the only legal spelling.
    > **Concern:** If G wins, the Q1 help and the :374 table rows give different applicability for the same kind of fix in the same ticket. The writer must then state why, or a model will learn the two as random.

  - Q3 `Child`-keyed rows — **I**

    > **Reasoning:** `kill` and `send_signal` are the released names a model has seen, and the generic help cannot reach them because the op is named `signal`. Three table lines in this ticket close the most likely generation error for this API. Moving them to a chore leaves a window where the predicted mistake has no fix.
    > **Concern:** The `kill(0)` → `SIGKILL` literal case is easy to get wrong in the implementation; it needs its own test.

  - Q3b §3.2 replaced-type sentence — **Yes**

    > **Reasoning:** It turns the Q3 decision into a general rule, so the next type rename does not need a panel to decide the key. Migrated code holds the new type whatever the variable's name, and that is what the lookup sees.
    > **Concern:** None from my seat beyond the writer keeping it to one sentence.

  - Q4a file-handle text, §4.7 examples, DECISIONS.md note — **Yes**

    > **Reasoning:** `file.read_all()` in §4.7 and "methods on a file handle" at :1076 are examples that contradict the rule, and a model copies examples over rules. Fixing them here keeps the spec self-consistent on the day the rule lands.
    > **Concern:** The post-v1 `fs` op names are not fixed; the writer must not invent them in the reword.

  - Q4b §4.4.2 prose — **Yes**

    > **Reasoning:** These are the lines this ticket edits, and :528 teaches the op list wrong (it omits `listen`). Cheap, local, and it removes a wrong fact a model would retrieve.
    > **Concern:** None.

  - Q5a `.await` rewording — **Yes**

    > **Reasoning:** :2999 states as a design principle the exact pattern H1 forbids ("method syntax for consuming results"). A model reading it would generalize to `child.wait()`. The handler question goes to its own type:spec ticket, which keeps this one to spelling.
    > **Concern:** The separate ticket on which handler answers `.await` must actually be filed, or the reword hides an open semantic question.

  - Q5b `.await` sentence in the rule — **Yes**

    > **Reasoning:** `fut.await` is the obvious counterexample a model or reader will raise against "values never take ops". One sentence pre-empts it at the cost of a few tokens.
    > **Concern:** None.

  - Q6 route-registration sentence — **Yes**

    > **Reasoning:** The example shows `server.route(...)` and `net.serve(server)` side by side, and without the sentence a reader cannot tell why one is a method and the other an op. It states a fact the spec already implies (route is not declared in `Net.Listen`) and reopens nothing.
    > **Concern:** The separate chore on the route trait and the `let` mutation shape must land, or the example keeps teaching a mutation pattern the stdlib does not have.

- **Minimalism:**

  - Q1 one call form (H1) — **Yes**

    > **Reasoning:** H1 adds no syntax, no new lookup step and no table. It deletes a second spelling from three places, and it states Q4a's choice once for every op. The handle stays the visible anchor for the effect and for the dispatch point, and the E0505 help is built from the declared ops, so it costs nothing to maintain and covers user effects.
    > **Concern:** The help's matching rule (type equality after inference, ambiguity, poison) is the one place that can grow. Each new special case must have a test, or the help will drift from the rule.

  - Q2 applicability of the fix — **T**

    > **Reasoning:** I change from G. The ballot's facts decide it: 04_effects.md:374 (6-0 vote) already gives the handle-operation rows in the same table two machine-applicable edits, the call rewrite and the row addition, and E0552 (:3467) adds a row entry as a machine-applicable fix too. So the spec has already ruled that adding the effect to the enclosing row is a safe tool edit, and plt's B2 argument against it contradicts that 6-0 vote. The minimal choice reuses the existing shape: one fix shape for every "you meant a handle op" diagnostic, not a second applicability rule beside the table. T also meets §3.1 rules 1 and 3, because the first repair alone makes the program legal.
    > **Concern:** If T loses, G and the :374 rows give two different fix shapes for one kind of mistake. Then the spec needs a sentence that says why, or a later ticket must reconcile them.

  - Q3 `Child`-keyed rows — **I**

    > **Reasoning:** It is two rows next to the help this ticket adds, and `pid.kill(sig)` is released code that will hit `child.kill(sig)` after migration, where the general help cannot reach `signal`. A follow-up chore would leave a gap in the fix-it story this ticket promises.
    > **Concern:** The literal-`0` → `SIGKILL` case is a special branch in a migration row. Its test must exist, or the row ships wrong.

  - Q3b §3.2 replaced-type sentence — **Yes**

    > **Reasoning:** Without it, the `Child` rows break §3.2's own rule ("receiver type", "only names a released Blink accepted"). One sentence makes the rule hold for this case and for the next type replacement.
    > **Concern:** Someone may read it as a licence to key rows on any type that resembles a released one. The sentence must say "replaced", meaning a decision named the successor.

  - Q4a file-handle text, §4.7 examples, DECISIONS.md note — **Yes**

    > **Reasoning:** Each item is text that contradicts the rule, and this ticket's test for scope is "fix what contradicts the rule". The limit holds: no post-v1 `fs` op names in the rule text, and `fs.read_all(file)` appears only in examples that the spec already marks post-v1.
    > **Concern:** `fs.read_all` in an example can still read as a promise. The post-v1 mark must stay next to it.

  - Q4b §4.4.2 prose — **Yes**

    > **Reasoning:** The ticket says fix §4.4.2 to match. Those three lines are false or misplaced next to the ops the rule names.
    > **Concern:** None worth a sentence.

  - Q5a `.await` rewording — **Yes**

    > **Reasoning:** :2999 states, as a design principle, the exact pattern H1 forbids. Fixing it at the source removes the counter-precedent. The handler question is a real rule-3 question and goes to its own ticket.
    > **Concern:** The separate ticket may find that `.await` must route through the handler. Then the "postfix suspension point" text must not have implied that it does not.

  - Q5b `.await` sentence in the rule — **No** *(dissent)*

    > **Reasoning:** Once Q5a fixes :2951/:2999, the spec has no text that calls `.await` a method, so a "this rule does not cover `.await`" line answers a question the spec no longer raises. Two places that say one thing must then stay in step. I do not feel strongly about it; it is a small cost, but a cost.
    > **Concern:** If Q5b passes, the sentence must cite §4.13 and not restate it, or the two texts drift.

  - Q6 route-registration sentence — **No** *(dissent)*

    > **Reasoning:** All seats sent the rule-3 reading of `route` to a separate ticket. This sentence answers that ticket's question ("is not a `Net.Listen` operation") in this ticket's text, before that panel meets. It would also sit beside route examples that the same separate ticket says are broken (no trait, mutation of a `let`). Leave the route lines and their prose to that ticket.
    > **Concern:** If Q6 passes, the separate ticket starts with its answer already in the spec, and a reversal there must remember to delete this sentence.

The Q2 dissent (PLT), in the seat's own words:

> **Reasoning:** Each diagnostic owns one edit: E0505 owns the respelling, and the missing-effect diagnostic owns the row change and its applicability rules. That composes: if the policy for adding an effect to a row ever changes (module budgets, public API rows), it changes in one place, not in every diagnostic that copies the row edit. The rewrite is a step on every path to a legal program, so §3.1 rules 1 and 3 hold, and `blink fix` reaches the same program as T in two passes.
> **Concern:** R differs in shape from the removed-function rows at 04_effects.md:374, which carry both edits in one fix, so the writer should state why handle-op respelling is not a removed-name row.

The Q5b dissent (Minimalism), in the seat's own words:

> **Reasoning:** Once Q5a fixes :2951/:2999, the spec has no text that calls `.await` a method, so a "this rule does not cover `.await`" line answers a question the spec no longer raises. Two places that say one thing must then stay in step. I do not feel strongly about it; it is a small cost, but a cost.
> **Concern:** If Q5b passes, the sentence must cite §4.13 and not restate it, or the two texts drift.

The Q6 dissent (Minimalism), in the seat's own words:

> **Reasoning:** All seats sent the rule-3 reading of `route` to a separate ticket. This sentence answers that ticket's question ("is not a `Net.Listen` operation") in this ticket's text, before that panel meets. It would also sit beside route examples that the same separate ticket says are broken (no trait, mutation of a `let`). Leave the route lines and their prose to that ticket.
> **Concern:** If Q6 passes, the separate ticket starts with its answer already in the spec, and a reversal there must remember to delete this sentence.

The majority answer on Q2: the removed-function rows already give a call rewrite and a row edit, both machine-applicable (04_effects.md:374), and E0552 does the same; one fix shape for "this call needs an effect" is easier to learn than a third. The majority answer on Q6: the sentence matches the effect declaration, and the separate ticket on route registration must cite it and may delete it.

#### Phase D

Not triggered. The closest results were Q2, Q5b and Q6 at 5-1.

### Final Spec

```blink
// A handle op has one call form: the handle, a dot, the op, the value as an argument.
fn run_job(cmd: Str) -> Result[Int, ProcessError] ! Process.Spawn {
    let child = process.spawn(cmd, [])?
    let result = process.wait(child)?     // not child.wait(): E0505
    Ok(result.code)
}

fn stop_job(child: Child) -> Result[(), ProcessError] ! Process.Signal {
    process.signal(child, SIGKILL)
}

fn start_server(config: ServerConfig) ! Net.Listen, IO {
    let server = net.listen(config.host, config.port)
    server.route("GET", "/users/:id", handle_get_user)
    net.serve(server)                     // not server.serve()
}

// post-v1: an fs handle op that takes a file handle
fn load_file() ! FS {
    let data = with fs.open("data.txt")? as file {
        fs.read_all(file)?
    }
}

// .await is a postfix keyword, not a call to a handle op (§4.13)
fn load(h: Handle[User]) -> User ! Async {
    h.await
}
```

Locked points:

- A handle op has one spelling, `handle.op(value, ...)`. A value that a handle op made is an argument, never the receiver. `v.op(...)` is trait-method lookup only and never reaches a handler.
- When lookup fails, E0505 gives the handle form in the first line of its help if a visible effect has an op of that name whose declared first parameter type equals the receiver type after inference and alias expansion. The test is equality, not assignability. A type parameter or the poison type matches no op, and the error is plain E0505. Two or more matching effects: the help lists each, and the fix is not machine-applicable.
- When one op matches, the fix carries two edits: the call rewrite and, when the enclosing row lacks the effect, the addition of the effect to the row. Both are machine-applicable, in the shape of the removed-function rows. The structured output reports the row edit, because a row change on a `pub fn` changes a public signature.
- The §4.4 removed table gets rows keyed by `Child` for `child.kill(sig)` and `child.send_signal(sig)`. A literal `0` argument to `kill` becomes `SIGKILL`; a non-literal `kill` argument gets a suggestion only. There is no row for `child.wait()` and none for `Pid`.
- §3.2 *Removed methods*: when a decision names a successor type for a released type, a row for a method of the old type is keyed by the successor type. The successor type does not get the old methods.
- Post-v1 file streaming arrives as `fs` handle ops that take a file handle; the text names no ops. The §4.7 examples use `fs.read_all(file)` and keep the post-v1 mark. The old Net.Listen server API row in DECISIONS.md gets a note that this vote supersedes the `server.serve()` spelling.
- §4.4.2 has two operations: `listen` makes a `Server`, and `serve` starts it. `server.serve()` is `net.serve(server)` in §4.4.2 and in §7. The route-method lines do not change.
- `.await` is a postfix keyword and a suspension point on a `Handle[T]`, not a method call. The rule text says the rule does not apply to `.await` and cites §4.13. The spec does not say which handler answers `.await`.
- Beside the §4.4.2 example: "Route registration builds the `Server` value and is not a `Net.Listen` operation; `net.serve(server)` is the operation that a handler answers."

### Amendments

None.

### Implementation notes

These are not spec text.

- The E0505 help comes from the declared ops of the visible effects, with no per-name table. It scans only on a failed method lookup. An index by first parameter type keeps the scan fast in an LSP session (sys).
- `lib/std/process.bl` still ships `Pid` with `PidOps` (`wait`, `kill`, `send_signal`). In that code `kill(0)` means `SIGKILL` and the result is `Int`. The `Child` rows land with the change that moves `std.process` to `Child`. The `kill(0)` row needs its own test.
- `lib/std/http_server.bl:78-101` has free functions (`server_route` and the like) that return a new `Server`. The route-method examples in §4.4.2 show a mutation of a `let` binding that these functions do not give.
- The §4.7 copy example writes with `fs.write_all(dst, data)`. The writer chose that name, not the panel, because `fs.write(dst, data)` would overload the v1 `fs.write(path, s)`. It is a post-v1 illustration; the post-v1 file API may rename it.
- `h.await()` should get the error "`.await` takes no parentheses", not "no method `await`" (devops).
- `blink fix` lists every row it changed (devops, web).
- Tests, one for each case (min): the equality match, a type parameter receiver, the poison type, two matching effects, the one-match two-edit fix, `kill(0)`, `kill` with a non-literal argument, and `send_signal`.

### Open cases and follow-ups

- Route registration (`route`, `get`, `post`): No Inherent Methods asks for a trait; the example mutates a `let` binding while the stdlib returns a new `Server`; and rule 3 reads "consumes" for values that pure code can also build. This is a separate spec ticket. It must cite the Q6 sentence. The seats differ on its weight: Systems asks that ticket to take the sentence as a given; Minimalism and DevOps let it revise or delete the sentence.
- Whether the `Async` handler that made a `Handle[T]` answers `.await` (rule 3). The spec text says nothing on it. A separate spec ticket decides it; if `.await` must route through the handler, the "postfix keyword" text must not have said otherwise (min).
- Whether `ch.send` and `ch.recv` on a `channel.new` value fall under rule 3 (friction).
- A removed-type row from `Pid` to `Child` joins the effect-tracked builtins follow-up.
- LSP postfix completion: after `child.`, offer `process.wait(child)` (tooling backlog).
