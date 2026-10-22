[< All Decisions](../DECISIONS.md)

# A Type Named Like a Variant — Design Rationale

A `type Red { A, B }` and a variant `Color.Red` can live in one program. The type is in the type namespace.
The variant is in `Color`'s `T.` namespace. A bare `Red` has one meaning at every site, but the dotted head
`Red.x` has two readings, and the spec had no rule for it. This ruling states the rule for the dotted head, decides
whether the pair is an error, and decides when the declaration gets a warning.

## Summary

| Q | Question | Result | Vote |
|---|---|---|---|
| Q1 | An enum (or alias, trait, effect) named like a variant of another enum: error (E) or legal (L) | **Tied.** E: web, devops, aiml. L: sys, plt, min. The owner broke the tie for L, amended: a type named like a variant is legal; a bare variant named like a type in scope is E0554; E0518 stays on the brace form | 3-3 after Phase D |
| Q2 | Reach of E over the type namespace (counts only if E wins Q1) | V1-all: struct, enum, alias, trait, effect. No spec text on this branch | 5-1 (min: V1-data) |
| Q3 | W1011 for a type that hides a variant at a dotted head | W2: at the type declaration, once for each hidden variant of a different enum; a dependency variant counts only when an import entry names its enum (the own-enum exemption of the vote is void: a variant with its enum's name is E0518) | 6-0 after Phase D |
| (agreed in Phase B) | Dotted head order; no fallback; own variant; scope; help lines | See Final Spec | no vote; no seat objected |

**Result:** Q1 tied 3-3 after Phase D; the owner broke the tie for L, amended (see *Owner tiebreak and amendment*).

**Owner tiebreak:** L, amended.

### Owner tiebreak and amendment

The owner's words, verbatim:

> "I would say: type Color { Red, Green } / type Red { A, B } is legal. And type Color { Red, Green } / Red <-- bad / Color.Red <-- okay. does that hold up?"
>
> "every bare is illegal"
>
> "Doesn't JsonValue.Bool need to be prefixed anyways to not conflict with builtin Bool?"

Reading: the type `Red` stays legal beside the variant `Color.Red` (L). A bare variant named like a type in scope is an error in an expression, so `Red` is bad and `Color.Red` is fine. The rule covers builtin and prelude types: `JsonValue.Bool` needs its prefix because of the builtin `Bool`. The new error is `VariantNamedLikeType` (E0554).

Scope, asked of the owner afterwards: "every bare is illegal" was said about this ticket's case, not as a rule for every position. The owner chose:

- **Expressions only.** `let c = Red` and `let c: Color = Red` are E0554; an expected type does not make the bare form legal. A pattern still finds its variant from the type of the matched value (§3.5), so `match c { Red => ... }` stays legal.
- **Builtin and prelude types count.** `Bool(true)` as a `JsonValue` variant is E0554; write `JsonValue.Bool(true)`.

The newtype panel (decisions/newtype.md, 6-0) made a variant with the name of its own enum an error, E0518 at the declaration (`type Token { Token(Str), End }`). So the own-enum case cannot occur, and the own-enum exemptions in the Q3 vote and in Phase B ("Own variant") no longer apply. The panelist quotes below stay as they were written.

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated in
independent-proposal, debate, vote rounds. Phase D was one extra round on Q1 and Q3. The ticket, verbatim:

> Title: Spec: sum type named like a variant of another enum (type Red vs Color.Red)
> Desc: A sum type named Red (type Red { A, B }) in one module and a variant Red of another enum (type Color { Red, Green }): the type name is in the type namespace, the variant in Color's T. namespace. Is a bare `Red` in an expression/pattern ambiguous, and does E0518 NameCollision (struct vs variant) extend to sum types? The spec names only struct vs variant. Raised by AI/ML during the bare-variant/value panel; out of scope there.

The text below is excerpted from each panelist's own text. A quote is a whole paragraph or a whole line of the
panelist's file. Heading lines in a quote show as bold text.

#### Phase A — Independent proposals

First choices: E for sys, web, devops and aiml; L for plt and min. Each seat gave its first choice and ranked the rest.

- **Systems** (`A_sys.md`): first choice E (P1: extend E0518 to enum types, same reach)

> The meaning of `Red.x` must be static and local, and must not depend on the members of `Red`. If a new `impl Label for Red` can change what `Red.label()` means, that is the C++ argument-dependent-lookup trap. No option has a runtime or layout cost.
>
> (a) An enum type named like a variant of a *different* enum of the package or the prelude is E0518. Same reach as the struct rule: package, prelude variants count in every module, a dependency variant never collides, an import entry that binds such a type is E0518 at the entry, fix is an alias. I extend it to every type-namespace name (alias, trait, effect): one rule, one set check per package.
>
> Tradeoff: P1 rejects a program that works today (F4). But it keeps the E0518 promise ("no path silently picks a winner") true for every type name, and the check is cheap. Without it, D picks the type over a package variant silently.

- **Web/Scripting** (`A_web.md`): first choice E (Proposal 1: extend E0518 to every type name, same reach, own enum exempt)

> Today `Red.label()` (F6) has two meanings, one silent pick, and an arity error that names neither. A JS/Python developer cannot see why.
>
> (a) A `type` (struct **or enum**) or a type alias named like a variant of **another** enum is E0518 `NameCollision` at the declaration. An enum with a variant of its own name (F8, `type Token { Token(Str), End }`) stays legal.
>
> Trait and effect: I leave them out. A trait or effect name is not a constructible thing and does not head a value the user builds. If the panel finds a case where `Trait.x()` heads a dotted call, add them with the same reach — but I want proof of a real case first (YAGNI).

- **PLT** (`A_plt.md`): first choice L (Proposal A: legal, plus a static path-head rule)

> So the ticket's question "is bare `Red` ambiguous?" has the answer no. The only real overlap is the path head, and the spec has no rule for it (F6). That is the gap to close. A declaration error is a blunt tool for a gap that sits in one position.
>
> **(a)** An enum type (and an alias, trait or effect) named like a variant of another enum, or of its own enum (F8), is legal. No diagnostic at the declaration.
>
> The rule must be **no fallback**: if `m` is not in `Red.`, the site is an error. It must not retry as a value. A fallback makes the meaning of `Red.label()` depend on whether some impl anywhere in the package adds `label` to `Red.`. Adding a declaration would then silently change the meaning of an old site. That breaks the property "resolution is static; a bare name at a site denotes exactly one entity" (03_types.md:2051). It also breaks monotonicity under extension, which matters for separate compilation. With type-first and no fallback, the reading is decided from the type namespace alone, before typing.

- **DevOps/Tooling** (`A_devops.md`): first choice E (Proposal 1: one E0518 rule for every type name, own enum exempt, plus a dotted-head order)

> My test: a reader, an LSP hover, and a `help:` line must all give the same one answer for `Red`, without a search of the whole program.
>
> **(a) Rule.** Widen E0518 from "struct" to "any type-namespace declaration": `type` (struct or enum), alias, `trait`, `effect`. A type-namespace name equal to a variant of **another** enum is E0518. A variant of the type's **own** enum is legal (F8).
>
> Why exempt the own enum: `Token(...)` and `Token.End` never compete. The bare `Token` is a constructor, the dotted `Token.` is the type. Haskell, OCaml and Rust newtype-style wrappers use this shape a lot, and AI writers will copy it. An error there gives friction with no gain.

- **AI/ML** (`A_aiml.md`): first choice E (Proposal A: extend E0518 to every type-namespace name, same reach, own variants exempt)

> A model writes `Red.x` from memory of the enum's name. It does not check every enum in the package for a variant `Red`. So the safe design is to stop the pair at the declaration, where one edit fixes it, and not at each use.
>
> **Rule.** Within one package, a `type` (struct or enum), alias, `trait` or `effect` must not have the name of a variant of another enum of the package or of the prelude. Same reach as E0518 and E1016: package, prelude counts in every module, a dependency variant never collides, an import entry that binds such a type is E0518 at the entry, fix is an alias.
>
> The rule is fixed and local: the type namespace wins at a dotted head, as it does at `Name { ... }` (struct step). The help line gives the model the exact text to paste.

- **Minimalism** (`A_min.md`): first choice L (Proposal 1: legal, plus one dotted-head rule)

> Bare `Red` is never a type (F2); patterns read the type at that position; type positions read only the type namespace (F12); an enum has no brace literal (F11). Only `Red.x` / `Red.x()` has two readings (F6). One site shape needs one sentence, not a declaration error.
>
> (a) An enum type named like a variant is legal: of another enum, of its own enum (F8), in any module or package. Alias, trait and effect names are legal for the same reason.
>
> The compiler does this today (F4, F6, F9). No reach, import-entry rule or alias fix is needed: nothing is a declaration error.

##### Phase A options

- **E** — extend E0518 to type-namespace names, same reach as the struct rule, own variants exempt (sys, web, devops, aiml).
- **L** — legal everywhere: the dotted-head rule plus the help lines, no new error (plt, min). Second choices: sys, web, devops, aiml.
- Ranked below by their authors: ban every type and variant pair, own variants too (aiml); E0518 for enums only (devops); do nothing (web, min).

#### Phase A.5 and Phase B — Dedupe and debate, round 1

One round. All six seats sent "ready to vote". The moderator listed the points that every seat raised (no vote unless a seat objected), and six variations:

> - A bare `Red` and `Red(...)` keep one meaning today; the only site with two readings is the dotted head `Red.x` / `Red.x()` (sys, web, plt, devops, aiml, min).
> - At a dotted head, a name in the type namespace comes before a bare variant: `Red.x` is a type path when a type `Red` is in scope. To reach a member of the variant value, write the qualified form (`Color.Red.label()`) (all six).
> - An enum with a variant of its own name (F8, `type Token { Token(Str), End }`) is legal (all six).
> - `help:` lines on the existing errors of F5 (`let x: Red = Red`) and F6 (`Red.label()` arity) that name the qualified variant (all six).
> - F7 (the ICE) is a compiler bug, not spec (all six).

> - **V1 Which type-namespace names E covers.** sys, devops, aiml: struct, enum, alias, trait, effect. web: "Trait and effect: I leave them out. [...] I want proof of a real case first (YAGNI)."
> - **V2 A value binding at a dotted head.** sys: "1. a local binding, or a module-scope value [...] 2. a type in scope [...] 3. a variant". devops: "local binding, module-scope value, type, variant". min: "a value binding named `Name` (a local, or a module-scope value) decides first. If none, a name in the type namespace decides". plt: "if `Name` is in the type namespace at the site, `Name.m` names the member `m` of `Name`'s `T.` namespace. It never reads `Name` as a bare value." web and aiml state type-first without naming the value step. Does a local `let Red = ...` decide `Red.x` before the type?
> - **V3 No fallback on the member set.** plt: "The rule must be **no fallback**: if `m` is not in `Red.`, the site is an error. It must not retry as a value." sys: "The compiler never looks at the member set to choose." Others silent.
> - **V4 W1011 for a type that hides a variant at a dotted head.** sys and devops (under E): W1011 when a type hides a dependency variant. Under L, min gives no warning; plt gives none. Is there a warning, and for which cases?
> - **V5 A unit variant named like its own type** (`type Unit { Unit }`): `Unit.x` is the type path; write `Unit.Unit.x()` (sys, web, aiml). Others silent.
> - **V6 Scope of the dotted-head rule.** aiml: "the dotted head rule must cover `fn T.name` and `const T.X` too, since they share the `T.` namespace."

The key shifts, by seat:

##### Q1: sys moves from E to L

- *sys (B1):*

> plt and min convinced me. My P1 reason was "no path silently picks a winner". But under the dotted-head rule the pick is static, and in practice a wrong pick gives an error, not a silent wrong program: `Red.label()` as a type path has the wrong arity (F6), and a missing member is an error (V3). For a silent misread, `Red.` must hold a member with the same name and the same call shape as a method on `Color.Red`. That is rare. plt is correct that E needs the dotted-head rule anyway for dependency variants, so E adds a check and an exemption but no soundness. E is still acceptable to me as a second choice.

##### V2: value first. plt concedes

- *plt (B1):*

> - **V2: I change my position.** I accept value → type → variant (sys, devops, min). My Phase A text said "It never reads `Name` as a bare value", and I based it on the brace form. That was wrong. `Name { ... }` has no reading as a value, but `Name.m` does: field access on a value is the main use of `.`. Lexical scope must decide first. A local or module value is visible in the file, so the order stays local and static. I keep this part: the head never reads as a *variant* while a type has the name.

- *sys (B1):*

> **V2 — value binding at a dotted head: value first**
> I keep: local, then module-scope value, then type, then variant. plt quotes the brace form ("a local `let` never changes what `Name { ... }` means"). That precedent does not carry: `Name { ... }` has no value reading at all, but `x.len()` on a local is the most common dotted head in the language. If a module-scope type beats a local, then `let Red = load()` then `Red.len()` reads as a type path, so an outer scope hides an inner one. That inverts lexical scope, and the reader cannot see the cause at the site. The value step costs nothing.

- *aiml (B1):*

> **V2: value first, then type, then variant (sys, devops, min).** plt cites the brace form: "a local `let` never changes what `Name { ... }` means." That precedent does not carry. A value can never take a brace literal, so the brace form has no value reading to rank. A dotted head does have one (F3: `Green.label()`). TS, Python, JS and Kotlin all let a local hide a class at `Name.member`, so models will expect that order. It also keeps one rule: the same first two steps as *Values come first*. A local named like a variant already gets W1011, so the case is marked.

##### V3: no fallback on the member set

- *plt (B1):*

> - **V3: yes, and it must be written into the rule.** The head decides the reading before the members are looked at. If `m` is not in that reading, the site is an error, with no retry. Without this, adding an impl in any module changes old sites, so resolution is not stable when code is added. sys says the same thing.

- *devops (B1):*

> **V3: no fallback. Agree with plt and sys.** For the LSP, a fallback means one new `impl` changes the meaning of sites in other files. That breaks incremental re-check: the server must re-resolve every dotted head in the package on each impl edit.

##### V1: web gives up its YAGNI point

- *web (A):*

> Trait and effect: I leave them out. A trait or effect name is not a constructible thing and does not head a value the user builds. If the panel finds a case where `Trait.x()` heads a dotted call, add them with the same reach — but I want proof of a real case first (YAGNI).

- *web (B1):*

> **V1: concede to sys/devops/aiml.** Under E, take every type-namespace name. "In a package, a name is a type or a variant, never both" is one sentence a user learns once. A list of "struct, enum, alias but not trait" is a rule a user must look up.

##### V4: W1011 under L

- *plt (B1):*

> - **V4: W1011 under L too.** A type that hides a variant of a different enum at a dotted head gets W1011 at the type declaration. This covers package, prelude and dependency variants. Own-enum variants are exempt. This is how the spec treats a value that hides a variant and a struct that hides a dependency variant: the shadow is legal, and a warning marks it. It also answers web's "trap in the first five minutes" with no new error. Fix: rename, or `@allow`.

- *min (B1):*

> - **V4.** No W1011 in L or E. Under L it would fire at most type declarations that match a dependency variant, mostly where `Red.x` is never written for the variant. The help line at the error is enough. A warning with no wrong site is noise.

##### V5 and V6

- *sys (B1):*

> `Unit.x` is the type path; write `Unit.Unit.x()`. It follows from the rule with no exception.

- *sys (B1):*

> Agree with aiml. They are members of `T.`, so "type path" covers them. The spec text should say "a member of `Name`'s `T.` namespace: a variant, a `fn T.name`, a `const T.X`, or a trait's associated function".

##### Moderator fact on a value and a type of one name

> - sections/02_syntax.md:904 puts `let`/`let mut`/`const`/`fn` in the value namespace and `type`/alias/`trait`/`effect` in the type namespace, each bare name with at most one declaration per namespace. So a module-scope `const Red` and a `type Red` in one module are legal today; no rule (E1012, E1016, E0518) covers that pair. Under V2, `Red.x` there reads the const.

devops (C) and plt (B1) asked about this pair. Both treat it as a gap of the same kind, outside this ruling:

- *plt (B1):*

> Side point, out of scope: a module-scope `const Red` and a `type Red` in one module. Under V2, the const hides `Red.A`. The moderator should check if E1016 or E1012 already covers this pair. If not, file friction.

- *devops (C):*

> **Note on the moderator fact**
> A module-scope `const Red` beside `type Red` makes `Red.x` read the const under V2, with no diagnostic. That is a separate gap (value vs type of one name at a dotted head); it should get a friction ticket, not a change to this vote.

#### Phase C — Vote

Each seat voted alone. Agreed by all six in Phase B (no vote), verbatim from the ballot:

> - V2: at a dotted head `Name.x` / `Name.x()`, the order is: a local or module-scope value binding named `Name`, then a name in the type namespace, then a bare variant.
> - V3: no fallback on the member set. If `x` is not a member of the type's `T.` namespace, the site is an error; it is not read again as a value.
> - V5: for `type Unit { Unit }`, `Unit.x` is the type path; write `Unit.Unit.x()` for a member of the variant value.
> - V6: the dotted-head rule covers every `T.` member: variant, `fn T.name`, `const T.X`, trait associated fn.
> - An enum with a variant of its own name (F8) is legal.
> - `help:` lines on the F5 and F6 errors that name the qualified variant.
> - F7 (the ICE) is a compiler bug, not spec.

Tally: **Q1** E 3 (web, devops, aiml), L 3 (sys, plt, min). **Q2** V1-all 5, V1-data 1 (min). **Q3** W2 4 (web, devops, aiml, plt), W0 2 (sys, min). The Concern lines are in *Concerns*, below.

##### Q1: An enum type (or other type-namespace name) named like a variant — E or L

- **Systems**

> **Vote:** L
> **Reasoning:** The dotted-head rule decides `Red.x` statically, from the scope and the type namespace only, so codegen has one path for each spelling. A wrong reading nearly always gives an error (arity, or a missing member under V3), not a wrong program. E adds a package-wide check and an own-variant exemption, but it does not remove the rule, because dependency variants never collide.

- **Web/Scripting**

> 1. **Vote:** E
> 2. **Reasoning:** With E, a spelling in one package names a type or a variant, never both, so a reader never sees `let c = Red` (a `Color`) next to `Red.A` (a `Red`). Under L, only a `help:` line catches that trap, and only when a type error happens. The fix under E is one rename or one import alias, at the declaration the author owns, and dependency variants stay legal.

- **PLT**

> **Vote:** L
>
> **Reasoning:** Under the agreed V2/V3 rule, each dotted head already has one static reading, and that reading does not change when code is added. So E adds no soundness. It only adds a restriction. E0518 exists because `Name { ... }` reads as two constructors. An enum type has no brace form (F11), so that reason does not apply. The spec already calls a value that hides a variant "a shadow between scopes", not a collision, and a type that hides a variant at a dotted head is the same kind of thing.
>

- **DevOps/Tooling**

> **Vote:** E
>
> **Reasoning:** A declaration error stops a package pair at one place, with one fixed message and a machine-readable fix (rename, or an import alias). Under L, every F5/F6 use site needs a correct `help:` line that searches the variant candidate set and the member set, in the CLI and in the LSP; more help-line logic gives more wrong help lines. E also keeps the E0518 sentence "no path silently picks a winner" true without an exception for a pair that the author controls.
>

- **AI/ML**

> **Vote:** E
>
> **Reasoning:** A model meets the clash once, at the declaration, with a one-edit fix (rename or alias). Under L it meets it at each use, through a type error that names `Red` for two things (F5), which is a poor input to a repair loop. E also gives one rule to learn: "in a package, a type-namespace name is never a variant of another enum." This replaces "structs collide, enums do not", a split a model cannot predict from the spec.
>

- **Minimalism**

> **Vote:** L
>
> **Reasoning:** Only one site has two readings, the dotted head, and all six seats agree on a static rule there. E keeps that rule and adds a declaration error whose reason (two brace readings, F11) does not apply to an enum. That error makes users rename or alias programs that are correct today and have no wrong site. The moderator fact shows the type namespace already sits beside a same-named value (`const Red` and `type Red`) with no error, so L keeps that model the same for variants.
>

##### Q2: Reach of E over the type namespace — V1-all or V1-data

- **Systems**

> **Vote:** V1-all
> **Reasoning:** One rule over the whole type namespace is one set check per package and one sentence in the spec. A list of kinds is a special case for each new kind of type-namespace name. A trait or effect name heads a dotted path too (associated functions), so it has the same dotted-head question.

- **Web/Scripting**

> 1. **Vote:** V1-all
> 2. **Reasoning:** "A type-namespace name is never a variant of another enum of the package" is one sentence a user learns once. A list that takes alias but not trait is a rule a user must look up. The check costs the compiler the same for all five kinds.

- **PLT**

> **Vote:** V1-all
>
> **Reasoning:** If E wins, the rule should be about the type namespace as one set. A partial list brings back the kind of exception that has no reason ("why does an alias collide but a trait does not?"). One rule over one namespace is simpler to state and to check.
>

- **DevOps/Tooling**

> **Vote:** V1-all
>
> **Reasoning:** The compiler and the LSP check one thing: "is this name in the type namespace". A sub-list of kinds is a second rule to teach, to put in ERROR_CATALOG, and to change later when someone writes `trait Red` or `effect Red`. One namespace, one check, one message.
>

- **AI/ML**

> **Vote:** V1-all
>
> **Reasoning:** A model learns "type names", not a list, and applies it to all of them. If trait and effect are out, the model must remember an exception that buys nothing, and a trait `Red` still heads `Red.x()` paths in the same way. The rule text is one word shorter, not longer.
>

- **Minimalism**

> **Vote:** V1-data
>
> **Reasoning:** If E wins, cover only the names a user builds values of or writes as `T.` path heads for data: struct, enum, alias. No seat showed a real program where a trait or effect named like a variant misleads a reader. Each extra name kind is one more case for every reader and one more check for the LSP, with no proven gain (YAGNI).
>

##### Q3: W1011 for a type that hides a variant at a dotted head — W0, W1 or W2

- **Systems**

> **Vote:** W0
> **Reasoning:** Under L the pair is legal, and the dotted-head site that reads the type gets an error with a `help:` line that names the qualified variant. A warning at the declaration fires where nothing is wrong yet, and that adds noise to every build that has such a pair. The help at the site gives the same fix at the place where the problem is.

- **Web/Scripting**

> 1. **Vote:** W2
> 2. **Reasoning:** A dependency variant can be a bare candidate only when an import entry names its enum, so only then can the type hide it at a dotted head. W1 would warn about enums the user never imported and does not know of, and a warning with no visible cause is noise that users learn to ignore. W2 keeps the same condition as 02_syntax.md:943, so one rule tells the user when a hide matters.

- **PLT**

> **Vote:** W2
>
> **Reasoning:** A type can hide a variant only if a bare use at that site could otherwise reach the variant. The variant must be in the candidate set. For a dependency, that means an import entry names its enum (02_syntax.md:943, and the pending candidate-set rule). W1 warns about variants that the site could never reach, so it is a false positive on shadowing. W2 uses the same condition as a value that hides a dependency variant. So all shadow warnings use one rule.
>

- **DevOps/Tooling**

> **Vote:** W2
>
> **Reasoning:** W2 keeps the warning local: the reader can see the cause in the same file, from an import entry, which is the same condition as the E1016 W1011 (02_syntax.md:943). W1 fires for a variant of any dependency enum, which the file may never name; a warning whose cause is not visible from the file is noise, and the LSP must check all dependency enums on each edit. Under E, W1 and W2 differ only for dependency variants, so W2 costs nothing for package code.
>
>
> **Note on the moderator fact**
> A module-scope `const Red` beside `type Red` makes `Red.x` read the const under V2, with no diagnostic. That is a separate gap (value vs type of one name at a dotted head); it should get a friction ticket, not a change to this vote.

- **AI/ML**

> **Vote:** W2
>
> **Reasoning:** W2 uses the same condition as W1011 for a value that hides a dependency variant (02_syntax.md:943), so a model learns one shadow condition, not two. A variant of an enum the module never imports does not appear in the code the model reads, so a warning about it is noise that the model cannot connect to the site. Noise warnings teach models to ignore W1011.
>

- **Minimalism**

> **Vote:** W0
>
> **Reasoning:** A warning must point at a site that is wrong or likely wrong. W1 and W2 fire at the type declaration even when no `Red.x` in the program meant the variant, which is the common case. The help line at the error site already gives the exact fix where a problem exists. The struct W1011 case differs: there `Name { ... }` is a construction the user may well have meant as the variant.
>

#### Phase D — One round on Q1 and Q3

The moderator sent the Phase C tally and the strongest quotes for and against. Each seat answered the strongest point against its vote and voted again. Q2 was not reopened. Result: **Q1** E 3 (web, devops, aiml), L 3 (sys, plt, min), a tie again. **Q3** W2 6-0: sys and min changed from W0 to W2.

- **Systems** (`D_sys.md`)

> **Q1: answer to web**
>
> web's strongest point: under L a reader sees `let c = Red` (a `Color`) next to `Red.A` (a `Red`), and only a type error shows the trap. That is true under L with W0. It is not true under L with W2: the declaration `type Red` gets W1011 for that exact pair in the package, so the trap is visible before any use site goes wrong. E removes the same trap, but it also rejects correct programs, and its reason (two constructors at `Name { ... }`) does not apply to an enum type (plt, F11). L plus W2 gives the reader the signal at a lower cost.
>
> **Q3: answer to plt and web, and a change**
>
> My W0 concern was that the silent case (same member name and call shape on both readings) gets no signal at all. min names the same case. That is the one case where the program compiles and does the wrong thing, and the warning is the only tool under L that catches it. I accept plt's point that W2 uses the same condition as a value that hides a dependency variant, so it adds no new rule. min's noise point is weaker under W2, because W2 fires only where a bare use could reach the variant, and an alias or rename removes it. I change to W2.
>
> **Re-vote**
>
> **Q1: L**
> Reason: the dotted-head rule plus W2 makes every reading static and visible without rejecting correct programs.
>
> **Q3: W2**
> Reason: the silent misread is the only case that compiles wrong, and W2 flags it with the existing shadow condition.

- **Web/Scripting** (`D_web.md`)

> **1. Answers**
>
> **Q1, against sys/plt: "E does not remove the rule, because dependency variants never collide."** True, but that misses my point. E removes the case the user meets most: two names that the user wrote in one package. The dotted-head rule then applies only to a dependency variant or to a type's own variant, and in both of those the cause is visible from the file. sys and min both name a case that is silent under L: `Red.x()` type-checks on both readings and changes meaning with no error. E makes that case impossible for package code. A help line cannot help, because no error occurs. min's `const Red` beside `type Red` is not the same: the user wrote both names in one module and can see them. A bare variant comes from a different enum, maybe in another module.
>
> **Q3, against sys/min: "a warning at the declaration fires where nothing is wrong yet."** Under E, W2 fires only for a dependency enum that an import entry names, so the user can see the cause in the file and the warning is rare. It is also the only signal for the silent case in Q1: if both readings type-check, no error and no help line exists. A warning on a real hazard that the user can see is not noise. W2 keeps one shadow condition for values, structs and types (02_syntax.md:943).
>
> **2. Re-vote**
>
> **Q1: E.** Reason: E is the only option that makes the silent `Red.x()` change of meaning impossible for names the user wrote, at the cost of one rename or alias.
>
> **Q3: W2.** Reason: W2 is the only signal when both readings of `Red.x()` type-check, and its condition is the one the user already knows from values.

- **PLT** (`D_plt.md`)

> **Q1: answer to the strongest point against L**
>
> The strongest point is the silent case from sys and min: `Red.x()` type-checks under both readings, so the meaning changes with no error. That case is real. But E does not remove it. Dependency variants never collide under E, so the same silent case stays there, and E needs a warning for it too. The warning that closes the case is the one in Q3: L plus W2 marks every reachable shadow at the declaration. web's "a reader sees `let c = Red` next to `Red.A`" is the same pair, and W2 marks it. So L + W2 covers every case that E + W2 covers, with one rule and no error on correct programs.
>
> To devops: under W2, help lines are a convenience and not the only signal, so a wrong help line does not hide the shadow.
>
> **Q3: answer to the strongest point against W2**
>
> sys and min: the warning "fires where nothing is wrong yet". A local that hides a variant gets W1011 by the same logic, and nothing is wrong at that site either. The spec warns because the shadow can make a later site change meaning without notice. min's own Q3 concern names this silent case. Only a declaration-site warning catches it, because a site that type-checks gives no error to hang a help line on. One `@allow` at the declaration ends the noise for that pair.
>
> **Re-vote**
>
> **Q1: L.** Reason: with W2, L closes the silent case for package, prelude and dependency variants under one shadow rule. E closes it only for package and prelude variants, and adds an error on programs that are correct.
>
> **Q3: W2.** Reason: it is the only option that signals the silent case, and it uses the same reach condition as every other W1011.

- **DevOps/Tooling** (`D_devops.md`)

> **1. Answers**
>
> **Q1 (against E, plt and sys):** "E adds no soundness" and "it does not remove the rule" are both true; I do not claim soundness. My claim is about the case that gives no error. sys and min both name it: `Red.x()` where the type path and the variant value both have `x` with the same shape type-checks, reads the type, and gives no error and no help line, because a help line needs an error to attach to. Under L that case is open for every pair in the package; under E it is closed in the package and stays open only for dependency variants, where W2 marks it. On min's `const Red` beside `type Red`: that pair is a gap of the same kind, not a model to copy; I asked for a friction ticket on it.
>
> **Q3 (against W2, min and sys):** "A warning at the declaration fires where nothing is wrong yet." Under E, W2 fires only for a type that hides a dependency variant whose enum an import entry names in that file. That is rare, and the cause is visible in the same file. A help line at the use site cannot cover the silent same-shape case, because there is no error there; the declaration warning is the only signal that case gets. W2 also uses the same condition as the value W1011 (02_syntax.md:943), so the LSP has one shadow check, not two.
>
> **2. Re-vote**
>
> **Q1: E.**
> Reason: E closes the silent same-shape reading for every pair in the package with one declaration error, and leaves only the dependency case to the dotted-head rule.
>
> **Q3: W2.**
> Reason: W2 is the only signal for a same-shape `Red.x()` that type-checks, and it fires only where the file names the variant's enum.

- **AI/ML** (`D_aiml.md`)

> **1. Answers**
>
> **Q1 (against E).** plt says E "adds no soundness", and min says `const Red` beside `type Red` is legal today, so L keeps one model. Soundness is not my axis; what a model can predict is. Both sides named a silent case (sys: `fn Red.make()` beside a zero-argument value method `make`; min: same member, same arity, same type). Under L that case compiles to the other reading with no error, and under W0 with no warning too. A repair loop cannot fix an error it never sees, and E removes that case for all package code. The `const Red` / `type Red` pair is a separate gap of the same kind (devops is right to ask for a friction ticket). It is not a model to copy.
>
> **Q3 (against W2).** min says W2 "fire[s] at the type declaration even when no `Red.x` in the program meant the variant". Under E, W2 is left with one case: a dependency enum the file imports by name, with a variant named like a local type. That is exactly the case where a model writes `Red.x()` from memory of the imported enum. When both readings type-check, the declaration warning is the only signal. It costs one rename or alias, and it uses the same condition as the W1011 that exists today (02_syntax.md:943), so the model learns no new rule.
>
> **2. Re-vote**
>
> **Q1: E.** One declaration error with a one-edit fix removes the silent dotted-head case for package code, and gives one rule over the type namespace.
>
> **Q3: W2.** It is the only signal for the silent case that is left (dependency variants), and it uses the shadow condition that already exists.

- **Minimalism** (`D_min.md`)

> **1. Strongest points against my Phase C votes**
>
> **Q1 (web): "a reader never sees `let c = Red` (a `Color`) next to `Red.A` (a `Red`)."** E does not give this. A dependency variant never collides, so the same pair stays legal next to `import pal.{Color}`. The moderator fact gives a third case: `const Red` next to `type Red` is legal, and `Red.x` reads the const. Nobody proposes to ban that pair, and it is the same "values come first" shape. aiml's point "structs collide, enums do not" has a reason the spec can state in one sentence: only a struct has a brace form that a variant also has (F11). So the split is not arbitrary, and E keeps a second rule (the dotted head) anyway.
>
> **Q3 (plt): "W2 uses the same condition as a value that hides a dependency variant. So all shadow warnings use one rule."** This point beats mine. I said a declaration warning fires where no site is wrong. But W1011 for `const Warm` that hides `Tone.Warm` (03_types.md:2060) already fires at the declaration with no wrong site, and the spec accepts it. So W2 adds no new rule, only one more kind of name under the existing one. It also covers the silent case I named in Phase C (both readings type-check), which W0 leaves with no signal. I change to W2.
>
> **2. Re-vote**
>
> **Q1: L**
> Reason: the dotted-head rule already gives one static reading at every site, so E adds a restriction with no gain in soundness and makes users rename correct programs.
>
> **Q3: W2**
> Reason: it reuses the existing W1011 shadow condition (02_syntax.md:943), so the panel adds no new warning rule, and it covers the silent same-shape case.

**Result:** Q1 tied 3-3 after Phase D; the owner broke the tie for L, amended (see *Owner tiebreak and amendment*).

**Owner tiebreak:** L, amended.

### Concerns

Each seat's Concern line from Phase C and Phase D, in the seat's own words.

#### Phase C

- **Systems**

> Q1 — **Concern:** A type-scoped member with the same name and call shape as a method on the variant value (for example `fn Red.make()` and a zero-argument value method `make`) reads as the type path with no error, and the reader does not see why.
>
> Q2 — **Concern:** If E wins, users get an error for a trait or effect name that has no real clash in their code, and they must rename for no gain they can see.
>
> Q3 — **Concern:** The silent case from Q1 (same name and same call shape) gets neither a warning nor an error, so W0 gives no protection there.

- **Web/Scripting**

> Q1 — 3. **Concern:** E rejects code that compiles today (F4, F9), and the error is new to users, so the E0518 message and its alias help must be clear on the first read.
>
> Q2 — 3. **Concern:** A trait or effect named like a variant is rare, so the wider rule may stop a correct name that nobody reads two ways.
>
> Q3 — 3. **Concern:** If the bare-variant candidate set (branch spec/variant-hint-positions) changes, the W2 condition must change with it or the warning and resolution drift apart.

- **PLT**

> Q1 — **Concern:** If L wins, users depend on the help lines and W1011 to see the shadow. If the implementation leaves out either of them, `Red.label()` gives an error that does not name the cause, as in F6 today.
>
> Q2 — **Concern:** V1-all can reject a trait or effect name that never heads a dotted path in which a variant could compete. Then the error has no use-site ambiguity to point to.
>
> Q3 — **Concern:** If a later spec change widens the candidate set, the W2 condition must stay tied to the candidate set and not be copied as a separate rule, or the two will drift apart.

- **DevOps/Tooling**

> Q1 — **Concern:** E rejects programs that compile today (F4, F9), so the diagnostic must name both spans (type and variant) and give the alias text, or users will hit a rename with no clear cause.
>
> Q2 — **Concern:** If a real trait or effect name is common as a variant name in existing code, V1-all gives a rename with less gain than for data types.
>
> Q3 — **Concern:** A dependency variant that reaches the file by global-unique resolution with no import entry for its enum hides with no warning; the F6 `help:` line is then the only signal.

- **AI/ML**

> Q1 — **Concern:** Code ported from Rust or TS that has `enum Red` beside `Color.Red` will fail to compile, so the E0518 help must give the exact alias or rename text, or the model will guess.
>
> Q2 — **Concern:** A trait or effect named like a common prelude variant (for example `Ok`) gets an error that a user may find odd, so the message must say that the reason is the `Red.` path, not the bare name.
>
> Q3 — **Concern:** A bare variant that the global-unique step finds with no import entry can still be hidden at `Red.x` with no warning; the F6-style help line is then the only signal, so it must be present.

- **Minimalism**

> Q1 — **Concern:** If the help lines on F5/F6 are weak or missing, a user who meant the variant at `Red.x()` gets an arity or member error that does not name the cause.
>
> Q2 — **Concern:** If E with V1-data wins, a later case with `Trait.x()` may force a second ballot to add trait and effect.
>
> Q3 — **Concern:** If W0 wins, a `Red.x()` that meant the variant and still type-checks (both readings have a member `x` of the same arity and type) is a silent change of meaning, with no error and no warning.

#### Phase D

- **Systems**

> Q1 — Concern: if E loses, the spec must say clearly that E0518 is about the brace form only, or readers will still expect enums to collide as structs do.
>
> Q3 — Concern: W2 fires at the declaration for every pair, also when no `Red.x` site exists, so some users will see it as noise and suppress it.

- **Web/Scripting**

> Q1 — Concern: code that compiles today stops compiling, so the E0518 message must name both spans and give the exact alias text.
>
> Q3 — Concern: devops and aiml are right that a variant reached by global-unique resolution with no import entry still hides with no warning, so the F6 help line must be present.

- **PLT**

> Q1 — Concern: if W2 loses, L leaves the silent case with no signal, so a W0 + L result should be checked again.
>
> Q3 — Concern: users may add `@allow` by reflex, and then the warning stops being useful.

- **DevOps/Tooling**

> Q1 — Concern: E rejects programs that compile today (F4, F9), so the E0518 message must show both spans and give the exact alias text.
>
> Q3 — Concern: The W2 condition must stay tied to the bare-variant candidate set (branch spec/variant-hint-positions), or the warning and the resolution will drift apart.

- **AI/ML**

> Q1 — Concern: code ported from Rust or TS that has `enum Red` beside `Color.Red` now fails to compile, so the E0518 help must give the exact rename or alias text.
>
> Q3 — Concern: if the candidate set on spec/variant-hint-positions changes, the W2 condition must stay tied to it, or the warning and resolution will drift apart.

- **Minimalism**

> Q1 — Concern: under L, the F5/F6 help lines and W2 are the only signals, so the implementation must ship them, not defer them.
>
> Q3 — Concern: under L, W2 fires for package and prelude variants too, so a package with many such pairs gets many warnings; the message must name the qualified variant so that each warning has a clear fix.

The silent same-shape case (named by sys and min in Phase C, and by devops, aiml and web in Phase D): `Red.x()` type-checks under both readings, so the meaning
changes with no error and no help line can attach. This is the case that moved sys and min from W0 to W2. plt (D)
states the answer, and the spec takes it: W1011 at the declaration marks the pair, and one `@allow` ends the noise.

> plt (D): "The warning that closes the case is the one in Q3: L plus W2 marks every reachable shadow at the declaration."

Binding concerns for the implementation:

- (plt, min, sys) The help lines on a failed type path and the W1011 type case ship together with the rule. Under L they are the only signals.
- (min, plt, devops, web) The W1011 condition stays tied to the bare-variant candidate set (*Resolution order*). It is not a copy of that set, so the two cannot drift apart.
- (min) The W1011 message names the qualified variant, so each warning has a clear fix.
- (sys) Under L, the spec says clearly that E0518 is about the brace form only. The sentence is in *Name collisions*.
- (devops, web, aiml) A dependency variant that a bare use reaches by the global-unique step with no import entry for its enum hides with no warning. The help line is then the only signal, so it must be present.

### Final Spec (text for L, as the owner amended it)

```blink
type Color { Red, Green }

type Red { A, B }                     // warning[W1011]: type `Red` hides variant `Color.Red`

trait Label { fn label(self) -> Str }
impl Label for Red { fn label(self) -> Str { "type" } }
impl Label for Color { fn label(self) -> Str { "variant" } }

fn main() ! IO {
    let c = Red                       // error[VariantNamedLikeType]: bare `Red` names the type `Red`, not a variant
                                      // help: write the variant with its enum: `Color.Red`
    let d = Color.Red                 // the variant
    let r = Red.A                     // type path: variant `A` of the type `Red`
    io.println(Red.label())           // error[TypeError]: function Red.label expects 1 argument(s), got 0
                                      // help: to use the variant, write `Color.Red`
    io.println(Color.Red.label())     // the qualified form always reaches the variant
}
```

- **Dotted head (agreed in Phase B).** At `Name.x` and `Name.x(...)` the order is: a local or module-scope value named `Name`; then a name in the type namespace (type path); then a bare variant. A bare `Name` and `Name(...)` keep *Values come first*, so a type name is never a bare value (§3.4 *Dotted heads*).
- **No fallback (agreed in Phase B).** The reading comes from scope and namespaces only. If `x` is not a member of the type, the site is an error. An `impl` added elsewhere never changes what an existing site means.
- **Own variant (replaced).** Phase B agreed that `type Token { Token(Str), End }` is legal. The newtype panel made it E0518 at the declaration, so no own-enum exemption remains.
- **Scope (agreed in Phase B).** "Type path" covers every `T.` member: a variant, `fn T.name`, `const T.X`, a trait associated function.
- **Help (agreed in Phase B).** A failed type path (unknown member or arity), with a bare variant of that name in reach, gets a `help:` line that names the qualified variant.
- **W1011 (Q3, W2).** At the type declaration, once for each hidden variant of a different enum. A dependency variant counts only when an import entry names its enum (§10.6 *Shadowing Rules*). The condition is tied to the bare-variant candidate set by cross-reference. `@allow(ShadowedVariant)` on the `type` silences it for a struct, enum or alias; the `[lints]` table covers a trait or effect.
- **Q1 (L, owner tiebreak, amended).** An enum, alias, trait or effect named like a variant is legal at its declaration. A bare variant `X` or `X(...)` is `VariantNamedLikeType` (E0554) when a type named `X` is in scope (a declared or imported struct, enum, alias, trait or effect; builtin and prelude types count). The rule holds in every expression; a hint does not make the bare form legal. Patterns are not affected: a pattern finds its variant from the type of the matched value (§3.5). The help writes the variant with its enum, and lists each form when two enums have the variant. The help is machine-applicable with one candidate. §3.4 *Name collisions* says that E0518 covers a struct because `Name { ... }` reads as both a struct literal and a variant brace literal.
- **Q2 (V1-all, 5-1).** Applied only if the owner picked E. The owner picked L, so no spec text.
- **Not spec.** The internal compiler error on an unknown member of an enum type path is a compiler bug.

Governing text: §3.4 *Values come first*, *Dotted heads* and *Name collisions*, §10.6 *Shadowing Rules*.

### Known gaps and follow-ups

1. Implementation: the dotted-head order (value, type, variant) with no fallback on the member set; the help lines on a failed type path; W1011 for a type that hides a variant of a different enum; E0554 for a bare variant named like a type in scope, in expressions, hinted positions and patterns; the internal compiler error on an unknown member of an enum type path (a compiler bug, not spec); tests for each point, including a cross-package pair.
2. Friction already filed: a module `const Red` beside `type Red` in one module is legal, and `Red.x` reads the value with no diagnostic.
3. Void: the owner picked L, so E0518 does not extend to the type namespace.
4. `fn T.name` does not parse today. The dotted-head rule names it as a member of `T.`, as the spec already does (§2.12.3).

#### AI-first review

1. Learnability — PASS. One ordered list for a dotted head: value, type, variant. The qualified variant always reaches the variant.
2. Consistency — PASS. A type that hides a variant gets W1011 with the same condition as a value that hides one.
3. Generability — PASS. A model writes `Red.A` for the type and `Color.Red` for the variant, and a bare `Red` is E0554 with a help that names `Color.Red`.
4. Debuggability — PASS. A failed type path with a bare variant in reach carries a `help:` line that names the qualified variant.
5. Token efficiency — PASS. No new syntax; one new error code, E0554, and its fix is a qualifier.

0 of 5 fail. No flags.
