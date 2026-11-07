[< All Decisions](../DECISIONS.md)

# One Name Re-exported From Two Modules — Design Rationale

A facade that does `pub import b1` and `pub import b2`, where both modules export `pub let G`, gave `facade.G` the first hit of a map walk. The hit followed the directory, not the source order. In one program `facade.G` printed `2` and `import facade.{G}` printed `1`. With `pub fn G` in one module and `pub let G` in the other, `facade.G` took the fn and the print failed with `MissingDisplayImpl`. A facade that declared `pub let G: Int = 3` and also did `pub import b1` (b1 exports `G`) gave `3` with no diagnostic, although §10.5 says a module that defines and re-exports one name gets E1012. `blink check` on the facade said `ok`.

§10.1 *Qualified Access* already says that a whole-module import binds only its qualifier, so `import b1` and `import b2` in a consumer do not collide. §10.5 *Imported Names* already says that E1005 covers two imports in one file, and that the check runs when the import is read. The text gave no rule for the export set of a module that re-exports.

## Summary

| Q | Question | Result | Vote |
|---|---|---|---|
| Q1 | What a facade does when two `pub import` entries give one name to different items | A: the export set maps each name to one item. The compiler checks it at the facade, whether or not any file reads the name. The kind of the item does not matter | 6-0 |

Cases that the vote carried:

```blink
// b1.bl: pub let G: Int = 1        b2.bl: pub let G: Int = 2
// facade.bl
pub import b1
pub import b2        // error[E1005]: `G` is exported by `b1` and `b2`

// c1.bl: pub fn G() -> Int { 1 }   c2.bl: pub let G: Int = 2
// facade.bl
pub import c1
pub import c2        // error[E1005]: the same; the kind does not matter

// facade.bl, b1 exports G
pub import b1
pub let G: Int = 3   // error[E1012]: `G` is also re-exported by `pub import b1`

// mid.bl: pub import b1
// facade.bl
pub import b1
pub import mid       // OK: both reach the one item `b1.G`

// facade.bl
pub import b1.{G}
pub import b2.{G}    // error[E1005]: selective re-exports, the same rule

// facade.bl
pub import b1
pub import b2.{H}    // OK: b1 has no H; this is the fix for the author

// b2.bl has a private G, and b1 exports pub G
// facade.bl
pub import b1
pub import b2        // OK: only pub items enter the export set

// facade.bl
import b1            // a plain import exports nothing
import b2            // OK: no clash

// main.bl: a file that wants both values (unchanged, §10.1)
import b1
import b2

fn main() {
    io.println("{b1.G} {b2.G}")   // 1 2
}
```

Wording that the vote carried, with no separate ballot:

- The E1005 message for the facade case names the name and both source modules. Its help shows a selective `pub import b2.{other}`.
- The E1012 diagnostic for a whole-module `pub import` has a second label at the `pub import` line that re-exports the name.
- The "Re-exported items are indistinguishable from locally-defined `pub` items" text holds again: `facade.G` and `import facade.{G}` name the same item.
- The spec states the known cost: a new `pub` name in a module that a facade re-exports whole can break that facade. A selective `pub import` prevents it.
- ERROR_CATALOG.md widens the E1005 and E1012 rows. No code is new.

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated. All six proposed the same behavior in every case, so the fast path ran: Phase B (debate) and Phase D did not run. Quotes are verbatim; "…" marks a cut.

#### Phase A — Independent proposals

- **Systems:** "Rule: a module's exported names form one table. `pub import M` adds every pub item of M to it. If two entries bind one name to different items, that is E1005 (AmbiguousImport). It points at the second `pub import` line and names both source modules. The check runs when the facade is compiled, whether or not anyone reads the name. Item kind does not matter." … "With the error at the facade, the table is total and every later phase can assume one item per name. That is the cheaper invariant." … "Order or priority (\"first wins\", \"last wins\") is the worst choice. The result depends on the source line order or on a hash-map walk, and one name gives different items in two spellings (already measured)." …
- **Web/Scripting:** "Position: the facade is the only place that can fix the clash, so it errors there. Read order and map order never pick a winner, and the check does not depend on whether anyone reads the name." … "Defined order (first or last wins): this is the Python `from x import *` trap. It is silent, it depends on line order, and it produces the Stack Overflow question \"why did my G change when I reordered imports\". I reject it." … "A new code: E1005 already says \"one name, two items\". The message text names the facade case. A new code adds a thing to learn for no gain." …
- **PLT:** "Principle: a module's export namespace must be a function from name to one item. It cannot depend on map order or on how the consumer spells the read. Today `facade.G` and `import facade.{G}` give different items, so \"re-exported items are indistinguishable from local pub items\" is false." … "The rule must read the export set, not the binding table. Local does not shadow." … "Lazy checking makes the facade's validity depend on its consumers, which does not compose." …
- **DevOps/Tooling:** "Rule: a module has one export table. Two whole-module re-exports that put one name into it, for different items, are E1005 at the facade. The facade is the only file that can fix it. Consumers are never blamed." … "Case 3, local `pub let G = 3` plus `pub import b1` (b1 exports G): E1012 at the local declaration. A secondary label points at the `pub import b1` line and says \"re-exports `G`\"." … "One cost: when b2 adds a `pub` name, the facade breaks even if no consumer reads it." …
- **AI/ML:** "RULE (one rule, no order, no kind exception): a module's public surface maps each name to exactly one item." … "The error names both source modules and the name." … "Tradeoff: facades over many modules with incidental name overlap (e.g. both export `new`) must switch to selective `pub import`. That costs a few tokens but is explicit and visible in source." …
- **Minimalism:** "Rule: a module's pub namespace is a set of names. A name must come from exactly one item." … "We add no new code and no new concept." … "Case 3 … This is a bug against the existing spec, not a new rule." … "Tradeoffs: a facade that wildcard-re-exports two modules with an overlap now needs a selective `pub import b.{...}`. That is the cost, and it is small." …

All six seats gave the same behavior: E1005 at the second `pub import` for two re-exports of one name (kind does not matter); E1012 at the local declaration for a declaration plus a re-export; no error for one item by two paths; the check runs whether or not any file reads the name.

#### Phase B — Debate

Did not run. After the mechanical dedupe, one option remained and no seat flagged a variation.

#### Phase C — Final vote

Votes are verbatim from each seat's ballot file.

- **Q1: Adopt option A.** A: the facade's export set maps each name to one item; it is checked at the facade, whether or not a consumer reads the name; the kind of the item does not matter. B: reject A. **6-0 for A.**
  - **Systems:** A — "One item per exported name makes the C symbol for `facade.G` fixed, so mono, cname and the cache need no \"ambiguous\" state. The check is one compile-time pass over the exports, with no runtime or layout cost. It also ends the dependence on map order, which makes today's output differ between directories." Concern: "A `pub let` added later to a wildcard-re-exported module can break an unchanged facade, though selective re-export is the fix."
  - **Web/Scripting:** A — "The error lands on the facade line the author wrote, so a JS or Python dev finds the cause in the file they are editing. It removes the silent \"which G did I get\" result that Python's `import *` gives. The fix is one line, either a selective re-export or the consumer's own `b1.G` and `b2.G`, with no new syntax." Concern: "Facades over many modules will now fail on a shared common name such as `init` or `Error`, and the author must write selective re-exports to fix it."
  - **PLT:** A — "The export namespace must be a function from name to item, and it must not depend on map order or on how the consumer spells the read. Checking at the facade makes validity independent of the consumer set, so the rule composes." … "Kind-blindness is correct because fn and let share one value namespace." Concern: "The check must compare item identity after following pub import chains, and a bug there would wrongly reject diamond re-exports (case 4) or miss a real clash."
  - **DevOps/Tooling:** A — "One check at the facade gives one error site, one span and one fix, and it runs whether or not anyone reads the name. The LSP then has one target for each exported name, and import order cannot change what a program does." Concern: "A new pub name in an upstream module can break a facade that no consumer reads, so the E1005 help line must show the selective `pub import b2.{other}` fix."
  - **AI/ML:** A — "One rule (\"a facade exports each name once\") has no order and no kind exception, so an AI can learn it from the spec alone with no extra decision points. The error lands at the facade the model just wrote, so the fix is local, and the selective `pub import b2.{H}` repair is cheap in tokens." Concern: "Large facades with incidental overlap (e.g. `new`) now need selective imports, and a message that fails to name both modules would leave the model guessing which line to change."
  - **Minimalism:** A — "It adds no new code and no new rule. It extends E1005 and E1012 to the names a `pub import` re-exports, which the spec already says. It removes the order- and spelling-dependent result (`facade.G` giving a different item than `import facade.{G}`)." Concern: "A facade that re-exports two large modules with a small overlap now needs selective `pub import`, and a later new `pub` name in a dependency can break the facade (a source-compatibility hazard for library authors)."

#### Phase D — Follow-up round

Did not run.
