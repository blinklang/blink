[< All Decisions](../DECISIONS.md)

# Struct-vs-Variant Collision Reach — Design Rationale

The struct-vs-variant `NameCollision` (E0518) rule in §3.4 checked the whole program. §3.4 *Resolution order*
did not say where a struct type `Name` sits at a site `Name { ... }`, because E0518 made the pair of a struct
and a variant impossible. The earlier "Bare variant and value names" ruling gave value-vs-variant (E1016)
package reach, and it left the struct case to a follow-up. This ruling closes that follow-up.

## Summary

| Q | Question | Result | Vote |
|---|---|---|---|
| Q1 | Reach of struct-vs-variant E0518 | E0518 covers the package plus the prelude. An import entry that binds a struct named like a package or prelude variant is E0518 at the import entry; the fix is an alias. At `Name { ... }` a struct type in scope comes before a variant, and a hint never moves resolution past it. W1011 widens to a struct that hides a dependency variant | 6-0 |
| Q2 | Where the struct step is written | A new step in *Resolution order*, after Qualified and before Hint-directed | 6-0 |
| Q3 | How to suppress W1011 for a struct | `@allow(ShadowedVariant)` on the `type`; the `[lints]` table for an import entry | 6-0 |
| Q4 | An import entry that binds a value named like a package or prelude variant | E1016 at the import entry; the fix is an item alias | 6-0 |

The panel took one round of debate (Phase B). All six seats sent "ready to vote", all four questions passed 6-0,
and no Phase D was needed.

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated in
independent-proposal, debate, vote rounds. The ticket, verbatim:

> Full ID:  0n0q18
>   Title:    Spec: narrow struct-vs-variant NameCollision (E0518) from program-wide to package reach?
>   Status:   open (ready)
>   Priority: P2
>   Desc:     The struct-vs-variant NameCollision (E0518) rule in sections/03_types.md 3.4 checks the whole program. The bare-variant/value decision chose package reach for value-vs-variant (E1016) because a program-wide check lets a dependency's minor release break a downstream build. Should struct-vs-variant also narrow to the package (dependency pairs then resolve by scope or hint)? Raised by DevOps and AI/ML during the panel; out of scope there.

The text below is excerpted from each panelist's own text. `[...]` marks a cut inside a quote, and
`> *[example omitted]*` marks an omitted code block.

#### Phase A — Independent proposals

- **Systems** (`A_sys.md`):

> I support narrowing E0518 to the package (plus the prelude), the same split as E1016. Across packages, a struct
> in scope comes first. This is the type-level form of *Values come first*. The qualified form always reaches the
> variant. Label: **sys-1**. I also list sys-2 (do nothing) and sys-3 (use-site error) and give reasons to reject them.
>
> From my seat the deciding fact is this. The program-wide rule makes a package's validity depend on the whole
> dependency graph. This is worse than the E1016 case. With two third-party packages, one with `struct Foo` and one
> with variant `Foo`, the program fails to compile and the user owns neither declaration. The only fix is a fork.
> The runtime cost is zero both ways. All of the cost is in build health and in compiler invariants.

- **Web/Scripting** (`A_web.md`):

> I support narrowing E0518 to the package, for the same reason the panel gave for E1016. My test is
> "would a JS/Python dev understand this in 5 minutes". The answer is yes only when struct-vs-variant
> and value-vs-variant follow ONE rule. A user who has learned "values come first, my package must not
> clash with itself, dependencies are hidden by what I import" must not have to learn a second rule for
> structs. So web-1 copies the E1016 split onto structs, nearly word for word.

- **PLT** (`A_plt.md`):

> E0518 today checks the *pool* against *every struct of every module*. That check is wider than any site can see.
> It rejects a pair that no site can confuse (a struct in package `a`, a variant in package `b`, and no module
> that sees both), and it makes the program non-compositional: two packages that each type-check alone can fail
> to type-check together, and the error points into code that neither the user nor the dependency author can fix
> alone. That breaks the property we want from separate compilation: if each package is well-formed, the link of
> well-formed packages is well-formed. E1016 already gave up the program-wide reach for exactly this reason
> (DV-1). Structs are the same shape of problem and need the same answer.

- **DevOps** (`A_devops.md`):

> My test for a collision rule: the error must point at a line the user owns, and the user must be able to fix it
> from that line. Program-wide E0518 fails this test in two cases that E1016 already fixed for values:
>
> 1. **Dependency minor release.** My package has `type Status { code: Int }`. Package `jobs` 1.4.0 adds
>    `Job.Status { at: Int }`. My build breaks on `blink update`, and nothing in my code changed. Under semver,
>    adding a variant is a minor change (it breaks only exhaustive matches *on that enum*, which I may not have).
> 2. **Two dependencies collide with each other.** `pal` has `type Status { .. }`, `jobs` has `Job.Status`. Neither
>    is my code. Today the build fails with E0518 whose primary span is in `~/.blink/pkg/pal/...` and whose label is
>    in `~/.blink/pkg/jobs/...`. The help says "rename either the struct or the variant". The user can do neither.
>    The only fix is to fork a dependency or drop one. That is a toolchain bug wearing a diagnostic's clothes.

- **AI/ML** (`A_aiml.md`):

> My test for every option: can a model learn the rule from §3.4 alone, with no exceptions to memorize, and does
> the same code keep its meaning when a dependency changes? Today an AI that writes `type Point { x: Int, y: Int }`
> in its own package can get E0518 because some dependency it never imported has a variant `Point`. The model cannot
> predict that from the code it sees, and the fix ("rename either the struct or the variant") points at code the
> user does not own. That is the worst kind of error for code generation: non-local, and not fixable by the writer.

- **Minimalism** (`A_min.md`):

> The user never imports `std.time` or names `Duration` the struct. The primary span is in a stdlib file the user does
> not own. The same program with a variant `Request` compiles, only because `std.http_types` is not loaded. So whether a
> user's variant name is legal depends on which stdlib modules the build pulls in, through any path. That is the exact
> semver hazard that the bare-variant-value-names panel rejected for E1016 (decisions/bare-variant-value-names.md:678).
> It is worse here: with two dependencies, A (`type Config { ... }`, a struct) and B (`type Mode { Config, ... }`), the
> user owns neither declaration and has no fix except dropping a dependency.
>
> The current rule is not a conservative default. It is a global coupling. Removing it removes complexity.

##### Phase A options

All six seats proposed Option P (package reach, and a struct in scope comes before a variant): aiml-1,
sys-1, web-1, devops-1, min-1, plt-1. PLT and Systems also listed Option U (package reach, and a bare
`Name { ... }` with a scoped struct and a dependency variant both as candidates is E0519 at the site; plt-2,
sys-3). Option K keeps the program-wide check.

#### Phase B — Debate, round 1

One round. All six seats sent "ready to vote". The key shifts, by seat:

##### V1: the struct step covers `Name { ... }` only (sys, web, min, plt concede; aiml follows)

- *sys (B1):*

> **I concede to min-1 and devops-1.** My rule 3 said "`Name { ... }`, `Name(...)`, bare `Name`". That was wrong.
> min-1: "A struct is not callable and has no bare-name value form". I checked: 03_types.md:5860 says `(T)` is
> parenthesization and "For newtype wrapping, use a named struct", and the newtype in the spec,
> `type Errno { Errno(Int) }` (03_types.md:2086), is an enum, not a struct. So only `Name { ... }` can reach a
> struct. `Name` and `Name(...)` follow *Values come first* with no change.

- *web (B1):*

> **I concede to min-1 and devops-1.** My rule 3 listed `Name { ... }` / `Name(...)` / `Name`; that was
> wrong. min-1: "A struct is not callable and has no bare-name value form (`(T)` is parenthesization,
> 03_types.md:5860; a newtype is a named struct or a one-variant enum)". I checked 03_types.md:5860:
> "`(T)` in type or expression position is always parenthesization ... For newtype wrapping, use a
> named struct". So only `Name { ... }` can find a struct. `Name` and `Name(...)` keep *Values come
> first* unchanged.

- *min (B1):*

> I keep min-1, and devops-1 D5 and plt-1 agree: "Only the brace form `Name { ... }` is at stake. A struct has no bare
> form ... and no call form" (plt-1). web-1, sys-1 and aiml-1 say the struct step covers `Name`, `Name(...)` and
> `Name { ... }`. That text implies a struct can be found at `Name` or `Name(...)`. It cannot, so the extra spellings are
> a rule with no case. Worse, an LLM or a reader who sees "all three spellings" will assume `Point(1, 2)` or a unit
> struct `Marker` exists. Write the step for `Name { ... }` only, and add devops's one sentence: "A struct has no bare or
> call form, so `Name` and `Name(...)` follow *Values come first* unchanged." If Blink ever adds tuple or unit structs,
> that change must revisit this step anyway.

- *plt (B1):*

> I side with min-1 and devops-1: **only `Name { ... }`**. Quoting min-1: "A struct is not callable and has no bare-name
> value form (`(T)` is parenthesization, 03_types.md:5860...)". A typing rule must list exactly the forms where both
> judgments can derive. A struct has no introduction form at `Name` or `Name(...)`, so a step there is dead text. Worse,
> web-1/sys-1/aiml-1's wording "for all three spellings" invites a reader (or an LLM) to infer that `Name` alone can
> denote a struct type in expression position. It cannot. If a later panel adds a struct constructor call, that panel
> must extend the step, and it should have to say so.

- *aiml (B1):*

> My Phase A text "for all three spellings: `Name`, `Name(...)`, `Name { ... }`" was not precise. sections/03_types.md:5860
> says "`(T)` ... is always parenthesization" and points newtypes at a named struct. A struct has no bare value form and
> no call form, so only `Name { ... }` can find both a struct and a variant. I support devops-1 D5: one sentence that
> says `Name` and `Name(...)` never find a struct and follow *Values come first* unchanged. That sentence matters for
> a model: without it, a reader asks whether `Point(1, 2)` now means something, and guesses.

##### V2: sys, web, min, plt move to ORDER; devops moves to BINDINGS

- *sys (B1):*

> **I now support plt-1 / devops-1: a new step in the *Resolution order* list for `Name { ... }`, after Qualified
> and before Hint-directed.** I withdraw "a new step 3 in *Values come first*".

- *web (B1):*

> **I now support plt-1 / devops-1: a new step in *Resolution order*, after Qualified and before
> Hint-directed.** This follows from V1. *Values come first* covers "a bare use of `Name`, in an
> expression or in a call `Name(...)`" (03_types.md:1973). A struct never appears there, so putting it
> in that list (my web-1, sys-1) adds a step that never fires for two of the three spellings. The
> *Resolution order* list is already the list "at a bare struct-style construction site
> `Name { ... }`" (03_types.md:1965), which is exactly the one site a struct reaches. One list, one
> syntax, no "except" clauses.

- *min (B1):*

> I withdraw my "rename to *Bindings come first*". plt-1 and devops-1 put the struct step in the *Resolution order*
> list, which is the list for `Name { ... }` sites. That is the better place:

- *plt (B1):*

> I prefer the second only because *Resolution order* is the list that already governs `Name { ... }` (03_types.md:1965),
> so the reader of the brace form finds every step in one list. This is wording, not semantics.

- *devops (B1):*

> I concede to min-1 and aiml-1: put it in the *Values come first* list, not a new step in the *Resolution order* list
> as my D2 did.

- *aiml (B1):*

> From my seat the test is: one list, read once, gives the answer. min-1 ("A struct type in scope at the site ... is a
> binding in the type namespace") and my aiml-1 both keep a single scope list: local, module scope (value or struct),
> then variant. plt-1 and devops-1 put "Scoped struct" before "Hint-directed" in the *Resolution order* list. That
> gives the same result, but then the scope rule is in two lists: values in one, structs in the other. A model then
> has to merge two lists to find the order. I prefer the single list, under min's title. I will accept the plt/devops
> placement if the text keeps "A hint never moves resolution past it" in so many words.

##### V3: sys, plt, web, min correct devops on `@allow`

- *sys (B1):*

> **New evidence: devops-1 D3 rests on a false premise.** devops-1: "a `type` has no enclosing `fn` for `@allow`."
> The annotation table at sections/07_trust_modules_metadata.md (§11.1, line 2926) says:
>
> > `@allow(WarningName, ...)` | fn, type | ... | Suppresses the named warnings inside the annotated function, or
> > inside the type declaration and its body.
>
> The 03c_protocols.md:918 parenthesis ("`@allow` attaches to a `fn`") is about a method in an `impl`, and is not
> the full rule.

- *plt (B1):*

> devops-1 D3 says a `type` "has no enclosing `fn` for `@allow`". The digest quotes 03c_protocols.md:918
> ("`@allow` attaches to a `fn`"). Both are incomplete. **New evidence:** the annotation table at
> sections/07_trust_modules_metadata.md:2926 lists `@allow` targets as "fn, type": "Suppresses the named warnings inside
> the annotated function, or inside the type declaration and its body.

- *web (B1):*

> **devops-1 D3 is based on a stale fact.** devops-1: "because a `type` has no enclosing `fn` for
> `@allow`". The annotation table says otherwise, sections/07_trust_modules_metadata.md:2926:
> "`@allow(WarningName, ...)` | fn, type | ... Suppresses the named warnings inside the annotated
> function, or inside the type declaration and its body." The 03c_protocols.md:918 parenthetical
> ("`@allow` attaches to a `fn`") is about a method, where the `fn` is the right target; it does not
> say `@allow` attaches only to a `fn`.

- *min (B1):*

> New evidence: that is not what the spec says. The §11.1 attribute table, sections/07_trust_modules_metadata.md:2926:
>
> > `@allow(WarningName, ...)` | fn, type | ... | Suppresses the named warnings inside the annotated function, or
> > inside the type declaration and its body.
>
> 03c_protocols.md:918 ("`@allow` attaches to a `fn`") speaks about a method, so it is not a general limit.

- *devops (B1):*

> Keep D3: the `[lints]` table of `blink.toml` (§4.16.8). The digest's fact confirms the reason: "`@allow` attaches to a
> `fn`, §11.1" (sections/03c_protocols.md:918). A `type` declaration and an import entry have no enclosing `fn`, which
> is the same position as a module-scope `let`, and §10.6:2640 already sends that case to `[lints]`. Whether `@allow`
> should attach to a `type` or an import is a §11.1 question for all lints, not for this ticket. The spec text should
> name the suppression form in the W1011 paragraph so no one has to infer it.

##### V4: five seats fold the imported-value case; aiml keeps it for a separate ticket

- *sys (B1):*

> **Fold it into this edit, as its own line in the vote.** Reasons from my seat:
>
> - The spec sentence at 03_types.md:1979 ("A value that step 2 finds is never a variant of the same package") is
>   false for `import dep.{Red}` in a package that declares `Color.Red`, unless E1016 covers the import entry. Option
>   P writes the matching struct sentence ("a struct that step 2 finds is never a variant of the same package"), and
>   that one is true only because of the import-entry rule. If we fix the struct form and leave the value form, the
>   two parallel sentences in one section have different truth values. A compiler author who reads them will
>   assume they mean the same thing.
> - It is the same rule with the same fix (alias at the import), in the same paragraph. A separate ticket costs a
>   full panel for one sentence.

- *web (B1):*

> **Fold it in, as one sentence, with E1016 at the import entry.** Reasons:
>
> - The spec already claims it. 03_types.md:1979: "A value that step 2 finds is never a variant of the
>   same package or of the prelude, because that pair is E1016". Step 2 includes "an imported value"
>   (03_types.md:1977). Today that sentence is false for `import dep.{Red}` in a package with
>   `Color.Red`. This edit rewrites the paragraph next to it; leaving a known-false sentence beside the
>   new text is worse than fixing it.

- *plt (B1):*

> **Fold it in.** Reasons from my seat:
>
> 1. 03_types.md:1979 is a soundness claim the resolution order relies on: "A value that step 2 finds is never a variant
>    of the same package or of the prelude". Step 2 includes "an imported value". If `import dep.{Red}` in a package
>    that declares `Color.Red` is legal, the claim is false, and the rule "a bare name denotes exactly one entity"
>    then depends on an ordering the spec says cannot arise. A spec that states a false invariant is a bug, not a
>    friction item.

- *devops (B1):*

> Fold it in. The edit already adds "an import entry that binds a struct named like a package or prelude variant is
> E0518 at the import entry". The value twin is one clause: "an import entry that binds a value named like a package or
> prelude variant is E1016 at the import entry; the fix is an item alias." Reasons:
>
> - Without it, the line this edit rewrites next to, sections/03_types.md:1979 ("A value that step 2 finds is never a
>   variant of the same package or of the prelude, because that pair is E1016"), is false for `import dep.{Red}` in a
>   package with `Color.Red`. We would ship a spec edit that sits beside a false claim we know about.

- *min (B1):*

> Fold it into this edit. Reasons:
>
> 1. This edit rewrites the paragraph at 03_types.md:1979 anyway, to add the parallel struct sentence. If we add "a
>    struct ... is never a variant of the same package" and the struct rule covers import entries, while the value
>    sentence next to it stays false for `import dep.{Red}`, we publish two parallel claims where only one is true.
>    That is worse than both the fix and the status quo.

- *aiml (B1):*

> The value case amends the bare-variant-value-names ruling (DECISIONS.md:437 names "a module-scope
> `let`/`let mut`/`const`/`fn`"), so it needs its own vote; this panel should not widen a past ruling as a side effect.

##### Option U: plt withdraws plt-2

- *plt (B1):*

> I support **Option P**. I oppose Option K, as in Phase A. I withdraw plt-2 (Option U) as a live option for this
> ticket. It is fair only if fegp6p narrows the variant pool to enums in scope, and fegp6p is open. If fegp6p later
> narrows the pool, Option P stays sound under it: the scoped struct still comes first, and the pool only gets smaller.
> So no decision here blocks fegp6p.

- *min (B1):*

> Against K: my probe stands. gen1 rejects a user variant `Duration` with the primary span at lib/std/time.bl:190:5, and
> the program never imports `std.time`.

#### Phase C — Final vote

Each seat voted alone. Q1 to Q4 each passed 6-0. The votes and the reasoning of each seat follow, in full.

devops returned to ORDER (Q2) and to ALLOW-TYPE (Q3). In B1 devops had moved to BINDINGS and to LINTS. Its reasons,
from `C_devops.md`:

> **Reasoning:** In B1 I conceded to BINDINGS for the one-list argument. After V1 settled on the brace form only, the
> *Resolution order* list (03_types.md:1965) is the one that already governs `Name { ... }`, so a reader of that
> spelling finds every step in one place. plt's B1 shows the risk in BINDINGS: unless the text splits namespaces, "a
> binding comes first" lets a local `let Status = 5` hide `Status { ... }`. ORDER avoids that wording trap.

> **Reasoning:** I was wrong on the fact in D3. The annotation table (sections/07_trust_modules_metadata.md:2926) lists
> `@allow` on `fn` and `type`, and it suppresses warnings "inside the type declaration and its body". A suppression next
> to the declaration it covers is easy to find, and the LSP's "suppress this warning" quick fix can insert it in place.

##### Q1: Reach of struct-vs-variant E0518 — P, 6-0

- **Systems** — Vote: P

> **Reasoning:** With a check at package reach, the compiler can check each package once and cache the result with that package. A program-wide check must run again for each new set of dependencies. The program-wide check also rejects programs that no one can fix: min's probe shows a user enum with a variant `Duration` failing at lib/std/time.bl:190, which the program never imports. P costs nothing at run time and emits the same C for both spellings. It needs no new syntax.
>
> **Concern:** Typecheck and codegen today assume that struct names and variant names never overlap in the whole program (src/typecheck.bl:819, :11230; the tid-collapse notes at :3084). If some `StructLit` path still picks the enum from the global variant map, it will miscompile without an error. So the tests must include a pair across two packages, written in both spellings and with a hint.

- **Web/Scripting** — Vote: P

> **Reasoning:** P gives the rule a Python or JS dev already has: names I declare or import win over a library's names, and in my own package one name means one thing. It removes the error that points into code the user did not write. min's probe showed a user variant `Duration` failing at lib/std/time.bl:190 for a module the program never imports. It also uses the same package reach as value-vs-variant (E1016), so there is one rule to learn, not two.
>
> **Concern:** A user who writes `let s: Shape = Point { x: 1, y: 2 }` with their own struct `Point` gets a type error, not the variant. If the `help: write Shape.Point { ... }` line is left out of the implementation, this becomes a confusing error.

- **PLT** — Vote: P

> **Reasoning:** Package-plus-prelude reach makes the check compositional: packages that each type-check alone also
> type-check together, and a dependency's minor release can no longer break a downstream declaration. The scoped struct
> is a scope lookup that runs before the hint, so what kind of entity a name denotes never depends on inference. That
> keeps "a bare name at a site denotes exactly one entity, determined statically". It is the same rule as E1016, over
> the type namespace in place of the value namespace.
>
> **Concern:** If the compiler keeps tables keyed by bare name that assume a struct and a variant never share one
> (src/typecheck.bl:819, :11230), a cross-package pair could resolve one way in typecheck and another way in codegen.
> The implementation must key those tables by the resolved entity, and corpus tests must cover the dependency pair.

- **DevOps** — Vote: P

> **Reasoning:** Under P, every E0518 has its primary span in the user's package, and its help (rename, or alias the
> import) is an edit the user can make on that line. The LSP can attach a code action to it. K fails min's probe: the
> primary span lands in lib/std/time.bl for a program that never imports `std.time`. U still lets `blink update` break
> a build with no change in user code; it only moves the error to every bare site.
>
> **Concern:** The W1011 note must say that `Status` and `Status(...)` still mean the variant. If it does not, a user
> who sees `Status { ... }` build the struct will expect `Status(3)` to fail too, and will read a correct build as a bug.

- **AI/ML** — Vote: P

> **Reasoning:** Under P a model can predict every E0518 from the files of its own package and its own import lines,
> and the fix is always in code it owns. min's probe (a user variant `Duration` gets E0518 at lib/std/time.bl:190
> with no `std.time` import) shows that K teaches an error no reader of the spec can foresee. U moves the semver break
> to each use site, which gives more errors per dependency change, not fewer. P adds no syntax and no new decision
> point: "a name in scope comes before a variant" was already the rule for values.
>
> **Concern:** If the W1011 for a struct is easy to miss, a model may write `Point { ... }` meaning the dependency
> variant and get a type error at a hinted site; the `help: write \`Shape.Point\`` line must appear there in every
> case, or models will loop on that error.

- **Minimalism** — Vote: P

> **Reasoning:** P removes a global coupling and adds no syntax or code. It gives one reach rule (package plus prelude) for both E1016 and E0518, where today there are two. The gen1 probe shows that the program-wide check rejects correct user code because of a stdlib struct the user never imported, with the error span in lib/std. U moves that same semver break to every use site.
>
> **Concern:** A struct that hides a dependency variant whose enum the module does not import gets no W1011, so a user who expected the variant gets a type error, with the `help:` line only when a hint names the enum.

##### Q2: Where the struct step is written — ORDER, 6-0

- **Systems** — Vote: ORDER

> **Reasoning:** One ordered list per syntactic form gives one lookup order per AST node kind, and the compiler will be built in that shape. The brace form reads the type namespace and the other forms read the value namespace. Putting a struct clause in the shared *Values come first* list mixes two lookups that never apply at the same site. Other sections cite that heading (02_syntax.md:942, 07:2616), so renaming it is churn with no change in behavior.
>
> **Concern:** The *Resolution order* list and *Values come first* could drift apart, so each must say which syntactic form it governs.

- **Web/Scripting** — Vote: ORDER

> **Reasoning:** All panelists agree that only `Name { ... }` can find a struct, and plt notes that a local `let` never hides the brace form. So the brace form already has its own list, *Resolution order* (03_types.md:1965), and a user who asks "what does `Point { ... }` mean here" should find the full answer in that one list. A merged *Bindings come first* list would need an "only for the brace form" clause on the struct step and an "except the brace form" clause on the local step, and that is harder to read than two short lists that each cover one syntax. I also prefer to keep the word "values": users read "binding" as "variable", not "type".
>
> **Concern:** If BINDINGS wins, the merged list must still say plainly that a local `let Point = ...` does not change what `Point { ... }` means, or users and the LSP will read the list in the wrong order.

- **PLT** — Vote: ORDER

> **Reasoning:** *Resolution order* is the list that already governs `Name { ... }`, and the brace form is the only
> spelling that can reach a struct (V1). So a step there fixes the gap in one place, with no namespace split to explain.
> BINDINGS has the same meaning, but it puts a type-namespace clause into a list that mostly reads the value namespace.
> A reader must then learn that the local step does not apply to the brace form.
>
> **Concern:** The *Values come first* list and the new step must cross-reference each other. If they do not, a reader
> of one list will not know that `Name { ... }` has a step the other list lacks.

- **DevOps** — Vote: ORDER

> **Reasoning:** In B1 I conceded to BINDINGS for the one-list argument. After V1 settled on the brace form only, the
> *Resolution order* list (03_types.md:1965) is the one that already governs `Name { ... }`, so a reader of that
> spelling finds every step in one place. plt's B1 shows the risk in BINDINGS: unless the text splits namespaces, "a
> binding comes first" lets a local `let Status = 5` hide `Status { ... }`. ORDER avoids that wording trap. It is also
> my own placement from devops-1 D2.
>
> **Concern:** *Values come first* and *Resolution order* must cross-reference each other, or a reader of one list will
> miss the step in the other.

- **AI/ML** — Vote: ORDER

> **Reasoning:** I change my vote from BINDINGS. plt's B1 point settles it: the brace form reads the type namespace and
> `Name`/`Name(...)` read the value namespace, so a local `let Point` never hides `Point { ... }`. If one *Bindings come
> first* list held both, a model would read "local, then module scope, then variant" and wrongly apply the local step
> to the brace form. A step in the `Name { ... }` list that says exactly which names it finds is the smaller rule to
> learn.
>
> **Concern:** The sentence "a hint never moves resolution past it" must sit inside that list next to the new step;
> if it stays only under *Values come first*, a reader may think the hint step outranks the struct.

- **Minimalism** — Vote: ORDER

> **Reasoning:** Only `Name { ... }` can reach a struct, and *Resolution order* is the list for that spelling. So the new step changes one list and leaves the decided *Values come first* text word for word. It also keeps plt's split with no extra words: the brace form reads the type namespace, so a local `let Status` can never hide `Status { ... }`. I withdrew my BINDINGS rename in B1 for these reasons.
>
> **Concern:** The two lists sit next to each other, and a reader may think that *Values come first* also applies to `Name { ... }` unless the struct step says it decides before the hint and the variant pool.

##### Q3: How to suppress W1011 for the struct case — ALLOW-TYPE, 6-0

- **Systems** — Vote: ALLOW-TYPE

> **Reasoning:** The annotation table (07_trust_modules_metadata.md:2926) already lets `@allow` attach to a `type`, so this adds no new form. Suppression next to the declaration is narrow and stays with the code that chose the name. A `[lints]` entry would turn the warning off for the whole package. An import entry has no annotation site, so it falls back to `[lints]`, the same as a module-scope `let`.
>
> **Concern:** 03c_protocols.md:918 says "`@allow` attaches to a `fn`", which a reader can take as the full rule, so the W1011 paragraph must name both forms in plain words.

- **Web/Scripting** — Vote: ALLOW-TYPE

> **Reasoning:** The annotation table (07_trust_modules_metadata.md:2926) already lets `@allow` attach to a `type`, so the user puts the allow on the line that warns, which is what every linter they know does. A rule of "`[lints]` only" would send them to `blink.toml` for a warning on one declaration, and that will become a "how do I silence this" question. An import entry has no annotation site, so `[lints]` (or an alias) for that case is correct.
>
> **Concern:** The 03c_protocols.md:918 parenthetical ("`@allow` attaches to a `fn`") reads like a general rule. If the edit does not reword it, it will keep misleading readers, as it misled one seat here.

- **PLT** — Vote: ALLOW-TYPE

> **Reasoning:** The annotation table (07_trust_modules_metadata.md:2926) already lists `type` as an `@allow` target,
> "inside the type declaration and its body". So `@allow(ShadowedVariant)` on the struct is the existing rule, not a new
> one, and it records the author's choice at the declaration. An import entry has no annotation site, so `[lints]` is the
> only control there, as for a module-scope `let`.
>
> **Concern:** "Inside the type declaration and its body" must clearly cover a warning whose span is the type's own name.
> If it does not, the spec text needs one clause that says so.

- **DevOps** — Vote: ALLOW-TYPE

> **Reasoning:** I was wrong on the fact in D3. The annotation table (sections/07_trust_modules_metadata.md:2926) lists
> `@allow` on `fn` and `type`, and it suppresses warnings "inside the type declaration and its body". A suppression next
> to the declaration it covers is easy to find, and the LSP's "suppress this warning" quick fix can insert it in place.
> An import entry has no annotation site, so `[lints]` covers it, the same as a module-scope `let`.
>
> **Concern:** "Inside the type declaration and its body" must cover a warning on the type's own name. If it does not,
> the quick fix inserts an `@allow` that has no effect.

- **AI/ML** — Vote: ALLOW-TYPE

> **Reasoning:** sections/07_trust_modules_metadata.md:2926 already says `@allow` attaches to "fn, type", so
> `@allow(ShadowedVariant)` on the `type` is the existing rule, not a new one. The suppression then sits on the line
> that chose the name, which is where a model (and a reviewer) looks. An import entry has no annotation site, so
> `[lints]` for that case is the only option and matches the module-scope `let` case.
>
> **Concern:** The W1011 paragraph at 07:2640 must name both forms in so many words, or models will copy the
> `[lints]`-only pattern from the module-scope `let` text and miss the `type` form.

- **Minimalism** — Vote: ALLOW-TYPE

> **Reasoning:** The §11.1 table (07_trust_modules_metadata.md:2926) already lets `@allow` attach to a `type`, so this uses an existing mechanism and adds nothing. A project-wide `[lints]` switch is too wide for one deliberate name choice. For an import entry, which has no annotation site, `[lints]` or an alias is the only route, and ALLOW-TYPE already says so.
>
> **Concern:** The W1011 text at 07:2635 must name the `type` form, or readers will keep repeating the "`@allow` attaches to a `fn`" claim from 03c_protocols.md:918.

##### Q4: An import entry that binds a value named like a package or prelude variant — FOLD, 6-0

- **Systems** — Vote: FOLD

> **Reasoning:** This edit writes a sentence for structs that matches 03_types.md:1979 for values. Without FOLD, the struct sentence is true and the value sentence is false, and a compiler author will read them as one rule. It is the same rule, with the same fix (an alias) and the same span (the import entry). The earlier panel's Phase A text already meant the import case to be an error. The ruling row names only declarations, so this closes a gap and does not reverse that ruling.
>
> **Concern:** aiml's point that this widens a past ruling as a side effect is fair, so the decision record must name the amended row (DECISIONS.md:437) in plain words.

- **Web/Scripting** — Vote: FOLD

> **Reasoning:** The spec already claims this, at 03_types.md:1979 ("A value that step 2 finds is never a variant of the same package"), and step 2 includes imported values. This edit rewrites the paragraph next to that sentence. If an imported struct `Red` is an error but an imported `fn Red` silently hides `Color.Red`, users learn two rules for one situation. The semver reason behind the earlier ruling still holds: the error is on an import entry in the user's own file, so a dependency can never trigger it.
>
> **Concern:** aiml is right that this widens a past ruling (DECISIONS.md:437). The decision record must say so plainly and list the amended row, so that no one later reads E1016's reach from the old ruling alone.

- **PLT** — Vote: FOLD

> **Reasoning:** 03_types.md:1979 states an invariant that the resolution order depends on: a value that step 2 finds is
> never a variant of the same package or of the prelude. Step 2 includes imported values, so without this clause the
> invariant is false today. Q1 adds the import-entry rule for structs. If values stay out, the two namespaces get two
> rules with no reason for the difference.
>
> **Concern:** A downstream package that today imports a dependency value named like its own variant will break at the
> import entry. The diagnostic must give the alias fix (`import dep.{Red as DepRed}`) as machine-applicable.

- **DevOps** — Vote: FOLD

> **Reasoning:** This edit rewrites the text next to 03_types.md:1979. With TICKET, that text keeps a claim we know is
> false for `import dep.{Red}` in a package that declares `Color.Red`. The diagnostic has the same shape as the struct
> import case (primary span on the import entry, note at the variant, alias help), so tooling builds one pattern for
> both. E1016 is the right code: it is the value-vs-variant code at package reach, whatever binds the value.
>
> **Concern:** The implementer may reuse E1012 for the import case because it already handles import entries. The spec
> text must name E1016 explicitly.

- **AI/ML** — Vote: FOLD

> **Reasoning:** I change my vote from TICKET. The other five seats show it is not a new direction: the earlier panel's
> own Phase A text (decisions/bare-variant-value-names.md:382) assumed the import case, and the ruling's §3.4 text at
> 03_types.md:1979 already depends on it. From my seat the decisive point is that P would otherwise make an imported
> struct named `Red` an error while an imported `fn Red` silently hides `Color.Red`, two rules where one does. A model
> learns "an import entry that takes a package or prelude variant's name is an error, fix it with an alias" once, for
> both namespaces.
>
> **Concern:** The value case gets E1016 and the struct case E0518 for one shape of mistake; the help text and span
> of the two must read the same, or the split code looks like two rules to a model.

- **Minimalism** — Vote: FOLD

> **Reasoning:** This edit rewrites the paragraph at 03_types.md:1979. If we add a struct sentence that is true for import entries next to a value sentence that is false for them, the spec makes two parallel claims and only one holds. It is the same reach rule in the value namespace. It is semver-safe because a dependency cannot add an import entry to the user's file. aiml says a past ruling needs its own vote: this ballot line is that vote, by the full panel.
>
> **Concern:** I have not probed the cross-package value case in gen1. The implementer must add a two-package test for it, or the rule stays text only.

#### AI-first review

1. Learnability — PASS. One ordered list per form; scoped names come before the ambient variant pool.
2. Consistency — PASS. E0518 now has the same reach as E1016; the import-entry errors match E1012's span shape.
3. Generability — PASS. A model writes `Point { ... }` and gets the scoped struct.
4. Debuggability — PASS. Every error lands in the user's package with an alias or qualify fix.
5. Token efficiency — PASS. No new syntax; the fix is an alias or a qualifier.

0 of 5 fail. No flags.

### Final Spec

```blink
// package app; package geo declares `pub type Shape { Point { x: Int, y: Int }, Circle { r: Int } }`
// package pal declares `pub fn Red() -> Int`
import geo.{Shape}

type Point { x: Int, y: Int }     // warning[W1011]: struct `Point` hides variant `Shape.Point`

fn main() {
    let a = Point { x: 1, y: 2 }                // the struct `Point`
    let b: Shape = Point { x: 1, y: 2 }         // error[TypeError]: declared type Shape but got Point
                                                // help: write `Shape.Point { ... }` for the variant
    let c: Shape = Shape.Point { x: 1, y: 2 }   // the qualified form always reaches the variant
}
```

```blink
// package app declares `type Color { Red, Green }` and `type Shape { Point, Line }`
// package pal declares `pub fn Red() -> Int`; package geo declares `pub type Point { x: Int, y: Int }`
import pal.{Red}                  // error[E1016]: `Red` collides with variant `Color.Red`
                                  // help: import pal.{Red as PalRed}
import geo.{Point}                // error[NameCollision] (E0518): `Point` collides with variant `Shape.Point`
                                  // help: import geo.{Point as GeoPoint}
```

- E0518 covers the package plus the prelude, not the whole program. A dependency enum's variant never gives E0518 (§3.4 *Name collisions*).
- An import entry that binds a struct named like a package or prelude variant is E0518 at the import entry. The fix is an alias.
- At `Name { ... }`, a struct type in scope (declared in the module or bound by an import entry) comes before a variant. A hint never moves resolution past it (§3.4 *Resolution order*).
- *Resolution order* governs `Name { ... }`. *Values come first* governs `Name` and `Name(...)`. A struct has no bare or call form, so those two spellings never find a struct. A local `let` never changes what `Name { ... }` means.
- Patterns do not change: the scrutinee type decides.
- W1011 covers a struct that hides a dependency variant, with the existing trigger (the module imports the variant's enum through an import entry that names it). Only the dependency case can occur, because the same-package and prelude pairs are E0518.
- W1011 for a struct: `@allow(ShadowedVariant)` on the `type` (it covers a warning on the type's own name); the `[lints]` table for an import entry (§10.6 *Shadowing Rules*).
- A type error at `Name { ... }`, where a struct in scope hid the hinted variant, gets a `help:` line that names the qualified variant, for example `Shape.Point { ... }`.
- An import entry that binds a value (`let`, `const` or `fn`) named like a package or prelude variant is E1016 at the import entry, not E1012. The fix is an item alias (§2.12.1).

This ruling amends the "Bare variant and value names" row of DECISIONS.md (the row that rules E1016 for a module-scope `let`/`let mut`/`const`/`fn` and gives the declaration form only). It adds the import-entry case to E1016. The earlier panel's own Phase A text had already assumed the import case, and §3.4 *Values come first* depends on it.

Governing text: §2.12.1, §3.4 *Resolution order*, *Values come first* and *Name collisions*, §10.6 *Shadowing Rules*, §11.1, `ERROR_CATALOG.md` (E0518, E1016).

### Implementation notes

1. Impl: E0518 package reach; import-entry E0518/E1016; struct step in StructLit path only; tables keyed by resolved
   entity (src/typecheck.bl:819, :11230; tid-collapse map :3084, :3162); W1011 struct case; help line; explain text
   (src/diagnostics.bl:1458) rewritten for the new reach; two-package corpus tests.

Binding concerns from Phase C:

- (sys, plt) The implementation keys its tables by the resolved entity, not by the bare name. The corpus gets a test with a cross-package pair, in both spellings, with a hint.
- (web, aiml) A hinted type error at `Name { ... }` where a scoped struct hid the hinted variant gets a `help:` line that names `Shape.Point { ... }`.
- (devops) The struct W1011 note says that `Name` and `Name(...)` still mean the variant.
- (min) No W1011 when the variant's enum is not imported. The help line at hinted sites covers that case. A two-package test covers the imported-value case.
- (plt) The alias fix is machine-applicable. (aiml) The E0518 and E1016 import diagnostics read the same (span, help).

### Known gaps and follow-ups

1. 6xcq94 (sum type named like a variant) should take the same package reach.

2. fegp6p (variant pool limited to enums in scope): P stays sound under it (plt B1).
