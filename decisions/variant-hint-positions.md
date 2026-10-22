[< All Decisions](../DECISIONS.md)

# Variant Hint Positions and Global-Unique Reach — Design Rationale

The spec for a bare variant name (`Red`, `Red(1)`, `Red { x: 1 }`) left two gaps. The *Hint-directed* step of §3.4 *Resolution order* listed four positions in a short parenthesis, and the
compiler gave an expected type at about twelve. The *Global-unique* step searched "the whole program", and the
compiler read that as every loaded module, with a special case that kept a program's enums out of std. This ruling
lists the positions that give an expected type, and it fixes the set of enums that the global-unique step searches.

## Summary

| Q | Question | Result | Vote |
|---|---|---|---|
| Q1 | Form of the hint list | L1: one closed list of the positions that give an expected type, named *Expected type at a site*, with a sentence that no other position gives one. An expected type reaches each `if` branch, each `match` arm and the tail of a block, and no condition, guard, scrutinee or non-tail statement. A parameter whose type is a type parameter of the callee gives none, unless explicit type arguments fix it. In a comparison, a bare variant takes the type of the other operand; if both are bare variants, neither gets one | 6-0 |
| Q2 | Reach of the global-unique step | R1+I: the enums of the site's module, the `pub` enums of the other modules of its package, the prelude enums, and each enum of another package that the module binds by an import entry that names the type. A non-`pub` enum of another module is never a candidate | 6-0 |

Not voted, because no seat contested them: the visibility filter (V8) is part of every Q2 option; a bare name that the
global-unique step does not reach fails at the name with the undefined-name code and a fix; the unused-import lint
counts a bare-variant use; the editorial rider names the global-unique step instead of a number in cross-references.

The panel took two rounds of debate (Phase B). Round 1 ended with three seats ready and three not. Round 2 ended with
all six ready. Both questions passed 6-0 in Phase C, and no Phase D was needed.

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated in
independent-proposal, debate, vote rounds. The ticket asked two things: which positions give a bare variant its
expected type, and how far the global-unique step reaches.

The text below is excerpted from each panelist's own text. A quote is cut at a sentence end, and line breaks in the
source files are joined.

#### Phase A — Independent proposals

All six seats put a closed list first for Q1. For Q2 the first choices split three ways. The headings below are each
seat's own labels.
- **Systems** (`A/sys.md`):

> sys-1 (FIRST CHOICE for Q1) — a closed list of hint positions, with comparisons by cross-reference to §3.2
>
> sys-2 (FIRST CHOICE for Q2) — global-unique searches the site's package, the prelude, and the packages it depends on

- **Web/Scripting** (`A/web.md`):

> web-1 (FIRST CHOICE for Q1): one rule — "the expected type at the site", defined once, with a closed list
>
> web-2 (FIRST CHOICE for Q2): global-unique reaches the site's package plus the prelude

- **PLT** (`A/plt.md`):

> plt-1 (FIRST CHOICE, Q1): one closed definition of "expected type", sources plus propagation
>
> plt-2 (FIRST CHOICE, Q2): step 4 searches the enums *visible* at the site, plus the prelude

- **DevOps/Tooling** (`A/devops.md`):

> devops-1 (FIRST CHOICE) — one closed list, "Expected type at a variant site", in its own paragraph
>
> devops-2 — step 4 reaches the site's package, its dependencies, and the prelude; never a package that depends on it

- **AI/ML** (`A/aiml.md`):

> aiml-1 (FIRST CHOICE for Q1): one closed list of hint positions, stated once, with one propagation rule
>
> aiml-2 (FIRST CHOICE for Q2): the global-unique step searches the site's package plus the prelude

- **Minimalism** (`A/min.md`):

> min-1 (FIRST CHOICE): one closed definition of "expected type", cited by name; no new mechanism
>
> min-2 (FIRST CHOICE): global-unique searches the site's package plus the prelude — the same reach as E0518

##### Phase A options

Q1: all six seats proposed a closed list (L1). Four of them (sys, web, aiml, devops) also listed the same rows as
examples of a general rule (L2) as a second choice.

Q2: three options.

- **R1** — the site's package plus the prelude (the reach of E0518): web, aiml, min.
- **R2** — the site's package, every package it depends on, and the prelude; never a package that depends on it: sys, devops.
- **R3** — the enums visible at the site (the module's own enums, the `pub` enums of modules the file can import, the prelude enums): plt.

#### Phase B — Debate, round 1

The moderator measured the cost of R1 before the round. It changed the compiler so that a site outside std stops
seeing std enums at the global-unique step, and it ran `blink check` on 2565 library and test files and 122 more.
From `measure.md`:

> tests/test_*.bl: 4 of 2514 change pass -> fail. (10 files already fail in baseline, unchanged.)
>
> None of the 4 fail with E0519. All are the same cause: a call or pattern `Errno(...)` (std.errno transparent newtype, `pub type Errno { Errno(Int) }`, imported via `import std.errno.{Errno}`) resolved before only through the global-unique step, to std_errno enum Errno.Errno. With std_ enums hidden, the name is unresolved at those sites, and the failure appears as inference errors, not an unresolved-name error.

The four failures have one shape: a bare `Errno(...)` after `import std.errno.{Errno}`. In the same round min added a
probe, p2.bl, that shows a second fact: a user program with no import fails today because of std.


##### aiml and sys move to R3
- **AI/ML** (`B1/aiml.md`):

> Q2: I move my first choice from R1 to R3, with R2 second and R1 third.
>
> **The breakage count hits the spec's own newtype idiom.** All four failures are `Errno(5)` after `import std.errno.{Errno}`. 03_types.md:2185 names `type Errno { Errno(Int) }` as *the* single-payload newtype pattern. Under R1, a user who imports the type by name and writes its constructor (the most obvious code a model writes) gets an inference error. The count is small (4 of 2514), but it is the code a model writes most often for a dependency enum.

- **Systems** (`B1/sys.md`):

> Q2: R3 first, R2 second, R1 last. I withdraw sys-2b (= R1) as a fallback I would vote for.
>
> **The measurement goes against R1 on the newtype idiom.** All four failures are `Errno(...)` after `import std.errno.{Errno}`. `type Errno { Errno(Int) }` is the zero-cost newtype that 03_types.md:2185 names as the reason single-payload enums exist. Under R1, every newtype from a dependency must be written `Errno.Errno(5)` at an unhinted site. That puts a tax on the pattern the spec tells users to use for type-safe wrappers with no run-time cost. Also, the measured failures show as an ICE (`NodeCarriesNoType`) and as `CannotInferType`, not as a clean "not a variant of this package" error. So R1 is not only a spec change; it needs diagnostic work that nobody has costed yet.


##### devops moves to R1 on two conditions
- **DevOps/Tooling** (`B1/devops.md`):

> Q2: I withdraw devops-2 (R2) and move to R1, with two conditions
>
> The decision must state the required outcome: a bare name that resolves to nothing in the package or prelude, but is a variant of a reachable dependency enum, is an error at the name, with a `help:` that writes the qualified form (`Method.Get`, `Errno.Errno(5)`) as a machine-applicable fix, and the binding gets the poison type so no cascade follows (§6.3.5, as E0547 already does). Use the existing E0504 / undefined-name code with that help; no new code.
>
> `import std.errno.{Errno}` then `Errno(5)` failing will read as a bug to every user: they imported the type by name and its only variant has the same name.


##### plt: the privacy argument (V8)
- **PLT** (`A/plt.md`):

> A private enum of another module is not a candidate. Its value would escape the module through a bare name, which privacy forbids for every other route.

- **PLT** (`B1/plt.md`):

> So whatever reach wins, the candidate set must hold only enums that are visible at the site.


##### min: p2.bl and R1+I
- **Minimalism** (`B1/min.md`):

> So a user's own enum, in a one-file program that never names std.time, cannot use a bare variant because std has `Weekday.Monday`. That is the "distant enum declaration changes a site" failure, live on main.
>
> **Support, first choice now: R1+I** — the site's own enums (module + `pub` enums of its package) and the prelude, plus each dependency enum that the module binds by an import entry naming the type.
>
> If the panel rejects the import clause, I vote **R1** over R2/R3: `UserId.UserId(5)` is an ugly spelling, but p2.bl is a correctness bug.


##### web: `Read`, `File`, `Other`, and web-2b
- **Web/Scripting** (`B1/web.md`):

> `Read`, `Write`, `File`, `Dir`, `Other`, `NotFound`, `Timeout` are some of the most common variant names users write. A user's own enum must win at an unhinted site in their own package, with no qualification, when they never touched std.fs.
>
> web-2b (new FIRST CHOICE): the site's package and the prelude, plus each `pub` enum that the module binds by an import entry; private enums of another module never count (V8).

Status after round 1: aiml, sys and plt ready; devops, min and web not ready. The open requests of the three are
quoted in `B2.md`. They concern the `Errno(5)` shape, the p2.bl probe, the std name collision, and a ballot option
that adds enums imported by name.

#### Phase B — Debate, round 2

The moderator ran min's two probes on this tree and gave the facts to all six seats. From `B2.md`:

> min's p2.bl (one file, no import, `type Day { Monday, Funday }`, `let d = Monday`) gives today:
>
> "error[AmbiguousConstruction]: `Monday` is a variant of both Weekday and Day; qualify as Weekday.Monday or Day.Monday".
>
> p3.bl (one file, no import, `type Node { File, Dir, Other }`, `let n = Other`) checks clean today (only an unused-variable warning).
>
> std's `FileKind { File, Dir, Other }` (lib/std/fs_ops.bl:14) is not a candidate at that site in this build; std's `Weekday` (lib/std/time.bl:185) is.

Every seat that ranked R2 or R3 first then answered both probes. Three of them withdrew.

- **Systems** (`B2/sys.md`):

> p2.bl (min) and web's `Read`/`File`/`Other` example: I concede. R2 and R3 are wrong.
>
> I withdraw sys-2 and my support for R3.
>
> 1. **R1+I** (= web-2b): the site's package, the prelude, and each enum the module binds by an import entry. Private enums of another module never count.

- **PLT** (`B2/plt.md`):

> min and web are right. Every file can import every std module, so under R3 "the `pub` enums of modules the file can import" includes all of std. With R3, p2.bl (`type Day { Monday, Funday }`, `let d = Monday`) stays E0519 against `Weekday`. web's `type Perm { Read, Write }` with `let p = Read` becomes E0519 against `FsOp`, in a file that never mentions std.fs.
>
> One wording point for the record: only an entry that names the type counts (`import std.errno.{Errno}`). A whole-module `import std.errno` does not.

- **AI/ML** (`B2/aiml.md`):

> For a model this is the worst failure on the table. To predict it, the model must know every variant name in std, a set it cannot see in the file and that grows with each std release. R2 has the same flaw. I withdraw R3 as my first choice.
>
> I reverse my round-1 objection to aiml-2b. I said an import would change resolution. It does, but only by *adding* the type the import names, the same type the file must import to write `Errno.Errno` or to annotate `: Errno`. Removing that import already breaks those uses, so no new hazard appears.

- **DevOps/Tooling** (`B2/devops.md`):

> Tooling requirement that comes with R1+I: the unused-import lint must count a bare-variant use as a use of the entry that brought the enum in. The resolver knows which enum it picked, so this is cheap. Without it, the lint (or an LSP "organize imports") removes the entry and breaks the code.

- **Minimalism** (`B2/min.md`):

> Why R1+I over R1: it costs one clause, and it uses the mechanism step 2 already has (an import entry decides a bare name).

- **Web/Scripting** (`B2/web.md`):

> I count this as decisive against R2 and R3.

All six seats asked that V8 sit inside every Q2 option, and that R1+I and web-2b be one option. Status after round 2:
all six ready to vote.

#### Phase C — Final vote

Each seat voted alone. Q1 and Q2 each passed 6-0. The ballot listed R1+I, R1, R3 and R2; every seat voted R1+I.
The reasoning and the concern of each seat follow, in full.

##### Q1: Form of the hint list — L1, 6-0
- **Systems** — Vote: L1

> Each row on the closed list is a position where the type is known before the site is checked. So resolution is one forward pass, with no back-propagation and no dependence on the order of unification. That is the property that makes the same source always resolve to the same tag constant. An open rule would let the checker add hint sites with no spec change, and each new site changes which programs give E0519.
>
> **Concern:** The list can fall out of date when a new expected-type position enters the language. A compiler that adds one without a spec change would make the closed list silently false.

- **Web/Scripting** — Vote: L1

> A JS or TS dev already knows "contextual typing" works at assignments, returns, arguments, elements and branches, so the list holds no surprises. A closed list also answers the edge questions (`(x, Red)`, `id(Red)`, a guard) from the text alone, and those are the cases that would become Stack Overflow questions under an open rule. It matches what the compiler does today, so no user program breaks.
>
> **Concern:** A user who expects Kotlin-style inference through generics will hit E0519 at `id(Red)`. If the help line does not offer `id[A](Red)` or `A.Red` at once, the closed list reads as an arbitrary rule.

- **PLT** — Vote: L1

> The expected type is the checking judgment of a bidirectional system. A checking judgment is defined by a closed set of rules, not by a sample of them. If the list is open, "does this site have an expected type?" has no answer in the text. Then whether a program is E0519 depends on the compiler, and the Q8 invariant ("determined statically") holds only by accident. A closed list also makes each new hint position a visible spec change, which is right, because a new position changes which programs are well-formed.
>
> **Concern:** The compiler may already hint at a position the closed list omits (a probe set of F38–F46 does not prove there are none), and then the conformance work will find that the compiler accepts programs the spec calls E0519.

- **DevOps/Tooling** — Vote: L1

> A tool can test against a closed list and cannot test against a general rule. With L1 the compiler, the LSP (ranking the expected enum's variants at the cursor, hover "expected type: Ordering") and the E0519 help ("give the site an expected type") all read one table, so they cannot disagree. The negative half (no condition, guard, scrutinee or non-tail statement; no type parameter without explicit type arguments) is what lets the E0519 note say exactly why a site has no expected type.
>
> **Concern:** When the checker gains a new hint site and nobody updates the list, the list goes stale without a sound. The implementation ticket should add a test per row so a new or lost hint site fails the gate.

- **AI/ML** — Vote: L1

> A closed list lets a model learn the hint positions from the spec alone. It reads one paragraph and knows whether a site gets a hint. It does not have to simulate the type checker at the edges, where models guess wrong (generic parameters, an unannotated tuple). The "no other position" sentence turns each unlisted position into a known E0519 with a known fix, not a guess. An open rule (L2) leaves exactly those edge cases undecided, and those are the cases the list exists to settle.
>
> **Concern:** The checker can grow a new hint position without a spec edit. The closed list then states a rule the compiler no longer follows, the same drift that caused this ticket. So the implementation ticket should test each row and the "no other position" negative.

- **Minimalism** — Vote: L1

> This ticket exists because the list was open. An open list with "such as" lets each reader, and each compiler change, add a position without a decision. A closed list costs nine rows once, and in return every later "does X count" question has an answer in the text, not in a new ticket. The rows add no new mechanism. They state what the compiler already does, and the comparison row cites §3.2 instead of restating it, so the spec gets no second operator rule.
>
> **Concern:** A future feature that adds a new expression form (for example a new collection literal) may forget to add its row. Then the closed list quietly makes that form give no hint, so the feature's spec change must check this list.


##### Q2: Reach of the global-unique step — R1+I, 6-0
- **Systems** — Vote: R1+I

> The candidate set is the package, the prelude and the module's own import entries. The compiler knows all of these when it compiles the module, so a compiled package (the std archive today, a per-package object cache later) stays valid for every program that uses it. The compiler needs no index of every dependency enum, and the load set no longer changes resolution, which the compiler permits today and *Impl visibility* forbids. It keeps the no-run-time-cost newtype idiom (`import std.errno.{Errno}` then `Errno(5)`) without `Errno.Errno(5)`.
>
> **Concern:** The implementation could still read the candidate set from the enum slots that the build loaded, not from the import entries. Then the p2/p3 dependence on loaded modules would continue under the new text, so the ticket needs a test where an unrelated import loads a std module that declares the same variant name.

- **Web/Scripting** — Vote: R1+I

> A user's own enum must work bare in their own program, even when std or a dependency declares the same variant name. p2.bl (`Monday` vs std `Weekday`) shows that whole-program, R2 and R3 all break this for a beginner with no imports. The import clause keeps the idiom every web dev writes, `import std.errno.{Errno}` then `Errno(5)`, and the module's own text decides the candidate set.
>
> **Concern:** If the implementation ships without the recorded diagnostic, a user who writes `import std.errno` (whole module) and then `Errno(5)` gets an inference error three lines later instead of "write `errno.Errno(5)` or import `Errno` by name". If the unused-import lint does not count the bare use, it removes a load-bearing import.

- **PLT** — Vote: R1+I

> R1+I is the only option that fixes the candidate set at a site from just two things: the site's package and the text of the site's own file. That is the modularity property that impl visibility (03_types.md:4695) and E0518 reach already require. R2 and R3 make a user's own `Monday` or `Read` ambiguous because of std enums the file never names, so the meaning of a site changes with each dependency release. Plain R1 is sound, but it rejects `Errno(5)` after `import std.errno.{Errno}`, even though the file has named the type explicitly. A selective import entry is ordinary lexical scoping, so adding the import clause adds no non-local effect.
>
> **Concern:** The import clause makes candidacy cross-package depend on a selective entry and in-package independent of imports. If the spec text does not state that split in one sentence next to the decided ":385" rule, readers will repeat the "imports restrict candidates" misreading this ticket began with.

- **DevOps/Tooling** — Vote: R1+I

> The candidate set comes from the site's package, the prelude and import entries in the site's own file. The compiler, a single-file `blink check` and the LSP therefore always have every candidate loaded, and they agree by construction. With today's load-dependent set (p3.bl) they can disagree. A dependency release can no longer make an unhinted bare name in a file that never named it ambiguous (p2.bl). The import clause keeps the newtype idiom `Errno(5)` working with no rewrite.
>
> **Concern:** If the unused-import lint, or an LSP "organize imports" action, does not count a bare-variant use as a use of its import entry, it will remove the entry and break working code. A bare name that loses its candidate will then fail as `CannotInferType` or an ICE, as measured, unless the recorded diagnostic requirement ships in the same slice.

- **AI/ML** — Vote: R1+I

> The model checks the candidate set against the file it is writing: its package, the prelude, and the types its import entries name. Nothing in the set is hidden. It keeps the spec's own newtype pattern working across packages (`Errno(5)` after `import std.errno.{Errno}`). It also stops std's variant names (`Weekday.Monday`, `FileKind.Other`) from blocking a user's own bare variants (p2.bl), which a model cannot predict under R2 or R3. With V8 folded in, every candidate is one the site can write qualified, so the E0519 help never suggests code that fails.
>
> **Concern:** "An import entry naming the type" and "a whole-module import" look alike in generated code. A model that writes `import std.errno` and then a bare `Errno(5)` will hit the failure, so the agreed diagnostic must offer the import entry as the machine-applicable fix. If it does not, models will learn the pattern from failures.

- **Minimalism** — Vote: R1+I

> One clause fixes three problems. It fixes the bug the ticket names: the std/program special case becomes a consequence of the rule. It fixes the p2.bl failure on main, where std's `Weekday` blocks a user's own bare `Monday`. And it keeps the measured newtype idiom: `import std.errno.{Errno}` then `Errno(5)` still works. The import clause adds no new kind of input, because an import entry already decides a bare name at step 2 of *Values come first*. A dependency release can then affect only a module whose own text names the changed enum, so the candidate set never depends on which modules the build loads.
>
> **Concern:** The import clause makes an import entry load-bearing for name resolution. If the unused-import lint, `blink fmt`, or an LSP "organize imports" action does not count a bare-variant use as a use of the import, a tool can remove the import and break code that compiled.


### Final Spec

```blink
// package app; std.time declares `pub type Weekday { Monday, Tuesday, ... }`
// and std.errno declares `pub type Errno { Errno(Int) }`
import std.errno.{Errno}
import std.time

type Day { Monday, Funday }

fn main() {
    let d = Monday                    // Day.Monday: std's Weekday is not a candidate
    let e = Errno(5)                  // Errno.Errno: the import entry names the type
    let w: time.Weekday = Tuesday     // the hint reaches any enum that the site names
}
```

- A site has an expected type at nine positions and at no other: a `let` annotation, an assignment to a place, a function tail or `return`, a call or method argument, a field value in a brace literal, the payload of `Some`/`Ok`/`Err`, a list or tuple element, the right operand of `??`, and a comparison operand (§3.4 *Expected type at a site*).
- An expected type reaches each `if` branch value, each `match` arm value and the tail of a block. It does not reach a condition, a guard, a scrutinee or a statement that is not the tail.
- A parameter whose type is a type parameter of the callee gives no expected type, unless explicit type arguments fix it: `id[A](Red)` has `A`, and `id(Red)` has none.
- In a comparison, if exactly one operand is a bare variant name, the other operand gives its type. If both are, neither gets one. §3.2 *Operator operands* stays the only statement of the literal rule.
- The hint-directed and global-unique steps decide `Name` and `Name(...)` as well as `Name { ... }`, after *Values come first*.
- The global-unique step searches the enums of the site's module, the `pub` enums of the other modules of its package, the prelude enums, and each enum of another package that the module binds by an import entry that names the type. A whole-module import adds none. A non-`pub` enum of another module is never a candidate.
- Inside the package, an import never adds or removes a candidate. For an enum of another package, only an import entry that names the type adds it.
- A site in a dependency never sees an enum of a package that depends on it. A new `pub` enum in a dependency changes a bare name only in a module that imports that enum by name.
- A bare name that matches no candidate, but matches a `pub` enum of another package that the module does not import by name, is an undefined-name error at the name (`UndefinedVariable` E0506 or `UndefinedFunction` E0504). The `help:` names the enum and gives the qualified form or the import entry. The binding has the poison type, so no follow-on error appears.
- A bare variant name that resolves through an import entry is a use of that entry for W0602 (§10.5 *Unused Imports*).
- Cross-references name the *Global-unique* step, not a step number.

Governing text: §3.4 *Resolution order*, *Expected type at a site*, *Values come first* and *Name collisions*, §3.5 (patterns), §10.5 *Unused Imports*, `ERROR_CATALOG.md` (E0504, E0506, E0519).

### Concerns

Each seat's Phase C concerns, verbatim (Q1 first, then Q2):

- **Systems:** Q1: "The list can fall out of date when a new expected-type position enters the language. A compiler that adds one without a spec change would make the closed list silently false." Q2: "The implementation could still read the candidate set from the enum slots that the build loaded, not from the import entries. Then the p2/p3 dependence on loaded modules would continue under the new text, so the ticket needs a test where an unrelated import loads a std module that declares the same variant name."
- **Web/Scripting:** Q1: "A user who expects Kotlin-style inference through generics will hit E0519 at `id(Red)`. If the help line does not offer `id[A](Red)` or `A.Red` at once, the closed list reads as an arbitrary rule." Q2: "If the implementation ships without the recorded diagnostic, a user who writes `import std.errno` (whole module) and then `Errno(5)` gets an inference error three lines later instead of "write `errno.Errno(5)` or import `Errno` by name". If the unused-import lint does not count the bare use, it removes a load-bearing import."
- **PLT:** Q1: "The compiler may already hint at a position the closed list omits (a probe set of F38–F46 does not prove there are none), and then the conformance work will find that the compiler accepts programs the spec calls E0519." Q2: "The import clause makes candidacy cross-package depend on a selective entry and in-package independent of imports. If the spec text does not state that split in one sentence next to the decided ":385" rule, readers will repeat the "imports restrict candidates" misreading this ticket began with."
- **DevOps:** Q1: "When the checker gains a new hint site and nobody updates the list, the list goes stale without a sound. The implementation ticket should add a test per row so a new or lost hint site fails the gate." Q2: "If the unused-import lint, or an LSP "organize imports" action, does not count a bare-variant use as a use of its import entry, it will remove the entry and break working code. A bare name that loses its candidate will then fail as `CannotInferType` or an ICE, as measured, unless the recorded diagnostic requirement ships in the same slice."
- **AI/ML:** Q1: "The checker can grow a new hint position without a spec edit. The closed list then states a rule the compiler no longer follows, the same drift that caused this ticket. So the implementation ticket should test each row and the "no other position" negative." Q2: ""An import entry naming the type" and "a whole-module import" look alike in generated code. A model that writes `import std.errno` and then a bare `Errno(5)` will hit the failure, so the agreed diagnostic must offer the import entry as the machine-applicable fix. If it does not, models will learn the pattern from failures."
- **Minimalism:** Q1: "A future feature that adds a new expression form (for example a new collection literal) may forget to add its row. Then the closed list quietly makes that form give no hint, so the feature's spec change must check this list." Q2: "The import clause makes an import entry load-bearing for name resolution. If the unused-import lint, `blink fmt`, or an LSP "organize imports" action does not count a bare-variant use as a use of the import, a tool can remove the import and break code that compiled."

Process note: the AI/ML seat cast its Phase C vote from the round digests, without reading the other seats' round files.

### Follow-ups

1. Implementation: change the reach of the global-unique step to the four-part candidate set; remove the special case that hides a program's enums from std; add the undefined-name diagnostic with the fix and the poison type; make the unused-import lint count a bare-variant use; add a test for each row of the list.
2. Bug: `{ Red } == A.Blue`, with `A` and `B` both declaring `Red`, is E0519 today. Under the comparison row the site has the expected type `A`, so it must compile (probe `g2.bl` from PLT).
3. The four tests that use a bare `Errno(...)` after `import std.errno.{Errno}` keep working under R1+I with no edit.

### AI-first review

1. Learnability — PASS. One named list says which positions give an expected type; one four-line list says which enums a bare name can mean.
2. Consistency — PASS. The candidate set follows the same package edge as E0518 and E1016, and an import entry decides a bare name as it does for a value.
3. Generability — PASS. A model checks the rule against the file it writes: its package, the prelude and the types its import entries name.
4. Debuggability — PASS. A name that no candidate matches fails at the name, with a fix that names the enum.
5. Token efficiency — PASS. No new syntax; the bare form works wherever the list gives a type.

0 of 5 fail. No flags.
