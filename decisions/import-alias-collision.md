[< All Decisions](../DECISIONS.md)

# Import Alias Collision — Design Rationale

Two selective imports could bind one name to different items:

```blink
import auth.{Error as E}
import db.{Error as E}
```

The spec did not say what happens. The compiler stored aliases in one global map
(`tc_alias_to_original` in src/typecheck.bl), so the second import silently replaced the first and
the last import won. The map is global, although the spec says aliases are local to each file. The
E1005 text was also stale: §10.1 called `import foo` + `import bar` (both export `helper`) an error at
the bare use `helper()`, but a whole-module import binds no bare name. The example diagnostic pointed
at line 4:1, which is neither import line.

## Summary

| Q | Question | Result | Vote |
|---|---|---|---|
| C1–C6 | Shared points: two imports that bind one name to different items are an error, keyed on the bound name, both namespaces, `import` and `pub import`; checked at the import site whether or not the name is used; fix is a suggestion only; alias vs declaration stays E1012; fix the §10.1, §5 and catalog text; bindings are per file | Yes | 6-0 |
| Q1 | Code | E1005 for import vs import; E1012 stays for import vs declaration | 6-0 |
| Q2 | Same item, same name, twice | W0602 on the later entry with a machine-applicable delete; identity is the resolved item after `pub import` chains; no new code | 6-0 |
| Q3.1 | `import http` + `import http2 as http` | E1005 | 6-0 |
| Q3.2 | `import db` + `import auth.{Token as db}` | E1005: bare names and qualifiers share one binding table | 6-0 |
| V1 | E1005 replaces W0602 on the colliding entry | Yes | 6-0 |
| V2 | Declaration also takes the name: E1012 first, E1005 only between entries without E1012 | Yes | 6-0 |
| V3 | Help names | Non-normative "should": a concrete name not already bound in the file; no naming scheme in the spec | 6-0 |
| V4 | `import a.{X, X as Y}` | Legal | 6-0 |
| V5 | Alias that is a compiler-known name | Stays under W1010 | 6-0 |
| V6 | Spec says each file has its own binding table | Yes | 6-0 |
| V7 | One sentence under *Import Aliases* | Yes | 6-0 |

AI-First review: 5/5 pass (one rule, mirrors E1012, no new syntax, located errors with concrete help,
nothing to type).

**Known gap (temporary).** Under Q3.2 an import of a name that is also a module qualifier is E1005,
but a *declaration* of a qualifier name (`import db` + `type db`, `fn db`, module `let db`) stays
legal under the earlier E1012 decision. Minimalism's Q3.2 vote was conditional on this record naming
a follow-up `type:spec` ticket for that pair; Systems, PLT, DevOps and AI/ML asked for the same
ticket. It is filed.

**Tooling note (agreed in Phase B, not voted).** `blink fmt` does not remove duplicate imports,
because the check needs name resolution. The W0602 delete belongs to `blink fix` and the LSP.

**A note on quotation.** Panelist text below is verbatim: each panelist wrote each submission to a
file, and the texts are those files. The only change is `br` ticket identifiers: `br` is local-only,
so each is replaced by a bracketed description of the ticket. Minimalism's Phase A file differs from
the message it first sent in one column number (2:23 became 2:21), a correction Minimalism made to
its own count.

---

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated in
independent-proposal → debate → vote rounds. All six Phase A proposals shared points C1–C6. The
mechanical dedupe left three open questions (code, same-item repeats, module qualifiers) and seven
smaller variations. Phase B ran two rounds, after which all six signalled "stable, ready to vote".
In Phase B, PLT, AI/ML and Systems withdrew an argument that adding a re-export could break a
downstream build (Minimalism showed such an import was already E1003), and Minimalism moved to Q2-B
and Q3.2-A. Phase C was a silent vote; every question passed 6-0, so Phase D did not run.

#### Phase A — Independent proposals

##### Systems

> # Systems panelist, Phase A: colliding import aliases
>
> **Position.** Module scope is one flat hash map, and §10.6 already says two bindings in it are a duplicate. An import is an insert into that map. A colliding insert is an error at the insert, which is the import line. No lazy state and no use-site work.
>
> ## Proposal S1: E1005 means "two imports bind one name", reported at the import site
>
> **Rule.** Two imports in one file that bind the same bare name to *different items* are `AmbiguousImport` (E1005). The check uses the name the import binds: the name after `as` if there is one, otherwise the item name. It fires whether or not the name is used.
>
> ```blink
> import auth.{Error as E}
> import db.{Error as E}      // error[E1005]
>
> import auth.{Error}
> import db.{Error}           // error[E1005], same rule with no rename
> ```
>
> ```
> error[E1005]: `E` is imported twice, from `auth` and `db`
>  --> src/main.bl:2:22
>   |
> 1 | import auth.{Error as E}
>   |                       ^ first bound here (auth.Error)
> 2 | import db.{Error as E}
>   |                     ^ bound again here (db.Error)
>   |
>   = help: rename one: import db.{Error as DbError}
>           or drop it and use `db.Error`
> ```
>
> There is no machine-applicable fix, because the compiler cannot choose the new name. Both fixes are suggestions.
>
> **Code split.** E1005 covers import against import. E1012 covers import against declaration, as decided today. That gives two codes for two causes, and the help text differs: for E1012 you can drop the import, for E1005 you have to choose a name. Rust splits the same way: E0252 for two `use` items, E0255 for a `use` against a local item. Both are errors at the `use` site, even when the name is never used. Go also reports "X redeclared in this block" at the import.
>
> **Why the import site and not the use site.**
> - **Cost and determinism.** An import-site check is one hash lookup per binding. A use-site check, Haskell-style, means the symbol table has to hold a set of bindings per name and check it on every lookup. That is more state, and the diagnostic then depends on which uses exist.
> - **No hidden failures.** With a use-site check, a file builds today and breaks when someone adds a use 400 lines away, and the error points at that innocent line. The cause is at the import, so the error should be there too.
> - **Matches the existing collision rule.** E1012 fires at the declaration, used or not. If import collisions were checked differently, there would be two collision rules where one will do.
>
> ## Proposal S2: identity decides, not spelling (needed for the facade pattern)
>
> `pub import` re-exports already exist (`codegen_common` re-exports `codegen_types.emit_line`). So two paths can reach **one** item:
>
> ```blink
> import codegen_types.{emit_line}
> import codegen_common.{emit_line}   // same item through a re-export
> ```
>
> This is not ambiguous, because the program means one thing either way. Rule: if both bindings resolve to the same item (the same declaration, after following `pub import` chains), it is not E1005. The second entry is redundant, so it gets the existing `UnusedImport` (W0602), with a machine-applicable fix that deletes the entry. The same applies to a literal repeat, `import auth.{Error}` written twice. This adds no new code. The cost is one comparison of declaration IDs, which name resolution already has.
>
> ## Proposal S3: the same rule for module-qualifier names
>
> ```blink
> import http
> import http2 as http        // error[E1005]: qualifier `http` bound twice
> ```
>
> `blink explain E1005` already says this. The spec text must say it too. Qualifiers are a separate layer (§10.1: a local `let auth` hides a qualifier), so a qualifier never collides with a bare selective binding. The collision rule applies only within each layer.
>
> ## Spec edits this forces
>
> 1. **Import Errors table, E1005:** "Two imports in one file bind one name (after `as`) to different items, in the bare-name layer or the qualifier layer."
> 2. **E1005 example:** the location `src/main.bl:4:1` points at neither import. Move it to the second binding token and add a secondary label on the first.
> 3. **§10.1 *Qualified Access*:** the line "if `import foo` and `import bar` both export `helper`, bare `helper()` is E1005" contradicts "Selective imports restrict unqualified only". A whole-module import binds no bare `helper`, so bare `helper()` is plain name-not-found. Rewrite it to: "two selective imports of `helper` are E1005; use `foo.helper()` or rename."
> 4. **§5 line 545** and **ERROR_CATALOG.md:** reword to match edit 1.
> 5. **Import Aliases:** add "Two aliases of one name in one file are E1005 (§10.5 *Import Errors*)."
>
> **Implementation note (not spec):** `tc_alias_to_original` is one global map, but the spec says aliases are local to the file. Today `import a.{X as Y}` in file 1 can leak into file 2, or be overwritten by it. That is a correctness bug separate from this ticket. Key the map by (file, alias), and put the E1005 check on that insert.
>
> ## Tradeoffs
>
> - **Against S1:** it is stricter than a use-site check, because an unused colliding import fails the build. I accept that. Collision is a static property of the import block, and the panel's own rule says an AI reading the import block must be able to know every name. A block that binds `E` twice fails that test.
> - **Against S2:** the error depends on resolving re-exports, so it is not purely textual. That is acceptable, because name resolution already resolves `pub import` chains, so this adds no new pass.
>
> **Vote preference:** S1 + S2 + S3 together. If S2 loses, the fallback is E1005 for any repeat, the Rust choice. Simpler, but it penalizes facade modules for no gain.

##### Web/Scripting

> # Web/Scripting proposal for [this spec ticket]: two selective imports binding one alias
>
> ## Proposal W1: one name has one binding per file, checked at the import line
>
> **Rule.** Two imports in one file that bind the same bare name are an error, `AmbiguousImport` (E1005). The check runs at the second import line, whether or not the code ever uses the name. It treats an `as` rename and a plain name the same way, because the check uses the name that is bound (the name after `as`), as E1012 already does. `import` and `pub import` both count.
>
> ```blink
> import auth.{Error as E}
> import db.{Error as E}       // error[E1005]
>
> fn main() ! IO {
>     io.println("hi")         // E is never used: still an error
> }
> ```
>
> ```
> error[E1005]: `E` is imported twice
>  --> src/main.bl:2:21
>   |
> 1 | import auth.{Error as E}
>   |                       ^ `E` is `auth.Error` here
> 2 | import db.{Error as E}
>   |                     ^ and `db.Error` here
>   |
>   = help: give each its own name:
>           import auth.{Error as AuthError}
>           import db.{Error as DbError}
> ```
>
> The fix is a suggestion only, not machine-applicable. Picking a name is a human decision.
>
> **Why E1005 and not E1012.** This gives a split a JS or Python developer learns in 5 minutes:
> - Two imports with one name: E1005.
> - An import and a declaration with one name: E1012.
>
> Both follow the flat-module-scope principle from the merged decision. The existing E1005 help text ("or rename: `import auth.{Error as AuthError}`") and the `blink explain E1005` example (`import http` / `import http2 as http // E1005`) already read this way. A new code would add a third concept to search for with nothing new to learn.
>
> **Why check at the import line, not the use site.** Python is the warning here. `from auth import Error` followed by `from db import Error` silently rebinds the name, and the bug shows up three files away as an `isinstance` that fails. That is a Stack Overflow classic. Today's compiler, where the last import wins, is the Python bug exactly. Other languages fail at the import:
> - **JS/TS:** a duplicate import binding is an early `SyntaxError` ("Identifier 'E' has already been declared").
> - **Rust:** E0252, "defined multiple times", at the `use`.
> - **Kotlin:** "Conflicting import".
>
> Of the common languages, only Haskell waits until a use. Checking at the import line also helps AI-written code: the error points at the line the model just wrote, not at a use far away.
>
> **Also fix the existing example.** The plain `{Error}` + `{Error}` example in Import Errors reports `src/main.bl:4:1`, which is neither import line. Change it to point at the second binding and label both spans, as above. One rule gives one diagnostic shape.
>
> ## Sub-cases the spec must settle
>
> **S1. The same item imported twice under one name** (`import auth.{Error}` twice, or `{Error as E}` twice). It is not ambiguous, because there is one entity. This happens often after merge conflicts and IDE auto-imports. Recommendation: a warning, not an error. Reuse the redundant/unused-import warning (W0602 family) and make "delete the second entry" a machine-applicable fix. Making this a hard error would punish a harmless mistake. Tradeoff: one more case in the rule. Minimalism may prefer "always E1005", and I would accept that if the fix stays machine-applicable.
>
> **S2. One item under two names** (`import auth.{Error as E, Error as AuthError}`). Allow it with no diagnostic. It binds two names to one entity, and no name is bound twice.
>
> **S3. A module qualifier and a selective name collide**:
>
> ```blink
> import errors as E
> import auth.{Error as E}     // E1005: `E.x` would be ambiguous
> ```
>
> Same rule, same code. A whole-module import binds its qualifier (leaf or alias), so it joins the one-binding-per-name check. The explain text's `http`/`http2` example is this case, so the spec should say it outright.
>
> **S4. The §10.1 sentence "bare `helper()` is an error (E1005)" for `import foo` + `import bar`.** Under "selective restricts unqualified only", whole-module imports bind no bare `helper`, so bare `helper()` is just an unresolved name. Recommendation: reword that sentence so E1005 has one meaning, "an import-site collision". Otherwise users get E1005 in two unrelated situations, which means two Stack Overflow questions.
>
> **S5. Scope is per file.** The spec says aliases are local to the importing file. The ticket shows `tc_alias_to_original` is one global map. The rule must say the collision check, and alias lookup, are per file. Two files may each bind `E` to different items. This is an implementation note for the fix ticket, not a vote.
>
> ## Tradeoffs (DX view)
>
> - **For:** the error lands on the line just written, silent overwrite never happens, the help text matches what a developer would do anyway, and every module-scope collision follows one principle.
> - **Against:** an unused colliding import is an error, not a lint. I accept that: an unused duplicate is dead code plus a trap, and E1012 already takes the same eager position.
> - **Rejected: check at the use site (Haskell-style).** It defers the error to the reader's code, and E1012 already chose eager. Mixing eager and deferred checks for module-scope names would itself be a Stack Overflow question.
>
> ## Votes I would cast
>
> | Question | Vote |
> |---|---|
> | Code | E1005 for import vs import (alias or not), E1012 for import vs declaration |
> | Where | At the import site, eager |
> | Alias vs local declaration | Already E1012 by the merged decision |
> | S1 | Warning with machine-applicable delete |
> | S2 | Allow |
> | S3 | E1005 |
> | S4 | Reword §10.1 |

##### PLT

> # PLT Phase A — Colliding import aliases
>
> ## Core principle (P1): a selective import is a binding; collisions are checked eagerly at the import site
>
> Module scope is one flat environment ([the flat module-scope decision], §10.6). A selective import binds `name-after-as` (or the item name) to an *entity*. Two imports that bind one name to **different entities** violate the same rule E1012 enforces for import-vs-declaration. So the check is **eager, at the import site, regardless of use**.
>
> ```blink
> import auth.{Error as E}
> import db.{Error as E}     // error[E1005]
> ```
>
> ```
> error[E1005]: `E` is imported twice in module `main`
>  --> src/main.bl:2:20
>   |
> 1 | import auth.{Error as E}
>   |                       ^ binds `auth.Error` here
> 2 | import db.{Error as E}
>   |                     ^ also binds `db.Error` here
>   |
>   = help: rename one: import db.{Error as DbError}
> ```
>
> Reported at the later import in source order, both spans labelled (E1012 house style). A location is required; the current example's `--> src/main.bl:4:1` (a use site) is retired, and the compiler's `diag_error_no_loc` is a bug against this text. On that import entry E1005 replaces W0602 (unused import), parity with E1012.
>
> Why eager, not Haskell-style lazy: Haskell reports ambiguity at use because `import M` brings names implicitly, so incidental clashes are normal. Blink has no wildcard imports; every bare name is an explicit binding the author wrote. There is nothing left to resolve lazily, and a lazy check would let a latent ill-formed environment compile until someone touches the name. Rust takes the eager position for the same reason (`use a::E; use b::E as E;` is E0252 at the `use`).
>
> ## Code (P2): keep E1005 for import-vs-import; redefine its cause
>
> The discriminating property is machine-applicability of the fix (§8.6):
> - E1012 (decl vs import) has a canonical winner, the local declaration; "drop from import list" is machine-applicable.
> - E1005 (import vs import) has no canonical winner; the fix is suggestion-only (rename one, or use the qualified name).
>
> Different fix policy is a principled reason for a distinct code; merging them makes one code carry two fix semantics.
>
> New table row: `E1005 | Ambiguous import | Two imports bind one name in module scope to different items`.
>
> Two sentences describe a set-valued lookup that no longer exists and must change in the same edit:
> - §10.1 *Qualified Access*: "If `import foo` and `import bar` both export `helper`, bare `helper()` is an error" — under no-wildcards bare `helper` is not in scope at all (that is "not found", not "ambiguous"). Rewrite with selective imports or delete.
> - §5:545 and the ERROR_CATALOG row: reword to "two imports bind one name".
>
> ## Sub-cases the spec must settle (P3)
>
> **(a) Same entity, same name, twice.** The likely point of disagreement.
> ```blink
> import a.{X}
> import b.{X}      // b has: pub import a.{X}
> ```
> Binding identity is name→entity. Both denote one entity, so the environment has one binding and no ambiguity. Proposal: W0602 (redundant import), machine-applicable delete — not an error. Same for a literally repeated line. Compositionality argument: if this were an error, a library adding a re-export path in a minor release could break a downstream build that names nothing new. Rust errors here; Haskell and OCaml (for structurally equal items) do not. Blink should not make re-exporting a breaking change. §10.6's "duplicate" then means "one name, two entities"; say so in one clause.
>
> **(b) Two names, one entity:** `import a.{X, X as Y}` is fine.
>
> **(c) Cross-namespace:** `import a.{Error}` (type) + `import b.{Error}` (fn) is E1005. Collision is on the bound name, both namespaces, consistent with the E1012 decision. Namespace-splitting here would make the two rules disagree.
>
> **(d) `pub import`:** same rule. Otherwise the module's export table holds two entries for one name and every consumer inherits an ill-formed interface; must be an error at the producer.
>
> **(e) Module qualifiers:** `import http` + `import http2 as http` binds the qualifier `http` twice; same principle, E1005 (matches existing `blink explain E1005` text, which today lacks spec backing).
> ```
> error[E1005]: module qualifier `http` is bound twice
> ```
> Qualifier-vs-selective-name (`import auth` + `import x.{y as auth}`) is a different layer (§10.6 routes value-vs-qualifier through the `let auth = 5` rule). Propose deferring to a friction ticket rather than settling it implicitly here.
>
> **(f) Alias vs local declaration:** already settled (E1012, name after `as`). No change.
>
> **(g) File scope:** "Aliases are local to the importing file" is existing text; the global `tc_alias_to_original` map is a compiler bug, not a spec question. Fix alongside.
>
> ## Tradeoffs
>
> Cost: eager rejection forbids an unused colliding import that Haskell would accept; with explicit-only imports that program is always a mistake, so the cost is near zero. Gain: one principle (flat scope, a name maps to at most one entity) now covers declarations, selective imports, aliases, re-exports and qualifiers, with no set-valued environment — the source of Haskell's hard-to-reason-about import ambiguity rules.
>
> Vote preference: P1+P2+P3 together. Fallback: P1 with widened E1012, only if the panel accepts one code with two fix policies.

##### DevOps/Tooling

> **DEVOPS/TOOLING — Phase A proposal ([this spec ticket])**
>
> **Position.** The error is E1005, it fires at the import site whether or not the name is used, and every case carries a source location. E1012 stays the code for an import colliding with a declaration (already decided). Sub-question 3 is closed by that decision.
>
> **P1. Two imports that bind one name are E1005, at the import site.**
>
> ```blink
> import auth.{Error as E}
> import db.{Error as E}     // error[E1005]
>
> import auth.{Error}
> import db.{Error}          // error[E1005], the same rule without aliases
> ```
>
> ```
> error[E1005]: `E` is imported twice in this file
>  --> src/main.bl:2:22
>   |
> 1 | import auth.{Error as E}
>   |                       - first bound here, to `auth.Error`
> 2 | import db.{Error as E}
>   |                     ^ bound again here, to `db.Error`
>   |
>   = help: rename one of them: import db.{Error as DbError}
>           or drop it and use `db.Error`
> ```
>
> Why import site and not use site:
> - **LSP.** A use-site error appears only when someone types the first use. That can be months after the import that caused it, and on a line far away from it. At the import site, the squiggle and the code action sit on the line that caused the problem. rust-analyzer and rustc (E0252 "defined multiple times"), Go ("X redeclared in this block") and TypeScript ("Duplicate identifier") all report it eagerly. Python is the only one that lets the last import win, and that is the bug we have today.
> - **Consistency.** E1012 is already eager, and §10.6 says two module-scope bindings are a duplicate. A duplicate is a fact about the declarations, not about the uses.
> - **Location.** The current spec example puts E1005 at `4:1`, which is neither import line. The compiler emits it with no location at all. The spec must require a primary span on the second binding and a secondary span on the first. An LSP cannot attach a diagnostic that has no range.
>
> Why E1005 and not a wider E1012: the fixes are different, and a code should name one fix family. For E1012 the fix is "drop the import, the local declaration wins", and it is machine-applicable. For E1005 the fix is "pick a new name", which the compiler cannot choose, so it is a suggestion only. `blink explain E1005` already uses this meaning (`import http` / `import http2 as http`), so there is no churn there. Rename the row's Cause to: "Two imports in one file bind the same name (selective entry, alias, or module alias)". Change the §5 line and ERROR_CATALOG to match. Then E1005 is about bindings, not about "exists in multiple modules". Under §10.1, `import foo` + `import bar` binds no bare `helper`, so a bare `helper()` there is "not found", not "ambiguous". The §10.1 bullet that calls this E1005 needs a correction too.
>
> **P2. The same entity imported twice is not E1005. It is a warning with a machine-applicable fix.**
>
> ```blink
> import auth.{Error}
> import auth.errors.{Error}   // auth re-exports auth.errors.Error: same item
> ```
>
> There is nothing ambiguous here, so an error is wrong. Report it as `warning[W0602]`, or a new `DuplicateImport` code (the catalog owner picks). The fix "delete this entry" is machine-applicable, and it rewrites an emptied list to `import auth.errors` when names still go through that qualifier, the same rule as E1012. "Same entity" is decided by name resolution (the original definition after re-exports), not by text. **`blink fmt` does not dedupe.** fmt is syntactic and must not resolve names. Deduping is `blink fix`'s job.
>
> Also legal: one item under two aliases (`{Error as E1, Error as E2}`). Two names for one entity is not a collision.
>
> **P3. Module aliases and module qualifiers are in scope of E1005.**
>
> ```blink
> import db
> import auth.{Token as db}    // error[E1005]: `db` bound as module qualifier and as item
> import http
> import http2 as http         // error[E1005]
> ```
>
> The first case is the worst silent failure. §10.1 says a local binding hides a qualifier, so `db.connect()` quietly becomes a static call on `Token`. Making it eager at the import costs nothing and removes a class of "go to definition jumps to the wrong file" reports.
>
> **P4. `pub import` participates. Its fixes are suggestions only.**
>
> A `pub import` colliding with an `import`, or with another `pub import`, is E1005. A rename changes the public API, so no fix is machine-applicable. That matches the E1012 rule for `pub import`.
>
> **P5. Aliases are per file (normative restatement).**
>
> The spec already says so. The compiler's global `tc_alias_to_original` breaks it: file A's alias can overwrite file B's. That is an implementation bug, not a spec question, but the spec text should say "each file has its own binding table, and E1005 is checked per file". Then the test for it is plain.
>
> **One diagnostic per mistake.** On the second binding, E1005 replaces W0602 (unused import), the same as E1012 does. If a name collides both with a declaration and with another import, report E1012 for the declaration pair, and E1005 only between imports that remain after that. The cleanup order should be the same in CLI output and in the LSP.
>
> **Tradeoffs.** Eager checking rejects a file that has an unused colliding import, which some users will call strict. That is correct: an unused import is already W0602, and a binding that is wrong but unused is a trap waiting to go off. Splitting the work between E1005 and E1012 costs users one more code to learn, but each code maps to exactly one fix shape. That one-to-one mapping is what `blink fix`, the LSP code actions and AI agents need.

##### AI/ML

> ## AI/ML panelist, Phase A: two imports that bind one alias
>
> **My position.** Use one rule: "a bare name has one binding in module scope." The [the flat module-scope decision] decision and the E1012 decision already state this rule. Two import entries that bind one name to *different* items get E1005. The bound name is the name after `as`, the same rule E1012 uses. The compiler reports the error at the import site whether or not any code uses the name.
>
> ### Proposal 1 (preferred): E1005 at the import site, keyed on the bound name
>
> ```blink
> import auth.{Error as E}
> import db.{Error as E}      // error[E1005]
>
> fn f(e: E) { }
> ```
>
> ```
> error[E1005]: `E` is imported twice, as `auth.Error` and as `db.Error`
>  --> src/main.bl:2:24
>   |
> 1 | import auth.{Error as E}
>   |                       ^ first bound here to `auth.Error`
> 2 | import db.{Error as E}
>   |                     ^ bound again here to `db.Error`
>   |
>   = help: give each import its own name:
>           import auth.{Error as AuthError}
>           import db.{Error as DbError}
>           or drop one name and use `auth.Error` / `db.Error`
> ```
>
> The rule is the same with or without `as`. `import auth.{Error}` + `import db.{DbError as Error}` is E1005, and so is the existing `{Error}` + `{Error}` example.
>
> **Why E1005 and not E1012.** For the last decision, the panel kept E1005 out of import+declaration because its help ("qualify both") has no meaning for a local declaration. Here that help fits: both sides are imports, so both have a qualified form, and renaming with `as` is a valid fix. Each code then maps to one family of fixes:
> - E1005: import + import. Fix: qualify or re-alias.
> - E1012: import + declaration. Fix: drop the import or re-alias.
>
> When the code alone tells a model which fix to apply, the model gets it right on the first edit. If both pairs share one code, the model must also read which pair collided.
>
> **Why at the import site and not at the use.**
> 1. **The error is at the cause.** With a use-site-only error, the file compiles until someone writes `E`, perhaps 400 lines further down and edits later. A model then sees the error at a use, not at the imports that caused it, and the usual wrong fix is to edit the use.
> 2. **It matches E1012**, which fires at the declaration whether or not code uses the name. If one rule fires eagerly for one pair and lazily for the other, a model has to learn two behaviours.
> 3. **An import that cannot be used is dead code that looks live**, the same argument as last time.
> 4. **Other languages do the same.** Rust (E0252, "defined multiple times") and TypeScript (TS2300, "Duplicate identifier") report this at the import. Go reports "redeclared". Python silently lets the last import win, which is the behaviour the compiler has today and the bug this ticket reports.
>
> **Fix applicability.** A suggestion only, not machine-applicable. Choosing a new name is a judgment, and every use has to change with it. The help must still print *concrete, deterministic* names: module leaf in PascalCase + item for types (`AuthError`), and `leaf_item` for fns (`auth_parse`). A model copies the help line exactly, so the help must spell out the full edit.
>
> ### Sub-cases the spec must settle (my recommendations)
>
> **S1. The same item bound twice under one name** (`import auth.{Error}` twice, or `a.{X}` + `b.{X}` where `b` does `pub import a.{X}`). The name has one meaning, so nothing is ambiguous. Report the second entry as W0602 (redundant import), with a machine-applicable fix that deletes it. Do not use E1005. Re-export diamonds produce this case legitimately, and models often write duplicate imports when they merge edits. An error here costs a compile cycle and gains nothing. Identity means the resolved item, after `pub import` chains, not the spelling.
>
> **S2. Aliases are per file** (the spec already says so). Add a conformance test: two files, each with `import X.{Error as E}` from a different module, must both compile. The compiler today keeps one global `tc_alias_to_original`, which breaks this.
>
> **S3. A selective alias against a prelude name** (`import auth.{Error as Option}`). No change: W1010 already covers it ("a name that another module declares and this module imports").
>
> **S4. Whole-module qualifiers.** `blink explain E1005` already says `import http` + `import http2 as http` is E1005. The spec should say this too, under the same rule (two imports, one qualifier spelling). This is the qualifier layer, not module scope, so I would add this one sentence and nothing more.
>
> **S5. Stale text to fix in the same change:**
> - §10.1 says "if `import foo` and `import bar` both export `helper`, bare `helper()` is an error". A whole-module import binds no bare name (§10.5, "Selective imports restrict unqualified only"), so this sentence teaches a false model. Reword it to use selective imports.
> - The E1005 example points at `4:1`, which is not an import line. Point it at the second binding.
> - Table row: "Two import entries bind one bare name to different items." Update §5:545 and ERROR_CATALOG to match.
>
> ### Proposal 2 (fallback): widen E1012 to cover import + import as well
>
> This gives one code for every module-scope duplicate, and the help text changes by pair. It is less to learn, but the code no longer predicts the fix. I would accept it if the panel wants one code. In that case E1005 would keep only S4 (qualifier collisions), and the explain text would need a rewrite.
>
> ### What this costs and what it gains for models
>
> There is no new concept. The rule and the error code already exist. The change adds one sentence ("the bound name is the one after `as`") and one carve-out (S1). Every error names both bindings with spans and prints the edit in full, so a model can fix the error from the message alone.

##### Minimalism

> **Minimalism panelist: Phase A proposal ([this spec ticket])**
>
> ## Position: no new rule and no new code. The spec already contains the answer, and the change is about three sentences.
>
> The [the flat module-scope decision] principle and the E1012 decision made today give one rule: *module scope is flat, and two module-scope bindings of one name are a duplicate.* E1012 covers an import plus a declaration. E1005's own example, `import auth.{Error}` + `import db.{Error}`, is already two selective imports binding one name. A renamed import is the same case, because E1012 already established that **the binding is the name after `as`**. So `{Error as E}` twice is just `{E}` twice. Writing a separate "alias collision" rule would add surface for a case that has none of its own.
>
> ### Proposal M1 (recommended): E1005 is the import-vs-import duplicate, checked on the bound name, at the import site
>
> ```blink
> import auth.{Error as E}
> import db.{Error as E}      // error[E1005]
>
> import auth.{Error as E}
> import db.{Failure as E}    // error[E1005]: different original names, one binding
>
> import auth.{Error as AuthError}
> import db.{Error}           // OK: binds AuthError and Error
> ```
>
> ```
> error[E1005]: `E` is imported twice in module `main`
>  --> src/main.bl:2:21
>   |
> 1 | import auth.{Error as E}
>   |                       ^ first bound here (auth.Error)
> 2 | import db.{Error as E}
>   |                     ^ bound again here (db.Error)
>   |
>   = help: rename one: import db.{Error as DbError}
>           or drop it and use the qualifier: db.Error
> ```
>
> Spec edits:
> 1. Change the E1005 table row to "Two selective imports bind one name (the name after `as` when present)."
> 2. Point the example diagnostic at the second import line, not `4:1`. Today it reads like a use-site error, and that location is the real gap.
> 3. Add one sentence under *Import Aliases*: "An alias is the bound name. Two imports that bind one name are E1005, whatever names they rename."
>
> **Import site, not use site.** A use-site-only error lets a file with a latent duplicate compile until someone writes `E`. That is a shadow by the back door, and [the flat module-scope decision] ruled it out. It is also the Go rule (`fmt redeclared in this block`) and the Rust rule (E0252, `defined multiple times`), checked eagerly and with no special cases.
>
> **No same-entity exemption.** `import auth.{Error}` twice, or reaching `db.Error` through `auth`'s `pub import`, is still E1005. An "it is the same item, so allow it" carve-out needs identity resolution through re-exports and protects nobody. The fix is to delete a line. Rust errors here too. YAGNI.
>
> **Third sub-question.** E1012 (decided today) already covers an alias that collides with a local declaration. Nothing to add.
>
> ### Proposal M2 (alternative): fold E1005 into E1012
>
> Under the eager reading, the name "Ambiguous import" is wrong: nothing is ambiguous, it is a duplicate. The most minimal spec would have one code: "E1012 DuplicateSymbol: two module-scope bindings of one name (declaration or selective import)". E1005 would be retired.
>
> Cost: a published code changes meaning, and the catalog, §5:545, `blink explain` and tests all churn. I would not spend that churn unless the panel also wants E1005 for something else. I prefer M1 and keep M2 as a fallback if others want "one concept, one code".
>
> ### Sub-cases the spec must settle (and how M1 settles them)
>
> | Case | Ruling |
> |---|---|
> | `import http` + `import http2 as http` | E1005. Two bindings of one qualifier. `blink explain E1005` already says this, so the spec should say it too. |
> | `{Error as E}` + `{Failure as E}` | E1005 (shown above). |
> | `{X as E}` + `type E` | E1012 (already decided). |
> | `pub import` either side | Same rule. Visibility does not change the binding. |
> | The §10.1 sentence: "If `import foo` and `import bar` both export `helper`, bare `helper()` is an error (E1005)" | **Stale.** Under §10.1 itself, a whole-module import binds no bare name, so bare `helper()` is "not found", not ambiguous. Either strike the sentence or rewrite it as the selective case. Leaving it in teaches the wrong model, both to users and to the AI readers this spec trains. |
>
> **Fix applicability.** Unlike E1012, dropping one import is not machine-applicable, because the tool cannot know which binding the user meant. "Rename the second import" needs a name only a human can choose. So E1005's fix stays a suggestion only.
>
> ### Cross-language note
>
> Go and Rust both treat this as a plain duplicate, checked eagerly, under one rule. Python silently lets the last import win, which is exactly today's compiler bug. The C++ committee shows the cost of a separate lookup rule for each binding form. One flat-scope rule applied to the bound name is the whole design.
>
> **Not spec, but should be logged:** the compiler stores aliases in a global map (`tc_alias_to_original`), while the spec says aliases are per file. That is an implementation bug, separate from this decision.

#### Phase A.5 — Mechanical dedupe (moderator)

> # Phase A.5 — mechanical dedupe of the six Phase A proposals
>
> Full proposals: phaseA_{sys,web,plt,devops,aiml,min}.md in this directory. Read the others' files before replying.
>
> ## Points every proposal shares (all 6 proposed; listed so the vote can confirm them)
> - C1. Two imports in one file that bind one name to different items are an error, keyed on the bound name (the name after `as`, else the item name). Both namespaces (PLT stated explicitly; no one proposed otherwise). Applies to `import` and `pub import`.
> - C2. Checked eagerly at the import site, whether or not the name is used. Primary span on the later binding, secondary span on the first. The `4:1` location in the current example goes.
> - C3. Fix is a suggestion only (rename with `as`, or use the qualified name); not machine-applicable.
> - C4. Alias vs module-level declaration stays E1012 (already decided).
> - C5. The §10.1 Qualified Access sentence ("`import foo` + `import bar` ... bare `helper()` is an error (E1005)") is wrong and changes; §5:545 and the ERROR_CATALOG row reword to match.
> - C6. Aliases/bindings are per file (existing spec text); the global `tc_alias_to_original` map is an implementation bug for the impl ticket.
>
> ## Q1 — Which code
> - Q1-A: E1005 for import vs import; E1012 stays import vs declaration. (sys S1, web W1, plt P2, devops P1, aiml P1, min M1)
> - Q1-B: One code for every module-scope duplicate: widen E1012 to cover import vs import and retire E1005 for this use (min M2, fallback); or widen E1012 with E1005 kept only for qualifier collisions (aiml P2, fallback).
>
> ## Q2 — Same item bound twice under one name (literal repeat `import auth.{Error}` twice, or two paths to one item through `pub import`)
> - Q2-A: E1005, like any other repeat; no same-entity exemption. (min)
> - Q2-B: Not E1005. Warning W0602 on the redundant entry, machine-applicable delete; identity = resolved item after `pub import` chains. (sys S2, web S1, plt P3a, aiml S1)
> - Q2-C: As Q2-B, but the warning is W0602 or a new `DuplicateImport` code (catalog owner picks); `blink fmt` does not dedupe, `blink fix` does. (devops P2)
>   (web S1 said it would accept Q2-A if the fix stays machine-applicable.)
>
> ## Q3 — Module qualifiers
> - Q3.1 Qualifier vs qualifier (`import http` + `import http2 as http`): E1005. (sys S3, plt P3e, devops P3, aiml S4, min sub-case table; web S3 covers it under the same rule)
> - Q3.2 Qualifier vs selective bare binding (`import db` + `import auth.{Token as db}`, `import errors as E` + `import auth.{Error as E}`):
>   - Q3.2-A: E1005, one binding per name across both. (web S3, devops P3)
>   - Q3.2-B: Separate layers; never collide. (sys S3)
>   - Q3.2-C: Do not settle here; file a friction ticket. (plt P3e)
>   - (aiml S4 called qualifiers "the qualifier layer, not module scope" without addressing this pair; min did not address this pair.)
>
> ## Smaller variations (raised by one or two panelists; others silent)
> - V1. On the colliding entry, E1005 replaces W0602 (one diagnostic per mistake). (plt, devops)
> - V2. When a name collides with a declaration and with another import, report E1012 for the declaration pair and E1005 only among the remaining imports. (devops)
> - V3. Help prints concrete deterministic names: module leaf PascalCase + item for types (`AuthError`), `leaf_item` for fns. (aiml)
> - V4. One item under two names (`import a.{X, X as Y}`) is legal, no diagnostic. (web S2, plt P3b, devops P2)
> - V5. Selective alias that is a prelude/compiler-known name (`{Error as Option}`): W1010 already covers it, no change. (aiml S3)
> - V6. Spec states "each file has its own binding table; E1005 is checked per file". (devops P5, web S5)
> - V7. Add to Import Aliases: "Two aliases of one name in one file are E1005." (sys, min)

#### Phase B — Debate, round 1

##### Systems

> # Systems, Phase B round 1
>
> **C1–C6:** I confirm all six.
>
> ## Q1: Q1-A (E1005 for import against import, E1012 stays import against declaration)
>
> PLT and devops gave the deciding reason. One code should carry one fix policy. E1012 has a winner, the declaration, so its fix is machine-applicable. E1005 has no winner, so its fix is a suggestion only. If we merge them (Q1-B), `blink fix` and the LSP have to look inside the diagnostic to know whether they may apply the fix. Min's own M1 prefers Q1-A, and M2 also costs a published code changing meaning.
>
> ## Q2: Q2-B (W0602 with a machine-applicable delete; identity after `pub import` chains)
>
> To min: "identity resolution protects nobody and costs work". The cost is zero. To type the binding, name resolution must already resolve every import entry to its declaration, so the check is an integer compare of two declaration IDs that already exist. Nothing new is computed.
>
> What it protects is the facade migration we use in this repo. A module moves `Error` into `auth.errors` and re-exports it from `auth`. During the move, a file can import both paths. That program has one meaning, and an error there is noise that blocks a mechanical refactor. W0602 still flags the redundant entry, and `blink fix` deletes it.
>
> I oppose Q2-C's new `DuplicateImport` code. A redundant entry is an unused entry: the first one binds the name, so the second does nothing. W0602 already means that, and a new code adds a catalog row for no new behavior. I agree with devops that `blink fmt` must not dedupe, because fmt does not resolve names. That point can go in the decision record without a vote.
>
> ## Q3.1: E1005. All six agree.
>
> ## Q3.2: I change my position from B to A (E1005), for import-against-import pairs only
>
> Devops convinced me with `import db` + `import auth.{Token as db}`. Under §10.1, a local binding hides a qualifier. So `db.connect()` silently becomes `Token.connect()`, a static call on a different type, with no diagnostic. That is the same silent rebinding this ticket exists to remove, so "separate layers" protects the wrong thing.
>
> The implementation cost also favors A. One per-file table keyed by bound name, holding both qualifiers and bare names, is one lookup per import entry. With two layers you need two tables plus a rule for which one wins at each use.
>
> Scope limit: Q3.2-A covers **import against import** only. A *declaration* against a qualifier (`import db` + `fn db()`), and `let db` inside a function, stay under the existing §10.1 hiding rule. I support PLT's friction ticket for the declaration-against-qualifier pair (Q3.2-C) as a follow-up, but not as the answer for the import pair.
>
> ## V-items
>
> - **V1 (E1005 replaces W0602 on the colliding entry): support.** One mistake gives one diagnostic, as with E1012.
> - **V2 (E1012 first, then E1005 among the remaining imports): support.** The order is deterministic, which LSP and CLI output need.
> - **V3 (help derives names such as `AuthError` / `auth_error`): partial support.** Help text may show a derived name as an example. The spec must not make a naming convention normative for a suggestion-only fix.
> - **V4 (`import a.{X, X as Y}` is legal): support.** It binds two names to one item, and no name is bound twice.
> - **V5 (prelude-name alias stays under W1010): support.** No change.
> - **V6 (per-file binding table, stated in the spec): support.** This also makes the `tc_alias_to_original` bug directly testable.
> - **V7 (one sentence under *Import Aliases*): support.**
>
> Stable, ready to vote.

##### Web/Scripting

> # Web/Scripting, Phase B round 1
>
> ## Q1: Q1-A (E1005 for import vs import, E1012 for import vs declaration). No change.
>
> All six of us put Q1-A first. Min's M2 is cleaner on paper, but it changes the meaning of a published code. It also loses the property that devops, PLT and AI/ML named: each code maps to one fix shape. E1012 means "drop the import", which is machine-applicable. E1005 means "choose a name", which is a suggestion. A developer who reads only the code still knows what to do next. The diagnostic title can say "imported twice", so "Ambiguous" in the catalog name does no harm.
>
> ## Q2: Q2-B (W0602 warning, machine-applicable delete, identity is the resolved item). I am moving off my "would accept Q2-A" fallback.
>
> Min, you say the same-entity exemption "protects nobody". It protects two real groups:
> 1. **Facade users.** Sys's `codegen_types` / `codegen_common` case is in this repo today. PLT's point decides it for me: under Q2-A, when a library adds a `pub import` in a minor release, a downstream build that adds no new name breaks. In npm terms, a patch release breaks your build because the library re-exported something. That costs real hours.
> 2. **Merge results and auto-imports.** Two branches that each add `import auth.{Error}` produce a literal repeat. TS reports that (TS2300), but TS users also have an editor that dedupes on save. Making it a hard error that stops `blink run` for a line with one meaning is friction with nothing gained. A warning plus `blink fix` cleans it up.
>
> The identity check is not new machinery. Name resolution already follows `pub import` chains to get the item.
>
> On Q2-C: reuse W0602 and do not add a `DuplicateImport` code. Agree with devops that `blink fmt` must not dedupe, because fmt does not resolve names. `blink fix` does it.
>
> ## Q3.2: Q3.2-A (a qualifier and a selective bare binding of one name are E1005). C is my second choice, B my last.
>
> Sys, the "separate layers" reading is correct as a statement about lookup. As a rule for users it is the worst silent failure in this ticket. Devops's case:
>
> ```blink
> import db
> import auth.{Token as db}
>
> fn f() {
>     db.connect()    // today: a static call on Token, not the db module
> }
> ```
>
> Under §10.1's rule that "local definitions shadow module names", the qualifier silently loses. This is the Python last-import-wins bug in another form. A JS developer sees one identifier, `db`, written twice in the import block. In JS, `import * as db` together with `import { Token as db }` is a SyntaxError ("Identifier 'db' has already been declared"). Python rebinds silently and costs people an afternoon. "One spelling, one binding in the import block" also serves the §10.1 goal: you can find every name from the import block alone. A block where `db` means two things fails that test.
>
> The `let auth = 5` hiding rule stays as it is. That is a local in a nested scope, not two imports. Q3.2-A only covers two entries in the import block.
>
> PLT: deferring (Q3.2-C) is better than Q3.2-B, because it at least does not bless the silent case. But we have the context now, the fix is one more key in the same per-file table, and a friction ticket only means we hold this debate again later.
>
> ## V-items
>
> - **V1, support.** One mistake gives one diagnostic.
> - **V2, support.** Report E1012 first, then E1005 among the imports that remain. That is a stable cleanup order for the CLI and the LSP.
> - **V3, support.** Help text with concrete names (`AuthError`, `auth_parse`) is what a developer copies. A vague "rename one" makes people search for an answer.
> - **V4, support.** `{X, X as Y}` is legal.
> - **V5, support.** No change.
> - **V6, support.** It makes the per-file rule something a test can check.
> - **V7, support.** One sentence under Import Aliases.
>
> Stable, ready to vote.

##### PLT

> # PLT — Phase B round 1
>
> ## Q1: Q1-A (E1005 import vs import; E1012 import vs declaration)
>
> No change. All six panelists hold this, and Minimalism's M2 is a fallback, not a preference. The reason is formal: a diagnostic code should index the violated rule *plus its repair policy*. Both pairs violate one rule (flat scope), but only E1012 has a canonical winner, so only E1012 has a machine-applicable fix. One code with two fix policies is a worse index for `blink fix`, LSP and models (devops, aiml make the same point from their side).
>
> ## Q2: Q2-B (same item, same name → W0602, machine-applicable delete; identity after `pub import` chains)
>
> Against Minimalism's Q2-A. The rule [the flat module-scope decision] states is "one name, one binding". A binding is a name→entity pair. `import a.{X}` + `import b.{X}` where `b` re-exports `a.X` produces the *same* pair twice; the environment is a function either way, so nothing is duplicate in the semantic sense. Q2-A makes the rule depend on the import *path*, which is not part of the denotation.
>
> The cost Minimalism names ("needs identity resolution through re-exports") is not real: name resolution already resolves `pub import` chains to the defining declaration (sys S2); the check is one ID comparison.
>
> The cost of Q2-A is real: it makes adding a re-export a breaking change for downstream code. A facade module that adds `pub import inner.{X}` breaks every client that already imports `X` from both. That is non-compositional — a library's additive change should not invalidate a well-formed client. Rust's E0252 is the counter-example, and Rust then needed glob-import special cases to soften exactly this.
>
> I accept devops' Q2-C refinement on one axis: `blink fmt` does not dedupe (it is syntactic and must not resolve names); `blink fix` does. On the code: reuse W0602; no new code (Minimalism should prefer that).
>
> ## Q3.1: E1005. Agreed by all.
>
> ## Q3.2: change of position — from Q3.2-C (defer) to Q3.2-A (E1005)
>
> devops' example settles it:
> ```blink
> import db
> import auth.{Token as db}    // E1005
> ```
> Sys argues the layers are separate. They are not separable in the syntax: `X.y` is both qualified access (`auth.Token`) and type-qualified access (`Token.new`, `Role.Admin`). If `db` is both a qualifier and a bare type, `db.connect()` resolves only through a precedence rule — that is a shadow inside module scope, which [the flat module-scope decision] forbids. So the qualifier layer and the bare-name layer share one key space for module-scope bindings, and the collision is E1005.
>
> The §10.1 rule "`let auth = 5` hides `auth.login()`" stays: a function-local `let` is a nested scope, and shadowing between nested scopes is legal. A *module-level* `let db` against `import db` is the decl-vs-qualifier pair; by the same reasoning it should be E1012, but that widens an already-decided code, so I propose a friction ticket for it rather than settling it here.
>
> ## V-items
>
> - V1 support (my proposal; one mistake, one diagnostic).
> - V2 support. The declaration is the canonical winner, so its pair gets resolved first; E1005 then runs over the imports that remain. Deterministic ordering in CLI and LSP.
> - V3 support as a "should" in help text, not a normative naming scheme. Spec must not fix identifier generation.
> - V4 support. Two names, one entity: no name has two bindings.
> - V5 support. Prelude is a nested scope; W1010 is the correct layer.
> - V6 support. Already existing text; the restatement makes the test plain.
> - V7 support. One sentence, under Import Aliases.
>
> Stable, ready to vote.

##### DevOps/Tooling

> **DEVOPS/TOOLING — Phase B round 1**
>
> **Q1: A (E1005 import vs import; E1012 import vs declaration).** No change. All six of us put A first, and PLT gives the reason I care about: one code, one fix policy. `blink fix` and the LSP pick their code-action kind from the diagnostic code. E1012 maps to "machine-applicable delete" and E1005 to "suggestion, a human picks a name". If we merge them, every tool has to look inside the diagnostic to decide whether it may auto-apply the fix. That is a smell. Min's M2 is right that the name "Ambiguous import" now fits poorly, but a code number is a stable public handle, and renaming it costs more than the bad name does.
>
> **Q2: B. I fold my Q2-C into it.** I withdraw the "new `DuplicateImport` code" option. W0602 on the redundant entry, with a machine-applicable delete, is enough. I keep one clause from Q2-C: `blink fmt` does not dedupe, because the check needs name resolution and fmt must stay syntactic. The delete belongs to `blink fix` and the LSP quick-fix.
>
> Against Min's Q2-A: the "needs identity resolution through re-exports" cost is not new. The compiler already follows `pub import` chains to report E1003 and to resolve every use. PLT's compatibility argument decides it for me. If a library adds a re-export path in a minor release, a downstream build that names nothing new would then fail with an *error*. From the tooling side, that is a CI break that no `blink fix` can resolve without user input, for a program that has no ambiguity. A warning with an auto-fix gives the same cleanup without the break.
>
> **Q3.2: A (one binding per name across bare names and qualifiers). I hold this, against Sys (B) and PLT (C).**
>
> ```blink
> import db
> import auth.{Token as db}
> fn f() { db.connect() }      // module call, or static method on Token?
> ```
>
> Sys says these are separate layers, citing §10.1 `let auth = 5`. But that rule is about a *nested* (function) scope hiding a module qualifier. Here both bindings are at file scope, and [the flat module-scope decision] says two bindings at one level are a duplicate, never a shadow. If the layers never collide, the spec still has to say which one `db.connect()` resolves to. Whichever answer it picks is a silent same-level shadow, which is the bug this ticket exists to remove. From the LSP side, hover, go-to-definition and rename on `db` have to pick one target without a diagnostic. That is the "jumps to the wrong file" class of report.
>
> PLT's defer (C) leaves the compiler with no specified answer, so the implementation ticket will pick one silently. If the panel will not take A, I prefer C over B, because C at least does not bless the silent pick.
>
> Web's S3 (`import errors as E` + `import auth.{Error as E}`) is the same case, and `E.x` shows the ambiguity directly.
>
> **V-items**
> - V1 support (E1005 replaces W0602 on the entry).
> - V2 support (E1012 first, E1005 among the remaining imports). Without an order, a file with three bindings of `X` gives output that depends on traversal order, and LSP diagnostics flicker between edits.
> - V3 support, with two conditions. The suggested name must be checked as free in the file before it is printed (never suggest `AuthError` when `AuthError` is already bound). The suggestion stays non-applicable (C3).
> - V4 support (`{X, X as Y}` legal).
> - V5 support (W1010 already covers it).
> - V6 support. The test plan needs "two files each bind `E` differently, with no diagnostic".
> - V7 support.
>
> Stable, ready to vote.

##### AI/ML

> # AI/ML panelist, Phase B round 1
>
> **C1–C6:** I support all six as written.
>
> ## Q1: Q1-A (E1005 for import vs import, E1012 for import vs declaration)
>
> I drop my P2 fallback. Five other panelists reached Q1-A on their own, and PLT and devops gave the deciding reason: each code has one fix policy. For E1012 the fix is "drop the import", which is machine-applicable. For E1005 the fix is "pick a new name", which is a suggestion only. When a model sees the code, it knows the fix without reading the spans. Min's M2 ("nothing is ambiguous, it is a duplicate") is right about the name. But if E1005 changed meaning, the catalog, `blink explain`, tests and model training data would all have to change, and the model would gain nothing from that. Keep E1005, and reword its Cause as C5 says.
>
> ## Q2: Q2-B (W0602 with a machine-applicable delete; identity is the resolved item)
>
> Min argues that the carve-out "protects nobody". PLT's compositionality point answers that. If this were E1005, a library that adds a `pub import` path in a minor release could break a downstream build that names nothing new. A user cannot predict that kind of break from their own file. It is also the worst case for a model: the error appears in code the model did not change, and the only fix is to delete a line that looks correct.
>
> Models also write literal duplicate imports all the time when they merge two edits into one import block. A warning with a machine-applicable delete fixes this in zero round trips. An error costs one compile and one edit, and the program means the same either way.
>
> I support devops's Q2-C detail that `blink fmt` does not dedupe and `blink fix` does. But reuse W0602, with no new `DuplicateImport` code: one fewer code to learn, and the fix is the same as for any unused import. If Q2-B loses, I accept Q2-A only if the delete fix is machine-applicable there too, as web said.
>
> ## Q3.1: E1005
>
> Everyone agrees, and `blink explain` already says so.
>
> ## Q3.2: I move to Q3.2-A (E1005 across qualifier and bare binding)
>
> My Phase A did not address this pair, and devops's P3 example decides it for me:
>
> ```blink
> import db
> import auth.{Token as db}    // E1005
> fn f() { db.connect() }      // without the error: a static call on Token
> ```
>
> Sys says the two are separate layers. They are separate in the symbol table, but at a use the reader sees one spelling, `db.x`, and §10.1 lets a binding hide the qualifier. Without an error, `db.connect()` silently changes meaning, and "no such method `connect` on Token" sends a model looking in the wrong file. Two layers that a reader cannot tell apart at the use site should be checked as one.
>
> PLT's Q3.2-C (file a friction ticket and decide later) leaves this trap open until that ticket closes. An eager error now costs nothing: no correct program needs both bindings.
>
> The same reasoning would cover a module-level declaration `fn db` + `import db`. That case is not on this ticket. I would note it for a follow-up and not decide it here.
>
> ## V-items
>
> - **V1 (E1005 replaces W0602 on that entry): support.** One mistake gives one diagnostic, the same as E1012.
> - **V2 (E1012 first, then E1005 among the remaining imports): support.** This gives a deterministic order of fixes, and agents apply diagnostics in order.
> - **V3 (deterministic names in help): I keep it.** Sys, web, devops and min all printed `DbError` in their own examples, so the panel already does this. V3 only makes it the rule. It belongs to the help text and changes no semantics.
> - **V4 (`{X, X as Y}` is legal): support.** It binds two names and binds no name twice.
> - **V5 (prelude alias stays W1010): support.**
> - **V6 (per-file binding table stated as normative): support.** It makes the global-map bug testable against the spec text.
> - **V7 (one sentence under Import Aliases): support.** The rule must be readable at the place where a model learns `as`.
>
> stable, ready to vote

##### Minimalism

> ## Minimalism, Phase B round 1
>
> **C1–C6:** I confirm all six. They are the whole of my M1.
>
> ### Q1: Q1-A (E1005 for import vs import, E1012 for import vs declaration)
>
> I withdraw my fallback M2. PLT and devops made the case: E1012's fix is machine-applicable (the declaration wins), and E1005's fix is a suggestion only (someone must choose a name). One code per fix policy is the smaller contract for `blink fix`, the LSP and models. Q1-A also needs no new code and no churn in `blink explain`. Merging the codes would save one table row and cost a code that carries two fix policies. Not worth it.
>
> ### Q2: I change from Q2-A to Q2-B
>
> I was the only vote for Q2-A, and I was wrong for a minimalist reason. Define a binding as a pair: name → entity. Then "duplicate" means one name with two entities, as PLT put it. Inserting the same pair a second time changes nothing, so no rule is broken. The redundant entry is then just an import that does nothing, which is the existing W0602. Q2-B adds **no rule and no code**. It follows from defining a binding correctly, so the "same-entity exemption" I opposed is not really an exemption.
>
> The cost I feared, identity resolution through `pub import`, is something name resolution already does (sys). I do not accept PLT's compositionality argument as written: `import b.{X}` was E1003 before `b` re-exported `X`, so adding a re-export cannot break an existing build. The stronger reason is that Q2-A would penalize harmless code with no gain.
>
> I oppose **Q2-C's** "new `DuplicateImport` code". W0602 already covers it, so a new code is surface for nothing. Devops' "`blink fmt` does not dedupe" is right, but it is tooling policy, not language spec. Leave it out of the spec text.
>
> ### Q3.2: Q3.2-B (separate layers), with Q3.2-C as my second choice
>
> I oppose Q3.2-A, because it breaks a decision made today. The E1012 decision says that a whole-module import binds no bare name, so it never collides with a declaration. So `import db` + `type db` is legal, and `db.x` follows the §10.1 hiding rule. Under Q3.2-A, `import db` + `import auth.{Token as db}` would be an error. That gives two rules for the same qualifier-vs-bare-name pair, decided by whether the bare name came from an import or a declaration. That asymmetry is exactly what [the flat module-scope decision] and E1012 removed.
>
> Devops' hazard (`db.connect()` silently becomes a call on `Token`) is real. But `type db` causes it too, so it is a hiding-rule question for both kinds of binding, not an import-collision question. If the panel wants to close it, do it once, for declarations and imports together, in its own ticket (PLT's Q3.2-C). Do not patch half of it here.
>
> **Q3.1:** E1005. That is the consensus, and `blink explain` already says it.
>
> ### V-items
>
> - **V1 (E1005 replaces W0602 on the colliding entry):** support. One mistake gives one diagnostic, the same as E1012.
> - **V2 (E1012 first, then E1005 among the remaining imports):** support. It is a deterministic order and costs one sentence.
> - **V3 (concrete deterministic help names):** oppose as spec text. It is diagnostic polish that belongs to the implementation and to tooling guidance. Fixing a naming convention in the spec freezes something we will want to tune later. A good help line is fine. A normative naming algorithm is not.
> - **V4 (`{X, X as Y}` is legal):** support. It already follows from C1. At most one clause, or none.
> - **V5 (prelude alias is covered by W1010):** support. No change needed.
> - **V6 (per-file binding table):** support only as a restatement of existing text, one clause. The real work is the compiler bug.
> - **V7 (one sentence under Import Aliases):** support. This is my own item.
>
> Stable, ready to vote.

#### Phase B — Debate, round 2

##### Systems

> # Systems, Phase B round 2
>
> No change in position. I hold Q1-A, Q2-B, Q3.1 = E1005 and Q3.2-A. Two replies follow.
>
> **To min on Q3.2 (asymmetry with the decision made today).** The asymmetry is real: under A, `import db` + `type db` is legal, but `import db` + `import auth.{Token as db}` is E1005. Choose by which mistake can be undone:
> - If the follow-up ticket (declaration against qualifier) picks "one key space", then A is already right, and only declarations need to change.
> - If it picks "separate layers, hiding rule", then E1005 on this pair relaxes to legal. Accepting more programs breaks nobody.
> - B now, followed by "one key space" later, turns programs that build today into errors. That is a breaking change, and in the meantime the silent `db.connect()` → `Token.connect()` trap stays open.
>
> So A is the safe choice now. B locks in the one outcome that can only be reversed by breaking users. I agree a follow-up ticket must settle the declaration pair. That ticket should be filed whatever the vote, so the asymmetry has an owner.
>
> **To min and PLT on Q2.** Min is right that PLT's compositionality case fails: `import b.{X}` was already E1003 before the re-export existed. The reasons for Q2-B that still stand are the facade migration in this repo (both paths are valid while the move is in progress), merged and auto-generated duplicate lines, and the binding defined as name → entity, which min now states. Each has one meaning, so a warning is correct and an error is noise.
>
> **V3.** I hold "help text may show a derived name; the naming scheme is not normative". Devops's condition fits well: a suggested name must be free in the file. I support that as a "must" on the help text.
>
> Stable, ready to vote.

##### Web/Scripting

> # Web/Scripting, Phase B round 2
>
> **Q2, conceding a point.** Min is right that PLT's re-export argument fails as written: `import b.{X}` was E1003 before `b` re-exported `X`. My Q2-B vote does not depend on it. It rests on merge duplicates, auto-imports and sys's facade migration, plus min's own point that the same name-to-item pair inserted twice breaks no rule.
>
> **Q3.2, answering min. I hold A.** The asymmetry is real. `import db` + `type db` stays legal under the E1012 decision, so A closes the import half of the hazard and leaves the declaration half open. But B does not remove the asymmetry. It blesses the silent case for both halves. Two points favor closing the import half now:
>
> 1. **The §10.1 principle is about the import block.** "You can find every name from the import block alone." When both bindings sit in the import block, a reader sees `db` written twice four lines apart. A `type db` 300 lines down is a different reading problem: it is the declaration-vs-qualifier question that sys, PLT and AI/ML all want in a follow-up ticket.
> 2. **This case is the common one.** Aliasing with `as` is how people resolve name clashes, so `{Token as db}` next to `import db` is the mistake a JS or Python developer actually makes. Nobody names a type `db` by accident.
>
> So: A for import vs import now, plus the follow-up ticket for declaration vs qualifier, where min's "close it once for both" applies. If A loses, I vote C over B.
>
> **V3, narrowing my support.** I agree with sys, PLT and min: concrete names in help are a "should" for the diagnostic text, not a normative naming algorithm. I add devops's condition that a suggested name must not already be bound in the file.
>
> Stable, ready to vote.

##### PLT

> # PLT — Phase B round 2
>
> No change in votes: Q1-A, Q2-B, Q3.1 E1005, Q3.2-A, V1–V7 as in round 1. Two replies to Minimalism.
>
> **On Q2, Min is right about my argument.** If a client imports `X` through `b`, `b` must already export `X`, or the import is E1003. So adding a re-export cannot break an existing build in the simple case. I withdraw that argument. Min's own reason is the correct one: a binding is a pair of a name and the item it denotes, and adding the same pair twice adds nothing. Q2-B follows from that definition and needs no exemption. Sys's facade migration (two paths to one item while code moves) is the practical case.
>
> **On Q3.2, the asymmetry Min names is real, but A is still the right step.** Under A, `import db` + `import auth.{Token as db}` is an error, while `import db` + `type db` stays legal under the E1012 decision. But A only rejects programs; it never accepts one that B would reject. When the follow-up makes a declaration that collides with a module name an error too, it will only add rejections, so no program legal under A becomes illegal in a surprising way after that ticket. B instead defines the import-vs-import case as legal now, and closing the hole later would then be a breaking change. The order that keeps the language consistent is "reject now, extend the rejection later", not "allow now, decide together later".
>
> Request for the decision record: file the declaration-vs-module-name pair (`import db` + `type db`/`fn db`) as a `type:spec` ticket, not friction. It should say this asymmetry is temporary.
>
> Stable, ready to vote.

##### DevOps/Tooling

> **DEVOPS — Phase B round 2 (rebuttal to Min on Q3.2)**
>
> Min says Q3.2-A breaks the E1012 decision, because `import db` + `type db` is legal and so `import db` + `import auth.{Token as db}` must be legal too. Read §10.1 again: "**Local definitions** shadow module names." `type db` is a local definition, so the hiding rule gives a winner, and today's decision left that pair alone on purpose. An imported `Token as db` is not a local definition. Under the current text, which side wins between two *imports* is **not specified at all**. Q3.2-B would not keep an existing rule. It would invent a precedence between two imports in one block. That is the same silent last-import-wins this ticket exists to remove.
>
> So there is no conflict:
> - declaration vs qualifier: the existing hiding rule gives a canonical winner. The friction ticket (Sys, PLT, AI/ML, Min all agree) can revisit it for declarations and imports together.
> - import vs qualifier: no rule gives a winner, so E1005. This matches Q1's logic: no canonical winner means E1005, suggestion-only fix.
>
> Tooling note: under B the LSP must ship its own invented precedence for hover and go-to-definition on `db`, and that precedence is not in the spec. A tool that has to make up language semantics is a spec gap.
>
> Smaller items:
> - V3: I accept "should, not normative" (Sys, PLT, Min).
> - `blink fmt` does not dedupe: fine in the decision record rather than spec text (Min).
>
> Position unchanged: Q1-A, Q2-B, Q3.1 E1005, Q3.2-A (C second), V1–V7 support, with V3 non-normative.

##### AI/ML

> # AI/ML, Phase B round 2
>
> **Q2: no change (Q2-B), but I concede one point to Min.** Min is right that PLT's re-export argument does not hold as stated: `import b.{X}` was E1003 before `b` re-exported `X`, so adding a re-export cannot break an existing build. Part of my round 1 relied on that argument, and I withdraw that part. Q2-B still holds on the binding definition (name → entity), which Min and PLT both accept, and on merged duplicate import lines, which models write often.
>
> **Q3.2: I hold A, and I accept that Min's asymmetry is real.** `import db` + `type db` is legal under today's E1012 decision, and `import db` + `import auth.{Token as db}` would be E1005. Two answers for one qualifier-vs-bare-name pair is a decision point that a model has to learn. But B and C each cost a silent rebinding, and that is worse for a model than an asymmetry the compiler enforces. The asymmetry produces an error the model can read and fix. The rebinding produces "no method `connect` on Token" in a file the model did not touch. The import half is also the half that actually happens: the user picks an alias freely, so a lowercase alias such as `db` is plausible, while `type db` breaks the naming convention.
>
> So: A for import vs import now, plus a follow-up ticket that puts declaration vs qualifier under the same rule. That ticket ends with one symmetric rule. Sys and PLT already asked for the same follow-up. If A loses, I vote C over B.
>
> **V3: I narrow it.** I agree with Sys, PLT and Min: no normative naming algorithm. Spec text: "help should print a concrete name". Add Devops's condition that the printed name must not already be bound in the file. The exact naming scheme belongs to the implementation.
>
> stable, ready to vote

##### Minimalism

> ## Minimalism, Phase B round 2
>
> **Q3.2: I change from B to A.** PLT's argument settles it. `X.y` is both qualified access (`auth.Token`) and type-qualified access (`Token.new`). So a qualifier and a bare type share one key space at the use site. If both bind `db`, the spec has to say which one wins, and that is a shadow inside module scope, which [the flat module-scope decision] forbids. One per-file table keyed on the bound name (sys) is also the smaller model: one table and one rule, not two layers plus a precedence rule.
>
> My asymmetry objection still stands, but it now points at a follow-up, not at B. Today `import db` + `type db` is legal under the E1012 decision, while `import db` + `import auth.{Token as db}` becomes E1005. By PLT's own reasoning the declaration pair should be E1012 too. That widens an already-decided code, so it belongs in its own ticket. **Condition on my vote:** the decision record names that follow-up (declaration vs module qualifier), so the asymmetry is on record as temporary and not as the design. A function-local `let auth` keeps the §10.1 hiding rule, because it is a nested scope.
>
> **V3:** I now accept the sys/PLT form. The help line *should* show a concrete, free name (devops: check that the name is not already bound in the file). The spec does not fix a naming algorithm. I still oppose V3 as a normative naming scheme.
>
> Q1-A, Q2-B and the other V-items: no change.
>
> Stable, ready to vote.

#### Phase C — Final vote (all 6-0)

##### Systems

> # Phase C, systems vote
>
> **C (shared points C1–C6): YES**
> - Reasoning: One per-file table keyed by the bound name, checked when each import entry goes in. That is one lookup per entry, the result does not depend on which uses exist, and every error carries a location.
> - Concern: The implementation ticket could fix the spec text and leave the global `tc_alias_to_original` map in place. C6 must arrive with a test that has two files.
>
> **Q1: Q1-A**
> - Reasoning: One code has one fix policy. Tools pick "auto-apply" or "suggest" from the code alone, without reading the message. No published code changes meaning.
> - Concern: The catalog name "Ambiguous import" now describes a duplicate. The Cause text must be reworded, or readers will keep looking for an ambiguity at the use site.
>
> **Q2: Q2-B**
> - Reasoning: Name resolution already resolves each entry to a declaration ID, so the check is one compare of two integers. A binding is the pair name → item. A repeat of the same pair changes nothing, so W0602 with a delete fix is correct. This also keeps facade moves and merged duplicate lines out of the error path.
> - Concern: "Same item" must mean the same declaration after following `pub import` chains, not the same spelling. An implementation that compares paths as text would give wrong E1005 errors.
>
> **Q3.1: YES**
> - Reasoning: The same table and the same rule apply. `blink explain E1005` already says this.
> - Concern: None worth naming. It must have a location like every other E1005.
>
> **Q3.2: Q3.2-A**
> - Reasoning: Without it, `db.connect()` silently resolves to `Token.connect()`. That is a same-level shadow, which [the flat module-scope decision] forbids. A is also the choice that can be undone safely: if a later ruling separates the layers, relaxing E1005 breaks nobody. B followed by a later "one key space" ruling would break code that builds today.
> - Concern: For now, `import db` + `type db` stays legal while the import pair is an error. A follow-up ticket for declaration against qualifier must be filed with this decision, or the mismatch stays for good.
>
> **V1: YES**
> - Reasoning: One mistake gives one diagnostic, the same as E1012.
> - Concern: The W0602 pass must know E1005 already fired, so the passes must run in a fixed order.
>
> **V2: YES**
> - Reasoning: A fixed order makes the output stable across runs and edits, so LSP diagnostics do not change between edits.
> - Concern: When a declaration and two imports all bind `X`, the order of fixes must be tested, not assumed.
>
> **V3: V3-b**
> - Reasoning: A concrete name the user can copy is good. A free-name check is cheap. A normative naming algorithm freezes polish we will want to tune later.
> - Concern: Implementers may read the "should" as optional and print a bare "rename one".
>
> **V4: YES**
> - Reasoning: It binds two names and binds no name twice, so it follows from C1 and costs nothing.
> - Concern: None.
>
> **V5: YES**
> - Reasoning: The prelude is a nested scope, and W1010 already covers this case.
> - Concern: None.
>
> **V6: YES**
> - Reasoning: It makes the global-map bug testable against the spec text: two files each bind `E` differently, with no diagnostic.
> - Concern: None.
>
> **V7: YES**
> - Reasoning: The rule must be readable where a user or model learns `as`.
> - Concern: None.

##### Web/Scripting

> # Phase C, Web/Scripting ballot ([this spec ticket])
>
> **C (C1–C6): YES**
> - Reasoning: Eager, located errors on the import line are what JS/TS, Rust, Kotlin and Go developers already expect. The current silent last-import-wins behavior is Python's known footgun. The suggestion-only fix, the stale §10.1 sentence and the per-file scope are all plain corrections.
> - Concern: The implementation may keep `diag_error_no_loc`. A location-free E1005 would undo the main DX gain, so the impl ticket must test the spans.
>
> **Q1: Q1-A**
> - Reasoning: A developer can learn the split in one line: two imports is E1005, an import and a declaration is E1012. Each code maps to one fix: choose a name, or drop the import. It reuses an existing code and help text, with no churn in `blink explain` or in docs people have already searched.
> - Concern: The catalog name "Ambiguous import" now reads slightly off for an eager duplicate check. The diagnostic title must say "imported twice", or people will look for a use-site cause.
>
> **Q2: Q2-B**
> - Reasoning: A literal repeat from a merge, an auto-import, or a facade migration means one thing. A hard error that stops `blink run` for it is pure friction. A warning with a machine-applicable delete in `blink fix` cleans it up in zero round trips, and it reuses W0602 with no new code.
> - Concern: Users may not see that two different paths reach one item. The W0602 message should name the shared resolved item, not just say "unused".
>
> **Q3.1: YES**
> - Reasoning: Two module aliases with one spelling is the plainest form of the bug. `blink explain` already promises this.
> - Concern: None material.
>
> **Q3.2: Q3.2-A**
> - Reasoning: `import db` + `import auth.{Token as db}` silently turns `db.connect()` into a call on `Token`. That is Python's silent rebinding again, and in JS the same pair is a SyntaxError. Both bindings sit in the import block, so one spelling must mean one thing there.
> - Concern: This leaves the declaration-vs-qualifier half (`import db` + `type db`) open and asymmetric. The decision must file that follow-up ticket explicitly, or the gap becomes permanent.
>
> **V1: YES**
> - Reasoning: One mistake gives one diagnostic, the same as E1012.
> - Concern: None.
>
> **V2: YES**
> - Reasoning: A stable cleanup order keeps CLI and LSP output from shuffling between edits.
> - Concern: The rule is an edge case and could end up wordy in the spec. Keep it to one sentence.
>
> **V3: V3-b**
> - Reasoning: A help line developers can copy (`import db.{Error as DbError}`) stops the "what do I rename it to" question. A normative naming algorithm would freeze polish the team will want to tune.
> - Concern: The implementation may skip the "not already bound" check and suggest a name that itself collides.
>
> **V4: YES**
> - Reasoning: Two names for one item binds no name twice, so it is not a collision.
> - Concern: None.
>
> **V5: YES**
> - Reasoning: W1010 already covers this case, so no change is needed.
> - Concern: None.
>
> **V6: YES**
> - Reasoning: It restates the existing per-file text in a form a test can check, and it targets the global-map bug.
> - Concern: None.
>
> **V7: YES**
> - Reasoning: People learn `as` in the Import Aliases section, so the collision rule should be visible there.
> - Concern: None.

##### PLT

> # PLT — Phase C vote
>
> **C (C1–C6): YES**
> Reasoning: One rule, flat module scope where a name maps to at most one item, applied to the bound name and checked eagerly. This follows directly from [the flat module-scope decision] and the E1012 decision.
> Concern: The §10.1 sentence and §5:545 must change in the same edit, or the spec will define E1005 two ways.
>
> **Q1: Q1-A**
> Reasoning: A code should identify the rule that was broken and how to fix it. Both pairs break the same flat-scope rule, but only E1012 has a clear winner, so only E1012 has a fix that tools can apply automatically. Giving them separate codes keeps that difference visible to tools.
> Concern: The catalog name "Ambiguous import" no longer describes the cause, so the Cause text must carry the new meaning.
>
> **Q2: Q2-B**
> Reasoning: A binding is a pair of a name and the item it means. Adding the same pair twice adds nothing, so no rule is broken, and the extra entry is just an unused import (W0602). The comparison of resolved items costs nothing new, because name resolution already follows `pub import` chains.
> Concern: "Same item" must mean the same declaration after re-exports are followed, not two items with the same structure. The spec text must say that exactly.
>
> **Q3.1: YES**
> Reasoning: Two bindings of one module name in one file are a duplicate under the same rule. `blink explain E1005` already says this.
> Concern: None material.
>
> **Q3.2: Q3.2-A**
> Reasoning: `X.y` is both qualified access (`auth.Token`) and type-qualified access (`Token.new`). So module names and bare names share one key space, and allowing both would be a shadow inside module scope. A only rejects programs, so a later rule that also rejects declarations against module names can extend it without breaking anyone.
> Concern: Until a follow-up ticket covers the declaration-vs-module-name pair (`import db` + `type db`), the rules disagree, so the decision record must say that and file it as `type:spec`.
>
> **V1: YES**
> Reasoning: One mistake should give one diagnostic, as with E1012.
> Concern: None material.
>
> **V2: YES**
> Reasoning: The declaration is the clear winner, so its pair is resolved first. The order is fixed and does not depend on the order the compiler walks the file.
> Concern: The spec must give the order in one sentence so the CLI and the LSP agree.
>
> **V3: V3-b**
> Reasoning: A concrete name in the help text is useful, but the spec must not fix how names are made up for a fix that is only a suggestion. Requiring that the name is not already bound in the file prevents a suggestion that would itself cause a collision.
> Concern: Implementations may differ in the names they print. That is acceptable.
>
> **V4: YES**
> Reasoning: It binds two names to one item and binds no name twice.
> Concern: None material.
>
> **V5: YES**
> Reasoning: The prelude is an outer scope, and a module binding hiding it is ordinary nested-scope shadowing, which W1010 already covers.
> Concern: None material.
>
> **V6: YES**
> Reasoning: This restates existing text, and stating it as a rule lets a test check the global-map bug against the spec.
> Concern: None material.
>
> **V7: YES**
> Reasoning: The rule should be readable where `as` is taught.
> Concern: None material.

##### DevOps/Tooling

> # DEVOPS/TOOLING — Phase C vote ([this spec ticket])
>
> **C (C1–C6): YES**
> Reasoning: Eager, located, per-file diagnostics with suggestion-only fixes are what an LSP can attach to a range and offer as code actions. The `4:1` location and the no-loc emission must go.
> Concern: The implementation might keep `diag_error_no_loc` for some path, which would leave an LSP diagnostic with no range.
>
> **Q1: Q1-A**
> Reasoning: One code, one fix policy. E1012 auto-applies and E1005 is suggestion-only, so `blink fix` and editors can pick the code-action kind from the code alone. No published code changes meaning.
> Concern: The catalog name "Ambiguous import" now reads oddly for an eager duplicate, so the diagnostic title must say "imported twice".
>
> **Q2: Q2-B**
> Reasoning: The program has one meaning, so a warning with a machine-applicable delete fixes it in zero round trips, and adding a re-export upstream never breaks CI. Identity is already computed by name resolution. `blink fmt` stays syntactic and does not dedupe.
> Concern: If identity is compared by path text instead of resolved item, two paths to one item will be wrongly reported as E1005.
>
> **Q3.1: YES**
> Reasoning: `blink explain E1005` already says this. The spec must back what the tool prints.
> Concern: None material.
>
> **Q3.2: Q3.2-A**
> Reasoning: Between two imports, no rule picks a winner, because §10.1 hides qualifiers only for local definitions. Without the error, hover and go-to-definition on `db` must invent a precedence the spec lacks. An eager E1005 removes the silent `db.connect()` retarget.
> Concern: Users may ask why `type db` + `import db` is legal while the import pair is not. The follow-up ticket on declaration vs qualifier must be filed, or the asymmetry reads as an accident.
>
> **V1: YES**
> Reasoning: One mistake gives one diagnostic, the same as E1012.
> Concern: An implementation that emits both will make the editor show a misleading "unused import" quick-fix next to the real error.
>
> **V2: YES**
> Reasoning: A deterministic order keeps CLI and LSP output stable between edits, and gives agents a fixed order of fixes.
> Concern: The order must be specified as a rule, not left to traversal order.
>
> **V3: V3-b**
> Reasoning: A concrete name that is free in the file is what a developer or model copies. A fixed naming scheme would freeze diagnostic polish into the spec.
> Concern: A suggested name that is already bound creates a second error, so the "not already bound" clause must be tested.
>
> **V4: YES**
> Reasoning: Two names bound to one entity, and no name bound twice. Nothing to report.
> Concern: None material.
>
> **V5: YES**
> Reasoning: W1010 already covers this case at the correct (nested prelude) layer.
> Concern: None material.
>
> **V6: YES**
> Reasoning: This makes the global-map bug testable: two files each bind `E` differently, with no diagnostic.
> Concern: The LSP's incremental cache must also key bindings per file, or editor results will diverge from the CLI.
>
> **V7: YES**
> Reasoning: The rule must be readable where users and models learn `as`.
> Concern: None material.

##### AI/ML

> # Phase C — AI/ML vote
>
> **C (C1–C6): YES**
> Reasoning: Together these points give one rule (one bound name, one binding per file), checked at the line that caused the error. A model can learn that rule from the spec alone. They also remove the stale §10.1 text, which teaches a false model.
> Concern: If the implementation keeps `diag_error_no_loc` for E1005, the import-site rule will be true in the spec and false in practice.
>
> **Q1: Q1-A**
> Reasoning: Each code maps to one family of fixes. E1005 means "pick a name" (a suggestion). E1012 means "drop the import" (machine-applicable). A model or `blink fix` can choose the action from the code without parsing the spans.
> Concern: The catalog name "Ambiguous import" no longer describes an eager duplicate check. Models that learned the old wording may look for a use site.
>
> **Q2: Q2-B**
> Reasoning: A binding is a name plus the item it refers to, so a repeated pair breaks no rule. Models often write duplicate imports when they merge edits. A warning with a machine-applicable delete fixes that with no extra compile round trip.
> Concern: The check must compare items after following `pub import` chains, not spellings. If it compares spellings, the two re-export paths get E1005 by mistake.
>
> **Q3.1: YES**
> Reasoning: `blink explain E1005` already states this. The spec should match the text that models see.
> Concern: None of substance.
>
> **Q3.2: Q3.2-A**
> Reasoning: At a use, `db.connect()` has one spelling and two possible meanings. A silent rebinding produces errors in files the model did not touch. An eager E1005 at the import is cheap to read and fix.
> Concern: Until a follow-up puts declaration vs qualifier (`import db` + `type db`) under the same rule, the asymmetry stays: one more decision point to learn.
>
> **V1: YES**
> Reasoning: One mistake gives one diagnostic. Two diagnostics for one line make an agent do redundant fix steps.
> Concern: The implementation must suppress W0602 only on the colliding entry, not on the whole import line.
>
> **V2: YES**
> Reasoning: A fixed order gives stable output. Agents apply diagnostics in order, and the LSP shows them in that order.
> Concern: Spec text for the order may be over-specific for a rare triple collision.
>
> **V3: V3-b**
> Reasoning: A model copies a concrete name exactly, but the spec should not freeze a naming scheme. Devops's condition (the suggested name must not already be bound) prevents a help line that causes a new collision.
> Concern: Without any normative floor, an implementation might print "rename one", which a model cannot act on in one edit.
>
> **V4: YES**
> Reasoning: Two names that refer to one item bind no name twice, so this follows from C1.
> Concern: None.
>
> **V5: YES**
> Reasoning: The prelude is a nested scope, and W1010 already covers this case, help text included.
> Concern: None.
>
> **V6: YES**
> Reasoning: The global-map bug becomes directly testable against spec text.
> Concern: None.
>
> **V7: YES**
> Reasoning: The rule has to be readable where models learn `as`.
> Concern: None.

##### Minimalism

> # Minimalism: Phase C vote ([this spec ticket])
>
> **C (C1–C6): YES**
> - Reasoning: The six shared points are the one flat-scope rule from the earlier decision, applied to the bound name. The change adds no new concept. It corrects stale text (§10.1, the 4:1 location) and leaves the per-file scope already in the spec as it is.
> - Concern: The §10.1 rewrite could grow into a new paragraph. It should stay one sentence about selective imports.
>
> **Q1: Q1-A**
> - Reasoning: Q1-A needs no new code and no change to `blink explain`. It also keeps one fix policy per code: the E1012 fix is machine-applicable, and the E1005 fix is a suggestion only. Merging the codes would save one table row but make every tool look inside the diagnostic.
> - Concern: The name "Ambiguous import" now describes a duplicate, which can mislead readers, so the reworded Cause text has to carry the meaning.
>
> **Q2: Q2-B**
> - Reasoning: A binding is a pair of name and item. The same pair twice is not a duplicate, so the extra entry is just an unused import (W0602). This adds no rule and no code, and name resolution already follows `pub import` chains, so the identity check costs one ID comparison.
> - Concern: Someone may later read "identity after `pub import` chains" as license to add a separate identity pass. The spec should say it reuses the item name resolution already finds.
>
> **Q3.1: YES**
> - Reasoning: Two qualifiers with one spelling is the same rule in the qualifier layer, and `blink explain E1005` already says so. The spec only catches up.
> - Concern: None that matters. The cost is one row of examples.
>
> **Q3.2: Q3.2-A**
> - Reasoning: `X.y` is both module-qualified and type-qualified access, so qualifiers and bare names share one key space at the use site. Separate layers would need a precedence rule, which is a same-level shadow. One per-file table keyed on the bound name is the smaller model. My vote has a condition: the decision record must name a follow-up for a declaration against a module qualifier (`import db` + `type db`), so the import/declaration asymmetry is on record as temporary.
> - Concern: Without that follow-up, the spec keeps an asymmetry. `import db` + `type db` is legal, while `import db` + `import x.{T as db}` is an error.
>
> **V1: YES**
> - Reasoning: One mistake gives one diagnostic, the same as E1012. Two messages for one line make users and models do needless work.
> - Concern: Implementations may suppress W0602 too broadly, beyond that one entry.
>
> **V2: YES**
> - Reasoning: The declaration pair has a clear winner, so it resolves first. The order is deterministic and costs one sentence.
> - Concern: It adds ordering text that could grow into a general precedence section. Keep it to one sentence.
>
> **V3: V3-b**
> - Reasoning: A concrete, free name in the help is good practice, and every panelist already wrote one. A normative naming algorithm would freeze an implementation detail into the language spec. So the spec says "should" and fixes no scheme.
> - Concern: Over time, "should" text may be treated as normative anyway.
>
> **V4: YES**
> - Reasoning: Two names for one item binds no name twice, so this follows from C1 with no new rule.
> - Concern: None. At most one clause.
>
> **V5: YES**
> - Reasoning: W1010 already covers an imported name that shadows a compiler-known type, so no change is needed.
> - Concern: None.
>
> **V6: YES**
> - Reasoning: This restates existing text ("Aliases are local to the importing file") in one clause, and makes the global-map bug testable against the spec.
> - Concern: The restatement should stay one clause, not a new section.
>
> **V7: YES**
> - Reasoning: Readers learn `as` in Import Aliases, so the rule has to be visible there. It is one sentence.
> - Concern: None.

### Final Spec

```blink
import auth.{Error}
import db.{Error}                     // error[E1005]: `Error` is imported twice

import http
import http2 as http                  // error[E1005]: `http` is imported twice

import db
import auth.{Token as db}             // error[E1005]: `db` is imported twice

import auth.{Error}
import auth.{Error}                   // warning[W0602]: same item; machine-applicable delete
import auth.{Token, Token as AuthToken}   // OK: two names, one item
```

- Each file has its own binding table; bare names and module qualifiers share it.
- E1005 `AmbiguousImport`: two imports in one file bind one name to different items. The check uses
  the name after `as`, covers both namespaces and `import`/`pub import`, and runs at the import site
  whether or not the name is used. Primary span on the later import, secondary on the first.
- The fix is a suggestion only; help should print a concrete name not already bound in the file.
- Same item twice (after `pub import` chains): W0602 on the later entry, machine-applicable delete.
- E1005 replaces W0602 on the colliding entry. With a declaration also taking the name, E1012 goes
  on every colliding import entry first, and E1005 applies only between entries without E1012.
- An alias that is a compiler-known name stays under W1010.
- Spec: §10.1 *Qualified Access*, §10.5 *Imported Names*, *Import Errors*, *Import Aliases*;
  §5 *Ambiguity detection*; ERROR_CATALOG E1005.
