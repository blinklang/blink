[< All Decisions](../DECISIONS.md)

# `mut` in Patterns — Design Rationale

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated in independent-proposal → debate → vote rounds.

The gap: the spec said nothing about `mut` inside a destructuring pattern. On the compiler at main 63da669b:

| Source | Result |
|---|---|
| `let mut (x, y) = (1, 2)`, then `x = x + 1; y = y + 1` | compiles; both names mutable |
| `let (mut x, mut y) = pair` | `UnexpectedToken: unexpected token in pattern: mut` |
| `for (k, mut v) in xs`, `Some(mut v) =>` | same parse error |
| `for mut (k, v) in xs`, `for mut i in xs` | parse error (`mut` read as a name) |
| `let (a, b) = (1, 2)`, then `a = 5` | compiles and runs; no E0610 |
| `Some(v) => { v = v + 1 }`, `for i in xs { i = i + 1 }` | compiles and runs; no E0610 |

So the compiler enforced immutability on no pattern binder, and it rejected the form that agents write first. The ticket was P0 because it blocked Blink in a token benchmark.

#### Phase A — Independent proposals

All six ranked the same shape first: `mut` is a prefix on a binder name in every pattern position.

- **Systems:** "Grammar: `BindPat := "mut"? IDENT`. `let mut x = e` is then `let <BindPat> = e`, so the existing form needs no special rule. The same pattern grammar serves let, for, match and `as`. This is the Rust model." On cost: "Whether a binder is mutable changes nothing in the emitted code. Each pattern binder becomes one fresh C local, with or without `mut`." On stakes: "A `for` variable or `match` binder can be reassigned and then captured by a spawned closure, and E0650 does not see it. That is a data-race hole, and it is the strongest reason to decide this now."
- **Web/Scripting:** "A JS or Python dev learns the rule from one example in under a minute: "`mut` goes in front of the name that changes." The same words work in `let`, `for` and `match`, so there is nothing more to learn." And: "Shipping the syntax without enforcement leaves `mut` as decoration. Shipping enforcement without the syntax gives an error whose fix is impossible to write."
- **PLT:** "Mutability is a property of a name in the environment (Γ ⊢ x : T, mutable), not of a type or a value. So the rule must attach `mut` to the place where a name is introduced: the variable leaf of a pattern." Proposed OR-pattern agreement: "a binder must have the same mutability in every alternative, just as it must have the same type." First proposed a warn-first removal of `let mut (x, y)`: "Accept it with a warning that has an auto-fix, migrate the code, then make it an error".
- **DevOps:** "Each binder carries its own mutability bit, so E0610, UnusedMut and the E0650 spawn-capture check all read one place. A mutability bit on the whole pattern would force every lint to walk up the tree to the `let`." On the fix: "The help shows the edited pattern, not a general rule, so an agent can copy it." Listed `with open(path) as mut f { }` in its first example.
- **AI/ML:** "In Rust, `let (mut a, b)`, `Some(mut v)` and `for (i, mut x)` are the only legal forms. In Rust, `let mut (a, b)` is itself an error ... An agent trained on Rust gets Blink right on the first try. Today it fails at parse time, which is the benchmark failure in this ticket."
- **Minimalism:** "My test is which choice gives the fewest rules. The answer is one rule: **`mut` is a prefix on a binder name, and nothing else.**" Considered and rejected the zero-syntax option (always immutable, rebind with `let mut x = x0`): "Minimal syntax that costs an extra rebind on every use is not minimal in total."

Fallbacks: Systems, Web, PLT, DevOps and AI/ML listed "A plus `let mut <pattern>` as sugar" second. Minimalism rejected it: "That gives two spellings and a precedence question (`let mut (mut x, y)`?). It is the C++ path." All six rejected "binders always immutable".

#### Phase B — Debate highlights

One round. All six ended "STABLE, ready to vote".

- **Enforcement timing.** Web: "The warn-first rule in §3.6 is for errors that change the meaning of code users wrote against the spec. `let mut (x, y)` was never in the spec, and the fix keeps behavior exactly." DevOps: "The 3-step bootstrap protocol is only the order of work inside this repo (add, migrate src, reject). It is not what users see." PLT withdrew its warn-first wording in Phase C.
- **One code for OR-pattern agreement.** Systems: "One binder in an OR-pattern lowers to one C local that every alternative writes, so it can have only one mutability. But I would not add a new code, E0614." Minimalism: "That changes one rule and adds no new code."
- **Option B.** Minimalism quoted the fallback texts back: "Five of six panelists list B as a fallback. Their own texts argue against it." AI/ML: "B would keep two spellings in the docs and in this repo's corpus, and future models train on that corpus."
- **`with expr as mut f`.** Web, AI/ML and Minimalism first said the binder rule covers it. Systems rebutted: "If `f` is `mut`, then `f = other` inside the body has two effects: `close()` runs on `other`, so `other` is closed twice when its own `with` ends. The resource that `with` acquired is never closed. It leaks." DevOps withdrew it: "§2.18 binds one name, not a pattern, and promises to close "the" resource."
- **Parameter patterns.** DevOps: "If E0610 fired here with an "insert `mut`" fix, `blink fix` would apply it, and the next build would then report E0612: a fix loop that never ends."
- **`mut whole as (a, b)`.** Systems: "this is the one place where Option A looks like the old whole-pattern form ... The spec example must say this explicitly."
- **Diagnostic name.** Minimalism: "`MutOnPattern`. Three panelists chose it, and I drop `MutOutsideBinder`." AI/ML: "I switch from `MutOnPattern` to **`MutOutsideBinder`** (min), with code E0613. Use one code for `mut (x, y)`, `mut _`, `mut 5` and `mut None`, because all four have the same cause: `mut` is not before a name."
- **Fix shape.** Web: "after the `MutOnPattern` fix, UnusedMut warnings fire on binders that the fix itself just added. I ask the implementer to make the E0613 fix put `mut` only on binders the body mutates where the checker knows this ... This is implementation guidance, not a spec rule."

#### Phase C — Final vote

- **Q1: Surface form — A (`mut? IDENT` per binder)** (6-0)
  - **Systems:** A — "The mutability bit belongs on the C local that each binder lowers to, so it belongs on the binder in the grammar."
  - **Web/Scripting:** A — "B gives two spellings and an FAQ question: what does `let mut (a, c as Cfg { port, .. })` mean?"
  - **PLT:** A — "B makes the scope of a distributed `mut` unclear in nested and `as` patterns, and it still needs per-binder `mut` for `match` and `for`. C does not compose."
  - **DevOps:** A — "B needs three more diagnostics (a redundant `mut`, a two-edit UnusedMut fix, and a rule to choose a spelling) to keep a shorthand that saves one token."
  - **AI/ML:** A — "This is also the form that Rust-trained models already write ... so agents get it right on the first try."
  - **Minimalism:** A — "`mut? IDENT` is one rule, and parameters already use it."
- **Q2: E0610 on pattern binders — error at once** (6-0)
  - **Systems:** "Today a reassigned `for` or `match` binder slips past E0650 when an `async.spawn` closure captures it. That is a data-race hole, not a style issue."
  - **Web/Scripting:** "The fix is one exact edit, and an agent reads a warning as "done"."
  - **PLT:** "Accepting them is a soundness bug in the checker, not a behaviour we promised."
  - **DevOps:** "The fix is exact and `blink fix` applies it, so a warning release buys users nothing."
  - **AI/ML:** "A warning period lets agents and the corpus learn the wrong form from code that compiles."
  - **Minimalism:** "§2.2 already makes these writes illegal, so this is a bug fix."
- **Q3: Machine-applicable E0610 fix for local pattern binders** (6-0, yes)
  - **Systems:** "The edit is one token at a single declaration site. It does not change codegen or the effect row."
  - **Web/Scripting:** "A help line that shows the user's own pattern with `mut` inserted gives a fix a user can copy and paste."
  - **PLT:** "The fix is a local insertion at the single declaration site that changes no meaning, so it meets the bar for a machine fix."
  - **DevOps:** "The help line must show the user's own pattern after the edit (`for (k, mut v) in pairs`), because an agent copies it."
  - **AI/ML:** "An exact fix is the cheapest diagnostic for an agent to act on."
  - **Minimalism:** "the "help only" exception in §2.22 has no reason left, and removing it shortens the spec."
- **Q4: Name of E0613 — `MutOnPattern`** (4-2, Systems and AI/ML dissent; one code for all non-name forms 6-0)
  - **Web/Scripting:** `MutOnPattern` — "`MutOnPattern` names what the user wrote, in plain words. "Binder" is a PLT word that a web dev has to look up."
  - **PLT:** `MutOnPattern` — "All the cases have one cause (`mut` with no name to mark), so one code with a help line for each case is the right split."
  - **DevOps:** `MutOnPattern` — "The name says what the user wrote, with no jargon ("binder") to explain".
  - **Minimalism:** `MutOnPattern` — "the majority already uses `MutOnPattern`, and I dropped my name in Phase B."
  - **Systems:** *(dissent)* `MutOutsideBinder` — "`_` and `5` are patterns but not binders, so the binder framing covers every case without a special clause. It also covers the `with ... as` rejection in Q7 ... I accept `MutOnPattern` if it wins."
  - **AI/ML:** *(dissent)* `MutOutsideBinder` — "`_`, `5` and `None` are patterns but not binders, so `MutOnPattern` gives the wrong cause for them."
  - Concern fields of PLT ("the name reads oddly for `mut _` and `mut 5`, so the per-case help line must carry the explanation") and Web ("for `mut _` and `mut 5` the name reads a little oddly") grant the dissent's point. Read as soft consensus, so no Phase D; the user approved that reading.
- **Q5: `let mut (x, y)` for users — error at once with a machine fix that puts `mut` on every binder** (6-0)
  - **Systems:** "The spec never defined this form, so no deprecation was promised."
  - **Web/Scripting:** "A warning release gives two legal spellings for one release, and examples written during that release keep teaching the wrong one."
  - **PLT:** "I withdraw my Phase A warn-first wording. The 3-step protocol is for the compiler source."
  - **DevOps:** "A warning release would give two legal spellings, and agents and the repo corpus would learn the wrong one."
  - **AI/ML:** "The 3-step protocol is only for our own source."
  - **Minimalism:** "The 3-step protocol is a constraint on our own source, not a user policy."
- **Q6: OR-pattern mutability — extend `InconsistentPatternBindings`** (6-0)
  - **Systems:** "That is the same kind of agreement as "same type", so it is the same check and the same code."
  - **Web/Scripting:** "this is the same "alternatives must agree" rule with one more field".
  - **PLT:** "Mutability is part of a binder's static judgement, just like its type."
  - **DevOps:** "Mutability is one more field of the same agreement check, so one cause gets one code."
  - **AI/ML:** "A new code adds a catalog row and something new to learn, with no gain in precision."
  - **Minimalism:** "this extends one existing rule and adds no new code."
- **Q7: `with expr as mut f` — rejected (E0613)** (6-0; Web, PLT, AI/ML and Minimalism changed from Phase B)
  - **Systems:** "If `f` can be reassigned, `close()` runs on the new value: the acquired resource leaks and the other value is closed twice."
  - **Web/Scripting:** "in Phase A I put uniformity first, but sys showed a real footgun."
  - **PLT:** "Cleanup in `with` holds only if the name still refers to the acquired resource when the block ends."
  - **DevOps:** "A change to state outside the language (a file, a socket) takes plain `self` (§3.6), so `f.write(..)` needs no `mut`."
  - **AI/ML:** "That is a real correctness hole, which outweighs uniformity."
  - **Minimalism:** "§3.6 lets external-state methods take plain `self`, so `mut` buys nothing here (YAGNI)."
- **Q8: Struct field binders** (6-0, yes)
  - **Systems:** "Shorthand `{ mut x }` is sugar for `{ x: mut x }`. `{ mut x: px }` puts `mut` before a field name, not a binder".
  - **PLT:** "`{ mut x: px }` puts `mut` on a field label, which is not a binder, so it is E0613."
  - **Web/Scripting, DevOps, AI/ML, Minimalism:** yes — it "follows from the grammar".
- **Q9: A binder in a parameter pattern is a parameter (E0612 for `=`)** (6-0, yes)
  - **Systems:** "This also prevents the fix loop that devops found".
  - **PLT:** "Any other rule would let one name follow two different rules depending on whether the parameter is destructured."
  - **DevOps:** "One role per binding site gives one diagnostic and one fix that ends the loop."
  - **Web/Scripting, AI/ML, Minimalism:** yes — "we do not create a third class of binding" (Minimalism).
- **Q10: UnusedMut per binder; a `mut` binder counts as `let mut` for E0650; a binder is a new local with no write-back** (6-0, yes)
  - **Systems:** "a binder is a by-value copy into a fresh local, and a shared cell copies its pointer, so pushes alias but `=` never writes back."
  - **PLT:** "A `mut` binder is a fresh local, and only shared cells alias."
  - **Web/Scripting:** "`Some(mut u) => u.visits += 1` looks as if it changes the Option, and the spec must say that it does not, except through shared cells."
  - **DevOps, AI/ML, Minimalism:** yes on all three parts.

**Concerns for the implementation** (from the Phase C Concern fields):

- Systems, Web, PLT, DevOps, AI/ML and Minimalism: the `let mut (x, y)` fix adds `mut` to names the body never mutates, so UnusedMut fires on the fix's own output. Put `mut` only on mutated binders where the checker knows them.
- Systems and DevOps: the parser recovers from E0613 by putting `mut` on every leaf, so one E0613 does not hide later errors.
- PLT and Systems: the E0610/E0612 choice reads where the binder was bound; a parameter-pattern binder never gets the "insert `mut`" fix.
- Systems: run the corpus once with the check on before landing, so the size of the break is known.
- DevOps and AI/ML: struct patterns in `let` do not parse yet (separate bug); test field binders in `match` first.
- Web and DevOps: reword `InconsistentPatternBindings` so a mutability mismatch does not read as a type mismatch.

**AI-first review:** learnability, consistency, generability, debuggability, token efficiency: 5/5 pass. The one token cost is `let (mut x, mut y)` over `let mut (x, y)`.

### Final Spec

```blink
let (mut lo, hi) = bounds(xs)              // only `lo` is mut
for (name, mut score) in scores { score += 1 }
for mut i in xs { i += 1 }                 // legal: `i` is a binder
match o {
    Some(mut n) => { n *= 2 }
    None => {}
}
let Point { mut x, .. } = p                // short for `x: mut x`
let Point { x: mut px, .. } = p
let mut whole as (a, b) = pair             // only `whole` is mut

let mut (x, y) = pair                      // error[E0613] MutOnPattern: fix `let (mut x, mut y)`
let (a, b) = pair
a = 5                                      // error[E0610]: fix `let (mut a, b)`
with fs.open(p)? as mut f { }              // error[E0613]: remove `mut`
fn f((mut xs, n): (List[Int], Int)) { n = 1 }   // error[E0612] ParamAssign
```

- `binder ::= "mut"? IDENT` in every pattern position (§3.5 *Mutable Binders*). `mut` marks one name.
- `mut` before a tuple, struct, constructor, variant, `_`, literal, range, field label or `with` name is E0613 `MutOnPattern`, with a machine fix.
- E0610 covers every pattern binder at once; the fix "insert `mut` before the binder" is machine-applicable for local binders and edits every OR alternative.
- OR-pattern alternatives agree on mutability under `InconsistentPatternBindings`.
- A parameter-pattern binder is a parameter (§3.6): `mut` allows mutating calls; `=` is E0612.
- A `mut` binder is a `let mut` for E0650 and UnusedMut (per binder). A binder is a new local; assignment never writes back, and shared cells still alias.
- No warning release for users; the compiler source migrates by the 3-step bootstrap protocol.
