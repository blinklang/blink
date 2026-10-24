[< All Decisions](../DECISIONS.md)

# Reserved Built-in Effect Names — Design Rationale

**Gap:** "Spec: may a user effect share a builtin effect root's name (Time, IO, Rand), and which one does Time then mean?" §10.6 was silent. A user `effect Time` (or `Rand`, `IO`) in any module passed `blink check` and then stopped the build with an internal error in codegen (`EffectDefaultBodyNotNameable`), even when no code used it. `effect State` ran. The W0545 check finds an effect declaration by name across the whole program, so a user `Time` in one module could take over the built-in `Time` check in another. The §10.6 *Compiler-Known Type Names* table lists types only, so the shadow ruling for type names (see [Builtin type name shadowing](../DECISIONS.md)) never covered effect names.

**Result:**

- **Q1 (6-0, A):** the built-in effect names `FS`, `Net`, `DB`, `IO`, `Env`, `Time`, `Rand`, `Crypto`, `Process`, `State` and `Async` are reserved. A top-level user `effect` with one of them is the new error `ReservedEffectName` (E0559), in every module, `pub` or not. `Time` then always means the built-in effect in rows, `with`, handlers and `time.x()` calls, with no import. A per-module shadow with W1010 lost.
- **Q2 (5-1, A2; Minimalism dissent for A1):** a built-in effect name reserves the top-level `effect` declaration only. A `type` with that name is legal, and in a type position the user type is the one named in its module. The vote was 3-3 (A/B) in Phase C and moved to 5-1 in Phase D.
- **Q3 (3-3 after Phase D, owner broke the tie for B):** no definition line. §4.3 is the one list. The compiler test that holds E0538 and `ReservedEffectName` to one table carries the single-list guarantee.

**Points all six seats agreed (not balloted):**

- Option 1 (reserve) 6-0 as the primary from Phase A on. Per-module shadow with W1010 was the fallback in Phase A; every seat that listed it opposed it. "Reserve only the names that have a built-in handle" was dropped: `Async` has a handle (`async.spawn`, `async.scope`).
- §4.3 holds the list and gains `Async`. One sentence in §10.6 *Shadowing Rules* says that the `effect` shadow clause does not cover a built-in effect name. The §10.6 table stays types-only. The ruling on type-name shadowing is unchanged.
- The rule applies to the top-level name only, and the spec says so. `effect Clock { effect Time { ... } }` stays legal, because the handle of a sub-effect is the handle of its parent.
- The help line names the rename and adds: "to replace the clock in tests, write `handler Time { ... }` and use `with`" (DevOps wording).
- A rename quick fix in the LSP is tooling, not spec text.
- The W0545 lookup by effect identity (not by name across the program) is a separate bug and not part of this ruling.
- Existing code with `effect State` stops compiling, so the release notes must say so. `effect State` was the one name that ran.

**Owner tiebreak (Q3):** the owner broke the 3-3 tie for B (no definition line), with Systems, Web/Scripting and Minimalism. The A side (AI/ML, DevOps, PLT) admitted that a later std-module effect outside §4.3 would make the line stale. The B side admitted that "An implementer may build a second list for `ReservedEffectName`, and the spec gives no sentence to point to when it drifts." The compiler test that holds E0538 and `ReservedEffectName` to one table carries the single-list guarantee.

**Reading gaps in the panel (as the moderator recorded them):**

- Phase B: AI/ML read the Phase B digest and A/devops, A/plt, A/sys, only the top of A/min, and none of A/web. Web/Scripting read A/web in full, the first part of A/aiml and A/plt, and did not open A/devops, A/min, A/sys. PLT read all six A files in part. Systems, DevOps and Minimalism read all six.
- Phase C: Minimalism read B1/min in full and only grep excerpts of the other B1 files, not every A file. Web/Scripting read the other five A files only through the Phase B digest and replies.
- Phase D1: Web/Scripting read only the Web/Scripting C file; the others came from the quotes in the Phase D digest. Minimalism read the digest, the brief head, the ballot and its own C file. DevOps read its own and PLT's C files in full. AI/ML read the Web/Scripting C file in part.
- Phase D2: all six seats read all six D1 files.
- Probes after Phase D1 (the moderator ran them at PLT's and DevOps's request): `Template[DB]` compiles with and without a user `type DB`, so no probe shows which `DB` it names. `List[DB]` and `List[Time]` give `UnknownType`, although §3b says `List[DB]` compiles. That is the effect-type argument that the compiler does not implement yet. It is already in the open `Template` implementation work, so it needs no new ticket.

**AI-first review:** 5/5 pass. Learnability: one rule with one error and a help line that names the repair, so a model that wrote `effect Time` from Koka or OCaml 5 habit fixes it in one round. Generability: `Time` means one thing in every file, so a model needs no import context to write a row. Debuggability: the error appears at the declaration and not as an internal error at `run`. Token efficiency: no new syntax. Consistency: the list is the §4.3 list that E0538 already uses.

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated in independent-proposal → debate → vote rounds. The texts below are the panelists' own, verbatim, except that internal ticket IDs are removed and shown as `[...]`.

#### Phase A — Independent proposals

##### Systems

> ## sys-1 (preferred): reserve the built-in effect root names; the declaration is an error
>
> A top-level `effect` named `FS`, `Net`, `DB`, `IO`, `Env`, `Time`, `Rand`, `Crypto`, `Process`, `State` or `Async` is E0524-class: new code `ReservedEffectName`. No shadow, no per-module meaning. Every name in the set gets the same rule, `State` and `Async` included (`h.bl` today is only "ok" because nothing reads the declaration back).
>
> ```
> error[E05xx]: effect `Time` has the name of a built-in effect
>  --> src/clock.bl:3:8
>   |
> 3 | effect Time {
>   |        ^^^^ reserved: `Time` is the built-in effect root (root handler, `time.x()` handle)
>   |
>   = help: rename it, for example `effect Clock`
> ```
>
> Fix is a rename. Nested names are unaffected: `effect Clock { effect Time { ... } }` is not a top-level root (the rule applies to the top-level name only, as for handles, 04:303).
>
> ```
> effect Clock {
>     effect Tick { fn tick() -> Int }
> }
> fn use_tick() -> Int ! Clock.Tick { clock.tick() }
> ```
>
> ### Why effects differ from the type-name ruling (DECISIONS.md:369)
> A type name has no runtime identity. A built-in effect root has four things a type does not:
> 1. a root handler that `main` installs (04:1838), emitted per built-in;
> 2. a lowercase handle in a reserved namespace (`time.read()`, E0710). A shadow gives `time` two meanings in one module, or needs a second handle name, which is a new rule;
> 3. `@handle_all` and W0545, which look the effect up program-wide today (the ticket's cross-module takeover);
> 4. a C-level default body per operation. The ICE `EffectDefaultBodyNotNameable` (src/cg_decl.bl:1551) shows codegen keys on the declared name. The ruling says "no codegen stage selects behavior by a name string"; for effects, rows and handles still are the name string. A shadow means mangled C symbols for the user effect, a second lookup path in W0545, and handler dispatch that reads the module scope. Zero runtime gain, real codegen risk.
>
> The ruling's reason to let types shadow ("the reserved set grows only when literal syntax grows") rests on the §10.6 table being frozen. The built-in effect list in §4.3 is also closed (new built-ins go in named std modules), so the reserved set does not grow. A new built-in effect never breaks a program.
>
> ### Reach to the built-in
> Nothing to reach: the name is never shadowed, so `Time` always means the built-in. No import-alias escape needed. This also closes the [module-qualified effect name ticket] interaction: a module-qualified row name can never collide with a root, because the user cannot declare the root.
>
> ### Tooling
> LSP: rename quick-fix on the diagnostic. `blink fmt`: no change. Docs: one sentence in §4.3 ("these names are reserved") and one row in ERROR_CATALOG.md. The §10.6 table stays types-only.
>
> ### Tradeoffs
> - Cost: one reserved-name set (11 names) and one new error. Smaller than any shadow design.
> - Loses: a user cannot call their own effect `Time` or `Rand`. Nobody needs it; `Clock` is clearer anyway, and a reader never has to ask which `Time` a row means. Cost to AI/readers is nil.
> - W0545 stays program-wide and correct, since only built-ins can be `@handle_all` roots.
>
> ## sys-2 (fallback if the panel wants parity with types)
> Per-module shadow with W1010. Needs: unique C names for user effects, W0545 and root-handler lookup scoped per module, and a rule for the handle `time`. I would accept it only with those three fixed in the same change and a test for each. I vote against it as the default.
>
> ## Cross-language
> Koka: effect names are ordinary names; `std/time` is a module, so no clash. Eff/OCaml 5: effects are constructors in a module; no root handlers. Rust prelude shadowing: types and traits only, no runtime root. Haskell `import Prelude hiding`: needs an explicit hide, and still no root handler. Python builtins: shadowing works and bites. Blink's built-in effects have root handlers, so they are closer to `main` or `__init__` than to prelude names. Reserve them like Go's `init`.

##### Web/Scripting

> ## web-1 (primary): a user effect may not take a built-in effect's name
>
> **Rule.** A top-level `effect` whose name equals a built-in effect is an error at the declaration. The set is every name the compiler accepts in a row without a declaration: `FS`, `Net`, `DB`, `IO`, `Env`, `Time`, `Rand`, `Crypto`, `Process`, `State` and `Async`. One rule, no exceptions. `Time` always means the built-in. Rows, `with`, handlers and `time.x()` never see a user `Time`. No module can reach a shadowed built-in, because nothing shadows it.
>
> ```blink
> effect Time {            // error E0525 ReservedEffectName
>     effect Tick { fn tick() -> Int }
> }
>
> effect Clock {           // the fix: any other name
>     effect Tick { fn tick() -> Int }
> }
>
> fn use_tick() -> Int ! Clock.Tick { clock.tick() }
> ```
>
> **Diagnostic.**
> ```
> error[E0525]: effect `Time` is a built-in effect name
>   --> clock.bl:1:8
>    |
>  1 | effect Time {
>    |        ^^^^ rename this effect, for example `Clock`
>    = note: `Time` in a row, `with`, or `time.` call always means the built-in effect
> ```
> The LSP offers a rename quick-fix. `blink fmt` is unchanged. The docs list the reserved effect names in §4.3 (one table, the single source for the check and for E0538).
>
> **Why not shadow, as types do.** A type name is resolved inside one module, and a use site sees one binding. An effect name is different in three ways.
> 1. A row is part of a function's signature. It crosses module borders as a name. A per-module shadow means `! Time` in module A and `! Time` in module B can be two effects. Until [the module-qualified effect name ticket] gives rows a qualified form, there is no way to write the difference.
> 2. The handle is the lowercase of the name (04:303), and handles live in a reserved namespace (E0710). A user `Time` also owns `time`. Then `time.read()` is the built-in in one file and an error in the next. That is the confusing case for a JS or Python dev: `time` silently changes meaning with an import.
> 3. Effects are capabilities. A reviewer who reads `! Time` must know it is the clock. A user `Time` that looks like the clock hides a real capability check (W0545 today already mixes them up program-wide).
>
> **Relation to the shadowing ruling (DECISIONS.md:369).** That ruling names the *type* namespace, and the §10.6 table lists type names only. It lists no built-in effect. So I do not reverse it. I do add one carve-out to §10.6 "Shadowing Rules": the clause that says `effect` shadows applies to effect names that are not built-in. The panel should vote this carve-out openly. The reserved-set growth rule ("only when literal syntax grows") speaks of type names; a closed set of ten effect names is already frozen by §4.3. Add Async to §4.3 so the list and the check agree.
>
> **Tradeoffs.** Pro: zero new concepts; the error says what to do; the ICE disappears because no such program reaches codegen; W0545 needs no per-module lookup. Con: a library cannot export a `Time` effect (it picks `Clock`); a future built-in effect would break user code that already uses that name. Mitigation: new built-ins go in named std modules (the §10.6 freeze), so this does not happen.
>
> **Cross-language.** Koka has `std/time` as a module, so `time` lives in a namespace and does not collide. Rust lets you shadow `Option` in your crate, but the prelude is only names, not a capability check. Python lets `list = 3` and the Stack Overflow answers are all "do not". OCaml 5 effects are ordinary constructors and have no built-in set. Haskell `import Prelude hiding (...)` needs explicit opt-in, which Blink effects cannot offer because of the handle.
>
> ## web-2 (fallback, ranked lower): per-module shadow with W1010
>
> Follow the type ruling exactly. User `Time` wins in its own module, W1010 at the declaration, `import blink.core.{Time as BuiltinTime}` reaches the built-in. I oppose this: the handle `time` still has to pick one owner (reason 2), and rows cross modules (reason 1). It needs a handle-alias feature and [the module-qualified effect name ticket] first. Do not choose it before those exist.
>
> ## web-3: do nothing
>
> Not valid. The ICE hits any program that has a user `Time` in any module.
>
> Fix note: whatever wins, add the failing test (user `effect Time` in module b/) to the corpus.

##### PLT

> ## plt-1 (recommended): reserve every built-in effect root name
>
> A top-level `effect` whose name is a built-in effect root is an error at the declaration. The roots are `FS`, `Net`, `DB`, `IO`, `Env`, `Time`, `Rand`, `Crypto`, `Process`, `State` and `Async`. One rule covers all of them.
>
> ```blink
> effect Time {            // error[E05xx] ReservedEffectName
>     effect Tick { fn tick() -> Int }
> }
>
> effect Clock {           // fine
>     effect Tick { fn tick() -> Int }
> }
> ```
>
> ```
> error[E05xx]: effect `Time` is a built-in effect
>  --> src/clock.bl:1:8
>   |
> 1 | effect Time {
>   |        ^^^^ built-in effect names cannot be declared
>   = help: choose another name, for example `Clock`
> ```
>
> **Why this differs from the type ruling (DECISIONS.md:369).** That ruling shadows a type because a type name lives in the type namespace, and a prelude entry sits in an outer scope. A built-in effect is not in the §10.6 table, and §10.6 lists type names only. It is not in an outer scope. 04:193 says a row name is a built-in effect or a program-declared one, in one flat set. So a user `Time` is a second declaration in that set, not a shadow. Reserving the name does not grow the §10.6 table. It does not grow the literal-syntax reserved set either. It is a separate rule, tied to the effect namespace.
>
> **Soundness arguments.**
> 1. Handles are the lowercase of the root name (04:303) and live in a reserved flat namespace (E0710, DECISIONS.md:140). User `Time` gives handle `time`. Then `time.read()` and `time.tick()` resolve by an operation lookup across two effects that share one handle. A per-module shadow needs per-module handle meaning, and the reserved-namespace ruling forbids that. Handles are the one place where shadowing is name-based, not identity-based.
> 2. A root handler exists for each built-in effect (04:1838). A user `Time` has none. The same row name would then mean "discharged by `main`" in one module and "E0539 unless `with`" in another.
> 3. `@handle_all` and W0545 find an effect by name program-wide today. With reservation, the name has one meaning, so that lookup becomes correct without a per-module fix. I still recommend a separate bug fix to look it up by identity.
> 4. Soundness of rows needs one name to mean one effect across modules. Reservation gives this without effect identities in row types.
>
> **Reaching the built-in.** Nothing to do: the name is never shadowed, so `Time` always means the built-in. No `import blink.core` path is needed.
>
> **Other modules.** No effect: a module cannot declare the name, so there is nothing to import.
>
> **Relation to [the module-qualified effect name ticket].** A module-qualified effect row name (`clock.Time`) stays open. This rule does not depend on it. If that ticket adds qualified names, a user effect `clock.Ticker` never collides with a built-in root, because no user name equals a root.
>
> **Tooling.** `blink check` reports at the declaration, so the ICE never shows. LSP rename offers no built-in effect name. `blink fmt` needs no change. `blink llms` and §4.3 get one sentence: "These names are reserved."
>
> **Tradeoffs.** A user who wants a `Time` effect for a test double should write `handler Time { ... }` for the built-in, which is what §4 already offers. Cost: a new reserved-name list that grows when a built-in effect is added. Mitigation: new built-in effects go in named std modules, as the §10.6 freeze says, so the list is closed and frozen.
>
> **Cross-language.** Koka and OCaml 5 have no built-in effect names a user cannot reuse, but they also have no flat handle namespace derived from the name. Haskell `import Prelude hiding (...)` needs a per-module hide, which Blink has no syntax for. Rust shadows its prelude because paths are scoped, and Blink handles are not.
>
> ## plt-2 (fallback): per-module shadow, mirror the type ruling
>
> Legal with W1010. The handle for a shadowing effect must differ (error on `time.x()` ambiguity, E0710 widened). I oppose this: it needs per-module handle meaning and per-module root-handler lookup, which add two new rules for one corner case.

##### DevOps

> ## devops-1 (primary): reserve the built-in effect names. A top-level `effect` with one of them is an error.
>
> Reserved set: `FS Net DB IO Env Time Rand Crypto Process State Async`. One list, one rule, no per-name exceptions. The list is the §4.3 list plus `Async`, which rows already accept (04:3233). Today `h.bl` (`effect State`) passes `run` only by luck. It would collide with the builtin the same way `Time` does.
>
> ```blink
> // clock.bl
> effect Time {                 // error
>     effect Tick { fn tick() -> Int }
> }
>
> effect Ticker {               // fix: any other name
>     effect Tick { fn tick() -> Int }
> }
> ```
>
> Diagnostic (new code, next free E05xx, name `ReservedEffectName`), at the name in the declaration:
>
> ```
> error[E05xx]: `Time` is a built-in effect and cannot be declared
>   --> clock.bl:1:8
>    |
>  1 | effect Time {
>    |        ^^^^ built-in effect (spec 4.3); its handle is `time`
>    = help: rename it, for example `effect Ticker` (handle `ticker`)
> ```
>
> Why an error and not a shadow, from the tooling side:
>
> 1. **The handle collides.** The handle is the lowercase top-level name (04:303), and handles live in a reserved namespace (E0710, DECISIONS.md:140, 5-0). A user `Time` gives `time.tick()` and the builtin `time.read()` the same root. Completion after `time.` then must list two effects, or hide one. A shadow rule needs a new way to name the builtin handle, and no such way exists.
> 2. **The failure is global today.** One user `Time` in any module breaks the build (b/ probe), and W0545 reads it program-wide. A per-module shadow needs per-module effect lookup in W0545 and in codegen, plus new rules in the LSP, `blink doc` and `blink explain`. An error needs one check at the declaration.
> 3. **No W1010 trap.** W1010 says "this shadows a name you can still reach with `import blink.core.{X as Y}`". No `blink.core` path reaches an effect root, so the W1010 fix hint would lie.
> 4. **Rows read the same in every file.** `! Time` in a signature then always means the builtin. A reader, an LLM and `blink query` need no import context.
>
> Relation to DECISIONS.md:369: that ruling covers names in the §10.6 *type* table, and the table has no effect. Built-in effects are roots of the row, handler and handle systems, not compiler-known types. So the ruling stays as written. The shadow rule at 07:2846 gets one sentence: "`effect` shadows a prelude type name; it may not take a built-in effect name (E05xx)." This does not grow the reserved *type* set. It does set a rule: the reserved effect set changes only when §4.3 changes.
>
> Interaction with [the module-qualified effect name ticket]: not decided here. If a module-qualified row name (`clock.Time`) is allowed later, it still cannot name a user `Time`, because that declaration cannot exist. The reserved list removes that ambiguity in advance.
>
> `blink fmt`: no change. LSP: the error carries a rename quick-fix. Hover on a built-in effect name in a row shows its §4.3 entry.
>
> Cost: a user who wants a fake clock for tests cannot name it `Time`. They already have `handler Time` for the builtin (04:2565, `@handle_all`), which is the intended tool. The error `help` line should say so: "to replace the clock in tests, write `handler Time { ... }` and use `with`".
>
> Cross-language: Rust lets you shadow `Option` and `Vec`. Rust's prelude holds types and not keywords, so this is the shadow case, and Blink already follows it for types. Koka effects (`console`, `exn`) live in std modules, and a user `effect console` shadows it only by explicit import choice. Blink has no module for effect roots. Python lets you rebind `open` silently, and the bug reports that follow are the cost of a silent shadow.
>
> ## devops-2 (fallback): per-module shadow with a warning.
>
> Legal; the user `Time` wins in its own module; W1010 at the declaration; every other module keeps the builtin. This needs: effect lookup per module (W0545, `tc_effect_decl_named`), a name for the builtin handle (none today), a codegen fix for `EffectDefaultBodyNotNameable`, and a rule for `main`'s root handler. I vote against it unless the panel supplies a way to name the builtin.
>
> ## Not proposed
>
> Reject-only-in-codegen. The ICE message is the current behaviour and is the worst diagnostic surface.

##### AI/ML

> ## aiml-1: Reserve every built-in effect name. A user `effect` with that name is an error.
>
> **Rule.** A user `effect` declaration whose top-level name is a built-in effect name is error E-new `ReservedEffectName`. The reserved set is the §4.3 list (`FS`, `Net`, `DB`, `IO`, `Env`, `Time`, `Rand`, `Crypto`, `Process`, `State`) plus `Async`. Every name gets the same rule. The rule applies in every module, `pub` or not, and with or without sub-effects. There is no shadowing and no escape import. `Time` always means the built-in.
>
> ```blink
> effect Time {            // error[E-new]: `Time` is a built-in effect name
>     effect Tick { fn tick() -> Int }
> }
>
> effect Clock {           // fine
>     effect Tick { fn tick() -> Int }
> }
>
> fn use_tick() -> Int ! Clock.Tick { clock.tick() }
> ```
>
> **Diagnostic.**
> ```
> error[E-new]: `Time` is a built-in effect and cannot be redeclared
>   --> clock.bl:1:8
>    = help: rename it, for example `effect Clock`
>    = note: reserved effect names: FS Net DB IO Env Time Rand Crypto Process State Async
> ```
>
> **Why this differs from the type-shadowing ruling (DECISIONS.md:369).** That ruling lets a user type shadow a compiler-known type. A type name has no second use. An effect name has one: the handle is the lowercase form of the root name (04:303), and handles are a reserved namespace (E0710, DECISIONS.md:140, 5-0). A user `effect Time` creates a handle `time`. It collides with the built-in `time.read()`. So `time.tick()` and `time.read()` would be two different effects behind one handle in one module. The type rule never has this problem. This rule needs no new principle: the reserved set follows the handle namespace, not literal syntax. I read "reserved set grows only when literal syntax grows" as a rule about the type table. The brief gives me no reason to apply it to handles.
>
> **AI/ML cost of the alternative (per-module shadow).**
> - Every `! Time` in a file would need a lookup: "does this module declare `Time`?" A model reading one function cannot answer this. It must read the imports.
> - A model trained on Koka, Eff and OCaml 5 sees `Time`/`IO` as library names. It will write `effect Time` in generated code. A hard error with a "rename" hint fixes this in one round. A silent shadow produces code that type-checks and calls the wrong effect.
> - The decision points are two (shadow or not, then which one). Reservation has zero.
>
> **Fixes that come for free.**
> - The codegen ICE (`EffectDefaultBodyNotNameable`) cannot be reached from a user program.
> - W0545 may keep its program-wide lookup. A user `Time` cannot exist.
> - Probes `a`, `c`, `d`, `h`, `i`, `j` and `b/` all become one clear front-end error, not an ICE at `run`. `h.bl` (`effect State`) is today a silent accept. It now errors.
> - The rule does not need [the module-qualified effect name ticket]: no module-qualified name can refer to a built-in.
>
> **Tooling.** The LSP shows the error at the name token. The quick fix renames the effect. `blink fmt` is unchanged. The docs list the reserved effect names once, in §4.3, with a pointer from §10.6.
>
> **Open points.**
> - `type Time` (e.bl) stays legal. Effect rows read names in effect position. I would leave it. PLT should say whether the shared namespace (03b:820) makes it a clash.
> - `Async` is in rows but not in §4.3. If the spec does not call it an effect with a handle, the spec must say so before we reserve it. I vote to reserve it. Row ambiguity alone justifies it.
>
> **Cross-language.** Rust lets users shadow prelude names, but a name has no hidden second namespace there. Haskell `import Prelude hiding` needs an explicit opt-out. Koka has no reserved effect names. In Koka a user `effect time` is possible because handlers are not tied to a lowercase handle. Python lets code shadow `list`. Style guides list it as a common bug.
>
> ## aiml-2 (fallback): Reject the declaration only when it collides with a handle
> Same error, but only for the 10 names that have a built-in handle. It leaves `Async` open. I prefer aiml-1 because it is simpler to state and to learn.

##### Minimalism

> ## min-1: Reject the declaration. A user `effect` may not take a built-in effect root name.
>
> **Rule.** `effect X { ... }` is an error when `X` is one of the §4.3 built-in effect roots: `FS`, `Net`, `DB`, `IO`, `Env`, `Time`, `Rand`, `Crypto`, `Process`, `State`. Add `Async` to the list, because rows already use it (§4.13). The check is per declaration, in any module, `pub` or not. New diagnostic: `ReservedEffectName`, next free E05xx code. Message:
>
> ```
> error[E05xx]: `Time` is a built-in effect and cannot be redeclared
>   --> clock.bl:1:8
>    |
>  1 | effect Time {
>    |        ^^^^ built-in effect names are reserved
>    = help: choose another name, such as `Clock` or `Ticker`
> ```
>
> ```blink
> effect Clock {
>   effect Tick { fn tick() -> Int }
> }
>
> fn use_tick() -> Int ! Clock.Tick { clock.tick() }
> ```
>
> Nothing else changes. `Time` always means the built-in in rows, `with`, `handler Time`, and in the `time.x()` handle call, in every module. No import form is needed to reach it. W0545 may keep its program-wide lookup, because no user declaration can collide with a built-in. That removes the cross-module takeover and the ICE (`EffectDefaultBodyNotNameable`) with one check. The ICE becomes unreachable.
>
> **Why this does not contradict the 369 ruling.** That ruling covers names in the *type* namespace, and it is about the §10.6 table. The table lists no effect. An effect has a second identity that a type lacks. Its handle is the lowercase root name (04:303), the handle namespace is reserved (E0710, 5-0), and `main` installs one root handler per built-in effect (04:1838). A user `Time` would own handle `time`. It would collide with the built-in handle in the same scope. Shadowing would then force a second rule: which `time.x()` wins, and how does a module reach the other one? The ruling's own "reserved set grows only when literal syntax grows" concerns type names. Built-in effect roots are not type names in the §10.6 sense, so they carry a separate, closed list (§4.3). State this carve-out in §10.6 Shadowing Rules and in §4.3 in one sentence each.
>
> **All ten plus `Async` get the same rule.** `h.bl` (`effect State`) works today only by accident. Two rules for one list cost more than one. Existing user code that declares `effect State` breaks, so this needs a note in the changelog. Blink has few users and the ICE already blocks the other ten names.
>
> **Tradeoffs (minimalism).**
> - Adds one error code and one list lookup. Shadowing instead adds: a new W1010 variant for effects, a hatch for the built-in (`import blink.core.{Time as ...}` does not fit, since effects are not in the table), handle renaming, and a rule for cross-module row identity. It also collides with open ticket [the module-qualified effect name ticket] (module-qualified effect names in rows). Reject avoids all of that and does not pre-decide it.
> - Future built-in effects must be added to a std module, not to the reserved list, by the frozen-set ruling. If std later adds an effect `Foo`, a user `Foo` stays legal because it is a module-scope name that shadows nothing. Only the §4.3 roots are reserved.
> - A user loses the name `Time`. They gain nothing from it that `Clock` does not give.
>
> **Tooling.** The LSP reports the error on the name token. A quick-fix is not needed. `blink fmt` is unaffected. `blink doc` and the §4.3 table are the single list of reserved names.
>
> **Cross-language.** Koka and OCaml 5 allow `effect time` as a user name because their built-in effects are ordinary library names that shadow normally. Blink's built-ins carry fixed handles and root handlers, so the Koka case does not transfer. Closer analogs: Go forbids redeclaring `init` as a value, and Rust rejects `mod core` collisions with the crate name in 2018+. Python lets you shadow `open`, and that is a known source of bugs.
>
> ## min-2 (fallback, if the panel wants shadowing)
> Per-module shadow with W1010 at the declaration, and no way to reach the built-in in that module. Do not add an import hatch: a module that wants the built-in does not declare its own `Time`. This is the smallest shadowing design, but it still needs a handle rule (user `time` wins in that module) and per-module `@handle_all` lookup. I rank it below min-1.

#### Phase B — Debate

The moderator sent a digest of the Phase A proposals. It had three options (reserve; per-module shadow with W1010; reserve only names with a handle) and seven variations inside Option 1 (V1 where the list lives, V2 LSP quick fix, V3 help text, V4 top-level only, V5 a `type` with a built-in effect name, V6 W0545 lookup, V7 existing code). Each seat read the Phase A files and replied.

##### Systems

> Read: A/aiml.md, A/devops.md, A/min.md, A/plt.md, A/sys.md, A/web.md, B1.md
>
> All six seats converge on Option 1. I support it.
>
> **V1 (where the list lives).** The §4.3 list is the single source. I concede the §10.6 sentence. My "table stays types-only" holds: no effect enters the table. But §10.6:2846 says the shadow rule covers `effect`. Without a carve-out the two sections contradict each other. One sentence there ("an `effect` may not take a built-in effect name, E05xx; §4.3") and one in §4.3. Add `Async` to §4.3 (it has handle `async`, 04:3259).
>
> **V2 (LSP).** A rename quick fix is cheap and I keep it, but it is not a spec point. Do not put it in the ruling.
>
> **V3 (help text).** Devops' line about `handler Time { ... }` and `with` is good: it names the real tool for test doubles. Use it.
>
> **V4 (top-level only).** State it in the rule. A nested `effect Clock { effect Time { ... } }` is not a root and has no root handler or bare handle, so the rule must not fire. This matches 04:303.
>
> **V5 (`type Time`).** Stays legal. Probe l.bl shows rows and handle calls resolve to the effect. A type is not a root and has no handle. The §10.6 table has no effect, so no new rule is needed. Do not add one.
>
> **V6 (W0545).** Reservation makes the program-wide name lookup correct, so I do not need the lookup change for this ruling. I agree with plt that identity lookup is a good separate bug.
>
> **V7 (existing code).** Agree with min: `effect State` is silently accepted today. Add a changelog note. It is the only name where a working program breaks.
>
> **Option 2.** Drop it from the ballot. Six of six oppose it, and each needs three extra rules (C names, per-module W0545 and root-handler lookup, a way to name the built-in handle). A ballot item nobody wants adds noise.
>
> **Option 3.** Drop it. Its reason fails: `Async` has a handle and a root in `main` (04:3392). Leaving it open reproduces the same collision for one name.
>
> STATUS: ready to vote

##### Web/Scripting

> Files read: A/aiml.md (first part), A/plt.md (first part), A/web.md, and B1.md; A/devops.md, A/min.md and A/sys.md only through the digest.
>
> **Position: Option 1.** Drop Options 2 and 3 from the ballot.
> - Option 3 stood on `Async` having no handle. The digest facts show `async.spawn` and `async.scope`, so `Async` has one. Option 3 then equals Option 1. Remove it.
> - Option 2 has no champion. All six seats oppose it. Keep it on the ballot only if someone asks. I do not.
>
> **V1.** One sentence in §4.3 holds the list (and adds `Async`). One sentence in §10.6 *Shadowing Rules* says the `effect` clause does not cover built-in effect names. The §10.6 table stays types-only. A reader who starts at the shadowing rule must find the exception there, not only in §4.3.
>
> **V2.** Rename quick fix: yes, but low value. The error text already says what to do. I do not insist.
>
> **V3.** Accept devops: add the line "to replace the clock in tests, write `handler Time { ... }` and use `with`". Most users who write `effect Time` want to fake the clock. This answers that need in the error itself.
>
> **V4.** Top-level names only. `effect Clock { effect Time { ... } }` is legal. State it in the spec text. `Clock.Time` is a different name from `Time`.
>
> **V5.** `type Time` stays legal. It sits in the type namespace, and a built-in effect is not a module binding, so it is not a duplicate (probe l.bl). It makes no handle. No change.
>
> **V6.** W0545: file a separate bug to look up by identity. Under Option 1 it cannot take over a built-in any more, but a program-wide lookup by name is a latent fault.
>
> **V7.** Agree with min: changelog note. `effect State` in h.bl runs today, so a user can have it. Tell them to rename. The error code is the next free one at landing, not E0525.
>
> **New evidence.** None beyond the digest. One point for the spec text: say that the reserved list is one list used by both E0538 `UnknownEffect` and the new error, so the two cannot drift.
>
> STATUS: ready to vote

##### PLT

> Files read: A/aiml.md, A/devops.md, A/min.md, A/plt.md, A/sys.md, A/web.md (aiml, devops, min, sys and web read in part: rule, rationale and tooling sections).
>
> **Option 1 holds.** Six of six agree. The soundness base is the handle: the handle is name-derived, flat and reserved (04:303, E0710), so it is the one place where lookup is by name, not by declaration identity. I concede that web's point is as strong as mine: a row crosses module borders as a name, and [the module-qualified effect name ticket] gives it no qualified form.
>
> **V1. Where the list lives.** §4.3 holds the list, with `Async` added there. §10.6 *Shadowing Rules* gets one sentence: "`effect` shadows a prelude type name; it may not take a built-in effect name (§4.3)." The panel must vote this carve-out openly, as web says. The clause "covers every declaration ... `effect`" is true as written for type names, but a reader will otherwise ask why `effect Time` is not W1010. I oppose any change to the §10.6 table.
>
> **V2. Quick fix.** Rename quick fix is fine. It is tooling, not spec. No vote needed.
>
> **V3. Help text.** Use devops wording: rename, and to replace the clock in tests use `handler Time { ... }` with `with`. That points to the right feature.
>
> **V4. Top-level only.** Agree with sys. `effect Clock { effect Time { ... } }` is legal: a nested name is not a root and its handle is `clock`. Say it in the spec sentence.
>
> **V5. `type Time`.** Stays legal, no W1010, no clash. A built-in effect is not a declaration, and 03b:820 shares one namespace among declarations only. A row position and a type position never read the same name (probe l.bl). I accept the asymmetry with g.bl (`effect Clock` + `type Clock` is E1016).
>
> **V6. W0545.** Reservation makes the program-wide lookup correct. A separate identity-lookup fix is hygiene, not part of this ruling. Do not tie it to the vote.
>
> **V7. Existing code.** Agree with min: a changelog note. `h.bl` (`effect State`) is a silent accept today and becomes an error.
>
> **Ballot.** Option 2 should leave the ballot. Its variants each add a rule (per-module handle meaning, a handle hatch). Option 3 should leave too: `Async` has a handle (`async.spawn`, 04:3259), so aiml's stated reason does not hold.
>
> STATUS: ready to vote

##### DevOps

> Files read: A/aiml.md, A/devops.md, A/min.md, A/plt.md, A/sys.md, A/web.md, B1.md
>
> devops, Phase B round 1. I support Option 1.
>
> **V1, list location.** §4.3 holds the list and gains `Async`. §10.6 *Shadowing Rules* gets one sentence: "`effect` shadows a prelude type name; it may not take a built-in effect name (ReservedEffectName)." Web is right that the carve-out must be voted openly. A reader of §10.6 who finds only "effect shadows" will file this ticket again. The §10.6 table stays types-only.
>
> **V2, quick fix.** Keep it, as a rename action on the declaration, with no fixed new name. Rename also updates the module's own `clock.tick()` handle uses, which a user does by hand today. I withdraw nothing: min's "not needed" is a cost argument and the cost is small. The `help` line stays, because the first thing a user sees is the message and not the code action.
>
> **V3, help text.** Two lines: the rename hint, and "to replace the clock in tests, write `handler Time { ... }` and use `with`". A user who writes `effect Time` is most often building a fake clock. Without the second line the error does not tell them how.
>
> **V4, top-level only.** Yes. `effect Clock { effect Time { ... } }` stays legal. The spec should say "top-level" in the rule text, as 04:303 does for handles.
>
> **V5, `type Time`.** Legal. Probe l.bl shows the row and the handle call still reach the built-in. The error is about the effect root and its handle. A type has neither. The shared namespace at 03b:820 is between user declarations, and no user `effect Time` can exist, so there is no clash to report. Add a spec line so nobody reads 03b:820 the other way.
>
> **V6, W0545.** Separate bug: look the effect up by identity. After this ruling the program-wide lookup gives the right answer, so it is not blocking.
>
> **V7, existing code.** Changelog note. The error text names `State` so the break is clear.
>
> **Ballot.** Drop Option 3: the digest fact shows `Async` has a handle (`async.spawn`), so the reason to leave it open is gone. Keep Option 2 on the ballot only so a vote against it is on record.
>
> STATUS: ready to vote

##### AI/ML

> Files read: A/aiml.md, A/devops.md, A/min.md, A/plt.md, A/sys.md, A/web.md (web and min read in part), B1.md.
>
> ## Position
>
> Option 1 is the primary for all six seats. I support it. The set is the ten names in §4.3 plus `Async`. The new facts help: `Async` has a handle (`async.spawn`, 04:3259), so Option 3 has no ground to stand on.
>
> **Option 3: remove from the ballot.** It exists only because I was unsure whether `Async` has a handle. It has one. Option 3 now equals Option 1 minus `Async`, and it gives a model a list with a hole in it.
>
> **Option 2: keep it on the ballot as the named fallback, no more.** All six oppose it. A shadow needs a way to name the built-in handle, and no such way exists. I accept a vote on it so the record shows why it lost.
>
> **V1, list location.** §4.3 holds the list and says "reserved". §10.6 *Shadowing Rules* gets one sentence: "`effect` may not take a built-in effect name." Reason: a model that reads only §10.6 sees "`effect` shadows" and must see the carve-out in the same place. Without it, the shadow rule reads as a trap. The §10.6 type table stays types-only.
>
> **V2, quick fix.** Keep the rename quick fix. A fix that edits one line costs little and helps an agent that cannot reason about spec text. Never offer a built-in name in the rename prompt (plt is right on this).
>
> **V3, help text.** Take devops: the help line says "rename it, for example `effect Clock`; to replace the clock in tests, write `handler Time { ... }` and use `with`". It answers the real reason a user writes `effect Time`.
>
> **V4, top-level only.** Yes. `effect Clock { effect Time { ... } }` stays legal, because the sub-effect is not a root and its handle is `clock`. The spec must say "top-level" so a model does not over-apply the rule.
>
> **V5, `type Time`.** Stays legal. Probe l.bl shows the row and the handle call resolve to the built-in effect, and g.bl's E1016 covers `effect`+`type` of one name only. I withdraw my "clash" question. Spec one line: "Reserved effect names do not reserve type names." Without that line, a model must guess.
>
> **V6, W0545.** Lookup by identity is a separate bug fix, not part of this ruling.
>
> **V7, existing code.** Support min: changelog note. `effect State` breaks, and `h.bl` shows it was silent before.
>
> STATUS: ready to vote

##### Minimalism

> Read: A/aiml.md, A/devops.md, A/min.md, A/plt.md, A/sys.md, A/web.md
>
> Six of six choose Option 1. I have no new objection to it. My position on the open variations:
>
> - **V1 (where the list lives).** The §4.3 table holds the list, and it adds `Async`. The check and E0538 read that one table. §10.6 *Shadowing Rules* gets one sentence: "`effect` shadows a prelude type name; it may not take a built-in effect name." The §10.6 type table stays types-only. I take devops's wording. I agree with web that the panel votes this carve-out openly, so it is not a hidden edit.
> - **V2 (LSP quick fix).** I withdraw my objection. A rename fix costs the language nothing, because it is tooling. It must not enter the spec text. Four seats want it. I do not need it.
> - **V3 (help text).** I support devops's line about `handler Time { ... }` and `with`. It answers the one real reason to write `effect Time`, which is a test double. Keep it to one sentence.
> - **V4 (top-level only).** Agree. `effect Clock { effect Time { ... } }` stays legal (probe k.bl runs). The handle is the lowercase top-level name, so a nested name has no handle to collide with. The spec must say "top-level".
> - **V5 (`type Time`).** Stay legal. Probe l.bl shows the row and the handle resolve to the built-in. The rule is about effect declarations. I would not add a second reserved set for type names. A user `effect Time` can no longer exist, so the 03b:820 shared-namespace clash cannot occur.
> - **V6 (W0545).** Out of scope. The program-wide lookup becomes correct under Option 1. The identity fix is a separate bug.
> - **V7 (existing code).** Changelog note for `effect State`. No deprecation period. The name has never worked at `run` for the other ten, and `State` is the one accidental pass.
>
> **Ballot.** Drop Option 3. `Async` has a handle (`async.spawn`, 04:3259), so Option 3 has the same set as Option 1. Its only effect is to leave `Async` open, and nobody argues for that. Keep Option 2 on the ballot as the recorded alternative, with the web-2 and min-2 variants merged into "per-module shadow, with or without an import escape". All six rank it second, and a vote on record is cheap.
>
> STATUS: ready to vote

#### Phase C — Silent ballot

All six seats voted alone. The ballot listed points that all six B1 replies state (Option 3 dropped; the set and the name; §4.3 holds the list and gains `Async`; one §10.6 sentence; top-level name only; the help line; the rename quick fix as tooling; `type Time` stays legal; the W0545 identity lookup as a separate bug; a changelog note). It asked three questions.

- **Q1. The rule.** A: reserve the built-in effect names (`ReservedEffectName`). B: per-module shadow with W1010.
- **Q2. A spec line that a built-in effect name does not reserve a type name.** A: add the line. B: no line.
- **Q3. A spec line that one list serves both E0538 `UnknownEffect` and `ReservedEffectName`.** A: add the line. B: no line.

| Seat | Q1 | Q2 | Q3 |
|---|---|---|---|
| Systems | A | B | B |
| Web/Scripting | A | B | A |
| PLT | A | A | A |
| DevOps | A | A | A |
| AI/ML | A | A | A |
| Minimalism | A | B | B |
| **Result** | **A 6-0** | **3-3** | **A 4-2** |

##### Systems

> Files read: brief.md, B1.md, A/aiml.md, A/devops.md, A/min.md, A/plt.md, A/sys.md, A/web.md, B1/aiml.md, B1/devops.md, B1/min.md, B1/plt.md, B1/sys.md, B1/web.md, ballot.md
>
> ## Q1. The rule
> **Vote:** A
> **Reasoning:** A built-in effect root carries a root handler that `main` installs (04:1838), a lowercase handle in a reserved namespace (E0710), and a per-operation C default body. The ICE at `EffectDefaultBodyNotNameable` shows codegen keys on the declared name. A shadow would need unique C names for the user effect, per-module W0545 and root-handler lookup, and a way to name the built-in handle, and none of these exist. Reservation costs one check at the declaration, gives zero runtime change, and makes the ICE unreachable.
> **Concern:** The carve-out in §10.6 *Shadowing Rules* must read clearly, or a later reader sees "`effect` shadows" and files this ticket again.
>
> ## Q2. A spec line that a built-in effect name does not reserve a type name
> **Vote:** B
> **Reasoning:** A type has no root handler and no handle. The reserved-effect rule names effect declarations only, and 03b:820 shares a namespace among user declarations only, so `type Time` (probe e.bl, l.bl) already works with no new text. A spec line that states what a rule does not cover adds a second statement to keep in step with the first.
> **Concern:** A model may over-apply the reservation to `type Time` and avoid a legal name, which costs a rename but no wrong code.
>
> ## Q3. A spec line that one list serves both checks
> **Vote:** B
> **Reasoning:** The check reads the §4.3 table, and 04:193 already says a row name is a built-in effect or a declared one. That text makes one list the source for both checks. A sentence about which compiler check reads which list is an implementation detail, and the spec should not hold it.
> **Concern:** Without the line, a later change could split the list in the compiler, so the compiler needs a test that holds E0538 and `ReservedEffectName` to the one table.

##### Web/Scripting

> Files read: brief.md, B1.md, A/web.md (in full), A/aiml.md, A/devops.md, A/min.md, A/plt.md, A/sys.md (via the B1 digest and the six B1 replies, not in full), B1/aiml.md, B1/devops.md, B1/min.md, B1/plt.md, B1/sys.md, B1/web.md, ballot.md
>
> ## Q1. The rule
> **Vote:** A
> **Reasoning:** A JS or Python dev reads `! Time` and `time.read()` as the clock. Under B, those two words change meaning from file to file, and rows cross module borders as bare names with no qualified form. A is one rule with no import hatch, and the error text tells the user to rename and how to fake the clock with `handler Time`.
> **Concern:** A library cannot export an effect called `Time`, and a future built-in effect name would break user code that already uses it.
>
> ## Q2. Spec line that a built-in effect name does not reserve a type name
> **Vote:** B
> **Reasoning:** `type Time` already works today (probe l.bl), and no text says otherwise. The rule is about effect roots and their handles, and a type has neither. A line adds one more sentence for a case almost nobody hits. If it shows up in questions, add the line then.
> **Concern:** A model may guess `type Time` is also an error, and a user may ask why `effect Clock` plus `type Clock` clashes (E1016) while `type Time` does not.
>
> ## Q3. Spec line that one list serves both checks
> **Vote:** A
> **Reasoning:** This is a single-source rule. If E0538 `UnknownEffect` and `ReservedEffectName` read different lists, a user gets "unknown effect" for a name the other check calls reserved. One sentence in §4.3 prevents drift for the cost of one line.
> **Concern:** The sentence ties the spec to an implementation detail, so a later split of the two lists would need a spec change.

##### PLT

> Files read: brief.md, B1.md, A/aiml.md, A/devops.md, A/min.md, A/plt.md, A/sys.md, A/web.md, B1/aiml.md, B1/devops.md, B1/min.md, B1/plt.md, B1/sys.md, B1/web.md (plus ballot.md and PANEL_RULES.md)
>
> ## Q1. The rule
>
> **Vote:** A
>
> **Reasoning:** A row name must denote one effect in every module. 04:193 gives rows one flat set (built-in or declared), and the handle is name-derived, flat and reserved (04:303, E0710). A per-module shadow would make `time` and `! Time` mean different effects across module borders. Rows have no qualified form until [the module-qualified effect name ticket] is decided, so the two could not be told apart. The shadow design would also need per-module handle meaning and per-module root-handler lookup, which are two new rules for one corner case. Reservation needs none of them and leaves DECISIONS.md:369 intact, because the §10.6 table lists no effect.
>
> **Concern:** The §4.3 list is now a frozen reserved set, so any future built-in effect must go into a named std module, or it will break user programs that already use the name.
>
> ## Q2. A spec line that a built-in effect name does not reserve a type name
>
> **Vote:** A
>
> **Reasoning:** 03b:820 says `type`, alias, `trait` and `effect` share one namespace. A reader can therefore ask whether `type Time` clashes with the reserved effect `Time`. It does not: a built-in effect is not a module binding, and a type position and a row position never read the same name (probe l.bl). The rule is sound without the line, but the line is one sentence, and it closes a reading that 03b:820 invites.
>
> **Concern:** If the line is worded as a general statement about namespaces instead of one fact about `type Time`, it could restrict how a later ruling treats module-qualified effect names ([the module-qualified effect name ticket]).
>
> ## Q3. A spec line that one list serves both checks
>
> **Vote:** A
>
> **Reasoning:** E0538 `UnknownEffect` accepts a row name if it is built-in or declared (04:193). `ReservedEffectName` rejects a declaration that equals a built-in. These are two directions of one predicate, "is this a built-in effect name". If the spec names one list for both, the accepted set and the reserved set cannot drift. A drift would let `Async` be accepted in a row but not reserved, which is the hole this ruling closes.
>
> **Concern:** If the line names the check mechanism and not the §4.3 list as the definition, it puts implementation detail in the spec, and the next change to the list must edit two places.

##### DevOps

> Files read: brief.md, B1.md, A/aiml.md, A/devops.md, A/min.md, A/plt.md, A/sys.md, A/web.md, B1/aiml.md, B1/devops.md, B1/min.md, B1/plt.md, B1/sys.md, B1/web.md
>
> ## Q1. The rule
>
> **Vote:** A
>
> **Reasoning:** One check at the declaration turns today's codegen ICE (`EffectDefaultBodyNotNameable`) into a front-end error that points at the name and says how to fix it. A per-module shadow needs a W1010 whose hint would lie (no `blink.core` path reaches an effect root), a way to name the built-in handle that does not exist, and per-module lookup in W0545, codegen, the LSP, `blink doc` and `blink explain`. Under A, `! Time` and `time.` completion mean the same thing in every file, so the LSP and `blink query` need no import context.
>
> **Concern:** A future built-in effect could break user code that already uses its name, unless new built-ins stay in named std modules as the §10.6 freeze says.
>
> ## Q2. Spec line: a built-in effect name does not reserve a type name
>
> **Vote:** A
>
> **Reasoning:** 03b:820 says `type`, alias, `trait` and `effect` share one namespace. A reader, or the LSP author who writes the rename and conflict checks, can read that as making `type Time` a clash. Probe l.bl shows it is legal today. One line stops a later ticket and a wrong "fix" in the checker.
>
> **Concern:** Each extra "does not" line adds spec text that someone must keep in step with the checker.
>
> ## Q3. Spec line: one list serves both E0538 and ReservedEffectName
>
> **Vote:** A
>
> **Reasoning:** The list is the §4.3 list plus `Async`. If the new check and E0538 `UnknownEffect` read different lists, a name could pass one and fail the other, and the user would get two messages that disagree. A stated single source gives the implementer and the test suite one thing to assert.
>
> **Concern:** The line fixes the design at the spec level, and a future list split (for example by std module) will need a spec change first.

##### AI/ML

> Files read: brief.md, B1.md, A/aiml.md, A/web.md (in part), A/devops.md, A/min.md, A/plt.md, A/sys.md (digest and B1 replies), B1/aiml.md, B1/devops.md, B1/min.md, B1/plt.md, B1/sys.md, B1/web.md.
>
> ## Q1. The rule
> **Vote:** A
> **Reasoning:** A model trained on Koka, Eff and OCaml 5 will write `effect Time` by habit. A hard error with a rename hint fixes it in one round. A per-module shadow adds two decision points (does this module declare `Time`, and which `Time` does a row mean) that a model cannot answer from one function. The handle `time` is name-derived and reserved, so the type-shadowing ruling does not carry over.
> **Concern:** A future built-in effect added to the list breaks user code that already uses the name, so the list must grow rarely and each change needs a changelog note.
>
> ## Q2. Line that a built-in effect name does not reserve a type name
> **Vote:** A
> **Reasoning:** `type Time` is legal, but the same word is now reserved as an effect. A model that reads "reserved" has to guess whether the type is also barred. One sentence removes the guess at a cost of about ten tokens, and it stops a model from writing needless renames of `type Time`.
> **Concern:** The line sits far from the §4.3 list, so a reader of only one of the two places can still miss it; put it in the same sentence as the rule.
>
> ## Q3. Line that one list serves both checks
> **Vote:** A
> **Reasoning:** Without this line a model can read E0538 `UnknownEffect` and `ReservedEffectName` as two lists. One named list is easier to learn and cannot drift when `Async` or a later effect is added. The line costs one sentence.
> **Concern:** If the compiler keeps two lists in code anyway, the spec line becomes a claim nothing tests; add a test that both checks read the same table.

##### Minimalism

> Files read: PANEL_RULES.md, ballot.md, brief.md (head), B1/min.md in full, and grep excerpts of B1/aiml.md, B1/devops.md, B1/plt.md, B1/sys.md, B1/web.md (V5 and one-list lines). I did not re-read every A/*.md file.
>
> **Q1. The rule.**
> - **Vote:** A
> - **Reasoning:** The built-in names already do not work as user effects: ten of eleven ICE at `run`. A reserved-name error removes a broken case and adds no new concept, because the §4.3 list exists and E0538 already reads it. Per-module shadowing (B) would add a second resolution rule for a name that nobody needs to redefine; the test-double need is met by `handler Time { ... }` and `with`.
> - **Concern:** The reserved list grows each time a built-in effect lands, and each addition breaks any user code that already used that name.
>
> **Q2. A spec line that a built-in effect name does not reserve a type name.**
> - **Vote:** B
> - **Reasoning:** §10.6 and 03b:820 already say the shared namespace holds user declarations, and a built-in effect is not a declaration. The probe l.bl shows `type Time` resolves. A line that states what a rule does not do invites a line for every other thing it does not do.
> - **Concern:** A model may guess wrong about `type Time` and avoid a legal name, which costs a few tokens and no correctness.
>
> **Q3. A spec line that one list serves both checks.**
> - **Vote:** B
> - **Reasoning:** The ballot already says §4.3 holds the list. One table that two checks read is one list by construction, so the sentence repeats the table. If the two checks drift, that is a compiler bug for a test, not spec text.
> - **Concern:** An implementer may build a second list for `ReservedEffectName`, and the spec gives no wording to point to when that drifts.

#### Phase D — Focused debate on Q2 and Q3

Q1 stood at A 6-0 and was not reopened. Q2 (3-3) and Q3 (4-2) got one round each. The moderator quoted the Phase C reasoning and concerns and added these facts, with no position implied:

- 03b:822: "An effect name denotes a type. Each `effect` declaration also gives a nominal type of the same name. ... So `Template[DB]` names the `DB` effect's type". The text says "each `effect` declaration"; it does not say whether a built-in effect gives such a type, but its example `Template[DB]` uses the built-in `DB`.
- 03b:820: a `C` "names any declaration in the type namespace: a `type`, a type alias, a `trait`, or an `effect` (these share one namespace, §10.6 *Shadowing Rules*)".
- 04:193: "Every name in an effect row must be a built-in effect (above) or one the program declares (§4.12). Any other name is rejected with `UnknownEffect` (E0538)." "(above)" points at the §4.3 list.
- The project rule: sections/ holds no implementation details. sections/ does name user-visible error codes.
- Probe l.bl: `type Time { t: Int }` with `! Time.Read` and `time.read()` in one module runs. The row and the handle call resolve to the built-in effect.

##### Phase D1 replies

###### Systems

> Files read: brief.md, ballot.md, D1.md, C/aiml.md, C/devops.md, C/min.md, C/plt.md, C/sys.md, C/web.md
>
> **Q2: I change to A, on one condition.** My Phase C reason was that no text is needed. The new fact at 03b:822 weakens that. It says each `effect` declaration gives a nominal type of the same name, and its example is `Template[DB]` with the built-in `DB`. So a reader can say that the built-in `Time` already holds the type name `Time`, and that `type Time` must then clash or shadow. Probe l.bl shows it runs with no W1010. The spec does not say why. That is a real gap, not a "does not" line for a rare case. It costs no code, but the LSP author and a model both have to guess.
>
> Condition (plt's concern is right): the line states one fact about the reserved rule, in the same sentence as the rule. Example: "The reservation covers the top-level effect declaration only; it does not reserve a type name." It must not state a general namespace rule, so [the module-qualified effect name ticket] stays open. If the panel cannot agree on that narrow wording, I return to B.
>
> **Q3: I keep B.** 04:193 says "(above)", and that points at the §4.3 list. The new check reads the same §4.3 list, so one list serves both by construction. A sentence that says which check reads which list names the mechanism, and the project rule keeps mechanism out of sections/. The fix for drift is a compiler test. I agree with min. I accept devops's point that a future list split needs a spec change first, but that is true with or without the sentence.
>
> STATUS: ready to vote

###### Web/Scripting

> Files read: brief.md, ballot.md, D1.md (which quotes the six C votes and concerns), C/web.md. I did not open the other five C files; I used D1.md's quotes of them.
>
> **Q2: I change my vote from B to A.** The new fact decides it. 03b:822 says each `effect` declaration gives a nominal type of the same name, and its example `Template[DB]` uses the built-in `DB`. 03b:820 says effect and type names share one namespace. Read together, a built-in `Time` has a type `Time`, so `type Time` looks like a clash. Probe l.bl shows it is legal. That is no longer "a case nobody hits": two spec sentences point the wrong way, and a JS or Python dev (or a model) who reads them will avoid a legal name or file a bug. My Phase C reason ("no text says otherwise") was wrong.
> Wording: put it in the same sentence as the rule (aiml) and state one fact about `type Time` (plt). Do not state a general namespace rule, so [the module-qualified effect name ticket] stays open. Say whether the built-in effect gives a type.
>
> **Q3: I change my vote from A to B.** sys is right that 04:193 already says a row name is a built-in effect "(above)" or a declared one, so the §4.3 list is the one source. My Phase C concern, that the line ties the spec to an implementation detail, applies to the line itself. The project rule keeps implementation detail out of sections/. The fix belongs in a test that holds E0538 and `ReservedEffectName` to one table, not in spec text. The spec needs one thing: §4.3 says it is the list of built-in effect names, and the new rule says "a name in §4.3".
>
> STATUS: ready to vote

###### PLT

> Files read: D1.md, brief.md, ballot.md, C/aiml.md, C/devops.md, C/min.md, C/plt.md, C/sys.md, C/web.md
>
> ## Q2. Vote stays A, for a stronger reason than in Phase C
>
> The Phase D fact at 03b:822 changes my view. "An effect name denotes a type", and the example `Template[DB]` uses the built-in `DB`. So a built-in effect name already has a use in type position, as a type argument. Then `type Time { t: Int }` and `Template[Time]` meet in one position. My Phase C claim, "a type position and a row position never read the same name", is wrong for type arguments. Probe l.bl only tested row and handle positions.
>
> Sys, web and min say a type has no handle and no root, so there is nothing to clash. That holds for rows and handles. It does not hold for `Template[Time]`. Without a line, the spec does not say which `Time` that is: the user type or the effect type. The ballot says `type Time` stays legal. So the line must say what `Time` means in type position when a module declares `type Time`. The shadow rule at 07:2846 gives one answer: the user type wins in its module, as for any prelude name. The line is then not a "does not" line. It is a resolution rule, and a checker needs it.
>
> I ask the moderator to have someone run `Template[Time]` with and without `type Time` before the vote.
>
> ## Q3. Vote stays A, with wording
>
> Write the line as a definition: "The built-in effect names are the names in this list." Do not name the checks. That keeps E0538 and `ReservedEffectName` on one predicate, and it is not an implementation detail. Sys and min are right that a line naming which check reads which list would be one.
>
> STATUS: ready to vote

###### DevOps

> Files read: brief.md, ballot.md, D1.md, C/devops.md, C/plt.md (full), and the Phase C excerpts of aiml, min, sys, web as quoted in D1.md; sections/03b_contracts.md lines 815-835.
>
> # devops, Phase D
>
> ## Q2. Keep A, and the fact at 03b:822 makes it stronger
>
> 03b:822 says each `effect` declaration gives a nominal type of the same name, and its own example is `Template[DB]` with the built-in `DB`. So a built-in effect name also sits in type-argument position. `type Time { t: Int }` is legal (probe l.bl), but then `Template[Time]` has two readings: the built-in effect's type, or the user struct. The spec does not say. The LSP, hover and go-to-definition must pick one, and a model must guess. This is more than the "almost nobody hits it" case: `type DB` and `type Env` are plausible names.
>
> Without a line, my conflict check cannot be written from the spec. I support a line that gives one fact: a user `type` named like a built-in effect is legal, and in a type position the user type wins in its module (same as DECISIONS.md:369 for any shadowed name). That is not a general namespace statement, so it does not touch [the module-qualified effect name ticket] (plt's concern). Put it in the same sentence as the rule (aiml's point). I do not change my vote. I ask the panel to check the `Template[Time]` reading before it fixes the wording.
>
> ## Q3. Keep A, with plt's wording
>
> Write the line as a definition, not as a mechanism: "§4.3 lists the built-in effect names. A row name is accepted (E0538) or a declaration is rejected (ReservedEffectName) by that list." It names a user-visible fact and no compiler stage, so it meets the "no implementation details in sections/" rule: 04:193 already names E0538 the same way. I agree with sys and min that a test must hold both checks to one table. That test is separate from the spec line. My Phase C concern stands.
>
> STATUS: ready to vote

###### AI/ML

> Files read: brief.md, ballot.md, D1.md, C/aiml.md, C/devops.md, C/min.md, C/plt.md, C/sys.md, C/web.md (web in part), plus B1/*.md from Phase C. New probe: aiml/m.bl.
>
> ## Q2
> **Position: A, unchanged.** New evidence: 03b:822 says an effect name denotes a type, and its own example is `Template[DB]` with the built-in `DB`. So a careful reader can say a built-in effect already owns a type name, and `type DB` then looks like a clash. Probe m.bl: `type DB { x: Int }` with a use compiles and runs. The line is therefore not about a rare corner. It settles a real conflict between 03b:822 and the reservation. A model cannot settle it from the text. web and min say the cost of a wrong guess is a few tokens. A wrong guess here also makes a model refuse a legal name, and a trained model repeats that guess in every file.
>
> I accept plt's wording limit: state one fact, not a namespace principle. Example: "A built-in effect name reserves the effect declaration only; `type Time` remains legal." It goes in the rule sentence (my Phase C concern).
>
> ## Q3
> **Position: A, with a wording change.** I accept sys, min and plt: do not name checks. Write the line as a definition: "The names in §4.3 are the built-in effect names. A row accepts them without a declaration and a declaration may not take them." That is spec content, not mechanism, and it keeps E0538 and `ReservedEffectName` tied to one list. If the panel dislikes even this, I move to B, because 04:193 already points "(above)" at the list. A compiler test must then hold both checks to one table.
>
> STATUS: ready to vote

###### Minimalism

> Files read: D1.md, brief.md (head), ballot.md, C/min.md, and the C excerpts quoted in D1.md for the other five seats. I did not open the other five C files.
>
> **Q2. Change: B to A, if the line is narrow.**
> The new fact decides it. 03b:822 says each `effect` declaration gives a type of the same name, and its example `Template[DB]` uses the built-in `DB`. So a reader can ask whether built-in `Time` also gives a type `Time`, and then whether `type Time` clashes. Today the text does not answer. This is a real gap in existing text, not a "does not" line for a rare case. My Phase C worry (one line invites many) is weaker than a reading that two sections now allow both ways.
>
> Conditions, which answer plt's concern: one sentence; a fact about built-in effect names only; no general statement about namespaces. Example: "A built-in effect name does not reserve a type name; `type Time` is legal." Place it with the rule, as aiml asks. If the panel cannot agree on that wording, I go back to B.
>
> **Q3. No change: B.**
> 04:193 already says an effect row name is a built-in effect "(above)", and "(above)" is the §4.3 list. The spec already names one list. A sentence about which checks read it is an implementation detail, and the project rule keeps those out of sections/. The drift risk is real, but a corpus test holds it. My Phase C concern stands; the answer is a test, not spec text.
>
> STATUS: ready to vote

After D1 the moderator ran probes at PLT's and DevOps's request (gen1 at main 2aef8fb3):

- `n3.bl`: `fn sink(_t: Template[DB]) -> Int { 7 }`, no user `DB`. `run` prints `ok`.
- `n4.bl`: `type DB { x: Int }`, the same `sink`, and `DB { x: 1 }` in `main`. `run` prints `1`. The probe cannot show which `DB` the `Template[DB]` names.
- `n5.bl`: `fn f(_x: List[DB]) -> Int { 7 }`, no user `DB`. `error[UnknownType]: unknown type DB`. 03b:829 rule 1 says "`List[DB]` compiles".
- `n1.bl`: `List[Time]`, no user `Time`. `error[UnknownType]`.
- `n2.bl`: `type Time { t: Int }` and `List[Time]` holding `Time { t: 1 }`. It runs; `Time` is the user type.
- AI/ML's own probe `m.bl`: `type DB { x: Int }` used in `main`. It runs.

All six D1 replies voted to add a line for Q2. They differed on its content. A1: one fact, the reservation does not reserve a type name. A2: the fact, plus which `Time` a type position means when a module declares `type Time`. B: no line. For Q3, A was a definition line naming no check, and B was no line.

##### Phase D2 — Silent re-vote

All six seats read all six D1 files. Q2 options: A1 (the fact only), A2 (the fact plus: in a type position the user type wins in its module), B (no line). Q3 options: A (a definition line naming no check) and B (no line).

| Seat | Q2 | Q3 |
|---|---|---|
| Systems | A2 | B |
| Web/Scripting | A2 | B |
| PLT | A2 | A |
| DevOps | A2 | A |
| AI/ML | A2 | A |
| Minimalism | A1 | B |
| **Result** | **A2 5-1** | **3-3** |

###### Systems

> Files read: PANEL_RULES.md, ballot-D.md, brief.md, ballot.md, D1.md, D1/aiml.md, D1/devops.md, D1/min.md, D1/plt.md, D1/sys.md, D1/web.md.
>
> ## Q2. The line about a type named like a built-in effect
>
> **Vote:** A2 (the fact, plus which `Time` a type position means when a module declares `type Time`).
>
> **Reasoning:** The n3/n5 probes show a built-in effect name does work in type-argument position (`Template[DB]` compiles with no user `DB`), so a type position can read the same name as the reservation. A1 alone says `type Time` is legal and leaves `Template[Time]` with two readings; the compiler has to pick one, and n4 cannot show which. A2 gives the pick at no cost: the user type wins in its module, the rule DECISIONS.md:369 and 07:2846 already apply to every prelude name. No new mechanism, no codegen branch on a name string, and the type resolves to one tid at compile time.
>
> **Concern:** The spec will state a resolution that no probe has shown the compiler to follow, so the line needs a test (`type DB` plus `Template[DB]`) before it lands.
>
> ## Q3. The §4.3 list as the one source
>
> **Vote:** B (no line).
>
> **Reasoning:** 04:193 already says a row name is a built-in effect "(above)" or a declared one, and the new rule reads "a name in §4.3". One table gives one list by construction. A line that says which check reads the list describes how the compiler is built, and sections/ holds no mechanism. The drift risk is real, and a compiler test that holds E0538 and `ReservedEffectName` to one table covers it.
>
> **Concern:** An implementer may build a second list for `ReservedEffectName` and the spec gives no sentence to point to when the two drift.

###### Web/Scripting

> Files read: PANEL_RULES.md, ballot-D.md, brief.md, ballot.md, D1.md, D1/aiml.md, D1/devops.md, D1/min.md, D1/plt.md, D1/sys.md, D1/web.md.
>
> ## Q2. The line about a type named like a built-in effect
>
> **Vote:** A, wording A2 (the fact, plus which `Time` a type position means). A1 is my second choice; B is out.
>
> **Reasoning:** The probes show the gap. n4 runs but cannot say which `DB` the `Template[DB]` names, and n5 says `List[DB]` is `UnknownType` while 03b:829 says it compiles. A JS or Python dev who writes `type DB` and then `Template[DB]` gets no answer from the spec, and a one-fact line (A1) leaves that case open. A2 adds no new rule: it applies the DECISIONS.md:369 shadow rule (user type wins in its module) to one named case. Put it in the same sentence as the reservation, as one fact about built-in effect names, not a general namespace rule, so [the module-qualified effect name ticket] stays open.
>
> **Concern:** If the compiler does not match "the user type wins" today, the line is a promise the compiler breaks, so a test must pin it first.
>
> ## Q3. The §4.3 list as the one source
>
> **Vote:** B.
>
> **Reasoning:** 04:193 says "(above)" and points at the §4.3 list, so the spec already has one list. A definition line repeats the table, and a second statement of the same fact gives a place for the two to disagree. The new rule only has to say "a name in §4.3". A compiler test that holds E0538 and `ReservedEffectName` to one table covers drift.
>
> **Concern:** An implementer may build a second list for `ReservedEffectName`, and the spec has no sentence to point to when it drifts.

###### PLT

> Files read: PANEL_RULES.md, ballot-D.md, brief.md, ballot.md, D1.md, D1/aiml.md, D1/devops.md, D1/min.md, D1/plt.md, D1/sys.md, D1/web.md.
>
> ## Q2. The line about a type named like a built-in effect
>
> **Vote:** A (A2 wording: the fact, plus which `Time` a type position means).
>
> **Reasoning:** The probes show the type namespace and the effect namespace differ in practice. n1 shows `List[Time]` with no user `Time` is `UnknownType`, and n2 shows the user type wins when it exists. So the fact "a built-in effect name does not reserve a type name" is true for ordinary type positions. The only position that can read a built-in effect name as a type is a type argument such as `Template[DB]` (03b:822). n4 cannot show which `DB` that names. A rule must say. The shadow rule at 07:2846 gives one answer, and it is a deterministic one: in a module that declares `type DB`, `DB` in type position means the user type. A1 states the fact and leaves that position open. A2 closes it with an existing rule, so it adds no new principle.
>
> Preferred wording, one sentence, placed with the reservation rule: "A built-in effect name reserves the top-level `effect` declaration only. A `type` with that name is legal, and in type position the user type is the one named in its module."
>
> **Concern:** n5 shows `List[DB]` is `UnknownType`, but 03b:829 rule 1 says it compiles. The spec and the compiler already disagree on where an effect type may appear, and a ruling on `type DB` should not hide that. This is a separate bug for a ticket, not part of this ruling.
>
> ## Q3. The §4.3 list as the one source
>
> **Vote:** A (definition line, naming no check).
>
> **Reasoning:** Accepting a row name and rejecting a declaration are two uses of one predicate, "is this a built-in effect name". A definition in §4.3 states the predicate once, so the accepted set and the reserved set cannot differ. Sys and min are right that 04:193 "(above)" points at the list. But "(above)" is a back-reference in a rule about rows. It does not say the list is a definition that the new rule also uses. The definition costs one sentence and names no compiler stage, so it is not an implementation detail. 04:193 already names E0538 the same way.
>
> Preferred wording (aiml's, which names no check): "The names in §4.3 are the built-in effect names. A row accepts them without a declaration and a declaration may not take them." Any of the three A wordings is acceptable. I reject only a wording that says which compiler check reads which list.
>
> **Concern:** If the line names a check or a mechanism, it puts implementation detail in sections/, and a future split of the list by std module would need a spec change first.

###### DevOps

> Files read: PANEL_RULES.md, ballot-D.md, brief.md, ballot.md, D1.md, D1/aiml.md, D1/devops.md, D1/min.md, D1/plt.md, D1/sys.md, D1/web.md.
>
> # devops, Phase D2 vote
>
> ## Q2. The line about a type named like a built-in effect
>
> **Vote:** A2 (the fact, plus which `Time` a type position means when a module declares `type Time`).
>
> **Reasoning:** Probe n5 shows `List[DB]` is `UnknownType` with no user `DB`, so a built-in effect name gives a type only where 03b:822 says (`Template[DB]`). Probe n3 accepts `Template[DB]` with no user `DB`, and n4 cannot show which `DB` it names when `type DB` exists. An LSP hover, go-to-definition and a rename or conflict check must pick one answer, and A1 leaves that pick to each tool author. The shadow rule at 07:2846 already gives the answer (the user type wins in its module), so A2 adds a pointer, not a new rule. Wording: "A built-in effect name reserves the effect declaration only. `type Time` is legal, and in a type position it names the user type in its module (§10.6 *Shadowing Rules*)." Put it in the sentence that states the rule. It says nothing general about namespaces, so [the module-qualified effect name ticket] stays open.
>
> **Concern:** If the compiler today resolves `Template[DB]` to the effect type when `type DB` exists, A2 states a rule the compiler does not follow, so a test must check it before the line lands.
>
> ## Q3. The §4.3 list as the one source
>
> **Vote:** A (definition line, naming no check).
>
> **Reasoning:** Two checks, E0538 `UnknownEffect` and `ReservedEffectName`, give the user two messages about one name. If their lists differ, a name can pass one and fail the other, and the messages then disagree. A definition line says what the list is, not which stage reads it, so it holds no implementation detail; 04:193 already names E0538 in the same way. A compiler test holds the code to the table, and the spec line gives that test its source of truth.
>
> **Wording:** I prefer my own: "§4.3 lists the built-in effect names. A row name in that list is accepted without a declaration (otherwise E0538), and a declaration with a name in that list is rejected (`ReservedEffectName`)." plt's shorter "The built-in effect names are the names in this list" is also fine. Any of the three D1 wordings is acceptable to me.
>
> **Concern:** A future split of the list (for example by std module) needs a spec change first, and the line makes that cost explicit, but a reader may treat the line as a second statement to keep in step with 04:193.

###### AI/ML

> Files read: PANEL_RULES.md, ballot-D.md, brief.md, ballot.md, D1.md, D1/aiml.md, D1/devops.md, D1/min.md, D1/plt.md, D1/sys.md, D1/web.md. Probes n1-n5 are as ballot-D.md reports them; I did not re-run them.
>
> ## Q2. The line about a type named like a built-in effect
>
> **Vote: A2** (the fact, plus which `Time` a type position means when a module declares `type Time`).
>
> **Reasoning.** The ballot says `type Time` stays legal, and 03b:822 says an effect name denotes a type (`Template[DB]`). So `Template[Time]` in a module with `type Time` has two readings, and probes n3 and n4 cannot tell them apart. A model cannot settle this from the text, and it will repeat its guess in every file. A1 states the fact but leaves that reading open. A2 adds one clause that reuses the shadow rule at 07:2846: the user type wins in its module. The clause adds no new decision point, because a model already learns that rule for every prelude name. It costs about twenty tokens.
>
> The wording must state one fact about built-in effect names and not a general namespace rule, so [the module-qualified effect name ticket] stays open. Example: "A built-in effect name reserves the effect declaration only. `type Time` is legal, and in a type position the user type wins in its module." Put it in the sentence that states the rule.
>
> **Concern.** If A2 wins but the compiler resolves `Template[Time]` to the effect type (n4 cannot show which it picks), the spec and the compiler disagree. Someone must test `Template[Time]` against the line before it lands.
>
> ## Q3. The §4.3 list as the one source
>
> **Vote: A**, naming no check. Preferred wording (mine): "The names in §4.3 are the built-in effect names. A row accepts them without a declaration, and a declaration may not take them." I accept plt's or devops's wording as well, so "any" of the three is fine. I do not accept a wording that names which compiler check reads which list.
>
> **Reasoning.** 04:193 says "(above)", but that is a pointer. It does not say that the list is complete and that it defines the reserved set. A model that reads the new rule and 04:193 can see two lists, one for "accepted" and one for "reserved". The definition line is one sentence of user-visible fact, in the same form as 04:193, so it is not an implementation detail. It also makes the `Async` change to §4.3 carry both meanings with no further edit. The drift risk that sys and min name is real, and a compiler test should hold both checks to one table in any case. That test and this line do not conflict.
>
> **Concern.** If the line wins and a std module later adds a built-in effect outside §4.3, the line is wrong until someone edits it, and a model will trust the stale list.

###### Minimalism

> Files read: PANEL_RULES.md, ballot-D.md, brief.md, ballot.md, D1.md, D1/aiml.md, D1/devops.md, D1/min.md, D1/plt.md, D1/sys.md, D1/web.md.
>
> ## Q2. A line about a type named like a built-in effect
>
> **Vote:** A, wording A1 (one fact). Not A2.
>
> **Reasoning:** Probes n3 to n5 show the type side is unclear in the spec: `Template[DB]` compiles with no user `DB`, while `List[DB]` gives UnknownType, and 03b:829 says `List[DB]` compiles. Two sections point opposite ways, so one sentence is a repair of existing text, not a new "does not" line. A1 states the fact and adds no new mechanism. A2 adds which `Time` wins in type position, but 07:2846 already gives that answer for every shadowed name, so A2 repeats a rule the spec already holds. If A2's second half is wanted, a pointer to 07:2846 is enough; I do not need it in the sentence.
>
> **Concern:** The 03b:829 text on `List[DB]` still disagrees with the compiler (n5), and the new line does not fix that; someone must file it as a separate chore.
>
> ## Q3. The §4.3 list as the one source
>
> **Vote:** B.
>
> **Reasoning:** 04:193 already points "(above)" at the §4.3 list, so the spec already names one list. A definition line repeats it and then needs care each time the list or the two checks change. A compiler test that holds E0538 and `ReservedEffectName` to one table gives the guarantee at no spec cost. web and sys reached the same view.
>
> **Concern:** An implementer may build a second list for `ReservedEffectName`, and the spec gives no extra wording to point to when that drifts.

##### Owner tiebreak

Q3 stood at 3-3 (A: aiml, devops, plt; B: sys, web, min). The owner broke the tie for B. There is no definition line. §4.3 stays the one list, and 04:193 keeps pointing at it. The compiler test that holds E0538 and `ReservedEffectName` to one table carries the single-list guarantee.

Q2 ended 5-1 for A2. The dissent is Minimalism for A1: "A2 adds which `Time` wins in type position, but 07:2846 already gives that answer for every shadowed name, so A2 repeats a rule the spec already holds."

### Final Spec

```blink
effect Time { fn now() -> Int }        // ReservedEffectName (E0559): `Time` is a built-in effect name

effect Clock {
    effect Time {                      // legal: a sub-effect, and its handle is `clock`
        fn now() -> Int
    }
}

type Time { t: Int }                   // legal: a type, not an effect

fn stamp() -> Int ! Clock.Time {
    clock.now()
}

fn wall() -> Instant ! Time.Read {     // `Time` is the built-in effect in every module
    time.read()
}
```

```
error[ReservedEffectName]: `Time` is a built-in effect name
 --> clock.bl:1:8
  |
1 | effect Time {
  |        ^^^^ reserved: `Time` is a built-in effect
  |
  = help: rename it, for example `effect Clock`
  = help: to replace the clock in tests, write `handler Time { ... }` and use `with`
```

- The reserved names are `FS`, `Net`, `DB`, `IO`, `Env`, `Time`, `Rand`, `Crypto`, `Process`, `State` and `Async`. §4.3 holds the one list and gains `Async`, with its handle `async`.
- A top-level user `effect` with a reserved name is `ReservedEffectName` (E0559), in every module, `pub` or not.
- `Time` always means the built-in effect in rows, `with`, handlers and `time.x()` calls. No import reaches it.
- The rule covers the top-level name only. `effect Clock { effect Time { ... } }` stays legal.
- The rule reserves the `effect` declaration only. A `type` with a built-in effect name is legal, and in a type position the user type is the one named in its module.
- The help text gives the rename and the test advice: write `handler Time { ... }` and use `with`.
- §10.6 *Shadowing Rules* gains one sentence: the `effect` clause does not cover a built-in effect name. The §10.6 table stays types-only, and the ruling at DECISIONS.md:369 stands as written.
- §3b gains one sentence: a built-in effect name does not reserve a type name, so in a module that declares `type DB`, `Template[DB]` names the user type.
- No definition line states that §4.3 serves both E0538 and `ReservedEffectName`. 04:193 already points at the §4.3 list.
- A rename quick fix in the language server is tooling and is not spec text.
- The identity lookup in W0545 is a separate bug and is not part of this ruling.
- Existing code that declares `effect State` now fails with `ReservedEffectName`. The release notes for the implementation carry a note.
- AI-First 5/5 pass.
