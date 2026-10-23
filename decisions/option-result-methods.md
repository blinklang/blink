[< All Decisions](../DECISIONS.md)

# Option and Result Methods — Design Rationale

### Panel Deliberation

The ticket asked that `llms-full.md` cover what the spec and `examples/` use. Moderator triage found that most items were already specified. Three defects were left: the spec names methods on `Option` and `Result` that no section declares (`unwrap_or`, `unwrap_or_else`, `expect` in the §7.5 text and the E0306 help, and `map_err` in two DECISIONS.md rows); the reference files `llms.md` and `llms-full.md` have no rule that ties them to `sections/`; and `llms-full.md` still prints `read_file`, which §4.4 removed. The panel took the method surface of `Option` and `Result`, the names the table leaves out, and the reference-sync rule.

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated in four phases. Quoted text is each panelist's own words. Each quote is a whole paragraph or list item of the panel record; "…" marks a cut inside one.

Questions:

- Q1: the base table. Option: `is_some`, `is_none`, `unwrap`, `map`, `ok_or`. Result: `is_ok`, `is_err`, `unwrap`, `unwrap_err`, `map`, `map_err`, `ok`. Spec text that names a method outside the table is rewritten.
- Q2: add `and_then`. Q3: add `expect`.
- Q4: the default on a `Result`: **D-ok** (only `r.ok() ?? d`) or **D-unwrap_or** (also `Result.unwrap_or(d)`).
- Q5: callbacks of `map` and `map_err` forward effects with `! _`.
- Q6: Rust names not in the table: **N-spec** (the spec lists them with the help each gets) or **N-chore** (a tooling chore, no list in the spec).
- Q7: how the reference files stay in step with `sections/`: **E-drift** (one check on the method names), **E-drift+ratchet** (E-drift, plus `examples/*.bl` and `llms-full.md` code blocks under `blink check` as shrink-only lists), or **E-none** (a convention).

#### Phase A — Independent proposals

All six proposed a closed, declared method table with `ok_or`, `map_err` and `ok`, and no `filter`. They differed on `map`, `and_then`, `expect`, `err()` and on the default on a `Result`. All six agreed that `sections/` is the normative source and that the reference files state no more and no less.

- **Systems:**

> Add a §7.6 *Option and Result Methods* table next to §7.5. The methods are built in and "behave as if declared", the same
> wording §7.5 uses for `unwrap`. The table is closed: a method not in it is UnresolvedMethod.
>
> Rule for the spec: **a method, builtin or syntax form may appear in llms-full.md / llms.md, in a ```blink block of
> sections/, or in examples/ only if a section declares it.** A use with no declaration is a defect in the use, not a
> license to add the feature.

- **Web/Scripting:**

> Why `??` everywhere and no `unwrap_or` / `unwrap_or_else`:
> - JS and TS devs already know `??` (and C#, Kotlin's `?:`, Swift's `??`). One default operator for both types is a 5-minute
>   learn. Two forms (`??` for Option, `unwrap_or` for Result) is a guaranteed Stack Overflow question: "why does
>   `o.unwrap_or(0)` not compile when `r.unwrap_or(0)` does?"
> - `??` is lazy (it desugars to `match`), so `unwrap_or_else` buys nothing. When the error value matters, that is a `match`.
> - Principle 2 holds without asking anyone to remember an asymmetry.
>
> Rule (put in 06_tooling.md next to `blink llms`):
> 1. sections/ is normative. llms.md / llms-full.md are a derived summary.
> 2. The reference may list only API that a section declares. (Fails today: llms-full.md:433 builtin `read_file`.)
> 3. Every API a spec code block or examples/*.bl file calls must be declared in a section and listed in the reference.
>    (Fails today: `map_err`, `ok_or`, `unwrap_or`, `expect`.) A spec example that uses something undeclared is a spec bug,
>    fixed by declaring it or rewriting the example.
> 4. A spelling rule that changes what users type (`T?` / `List[T]`, DECISIONS.md:472) goes in the reference too.

- **PLT:**

> Add a §7.6 "Combinators" next to §7.5. Same wording pattern as §7.5: "built in and behave as if declared".
>
> The defect class here is that the spec text and the reference files assert facts that no section declares. A theory
> that uses symbols it never defines is not a theory. The rule:

- **DevOps/Tooling:**

> §7.5 becomes "Option and Result Methods" with one closed table per type. The sentence "the methods are exactly" makes the
> table the full set, so the LSP completion list, E0505's "did you mean" list and llms-full.md all read one source.
>
> The reference that `blink llms` prints is derived from this specification. A name, method or signature it shows must be
> in the spec. A code block it shows must compile with the shipped compiler.

- **AI/ML:**

> An LLM that writes Blink brings a strong Rust prior for `Option`/`Result`: `map`, `map_err`, `and_then`,
> `ok`, `ok_or`, `unwrap_or`, `unwrap_or_else`, `expect`. The spec already *uses* six of these (12+ `map_err`
> sites, `ok_or` at 03c:408, `unwrap_or` at 04:1498 and 06:827, `expect` in examples/json_validator.bl) and tells
> users to call `unwrap_or` in the E0306 help (05:896, :908). But no section declares them, llms-full.md lists only
> `unwrap`/`is_*`, and gen1 resolves almost none. So today an AI gets three different answers from three sources:
> the spec examples say "call `.map_err`", llms-full.md says "it does not exist", and the compiler says
> UnresolvedMethod. That is the worst case for learnability: the model cannot learn the surface from the spec alone,
> because the spec contradicts itself. Whatever set we pick, the fix is one declared table that the spec, the
> reference, and the compiler all agree on.
>
> The one rule for defaults, written once in the table's lead text: **a default always uses `??`. To default a
> `Result`, take `.ok()` first.**

- **Minimalism:**

> The ticket reads as "the reference must cover what the examples use". From my seat the real gap is the other way around:
> the examples use methods that the language never chose to have. Adding every name the prose happens to use would grow the
> surface by accident, one example at a time. Each method on Option or Result is a second way to write a `match`, so
> Principle 2 (01_philosophy.md:32) puts the burden on the method, not on the `match`.
>
> Rule (one sentence for 06_tooling.md or the llms docs section): **llms.md and llms-full.md document only names that a
> section of sections/ declares; a spec example or a file in examples/ may call only declared names.** A violation is a
> `type:chore` bug against whichever side is wrong — never a reason to add an API.

#### Phase B — Debate highlights

- **Systems withdrew `expect` and `Result.err()`:**

> I withdraw `expect` and `Result.err()` from sys-1. With them gone, sys-1 is plt-1 plus the three methods that
> already exist (`unwrap`, `unwrap_err`, `is_*`). I now back **plt-1 as the surface**. sys-1 stands only as the name for
> "plt-1 + the V5 chore", and I fold that into my plt-1 vote (see V5).
>
> - `expect`: web, plt, devops and min all leave it out. From my seat it adds no new machine behaviour: `match` +
>   `panic(msg)` compiles to the same tag test and the same call into the panic path. It costs a second Debug-bound row
>   in §7.5 (DECISIONS.md:390) for no new power. Concede.
> - `err()`: no site in sections/ or examples/ uses it. YAGNI. Concede. It can come later; adding a method is not a break.

- **PLT dropped `and_then`:**

> My Phase A test was "a map, a bind, or a bridge". `and_then` is the bind, and it is sound. But I checked the alternative.
> `?` already works on `Option[T]` (02_syntax.md:1907 names both carriers), so bind inside a function is
> `let x = o?` and needs no closure. So `and_then` is a second spelling of `?` plus a helper fn. sys adds that each such
> method is a closure allocation unless lowered. Three seats drop it, and nothing in sections/ or examples/ uses it.
> Adding it later is not a breaking change. I withdraw it, and `Result.err()` stays out for the same reason (no use site).

- **DevOps withdrew `Result.unwrap_or` / `unwrap_or_else` and the lint-backed duplicate:**

> **I withdraw `Result.unwrap_or` / `unwrap_or_else` from devops-1.** I was the only seat with them in a first proposal. The
> argument that moved me is the diagnostic one, which is my own seat's test: with `.ok() ??` the fix-it table has ONE target
> for every default, on both types. With my devops-1, the help for `o.unwrap_or(d)` says "use `??`", and the help for
> `r.ok() ?? d` written by someone who read the Option rule would have to say... nothing, it works. So a user gets two right
> answers for Result. web put it plainly: "why does `o.unwrap_or(0)` not compile when `r.unwrap_or(0)` does?" is a question
> I would answer with a diagnostic forever. One operator means the help line is the same text in every case.
>
> **I withdraw devops-2.** No seat supports a lint-backed duplicate, and DECISIONS.md:472 shows we delete those one release later.

- **Fact: `??` is lazy and a method argument is eager.** Min had asked for a spec edit. The text already existed:

> The digest is right: §2.22 (02_syntax.md:2888) already says "`??` (§3.5): the default runs only when the left side is
> `None`." I withdraw the min-1 edit that asked §7.3 to state it. That strengthens min-1's case: `unwrap_or_else` on Option
> is already redundant by existing text, with no new sentence needed.

  Systems applied it to `Result.unwrap_or`:

> `Result.unwrap_or(d)` is cheap (no closure), but `d` is eager under §2.22: a method argument is not in the closed list
> of lazy forms (02_syntax.md:2884-2889). So `r.unwrap_or(expensive())` always pays for `expensive()`, while
> `r.ok() ?? expensive()` pays only on Err. Two default forms with two evaluation orders, chosen by the receiver type,
> is a trap. That is the case for `.ok() ??` from my seat, not just Principle 2.

- **Fact: the closure parameter type comes from the expected type.** PLT:

> The E0301 is a bug against 03_types.md:1751, which already exists. Leaving `map` out of the spec does not fix it.
> `List.map` hits the same inference rule. I keep `map` on both types: it is the functor action, it is the one form that
> transforms a payload inside an expression, and the decision file's `char_at(i).map(...) ?? false` shows the composition
> with `??` that keeps defaults on one operator. Without `map`, that line is a four-line `match`. I agree with min about
> everything else in min-1. The difference between min-1 and amended plt-1 is now `map` alone.

- **Fact: a callback type with no effect row is pure.** PLT:

> This is not "signatures with no effects written". The spec gives that spelling a meaning:
>
> - 04_effects.md:3256: "A function type without `!` is pure."
> - 04_effects.md:3277: "`fn(Int) -> Int` and `fn(Int) -> Int ! IO` are different types — the compiler rejects passing
>   an effectful callback where a pure one is expected."

#### Phase C — Silent vote

Changes in round 1: sys withdrew `expect` and `err()`; aiml dropped `err()`; plt dropped `and_then`; min amended to `map` on both types and nothing else; devops withdrew `Result.unwrap_or` and `unwrap_or_else` and moved its examples check to a ratchet.

| Question | Result |
|---|---|
| Q1 base table | **yes 6-0** |
| Q2 add `and_then` | **no 5-1** (aiml: yes) |
| Q3 add `expect` | **no 5-1** (aiml: yes) |
| Q4 default on a `Result` | **D-ok 6-0** |
| Q5 `! _` on callbacks | **yes 6-0** |
| Q6 Rust names not in the table | **3-3**: N-spec (web, devops, aiml); N-chore (sys, plt, min). Phase D |
| Q7 reference sync | **E-drift+ratchet 4-2** (aiml, min: E-drift). Phase D |

Each seat's vote, reasoning and concern:

- **Systems:**

  - Q1 — **yes**

    > **Reasoning:** Each method is a tag test plus at most one call. Only `map` and `map_err` take a closure, and §2.22 (02_syntax.md:2891) lets codegen lower a closure-literal argument to an inline `match` with no visible change. Seven methods per type is a small, auditable codegen surface, all built in, with no stdlib dispatch.
    >
    > **Concern:** If no one files the closure-literal lowering chore, `fs.read(p).map_err(fn(e) { ... })?` will heap-allocate a `blink_closure` on every successful call. Users who care will then hand-write `match`, and the corpus will have two styles.

  - Q2 `and_then` — **no**

    > **Reasoning:** No site in sections/ or examples/ uses it. `?` inside a helper function gives bind with zero allocation. It would be one more closure-taking method, with a hidden alloc until the lowering chore lands. Adding it later is not a break, so wait for a real need.
    >
    > **Concern:** If it passes, it adds a closure path that has no call site to measure, before codegen can make closures free.

  - Q3 `expect` — **no**

    > **Reasoning:** `match` plus `panic(msg)` compiles to the same tag test and panic call. `expect` adds no machine behaviour, and it adds a second Debug-bound row to §7.5 (DECISIONS.md:390).
    >
    > **Concern:** The Rust habit makes `.expect(` the most likely first-draft error. The help line must turn it into `match` plus `panic` in one cycle.

  - Q4 default on a Result — **D-ok**

    > **Reasoning:** `r.ok() ?? d` is a re-tag and a branch, and `d` runs only on Err (02_syntax.md:2888). `Result.unwrap_or(d)` would evaluate `d` before the call under §2.22. That gives two default forms with two evaluation orders, split by the receiver type, so `unwrap_or(expensive())` pays on the hot path.
    >
    > **Concern:** If D-unwrap_or wins, the spec must state in the table that the argument is eager. Users will assume it matches `??`.

  - Q5 `! _` — **yes**

    > **Reasoning:** A callback type with no row is pure (04_effects.md:3256), so leaving the row out would reject `map_err` bodies that log or do IO. `List.map` already uses this shape (03_types.md:781). Effect rows erase in codegen, so forwarding costs nothing at runtime.
    >
    > **Concern:** gen1 already fails to infer closure-parameter types on `o.map(...)` (E0301). Effect forwarding on a builtin receiver must not become a second inference gap that blocks the table from shipping.

  - Q6 names not in the table — **N-chore**

    > **Reasoning:** The help lines are diagnostic surface. Q1 already fixes the normative part, which is that the E0306 help names only declared forms. A spec list of rejected foreign names has no end, and it costs spec text with no effect on what the program compiles to.
    >
    > **Concern:** If the chore slips, the most common Rust-habit errors will get a bare UnresolvedMethod with no fix.

  - Q7 reference sync — **E-drift+ratchet**

    > **Reasoning:** The ticket shows the convention already failed: `read_file` is still in llms-full.md:433, and a v1-blocking `map_err` impl ticket exists with no spec behind it. scripts/check_str_byte_methods.sh is the in-repo precedent for the drift check. The ratchet stops new broken examples now, without blocking on the 11 that already fail.
    >
    > **Concern:** A shrink-only ratchet with 11 of 22 examples failing can sit at 11 for a long time. It needs an owner ticket to bring it to zero.

- **Web/Scripting:**

  - Q1 — **yes**

    > **Reasoning:** Twelve methods, one job each, and every one is a name a JS/TS/Python dev or an LLM can guess from the call site.
    > The spec stops telling users to call methods that do not exist, which is the main failure this ticket shows. `map` +
    > `??` covers the most common "look up, transform, default" line in one line.
    >
    > **Concern:** If `map` still gives E0301 on `o.map(fn(x) { ... })` when the table ships, the first thing a new user tries
    > on a specified method fails, so the inference fix must land with the table.

  - Q2 `and_then` — **no**

    > **Reasoning:** JS and Python devs have no prior for `and_then`; `?` inside a function that returns `U?` or `Result` already
    > does the job and is the form we teach. Adding it later breaks nothing, while removing it would. Fewer names means fewer
    > "which one do I use" questions.
    >
    > **Concern:** Users who chain lookups in one expression will write a nested `match` and find it verbose, and that will
    > bring this request back soon.

  - Q3 `expect` — **no**

    > **Reasoning:** `match` + `panic(msg)` already gives a custom message, and the E0306 help already names that path. A second
    > panicking accessor adds a Debug-bound row and a choice to make with no new power. The fix-it (Q6) turns the Rust habit
    > into one compile cycle.
    >
    > **Concern:** Rust-trained code will write `.expect(...)` often, so the cost moves entirely onto the Q6 diagnostic, and it
    > must actually ship.

  - Q4 default on a Result — **D-ok**

    > **Reasoning:** One rule — "a default is `??`" — for both types, the operator JS/TS/C#/Swift devs already know, and it chains
    > (`a.ok() ?? b.ok() ?? 0`). `unwrap_or` on Result but not on Option is an asymmetry that both people and models get wrong.
    >
    > **Concern:** `r.ok() ?? d` reads as indirect to a newcomer, so the §7 table and llms-full.md must show it as the first
    > example, not hide it in prose.

  - Q5 `! _` — **yes**

    > **Reasoning:** A callback that logs or reads a file inside `map` / `map_err` must just work, the same as `List.map`
    > (03_types.md:781). Without forwarding, a callback with no effect row is pure (04_effects.md:3256), so the most ordinary
    > scripting callback becomes an effect error.
    >
    > **Concern:** The effect error in a forwarded callback must point at the call inside the closure, not at the `.map(`, or
    > users will not see why the outer function needs `! IO`.

  - Q6 names not in the table — **N-spec**

    > **Reasoning:** The small table is only friendly if each rejected name answers with the Blink form (`o ?? d`,
    > `r.ok() ?? d`, `match` + `panic`). If the spec does not list it, it ships as a bare UnresolvedMethod and the user has to
    > search the docs. §7.5 already specifies its E0306 help text, so there is a precedent.
    >
    > **Concern:** The list can grow into a long catalogue of other languages' names; keep it to the handful that real code and
    > models produce.

  - Q7 reference sync — **E-drift+ratchet**

    > **Reasoning:** `blink llms --full` is where new users and every agent learn Blink, and a convention already failed
    > (`read_file` is still printed after §4.4 removed it). A shrink-only ratchet on examples/*.bl and the reference code blocks
    > stops new breakage without forcing the 11 current failures to be fixed in this change.
    >
    > **Concern:** A ratchet that starts at 11 of 22 failing can sit there for a long time, so each failure needs its own
    > ticket and the count needs an owner.

- **PLT:**

  - Q1 — **yes**

    > **Reasoning:** The spec defines each method as its `match`, so the table extends the language by definition only: no new typing judgement, no new exhaustiveness case. The table is closed and each entry has one job: functor map (`map`), the error leg of the bifunctor (`map_err`), and the two bridges (`ok`, `ok_or`). It also gives the decided `?` exact-match rule the tool that the rule names.
    >
    > **Concern:** The table text must state each method's `match` desugar and that the callback runs at most once, only on the named arm. Without that, gen1 and the spec can drift on evaluation order.

  - Q2 `and_then` — **no**

    > **Reasoning:** `?` already works on `Option[T]` and `Result[T, E]` (02_syntax.md:1907), so bind inside a function is `let x = o?` and needs no closure. `and_then` is sound, but it is a second spelling of `?` plus a helper fn, and no spec or example site uses it. Adding it later breaks nothing.
    >
    > **Concern:** None from my seat if it loses. If it wins, its signature must carry `! _` like the others.

  - Q3 `expect` — **no**

    > **Reasoning:** It is a second panicking accessor next to `unwrap`. A panic with a custom message is `match` + `panic`, which the E0306 help already names. It is sound under the §7.5 Debug rule, but it adds a method and a bound for no new power.
    >
    > **Concern:** None from my seat if it loses. If it wins, Result.expect must require `E: Debug` and its panic text must be normative, as §7.5 requires.

  - Q4 default on a Result — **D-ok**

    > **Reasoning:** One default operator for both types, and it is lazy (02_syntax.md:2888). `Result.unwrap_or(d)` takes an argument that is evaluated before the call. So `r.unwrap_or(f())` and `r.ok() ?? f()` would differ in when `f()` runs, and the language would have two default forms with two evaluation orders, picked by the receiver's type. `.ok() ??` composes two things we already have.
    >
    > **Concern:** The Rust habit `r.unwrap_or(0)` will be common, so the UnresolvedMethod help must name `.ok() ?? 0` from day one.

  - Q5 `! _` — **yes**

    > **Reasoning:** A callback type with no row is pure (04_effects.md:3256, :3277). Without `! _`, `r.map_err(f)` would be strictly weaker than the `match` that defines it: an effectful callback would be rejected where the same arm in a `match` is legal. With `! _` the call's row equals the row of its `match`, a pure callback makes the call pure (04_effects.md:3383), and the shape matches `List.map` (03_types.md:745).
    >
    > **Concern:** gen1 must solve `_` and infer the closure parameter from the receiver (03_types.md:1751). The E0301 on `o.map(fn(x) { ... })` today means an impl ticket must land before users see this table.

  - Q6 names not in the table — **N-chore**

    > **Reasoning:** The spec defines the language by what it has. The closed table already makes every other name UnresolvedMethod, and that is the whole rule. A spec list of another language's method names, each with its help line, puts tooling detail in the normative text and needs updating each time a Rust habit shows up. A diagnostic chore can keep and grow that list freely.
    >
    > **Concern:** If no one owns the chore, the fix-it lines never ship, and the Rust-habit error costs a docs search where it should cost one compile cycle.

  - Q7 reference sync — **E-drift+ratchet**

    > **Reasoning:** The ticket shows that a convention already failed: a v1-blocking `map_err` impl ticket exists with no spec text behind it. The drift check catches the exact defect here, including help text that names a missing method. The shrink-only ratchets bring the 11 of 22 failing examples, and the reference code blocks, under a gate with no flag day. That makes "the reference states no more and no less" a property a machine checks, not a hope.
    >
    > **Concern:** The ratchet checks examples against gen1, not against the spec. A name that no section declares but gen1 happens to accept would still pass. A later spec-vs-spec name check should close that gap.

- **DevOps/Tooling:**

  - Q1 — **yes**

    > **Reasoning:** One closed table gives the LSP completion list, the E0505 "did you mean" list, `blink query` and `blink llms`
    > one source. Today the E0306 help sends users to `unwrap_or` and the compiler then answers E0505; rewriting the spec sites
    > to the table ends that loop.
    >
    > **Concern:** gen1's E0301 on `o.map(fn(x) { x + 1 })` makes the first error a user sees on a specified method an inference
    > failure; the table must not ship to users until that probe passes.

  - Q2 `and_then` — **no**

    > **Reasoning:** `?` inside a function does the same job with a better error: E0509 names both error types at the line. A
    > type error inside a nested `and_then` closure reads as an inference failure at the closure's return. Adding it later is
    > not a breaking change.
    >
    > **Concern:** Rust-trained code will write `.and_then(...)` often; if the E0505 help for it is vague ("use match"), users pay
    > a search instead of one compile cycle.

  - Q3 `expect` — **no**

    > **Reasoning:** It adds a row to the E0306 table and a second normative panic-message format to keep stable, for what
    > `match` + `panic(msg)` already says. The rejected-name help covers the habit.
    >
    > **Concern:** examples/json_validator.bl and model drafts use `.expect`; the help line must show the exact `match` rewrite,
    > or users will fall back to bare `unwrap` and lose their message.

  - Q4 default on a Result — **D-ok**

    > **Reasoning:** One default operator for both types means one help text for every default fix, on both types, and all of
    > them are mechanical (`r.unwrap_or(d)` → `r.ok() ?? d`). Two forms split by receiver type make a diagnostic that has to
    > explain an asymmetry forever.
    >
    > **Concern:** `r.ok() ?? d` drops the error silently; a later lint for "discarded error in a default" may be wanted, and we
    > should not let that turn into a reason to add `unwrap_or` back.

  - Q5 `! _` — **yes**

    > **Reasoning:** A callback type with no effect row is pure (04_effects.md:3256, :3277), so without `! _` the hover and
    > `blink query` signature would reject every effectful closure, and the error would blame the user's closure for a
    > signature we wrote wrong. Same shape as `List.map`, so the hover text is what users already know.
    >
    > **Concern:** the effect error inside a forwarded closure must point at the effect use in the closure body, not at the
    > `.map(` call, or it reads as the method's fault.

  - Q6 names not in the table — **N-spec**

    > **Reasoning:** The spec already lists removed names with their replacement (§4.4 `read_file`); this is the same device. An
    > agent that reads only the spec then learns that `unwrap_or` is absent by design, not a gap the compiler will fill later.
    > The list also fixes which rewrites are machine-applicable (`o.unwrap_or(d)` → `o ?? d`) and which are help-only
    > (`r.unwrap_or_else(f)`, `expect`), which `blink fix` needs to be safe.
    >
    > **Concern:** the list can grow into a second Rust API index; keep it to names seen in our own spec, examples and model
    > drafts, with a "use `match`" catch-all for the rest.

  - Q7 reference sync — **E-drift+ratchet**

    > **Reasoning:** E-drift alone catches the method-table defect in this ticket, but not the `read_file` call that
    > llms-full.md:1075 and :1088 still show, nor the 11 of 22 examples that fail gen1 `blink check` today. A shrink-only
    > ratchet lands green on day one (the current failures are listed), then fails any new breakage and any fixed file left on
    > the list. The repo already runs that pattern (scripts/ratchet.sh). A code block that `blink llms` prints must compile with
    > the binary that prints it.
    >
    > **Concern:** a ratchet list with no owner only stops new breakage; each listed file needs its own chore, or the 11
    > failing examples stay broken as training data.

- **AI/ML:**

  - Q1 — **yes**

    > **Reasoning:** One closed table that the spec, llms-full.md and the compiler all agree on removes today's three
    > contradicting answers. Every name in it has the Rust name and signature, so the model prior is right for each of them.
    > Rewriting the spec sites that name `unwrap_or` and `expect` stops the spec from teaching methods that do not exist.
    >
    > **Concern:** Until gen1 infers the closure parameter for `o.map(fn(x) { ... })` (E0301 today), the most-guessed method
    > in the table fails on first use. Models that see it fail will move to `match`, and the corpus will split.

  - Q2 `and_then` — **yes**

    > **Reasoning:** `and_then` stays in the expression and `?` leaves the function, so they do different jobs. Choosing
    > between them is decided by context, not by style. Without it, the only fix a tool can offer for a Rust-style
    > `and_then` call is "write a helper function", which no tool can apply. It is a high-prior name with one meaning, so it
    > adds no decision point.
    >
    > **Concern:** If it is left out, models keep writing it, and no machine-applicable fix gets them to the Blink form.

  - Q3 `expect` — **yes**

    > **Reasoning:** `expect("msg")` is about 4 tokens; `match` + `panic` is about 20 over four lines. Models do not write
    > that form unprompted, so in practice they write `.unwrap()` and the message is lost. The Debug-bound rule
    > (DECISIONS.md:390) already covers it, so it adds no new concept.
    >
    > **Concern:** If it loses, the help line for `expect` must say "`unwrap`, or `match` with `panic(msg)`". If it does
    > not, the first draft of almost every model-written CLI gets an error with no clear rewrite.

  - Q4 default on a Result — **D-ok**

    > **Reasoning:** One rule for the concept, "a default is `??`", whatever the receiver type. Models generalise across the
    > Option/Result pair. With `Result.unwrap_or`, they write `o.unwrap_or` next, and Result also gets two default forms
    > (`unwrap_or` and `.ok() ??`). The token cost is the same.
    >
    > **Concern:** The Rust prior for `r.unwrap_or(0)` is very strong. Without the machine-applicable fix to `r.ok() ?? 0`,
    > this choice costs one failed compile on most first drafts.

  - Q5 `! _` — **yes**

    > **Reasoning:** It is the same signature as `List.map`, so a model learns one shape for every higher-order method.
    > Callbacks with no effect row are pure (04_effects.md:3256), so without `! _` a `map_err` closure that logs would be a
    > type error that the model cannot predict from the table.
    >
    > **Concern:** The llms-full.md table must show the `! _` in the signatures. If it shows simplified signatures, the
    > reference again says less than the spec.

  - Q6 names not in the table — **N-spec**

    > **Reasoning:** An AI that reads only the spec should learn the mapping "`unwrap_or` → `??`, `r.unwrap_or` →
    > `.ok() ??`". The spec already does this for removed APIs (§4.4 lists `read_file` as REMOVED with its replacement). A
    > list in the spec also gives the drift check in Q7 a source for the help text.
    >
    > **Concern:** The list could grow into a second, larger table of "Rust things we do not have". Keep it to the names
    > that the spec or a common model prior uses, about eight rows.

  - Q7 reference sync — **E-drift**

    > **Reasoning:** It catches the exact failure in this ticket: the E0306 help and llms-full.md naming methods the spec
    > does not declare. It keeps llms-full.md following the spec, not gen1. A ratchet on `blink check` of reference blocks
    > would block a spec-correct example (for example `map`) until the impl lands. I support the examples/*.bl ratchet as a
    > separate chore, because those files are training data and 11 of 22 fail today. It does not need to be part of this
    > decision.
    >
    > **Concern:** E-drift covers only the Option/Result tables. Other reference tables (builtins such as `read_file` at
    > llms-full.md:433) can still drift until the same check reaches them.

- **Minimalism:**

  - Q1 — **yes**

    > **Reasoning:** Each of the seven new names has one job that no other form does in one expression: `map` keeps the shape,
    > `map_err` is the tool the `?` exact-match rule names, `ok` and `ok_or` bridge the two types for `??` and `?`. The table is
    > closed, so it adds a bounded surface and removes a worse state, a spec that tells users to call methods that do not exist.
    >
    > **Concern:** `map` ships with gen1's E0301 on closure parameters, and until the impl ticket lands the first specified
    > combinator a user tries is an error.

  - Q2 `and_then` — **no**

    > **Reasoning:** In Blink, bind already has syntax: `?`. `and_then` does the same job inside an expression, which is the
    > choice Principle 2 removes; `if let` fell to the same test (DECISIONS.md:128). Adding it later is non-breaking, removing it
    > is not, so YAGNI decides.
    >
    > **Concern:** If it passes, the corpus splits between `?`-in-a-helper and `and_then` chains, and agents waver between them
    > on every chain.

  - Q3 `expect` — **no**

    > **Reasoning:** It adds no power over `match` + `panic(msg)`, pulls the DECISIONS.md:390 bound onto one more method, and
    > makes one more panic message string normative. A second panicking accessor is surface without a job.
    >
    > **Concern:** Rust-trained drafts will type `.expect(...)` often; the help line must name the `match` + `panic` form or the
    > no-vote costs a round trip each time.

  - Q4 default on a Result — **D-ok**

    > **Reasoning:** With `ok()` in the table, `Result.unwrap_or(d)` is a second spelling of `r.ok() ?? d`, and it is eager where
    > `??` is lazy (02_syntax.md:2888). D-ok keeps one default operator, one evaluation order, for both types.
    >
    > **Concern:** The `unwrap_or` prior is strong, and the help line for it is the only thing standing between users and
    > repeated UnresolvedMethod errors.

  - Q5 `! _` — **yes**

    > **Reasoning:** This is the existing `List.map` shape (03_types.md:745), not a new rule. Leaving it off would make an
    > Option callback pure by default (04_effects.md:3256) while the List callback is not — an extra difference to learn.
    >
    > **Concern:** None from my seat beyond implementation lag in gen1.

  - Q6 names not in the table — **N-chore**

    > **Reasoning:** A list of rejected names in the spec is a second table to keep in sync and it grows each time someone
    > reaches for a new Rust name. One sentence ("a name not in the table is UnresolvedMethod; the help names the Blink form
    > where one exists") is enough spec; the rows belong in the diagnostic code.
    >
    > **Concern:** If N-spec wins, the rejected-names list becomes a de facto second API reference that drifts the same way
    > llms-full.md did.

  - Q7 reference sync — **E-drift**

    > **Reasoning:** One script on the precedent of scripts/check_str_byte_methods.sh catches exactly this ticket's failure at
    > zero language cost. Putting examples and reference blocks under `blink check` ties the docs to gen1 while the spec leads
    > the compiler, and 11 of 22 examples fail today for reasons outside this ticket; that is a separate chore.
    >
    > **Concern:** If E-drift+ratchet wins, the ratchet's fence-tag rule and the baseline become doc-writing friction, and the
    > ratchet number gets bumped rather than the examples fixed.

#### Phase D — Q6 and Q7 re-vote

Q6 split 3-3 and Q7 had a 2-seat minority, so the panel ran Phase D.

**Facts raised in step 1.** Systems and PLT: a method argument runs before the call, but the `??` default runs only on `None` (02_syntax.md:2884-2889), so the rewrite `o.unwrap_or(f())` → `o ?? f()` drops the effects of `f()` when the value is `Some`.

Systems:

> This is the strongest argument on either side, and it has a catch that comes from my seat. The rewrites are not all
> safe. Under §2.22 a method argument is eager, and `??` evaluates its right side only on `None` (02_syntax.md:2884-2889).
> So `o.unwrap_or(log_and_default())` → `o ?? log_and_default()` drops a side effect on the `Some` path. The same holds
> for `r.unwrap_or(d)` → `r.ok() ?? d`. The fix is safe only when `d` is a value with no effect and no panic: a literal,
> a variable, or a pure call. That condition is a fact about the language's evaluation order, not about tooling. A list
> that marks these rows "machine-applicable" with no condition would make `blink fix` change behaviour.

PLT:

> This is the strongest N-spec argument, and it points the other way. `o.unwrap_or(d)` → `o ?? d` is **not**
> meaning-preserving in general. Rust's `unwrap_or` evaluates `d` first, but `??` evaluates `d` only on `None`
> (02_syntax.md:2888). If `d` has an effect (`o.unwrap_or(next_id())`), the rewrite changes behavior. So "machine-
> applicable" depends on whether `d` is pure, which the fix engine can decide from the effect row. That rule belongs
> with the fix engine and its tests, where it can be refined, not frozen in sections/. If the spec froze "`o.unwrap_or(d)`
> → `o ?? d` is machine-applicable", it would bless a rewrite that is unsound for effectful `d`.

Min: the §3.2 removed-names table holds only names that a released Blink accepted (03_types.md:194), and `unwrap_or`, `unwrap_or_else`, `expect` and `and_then` were never accepted. In min's words:

> The device has an admission rule, and these names fail it. §3.2 *Removed methods* (sections/03_types.md:194), which §4.4
> defers to for method rows (04_effects.md:334): "The table holds only names that a released version of Blink or its
> standard library accepted." `read_file` qualifies: Blink shipped it, users wrote it, the table owes them a migration.
> `Option.unwrap_or`, `expect`, `and_then` on Option/Result were never accepted (gen1 gives UnresolvedMethod today,
> context.md §3). So N-spec is not "the same device". It is one of two new things:
> - widen the §3.2 criterion from "names Blink once had" to "names other languages have", which opens the table to every
>   foreign habit with no stopping rule; or
> - a second, new table next to §3.2 with a different rule.

Sys then moved to a bounded list, and web amended N-spec to the same shape.

Systems:

> **My position:** I move to **N-spec if it is bounded**: a closed list of the names this decision removes from spec
> text (`unwrap_or`, `unwrap_or_else`, `expect`, `and_then`), with the Blink form for each, on the §4.4 REMOVED pattern.
> Any machine-applicable rewrite carries the condition that the default argument has no effect and cannot panic. Other
> Rust names go to the chore under min's one sentence. If the step-2 options do not offer that bounded form, I stay
> **N-chore**: an unbounded list in the spec is worse than none.

Web/Scripting:

> To sys ("A spec list of rejected foreign names has no end") and min ("it grows each time someone reaches for a new Rust
> name"): I agree that an open list is wrong. So I amend N-spec to a **bounded** form. The spec lists only the rows that
> record a decision this panel just made, and every other name gets min's one sentence:
>
> | Written | Help names |
> |---|---|
> | `o.unwrap_or(d)`, `o.unwrap_or_else(f)` | `o ?? d` (Q4) |
> | `r.unwrap_or(d)`, `r.unwrap_or_else(f)` | `r.ok() ?? d`, or `match` (Q4) |
> | `expect(msg)` | `unwrap`, or `match` + `panic(msg)` (Q3) |
> | `and_then(f)` | `?` inside a function, or `match` (Q2) |

Min, on the ratchet half of Q7:

> What still stops me, for the llms-full.md code-block half: aiml — "A ratchet on `blink check` of reference blocks would
> block a spec-correct example (for example `map`) until the impl lands." plt says the same from the other side: "The
> ratchet checks examples against gen1, not against the spec." The rule all six agreed is "sections/ is normative; the
> reference states no more and no less". A gate whose oracle is gen1 enforces a different rule: "the reference states no
> more than gen1". That is a second source of truth, and this decision exists to have one. It also needs the
> `blink-fragment` fence convention, which is a doc-writing rule.

**Step 2 result.**

| Question | Result |
|---|---|
| D1 (Q6) | **N-spec-bounded 6-0** (min switched from N-chore) |
| D2 (Q7) | **E-drift+ratchet 5-1** (min: E-drift) |

Each seat's vote, reasoning and concern:

- **Systems:**

  - D1 (Q6) — **N-spec-bounded**

    > **Reasoning:** The spec text taught these four names (05:853 and :896-908, plus `expect` in examples), so the spec owes the reader the mapping that replaces them. The machine-applicable condition is a fact about evaluation order. A method argument is evaluated at the call, and the `??` default runs only on `None` (02_syntax.md:2884-2889). Only normative text can stop `blink fix` from dropping a side effect on the `Some` or `Ok` path. **Where the list lives:** in the new Option/Result method section, directly under the closed table, as a "Not provided" list. It does not go in the §3.2 removed-names table, because no released version accepted these names (03_types.md:194).
    >
    > **Concern:** The list must stay at four rows. Every later row needs a panel vote, or it grows into a mirror of Rust's API.

  - D2 (Q7) — **E-drift+ratchet**

    > **Reasoning:** The two checks catch different failures. The drift check catches spec-vs-reference name drift. The ratchet catches code that the shipped binary prints but cannot compile, and it stops a 12th broken example from landing as silently as the first 11. Each baseline entry names its clearing ticket, so a reviewer sees and approves any change to the baseline.
    >
    > **Concern:** A reference block for a spec-correct but unbuilt method (such as `map` under today's E0301) has to wait out of llms-full.md until the impl lands. Someone must track those gaps so the reference does not stay short.

- **Web/Scripting:**

  - D1 (Q6) — **N-spec-bounded**

    > **Reasoning:** A user who types `o.unwrap_or(0)` should learn in one compile cycle that Blink left the name out on purpose
    > and what to write instead. With four rows, all of them decisions this panel just made (Q2, Q3, Q4), the list cannot grow on
    > its own. It also gives the Q7 drift check a source for the help text. Where it lives: in a "Not in the table" note
    > directly under the new §7 Option/Result method table, not in the §3.2 removed-names table. Those names were never
    > accepted by a released Blink, so 03_types.md:194 correctly keeps them out of §3.2. sys's rule stays: the rewrite is
    > machine-applicable only when the default has no effect and cannot panic. Otherwise the help only names the form.
    >
    > **Concern:** The effect caveat (`o.unwrap_or(f())` → `o ?? f()` drops `f()`'s effects on `Some`) must show in the help
    > text. If it does not, users will think the help-only rewrite is a fix they can apply safely and it will change behavior.

  - D2 (Q7) — **E-drift+ratchet**

    > **Reasoning:** `blink llms --full` is what new users and agents copy from, so its code blocks and examples/*.bl must
    > compile with the binary that prints them. The drift check alone missed the `read_file` call sites in llms-full.md:1075
    > and :1088, because they are code, not a table row. A shrink-only ratchet where each baseline entry names its ticket is
    > green on day one and cannot hide new breakage.
    >
    > **Concern:** Spec-correct reference examples (such as `map`) stay out of llms-full.md until the E0301 inference fix lands.
    > That fix must be scheduled as a v1 blocker, or the reference keeps no runnable example for the most common combinator.

- **PLT:**

  - D1 (Q6) — **N-spec-bounded**

    > **Reasoning:** I voted N-chore for two reasons: the list had no end, and the "machine-applicable" mark froze a rewrite that is wrong for an effectful default. This option removes both. The list is closed to the four names that this panel removed from spec text, and new rows need a panel vote. A rewrite is machine-applicable only when the default has no effect and cannot panic, which keeps `blink fix` meaning-preserving under §2.22 and 02_syntax.md:2884-2889. sys's point decides it for me: the spec itself taught these four names (05:853, :896-908, examples/), so the spec owes a record of the change. That is a migration from our own text, not a list of Rust's API. Location: the list goes in §7.6 next to the table, under its own admission rule ("names this specification once used, removed by a panel vote"). It does not go in §3.2, whose rule (03_types.md:194) admits only names that a released Blink accepted. Widening §3.2's rule is the unbounded growth that min warns about.
    >
    > **Concern:** A second table with its own admission rule may later receive "one more Rust name" by a loose vote. The rule must stay "names this spec once used", or the list becomes the foreign-API catalogue that all six seats rejected.

  - D2 (Q7) — **E-drift+ratchet**

    > **Reasoning:** The drift leg checks spec against reference against help text, and its oracle is sections/. That is the single source of truth. The ratchet leg covers a different defect class, which E-drift cannot see: programs that we ship (examples/*.bl) and the code blocks the binary prints under `blink llms`, which fail on first compile. `read_file` at llms-full.md:1075 and :1088 is an instance. Neither leg touches sections/, so the spec still leads the compiler. Shrink-only with a ticket per baseline entry lands green and makes any growth a visible, reviewed edit.
    >
    > **Concern:** For llms-full.md blocks, the oracle is gen1. If the drift leg is ever weakened to "whatever gen1 accepts", a name that gen1 accepts but no section declares would pass both checks. The drift check must keep sections/ as its only oracle.

- **DevOps/Tooling:**

  - D1 (Q6) — **N-spec-bounded**

    > **Where the list lives:** in the new §7.6 itself, directly under the method table, as a "Not in the table" block. Not in
    > the §3.2 removed-names table: that table holds only names a released Blink accepted (03_types.md:194), and gen1 never
    > accepted these four. They were taught by spec text and examples, not by a release, so they are a fact about the §7.6
    > table, not a removal.
    > **Reasoning:** The help lines are where this ticket's bug lived (the E0306 help named a method the spec does not declare).
    > With the four rows in §7.6, the Q7 drift check has a spec source for the help text on both sides, declared and rejected
    > names, so that bug cannot come back silently. I accept sys's applicability rule and correct my earlier claim: I said
    > `o.unwrap_or(d)` → `o ?? d` is always safe because the default runs in fewer cases, but fewer runs drops `d`'s effects or
    > panic on `Some`, so the rewrite is machine-applicable only when `d` has no effect and cannot panic (a literal, a local, a
    > pure field read); otherwise it is help-only.
    >
    > **Concern:** "New rows only by panel vote" can make the list stale in the other direction: a common model-prior name
    > appears, gets a bare UnresolvedMethod, and nobody brings it to the panel; the one-sentence rule must still let tooling give
    > a help line for it.

  - D2 (Q7) — **E-drift+ratchet**

    > **Reasoning:** The drift check catches the table defect; the ratchets catch what it cannot: `blink llms --full` still
    > prints `read_file` calls at llms-full.md:1075 and :1088, and 11 of 22 examples fail gen1 `blink check`. A shrink-only
    > baseline blocks no spec-ahead example (it goes on the list with its ticket), and the per-entry ticket answers the
    > "number gets bumped" risk. A code block the binary prints as working Blink must compile with that binary.
    >
    > **Concern:** If the baseline grows each time a spec-ahead block lands, the gate turns into a list of known gaps that nobody
    > reads; the gate output must print the count and the oldest entry, so growth is seen.

- **AI/ML:**

  - D1 (Q6) — **N-spec-bounded**

    > **Reasoning:** An AI that reads only the table cannot tell "left out by design" from "not built yet", and models
    > assume the second. Four closed rows written right under the table tell them `??`, `.ok() ??` and `match` are the
    > designed forms. The list lives in §7.6 itself, as a "Not in this table" paragraph under the method table, and not in
    > the §3.2 removed-names table. These names were never accepted by a released Blink, so 03_types.md:194 keeps them out
    > of §3.2. I accept sys's rule: the rewrite is machine-applicable only when the default has no effect and cannot panic.
    > For other defaults the help line names the form but offers no auto-fix, because `o ?? f()` would drop `f()`'s effects
    > when the value is `Some`.
    >
    > **Concern:** The four rows must stay tied to panel votes. If a later change adds rows by habit, the list turns into
    > the second API index that min warned about.

  - D2 (Q7) — **E-drift+ratchet**

    > **Reasoning:** `blink llms` prints llms-full.md from the binary, and models copy its blocks exactly. A printed block
    > that the same binary rejects teaches a pattern that fails, with no fix the model can apply. The drift leg keeps the
    > reference tied to the spec, not to gen1. The shrink-only ratchets stop new broken examples now, and the 11 failing
    > examples are training data, so each needs a ticket.
    >
    > **Concern:** While E0301 is open, the llms-full.md block for `map` cannot go in, so the reference may show `map` in the
    > table with no example. That gap must close when the E0301 fix lands, and not become permanent.

- **Minimalism:**

  - D1 (Q6) — **N-spec-bounded**

    > **Reasoning:** I change my vote. The bounded form removes my main objection: the list is closed at four rows, grows only by
    > panel vote, and does not widen §3.2. The effect fact from sys and plt decides it. `o.unwrap_or(f())` → `o ?? f()` drops
    > `f()`'s effects on `Some` (02_syntax.md:2884-2889), so the rule that says when a rewrite is machine-applicable is about
    > what a program does. Semantics like that belong in the spec, not only in tooling. Where it lives: in §7, directly under
    > the Option/Result table, as "Names not in the table". It must not go in §3.2 *Removed methods*, whose admission rule
    > (03_types.md:194) these names fail.
    >
    > **Concern:** The "new rows only by panel vote" gate could wear down one Rust name at a time, until the list is the second
    > API index that every seat warned about.

  - D2 (Q7) — **E-drift**

    > **Reasoning:** The drift check compares the spec with the reference, which is the one rule all six agreed on. A ratchet on
    > llms-full.md code blocks under `blink check` makes gen1 a second oracle for the reference, and gen1 lags the spec (`map`
    > gives E0301 today). The examples/*.bl ratchet is worth having, and I want it filed as its own chore with this decision.
    >
    > **Concern:** If E-drift+ratchet wins, a correct reference example such as `o.map(...)` gets a baseline entry, or is held
    > back, until gen1 catches up. The reference then follows the compiler, not the spec.

### Final Spec

Section 7.6 of `sections/05_memory_compile_errors.md` holds the table. Signatures:

```blink
impl[T] Option[T] {
    fn is_some(self) -> Bool
    fn is_none(self) -> Bool
    fn unwrap(self) -> T                                  // §7.5
    fn map[U](self, f: fn(T) -> U ! _) -> U? ! _
    fn ok_or[E](self, e: E) -> Result[T, E]
}

impl[T, E] Result[T, E] {
    fn is_ok(self) -> Bool
    fn is_err(self) -> Bool
    fn unwrap(self) -> T                                  // §7.5
    fn unwrap_err(self) -> E                              // §7.5
    fn map[U](self, f: fn(T) -> U ! _) -> Result[U, E] ! _
    fn map_err[F](self, f: fn(E) -> F ! _) -> Result[T, F] ! _
    fn ok(self) -> T?
}
```

Locked points:

- The tables are closed. A name in no table is E0505 `UnresolvedMethod`. Where a Blink form does the same job, the help names it.
- No `and_then` (Q2), no `expect` (Q3), no `unwrap_or` or `unwrap_or_else` on either type (Q4). The default on a `Result` is `r.ok() ?? d`.
- The callbacks of `map` and `map_err` carry `! _`, the shape of `List.map`. Each method has the meaning of its `match` (Q5).
- The list of four names is in §7.6, under the table. It is not a part of the §3.2 table of removed names. It holds only names that this specification once used, and a new row needs a panel vote (D1).
- The rewrite to `??` is machine-applicable only when the default has no effect and cannot panic. Otherwise the help names the form and offers no edit. The help says that `o ?? f()` does not run `f()` when the value is `Some` (D1).
- `sections/` is normative. `llms.md` and `llms-full.md` state no more and no less. The method names in the reference tables and in the help text match the §7.6 tables. Reference code blocks and `examples/` pass `blink check`; a known failure is on a shrink-only list, with the change that clears it (D2). The rule is in §8.17.1.

### Amendments

No earlier row changes. Two earlier rows say "Use `.map_err()`": "`?` error conversion" and "`?` operator: error type match". Both named a method that no section declared. §7.6 now declares `map_err`, so both rows have spec text behind them.

### Implementation notes

These are not spec text.

- gen1 gives E0301 `CannotInferType` on `o.map(fn(x) { x + 1 })` and on `r.map(...)`. This goes against the closure-parameter rule at sections/03_types.md:1745-1751. All six seats name it.
- gen1 has no `ok_or`, `ok` or `map_err`; it gives `UnresolvedMethod`.
- The drift check compares the §7.6 tables, the `llms-full.md` tables and the help text. Its model is scripts/check_str_byte_methods.sh. Its only oracle is `sections/`.
- The shrink-only lists for `examples/*.bl` and `llms-full.md` code blocks are modelled on scripts/ratchet.sh. Each entry names the ticket that clears it. The gate prints the count and the oldest entry (devops). 11 of 22 examples fail gen1 `blink check` today.
- Sys: lower a closure-literal argument of `map` or `map_err` to an inline `match`. §2.22 allows it, because making a closure literal does not run its body. Without it, each call allocates a closure.
- Devops: keep closure spans in diagnostics, so that an effect error inside a forwarded callback points at the effect use in the closure body and not at the `.map(` call (web, devops).
- The machine-applicable rewrite needs an effect and panic check on the default expression.
- Related work: the `map_err` impl and the friction on `unwrap_or`.

### Open cases and follow-ups

- PLT: a later check that every method name the spec uses is declared in some section. The drift check covers only `Option` and `Result`, and its oracle is `sections/` and not gen1.
- Sys, min: if the open `?? return` ticket passes, revisit `ok_or`.
- Min: file the `examples/*.bl` ratchet as its own chore, with an owner for each failing example.
- Devops: tooling help for common Rust names that are not on the list. The list is closed, but a bare `UnresolvedMethod` is a poor answer to a common name.
- Sys, web, aiml: the E0301 fix must land before `llms-full.md` shows a `map` example. Until then the table lists `map` and the reference has no runnable example for it. Track the gap so it closes.
- Aiml: the drift check covers only the `Option` and `Result` tables. Other reference tables, such as the builtins, can still drift.
