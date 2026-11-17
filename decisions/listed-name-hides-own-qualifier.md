[< All Decisions](../DECISIONS.md)

# A Listed Name Equal to Its Own Qualifier — Design Rationale

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated
in independent-proposal → debate → vote rounds. Ticket IDs in the quoted text are replaced with `[ticket]`.

#### Phase A — Independent proposals

- **Systems:** (excerpt, section `G3 ([ticket]): `import m.{m}``)

>
> **Facts.** Names are case-sensitive: `import shape.{Shape}` binds `shape` and `Shape`, two names, not this case. The E1005 text covers "two imports"; `import m.{m}` is one entry binding two roles to one name.
>
> ### G3-P1 (preferred): legal when the listed item has no dotted members (a fn); E1005 at the entry when it is a type, trait or const
>
> A bare `m` never resolves to a qualifier (§10.5), and `m.y` on a fn is never member access. So for a fn item, the two roles never meet: bare `m(...)` is the fn, `m.y` is the qualifier. For a type, trait or const, `m.y` has two readings (type-scoped fn or field vs. pub item `y` of module m). The check decides from the item's kind, at the import, whether or not the file uses `m.y`, as all import checks do.
>
> ```blink
> import greet.{greet}             // OK: `greet("x")` is the fn, `greet.other()` is module greet
> import cfg.{cfg}                 // error[E1005] (`cfg` is a const): `cfg.port` is ambiguous
>                                  // help: import cfg as cfg_mod.{cfg}
> import shape as sh.{shape}       // OK for any kind: the qualifier is `sh`, not `shape`
> pub import auth.login.{login}    // OK: a fn; the export set gets `login` only
> ```
>
> `import m as k.{m}`: no clash, any kind. `pub import m.{m}`: the same rule in this file's table; the export set gets only the item (a qualifier is never exported).
>
> Tradeoffs (systems): resolution stays a table lookup with no fallback order to remember. Decided from the declaration kind, so no use-site search. Keeps src/cli.bl and the ~20 fixtures (all fns) legal.
>
> ### G3-P2: qualifier first in `m.y`, item for bare `m` (any kind)
>
> Also coherent and simpler to state, but `cfg.port` then silently means module item `port`, not the field: a silent change of meaning based on what module cfg exports. I rank it second.
>
> ### G3-P3: E1005 as written
>
> Breaks the spec's own Re-exports example and every fixture for no hazard in the fn case.

- **Web/Scripting:** (excerpt, section `G3 — `import m.{m}``)

>
> **Facts today.** `import greet.{greet}` then `greet("a")` calls the fn, and `greet.other()` is
> "unresolved method `.other` on type Fn(Str) -> Str": the item already wins over the qualifier.
>
> ### G3-P1 (preferred, option B): within one entry, a listed name equal to the qualifier wins; that entry binds no qualifier
>
> `import m.{m}` binds only the item `m`. It is not E1005 (one import, one binding). `m.x` in that
> file is access on the item: a field or method of a value, a static of a type, never module `m`'s
> other item `x`. The diagnostic for a failed `m.x` gets a help that says the qualifier is hidden and
> names the fixes. Names are case-sensitive, so `import shape.{Shape}` binds both `shape` and `Shape`
> as today. Same for fn, type and const items.
>
> ```blink
> import greet.{greet}
>
> fn main() {
>     io.println(greet("ann"))       // OK: the fn
>     io.println(greet.other())      // error: no method `other` on fn `greet`
>                                    // help: `import greet.{greet}` hides the module `greet`;
>                                    //   import it too: `import greet.{greet, other}`
>                                    //   or alias the module: `import greet as g.{greet}`, then `g.other()`
> }
> ```
>
> - `import m as k.{m}`: binds qualifier `k` and item `m`. Different names, no question.
> - `pub import m.{m}`: re-exports the item `m` (the export set holds items, not qualifiers). This
>   keeps the §Re-exports example `pub import auth.login.{login, AuthError}` valid as written.
> - `import m` and `import m.{m}` in one file: two imports bind `m` to two things, E1005 at the second
>   as for any other pair. Help: drop `import m` or alias one.
>
> Tradeoffs. For: `from greet import greet` is everyday Python, and ~20 fixtures plus src/cli.bl
> use it; the spec's own example uses it. B matches today, matches the rule that a nearer binding hides
> a qualifier (§10.1), and gives one meaning to `m.x`. Against: `m.other()` stops working in that file;
> the help covers it.
>
> ### G3-P2 (option C): both coexist
>
> `greet(..)` is the fn, `greet.other()` is the module. Clever, but for a type item `shape.new()` can
> mean a module fn or a static method, and readers must know a resolution order. More Stack Overflow
> questions than B, for a small gain. Not preferred. Option A (E1005) breaks the most common import
> shape in Python-trained code and the spec's own example; reject.

- **PLT:** (excerpt, section `G3: `import m.{m}``)

>
> Read literally, one entry binds `m` twice. But the spec already has the rule that settles it: "A local binding hides a module qualifier ... `auth.y` resolves against the local binding only" (§10.1), and "a qualifier is used only in `q.y`; a bare `q` never resolves to a qualifier" (§10.5). The listed item is a binding named `m`. Apply the same hiding rule, and there is no ambiguity to report.
>
> ### G3-P1 (preferred): the listed item hides its own entry's qualifier (option B, by the existing hiding rule)
>
> - `import m.{m}` binds the item `m`. The qualifier `m` of that entry is hidden in this file, the same as a local `let m` hides it. No E1005: one entry, one name, one item that can be reached.
> - Bare `m` / `m(...)` is the item, as for every import.
> - `m.x` resolves against the item `m` only, with no fallback to the qualifier (the same as the local rule). If the item is a fn, `m.x` is the usual "no such field/method" error. Its note names the hidden module and its help gives `import m.{m, x}` or `import m as mm.{m}` (the §10.6 shadow-diagnostic rule). If the item is a const of type `T`, `m.x` is a method or field of `T`.
> - A second entry in the same file that binds qualifier `m` (`import m.{x}`) binds `m` to the module, while the first binds `m` to the item: E1005 at the second entry, help "merge: `import m.{m, x}`". One file, one meaning for `m`.
> - `import m as k.{m}`: the names differ (`k` is the qualifier, `m` is the item). No hiding.
> - `pub import m.{m}`: the export set gets the item `m`. A qualifier is never exported, so the rule does not reach consumers.
> - Names are case-sensitive: `import shape.{Shape}` binds `shape` and `Shape`, which are two names. The rule does not apply.
>
> ```blink
> import greet.{greet}            // OK: binds fn `greet`; qualifier `greet` hidden in this file
>
> fn main() {
>     greet("x")                  // the fn
>     greet.hello()               // error: fn `greet` has no method `hello`
>                                 // note: module qualifier `greet` is hidden by the imported fn `greet`
>                                 // help: import greet.{greet, hello}
> }
> ```
>
> ```blink
> import greet.{greet}
> import greet.{hello}            // error[E1005]: `greet` is bound to fn `greet.greet` and to module `greet`
>                                 // help: import greet.{greet, hello}
> ```
>
> Tradeoffs. No new resolution rule: an item binding hides a qualifier, which is already true for locals. Resolution stays syntax-directed (no type-directed fallback in `m.x`). The spec's own `pub import auth.login.{login, ...}` and src/cli.bl stay valid.
>
> ### G3-P2: option C, qualifier first in `m.x`, item for a bare name
>
> This is a type-directed or position-directed overload of one name in one table. It contradicts the local-hides-qualifier rule (a local `m` wins in `m.x`, an imported `m` would lose), so two bindings of the same name kind resolve in opposite ways. Reject.
>
> ### G3-P3: option A, E1005 as written
>
> Sound, but it gives no gain in meaning, and it breaks the spec's own Re-exports example. Reject.
>
> Cross-language: Python `from m import m` rebinds `m` to the item and the module name goes away, which is P1. OCaml `open M` followed by a value `m` leaves `M.x` and `m` apart only because of case, which Blink does not have.
>
> ---

- **DevOps:** (excerpt, section `G3: `import m.{m}``)

>
> **Today (probed, package with src/greet.bl, pub fn greet, pub fn other):** the item wins.
> `import greet.{greet}` then `greet("a")` runs; `greet.other()` and `greet.greet("a")` fail with
> "unresolved method `.other` on type Fn(Str) -> Str". `import greet as g.{greet}` gives both
> `g.other()` and `greet("z")`. `pub import greet.{greet}` works.
>
> ### G3-P1 (preferred): the listed name wins in its own entry (option B), with a real diagnostic
>
> When a listed name (after `as` if any) equals the qualifier of its own entry, the entry binds
> only the item; it does not bind the qualifier. This is one import, so it is not E1005. Any OTHER
> import in the file that binds the same name (`import greet`, `import x.{greet}`) is E1005 as
> today. Case matters: `import shape.{Shape}` binds two different names, so this rule does not
> apply. Kind of item (fn, const, type) does not matter. `m.x` resolves against the item
> (field/method of a const, nothing on a fn), never the module. `import m as k.{m}` binds `k`
> and `m`, no conflict. `pub import m.{m}` re-exports the item; qualifiers are never exported.
>
> ```blink
> import greet.{greet}
> fn main() {
>     io.println(greet("a"))                    // OK: fn greet
>     io.println(greet.other())                 // error: see below
> }
> import greet as g.{greet}                     // OK: g.other() and greet("a") both work
> ```
>
> The error at `greet.other()` today names `Fn(Str) -> Str` and no module. It must say:
> "`greet` here is the fn `greet.greet` imported at line 1; the import does not bind the qualifier
> `greet` because its list takes that name". Help (suggestion, per §8.6 since it changes `m.y`
> meaning elsewhere): `import greet as greet_mod.{greet}`, then `greet_mod.other()`. LSP: go-to-def on
> bare `greet` lands on the fn; hover on the import entry says "binds `greet` (fn); qualifier not
> bound".
>
> Tradeoffs: matches today, keeps the facade shape (`pub import auth.login.{login}`, src/cli.bl,
> ~20 fixtures), and every name has one meaning in the file, so hover and rename stay simple. It
> is the same shape as the settled rule "a local binding hides a qualifier", one level up.
>
> ### G3-P2: coexist (option C)
>
> Qualifier in `m.y`, item elsewhere. Rejected: `cfg.port` with `import cfg.{cfg}` (a const
> struct) is ambiguous, and go-to-def on one token depends on the next token. One name, two
> meanings in one table is what E1005 exists to stop.
>
> ### G3-P3: E1005 (option A)
>
> Consistent with the letter of :4152 but breaks the spec's own re-export example and a common
> facade. The fix (`import m as m_mod.{m}`) is noise for users who never write `m.y`.

- **AI/ML:** (excerpt, section `G3 — `import m.{m}``)

>
> **Facts today:** `import greet.{greet}` binds the fn; `greet.other()` then reports
> "unresolved method `.other` on type Fn(Str) -> ()": the item wins and the qualifier is gone.
> `import greet as gg.{greet}` gives both `gg.other()` and `greet(...)`.
>
> ### G3-P1 (PREFERRED): one entry, one binding — the listed item wins; not E1005
>
> Inside one entry, a listed name that equals the entry's qualifier binds the item only; the entry
> binds no qualifier. E1005 does not apply (it is about two imports). `m.x` in that file is access
> through the item (field, method, or static of a type), never through the module. Names are
> case-sensitive: `import shape.{Shape}` binds both `shape` and `Shape`. Same rule for a fn, type,
> const. `import m as k.{m}` binds `k` and `m`, no overlap. `pub import m.{m}` re-exports the
> item `m` (a qualifier is never exported). A second entry that binds qualifier `m` (for example
> `import m` plus `import m.{m}`) is E1005 at the second entry.
>
> ```blink
> import greet.{greet}             // binds fn `greet` only
> import auth.login.{login}        // binds fn `login` only
>
> fn main() ! IO {
>     greet("a")                   // OK: the fn
>     greet.other()                // error: no method `other` on fn `greet`
>                                  //   note: `greet` is the fn from `import greet.{greet}`, not the module
>                                  //   help: list it: `import greet.{greet, other}`
>                                  //   help: or rename the module: `import greet as g.{greet}`
> }
> ```
>
> Tradeoffs: this keeps the `from datetime import datetime` idiom that models write by habit
> (Python, and the spec's own re-export example). One lookup rule, no fallback chain. The cost is
> one diagnostic that must name the hidden qualifier; today's "unresolved method on Fn" text gives
> a model no clue, so the note/help above is part of this proposal.
>
> ### G3-P2: qualifier and item coexist (`m.x` tries the module, then the item)
>
> Two-step lookup on every `m.x`. When the item is a type with a static `new` and the module has
> a pub `new`, the result depends on lookup order: a hidden decision point. Rejected by this seat.
>
> ### G3-P3: E1005 as written
>
> Breaks ~20 fixtures, src/cli.bl and the spec's own example, and rejects a top idiom in training
> data. Simple to learn, but high friction for no safety gain.
>
> ---

- **Minimalism:** (excerpt, section `G3 — `import m.{m}``)

>
> Facts today (gen1, probe g3/): `import greet.{greet}` then `greet.other()` is "unresolved method `.other` on type `Fn() -> Str`"; with `import c.{cfg}` (pub const `cfg: Cfg`, and module `c` also has `pub const port`), `cfg.port` prints the field (8), not `c.port` (99). So today the listed item wins and the qualifier is not bound.
>
> ### G3-P1 (PREFERRED): an entry whose listed name equals its own qualifier binds only the item — option (B), which is today's behavior
>
> - `import m.{m}` binds one name, `m`, to the item. It does not bind the qualifier `m`. One binding, so no E1005 from that entry. E1005 still applies across imports as written ("two imports").
> - So in that file `m.y` resolves against the item: a field, a method, or a type-scoped fn of the item. There is no fallback to the module. That is the rule the spec already has for a local binding that hides a qualifier (§10.1); reuse it and its diagnostic note that names the hidden module.
> - Works the same for a fn, a type and a const. Names are case-sensitive: `import shape.{Shape}` binds `Shape` and `shape`, no overlap, not this case.
> - `import m as k.{m}`: qualifier `k`, item `m`, no overlap. This is the fix to offer when a user wants both (`k.other()`).
> - `import m.{m as mm}`: qualifier `m`, item `mm`, no overlap.
> - `pub import m.{m}`: the export set gets item `m`; a qualifier never enters the export set, so nothing changes.
>
> ```blink
> // src/greet.bl
> pub fn greet() -> Str { "hi" }
> pub fn other() -> Str { "o" }
>
> // src/main.bl
> import greet.{greet}
> fn main() {
>     io.println(greet())            // OK: the fn
>     io.println(greet.other())      // error: no method `other` on `fn() -> Str`
>                                    // note: the import of `greet` hides the module qualifier `greet`
>                                    // help: `import greet as g.{greet}`, then `g.other()`
> }
> ```
>
> Tradeoffs: zero compiler change, zero new rule (reuses "a binding hides a qualifier, no fallback"), keeps the spec's own `pub import auth.login.{login, AuthError}` and ~20 fixtures valid. (A) E1005 punishes a very common, harmless idiom with alias noise. (C) "qualifier first, then item" adds a lookup order with fallback, which §10.1 has rejected on purpose, and is ambiguous for a const struct (`cfg.port`: field or module const?).
>
> Cross-language: Python `from m import m` rebinds `m` to the item, the module name is gone — the same result.

#### Phase B — Debate highlights

- **Systems:** (excerpt, section `G3: G3-B (changed from G3-K)`)

> I move to B. My Phase A worry was `cfg.port` with `import cfg.{cfg}`: two readings. Under B
> there is one reading (the item, as a local hides a qualifier), decided from the entry, with no
> look at what module `cfg` exports. That is the deterministic rule I wanted, and it covers every
> item kind with one rule instead of a kind split. K's one gain (`greet.other()` reaching the module)
> is not worth a rule that changes by item kind. I support both B variations (web: `import m` plus
> `import m.{m}` is E1005; plt: a second `import m.{x}` is E1005 with a merge help): each is just
> "two imports bind `m` to different items", the existing E1005 text.

- **Web/Scripting:** (excerpt, section `G3: G3-B (no change); I accept plt's variation`)

> Against G3-K (sys):
> - Whether an import is legal depends on the kind of the item. If `greet` changes from a fn to a
>   type, or a const becomes a fn, files that import it start or stop failing at the import line.
>   Under B the import line never fails on its own.
> - Under K, `greet("x")` is the fn and `greet.other()` is the module, so one name means two things
>   in one file. A reader must know the item's kind to read `greet.x`. That is the Stack Overflow
>   question B avoids.
> - sys's hazard (`cfg.port` meaning two things) does not exist under B: `cfg.port` is always the
>   field of the item `cfg`, and nothing changes meaning when module cfg adds an export.
> - K buys `greet.other()` without an alias. The B help gives that in one edit (`import greet.{greet, other}`).
>
> plt's variation (`import m.{m}` plus `import m.{x}` in one file is E1005, help: merge the entries)
> follows from B, and so does mine (`import m` plus `import m.{m}` is E1005). I accept both as one rule:
> in a file, `m` names the item or the module, never both.

- **PLT:** (excerpt, section `G3: G3-B (no change), with both E1005 variations`)

>
> - web's variation (`import m` plus `import m.{m}`) and mine (`import m.{m}` plus `import m.{x}`) are one rule: two entries bind `m`, one to the module and one to the item, so E1005 at the second entry, with the help to merge. Put both in.
> - **Against G3-K:**
>   1. It makes resolution depend on the item's kind. Under K, `m.x` means the module when `m` is a fn and is an error when `m` is a const. That is the type-directed overload that §10.5 avoids by giving bare names and qualifiers one table.
>   2. It inverts the existing hiding rule. A local `let greet = ...` hides the qualifier in `greet.x` (§10.1). Under K, an imported fn `greet` would not hide it. So two bindings of the same name resolve `greet.x` in opposite ways.
>   3. It is not stable. If fn values ever get methods, `greet.other()` becomes ambiguous for fns too, and K must change. B does not depend on what members a fn has.

- **DevOps:** (excerpt, section `G3: G3-B (no change), with both variations`)

>
> web's and plt's variations are the same rule: in a file, `m` may have only one meaning. If
> another entry binds the qualifier `m` (`import m`, `import m.{x}`), that is E1005, because one
> entry binds `m` to the fn and the other binds it to the module. Help for the plt case: merge into
> `import m.{m, x}`. I accept both.
>
> Against G3-K (sys):
> 1. The kind of the imported item decides whether the import is legal. If the author of the
>    imported module changes `pub fn cfg` to a `pub let cfg` const, every importer breaks with
>    E1005 at the import line, and the importer did not touch that line. The error appears in a
>    file that the person who made the change does not own.
> 2. What one token resolves to depends on the next token: `greet` is the fn in `greet(x)` and
>    the module in `greet.other()`. Go-to-definition, hover and rename must look at the parse
>    context to answer. With G3-B, the name `greet` has one target in the whole file.
> 3. Today's compiler does B. K changes how existing files resolve. B changes only one message.

- **AI/ML:** (excerpt, section `G3: G3-B (no change)`)

> Against G3-K:
> - The rule depends on the kind of the item (fn yes, const or type no). A model must know the kind of the item in another module before it can write the import line. That is a non-local decision point.
> - Under K, `greet("x")` is the fn and `greet.other()` is the module, so one bare name has two meanings in one file. The spec chose one shared binding table for bare names and qualifiers (§10.5) to stop this.
> - B matches gen1 today and the `from x import x` habit in training data.
>
> I support both variations within B as one rule: a second entry in the same file that binds qualifier `m` (`import m` or `import m.{x}`) next to `import m.{m}` is E1005 at the second entry. The help says to merge into `import m.{m, x}` or to alias with `import m as mm`.
>
> Writer note: the `m.x` diagnostic must name the hidden module and give both repairs. Today's "unresolved method `.other` on type Fn" gives no clue.

- **Minimalism:** (excerpt, section `G3: stay with G3-B. Accept both variations in B (web, plt).`)

> Both variations follow from the E1005 rule as it is written: `import m` or `import m.{x}` binds the qualifier `m` to the module, `import m.{m}` binds `m` to the item, so two entries bind one name to different items = E1005. That is no new rule. The help to merge into one entry is good.
>
> Against G3-K (sys):
> - The legality of an import depends on the kind of the item. If the owner of module `cfg` changes `pub fn cfg` to `pub const cfg`, every importer gets a new E1005 at an import line that did not change. B gives one rule for every kind.
> - K lets one name hold two roles in one file (a bare `greet` is the fn, `greet.y` is the module), but §10.5 says bare names and qualifiers share one table for this reason. K adds a special case to that table.
> - K's premise "`m.y` on a fn is never member access" is a rule that a later feature (methods on fn types, a trait impl for a fn type) can break. B does not depend on it.
> - The cost of B is only `greet.other()`, and the help gives two one-line fixes. That is gen1's behavior today, with a better diagnostic.

#### Phase C — Final vote

- **G3-Q1: `import m.{m}`: the listed item hides its own entry's qualifier (6-0; not E1005)**

- **Systems:**

> ## G3-Q1
> **Vote:** B
> **Reasoning:** One name has one target in the file, and the import entry alone decides it, so resolution is a table lookup with no dependence on the item's kind or on what module `m` exports. It is gen1's behavior today, and it is the same as a local hiding a qualifier. The E1005 variations (`import m` or `import m.{x}` next to `import m.{m}`) follow from the existing text.
> **Concern:** If the diagnostic for `greet.other()` does not name the hidden module and give both repairs, users will read a "no method on fn" error as a compiler bug.

- **Web/Scripting:**

> ## G3-Q1
> **Vote:** B
> **Reasoning:** `from greet import greet` is everyday Python. B keeps it legal for every item kind and gives the name one meaning per file. B is also what gen1 does today. Under K, whether an import is legal changes when the imported module changes an item's kind, and `greet` means two things in one file.
> **Concern:** Today's error for `greet.other()` ("unresolved method `.other` on type Fn") gives no clue. Unless the hidden-module help ships with the rule, users will think imports are broken.

- **PLT:**

> ## G3-Q1
> **Vote:** B
> **Reasoning:** An imported item named `m` hides the qualifier `m` the same way a local `m` does (§10.1). Resolution stays syntax-directed, one name has one target per file, and the rule does not depend on the item's kind or on what members a fn may later get. A second entry that binds `m` to the module is the existing E1005, so no new rule is needed.
> **Concern:** The `m.x` diagnostic must name the hidden module and give both repairs. Without that, the hiding looks like a compiler bug ("no method `other` on fn").

- **DevOps:**

> ## G3-Q1
> **Vote:** B
> **Reasoning:** Each name in a file has one target, so go-to-definition, hover and rename need no context from the next token, and an import never breaks because another module changed an item's kind. It matches gen1 today, so the only change is a better diagnostic for `m.x`.
> **Concern:** If the `m.x` diagnostic does not name the hidden module and give both repairs, users keep getting today's "unresolved method `.other` on type Fn(Str) -> Str", which gives them no clue.

- **AI/ML:**

> ## G3-Q1
> **Vote:** B
> **Reasoning:** One name has one meaning in a file, decided from the import line alone. The rule does not depend on the item's kind in another module. B keeps the `from x import x` habit that is common in training data, and matches gen1 today. The cost is one diagnostic for `m.x`, with two one-edit repairs.
> **Concern:** If the `m.x` diagnostic stays "unresolved method on type Fn" and does not name the hidden module, models will not find the alias repair.

- **Minimalism:**

> ## G3-Q1
> **Vote:** B
> **Reasoning:** It is today's behavior, and it reuses the "a binding hides a qualifier, no fallback" rule for every item kind. The E1005 variations follow from the existing text with no new rule. K makes import legality depend on the kind of an item in another module, which adds a case.
> **Concern:** If the diagnostic for `m.x` does not name the hidden module and give the alias fix, users will read "no method `other` on fn" as a compiler bug.

### Final Spec

```blink
import m.{m}                  // OK: `m` is the item; it hides the qualifier `m`
import m as k.{m}             // OK: `m` is the item, `k` is the module
import m.{m}
import m                      // error[AmbiguousImport] (E1005) at the later entry
```

- An entry that lists a name equal to its own qualifier binds that name to the item only. The item hides the qualifier, for a fn, a type, a trait and a const. This is not E1005.
- In that file `m.x` is resolved against the item. A `m.x` that does not resolve names the hidden module and gives both repairs: `import m.{m, x}` and `import m as k.{m}` then `k.x`.
- Another entry in the file that binds the qualifier `m` (`import m`, `import m.{x}`) is E1005 at the later entry, with a help to merge the entries or alias the module.
- `import m as k.{m}` has the qualifier `k` and no conflict.
- `pub import m.{m}` re-exports the item. The `pub import auth.login.{login, AuthError}` example stays valid.
- Names compare case-sensitive: `import shape.{Shape}` is not this case.
- Spec text: §10.1 *Qualified Access*; §10.5 *Imported Names*, *A listed name that equals its own qualifier*; E1005 in ERROR_CATALOG.md.
