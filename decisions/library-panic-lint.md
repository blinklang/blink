[< All Decisions](../DECISIONS.md)

# Library-Panic Lint — Design Rationale

**Gap:** "§2.20 says "A lint warns when panic() appears in library code" but the lint has no name, no code and no defined scope, so @allow and [lints] cannot name it. Deferred by the todo/unreachable panel (decisions/todo-unreachable-builtins.md, Q3b LATER 5-1; AI/ML dissent wanted it named now). Already fixed by that panel: the lint skips calls that resolve to the built-in todo or unreachable (not by name); its help names Result[T, E] for error paths and unreachable only for dead paths, and never proposes a plain panic->unreachable rename. Open: (1) name and W-code; (2) what counts as "library code" (pub fn? any non-main package? lib/ target?); (3) default level; (4) whether any bare panic in a library is fine (Min); (5) help text wording."

The panelist texts below quote `fq5b90`, the local tracker ID of this gap.

**Facts given to the panel** (summary): the language has no library/application split; `[package]` has no kind field, and a bare package import resolves to `src/<name>.bl` (§10.1). `panic()` is not yet in the compiler, and lib/std has no `panic(` call. W0705 is free. `@allow` takes names and `[lints]` takes codes; the levels are `"off"`, `"warn"` and `"error"`, and no Blink warning ships off by default. `@requires` is a caller's promise that the compiler checks at each call site (§3b.2).

**Result:**

- **Q1 (5-1, PKG; Min dissent for removing the lint):** `PanicInLibrary` (W0705). A package is a library when its entry module `src/<name>.bl` declares no `fn main`. A package whose entry module declares `fn main` is an application. A file outside any package is never library code. In a library package the lint fires on each call that resolves to the built-in `panic` outside test blocks, private functions included.
- **Q2 (6-0, WARN):** on as a warning; `[lints] W0705 = "off" | "error"`; a function-level `@allow(PanicInLibrary)` overrides `[lints]`.
- **Q3 (6-0, YES):** `@trusted(audit: K)` does not suppress the lint; it has no machine-applicable fix; a reference to the built-in `panic` used as a value (`let f = panic`) also fires, with the span on the reference.
- **Q4 (5-1, FILL; Min dissent for GENERIC):** the one `help:` line names the function's real return type (`Result[Int, E]`), else `Result[T, E]`.
- **Q5 (6-0 in Phase D, NONE; 4-2 in Phase C, Sys and PLT for NOTE):** `@requires` does not appear in the output. It goes in the `blink explain W0705` text.
- **Q6 (6-0, SCOPE-NOTE):** a `note:` states why the code is in scope: "package `ringbuf` is a library: `src/ringbuf.bl` declares no `fn main`".

**Settled with the user at the checkpoint:**

- For a function that returns `()`, the `help:` line says `Result[(), E]`. PLT asked for the generic form there; Sys and Web asked for `Result[(), E]`. The user took `Result[(), E]`.
- For a type parameter or `Never`, the help says `Result[T, E]` (Sys, PLT, AI/ML). When the function already returns `Result`, the help says "return `Err(...)`" (DevOps, Q4 concern).

**Follow-ups taken from the Phase C and Phase D concerns:**

- The spec says a demo `main` in the entry module makes the package an application, and that the rule moves to a library target if Blink adds one (Sys, Web).
- The spec says a throwaway `fn main` is not a fix, and the scope note never suggests one (AI/ML, Min).
- The scope note names the entry file path that the compiler resolved (Sys, DevOps).
- `blink explain W0705` names `@requires` right after `Result`, as "state it with `@requires(...)` and remove the check", and forbids the rename to `unreachable` (all six, Phase D).
- The value-use span is on the reference; a later call through the bound name does not fire again (DevOps, Web).
- For the implementation: when an edit adds or removes `main` in the entry module, the LSP sends new diagnostics for the whole package (DevOps); golden tests pin the help and note text (PLT); a test passes `panic` as a `fn(Str) -> Never` argument (Sys).

**AI-first review:** 5/5 pass. Learnability and debuggability pass: the scope rule is one sentence, and the scope note puts it in the output. Generability passes: the filled-in `help:` line can be copied as written. Consistency passes: the catalog row and the suppression path follow W0610. Token efficiency passes, with a cost Min and DevOps named: `@allow` lines on private invariant helpers.

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated in independent-proposal → debate → vote rounds. The texts below are the panelists' own, verbatim. Their headings are set to one level so that they nest under each panelist.

#### Phase A — Independent proposals

##### Systems

###### Systems — Phase A

###### Proposal S1 (preferred): `PanicInLibrary`, W0705, scoped to packages that have no `main`

**Name and code.** `PanicInLibrary`, **W0705**. It joins the W070x lints next to `TodoInCode` (W0703), which is also a §2.20 lint. The catalog should add a W070x range row; the current table lacks one (F3).

**What counts as library code.** A package is a library when its entry module (`src/<name>.bl`, §10.1) declares no `fn main`. The compiler reads that one fact once per package, at the time it resolves the entry. In a library package, the lint fires on every call that resolves to the built-in `panic`, in every non-test body. Private functions count too.

Why not "only `pub fn`"? A panic in a private helper reaches callers through every `pub` path that calls the helper. To catch only the `pub` cases, the compiler would need a call-graph walk across modules. That is real compile-time cost, and its verdict changes when someone edits a far-away caller. A rule keyed on the package is O(1), local and stable. It also needs no new `[package]` field (F1).

A reference that resolves to the built-in and is used as a value (`let f = panic`) also fires. Without that, code can hide the call and slip past the lint.

```blink
// src/ringbuf.bl  (package "ringbuf", no fn main => library)
pub fn pop(self: RingBuf[T]) -> T {
    if self.len() == 0 {
        panic("pop on empty ring")
    }
    self.take_head()
}
```

```
warning[W0705]: PanicInLibrary: `panic` in library code
  --> src/ringbuf.bl:4:9
   |
 4 |         panic("pop on empty ring")
   |         ^^^^^^^^^^^^^^^^^^^^^^^^^^ the caller cannot handle this
   |
   = help: return `Result[T, E]` (or `Option[T]`) so the caller can handle this error
   = help: if this path can never run, use `unreachable()`
   = note: if this is a broken invariant, add `@allow(PanicInLibrary)` to the function
```

**Default level: warn.** That is what §2.20 already says, and the lint costs nothing at run time. It is a front-end check on a resolution the typechecker already does, and `panic` code generation does not change. A team can promote it with `W0705 = "error"` under `[lints]`.

**Is a bare panic in a library ever fine?** Yes. Allocator corruption, a broken internal index and a violated `unsafe`/FFI contract are not errors the caller can handle. The answer to those is `@allow(PanicInLibrary)` on the function. That marks the spot in code review and costs one line. The lint should not get a list of exempt patterns: each exemption is a rule the compiler must evaluate and users must learn.

A `fn fail(m: Str) -> Never { panic(m) }` wrapper fires once, at its own body. Callers of `fail` do not fire. That is fine: the `@allow` is visible where the wrapper is defined.

**Help text.** The first `help:` names `Result[T, E]`, so the repair converges on it (F5). The second names `unreachable()`, only for paths that can never run. The `note:` names `@allow` for broken invariants. No line offers "change `panic` to `unreachable`" as a fix by itself (Q3a constraint).

**Tradeoffs (systems view).**
- (+) No run-time cost, and the scope decision is O(1). Two builds of the same package always give the same verdict.
- (+) lib/std has zero `panic(` calls today, so turning the lint on there costs nothing and keeps it that way.
- (−) A package that has both a library entry and a `main` is classed as an application, so the lint stays off for it. That is acceptable until Blink adds a lib/bin split. The spec should say this rule then becomes "the library target".
- (−) Coarser than a `pub`-reachability rule. But the precise rule needs a whole-program analysis whose verdict moves with edits elsewhere. I reject that cost.

**Cross-language notes.** Rust's `clippy::panic` is off by default, and `missing_panics_doc` covers only `pub` items. Because nothing enforces it, crates panic freely; Blink should not copy that. Go and Zig have no such lint and rely on convention (`error` returns, error unions). Zig's habit of panicking only on broken invariants and returning error unions for everything else matches this split well.

###### Proposal S2 (fallback): `pub` items only, on the direct body

The lint fires only on a `panic` written directly in the body of a `pub fn` or a `pub` impl method, in any module except the one that declares `main`. It needs no call graph, but it misses panics in private helpers (false negatives), and it fires on modules inside applications (false positives). I list it only as a fallback if the panel rejects classifying by package.

**Preferred:** S1. `PanicInLibrary` (W0705), warn by default, fires on every built-in `panic` reference in any package whose entry module has no `fn main`, with `@allow(PanicInLibrary)` as the escape for broken invariants.

##### Web/Scripting

###### Web/Scripting — Phase A

###### Proposal A (preferred): `PanicInPublicFn` (W0705), scoped to `pub fn` outside the entry file

1. **Name/code.** `PanicInPublicFn`, W0705 (next free slot in the W070x Linting block, beside `TodoInCode` W0703). The name says *where* the panic is, not what kind of package it lives in. A JS/Python dev reads "panic in public fn" and knows what to change without opening docs. "Library" is a word Blink does not define (F1). A lint named for a concept the language lacks means every Stack Overflow answer starts with "well, what counts as a library…".

2. **Scope.** Fires when a call resolves to built-in `panic` AND it is lexically inside the body of a `pub fn` (closures in that body included) AND the file is not the package entry file (the file holding `fn main`) AND it is not in a `test` block. Private helpers do not fire. This is a nudge at the API boundary, not a proof of panic-freedom. A whole-program "may panic" analysis gives warnings far from the cause, and people cannot act on them.

3. **Default level.** Warning. Escalate with `W0705 = "error"` under `[lints]`. A one-file script or `main.bl` never sees it, so the 90% case stays quiet.

4. **Bare panic in a pub fn — fine?** No free pass by message text or anything else. Library authors with a real invariant write `@allow(PanicInPublicFn)` on the fn. One line, greppable, and reviewers can see it was on purpose. Same mental model as `// eslint-disable-next-line`, but named.

5. **Help text.** Names the concrete return type, so the repair is copy-pasteable:

```blink
pub fn parse_port(s: Str) -> Int {
    match s.to_int() {
        Some(n) => n
        None => panic("bad port: {s}")
    }
}
```

```
warning[W0705]: PanicInPublicFn: `panic` in public function `parse_port`
  --> src/netutil.bl:4:17
   |
 4 |         None => panic("bad port: {s}")
   |                 ^^^^^^^^^^^^^^^^^^^^^^ a caller cannot recover from this
   = help: if the caller can handle this error, return `Result[Int, E]`
   = note: if this path can never run, use `unreachable()`; to keep this panic, add `@allow(PanicInPublicFn)` to `parse_port`
```

`help:` names `Result[T, E]` first (instantiated), `unreachable` only for dead paths, and never a bare rename. Every repair named exists (F5).

**Tradeoffs (DX):**
- (+) Learnable in 30 seconds: "public function, not main → return a Result."
- (+) No new blink.toml field, no lib/bin concept. Works today.
- (+) Scripts and apps are silent by default; no warning fatigue for the largest user group.
- (−) A panic in a private helper called from a `pub fn` slips through. Accepted: a lint people understand and obey beats a complete one they `@allow` everywhere.
- (−) A multi-file app gets warnings on `pub fn` in non-entry modules. That is defensible, and an app author can turn it off package-wide with `W0705 = "allow"` under `[lints]` (this assumes `"allow"` is a legal `[lints]` level; DevOps should confirm).

**Cross-language:** Rust clippy has `panic` (allow-by-default) and `missing_panics_doc` (scoped to `pub fn`). The `pub fn` scope is the one people actually use. Go's Effective Go says "don't panic across package APIs", a convention with no tooling. Kotlin and Python have nothing, and their users still argue about checked vs unchecked exceptions. Blink can beat all of them by being simple and explicit.

###### Proposal B (fallback, I reject it): `PanicInLibrary` (W0705), package-dependency scope

Fires on any `panic` in a package when it is compiled as a dependency of another package. Std and pkg authors would see it via `blink check --as-dependency` or similar.
- (−) The author never sees the warning while writing the code. Terrible DX. Also needs build-mode plumbing. Listed only to show why scoping by package fails.

**Preferred:** Proposal A — `PanicInPublicFn` (W0705), a warning on built-in `panic()` inside a `pub fn` outside the entry file and tests; help names `Result[<ret>, E]`, with `@allow(PanicInPublicFn)` as the escape.

##### PLT

**PLT panelist: Phase A proposal (fq5b90)**

**Framing.** We decided 5-0 that `panic` is untracked divergence. Its type, `Never`, says nothing to the caller. Koka would put the divergence in the effect row, but that option is closed. The lint is therefore an approximation of a missing piece of interface information, and it should approximate at the point where the interface matters: the package boundary, where one author's invariant becomes another author's surprise. The rule has to be local and decidable from the package's own source. It must not depend on who imports the package, or the same file would change status per importer, and that does not compose.

**Proposal A (preferred): `PanicInLibrary`, W0705, keyed on package kind derived from source**

1. **Name and code.** `PanicInLibrary`, W0705. This puts it next to `TodoInCode` (W0703) in the §2.20 family under Linting. W0705 is free, and no live name collides with it ignoring case, `_` and `-`.
2. **Library code: a rule, not a guess.** A module is library code when it belongs to a package (has a `blink.toml`) whose entry module `src/<name>.bl` (§10.1) declares no `fn main`. A package that has `main` is an application. A file outside any package, meaning a script, is never library code. lib/std has no `main`, so it is library code. The compiler decides this from the package alone, with no new manifest field.
3. **Scope inside library code.** The lint fires on every call that resolves to the built-in `panic` in non-test code, private functions included. If it covered only `pub fn`, a private helper would get around it. A call-graph version (panics reachable from `pub` items) would be sound, but it costs more for little gain. Test blocks are exempt. Q3a already exempts `todo` and `unreachable` by resolution.
4. **Level.** `warn` by default. `W0705 = "error"` under `[lints]` gives strict libraries a hard error. `@allow(PanicInLibrary)` on the fn is the audited escape. `@trusted` does not suppress it, matching W0610.
5. **Is a bare panic ever fine (Min's Q4)?** Not silently. A real invariant violation that a caller can reach in a library is legal, but the author must say so with `@allow`. That marker is visible in the source and greppable, so it gives the panic a declared place. This answers Min's "rename to unreachable" worry: `unreachable` is for paths that can never run, and `@allow` is for paths that can run but break the library's own invariant.
6. **Help text.** The repairs move the divergence into the signature, in this order: Result, then `@requires`, then `unreachable`. `@requires` is the principled fix for "caller passed bad input". The partiality moves from a hidden `Never` into the function's contract, the SMT solver checks it at call sites, and `blink query --layer contract` shows it. All three repairs exist (§3.1 F5).

```blink
pub fn nth(xs: List[Int], i: Int) -> Int {
    if i < 0 {
        panic("negative index")   // W0705
    }
    xs.get(i).unwrap()
}

// repair 1: total function
pub fn nth(xs: List[Int], i: Int) -> Result[Int, IndexError] { ... }

// repair 2: partiality in the interface
@requires(i >= 0)
pub fn nth(xs: List[Int], i: Int) -> Int { ... }

// audited invariant
@allow(PanicInLibrary)
fn rebalance(t: Tree) -> Tree { ... panic("tree height invariant broken") ... }
```

```
warning[W0705]: PanicInLibrary: `panic` in library package `listx`; a caller cannot see or handle it
  --> src/listx.bl:3:9
  = help: return Result[T, E] if a caller can cause or handle this error; state the caller's
          duty with @requires(...); use unreachable() only if this path can never run
```

**Tradeoffs (PLT).**
- (+) The rule is a pure function of the package source: compositional, deterministic, and cacheable.
- (+) Every repair makes the interface more honest. None of them is a rename.
- (−) "No `main` in the entry module" is a structural proxy. A library that ships a demo `main` in its entry module reads as an app. That is a true false negative, but it is sound in the safe direction because warnings are missed, not invented. If the panel later adds a manifest `kind`, the rule swaps its source without changing the lint's name or code.
- (−) Covering private functions brings more `@allow` noise in algorithmic libraries. I accept that: an invariant panic should be marked.

**Proposal B (rejected by me, listed for the record): scope = `pub fn` bodies in any module.** This needs no package-kind rule, but `pub` means visible to other modules, not other packages. Every multi-module application would warn on its own internal `pub` helpers. That is a semantic mismatch, and a semantic mismatch is a design flaw, not a matter of tuning.

**Cross-language notes.**
- Rust: Clippy's `panic` lint is allow-by-default, and `missing_panics_doc` requires `pub fn` docs to say when the function panics. Proposal A puts that duty in `@requires` instead of prose.
- GHC 9.8 added `-Wx-partial` for `head`/`tail` partiality.
- Koka tracks the same thing exactly as the `div`/`exn` effects. This lint is our sound under-approximation of that.

**Preferred:** Proposal A, `PanicInLibrary` (W0705): warn by default on every built-in `panic` in non-test code of a package whose entry module has no `main`; `@allow` on the fn as the audited escape; help names Result, `@requires` and `unreachable` in that order.

##### DevOps

**DevOps/Tooling panelist: Phase A proposal (spec gap fq5b90)**

My test for every option: can `blink check`, the LSP and CI each decide the lint from one file, give the same answer, and show one clear repair? A lint whose scope changes with the build target makes the LSP show something different from CI. Users then learn to ignore it.

---

**Proposal T1 (preferred): `PanicInLibrary` (W0705). "Library" means a module with no `fn main`.**

- **Name and code.** `PanicInLibrary`, W0705. It sits next to TodoInCode (W0703) and DivisionByLiteralZero (W0704). It also needs a catalog range row, `W070x | Linting`, which is missing today (F3). The name passes the case/`_`/`-` collision rule (F4). No live name is close to it.
- **Scope.** The lint fires on each call that resolves to the built-in `panic`, when:
  - the module that holds the call declares no `fn main`, and
  - the call is not inside a test block. The test runner catches panic, and `assert_panics` bodies need it.

  The rule reads only the current file, so the LSP, a one-file `blink check` and the CI build always agree. It needs no new manifest field (F1), and nothing depends on which binary imports the module. Calls that resolve to `todo` or `unreachable` are skipped, as the earlier panel decided (Q3a).
- **Default level.** `warn`. `W0705 = "error"` makes it fail the build. lib/std should set that, since it has zero panics today (F2).
- **Q4 (is a bare panic in a library ever fine?).** Yes, when the author says so where the code is. Use `@allow(PanicInLibrary)` on the function. That is the record a reviewer greps for. I do not want a second escape, such as a special message form or a "reason" argument. That would be one more channel to document and to lint.
- **A multi-module application.** Its own modules without `fn main` get the warning. That is correct: those modules hold no capability budget either (§10.3). The output tells such a project how to turn the lint off, in one line.

**Diagnostic shape:**

```blink
pub fn parse_depth(n: Int) -> Int {
    if n < 0 {
        panic("negative depth")
    }
    n
}
```

```
warning[PanicInLibrary]: `panic` in library code
 --> src/json.bl:3:9
  |
3 |         panic("negative depth")
  |         ^^^^^^^^^^^^^^^^^^^^^^^ stops the caller's program; the caller cannot handle it
  |
  = help: if a caller can cause this state, return `Result[T, E]` and let the caller decide
  = note: use `unreachable()` only when this path can never run, not to silence this warning
  = note: for a deliberate invariant check, add `@allow(PanicInLibrary)` to the function
  = note: for an application, turn the lint off in blink.toml: [lints] W0705 = "off"
```

- **No machine-applicable fix.** A change to `Result` changes the signature and every caller. A rename to `unreachable` is forbidden as a repair on its own. So the diagnostic has no fix for an agent to apply without thought. This keeps the "rename panic to unreachable" outcome, which Minimalism fears, out of `blink fix`.
- **Help text and §3.1.** The first `help:` is the only repair line. The `unreachable` text is a `note:`, so it is not a competing help. That follows F5: everything converges on the first help.
- **Cross-language.** Clippy's `panic` / `unwrap_used` are opt-in and work at crate level. Go vet has no such lint, and Go library panics are a known problem. Per-file scope is what lets rust-analyzer and the CLI agree. I copy that property here, but not the default-off level.

---

**Proposal T2 (rejected): scope is `pub fn` bodies only**

This is easy to decide, but a panic in a private helper that a `pub fn` calls gets past it. A lint that misses the common case trains users to distrust it.

**Proposal T3 (rejected): a `[package] kind = "lib"` field in the manifest**

The LSP would then need to read the manifest for a source-level warning. It adds manifest surface to answer one lint question. Single-file scripts have no manifest. YAGNI.

**Help text, settled now.** Whatever scope the panel picks, it should fix these now:
- the message and help lines above,
- no machine-applicable fix,
- the catalog row in the W0610 style: scope, `@allow(PanicInLibrary)`, `@trusted` does not suppress it (it does not meet the audit-gated rule in §9.1), and `W0705` under `[lints]`.

**Preferred:** T1. `PanicInLibrary` (W0705) warns on built-in `panic` calls outside test blocks in any module without `fn main`. The default is `warn`. The only repair line names `Result[T, E]`, and there is no auto-fix.

##### AI/ML

###### AI/ML: Phase A proposals for fq5b90

My position from Q3b stands. A lint with no name has no `@allow`, no `[lints]` key and no string an agent can match in a fix loop. Every sub-question below should have one answer that a model can work out from the code alone, with no build context and no project config.

###### Proposal 1 (preferred): `PanicInPublicApi` (W0705), keyed on visibility

**(1) Name and code.** `PanicInPublicApi`, W0705. It sits next to `TodoInCode` W0703 in the W070x Linting block. The name says what triggers it, so an agent can learn the rule from the name. "PanicInLibrary" names an idea that the language does not define (F1).

**(2) Scope.** The lint fires on a call that resolves to the built-in `panic` when the call is lexically inside the body of an item that can be called from another module. That means a `pub fn`, a method in an `impl` of a `pub` type, or a closure written inside one of these. It does not fire in:
- a module that defines `fn main`
- `test` blocks
- private functions

The check is local and needs no call-graph walk. A model can apply it by looking at one function. "Library code" then means "public API", which uses the `pub` mark that §10.2 already defines. We add no new package field.

**(3) Default level.** `"warn"`. A lint that is off by default has no effect on generated code, because models do not opt in to lints.

**(4) Is a bare panic ever fine?** Yes. An invariant violation is a real use, so Minimalism's point holds. But the author must say so once: `@allow(PanicInPublicApi)` on the function. That costs one line, and it tells readers and agents that the panic is on purpose. `@trusted` does not suppress the lint.

**(5) Help text.** The first `help:` gives the fix that covers most cases (F5). The second line gives the two other options and does not offer a plain rename to `unreachable()`.

```blink
pub fn parse_port(s: Str) -> Int {
    match s.to_int() {
        Some(n) => n
        None => panic("bad port")
    }
}

@allow(PanicInPublicApi)
pub fn slot(self, i: Int) -> Int {
    if i >= self.cap { panic("slot index past capacity: ring invariant broken") }
    self.buf.get(i).unwrap()
}
```

```
warning[W0705]: `panic` in public function `parse_port`
  --> src/net.bl:4:17
   |
 4 |         None => panic("bad port")
   |                 ^^^^^^^^^^^^^^^^^ callers in other modules cannot recover from this
   = help: return `Result[Int, E]` so the caller can handle the error
   = note: if this path can never run, use `unreachable()`; if it guards an invariant, add `@allow(PanicInPublicApi)` to `parse_port`
```

The catalog row follows the W0610 model. It states the scope, `@allow(PanicInPublicApi)`, that `@trusted` does not suppress it, and `W0705 = "error"` / `"off"` under `[lints]`.

**Tradeoffs (AI/ML)**
- One decision point ("is the enclosing item visible outside its module?"), and a model can answer it from the text in front of it.
- An app with `pub` helpers gets false positives. The fix is one line, `W0705 = "off"` in `[lints]`, and the help can say so. That is cheaper than a lib/bin field that the spec would have to define and that models would then forget to set.
- A private helper that panics, called from a `pub fn`, does not trigger the lint. I accept that. A transitive version gives a warning far from the code that causes it, and agents cannot act on that.

**Cross-language note.** Clippy's `panic` / `unwrap_used` and `missing_panics_doc` key on `pub` items in the same way. Go vet has no such lint, and Go library panics are a known source of production failures.

###### Proposal 2 (fallback): scope by dependency position

The lint fires on `panic` in any module of a package that another package imports. A package learns this only when someone builds it as a dependency.

I rank this low. The author never sees the warning while they edit their own package, only their users do. A model that writes the library gets no signal in its fix loop. It also needs build-graph context that a single-file check cannot see.

###### Proposal 3 (rejected): off by default, opt-in

This is safe, but it is a no-op for AI-written code. It also contradicts the text "a lint warns" in §2.20.

###### Answer to Minimalism's objection from Q1

Requiring `@allow` for a deliberate invariant panic keeps the lint honest. The lint never becomes "rename panic to unreachable", because the help never offers that rename. The `unreachable` option also applies only to paths that can never run, which a reviewer can check.

**Preferred: Proposal 1. `PanicInPublicApi` (W0705), on by default as a warning, fires on built-in `panic` lexically inside items visible outside their module (not in the `main` module or tests), suppressed only by `@allow(PanicInPublicApi)`, with `Result[T, E]` as the first `help:`.**

##### Minimalism

**Minimalism, Phase A: the library-panic lint (§2.20)**

**The core problem.** This lint guards a boundary the language does not have (F1). Blink has no library/application split: blink.toml has no `kind`, and `src/lib.bl` is explicitly not a convention. To name and scope this lint, we would first have to invent "library code". That would be a new concept in the package model, and its only user would be one warning. The tail is wagging the dog.

There is a second problem. The §2.20 table already says `panic(msg)` is correct for "any other programmer error". A violated precondition in a library (an index out of range, a broken internal invariant) is that kind of error. So a default-on lint would fire on code the spec calls correct. Authors would silence it with `@allow` or by renaming `panic` to `unreachable`. That is the rename Q3a's conditions forbid us to propose, and users will do it anyway.

---

**Proposal M1 (preferred): remove the lint from the spec. Rely on the table.**

Spec change: delete "A lint warns when `panic()` appears in library code" at line 1797, and delete the "library-panic lint" paragraph at line 1868. Keep the decision table, which is the convention. W0703 `TodoInCode` stays as it is.

```blink
pub fn parse_port(s: Str) -> Result[Int, ParseError] {
    // error the caller can handle -> Result (the table says so)
    ...
}

pub fn get_unchecked(xs: List[Int], i: Int) -> Int {
    if i < 0 || i >= xs.len() {
        panic("get_unchecked: index {i} out of range 0..{xs.len()}")
    }
    xs.get(i).unwrap()
}
```

No diagnostic. Both functions are correct as written.

- Gains: there is no new code, no new "library" concept, no `@allow` noise, and no reason to rename `panic` to `unreachable`. The Q3a exemption becomes moot, so the "escape hatch" concern goes away. F2 says no lint code exists and lib/std has zero `panic(` calls, so removing it now costs nothing.
- Cost: no tool pushes authors toward `Result`. But the type signature already does that. A caller sees `-> Int` and not `-> Result`, and code review catches the rest.
- Cross-language: Go has no vet check for `panic` in packages; Effective Go just says "don't panic" as a convention. Rust's standard lints do not flag `panic!` either.

---

**Proposal M2 (fallback, if the panel wants a named lint): opt-in, scoped to `pub fn`, no new package concept.**

- (1) Name and code: `PanicInPublicFn`, **W0705**, next to W0703 and W0704 in the Linting group, which also needs a W070x range row.
- (2) Scope: a call that resolves to the built-in `panic` and sits lexically in the body of a `pub fn`, including nested closures. The check is not transitive through callees, and it does not look at package kind, because none exists. Built-in `todo`/`unreachable` stay exempt (Q3a). Test blocks are skipped.
- (3) Default level: **allow (off)**. A project turns it on with `[lints] W0705 = "warn"` or `"error"`, and a function-level `@allow(PanicInPublicFn)` overrides that (§4.16.8). §10.3 already tells library authors to set capability budgets. Turning on this lint is one more line of the same advice.
- (4) Yes, a bare `panic` with a message in a library is fine for programmer errors. That is the reason the default is off.
- (5) Help text:

```
warning[W0705]: `panic` in public function `get_unchecked`
  --> src/vec.bl:9:9
   |
 9 |         panic("get_unchecked: index {i} out of range")
   |         ^^^^^
   = help: if the caller can handle this error, return `Result[T, E]`
   = help: if this path can never run, call `unreachable()`
   = note: suppress with `@allow(PanicInPublicFn)` for a documented precondition
```

The first `help:` names `Result` (F5 convergence). `unreachable` appears only with its condition, never as a rename on its own.

- Tradeoffs: "public function" already exists in the language, so this adds no package-model concept. Being off by default means correct invariant guards produce no noise. The cost is one more catalog row and one more name.
- Cross-language: this is exactly Clippy's `clippy::panic`, which sits in the *restriction* group and is allow-by-default. Rust tried this and left it opt-in for the same reason.

---

**Rejected outright:** keying the scope on "non-main package" or a `lib/` target. Either one adds a package-kind field or a directory convention that only this lint would use. That is C++-committee growth: a feature that exists to justify another feature.

**Preferred: M1. Delete the lint sentence and rely on the §2.20 table. If the panel insists on a lint, use M2 (`PanicInPublicFn` W0705, `pub fn` scope, off by default).**

#### Phase B — Debate (one round; all six reported stable)

The moderator's deduped option space: R (remove the lint), PKG (keyed on the package), MOD (keyed on the module), PUB (keyed on visibility), with variations on name, default level, help text, suppression, auto-fix and value use.

##### Systems

###### Systems — Phase B round 1

**Main option: PKG.** I keep it. Here is why the other options are worse.

**Against MOD (DevOps).** MOD fires on every module without `main`, private functions included. In a multi-module application, that is almost every file. DevOps' own diagnostic has to add "for an application, turn the lint off in blink.toml", so the scope is wrong for the largest user group. DevOps says PKG makes the LSP read a second file. That is one read of `src/<name>.bl`, which the LSP already resolves for imports. It is cached and does not change with the importer or the build target, so LSP and CI still agree. The cost is the same as for MOD, and the false positives go away.

**Against PUB (Web, AI/ML, Min M2).** I like that PUB is local. But PLT is right: `pub` means "seen by other modules", not "seen by other packages". PUB fires on the internal `pub` helpers of every multi-module app, which is the noise Web wants to avoid. It also misses every private helper that a `pub fn` calls. So it gives false positives in apps and false negatives in libraries at the same time. Web and AI/ML say "library" is undefined (F1). PKG defines it with one sentence that the compiler can check from source. That defines a term the spec already uses (F9). It is not a new package-model concept, and it needs no manifest field.

**Against R (Min).** Min's best point is that the table calls `panic` correct for "any other programmer error". I concede part of it: the lint must stay quiet in applications. PKG does that. In a library, the panic ends someone else's program, and one `@allow` line per invariant is a cheap price for making that visible. §2.20 already promises the lint. lib/std has zero panics, so the lint costs nothing there. Removing a spec promise to avoid defining one word is the wrong trade.

**Variations**
- **V2:** warn. F8 shows no warning ships off by default. Opt-in would be the first such case, and AI/ML is right that agents never opt in.
- **V3 / V4:** not relevant under PKG. If PUB wins, include methods in an `impl` of a `pub` type (otherwise every method gets past it), and exclude the module that defines `main`.
- **V5:** I change my position on two points.
  - I drop "(or `Option[T]`)". Fill in the real return type, `Result[Int, E]`, as Web and AI/ML do.
  - I move `unreachable()` to a `note:`. DevOps is right that a second `help:` competes with the first under F5.
  - `@allow(PanicInLibrary)` goes in a `note:`.
  - PLT's `@requires`: I accept it, but only in a `note:` and only worded as "state the caller's duty with `@requires(...)` and remove the check". If the `panic` stays in the body, the lint still fires, so the help must not imply that adding `@requires` alone is the fix (F5: never name a repair that does not work). The text must also not suggest `@requires` plus renaming `panic` to `unreachable`, which is the same rename by another route.
  - I reject DevOps' "turn off for applications" note. Under PKG, applications never see the lint.
- **V6:** agree, `@trusted` does not suppress it.
- **V7:** agree, no machine-applicable fix. Changing to `Result` changes the signature.
- **V8:** keep it. A reference to built-in `panic` used as a value (`let f = panic`, or passing it as a `fn(Str) -> Never`) fires too. Otherwise one `let` defeats the lint. It costs nothing because the check uses the same resolution.

**Stable, ready to vote.** PKG with `PanicInLibrary` (W0705), warn by default; V5 as above, V6 yes, V7 yes, V8 yes.

##### Web/Scripting

###### Web/Scripting — Phase B round 1

###### I change my main position: PUB → PKG

After reading Sys and PLT, I concede that PUB puts its false positives on the wrong people. With PUB, every multi-module app (a web service with `routes.bl`, `db.bl`, `auth.bl`) warns on its own `pub` helpers. App authors are the 90% case, and they would see a library warning in code that is not a library. PLT is right: `pub` means "visible to other modules", not "visible to other packages". My own Phase A answer for that case was a package-wide off switch. That means the default is wrong for most users.

PKG gets the 90% case right. An app package (entry has `fn main`) and a single-file script are silent. A package with no `main` is a library, and its author is the audience for this lint. The rule is explainable in one sentence: "your package has no `fn main`, so it is a library; return a Result." That is a 5-minute concept, as long as the diagnostic says it:

```
warning[W0705]: PanicInLibrary: `panic` in library package `ringbuf`
  --> src/ringbuf.bl:4:9
   |
 4 |         panic("pop on empty ring")
   |         ^^^^^^^^^^^^^^^^^^^^^^^^^^ a caller cannot handle this
   = help: if a caller can cause this error, return `Result[T, E]`
   = note: package `ringbuf` is a library because `src/ringbuf.bl` has no `fn main`
   = note: if this path can never run, use `unreachable()`; for a broken invariant, add `@allow(PanicInLibrary)` to `pop`
```

The "is a library because" note answers the first Stack Overflow question before anyone asks it.

###### Rebuttals

- **MOD (DevOps):** it is worse than PUB for apps. It fires on every module without `main`, private fns included, so a 10-module app warns everywhere. The LSP/CI agreement argument is valid, but PKG keeps it: the entry module is already resolved for every package build, and LSP already loads the package. A loose file with no package is never a library.
- **R / M2 (Min):** Min says the table calls invariant panics correct. Agreed. That is why the cost is one `@allow` line, not a rewrite. Off-by-default (V2) is dead on arrival for AI-written code (AI/ML) and has no precedent in Blink (F8). Removing the lint leaves library authors with no tool, and Go shows where that leads.
- **Min on "inventing library":** PKG adds no manifest field and no directory rule, only one sentence that derives the term from a fact the compiler already has. The spec already says "library" (F9). PKG defines that word, it does not add a concept.

###### Variations

- **V1 name:** with PKG, `PanicInLibrary`. The word is now defined, so the name is honest. (If PUB wins: `PanicInPublicFn`.)
- **V2 level:** warn.
- **V3/V4:** moot under PKG. If PUB wins: `pub fn` plus pub-type impl methods, and exclude the `main` module.
- **V5 help:** one `help:` only (F5), naming `Result[T, E]`. I drop my fill-in of the real return type: in a private helper it adds noise, and `T` reads fine. No `Option[T]` and no `@requires` in `help:`. Each extra repair is one more choice a beginner cannot rank. `@requires` can go in the `blink explain W0705` text. `unreachable` and `@allow` go in a `note:`. Drop DevOps's "turn off for an application" note, because PKG never fires in apps. I concede F7: `"off"`, not `"allow"`.
- **V6:** `@trusted` does not suppress it. Agree.
- **V7:** no auto-fix. Agree.
- **V8:** a value use of `panic` fires. Agree, it closes a cheap hole.
- Sys/PLT open edge: a library whose entry has a demo `main` reads as an app. Accept it, and make the spec state it plainly.

**Stable, ready to vote:** PKG (`PanicInLibrary`, W0705, warn), second choice PUB, against MOD and R.

##### PLT

**PLT, Phase B round 1**

**On R (Min).** Min's best point: the §2.20 table calls `panic(msg)` correct for "any other programmer error", so a default-on lint fires on code the spec blesses. I accept the premise but not the conclusion. The lint does not say "this code is wrong". It says "this partiality is not visible in the interface". At a package boundary, the "programmer error" is nearly always the *caller's* error, which is a precondition. Blink has a construct for exactly that: `@requires` (F10). The caller sees it, and the compiler checks it at each call site. So the table and the lint agree. Inside your own package a panic is your own invariant. At the boundary it should be either a `Result` or a stated precondition. Removing the lint leaves `Never` as the only signal, and `Never` says nothing. R stays my last choice.

**On MOD (DevOps).** Per-file decidability is a real property, but the boundary is wrong. In a multi-module app, every non-`main` module becomes "library", so MOD has the same semantic mismatch I rejected in PUB, with more false positives. The LSP already resolves the package entry to resolve imports, so PKG costs one fact per package that the tool already has. The verdict is still stable across edits in other files, unless you edit `main` in the entry file, and that edit really does change what the package is.

**On PUB (Web, AI/ML, Min M2).** Two flaws. (1) Moving the `panic` into a private helper evades it, so the rule depends on where code sits, not on what the code means. (2) `pub` is module visibility, not package visibility, so apps get false positives. AI/ML says "a model can decide it from one function". That is true, but a rule that is easy to apply and keyed on the wrong property trains the wrong habit: split out a helper.

**Concession (Sys's point).** Under PKG, a library that ships a demo `main` in its entry module is classed as an app. I accept this false negative. The spec should say the rule moves to "the library target" if Blink ever adds a lib/bin split.

**Ranking:** PKG > MOD > PUB > R.

**Variations**
- **V1:** if PUB wins, the name must match the rule exactly: `PanicInPublicFn` if only `pub fn`, `PanicInPublicApi` if V3 adds methods.
- **V2:** warn. An off-by-default lint contradicts "a lint warns" (F9), and nothing ships off today (F8).
- **V3 (if PUB):** include methods in an `impl` of a `pub` type. Callers outside the module can call them just like a `pub fn`, so leaving them out is incoherent.
- **V4 (if PUB):** exclude the module that defines `fn main`.
- **V5:** first `help:` = `Result[<ret>, E]`, with the real return type filled in (Web/AI/ML). "(or `Option[T]`)" is fine, because it is the same total-function repair. **I concede the format:** F5 wants one converging help, so `@requires(...)` moves to a `note:`. The note keeps `unreachable()` and `@allow` and says when each applies: "if a caller must meet a condition, state it with `@requires(...)`; if this path can never run, use `unreachable()`; for a broken internal invariant, add `@allow(<Name>)`". I still want `@requires` named, because it is the only repair that keeps the signature and makes the partiality visible. DevOps's "turn off for applications" note: not needed under PKG, fine under MOD/PUB.
- **V6:** `@trusted` does not suppress it. Agree.
- **V7:** no machine-applicable fix. Agree: every real repair changes the interface.
- **V8:** a value use of built-in `panic` (`let f = panic`) fires. Agree strongly. Without it, binding `panic` to a value or wrapping it in a lambda evades the lint, and a rule keyed on resolution has to cover every occurrence that resolves to the built-in, not only call syntax.

**Stable, ready to vote.**

##### DevOps

**DevOps/Tooling: Phase B round 1**

**I move from MOD to PKG.** I chose MOD because I thought a per-file rule was the only way to keep the LSP and CI in step. PKG keeps them in step too. The verdict is a pure function of one fact in the package's own source: does `src/<name>.bl` declare `fn main`? The LSP already finds `blink.toml` and the entry module to resolve imports, so it costs one more lookup. When an edit adds or removes `main`, the LSP sends new diagnostics for the open files of that package. rust-analyzer does the same when `Cargo.toml` changes. The importer never changes the verdict, and that was my real test.

PLT's argument against PUB applies to MOD as well. In a multi-module application, every `handlers.bl` would warn. My own "turn it off for an application" note was a patch for that false positive. PKG removes the false positive, so I withdraw that note (V5).

**Against PUB (Web, AI/ML).**
- It fires on the internal `pub` helpers of every multi-module application. To an app author those are false positives, and users who see false positives turn the lint off.
- It misses a panic in a private helper that a `pub fn` calls. That is the common shape: a check in a helper. A lint that misses the common case and flags the harmless one is the worst diagnostic surface.
- AI/ML says PUB can be decided from the text in front of the model. PKG can be too, if the diagnostic shows its one fact:

```
warning[PanicInLibrary]: `panic` in library code
  --> src/ringbuf.bl:4:9
   |
 4 |         panic("pop on empty ring")
   |         ^^^^^^^^^^^^^^^^^^^^^^^^^^ the caller cannot handle this
   |
   = help: return `Result[T, E]` so the caller can handle this error
   = note: package `ringbuf` is a library: `src/ringbuf.bl` declares no `fn main`
   = note: use `unreachable()` only for a path that can never run
   = note: for a broken invariant, add `@allow(PanicInLibrary)` to `pop`
```

An agent reads the reason and the escape from the output itself.

**Against R (Min).** If we delete the lint, CI has no code to gate on. The §2.20 table then binds nobody, and lib/std's zero-panic state has nothing to keep it there. Min says the table calls an invariant panic correct. That is true, and `@allow(PanicInLibrary)` is how the author records that it is the table's "other programmer error" case. One line per function is a fair price for a greppable record.

**Variations:**
- **V2:** warn. F8: no warning ships off by default today. An off default would be a first, and it would do nothing for generated code.
- **V5:**
  - The first `help:` names `Result[...]`. Fill in the real return type when it is known (`Result[Int, E]`), because that output can be copied directly. I do not want Sys's "(or `Option[T]`)": that puts two repairs on one line.
  - `unreachable` goes in a `note:`, not a second `help:`. That keeps one repair line (F5) and keeps it away from the rename that Q3a forbids.
  - Keep `@requires` out of the help. With `@requires` added, the guarded branch can never run, so the warning stays until the author also changes `panic` to `unreachable`. Shown alone, that repair is incomplete, and in two steps it is the forbidden rename. PLT can have it as a `note:` at most.
  - Add the "package is a library" note above.
- **V6:** `@trusted` does not suppress the lint. Agree.
- **V7:** no machine-applicable fix. Agree.
- **V8:** yes, a value use (`let f = panic`) also fires, with the span on the reference. Otherwise the lint is easy to get around.
- **Sys caveat:** a package whose entry module has both library code and a `main` counts as an application. The spec should say so and should say the rule later reads a lib/bin field if one is added. The name and code stay.

**Position:** PKG, `PanicInLibrary` W0705, warn, with V5/V6/V7/V8 as above. Stable, ready to vote.

##### AI/ML

###### AI/ML: Phase B round 1

**I change my main option from PUB to PKG.**

PLT's argument (Proposal B) changed my mind. I first read it as a semantics point, but it is also a fix-loop point. Most AI-written Blink will be applications with several modules, and their internal helpers use `pub` because `pub` is how a module exports anything (§10.2). Under PUB, an agent that builds such an app gets W0705 on its own helpers. The help line then tells it to change the signature to `Result`. An agent follows the first `help:`, so it rewrites signatures and every call site for errors that no outside caller will ever see. Otherwise it learns to write `W0705 = "off"` in every project, and then the lint is dead for the libraries it is meant to protect. Either way, false positives in the main use case are worse than false negatives in a rare one.

PKG puts the false negative in the rare case (a library whose entry module has a demo `main`), and Sys and PLT both say the spec can switch to a lib target later without a new name or code. The rule is still one decision a model can learn from the spec: "Is this package's entry file without `fn main`? Then every `panic` outside tests warns." Scripts outside a package never see it. Private helpers count, which answers DevOps's point that a `pub`-only lint misses the common case.

**On R (Min M1):** no. A convention in a table with no tool behind it is not something models learn. Models trained on Rust write `panic!`-shaped code in library paths. The type signature does not push back, because `-> Int` with a `panic` inside type-checks. §2.20 already promises a lint, and this panel exists to name it.

**On MOD:** no. It warns on every non-`main` module of an app, which is the PUB false-positive problem again, and worse.

**Name:** `PanicInLibrary`. Under PKG, "library" becomes a defined term: one sentence in §10.1 ("a package whose entry module declares no `fn main`"). My objection to the name was that the word had no meaning, and PKG gives it one. V1 is moot.

**Variations**
- V2: warn. Agents do not opt in to lints, so a lint that is off by default does nothing for them.
- V3/V4: moot under PKG.
- V5: exactly one `help:` line, naming `Result[<ret>, E]` with the real return type filled in (Web), because an agent can copy it as written. `unreachable()` and `@allow(PanicInLibrary)` go in `note:` lines (DevOps/Web), so the help lines do not compete (F5). I am against `@requires` in the help (PLT). It adds a third repair and a choice the agent has to make on every hit, and the help points at no predicate it could write. I would accept it as a further `note:`. DevOps's "turn it off for an application" note is not needed under PKG, because applications never see the lint. Drop it.
- V6: `@trusted` does not suppress it. Agreed.
- V7: no machine-applicable fix. Agreed. That keeps "rename to unreachable" out of `blink fix`, which is Min's concern from Q1.
- V8: a value use (`let f = panic`) fires. Agreed. The lint is keyed on resolution, as Q3a decided, so a call and a reference must behave the same way. If they did not, the gap would be a trick that agents learn.

**Current position:** PKG, `PanicInLibrary` W0705, warn by default, one `help:` naming `Result[<ret>, E]`, with `unreachable`/`@allow` as notes, V6–V8 yes. Stable, ready to vote.

##### Minimalism

**Minimalism, Phase B round 1**

**Main option: R first, PUB second. I oppose PKG and MOD.**

I still rank R first. Nobody else backs it, so I will not spend the round on it. My vote will say R, and I will name PUB as the outcome I can endorse.

**Against PKG (Sys, PLT).** "A package with no `fn main` in its entry module is a library" is a new concept. It adds no syntax, but users must learn it, and the spec must keep it once a real lib/bin split arrives. PLT admits that a library with a demo `main` is classed as an app. PKG also fires on private helpers. Those are where real invariant guards live (rebalance, slot math). So every correct invariant panic needs an `@allow`. When `@allow` turns up everywhere, it stops carrying information, and the cheaper way out is to rename the call to `unreachable`. That is the outcome Q3a wanted to prevent.

Sys argues that `pub` scope needs a call-graph walk. It does not. PUB is lexical, as all four PUB proposals say. Sys's concern applies only to a transitive version, which nobody proposes.

**Against MOD (DevOps).** MOD fires on every non-main module of every multi-file app, private functions included. DevOps's fourth note ("for an application, turn the lint off") admits the default is wrong for most users. A diagnostic whose help says "turn me off" is a design smell.

**For PUB, rebutting PLT.** PLT says `pub` means "other module", not "other package". True. But a `pub fn` is the interface to code the author does not see while editing, and that is the boundary that matters. `pub` is a word the language already has. PKG's proxy is not.

**V2 default level: I concede to warn.** F8 shows that no Blink lint ships off by default, and F7 shows there is no "allow" level. A default-off lint would add a per-lint default level, which is a new concept. AI/ML is right that an opt-in lint does nothing for generated code. I withdraw "off".

**V1 name:** `PanicInPublicFn`. The scope is a function body. `PanicInPublicApi` names a concept ("API") that the spec does not define, and that is the same flaw as "Library". If V3 extends the reach to methods, `PanicInPublicFn` still fits, because a method is a fn.

**V3 reach:** key on the enclosing fn's own visibility as §10.2 defines it. If a method in an `impl` is callable from another module under §10.2, it is in scope. Add no separate rule about `impl` of a `pub` type.

**V4 exclusion:** accept excluding the module that declares `fn main`. It is decided per file, at no cost, and keeps scripts silent.

**V5 help:**
- One `help:` line, naming `Result[T, E]`. Filling in the real return type is fine.
- `unreachable()` goes in a `note:`. I concede that from my M2: one help line means one repair to converge on (F5).
- Reject `@requires` in the help (PLT). Three repairs in one help line breaks convergence.
- `@allow(PanicInPublicFn)` goes in a `note:`. Yes.
- Reject DevOps's "turn off in blink.toml" note. Under PUB with V4 it is rarely needed, and it invites users to turn the lint off.

**V6:** agree, `@trusted` does not suppress it.

**V7:** agree, no machine-applicable fix. This is the strongest guard against the rename-to-`unreachable` outcome.

**V8:** agree. A value reference resolves to the built-in under the same rule, so it adds no new rule. Without it, a one-line way around the lint exists.

**Stable, ready to vote.** Main option: R, then PUB. Variations: warn, `PanicInPublicFn`, §10.2 visibility, exclude the `main` module, one help line, V6/V7/V8 yes.

#### Phase C — Final vote

| Q | Sys | Web | PLT | DevOps | AI/ML | Min | Result |
|---|---|---|---|---|---|---|---|
| Q1 main option | PKG | PKG | PKG | PKG | PKG | R | PKG 5-1 |
| Q2 default level | WARN | WARN | WARN | WARN | WARN | WARN | WARN 6-0 |
| Q3 bundle B | YES | YES | YES | YES | YES | YES | YES 6-0 |
| Q4 return type in `help:` | FILL | FILL | FILL | FILL | FILL | GENERIC | FILL 5-1 |
| Q5 `@requires` in output | NOTE | NONE | NOTE | NONE | NONE | NONE | 4-2, to Phase D |
| Q6 scope note | SCOPE-NOTE | SCOPE-NOTE | SCOPE-NOTE | SCOPE-NOTE | SCOPE-NOTE | SCOPE-NOTE | SCOPE-NOTE 6-0 |

##### Systems

###### Systems — Phase C ballot

###### Q1 — Main option
**Vote:** PKG
**Reasoning:** The scope is one fact per package: does `src/<name>.bl` declare `fn main`? The compiler and the LSP already resolve that file, so the check is O(1), can be cached, and gives the same verdict in every build and for every importer. Applications stay silent. Every panic in a library warns, private helpers included, so code cannot get past the lint by moving a check into a helper. The check runs only at compile time on a resolution the typechecker already does, so it costs nothing at run time.
**Concern:** A library whose entry module ships a demo `main` is silently classed as an application. The spec must state that edge and say that the rule moves to "the library target" if Blink adds a lib/bin split.

###### Q2 — Default level
**Vote:** WARN
**Reasoning:** No Blink warning ships off by default (F8), and §2.20 already says "a lint warns". A lint that is off by default never runs on the code that most needs it, including code that agents write. The cost of a deliberate invariant panic is one `@allow` line.
**Concern:** Algorithm-heavy libraries may need many `@allow` lines. If those lines are everywhere, reviewers stop reading them.

###### Q3 — Bundle B
**Vote:** YES
**Reasoning:** (a) `@trusted` is for audited unsafe code, not for errors the caller cannot handle, so it must not suppress this lint. (b) Every real repair changes the interface, so a machine fix would either be wrong or be the forbidden rename. (c) The lint is keyed on resolution, so a value reference to `panic` must fire like a call. Otherwise one `let` defeats it. The check reuses the same resolution, so it costs nothing extra.
**Concern:** The value-use rule needs a test for `panic` passed as a `fn(Str) -> Never` argument, not only for `let f = panic`.

###### Q4 — Return type in `help:`
**Vote:** FILL
**Reasoning:** The typechecker already knows the return type at that point, so filling it in costs nothing. `Result[Int, E]` can be copied as written. When the return type is a type parameter, the output falls back to `Result[T, E]`, so it is never wrong.
**Concern:** For a function that returns `Never` or `()`, the filled text must read correctly (`Result[(), E]`) and must not print an odd type.

###### Q5 — `@requires` in the output
**Vote:** NOTE
**Reasoning:** `@requires` is the only repair that keeps the signature and moves the check to compile time. Callers are checked statically, so the precondition costs nothing at run time. It must be worded as "state the caller's duty with `@requires(...)` and remove the check". Adding `@requires` alone does not clear the lint, and the note must not suggest that it does.
**Concern:** People will add `@requires` and then rename the `panic` to `unreachable`, which is the forbidden rename in two steps. The catalog row must say that, after a `@requires` repair, the check is removed and not renamed.

###### Q6 — Scope note
**Vote:** SCOPE-NOTE
**Reasoning:** It is one line that the compiler already knows, and it explains the only non-obvious part of the rule: why this file counts as library code. It prevents the "why does my code warn?" question at no cost.
**Concern:** None worth naming. The note text must name the real entry file path when a package uses a non-default layout.

##### Web/Scripting

###### Web/Scripting — Phase C ballot

###### Q1 — Main option
**Vote:** PKG
**Reasoning:** PKG keeps the 90% case (apps and scripts) silent and puts the warning in front of the one audience that needs it: library authors. PUB and MOD both give false positives to multi-module apps. Users then learn that the lint is noise and turn it off. "No `fn main`, so it is a library" is one sentence that a JS/Python developer understands at once, as long as the output says it (Q6).
**Concern:** a library that ships a demo `main` in its entry module goes silent with no hint why, so the spec must state that edge plainly.

###### Q2 — Default level
**Vote:** WARN
**Reasoning:** an opt-in lint helps nobody who does not already know about it, and those are the people it is for. No Blink warning ships off by default (F8). Apps never see this one under PKG, so warn costs the majority nothing.
**Concern:** private invariant guards in algorithm-heavy libraries pile up `@allow` lines, and authors may answer with a package-wide `"off"`.

###### Q3 — Suppression, auto-fix and value use
**Vote:** YES
**Reasoning:** `@allow` as the only escape is one rule to learn. No auto-fix is right, because every real repair changes a signature and its callers. A value use firing closes a one-line way around the lint at no extra cost to learn, because "resolves to `panic`" already covers it.
**Concern:** a value use in a higher-order call (`list.map(panic)`) may confuse a beginner unless the span and message say "reference to `panic`", not "call".

###### Q4 — Return type in the `help:` line
**Vote:** FILL
**Reasoning:** I change my B1 view. A concrete `Result[Int, E]` is text you can copy and paste, and it shows the beginner exactly what the new signature looks like. That is the biggest DX win in the whole diagnostic. The "noise in private helpers" worry I raised is weak: the real type is never less clear than `T`.
**Concern:** for a generic or `()` return, the filled text (`Result[(), E]`, `Result[T, E]` with a real `T`) must still read naturally, or it looks like a compiler bug.

###### Q5 — `@requires` in the output
**Vote:** NONE
**Reasoning:** each extra repair is one more choice a beginner cannot rank, and the lint's output already has a help and two notes. `@requires` alone does not clear the warning: the `panic` stays and still fires. So it is an incomplete repair, and in two steps it becomes the forbidden rename to `unreachable`. Put it in `blink explain W0705`, where a curious reader finds it.
**Concern:** if NOTE wins, users will add `@requires`, see the warning stay, and file "lint is broken" issues.

###### Q6 — Note that states the scope fact
**Vote:** SCOPE-NOTE
**Reasoning:** "why is my code a library?" is the first Stack Overflow question this lint creates, and the note answers it in place. It also tells an author exactly what fact to change if the classification is wrong. That is cheap, local, and makes PKG self-explaining.
**Concern:** none of note; keep it to one short line so the output does not grow past four lines.

##### PLT

**PLT, Phase C ballot**

**Q1: PKG**
- Reasoning: The lint stands in for interface information that the type `Never` does not carry. That information matters at the package boundary, where one author's invariant becomes another author's crash. PKG decides library status from one fact in the package's own source. The verdict is compositional and the same for every importer, and the helper split that gets around PUB does not get around it. MOD and PUB both key on module structure, which is the wrong boundary.
- Concern: "no `fn main` in the entry module" is a proxy. The spec must state the demo-`main` false negative and say the rule moves to a library target if a lib/bin split is ever added, so the proxy does not harden into a second meaning of "library".

**Q2: WARN**
- Reasoning: §2.20 says "a lint warns" (F9), and no Blink warning ships off (F8). An opt-in lint would add a per-lint default level to the language, which is a new concept with no other user.
- Concern: noisy `@allow` in algorithm-heavy libraries. If that shows up in lib/std, revisit it with data, not by changing the default.

**Q3: YES**
- Reasoning: (a) `@trusted` vouches for a different property (FFI/audit), so letting it suppress this lint would mix two unrelated judgments. (b) Every real repair changes the interface, so no fix is mechanically correct. (c) The rule is keyed on resolution (Q3a). A reference that resolves to the built-in is the same entity as a call, and leaving references out makes the rule depend on syntax, which lets `let f = panic` or eta-expansion get around it.
- Concern: (c) must stay "resolves to the built-in" and never turn into a flow analysis of where `f` goes. Keep the span on the reference only.

**Q4: FILL**
- Reasoning: The typechecker knows the return type, so `Result[Int, E]` is the exact type of the repaired function, and `T` is a needless variable. If the return type is `()` or a type parameter, fall back to the generic form.
- Concern: in a private helper whose return type is itself generic, the filled-in text may read oddly. The fallback rule must be stated, not left to the implementation.

**Q5: NOTE**
- Reasoning: `@requires` is the only repair that keeps the signature and puts the partiality in the contract, where callers see it and the compiler checks it at call sites (F10). Without it, the output pushes every precondition into `Result`, which over-corrects. Wording, following Sys: "if a caller must meet a condition, state it with `@requires(...)` and remove the check". The runtime entry check (§3b.4) then covers the case that once panicked. It must not imply `@requires` plus renaming to `unreachable`.
- Concern: the note might read as "add `@requires` and the warning goes away" while the `panic` stays. Golden tests must pin the "remove the check" clause.

**Q6: SCOPE-NOTE**
- Reasoning: A diagnostic whose firing condition depends on a non-local fact must state that fact. Otherwise the rule cannot be observed from the output, and users (and models) guess at it. One note makes PKG self-explaining at the point of use.
- Concern: the note must name the exact file and fact (`src/ringbuf.bl` declares no `fn main`) and repeat it on every hit, so it stays deterministic and matches the spec sentence word for word.

##### DevOps

**DevOps/Tooling: Phase C ballot**

**Q1: PKG**
- Reasoning: The verdict is a pure function of one fact in the package's own source, the `fn main` in `src/<name>.bl`. The LSP already resolves that file for imports, so `blink check`, the LSP and CI always agree, and the importer never changes the result. Unlike MOD and PUB, it is silent on application modules, so app authors do not learn to turn it off. It covers private helpers, where the common panic sits.
- Concern: When an edit adds or removes `main` in the entry module, the verdict flips for every file in the package. The LSP must send new diagnostics for the whole package on that edit, or the editor shows stale warnings.

**Q2: WARN**
- Reasoning: F8 says no Blink warning ships off by default, so an off default would need a new per-lint default-level concept. A lint that is off does nothing for generated code or for CI. `"off"`/`"error"` under `[lints]` and fn-level `@allow` give every project the control it needs.
- Concern: Libraries with many invariant guards collect `@allow` lines. If teams set `W0705 = "off"` package-wide to stop them, the lint is dead for the code it is meant to guard.

**Q3: YES**
- Reasoning: (a) The lint does not meet the §9.1 audit-gated rule, and `@trusted` should not silently suppress an unrelated warning, as with W0610. (b) Every real repair changes the interface, so no fix is safe to apply automatically. That keeps "rename to `unreachable`" out of `blink fix` and agent fix loops. (c) The lint is keyed on resolution, so a value reference must fire too. Otherwise `let f = panic` is a one-line way around it.
- Concern: The value-use span must point at the reference and not repeat at each later call through `f`, or one binding gives many warnings.

**Q4: FILL**
- Reasoning: The help can be copied as written, and that matters for agents and for the LSP hover. The checker already knows the return type at that point. The type is the nearest enclosing fn or closure, the same body the lint inspects.
- Concern: If the function already returns `Result`, "return `Result[...]`" is the wrong repair, because the signature already has it. The spec must say that the help then reads "return `Err(...)`". Otherwise FILL (or GENERIC) names a repair the author has already made, against F5.

**Q5: NONE**
- Reasoning: Many panics guard internal state, not a parameter, and for those an `@requires` note is noise on every hit. The only complete form is "add `@requires` *and* delete the check", which is two edits and easy to misread as "add `@requires`, keep `unreachable`", the forbidden rename. Put `@requires` in the `blink explain PanicInLibrary` text, where there is room to explain it.
- Concern: Without the note, library authors may not find `@requires` for real precondition panics and will reach for `@allow` instead.

**Q6: SCOPE-NOTE**
- Reasoning: PKG's one hidden input is in another file. The note puts it in the output ("package `ringbuf` is a library: `src/ringbuf.bl` declares no `fn main`"), so a reader or an agent sees why the lint fired and how the scope works, with no docs lookup. It costs one line and answers the first support question before anyone asks it.
- Concern: The note must name the real entry file path that the compiler resolved. If it does not, the note misleads about which file decides.

##### AI/ML

###### AI/ML: Phase C ballot

###### Q1: Main option
**Vote:** PKG
**Reasoning:** Most AI-written Blink will be multi-module apps. PUB and MOD would warn on those apps' own helpers, and an agent then either rewrites the signatures to `Result` for no gain or learns to put `W0705 = "off"` in every project. PKG keeps apps and scripts silent and reduces the rule to one fact a model can learn from the spec: "entry file has no `fn main`, so every `panic` outside tests warns". With the Q6 note, the agent also reads that fact in the output.
**Concern:** A model writing a library may add a throwaway `fn main` to the entry file, so the package reads as an app and the lint goes quiet. The spec and the `blink explain W0705` text should say plainly that this is not a fix.

###### Q2: Default level
**Vote:** WARN
**Reasoning:** Agents do not opt in to lints, so a lint that is off by default has no effect on generated code. No Blink warning ships off by default (F8), and §2.20 says "a lint warns".
**Concern:** If lib/std does not set `W0705 = "error"`, the zero-panic state can drift, and models learn from lib/std.

###### Q3: Bundle B
**Vote:** YES
**Reasoning:** (a) A suppression path that differs from W0610 is one more rule to learn, so match W0610. (b) Without a machine-applicable fix, `blink fix` cannot do the panic-to-`unreachable` rename. (c) The lint is keyed on resolution (Q3a), so a reference to `panic` must fire just as a call does. Otherwise `let f = panic` becomes a trick that agents learn and copy.
**Concern:** The span for (c) must point at the reference with the same help, or the agent sees two different diagnostic shapes for one rule.

###### Q4: Return type in the help line
**Vote:** FILL
**Reasoning:** An agent copies the `help:` text as written. `Result[Int, E]` gives it the real type and saves a step, while `Result[T, E]` makes it work out `T` again on every hit. Filling in the type uses no extra decision and only a few tokens.
**Concern:** The help must fall back to `Result[T, E]` when the return type is generic or `Never`, and the spec must state that fallback, or the output varies in a way a model cannot predict.

###### Q5: `@requires` in the output
**Vote:** NONE
**Reasoning:** Sys and DevOps showed that `@requires` alone does not clear the warning. The guarded `panic` stays, so an agent that follows the note then changes `panic` to `unreachable`. That is the forbidden rename done in two steps. Each extra repair in the output is also one more choice an agent must rank on every hit. Put `@requires` in the `blink explain W0705` text, where a person reading by choice can weigh it.
**Concern:** Leaving it out of the output means agents seldom use `@requires` for a broken precondition, so the contract feature gets less use in library code.

###### Q6: Scope note
**Vote:** SCOPE-NOTE
**Reasoning:** PKG's one weakness for a model is that the trigger fact lives in a different file (the entry module). A note such as "package `ringbuf` is a library: `src/ringbuf.bl` declares no `fn main`" puts that fact in the output. The agent can then act without opening another file, and it does not guess wrongly that the warning is about `pub`.
**Concern:** The note shows agents the way to escape the lint (add a `fn main`). The note must not suggest that, and the explain text should say it is wrong.

##### Minimalism

**Minimalism, Phase C ballot**

###### Q1 — Main option
**Vote:** R
**Reasoning:** The §2.20 table already says when to use `Result`, `unreachable` and `panic`. A lint adds a code, a catalog row, a rule for what counts as a library, and `@allow` lines on correct code. PKG does not reuse a fact the language has. It gives a new meaning to "has no `fn main`" ("this is a library"), and the spec must keep that meaning when a real lib/bin split arrives. If R loses, PUB is my second choice, because `pub` is a word the language already defines.
**Concern:** Under PKG, private invariant helpers in libraries fill up with `@allow(PanicInLibrary)`. When `@allow` is on every such helper, it stops telling readers anything. Authors will then find that renaming `panic` to `unreachable` is the cheaper way to silence the lint.

###### Q2 — Default level
**Vote:** WARN
**Reasoning:** No Blink lint ships off by default (F8). An off default would add a per-lint default level, which is a new concept. §2.20 already says "a lint warns". I conceded this in round 1.
**Concern:** none beyond Q1. A warn default makes Q1's scope rule matter more, because every false positive reaches every user.

###### Q3 — Bundle B
**Vote:** YES
**Reasoning:** (a) keeps one way to suppress the lint, `@allow`, so there is no second channel. (b) is the strongest guard against an automatic rename to `unreachable`. (c) adds no new rule: a value reference resolves to the built-in, the same way a call does (Q3a), and it closes a one-line way around the lint.
**Concern:** Item (c) must stay keyed on resolution and never grow into a search for wrapper functions. Sys already accepts that a `fail` wrapper fires once, in its own body.

###### Q4 — Return type in the `help:` line
**Vote:** GENERIC
**Reasoning:** `Result[T, E]` is one fixed string. Users, agents and the catalog row can match it, and the printer needs no special cases. Filling in the type still leaves `E` open, so the copied line is never a finished repair. The fill-in also adds cases (generic return types, `Never`, `Unit`, closures) that someone must specify and test.
**Concern:** If FILL wins, the spec must say what prints for a generic or `Unit` return type, or two printers will disagree.

###### Q5 — `@requires` in the output
**Vote:** NONE
**Reasoning:** DevOps and Sys showed that `@requires` alone does not clear the warning. The check stays, and the next step is a rename to `unreachable`, which is the forbidden repair done in two steps. Under F5, the output must not name a repair that does not work by itself. `blink explain W0705` is the right place to discuss preconditions.
**Concern:** If NOTE wins, its wording must forbid "add `@requires` and change `panic` to `unreachable`". If it does not forbid that, the note teaches the rename.

###### Q6 — Note that states the scope fact
**Vote:** SCOPE-NOTE
**Reasoning:** If the lint keys on a rule the reader cannot see at the call site, the output must state that rule. Otherwise every user asks "why is this a library?" A rule that exists, but is hidden from the reader, costs more than one note line. I would accept less output under PUB, but `pub` is visible on the line above the panic.
**Concern:** The note must state the fact only ("`src/ringbuf.bl` declares no `fn main`"). It must not suggest adding a `main` to make the warning go away.

#### Phase D — Round 2 (Q5 only)

Result: NONE 6-0. Sys and PLT changed from NOTE. PLT's condition: `blink explain W0705` states "replace the guard with @requires(...); no panic remains".

##### Systems

###### Systems — Phase D (Q5)

DevOps has the strongest point: many library panics guard internal state, not a parameter. For those, an `@requires` note is wrong advice, and it shows on every hit. The compiler cannot tell the two cases apart, so the note cannot be made conditional at no cost. I also correct my own claim: PLT cites a runtime entry check (§3b.4), so `@requires` is not purely a compile-time repair. It also needs two edits before it is complete. Given all that, a note on every hit costs more than it gives. The `blink explain` text has room for the full repair ("state the precondition, then delete the check; do not rename it"). I change my vote to NONE, on the condition that the explain text says so.

###### Phase D vote
**Vote:** NONE
**Reasoning:** The compiler cannot tell a parameter precondition from an internal invariant, so a `@requires` note would show on every hit and be wrong for many of them. The repair needs two edits, and a one-line note invites the second edit to be the forbidden rename. `blink explain W0705` can state the full repair with room to qualify it. The output stays at one help line and the decided notes, so it converges under F5.
**Concern:** The `blink explain W0705` text must name `@requires` and the "delete the check, do not rename" rule; if it does not, the repair disappears entirely.

##### Web/Scripting

###### Web/Scripting — Phase D (Q5)

PLT's strongest point: without `@requires`, the output pushes every precondition into `Result`, which over-corrects. I grant that "state it with `@requires(...)` and remove the check" is a complete, sound repair, because the compiler checks every call site (F10). But the note shows on every hit, and many hits guard internal state with no parameter to state a condition on (DevOps). For those, it is noise that a beginner must read and rule out each time. The over-correction is also smaller than claimed: the `@allow` note already covers "this is a real invariant, keep it". So no author is forced into `Result`. The `@requires` path is the best answer for a subset of hits. That subset is best taught in `blink explain W0705`, which has room for an example of the two-edit repair. A one-line note does not.

###### Phase D vote

**Vote:** NONE
**Reasoning:** the output already has one help and two notes, and a third repair is one more choice a beginner or agent cannot rank on every hit. The complete `@requires` repair takes two edits, and a short note invites doing only half of it, or the forbidden rename. `blink explain W0705` can show the full repair with code, and that is where a reader who wants contracts will look.
**Concern:** library authors may not find `@requires` for real precondition panics, so the `blink explain` text must lead with it right after `Result`.

##### PLT

**PLT, Phase D reply (Q5)**

The "two-step rename" point is wrong. Repaired as stated, the edit is one step: the guard `if i < 0 { panic(...) }` becomes `@requires(i >= 0)`, and the guard goes away. No `panic` stays to rename, and §3b.4's entry check covers the runtime case. So the repair is complete and F5 holds.

DevOps's point is the strong one, and I accept it. Many library panics guard internal state, not a parameter. A note on every hit would name a repair that does not apply to most of them. To show the note only when it applies, the lint would have to inspect the guard condition, and that is a new rule nobody put on the ballot. That noise is real, and `blink explain W0705` has room to state the precondition repair precisely.

###### Phase D vote

**Vote:** NONE (changed from NOTE)

**Reasoning:** The `@requires` repair is sound and complete, but it applies only to panics that guard a caller-supplied value. A per-hit note does not know which case it is in. Per-hit output should name only repairs that apply at that hit. The precondition repair belongs in the `blink explain W0705` text, stated as "replace the guard with `@requires(...)`; no `panic` remains".

**Concern:** If the explain text drops the "replace the guard" wording, the two-step rename that Sys and Min fear becomes the documented path, so the catalog row must pin that wording.

##### DevOps

**DevOps/Tooling: Phase D reply (Q5)**

The best point for NOTE comes from PLT: without `@requires`, the output pushes every precondition into `Result`, which over-corrects. The wording "state it with `@requires(...)` and remove the check" is a complete repair in one step. I accept both points.

But the lint cannot tell a parameter guard from an internal-state guard, so the note would show on every hit. Most library panics guard internal state (`rebalance`, ring slot math), and there `@requires` does not apply. A note that is wrong for most hits trains readers to skip notes, and that includes the `unreachable` and `@allow` notes we need them to read. Showing the note only when the guard reads parameters is a heuristic. A heuristic brings its own edge cases and golden tests. The over-correction risk is real, but `blink explain` can address it, and the first `help:` already says "if a caller can cause this", not "always".

###### Phase D vote

**Vote:** NONE

**Reasoning:** The lint cannot tell whether a panic guards a caller's input, so a `@requires` note would be wrong for most hits. Noise in one note lowers the value of the notes we need people to read. The complete `@requires` repair has two parts and needs room to explain, and `blink explain PanicInLibrary` gives that room. That explain text must cover "add `@requires` and remove the check", and it must forbid the rename to `unreachable`.

**Concern:** If `blink explain` does not lead with the `@requires` repair, real precondition panics end up as `@allow` or `Result` over-corrections.

##### AI/ML

###### AI/ML: Phase D reply on Q5

The strongest NOTE point (Sys, PLT): with the words "and remove the check", the repair is complete and no rename takes place. The §3b.4 entry check also covers the case at run time. I accept that this wording is correct.

My objection is how agents use output. The lint cannot tell whether a `panic` guards a parameter or internal state. So the note would show on every hit, including the many internal-state panics where `@requires` has nothing to name. Agents try the listed repairs in turn. On an internal-state panic, an agent writes an `@requires` that it cannot express, or one that is wrong, and the call sites then fail. That is churn the output caused. A note about the parameter case only helps when the lint knows the panic guards a parameter, and it does not. `blink explain W0705` can teach `@requires` with room for the "remove the check" clause.

###### Phase D vote

**Vote:** NONE
**Reasoning:** The note would be on every hit, but it applies only to panics that guard a parameter, and the lint cannot detect those. For an agent, an option that does not apply is a wrong turn waiting to happen, and a wrong `@requires` breaks call sites across the package. One help line and two notes already give every repair that always applies. Put `@requires`, with "remove the check", in `blink explain W0705`.
**Concern:** Agents seldom read explain text, so library code written by AI will use `@allow` where `@requires` was the better repair.

##### Minimalism

**Minimalism, Phase D reply (Q5)**

The best NOTE argument comes from Sys and PLT. With the words "and remove the check", the repair is complete, and it is the only repair that keeps the signature. I accept that the wording makes it complete. But the note would print on every hit, and DevOps is right that many library panics guard internal state, not a parameter. For those hits, a note about a caller's precondition names a repair that does not apply. That is noise at best, and at worst a wrong repair (F5). The note also asks the author to make two linked edits, and an agent can get one of them wrong. Nobody disputes that `@requires` is a real repair for a precondition. The point is that only some hits have a precondition. `blink explain W0705` can tell those cases apart. A one-line note printed on every hit cannot.

###### Phase D vote
**Vote:** NONE
**Reasoning:** A note that prints on every hit must apply to every hit. `@requires` applies only to panics on a caller's input, not to those on internal state. Its only complete form is two edits, and when an author makes only one of them, the result is the forbidden rename to `unreachable`. Fewer lines in the output also means fewer repairs to rank, and the `help:` line stays the single point to converge on. `blink explain W0705` should describe `@requires` in full.
**Concern:** If the explain text does not cover `@requires`, library authors will use `@allow` for real preconditions, and the contract feature goes unused.

### Final Spec

```blink
// src/stats.bl, in a package whose entry module declares no `fn main`
pub fn average(total: Int, count: Int) -> Int {
    if count == 0 { panic("count is zero") }
    total / count
}
```

```
warning[PanicInLibrary]: `panic()` in a library package
 --> src/stats.bl:2:21
  |
2 |     if count == 0 { panic("count is zero") }
  |                     ^^^^^ this ends the caller's program
  |
  = help: return `Result[Int, E]` and return `Err(...)` for this error
  = note: package `stats` is a library: `src/stats.bl` declares no `fn main`
  = note: if this path can never run, use `unreachable()`
  = note: to keep this panic, add `@allow(PanicInLibrary)` to the function
```

- A package is a library when its entry module `src/<name>.bl` declares no `fn main`. A demo `main` makes it an application. A file outside a package is never library code.
- The lint fires on each reference that resolves to the built-in `panic` (calls and value uses), outside test blocks, private functions included. `todo()` and `unreachable()` are exempt, keyed on resolution.
- Warn by default. `@allow(PanicInLibrary)`, or `W0705 = "off" | "error"` under `[lints]`. `@trusted` does not suppress it. No machine-applicable fix.
- One `help:` line that names `Result` with the enclosing function's return type; three notes: the scope fact, `unreachable()`, `@allow`. No `Option`, no `@requires`, no bare rename to `unreachable`, never a suggestion to add `fn main`.
- `blink explain W0705` lists `Result`, then `@requires(...)` with the check removed, then `unreachable()`, then `@allow`.
