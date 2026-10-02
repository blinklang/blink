[< All Decisions](../DECISIONS.md)

# Module-Scope Name Collision — Design Rationale

`sections/02_syntax.md` §2.12.1 forbade two module-level `let` bindings of one name, but the compiler
did not implement the rule. On the current compiler (gen1), measured before the panel met:

| Program shape (module scope) | Result |
|---|---|
| `let a` + `let a` | `check` ok; `run` fails in the C compiler (C symbol defined twice) |
| `fn f() -> Int` + `fn f() -> Int` | `check` ok; `run` fails in the C compiler |
| `fn f() -> Int` + `fn f(x: Int) -> Int` | the second declaration wins at typecheck: `f()` is refused for a missing argument |
| `let b` + `fn b`, `const k` + `fn k` | E1016 DuplicateModuleBinding |
| `type P` + `type P`, `trait T` + `trait T`, `type T` + `trait T`, `const k` + `const k`, `const k` + `let k` | `check` ok (silent) |
| `type P` + `fn P` | ok (different namespaces) |

The spec also gave `DuplicateModuleBinding` the code E1009 and `PubLetMutForbidden` the code E1006.
Both codes ship with other meanings (E1009 PackageEntryNotFound, E1006 ImportNotSelected). A second,
stale error table in §10.8 gave E1010 to private item access and E1011 to ambiguous import; those
codes ship as OrphanFile and InvalidPackageName.

## Summary

| Q | Question | Result | Vote |
|---|---|---|---|
| — | Rule: one declaration per name per namespace in module scope; two `fn`s of one name have no winner; E1009 → E1016 in §2.12.1; no shipping code moves | Agreed in Phase A, not on the ballot | 6-0 |
| Q1 | Code for import + declaration | E1012 stays for that pair; E1016 covers two declarations; the spec states the rule once and E1005/E1012/E1016 name which pair collided | 6-0 |
| Q2 | Code for PubLetMutForbidden | E1013 | 5-1 (Systems: E1017) |
| Q2b | Reserve the constant in src/diagnostics.bl; spec row says "not yet enforced" | Yes | 6-0 |
| Q3 | Stale "Compilation Model Errors" table | Delete it; prose and example take E1003 | 5-1 (Web: fix in place) |
| Q4 | Add E1006, E1007, E1013, E1015, E1016 to the main table; E1003 row becomes Private item access, cause text matched to src | Yes | 6-0 |
| Q5 | Spec-vs-src code drift gate in `task ci` | Separate chore that depends on this ticket | 4-2 (DevOps, AI/ML: land with this change); soft consensus, no Phase D |
| Q6 | Diagnostic shape: primary span on the later declaration, N-1 diagnostics, report at name resolution, bind to the first and poison, explain text widened without the C-symbol reason, suggestion-only fix | Yes | 6-0 |

**Q5, no Phase D.** All four majority voters wrote the dissent's point into their own Concern field
("a separate chore can sit in the backlog while new drift creeps in"), AI/ML gave A as second
choice, and DevOps wrote in Phase B: "If the panel prefers, split it into a `type:chore` that this ticket blocks on. But do not drop it."
The user approved the tally with this soft-consensus reading.

Out of scope, filed as separate tickets: enforcing `pub let mut` (src/ uses it widely, so it needs
a 3-step migration), duplicate `test` names (not a binding, needs its own code), and whether a bare
enum variant is a module-scope value (`type Color { Red }` + `fn Red()` is silent today).

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated
in independent-proposal → debate → vote rounds. The text below is each panelist's own, in full.
Headings inside a panelist's text are shown in bold.

#### Phase A — Independent proposals

##### Systems

I'm the Systems panelist. My Phase A proposals for j8tz4f follow.

**Proposal 1 (preferred): one rule, one code (E1016), checked separately in each namespace**

**Rule:** a bare name has one declaration per namespace in module scope.
- The value namespace holds `let`, `let mut`, `const` and `fn`.
- The type namespace holds `type`, type alias, `trait` and `effect`.
- Any two declarations of one name in one namespace give `DuplicateModuleBinding` (E1016). This covers `let`+`let`, `fn`+`fn`, `let`+`fn`, `const`+`const`, `const`+`let`, `type`+`type` and `type`+`trait`.
- E1012 stays the code for an import against a declaration.

```blink
fn f() -> Int { 1 }
fn f(x: Int) -> Int { x }
fn main() { let _ = f() }
```
```
error[E1016]: `f` is declared twice in module `main`
 --> main.bl:2:4
  |
2 | fn f(x: Int) -> Int { x }
  |    ^ second declaration
note: first declaration at main.bl:1:4
help: rename one of them. Blink has no function overloading
```

**No winner.** Two functions of one name have no defined winner, because the program does not compile. The spec should also say that E1016 is the only error for the pair. Today the second `f` wins at typecheck, so the user gets a "missing argument" error that sends them to the wrong line.

**Why this fits the systems view:**
- Each name in a namespace becomes exactly one module-qualified C symbol. Two declarations with one name need two definitions of that symbol.
- Today `let`+`let` and `fn`+`fn` pass `check` and then fail in `cc` with "redefinition". That is a C compiler error that leaks to the user. No Blink diagnostic should come from `cc`.
- Two `type P` declarations become two C typedefs or structs with one name, so they belong in the same rule.
- With this rule in place, the C printer can assert one symbol per name and report an ICE if that breaks. That gives predictable codegen.

**Cost:** one hash set per namespace per module while declarations are collected, so O(n). There is no runtime cost and no ABI change.

**Explain text:** the current E1016 explain text describes only the `let`+`fn` case. Widen it to cover any pair in one namespace.

**Proposal 2: fix the spec's code drift to match what ships (in scope)**

- **§2.12.1:** change E1009 to E1016 for DuplicateModuleBinding. This matches what ships.
- **PubLetMutForbidden:** give it **E1013**, the lowest unused code in both spec and src. Change §2.12.1 and §10 (07:1650) from E1006 to E1013.
- **Do not move any shipping code.** Tests and users match on E1009 PackageEntryNotFound and E1006 ImportNotSelected.
- **Implementing PubLetMutForbidden is out of scope.** The compiler's own `src/` uses `pub let mut` in many files, so enforcing the rule needs a separate 3-step bootstrap ticket. This ticket only reserves the code, so the spec stops pointing at a code that means something else.

I found one more drift the brief does not list:
- The "Compilation Model Errors" table at sections/07:2463 lists E1010 for private item access and E1011 for ambiguous import. What ships is E1003 PrivateItemAccess and E1005 AmbiguousImport. E1010 and E1011 already mean OrphanFile and InvalidPackageName.
- Fix that table, or delete it and point to the main table.
- Add the codes that ship but are missing from the main §10 table: E1006, E1007, E1013 (reserved), E1015 and E1016.

**Proposal 3 (rejected alternatives)**

**3a. Merge the pairs into E1012 DuplicateSymbol.**
- The two cases have different fixes. E1012 has a machine-applicable fix: drop the name from the import list. E1016 has none, because a person must pick which declaration to rename.
- Tools that use the code to pick the fix need the codes kept apart.
- The rule text stays one sentence. The two codes only label which pair collided, as the earlier panel asked.

**3b. One code for each pair (DuplicateFunction, DuplicateType, and so on).**
- This multiplies codes for one rule with one fix. I reject it.

**Out of scope (separate tickets)**

**Bare enum variant against a `fn` (`type Color { Red }` + `fn Red()`).**
- Variant constructors get an enum-qualified C symbol, so there is no C collision.
- The open question is whether a bare variant is a value binding in module scope. That is a name-resolution question and needs its own spec decision.

**Duplicate `test "a"` names.**
- The spec already makes this an error, but it has no code. A test is not a binding.
- Log it as a separate bug and give it its own code, for example E1017 DuplicateTestName. Do not fold it into E1016.

**Cross-language note**

- C reports redefinition at link or compile time with no source-level reason. Blink should not inherit that.
- Rust gives E0428 ("defined multiple times") per namespace, with types and values kept apart. That is the same shape as Proposal 1.
- Go reports "redeclared in this block" for one name across all kinds, because Go has one namespace.
- Zig refuses duplicate members of a container.
- None of these languages defines a winner.

**My preference:** Proposal 1 together with Proposal 2.

##### Web/Scripting

**Web/Scripting panelist: proposals for j8tz4f**

**Proposal 1 (preferred): one rule, one code per namespace pair, spec matches what ships**

**The rule:** in module scope, a bare name has one binding in each namespace. In the value namespace (`let`, `let mut`, `const`, `fn`), any two declarations of one name are `DuplicateModuleBinding` (E1016). The type namespace (`type`, alias, `trait`, `effect`) follows the same rule under the same code. E1012 stays for the import-plus-declaration case only. A type and a value can still share a name, as they do now.

All three cases in the ticket fall under one rule and one code:

```blink
let mut a: Int = 1
let mut a: Int = 2      // error[E1016]

fn f() -> Int { 1 }
fn f() -> Int { 2 }     // error[E1016]

fn f() -> Int { 1 }
fn f(x: Int) -> Int { x } // error[E1016] — no overloading, so a different signature does not help

type P { x: Int }
trait P { }             // error[E1016]
```

What the user sees, with both sites shown:

```
error[E1016]: `f` is declared twice in module `main`
  --> main.bl:2:4
   |
 1 | fn f() -> Int { 1 }
   |    - first declared here
 2 | fn f() -> Int { 2 }
   |    ^ second declaration
   = note: Blink has no function overloading. Module scope has one binding per name.
   = help: rename one of them
```

**Which same-name function wins? Neither.** The compiler gives an error, so the question goes away. Today the second `f(x: Int)` silently wins, and then `f()` fails with "missing argument". That is the worst result. The user reads the first `f`, sees that it takes no argument, and cannot see why the call fails. That will be a Stack Overflow question on day one.

**Spec code drift:** correct the spec, not the compiler.
- §2.12.1: DuplicateModuleBinding E1009 → E1016.
- PubLetMutForbidden E1006 → E1013 (unused in spec and src). Put it in the §10.x table and mark it "not yet implemented", because the compiler does not refuse it yet.
- Add E1007 and E1016 to the §10.x table while we are in it.

Renumbering E1006 or E1009 would break the shipped tests and any user who matches on those codes. That is not worth it to protect numbers in a spec that nobody has implemented.

**Tradeoffs (DX):**
- Developers learn one code with one meaning: "you named two things the same". The message says which two, so the code does not need to.
- The error fires at `check`, not as a C compiler error. A `redefinition of symbol` error from cc is the worst possible message for a scripting user, because it names C, and they never wrote C.
- Cost: a Python user who uses "redefine the function lower in the file" as a habit will see an error. That is a good outcome. pyflakes has F811 "redefinition of unused name" because that habit hides bugs.

**Cross-language:** Python and JS (`function f` twice) let the last one win silently, and both ecosystems added linters to catch it. TypeScript gives TS2393 "Duplicate function implementation". Go gives "f redeclared in this block". Kotlin gives "Conflicting overloads". Blink should match TS and Go, and give it at compile time.

**Proposal 2 (second choice): put E1012 into E1016**

Use one code for every module-scope collision, from imports or from declarations. A user does not care how the second binding got there.

Rejected as first choice: E1012 merged today with its own fix rule (drop the name from the import list, which a tool can apply). A declaration-plus-declaration collision has no safe automatic fix. When two cases have different fixes, they should have different codes. The panel also just voted on E1012, so reopening it costs more than it gains.

**Proposal 3 (rejected): one code per pair (DuplicateFunction, DuplicateConst, ...)**

This gives more codes to learn for the same mistake, and more pages to look up. No gain for the 90% case.

**Scope**

**In scope:** the value-namespace rule (`let`/`const`/`fn`), the type-namespace rule, no winner for two same-name functions, and the spec code corrections.

**Out of scope, log separately:**
- **Bare enum variant vs `fn Red()`.** This needs a decision on whether a variant is a module-scope value binding. It is a real ambiguity for a reader, but it needs its own panel.
- **Duplicate `test "a"` names.** The spec already says this is an error. This is a bug ticket, not spec work. Use its own code, because a test name is a string, not a binding.
- **Making the compiler refuse `pub let mut`.** The compiler's own src/ uses `pub let mut` widely, so this needs a 3-step migration. Assign the code now, and implement it in a separate ticket.

**Preferred: Proposal 1.**

##### PLT

**PLT panelist: Phase A proposals for j8tz4f**

**The rule (the basis for every proposal)**

A module scope is two finite maps, one per namespace: type names to declarations, and value names to declarations. A map has at most one entry per key. A second declaration of a key is not a shadow and not an overload. It is an ill-formed environment. This is the "flat namespace" rationale already decided, stated as a well-formedness condition.

Module declarations do not depend on order: a `fn` can call a `fn` that comes after it. So "the later declaration wins" has no meaning. It would make source order part of the semantics in one place only. Without overloading, two `fn f` have no defined winner, whatever their signatures. Today the checker lets the second one win when the arity differs (`f()` is refused for a missing argument). That is a bug, not a rule.

Enum variants are not module-scope bindings. §3 resolves a bare variant through the type hint, then a program-wide unique search, and never through the module map. So `type Color { Red }` + `fn Red()` is **out of scope**. It needs its own ticket. Test names are strings, not bindings, so duplicate `test` names are also **out of scope** (separate ticket, separate code).

**Proposal 1 (preferred): one rule, three codes, each code names the kind of pair**

| Pair in one module scope, one namespace | Code |
|---|---|
| import + import | E1005 AmbiguousImport (ships) |
| import + declaration | E1012 DuplicateSymbol (decided) |
| declaration + declaration | **E1016 DuplicateModuleBinding**, widened |

E1016 covers every declaration kind in its namespace. In the value namespace that is `fn`, `let`, `let mut` and `const`. In the type namespace it is `type`, alias, `trait` and `effect`. A type name and a value name do not collide.

```blink
const k: Int = 1
let k = 2                    // error[E1016]

fn f() -> Int { 1 }
fn f(x: Int) -> Int { x }    // error[E1016]: no overloading, no winner

type T { a: Int }
trait T { fn m(self) -> Int } // error[E1016]: type namespace

type P { a: Int }
fn P() -> Int { 1 }          // OK: two namespaces
```

```
error[E1016]: `f` is declared twice in module `main`
 --> main.bl:2:4
  |
2 | fn f(x: Int) -> Int { x }
  |    ^ second declaration
  = note: first declared at main.bl:1:4
  = help: rename one of them; Blink has no function overloading
```

Report one diagnostic for each declaration after the first, and point it at the first. To prevent cascades, bind the name to the first declaration and mark the name as poisoned, so that uses of it give no more errors.

Spec edits:
- §2.12.1 changes E1009 to E1016 and widens the rule from "two `let`" to "two declarations in one namespace".
- Rewrite the E1016 explain text. Remove the C-symbol reason, because a language rule must not rest on a backend detail. The C clash is a result of the ill-formed scope, not its cause.

Tradeoffs:
- The three codes split the collisions into separate cases that do not overlap. The fixes are different: E1012 has a fix that a machine can apply (drop the name from the import), and E1016 needs a rename. So separate codes give real information.
- The cost is three codes for one rule. The spec must say once that it is one rule with three labels.

**Proposal 2: one code for all collisions in module scope**

Fold E1012 into E1016. One rule gets one code. I reject this: E1005 ships, E1012 was decided today, and the fixes differ. Merging the codes removes information and gives nothing back in soundness.

**Proposal 3: fix the code drift (in scope, with Proposal 1)**

- PubLetMutForbidden moves from E1006 to **E1017**, which is the next free code. It is a visibility rule, not a collision, so it must not share E1016. Do not reuse E1013 or E1014. A gap in the numbers is cheaper than an argument later about whether a number was reserved. The *implementation* of PubLetMutForbidden, and the migration of `pub let mut` out of src/, is **out of scope**. It needs the 3-step migration and its own ticket.
- Add E1016, E1017 and E1007 to the §10.x error table.
- **Adjacent drift, also in scope:** the "Compilation Model Errors" table in §10 (sections/07, near line 2463) and its prose and example (near lines 2407 and 2423) give E1010 to private item access and E1011 to ambiguous import. These clash with E1003, E1005, E1010 OrphanFile and E1011 InvalidPackageName. Change them to E1003 and E1005. This ticket exists to fix code drift, so leaving this drift would defeat it.

**Cross-language note**

- Haskell's top-level declarations do not depend on order, and Haskell refuses any duplicate in each namespace ("Multiple declarations of 'f'"). Blink's module scope has the same structure, so it must follow the same rule.
- Rust E0428 ("defined multiple times") is one rule for each namespace and covers all item kinds.
- OCaml lets a later `let x` shadow an earlier one in a structure. It can do that only because structures are evaluated in order. Blink modules are not, so OCaml is the wrong model here.

**Preferred: Proposal 1, together with Proposal 3.**

##### DevOps

**DevOps/Tooling panelist: Phase A proposals for j8tz4f**

**Fact check first.** The drift is wider than the ticket says. sections/07 has a second table, "Compilation Model Errors" (around line 2463). It gives E1010 to Private item access and E1011 to Ambiguous import. What ships is E1003 and E1005. The main §10 table also leaves out E1006, E1007, E1015 and E1016, which all ship. So the spec disagrees with itself as well as with src/.

**Proposal 1 (preferred): one rule, two codes, split by fix shape**

Spec rule: **a bare name has one binding per namespace in module scope.**

- **E1016 DuplicateModuleBinding** covers two *declarations* of one name in one namespace of one module:
  - Value namespace: `let`/`let`, `fn`/`fn`, `let`/`fn`, `const`/`const`, `const`/`let`, `const`/`fn`.
  - Type namespace: `type`/`type`, `type`/`trait`, `trait`/`trait`, alias, `effect`.
- **E1012 DuplicateSymbol** stays as decided: an *import* and a declaration of one name.

The test for one code or two: does the fix differ? It does. For E1012, "drop the name from the import list" is machine-applicable. For E1016 the only fix is a rename, which a tool cannot pick. An LSP quick-fix keyed on the code gets the right action with no extra logic. If one code covered both, every tool would have to inspect the spans to choose the fix.

**Same-name functions: no winner.** Today the second declaration wins silently at typecheck. That is the worst result for tools: hover and go-to-definition point at one body while the user reads the other. Make it E1016.

```blink
fn f() -> Int { 1 }
fn f(x: Int) -> Int { x }
fn main() { let _ = f() }
```
```
error[E1016]: `f` is declared twice in module `main`
 --> main.bl:2:4
  |
1 | fn f() -> Int { 1 }
  |    - first declaration (fn)
2 | fn f(x: Int) -> Int { x }
  |    ^ second declaration (fn)
  = note: module scope has one binding per name; Blink has no function overloading
  = help: rename one of them
```

Type namespace:
```
error[E1016]: `T` is declared twice in module `main` (type namespace)
 --> main.bl:4:7
  |
1 | type T { a: Int }
  |      - first declaration (type)
4 | trait T { fn go(self) }
  |       ^ second declaration (trait)
```

Rules that keep output stable for tools:
- The primary span is the later declaration, in source order. The secondary label marks the first.
- With N declarations, emit N-1 diagnostics, each pointing back at the first. One mistake gives one diagnostic per extra declaration.
- Report E1016 at name resolution, before typecheck. Then no follow-on type errors come from the losing declaration.
- Keep the name `DuplicateModuleBinding`. tests/test_diagnostics_module_let_and_fn_of_one_name.bl matches on it, and renaming it breaks name matchers for no gain.
- Widen the E1016 explain text. It now says "a binding and a function", which is too narrow. Keep the C-symbol sentence out of it: that is an implementation detail, not the reason for the rule.

**Spec codes.** Correct the spec to match what ships. Do not move E1006 or E1009. They ship, tests match on them, and so might user scripts and CI filters. Changing a shipped code is a breaking change for every tool that matches on it. Go and rust-analyzer users rely on that stability.

- §2.12.1: DuplicateModuleBinding becomes **E1016**.
- PubLetMutForbidden gets a new code, **E1017**. Do not fill E1013 or E1014. We cannot prove they were never handed out in an earlier release, and reusing a retired code is the same break in another form (Rust never reuses codes).
- Fix the "Compilation Model Errors" table to E1003 and E1005, or delete it and point to the main table.
- Add E1006, E1007, E1015, E1016 and E1017 to the main table.

Cross-language: Rust uses one code for "defined multiple times" (E0428) and separate codes for import-vs-item clashes (E0255). That is the same split as this proposal. Go has one message, "x redeclared in this block". TypeScript splits by declaration kind (TS2300, TS2393, TS2451), and users find that noisy to filter.

**Proposal 2: a gate so the drift does not come back**

Add a check to `task ci`: parse every `| Exxxx |` row in sections/ and diff it against the `pub const ... = "Exxxx"` lines in src/diagnostics.bl.
- Fail when one code has two meanings across tables.
- Fail when a shipped code is missing from the spec.
- Allow spec-only codes only with a marker such as "not yet enforced".

This is how both drifts happened: nothing compared the two lists. The cost is one script. This is tooling, not language, so it can land as a chore under this ticket.

**Proposal 3 (rejected): one code for every module-scope collision**

Fold E1012 into E1016, or the reverse. It is simpler to read in a table but worse for tools, for the reason in Proposal 1: one code would then map to two fixes, one machine-applicable and one not. I vote against it.

**Scope**

**In scope:**
- The three ticket cases and all value-namespace and type-namespace pairs, under E1016.
- The spec code corrections.
- The E1017 assignment.
- The table repair.
- Proposal 2.

**Out of scope (separate tickets):**
- **Implementing PubLetMutForbidden.** src/ uses `pub let mut` widely, so it needs the 3-step bootstrap migration. Assign the code now and mark it "not yet enforced".
- **Bare enum variant vs `fn` of one name** (`type Color { Red }` + `fn Red()`). Whether a variant is a value binding is a PLT question. Answer it before tools rely on it.
- **Duplicate `test "a"` names.** Tests are not bindings, so do not put them under E1016. They need their own code (E1018 or an E05xx test code). The spec already says this is a compile error, so it is an implementation bug, not a spec gap.

**Preferred:** Proposal 1 plus Proposal 2.

##### AI/ML

**AI/ML panelist: Phase A proposals for j8tz4f**

**Proposal 1 (preferred): one rule, one code for every pair of declarations, and no winner**

**Rule.** In module scope, a bare name has one binding in each namespace. This makes any two module-level declarations of one name in the same namespace a compile error, E1016 DuplicateModuleBinding:
- **Value namespace:** `let`, `let mut`, `fn`, `const`.
- **Type namespace:** `type`, alias, `trait`, `effect`.

E1012 stays for an import colliding with a declaration. The rule is the same. The code only says which pair collided, and the fix differs:
- **E1016:** rename one declaration or delete it.
- **E1012:** drop the name from the import, or alias it.

Two same-name functions have **no winner**. Blink has no overloading, so the spec must not define "last one wins" or "first one wins". Both declarations are the error.

```blink
fn parse(s: Str) -> Int { 0 }

fn parse(s: Str) -> Int {   // error[E1016]
    s.len()
}
```

```
error[E1016]: `parse` is declared twice in module `main`
 --> src/main.bl:3:4
  |
1 | fn parse(s: Str) -> Int { 0 }
  |    ----- first declared here
3 | fn parse(s: Str) -> Int {
  |    ^^^^^ declared again here
  |
  = help: Blink has no function overloading. Delete one declaration,
          or rename one of them
```

Type namespace, same code:

```blink
type Shape { w: Int }
trait Shape { fn area(self) -> Int }   // error[E1016]: `Shape` is declared twice in module `main`
```

**Why this matters for AI.** The two-function case is a common LLM failure. To "fix" a function, a model often adds a new copy below the old one and leaves the old one in place. Today Blink's behaviour depends on the signatures:
- Two identical signatures pass `check` and then fail in the C compiler. The model sees an error about C symbols, not Blink, and has nothing to act on.
- Two different signatures let the second one win silently. The model then gets a misleading "missing argument" error at a call site far from the real cause.

A clear E1016 with both spans gives the model one action: delete the stale copy. Both spans matter, because the model must see which copy is old.

The fix is a **suggestion only, never machine-applicable**. The compiler cannot know which copy is the intended one. If an auto-fix deleted the wrong copy, the model's new work would be lost without notice.

**Decision points.** One rule and two codes. A model learns one sentence: "one bare name, one binding per namespace in module scope". It does not have to learn a separate case for each declaration kind.

**Cross-language.**
- **Rust:** E0428 ("the name is defined multiple times") covers every item kind under one code, per namespace. This is the closest match to this proposal.
- **Go:** "`f` redeclared in this block", with a note at the other declaration.
- **Python:** the last definition silently wins. This is a known source of bugs in generated code, and it is the behaviour we have today for functions with different signatures.

**E1016 explain text.** Generalise the "binding and a function" text to "two module-level declarations in one namespace". Remove the C-symbol reason. It is an implementation detail. A model learns more from the namespace reason.

**Proposal 2: correct the spec's codes to match what ships**

I agree with the ticket. Do not move shipping codes. Tests and users match on E1006 and E1009, and a model trained on current output would learn wrong codes if they move.

In §2.12.1 and the §10.x table:
- DuplicateModuleBinding becomes **E1016**.
- PubLetMutForbidden takes a free code, **E1013** (unused in both spec and src). It stays a separate code because its fix is different: expose the state through a function.
- Add the missing rows to the table: E1006, E1007, E1013, E1015, E1016.

A model that reads the spec must find the same code that the compiler prints. Drift between the two is worse than an ugly number.

PubLetMutForbidden is still not implemented, and src/ uses `pub let mut` widely. The implementation needs the 3-step migration. That is a separate implementation ticket. This ticket fixes only the spec text.

**Proposal 3: adjacent items, out of scope with follow-up tickets**

1. **Duplicate `test "a"` names.** Test names are not bindings, so E1016 is the wrong label. Give them their own code, for example E1014 DuplicateTestName. That keeps E1016's text accurate. Implementation follow-up.
2. **Enum variant vs. `fn Red`.** Is a bare variant a module-scope value binding? That needs its own spec decision. Do not fold it in here, because the answer depends on the variant-resolution rules (§ bare variant patterns).

**Tradeoffs**

- **One code for everything (E1012 widened, E1016 removed)** gives fewer codes. But the help text for import collisions ("drop from the import list") is wrong for two local declarations. When a code says exactly what to fix, a model corrects its code in one try. When it does not, the model tries a few fixes until one works.
- **A separate code for each declaration kind** adds decision points with no gain. A model would have to learn many codes for one rule.

**Preferred:** Proposals 1 and 2 together, with Proposal 3 filed as follow-ups.

##### Minimalism

**Minimalism panelist: Phase A proposals for spec ticket j8tz4f**

**Facts I checked (read-only)**
- `sections/07` §10 error table already lists E1009 as Package entry not found. The spec contradicts itself: §2.12.1 says E1009 is DuplicateModuleBinding.
- `sections/07` lines ~2459-2464 have a second, stale "Compilation Model Errors" table. It lists E1010 Private item access and E1011 Ambiguous import, which conflicts with the main table (E1003, E1005, E1010, E1011). This is more of the same drift.

---

**Proposal 1 (preferred): one rule, one code, the code that already ships**

**Rule:** in one module, a bare name has one binding per namespace. Any two module-scope bindings of one name in one namespace are a compile error. "Two bindings" covers two declarations, or a declaration and a selective import. There is no winner and no "last one wins".

**Code:** E1016 DuplicateModuleBinding is the single code. It ships, it has explain text and it has a test. E1012 DuplicateSymbol is spec-only, so retiring it breaks no user. Mark E1012 retired in the table and do not reuse it. The text says which pair collided. The code does not.

```blink
fn f() -> Int { 1 }
fn f(x: Int) -> Int { x }   // error[E1016]
fn main() { let _ = f() }
```
```
error[E1016]: `f` is declared twice in module `main`
  first declared here: line 1 (fn)
  again here: line 2 (fn)
  Blink has no function overloading. Rename one of them.
```
```blink
import alpha.{Point}
type Point { x: Int }       // error[E1016]: `Point` is both imported from `alpha` and declared
```
```blink
type Shape { w: Int }
trait Shape { }             // error[E1016]: `Shape` is declared twice (type, trait)
```

The rule covers every case in the brief's table. The value namespace is `let`/`fn`/`const` in any pair. The type namespace is `type`/alias/`trait`/`effect` in any pair. `type P` + `fn P` stays legal, because those are two namespaces and that is already decided. The "drop the name from the import list" fix still attaches to the import+declaration case. A fix belongs to the diagnostic instance, so it does not need its own code.

**Tradeoffs:** This adds no new code and removes one (E1012). One rule gets one code, which is what the prior panel asked for ("the codes only label which pair collided"). An agent can match one code for "rename or drop one". The cost is that tooling cannot tell the import case from the declaration case by code alone. The message and the attached fix carry that difference. E1005 AmbiguousImport (import + import) stays as it is: it ships, and its fix (use a qualified path) is different.

**Cross-language:** Go has one error for every case ("x redeclared in this block"). Python silently keeps the last definition, which is the bug this rule prevents. Rust splits it into E0428 and E0255. That split adds surface and gives the user nothing.

**Proposal 2: two codes (E1012 for import + declaration, E1016 for declaration + declaration)**

This keeps today's merged text and only widens E1016. The cost is two codes for one rule, and E1012 still has to be implemented under its own name. I reject it, but it does break nothing.

**Proposal 3: widen E1012 and retire E1016**

E1016 ships and has a test. Moving it breaks users for no gain. I reject it.

---

**Code drift (part 2): correct the spec, move no shipping code**

- §2.12.1: E1009 → E1016.
- PubLetMutForbidden: remove the number E1006 and leave it as "code assigned when implemented". The drift happened because the spec gave out numbers that src never reserved. A number given out before the code ships will drift again. If the panel wants a number now, use E1013 and add it to `src/diagnostics.bl` in the same change.
- Add E1007 ModuleQualifiedType to the table, because it ships.
- **Delete** the stale "Compilation Model Errors" table, since the main table already covers it. Removing text is the cheapest fix.
- The E1003 row: the table says "Item not found"; src says PrivateItemAccess. Align the table to src.

**Out of scope (file separate tickets, do not decide here)**

- **Implementing `pub let mut` refusal.** The decision exists. The compiler's own src uses `pub let mut` widely, so this is a 3-step migration and needs a `type:feature` ticket.
- **Duplicate `test "a"` names.** The spec already says this is an error, so it is a `type:bug`. A test name is a string, not a binding, so it should not use E1016. Its code gets chosen at implementation time.
- **Bare enum variant vs `fn Red`.** Whether a variant is a module-scope value binding is a new language question. It needs its own `type:spec` ticket and should not be stretched into this one.

**Preferred:** Proposal 1, plus the part-2 corrections.

#### Phase B — Debate, round 1

Phase B ran one round on the deduped option space. All six panelists ended with "STABLE — ready to vote".

##### Systems

**Phase B round 1 — Systems (sys)**

**Q1: I keep Q1-A.** E1012 covers an import and a declaration. E1016 covers two declarations.
- min says the fix belongs to the diagnostic instance. That is true for an LSP that reads the attached fix. But CI filters, `blink check --format json` consumers and agents switch on the code first.
- One code with two fix shapes, where one fix is machine-applicable and the other is not, makes every consumer inspect spans. devops and plt make the same point.
- The rule text stays one sentence. The codes only label the pair, as the prior panel asked. E1012 was decided 6-0 today. I see no new fact that reopens it.

**Q2: I move from E1013 to E1017 (Q2-B). I also adopt min's "reserve it in src in the same change".**
- devops worries that E1013 or E1014 was handed out in an earlier release. I checked git history: `git log -S'E1013'` and `-S'E1014'` find nothing. So E1013 is safe.
- Even so, an allocation policy beats a one-off choice. "New codes append after the highest code in use; gaps stay gaps" is a rule anyone can apply without searching history. That is the predictable choice.
- Q2-C (no number in the spec) leaves the spec text without a code for a decided rule. The root cause of the drift is that the spec gave out a number that src did not hold. So add `pub const PUB_LET_MUT_FORBIDDEN = "E1017"` to src/diagnostics.bl in this change, and mark the spec row "not yet enforced". That closes min's concern and keeps a number in the text.

**Q3: I prefer Q3-B, delete the table.** I accept Q3-A as a fallback.
- Two tables for one code space are how this drift started. One table means one place to update.
- Correct the prose and example at 07:2407 and 07:2423 to E1003 either way, because they are not a table.

**Q4: add E1006, E1007, E1015, E1016 and E1017 (marked "not yet enforced").** I also agree with min: align the E1003 row title to PrivateItemAccess. The spec table should use the names that src ships.

**Q5: I support Q5-A, the drift gate, as a chore under this ticket.**
- The gate is one script with no runtime or codegen cost. It turns "one code, two meanings" into a gate failure instead of a user surprise.
- The "not yet enforced" marker from Q2 and Q4 is exactly the input it needs.
- If the panel thinks a CI gate is out of scope for a `type:spec` ticket, file it as a separate chore. Do not drop it.

**Variations: I agree with all of them, with two notes.**
- Bind the name to the first declaration, poison it, and report at name resolution before typecheck. This stops the "missing argument" cascade that the measured `fn f()` + `fn f(x: Int)` case shows today.
- Drop the C-symbol sentence from the E1016 explain text. plt is right that a language rule must not rest on a backend detail. The systems reason stays as an implementation invariant: the C printer asserts one C symbol per module-qualified name and raises an ICE if that breaks. No collision may ever reach `cc` again. This goes into implementation notes, not spec text.
- N-1 diagnostics, a primary span on the later declaration, and a suggestion-only fix: I agree with all three.

STABLE — ready to vote

##### Web/Scripting

**Web/Scripting — Phase B round 1 (j8tz4f)**

P1–P6: agree.

**Q1: Q1-A (E1012 for import + declaration, E1016 for declaration + declaration)**

To min: I agree that "one rule, one code" is the easiest thing to learn. But a user does not read the code number first. They read the message and the fix. The fixes differ: dropping the import is safe for a tool to apply, and a rename is not. If one code maps to two fixes, every editor quick-fix has to look at the spans to pick one. That is the same work done again in every tool. Also, E1012 got a 6-0 vote today. A ticket about code drift should not reopen a code that was just decided. Holding A.

**Q2: Q2-A (E1013), and change it to Q2-B if needed**

devops says we cannot prove that E1013 was never handed out. I checked (read-only): `git log -S` finds no commit that adds or removes `E1013` or `E1014`, in src/ or sections/, over the full history (v0.7.0 to v0.9.0 tags included). So it was never used, and filling the gap breaks nobody. I still prefer E1013. A gap in the numbers makes people ask "what was E1013?" (and that becomes a Stack Overflow question).

This is a weak preference. E1017 also breaks nobody. If the vote goes to Q2-B, I accept it.

To min (Q2-C): I agree that the number must ship together with the check. But a spec row with no number reads as unfinished to a user. Assign the number and mark the row "not yet enforced". With the Q5 gate, that marker keeps it honest.

**Q3: Q3-A (correct the codes to E1003/E1005)**

I did not address this in Phase A. I agree that the clash is real. I prefer to fix it in place, not delete it. That table sits next to the compilation-model prose and its examples. A reader who lands there from a search wants the code in front of them, not a link. Q3-B is also fine if the prose and example at ~2407/~2423 get fixed too. Deleting only the table would leave wrong codes in the example.

**Q4: rows**

Add E1006, E1007, E1015, E1016 and the PubLetMutForbidden code (marked "not yet enforced"). Agree with min: align the E1003 title to PrivateItemAccess. The title in the table must be the name the compiler prints. No disagreement.

**Q5: Q5-A (gate)**

Yes. Two separate drifts happened because nothing compared the lists. A user who searches an error code and finds the wrong meaning in the spec loses trust in every page of the docs. One script is a small cost. Land it as a chore under this ticket.

**Diagnostic shape**

I agree with all of them: the primary span on the later declaration, N-1 diagnostics, resolution at name binding with the poisoned name, the widened explain text with no C-symbol reason, and the fix as a suggestion only. The C-symbol reason must go. A scripting user has never seen the C, and the rule stands without it.

STABLE — ready to vote

##### PLT

**PLT, Phase B round 1 (j8tz4f)**

**Q1: Q1-A (E1012 for import + declaration, E1016 for declaration + declaration)**

I agree with min on the rule: there is one rule. But one rule does not need one code. Q1-B is not consistent with itself. It keeps E1005 for import + import, and that pair breaks the same rule ("one binding per name in module scope"). If one rule needed one code, E1005 would have to merge as well, and nobody proposes that. Once E1005 stays separate, the panel already accepts this model: one rule, and codes that label the pair. The earlier panel said this in words: "the codes only label which pair collided." The three pairs are import/import, import/declaration and declaration/declaration. They do not overlap, and each pair has a different fix: qualify the name, drop it from the import list, or rename a declaration. A code that maps to exactly one kind of fix is a better label than a code that needs the spans to select the fix. min is right that retiring E1012 breaks no user. That shows Q1-B is possible. It does not show that Q1-B is better.

**Q2: change to Q2-A (E1013), with min's condition from Q2-C**

My Phase A argument for E1017 was risk: maybe someone gave out E1013 or E1014 before. I checked: `git log -S` finds no `E1013` or `E1014` in the history of src/ or sections/. No one has ever used these codes, so the risk that devops and I named does not exist. The lowest free code is the simplest choice that has no cost. I also accept min's root cause: the drift happened because the spec gave out numbers that src never reserved. So assign E1013 **and** add `pub const PUB_LET_MUT_FORBIDDEN = "E1013"` to src/diagnostics.bl in the same change, with a "not yet enforced" marker in the spec table. Then the number is reserved in both places. A spec that leaves out the number has a gap, and a spec number that src does not hold invites the drift again.

**Q3: change to Q3-B (delete the stale table)**

Two tables that list one set of facts can disagree. That is how this drift started. Delete the "Compilation Model Errors" table and point to the main §10 table. The prose and the example near 07:2407 and 07:2423 stay, so change their codes from E1010 to E1003. That edit is needed with either option.

**Q4: add E1006, E1007, E1013 (not yet enforced), E1015 and E1016**

I agree with min's change to the E1003 title, on one condition. The row's "Cause" text must still match what src reports. If src does not use E1003 for "item does not exist", remove that clause too. Do not change only the title.

**Q5: Q5-A, as a chore that this ticket blocks**

The drift gate fixes the cause. Without it, this ticket fixes only the symptoms. It is tooling, not language, so file it as a `type:chore` that depends on this ticket. Do not put it in the spec text.

**Variations**

I agree with all of them. The two points from devops and me are compatible: report the duplicate at name resolution, and bind the name to the first declaration so it does not cause later errors. The E1016 fix is a suggestion only, because a tool cannot choose which declaration to rename. Remove the C-symbol sentence from the explain text. sys's systems reason (one name, one C symbol) is true, but it is a result of the rule. It is not the reason for the rule.

STABLE — ready to vote

##### DevOps

**DevOps/Tooling: Phase B round 1 (j8tz4f)**

P1–P6: agree.

**Q1: Q1-A (E1012 for import + declaration, E1016 for declaration + declaration).**
min says a fix belongs to the diagnostic instance, so one code is enough. That is true for an LSP code action. It is not true for the other tools that key on the code alone:
- `blink explain E10xx` gives one fix story per code. With Q1-B, the E1016 text must say "rename one, or if one side is an import, drop it from the list", which is two fixes in one entry.
- `@allow`/lint config, CI log filters and agent retry logic match on the code, not on the instance. "Drop from import list" is safe to auto-apply on plain `import`. "Rename" never is. One code mixes a safe class with an unsafe class.
- E1012 was merged 6-0 today with its text, its fix rule and its interaction with W0602. Q1-B reopens that decision for a small saving. One extra spec-only code costs nothing to users.
min's Rust point ("the split gives the user nothing") is about reading the message. My point is about tools matching on the code, and there the split pays.

**Q2: change to Q2-A (E1013).** My reason for E1017 was "we cannot prove E1013/E1014 were never handed out". I checked: `git log -S` shows E1013 and E1014 never appear in the history of src/ or sections/. No user can have matched on them, so filling the gap breaks nothing. I withdraw E1017.
On Q2-C: I disagree with "no number until implemented". A spec rule with no code cannot get a row in the table or in the Q5 gate, and the next new diagnostic may take the number. Do min's fallback: E1013 in the spec, marked "not yet enforced", and a reserved `pub const PUB_LET_MUT_FORBIDDEN = "E1013"` in src/diagnostics.bl in the same change. Then src reserves the number, and the drift that caused this ticket cannot happen again.

**Q3: Q3-B (delete the table), and fix the prose too.** Two tables for one code range is how the drift began. Keep one source. Whichever option wins, the prose and example at 07:2407 and 07:2423 still say E1010 for private access. They must change to E1003, or the deletion leaves the same error in the text.

**Q4: agree with the full list:** E1006, E1007, E1013 (not yet enforced), E1015, E1016. Also align the E1003 row title to PrivateItemAccess (min). The title and the src name should match, because tools print the name.

**Q5: keep Q5-A.** No one argued against it. The others simply did not address it. This ticket exists because nothing compares the spec table to src. Every fix in Q1–Q4 is a manual correction that will drift again without a check. The cost is one script in `task ci`, with no language change. If the panel prefers, split it into a `type:chore` that this ticket blocks on. But do not drop it.

**Variations:** I agree with all of them. The two cascade points work together: plt binds the name to the first declaration and marks it poisoned, and I report at name resolution, before typecheck. The fix for E1016 is a suggestion only (aiml).

STABLE — ready to vote

##### AI/ML

**AI/ML panelist: Phase B round 1 (j8tz4f)**

**Q1: Q1-A (E1012 for import + declaration, E1016 for declaration + declaration).**
min says the fix can belong to the diagnostic instance, so one code is enough. In practice a model reads the code and the title first, and it uses them to choose its next edit. The two cases need opposite edits: E1012 needs an edit to the import line, and E1016 needs a rename or a delete of a declaration. With one code, the model must read the spans to choose. That is one more decision point, and it is the point where models make the most errors. Rust (E0428 and E0255) and devops's quick-fix argument support this split. E1005 also shows that Blink already labels a collision by the kind of pair. So Q1-A is consistent and Q1-B is not.

**Q2: Q2-A (E1013). I also accept E1017.**
devops says we cannot prove that E1013 was never given out. We can. `git log -S'"E1013"' -- src` and `git log -S'E1013' -- sections` both return nothing. The same is true for E1014. No release ever printed these codes, so this is not reuse. For a model, the number has no meaning, and a gap or no gap costs nothing. I will not block E1017.
Q2-C (no number until the check is implemented) is acceptable to me only together with Q5. Without a gate, a code that is not yet enforced will drift again. With a gate, it is better to give the number now and mark the row "not yet enforced". The spec then shows a model the full set of codes.

**Q3: Q3-B (delete the stale table, point to the main §10 table) and correct the prose and example near 07:2407 and 07:2423 to E1003 and E1005.**
Two tables that list the same codes are two sources of truth. A model that reads one table learns wrong codes. A pointer costs fewer tokens and cannot drift. Deleting the table does not fix the prose, so the prose must change in either case.

**Q4: add E1006, E1007, E1015, E1016 and the PubLetMutForbidden code.**
I agree with min: align the E1003 row title to PrivateItemAccess. The spec and the compiler output must use the same words, because a model searches the spec for the name it sees in the error.

**Q5: Q5-A (gate). I support it.**
This ticket exists because nothing compares the spec with src. The cost to models is real: the spec is the training and retrieval text (`blink llms`), and each wrong code in it gives a wrong lesson. One script removes this class of error. It is a chore under this ticket, not a language change, so it does not expand the spec decision.

**Variations.**
- Primary span on the later declaration, secondary label on the first, and N-1 diagnostics: agree.
- Report E1016 at name resolution and mark the name as poisoned: agree. Cascade errors from the losing declaration are the main thing that makes a model "fix" the wrong place.
- Widen the E1016 explain text and drop the C-symbol reason: agree.
- The E1016 fix is a suggestion only: I hold this. The compiler cannot know which copy is new. Can the panel state it in the spec, so that no tool adds an auto-delete later?

STABLE — ready to vote

##### Minimalism

**Phase B round 1 — Minimalism (j8tz4f)**

I agree with P1–P6.

**Q1: import + declaration code — I move to Q1-A**

I proposed Q1-B to save one code. The others make a fair case. The two pairs have different fixes: the import case has a fix that a tool can apply, and the declaration case only has a rename. Rust uses the same split (E0255 against E0428). E1012 was also decided 6-0 today, and keeping it costs one table row and no new surface. That is a cost I accept. One condition: the spec must state the rule once ("a bare name has one binding per namespace in module scope"), and list E1005/E1012/E1016 as labels for which pair collided, as PLT wrote. It must not read as three rules.

**Q2: PubLetMutForbidden code — Q2-A (E1013), and drop my Q2-C**

Devops says we "cannot prove E1013/E1014 were never handed out". We can. `git log -S'"E1013"' -- src` and `-S'E1013' -- sections` return nothing, and the same is true for E1014. No release and no spec text has ever used either code. So filling E1013 breaks nothing. Leaving a hole buys nothing. PLT wants a gap so no one argues later about whether a number was reserved. The fix for that is to reserve it in src: add the const to src/diagnostics.bl in the same change, marked not yet enforced. That is the part of my Q2-C that I keep. Then spec and src agree today, and the Q5 gate can check them. I drop "no number until implemented", since the panel wants a number now and a reserved const solves my concern.

**Q3: stale table — Q3-B (delete), with prose fixes**

Two tables for one set of codes caused this drift, so a second copy is a defect in itself. Delete the "Compilation Model Errors" table and point to the main §10 table. The prose and example at 07:2407 and 07:2423 still need their codes corrected to E1003 (and E1005 where it applies), whatever we do with the table. If the panel prefers Q3-A, I accept it. It is the second-best option, not a wrong one.

**Q4: rows to add**

Add E1006, E1007, E1015, E1016 and E1013 (marked not yet enforced). I keep the E1003 title fix: the main table says "Item not found ... or isn't pub", and src says PrivateItemAccess. That is small drift of the same kind. I will not block on it.

**Q5: drift gate — Q5-A, as a separate chore**

The gate goes at the root cause: nothing compares the two lists. It is one script and adds nothing to the language. I support it. File it as a chore that depends on this ticket, so this spec ticket does not wait on tooling work.

**Variations**

I agree with all of them: primary span on the later declaration, N-1 diagnostics, poisoning the name, reporting at name resolution, widening the explain text and removing the C-symbol reason, and a fix that is a suggestion only. I dispute nothing.

STABLE — ready to vote

#### Phase C — Final vote

##### Systems

**Phase C ballot — Systems (sys)**

**Q1**
- Vote: A
- Reasoning: The two pairs have different fixes. One fix a tool can apply (drop the name from the import), and the other a person must choose (rename). With a code per fix shape, every consumer can switch on the code and not read the spans. The rule text stays one sentence, so this adds no semantic surface.
- Concern: E1012 is still spec-only. If it is not implemented soon, the import + declaration case may reach codegen and fail in `cc`, as `let`+`let` does today.

**Q2**
- Vote: B
- Reasoning: "New codes go after the highest code in use; gaps stay gaps" is a rule that anyone can apply without searching history. I checked git, and E1013 was never used, so A is also safe. B is the more predictable rule for the future.
- Concern: The number is only safe if src holds it too. Without Q2b it will drift the same way E1006 did.

**Q2b**
- Vote: Yes
- Reasoning: The drift happened because the spec gave out numbers that src did not hold. A `pub const` in src/diagnostics.bl claims the number at no runtime cost, and the marker tells readers the rule does not fire yet.
- Concern: An unused constant may get removed in a cleanup unless the marker or a lint keeps it.

**Q3**
- Vote: B
- Reasoning: Two tables for one code space are what produced this drift. One table gives one place to update.
- Concern: Some text may link to the deleted table and become a dead link. Check it with a grep.

**Q4**
- Vote: Yes
- Reasoning: The spec table must list every code that ships, under the name that src reports. Otherwise users who match on codes have no reference.
- Concern: The E1003 cause text must match what the compiler really reports, which is private access or not found. Verify it against the emit sites, not only the constant name.

**Q5**
- Vote: A
- Reasoning: The gate is cheap and stops a code from getting two meanings. A separate chore keeps this spec change small and lets the script get its own review and test.
- Concern: A chore with no owner can wait a long time while the drift starts again. Give it a dependency on this ticket so that it surfaces next.

**Q6**
- Vote: Yes
- Reasoning: If we report at name resolution and poison the name, the losing declaration never reaches typecheck or codegen. That removes today's misleading "missing argument" cascade and the redefinition errors from `cc`. The C-symbol view stays as an implementation invariant: the C printer raises an ICE if two declarations ever get one C symbol. It does not go in the spec text.
- Concern: If the poison does not cover every path into codegen, a duplicate can still produce two C definitions. So the ICE backstop in the C printer must also land.

##### Web/Scripting

**Phase C ballot — Web/Scripting (j8tz4f)**

**Q1**
**Vote:** A
**Reasoning:** Users act on the fix, not on the number. Dropping an import is safe for an editor to apply, and a rename is not. Two codes let each quick-fix key on the code alone. E1012 also passed 6-0 today, so a ticket about drift should not reopen it.
**Concern:** People reading the error table will see three codes and ask which one they hit. The spec must say once, in plain words, that this is one rule and the codes only name which pair collided.

**Q2**
**Vote:** A
**Reasoning:** A `git log -S` search shows that E1013 and E1014 were never used in src/ or sections/, so filling the gap breaks nobody. A gap in the numbers makes readers ask "what was E1013?". This is a weak preference, and E1017 is also fine.
**Concern:** If E1013 wins, a later ticket may take E1014 for something unrelated. Then the numbering looks random to readers, and that is a small cost in findability.

**Q2b**
**Vote:** Yes
**Reasoning:** The drift happened because the spec gave out numbers that src never held. Putting the constant in src makes the number real, and the "not yet enforced" marker tells users the truth: today the compiler does not refuse `pub let mut`.
**Concern:** A constant that no code emits looks like dead code. Someone may delete it in a cleanup unless a comment gives the reason.

**Q3**
**Vote:** A
**Reasoning:** That table sits next to the compilation-model prose. A reader who lands there from a search wants the right code in front of them, not a link to follow. Correcting two cells costs less than reworking the section.
**Concern:** If the table stays, it is a second copy that can drift again. The Q5 gate must cover every `| Exxxx |` table in sections/, not only the main one.

**Q4**
**Vote:** Yes
**Reasoning:** A shipped code that is missing from the spec is the worst case for a user who searches the code. The row title must be the name the compiler prints, so that a search for PrivateItemAccess finds the row.
**Concern:** The cause text for E1003 may still differ from what src reports in edge cases. Check it against the explain text, not only against the constant name.

**Q5**
**Vote:** A
**Reasoning:** The gate is tooling, not language. A separate chore keeps this spec change small and easy to review, and a dependency on this ticket keeps the gate from being forgotten. It also stops the gate from failing on drift that this change is fixing in the same commit.
**Concern:** A separate chore can sit in the backlog while new drift creeps in. It needs a near-term owner.

**Q6**
**Vote:** Yes
**Reasoning:** One diagnostic per extra declaration, with both spans, answers "which one?" at a glance. Poisoning the name stops a cascade of type errors that would hide the real cause. A scripting user has never seen the C output, so the C-symbol reason must go. The rule stands on the flat namespace alone.
**Concern:** If the poisoned name stops all later errors, a user can fix the duplicate and then see a new batch of errors that were hidden. The help text should not suggest that the file is otherwise clean.

##### PLT

**PLT ballot (j8tz4f)**

**Q1. Vote: A**
Reasoning: There is one rule, a well-formed module scope has one binding per name per namespace, and the spec states it once. E1005, E1012 and E1016 label the three pairs that can break the rule. The pairs do not overlap, and each one has its own fix. Option B keeps E1005 separate but merges E1012, so it does not apply its own "one rule, one code" reasoning in the same way to every pair.
Concern: The spec could present E1012 and E1016 as two rules and not as two labels of one rule. Then the next new declaration kind gets added to one code and not to the other.

**Q2. Vote: A (E1013)**
Reasoning: `git log -S` shows that no one has ever used E1013, in src/ or in sections/. So the lowest free code has no reuse risk and leaves no gap in the numbers. Without a number (option C), the spec has a hole where the rule has a code.
Concern: Someone could later fill E1014 with something unrelated. Then the numbers near a visibility rule stop being grouped by meaning, and that only affects how easy the table is to read.

**Q2b. Vote: Yes**
Reasoning: The drift happened because the spec gave out a number that src never held. When both places hold the number, the spec and src cannot disagree about who owns it. The "not yet enforced" marker states truthfully that the rule is decided but the compiler does not check it yet.
Concern: A constant that nothing emits could look like dead code, and someone could remove it before the check is implemented.

**Q3. Vote: B**
Reasoning: Two tables that list one set of facts can disagree, and this one already does. With one table there is only one place to be correct.
Concern: Readers of the compilation-model section lose the error list next to the text. The link to the main table must therefore be explicit.

**Q4. Vote: Yes**
Reasoning: The spec table must list every code that ships, and each row's cause text must match what the code reports. A row title that matches src but has cause text src does not report is still drift.
Concern: If no one checks what src reports for E1003, someone could change the title alone and leave the "does not exist" clause incorrect.

**Q5. Vote: A**
Reasoning: The gate fixes the cause of the drift, but it is tooling and not language semantics. So it belongs in its own chore and not in a spec change. Making the chore depend on this ticket keeps the two linked.
Concern: A separate chore can wait for a long time, and while it waits, new drift can start.

**Q6. Vote: Yes**
Reasoning: Report the duplicate at name resolution, because that is where the environment is built, so an ill-formed environment must be refused there and not after typecheck. Bind the name to the first declaration and poison it, so that typecheck runs on a well-formed environment and gives no errors that come from the duplicate. The C-symbol clash is a result of the rule, not the reason for it, so the explain text must not give it as the reason.
Concern: "Bind to the first" could later be read as "the first declaration wins". The spec must say that the program does not compile, and that the first declaration is used only to recover from the error.

##### DevOps

**DevOps/Tooling ballot (j8tz4f)**

**Q1. Vote: A**
Reasoning: Tools key on the code, not the instance: `blink explain`, `@allow`, CI log filters and agent retry logic. "Drop from import list" is safe to auto-apply on a plain `import`; "rename" never is. One code would put a safe fix class and an unsafe one under one key. E1012 was also merged 6-0 today with its own fix rule and W0602 interaction.
Concern: A user who matches only E1016 to find "duplicate names" will miss the import case, so the §10.6 rule text must name all three codes in one place.

**Q2. Vote: A (E1013)**
Reasoning: `git log -S` shows E1013 never appeared in the history of src/ or sections/, so no user can match on it and filling the gap breaks nothing. A number now lets the table row and the drift gate cover the rule.
Concern: If the implementation ticket stalls, a reserved code with no emit site looks like dead code to a later cleanup, so the "not yet enforced" marker must stay until it ships.

**Q2b. Vote: Yes**
Reasoning: The drift in this ticket came from the spec giving out numbers that src never reserved. A `pub const` in src/diagnostics.bl takes the number off the free list, so the next new diagnostic cannot take it.
Concern: A lint for "unused diagnostic constant" (if one exists or is added) will flag it. It needs an allow-list entry tied to the marker.

**Q3. Vote: B (delete)**
Reasoning: Two tables for one code range is how this drift began. One table is one source for tools and for the gate to parse.
Concern: Other prose may link to the deleted table's heading. Grep for links to it before deletion.

**Q4. Vote: Yes**
Reasoning: Every shipped code needs a spec row, or users who see it in output find no reference. Row titles must match the src names, because tools print the name next to the code.
Concern: The E1003 cause text must match what src actually checks (private access, not "not found"), or a not-found case reported under another code will confuse users.

**Q5. Vote: B (land with this ticket)**
Reasoning: The gate proves that this ticket's corrections are complete. Landing it in the same change shows it green on the fixed tables, and red on the old ones. A separate chore can sit in the backlog while new drift comes in.
Concern: The parser for `| Exxxx |` rows may catch example tables or retired-code rows; it needs an explicit marker convention for "retired" and "not yet enforced" from day one.

**Q6. Vote: Yes**
Reasoning: Primary span on the later declaration matches where the user just typed, and it is what LSP clients show first. N-1 diagnostics, each pointing at the first, give stable counts that tools can diff. Reporting at name resolution with a poisoned binding stops typecheck cascades from the losing declaration. A rename is never machine-applicable.
Concern: "First" must be well defined if a module ever spans files. Order by source position within the one file today, and state that in the spec.

##### AI/ML

**AI/ML panelist ballot (j8tz4f)**

**Q1. Vote: A**
Reasoning: A model reads the code and title first, and it uses them to choose its next edit. The import case needs an edit to the import line. The declaration case needs a rename or a delete. Separate codes remove one decision point, and they follow the E1005 precedent of labelling a collision by its pair.
Concern: A model may treat E1012 and E1016 as two rules. The spec must state the rule once and say the codes only label the pair.

**Q2. Vote: A**
Reasoning: `git log -S` shows that neither E1013 nor E1014 has ever appeared in src/ or sections/, so this is not reuse. The number has no meaning to a model. If the spec gives the full set of codes now, a model reading the spec sees the complete picture.
Concern: If B wins, nothing goes wrong for models. If C wins, the spec names a check with no code, and a model cannot match on it.

**Q2b. Vote: Yes**
Reasoning: A number that the spec gives out but src does not reserve is how this drift began. If src reserves the constant, the number cannot be taken twice. The "not yet enforced" marker tells a model not to expect the diagnostic today.
Concern: Someone may forget to remove the marker when the check lands. The gate in Q5 should catch that.

**Q3. Vote: B**
Reasoning: Two tables that list the same codes are two sources of truth, and the stale one already taught wrong codes. A pointer costs fewer tokens in `blink llms` output and cannot drift.
Concern: If the deleted table carried context that the main table does not have, a model loses it. Check that the main table rows cover that context before deleting.

**Q4. Vote: Yes**
Reasoning: A model searches the spec for the name it sees in the compiler output. Row titles and cause text must use the same words as src. Codes that ship but are missing from the table are codes that a model cannot look up.
Concern: The cause text for E1003 must match what src reports today, not what we wish it reported. Copy it from the explain text.

**Q5. Vote: B**
Reasoning: This ticket exists because nothing compares the spec with src. If the gate lands in the same change, it proves that the corrected tables are right on day one. A separate chore can wait in the backlog while the drift starts again. A is my second choice.
Concern: A strict gate may fail on spec-only codes (E1012) until the "not yet enforced" marker format is agreed. Define the marker in the same change.

**Q6. Vote: Yes**
Reasoning: Errors on the losing declaration that cascade into later code are the main cause of a model "fixing" the wrong place. Poisoning the name and reporting at name resolution stop that. Both spans let the model see which copy is old. A fix that is only a suggestion protects new work from an auto-delete of the wrong copy.
Concern: With the name bound to the first declaration, hover and go-to-definition point at the old copy, which is often the stale one. The diagnostic text must name both locations so that the model does not trust the hover.

##### Minimalism

**Phase C ballot: Minimalism (j8tz4f)**

**Q1: A**
**Reasoning:** E1012 was decided 6-0 today, so keeping it adds no new surface. The two pairs have different fixes: a tool can apply one of them, and the other needs a rename. That difference earns the second code. The rule stays one sentence, and the codes only label which pair collided.
**Concern:** The spec could drift into describing three rules where there is one. The text must state the rule once and list the codes under it.

**Q2: A (E1013)**
**Reasoning:** git history shows that no src change and no spec text ever used E1013 or E1014. Filling the lowest free code breaks nothing. A deliberate gap only adds a question that every future reader has to ask.
**Concern:** If E1017 wins, the gap at E1013/E1014 will tempt someone to fill it later without a reservation, which is how drift happens again.

**Q2b: Yes**
**Reasoning:** The drift started because the spec gave out numbers that src never reserved. A reserved constant in src/diagnostics.bl makes the two lists agree today and gives the drift gate something to check.
**Concern:** A reserved constant that nothing emits can look like dead code and get removed. Its comment must say why it is there.

**Q3: B (delete)**
**Reasoning:** A second table of the same codes is the defect. Two copies will drift again even if both are correct today. Point to the main §10 table, and fix the prose and example codes.
**Concern:** If A wins, the duplicate table stays, and nothing except the Q5 gate keeps it in step.

**Q4: Yes**
**Reasoning:** Codes that ship must appear in the spec, and the E1003 title is the same kind of drift. This adds rows only, with no language surface.
**Concern:** Matching the E1003 cause text to src could hide a real spec rule ("item not found" against "private"). Check that src covers both causes before narrowing the text.

**Q5: A (separate chore)**
**Reasoning:** The gate fixes the root cause at the cost of one script, and it adds nothing to the language. A separate chore keeps this spec ticket small and lets it close without waiting on tooling.
**Concern:** A separate chore can sit in the backlog unworked. Wire the dependency so that /next shows it.

**Q6: Yes**
**Reasoning:** Each item makes the output more exact and adds no surface. Removing the C-symbol reason keeps the language rule independent of the backend. Making the fix a suggestion only means the compiler never deletes work it cannot judge.
**Concern:** Poisoning the name could hide real errors in uses of the first declaration. Test that a poisoned name stops only the follow-on errors from the duplicate.

#### AI-first review

| Criterion | Result | Note |
|---|---|---|
| Learnability | Pass | One sentence: one declaration per name per namespace in module scope |
| Consistency | Pass | Same rule as E1012 and the §10.6 shadowing text; no overloading, as §4 already says |
| Generability | Pass | Nothing new to write; the rule only refuses programs |
| Debuggability | Pass | Both locations in one diagnostic; one code per kind of fix |
| Token efficiency | Pass | No syntax added |

### Final Spec

```blink
// One declaration per name in each namespace of module scope
let x = 1
let x = 2                    // error[E1016]: `x` is declared twice in module `main`

fn f() -> Int { 1 }
fn f(n: Int) -> Int { n }    // error[E1016]: no overloading, and neither one wins

pub let mut shared = 0       // error[E1013] PubLetMutForbidden (not yet enforced)
```

- Value namespace: `let`, `let mut`, `const`, `fn`. Type namespace: `type`, type alias, `trait`, `effect`. A type and a value of one name do not collide.
- One rule, three labels: E1005 (import + import), E1012 (import + declaration), E1016 (declaration + declaration). §10.6 *Shadowing Rules* states it once.
- E1016: primary span on the later declaration in source order, a label on the first; N declarations give N-1 diagnostics; reported at name resolution; the name binds to the first declaration only to recover, never as a winner; the fix is a suggestion only. The explain text covers any pair in one namespace and does not give the C symbol as the reason.
- PubLetMutForbidden is E1013. `src/diagnostics.bl` holds the constant now; the check is not yet enforced.
- The §10.8 "Compilation Model Errors" table is gone. Private item access is E1003 everywhere. The §10.5 *Import Errors* table lists E1006, E1007, E1013, E1015 and E1016.
- Governing text: §2.12.1, §10.2, §10.5 *Import Errors*, §10.6 *Shadowing Rules*, §10.8 *Visibility Enforcement*.
