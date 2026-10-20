[< All Decisions](../DECISIONS.md)

# Keyword Marker Re-audit (`*` replaces `--`) — Design Rationale

A batch of re-audits reopened earlier votes under one rule: "match LLM priors unless the deviation prevents a bug class." This one asked about the `--` separator that marks keyword parameters. The ticket said: "the -- separator for keyword arguments has no equivalent in common languages. LLMs will not write it by default. [...] keep only if it prevents a bug class; else use a familiar form."

Facts before the vote:

- The rule is the audit's rule. It is not text in `sections/01_philosophy.md`. One earlier re-audit used it: [Map Index Assignment Re-audit](map-index-assignment-reaudit.md) (kept E0313, 6-0).
- The original vote on the separator (5-seat panel) was 3-1-1: `--` 3, `;` 1, `*` 1. Labels are call-site sugar and not part of the function type, 5-0. Rationale: [Keyword Arguments and Defaults](keyword-arguments-defaults.md).
- The DECISIONS.md "Rejected" table rejects optional keyword args (caller's choice), mixed positional and keyword at one call site (`foo(1, y: 2)`), and function parameter defaults. Yet §2.13 and §2.21 allow defaults on params after `--` (E0531 PositionalParamDefault, E0532/E1104 non-const default), and the §2.13 examples mix positional and keyword in one call (`transfer(300, from: alice, to: bob)`). Defaults hang off the `--` boundary.
- §2.13 puts the choice at the declaration. The caller has no choice. `blink check` rejects a label on a positional param and a keyword param given without a label. Five codes: MissingKeywordArg E0510, UnlabeledKeywordArg E0529, InvalidKeywordArg E0511, PositionalAfterKeyword E0527, DuplicateKeywordArg E0528. The "3-8% per call site" swap rate in "Why `--`" and "The Problem This Solves" has no citation.
- §3.3: labels are invisible to the type; `fn(Int, Account, Account)`. §2.22: keyword args evaluate in written order, then bind.
- Verified on gen1: `fn transfer(amount: Int, -- from: Int, to: Int)` then `transfer(300, 1, 2)` gives `error[UnlabeledKeywordArg]`, with a help line that says to label the argument already written.
- Usage: lib/std declares zero keyword params. src/ declares zero. examples/ has 3 declarations. tests/ has about 104 lines and sections/ about 18. Spec §7 gives `recv_bytes` and `send_bytes` a trailing keyword `flags` that lib/std/libc.bl does not have yet (spec leads compiler).
- Open tickets ride on this design: trait vs impl conformance for keyword params and defaults through a bound; a keyword default on a param typed by a bare type parameter; variant paren payload labels; variant constructor arity.

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated
in independent-proposal → debate → vote rounds. Quoted text is each panelist's own, verbatim. `…` or `[…]` marks a cut. Moderator text is plain and short. Ticket IDs inside quotes are the panelists' own.

The options were STAR (`*` as a list item, all §2.13 rules unchanged) and KEEP (`--` as is). Round 1 left two questions split, Q3 (migration) and Q9 (the rest of the diagnostics). Phase D re-voted only those two.

#### Phase A — Independent proposals

All six seats proposed STAR first and listed KEEP as the fallback. Excerpts:

- **Systems:**

> The `*` sits in the list as its own element, with a comma on each side, as in Python's `def f(a, *, b)`. All the other rules stay as they are: the declaration site decides, labels are required after the marker and forbidden before it, the five codes E0510/E0511/E0527/E0528/E0529 keep their meaning, defaults are const-only, and labels are erased from the type.
>
> **What prevents the bug class.** The thing that prevents the swap bug is the **required label**, not the `--` token. `transfer(300, bob, alice)` fails with E0529 because `from` and `to` take labels, and any marker gives you that. I found nothing that `--` prevents and `*` does not:
>
> - `*` has no prefix meaning in Blink. There is no unary deref: `Ptr` uses `.deref()` (§7). There are no variadics, so `*args` cannot be misread.
>
> - The old argument that `*` is "too subtle" is about how people read code. It is not a bug class. A missing marker shows up loudly anyway: every call site that tries to use labels fails with E0511.
>
> - An LLM writes `*,` from its Python priors with no prompting. It will not write `--`. When it guesses the marker wrong, the build breaks and nothing happens silently. So the gain is fewer wasted round trips, and safety stays the same.
>
> The swap guard holds only at direct calls. `let g = transfer` followed by `g(300, bob, alice)` type-checks, because labels are erased. That is the price of the 5-0 "labels are sugar" ruling, and I still back it: putting labels in the type would split fn types and make mono and HOF codegen harder. The spec should say the guard covers named calls and not fn values, and then drop the uncited "3-8%" figure or cite a source.
>
> The current form prevents the same-typed argument swap at direct calls. S1 keeps that in full, because the required labels do the work and the token does not. S1 gives up nothing except the "visually loud" look, which is a style point and not a bug class. Runtime, ABI, and codegen stay the same.

- **Web/Scripting:**

> The safety is in the rule: the author makes params keyword-only and the checker enforces it. The `--` token adds no safety. It is the one part with no prior in any common language. So I recommend this:
>
> - **Replace `--` with `*`**, Python's keyword-only marker, with the same meaning.
>
> - **Python devs know it in 5 seconds, not 5 minutes.** `def f(a, *, b)` is PEP 3102. It means the same thing as our rule: what follows is keyword-only, and an unlabeled argument is an error. This is not a near match. The semantics are the same.
>
> - **LLM priors:** Python is the biggest prior there is. A model that has seen `*,` in Python signatures knows what comes after it.
>
> - **The 2024 objection was "too subtle".** The thing that keeps you safe is not how loud the token is. The checker is.
>
> **Bug class (ticket principle):** the bug class is swapped same-typed arguments (`transfer(300, bob, alice)` compiles and is wrong). W1 keeps this prevention in full, because it comes from required labels, not from the spelling of the marker. W1 loses nothing.
>
> Also strike the uncited "3-8% per call site" figure in §2.13 and decisions/keyword-arguments-defaults.md. Say instead that a same-typed swap type-checks and is silent. That is true and needs no number.

- **PLT:**

> **My reading.** The bug that §2.13 prevents is real: a swap of two same-typed arguments that still type-checks, as in `transfer(300, bob, alice)`. But the `--` token does not prevent it. Two rules prevent it, and `blink check` enforces both: the author decides which params are keyword (declaration-site control), and every keyword argument must carry its label. Any marker that triggers the same rules prevents the same bug. So the principle says: keep the rules, and use a familiar token. One familiar token has exactly these semantics.
>
> - `*` stands alone as a list element, with a comma after it, as in Python. It can appear at most once.
>
> - Everything else stays the same: the five codes E0510/E0511/E0527/E0528/E0529, written-order evaluation (§2.22), labels erased from the type (§3.3), and defaults only after the marker (E0531).
>
> **Bug class.** The swap bug stays prevented: the checker enforces labels, and the token has no part in that. Nothing is lost. The real risk under `--` is a different one: an LLM that does not know `--` writes no marker, so every param silently becomes positional and the protection is gone without a sign. `*` makes it more likely that the model writes the marker at all.
>
> **Lexer note (I checked this).** `src/lexer.bl:734` turns `--` into one token everywhere. So today `let y = --x` and `3--1` give `UnexpectedToken` (I confirmed this with `build/blink check`). Keep lexing `--` as a token, but give it one targeted diagnostic: "Blink has no decrement and no `--` separator. Use `x -= 1`, `- -x`, or `*,` in a param list", with a machine-applicable fix in the param-list case. That gives a C or old-Blink prior a clear repair.
>
> Rule: an impl method must repeat the trait method's positional/keyword boundary and the same keyword names. Order after the marker may differ, because binding is by name. A mismatch is an error. This is a check on the declaration, not on the type, so `fn(Int, Int) -> Int` stays label-free.
>
> Typing rule: a function with keyword defaults has its full type, here `fn(Str, Port, Bool)`. A direct call `start_server(port: 3000)` expands to a full call. The written arguments evaluate first, in written order. Then the const defaults fill the gaps. Then all values bind. As a value, `start_server` takes all three arguments. This composes: no partial-application or subtyping question comes up, which was the reason for the original rejection. The rule also answers the bare-`T` defaults question: a default must type-check against the declared param type in the declaration's own generic context, so `x: T = 0` with a bare `T` is an error.
>
> A lint for a signature with three or more params, of which two or more share a type and are next to each other, with no keyword marker. It would suggest adding `*,`. This turns "the author forgot the marker" from a silent loss into a visible one. It needs its own ticket.

- **DevOps:**

> - The lexer always reads `--` as one `DashDash` token (src/lexer.bl:734). So `let a = 5--1` gives `error[UnexpectedToken]: unexpected token --`. The token exists only for this separator.
>
> - `fn f(a: Int, *, b: Int)` (the Python form) gives `expected IDENT, got *` plus a false `UnusedVariable` warning for "variable `*`". This is a bad first contact for the most-trained form.
>
> - `f(1, b = 2)` (Python call form) gives four errors: two `UnexpectedToken`, an `UndefinedVariable` and an `UnlabeledKeywordArg`. None says "use `:`".
>
> - `fn h(--` followed by a newline breaks the parse and cascades. The formatter never emits this layout, but people and LLMs will write it.
>
> - E0529 has a grammar bug: "`b` of `f` are keyword parameters".
>
> - **The important one:** §2.13 and `blink explain E0529` call E0529 "machine-applicable ... a tool can apply unaided". If a tool applies it, `transfer(300, bob, alice)` becomes `transfer(300, from: bob, to: alice)`. That is the swap the feature exists to stop, now hidden behind labels that look deliberate. Today `blink fix` does not apply it (help only, no span: "0 fix(es) applied"), so the code is safe and the spec text is wrong.
>
> The bug class (a swap of same-typed arguments) is prevented by **required labels at the call site**: the author picks keyword params and the checker refuses an unlabelled value. The token that marks the boundary prevents nothing. `--`, `*` and `;` all give the same enforcement and the same five diagnostics. So under the ticket principle, keep the semantics and choose the token only on priors and tooling cost.
>
> 1. **E0529 must never be machine-applicable.** Strike that claim from §2.13 and the E0529 explain text. Its fix assigns labels by position, and the position is exactly what is in doubt. Keep it as help only, and name both candidate orders ("label each argument; check which value is `from`"), not just `from: ...`. Rust's term for this is `MaybeIncorrect`.
>
> 2. `name = value` at a call site: one error, "keyword arguments use `:`", with a machine-applicable fix. This one is safe because the author already wrote the label. Suppress the cascade.
>
> 3. Allow a newline after the marker in a param list, the same as after a comma.
>
> 4. Fix the singular/plural grammar in E0529.

- **AI/ML:**

> The bug class is real: a swap of same-typed arguments that still typechecks (`transfer(300, bob, alice)`). Each call site is written once, and a wrong guess from the model compiles and fails silently. What prevents it is the **semantics**: declaration-site control, required labels, and the checker enforcing both (E0529, with a fix a machine can apply).
>
> The **token** `--` prevents no bug. It only marks where the keyword params start. Any visible marker with one meaning gives the same guarantee. So under the ticket's rule, the semantics stay and the token must justify itself on its own. I find no reason for it, and two costs.
>
> - **Declarations (the ticket's problem):** a model that wants keyword-only params reaches for Python's `*`. PEP 3102 has exactly Blink's semantics: params after `*` are keyword-only, labels are required, defaults are allowed. That is a very large mass of training data for the same idea. I checked today's compiler: `fn transfer(amount: Int, *, from: Int, to: Int)` gives `expected IDENT, got *`, then `variable `*` is never read`, then InvalidKeywordArg at every call. That is three wrong signals for one natural guess.
>
> - **`--` collides with priors.** It is the comment marker in SQL, Lua, Haskell and Elm, so a model with those priors can read `fn f(a: Int, -- from: Account)` as a comment and copy or drop the params wrongly. It is decrement in C, JS and Java. And the lexer always makes `--` one token, so `let y = x--1` fails today with `unexpected token --`, where every C-family reader expects `x - (-1)`. This hazard exists only because of the chosen token.
>
> - No change to the five codes (E0510/E0511/E0527/E0528/E0529), the defaults rules (E0531, E0532/E1104), §2.22 order, or labels as call-site sugar (§3.3). Only the token in §2.13 changes.
>
> Caller-optional labels (Kotlin/Swift style). It matches priors, but it brings back a style choice at every call site and lets the swap bug return. The rule permits a deviation that prevents a bug class, and this one does.

- **Minimalism:**

> The bug class (two args of the same type passed in swapped order, e.g. `transfer(300, bob, alice)`) is stopped entirely by (1). The `--` token adds nothing to that protection. Any token in the same place with the same rules gives the same checks: E0510, E0511, E0527, E0528 and E0529. So under the ticket's own rule, `--` does not earn its deviation. It is an unfamiliar spelling of a familiar idea.
>
> I checked the lexer and parser. `DashDash` is a token used in exactly one place: `parse_fn_def`, src/parser.bl:3561 and 3575 (and the copy at 3834/3848). It has no other job in the grammar.
>
> - `*` stands as its own list element, followed by a comma, as in Python.
>
> - Every rule, code and fix-it stays as it is. Only the token changes.
>
> **The one difference from Python, which Blink already handles.** In Python, params before `*` can also be passed by label. In Blink they are positional-only. If someone writes `transfer(amount: 300, ...)`, E0511 already rejects it with "pass it without a label". No new rule is needed.
>
> **Bug class under M1:** kept, fully. Nothing is lost, because the token never carried the protection.
>
> **Flag for a separate ticket:** §2.13 all-keyword functions and the §2.15 struct shorthand are two ways to write the same "config call" (`start_server(port: 3000)` vs `start_server({ port: 3000 })`). That is a Principle 2 overlap. It deserves its own triage ticket, not a decision here.

#### Phase B — Debate highlights

The moderator deduped the six proposals into nine questions (Q1–Q9) and asked each seat for a position. All six replied "stable, ready to vote". These position shifts happened. Each is quoted from the seat's own text.

**Systems and DevOps moved Q4 (the `--` token) from DELETE to KEEP-TOKEN.** In Phase A both had proposed to delete `DashDash` so that `5--1` lexes as `5 - -1`.

- **Systems:**

> **Q4, `--` token: I change my vote to plt and disagree with devops (and with my own S1 side benefit).** Delete `DashDash` and `--x` lexes as `-(-x)`, which is `x`. A model with a C/JS/Java prior writes `let y = --x` to mean pre-decrement and gets `x`, with no error. That is a silent wrong value, the same kind of bug this feature exists to stop. `5--1` failing today is a small cost. Turning `--x` into a no-op is not small. So keep `--` as one token and give it the single targeted diagnostic plt wrote: no decrement, no `--` separator, use `x -= 1`, `- -x`, or `*,`. Make the fix machine-applicable only in the param-list case. This goes in this ruling, not a chore (min). Whether `--x` is legal is a lexical rule users see.

- **DevOps:**

> **Q4 lexer: I change my vote to plt's position. Keep `DashDash` and give it a targeted diagnostic.** In Phase A I said to delete the token. That was wrong, for a reason I missed. If `--` lexes as two minus signs, a C/JS writer's `--x` (meant as a decrement) parses as `- -x`, which is `x`. That is a silent no-op, a new bug class that comes only from deleting the token. A kept token turns it into a loud error: "Blink has no decrement; write `x -= 1`" (`- -x` / `5 - -1` for a double negative), plus the param-list fix from Q3. sys: the `5--1` wart then stays an error, but it gets a precise help line. That is the right trade.

**Web, AI/ML and Minimalism withdrew the claim that E0529's fix is machine-applicable.** DevOps had shown that a tool which labels by position writes the swap in.

- **DevOps (the point they accepted):**

> **Q5 E0529 must not be machine-applicable: in this ruling.** I disagree with web ("E0529 with a fix the machine can apply"), aiml ("with a fix a machine can apply") and min ("E0529 fixes it for you"). E0529 fires on `transfer(300, bob, alice)`. The only fix a machine can write labels by position: `from: bob, to: alice`. That turns a swap the checker caught into a swap with labels that say "I meant this", which a reviewer reads as intent. The more an agent loop trusts `blink fix`, the worse this gets. So the spec must say:
> - E0529 is help-only (no span edit). This matches the compiler today: `blink fix` applied 0 fixes.
> - The help names the parameters and asks the author to choose: "label each argument with the parameter it is for: `from:`, `to:`".
> - Strike "machine-applicable ... a tool can apply unaided" from §2.13 and from the E0529 explain text.

- **Web/Scripting:**

> **Q5 (E0529 fix): devops is right, and I retract my claim.** In my Phase A text I counted E0529 as "a fix the machine can apply" in favour of W1. That was wrong. Labels assigned by position write the swap in under labels that look deliberate. That is worse than the unlabelled bug, because a reviewer now trusts it. E0529 must stay help-only and name the need to check which value is which. Put it in this ruling, because §2.13 states the opposite today. aiml and min should drop the same claim. W1 does not depend on it: the main win is that the call fails, not that it auto-repairs.

- **AI/ML:**

> **Q5 — E0529 machine-applicable: devops is right, and I withdraw my claim.** I cited E0529's fix as a point in favour. That was wrong. Labelling by position writes the swap in, behind labels that look deliberate. For models this is worse than no fix: an agent loop that auto-applies fixes would launder the exact bug. Put it in this ruling: strike the claim from §2.13 and from the E0529 explain text, and keep the fix as help only, naming both orders. web and min cited the same claim. I ask them to drop it as well.

- **Minimalism:**

> **Q5 E0529: I concede to devops. Strike "machine-applicable" from §2.13 and the E0529 explain text.**
> - I cited it in my Phase A as a point in favour, and that was wrong.
> - Labelling by position turns `transfer(300, bob, alice)` into `transfer(300, from: bob, to: alice)`. That is the swap, now hidden behind labels that look deliberate.
> - A repair that writes in the bug the feature exists to stop must never be applied by a tool. Keep it as help that names both orders.
> - This is the one sub-ruling that protects the bug class under any token. It belongs in this ruling.

**Systems moved Q3 (migration) to HARD in round 1. PLT moved to DEPRECATE.** Systems had proposed the 3-step path in Phase A and PLT had proposed no deprecation period.

- **Systems:**

> **Q3, migration: I change my vote to min/plt.** No deprecation period. `--` in a param list becomes an error with a machine-applicable fix to `*,`. My reason for the change: src/ and lib/std declare no keyword params, and the corpus compiles under gen1, not under the pinned gen0. So nothing forces a release with both forms. An "accept both" commit can exist in the landing order, but that is how we implement it. It is not a spec state. The fix `--` → `*,` is purely syntactic, so it is safe to apply by machine.

- **PLT:**

> **Q3 (migration): 3-step, accepted.** My no-deprecation plan was fine for this repo. But code outside the repo, and LLM drafts, will still carry `--` for a while. A warning with a syntactic fix (`--` → `*,`) costs little. I move to the majority.

**AI/ML moved Q4b (where the lexical rule is recorded) from CHORE to IN-RULING.** In Phase B AI/ML held that it was a chore:

- **AI/ML (Phase B):**

> **Q4 — lexer: keep `DashDash` with plt's targeted diagnostic.** This reverses the lean in my Phase A. Priors for `5--1` are mixed. C and JS reject it, because maximal munch makes it decrement. Python reads it as `5 - -1`. The common LLM error is `x--` or `--x` as decrement. Delete the token and `x--` turns into a confusing `x - -<missing>` parse error. Keep it and one message says "Blink has no decrement; use `x -= 1`". That repairs the error better. I see this as a diagnostic detail, not spec text, so it is a chore under this ruling.

- **AI/ML (Phase C):**

> ## Q4b — IN-RULING
> **Reasoning:** I move from CHORE. A model that learns from the spec alone must be able to read "`--` is reserved; `a--b` is an error, write `a - -b`" in the spec. Otherwise the rule exists only in the compiler. The diagnostic wording can stay a chore, but the lexical rule is user-visible.
> **Concern:** the spec may end up stating the diagnostic message text, which belongs to the implementation, so keep the rule normative and the wording out.

**Web moved Q7 (defaults typing) to ONE-LINE.** In Phase B web held that all of it belongs to the bare type parameter default ticket.

- **Web/Scripting (Phase B):**

> **Q7 (default typing): separate (the bare-`T` defaults question).** The rule plt states seems correct to me. Vote it there.

- **Web/Scripting (Phase C):**

> ## Q7 — defaults typing
> **Vote:** ONE-LINE
> **Reasoning:** I change from SEPARATE. A single sentence ("the fn type has full arity; a direct call fills the const defaults after the written args evaluate") answers "what is `start_server`'s type?" before anyone asks it. The hard part, the bare-`T` default, still goes to the bare-`T` defaults question.
> **Concern:** The sentence may look like it settles the bare-`T` defaults question, so it must point to that open case.

#### Phase C — Final vote (round 1)

Each entry gives the seat's vote, reasoning and concern. `*(dissent)*` marks a vote against the round 1 result.

- **Q1: Separator token** (STAR 6-0)
  - **Systems:** STAR — Labels are erased before mono, so every marker lowers to the same positional C call: zero runtime cost, no ABI change. The required labels stop the swap bug, not the token. The token only has to match priors, and Python's `*,` has the exact meaning. / Concern: In a long one-line signature a reader can miss `*`. The formatter should put the marker on its own line once a signature wraps.
  - **Web/Scripting:** STAR — Python's bare `*` has the same meaning, so a Python dev or an LLM reads the signature right on first sight. `--` has wrong priors: it is a comment in SQL and Lua, decrement in C and JS, and end-of-options in shells. The required labels prevent the swap bug, not the token, so the change loses no safety. / Concern: Python devs may expect params before `*` to take labels too, as Python allows, so E0511's "pass it without a label" help must be clear.
  - **PLT:** STAR — The swap guard comes from two rules: the declaration decides which params are keyword, and the checker rejects a keyword argument without its label. The token plays no part in that, so changing the token keeps every typing rule and every diagnostic. Python's PEP 3102 `*` has the same meaning, so this is a prior with zero semantic gap. / Concern: Python writers may expect params before `*` to accept labels. E0511 rejects that, but the first draft will hit it.
  - **DevOps:** STAR — The required labels stop the swap, and the token does not. `*` is the form a Python-trained model writes first, and today that guess produces three wrong diagnostics. With `*`, the first draft is right more often and every check stays the same. / Concern: Python users may write `*args` and expect varargs, so the `*args` diagnostic (Q9) must ship with the token change.
  - **AI/ML:** STAR — Python's `*` has the same meaning as Blink's marker, and it is the most-trained keyword-only marker there is. A model writes it with no prompting. `--` carries wrong priors: it starts a comment in SQL, Lua and Haskell, and it is decrement in C and JS. The required labels prevent the bug class, and they stay the same. / Concern: a model with Python priors may also write `*args` or label a positional param, so the targeted diagnostics in Q9 must ship with the token change.
  - **Minimalism:** STAR — The required label stops the swap, and the token stops nothing. `*` reuses a token we already have and matches Python's exact meaning, so we lose one foreign construct and gain nothing new to learn. / Concern: Python users may expect params before `*` to take labels too; E0511's help must say "pass it without a label" clearly.

- **Q2: DECISIONS.md Rejected rows** (REWRITE 6-0)
  - **Systems:** REWRITE — The rows reject what the spec ships and the compiler enforces. A spec that contradicts itself teaches the wrong rule to people and to models. The HOF worry in the old row no longer applies: the fn type is full-arity and has no labels. / Concern: If "Caller-chosen labels" is worded loosely, it can read as banning `transfer(300, from: a, to: b)`. The row text must say mixing is allowed exactly as the declaration fixes it.
  - **Web/Scripting:** REWRITE — A Rejected table that lists what §2.13 ships teaches two opposite rules, and a reader trusts neither. The new wording names what was really rejected: caller-chosen labels and positional defaults. / Concern: The "mixing only as the declaration fixes it" wording may still read as "mixing is rejected" to a fast reader, so keep a `transfer(300, from: a, to: b)` example next to the row.
  - **PLT:** REWRITE — A spec that rejects what it ships is not consistent, and a learner cannot tell which text governs. The real rejections are about the caller's choice and about defaults on positional params, and the new wording says exactly that. / Concern: The rewrite must also touch decisions/keyword-arguments-defaults.md ("Reject Function Parameter Defaults"). If it does not, that file still contradicts the spec.
  - **DevOps:** REWRITE (with "*caller-chosen* mixing") — `blink llms` and readers see DECISIONS.md and §2.13 side by side. Today one says "rejected" next to a feature the other ships, and models learn opposite rules from the two. / Concern: Someone may reword the rows loosely enough that they again disagree with E0531/E0527. The text must name the codes.
  - **AI/ML:** REWRITE — today a spec-only learner reads two opposite rules, Rejected rows on one side and §2.13 on the other. For learnability that is worse than any token choice. The rewritten rows state what was really rejected: labels the caller chooses, and defaults on positional params. / Concern: the new wording can drift from §2.13 again unless the two rows link to §2.13 and do not restate its rules.
  - **Minimalism:** REWRITE — Spec and DECISIONS.md must not teach opposite rules. A Rejected row should name only what was rejected: caller-chosen labels, and defaults on positional params. / Concern: The rewrite must also fix decisions/keyword-arguments-defaults.md ("Reject Function Parameter Defaults"), not only the table, or the contradiction lives on.

- **Q3: Migration** (HARD 4, DEPRECATE 2: split, taken to Phase D)
  - **Systems:** HARD — Neither src/ nor lib/std declares a keyword param, and the corpus builds under gen1. So no bootstrap state needs a release that accepts both forms. The `--` → `*,` edit is purely syntactic and safe for a machine to apply. / Concern: Code outside this repo that uses `--` breaks at once. The machine fix must work through `blink fix`, not only print as help.
  - **Web/Scripting:** DEPRECATE *(dissent)* — Old snippets will live in user repos and LLM data after the change. A warning with a mechanical fix keeps that code building and gives one `blink fix` repair. It costs one release of parser code. / Concern: If HARD wins, the error must still carry the machine fix, or users with old code hit a wall with no one-step way out.
  - **PLT:** DEPRECATE *(dissent)* — Code outside this repo and LLM drafts will carry `--` for a while. One warning release with a syntactic fix costs little and never changes meaning. / Concern: The warning release must have a fixed end. If it does not, two spellings live on, which breaks Principle 2.
  - **DevOps:** HARD — No src/ or lib/std code uses the feature, and we are pre-1.0. An error that carries a span edit gives `blink fix` a one-command migration, the same as a warning would, with one release less of two spellings in the wild. / Concern: If the error ships without a span edit (help only), users lose the mechanical path. The fix must be machine-applicable, and a test must prove it.
  - **AI/ML:** HARD — src/ and lib/std declare no keyword params, so a warning window protects no self-host step. For a model, one release where both forms are accepted is one release of training data with two ways to write it. The machine fix to `*,` is a pure syntax rename, so it is safe to apply unaided. / Concern: examples or tests that the migration pass misses will break at once instead of warning first, so the pass must sweep sections/ and examples/ as well as tests/.
  - **Minimalism:** HARD — src/ and lib/std declare no keyword params, so a deprecation stage protects nothing and adds a diagnostic we must later delete. One change migrates tests, examples and sections, and `--` in a param list becomes an error with a fix to `*,`. / Concern: Old Blink snippets in model training data will hit the error; the fix must stay as long as the `--` token stays.

- **Q4a: The `--` token in the lexer** (KEEP-TOKEN 6-0)
  - **Systems:** KEEP-TOKEN — If we delete `DashDash`, `--x` lexes as `-(-x)` = `x`. A C/JS prior that writes `let y = --x` then gets a wrong value with no error. A reserved token that errors with help costs nothing at run time and closes that hole. / Concern: `5--1` stays an error, which annoys people who write it on purpose. The help must name `5 - -1` exactly.
  - **Web/Scripting:** KEEP-TOKEN — The real JS and C mistake is `i--` in a loop. With the token kept, that mistake can get "no decrement; write `i -= 1`" in place of a generic parse error. The same token lets old `-- from:` signatures get the fix to `*,`. / Concern: A Python dev who writes `a--b` and means `a - (-b)` gets an error where Python gives a value, so the help text must show `a - -b`.
  - **PLT:** KEEP-TOKEN — If we delete `DashDash`, `let y = --x` type-checks as `-(-x)` = `x`, but a C-family writer means `x - 1`. That is a silent wrong value, the bug class the audit rule exists to prevent. If `--` stays reserved, the error happens at parse time, with help. / Concern: `a--b` stays a parse error that some readers find fussy. The help line must make the repair (`a - -b`) obvious.
  - **DevOps:** KEEP-TOKEN — If we delete `DashDash`, a C/JS writer's `--x;` lexes as `-(-x)`, a silent no-op. Keeping the token turns that into a loud error with a precise help line. The `5--1` wart stays an error, but it gets a help line that says "write `5 - -1`". / Concern: The help for prefix and infix `--` must stay help-only. A machine fix cannot know whether `--x` meant a decrement or a double negation.
  - **AI/ML:** KEEP-TOKEN — a common LLM error is `x--` or `--x` meant as decrement. A reserved token gives one exact message ("no decrement; write `x -= 1`"). Without it, the parse error is confusing. The priors for `5--1` are mixed anyway: C and JS reject it. / Concern: a reserved token that does nothing can look odd to a reader of the spec, so the spec must say in one line why it is reserved.
  - **Minimalism:** KEEP-TOKEN — Delete the token, and `let y = --x` compiles silently as `-(-x)` where every C-family prior expects a decrement. A silent wrong value is worse than a rare `5 - -1` that must be spelled out. Help text on the existing error, no new code. / Concern: A reserved token that means nothing is a small permanent cost; the spec must say why it stays so a later cleanup does not delete it.

- **Q4b: Where the lexical rule is recorded** (IN-RULING 6-0)
  - **Systems:** IN-RULING — Whether `--x` and `a--b` are legal is a lexical rule that every user sees. It belongs in the spec, not only in a diagnostic. The exact message wording can stay a chore. / Concern: The spec could over-specify message text. State the rule (reserved token, rejected outside the param-list fix) and leave the wording to the diagnostic.
  - **Web/Scripting:** IN-RULING — Users see the lexical rule ("`--` is reserved and never means decrement"), so it is language behaviour, not an internal detail. The spec must say what a user who types `i--` gets. / Concern: The spec text may grow into a diagnostic catalogue. Keep it to the rule plus one example.
  - **PLT:** IN-RULING — Which character sequences form tokens is lexical grammar, and users see it. It belongs in spec text, not in a chore. / Concern: The spec must state the rule in terms of what the lexer rejects. It must not describe the lexer's code.
  - **DevOps:** IN-RULING — "`--` is a reserved token with no meaning" is a lexical rule users meet. The LSP, the formatter and other tools need it in the spec, not only in the compiler. The diagnostic wording can stay a chore. / Concern: The spec could start to name diagnostic wording. Keep it to the rule and say that a targeted message is required.
  - **AI/ML:** IN-RULING — I move from CHORE. A model that learns from the spec alone must be able to read "`--` is reserved; `a--b` is an error, write `a - -b`" in the spec. Otherwise the rule exists only in the compiler. The diagnostic wording can stay a chore, but the lexical rule is user-visible. / Concern: the spec may end up stating the diagnostic message text, which belongs to the implementation, so keep the rule normative and the wording out.
  - **Minimalism:** IN-RULING — Whether `--x` and `a--b` are valid is user-visible syntax, so it belongs in the spec text. One sentence: `--` is a reserved token with no meaning. / Concern: None worth noting, if the sentence stays one sentence.

- **Q5: E0529 fix applicability** (HELP-ONLY 6-0)
  - **Systems:** HELP-ONLY — Labels assigned by position write in the very swap the feature exists to stop, and make it look deliberate. Today `blink fix` does not apply E0529's help as a fix, so the spec text is the only thing wrong. Fix the text. / Concern: A future tooling change could promote the help to a fix by mistake. The E0529 explain text should say why it is help-only.
  - **Web/Scripting:** HELP-ONLY — If a tool adds labels by position, it writes the swap in under labels that look deliberate, and reviewers then trust it. That is worse than the bug the feature prevents. I retracted my Phase A claim on this point. / Concern: An IDE or LSP plugin may still offer a one-click "add labels" quick fix unless the help text and the fix metadata both mark it as unsafe.
  - **PLT:** HELP-ONLY — The E0529 repair assigns labels by position, and position is exactly the unknown. A fix that a tool applies alone would write the swap in and make it look deliberate. Rust's applicability term for this case is `MaybeIncorrect`. / Concern: Someone may later add a "fix all" mode that applies help-only repairs too. The spec text should forbid that for E0529.
  - **DevOps:** HELP-ONLY — E0529's only mechanical fix labels by position. That writes the swap the checker just caught, with labels that look deliberate. Agent loops and `blink fix --all` trust machine fixes, so this one claim could bring the bug class back. The compiler already treats it as help only, so only the text must change. / Concern: A later contributor may "improve" E0529 by adding a span edit. The E0529 explain text should say why it has none.
  - **AI/ML:** HELP-ONLY — if an agent loop applies E0529's fix unaided, it writes the swap in behind labels that look deliberate. That launders the exact bug class the feature exists to stop. The help must name the params and leave the order to the author. / Concern: tools that apply every fix they see could still apply the help text, so the explain text must say plainly that the order is in doubt.
  - **Minimalism:** HELP-ONLY — A tool that labels by position writes in the swap the feature exists to stop, and hides it behind labels that look deliberate. This protects the bug class under any token. / Concern: Help text that names the params in declaration order still steers toward the positional guess; it should name the params, not pre-fill an order.

- **Q6: Trait/impl keyword conformance** (SEPARATE 5, IN-RULING 1)
  - **Systems:** SEPARATE — The rule is right. Through a bound, the trait's label order binds the values and the impl reads them in its own order, so the generated code really swaps them at run time. But that widens a token re-audit into conformance semantics, and the conformance ruling is the right place to rule on it. / Concern: the conformance ruling can sit idle while the hole stays open. 8b's trait-bound clause keeps the spec honest until it lands.
  - **Web/Scripting:** SEPARATE — The hole is real, but it has the same shape under either token and needs its own scope: defaults through a bound and generic impls. This ruling should stay about the token and the text that rides on it. / Concern: the conformance ruling could stall and leave the trait-bound swap open, so Q8b must name the gap until it lands.
  - **PLT:** SEPARATE — Conformance between a trait and its impl is its own typing question (the conformance ruling), with its own cases: default methods, generic impls, and order after the marker. Put it to its own vote. This ruling only needs to name the gap honestly (Q8b). / Concern: the conformance ruling could stall, and then the trait-bound swap stays open. Q8b's clause is the guard against people forgetting that.
  - **DevOps:** IN-RULING *(dissent)* — This is the same swap bug, through a trait bound, and the same principle applies. Leaving it open means §2.13 claims a guarantee that a generic call breaks today. I accept SEPARATE if the Q8b text names the gap. / Concern: If SEPARATE wins and the conformance ruling stalls, the gap stays live with only a sentence of spec text as its guard.
  - **AI/ML:** SEPARATE — the hole through a trait bound is real, but it has its own probe and its own repair. It deserves its own scrutiny under the conformance ruling. Bundled into a token vote, it gets less. / Concern: the conformance ruling may sit unfixed while the spec claims the swap guard holds, which is why I vote the trait-bound clause in on Q8b.
  - **Minimalism:** SEPARATE — The hole is real, but the conformance ruling owns it with its own scope. Folding it in turns a token ticket into a semantics ticket and puts both at risk. / Concern: the conformance ruling could sit for months while the swap goes through a trait bound; it should be queued next.

- **Q7: Defaults typing** (ONE-LINE 6-0)
  - **Systems:** ONE-LINE — "Full-arity type; a direct call fills const defaults after the written args evaluate" is what the lowering does now. Saying it here answers the stale row's HOF worry. The bare-`T` clause needs its own typing work in the bare-`T` defaults question. / Concern: The line must say that defaults fill after the written args evaluate. Otherwise readers can assume defaults run first, which breaks the §2.22 order.
  - **Web/Scripting:** ONE-LINE — I change from SEPARATE. A single sentence ("the fn type has full arity; a direct call fills the const defaults after the written args evaluate") answers "what is `start_server`'s type?" before anyone asks it. The hard part, the bare-`T` default, still goes to the bare-`T` defaults question. / Concern: The sentence may look like it settles the bare-`T` defaults question, so it must point to that open case.
  - **PLT:** ONE-LINE — The fn type has full arity, and a direct call fills in the defaults after the written args are evaluated. That is a clean elaboration, and it composes with HOFs and closures. It is also the reason the old Rejected row is stale, so it belongs next to Q2. The bare-`T` case needs its own analysis (the bare-`T` defaults question). / Concern: The sentence must say defaults are filled in after *all* written args evaluate. Otherwise the §2.22 evaluation order can be misread.
  - **DevOps:** ONE-LINE — One sentence fixes the meaning that signature help and hover display: the full-arity type, with defaults filled at a direct call. The generic clause needs its own probe and belongs with the bare-`T` defaults question. / Concern: The LSP may still show the fn type without its defaults. Hover and signature help should show `= <default>`.
  - **AI/ML:** ONE-LINE — "the type is the full arity; a direct call fills the const defaults after the written args evaluate" is one learnable sentence. It also answers the HOF worry behind the old Rejected row. The bare-`T` clause has its own open question (the bare-`T` defaults question). / Concern: the sentence could be read as allowing defaults through a fn value, so it must say plainly that a fn value takes every argument.
  - **Minimalism:** ONE-LINE — The sentence restates what §2.13, §2.21 and §2.22 already imply together; writing it once removes guesswork. The bare-`T` clause is the bare-`T` defaults question. / Concern: The one line must not grow into a typing section here.

- **Q8a: Drop the "3-8%" figure** (YES 6-0)
  - **Systems:** YES — An uncited number in a spec that doubles as training data gets repeated as fact. The claim stands without it: a same-typed swap type-checks and is silent. / Concern: None of note.
  - **Web/Scripting:** Yes — A number nobody can trace gets repeated in LLM training data and in blog posts. The claim stays true in words: a same-typed swap type-checks and is silent. / Concern: Without a number, a reader may see the feature as optional polish, so the text must state the bug plainly.
  - **PLT:** YES (drop "3-8%") — The spec makes no claim it cannot back. The bug class is sound without the number: a same-typed swap type-checks. / Concern: None worth noting.
  - **DevOps:** YES — A number nobody can trace becomes training data and gets repeated. The claim in words ("a same-typed swap type-checks and is silent") is true and needs no number. / Concern: None.
  - **AI/ML:** YES — an uncited number in the spec turns into a "fact" in training data. The claim holds in words alone: a same-typed swap type-checks and is silent. / Concern: none of substance.
  - **Minimalism:** yes — A number nobody can trace should not go into training data. The plain claim needs no number. / Concern: None.

- **Q8b: Limit sentence on the swap guard** (YES 6-0, trait-bound clause IN)
  - **Systems:** YES, trait-bound clause IN — The spec must not claim "impossible" for more than the checker covers. Today fn values and calls through a trait bound both let the swap through, so say both. Remove the trait-bound clause when the conformance ruling lands. / Concern: Someone has to delete the clause when the conformance ruling closes. Link the two.
  - **Web/Scripting:** Yes, trait-bound clause IN — A user who finds the gap on their own (fn values, or calls through a bound) stops trusting the rest of the spec. Saying where the guard ends costs one sentence. / Concern: Someone must remove the trait-bound clause when the conformance ruling lands, so link the clause to that ruling.
  - **PLT:** YES, trait-bound clause IN — The guarantee is stated as "impossible", so its scope must be exact. My probe shows that a call through a trait bound can bind by the trait's labels into an impl that put its params in a different order. Leaving that out would overstate soundness. / Concern: When the conformance ruling lands, someone must remove the clause, or the spec will understate the guard.
  - **DevOps:** YES, trait-bound clause IN — A spec that names the limits of its own guarantee is what lets tools (a future lint, the LSP) warn at those places. Until the conformance ruling lands, a call through a trait bound is a real hole, and the text must say so. / Concern: Nobody may remember to remove the clause when the conformance ruling lands. The conformance-ruling ticket should list the edit.
  - **AI/ML:** YES, trait-bound clause IN — a model that reads "the swap is impossible" will trust a call through a fn value or a trait bound. The spec must not claim more than the checker holds. When the conformance ruling lands, the trait-bound clause comes out. / Concern: the clause can go stale after the conformance ruling lands, so the conformance ruling's done criteria must include removing it.
  - **Minimalism:** yes, trait-bound clause IN — Spec text must not promise more than the checker holds. Naming the trait-bound gap until the conformance ruling lands is honest, and the clause comes out when it lands. / Concern: The clause can go stale after the conformance ruling; that ticket should list "remove the §2.13 limit clause" as a step.

- **Q9 (newline after the marker)** (IN-RULING 6-0)
  - **Systems:** IN-RULING — This is grammar. It belongs with the marker rule, and a newline after `*,` should behave like a newline after any comma. / Concern: None of note. `*` followed by a newline and then `)` must still be an error (a marker with no keyword params after it).
  - **Web/Scripting:** IN-RULING — People and LLMs will write a long signature with `*,` on its own line, because the formatter lays it out that way. A grammar rule that rejects the formatter's own layout is a bug. It belongs in the grammar text. / Concern: None worth naming.
  - **PLT:** IN-RULING — Where a newline may appear in a param list is grammar. The formatter and the parser must agree on it, and that comes from spec text. / Concern: None worth noting.
  - **DevOps:** IN-RULING — This is grammar, and the formatter, the parser and the LSP's incremental parse must agree on it. Today `fn h(*,` followed by a newline would cascade into many errors. / Concern: None.
  - **AI/ML:** IN-RULING — models often break long signatures after the marker. Whether that parses is grammar, so the spec must state it. / Concern: none of substance.
  - **Minimalism:** IN-RULING — It is grammar: the marker is a list item and should take a newline after it like any comma. One sentence. / Concern: None.

- **Q9 (the rest)** (CHORES 4, IN-RULING 2: split, taken to Phase D)
  - **Systems:** CHORES — `name = value`, `*args`/`**kw`, the plural fix, and a second `*` are each a diagnostic for a mistake that is already an error. They change no legal program, so they need no vote. File them under this ruling. / Concern: Chores get dropped. File each as a br ticket the same day the ruling is recorded.
  - **Web/Scripting:** CHORES — `name = value` → "keyword arguments use `:`" is the most valuable item for Python devs, and the variadics and plural fixes are cheap. None of them needs a vote on the merits. Filing them as chores under this ruling keeps the spec text short. / Concern: Chores slip, and `f(1, b = 2)` gives four errors with no hint today, so file it as the first of them.
  - **PLT:** IN-RULING *(dissent)* — `name = value`, `*args` and a second `*` are the shapes we predict from Python priors once `*` is adopted. Stating the required diagnostic is part of making STAR safe, so it is normative, not polish. The E0529 plural fix is a text bug, and it can stay a chore. / Concern: The rules must not be so detailed that the exact wording of messages gets frozen into the spec.
  - **DevOps:** IN-RULING *(dissent)* — These are the first errors a model with Python priors meets: `b = 2`, `*args`, a second `*`. The ruling's case rests on "the wrong guess is cheap", so their shape (one error, no cascade, a machine fix only where the label is already written) is normative. I accept CHORES if the ruling states the one-error, no-cascade requirement. / Concern: As chores without a stated requirement, they may slip, and the change to `*` would ship with today's three-signal output for the most common guesses.
  - **AI/ML:** CHORES — I strongly want these four messages, the `name = value` and `*args` cases most, because they are the next Python forms a model writes. But they are diagnostic behaviour, not language rules. Filed as chores under this ruling, they stay required without fixing wording in the spec. / Concern: chores can slip behind the token change, so file them blocking the `--` removal step.
  - **Minimalism:** CHORES — These are help text on existing codes, not language rules. Normative diagnostic wording in the spec grows surface we must keep in sync for no user-visible semantics; "at most one marker" can be one grammar sentence, with no new code. / Concern: Chores filed under a ruling tend to rot; each needs its own br ticket at once.

#### Phase D — Round 2 (Q3, Q9-rest)

Every other question was decided in round 1. Phase D covered only Q3 and Q9 (the rest). Each seat wrote one debate reply, read the other five, and voted again. Debate excerpts:

- **Web/Scripting (moves to HARD):**

> ## Q3: I move to HARD, on one condition
>
> devops and aiml answered my concern. My case for DEPRECATE was that old code should keep a one-step way out. devops is right that an error with a span edit gives `blink fix` the same one-command path a warning does. aiml's point weighs most from my seat: a release where both forms are legal puts two spellings into the snippets that people and models copy. "Which one is right?" is exactly the Stack Overflow question this change exists to remove.

- **PLT (moves to HARD on Q3, to CHORES on Q9):**

> **Q3: I move to HARD, on one condition.**
> I voted DEPRECATE so that old code keeps building. devops is right that an error which carries a span edit gives the same one-command path through `blink fix` as a warning does. aiml is right that a warning release puts two legal spellings into the world, and that breaks Principle 2 for the length of the window. My only aim was a mechanical way out, and HARD keeps it.
>
> **Q9 (the rest): I move to CHORES, with two points kept in the ruling.**
> min and sys are right that `name = value`, `*args`/`**kw` and the E0529 plural fix change no legal program. They are diagnostics for code that is already wrong, so spec text would only freeze the wording.
>
> 1. **"A param list has at most one keyword marker" is grammar.** It decides which programs parse. min already offers it as one grammar sentence, and that sentence belongs in §2.13 beside the newline rule.
> 2. **devops's requirement goes in one sentence:** each of the predicted Python-prior mistakes gives one error with no cascade. That is a promise about how the checker behaves. It is not message text, and it is the reason STAR is cheap when a model guesses wrong.
>
> 2. **devops's requirement goes in one sentence:** each of the predicted Python-prior mistakes gives one error with no cascade. That is a promise about how the checker behaves. It is not message text, and it is the reason STAR is cheap when a model guesses wrong.

- **DevOps (moves to CHORES on Q9):**

> **Q3: I stay HARD.** web says a warning "keeps that code building". That is true, but a warning nobody acts on is how two spellings survive. plt's own concern ("the warning release must have a fixed end") names that risk. With HARD, the user still has a one-command way out, as long as one tooling fact holds, and I want the ruling to state it: **`blink fix` must apply the `--` → `*,` edit even though it comes from a parse error.** Today `blink fix` runs the checker and applies span edits. A parse-stage fix has to reach that path, and the cascade after the bad token must not block it, so the parser must recover at the marker and keep parsing the param list. If that holds, HARD and DEPRECATE cost the user the same: one `blink fix`. HARD costs us one release less of two forms in training data (aiml's point). min is right that the fix must live as long as the `DashDash` token does. Q4a keeps the token, so the fix stays.
>
> **Q9 (the rest): I move to CHORES, on aiml's condition.** sys and min are right that these change no legal program, and plt is right that the wording must not freeze in the spec. My Phase C concern was that STAR would ship with today's three-signal output for `*`-style guesses. aiml's condition answers it: file the four chores at once and make the `name = value` and `*args`/`**kw` chores **block the `--` removal step**, so the token change cannot land without them. The one part I still want as a sentence in the ruling is the requirement, not the wording: "each of these shapes gives one error with no cascade". "At most one marker" is grammar, and min's single grammar sentence covers it.

- **Systems (offers the sentence):**

> devops offers to accept CHORES if the ruling states the requirement. I accept that, and I think it settles the question for plt too. Put one sentence in the ruling:
>
> > A Python-shaped mistake in a param list or call (`name = value`, `*args`/`**kw`, a second `*`) gives one error on that construct, with no cascade. A machine fix is allowed only where the author already wrote the label.

- **AI/ML:**

> I move toward **devops**'s middle position.
> - **plt** and **devops** are right that the case for STAR rests on "the wrong guess is cheap". A switch to `*` that ships with today's output (three signals for `*,`, four errors for `b = 2`) breaks that promise for the forms models write first.
> - **min** and **plt** are also right that fixed message wording must not go into the spec.
>
> - **plt** and **devops** are right that the case for STAR rests on "the wrong guess is cheap". A switch to `*` that ships with today's output (three signals for `*,`, four errors for `b = 2`) breaks that promise for the forms models write first.
> - **min** and **plt** are also right that fixed message wording must not go into the spec.
>
> > Each of the predicted Python forms (`*` used wrongly, `name = value` at a call, `*args`/`**kw`, a second marker) produces one error and no cascade. A machine fix is offered only where the author already wrote the label.

- **Minimalism (moves from CHORES ONLY to CHORES + SENTENCE in the re-vote):**

> **plt, devops:** "making STAR safe" overstates it. Each of the four shapes is already a compile error today:
> - `name = value`
> - `*args` / `**kw`
> - a second `*`
> - the E0529 plural
>
> If the panel wants one normative line, I accept this one in place of a list: "a misplaced or repeated marker is a parse error". That is grammar. The rest stays chores.

Re-vote. No dissent remains.

- **Q3: Migration** (HARD 6-0. Conditions: the error carries a machine-applicable span edit to `*,`, the parser recovers at the marker, a test proves `blink fix` applies it, and the fix lives as long as `--` stays reserved)
  - **Systems:** HARD — Neither src/ nor lib/std declares a keyword param, so no bootstrap step needs a release that accepts both forms. An error with a machine span edit gives the same one-command repair (`blink fix`) as a warning would, and Blink never has two spellings in the wild. The `--` → `*,` edit only renames syntax, so it keeps the meaning. / Concern: If the parser does not recover at the marker, the span edit never reaches `blink fix`. A test must prove the end-to-end rewrite.
  - **Web/Scripting:** HARD — An error that carries a tested span edit to `*,` gives old code the same one-command repair that a warning would. It also keeps a release of two legal spellings out of the snippets that people and models copy. Under the stated conditions, I see nothing that DEPRECATE protects and HARD does not. / Concern: If parser recovery at the marker regresses, the fix never reaches `blink fix`, and users with old code hit a wall, so the test must run in `task ci`.
  - **PLT:** HARD — An error that carries a span edit gives old code the same one-command way out as a warning does. It also avoids a release in which two spellings are legal, which breaks Principle 2. No self-host step depends on `--`, so a deprecation window protects nothing in this repo. / Concern: If the parser does not recover at the marker, `blink fix` never sees the edit and the mechanical path is lost. The test must run `blink fix` from start to end.
  - **DevOps:** HARD — An error that carries a machine-applicable span edit to `*,` gives old code and old LLM drafts the same one-command repair through `blink fix` that a warning gives, with no release where both spellings compile. The fix must reach `blink fix` from a parse error. So the parser recovers at the marker and keeps parsing the param list, and a test proves that `blink fix` rewrites `--` to `*,`. Under Q4a the fix lives as long as `--` stays reserved, which is always. / Concern: If the parser does not recover at `--`, the cascade buries the span edit, and HARD becomes a wall with only a help line.
  - **AI/ML:** HARD — Training data with `--` outlives any warning window. The thing that helps models and old snippets is a machine fix that never expires, and HARD gives exactly that. A warning release would let both spellings compile for a time, and code from that time teaches the next model the wrong lesson. The stated conditions make the path mechanical: a span edit, parser recovery at the marker, and a test that proves `blink fix` applies it. / Concern: if parser recovery at `--` is weak, the fix may never reach `blink fix`, and users would get a bare error with no way out.
  - **Minimalism:** HARD — An error that carries a span edit gives the same one-command `blink fix` path as a warning, with no release where two spellings compile. I take the stated conditions as part of the vote: - the edit is machine-applicable; - the parser recovers at the marker so that `blink fix` reaches the edit; - a test proves the fix applies; - the fix lives as long as `--` stays reserved. / Concern: If the parse-stage fix does not reach `blink fix` in practice, HARD becomes a wall; that test must land with the change, not after it.

- **Q9 (the rest)** (CHORES + SENTENCE 6-0)
  - **Systems:** CHORES + SENTENCE — The one sentence fixes behaviour that users and models depend on: one error, no cascade, and a machine fix only where the label is already written. That last rule is the same safety rule that made E0529 help-only, so it belongs in the spec, not in a chore's acceptance criteria. The message wording stays out of the spec, which keeps the surface small. / Concern: The sentence could be read as banning the follow-on diagnostics that help. It should say "no cascade from that construct", not "no other errors in the file".
  - **Web/Scripting:** CHORES + SENTENCE — The predicted Python-shaped mistakes are the first errors a new user meets after the change to `*`. One normative sentence ("one error, no cascade, a machine fix only where the label is already written") makes the ruling's claim that "the wrong guess is cheap" binding. It does not freeze any message wording. An acceptance line on a chore (min's form) can be edited away without a panel, so a bar that the ruling depends on should not live there. / Concern: "No cascade" can be read too loosely, so each chore needs a golden test that counts exactly one error.
  - **PLT:** CHORES + SENTENCE — The message wording is tooling, so it belongs in chores. But "one error, no cascade" and "a machine fix only where the author already wrote the label" are promises about checker behaviour. The second one is the same reason that made E0529 HELP-ONLY. One normative sentence keeps that promise sound across every future diagnostic without fixing the wording. "At most one keyword marker" is grammar and goes in the grammar text. / Concern: The sentence must name the predicted mistakes as a closed list. If it does not, it can be read as a general no-cascade rule for every diagnostic, which the checker cannot meet today.
  - **DevOps:** CHORES + SENTENCE — The sentence fixes behaviour, not wording: one error with no cascade, and a machine fix only where the author already wrote the label. Tools and agent loops depend on that contract, and it is the reason STAR makes the wrong guess cheap. min is right that no program is silently wrong today. But the label-only fix rule is the same safety rule as Q5, so it belongs in spec text and not only in a chore's acceptance line. The four chores block the `--` removal step. / Concern: Someone may read "no cascade" as "no further diagnostics in the file". The ruling should say it means no follow-on errors from that one construct.
  - **AI/ML:** CHORES + SENTENCE — the case for STAR rests on "the wrong guess is cheap" for the Python forms models write first. One normative sentence makes that a promise in the spec and fixes no message wording. min's version turns the bar into acceptance lines on the chores. That leaves the promise out of the spec, which is the one place a spec-only learner or a future implementer will look. / Concern: the sentence names a fixed list of "predicted mistakes", and that list can go stale as new prior-driven errors show up. Phrase the list as examples, not as a closed set.
  - **Minimalism:** CHORES + SENTENCE (I move from CHORES ONLY) — My objection was to freezing message wording in the spec. The sentence fixes behaviour, not words: one error, no cascade, and a machine fix only where the author already wrote the label. That is a short, checkable promise, and it backs the ruling's claim that the wrong guess is cheap. "At most one keyword marker" goes in the grammar text, and the chores block the `--` removal step. / Concern: "No cascade" needs a test per predicted form, or the sentence becomes a normative claim the checker does not hold.

### Final Spec

```blink
fn transfer(amount: Int, *, from: Account, to: Account) -> Result[Transaction, BankError] {
    // ...
}
transfer(300, from: alice, to: bob)
fn start_server(*, host: Str = "0.0.0.0", port: Port = 8080) ! Net { }
```

Locked points:

- **Q1.** `*` replaces `--` as the keyword marker. It is its own list item with a comma after it. All §2.13 rules and the five codes (E0510, E0511, E0527, E0528, E0529) stay as they are. Labels stay call-site sugar. 6-0.
- **Q2.** Rewrite the DECISIONS.md Rejected rows "Defaults on positional parameters (E0531)" and "Caller-chosen labels". Mixing is allowed exactly as the declaration fixes it. Keep "Optional keyword args (caller's choice)" as it is. 6-0.
- **Q3.** `--` in a param list is an error at once, with a machine-applicable edit to `*,`. The parser recovers at the marker. A test proves that `blink fix` applies the edit. The fix lives as long as `--` stays reserved. 6-0 in round 2, after 4-2 in round 1 (web and PLT for DEPRECATE).
- **Q4a.** `--` stays a reserved token. In a param list, the fix is `*,`. A prefix `--x` gets a help line: no decrement, write `x -= 1`. An infix `a--b` gets a help line: write `a - -b`. 6-0.
- **Q4b.** The lexical rule goes in the spec text. The message wording does not. 6-0.
- **Q5.** E0529 is help-only. Strike "machine-applicable" from §2.13 and from the E0529 explain text. The help names the params and pre-fills no order. 6-0.
- **Q6.** Trait/impl conformance for the keyword boundary and names is a separate ruling, under the open trait/impl ticket. 5-1 (DevOps dissents, and accepts it if Q8b names the gap).
- **Q7.** One line in §2.13: a fn's type is its full arity. A direct call fills the const defaults after all written args evaluate. A fn value takes every argument. The bare-`T` default clause goes to its own open ticket. 6-0.
- **Q8a.** Drop the uncited "3-8%" figure. The claim stays in words: a same-typed swap type-checks and is silent. 6-0.
- **Q8b.** Add a limit sentence. The guard covers direct calls and method calls on a concrete receiver. A fn value carries no labels. Calls through a trait bound are not covered until the conformance ruling lands. 6-0.
- **Q9 (newline).** A newline after the marker is allowed, as after any comma. A param list has at most one marker. Both go in the grammar text. A marker with no keyword param after it is an error. 6-0.
- **Q9 (the rest).** Four diagnostic chores: `name = value` gives "keyword arguments use `:`" with a machine fix; `*args` or `**kw` gives "no variadic parameters; take `List[T]`"; a second `*` gives one error; the E0529 message uses the plural form correctly. Each chore needs a golden test that counts exactly one error. The chores block the step that removes `--`. One normative sentence goes in the ruling: each such mistake gives one error with no follow-on errors from that construct, and a machine fix is offered only where the author already wrote the label. 6-0 in round 2, after 4-2 in round 1 (PLT and DevOps for IN-RULING).
- **Follow-ups, no vote.** A lint for three or more params with adjacent same-typed params and no marker (PLT; DevOps wants warning level). The overlap between all-keyword fns in §2.13 and the §2.15 struct shorthand (Minimalism).
