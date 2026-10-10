[< All Decisions](../DECISIONS.md)

# Module Qualifier and Module-Level Declaration — Design Rationale

## Gap

Under *Import Alias Collision* (6-0), bare names and qualifiers share one per-file binding table, so
`import db` + `import auth.{Token as db}` is E1005. But the earlier E1012 text said "A whole-module
import (`import alpha`) binds no bare name, so it never collides with a declaration", so
`import db` + `type db` (or `fn db`, module `let db`) stayed legal. That record named this gap as a
temporary inconsistency. The ticket also asked how the answer interacts with the §10.1 rule that a
local `let auth = 5` hides the module qualifier.

```blink
// main.bl
import db
type db { x: Int }
fn main() { db.connect() }
```

Facts from today's compiler: the `type db` case compiles with no diagnostic, and `db.` means the
module or the type by context. With `fn db` or `let db`, `db.connect()` fails at the use site
("unresolved method `.connect`") and the import gets a false W0602. The scan of src/, lib/, tests/
and examples/ found 0 whole-module qualifier collisions and 1 selective-import qualifier collision
(`src/lexer.bl`: `import tokens.{...}` + `pub let mut tokens`).

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated
in independent-proposal → debate → vote rounds.

#### Phase A — Independent proposals

All six proposed the same core rule (Option Q): a qualifier is a binding in both namespaces, and a
declaration of that name is E1012.

- **Systems:** "Position: one name, one meaning per file at module scope. `X.y` must resolve with
  one table lookup on `X`, with no fallback chain across namespaces." And: "The same applies to the
  qualifier that a selective import gives (`import alpha.{Point}` also gives `alpha.`, §10.1), so
  `import alpha.{Point}` + `fn alpha()` is E1012 too." Cross-language: "Go uses `.` for both package
  and value access and gives the same answer: `import "fmt"` + `var fmt = 1` is "fmt redeclared in
  this block". Rust allows `use std::fmt;` + `fn fmt()` only because it splits `::` (path) from `.`
  (value); Blink has one operator, so it must follow Go." On locals (S2): "A function-local binding
  (`let`, parameter, pattern binding, closure parameter) that spells a qualifier stays a legal
  shadow. [...] Adding a warning only for qualifiers would make one shadow kind special."
- **Web/Scripting:** "One rule, no exceptions: `import db` binds `db` in the file's binding table
  (that is already in the spec for E1005). A module-level declaration of the same spelling, in
  either namespace, is E1012 `DuplicateSymbol`." And: "**JS/TS developers already expect it.**
  `import * as db from "./db"` then `const db = 1` is `SyntaxError: Identifier 'db' has already
  been declared`." W3: "Do not add a case rule to module aliases to dodge collisions [...] Fewer
  rules beat a naming trick a newcomer must learn."
- **PLT:** "The inconsistency has one root cause. §10.5 *Imported Names* already says a
  whole-module import **binds** its qualifier in the per-file table [...] The E1012 sentence [...]
  then treats the same binding as if it did not exist. Both cannot be true." And: "Rust can put
  modules in the type namespace only because `::` and `.` are distinct selectors; Blink has one
  selector, so it cannot." On locals: "Inside that scope `x.y` resolves against the local binding
  only. There is no fallback to the qualifier." and "Resolution must be purely lexical; typing
  comes after."
- **DevOps:** "Today `import db` + `fn db() -> Int` gives two wrong diagnostics, both far from the
  cause [...] The fault is the declaration. Neither message points at it. The `type db` case is
  worse: no message, and `db.` has two meanings that the reader must sort out by hand." D2: "Making
  it an error buys little and costs a lot of renames. Keep §10.6 as is: local over module is a
  nested-scope hide, not a duplicate." D3 (second choice): "A warning at the local `let` when the
  same function **also** reaches the qualifier before the hide".
- **AI/ML:** "The compiler must decide "module or not" for `db.connect()` before it knows which
  namespace to search, so a qualifier cannot sit in only one." And: "This makes §10.5 agree with
  §10.6, which already says two bindings of one name in module scope "are a duplicate, never a
  shadow"." Proposal 2: "A function-local `let auth = 5` stays legal and hides the qualifier in that
  scope."
- **Minimalism:** "The spec today has two rules for one table. [...] A reader must hold both and
  learn where the seam is. That seam is the cost. The cheapest fix removes a sentence. It does not
  add a rule." Spec edit: "delete "A whole-module import (`import alpha`) binds no bare name, so it
  never collides with a declaration."" and "§10.6 then needs no new case: "a selective import and a
  declaration are E1012" becomes "an import entry and a declaration are E1012"."

Fallbacks named and ranked below Q by their own proposers: value namespace only (Sys S3), document
that a declaration hides the qualifier (Min M2: "I list it to reject it."), type namespace only
(PLT 3: "I vote against.").

#### Phase B — Debate highlights

- **V1 (primary span).** In Phase A, Sys, Web and DevOps put the arrow on the import entry; PLT,
  AI/ML and Min on the declaration. In round 1 AI/ML, Min, Web and DevOps moved toward the import
  for "one code, one layout" (Web: "I would accept the declaration as the primary span only if the
  panel moves the selective-import case too, in the same change."). The moderator then surfaced a
  fact: the spec's own E1012 example has `-->` on the declaration. **Systems:** "'Every import
  entry that collides with it gets E1012' and 'on that import entry, E1012 replaces W0602' say which
  entry the error is charged to, not where the arrow points. [...] **the primary span is on the
  later binding in source order**". **DevOps** (round 2): "Fact 1 shows I misread it [...] Web,
  AI/ML, Min and I all made the same misreading [...] When several import entries collide with one
  declaration, emit one E1012 for each entry, each with the arrow on the declaration and a label on
  that entry." **Web** (round 2): "the spec's own example is the layout to be consistent with."
- **V2 (selective import's qualifier).** **DevOps:** "`src/lexer.bl` imports `tokens.{Token, ...}`
  and declares `pub let mut tokens`. All 14 `tokens.` uses reach the value, but a reader, hover, or
  go-to-definition sees `tokens.kinds` next to an import that makes `tokens.Token` legal. That is
  the two-meaning problem, in our own compiler." **Web:** "DevOps's label ("this import also binds
  the qualifier `alpha`") is the right wording, because the user never wrote `alpha` as a binding."
- **L2 (where the hide note lives).** **Minimalism** (round 1): "I move to spec text, but only as
  an extension of a list that exists. [...] §10.6 *Diagnostics that involve a shadowing name* [...]
  already requires a `note:` for every diagnostic whose subject is a shadowing name." Then (round
  2): "**L2 — I concede: chore.** Four of six say chore." The Phase C vote went the other way, 5-1,
  with Min the only CHORE vote.
- **L5 (binder warning).** DevOps withdrew D3 before the vote.

#### Phase C — Final vote

- **Q: a qualifier binds in both namespaces; a module-level declaration of that name is E1012;
  delete "binds no bare name"; fix is a suggestion** (6-0)
  - **Systems:** Q — "`X.y` must resolve with one lookup on `X`. A qualifier that shares a name
    with a declaration in either namespace forces a fallback chain (module, then type-scoped item,
    then value method), and that is the hidden resolution cost I object to."
  - **Web/Scripting:** Q — "JS/TS already reject `import * as db` plus `const db`, so nobody will
    need to ask why. The error moves from a confusing use site to the line that caused it."
  - **PLT:** Q — "Blink has one selector, `.`, so `X.y` needs one lookup of `X` in one
    environment. [...] S3 and P3 each leave one ambiguous pair in place. M2 keeps the
    silent-override behavior that is today's bug."
  - **DevOps:** Q — "Q gives one error at the cause, with a fix the LSP can offer. It also gives
    `db.` completion and go-to-definition a single target."
  - **AI/ML:** Q — "At module scope a name is either a qualifier or a declaration, never both, so
    `db.y` has one meaning that a model can learn from one sentence."
    Concern: "Code generated from Python habits (`import json` + module-level `json = ...`) will hit
    E1012 often, so the help text must offer the alias form clearly."
  - **Minimalism:** Q — "Q deletes a sentence and an exception. Then one table has one collision
    story: E1005, E1012, E1016."
- **V1: primary span** (6-0, DECL)
  - **Systems:** DECL — "the existing E1012 example already puts `-->` on the declaration, and
    DECL keeps it, so E1012 has one layout with no spec edit."
  - **Web/Scripting:** DECL — "One guessable rule: the arrow is at the second thing that took the
    name."
  - **PLT:** DECL — "One principle then covers E1005, E1012 and E1016: the primary span is on the
    later binding in source order."
  - **DevOps:** DECL — "The LSP puts the import in `relatedInformation`, and the `as` code action
    can edit the import line whatever range the diagnostic has."
  - **AI/ML:** DECL — "A model that reads diagnostics to find its edit does not need to know the
    import kind."
  - **Minimalism:** DECL — "DECL changes no spec text and IMPORT rewrites it."
- **V2: a selective import's qualifier collides too** (6-0, YES)
  - **Systems:** YES — "Without V2, `alpha.y` keeps two meanings, which Q exists to remove."
    Concern: "the `src/lexer.bl` rename must land before the check, or gen1 fails."
  - **Web/Scripting:** YES — "Migration is one rename in one file."
  - **PLT:** YES — "Exempting it brings back the same `alpha.y` ambiguity at a smaller scale."
  - **DevOps:** YES — "Leaving it out keeps the same ambiguous `alpha.y` for hover, completion and
    readers."
  - **AI/ML:** YES — "One rule, "every import binds its qualifier", is easier to learn than an
    exception."
  - **Minimalism:** YES — "Leaving it out keeps the exact two-meaning case Q removes."
- **V3: use-site errors caused only by the collision are not reported** (6-0, SPEC)
  - **Systems:** SPEC — "Not fixing the recovery binding keeps implementations free."
  - **Web/Scripting:** SPEC — "Cascades are what teach users to ignore the error list."
  - **PLT:** SPEC — "It also leaves the recovery binding free, so no semantics is fixed for an
    ill-formed program."
  - **DevOps:** SPEC — "Leaving the use-site cascade to each tool means compilers and LSPs differ in
    how many errors one mistake gives."
  - **AI/ML:** SPEC — "Cascade errors are the main cause of wrong fixes in model-written code."
  - **Minimalism:** SPEC — "Without it, "E1012 replaces W0602" reads as the only suppression, and a
    compiler can conform while it emits N+2 errors."
  - Shared concern (all six): an implementation may over-suppress and hide an unrelated error.
- **V4: §10.6 says "import entry and declaration"** (6-0, YES)
  - **Systems:** YES — "it is the smallest edit that makes §10.6 true once V2 holds."
  - **Web/Scripting:** YES — "It is the smallest edit that keeps §10.6 true for both import kinds."
  - **PLT:** YES — "once V2 holds, "selective import" in §10.6 is too narrow".
  - **DevOps:** YES — ""Import entry" is the exact term, and it costs nothing."
  - **AI/ML:** YES — "the new wording is exact and costs nothing."
  - **Minimalism:** YES — "it is the smallest edit that makes §10.6 true once Q and V2 pass."
- **V5: no case rule for `as` aliases** (6-0, YES)
  - **Systems:** YES — "a case rule adds surface and stops nothing new."
  - **Web/Scripting:** YES — "A case rule is one more thing to learn and stops nothing new."
  - **PLT:** YES — "case is a convention, not a scoping rule."
  - **DevOps:** YES — "A case rule adds a second error for the same mistake."
  - **AI/ML:** YES — "catches nothing E1012 does not already catch."
  - **Minimalism:** YES — "a case rule is new surface for a problem E1012 already solves."
- **L: a local hides the qualifier; legal; no binder warning** (6-0, YES)
  - **Systems:** YES — "nested-scope shadowing is the one shadow kind Blink allows (§2.2, §10.6)".
  - **Web/Scripting:** YES — "`let json = fs.read(path)` next to `import std.json` is everyday
    scripting code."
  - **PLT:** YES — "hiding by an inner binder is ordinary lexical scoping".
  - **DevOps:** YES — "A warning at the binder fires on working code and teaches people to suppress
    W-codes."
  - **AI/ML:** YES — "`let json = ...` beside `import std.json` is one of the most common things a
    model writes".
  - **Minimalism:** YES — "Go, Rust, Python and Zig all allow a local to shadow a package name."
  - Shared concern (all six): the silent case, where the local's type has a method of that name,
    compiles against the local.
- **L1: no-fallback sentence; binder list once in §2.2, pointer from §10.1** (6-0, LIST22)
  - **Systems:** LIST22 — "without it, the target of `x.y` depends on the method set of `x`'s type,
    and a later stdlib method could re-route calls."
  - **Web/Scripting:** LIST22 — "The no-fallback sentence answers the first question a Python/JS
    user asks."
  - **PLT:** LIST22 — "the no-fallback sentence is semantics."
  - **DevOps:** LIST22 — "One list in §2.2, with a pointer from §10.1, gives one source of truth for
    every scope-aware tool".
  - **AI/ML:** LIST22 — "A model learns the list once and applies it everywhere shadowing matters."
  - **Minimalism:** LIST22 — "Binder kinds are a property of scoping, not of imports, so define them
    once in §2.2 and point to them from §10.1."
- **L2: hide note is an item in §10.6 *Diagnostics that involve a shadowing name*** (5-1, S106;
  Minimalism dissent)
  - **Systems:** S106 — "§10.6 already requires a `note:` for a name that shadows a compiler-known
    type; a local that hides a qualifier is the same pattern."
  - **Web/Scripting:** S106 — "It fixes the content of the note, not its wording."
  - **PLT:** S106 — "Widening that rule reuses an existing concept and adds no new one."
  - **DevOps:** S106 — "Tools and models already expect the note there."
  - **AI/ML:** S106 — "It also lets a model predict the note from the spec."
  - **Minimalism:** *(dissent)* CHORE — "the note changes no accept or reject decision, and four of
    six panelists said chore. Fewer normative words for a rule no program can break."
- **L3: note only when the hidden module has a `pub` item with that name** (6-0, YES)
  - **Systems:** YES — "A note that points at a module without the item sends the user to a dead
    end."
  - **Web/Scripting:** YES — "A wrong hint costs more than no hint."
  - **PLT:** YES — "The condition is one export-table lookup on an error path."
  - **DevOps:** YES — "a wrong hint costs more than no hint."
  - **AI/ML:** YES — "sends the model to a second error."
  - **Minimalism:** YES — "a note that points at a module without the item sends the reader the
    wrong way."
- **L4: W0602 on a hidden import** (3-3: PLAIN Sys, PLT, Min; NAME Web, DevOps, AI/ML → Phase D)
  - **Systems:** PLAIN — "the drop rule is semantics of diagnostic count and belongs in spec;
    message content does not."
  - **PLT:** PLAIN — "Naming the hiding binder in its text is diagnostic quality."
  - **Minimalism:** PLAIN — "The text of the warning is wording, and wording stays free to improve
    outside the spec."
  - **Web/Scripting:** NAME — "Naming the binder ("every use resolves to the local at 4:7") points
    to the fix right away."
  - **DevOps:** NAME — "In the silent wrong-call case, W0602 is the only signal".
  - **AI/ML:** NAME — "Naming the hiding binder gives the cause and the fix in one step".
- **L5: a W-code at a local that hides a used qualifier** (6-0, NO)
  - **Systems:** NO — "it adds a code for a rare case, flags correct code".
  - **Web/Scripting:** NO — "A warning on working code teaches people to add suppressions."
  - **PLT:** NO — "W0602 covers more for less."
  - **DevOps:** NO — "I withdrew D3."
  - **AI/ML:** NO — "DevOps withdrew it."
  - **Minimalism:** NO — "it warns on correct code."

#### Phase D — Round 2 (L4)

- **L4: W0602 on a hidden import** (6-0 NAME, after 3-3 in Phase C)
  - **Systems:** NAME — "Voting PLAIN after S106 would leave one hide diagnostic with fixed content
    and its twin without. That is the inconsistency, and it is mine."
  - **Web/Scripting:** NAME — "PLAIN would specify the content for the easy case (the one that
    already has an error) and leave it out for the hard case (the silent wrong call, where W0602 is
    the only signal)."
  - **PLT:** NAME — "A content rule should not depend on whether a type error happened to occur."
  - **DevOps:** NAME — "PLAIN admits that problem and leaves it to a chore that no gate checks."
  - **AI/ML:** NAME — "A model that gets "unused" next to code that spells `json.` will most likely
    delete the import, which is the wrong fix."
  - **Minimalism:** NAME — "Two treatments for one cause is the exact kind of exception I spent
    this panel removing."

AI-First review: 5/5 pass (one table and one rule, located errors with a named fix, no new syntax,
no new code).

### Final Spec

```blink
import alpha
import beta as b
import gamma.{Point}

type alpha { x: Int }    // error[E1012]: `alpha` is both a module qualifier and a declaration
fn b() -> Int { 1 }      // error[E1012]: the import binds the qualifier `b`
let gamma = 3            // error[E1012]: the selective import binds the qualifier `gamma`

fn parse(json: Str) -> Int {   // with `import std.json`: legal, the parameter hides the qualifier
    json.len()                 // the parameter, never the module
}
```

- Every import binds its qualifier: the leaf name, or the name after `as`. A selective import binds
  its qualifier too.
- A qualifier is in both namespaces. A module-level declaration of that name (`type`, alias,
  `trait`, `effect`, `fn`, `const`, `let`, `let mut`) is E1012, for `import` and `pub import`.
  The sentence "binds no bare name" is deleted.
- Primary span on the declaration, the import entry as a label; one E1012 per colliding entry.
- The fix is a suggestion only (§8.6). E1012 replaces W0602 on that entry. Use-site errors caused
  only by the collision are not reported. The recovery binding is not specified.
- No case rule for `as` aliases.
- A local binding (§2.2 *Local bindings*) hides a qualifier for its scope. It is legal and gets no
  warning. `x.y` resolves against the local only; there is no fallback to the qualifier.
- §10.6 *Diagnostics that involve a shadowing name*: a use-site failure under a hide gets a note
  that names the hidden module, only when that module has a `pub` item with that name. When every
  `q.y` resolves to a local, W0602 adds a note with the first hiding binder in source order. When
  the hide note fired, no W0602.

Governing text: §2.2 *Local bindings*; §10.1 *Qualified Access*; §10.5 *Imported and Declared
Names*; §10.6 *Shadowing Rules*; *Import Errors* table (E1012).

Follow-ups: implementation ticket; the `src/lexer.bl` rename lands in its own bootstrap step before
enforcement; and a spec ticket for two selective imports from modules with one leaf name (with
selective imports binding their qualifier, the E1005 rule may now apply to that pair).
