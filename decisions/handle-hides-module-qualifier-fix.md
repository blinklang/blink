[< All Decisions](../DECISIONS.md)

# The E0505 Fix When a Handle Hides the Module Qualifier — Design Rationale

Section 4.4.7 gives a fixed list of four candidates for the fix of an E0505 where a module function is called
through an effect handle. A later paragraph of §4.4 said that, when a reserved handle has the same spelling as a
module qualifier, the fix is an alias. The two texts did not agree. This ruling makes the walk of §4.4.7 apply with
no exception for a handle, and it says where the new import line goes when the file already imports the module.

## Summary

| Q | Question | Result | Vote |
|---|---|---|---|
| Q1 | When the file already has `import util.log` (no `as`), what does candidate 3 do? | Add: a new line `import util.log.{format}` goes after the existing import, and the call becomes `format("x")`. The existing line does not change. | 6-0 after Phase D (Phase C: rewrite 5-1, PLT for add) |
| Q2 | The edit when the existing import is `pub import util.log` | Moot under add: a private line is added, and the public API does not change. Phase C had voted 6-0 for a private added line in case rewrite won. | 6-0 (Phase C) |

Shared by all six seats, and not put to a vote:

- Option (a): the walk applies with no handle exception. Candidate 1 fails, because the handle hides the qualifier.
  Candidate 2 fails condition 1. Candidate 3 passes. Option (b), that a handle blocks candidates 2 and 3, is rejected.
- The paragraph "A handle wins over a module qualifier" stops naming the alias as the fix and points to the walk.
- The sentence "Only a local binding named `random`" widens to a local binding or a reserved handle that hides the
  qualifier at the call.
- The rule is not specific to handles: one rule serves every help that says a name is a function in a module.
- With `log.record("y")` in the same body, the fix rewrites only the failing call. `log.record` stays a handle call.
- With `format` already bound, candidate 3 fails and candidate 4 applies: no `fix:`, a help that names the blocking
  binding and its position, and an alias example on a new import line.
- When candidate 3 passes, the diagnostic has no extra alias `help:` line.
- `logging` is an example name only. The rule that picks an alias name is not part of this ruling.

The panel took four rounds: independent proposals (Phase A), one round of debate (Phase B, all six seats said
stable), a silent vote (Phase C), and a focused re-vote on Q1 after the moderator gave a spec fact (Phase D).

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated in
independent-proposal, debate, vote rounds. The ticket, verbatim:

> Title: "E0505 module-fn fix when a handle hides the qualifier: selective-import fix or alias help
> only?"
>
> "sections/04_effects.md §4.4.7 (commit 70d8f154) gives a fixed candidate list for E0505 when a
> module function is called through an effect handle: (1) reuse a binding, (2) import M + M.f(...),
> (3) import M.{f} + f(...), (4) help only with an alias example. P4: one rule for every "X is a
> function in module M" help. It also says "Only a local binding named random at the call ... lets
> candidate 3 meet the conditions". But 04_effects.md ~4460 ("A handle wins over a module qualifier")
> says that for
> ```
> import util.log
> fn f() ! Log { log.format("x") }
> ```
> the diagnostic names the alias fix, import util.log as logging. Under the candidate walk, candidate
> 3 (import util.log.{format} + format("x")) rebinds the qualifier log to the same module (no E1005)
> and the callee resolves, so it passes: the walk gives a selective-import fix, not the alias fix, and
> the "only a local" sentence is false for the handle case. Question: (a) the walk applies, candidate
> 3 is the fix, ~4460 changes; (b) a handle that hides the qualifier blocks candidates 2 and 3 (help
> only, alias example), and §4.4.7 says so; (c) other. Found by the spec writer; the panel did not
> rule on it."

The text below is each panelist's own text, copied without change.

#### Phase A — Independent proposals

Each seat worked alone. The full text of each proposal:

- **Systems** (`A/sys.md`):

> # Systems seat, Phase A
>
> **Rank 1: (a). The walk applies. A handle that hides the qualifier is one more kind of hiding binding. Candidate 3 is the fix. ~4460 changes. The "only a local" sentence in §4.4.7 widens to "a local or a reserved handle".**
>
> ## Check of the ticket's claim
>
> I checked it. Candidate 3 adds no E1005. decisions/selective-import-qualifier-collision.md Q-S1 (6-0): "a qualifier bound again to the same module gets no E1005 and no W0602". `import util.log.{format}` binds `log` to `util.log` again, so the table does not change. The candidates for `log.format("x")` in `fn f() ! Log`:
>
> 1. Reuse: `import util.log` exists, but its qualifier does not resolve at the call, because the handle wins (§3c.4). Fails.
> 2. Qualified call: the same import again. `log.format` is still the handle. Fails condition 1.
> 3. Selective: `format` is free, the `log` rebind is a no-op, and `format("x")` resolves to `util.log.format`. Passes.
>
> So the ticket is right. A handle hides the qualifier the same way a local `random` does. The difference is that the handle is reserved for the whole function and not for a block.
>
> ## Proposal A1 (rank 1): the walk, with candidate 3 editing the import line
>
> ```blink
> import util.log
>
> effect Log {
>     fn record(msg: Str)
> }
>
> fn f() -> Str ! Log {
>     log.format("x")
> }
> ```
>
> ```
> error[E0505]: `format` is not an operation of effect `Log`
>   = note: `Log` operations are `record`
>   = help: `format` is a function in module `util.log`; `log` is the handle of `Log` here, and the handle hides the module qualifier `log` (import at 1:8)
>   = fix: change `import util.log` to `import util.log.{format}` and call `format("x")`
> ```
>
> After the fix the file compiles with no new output. `f` calls `util.log.format`.
>
> One change to the shape of the edit: when the file already has `import M` (whole) and the walk reaches candidate 3, the edit extends that line and does not add a second line. A selective import binds its qualifier (§10.1), so every other `log.x(...)` in functions that do not declare `Log` still resolves the same way. Why I want this:
> - One import line per module. Fixes in one pass compose (`import util.log.{format, parse}`), and applying them again changes nothing.
> - If the module was imported only for this call, an added line would leave the old entry unused (W0602). The edit removes it.
>
> **With a real handle op in the same body:**
>
> ```blink
> fn g() -> Str ! Log {
>     log.record("y")
>     log.format("x")
> }
> ```
>
> `log.record("y")` is a handle op and stays as it is. Only the `format` call gets E0505 and the same fix. After the fix: `log.record("y")` and `format("x")`. It compiles.
>
> **When `format` is already bound:**
>
> ```blink
> import util.log
>
> fn format(s: Str) -> Str { s }
>
> fn f() -> Str ! Log {
>     log.format("x")
> }
> ```
>
> Candidate 3 gives E1012 (`fn format` takes a name that the import binds). A local `let format = ...` fails condition 1, because `format("x")` would resolve to the local. Candidate 4, with no `fix:` line:
>
> ```
>   = help: `format` is a function in module `util.log`; `log` is the handle of `Log` here, and the handle hides the module qualifier `log` (import at 1:8). `format` is the function at 3:4, so `import util.log.{format}` would bind it twice
>   = help: import it under another name and call through that name: `import util.log as logging`, then `logging.format("x")`
> ```
>
> This is the ~4460 text, kept for the case where it is correct.
>
> ## Proposal A2 (rank 2): A1 plus a second help line when candidate 3 passes
>
> When candidate 3 passes, add one help line after `fix:`: "in each function that declares `Log`, `log` is the handle; to keep calls qualified, import it under another name: `import util.log as logging`". This is help only. The tool does not apply it. It tells the user about the trap for the whole file without making up an alias. Cost: one more golden.
>
> ## Rank 3, oppose: (b), help only when a handle hides the qualifier
>
> (b) gives no fix for a case where a fix passes both conditions. It also needs a special case in the checker ("is the hiding binding a handle?") and a branch in the spec rule that P4 says is one rule. More code, more goldens, more output shapes. (a) needs no new mechanism: the resolver already knows that the handle wins at the call, because that is why E0505 fires.
>
> ## Tradeoffs (Systems)
>
> - Runtime: none. Every form compiles to the same direct call of `util.log.format`. The handle form is never in the codegen for this call. The only cost is in the tool.
> - Predictability: (a) keeps the fix a pure function of the resolver's tables at the error site: the scope chain, the handle set from the `!` row, and the import table. This is the same lookup as for the local `random` case. A rule that names the kind of the hiding binding is one more input, and one more way for the fix code to be wrong.
>
> ## Cross-language note
>
> Rust and Go have no reserved handle namespace, so they have no such case. The closest is a Go local that hides a package name (`log := ...` then `log.Printf`). Go reports only "log.Printf undefined" and offers no fix. That is the gap that (b) leaves open, in a case where a correct fix exists.

- **Web/Scripting** (`A/web.md`):

> # Web/Scripting seat: Phase A
>
> ## Position: (a). The walk applies. Candidate 3 is the fix. ~4460 changes.
>
> A Python dev learns one sentence: "when the tool says X is a function in module M, it tries reuse, then
> `M.f`, then `{f}`, then tells you to alias." A second rule that turns on whether the handle and the
> qualifier share a spelling is a rule people find by accident. I do not want that.
>
> I checked the E1005 claim. decisions/selective-import-qualifier-collision.md Q-S1 (6-0): "a qualifier
> bound again to the same module gets no E1005 and no W0602". `import util.log.{format}` binds `log` to
> `util.log` again, so the table does not change. The ticket is right: candidate 3 passes.
>
> ## P1 (rank 1): run the walk; the help names the handle that hides the module
>
> The handle is one more binding that hides the qualifier at the call, the same as a local `random`.
> So the "Only a local binding" sentence widens to "a local binding or a reserved handle". The help
> line uses the same pattern as the local case and gives the position of the effect in the row:
>
> ```blink
> import util.log
>
> effect Audit {
>     effect Log {
>         fn record(msg: Str)
>     }
> }
>
> fn f() -> Str ! Audit.Log {
>     log.format("x")
> }
> ```
>
> ```
> error[E0505]: `format` is not an operation of effect `Audit.Log`
>   = note: `Audit.Log` operations are `record`
>   = help: `format` is a function in module `util.log`; `log` is the handle of `Audit.Log` (from `! Audit.Log` at 9:17) and it hides the module `util.log` in this function
>   = fix: add `import util.log.{format}` and call `format("x")`
> ```
>
> Candidate 1 fails (the qualifier does not resolve at the call). Candidate 2 fails (the file already
> imports `util.log`, and `log.format` is still the handle). Candidate 3 passes. After the fix, `f`
> compiles and prints nothing new. If the file has no other `log.` use outside effect functions, the
> old `import util.log` was already W0602 before the edit, so condition 2 ("no new warning") holds.
>
> **A real handle op in the same body.** The fix does not touch it:
>
> ```blink
> fn g() -> Str ! Audit.Log {
>     log.record("y")
>     log.format("x")      // E0505, same help, same fix
> }
> ```
>
> After the fix: `log.record("y")` stays a handle call, `format("x")` is the module call. It compiles.
>
> **`format` already bound.** Candidate 3 fails (E1012 for `fn format`, E1005 for
> `import other.{format}`, wrong callee for `let format`). Candidates 1 and 2 fail as above. So
> candidate 4, and this is exactly what ~4460 shows today:
>
> ```blink
> import util.log
>
> fn format(s: Str) -> Str { s }
>
> fn f() -> Str ! Audit.Log {
>     log.format("x")
> }
> ```
>
> ```
>   = help: `format` is a function in module `util.log`; `log` is the handle of `Audit.Log` (from `! Audit.Log` at 5:17) and it hides the module `util.log` in this function. `format` is the function at 3:4
>   = help: import it under another name and call through that name: `import util.log as logging`, then `logging.format("x")`
> ```
>
> So ~4460 is not wrong about the alias; it is wrong to say the alias is THE fix. Change ~4460 to: the
> handle wins, and the diagnostic follows the §4.4.7 walk, with the alias as help when no candidate
> passes. Show both outcomes there, short, or point to §4.4.7.
>
> ## P2 (rank 2): P1 plus one alias `help:` line when spelling is the same
>
> The same-spelling case differs in one way that matters to users: the hide repeats in EVERY function
> that declares `Log`. Candidate 3 fixes this call; the next `log.parse(...)` in another `! Log`
> function gets E0505 again, and the user grows `{format, parse, ...}` one error at a time. An extra
> `help:` line (no fix, author picks the name) that says "`log` names the handle in each function
> that declares `Log`; to call the module as a qualifier there, alias it: `import util.log as
> logging`" saves that loop. The fix stays candidate 3. This adds a help line, not a fifth candidate,
> so the fixed list holds. I rank it below P1 because it is a second shape of help text, and the walk
> alone already gives a working program.
>
> ## Reject (b)
>
> (b) blocks candidates 2 and 3 only because the handle spells the same as the qualifier. That makes
> the user lose a machine-applicable fix that compiles, and the tool hands them a naming decision for
> a one-line problem. Same-spelling is the common case (effect `Log`, module `log`; effect `Db`,
> module `db`), so (b) makes the common case the worst one.
>
> ## Tradeoffs
>
> - P1: one rule, one fix path, fewest Stack Overflow questions ("why did it alias here but not
>   there?"). Cost: the user may not learn that `log.` means the handle in every `! Log` function
>   until the second error. P2 pays for that.
> - The help line must say "handle" and "hides". "no member `record` on module `log`" (today's gen1)
>   is the opposite confusion and must go with the bug fix.
> - Worry for a writer: W0602 on `import util.log` next to the E0505 reads as "unused?? I call it!".
>   Its text should name the handle that hides the qualifier (§10.6 diagnostics that involve a
>   shadowing name). Not a vote; a friction note.
>
> ## Cross-language
>
> TypeScript and Python: a local `log` that hides an imported `log` gives no hint at all; you get
> "format is not a function on Logger". Kotlin's quick fix does what P1 does: it adds an explicit
> import of the function, not an alias. Users from all four expect the tool to add the import.

- **PLT** (`A/plt.md`):

> # PLT seat, Phase A
>
> ## Check of the ticket's claim
>
> I checked it against decisions/selective-import-qualifier-collision.md, and the claim is true. Q-S1 (6-0) says "a qualifier bound again to the same module gets no diagnostic", and a selective import's qualifier never gets W0602. W0602 goes only to a listed name that already imports its item. So `import util.log.{format}` next to `import util.log` binds `log` to the module it already names. That gives no E1005 and no W0602. `format` is new, so it gets no W0602 either.
>
> The walk on the ticket's case:
> - **C1** fails. Bare `format` is not bound. The file imports `util.log`, but its qualifier does not resolve at the call, because the handle wins (§3c.4).
> - **C2** fails condition 1. The import is already there, so the edit is only the call rewrite, and `log.format` is still the handle.
> - **C3** passes. `format("x")` resolves to `util.log.format`, and nothing new is reported.
>
> ## Proposal 1 (rank 1): (a). The walk applies, C3 is the fix, and ~4460 changes
>
> ```blink
> import util.log
> effect Audit {
>     effect Log {
>         fn record(msg: Str)
>     }
> }
> fn f() -> Str ! Audit.Log { log.format("x") }
> ```
> ```
> error[E0505]: `format` is not an operation of effect `Audit.Log`
>   = note: `Audit.Log` operations are `record`
>   = help: `format` is a function in module `util.log`; `log` is the handle of `Audit.Log` here, and the handle hides the module qualifier `log` (the import at 1:8)
>   = fix: add `import util.log.{format}` and call `format("x")`
> ```
> After the fix, the file compiles with no output. The fix also works when the body calls a real op:
>
> ```blink
> fn f() -> Str ! Audit.Log {
>     log.record("y")
>     format("x")        // after the fix
> }
> ```
> The edit changes one callee and adds one import line. `log.record("y")` stays a handle op. Bare `format` cannot collide with an op, because an op has only the handle call form (§3c.4). It compiles clean.
>
> When `format` is already bound (`fn format(n: Int) -> Int { n }` in the file, or `import fmt.{format}`), C3 gives E1012 or E1005. That is C4, with help only:
> ```
>   = help: `format` is a function in module `util.log`; `log` is the handle of `Audit.Log` here, and the handle hides the module qualifier `log` (the import at 1:8). `format` is the function at 2:4, so `import util.log.{format}` would bind it twice
>   = help: import it under another name and call through that name: `import util.log as logging`, then `logging.format("x")`
> ```
> The alias text from ~4460 lives on in this branch only.
>
> **Why the walk wins, in PLT terms:**
> 1. **One judgment.** The walk is a decision procedure over the resolver: it tries an edit and keeps it when the edit is resolution-checked. A handle is one more binder that hides a qualifier. Condition 1 already sees it (C1 and C2 fail), and C3 survives because the module-level `log` already names the same module. A special case for handles would be a second rule. It would also give a worse answer to a question that the general rule answers soundly.
> 2. **The alias is not a local edit.** `import util.log as logging` takes away the `log` qualifier from the whole file. Each `log.format` in a function without the effect, where `log` correctly names the module, then breaks. A machine-applicable alias fix must rewrite every module use in the file. That is why the walk keeps the alias as help only. Under (b) it would be the main answer in exactly the case where it is non-local.
> 3. **Soundness of C3 here.** The rebinding is a no-op in the module table (Q-S1: "the table does not change"). The new name `format` is checked by condition 2. No new reasoning is needed.
>
> **Required text fix in §4.4.7.** The sentence "Only a local binding named `random` at the call ... lets candidate 3 meet the conditions" is false. The correct condition: C3 can pass only if (i) a binder inside the call's scope hides the qualifier at the call, either a local or a reserved handle (§3c.4), and (ii) at module level the qualifier is free or already names the module. In the `rand` case (ii) holds because `random` is free. In the `log` case it holds because `log` already names `util.log`. Give ~4460 a cross-reference to the walk in place of its fixed alias claim.
>
> **Gap to name for the writer.** C4 says the example alias is "not bound in the file", but only `rng` is given. For a general module M, the rule that picks the name (here `logging`) is not stated. That rule must be deterministic so that the output is stable for tests and tools. This is a small gap and a separate one, but it is visible now that C4 serves every module.
>
> ## Proposal 2 (rank 2, I oppose it): (a) plus an alias help line every time a handle hides the qualifier
>
> The reason someone could want it: the hiding comes back in each function that declares `! Audit.Log`. Against it: it breaks P4 (one rule for every "function in module M" help), and it suggests a file-wide edit as an extra to a fix that already works. Rank 3 is (b).
>
> ## Cross-language note
>
> In OCaml and Haskell, hiding goes by lexical scope. The usual fix for a name that is hidden is an explicit import list or a qualified path, an edit at the call or at one import. A module rename (`import qualified M as N`) is a choice that the author makes for the whole file. That matches C3 as the fix and the alias as help only.

- **DevOps/Tooling** (`A/devops.md`):

> # DevOps seat, Phase A
>
> ## Check of the ticket's E1005 claim
>
> decisions/selective-import-qualifier-collision.md Q-S1 (6-0) and §10.5 (07_trust ~3911): a selective
> import that binds a qualifier again to the SAME module gets no E1005 and no W0602. So
> `import util.log.{format}` next to `import util.log` is clean. The ticket is right: candidate 3
> passes, and the "only a local" sentence is false for a same-spelling handle.
>
> ## Proposal D1 (my pick): option (a). The walk applies; candidate 3 is the fix; ~4460 changes
>
> Walk for the ticket's case:
> 1. Reuse: bare `format` is not bound; the qualifier `log` exists but the handle hides it. Fails.
> 2. Qualified call: `log.format("x")` is still the handle. Fails condition 1, always, when the handle
>    and the qualifier have one spelling.
> 3. Selective import: callee resolves to `util.log.format`, no new diagnostic. Passes.
>
> One tooling detail: when the file already has a whole import of M, candidate 3 REWRITES that line
> (`import util.log` -> `import util.log.{format}`). It does not add a second line. The rewrite binds
> the same `log` qualifier, so no other use in the file changes meaning, and the file does not keep
> two import lines for one module (and no unclear "is the whole import now unused?" W0602 case).
>
> ```blink
> import util.log
>
> effect Audit {
>     effect Log {
>         fn record(msg: Str)
>     }
> }
>
> fn f() -> Str ! Audit.Log {
>     log.format("x")
> }
> ```
>
> ```
> error[E0505]: `format` is not an operation of effect `Audit.Log`
>   = note: `Audit.Log` operations are `record`
>   = help: `format` is a function in module `util.log`; in this function `log` is the handle of `Audit.Log`, and it hides the module qualifier `log`
>   = fix: change `import util.log` to `import util.log.{format}` and call `format("x")`
> ```
>
> After the fix: compiles, prints nothing.
>
> **Same body also calls a real op.** The fix rewrites only the failing call. `log.record("y")` stays a
> handle call. After the fix: compiles, prints nothing.
>
> ```blink
> fn g() -> Str ! Audit.Log {
>     log.record("y")
>     format("x")
> }
> ```
>
> **`format` already bound** (`fn format` in the file, `import text.{format}`, or a local `format`;
> the `Audit` declaration is as above and left out).
> Candidate 3 gives E1012, E1005, or a callee that resolves to the local. No candidate passes.
> Candidate 4: help only, with the alias. The alias is a NEW line, not a rename of the existing
> import, so `log.x` module calls in functions without `! Audit.Log` keep working.
>
> ```blink
> import util.log
>
> fn format(s: Str) -> Str { s }
>
> fn f() -> Str ! Audit.Log {
>     log.format("x")
> }
> ```
>
> ```
> error[E0505]: `format` is not an operation of effect `Audit.Log`
>   = note: `Audit.Log` operations are `record`
>   = help: `format` is a function in module `util.log`; in this function `log` is the handle of `Audit.Log`, and it hides the module qualifier `log`. `format` is the function at 3:4, so `import util.log.{format}` would bind it twice
>   = help: import it under another name and call through that name: `import util.log as logging`, then `logging.format("x")`
> ```
>
> Spec edits that follow: ~4460 says the help names the selective-import fix, and the alias only when
> that fails. §4.4.7 says a local OR a same-spelling handle in scope at the call can let candidate 3
> pass. The help text for the same-spelling case must say "hides", because "`log` is the handle and
> `log` is the module" reads as nonsense.
>
> ## Proposal D2 (I reject it): option (b), help only whenever a handle hides the qualifier
>
> P4 exists so a tool computes the fix with one resolver walk. (b) adds a special case to drop a fix
> that the walk proves correct. The user gets help with no text to apply, and the alias they type by
> hand is a bigger edit (a new name at every call site). Worse surface, no gain in correctness.
>
> ## Tradeoffs (tooling)
>
> - D1 is one code path in the checker and the LSP code action: run the four candidates, take the
>   first that passes. The test matrix is the same as the `rand` cases, plus one row for "handle has
>   the qualifier's spelling".
> - Risk: the rewrite of a whole import into a selective import must keep any `as` alias
>   (`import util.log as l` -> `import util.log as l.{format}`). With an alias, candidate 1 already
>   passes (`l.format("x")`), so this path only runs on an un-aliased import. A test pins it.
> - The LSP hover on `log` inside an effect function must show "handle of `Audit.Log`", not the module,
>   so the user sees the hide before they read the error.
>
> ## Cross-language note
>
> Go: a local that shadows a package name gives a compile error at the call, and gopls offers no
> fix; authors rename the import by hand (`logpkg "util/log"`). rust-analyzer offers "import this
> item" before any rename. D1 matches the rust-analyzer order: a correct import edit first, a name the
> author must pick last.

- **AI/ML** (`A/aiml.md`):

> # AI/ML seat, Phase A
>
> ## Check of the ticket's claim
>
> decisions/selective-import-qualifier-collision.md Q-S1 (6-0): "a qualifier bound again to the same module gets no E1005 and no W0602; W0602 only for a duplicate listed item". So `import util.log` + `import util.log.{format}` binds `log` twice to one module: no E1005, no W0602. The ticket is correct. Walk for `log.format("x")` in a `! Audit.Log` fn:
>
> - C1: bare `format` is not bound; the qualifier `log` does not resolve at the call (the handle wins). Fail.
> - C2: `log.format(...)` is the handle again. Fail (condition 1).
> - C3: `import util.log.{format}` + `format("x")` resolves to `util.log.format` with no new diagnostic. Pass.
>
> The handle hides the qualifier in the same way as `let random = 7`: a binding that is not at module level and that covers the call. The "only a local" sentence is false.
>
> ## Proposal P1 (rank 1): option (a). The walk applies with no exception; ~4460 changes
>
> ### Behavior
>
> ```blink
> import util.log
>
> effect Audit {
>     effect Log {
>         fn record(msg: Str)
>     }
> }
>
> fn f() -> Str ! Audit.Log {
>     log.format("x")
> }
> ```
>
> ```
> error[E0505]: `format` is not an operation of effect `Log`
>   = note: `Log` operations are `record`
>   = help: `format` is a function in module `util.log`; in this function `log` is the handle of `Log`, and it hides the module qualifier `log`
>   = fix: add `import util.log.{format}` and call `format("x")`
> ```
>
> After the fix, the file compiles with no new output. The fix is the same if the file has no `import util.log`. The added import binds `log` at module level, and the handle hides it in `f` only.
>
> A real handle op in the same body. The fix rewrites only the failed call. `log.record` stays a handle call:
>
> ```blink
> fn g() -> Str ! Audit.Log {
>     log.record("y")
>     log.format("x")
> }
> ```
>
> Same `help` and `fix`. After the fix: `log.record("y")` and `format("x")`. That compiles.
>
> `format` is already bound (`fn format(n: Int) -> Int { n }`, a local `format`, or `import text.{format}`). C3 fails (E1012, E1005, or the callee resolves to the other `format`). C4: help only:
>
> ```
> error[E0505]: `format` is not an operation of effect `Log`
>   = note: `Log` operations are `record`
>   = help: `format` is a function in module `util.log`; in this function `log` is the handle of `Log`, and it hides the module qualifier `log`. `format` is the function at 3:4, so `import util.log.{format}` would bind it twice
>   = help: import it under another name and call through that name: `import util.log as logging`, then `logging.format("x")`
> ```
>
> The alias help says *add* the import. It does not say "rename the existing import", because other functions in the file can use `log.format` as a module call. (Writer check: that `import util.log` + `import util.log as logging` is legal with no warning. Two names for one module is not the Q-S1 case.)
>
> ### Spec edits (behavior only)
>
> - §4.4.7: the sentence that names what lets C3 pass covers each binding that hides the qualifier at the call and is not at module level: a local, or a reserved handle (§3c.4). It gets one example for each.
> - ~4460: "names the fix" becomes the walk (C3 when the name is free, the alias help when it is not).
> - The help text: when the handle and the qualifier have the same spelling, the help says "hides the module qualifier `log`", not "`log` is the handle and `log` is the module".
>
> ### Tradeoffs (AI/ML)
>
> - **One rule, no exception.** A model that reads §4.4.7 and §10.1 derives C3 for this case. Option (b) adds a spec sentence that contradicts what the rule itself gives. A model then has two sources that disagree, and it picks one at random.
> - **Fewer decision points.** C3 is one line and a shorter call. The alias help makes the model choose a name, and the model copies `logging` into every file. With no `fix:`, an agent loop has no edit it can apply, so it tries edits until one compiles.
> - **Same spelling is the risk.** In `rand`/`random` the two names differ. In `log`/`log` the model cannot see from the text which `log` the call uses. The help must say "hides". Without that, a model reads E0505 as a compiler bug and tries `log.format` again.
> - **Token cost.** C3: about 10 tokens added. The alias: one import plus a changed call, and a name to pick.
>
> ## Proposal P2 (rank 2): P1, and C3 extends an existing import of M
>
> When the file has `import util.log` (whole, no list), the C3 fix changes that line to `import util.log.{format}`, not adding a second line. Both bind the same names (a selective import binds its qualifier), so the conditions are the same. It gives one import line per module, which is what models see most in training data. Cost: a second edit shape in the fix code. Q-S1 said the formatter merges lines, so I rank this below P1.
>
> ## Option (b): reject
>
> It blocks a fix that the panel's own check proves correct. It also makes "handle" a special case in a rule that the panel made to be data.
>
> ## Cross-language
>
> Python: `import random` and then `random = 7` in a function hides the module; the usual fix is `from random import shuffle`. That is C3, and models already know that shape well.

- **Minimalism** (`A/min.md`):

> # Min seat, Phase A
>
> ## Vote: (a). The walk applies, with no new case. Delete the fix claim at ~4460.
>
> The walk is the one rule for every "X is a function in module M" help. (b) adds a second rule
> ("a handle that hides the qualifier blocks 2 and 3") that the walk already gives for candidate 2,
> and that is wrong for candidate 3. A rule that restates part of another rule and contradicts the rest is
> pure cost. The fix is to remove text, not add it.
>
> ### Check of the ticket's facts (I did not take them on trust)
>
> For `import util.log` + `fn f() -> Str ! Audit.Log { log.format("x") }`:
>
> - Candidate 1: the file imports `util.log`, but its qualifier does not resolve at the call (the
>   handle wins, §3c.4). Fails.
> - Candidate 2: `import util.log` again. `log.format` is still the handle, so condition 1 fails.
>   (It also gets W0602, "a whole-module import whose qualifier already names its module".) Fails.
> - Candidate 3: `import util.log.{format}`. Per decisions/selective-import-qualifier-collision.md,
>   "a qualifier bound again to the same module gets no diagnostic", so no E1005 and no W0602.
>   `format` resolves to `util.log.format`. Passes.
>
> So the ticket is correct. Candidate 3 is the fix, and ~4460 and the "Only a local binding" sentence are
> both false.
>
> ### Behavior
>
> ```blink
> import util.log
>
> effect Audit {
>     effect Log {
>         fn record(msg: Str)
>     }
> }
>
> fn f() -> Str ! Audit.Log {
>     log.format("x")
> }
> ```
>
> ```
> error[E0505]: `format` is not an operation of effect `Audit.Log`
>   = note: `Audit.Log` operations are `record`
>   = help: `format` is a function in module `util.log`; `log` is the handle of `Audit.Log`, and in this function the handle hides the module `log`
>   = fix: add `import util.log.{format}` and call `format("x")`
> ```
>
> After the fix: it compiles. Nothing new prints. `import util.log` keeps whatever W0602 status it
> had before. If its only use was that call, it was already unused, so the warning is not new.
>
> The function also calls a real op:
>
> ```blink
> fn g() -> Str ! Audit.Log {
>     log.record("y")
>     log.format("x")
> }
> ```
>
> Same diagnostic and fix, on the `format` call only. `log.record("y")` is untouched and still calls
> the handle. After the fix, `g` compiles.
>
> `format` is already bound in the file:
>
> ```blink
> import util.log
>
> fn format(s: Str) -> Str { s }
>
> fn f() -> Str ! Audit.Log {
>     log.format("x")
> }
> ```
>
> Candidate 3 adds E1012 and fails, so this is candidate 4. There is no `fix:` line:
>
> ```
>   = help: `format` is a function in module `util.log`; `log` is the handle of `Audit.Log` at 5:17, so `log.format` is not available here; `format` is the function at 3:4
>   = help: import it under another name and call through that name: `import util.log as logging`, then `logging.format("x")`
> ```
>
> The alias example is the help that ~4460 gives. ~4460 is correct only for this case.
>
> ### Spec edits (the writer picks the words)
>
> 1. ~4460: keep "a handle wins over a module qualifier". Replace "The diagnostic that follows names
>    the fix: give the import an alias" with a pointer: the E0505 help and fix follow §4.4.7. The
>    section must not restate the walk.
> 2. §4.4.7: change "Only a local binding named `random` at the call" so that it names any binding
>    that hides the qualifier at the call with no module-level binding of its own. That is a local,
>    or a reserved handle of the same spelling. Add the `log` case as one example next to the
>    `let random = 7` example. It is the same walk, with one more input that hides the name.
> 3. Catalog E0505: no change. The row already says "first of four candidates".
>
> ### Tradeoffs
>
> - For (a): one rule, and the spec gets shorter. Tools and LLMs learn one walk. The selective fix
>   needs one free name (`format`), and the alias fix needs one that the author must choose. The walk
>   already prefers the fix that needs no invented name.
> - Against (a): the file then holds `import util.log` and `import util.log.{format}`, and `log` is
>   the handle inside effect functions and the module outside them. That is legal and has no
>   warning. If it is confusing, the cause is §3c.4 shadowing, which is already decided. A special
>   rule in the fix walk does not cure it.
> - Against (b): a rule exists only to keep a sentence that was never checked against the walk. The
>   next "hides the qualifier" source (for example, a future binding form) would need a third rule.
>
> ### Open edge (not a vote)
>
> The candidate-4 example name has a rule only for `std.random` (`rng`). For `util.log`, nothing says
> where `logging` comes from. The compiler needs a deterministic picker. If there is a gap, a
> separate ticket must close it. Do not add a picker here.
>
> ### Cross-language
>
> rustc's E0425 suggests `use util::log::format;` before it suggests a rename. It prefers to import
> the item, and it never invents a name. This matches the walk.


#### Phase B — Debate, round 1

All six seats said STABLE after this round.

- **Systems** (`B/r1_sys.md`):

> # Sys, Phase B round 1
>
> ## V1: I move from V1-rewrite to V1-add
>
> I claimed that the rewrite composes. Read again, it does not. Take one `blink fix` pass with two E0505s in one file, `log.format("x")` and `log.parse("y")`:
>
> - **V1-rewrite:** both fixes edit the same span (`import util.log`). Edits that overlap conflict in a batch apply (LSP `WorkspaceEdit`, `blink fix`). The tool then needs merge logic so that the result is `import util.log.{format, parse}`. If it inserts `.{format}` at one point twice, the result is `import util.log.{format}.{parse}`, which does not parse.
> - **V1-add:** each fix is a pure insertion of its own line. The fixes do not depend on order, need no merge code, and each one is checked by the walk on its own:
>
> ```blink
> import util.log
> import util.log.{format}
> import util.log.{parse}
> ```
>
> Q-S1 says these lines give no E1005 and no W0602. If the whole import was used only by these calls, its W0602 was there before the edit, so it is not new (min). Merging the lines is the formatter's job (DevOps in Q-S1).
>
> So V1-add is less fix code, has no conflict case, and uses the same edit shape as the `rand` case, where the walk also adds a line. My one-line-per-module point is a style point, and the formatter covers it. I concede.
>
> ## V2: V2-no. I withdraw A2
>
> plt is right. A help line that shows only when the handle has the qualifier's spelling is a second help shape inside P4, which is one rule. It also suggests a file-wide edit next to a fix that already works. web's case (one E0505 for each `! Log` function) needs no extra line. Each new call gets its own E0505 and an added line. That cost is a few more fix rounds, and the result is always correct.
>
> ## Alias-name gap: not on this ballot
>
> The gap is real. Candidate 4 has a rule for every module M, but only `std.random` has an example name (`rng`). The picker must be deterministic, so that goldens and tool output stay the same from run to run. This is a separate gap, and it was there before this ticket, for every module that is not `std.random`. File a ticket. Until then, the writer can use `logging` as the example name in the ~4460 text, as one example only.
>
> ## Writer notes
>
> - In the help, give the import's position (`import at 1:8`). The import is the binding that is hidden, and the walk's rule is that the help names the blocking binding and its position. The `!` row is where the handle comes from, so it is a second fact. Put it in the help only if the line stays short.
> - In the help, say "hides". Do not write "`log` is the handle and `log` is the module".
>
> STABLE: ready to vote

- **Web/Scripting** (`B/r1_web.md`):

> # Web seat, Phase B round 1
>
> ## V1: I move to V1-rewrite, with one guard
>
> Sys and devops convinced me. A Python dev writes `from util.log import format, parse`, which is one
> line per module. Two lines for one module (`import util.log` plus `import util.log.{format}`) looks
> like a mistake, and the next person "cleans it up". The rewrite also composes: each later fix adds
> one name to the same list, and running a fix again changes nothing. The meaning stays the same
> because a selective import binds its qualifier, so every `log.x` module call outside `! Log`
> functions resolves as before.
>
> Guard (new, please put it on the ballot as part of V1-rewrite): rewrite only a private whole
> import. A `pub import util.log` re-exports the module. Turning it into `pub import util.log.{format}`
> would also re-export `format`, which changes the public API of the file. For `pub import`, the fix
> adds a private line:
>
> ```blink
> pub import util.log
>
> fn f() -> Str ! Audit.Log {
>     log.format("x")
> }
> ```
>
> ```
>   = fix: add `import util.log.{format}` and call `format("x")`
> ```
>
> The private rewrite case:
>
> ```
>   = fix: change `import util.log` to `import util.log.{format}` and call `format("x")`
> ```
>
> After either fix, the file compiles and prints nothing new.
>
> Devops's alias point holds too. The rewrite keeps `as` (`import util.log as l.{format}`), although
> candidate 1 usually passes first in that case.
>
> ## V2: I concede, V2-no
>
> PLT is right that the extra line is a second shape of help text for one rule. With V1-rewrite, the
> "grows one error at a time" cost is one fix per name, and each fix needs one key press. The
> 90%-case user gets a working program from the fix alone. I drop P2.
>
> ## Alias-name gap: not on this ballot
>
> I agree with min: file a separate ticket. The picker rule touches every candidate-4 help, not only
> handles. This ticket can ship with `logging` as the example in the spec text.
>
> ## Writer notes
>
> - "hides" must appear in the help (devops, aiml). It must not read "`log` is the handle and `log`
>   is the module".
> - Position: I gave the position of the effect in the row, and sys and plt gave the position of the
>   import. I do not mind which one, but the help gives one position, not two. The row position is
>   the cause the user can see, so I lean that way.
> - The W0602 text on a dead `import util.log` (only in the V1-add path; V1-rewrite removes the case)
>   should name the handle.
>
> STABLE: ready to vote

- **PLT** (`B/r1_plt.md`):

> # PLT seat, Phase B round 1
>
> ## V1: V1-add. V1-rewrite is my rank 2. This is a weak preference, not a soundness point.
>
> Both edits give the same binding environment at module level: `{log -> util.log, format -> util.log.format}`. So the two conditions give the same result for both, and neither is more correct. The choice is about the shape of the edit:
>
> - **Add is monotone.** Adding an import line that passes condition 2 never changes what another name in the file means. This can be checked at the one line. The decided C3 text says "Add `import M.{f}`", so add keeps the decided walk as it is.
> - **Rewrite needs a merge rule that nobody has given yet.** Which line gets the rewrite when there are two imports of M? An `import util.log.{parse}` merges into `{parse, format}`. An `import util.log as l` never reaches C3, because C1 passes. Each of these is a new edit shape with its own goldens. Q-S1 already said that merging lines is the formatter's job.
> - **The sys W0602 argument does not hold.** min is right: if the call was the only use, `import util.log` was already unused before the edit, because `log.format` was the handle. So add gives no new warning.
> - **The idempotence argument holds for both.** A second fix adds `{parse}` or extends the list. Both reach a fixed point, and neither gives a diagnostic.
>
> If V1-rewrite wins, it must apply to every C3 when the file already imports M, and the `std.random` local case is one of these. It must not be specific to handles, or we have two rules again.
>
> ## V2: V2-no. No change.
>
> web's loop is finite: each later `log.parse` in a `! Log` function gets its own C3 fix, and the fixes converge. An alias line as an extra to a fix that works offers a file-wide rename as an option. That breaks P4 without any gain in correctness.
>
> ## Alias-name gap: not on this ballot
>
> I concede to min. A separate ticket must close it. One requirement for the writer: ~4460 and §4.4.7 show `logging` only as an example. They must not state it as a derived rule.
>
> ## Writer notes
>
> - Position in the first help line: I move to web's form. §4.4.7 says that the help names "the binding that blocks the fix and its position". Here the binding that hides is the handle, and the `! Audit.Log` entry binds it, so give that position (`from `! Audit.Log` at 9:17`). The import position does not explain the hiding.
> - The word "hides" is required (devops, aiml, web). I agree.
> - In C4, the alias goes on a NEW import line. aiml asked whether `import util.log` together with `import util.log as logging` is legal with no warning. Q-S1 covers a qualifier that is bound again to the same module, but not two names for one module. The writer must check §10.5 *Import Aliases*. If that pair gets a diagnostic, the C4 help text is wrong.
>
> STABLE: ready to vote

- **DevOps/Tooling** (`B/r1_devops.md`):

> # DevOps seat, Phase B round 1
>
> ## V1: I hold V1-rewrite (rank 1). V1-add is rank 2; I can live with it.
>
> Reasons from tooling:
> - **No leftover warning after the fix.** With V1-add, if the call was the only use of
>   `import util.log`, that line was W0602 before the fix and stays W0602 after it. The user applies a
>   fix and still sees a warning on the same module. min says the warning "is not new", so condition 2
>   holds. That is true, but the result is still bad: a second edit for one mistake. V1-rewrite
>   removes the warning in the same edit.
> - **Fixes compose.** "Fix all in file" in the LSP applies every E0505 fix in one pass. With rewrite,
>   three calls give one line, `import util.log.{format, parse, write}`. With add, they give three new
>   lines, or a merge rule inside the fix code anyway.
> - **aiml's ranking reason has no source.** "Q-S1 said the formatter merges lines" is a DevOps quote
>   from that panel ("Merging the two lines is the formatter's job"). It is not a rule. sections/ has no
>   rule that `blink fmt` merges imports. So V1-add does not give one line per module after `blink fmt`.
>
> Scope of the rewrite, so nobody needs to guess: it applies only to an existing un-aliased import of
> M. An `as` import already passes candidate 1 (`l.format("x")`). An existing list
> (`import util.log.{parse}`) gets the name added to the list: `import util.log.{parse, format}`.
>
> ```
>   = fix: change `import util.log` to `import util.log.{format}` and call `format("x")`
> ```
>
> After the fix: it compiles and prints nothing, and no W0602 is left on `util.log`.
>
> ## V2: I hold V2-no.
>
> web's loop (one E0505 per `! Log` function) is real. The tooling answer is "fix all", together with
> V1-rewrite: one pass gives one import line with every name in it. An extra alias help suggests a
> file-wide rename next to a fix that works, and it is a second help shape for P4. If V1-add wins, the
> loop costs more lines, but the answer is still "fix all", not V2.
>
> ## Alias-name gap: not on this ballot
>
> I agree with min. It is real (goldens and tests need the same example name every time), but it
> applies to every module in candidate 4, not to handles. File a separate ticket. This ballot keeps
> `logging` as the example text only.
>
> ## Writer notes
>
> - Position in the first help line: give the position of the binding that blocks the fix. Here that
>   is the handle, so use the effect in the `!` row (web's `from `! Audit.Log` at 9:17`), not the import.
>   The rule already says "names the binding that blocks the fix and its position".
> - Say "hides". Keep the candidate-4 alias as a NEW import line.
> - LSP hover on `log` in an effect function shows "handle of `Audit.Log`".
>
> STABLE: ready to vote

- **AI/ML** (`B/r1_aiml.md`):

> # AI/ML, Phase B round 1
>
> ## V1: I move from V1-add to V1-rewrite, stated as one merge rule
>
> I move because of the file that the fix leaves behind. A model learns from the code that the fixes write. In the `log` case the file almost always has `import util.log` already (that is why the author wrote `log.format`). So V1-add leaves `import util.log` and `import util.log.{format}` in most fixed files. That is a pattern that models will copy into new code, where nothing makes it needed.
>
> I state the rule for every module M, not only for whole imports, so that P4 stays one rule:
>
> - If the file already imports M with no `as`, candidate 3 adds `f` to that line: `import M` becomes `import M.{f}`, and `import M.{g}` becomes `import M.{g, f}`. If not, it adds `import M.{f}`.
> - An import with `as` never gets here, because candidate 1 already passes (devops).
>
> ```blink
> import util.log
>
> fn f() -> Str ! Audit.Log {
>     log.format("x")
> }
>
> fn h() -> Str ! Audit.Log {
>     log.parse("y")
> }
> ```
>
> ```
> error[E0505]: `format` is not an operation of effect `Audit.Log`
>   = help: ...hides the module qualifier `log`
>   = fix: change `import util.log` to `import util.log.{format}` and call `format("x")`
> error[E0505]: `parse` is not an operation of effect `Audit.Log`
>   = help: ...hides the module qualifier `log`
>   = fix: change `import util.log` to `import util.log.{parse}` and call `parse("y")`
> ```
>
> Both fixes apply in one pass and give `import util.log.{format, parse}` (sys: they compose and are idempotent). After the fix, the file compiles and prints nothing new. When the old line is not used anywhere else, no unused whole import is left behind. The cost is a second edit shape in the fix code. The resolver already holds the existing import line, so I accept that cost.
>
> ## V2: no
>
> Web's case, where the user hits E0505 again in each `! Log` function, is real. But with V1-rewrite, each new error gets a fix that adds one name to the same line, so the user does not loop. An extra alias help line puts a naming choice next to a fix that already works. A model then chooses between two edits, and sometimes it applies both.
>
> ## The alias-name gap: not on this ballot
>
> I agree with min: open a separate ticket. Goldens and tools need a picker that always gives the same name, but that need holds for every module M, not only for handles. In this decision, `logging` is only an example.
>
> ## Writer notes
>
> - Use "hides the module qualifier `log`". Do not use "`log` is the handle and `log` is the module".
> - Give one position in the help. I prefer the import's position (`import at 1:8`), because the fix edits that line.
> - In candidate 4, the alias is a new line. It does not rename the existing import.
>
> STABLE: ready to vote

- **Minimalism** (`B/r1_min.md`):

> # Min seat, Phase B round 1
>
> ## V1: I change my vote to V1-rewrite
>
> My Phase A text said "keeps whatever W0602 status it had before". I did not check that against
> §10.5, and it does not hold. §10.5 (07_trust ~3930) says an entry is used when a name in the file
> resolves through it. Suppose `log.parse(...)` resolves through `import util.log` in a function with
> no `Log` effect. When a second line binds `log` to the same module, the spec does not say which
> entry gets the use. If the later entry gets it, the old entry gets a new W0602, and under
> condition 2 candidate 3 fails. Under V1-add, the outcome depends on a rule that the spec does not
> state. V1-rewrite does not depend on it.
>
> The rewrite does not add a mechanism. §10.5 (~3807) already has a fix that rewrites an import
> line, from `import alpha.{x}` to `import alpha`. V1-rewrite is the same edit in the other
> direction. A selective import binds its qualifier (§10.1), so every other `log.y` keeps its
> meaning.
>
> The rewrite is not only for the handle case. It applies to candidate 3 whenever the file has a
> whole `import M` with no `as`. The `rand` walk already has this case:
>
> ```blink
> import std.random
>
> fn deal(deck: List[Card]) -> List[Card] ! Rand {
>     let random = 7
>     rand.shuffle(deck)
> }
> ```
>
> ```
>   = fix: change `import std.random` to `import std.random.{shuffle}` and call `shuffle(deck)`
> ```
>
> So this is one rule in the candidate-3 text, not a branch for handles, and P4 holds. The ticket's
> case:
>
> ```
>   = fix: change `import util.log` to `import util.log.{format}` and call `format("x")`
> ```
>
> After the fix: it compiles, nothing new prints.
>
> When the file already has a list (`import util.log.{parse}`), the edit adds `format` to that list.
> That is the same rule, one import line for each module.
>
> ## V2: no
>
> The extra line repeats §3c.4 in every such diagnostic, on a fix that already works. It is a second
> help shape for one walk.
>
> ## Alias-name gap: not on this ballot
>
> §10.5 (~3926) already says, for E1005, "print a concrete name that is not already bound in the
> file". The rule for picking the name is missing for every diagnostic that prints such a name, not
> only for this one. It needs its own ticket.
>
> ## Writer notes
>
> - Say "hides" (agree with devops and aiml).
> - Give the position of the hiding binding, the effect in the row, because that is what blocks
>   `log.format`. Give the import's position only in candidate 4, where the import is what blocks.
>
> STABLE: ready to vote


#### Phase C — Silent vote

Result: Q1 went 5-1 for rewrite (PLT for add). Q2 went 6-0 for a private added line. The ballot:

> # Phase C ballot: silent vote
>
> All six seats said STABLE in round 1, so debate is closed. Vote alone. The full round 1 replies are at
> (scratch)/B/r1_{sys,web,plt,devops,aiml,min}.md
> Read all six first: several seats changed position at the same time. Every snippet below is copied
> from a seat's own text.
>
> Shared, not on the ballot:
> - Option (a): the walk applies with no handle exception. Candidate 1 fails, candidate 2 fails
>   condition 1, candidate 3 is the fix. ~4460 stops naming the alias as the fix; the §4.4.7 "Only a
>   local binding" sentence widens to a binding that hides the qualifier (a local or a reserved
>   handle). Option (b) is rejected.
> - With `format` already bound, candidate 4: no `fix:`, help with the alias example on a NEW import
>   line (`import util.log as logging`, then `logging.format("x")`).
> - V2: no extra alias `help:` line when candidate 3 passes (all six in round 1).
> - The alias-name picker gap goes to a separate ticket; `logging` is an example only (all six).
> - plt: "If V1-rewrite wins, it must apply to every C3 when the file already imports M, and the
>   `std.random` local case is one of these. It must not be specific to handles". aiml and min state
>   the rewrite the same way, for every module M.
>
> ## Q1. The candidate-3 edit when the file already imports M with no `as`
>
> - **Q1-add: add a second import line.**
>   ```
>     = fix: add `import util.log.{format}` and call `format("x")`
>   ```
>   sys: "each fix is a pure insertion of its own line. The fixes do not depend on order, need no
>   merge code, and each one is checked by the walk on its own". plt: "Add is monotone. Adding an
>   import line that passes condition 2 never changes what another name in the file means."
> - **Q1-rewrite: change the existing line (add `f` to its list).**
>   ```
>     = fix: change `import util.log` to `import util.log.{format}` and call `format("x")`
>   ```
>   aiml: "`import M` becomes `import M.{f}`, and `import M.{g}` becomes `import M.{g, f}`. If not, it
>   adds `import M.{f}`." devops: "V1-rewrite removes the warning in the same edit." min: "When a
>   second line binds `log` to the same module, the spec does not say which entry gets the use. If
>   the later entry gets it, the old entry gets a new W0602, and under condition 2 candidate 3 fails."
>   devops: "sections/ has no rule that `blink fmt` merges imports."
>
> ## Q2. Only if Q1-rewrite wins: the edit when the existing import is `pub import util.log`
>
> - **Q2-private-add: a `pub import` is not rewritten; the fix adds a private line** (web, round 1):
>   ```blink
>   pub import util.log
>
>   fn f() -> Str ! Audit.Log {
>       log.format("x")
>   }
>   ```
>   ```
>     = fix: add `import util.log.{format}` and call `format("x")`
>   ```
>   web: "Turning it into `pub import util.log.{format}` would also re-export `format`, which changes
>   the public API of the file."
> - **Q2-rewrite-pub: the rewrite applies to a `pub import` too**, as the Q1-rewrite scope reads in
>   devops ("an existing un-aliased import of M") and aiml ("If the file already imports M with no
>   `as`"), which do not name `pub`. Result: `pub import util.log.{format}`, and `format` is
>   re-exported.
>
> Seats that vote Q1-add still vote Q2 (in case Q1-rewrite wins).
>
> ## Your reply
>
> For Q1 and Q2: **Vote** (label), **Reasoning** (2–4 sentences, your domain), **Concern** (one
> sentence on what could go wrong with the option you expect to win). Wording and which position the
> help gives are writer notes; do not vote on them. Write to
> (scratch)/C/<your-seat>.md
> and return the same text as your final message.

The votes:

- **Systems** (`C/sys.md`):

> # Sys, Phase C vote
>
> ## Q1
>
> **Vote:** Q1-rewrite
>
> **Reasoning:** I change my round-1 vote. min found that under Q1-add, condition 2 depends on a rule the spec does not state: which of two entries that bind `log` to one module gets the use. If the later entry gets the use, the old line gets a new W0602, and the fix fails its own check. Q1-rewrite keeps one entry for each module, so the result is correct by construction and needs no new attribution rule. §10.5 already has a fix that rewrites an import line, so this adds no new mechanism. My round-1 point about overlapping edits is a matter of how the tool applies the fix, not of soundness. The fix can say "add `f` to the import entry of M", and the tool applies it to the current line, so the edits in one pass combine into `import util.log.{format, parse}`.
>
> **Concern:** If `blink fix` or the LSP applies two of these fixes as raw text replacements of the same span, the second edit overwrites the first or gives a parse error. A golden must apply two candidate-3 fixes to one import line in one pass.
>
> ## Q2
>
> **Vote:** Q2-private-add
>
> **Reasoning:** `pub import util.log.{format}` adds `format` to the module's public surface. Every dependent then sees a new re-export, and it can collide (E1005/E1012) in files that the fix never checked. Condition 2 checks only the file that the fix edits, so a fix that changes the exported symbol set goes past what the check can prove. A private added line keeps the export table the same, and Q-S1 makes it clean.
>
> **Concern:** In the `pub import` case, the attribution gap that min raised comes back for the private line next to the `pub` line. The spec still needs a rule for which entry gets a use, or this branch must check that condition 2 still holds.

- **Web/Scripting** (`C/web.md`):

> # Web seat, Phase C vote
>
> ## Q1
>
> **Vote:** Q1-rewrite
>
> **Reasoning:** A JS or Python dev expects one import line per module (`from util.log import format,
> parse`). Two lines for one module look like a mistake, and the user then edits them by hand. Min's
> point decides it for me: under Q1-add, whether the old line gets a new W0602 depends on which entry
> "gets the use", and the spec does not state that rule. So add can fail condition 2 in a way no
> user can predict. Rewrite is the same edit as the decided §10.5 fix, run the other way, and it
> applies to every module M, so P4 stays one rule.
>
> **Concern:** "fix all" in the LSP or `blink fix` must merge two fixes on one import line into
> `import util.log.{format, parse}`. If it applies them one after the other with no merge, the result
> is `import util.log.{format}.{parse}` (sys), which does not parse, so a test must pin it.
>
> ## Q2
>
> **Vote:** Q2-private-add
>
> **Reasoning:** A fix for a call inside a function body must never change what the file exports.
> `pub import util.log.{format}` re-exports `format`, so a downstream user can see a new public name
> that nobody chose. A fix that has a hidden API effect is a source of "why did my package API
> change?" questions. Adding a private `import util.log.{format}` keeps the public surface as it was,
> and the call still resolves.
>
> **Concern:** If the Q1-rewrite text says "an un-aliased import of M" and does not name `pub`, a
> writer or an implementer can miss this case, so the spec and a golden must show the `pub import`
> case on its own.

- **PLT** (`C/plt.md`):

> # PLT seat, Phase C vote
>
> ## Q1
>
> **Vote:** Q1-add
>
> **Reasoning:** Under add, the fixes are pure insertions, so they commute. Fix-all gives the same file in any order, and the walk checks each fix on its own. Under rewrite, two fixes edit one span, so the result depends on a merge that is not yet specified. min's ambiguity has an answer in §10.5 (07_trust ~3911): "A selective import's qualifier is not an entry of its own". So every `log.y` use can resolve only through the whole `import util.log` entry, the old line gets no new W0602, and condition 2 is well defined. devops's leftover W0602 was there before the edit, and its own fix (delete) is machine-applicable and never changes meaning (~3930). So the cost is a second, safe edit, not an error in the fix.
>
> **Concern:** If Q1-rewrite wins, the spec must define the merge for a batch apply. Two fixes on the same `import util.log` must give `import util.log.{format, parse}` in either order. The spec must also say which line gets the edit when the file imports M on more than one line. Otherwise "fix all" is not well defined.
>
> ## Q2
>
> **Vote:** Q2-private-add
>
> **Reasoning:** A rewrite of a `pub import` changes the module's exported interface, and an E0505 fix inside one function body must not do that. The spec already makes this distinction: §10.5 ~3807 says that for a `pub import` "the same edit changes the module's public API, so the fix is a suggestion only". A private added line binds `log` to the same module again, so Q-S1 gives no diagnostic, and the export set does not change.
>
> **Concern:** If Q2-rewrite-pub wins, a fix that is described as local silently re-exports `format` to every module that imports this file. This is an API change that no condition of the walk checks.

- **DevOps/Tooling** (`C/devops.md`):

> # DevOps seat, Phase C vote
>
> ## Q1
>
> **Vote:** Q1-rewrite.
>
> **Reasoning:** min's point decides it for me. When two lines bind `log` to one module, the spec does
> not say which entry gets the use, so under Q1-add the W0602 outcome (and so condition 2) depends on a
> rule nobody has written. A fix whose pass or fail depends on an unstated rule gives goldens that
> change with the implementation. sys's overlap point is real for a batch apply, but it is a property
> of "fix all", not of one fix: rustfix and `cargo fix` apply the edits that do not conflict, check
> again, and repeat. `blink fix` can do the same, and each round gives a correct file.
>
> **Concern:** "fix all" in the LSP and `blink fix` must apply two rewrites of one import line in two
> rounds (apply, check again, apply), not merge them as text, or the result can be
> `import util.log.{format}.{parse}`.
>
> ## Q2
>
> **Vote:** Q2-private-add.
>
> **Reasoning:** A fix that changes the public API of a module is not one that a tool should apply
> without a question. §10.5 already makes the E1012 fix on a `pub import` a suggestion only for that
> reason. Rewriting `pub import util.log` to `pub import util.log.{format}` re-exports `format`, so
> callers of this module see a new name. A private added line keeps the API as it was. Q-S1 gives it
> no E1005, and a selective import's qualifier never gets W0602.
>
> **Concern:** the file then holds `pub import util.log` and `import util.log.{format}`. A user or
> model may "clean up" that pair by hand into one `pub import` line and re-export `format` without
> seeing it.

- **AI/ML** (`C/aiml.md`):

> # AI/ML, Phase C vote
>
> ## Q1
>
> **Vote:** Q1-rewrite
>
> **Reasoning:** Fixed files become training data. The rewrite leaves one import line for each module, and that is the pattern a model should learn and copy. Min's point settles it: under add, condition 2 depends on which of two entries gets the use for W0602, and the spec does not say. A fix whose validity turns on a rule the spec does not state cannot be learned from the spec alone. Sys's overlapping-edit case is a real cost, but it is a cost in the fix code. A batch of rewrites on one line gives one list, and that list is what a model writes when it does the job by hand.
>
> **Concern:** If the fix code for "fix all" does not merge rewrites of one line into one list, a batch apply can give `import util.log.{format}.{parse}`. The goldens must pin a pass with two fixes on the same import.
>
> ## Q2
>
> **Vote:** Q2-private-add
>
> **Reasoning:** A fix must not change the public API of a file. A model that applies a machine fix will not check whether `format` is now re-exported, so the re-export would spread with no review. My round 1 scope ("imports M with no `as`") left out `pub`, and I accept web's guard. The rule a model learns is then: rewrite a private import of M that has no `as`; otherwise add a private line. That is still one sentence.
>
> **Concern:** The C3 rule now has two edit shapes (rewrite, or add for `pub` and when no import exists), and the spec must show the `pub` case with an example, or models will rewrite `pub import` by analogy.

- **Minimalism** (`C/min.md`):

> # Min seat, Phase C vote
>
> ## Q1
>
> **Vote:** Q1-rewrite
>
> **Reasoning:** The plt and sys replies answer only the case where the failing call was the only use
> of `import util.log`. They do not answer the case where another use exists, for example
> `log.parse(...)` in a function with no `Log` effect. Then two entries bind `log` to the same
> module, and §10.5 (~3930) does not say which entry gets the use. If the later entry gets it, the
> old line gets a new W0602, condition 2 fails, and the walk drops to candidate 4 when a correct fix
> exists. Q1-rewrite leaves one entry, so the result needs no such rule. It also adds no mechanism,
> because §10.5 (~3807) already rewrites import lines.
>
> **Concern:** "Fix all" in one pass gives two edits on the same span (`import util.log`). The tool
> must compute each fix again after the one before it applies, or the result is a list that does not
> parse.
>
> ## Q2
>
> **Vote:** Q2-private-add
>
> **Reasoning:** `pub import util.log.{format}` re-exports `format`, so it changes the public API. The
> §10.5 precedent (~3807) makes a `pub import` edit a suggestion only, never machine-applicable, for
> this reason. The private line has no W0602 risk, because a `pub import` never gets W0602 (§10.5,
> ~3755). So the add path is safe here, and the API does not change.
>
> **Concern:** The rewrite rule then has one exception (`pub`). The spec text must state its scope
> as "a private import of M with no `as`", or a writer will leave the exception out.

PLT's Phase C reasoning is in the PLT vote above: it answers the argument of the five rewrite votes with the line of
§10.5 that says a selective import's qualifier is not an entry of its own.

#### Phase D — Re-vote on Q1

All five rewrite votes of Phase C rested on one claim: the spec does not say which of two entries gets the use. The
moderator gave the spec fact that answers it (§10.5 *Imported Names*: a selective import's qualifier is not an entry
of its own; §10.5 *Unused Imports*: an entry is used when a name in the file resolves through it). The ballot:

> # Phase D: focused re-vote on Q1 only
>
> Phase C result: Q1 5-1 for Q1-rewrite (plt for Q1-add); Q2 6-0 for Q2-private-add. Q2 is decided.
>
> Five Q1-rewrite votes name one argument as the reason, min's: "When a second line binds `log` to
> the same module, the spec does not say which entry gets the use. If the later entry gets it, the
> old entry gets a new W0602, and under condition 2 candidate 3 fails."
>
> plt's Phase C vote answers it with a spec line. Read all six votes:
> (scratch)/C/{sys,web,plt,devops,aiml,min}.md
>
> ## Fact (spec text, moderator check; not a vote)
>
> sections/07_trust_modules_metadata.md line 3911, verbatim:
>
> > A selective import's qualifier is not an entry of its own, so it never gets W0602. When a later
> > selective import binds a qualifier again to the same module, the compiler reports nothing for the
> > qualifier. W0602 goes only to a listed name that already imports its item. A whole-module import
> > is an entry, and it binds only its qualifier, so it gets W0602 when that qualifier already names
> > its module:
>
> ```blink
> import a.x.{P}
> import a.x.{R}                // OK: binds `R`; `x` names `a.x` again
> import a.x                    // warning[W0602]: `x` already imports this module
> ```
>
> And §10.5 *Unused Imports* (~3930): "An import entry is **used** when a name in the file resolves
> through it".
>
> ## Your reply
>
> Q1 only. Options as on the Phase C ballot (Q1-add, Q1-rewrite). **Vote**, **Reasoning** (2–4
> sentences; say whether the fact above changes your reason), **Concern** (one sentence). Write to
> (scratch)/D/<your-seat>.md
> and return the same text as your final message.

The votes. Systems, Web/Scripting, DevOps/Tooling, AI/ML and Minimalism changed to add. PLT held add. The result is
6-0 for add.

- **Systems** (`D/sys.md`):

> # Sys, Phase D vote
>
> ## Q1
>
> **Vote:** Q1-add
>
> **Reasoning:** The fact takes away my Phase C reason. A selective import's qualifier "is not an entry of its own" (~3911). So every `log.y` use resolves through the whole `import util.log` entry. The old line gets no new W0602, condition 2 is well defined under add, and add is correct by construction too. With that settled, my round-1 point decides it again. Add fixes are pure insertions, so they commute. Fix-all gives one result in any order, with no merge rule in the spec or the tool. Rewrite needs a batch merge and a rule for which line gets the edit when M is imported more than once. A W0602 that was there before the edit stays, and its own fix (delete) is machine-applicable and never changes meaning (~3930). So it costs one more safe edit, not a wrong fix.
>
> **Concern:** When the only use was the call that the fix moves, the user sees a W0602 on `import util.log` right after the fix. Its help text should say that the handle hides the qualifier, or users will read it as a bug.

- **Web/Scripting** (`D/web.md`):

> # Web seat, Phase D vote
>
> ## Q1
>
> **Vote:** Q1-add (changed from Q1-rewrite)
>
> **Reasoning:** Yes, the fact changes my reason. In Phase C, min's argument was the one that decided
> my vote, and ~3911 removes it. A selective import's qualifier is not an entry, so every module use of
> `log.y` resolves through the whole `import util.log`. The old line gets no new W0602, and condition 2
> is well defined under add. My remaining reason was style (one line per module). Style does not
> outweigh plt's point: under rewrite, "fix all" depends on a merge rule that nobody has specified.
> Under add, each fix always works, in any order. "Just works" is the 90% case. A leftover W0602 on a
> dead whole import is one more one-key fix (delete), and it never changes meaning (~3930).
>
> **Concern:** Fix-all on three calls leaves `import util.log.{format}`, `import util.log.{parse}` and
> `import util.log.{write}` on three lines, which a Python dev reads as untidy. If real code shows this,
> give import-line merging to `blink fmt` in its own ticket, not to the fix walk.

- **PLT** (`D/plt.md`):

> # PLT seat, Phase D vote
>
> **Vote:** Q1-add
>
> **Reasoning:** The fact confirms my reason. It does not change it. Line 3911 says the selective import's qualifier "is not an entry of its own". So a `log.y` use can resolve only through the whole `import util.log` entry, and no second entry exists that could take the use. min's case, where the old entry gets a new W0602, cannot happen. Condition 2 is well defined under add. The only argument left for rewrite is style: one line per module, and no W0602 that was already there stays behind. Against that, add gives edits that commute and need no merge rule for a batch apply. I keep correctness of the composition above style.
>
> **Concern:** The same paragraph means that the place of the line matters. A whole-module import that comes AFTER a selective import of the same module gets W0602 ("`x` already imports this module"). So under add, the new `import util.log.{format}` must go after the existing `import util.log`. If the tool sorts it above that line, the edit adds a W0602 and candidate 3 fails condition 2. Whichever option wins, the writer must state where the edit goes.

- **DevOps/Tooling** (`D/devops.md`):

> # DevOps seat, Phase D vote, Q1 only
>
> **Vote:** Q1-add. I change my vote.
>
> **Reasoning:** Yes, the fact changes my reason. In Phase C I voted for rewrite because of min's
> argument: the spec did not say which entry gets the use. ~3911 does say it. A selective import's
> qualifier is not an entry, so every module use of `log.y` resolves through `import util.log`, and
> condition 2 has one clear result under add. My Phase A reason, that a W0602 is left after the fix,
> is about a warning that was there before the edit. Its delete fix is machine-applicable and "never
> changes what the file means" (~3930), so a second "fix all" round clears it. For a tool, the
> remaining difference favors add: inserted lines commute, so an LSP `WorkspaceEdit` or `blink fix`
> batch applies them in one pass with no merge code. Two rewrites of one span need a merge rule that
> the spec does not give.
>
> **Concern:** after the fix, a file whose whole `import util.log` was used only by the fixed calls
> keeps a W0602 on that line. The user then needs a second round of fixes, and the W0602 text should
> say that the handle hides the qualifier, so that "unused?" does not read as false.

- **AI/ML** (`D/aiml.md`):

> # AI/ML, Phase D vote
>
> ## Q1
>
> **Vote:** Q1-add (I change from Q1-rewrite)
>
> **Reasoning:** The fact removes the reason I gave in Phase C. §10.5 ~3911 says a selective import's qualifier is not an entry, so `log.y` uses can resolve only through the whole `import util.log`. Condition 2 is then well defined under add, and the spec states the answer. What is left of my case is the style point (one line per module), and Q2 now outweighs it. Q2-private-add already makes the fix add a line for `pub import` and when no import exists. With Q1-add, candidate 3 has one edit shape in every case, the decided text "add `import M.{f}`". A model learns that from one sentence, and fix-all commutes with no merge rule. The leftover W0602 on an import that was used only by the call was there before the fix. Its own machine fix (delete the line) is safe, so an agent loop ends in one more step.
>
> **Concern:** Fixed files keep `import util.log` next to `import util.log.{format}`, and no spec rule merges them, so models may copy two lines per module into new code. A friction ticket on whether `blink fmt` should merge imports of one module is the right place for that.

- **Minimalism** (`D/min.md`):

> # Min seat, Phase D vote
>
> ## Q1
>
> **Vote:** Q1-add (I change from Q1-rewrite)
>
> **Reasoning:** The fact removes my reason. A selective import's qualifier is not an entry (~3911), so
> every other `log.y` use can resolve only through the whole `import util.log` entry (~3930). The old
> line gets no new W0602, and condition 2 is well defined under add. My Phase C vote rested on that
> reason alone. Without it, rewrite only adds an edit shape, a merge rule for a batch apply, and a
> `pub` exception (Q2), and the decided candidate-3 text ("Add `import M.{f}`") needs none of them.
> One import line for each module is a style point, and it does not justify more fix code.
>
> **Concern:** When the failing call was the only use, the fixed file keeps a W0602 on `import util.log`
> that was there before. The user needs a second fix (delete, which is machine-applicable), and some
> will read it as a fix that left a warning.

### Gaps raised, not decided

1. The alias-name picker (PLT, Minimalism): which rule picks the alias name that the candidate 4 help shows. The
   ruling uses `logging` as an example only and does not write it as a derived rule. A separate ticket takes the
   question.
2. Whether `blink fmt` merges two imports of one module (AI/ML, Web/Scripting, DevOps/Tooling). Sections/ has no rule
   that it does. The added line stays a separate line until a panel decides this.

### Follow-ups

1. Implementation: give the E0505 help the wording "the handle hides the module qualifier" and name the effect and
   the position of its `!` row; run the candidate walk when a handle hides the qualifier; add the line after the
   existing import; give the `pub import` case a private added line; give candidate 4 the position of the blocking
   binding; add the `note:` to the W0602 of an import that a handle hides at every use.
2. A tool fact: the language server can show "handle of `Audit.Log`" on hover over `log`. That is tooling, not spec.
3. Llms text: the walk for the module-function fix also applies when a reserved handle hides a same-spelled qualifier.
   The fix adds `import M.{f}` after the existing import of `M`. The W0602 of the old import may stay. For a
   `pub import`, a private line is added. When `f` is already bound, there is no fix, and the help shows an alias
   on a new import line.

## Final Spec

- §4.4.7 *Helpers in `std.random`*: candidates 1, 3 and 4 and the "Only a binding that hides the qualifier" text, the
  new block "A reserved handle hides the qualifier" with its cases, and the paragraph "A handle wins over a module
  qualifier".
- §3c.4 *Effect Handle Operations*: a handle hides a same-spelled module qualifier in a function that declares the
  effect.
- §10.5 *Imported Names*: the order of a whole-module import and a selective import of one module, and an alias import
  next to a whole-module import.
- §10.6 *Shadowing Rules*: rule 5 of *Diagnostics that involve a shadowing name*.
