[< All Decisions](../DECISIONS.md)

# Two Effects With One Handle — Design Rationale

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated
in independent-proposal → debate → vote rounds. Ticket IDs in the quoted text are replaced with `[ticket]`.

#### Phase A — Independent proposals

- **Systems:** (excerpt, section `G3 ([ticket]) Two effects with one handle`)

> Facts: the ticket MVCE passes check and ICEs in C (duplicate member `ue_ab`). Worse, I found the
> same collision against a built-in: `effect Io { effect Go { fn ping() -> Int } }` and
> `fn f() -> Int ! Io.Go { io.ping() }` with `fn main() ! IO { io.println("{f()}") }` passes check
> and the binary prints `0` with no handler installed (probe g3b.bl). E0559 reserves `IO` but not
> `Io`, whose handle is also `io`. That is a soundness hole, not only an ICE.
>
> Two layers, and both need a rule:
> 1. Codegen: the handler slot must be keyed by the effect's identity (module path + declared name),
>    never by the handle text. Then no surface rule can make C collide. This is a compiler fix, not
>    spec text, but the panel should say it so the check is not the only guard.
> 2. Surface: the handle is a name in scope; two meanings for one name must be a check error.
>
> **G3-P1 (preferred): error at the declaration inside one module, error at the use across modules.**
> - Two top-level effects in one module whose lowercase forms are equal: new code
>   `EffectHandleClash` at the second declaration name, note at the first, help: rename one.
>   In `blink check`.
> - A user effect whose lowercase form is a built-in handle (`Io`, `Fs`, `Db`, `NET`): widen E0559
>   ReservedEffectName to compare lowercase forms. Error at the name.
> - Across modules: a fn row may hold `a.Log` and `b.Log` (it may only call helpers). A use of the
>   handle `log.op(...)` in a scope where two distinct effects give `log` is new code
>   `AmbiguousEffectHandle` at the handle, notes at both row entries, help: move the call into a
>   helper fn whose row names one of them.
>
> ```blink
> import a
> import b
>
> fn la() ! a.Log { log.log("x") }             // OK
> fn lb() ! b.Log { log.log("y") }             // OK
> fn both() ! a.Log, b.Log { la()  lb() }      // OK: no handle use
> fn bad() ! a.Log, b.Log { log.log("z") }     // error[AmbiguousEffectHandle] at `log`
>
> effect Ab { effect Go { fn ping() -> Int } }
> effect AB { effect Go { fn ping() -> Int } } // error[EffectHandleClash] at `AB`
> effect Io { fn ping() -> Int }               // error[ReservedEffectName] (E0559): handle `io`
> ```
>
> Tradeoff: no runtime cost; one lowercase compare per declaration and per handle lookup.
>
> **G3-P2: handle keeps case (option C).** Rejected: it breaks the documented `Log` -> `log` rule
> for every effect and makes `AB` give a handle `AB` that reads as a type.
>
> **G3-P3: use-site error only (option B), also within a module.** Coherent but lets a module
> declare two effects that no fn can ever use together through handles; the declaration error is
> cheaper to read.
>
> Cross-language: Koka and Effekt name the effect operation directly, so they have no handle clash;
> our handle is a derived name, so we must check it as one.
>
> ---

- **Web/Scripting:** (excerpt, section `G3 ([ticket]): two effects with one handle`)

> The handle rule is settled (lowercase of the declared name; the qualifier never changes it).
> So within a module the user can rename; across modules they cannot.
>
> ### G3-P1 (PREFERRED): error at the declaration inside one module; error at the use across modules
>
> 1. **One module**, two effect declarations whose handles are equal (`Ab`/`AB`, `Log`/`LOG`):
>    new code **EffectHandleCollision** at the second declaration, in `blink check`. Note at the
>    first; help: rename one. Also applies to two nested effects with one parent (`Ab.Go`/`Ab.GO`).
> 2. **Imported effects** (`a.Log`, `b.Log`): no error at the import or at a row. Rows propagate
>    to callers, so an error at the row would hit every caller that just calls two libraries. The
>    error is at a **use** of the handle where the enclosing fn's row holds two effects with that
>    handle: new code **AmbiguousEffectHandle** (or the same code with a second message), at the
>    handle, in `blink check`. The note lists both effects; help: move each use into its own fn
>    whose row names one of them.
>
> ```blink
> effect Ab { effect Go { fn ping() -> Int } }
> effect AB { effect Go { fn ping() -> Int } }    // error[EffectHandleCollision]: `AB` and `Ab` both give the handle `ab`
>
> import a
> import b
>
> fn log_a() ! a.Log { log.write("x") }             // OK: one `log` in this row
> fn log_b() ! b.Log { log.write("y") }             // OK
> fn both() ! a.Log, b.Log {                        // OK: no handle use
>     log_a()
>     log_b()
> }
> fn bad() ! a.Log, b.Log { log.write("z") }        // error[AmbiguousEffectHandle]: `log` is `a.Log` and `b.Log` here
> ```
>
> Tradeoffs: case-only twins in one file are always a bug or a smell; failing at the declaration
> is the clearest message. For imports, the error lands only where the user wrote the ambiguous
> line, and the fix (a small helper fn) is ordinary code. Either way the ICE goes away because
> check rejects every program where one handle has two meanings.
>
> Cross-language: TypeScript and Python flag two imports with one local name; macOS and Windows
> devs already know case-only file names cause pain.
>
> ### G3-P2: handle keeps case (`aB.ping()`)
>
> Rejected: reopens the settled lowercase rule and makes handle spelling a guessing game.
>
> ---

- **PLT:** (excerpt, section `G3. Two effects that give one handle`)

> The spec already settled the row case: a row with two effects that give one handle is E0562
> (§4.12, 04_effects.md:4985). The gap is where else a handle resolves. The sound, compositional
> rule: a handle is never resolved against declarations in scope; it is resolved against the
> set of effects available at the site, and that set may not hold two effects with one handle.
>
> ### G3-P1 (preferred): resolve a handle against the effects available at the site; widen E0562
>
> - The effects available at a site are the effects of the enclosing fn's row plus each effect a
>   `with` in force at the site handles. A handle `ab` names the one effect in that set whose
>   handle is `ab`.
> - Two effects with one handle in that set: E0562 EffectHandleCollision. For the row, at the row
>   (as today). For a `with` that adds an effect whose handle the set already has, at the `with`.
> - Two declarations `effect Ab` and `effect AB` in one module are legal by themselves. A fn that
>   uses one of them is fine; a fn that needs both is E0562.
> - Code generation keys each effect by its declared identity (module path + name), never by the
>   handle. The ICE (duplicate `ue_ab`) is a code generator defect under any option.
>
> ```blink
> effect Ab { effect Go { fn ping() -> Int } }
> effect AB { effect Go { fn ping() -> Int } }
>
> fn f() -> Int ! Ab.Go { ab.ping() }        // OK: `ab` is Ab.Go, the only `ab` in the row
> fn g() -> Int ! AB.Go { ab.ping() }        // OK: `ab` is AB.Go
> fn h() -> Int ! Ab.Go, AB.Go { ab.ping() } // error[E0562]: Ab.Go and AB.Go both have the handle `ab`
>
> import a
> import b
> fn k() ! a.Log, b.Log { log.log("x") }     // error[E0562], the cross-module case, as today
> ```
>
> Tradeoffs: one rule for the same-module and the cross-module case (a declaration-site rule can
> not reach the cross-module case: neither module is wrong). The rule is local to the fn. Adding a
> new effect to a module can never break a fn that does not name it. The cost: a module may keep
> two effects that differ only in case; that is a style matter, not a soundness one.
>
> ### G3-P2: also an error at the second declaration in one module
>
> Add a new code (`EffectHandleShadowed`) when one module declares two effects with one handle.
> Acceptable as an add-on to P1, not a substitute: P1 is still needed for imports. This seat is
> neutral; it is a lint-strength rule promoted to an error.
>
> ### G3-P3: keep case in the handle (`AB` gives `aB`, or `AB`)
>
> Rejected: it reopens the settled lowercase rule (04_effects.md:4966) and does not solve the
> cross-module `Log` case.
>
> Cross-language: Koka resolves an operation by its effect's qualified name and reports an
> ambiguous unqualified operation at the use; P1 is the same shape (judge at use, against what is
> in scope at the use).
>
> ---

- **DevOps:** (excerpt, section `G3 ([ticket]) two effects that give one handle`)

> Two cases with different fixes, so two rules.
>
> **G3-P1 (preferred): same module: error at the second declaration. Across modules: error at an
> ambiguous handle use only.**
>
> ```blink
> effect Ab { effect Go { fn ping() -> Int } }
> effect AB { effect Go { fn ping() -> Int } }   // error[E0xxx HandleCollision] at `AB`
> ```
> ```
> error[E0xxx]: effect `AB` gives the handle `ab`, and effect `Ab` (line 1) gives it too
>   = help: rename one of them; a handle is the lowercase form of the effect name
> ```
>
> Cross-module:
> ```blink
> import a
> import b
> fn relay() ! a.Log, b.Log {                        // OK: no handle used
>     a_work()
>     b_work()
> }
> fn main() {
>     with handler a.Log { fn log(m: Str) { } } {    // OK: handlers name the effect, not the handle
>         with handler b.Log { fn log(m: Str) { } } { relay() }
>     }
> }
> fn both() ! a.Log, b.Log {
>     log.log("x")      // error[E0xxx HandleCollision] at `log`: `a.Log` and `b.Log` both give it
> }
> ```
> Help for the use: "the handle `log` names two effects in this row; move the calls for one of
> them to a fn whose row has only that effect". One code for both sites; the JSON lists both
> effect declarations as related spans, so the LSP can link each.
>
> Tradeoffs: the declaration error in one module is cheap and always right (the author owns both
> names; a rename fixes it). Across modules the user owns neither name, and the handle cannot be
> qualified or aliased (settled), so an error at the row would forbid a pass-through row that is
> harmless and common (`main` handles both). Use-site only is the narrowest rule that closes the
> ICE. Completion: after `log.` with two candidates, the LSP offers nothing and shows the error.
>
> **G3-P2: error at the use only, in both cases.** Simpler rule, but a same-module collision
> then waits until someone writes `ab.`; the editor shows the error far from its cause.
>
> **G3-P3 (C, keep case in the handle).** Breaks the settled lowercase rule. Against.
>
> ---

- **AI/ML:** (excerpt, section `G3: two effects that give one handle`)

> ### G3-P1 (PREFERRED): error where two such effects first meet
>
> New code `EffectHandleCollision`, check time, at two kinds of site:
>
> 1. **Declaration, one module:** a second effect whose lowercase name equals the lowercase name of
>    an earlier effect in the same module. Error at the second declaration, note at the first,
>    help: rename one.
> 2. **Scope, any modules:** a fn row, or a `with handler` item, that brings in two different
>    effects with one handle. Error at the second row entry (or `with` item), note at the first.
>    A qualified and a bare spelling of one effect are one effect, so no error.
>
> ```blink
> effect Ab { effect Go { fn ping() -> Int } }
> effect AB { effect Go { fn ping() -> Int } }   // error[EffectHandleCollision]: `AB` and `Ab` both give the handle `ab`
>
> import a
> import b
> fn ok1() ! a.Log { log.log("x") }              // OK: one effect named Log here
> fn ok2() ! b.Log { log.log("y") }              // OK
> fn bad() ! a.Log, b.Log { log.log("z") }       // error at `b.Log`: `a.Log` and `b.Log` both give the handle `log`
> ```
>
> Tradeoffs (AI): the error comes before any use, so a model never has to guess which effect
> `ab.ping()` reached. Both sites are syntactic and local; a model checks them by reading one
> module or one row. Rule (2) also closes the C collision (`ue_ab` twice), so check keeps the
> promise. Help for (2) in the cross-module case: wrap one effect in a local effect with another
> name, or split the fn. Rare in practice; cost lands only on code that would be ambiguous anyway.
>
> ### G3-P2: error only at an ambiguous handle use (option B)
>
> Fewer errors, but a fn with `! a.Log, b.Log` and no `log.` call still ICEs in C unless codegen
> also changes, and the error moves away from its cause. More to learn, not less.
>
> ### G3-P3: handle keeps case (option C)
>
> Reopens the settled lowercase rule; rejected. Also `LOG` -> handle `LOG` reads as a constant.
>
> ---

- **Minimalism:** (excerpt, section `G3 ([ticket]) Two effects with one handle`)

> The rule exists: E0562 EffectHandleCollision (04_effects.md:4985, catalog row 194) rejects a row
> that holds two effects with the same handle. Probes on gen1:
> - `fn f() -> Int ! Ab.Go, AB.Go { ab.ping() }` checks clean: E0562 misses case-folded names. A bug.
> - `fn f() -> Int ! Ab.Go { ab.ping() }` reports "needs effect AB.Go": a resolution bug; the
>   handle must resolve through the row of the fn.
>
> ### G3-P1 (PREFERRED): no new rule; state that E0562 compares handles, and the row picks the effect
>
> - E0562 compares handles (the lowercase form), not names. `Ab` and `AB`, `LOG` and `Log`,
>   `a.Log` and `b.Log` all collide when one row holds both. One error, at the row, in check.
> - A row that holds one of them is legal. The handle resolves to the effect in that row. Two
>   such declarations in one module are legal.
> - The cross-module case is the example E0562 already shows.
> - The ICE (duplicate `ue_ab` member) is a codegen naming bug: the C name must come from the
>   effect's full path, not its handle. No language change.
>
> ```blink
> effect Ab { effect Go { fn ping() -> Int } }
> effect AB { effect Go { fn ping() -> Int } }
>
> fn one() -> Int ! Ab.Go { ab.ping() }          // OK: the row holds one effect with handle `ab`
> fn two() -> Int ! AB.Go { ab.ping() }          // OK
> fn both() -> Int ! Ab.Go, AB.Go { ab.ping() }  // error[EffectHandleCollision] (E0562) at the row
> ```
>
> Tradeoffs: zero new surface. A declaration-site ban (ticket option A) is a second rule for a
> case the row rule already makes safe; option C (handle keeps case) breaks "the handle is the
> lowercase form" in every example and doc.
>
> ### G3-P2 (acceptable fallback): also a lint-free error at the second same-module declaration
>
> Only if the panel wants an early catch. I see no user who needs it.
>
> ---

#### Phase B — Debate highlights

- **Systems:** (excerpt)

> ## G3: change. I now hold G3-D in this form: E0562 fires at a handle USE, not at the row.
>
> I missed that E0562 exists. Its text rejects any row with `a.Log, b.Log`. That is my objection to
> G3-R and G3-A: effects propagate. If `la()` needs `a.Log` and `lb()` needs `b.Log`, every caller
> of both must hold both in its row, up to the fn that handles them. Under R or A, two libraries
> that each declare `Log` can never be used in one call chain unless one is handled below the
> first common caller. The user owns neither name, and the handle cannot be qualified or aliased
> (settled). So the error at the row bans a composition that is safe.
>
> What makes it safe is codegen keyed by effect identity, which all six seats want. After that,
> the only defect left is a name lookup with two answers. Report it at the lookup.
>
> ```blink
> import a
> import b
>
> fn la() ! a.Log { log.log("x") }             // OK
> fn lb() ! b.Log { log.log("y") }             // OK
> fn both() ! a.Log, b.Log { la()  lb() }      // OK: no handle use (today E0562)
> fn bad() ! a.Log, b.Log { log.log("z") }     // error[EffectHandleCollision] (E0562) at `log`
> ```
>
> A `with handler b.Log` inside a fn whose row holds `a.Log` is fine; a `log.` use inside that
> block is E0562 at the use. Handlers name the effect, never the handle.
>
> Same module (`effect Ab`, `effect AB`): an error at the second declaration (same code, E0562).
> I keep it but it is not load-bearing; I can vote R's "legal" if the use-site rule wins.
>
> Load-bearing for me, and no other seat took it up: **widen E0559 ReservedEffectName to compare
> lowercase forms.** Probe: `effect Io { effect Go { fn ping() -> Int } }`, `fn f() -> Int ! Io.Go
> { io.ping() }`, `fn main() ! IO { io.println("{f()}") }` checks clean and prints `0` with no
> handler. `main` declares `IO`, and nearly every `main` does. Under any G3 option a user effect
> whose handle is `io`, `fs`, `net`, `db`, `env`, `time`, `rand`, `crypto`, `process`, `state` or
> `async` collides with the built-in in almost every program. The fix is the same as for `IO`: the
> name is reserved. Ballot: please list this as its own yes/no item.

- **Web/Scripting:** (excerpt)

> ## G3: I keep D (an error at a handle use across modules), and the use-site rule carries the weight. I oppose R and A for the row case. Widen E0559 (sys): yes.
>
> - The argument against a row error (R, A, and today's E0562 text): rows are transitive. Say `fn save()` in lib a has `! a.Log` and `fn send()` in lib b has `! b.Log`. Then any fn that calls both must write `! a.Log, b.Log`, and so must every caller up to the handler site. Under R that row is an error. Splitting the code into helpers does not help, because the caller of the helpers needs both effects again. The only way out is to handle one effect early. So two independent libraries that both declare an effect named `Log` cannot be used together in one call chain. The fix the error suggests ("rename one effect") is not open to the user for third-party code. The error must be where the ambiguity is: a handle use. `with` a handler for a second colliding effect is likewise an error only if a handle use inside it is ambiguous (answers (c): no error at the `with` itself).
> - Today's E0562 example is exactly a fn that uses `log` with both effects in its row. Under D that example still errors (at the use), so the spec example stays true. Only the error site moves from the row to the use.
> - Same-module declarations: I keep the error at the second declaration, because it is the earliest and clearest message and the user owns both names. I would trade it away for agreement: under the use-site rule it is a nice-to-have, not needed for soundness.
> - Code: one code for both sites is fine (devops): retarget E0562 EffectHandleCollision. That avoids a new code.
> - E0559: yes, compare lowercase forms. `effect Io` with a silent `io.ping()` returning 0 is a trap.

- **PLT:** (excerpt)

> ## G3: change to D (sys/web): error at the handle use across modules, error at the declaration in one module
>
> Position:
> - A row may hold two effects that give one handle. A use of that handle, where two effects
>   with it are available, is the error, at the handle. "Available" means the fn's row plus each
>   effect that a `with` in force handles.
> - Two declarations in one module that give one handle: an error at the second declaration.
> - Widen E0559 to compare lowercase forms (sys), so `effect Io` is reserved.
> - Codegen keys each effect by its identity.
>
> Why I changed (compositionality): under R and A, and under today's E0562 text, a fn that calls
> two library fns, one needing `a.Log` and one needing `b.Log`, must write both in its row, and
> then it is an error. Two libraries that each declare a `Log` effect could then never be used
> by one caller, except through a handler that discharges one of them. The fault is the name,
> not the row. The name is ambiguous only where someone writes it. Haskell and ML treat an
> ambiguous occurrence the same way: an import of two modules that export one name is legal,
> and only an unqualified use of that name is an error. My Phase A proposal (R) put the error
> at the row. That is the non-compositional rule. I withdraw it.
>
> - Against R and A: both reject `fn both() ! a.Log, b.Log { la()  lb() }`, which has no
>   ambiguity at all, and a row error spreads to every caller.
> - The declaration error in one module: I am neutral on soundness, because the use rule already
>   covers that case. I support it because the author controls both names, so the earliest error
>   is the best one.
> - Code count (one code or two; retarget E0562 to the use site) is a writer matter. Note: the
>   E0562 text and its example in 04_effects.md:4985-4991 must change. `fn both() ! a.Log, b.Log`
>   stops being an error.

- **DevOps:** (excerpt)

> ## G3: keep D, with one code.
> - In one module, two effects with one handle: error at the second declaration. Across modules, a row
>   may hold `a.Log, b.Log`, and the error is at a handle use whose set of effects (the row plus each
>   `with` in force) has two effects with that handle. Use E0562 at both sites and change its row
>   text. Also support sys: widen E0559 to compare lowercase forms (`effect Io`). That fixes a check-clean
>   wrong run, which is the most serious fact in this batch.
> - Against A and R (an error at a row that never uses the handle): a fn that only calls `la()` and
>   `lb()` from two libraries must carry both effects in its row. With a row error, no fix exists that
>   the user owns: they cannot rename either effect, and the handle cannot be qualified or aliased
>   (settled). E0562's help "put each use in its own function" is already true of `both`, but it still
>   gets the error. A rule whose help does not fix the error is a diagnostic bug. The row error also
>   travels: it fires in every caller up the chain, not only where the ambiguous line is.
> - Against R with no declaration error: `effect Ab` and `effect AB` in one file is always a mistake,
>   and the author owns both names. Wait for a use, and the editor shows the error far from its cause.
> - (c) A `with` that adds a colliding effect: not an error by itself. A handle use inside it is an
>   error (the use-site set includes the `with`). Same reason: the error goes where the ambiguous line is.

- **AI/ML:** (excerpt)

> ## G3: CHANGED. Same-module declaration error + cross-module error at the handle use only (G3-D)
>
> - Changed from Phase A (G3-A). devops's point decides it: a row propagates to callers and the
>   handle cannot be qualified or aliased (settled). Under a row-level error (A, R, today's E0562
>   text), a fn that calls one helper of lib `a` and one of lib `b` must list `a.Log, b.Log` and
>   is rejected; nested `with handler a.Log`, `with handler b.Log` in main is rejected under the
>   `with` clause (my A, plt). So two libraries that each declare `Log` cannot meet on any call
>   path. A model cannot fix that by renaming: it owns neither name. That is a composition bug,
>   not a safety rule.
> - The use-site error lands on the line that is actually ambiguous, and the fix (move the call
>   into a helper whose row names one effect) is ordinary, local code.
> - Same module: keep the declaration error. The author owns both names, the rename is the fix,
>   and it fires before any use, so the model never sees a confusing "needs effect AB.Go".
> - Code: one code for both sites (devops): reuse E0562 EffectHandleCollision with two messages.
>   Fewer codes to learn; the name fits both. E0562's row text narrows to the use site.
> - Support sys (d): widen E0559 to compare lowercase forms against built-in handles
>   (`effect Io` gives `io`). sys's probe shows a silent wrong value (prints 0, no handler). That
>   is a soundness hole; it belongs in this vote.
> - Codegen keys by effect identity under every option (all seats agree); writer note, not ballot.
> - Against R: correct within one fn, but its row clause forbids composition (above), and it
>   leaves `Ab`/`AB` in one module legal, which is always a typo for a model to trip on later.
>
> ```blink
> import a
> import b
> fn la() ! a.Log { log.log("x") }             // OK
> fn lb() ! b.Log { log.log("y") }             // OK
> fn both() ! a.Log, b.Log { la()  lb() }      // OK: no handle use
> fn bad() ! a.Log, b.Log { log.log("z") }     // error[E0562] at `log`
>
> effect AB { effect Go { fn ping() -> Int } } // error[E0562] at `AB` when `Ab` is declared above
> effect Io { fn ping() -> Int }               // error[E0559]: handle `io` is reserved
> ```

- **Minimalism:** (excerpt)

> ## G3: CHANGED. E0562 moves from the row to the handle use; no declaration error
>
> devops/sys's point is correct and it beats my Phase A: an error at the row makes two effects
> with one handle unusable together anywhere up the call chain. A fn that calls `la()` (needs
> `a.Log`) and `lb()` (needs `b.Log`) must hold both in its row, and so must each caller up to
> the handler. The E0562 help ("put each use in its own function") does not fix that.
>
> Position: a row may hold two effects with one handle. E0562 fires at a handle use whose name
> matches two or more effects available at the site (the row, plus each `with` in force), in
> check. A handle compares by lowercase form. Codegen keys by effect identity. No error at the
> declaration: two same-module declarations are only a case of the use rule, so a second rule
> for them is redundant. Keep the code E0562; only its site and text change.
>
> ```blink
> effect Ab { effect Go { fn ping() -> Int } }
> effect AB { effect Go { fn ping() -> Int } }    // OK
> fn one() -> Int ! Ab.Go { ab.ping() }           // OK: one effect gives `ab` here
> fn both() -> Int ! Ab.Go, AB.Go { one() + 1 }   // OK: no handle use
> fn bad() -> Int ! Ab.Go, AB.Go { ab.ping() }    // error[EffectHandleCollision] (E0562) at `ab`
> ```
>
> Against A (aiml): an error at the second row entry is the row rule again, with the same
> call-chain problem. Against D's two codes: one code covers it.
>
> (d) sys's widening of E0559 to compare lowercase forms: YES. A built-in handle is in force in
> every fn, so `effect Io` would make each `io.` use ambiguous; a declaration error is the clear
> site for a built-in name. That is the one place a declaration error earns its keep.

#### Phase C — Final vote

- **G3-Q1: where the collision is an error** (6-0, option USE: at a handle use; the other option was ROW, an error at the row)
- **G3-Q2: two effects of one module with equal handles** (5-1, option DECL: E0562 at the second declaration; Minimalism dissented for LEGAL)
- **G3-Q3: widen E0559 to lowercase forms** (6-0, YES)

- **Systems:**

> ## G3-Q1: USE
> Reasoning: effects propagate, so a row error makes two libraries that each declare `Log` unusable on one call path, with no fix the user owns. Once codegen keys each effect by its identity, the row is safe; the only defect left is a lookup with two answers, so report it at the lookup.
> Concern: the error appears only when someone writes the handle, so a library author never sees the clash their effect name causes for users.

> ## G3-Q2: DECL
> Reasoning: the author owns both names, the rename fixes it, and the earliest site gives the clearest message. It costs one lowercase compare per declaration.
> Concern: two codes or two messages under E0562 must stay clearly apart in the catalog so a tool can tell the declaration site from the use site.

> ## G3-Q3: YES
> Reasoning: the probe shows `effect Io` passes check and `io.ping()` prints 0 with no handler: a silent wrong value. A built-in handle is in force in nearly every `main`, so the clash is near certain; reserve the name as `IO` already is.
> Concern: none of note; a user effect named `Time`-like in other case (`TIME`) breaks, which pre-1.0 allows.

- **Web/Scripting:**

> ## G3-Q1: USE
> Reasoning: rows are transitive. Under ROW, two third-party libraries that each declare `Log` can never meet in one call chain, and the user owns neither name, so no fix is available to them. The error belongs on the line that is actually ambiguous, and the fix there (a small helper fn) is ordinary code.
> Concern: users may not know why `log.log` is ambiguous in a fn that only "obviously" means one; the note must list both effects and the helper-fn fix.

> ## G3-Q2: DECL
> Reasoning: `effect Ab` and `effect AB` in one module is always a mistake, and the author owns both names. The earliest error, at the declaration, beats a confusing "needs effect AB.Go" at a far-off use.
> Concern: none of note. It is redundant with USE for soundness, so it must use the same code (E0562) and not add a second one.

> ## G3-Q3: YES
> Reasoning: sys's probe shows `effect Io` makes `io.ping()` print 0 with no handler, check clean. That is a silent wrong result in almost every program, because nearly every `main` has `IO`. Reserving the lowercase handle is the obvious fix.
> Concern: the message must say the *handle* `io` is reserved, or a user named `Io` will think the rule is case-sensitive and be confused.

- **PLT:**

> ## G3-Q1: USE
> Reasoning: effect rows are transitive. A row error therefore forbids `fn both() ! a.Log, b.Log { la()  lb() }`, which has no ambiguity, and it travels to every caller up to the handler. Two libraries that each declare `Log` could then never meet on one call path. The defect is a name lookup with two answers, and it belongs at the lookup. Haskell and ML treat an ambiguous occurrence the same way. Codegen keyed by effect identity makes everything else sound.
> Concern: the "available set" must include each `with` in force, or a handle use inside a `with handler b.Log` in a fn whose row holds `a.Log` resolves silently to one of them.

> ## G3-Q2: DECL
> Reasoning: under USE this rule is not needed for soundness. But the author owns both names, so the earliest error, at the declaration, is the clearest one. It adds no non-local judgment, because it is about one module.
> Concern: none of substance. If the vote goes LEGAL, USE still covers every unsound case.

> ## G3-Q3: YES
> Reasoning: a built-in handle is the identity that users write, and E0559 exists to reserve built-in names. Comparing by spelling leaves `effect Io` free to shadow `io`, and sys's probe shows a silent wrong value. Comparing lowercase forms makes E0559 reserve the handle, which is the thing that can collide.
> Concern: the list of reserved handles must come from the built-in effect table, not a hand-written list, or it will drift.

- **DevOps:**

> ## G3-Q1: USE
> Reasoning: rows are transitive, so an error at the row bans two libraries that each declare `Log` from meeting on any call path, and the user owns neither name and cannot qualify or alias the handle. E0562's own help ("put each use in its own function") does not fix a row error; it does fix a use error. The error lands on the line that is really ambiguous.
> Concern: the error is only as good as its notes; it must list both effect declarations as related spans, or the user cannot tell which `log` is which.

> ## G3-Q2: DECL
> Reasoning: in one module the author owns both names, and a rename is the fix. The earliest error, at the declaration, is the clearest, and it stops the confusing "needs effect AB.Go" before any use exists.
> Concern: none of weight; it overlaps the use rule, so the same code (E0562) must fire at both sites to keep the catalog small.

> ## G3-Q3: YES
> Reasoning: `effect Io` today passes check and prints 0 with no handler. That is a wrong result with no diagnostic, the worst kind. A declaration error at the name is the only site the user can act on, since nearly every `main` declares `IO`.
> Concern: the list of built-in handles that is reserved must come from one table, or a new built-in effect will open the same hole again.

- **AI/ML:**

> ## G3-Q1: USE
> Reasoning: rows propagate and the handle cannot be qualified or aliased, so a row error means two libraries that each declare `Log` can never meet on one call path, and the user owns neither name. The use-site error lands on the line that is ambiguous, and the help (move the call into a helper whose row names one effect) really fixes it.
> Concern: the spec example and E0562 text in 04_effects.md must change in the same commit, or models trained on the old text will keep "fixing" harmless rows.

> ## G3-Q2: DECL
> Reasoning: in one module the author owns both names; the earliest error with a rename help is the cheapest for a model, and it avoids today's confusing "needs effect AB.Go" at a use. `Ab`/`AB` in one module is always a typo.
> Concern: none for soundness; if it loses, the USE rule still covers the case, only later.

> ## G3-Q3: YES
> Reasoning: `effect Io` checks clean and `io.ping()` prints 0 with no handler (sys probe): a silent wrong value, the worst class. Comparing lowercase forms is one rule a model already knows from how handles are formed.
> Concern: the error must list the reserved handles in its note, so a model picks a name that is free on the first retry.

- **Minimalism:**

> ## G3-Q1: USE
> Reasoning: rows are transitive, so a row error bans a safe composition of two libraries that each declare `Log` all the way up the call chain, with a help ("put each use in its own function") that does not fix it. The only real defect is a name lookup with two answers; report it at the lookup. Same code, E0562, retargeted; no new surface.
> Concern: the "available set" (row plus each `with` in force) must be defined once and match how handle lookup already works, or check and codegen will disagree again.

> ## G3-Q2: LEGAL
> Reasoning: under USE, `Ab` and `AB` in one module are already safe: a use where both are available is E0562, and a fn whose row holds one resolves to it. A declaration error is a second rule for a case the first rule covers. YAGNI; I do not block DECL.
> Concern: under LEGAL, a typo pair in one file shows its error only at a use, possibly far from the declaration; the E0562 note must point at both declarations.

> ## G3-Q3: YES
> Reasoning: a built-in handle is in force in nearly every fn, so `effect Io` makes almost every `io.` use ambiguous, and sys's probe shows a silent wrong value today. For built-in names the declaration is the right site, and this is the existing E0559 rule with one compare changed.
> Concern: the list of reserved handles must be derived from one table of built-in effects, not hand-copied into E0559.

### Final Spec

```blink
import a
import b

fn la() ! a.Log { log.log("a") }                // OK
fn lb() ! b.Log { log.log("b") }                // OK
fn both() ! a.Log, b.Log { la()  lb() }         // OK: a row with two effects of one handle is legal

fn bad() ! a.Log, b.Log {
    log.log("x")                                // error[E0562] at the use: `a.Log` and `b.Log` both have the handle `log`
}

fn added() ! a.Log {
    with handler b.Log.Emit { fn log(msg: Str) { } } {
        lb()                                    // OK: a `with` that adds one is legal
        log.log("y")                            // error[E0562]: the row holds `a.Log`, the `with` adds `b.Log`
    }
}

effect Ab { effect Go { fn ping() -> Int } }
effect AB { effect Go { fn ping() -> Int } }    // error[E0562] at `AB`, note at `Ab`
effect Io { effect Say { fn say(msg: Str) } }   // error[E0559] at `Io`: the handle `io` is the handle of `IO`
```

- A row may hold two effects with one handle, and a `with` may add one. This is legal (Q1).
- E0562 is at a handle use where two or more available effects have that handle. The available effects are the row of the enclosing fn and each `with` in force. Handles compare in lowercase.
- The use-site error lists both effect declarations as related spans.
- Two top-level effects of one module with equal lowercase names are E0562 at the second declaration, with a note at the first (Q2, 5-1; Minimalism dissented for LEGAL).
- E0559 compares lowercase forms, so `effect Io` is an error at its name (Q3).
- "The effects available at a site" is defined once, in §4.4, where the handle lookup is defined.
- Spec text: §4.4 *The effects available at a site*, §4.3 *A built-in effect name is reserved*, §4.12 *One handle for two effects*, §10 note on qualified effect names, E0559 and E0562 in ERROR_CATALOG.md.
