[< All Decisions](../DECISIONS.md)

# Selective Import Qualifier Collision — Design Rationale

## Gap

After *Module Qualifier and Module-Level Declaration* (V2, 6-0), §10.1 says a selective import binds
its qualifier, and §10.5 *Imported Names* says two imports that bind one name to different items
are E1005. Read together, `import a.x.{P}` + `import b.x.{Q}` is E1005 on `x` even when the file
never writes `x.y`. No panel voted on that pair. The question: E1005 at the import (eager, as for
whole-module imports), E1005 only when the file uses `x.y`, or no E1005 for a selective import's
qualifier.

```blink
import a.x.{P}
import b.x.{Q}
fn main() { let p = P {} }
```

Facts given to the panel:

1. The grammar had no form that renames a selective import's qualifier. Under an eager rule, a
   file that wants bare `P` from `a.x` and bare `Q` from `b.x` had no spelling.
2. Today's compiler parses neither `import m as q` nor any qualifier alias. It accepts
   `import a.x.{P}` + `import b.x.{Q}` with no diagnostic, and `x.hi()` resolves to `a.x` (the
   first import). With `import a.x` + `import b.x` it also compiles, and `x.hi()` resolves to `b.x`
   (the last import).
3. The scan of src/, lib/, tests/ and examples/ found 0 files that import two modules with one
   leaf name.
4. Leaf collisions are plausible: `std.json` vs `pkg.json`, `myapp.db.error` vs
   `myapp.http.error`.

The spec also already marked `import auth.{Token, Token as AuthToken}` OK, and that line binds the
qualifier `auth` a second time.

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated
in independent-proposal → debate → vote rounds.

#### Phase A — Independent proposals

- **Systems:** "Keep one rule: every import binds its qualifier, and two imports that bind one name
  to different items are E1005 at the import, whether or not the file uses the name. Close the gap
  in the grammar. Let `as` rename the module path before the brace list" — `import b.x as bx.{Q}`.
  "The rule for `as` stays the same everywhere: it renames the thing on its left. `b.x as bx`
  renames the module, and `Q as R` renames the item. The parse is LL(1)." Rank 2: an "AMBIGUOUS
  marker", E1005 only at use; "Proposal 2 alone is incomplete." Rank 3 (oppose): exempt.
- **Web/Scripting:** "If Blink gives an eager E1005 on a name the file never writes, AND the
  grammar has no way to fix it (fact 1), that is a top Stack Overflow question [...] An error with
  no fix is the worst DX we can ship." Rank 1: "A selective import binds its qualifier as an
  IMPLIED name [...] When the file writes `x.y` and `x` has more than one meaning, that use is
  E1005." Rank 2: eager plus `import b.x as bx.{Q}`; "I expect people to write
  `import b.x.{Q} as bx` and get a parse error." Rank 3: eager with no grammar, "Strong no."
- **PLT:** "Is a file's binding table a function from names to items? [...] The real defect is in
  the grammar: the user can get this error but has no way to write the fix." Rank 1: eager plus
  `import b.x.{Q} as bx`; "Rejected alternative spelling: `import b.x as bx.{Q}`. It makes `bx.{Q}`
  look like a module path." "Same module twice (`import a.x.{P}` + `import a.x.{R}`) is the same
  item, so it gets W0602 with the fix `import a.x.{P, R}`." Rank 2: eager, no grammar, "only as a
  first step, with the alias tracked as follow-up." Reject lazy and exempt.
- **DevOps:** "an error is only as good as the fix a tool can apply." Rank 1: eager plus
  `import <path> as <name>.{items}`; "The code action is one edit on one line. It changes no use
  site, because bare `Q` stays bare." Rank 2: eager, no grammar; "a punishment for a valid design
  choice". Reject lazy: "Adding one `x.` call far from the imports breaks a build, and the error
  points at the imports." Reject exempt: "`x.hi()` silently changes target."
- **AI/ML:** "A model that gets E1005 with no fix will loop." P1: eager plus
  `import b.x as bx.{Q}`; "The new form is `import m as q` with `.{...}` added, so a model that
  knows both parts can build it from the spec." P1-alt: `import b.x.{self as bx, Q}`, "it gives
  `self` a second meaning". P2: lazy; "it creates a second rule". P3: exempt, reject.
- **Minimalism:** "rank 1 is eager E1005 with no new grammar." "Three decided rules already give
  this answer [...] The ticket asks whether to make an exception. My answer is no." "The corpus has
  0 cases. When a case comes up, the user loses bare `Q` and writes `bx.Q`, which is 3 more
  characters. They lose no capability." Rank 2 (defer, YAGNI): `import b.x as bx.{Q}`; "File a
  friction ticket and add the form only if real code hits the limit."

All six asked to fix the first sentence of §10.5 *Imported Names*, which listed a selective
import's names but not its qualifier.

#### Phase B — Debate highlights

One round. All six sent "stable, ready to vote".

- **Web** moved from use-site E1005 to eager, on one condition: "I move to T-EAGER, but only if G
  adds a form in the same decision. [...] If G-NONE wins, I go back to T-USE". On the order:
  "to a Python dev, `import b.x.{Q} as bx` reads like `from b.x import Q as bx`, which renames Q,
  not the module."
- **PLT** moved from G-POST to G-PRE: "Systems gave the better rule: '`as` renames the thing on its
  left.' That rule is local and it composes. G-POST makes `as` reach past the `{...}` list to the
  path, so its scope is not local." PLT also changed its S1 position: "W0602 means 'this import is
  unused, delete it.' But the later line also binds `R`, so the fix would delete a live name."
- **DevOps** on the formatter: "With G-POST, the qualifier name moves below the closing `}`, far
  from the path it renames". And: "the parser must reject the other order with a targeted error and
  a machine-applicable fix [...] I ask that this go into the decision whichever order wins."
- **AI/ML** dropped G-SELF and answered Minimalism: "The fix rewrites every bare `Q` in the file to
  `bx.Q`, a multi-site edit [...] For a model, a one-line fix is more reliable than an edit across
  the file." Against T-USE: "A model cannot tell from `import a.x.{P}` that its `x` is 'weaker'
  than the `x` from `import a.x`."
- **Minimalism** moved part of the way: "Today's parser already rejects `import m as q`, so the
  whole-module alias form must be built anyway. Adding `.{...}` after it costs less than I said in
  Phase A. If the panel adds a form, I vote G-PRE". Against T-USE: "That is a permanent new idea in
  the spec, added to save a case that one alias line fixes."
- **Systems** against deferral: "'Add it later' is true. But the gap is in the grammar, the eager
  error exposes it at once, and once we choose T-EAGER we cannot defer it."

#### Phase C — Final vote

- **Q-T: when E1005 fires on a qualifier that two imports bind to different modules** (6-0,
  T-EAGER)
  - **Systems:** T-EAGER — "Each name has one entry in the table, each import does one insert, and
    the check runs when the compiler reads the import, with no wait on the body. This removes
    today's order bug (first-wins for selective, last-wins for whole-module) by making order
    irrelevant."
  - **Web/Scripting:** T-EAGER — "With a rename form, no file loses bare names, so my 'error with
    no fix' objection is gone." Concern: "If Q-G ends as G-NONE [...] my vote on Q-T changes to
    T-USE."
  - **PLT:** T-EAGER — "T-EAGER keeps import+import (E1005) and import+declaration (E1012, V2) as
    one rule over one table."
  - **DevOps:** T-EAGER — "The error fires at the import line, and the fix edits that same line,
    so the LSP shows cause and fix together."
  - **AI/ML:** T-EAGER — "One rule ('every import binds its qualifier, checked at the import') is
    what a model can learn from the spec alone."
  - **Minimalism:** T-EAGER — "T-USE adds a second kind of binding and a second check timing to one
    table, for a case that has 0 hits in the corpus. T-EXEMPT brings back the hidden first-wins or
    last-wins order."
- **Q-G: grammar to rename a selective import's qualifier** (5-1, G-PRE; Minimalism dissent)
  - **Systems:** G-PRE — "`as` comes right after the path it renames, the same as `Q as R`, so the
    qualifier is next to its module even when the brace list runs over many lines."
  - **Web/Scripting:** G-PRE — "G-PRE is two forms the spec already has (`import m as q` and
    `.{...}`) put together."
  - **PLT:** G-PRE — "One rule then covers `m as q`, `m as q.{...}` and `A as B` inside the
    braces." Concern: "Readers can take `bx.{Q}` for a module path named `bx`."
  - **DevOps:** G-PRE — "The path and its new name stay on one line even when `blink fmt` wraps a
    long list."
  - **AI/ML:** G-PRE — "G-POST puts `as` after a brace list, where a model reads it as 'rename Q',
    one token away from the item alias `{Q as R}`."
  - **Minimalism:** *(dissent)* G-NONE — "`import b.x as bx` plus `bx.Q` already writes every such
    program. What the user loses is the bare spelling, not a capability. A grammar form is
    permanent, and we have no real code that needs it yet."
- **Q-S1: a qualifier bound again to the same module gets no E1005 and no W0602; W0602 only for a
  duplicate listed item** (6-0, Yes)
  - **Systems:** Yes — "W0602 says 'unused import', and that is false when the statement brings a
    new item."
  - **Web/Scripting:** Yes — "W0602 means 'this line does nothing'. `import a.x.{R}` binds R, so it
    does something."
  - **PLT:** Yes — "When an import binds `x` to the module that `x` already names, the table does
    not change."
  - **DevOps:** Yes — "An auto-fix that breaks the build is the worst tool behavior. Merging the two
    lines is the formatter's job."
  - **AI/ML:** Yes — "A model would apply that fix and break the build."
  - **Minimalism:** Yes — "A warning whose fix breaks the code is worse than no warning."
- **Q-S2: selective + whole-module import with one leaf from different modules is the same E1005
  with the same fix** (6-0, Yes)
  - **Systems:** Yes — "Same table, same check, same one-line fix."
  - **Web/Scripting:** Yes — "A different rule here would be a hidden exception that users find by
    accident."
  - **PLT:** Yes — "The import form does not change what a collision is."
  - **DevOps:** Yes — "If the two shapes had different rules, users would have one more case to
    learn and the tool would have one more code path."
  - **AI/ML:** Yes — "A different answer would add a decision point for no gain."
  - **Minimalism:** Yes — "It is the same table and the same check, so we need no separate rule."
- **Q-S3: the first sentence of §10.5 *Imported Names* says a selective import binds its
  qualifier** (6-0, Yes)
  - **Systems:** Yes — "Today §10.5 teaches the wrong table and contradicts §10.1."
  - **Web/Scripting:** Yes — "A reader who reads only §10.5 learns the wrong table today."
  - **PLT:** Yes — "The spec must define the table in one way."
  - **DevOps:** Yes — "Tools and the LLM docs (`blink llms`) quote these sections one at a time, so
    each section must be correct by itself."
  - **AI/ML:** Yes — "The spec must agree with itself, or models learn whichever section they read
    first."
  - **Minimalism:** Yes — "This is a text fix that makes §10.5 agree with §10.1, not a new rule."
- **Q-P: the parser rejects `import b.x.{Q} as bx` with a targeted error and a machine-applicable
  fix to G-PRE** (5-0; Minimalism N/A, "If a form wins: Yes")
  - **Systems:** Yes — "A generic UnexpectedToken at `as` is what gen1 gives today, and it says
    nothing useful." Concern: "The recovery must not also report E1005 for the same line".
  - **Web/Scripting:** Yes — "A targeted error with a machine-applicable rewrite to G-PRE turns a
    habit from Python into a one-key fix." Concern: "The rewrite must keep any item aliases inside
    the braces as they are."
  - **PLT:** Yes — "A targeted error with a fix to the G-PRE spelling costs nothing, and it does not
    make G-POST legal."
  - **DevOps:** Yes — "A generic UnexpectedToken at `as` gives the user a puzzle and gives an agent
    a loop."
  - **AI/ML:** Yes — "That turns a model's first guess into a one-step self-correction". Concern:
    "the targeted error must not catch valid item-alias shapes such as `{Q as R}`."
  - **Minimalism:** N/A, Yes if a form wins — "A targeted parse error adds no language surface."
- **Q-A: §10.5 *Import Aliases* shows every alias form** (6-0, Yes)
  - **Systems:** Yes — "One table of forms is cheaper than three scattered examples."
  - **Web/Scripting:** Yes — "The example block must label each line with what it binds".
  - **PLT:** Yes — "so a reader can see the `as` rule in each."
  - **DevOps:** Yes — "The section must say clearly that `as` in braces renames an item and `as`
    before `.{` renames the qualifier".
  - **AI/ML:** Yes — "A spec that shows only the item alias makes models invent the other forms."
  - **Minimalism:** Yes — "If one section lists every form, users do not have to look for alias
    rules in two places".

Phase D did not run: the closest result was 5-1. The user signed off on the tally, with G-PRE over
the Minimalism dissent.

### AI-First Review

Learnability, consistency, generability, debuggability and token efficiency: 5/5 pass. One rule
("`as` renames the thing on its left"), one table checked at the import, a form built from two
known forms, a wrong-order guess that gets a machine-applicable fix, and a one-line fix that keeps
bare names.

### Final Spec

```blink
import a.x.{P}
import b.x.{Q}                // error[E1005]: the qualifier `x` is imported twice

import a.x.{P}
import b.x as bx.{Q}          // OK: binds `Q` and `bx`

import a.x.{P}
import a.x.{R}                // OK: binds `R`; `x` names `a.x` again

import b.x.{Q} as bx          // error[E1128]: fix writes `import b.x as bx.{Q}`
```

- A selective import binds each listed name and its qualifier. The qualifier is the leaf name, or
  the name after the `as` that follows the path.
- Two imports that bind one qualifier to different modules are E1005 at the import, for every
  pair of import forms, whether or not the file writes `x.y`.
- `import <path> as <name>.{items}` renames a selective import's qualifier. `as` renames the thing
  on its left.
- A qualifier bound again to the same module gets no diagnostic. A selective import's qualifier is
  not an entry of its own, so it never gets W0602. W0602 goes to a listed name that already imports
  its item, and to a whole-module import whose qualifier already names its module.
- `import b.x.{Q} as bx` is `QualifierAliasAfterList` (E1128), with a machine-applicable fix that
  keeps the list as written. The fixed import is checked, with no second diagnostic for the order.
- The E1005 help names the import to rename and keeps its bare names: `import b.x as bx.{Q}` or
  `import a.x as ax`.
- §10.1 *Qualified Access*, §10.5 *Imported and Declared Names*, *Imported Names* and
  *Import Aliases*, catalog E1005 and E1128.
