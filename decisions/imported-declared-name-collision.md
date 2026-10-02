[< All Decisions](../DECISIONS.md)

# Imported and Declared Name Collision — Design Rationale

A module could declare a name and also bind the same name with a selective import:

```blink
// alpha.bl
pub type Point { a: Int }

// main.bl
import alpha.{Point}
pub type Point { b: Int }
```

The compiler accepted this with no diagnostic: the local declaration won. The early return in
`nr_check_ambiguity` (src/typecheck.bl) skipped every declaration kind, so `fn helper` and a
module-level `let` were hidden the same way (a probe with both a `type` and a `fn` collision printed
"ok"). The spec stated no rule. The ticket proposed a new warning shaped like W1000 and W1010.

## Summary

| Q | Question | Result | Vote |
|---|---|---|---|
| Q1 | Rule | Compile error for every declaration kind (`type`, alias, `trait`, `effect`, `fn`, module `let`), both namespaces; the check uses the name after `as` | 6-0 |
| Q2 | Code | Widen E1012 to any selective import; drop "public" and "re-export" from its title and text | 6-0 |
| Q3 | Rollout | Error now; sweep src/ and lib/std/ in the same change | 6-0 |
| Q4 | Auto-fix text | Spec text next to E1012 (machine-applicable for plain `import`, suggestion for `pub import`, emptied list becomes `import alpha` unless no resolved name uses the qualifier, E1012 replaces W0602) | 6-0 in Phase D after 4-2 in Phase C (web, min: tooling note) |
| Q5a | "Shadowing happens only between nested scopes" sentence in §10.6 | Yes | 6-0 |
| Q5b | Sentence that the §10.1 qualifier rule (`let auth = 5`) is a different layer | Yes | 5-1 (Min: 5a already covers it) |
| Q5c | `import blink.core.{Handler}` + `type Handler` is E1012, not W1010; reword W1010 | Yes | 6-0 |
| Q5d | Both `as` examples | Yes | 6-0 |

**A note on quotation.** Panelist text below is verbatim: each panelist wrote each submission to a
file, and the texts are those files. The one exception is `br` ticket identifiers: `br` is
local-only, so each is replaced by a bracketed description of the ticket. No other text was changed.

---

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated in
independent-proposal → debate → vote rounds. All six proposed a compile error in Phase A. The
mechanical dedupe left one main option (E) with two fallbacks (F1: the existing W0602; F2: a new
W-code) and five variations (code, rollout, auto-fix, extra spec text, the two-imports-one-alias
ticket). Phase B ran one round, after which all six signalled "stable, ready to vote". Phase C was a
silent vote. Q4 came out 4-2 and went to a Phase D round on Q4 alone. Before Phase D the moderator
gave the panel one codebase fact: the spec already states, for single diagnostics, whether a fix is
machine-applicable (§8.6 at 06_tooling.md:284, 02_syntax.md:830, 07_trust_modules_metadata.md:91,
:524 and :702, 03b_contracts.md:635, 06_tooling.md:1434, and the ERROR_CATALOG E0538 row).

#### Phase A — Independent proposals

##### Systems

> **Sys proposal: gap [this spec ticket] (own declaration vs. a selective import of the same name)**
>
> **What the hardware sees.** Nothing. C symbols carry the module prefix (`alpha_Point` vs `main_Point`), so the linker never sees a clash, and either answer costs nothing at runtime. The check is one map lookup per imported name at name resolution. This is only a source-clarity question. I care that a name means one thing and that the reader can see which one.
>
> **The ticket picks the wrong analogues.** W1000 and W1010 cover names the user never wrote: a dependency path, and the implicit prelude. In this case the user wrote both names, in the same file, at module scope. The closest rules are the ones about two written names in one flat namespace, and every one of them is an error:
> - Two module `let`s with the same name: DuplicateModuleBinding, error. DECISIONS says "module-level does not [shadow]" (5-0).
> - Two imports of one bare name: E1005, error.
> - A module that defines a name and also `pub import`s it: E1012, error.
>
> The plain `import B.{foo}` plus `fn foo` case is the one gap in that set, and today it is exempt for every declaration kind (the `local_names` early return). In the probe, `helper` silently resolved to the local fn while `import alpha.{helper}` sat in the file looking live, and W0602 did not fire. That is a dead import that looks live, which is worse than a warning case.
>
> ---
>
> **Proposal A (preferred): error. Widen E1012 to cover non-`pub` selective imports.**
>
> ```blink
> // main.bl
> import alpha.{Point}
> pub type Point { b: Int }
> ```
> ```
> error[E1012]: `Point` is both imported and declared in module `main`
>  --> src/main.bl:2:10
>   |
> 1 | import alpha.{Point}
>   |               ^^^^^ imported from `alpha` here
> 2 | pub type Point { b: Int }
>   |          ^^^^^ also declared here
>   |
>   = help: drop `Point` from the import list and use `alpha.Point`,
>           or import it under another name: import alpha.{Point as AlphaPoint}
> ```
>
> - Scope: every declaration kind that enters module scope (`type`, alias, `trait`, `effect`, `fn`, `let`/const). The exemption is kind-blind today, so the fix must be too.
> - Not affected: `import alpha` (whole module, no bare name), and `import alpha.{Point as P}` (no collision).
> - No new code. E1012 already has this exact two-span shape. It goes from "defines and re-exports" to "defines and imports". Fewer codes means less for tools and LLMs to learn.
> - §3.4 holds: a type name resolves to one declaration identity, and no silent rule is needed to pick it.
> - The fix is always local, has one obvious form, and keeps the program the same. An auto-fix can drop the import entry, because today the import has no effect anyway.
> - Cost: a breaking change for code that compiles today. Before landing, sweep src/ and lib/std/ for the pattern. If the sweep finds many hits, ship it as a warning for one release, then make it an error.
>
> Cross-language: Rust gives E0255 ("the name `X` is defined multiple times") for `use a::X; struct X;`, a hard error. Go gives "X redeclared in this block" when an import name clashes with a file-scope declaration. Zig rejects a duplicate decl that collides with `const X = @import(...).X`. All three treat this as a duplicate, not as shadowing.
>
> **Proposal B (fallback): warn (W1011 ImportShadowedByDeclaration), and W0602 also fires.**
> Same spans as above, as a warning. This is better than silence, but it still lets a program build where `import alpha.{Point}` says one thing and the code does another. Downside for Sys: two diagnostics for one mistake, and the import stays dead code that the warning only points at. If the panel picks warn, the import must at least count as unused, so W0602 fires.
>
> **Proposal C (rejected): keep silent.** This is the only case in the module system where two written module-scope names collide with no diagnostic. A user reads `import alpha.{Point}` and gets `main.Point`, which breaks locality of reasoning (07:1559).
>
> **Out of scope, noted:** 07:1557 (`let auth = 5` shadowing the *module qualifier* `auth`) puts a value name over a qualifier, not two names in one namespace. Leave it alone here. If anything is done with it, it belongs with [the module-scope collision code-drift ticket].
>
> **Preference: A.** Make it an error under a widened E1012, covering all declaration kinds, with a sweep of src/ and lib/std/ first. Module scope is flat, and two names written in one flat namespace are a duplicate.

##### Web/Scripting

> The case is already an error next door, so I propose an error here too.
>
> ## Web panelist — Phase A proposal ([this spec ticket])
>
> ### What I see first
>
> The user wrote both lines, in one file, maybe ten lines apart. This is not a hidden shadow. W1010 warns because the builtin name was never imported; the user may not know it is there. W1000 warns because the two modules are in different places on disk. Here the user typed `import alpha.{Point}` and then typed `type Point`. One of those two lines is a mistake. A silent win hides the mistake. A warning reports it but still compiles code where one line has no effect.
>
> The spec already answers the pub version of this case. E1012 (07:1954) makes `pub import B.{foo}` plus `pub fn foo` a compile error. With silent shadowing, removing `pub` from the import line turns that error into nothing. A JS dev cannot learn a rule where `pub` turns a conflict on and off.
>
> Other facts point the same way:
> - Module scope is flat, with no shadowing (02:714, DECISIONS 5-0).
> - Two imports of one bare name is E1005.
>
> A selective import puts the name in module scope. So an import plus a declaration of the same name is a duplicate module-level name.
>
> ### Proposal 1 (preferred): error, for every declaration kind
>
> ```blink
> // alpha.bl
> pub type Point { a: Int }
>
> // main.bl
> import alpha.{Point}
> pub type Point { b: Int }   // error
> ```
>
> ```
> error[E10xx]: `Point` is both imported and declared in this module
>  --> src/main.bl:2:10
>   |
> 1 | import alpha.{Point}
>   |               ^^^^^ imported from `alpha` here
> 2 | pub type Point { b: Int }
>   |          ^^^^^ also declared here
>   |
>   = help: drop `Point` from the import list, or import it under another name:
>           import alpha.{Point as AlphaPoint}
> ```
>
> - **Scope:** every declaration kind: `type`, alias, `trait`, `effect`, `fn` and module `let`. The probe shows the exemption in the compiler covers `fn` too. A rule for types only would leave `fn helper` silent and create a second gap.
> - **Code:** one E-code shaped like E1012, with two labelled spans and a help line. E1012 stays as the pub case, or the new code takes it over; that is wording for the spec owner.
> - **DX:** both fixes are one edit, and the help line gives the fix in full. A beginner will not need Stack Overflow, because the error shows both lines.
> - **Cost:** code that compiles today breaks. That code always has a dead import, so the break finds a real defect. The migration is mechanical.
>
> ### Proposal 2 (fallback if the panel will not break code): report it as an unused import
>
> No new code. The shadowed import is dead, so W0602 must fire, and today it does not (probe: no diagnostic at all). The wording extends W0602:
>
> ```
> warning[W0602]: unused import `Point`
>  --> src/main.bl:1:15
>   |
> 1 | import alpha.{Point}
>   |               ^^^^^ never used: the declaration at line 2 shadows it
>   |
>   = help: remove `Point` from the import list, or import it as `alpha.{Point as AlphaPoint}`
> ```
>
> - **Plus:** no new language surface. It points at the line that does nothing, the import, and not the declaration.
> - **Minus:** it keeps the rule that `pub` changes the outcome (E1012 against a warning), so it is less coherent. Warnings also get ignored. In CI with `-W error` it acts as an error, without the clear message.
>
> ### Proposal 3 (rejected): a new W10xx at the declaration, as the ticket proposes
>
> This copies W1010's shape onto a case W1010 does not cover. The user wrote the import, so "shadows" is the wrong frame: there is nothing hidden to tell them about. It also adds a code that does the job of W0602 worse. I vote against it.
>
> ### How other languages handle it
>
> | Language | Same-file import plus declaration |
> |---|---|
> | TypeScript | Error TS2440, "Import declaration conflicts with local declaration of 'Point'" |
> | Rust | Error E0255, "the name `Point` is defined multiple times" |
> | Go | Error, "Point redeclared in this block" |
> | Python | Allowed; linters flag it as F811 (redefinition of unused name) |
>
> So the typed languages with explicit imports make it an error, and Python only warns through a linter. Blink's no-wildcard rule ("every name in scope is explicitly imported", 07:1560) puts it with the typed languages: the import block must tell the truth about what each bare name means.
>
> ### Preferred
>
> **Proposal 1.** It is an error for every declaration kind, with two spans and a help line that gives the `as` fix in full. It matches E1012, E1005 and the flat module-scope rule, and what TS and Rust users already expect. If the panel will not break existing code, use Proposal 2, which extends W0602. Proposal 2 must not ship with the error as the plan for later, because a later move from warning to error breaks the same code a second time.
>
> The panel does not own one item: `let auth = 5` shadowing the *module qualifier* `auth` (07:1557) is a separate namespace question. Proposal 1 does not change it.

##### PLT

> # PLT proposal: selective import vs own declaration of the same name
>
> ## Framing: this is not shadowing
>
> Shadowing needs two scopes, one nested inside the other. The inner binding hides the outer one. Every case the ticket uses as an analogue has that nesting:
>
> - **W1010:** the prelude and compiler-known names form an implicit outer scope that the user never wrote.
> - **W1000:** dependencies form an outer resolution layer under local modules.
> - **07:1557:** a `let` hides a module qualifier, and the module name sits in a lower layer.
> - **Function-local shadowing:** this is lexical nesting.
>
> A selective import has no such nesting. `import alpha.{Point}` is a binding the user wrote, in the module's own namespace. That is the same place as `pub type Point`. The spec says module scope is flat: "there is no inner scope for shadowing to inhabit" (02:714). DECISIONS.md agrees 5-0: "module-level does not [shadow]".
>
> So the case is two bindings of one name in one flat scope. The spec already rejects every other version of that:
>
> | Pair in one module scope | Rule |
> |---|---|
> | decl + decl | error (DuplicateModuleBinding) |
> | import + import | error E1005 |
> | `pub import` + `pub` decl | error E1012 |
> | import + decl | **silent (the gap)** |
>
> The gap is the only member of this family that the compiler accepts. The ticket's framing ("shadowing is allowed everywhere else") compares it with the wrong family.
>
> There is also a soundness-of-intent problem. Under the current rule, the import can never be used bare. It is dead on arrival, and the compiler does not even emit W0602. A program accepted with a binding that can never be reached is the same "accepted and then unusable" shape that §3.4 forbids for type declarations.
>
> ## Proposal P1 (preferred): make it an error, for every declaration kind
>
> ```blink
> // main.bl
> import alpha.{Point}
> pub type Point { b: Int }
> ```
>
> ```
> error[E1005]: `Point` is both imported and declared in this module
>  --> src/main.bl:2:10
>   |
> 1 | import alpha.{Point}
>   |               ----- imported from `alpha` here
> 2 | pub type Point { b: Int }
>   |          ^^^^^ declared here
>   |
>   = help: use the qualified name `alpha.Point` and drop it from the import list,
>           or rename the import: `import alpha.{Point as AlphaPoint}`
> ```
>
> The rule: a bare name that a selective import brings in must not also be declared at module level. This holds in both namespaces (types and values), so `fn helper` vs `import alpha.{helper}` is the same error. The rule does not depend on `pub`, and it does not depend on whether either binding is used.
>
> On the code: reusing E1005 makes it "collision of two explicit bindings", which covers import/import and import/decl. A fresh E10xx with the same shape is also fine. That choice is cosmetic, and I defer to devops on it. E1012 then becomes a special case: `pub import` + `pub` decl. The spec can keep it as its own code or fold it in. The `help:` line names the existing `as` rename, so the fix is one edit.
>
> **Tradeoffs**
>
> - **Pro, compositionality:** each bare name resolves to exactly one binding, and you learn which one from the import block plus the declarations. That is the locality guarantee in §10.1 ("an AI reading a file can determine every available name from the import block alone"). It holds without an order-dependent or priority rule.
> - **Pro:** this is the same rule as E1005 and DuplicateModuleBinding. It adds no new concept.
> - **Con:** it breaks programs that compile today. The cost is small: the probe shows the import is already dead, so the fix is to delete or rename it.
> - **Con:** adding a `pub` name to a dependency cannot cause this, because only *selective* imports are checked. A name the user never listed never collides. So the rule is stable under library evolution, which a glob-import language could not promise.
>
> ## Proposal P2 (fallback): own declaration wins, and the import is dead
>
> If the panel wants to keep accepting the program, then the honest diagnostic is not "shadows". It is: the import binds nothing.
>
> ```
> warning[W0602]: unused import `Point`
>  --> src/main.bl:1:15
>   |
> 1 | import alpha.{Point}
>   |               ^^^^^ hidden by the local declaration on line 2; it can never be used here
>   |
>   = help: remove `Point` from the import list
> ```
>
> This reuses W0602 and needs no new code. It is still weaker than P1. It writes into the spec a priority order inside a flat scope (decl > import), and DECISIONS.md rejected that at module level.
>
> ## Rejected: a new "shadows imported type" W-code (the ticket's option 2)
>
> This option copies W1010's form without W1010's reason. W1010 exists because the user cannot avoid the outer binding: the prelude is always in scope. Here the user wrote both bindings. A warning about a conflict the user created, in a scope with no nesting, is an error that has been downgraded. It also leaves `fn` vs imported `fn` unhandled unless the code is generalized, and then it is P1 at warning severity.
>
> ## Cross-language note
>
> - **Haskell:** a top-level `data Point` plus `import Alpha (Point)` gives "Ambiguous occurrence" at every use, and you resolve it by qualification. That is an error, not shadowing.
> - **Rust:** `use alpha::Point;` plus `struct Point` gives E0255 "defined multiple times", an error at the declaration, and the fix is `use alpha::Point as AlphaPoint`. That is exactly P1.
> - **OCaml:** `open` shadows by textual order. Blink has no ordered module scope, so the OCaml model does not carry over.
>
> ## Preference
>
> **P1.** Make it an error for all declaration kinds and both namespaces, at the declaration site, with the `as`-rename help line. Also amend the spec to say plainly that "shadowing" means only nested scopes (prelude, dependency, function-local), and that a collision inside the flat module scope is always an error.

##### DevOps

> # DevOps/tooling proposal: a declaration that clashes with a selective import
>
> ## The key point: this is not the W1000/W1010 case
>
> W1000 and W1010 warn about names the user **did not write in this file**: a dependency they pulled in, or a builtin that is in scope implicitly. Here the user **wrote both bindings in the same file**: `import alpha.{Point}` and `pub type Point`. The spec already treats module scope as flat and does not allow shadowing in it. DECISIONS.md: "module-level does not" (5-0). 02:714: "there is no inner scope for shadowing to inhabit." So the closest analogues are not W1000/W1010. They are the other module-scope cases where two bindings claim one name, and each of those is an error:
>
> - two imports of one name: E1005
> - two `let`s with one name: E1016 (spec calls it E1009)
> - a definition plus a `pub import` of the same name: E1012
>
> An import that a local declaration always beats is dead code. It can never resolve. Today it also suppresses W0602, which the gen1 probe confirmed. So the user gets no signal at all. A silent dead import is the worst result for tooling: the LSP hover, go-to-definition and the import block all disagree about what `Point` means.
>
> ## Proposal A (preferred): error, with one fix that is safe to apply automatically
>
> ```blink
> import alpha.{Point, helper}
> pub type Point { b: Int }
> fn helper() -> Int { 2 }
> ```
>
> ```
> error[E1017]: `Point` is both imported and declared in this module
>  --> src/main.bl:2:10
>   |
> 1 | import alpha.{Point, helper}
>   |               ----- imported from `alpha` here
> 2 | pub type Point { b: Int }
>   |          ^^^^^ declared here
>   |
>   = note: module scope is flat; one name has one meaning
>   = help: drop `Point` from the import list
>           or rename the import: `import alpha.{Point as AlphaPoint}`
>           or use the qualified name `alpha.Point` and drop the import
> ```
>
> - **Scope:** every declaration kind that puts a name in module scope (`type`, alias, `trait`, `effect`, `fn`, `let`/const). The probe shows the exemption in `nr_check_ambiguity` covers all of them, so the rule must too. A rule only for types would leave `fn helper` silent, and that is the same bug.
> - **Auto-fix:** "Drop `Point` from the import list" keeps behaviour the same. Every use already resolves to the local declaration, so the fix can be machine-applicable (`blink fix`, LSP quick-fix with `isPreferred`). When the import list becomes empty, the fix deletes the whole `import` line. "Rename the import" is a second code action, but not the preferred one, because the user must pick the name.
> - **Spans:** primary span on the declaration name. Secondary span on the import item. Both are needed so the LSP can show the error at both places.
> - **Code:** a new E10xx (E1017 above, as a placeholder). Do not reuse E1005: E1005's help text ("use qualified names for both") does not fit, because a local declaration has no qualified form. Assign the final number together with [the module-scope collision code-drift ticket]'s code cleanup.
> - **Migration risk:** low. The error fires only on code that has a dead import. The auto-fix makes the change for the user. The existing behaviour stays the same for every program that compiles.
>
> ## Proposal B (fallback): warning, but the warning targets the import
>
> If the panel will not accept an error, then do **not** use the ticket's wording ("type declaration shadows imported type", span on the declaration). Put the warning on the dead import. That is where the fix is applied:
>
> ```
> warning[W1011]: imported `Point` is never used: a local declaration takes the name
>  --> src/main.bl:1:15
>   |
> 1 | import alpha.{Point}
>   |               ^^^^^ hidden by `pub type Point` at src/main.bl:2:10
>   |
>   = help: drop `Point` from the import list
> ```
>
> This is in effect W0602 with a better reason. You could also extend W0602 rather than add a new code. Tradeoff: under `@allow` the dead import stays forever, and "one name has one meaning" stops being true for module scope. LSP rename gets ambiguous: a rename of `Point` at the import line must decide which binding the user meant.
>
> ## Rejected: keep silent
>
> There is no diagnostic, no dead-import warning, and hover disagrees with the import block. This also breaks the 07 promise: "an AI reading a file can determine every available name from the import block alone". Here the import block lies.
>
> ## Cross-language note
>
> - Rust: E0255, "the name `X` is defined multiple times" for `use a::X; struct X;`. It is an **error**, and rustc suggests `use a::X as OtherX`. rust-analyzer gives that fix as a quick-fix. This is exactly Proposal A.
> - Go: "X redeclared in this block" for an import name that clashes with a top-level declaration. Also an error.
> - TypeScript: "Import declaration conflicts with local declaration of 'X'" (TS2440). Also an error.
>
> All three of the toolchains I use as references make this an error. None warns.
>
> ## Preferred
>
> **Proposal A.** Make it a hard error (new E10xx) for every declaration kind, with the "drop from import list" fix marked machine-applicable. It matches the flat module-scope rule that the panel already decided 5-0. It matches E1005, E1012 and E1016. It matches Rust, Go and TypeScript. And a fix that keeps behaviour the same means the change costs users close to nothing. The 07:1557 rule ("local definitions shadow module names") does not apply. That rule is about a module *qualifier* (`auth.`) in the value namespace, not a selectively imported item. The spec should say so in one sentence.

##### AI/ML

> ## AI/ML panelist: Phase A proposal ([this spec ticket])
>
> ### Framing
>
> W1010 is a different case. A prelude name comes into scope without the user writing anything, so the user cannot see the conflict and a warning is the right signal. Here the author wrote both lines in the same file: `import alpha.{Point}` and `pub type Point`. That is not shadowing. It is two declarations of one bare name at module scope, and module scope is flat (02:714, "no inner scope for shadowing to inhabit"). Once the local type wins, the import line is dead code that still reads as true. That breaks the spec's own promise at 07:1557: "an AI reading a file can determine every available name from the import block alone." With the current silent rule, the import block gives the wrong answer for `Point`.
>
> Models make this mistake often. They add an import to fix an "unknown name" error without seeing a local type further down, or they move a type into another module and forget to delete the old local copy. Today nothing tells them. Under option 2 they get a warning, which agent loops usually ignore, so the import stays dead.
>
> ### Proposal A (preferred): compile error for every declaration kind
>
> ```blink
> import alpha.{Point, helper}
>
> pub type Point { b: Int }
> fn helper() -> Int { 2 }
> ```
>
> ```
> error[E10xx]: `Point` is both imported and declared in this module
>  --> src/main.bl:3:10
>   |
> 1 | import alpha.{Point, helper}
>   |               ^^^^^ imported from `alpha` here
> 3 | pub type Point { b: Int }
>   |          ^^^^^ declared here
>   |
>   = help: drop `Point` from the import list; `alpha.Point` still works
>   = help: or import it under another name: import alpha.{Point as AlphaPoint}
> ```
>
> - **Scope:** a selective import's bound name (after `as`) matches any module-level declaration: `type`, alias, `trait`, `effect`, `fn`, or module `let`. The probe shows `fn` is exempted the same way as `type`, so a rule that covers only types leaves the same hole.
> - **Consistency:** this is the module-scope "no duplicates" rule (E1009/E1016, decided 5-0) applied to imported names. It also extends E1012 (define plus `pub import` is an error) to plain `import`, and it matches E1005 (two imports of one bare name is an error). Of all the options, it adds the least new rule.
> - **One-step self-correction:** both spans are shown, and both fixes are mechanical edits on one line. Qualified access (`alpha.Point`) still works, so the user loses nothing by removing the name from the import list.
> - **Cost:** existing code that relies on the silent win breaks. That code only exists because of the bug in the ambiguity check, and the fix is one line.
> - **Cross-language:** Rust (E0255, "defined multiple times") and TypeScript (TS2440, "Import declaration conflicts with local declaration") both make this an error. Go also rejects it as a redeclaration. The training data from those languages points to an error. Python's silent rebinding is the outlier, and it is the pattern we want models to stop copying.
>
> ### Proposal B: warning (the ticket's option 2), widened to all declaration kinds
>
> The same diagnostic as A, but at warning level as W10xx. It is better than staying silent, but it keeps two meanings of one bare name in one file, and the import block stays false. A warning only helps when a human reads it. Generated code that compiles with warnings ships. I rank it second.
>
> ### Proposal C: keep the current silent behaviour
>
> This is the worst option for models. There is no signal at all, the import block is wrong, and the local `Point` gets used where the author meant `alpha.Point`. Then the next error, for example E0300 "expected Point, found Point", shows up far from its cause.
>
> ### Required with A or B: W0602 must fire here
>
> Today an import that the local declaration hides does not trigger W0602 (unused import), even though nothing can ever use it. With A this goes away, because the program does not compile. With B, W0602 must also fire, or the dead import stays invisible.
>
> ### Notes
>
> - The 07:1557 rule (`let auth = 5` hides a module qualifier) is a different axis: a value against a module qualifier, not two bare names in one namespace. I leave it out of scope.
> - Neighbouring tickets: A partly answers [the two-imports-one-alias ticket] (two aliases to one name) by the same principle, "one bare name, one source per module". [the module-scope collision code-drift ticket] should place the new code next to E1009/E1016 when it fixes the code drift.
>
> **Preferred: Proposal A.** Make it an error for every declaration kind, with both spans in the diagnostic and two help lines (drop the import, or alias it).

##### Minimalism

> Proposal from Min (minimalism), Phase A, ticket [this spec ticket].
>
> **Core point.** The ticket treats this as shadowing. It is not. `import alpha.{Point}` is something the user wrote, and it puts `Point` into the module's flat scope. A local `type Point` then puts a second `Point` into that same scope. The spec already has a rule for every case where two declarations of one name meet at module scope, and every one of those rules is an error:
>
> - Two module `let`s with the same name: E1009/E1016 ("no inner scope for shadowing to inhabit", decided 5-0).
> - Defining a name and also `pub import`ing it: E1012.
> - Two imports that bring in one bare name: E1005.
> - The DECISIONS.md rule that module level does not shadow (5-0).
>
> The two warn-analogues in the ticket do not apply here:
> - W1010 (prelude) covers names the user never imported. The warning exists because the collision is invisible in the source. Here the collision is in the source, three lines up.
> - W1000 is about package paths, not bare names.
> - 07:1557 is about a value name versus a module qualifier, which is a different namespace layer.
>
> So the gap is not "which warning". The gap is that one case is missing from a rule that already exists.
>
> ---
>
> ### Proposal 1 (preferred): widen E1012 to cover any import, not only `pub import`. No new code.
>
> ```blink
> // main.bl
> import alpha.{Point}
> pub type Point { b: Int }   // error
> ```
>
> ```
> error[E1012]: duplicate symbol `Point` in module `main`
>  --> src/main.bl:2:10
>   |
> 1 | import alpha.{Point}
>   |               ^^^^^ imported here
> 2 | pub type Point { b: Int }
>   |          ^^^^^ also defined here
>   |
>   = help: drop `Point` from the import list, or rename one:
>           import alpha.{Point as AlphaPoint}
> ```
>
> - The rule applies to every declaration kind (`type`, alias, `trait`, `effect`, `fn`, module `let`). The probe shows the silent exemption also hides `fn helper`, and a types-only rule would leave that hole open.
> - Spec change: about one sentence in §10 plus a wording change to E1012 ("duplicate public symbol" becomes "duplicate symbol"). The `pub` case stays an error and is now a special case of the general rule.
> - Compiler change: remove the local-names early return in `nr_check_ambiguity`. This makes the code smaller.
> - No impact on correct programs. Every failing program has a dead import, and the fix is to delete it or alias it.
>
> **Tradeoffs.**
> - Pro: zero new codes. One rule ("one bare name, one declaration, module-wide") replaces a list of special cases.
> - Pro: it keeps the 07:1559 promise that "an AI reading a file can determine every available name from the import block alone." A shadow-plus-warn rule breaks that promise: the import block says `Point` is alpha's, and it is not.
> - Con: stricter than the ticket's option 2. A refactor that moves a type into the module fails until the import is cleaned up. That is a one-line fix that the help text names exactly.
>
> **Alternative code choice.** Reuse E1005 and add a second label ("defined here"). I prefer E1012 because its rendered text already has this exact shape.
>
> ---
>
> ### Proposal 2 (fallback if the panel wants it allowed): no new code; fix W0602.
>
> A selective import that a local declaration shadows can never be used, so by definition it is an unused import. The probe shows W0602 does not fire today. That is a bug in an existing diagnostic, not a gap in the language.
>
> ```
> warning[W0602]: unused import `Point`
>  --> src/main.bl:1:15
>   |
> 1 | import alpha.{Point}
>   |               ^^^^^ never used: the local `type Point` (line 2) takes this name
>   |
>   = help: remove `Point` from the import list
> ```
>
> - Pro: this is the ticket's option 2 without adding a W10xx code.
> - Con: it still lets the import block lie about what names mean until someone reads the warning.
>
> ---
>
> ### Rejected: a new W10xx (the ticket's option 2)
>
> It adds a code that duplicates W0602's job and turns module-scope duplication into allowed shadowing, which goes against a 5-0 decision. Burden of proof is on the addition, and it does not meet it.
>
> ### Cross-language notes
>
> - **Rust:** `use a::Point; struct Point;` is error E0255, "defined multiple times".
> - **Go:** an imported package name that collides with a file-level declaration is a compile error. Go also rejects unused imports.
> - **Python:** allows this silently, and is the standard example of why that is a mistake.
>
> The two languages most often cited for smallness choose the error.
>
> ### Out of scope
>
> The aliased-import case (`import alpha.{Point as P}` plus a local `type P`) falls under the same rule with no extra wording. Ticket [the two-imports-one-alias ticket] (two aliases to one name) is the import-only version of the same rule. Under Proposal 1, E1005 already decides it the same way, so the panel may note that [the two-imports-one-alias ticket] closes for free.
>
> **Preferred: Proposal 1.** Widen E1012 to "a name imported and defined in one module is an error", for all declaration kinds. No new code, and the compiler gets smaller.

#### Phase B — Debate, round 1

##### Systems

> **Sys, Phase B round 1**
>
> All six of us pick Option E: an error, for every declaration kind. I keep that position.
>
> **V1, code.** I still prefer widening E1012. It already has the two-span shape, and DuplicateModuleBinding, E1005 and E1012 already make the code set large. I agree with devops that E1005 is the wrong home, because its help line ("use qualified names for both") has no meaning for a local declaration. A new E10xx is acceptable to me. The difference is small. What I do require: whichever code wins, the spec states one rule, "a bare name has one binding in module scope", and the codes only label which pair collided. If the panel picks a new code, assign it together with [the module-scope collision code-drift ticket] so we do not create more drift.
>
> **V2, rollout. I concede to web.** A warning first and an error later breaks the same code twice, and Blink is pre-1.0. The correct plan: sweep src/ and lib/std/, fix every hit in the tree in the same change, then land the error. No warning phase.
>
> **V3, auto-fix. I support it, with one correction.** Devops says that when the list becomes empty the fix deletes the import line. That is not always safe. 07:1555 says a selective import also gives qualified access ("`import auth.{login}` ... `auth.Token` still works"). If the file also uses `alpha.helper()`, deleting `import alpha.{Point}` breaks that use. So the fix must rewrite an emptied list to `import alpha`, not delete the line. The fix may delete the line only when nothing in the file uses the qualifier `alpha.`. With that rule the fix keeps behaviour the same, so it can be machine-applicable.
>
> **V4, spec text. I support both sentences.** They are cheap and they stop this ticket from coming back:
> 1. PLT: "shadowing" means only nested scopes (prelude, dependency, function-local). A collision of two bindings in the flat module scope is always an error.
> 2. Devops: 07:1557 (a value name over a module qualifier) is a different layer, and this rule does not change it.
>
> **V5, [the two-imports-one-alias ticket].** Two aliases that bind one name are an import-plus-import pair, so E1005 already covers them by the same rule. The panel can say that in the record. But this panel should not close [the two-imports-one-alias ticket]. Its owner should check that the compiler really emits E1005 for the alias case. The probe for this ticket showed the compiler is laxer than the spec.
>
> **One more point (systems).** The compiler change is to replace the `local_names` early return in `nr_check_ambiguity` with an error. That is the same map lookup the code does today, so the change adds no compile-time cost and no runtime cost. The C symbols are module-prefixed either way.
>
> SIGNAL: stable, ready to vote

##### Web/Scripting

> # Web — Phase B round 1 ([this spec ticket])
>
> All six of us chose Option E. I keep it. Below are my positions on V1–V5.
>
> **V1 — code: I change to (b), widen E1012.** Sys and Min are right. A JS dev learns one rule, "one name, one meaning per module", and one code. A new E10xx teaches two codes for one mistake. E1012's message must drop "public", for example "`Point` is both imported and declared in module `main`". The `pub import` case stays inside it with no change in behaviour. I reject (c), reuse E1005. Devops showed that E1005's help ("use qualified names for both") gives the wrong fix: a local declaration has no qualified form. A wrong help line produces Stack Overflow questions.
>
> **V2 — rollout: error at once, no warning release.** Moving from a warning to an error breaks the same code twice. Users first learn to ignore a warning, and then they get a break anyway. Blink is pre-1.0 (0.x), so a break costs least now. Sys's sweep is good practice, but it is our own work. If src/ or lib/std has hits, fix them in the same change. That is not a reason to add a warning period for users.
>
> **V3 — auto-fix: support.** "Drop from the import list" keeps behaviour the same, because the import is already dead. Mark it machine-applicable and make it the preferred LSP quick-fix. Delete the line when the list becomes empty. This is tooling and does not need spec text. One sentence in the spec is enough: "the fix that drops the entry keeps behaviour the same."
>
> **V4 — spec text: support, in two sentences at most.** PLT's sentence answers the question the ticket author asked: why W1010 warns and this case is an error. Put it in §10.6: "Shadowing applies only to nested scopes (prelude, dependencies, function-local). Two bindings of one name in the flat module scope are always an error." Devops's sentence on 07:1557 prevents the obvious follow-up question ("but `let auth` shadows!"), so I accept it too. Neither sentence changes behaviour.
>
> **V5 — [the two-imports-one-alias ticket]: note it, do not close it here.** Two aliases that bind one name is import plus import. That is E1005's area, not E1012's, and it is not on this ticket. Record "same principle" and let the owner close [the two-imports-one-alias ticket] after a check.
>
> **New point: state the alias case explicitly.** The rule matches the *bound* name, the one after `as`:
> - `import alpha.{Point as P}` with `type P` is an error.
> - `import alpha.{Point as P}` with `type Point` is fine.
>
> The second case is the fix the help line recommends. If the spec does not say this, someone will ask whether the fix itself triggers the error.
>
> SIGNAL: stable, ready to vote

##### PLT

> # PLT, Phase B round 1
>
> All six panelists landed on Option E for the same reason: the module scope is flat, so this is a duplicate binding, not shadowing. My remaining points are about getting the details right.
>
> **V1, the code.** I withdraw E1005. Devops is right: E1005's fix ("qualify both") has no meaning for a local declaration, because a local declaration has no qualified form. For the rule itself, the correct reading is DuplicateModuleBinding: an imported name is a module-scope binding. That code is caught up in [the module-scope collision code-drift ticket]'s drift, though. Widening E1012 to "duplicate symbol: imported and defined" is a good second choice. E1012's `pub` case is already this rule, limited to `pub`, so widening it removes a special case and adds no new concept. I support **(b), widen E1012**, and I am not opposed to a new code if [the module-scope collision code-drift ticket] renumbers.
>
> **V2, rollout.** I agree with web: no warn-then-error. A staged rollout breaks the same code twice and makes the spec state a rule it does not mean yet. Sys's sweep is good practice. Fix any hits in src/ and lib/std/ in the same change that lands the error.
>
> **V3, auto-fix.** I agree, with one limit that follows from the semantics. "Drop from import list" keeps behaviour the same only for a **non-`pub`** import, where every bare use already resolves to the local declaration. For `pub import` + `pub` decl (today's E1012), the program has never compiled, so no "current meaning" exists to keep. Dropping the re-export could change the public API that the author intended. So that case gets the fix as a suggestion, not as machine-applicable.
>
> **V4, spec text.** I keep this item, but I narrow it to one sentence in §10.6 Shadowing Rules: "Shadowing happens only between nested scopes: prelude under module, dependency under local module, and outer under inner in a function. Two bindings in module scope, from declarations or selective imports, are a duplicate (E1012)." The sentence stops the next ticket from arguing "shadowing is allowed everywhere" again. Devops's one-line note that 07:1557 is about a module *qualifier*, not a bare-name binding, fits well next to it.
>
> **New point: interaction with W1010.** `import blink.core.{Handler}` + `type Handler` now falls under the new error, not W1010. The user wrote both bindings, so this is correct. But the spec should state it, because W1010's text says it "covers module-level definitions reached by an explicit import". That phrase must read as "a name *declared in another module* and imported here", not "an import of the builtin itself".
>
> **Scope of the bound name.** The check uses the name after `as`. `import alpha.{Point as P}` + `type P` is an error, and `import alpha.{Point as P}` + `type Point` is fine. The spec should give both examples.
>
> **V5.** I agree that [the two-imports-one-alias ticket] follows from the same principle (one bare name, one binding), and E1005 already covers it. The panel should note this, not decide it.
>
> SIGNAL: stable, ready to vote

##### DevOps

> # Phase B r1 — devops
>
> All six of us chose Option E. I hold it. Here are my positions on V1–V5.
>
> **V1 (code): I change my position to (b), widen E1012.** I asked for a new E10xx so the code would name one failure mode. Sys and min showed that E1012 already is that failure mode ("one name, two written bindings in one module"), and that its rendered shape (two labelled spans) fits as it is. One code for the whole family is better for tools: `blink explain E1012`, LSP code-action lookup and LLM recall all key on the code. [the module-scope collision code-drift ticket] is also still fixing code drift (E1009/E1016), and a new number now adds to that work. Conditions:
> - The message must not mention `pub` or re-export. Use "`X` is both imported and declared in module `m`" for both cases.
> - Do not use E1005. Its help ("qualify both names") is wrong when one binding is local.
>
> **V2 (rollout): I side with web. No warning release first.** A move from warning to error breaks the same code twice and makes us spec a temporary W-code. The migration cost is low because the fix keeps behaviour the same and can be applied automatically. Sweep src/ and lib/std/ before landing, as sys asks. Hits there are a compiler bootstrap matter: fix them in the same change. They are not a reason for a user-facing warning phase.
>
> **V3 (auto-fix): I keep it and add one detail.** For a plain `import`, "drop `X` from the import list" is machine-applicable, because the import already binds nothing. The fix deletes the whole `import` line when the list becomes empty. For the existing `pub import` case, the same fix changes public API intent, so mark it as a suggestion only. The LSP decides per instance, so one code can carry both levels. I also ask for one rule: E1012 replaces W0602 on that import entry. One mistake gives one diagnostic, never two.
>
> **V4 (spec text): I support plt's sentence.** "Shadowing" means nested scopes only (prelude, dependency, function-local), and any collision in the flat module scope is an error. That one sentence also answers 07:1557, because a module qualifier is a lower layer, not a flat-scope binding. I do not need a separate change to 07:1557. This does not block the vote.
>
> **V5 ([the two-imports-one-alias ticket]): the same principle decides it, but do not close it here.** Two selective imports that bind one alias are an import+import collision, which falls under E1005 or under widened E1012. That choice is the [the module-scope collision code-drift ticket]/[the two-imports-one-alias ticket] owner's job. Note the link on that ticket and let it close on its own.
>
> SIGNAL: stable, ready to vote

##### AI/ML

> # aiml — Phase B round 1 ([this spec ticket])
>
> All six panelists prefer Option E. I keep it. Below are my positions on V1–V5.
>
> **V1, code: I move to (b), widen E1012.** One collision family should have one code, which gives a model one rule to learn: "a name in module scope comes from one place." E1012 already has the two-span shape: import plus declaration. Two conditions:
> - Drop "public" from the title. Make the title "`X` is both imported and declared in module `M`", so the text states the rule and does not depend on `pub`.
> - The help text must list the fixes for the plain-import case: drop the name, alias it, or use `alpha.X`.
>
> I reject (c), reuse E1005. As devops said, E1005's help ("qualify both") cannot apply, because a local declaration has no qualified form. A help line that cannot be followed costs the model a wasted step.
>
> **V2, rollout: I side with web. Make it an error at once, with no warning period.** The dead import never had any effect, so the fix changes no behaviour. A warning for one release means two version-dependent rules for one construct in the training data, and code written in that window teaches the wrong one. Do sys's sweep of src/ and lib/std/ before landing. Its result decides how much work the migration is, not which severity ships.
>
> **V3, auto-fix: support, with one new limit.** A machine-applicable "drop from import list" fix is the best case for agent loops: the diagnostic leads to one edit with no choice to make. The limit is that this fix is not behaviour-preserving for `pub import B.{X}` plus `pub fn X` (today's E1012). There, dropping the re-export, or dropping the declaration, changes the module's public API. So the fix is machine-applicable only for a plain `import`. For `pub import` it is offered but not preferred.
>
> **New point: state the rule in terms of the bound name.** The rule must use the name after `as`. Then `import alpha.{Point as P}` plus a local `type P` is an error, and `import alpha.{Point as AlphaPoint}` plus `type Point` is not. The second case is the help line's own fix. If the spec does not say this, the advised fix might itself be wrong.
>
> **V4, spec text: support plt's and devops's sentences.** Each one is a single line. "Shadowing means only nested scopes (prelude, dependency, function-local). A collision in the flat module scope is always an error." That gives a model learning from the spec a rule it can apply to cases nobody listed. The 07:1557 qualifier case stays as it is. One sentence saying it is a different layer stops a model from reading it as a counterexample.
>
> **V5, [the two-imports-one-alias ticket]: note it, do not close it here.** Two aliases that bind one name are import plus import, so E1005 decides it under the same principle. Record that the principle covers [the two-imports-one-alias ticket]. Whether to close it is up to that ticket's owner.
>
> SIGNAL: stable, ready to vote

##### Minimalism

> # Min — Phase B round 1
>
> All six panelists chose the error (Option E). Every panelist also rejects keeping it silent, and five of us reject the ticket's new W10xx. So the debate is now only about the variations V1–V5. My position on each:
>
> **V1 — diagnostic code. My first choice is still (b), widen E1012. I accept (a) if the majority wants a new code.**
> - E1012 already shows this case with the two spans "imported here / also defined here". If we widen it, the error is the same and only the word "public" is dropped from its title. The `pub` case does not change.
> - devops has a fair point against (c), E1005. Its help line says "use qualified names for both", and a local declaration has no qualified form. That objection does not apply to E1012.
> - A new code adds one more number for users, tools and LLMs to learn, for a rule we already have. I will not block over this, because the cost is small. But if we take (a), E1012 must then be folded into the new code. Two codes for the `pub` and non-`pub` forms of one rule is the worst result.
>
> **V2 — rollout. I agree with web: no warning release first.**
> - Blink is pre-1.0. A warning that later turns into an error breaks the same code twice and needs a deprecation plan, which is exactly the kind of surface we are trying to avoid.
> - sys's sweep of src/ and lib/std/ is good engineering, but it is an implementation step, not spec. The probe shows that every program that hits the error has a dead import, so the fix keeps behaviour the same.
>
> **V3 — auto-fix. Yes, but as a tooling note, not spec text.**
> "Drop the name from the import list" keeps behaviour the same, so the fix is machine-applicable. The spec already lets diagnostics carry fixes. Do not add a new normative rule for it.
>
> **V4 — extra spec text. I accept one sentence, and only one.**
> - I agree with plt's sentence in this narrow form, placed in §10.6: "Module scope is flat. A name bound by a selective import and a module-level declaration of the same name collide, as two declarations do. Shadowing applies only between nested scopes (prelude, dependency, function-local)." This stops the next ticket from using W1000/W1010 as analogues.
> - I reject devops's extra sentence about 07:1557. That rule covers a value hiding a module qualifier. It is out of scope, and touching it here makes the change wider for no gain.
>
> **V5 — [the two-imports-one-alias ticket].** I withdraw "closes for free" as a decision of this panel. Two aliases bound to one name is an import-plus-import collision. E1005 already appears to decide that case, but [the two-imports-one-alias ticket] is not on our agenda. Record it as a note on that ticket, not as a ruling.
>
> **Changes from my Phase A:** I concede that the code number is cosmetic (V1). I withdraw the claim about [the two-imports-one-alias ticket] (V5). I adopt plt's one-sentence amendment (V4).
>
> SIGNAL: stable, ready to vote

#### Phase C — Final vote

Tally: Q1 E 6-0; Q2 (b) 6-0; Q3 now 6-0; Q4 spec 4-2 (**Web/Scripting** and **Minimalism**
*(dissent)*: tooling note); Q5a yes 6-0; Q5b yes 5-1 (**Minimalism** *(dissent)*: no); Q5c yes 6-0;
Q5d yes 6-0. Each ballot below is verbatim.

##### Systems

> # Phase C ballot: sys ([this spec ticket])
>
> ## Q1: rule
> 1. **Vote:** E
> 2. **Reasoning:** Module scope is flat, so an import that a local declaration beats is a binding that can never be reached. That is a duplicate, not shadowing. The error costs nothing at runtime and nothing extra at compile time: it is the same map lookup `nr_check_ambiguity` already does, with an error where the early return is now. It also puts this case in line with DuplicateModuleBinding, E1005 and E1012, and with Rust (E0255), Go and TypeScript (TS2440).
> 3. **Concern:** If the check is added only for types, the `fn` and module `let` holes stay open. The test suite must cover every declaration kind in both namespaces.
>
> ## Q2: code
> 1. **Vote:** b (widen E1012)
> 2. **Reasoning:** E1012 already has the two-span "imported here / defined here" shape, and the `pub` case becomes one instance of the general rule. One code per collision family is easier for `blink explain`, the LSP and models. A new number would also add to the drift that [the module-scope collision code-drift ticket] is still cleaning up.
> 3. **Concern:** If the implementer leaves "public" or "re-export" in the E1012 title or help text, the message is wrong for the plain-import case. The spec example must show the plain-import form.
>
> ## Q3: rollout
> 1. **Vote:** now
> 2. **Reasoning:** I conceded this in round 1. A warning phase breaks the same code twice and needs a temporary W-code in the spec. The fix keeps behaviour the same, and Blink is pre-1.0.
> 3. **Concern:** Because of the bootstrap, a hit in src/ has to be fixed in a commit that gen0 can still compile. The sweep must run before the change lands, not after the error fires in `task ci`.
>
> ## Q4: auto-fix
> 1. **Vote:** spec
> 2. **Reasoning:** The emptied-list rule decides whether the fix is correct, not only how it looks. A selective import also gives `alpha.` qualified access (07:1555), so a tool that deletes the line breaks other code in the file. Every tool (`blink fix`, the LSP, agent loops) has to get this right in the same way, so it belongs in the spec, in one short paragraph. The plain-vs-`pub` split matters for the same reason: dropping a `pub import` changes public API.
> 3. **Concern:** The spec should also say that E1012 replaces W0602 on that import entry, as devops asked, so one mistake gives one diagnostic, not two. The ballot does not list this, and it can get lost.
>
> ## Q5: extra spec text
> - **5a: yes.** This sentence is the root fix for the ticket's framing. Without it, the next ticket uses W1000/W1010 as analogues again.
> - **5b: yes.** It is one sentence, and it stops 07:1557 from being read as a counterexample. It changes no behaviour, so it costs nothing.
> - **5c: yes.** `import blink.core.{Handler}` + `type Handler` is two bindings the user wrote, so the new rule must win over W1010. W1010's current text ("module-level definitions reached by an explicit import") is ambiguous enough that an implementer could emit the warning there instead of the error.
> - **5d: yes.** The alias form `{Point as AlphaPoint}` + `type Point` is the help line's own fix, so the spec must say plainly that it is legal. The check uses the bound name.
>
> **Concern (Q5):** Four extra sentences, which min wants to keep at one, could spread across §10 and §10.6. Put 5a, 5c and 5d together in §10.6 next to the rule, so a reader finds them in one place.

##### Web/Scripting

> # Web — Phase C ballot ([this spec ticket])
>
> ## Q1 — Rule
> **Vote:** E
> **Reasoning:** The user wrote both lines in one file, so one of them is a mistake, and a JS or TS dev expects to be told. TypeScript (TS2440), Rust and Go all make this an error, so most users arrive already expecting it. The fix is one edit, and the help line gives it in full.
> **Concern:** Users who copy Python habits will hit the error once and not know why "shadowing" is allowed for prelude names but not here, unless 5a's sentence is easy to find.
>
> ## Q2 — Code
> **Vote:** b
> **Reasoning:** One rule needs one code to learn, search and `blink explain`. A second code for the non-`pub` form of the same mistake would double the Stack Overflow questions with no gain. The title must drop "public" and "re-export", or the message reads wrong for a plain import.
> **Concern:** If someone widens the code but keeps the old E1012 title text, the message names `pub` for code that has no `pub`, and users will be confused.
>
> ## Q3 — Rollout
> **Vote:** now
> **Reasoning:** A warning that later becomes an error breaks the same code twice and teaches users to ignore the warning in the meantime. Blink is pre-1.0, so a break costs least now. Hits in src/ and lib/std are our own work and get fixed in the same change.
> **Concern:** If the sweep is skipped or partial, the bootstrap breaks, so the sweep must land in the same commit as the error.
>
> ## Q4 — Auto-fix text
> **Vote:** tooling
> **Reasoning:** The spec should say what the language does. Editor quick-fix levels and the emptied-list rewrite are tool behaviour. Record the behaviour (plain import machine-applicable, `pub import` suggestion only, an emptied list becomes `import alpha` unless the file does not use `alpha.`) as a binding tooling note, so it does not get lost.
> **Concern:** If the note sits only in a ticket and not in tooling docs, the LSP may ship the unsafe "delete the line" form that sys found.
>
> ## Q5 — Extra spec text
> - **5a:** yes
> - **5b:** yes
> - **5c:** yes
> - **5d:** yes
>
> **Reasoning:** Each sentence answers a question users will otherwise ask:
> - 5a: "why does `Option` shadow but this errors?"
> - 5b: "but `let auth` shadows!"
> - 5c: "`Handler` gave W1010 before, why an error now?"
> - 5d: "does the suggested `as` fix itself trigger the error?"
>
> Four short sentences cost less than four recurring questions.
> **Concern:** Each one adds spec text, and that text can grow over time. Keep each to one sentence or one pair of examples.

##### PLT

> # PLT ballot, Phase C ([this spec ticket])
>
> ## Q1: Rule
> 1. **Vote:** E
> 2. **Reasoning:** A selective import binds a name in the module's own scope, and that scope is flat (02:714, DECISIONS 5-0). So an import plus a declaration of one name is two bindings in one scope, which is a duplicate and not shadowing. The rule makes each bare name resolve to exactly one binding without a priority order. That matches §3.4 ("one declaration identity") and the E1005/E1012/DuplicateModuleBinding family. It must cover both namespaces and every declaration kind, because the current exemption ignores kind.
> 3. **Concern:** the implementation might add the check only for the type namespace and leave `fn`/`let` against an imported value silent, which is the same hole.
>
> ## Q2: Code
> 1. **Vote:** b
> 2. **Reasoning:** E1012's `pub` case is this rule limited to `pub`. Widening it removes a special case and adds no new concept, so the code matches the rule one-to-one. E1005 is wrong, because its "qualify both" fix has no meaning for a local declaration.
> 3. **Concern:** if the E1012 title or help text still says "public"/"re-export", the widened code will mislabel the plain-import case.
>
> ## Q3: Rollout
> 1. **Vote:** now
> 2. **Reasoning:** A staged rollout makes the spec state, for one release, a priority rule (decl over import) that it does not intend to keep. The break is cheap because every program it hits has a dead import, and the fix keeps meaning the same.
> 3. **Concern:** the sweep must cover lib/std/ as well as src/. A hit in an embedded stdlib module would break bootstrap, not just a user program.
>
> ## Q4: Auto-fix
> 1. **Vote:** spec
> 2. **Reasoning:** Whether the fix keeps meaning the same is a semantic fact, so the spec should own it. For a plain import every bare use already resolves to the local declaration. For `pub import` no compiled meaning exists to keep, and the export surface is at stake. Sys's emptied-list rule is required for correctness: under 07:1555 a selective import also gives the `alpha.` qualifier, so deleting the line could break qualified uses.
> 3. **Concern:** tools might implement "delete the emptied line" without the qualifier-use check, and then the fix silently breaks `alpha.helper()` calls.
>
> ## Q5: Extra spec text
> - **5a: yes.** This states the scoping principle that decides this ticket. Without it, a later ticket will use W1000/W1010 as analogues again.
> - **5b: yes.** A module qualifier is a separate layer under bare-name bindings. One sentence stops 07:1557 from being read as a counterexample to 5a.
> - **5c: yes.** Without it, W1010's "reached by an explicit import" phrase contradicts the new error for `import blink.core.{Handler}` + `type Handler`. Both bindings are written in one flat scope, so the error is the consistent answer.
> - **5d: yes.** The rule keys on the bound name. The second example proves that the help line's own fix (`as`) is legal.
>
> **Concern (Q5):** 5c changes how W1010 reads. The W1010 table and decision record should be checked for other text that assumes the builtin is reachable through an explicit import and then hidden.

##### DevOps

> # Phase C ballot — devops ([this spec ticket])
>
> ## Q1 — Rule
> 1. **Vote:** E
> 2. **Reasoning:** The user wrote both bindings, so the import is dead code that still reads as true. Hover, go-to-definition and the import block then disagree. An error with two spans and a fix that keeps behaviour the same is the clearest diagnostic surface. Rust (E0255), Go and TypeScript (TS2440) all do this.
> 3. **Concern:** The implementation could add the error but leave the `local_names` early return in place for some declaration kind (for example module `let` or `effect`). That would leave a quiet hole. The test suite must cover every kind and both namespaces.
>
> ## Q2 — Code
> 1. **Vote:** b
> 2. **Reasoning:** One collision family gets one code, so `blink explain`, code-action lookup and LLM recall each have one key to learn. E1012 already has the two-span shape. A new number now would add to [the module-scope collision code-drift ticket]'s drift.
> 3. **Concern:** If the title or explain text keeps "public"/"re-export" wording, the plain-import case looks wrong. The catalog entry and the §10 text must change in the same commit.
>
> ## Q3 — Rollout
> 1. **Vote:** now
> 2. **Reasoning:** The fix keeps behaviour the same and can be applied automatically, so a break costs little. A warning phase would break the same code twice and would make us spec a temporary code.
> 3. **Concern:** lib/std or src may have hits that need the self-host 2-step dance. The sweep must run first so the change does not land in a state where gen0 cannot build it.
>
> ## Q4 — Auto-fix
> 1. **Vote:** spec
> 2. **Reasoning:** Whether a fix is machine-applicable is a property of the language semantics. It depends on the plain-vs-`pub` split and on the 07:1555 rule that a selective import also gives qualified access. Every tool (blink fix, the LSP, third-party tools) must agree on it. If only one tool records it, tools drift. Sys's correction is right: an emptied list becomes `import alpha` unless nothing uses `alpha.`.
> 3. **Concern:** The "nothing uses `alpha.`" check must use resolved names, not text. A local binding named `alpha` (07:1557) would fool a text check.
>
> ## Q5 — Extra spec text
> 1. **Vote:** 5a yes, 5b yes, 5c yes, 5d yes
> 2. **Reasoning:**
>    - 5a gives the rule the next ticket will need, and it explains why W1010 warns while this case is an error.
>    - 5b costs one line and stops 07:1557 from being read as a counterexample. It also matters for the Q4 qualifier check.
>    - 5c is needed for correct diagnostics. Without it, `import blink.core.{Handler}` + `type Handler` could emit both W1010 and E1012. One mistake must give one diagnostic.
>    - 5d covers the help line's own fix. If the spec leaves it out, someone will ask whether the fix triggers the error.
> 3. **Concern:** The extra sentences could drift from the E1012 catalog text. Keep them in §10.6 and have them refer to E1012, not restate it.

##### AI/ML

> # Phase C ballot — aiml ([this spec ticket])
>
> ## Q1 — Rule
> 1. **Vote:** E
> 2. **Reasoning:** With E, the import block tells the truth: every bare name in a file comes from exactly one place, and a model can see which one by reading the file once. A warning still lets dead imports into generated code that "compiles", and agent loops often ignore warnings. The rule's two spans and two one-line fixes let a model correct the code in one step.
> 3. **Concern:** Some programs that compile today stop compiling, and gen0-era code samples will show the old silent behaviour for a while.
>
> ## Q2 — Code
> 1. **Vote:** b
> 2. **Reasoning:** One collision family should have one code, because models learn and recall a rule by its code. E1012 already has the import-plus-declaration shape. Widening it removes the special case where `pub` turns the error on and off.
> 3. **Concern:** If the wording keeps any trace of "public" or "re-export", a model will think plain imports are exempt. The title and help text must name the plain-import fixes.
>
> ## Q3 — Rollout
> 1. **Vote:** now
> 2. **Reasoning:** A warning release followed by an error release means two rules, each true for some versions, for one construct. Code written in the warning window then teaches the wrong rule. The fix changes no behaviour, so the error costs little to land at once.
> 3. **Concern:** The sweep may find hits in src/ or lib/std/ that need a gen0 bootstrap step, so the change must follow the two-step regen protocol.
>
> ## Q4 — Auto-fix
> 1. **Vote:** spec
> 2. **Reasoning:** Whether a fix is safe to apply without a human is part of what the diagnostic means. An agent applying fixes needs that fact to be the same in every tool, not only in our LSP. The `pub import` split and the emptied-list rule are exactly the details a tooling note would lose.
> 3. **Concern:** The emptied-list rule (rewrite to `import alpha` unless nothing in the file uses the `alpha.` qualifier) needs a file-wide qualifier scan. A tool that skips the scan deletes a line that is still needed.
>
> ## Q5 — Extra spec text
> - **5a:** yes
> - **5b:** yes
> - **5c:** yes
> - **5d:** yes
>
> 2. **Reasoning:** Each item is one sentence or one example, and each removes a case a model learning from the spec would otherwise guess at. 5a gives the general rule. 5b stops 07:1557 from being read as a counterexample. 5c resolves the W1010 overlap for `blink.core` imports. 5d shows that the help line's own `as` fix is legal.
> 3. **Concern:** 5c rewords W1010, which a 6-0 decision produced. That wording change must keep W1010 firing for plain declarations like `type Handler` that have no matching import.

##### Minimalism

> # Phase C ballot — min ([this spec ticket])
>
> ## Q1 — Rule
> 1. **Vote:** E
> 2. **Reasoning:** This adds no new rule. It removes an exemption, the local-names early return. Module scope is flat, and E1005, E1012 and DuplicateModuleBinding already reject the other pairs of written bindings. With E, "one bare name, one binding per module" holds with no exceptions. Because the check uses the bound name, kind does not matter, so no list of special cases is needed.
> 3. **Concern:** Code that hits the error has a dead import, but someone may have copied that pattern into lib/std or src. The sweep must find it before the change lands, or the bootstrap breaks.
>
> ## Q2 — Code
> 1. **Vote:** b
> 2. **Reasoning:** Zero new codes. The number of codes in the family goes down by one special case, because the `pub` form becomes one instance of the general rule. E1012 already has the two-span shape, so only its title and text change.
> 3. **Concern:** If [the module-scope collision code-drift ticket] later renumbers the module-scope codes, E1012 must move with the family, and not be split back into separate `pub` and plain codes.
>
> ## Q3 — Rollout
> 1. **Vote:** now
> 2. **Reasoning:** A staged rollout makes us spec a temporary warning and its retirement, which is surface that exists only to be deleted. Blink is pre-1.0, and the fix keeps behaviour the same. One break is cheaper than two.
> 3. **Concern:** none beyond the Q1 concern about the sweep.
>
> ## Q4 — Auto-fix
> 1. **Vote:** tooling
> 2. **Reasoning:** Whether a fix is machine-applicable describes the tools, not the meaning of the language. The language rule is only "this is an error". The behaviour itself is correct, and I agree with all of it: the plain-vs-`pub` split, and sys's emptied-list rule. It belongs in the diagnostic catalogue or LSP notes, not in the normative spec sections.
> 3. **Concern:** If spec wins, the spec starts to record fix applicability per diagnostic, and every later diagnostic is then expected to state one too. If tooling wins, sys's emptied-list rule must still be written down somewhere, or a tool will delete a line that the `alpha.` qualifier needs.
>
> ## Q5 — Extra spec text
> - **5a: yes.** One sentence that stops every later ticket from treating W1000 and W1010 as analogues. It costs less to state than to deliberate again.
> - **5b: no.** 5a already covers it: a module qualifier is a lower layer, as devops said in round 1. A second sentence about a rule we did not change adds text and adds nothing new.
> - **5c: yes.** Without the reword, W1010's text ("module-level definitions reached by an explicit import") contradicts the new rule for `import blink.core.{Handler}` plus `type Handler`. A contradiction in the spec is a latent bug, and fixing it here makes the spec shorter in total, not longer.
> - **5d: yes.** Two example lines. Without them, readers may think the help line's own fix (`as AlphaPoint` plus `type Point`) triggers the error. Examples are cheaper than a follow-up ticket.
> - **Concern:** The four items together may grow §10.6 past one paragraph. Keep 5a, 5c and 5d to one sentence or one example each.

#### Phase D — Round 2 (Q4 only)

Web/Scripting and Minimalism moved to "spec". Q4: spec 6-0. Each reply below is verbatim.

##### Systems

> # Phase D: sys (Q4 only)
>
> The moderator's fact settles min's main concern. The normative spec already states fix applicability for single diagnostics: §8.6 defines `fix.edits` as edits an agent applies verbatim, 02:830 names the one machine-applicable code of five, 07:91/:524/:702 and 03b:635 mark repairs that are NOT machine-applicable, and W1401 states its fix. So "spec" does not set a new precedent. "Tooling" would make E1012 the exception.
>
> Web and min both agree with the behaviour. They only ask where it goes. Under §8.6, `blink` itself emits `fix.edits` in its JSON diagnostics. So the fix is compiler output, not editor behaviour, and the spec already covers compiler output. An agent that applies `fix.edits` verbatim depends on those edits being correct. That is a contract, and a contract belongs in the spec.
>
> I accept devops's refinement. The "nothing uses `alpha.`" check runs on resolved names, not on text, because a local `alpha` binding (07:1557) would fool a text scan. The compiler already resolves these names, so the check costs nothing.
>
> Proposed text, one paragraph under the E1012 rule: "For a plain `import`, the fix that drops the name from the import list is machine-applicable. If the list becomes empty, the fix rewrites the line to `import alpha`, and deletes the line only when no resolved name in the file uses the `alpha` qualifier. For `pub import`, the fix is a suggestion, not machine-applicable. E1012 replaces W0602 on that import entry."
>
> 1. **Vote:** spec
> 2. **Reasoning:** The spec already records fix applicability per diagnostic (§8.6, 02:830, 07:91 and others), and `fix.edits` is compiler output that agents apply verbatim. The emptied-list rule decides whether that output is correct, so it is a contract, not editor polish. One paragraph is enough.
> 3. **Concern:** An implementer may emit the line-delete edit without the resolved-qualifier check, so the corpus needs a test with `import alpha.{Point}`, `type Point` and `alpha.helper()` in one file.

##### Web/Scripting

> # Web — Phase D (Q4 only)
>
> I change my vote to **spec**.
>
> My Phase C reasoning was "the spec says what the language does, and quick-fix levels are tool behaviour." The moderator's fact shows that this is not how Blink's spec works. §8.6 makes machine-applicable fixes part of every structured diagnostic. 02:830, 07:91/524/702, 03b:635 and W1401 each state fix applicability for a named code. In Blink, fix applicability is already normative spec text. A tooling note here would be the exception, and so it would be the place a reader looks last.
>
> My Phase C concern was that an LSP could ship the unsafe "delete the line" form. Spec text guards against that better than a note does. Devops's resolved-name point (a local `alpha` from 07:1557 can fool a text scan) is the kind of detail that is lost when it is not normative.
>
> Min's concern is fair: every later diagnostic could be expected to state a fix level. But the precedent already exists, so this ticket does not create it. Keep the text to one short paragraph, placed next to the E1012 entry:
> - For a plain import, "drop the name" is machine-applicable.
> - For `pub import`, it is a suggestion only.
> - When the list becomes empty, rewrite it to `import alpha`, unless no resolved `alpha.` use remains in the file. Only then delete the line.
> - E1012 replaces W0602 on that import entry.
>
> **Vote:** spec
> **Reasoning:** The spec already states fix applicability for named diagnostics (§8.6, 02:830, W1401), so this follows the existing pattern. The emptied-list rule decides whether the fix is correct, and every tool must agree on it. Spec text is where an agent or LSP author will look.
> **Concern:** The paragraph must specify the qualifier check by resolved names, not text, or a tool will implement the unsafe shortcut.

##### PLT

> # PLT, Phase D (Q4 only)
>
> The moderator's fact answers min's concern about precedent. The normative spec already records fix applicability for single diagnostics: 02:830, 07:91/524/702, 03b:635, 06:1434, and the §8.6 `fix.edits` contract. Stating it for E1012 follows existing practice. It does not start a new duty for every later diagnostic.
>
> On web's point that the spec says what the language does: §8.6 makes the `fix.edits` array part of the diagnostic contract. Under that contract, a fix marked machine-applicable promises that applying it keeps the program's meaning. That promise depends on two semantic facts. The first is the binding rule: in a plain import every bare use already resolves to the local declaration. The second is 07:1555: a selective import also gives the `alpha.` qualifier. A tool cannot keep the promise without those facts, so they belong in the spec, next to the rule they rely on.
>
> Devops's refinement should go into the spec text. The "nothing uses `alpha.`" check works on resolved names, not text. A local binding named `alpha` (07:1557) is not a use of the module qualifier.
>
> Sys's point should also go in: on that import entry, E1012 replaces W0602. One mistake gives one diagnostic.
>
> The text needs only one short paragraph under E1012. That fits min's minimalism goal.
>
> 1. **Vote:** spec
> 2. **Reasoning:** In §8.6, "machine-applicable" means the fix keeps the program's meaning. That is a semantic claim, and here it depends on the binding rule and on 07:1555. The spec already states fix applicability per diagnostic in at least six places, so this follows existing practice. A tooling note cannot bind third-party tools or `blink fix` to the qualifier-aware rule.
> 3. **Concern:** The paragraph could grow into a list of edit steps. It should state only the cases: plain import is machine-applicable, `pub import` is a suggestion, and an emptied list becomes `import alpha` unless no resolved `alpha.` use remains. The edit mechanics stay with tools.

##### DevOps

> # Phase D — devops (Q4 only)
>
> The moderator's fact answers min's concern. The spec already states fix applicability for single diagnostics: 02:830, 07:91/:524/:702, 03b:635, 06:1434, and §8.6 makes `fix.edits` normative. So "spec" adds no new kind of spec text. It follows a pattern the spec already has, and it does not oblige later diagnostics to say anything they do not already say.
>
> Web's own concern also argues for "spec". A "binding tooling note" has no home that third-party tools must read. §8.6 is that home: an agent applies `fix.edits` verbatim, so any edit marked as machine-applicable must be correct by the language's own rules. Sys's emptied-list rule depends on 07:1555 (a selective import also gives the `alpha.` qualifier). That is a language fact, so the fix's safety is a language fact too.
>
> To keep it small, I accept min's limit on the form: two sentences in the E1012 text, not a new subsection.
> - "Dropping the entry from a plain `import` is machine-applicable. For `pub import` it is a suggestion only."
> - "An emptied list becomes `import alpha`, unless no name in the file resolves through the `alpha` qualifier, in which case the line is removed."
>
> I also add sys's point: on that import entry, E1012 replaces W0602.
>
> ## Re-vote
> 1. **Vote:** spec
> 2. **Reasoning:** §8.6 already makes machine-applicable edits normative, and several sections state per-code applicability, so this follows an existing pattern. The safety of the fix depends on 07:1555 qualifier semantics, and only the spec owns those. Third-party tools and agents read the spec, not our LSP notes.
> 3. **Concern:** The emptied-list check must be stated in terms of resolution ("resolves through the qualifier"), not text matching. Otherwise a local binding named `alpha` (07:1557) makes tools disagree.

##### AI/ML

> # Phase D — aiml (Q4 only)
>
> The moderator's fact settles min's main concern. The normative spec already states fix applicability, per diagnostic, in at least six places (02:830, 06:1434, 07:91/524/702, 03b:635). §8.6 also makes `fix.edits` part of the diagnostic contract that agents apply verbatim. So "spec" adds one more entry to a pattern that already exists. It does not start a new pattern. If this fix went into a tooling note, it would be the exception, and a model learning from the spec would find nothing about it.
>
> Web's and min's concern is valid: the rule must not get lost. But the risk they name, a tool that deletes the line without the qualifier check, is exactly what a spec rule prevents and a tooling note does not. Third-party tools and agent harnesses read the spec, not our LSP notes.
>
> I adopt two additions from round C:
> - devops: the "nothing uses `alpha.`" check uses resolved names, not text, because of 07:1557.
> - sys: E1012 replaces W0602 on that import entry, so one mistake gives one diagnostic.
>
> Both fit in the same short paragraph.
>
> ## Re-vote
> 1. **Vote:** spec
> 2. **Reasoning:** §8.6 makes machine-applicable fixes part of what an agent sees from a diagnostic, and the spec already records applicability per code in six places. Whether this fix keeps meaning the same depends on the plain-vs-`pub` split and on qualified access (07:1555), which are language rules, not editor details. Every tool must agree, or an agent loop applies a fix that breaks `alpha.helper()`.
> 3. **Concern:** The paragraph could grow into a full edit algorithm. Keep it to three facts: the plain import is machine-applicable, `pub import` gets a suggestion only, and the emptied-list rule uses resolved qualifier uses.

##### Minimalism

> # Phase D — min (Q4 only)
>
> My Phase C vote rested on one claim: putting this in the spec would set a new precedent, so every later diagnostic would be expected to state its fix level. The moderator's fact shows that this is false. The spec already makes that statement per diagnostic. §8.6 makes `fix.edits` part of the structured diagnostic contract, and at least six other places say whether a fix is machine-applicable: 02:830, 07:91/524/702, 03b:635 and 06:1434. So the spec text adds no new kind of text. It follows a pattern that exists, which is the outcome a minimalist wants.
>
> The correctness argument from sys, plt and devops also stands. Because of 07:1555, deleting an emptied import can break `alpha.` uses. A rule that every tool must get right belongs where every tool reads it, not in notes for one tool.
>
> I change my vote to spec, with two limits:
> - Keep it to one short paragraph next to E1012, in the same style as 02:830. Do not add a new section.
> - Add sys's point: on that import entry, E1012 takes the place of W0602, so one mistake gives one diagnostic. Also add devops's point: the "nothing uses `alpha.`" check works on resolved names, not on text.
>
> ## Vote
> 1. **Vote:** spec
> 2. **Reasoning:** The spec already records whether a fix is machine-applicable for specific diagnostics (§8.6, 02:830, 07:91 and others). So stating it here follows the existing pattern and adds no new kind of surface. The emptied-list rule decides whether the fix is correct, and every tool must use the same rule. That is a spec matter.
> 3. **Concern:** The paragraph may grow into a general guide for fixes. Keep it to the plain-vs-`pub` split, the emptied-list rule (checked on resolved names) and the W0602 rule.

#### AI-first review

5/5 pass. Learnability: one flat-scope rule with no exception. Consistency: reuses E1012, and the
`pub import` case becomes one instance of the general rule. Generability: fewer legal forms.
Debuggability: one diagnostic with a machine-applicable fix. Token efficiency: unchanged.

---

### Final Spec

```blink
import alpha.{Point}
type Point { b: Int }                // error[E1012]: `Point` is both imported and declared

import beta.{Shape as S}
type S { r: Int }                    // error[E1012]: the check uses the name after `as`

import gamma.{Line as GammaLine}
type Line { len: Int }               // OK: the import binds `GammaLine`
```

- A module-level declaration of a name that a selective import binds is `DuplicateSymbol` (E1012),
  for every declaration kind in both namespaces, for `import` and `pub import`, at any visibility.
- E1012's title and table row drop "public" and "re-export"; the `pub import` + `pub` declaration
  case is one instance of the rule.
- The error lands at once, with src/ and lib/std/ fixed in the same change.
- Fix: dropping the name from a plain `import` is machine-applicable; for `pub import` it is a
  suggestion only. An emptied list becomes `import alpha`, and the line goes only when no name in the
  file resolves through the `alpha` qualifier (name resolution, not text search). On that import
  entry, E1012 replaces W0602.
- §10.6: shadowing happens only between nested scopes; two module-scope bindings are a duplicate.
  `import blink.core.{Handler}` + `type Handler` is E1012, not W1010; a plain `type Handler` still
  gets W1010. The §10.1 rule that a local definition hides a module qualifier is a different layer
  and does not change.
- Spec: §10.5 *Re-exports*, *Imported and Declared Names*, *Import Errors*; §10.6 *Shadowing
  Rules*; ERROR_CATALOG.md E1012.
- Not decided here: two selective imports that bind one alias (its own ticket; the same principle
  applies, under E1005). If the E10xx family is renumbered, E1012 moves with it.
