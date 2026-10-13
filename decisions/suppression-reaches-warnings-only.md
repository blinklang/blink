[< All Decisions](../DECISIONS.md)

# Suppression Reaches Warnings Only — Design Rationale

**Gap:** "ERROR_CATALOG.md Conventions example @allow(NonExhaustiveMatch) suppresses an ERROR, while §4.16.8 and the sections/07 annotation table say @allow takes warning names. The compiler applies @allow/[lints] overrides to every non-ice severity today (src/diagnostics.bl lint_apply_override). Decide whether an error-severity diagnostic may be named in @allow or set off/warn in [lints], and if not, which diagnostic refuses it (compare E0837 AuditGatedSuppression, E0842 UnknownDiagnosticName). Flagged as out of scope by all six panelists of [Unknown Diagnostic Names](unknown-diagnostic-name.md)."

**Facts given to the panel.** With the compiler at this point in the tree:

- `@allow(NonExhaustiveMatch)` on a function with a non-exhaustive `match` compiles, and the missing arm panics at run time: `panic: non-exhaustive match at nonex.bl:5`.
- `@allow(TypeError)` on `fn f() -> Int { "hello" }` passes the front end. Then the C compiler fails: `error: returning 'char *' from a function with return type 'int64_t'`.

**Result:**

- **Q1 (6-0, A):** `@allow` arguments and `[lints]` keys reach only names under *Warning Names*. The catalog row decides, not the severity in effect, so a promoted warning stays reachable. A name under *Error Names* (V0003 included) is the new error `NotAWarningName` (E0847). E0847 is refused, not ignored. It cannot be suppressed, every level is refused (`"error"` included), and the compiler reports each bad argument and key.
- **Q2 (6-0, A):** live names outside *Warning Names* and *Error Names* (info names V0001/V0004, and ICE names) also get E0847, not E0842.
- **Q3 (6-0, B):** the name is `NotAWarningName`. All six seats wrote `ErrorNotSuppressible` in Phase A. They moved because Q2 put info names in scope, and a name with "Error" in it would state a false cause for those.
- **Q4 (6-0, A):** the spec states the rule once. The old one-off sentences (E0842 cannot be suppressed, lexer errors, E0843, ICE codes) become consequences of it or pointers to it.
- **Q5 (5-1, A; Min dissent for B):** the first help line says "remove this argument/key". Next comes the named error's own primary help. When a row has a better repair, the catalog holds it as data (V0003 → `@verify(fallback: ...)`; E0501 → widen `@capabilities`). Otherwise the help is generic text with a `blink explain` note. The help never proposes another `@allow` and never proposes `_ => panic(...)`.
- **Q6 (6-0, A):** E0842 is checked first. E0837 and E0847 cover separate name sets, so the spec gives no order between them.
- **Q7 (6-0, Yes):** the named error still fires at its own site. The spec makes this a rule.
- **Q8 (5-1, A; AI/ML dissent for B):** the Conventions example becomes `@allow(UnusedVariable)`.

**Follow-ups taken from the Phase C concerns (the user approved them with the tally):**

- The audit-gated list (§9.1) holds warnings only, and a catalog check in `task ci` must keep it so. Sys, Web, DevOps and AI/ML raised this.
- Per-row repair text must come from the same source as the named error's help, so the two cannot drift. Sys, Web, PLT and AI/ML raised this.
- Next to the `UnusedVariable` example, the catalog says to suppress a warning only when the code is correct as written. This is AI/ML's Q8 concern.
- The release notes must name the breaking change: code that has `@allow(<error>)` today stops compiling. Sys raised this.

**AI-first review:** 5/5 pass. One rule ("suppression takes warnings") replaces four one-off sentences, and the refusal names its cause.

**Moderator note on the Phase A texts:** Sys's Phase A text says that V codes are not in *Error Names* or *Warning Names*. V0003 is under *Error Names* (moderator fact 2 in the Phase B digest), and Sys corrected this in Phase B (V-b).

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated in independent-proposal → debate → vote rounds. The panel texts below are verbatim. Only their headings were changed to bold lines, so they fit this page.

#### Phase A — Independent proposals

##### Systems

**P1 (recommended): only warnings can be suppressed. Naming an error is refused with a new error, E0847 `ErrorNotSuppressible`**

**Rule.** Each `@allow` argument and each `[lints]` key must name a diagnostic listed under *Warning Names*. A name listed under *Error Names* gets E0847 `ErrorNotSuppressible`. Like E0842 and E0843, E0847 is refused, not ignored, and no `@allow`, `[lints]` entry or flag changes it.

The test uses the diagnostic's **catalog** severity, not its effective severity. A warning promoted by `--strict`, by `[lints] = "error"`, or by `--strict-struct-layout` (W0812) stays a warning, so `@allow` still reaches it. The check is one catalog lookup at the write site. It needs no knowledge of which flags are active.

```blink
@allow(NonExhaustiveMatch)
// error[ErrorNotSuppressible]: `NonExhaustiveMatch` (E0004) is an error; only warnings can be suppressed
//   help: handle the missing cases, or add `_ => panic("unreachable")` to make the panic explicit
fn describe(c: Color) -> Str {
    match c {
        Red => "red"
        Green => "green"
    }
}
```

```toml
[lints]
TypeError = "warn"
# error[ErrorNotSuppressible]: `TypeError` (E0300) is an error; [lints] can set levels only for warnings
#   help: remove this key
```

`[lints] E-name = "error"` is also refused. It does nothing, and the simplest rule ("keys name warnings") is one the author can predict. Lexer codes, E0842 and E0843 are already covered, so they need no special case. E0837 stays as it is: an audit-gated name is a warning with its own channel, and its help (`use @trusted(audit: ...)`) differs.

**Catalog migration.** Change the *Conventions* example to a real warning, `@allow(UnrestoredMutation)`. Change line 28 from "*Error Names* or *Warning Names*" to "*Warning Names*", and add the E0847 rule. In `lint_apply_override`, delete the `"warn" && severity == "error"` demotion branch. The write sites then refuse error names. Release notes must name this as a breaking change: code that has `@allow(<error>)` stops compiling.

**Why, from what the hardware sees:**
- Every stage after typecheck (mono, layout, IR, C printer) assumes it gets well-typed input. Probe 6 shows what happens when an error is silenced: `@allow(TypeError)` sends ill-typed IR to C. Where C rejects it, the user gets a C compiler error they cannot read. Where C accepts an implicit int/pointer or int-width conversion, the user gets wrong machine code with no diagnostic. That is worse than any warning.
- If we allowed this, each codegen stage would need defensive paths for input that "should never happen". That is permanent cost in the compiler and loses invariants we use to keep codegen predictable.
- `@allow(NonExhaustiveMatch)` puts a hidden panic branch in the binary. An explicit `_ => panic(...)` arm compiles to the same branch, and the reader can see it. Cost should be visible in the source.
- A `[lints]` key in a dependency's `blink.toml` must not change whether that package's code is sound. If errors stay errors, "it compiled" means the same thing in every package.

**P2 (alternative, I vote against): a closed list of "demotable" errors**

The catalog would mark some errors as policy rules (for example E0501 `CapabilityBudgetExceeded` or E0827 `SkipOutsideTest`), and `[lints] "warn"` could demote only those. I reject this. If a rule can be safely downgraded, it is a warning, and the catalog should list it as one. Names are frozen but severities are not, so the panel can reclassify a diagnostic later. P2 also adds a third severity class that users must learn, and a per-diagnostic flag that must be kept in sync.

**Scope note**

V codes (for example V0003 under `@verify(fallback: "error")`) keep `@verify` as their only control. They are not in *Error Names* or *Warning Names*, so E0842 already refuses them in `@allow` and `[lints]`. I codes (ICE) are unchanged.

**Cross-language**

- **rustc:** `#[allow]` reaches only lints, including deny-by-default lints. You cannot allow a hard error such as E0308 mismatched types. P1 matches this split.
- **Go:** compile errors cannot be suppressed at all. `go vet` findings are a separate tool. The same principle, applied more strictly.
- **GCC:** `-Wno-error=X` undoes only a promotion made by `-Werror`. It does not touch real errors. `-fpermissive` is the exception, and it is widely seen as a mistake. That is the behaviour we have today.
- **TypeScript `@ts-ignore`:** this works only because TS erases types before it emits JS. In Blink, types decide layout and the C that we emit, so suppressing a type error gives undefined behaviour, not a lenient build. That is the main reason Blink must not copy it.

**Vote:** P1. New code E0847 `ErrorNotSuppressible`, checked against catalog severity, cannot be suppressed itself, and the catalog example moves to a warning.

##### Web/Scripting

**Proposal W1 (my pick): errors are not switches. Naming one in `@allow` or `[lints]` is refused.**

**Rule.** `@allow` takes warning names only. A `[lints]` key must be a warning name. If an `@allow` argument or a `[lints]` key names an error-severity diagnostic, the compiler refuses it with a new error, `ErrorNotSuppressible` (the moderator assigns the next free E08xx code). The rule covers every level: `"off"`, `"warn"`, and also `"error"`. `"error"` on an error does nothing, and an entry that does nothing is the silent success that §9.1 says is bad. No `@allow`, `[lints]` entry or `--strict` flag changes `ErrorNotSuppressible`, the same as E0842 and E0843. Like E0842, the compiler reports every bad argument and key, not only the first.

```blink
@allow(NonExhaustiveMatch)
fn label(c: Color) -> Str {
    match c {
        Color.Red => "red"
    }
}
```

```
error[E08xx]: NonExhaustiveMatch is an error and cannot be suppressed
 --> src/paint.bl:1:8
  |
1 | @allow(NonExhaustiveMatch)
  |        ^^^^^^^^^^^^^^^^^^ errors are not lints
  |
help: remove this argument and fix the match: add the missing arms or a `_ =>` arm
note: run `blink explain NonExhaustiveMatch` for details
```

```toml
[lints]
UnusedVariable = "off"      # ok: warning
TypeError = "warn"          # error[E08xx]: TypeError is an error and cannot be suppressed
```

The suppressed error is still reported at its own site. So the user sees two diagnostics: "you tried to turn this off" and the real problem. Neither hides the other.

**Why.**
- Anyone can learn it in under a minute: "warnings are switches, errors are not." That covers 100% of cases with no list to memorize. Python, JS and Kotlin users already think this way: a lint rule can be turned off, a syntax error cannot.
- The current behaviour is a trap. `@allow(TypeError)` makes the error go away and then C compilation fails with `returning 'char *' from ... 'int64_t'`. Each case like this becomes a Stack Overflow question, and none of them has a good answer. §3.1 also says no rule is enforced only at codegen, and today we break that rule.
- `@allow(NonExhaustiveMatch)` turns a compile error into a runtime panic. Swift and Kotlin users switch to these languages to get away from exactly that.

**Migration.** Change the ERROR_CATALOG Conventions example to `@allow(UnusedVariable)`. Change catalog line 28 to say "listed under *Warning Names*", and state the refusal there next to E0842/E0837. §4.16.8 and the sections/07 table already say "warning names", so they need no change. This is a breaking change against the current compiler (`lint_apply_override`), so the release notes must name it. Very few users should hit it, and the help line tells them the fix.

**Cross-language.** TypeScript's `// @ts-ignore` is the warning sign: it silences real type errors, and the TS team then had to add `@ts-expect-error` to limit the damage. Rust's `#[allow]` can only reach lints. Hard errors like E0308 cannot be allowed, and nobody asks for that. Go has no way to turn off a compile error, and its users do not miss one. ESLint lets you turn rules off, but `tsc` errors stay errors.

**Tradeoffs.**
- (+) One rule, one message, and the fix is in the help line. The catalog stops contradicting the spec.
- (+) It closes a real soundness hole and matches the principle behind E0837 and E0842.
- (−) Some errors are policy, not soundness: `CapabilityBudgetExceeded`, `XfailMissingReason`. Under W1 a team cannot turn these off one function at a time. I accept that. If a team needs to bend a policy, the policy rule should have its own escape built in (for example, raise the `@capabilities` budget), not a general off switch.
- (−) A new error code. That is still cheaper than one more special case inside E0842.

**Proposal W2 (alternative, only if the panel wants policy escapes): "default-error lints" as a separate tier**

The catalog gets a third column value. A diagnostic is a **warning**, an **error**, or a **lint that defaults to error** (Rust's deny-by-default model). Only the third kind can be named in `@allow`/`[lints]`. Plain errors are refused as in W1. Each move of a diagnostic into the third tier needs a panel vote.

```toml
[lints]
CapabilityBudgetExceeded = "warn"   # allowed only if the catalog marks it lint-default-error
```

**Tradeoffs.** It is more flexible, but users must now learn three tiers and check which tier each name is in. That brings back the "can I turn this off?" questions. YAGNI: no user has asked for this yet. W1 does not block W2, because the panel can add the tier later without breaking any code that W1 accepts.

**Vote intent**

W1. Errors are refused in `@allow` and in every `[lints]` level, with a dedicated diagnostic that cannot itself be suppressed and a help line that names the real fix. Defer W2 until someone files a concrete need.

##### PLT

**Proposal P1 (my vote): error severity is part of the language, so no suppression channel reaches it**

**Principle.** An error is a judgement that the program is not in the language. Example: `Γ ⊢ e : τ` has no derivation. A program with no typing derivation has no static meaning, so it has no dynamic meaning either. Nothing correct remains for the compiler to lower. The repo already shows this. `@allow(TypeError)` passes the front end and then fails in C. `@allow(NonExhaustiveMatch)` turns a static proof obligation into a run-time panic. The checker reports that the program is total, and the program is not. That is unsound.

A warning is a different kind of judgement. It is a statement about a program that is already well-formed. So suppression is an operation on warnings only:

```
sev(d) = base(d)                       if base(d) = error
sev(d) = fnAllow ∘ lints ∘ strict (warning)   otherwise
```

Errors are fixed points of every override. Warnings may move between off, warn and error, with the precedence the spec already gives (`@allow` beats `[lints]`).

**Rule.** An `@allow` argument or a `[lints]` key that names a diagnostic listed under *Error Names* is refused with a new error, `ErrorNotSuppressible` (E0847). E0847 is itself unsuppressible. This holds for every level, `"error"` included. A no-op entry looks like configuration and hides which kind of diagnostic it names, so the rule is "an error name is never a key", with no case split.

```blink
@allow(NonExhaustiveMatch)   // error[ErrorNotSuppressible]
fn label(c: Color) -> Str {
    match c {
        Color.Red => "red"
    }
}
```

```toml
[lints]
E0300 = "warn"   # error[ErrorNotSuppressible]
W0600 = "off"    # ok
```

Diagnostic shape:

```
error[ErrorNotSuppressible]: `NonExhaustiveMatch` is an error; `@allow` and `[lints]` take warning names only
  --> src/color.bl:1:8
  help: remove the argument and fix the cause: add the missing arm `Color.Green`
```

The help line reuses the primary help of the named error where one exists.

**Check order** (one reason per refusal, so the three refusals do not overlap):
1. Not a live name: E0842.
2. A live, audit-gated warning: E0837.
3. A live error: E0847.

**Compositionality gain.** Today the spec has three special cases: no setting reaches lexer errors, E0843 or E0842. Under P1 all three become instances of one rule. `lint_apply_override` loses its lexer and E0843 branches.

**Promoted warnings stay warnings.** `[lints] "error"`, `--strict` and `--strict-struct-layout` raise a warning's level, but its base severity stays "warning". `@allow` still reaches it, so the precedence decision is unchanged. W0734 ("never an error") is consistent with this.

**V0003 ContractUnverifiable.** Its own channel is `@verify(fallback: ...)`, which is part of the program and not a suppression. That matches the contracts decision that no `blink.toml` setting removes checks. In general, an error's only way out is to change the program.

**Migration.**
- ERROR_CATALOG *Conventions* line 27: replace the example with `@allow(UnusedVariable)` and add "`@allow` and `[lints]` take warning names only; an error name is `ErrorNotSuppressible` (E0847)."
- §4.16.8: add an "Error names" paragraph next to "Unknown names" and "Invalid levels".
- This is a breaking change. Release notes must name it: code that used `@allow(<Error>)` or `[lints] E… = "off"/"warn"` now fails to build. That code was already unsound or broke in C.

**Why not reuse E0842 or E0837?** E0842 means "this name does not exist". Here the name does exist, so reusing it gives a false message. E0837 means "a record would be lost", and its closed list holds warnings. Using one code per cause class keeps `blink explain` precise.

**Cross-language.** Rust is the closest model: `#[allow]` reaches lints only, and hard errors such as E0004 cannot be allowed. OCaml's `[@warning]` reaches warnings only, and type errors are never silenced. Haskell's `-fdefer-type-errors` is a dev-time mode that still inserts a run-time error at each site. That is what we get by accident today, and we have no such mode by design.

**Proposal P2 (not recommended; recorded for completeness): deny-by-default lints**

Add a catalog column `kind: hard | lint`. A lint may default to level "error", and `[lints]` could then demote it. This is Rust's deny-by-default model.

I reject it now for two reasons:
- No current error is a policy rule that someone has shown a need to demote. `CapabilityBudgetExceeded` and `UndeclaredModuleState` each have their own channel in the program (edit `@capabilities`, or declare the state).
- The *Error Names* / *Warning Names* split already is the hard/lint split.

If a real need appears, add the diagnostic as a warning and set its default level in the catalog. The soundness rule above does not change.

**Tradeoffs.** P1 costs users one escape hatch. That hatch only ever produced C failures or run-time panics where the checker had reported a proof. P1 gains a typing story that holds: if the checker accepts the program, it is well-formed. With today's override, that statement is false.

##### DevOps

**Proposal 1 (primary): `@allow` and `[lints]` reach warnings only. Naming an error is refused, with a new error code.**

**Rule.** An `@allow` argument or a `[lints]` key must name an entry under *Warning Names*. If it names an entry under *Error Names*, the compiler reports the new error `ErrorNotSuppressible` (E0847, next free code). This holds at every level, including `"off"`, `"warn"` and `"error"`. It is refused, not ignored, and no `@allow` or `[lints]` entry changes it. Like E0842, the compiler reports every such argument and key, not only the first.

```blink
@allow(NonExhaustiveMatch)
fn color_name(c: Color) -> Str {
    match c {
        Color.Red => "red"
    }
}
```

```
error[ErrorNotSuppressible]: `NonExhaustiveMatch` is an error; @allow takes warning names only
  --> src/paint.bl:1:8
   |
 1 | @allow(NonExhaustiveMatch)
   |        ^^^^^^^^^^^^^^^^^^ an error stops the build; no setting turns it off
   = help: remove `NonExhaustiveMatch` from @allow, then fix the match (add the missing arms or a `_` arm)
   = note: run `blink explain NonExhaustiveMatch`
```

```toml
[lints]
E0300 = "warn"    # error[ErrorNotSuppressible]: span on the key; help: remove this line
```

**Why a new code, not E0842 or E0837:**
- E0842 means "no live diagnostic has this name". `NonExhaustiveMatch` is live, so E0842 would tell the user something false. Its help logic also suggests the nearest name, which is the wrong repair here.
- E0837 means "use `@trusted(audit:)` instead". That is a different repair. §3.1 says the first `help:` must name the real repair, so each refusal gets its own code and its own help. LSP quick-fixes key on the code, so the codes must stay separate.
- The ordered checks at an `@allow`/`[lints]` site are: lexer and E0843 first, then E0842 (not a name), then E0837 (audit-gated), then E0847 (error-severity). Each one has a single repair.

**Per-error help.** The generic help is "remove it". Where a better repair exists, the help names it:
- V0003 ContractUnverifiable: change `@verify(fallback: ...)`.
- E0501 CapabilityBudgetExceeded: widen `@capabilities`.

**Migration:**
- The ERROR_CATALOG *Conventions* example becomes `@allow(UnrestoredMutation)`.
- §4.16.8 and the sections/07 table say "warning names" (they already do).
- Line 28 changes from "*Error Names* or *Warning Names*" to "*Warning Names*", and adds the E0847 rule.
- `lint_apply_override` drops the `"warn"`-demotes-error branch and the error-to-"off" path. The write sites refuse up front, and the apply step becomes a safety net, the same as the audit-gated pattern already there.
- This is a breaking change, so the release notes name it.

**Tooling payoff:**
- **LSP:** completion inside `@allow(` and under `[lints]` lists warning names only. Today it would offer about 107 error names that are traps. The E0847 code action removes the argument, or the line when it is the last one.
- **CI:** "the build has zero errors" becomes a fixed contract. Today a teammate's `blink.toml` line `E0300 = "warn"` silently demotes a type error, and the gate passes. Worse, the build then fails in C (`returning 'char *' from ... 'int64_t'`) or miscompiles silently, where C accepts the code. The second case breaks §3.1, "no rule is enforced only at codegen".
- **Dependencies:** a library cannot ship `@allow(TypeError)` and push a C compiler failure onto every user downstream.
- **Diagnostics:** the user sees a Blink error that points at the real problem, not a C error in generated code.

**Tradeoff.** It takes away the "let me compile anyway while I fix the rest" escape hatch. That hatch never existed in a safe form: the probe shows it gives a run-time panic or a C failure. Go has the same model: errors are not configurable, and `go vet` and staticcheck findings are. TypeScript's `// @ts-ignore` is the opposite model, and the TS ecosystem is still cleaning up after it with `@ts-expect-error` and lint rules that ban `@ts-ignore`.

**Proposal 2 (fallback, if the panel wants some errors demotable): only a closed, tagged list**

If someone shows a real policy error that users need to tune, the catalog gets a "Configurable" column. Only rows tagged in that column may take `[lints]` `"warn"`, and `@allow` still never reaches them. The default list is empty, and each entry needs a panel vote. This is the mirror image of the audit-gated closed list. Any untagged error is E0847, as in Proposal 1.

My read is that no current E-code qualifies. Every row in *Error Names* is a soundness, name-resolution, manifest or test-runner rule, and each one has a source-level fix. So I vote Proposal 1. I would accept Proposal 2 only with an empty list.

**Edge rules (both proposals)**

- **`[lints]` `"error"` on an error.** It is a no-op, but it is still refused (E0847). `[lints]` is a warnings table, and a refused no-op keeps the LSP schema and the completion list simple. I hold this loosely.
- **Warnings escalated by a flag** (`--strict`, `--strict-struct-layout` for W0812). These stay warning names, so `@allow` reaches them. The existing precedence holds: function-level `@allow` beats the escalation.
- **ICE (I) codes and Info names.** No change.

##### AI/ML

I propose that `@allow` and `[lints]` reach warnings only. Naming an error-severity diagnostic in either one is refused, not ignored, by a new error with its own name. This is my recommendation as the AI/ML panelist.

**Why this matters for AI users**

An agent under pressure to make the build pass is a real user of this language. Today `@allow(TypeError)` gets past the front end and then fails in the C compiler, and `@allow(NonExhaustiveMatch)` compiles and panics at run time. To an agent, each error message now looks like an instruction to add an `@allow`. That is the cheapest edit that turns the build green. The agent learns that it works, and the codebase becomes training data that teaches the next model the same trick. If errors can be suppressed, every error carries a hidden "or silence me" option. That adds a decision point at every error site.

**Proposal A (recommended): errors are never suppressible, and the compiler says so**

**Rule.** An `@allow` argument must name a live warning. A `[lints]` key must name a live warning. Any level given to an error key is refused, `"error"` included. One rule, no exceptions table: "suppression channels take warnings."

```blink
@allow(NonExhaustiveMatch)
fn describe(c: Color) -> Str {
    match c {
        Color.Red => "red"
    }
}
```

```toml
[lints]
E0004 = "warn"
```

Diagnostic shape (new name, for example `ErrorNotSuppressible`, next free E08xx):

```
error[ErrorNotSuppressible]: `NonExhaustiveMatch` is an error; `@allow` takes warnings only
  --> color.bl:1:8
   |
 1 | @allow(NonExhaustiveMatch)
   |        ^^^^^^^^^^^^^^^^^^
   = help: remove this argument and fix the error it names
   = note: run `blink explain NonExhaustiveMatch` for the fix
```

For the `[lints]` case the span is the key, and the help says "remove this key". Like E0837 and E0842, no `@allow`, `[lints]` entry or `--strict` changes it, and the compiler reports every such argument and key, not only the first. The original error still fires too. The agent then sees both the refusal and the real problem, so the first `help:` leads to the real fix and not to another suppression try. This keeps the §3.1 rule that diagnostics converge on one repair.

**Why a separate name and not E0842.** E0842 means "this name does not exist", and its help suggests a nearby name. For `NonExhaustiveMatch` that is false: the name exists. A message that does not match the cause makes an AI try spelling fixes. One cause per diagnostic name is easiest to learn.

**Why also refuse `"error"` on an error key.** It does nothing, so allowing it adds one more case to learn, and it invites `"warn"` as the next edit. A flat rule, "error keys are refused", has no special cases.

**Catalog migration.** Change the *Conventions* example to a real warning, for example `@allow(TodoInCode)`. The spec should never show the forbidden pattern. Models copy examples literally.

**V and I codes.** I-codes are already unsuppressible. V0003 stays under `@verify(fallback: ...)` only, and naming it in `@allow` or `[lints]` gets the same refusal. Each diagnostic has one control channel.

**Compiler impact.** In `lint_apply_override`, an error-severity target gives the refusal and not "off"/"warn". This is a breaking change, so the release notes must name it.

**Proposal B (rejected): a "suppressible error" tier**

Mark some policy errors as suppressible. The cost: every catalog row needs a flag that an AI must memorize, and the boundary between soundness and policy is not visible from the name. Every error message then raises "is this one of the suppressible ones?" If a rule is really policy, the correct fix is to reclassify it as a warning, with `[lints]` `"error"` available for strict teams. That is a per-diagnostic panel decision, not a channel rule. I vote against B.

**Tradeoffs**

- **For:** one rule that fits in one sentence. The C compiler and the run-time panic are no longer an escape route. The error text shows the repair in the same place.
- **Against:** no escape hatch for a false-positive error. That is correct: a false-positive error is a compiler bug, and an escape hatch would hide it. Code that relies on `@allow(SomeError)` today breaks. It was already broken, just at C compile time or run time.

**Cross-language notes**

- **Rust:** `#[allow]` reaches lints only. Naming a hard error like E0308 gives "unknown lint", which is confusing because the code exists. My separate name fixes that.
- **TypeScript:** `// @ts-ignore` silences type errors. It is the most-generated AI "fix" for type errors, and it spreads through training data. That is the failure Blink must not copy.
- **Go:** vet checks are not suppressible, and compile errors are never suppressible.

**Side finding (not part of the vote)**

§9.1.3 (sections/07 ~line 1254 and the table at ~line 1430) shows `@allow(W0816)`, which uses a code. Under E0842 that is refused. That spec text should become `@allow(<W0816's name>)`. It is the same kind of copied-wrong-example hazard.

##### Minimalism

**Proposal M1 (my vote): only warnings can be suppressed. Severity belongs to the catalog, not to the user.**

**Rule.** Each `@allow` argument and each `[lints]` key must name a live diagnostic listed under *Warning Names*. If the name is under *Error Names*, or is a V or I code, the compiler refuses it with one new diagnostic, `ErrorNotSuppressible` (next free E08xx). The compiler does not ignore the name.

- Levels stay `"off"`, `"warn"` and `"error"`. Because keys are warnings only, `"warn"` can no longer demote an error.
- Promotion stays as it is: `--strict`, `--strict-struct-layout` and `"error"` under `[lints]` still promote warnings.
- The test is the name's row in the catalog, not the severity at the time of the diagnostic. A W-code that `--strict` promoted to an error is still a warning name, so `@allow` still reaches it. Today's precedence rule depends on this.

```blink
@allow(NonExhaustiveMatch)
fn describe(c: Color) -> String {
    match c {
        Color.Red => "red"
    }
}
```

```
error[ErrorNotSuppressible]: `NonExhaustiveMatch` (E0004) is an error; `@allow` takes warning names only
  --> shapes.bl:1:8
   = help: remove `NonExhaustiveMatch` from `@allow`, then fix the error
```

```toml
[lints]
E0004 = "warn"   # error[ErrorNotSuppressible]: `NonExhaustiveMatch` is an error; `[lints]` keys must be warnings
```

**Check order:**
1. Not a live name: E0842.
2. A live error, V or I name: the new code.
3. An audit-gated warning: E0837, as today.

**Why this is subtraction, not addition.** The new code removes four special-case sentences from the spec, because each one becomes a consequence of the single rule:
- "E0842 is unsuppressible"
- "no setting suppresses a lexer error"
- "E0843: no `@allow`/`[lints]` changes it"
- "I codes cannot be suppressed" (catalog line 68)

The new rule is one sentence: *suppression reaches warnings; errors are not negotiable.*

**Why errors must not be suppressible at all.** The moderator's probe shows what happens today:
- `@allow(TypeError)` produces a C compiler failure.
- `@allow(NonExhaustiveMatch)` produces a run-time panic.

An error in Blink means the program has no defined meaning. A suppression channel for errors makes every soundness rule optional. Each later feature then has to ask "what if this check is off?", and that interaction cost grows with each new check.

**What about errors that are only policy?** If a rule should be negotiable, it is a warning by definition. Move it to *Warning Names* with a new code (names are frozen, codes are never reused). Do not add a second class of "demotable errors." Severity is one fact per diagnostic, and the catalog owns it.

**Migration:**
- The catalog's Conventions example becomes `@allow(TodoInCode)`.
- §4.16.8 already says "warning name". Add the refusal sentence there and in §9.1's neighbour text.
- Release notes name the break. Code that used it was already wrong.
- `lint_apply_override` stops applying overrides to error severity.

**Tradeoffs.**
- **Cost:** one new code. The new code is better than reusing E0842: a message that says a real error name is "unknown" would be false, and the name `UnknownDiagnosticName` is frozen.
- **Cost:** a user hit by a false-positive error has no escape hatch. That is a compiler bug, and the fix is a bug report, not a pragma. Go has kept that position for 15 years.
- **Gain:** "is this error real?" always has the answer "yes". AI agents and people cannot paper over type errors. That property matters most for a language whose code becomes training data.

**Options I reject**

**M2: keep today's behavior (any severity is reachable).** This is "do nothing". It is the TypeScript `@ts-ignore` / `@ts-nocheck` path, which is the clearest example of a suppression feature that destroys the type system's guarantee and spreads through codebases. The probe proves it gives undefined behavior. Reject.

**M3: a per-error "demotable" whitelist.** This creates two tiers of errors, a membership criterion to argue about for each new code, and a catalog column. It is the C++-committee pattern. Reclassifying the error as a warning already does the job. Reject.

**Cross-language note**
- **Rust:** `#[allow]` reaches only lints, and hard errors cannot be named. Deny-by-default lints are lints, not errors. M1 is the same split.
- **Go:** no suppression at all.
- **Swift:** no per-site warning suppression.
- **TypeScript:** `@ts-ignore` is the warning against M2.

**Side finding, not in scope**
§9 (sections/07, lines 1254 and 1430) says "`@allow(W0816)`". That passes a code to `@allow`, which E0842 already refuses. Fix the spec text to `@allow(<W0816's name>)` as a separate chore.

#### Phase B — Debate (one round)

All six proposed the same primary option in Phase A. The moderator's digest flagged seven variations (V-a to V-g) for debate and surfaced four facts. Five seats replied STABLE; PLT's reply left the name and scope open, which went on the ballot as Q2/Q3. The replies, verbatim:

##### Systems

**Option 1:** no objection. Code is E0847 (fact 1).

**V-a Info names.** Refuse them too, with E0847, not E0842. An info name is a live name, so "unknown" would be a false message. The rule becomes: only a name under *Warning Names* is accepted; any other live name is E0847. The message gives the real class: "`ContractProven` is an info diagnostic; only warnings can be suppressed". Info output already has its own display control, so `@allow` adds nothing.

**V-b V0003.** I was wrong: fact 2 puts it under *Error Names*. So it gets E0847 like any error. Help points to its own channel: "change `@verify(fallback: ...)`".

**V-c Spec restructure.** Yes. One rule replaces the special cases. Keep one "why" sentence for lexer errors (the recovered token is not the text the author wrote), because the reason differs even if the rule is the same. In the compiler, the check moves to the write site. `lint_apply_override` then handles warnings only and keeps no severity branches. An error that reaches it is an ICE, not a silent no-op. That gives one invariant: typecheck errors always stop the pipeline before mono/IR.

**V-d Help line.** plt's rule plus devops's overrides. The first part is fixed: "remove this argument". Then reuse the named error's primary help. Where a better repair exists, give an override in the catalog (V0003: `@verify(fallback: ...)`; E0501: widen `@capabilities`). Keep these as data in the catalog row, not as special cases in code.

**V-e Check order.** E0842 first, because an unknown name has no class. E0837 and E0847 cover disjoint sets: audit-gated names are warnings. Order between them cannot change the result. The spec should say they are disjoint. Then order is not a rule that needs a vote. If a vote is required: plt/devops order.

**V-f Named error still fires.** Yes, state it. E0847 at the `@allow` argument, plus the original error at its own site. If the second error is hidden, the author fixes the annotation and is then surprised by a "new" error.

**V-g Example.** `@allow(UnusedVariable)`. It is the warning most readers know. I drop UnrestoredMutation; I do not insist.

STABLE — ready to vote

##### Web/Scripting

**Option 1:** no objection. I agree the test should be the catalog row, not the effective severity. A promoted warning stays reachable by `@allow`.

**V-a Info names.** Refuse them with E0847, not E0842. E0842 says "unknown name", and `ContractProven` is a real name, so that message would confuse the user. E0847 should cover every live name that is not under *Warning Names*: errors, info and I codes. The message states the severity: "`ContractProven` is an info diagnostic; it never fails a build, so there is nothing to suppress". The rule stays "`@allow` and `[lints]` take warning names", and E0842 keeps its meaning of "no such live name".

**V-b V0003.** It is listed under *Error Names*, so it gets E0847 like any other error. The help points to its own channel: "use `@verify(fallback: ...)`". This is not a special rule. It is the V-d rule using V0003's own help text.

**V-c Spec restructure.** Yes. One rule ("only warning names") replaces the special-case sentences. The spec may keep each old sentence as a short "for example" so that readers who search for "lexer error" or "E0843" still find the answer, but no sentence may add a separate rule.

**V-d Help line.** Use plt's rule as the default. The help names the error and reuses that error's primary `help:` when it has one ("add the missing arms or a `_ =>` arm"). An error with its own escape channel uses that channel instead (V0003 → `@verify(fallback: ...)`, E0501 → widen `@capabilities`). The fallback is "remove this argument and fix the error it names", plus a `note:` with `blink explain <Name>`. The help never offers a different `@allow` as the fix, the same as E0842.

**V-e Check order.** Unknown, audit-gated and error/info names are disjoint sets, so every name gets exactly one of E0842, E0837 or E0847, and the order changes no output. The spec should say the sets are disjoint, not give an order. If the panel wants an order anyway, I take E0842 → E0837 → E0847 (plt/devops).

**V-f The named error still fires.** This must be in the spec. Refusing the `@allow` must not hide or replace the error at its own site. The user gets both reports in the same run. The same applies to an E0847 from `[lints]`.

**V-g Example.** `@allow(UnusedVariable)`. Every JS/Python dev knows `no-unused-vars` and `# noqa: F841`, so it needs no explanation. I am not attached to it. `TodoInCode` is also fine.

**V-h** Settled: E0847.

STABLE — ready to vote

##### PLT

**Option 1:** no objection. The test is the catalog row, not effective severity. That is what makes the override compose: severity = f(base row, overrides), and errors are fixed points.

**V-a. Info names.** Refuse them too. An info diagnostic never fails a build, so `"off"` means nothing and `"error"` would fail a build on a proof (ContractProven). But E0842 says "no live diagnostic has this name", which is false for a live info name. So the new code must cover *every live name outside Warning Names*, not only errors. That makes the frozen name `ErrorNotSuppressible` too narrow. I propose `NotAWarningName` (E0847). The message names the row: "`ContractProven` is an info diagnostic; `@allow` and `[lints]` take warning names only." If the panel keeps `ErrorNotSuppressible`, info names need their own sentence, and I prefer one name with one cause.

**V-b. V0003.** Fact 2 settles it: V0003 is under *Error Names*, so the rule covers it. sys's "E0842 already refuses them" is wrong for V0003. Its repair channel is `@verify(fallback: ...)`, which is part of the program and not a suppression, so the help line names it.

**V-c. Spec restructure.** Agree with min. State one rule in §4.16.8 and the Conventions, and turn the lexer, E0842 and E0843 sentences into consequences ("…so no setting reaches it"). Keep §2.4's sentence as a cross-reference, because a lexer reader needs it there.

**V-d. Help line.** The generic help is "remove this argument (key); fix the `<Name>` error it names". Where the catalog row has a better repair, use it: V0003 → `@verify(fallback: ...)`, E0501 → widen `@capabilities`. I object to sys's `_ => panic("unreachable")` as the default help. A wildcard turns off the exhaustiveness check for variants added later, which is the property the error protects. Say "add the missing arms".

**V-e. Check order.** Under Option 1 the classes are disjoint: audit-gated names are warnings, and the new code takes only non-warnings. So the order between E0837 and E0847 cannot be observed. Only "E0842 first" matters. The spec should state disjoint cases, not an order. min's and my order give the same result.

**V-f.** Yes. The named error still fires at its own site, and the refusal hides nothing.

**V-g.** Indifferent between the three, because each is a live warning. I lean to `UnrestoredMutation` because it matches the §4.16.8 example. I will take the majority.

NOT STABLE — the name/scope of the new code (V-a: `ErrorNotSuppressible` vs a name that also covers info rows) must be fixed before the vote, because names are frozen once published.

##### DevOps

**Option 1:** no objection. Six of six agree on the core.

**V-a. Info names.** Refuse them with the new code, as min says. An info name is live, so E0842 ("no live diagnostic") would give a false message. A suppression of something that never fails a build is a no-op, and the panel's principle says a silent no-op is as bad as a silent success. The rule then reads as one test: "an `@allow` argument or `[lints]` key must name a *Warning Names* row; any other live name is the new error". The LSP completion list is that one section, and nothing else.
Naming nit (not blocking): if info names are in scope, "ErrorNotSuppressible" is slightly wrong for V0001. `NotAWarningName` or `SuppressesNonWarning` fits both cases. I accept either name; the code is E0847.

**V-b. V0003.** Fact 2 settles it: V0003 is under *Error Names*, so it gets the new refusal, not E0842. Its help names `@verify(fallback: ...)` (see V-d).

**V-c. Spec restructure.** Support. One rule in §4.16.8 and in Conventions. The lexer, E0843, E0842 and I-code sentences become examples of it, not separate rules. A tooling author reads one predicate, and the compiler has one branch.

**V-d. Help line.** Take plt's mechanism: the help reuses the named error's primary help where one exists, after "remove this argument". That covers my per-error cases (V0003 → `@verify(fallback:)`, E0501 → `@capabilities`) with no new per-row table to maintain. Fall back to aiml's generic text plus a `blink explain <name>` note. The help never proposes another `@allow`.

**V-e. Check order.** It does not matter. E0837's list holds only warnings, and the new code fires only on non-warnings, so the sets are disjoint and no name can hit both. Only "E0842 first" matters, because the other two need a live name. The spec should say that, not fix an order with no effect.

**V-f. The named error still fires.** Yes, this is required. Two diagnostics, each with its own repair. CI logs and the LSP show the real problem, not only the refusal.

**V-g. Conventions example.** `@allow(UnusedVariable)`. Conventions is generic, and every user knows that warning. §4.16.8 keeps UnrestoredMutation for its own section. I hold this loosely.

STABLE — ready to vote

##### AI/ML

aiml — Phase B round 1

No objection to Option 1. I keep it as my vote.

**V-a. Info names.** Refuse them with the same new diagnostic, not E0842. E0842 says "this name does not exist" and suggests a spelling, which is false for ContractProven. That sends an AI looking for a typo. One rule: `@allow` and `[lints]` take *Warning Names* only. So the code name must not say "Error". I propose a name that does not depend on severity, for example `SuppressionOfNonWarning` (E0847). The message states the real category: "`ContractProven` is an info diagnostic; `@allow` takes warnings only". The name is frozen once published, so choose one that fits both cases now.

**V-b. V0003.** It is listed under *Error Names*, so the same refusal applies. Agree with devops: the help names `@verify(fallback: ...)` as its one control channel.

**V-c. Spec restructure.** Support. One rule that an AI can apply everywhere is better than four special cases. Keep each old sentence as a one-line instance that points to the rule, so readers who search for "E0843" still find the answer.

**V-d. Help line.** The first `help:` is "remove this argument" (or "remove this key"). That is the repair at this span. Second line: the primary help of the named error where one exists (plt), otherwise "fix the error it names". Then a note pointing to `blink explain <Name>`. I object to sys's `_ => panic("unreachable")` text. An agent that wants a green build reads it as the new way to silence the error. It moves the run-time panic into source and still skips the thinking. If it stays at all, it goes after "handle the missing cases", never first.

**V-e. Check order.** Mostly moot. Audit-gated names are W-codes, so E0837 and the new code never apply to the same name. The only order that matters is E0842 first: a name must exist before it has a category. Either plt's order or min's order works. I take plt/devops for the spec text.

**V-f. Named error still fires.** Required, and the spec must state it. If the refusal hid the original error, the agent would remove the `@allow` and then see a "new" error appear. That looks like the fix made things worse, and it causes churn.

**V-g. Example.** Switch to `@allow(UnrestoredMutation)`. It is the §4.16.8 example, and it is a warning that people really do suppress on purpose. One example in both places is easier to learn than two. `UnusedVariable` invites the wrong lesson, because its correct fix is usually to rename or remove the variable.

STABLE — ready to vote (subject to agreeing a code name that does not say "Error", per V-a)

##### Minimalism

**Option 1:** no objection. Six of six agree. Code number E0847.

**V-a. Info names.** An info name is live, so a refusal that says "unknown name" (E0842) is false. I prefer that the new code covers every live name that is not under *Warning Names*: errors and info. The rule is then one sentence: "`@allow` and `[lints]` reach warnings only." If the panel wants the new code scoped to *Error Names*, leave info under E0842 as today. That is no regression, so it is not a blocker for me.

**V-b. V0003.** V0003 is under *Error Names* (fact 2), so it gets the new code. Its help names `@verify(fallback: ...)`, its own channel. This is the only per-error help I support today.

**V-c. Spec restructure.** Yes. State the rule once in §4.16.8 and in the Conventions. The four special-case sentences become cross-references or are deleted. The lexer and E0843 branches go out of `lint_apply_override`. Fewer rules in the spec means fewer rules to drift apart.

**V-d. Help line.** Default help: "remove this argument; only warnings can be suppressed". Then reuse the named error's own primary help where it has one (plt). Do not write new fix text per error: that creates a second copy of each error's help, and the copies drift. The named error still fires at its own site with its own help, so a repeat is redundant. The one exception: an error with its own control channel (V0003 → `@verify`) names that channel.

**V-e. Check order.** I concede: E0842 → E0837 → new code. Audit-gated names are warnings, so E0837 and the new code never apply to the same name. The order has no effect, and I follow the majority.

**V-f. The named error still fires.** Yes, and the spec must say so: "the refusal does not hide the named diagnostic." Otherwise a reader can think the refusal replaces it.

**V-g. Example.** No strong view. `UnusedVariable` (W0600) is the warning most readers know, so I lean to it. `TodoInCode` is acceptable.

STABLE — ready to vote

#### Phase C — Final vote

Ballot: see the Result list above for the options that won. The losing options were: Q1 B (closed tier of demotable errors), Q1 C (status quo); Q2 B (info names stay under E0842); Q3 A `ErrorNotSuppressible`, C `SuppressesNonWarning`, D `SuppressionOfNonWarning`; Q4 B (keep the special-case sentences as separate rules); Q5 B (per-row repair text only for errors with their own control channel); Q6 B (fixed order E0842 → E0837 → E0847); Q8 B `UnrestoredMutation`, C `TodoInCode`.

- **Q1: Core rule** (6-0)
  - **Systems:** **Q1. Vote: A.** Reasoning: Every stage after typecheck (mono, layout, IR, C printer) assumes it gets well-typed input. If an error is suppressed, the C compiler fails on ill-typed IR, or worse, accepts it and produces wrong machine code. Under A, typecheck errors always stop the build, so codegen can depend on that. Concern: Code that has `@allow(<error>)` today stops compiling. The release notes must name this, or users will see it as a regression.
  - **Web/Scripting:** **Q1. Vote: A** Reasoning: "Warnings are switches, errors are not" takes about five seconds to learn. It ends the `@ts-ignore`-style trap where the error goes away and the C compiler, or a runtime panic, fails later. B makes users learn three tiers before anyone has asked for them, and B can still be added later without breaking code that A accepts. Concern: a team that hits a policy error such as CapabilityBudgetExceeded may feel stuck if the help line does not name that rule's own escape route.
  - **PLT:** **Q1. Vote: A** Reasoning: An error means the program has no typing derivation, so nothing correct remains to lower. Overrides must act only on judgements about well-formed programs, which are warnings. If the test is the catalog row, severity = f(base row, overrides) composes, and errors are fixed points. Concern: Someday a real policy error will want demotion, and people will reach for B before they reclassify it as a warning.
  - **DevOps:** **Q1. Vote: A** Reasoning: An error that a config line can switch off breaks the "zero errors" contract that CI gates on. The probe shows the result: a C compiler failure or silent miscompile, where the Blink error should be. A warnings-only rule also gives the LSP a clean completion list: one catalog section. Concern: A user with a real policy-error need gets no escape hatch, and may file pressure to reopen B without a concrete case.
  - **AI/ML:** **Q1. Vote: A.** Reasoning: An agent that wants a green build takes the cheapest edit, and today that edit is `@allow(<Error>)`. That gives a C compile failure or a run-time panic, and it teaches the trick to the next model through training data. A single rule, "suppression takes warnings", removes that decision point at every error site. A tier (B) makes every error message raise the question "is this one demotable?", which an AI can answer only by memorizing catalog flags. Concern: Someone hits a real false-positive error with no escape hatch. That must be filed as a compiler bug quickly, not routed around.
  - **Minimalism:** **Q1. Vote: A.** Reasoning: Severity is one fact for each diagnostic, and the catalog owns it. A suppression channel for errors makes every soundness rule optional, and each new check then has to ask "what if this check is off?". A policy rule that must be negotiable becomes a warning with a new code. That keeps one tier of errors. Concern: Someone hit by a false-positive error has no escape hatch. Compiler bugs that cause false positives must get a fast fix.

- **Q2: Info names and ICE names** (6-0)
  - **Systems:** **Q2. Vote: A.** Reasoning: An info name is a live name, so E0842 "unknown" would be a false message. One code for "a live name that is not a warning" keeps the check to one catalog lookup with one outcome. Concern: If Q3 picks a name with "Error" in it, the code is wrong for info names. Q2 A and Q3 A do not fit together.
  - **Web/Scripting:** **Q2. Vote: A** Reasoning: an error that calls a real name "unknown" sends the user to look for a typo that does not exist, and that is a classic Stack Overflow question. One code for "this is a real name, but not a warning" keeps E0842 meaning only "no such name". Concern: an author who wants to hide noisy info output may expect `[lints]` to do it, so the help should point to whatever output setting controls info lines.
  - **PLT:** **Q2. Vote: A** Reasoning: E0842 means "no live diagnostic has this name", and that is false for a live info name. One code for one cause class ("live, but not a warning") keeps each refusal's meaning exact. An info row has no level that means anything to set. Concern: I codes are not catalog names, so the spec text must say "live names" carefully, or it will seem to promise a name for ICEs.
  - **DevOps:** **Q2. Vote: A** Reasoning: E0842 says "no live diagnostic has this name". For V0001 that is false, and a false message sends the user and the LSP quick-fix the wrong way. One predicate ("must be a *Warning Names* row") is simpler to implement and to document than a split. Concern: Users may expect `@allow` to silence an info line in `--verbose` output, and they will get an error instead of a hint at the output flag.
  - **AI/ML:** **Q2. Vote: A.** Reasoning: E0842's message and suggestion say the name does not exist, which is false for ContractProven. An AI that reads "unknown name, did you mean X" makes spelling edits that cannot work. One cause per diagnostic is the easiest thing to learn and to self-correct from. Concern: The code name must then fit info names too. Q3 has to reflect that, or the message will lie a second way.
  - **Minimalism:** **Q2. Vote: A.** Reasoning: With A the rule is one sentence: "`@allow` and `[lints]` reach warnings only." E0842 is "unknown name", so it is false for a live info name. One refusal for every live name that is not a warning is simpler than two refusals split by catalog section. Concern: An info name in `@allow` used to get E0842 and now gets E0847. A tool that matches on E0842 sees a different code.

- **Q3: Name of E0847** (6-0, `NotAWarningName`)
  - **Systems:** **Q3. Vote: B (`NotAWarningName`).** Reasoning: Names are frozen, so the name must be correct for the full scope it covers. With Q2 A, that scope includes info and I-code names, which are not errors. So `ErrorNotSuppressible` would be wrong from the day it is published. `NotAWarningName` describes the exact test (is the name under *Warning Names*?) and is short. Concern: `NotAWarningName` reads as a fact about the name, not as a refusal. The message text must say "only warnings can be suppressed" to make the action clear.
  - **Web/Scripting:** **Q3. Vote: B (`NotAWarningName`)** Reasoning: under Q2 A, the code also covers info names and I codes, so `ErrorNotSuppressible` would be wrong for them. Names are frozen once published, so the name has to fit the full scope. `NotAWarningName` states the rule in plain words. The message text can still say "X is an error; only warnings can be suppressed". Concern: on its own, the name reads less clearly than the message, so the first line of the message must carry the meaning.
  - **PLT:** **Q3. Vote: B (`NotAWarningName`)** Reasoning: Under Q2 A, the code also covers info rows. `ErrorNotSuppressible` would then state a false cause for `ContractProven`, which is the same defect we refuse to accept in E0842. The name should describe the rule ("only warning names"), not one member of the class. Names freeze, so we must get this right now. Concern: If A wins, the spec needs an explicit sentence that info rows also get `ErrorNotSuppressible`, and that frozen name will always mislead for them.
  - **DevOps:** **Q3. Vote: B (`NotAWarningName`)** Reasoning: Under Q2 A, the code covers info names too, so "Error" in the name is wrong for V0001. `NotAWarningName` reads as a noun phrase about the argument, the same as its sibling `UnknownDiagnosticName`: "error[NotAWarningName]: `NonExhaustiveMatch` is not a warning name". Names are frozen, so a precise one is worth the change. Concern: `blink explain NotAWarningName` must say plainly why errors and info names are excluded, or the name reads as pedantic.
  - **AI/ML:** **Q3. Vote: B (`NotAWarningName`).** Reasoning: It is short, does not depend on severity, and states the exact cause in words an AI can act on: the name you gave is not a warning name. `ErrorNotSuppressible` is wrong for Info names under Q2 A. `NotAWarningName` reads better than my own `SuppressionOfNonWarning`, so I drop mine. Concern: If `ErrorNotSuppressible` wins, the message text has to say "info diagnostic" for V0001/V0004, so that the name and the message do not conflict.
  - **Minimalism:** **Q3. Vote: B (`NotAWarningName`).** Reasoning: After Q2 A, the code also refuses info names, so `ErrorNotSuppressible` would be false for part of its scope. The name is frozen once published, so it must be exact from day one. `NotAWarningName` is short, exact, and states the rule the user broke. Concern: The name describes the argument, not the action. A reader who sees only the name may not connect it to suppression, so the message text must say "`@allow` takes warning names only".

- **Q4: Spec structure** (6-0)
  - **Systems:** **Q4. Vote: A.** Reasoning: One rule gives one check in the compiler and one invariant to test. Separate special cases drift apart, as `lint_apply_override` already shows with its lexer, E0843 and audit-gated branches. Keep one "why" sentence for lexer errors, because their reason is different. Concern: Deleting the old sentences can lose a rationale someone relies on. Keep them as short pointers to the rule, not delete them outright.
  - **Web/Scripting:** **Q4. Vote: A** Reasoning: one rule in one place beats five scattered exceptions that a reader has to piece together. Short example pointers keep the old searches ("lexer error", "E0843") working. Concern: an editor could keep a pointer sentence and reword it until it reads like a separate rule again.
  - **PLT:** **Q4. Vote: A** Reasoning: One rule with corollaries is easier to reason about than four special cases that can drift apart. The lexer, E0842 and E0843 sentences become consequences ("…so no setting reaches it"). Keep pointers where a reader of that section needs them. Concern: A deleted sentence can lose a section-local detail, for example the E0843 span rule, so the editor must move it and not drop it.
  - **DevOps:** **Q4. Vote: A** Reasoning: One rule means one branch in `lint_apply_override` and one predicate for tool authors. Separate sentences invite drift between the spec, the catalog and the compiler, which is how this gap opened. Concern: Deleting the lexer/E0843 sentences outright could lose their "why" text, so keep them as short pointers.
  - **AI/ML:** **Q4. Vote: A.** Reasoning: One rule applies to every case, so it costs fewer tokens to learn and leaves fewer edge cases to get wrong. Keep the old sentences as short pointers, so a search for "E0843" or "lexer error" still finds the answer. Concern: Deleting the sentences outright could leave readers who jump straight to §E0843 with no local answer. Keep pointers.
  - **Minimalism:** **Q4. Vote: A.** Reasoning: Four special-case rules that say the same thing in four places will drift apart. One rule with pointers removes text and removes the chance of a contradiction. That is the gap this ticket came from: the catalog example contradicted §4.16.8. Concern: The person who edits the spec can delete a sentence that also carries a separate fact, for example the lexer recovery text. Each deletion must keep the facts that are not suppression facts.

- **Q5: Help line** (5-1, Minimalism dissent for B)
  - **Systems:** **Q5. Vote: A.** Reasoning: "Remove this argument" first, then the named error's own fix. Where a row has a better repair, that repair is catalog data, so no code path has to special-case it. Repair text is data with no runtime cost, and it makes the next build correct. Concern: Per-row repair text can go stale when the error's own fix changes. Generate it from the same source as the named error's help.
  - **Web/Scripting:** **Q5. Vote: A** Reasoning: the most useful help tells the user the real fix. Reusing the named error's help, plus catalog data for rows with a better repair, gives that fix without new prose for each error. It never offers another `@allow`, so users learn the right habit. Concern: per-row repair text can drift from the named error's own help over time unless a test ties them together.
  - **PLT:** **Q5. Vote: A** Reasoning: The help must lead to the repair the error protects, not to another escape. A wildcard arm as default help defeats exhaustiveness for variants added later. Per-row repair as catalog data is one source of truth. Concern: Per-row help text can rot when the named error's own help changes, so derive it from the error's help and do not copy it.
  - **DevOps:** **Q5. Vote: A** Reasoning: Each diagnostic's first help must name the real repair (§3.1). The named error's own help already holds it, so reusing it costs no new table. Where a control channel exists (V0003, E0501), catalog data points there. Concern: Some errors' primary help depends on the use site and reads oddly at an `@allow` site, so generic text plus `blink explain` must be the fallback.
  - **AI/ML:** **Q5. Vote: A.** Reasoning: The first help fixes the span the refusal points at (remove the argument). The named error's own help then leads to the real repair, so the diagnostics converge on one fix (§3.1). Per-row repair as catalog data means the compiler, LSP and `blink explain` agree, and no help ever suggests another suppression. Concern: Per-row text can drift from each error's own primary help. Generate it from the same catalog source.
  - **Minimalism:** *(dissent)* **Q5. Vote: B.** Reasoning: The named error still fires at its own site with its own help. Its primary help is reused, so more fix text for each error is a second copy that drifts. Repair text that is catalog data belongs only to errors that have their own control channel, such as V0003 and `@verify(fallback: ...)`. Concern: If A wins, the per-row repair column grows with no criterion for membership. Each new error then needs an argument about whether it gets one.

- **Q6: Check order among E0842 / E0837 / E0847** (6-0)
  - **Systems:** **Q6. Vote: A.** Reasoning: The sets are disjoint: audit-gated names are warnings, and E0847 covers non-warnings. An order between disjoint checks cannot change the result, so writing one into the spec adds a rule that does nothing. Concern: A future catalog change could make the sets overlap. Add a catalog check (`task ci`) that enforces the disjointness.
  - **Web/Scripting:** **Q6. Vote: A** Reasoning: the sets are disjoint, so a fixed order adds a rule that changes no output. Stating the disjointness is shorter and easier to keep correct. Concern: if a future name were both audit-gated and an error, the sets would overlap, so the catalog check should keep them disjoint.
  - **PLT:** **Q6. Vote: A** Reasoning: Under Q1 A, the two sets are disjoint (audit-gated names are warnings, and E0847 takes non-warnings), so an order between them cannot be observed. A spec that fixes an unobservable order adds a false constraint. Only "E0842 first" has meaning. Concern: If someone later adds an audit-gated non-warning, the sets overlap, and the spec must then pick an order.
  - **DevOps:** **Q6. Vote: A** Reasoning: The sets are disjoint, so a fixed order between E0837 and E0847 is a rule with no effect. The spec should state the true structure: E0842 first, then the name's catalog section picks the code. Concern: A later change that adds an error to the audit-gated list would break disjointness, so the spec must say the audit-gated list holds warnings only.
  - **AI/ML:** **Q6. Vote: A.** Reasoning: Stating the true structure (E0842 first, E0837 and E0847 cover separate sets) is more accurate than a fixed order that implies they overlap. An implementer or an AI reading B might think a name can hit both. Concern: If a future audit-gated diagnostic is an error, the sets would overlap. The spec should say that audit-gated membership is limited to warnings.
  - **Minimalism:** **Q6. Vote: A.** Reasoning: The name sets of E0837 and E0847 are disjoint, so a fixed order between them is a rule that changes nothing. Saying "disjoint" is true and shorter, and it does not make a reader look for a case where the order matters. Concern: If a future change makes an audit-gated name an error, the two sets overlap and the spec gives no order. That change must then add one.

- **Q7: The named error still fires at its own site** (6-0, Yes)
  - **Systems:** **Q7. Vote: Yes.** Reasoning: If the original error is hidden, the author removes the annotation and then sees what looks like a new error. Reporting both in one build is cheaper for the author. Concern: Two diagnostics for one mistake add output. Keep the E0847 message short.
  - **Web/Scripting:** **Q7. Vote: Yes** Reasoning: users should see the problem and the refused workaround together, in one run. Otherwise they fix the `@allow`, compile again, and only then meet the real error. Concern: two diagnostics for one mistake could feel noisy, so the E0847 message should point to the named error's site.
  - **PLT:** **Q7. Vote: Yes** Reasoning: The refusal is about the suppression channel. It must not hide the judgement that the program is ill-formed. Both facts are true, and the author must see both. Concern: The output has two diagnostics for one mistake, so the order of the diagnostics should put the real error's fix in a clear position.
  - **DevOps:** **Q7. Vote: Yes** Reasoning: CI logs and the LSP must show the real problem, not only the refusal. Two diagnostics, two repairs, neither hides the other. Concern: Users may see the pair as noise, so the refusal should sort next to the named error in output.
  - **AI/ML:** **Q7. Vote: Yes.** Reasoning: If the refusal hid the original error, the agent removes `@allow` and then sees a "new" error. That looks like its fix made things worse, and it causes churn. Both fire, and the agent sees the whole problem in one compile. Concern: Two diagnostics for one mistake may look noisy. Order the output so that the refusal comes next to the error it names.
  - **Minimalism:** **Q7. Vote: Yes.** Reasoning: Without this sentence, a reader can think the refusal replaces the named error and the program then compiles. It costs one sentence and closes a real misreading. Concern: An implementation can report the named error twice, once at the `@allow` site and once at its own site. The spec must keep the two diagnostics at their own sites.

- **Q8: Replacement for the Conventions example** (5-1, AI/ML dissent for B `UnrestoredMutation`)
  - **Systems:** **Q8. Vote: A (`UnusedVariable`).** Reasoning: It is the warning most readers already know, so the example teaches the rule and not the warning. Concern: Readers may infer that `@allow` is mostly for unused-code noise. The §4.16.8 examples still show the mutation lints.
  - **Web/Scripting:** **Q8. Vote: A (`@allow(UnusedVariable)`)** Reasoning: every JS and Python developer already knows no-unused-vars and `# noqa: F841`, so the example needs no explanation. Concern: it is a trivial example, so it does not teach that `@allow` is meant to be scoped to one function.
  - **PLT:** **Q8. Vote: A (`UnusedVariable`)** Reasoning: Any live warning is correct. `UnusedVariable` is the most familiar and is not domain-specific, and the majority leans that way. My earlier lean to UnrestoredMutation is weak. Concern: None of substance.
  - **DevOps:** **Q8. Vote: A (`UnusedVariable`)** Reasoning: Conventions is a generic section, and every user knows this warning. §4.16.8 keeps UnrestoredMutation for its own topic. Concern: None material.
  - **AI/ML:** *(dissent)* **Q8. Vote: B (`@allow(UnrestoredMutation)`).** Reasoning: It matches the §4.16.8 example, and it is a warning that people suppress on purpose. One example in both places is easier to learn. `UnusedVariable` invites the wrong lesson, because its correct fix is usually to remove or rename the variable, not to suppress it. Concern: If `UnusedVariable` wins, models will copy `@allow(UnusedVariable)` as the default fix for unused bindings. The example should at least sit next to text that says suppression is for deliberate cases.
  - **Minimalism:** **Q8. Vote: A (`@allow(UnusedVariable)`).** Reasoning: It is the warning that most readers know, from every other language. A Conventions example should teach the mechanism, not a Blink-specific analysis. Concern: None of weight. Any live warning name is correct.

#### Phase D

Not triggered: no result was closer than 5-1.

### Final Spec

```blink
type Color { Red Green Blue }

// intentional-error example
@allow(NonExhaustiveMatch)   // error[NotAWarningName]: `NonExhaustiveMatch` is an error;
                             //   `@allow` takes warning names only
                             // help: remove this argument
fn name(c: Color) -> Str {
    match c {                // error[NonExhaustiveMatch]: missing pattern `Blue`
        Red => "red"
        Green => "green"
    }
}

@allow(UnusedVariable)       // OK: a warning name
fn probe() {
    let x = 1
}
```

- `@allow` and `[lints]` reach only names under *Warning Names*. The catalog row decides, not the severity in effect (§4.16.8, ERROR_CATALOG.md *Conventions*).
- Any other live name (error, info, ICE) is `NotAWarningName` (E0847): refused, not ignored, at every level; not suppressible; each bad entry reported; the named error still fires at its own site.
- E0842 is checked first. E0837 and E0847 cover separate name sets, because the audit-gated list holds warnings only (§9.1).
- Help: remove the entry, then the named error's own help or its catalog repair; never another `@allow`, never `_ => panic(...)`.
- The E0842, E0843, lexer and ICE sentences now point to the one rule.
