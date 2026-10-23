[< All Decisions](../DECISIONS.md)

# Field Faults in Struct and Variant Brace Patterns — Design Rationale

**Resolution:** the labels of a struct pattern and of a variant brace pattern (bare `Rect { .. }` and qualified `Shape.Rect { .. }`) are checked like the labels of a literal. An unknown label is `NoSuchField` (E0525, widened). A label given twice is `DuplicateField` (E0316, widened). Fields left out with no `..` are the new `PatternMissingRest` (E0319). `..` is the preferred, machine-applicable fix; `f: _` for each left-out field is a second fix that is never machine-applicable. A punned unknown label gets the fix `y: yy`.

**Vote:** Q1 6-0; Q2 3-3 in Phase C, 6-0 in Phase D; Q3 4-2 in Phase C, 6-0 in Phase D. AI-First 5/5 pass.

## The Gap

§3.5 says "`..` is required when not all fields are listed", but no catalog code covered a struct pattern that leaves out fields, and the `NoSuchField` row named literals and field access only. Measured on the compiler at the time (gen1, v0.57.0):

| Program | `blink check` |
|---|---|
| `match p { Point { x, bogus } => x }` | ok; only `warning[UnusedVariable]` for `bogus` |
| `match p { Point { x } => x }` (`y` omitted, no `..`) | ok |
| `match s { Shape.Rect { w, .. } => w }` | ok (the grammar had no qualified variant brace pattern) |
| `match p { Point { x, x: z, .. } => x + z }` | ok |

### Panel Deliberation

The ticket, verbatim:

> **Spec: struct-pattern field faults: code for unknown field (widen E0525?) and for omitted fields without ..**
>
> Section 3.5 requires .. when a struct pattern omits fields, but no catalog code covers it, and E0525 NoSuchField names literals and field access only. On v0.57.0 gen1, 'match p { Point { x, bogus } => x }' passes check with only UnusedVariable, and 'match p { Point { x } => x }' passes too. Decide: (1) is an unknown field label in a pattern E0525 (widen the row) and what the help says; (2) the code and fix for a missing .. (reuse the literal MissingField code or a new one; machine-applicable fix adds ..); (3) binder poison and E0004 after the error, as E0547 does. Implementation ticket: [the struct-pattern field ticket].

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated in independent-proposal → debate → vote rounds, with one extra round (Phase D) on the two questions that Phase C left open.

#### Phase A — Independent proposals (excerpts)

- **Systems:**

  > A struct pattern compiles to a tag test (for a variant) plus one load per listed field, and one compare per refutable sub-pattern. An omitted field is no load and no test, with or without `..`. So every rule here is a compile-time rule with zero runtime cost, and the fix "add `..`" never changes what the program does. That second fact matters most to me: a fix that cannot change codegen is safe for a tool to apply in bulk.

- **Web/Scripting:**

  > The main rule I argue for: **a struct pattern uses the same three field checks as a struct literal, with the same codes and the same order.** A user who learned the literal errors (DECISIONS *Field checks in struct and variant literals*) already knows the pattern errors. One mental model, three codes, no new catalog row. The only part that differs is the fix for an omitted field, because in a pattern the right fix is the opposite of the literal fix: you do not supply the field, you ignore it.

- **PLT:**

  > These are the same three conditions the literal rules check (DECISIONS.md *Field checks in struct and variant literals*), but condition 3 differs in kind. In a literal, a missing field means no value exists: the term is ill-formed and no repair keeps its meaning. In a pattern, a missing field has one obvious meaning (match anything there): the pattern is well-defined, only its *form* is wrong. So conditions 1 and 2 reuse the literal codes, and condition 3 gets its own code. The recovery rules follow from the same split: faults 1 and 2 make the pattern's meaning unknown; fault 3 does not.

- **DevOps:**

  > A pattern differs from a literal in one way that matters for tooling: a pattern never needs a value from the user. So a pattern fault almost always has a safe, mechanical repair, where a literal fault (E0315) does not.

- **AI/ML:**

  > The `Point { x }` case (no `..`) will be the most frequent fault in AI output, because JS/TS destructuring (`const { x } = p`) allows a partial field list and that habit is heavy in training data. Rust writers already add `..`. So the omitted-`..` diagnostic must be cheap to repair, and the repair must be machine-applicable.

- **Minimalism:**

  > My position: this gap needs **zero new codes and zero new mechanisms**. The literal field checks (DECISIONS.md *Field checks in struct and variant literals*) already gave us three rows for exactly these three faults: unknown label, duplicate label, missing label. [...] Each new code we mint here is a code an agent must learn that means the same thing as one it already knows.

#### Phase B — Debate highlights (1 round; all six stable)

The moderator grouped the Phase A proposals into options:

- **M1 / M2** — the code for fields left out with no `..`. M1: widen E0315 `MissingField` to patterns (web, sys, min). M2: a new code (devops, aiml, plt).
- **F1 / F2** — a machine-applicable fix that adds `..`. F1: yes (web, sys, devops, aiml, plt). F2: no machine fix (min).
- **V1–V6** — V1: the fix for an unknown punned label. V2: which errors make a bad arm. V3: the poison scope. V4: whether the one suggestion for an unknown label counts as missing. V5: whether a field default counts as naming the field. V6: whether the help says "or add the field to `T`".

Key shifts:

- **Minimalism** conceded F1, and then M1: "I was alone on F2. [...] the compiler already reads the pattern as if `..` were there, so the fix changes no behaviour and adds no diagnostic. [...] The signal is the error, not the absence of a fix." And: "With F1, it needs three [exceptions]: a different help ("add `..`", not "add each field with a value"), a different fix policy (machine-applicable, where the literal row says "No machine-applicable fix" by decision), and no "or give it a default" line (wrong advice in a pattern; devops-1 point 2). [...] Minimalism counts rules an agent must branch on, not rows in a table."
- **Systems** moved from M1 to M2: "devops: the E0315 help says "or give it a default". In a pattern that advice is wrong (all six seats agree defaults play no role in a pattern). A widened E0315 row must then carry a "but not in a pattern" exception in its help, its fix policy and its `blink explain` text. That is two rows written as one. [...] Codes cost nothing at run time; a code whose meaning depends on where it fires costs every tool."
- **Web/Scripting** moved from M1 to M2: "From my seat, the deciding test: a JS/Python dev who sees `MissingField` on a pattern thinks "I must supply a field", and does the opposite of the fix."
- **DevOps** brought the §8.6 evidence: "The spec makes the name the key for a fix strategy. E0315's strategy is "write each field with a value; no machine fix" (ERROR_CATALOG :106, by decision). The pattern strategy is "add `..`; machine fix". Under M1 one name maps to two strategies, picked by syntax position. That breaks the §8.6 contract, not just a style preference."
- **All six seats** ended on a new code for the missing `..` (M2). The panel took devops's name, `PatternMissingRest`; the number went to Phase C.
- **PLT** on V1, with a counterexample: "web-1's fix gives `Point { x, y } => x + y + y`. The new binder `y` captures the body's `y`, which meant the parameter, so the program now computes a different value and no diagnostic says so. [...] `y: yy` cannot capture anything: it touches only the label, which lives in the field namespace, not the value namespace."
- **Systems** on V1: "Rename the pun `yy` to `y` and its uses: the body becomes `x + y + y`, and the parameter `y` is now shadowed. The program compiles and computes a different value. A machine fix must never do that."
- **Web/Scripting** withdrew its body rename: "plt-1 is right: "A machine-applicable fix must not create a new error." My Phase A fix (rename the pun to `y` and rename its uses in the arm body) is safe, but it is an edit across the whole arm, and that is a refactor, not a quick fix. `y: yy` is local, compiles clean, and the user can then rename the binder with the LSP if they want. I withdraw my "never `y: yy`"."
- **AI/ML** on V1: "My own Phase A example was wrong: it showed "rename `yy` to `y` (machine-applicable)" on `Point { x, yy } => x + yy`, and that edit leaves `yy` unbound in the body. A machine fix that creates a new error breaks the fix-then-recheck loop I argued for."
- **V2** settled on E0525 and E0316 both making a bad arm (web, devops, plt; then sys, aiml, min moved). **V3** settled on poison for binders under an unknown label only. **V4, V5, V6** were stated by some seats and contested by none.

#### Phase C — Final vote

Each panelist voted alone on a written ballot. The common ground of Phase B was not on the ballot.

##### Q1 — The number for `PatternMissingRest` — **A, E0319** (6-0)

Option B was E0548 (next to E0547). All six seats voted A.

- **PLT:** "`PatternMissingRest` is the third side condition of one judgment, the label-set check on a brace form (no label twice, each label declared, every field named or `..`). Its siblings in that judgment are E0315 and E0316, the literal and duplicate checks, not E0547, which judges variant names. A number next to E0315–E0318 puts the field-set faults together in the catalog [...]."
- **DevOps:** "The code most likely to be mixed up with this one is E0315 `MissingField`, and E0319 puts the two rows next to each other, so a reader of `blink explain` or the catalog sees the literal rule and the pattern rule side by side."
- **Concern (DevOps):** "the E0315 row should carry a one-line pointer to the pattern code whichever number wins."

##### Q2 — A text-only help "or rename the binder to `y`" on the punned-label E0525 — **3-3**

- **Web: A.** "Someone who typed `Point { x, yy }` meant the short form `y`. The fix `y: yy` is correct, but a JS or Python dev may not know the long form. A second help line shows the form they wanted, and shows that it needs a body edit too." Concern: "If the help says "rename the binder" but not "and its uses in the arm", a user may rename only the label and get an unknown-name error."
- **PLT: A.** "The machine fix `y: yy` is the only rename that cannot capture a free `y` in the arm body. The short form `y` is still what many users want, and it is correct when no free `y` exists. A text-only line names that option without making a tool apply a rewrite that can change the program's meaning." Concern: "An agent may read the text line as a fix to apply and rename by hand without checking for a free `y` in the body, [...]."
- **DevOps: A.** "The machine fix `y: yy` is safe but leaves the misspelled name in the code, which is web's fair objection. A second line, with no edit, shows the user the other repair and points to the LSP rename refactor, which checks for shadowing." Concern: "An agent may apply the rename by hand with a text replace and shadow an outer `y` with no error, [...]."
- **Systems: B.** "My B1 example shows that renaming the binder to `y` can shadow an outer `y` and change what the arm computes with no diagnostic. A text-only line still gets followed by hand, and by agents that do a plain text replace, without the LSP's capture check." Concern: "If A wins, the help text must at least not imply that the rename is always safe; [...]."
- **AI/ML: B.** "Each extra help line is one more choice for an agent and more tokens on every such error. This line points at the one edit that can change meaning: [...]." Concern: "some users keep `y: yy` forever and never learn that the short form exists; the §3.5 text should show the pun form so the spec teaches it."
- **Minimalism: B.** "A second help line that tells the user how to restyle a correct program is advice, not repair, and every line in a diagnostic is surface an agent reads and may act on." Concern: "agents will follow the text line by hand and rename only the label token, which makes the very unknown-name error that `y: yy` was chosen to avoid."

##### Q3 — A second structured fix `f: _` for each omitted field, not machine-applicable — **4-2 for A**

- **A (add it): Systems, PLT, DevOps, AI/ML.** Systems: "`f: _` keeps the pattern closed, so the next field added to the type breaks it again at compile time. That guarantee is the reason §3.5 requires `..` at all, and systems code depends on it." PLT: "The two repairs differ in kind: `..` makes the pattern open, `f: _` keeps it closed, so a field added later still reports." DevOps: "`f: _` is better than a bare binder `f`, because it gives no UnusedVariable warning after the fix." AI/ML: "As a structured fix with exact text, it is a choice between two complete edits, not prose to interpret: [...]." Concerns: PLT "On a struct with many fields the second fix writes a long run of `f: _` items, and a tool that does not read the applicability flag may apply it in place of `..`"; DevOps "the fix order (`..` first, marked machine-applicable) must stay fixed in the spec."
- **B (no): Web, Minimalism.** Web: "Two fix choices for one error is one more decision point in the LSP menu. For the 90% case [...] the second choice is noise." Minimalism: "A careful tool that wants the closed form can build `f: _` from the field list the diagnostic already gives." Concern (Minimalism): "agents that pick "the first fix" or "any fix" will behave differently across tools; the spec must then say which choice is preferred."

#### Phase D — One focused round (Q2 and Q3 only)

##### Q2 — **B, no such line** (6-0; web, plt and devops moved)

- **Systems** gave the case that settled it, from its B1 example: with a parameter `y` in scope, `x + y + yy` becomes `x + y + y`, "compiles, and computes a different value." And on the A wording: "When three A voters name the failure of A as its main risk, the line is the problem, not its wording."
- **Web/Scripting** moved: "A hand rename of `yy` to `y` can shadow an outer `y`, and then the arm silently computes something else. From my seat, a silent change in behavior is the worst possible outcome. It is worse than an ugly `y: yy`, and it is worse than a compile error, because the dev finds it in production. My Phase C wording ("rename `yy` to `y` here and in the arm") makes that hand edit more likely, not less." And: "§3.5 shows the pun form and the long form side by side, so the spec teaches it once, and no diagnostic invites an unchecked edit."
- **PLT** moved: "The rewrite is correct only under a side condition (no free `y` in the arm body, closures and nested blocks included). A help line that states the edit without the condition invites the unsound case; a line that states the condition is long and still asks a human or an agent to do a scope check by eye. The LSP rename already carries that check."
- **DevOps** moved: "A help line is read by agents as an edit to make, and this one leads to the only rename that can silently capture an outer `y` or leave a broken body. [...] The diagnostic should offer repairs only; teaching the pun form belongs in §3.5."
- **AI/ML** held B: "That is an argument for enumerating repairs as structured edits. It is not an argument for adding a repair as prose only."
- **Minimalism** held B: "The three A votes do not agree on what the line says."
- Concern (web, plt, devops, aiml, min): some users keep `y: yy` and never learn the short form, so §3.5 must show the pun form and the long form side by side.

##### Q3 — **A, add it** (6-0; web and minimalism moved)

- **DevOps** answered web's "one more decision point": "two quick fixes for one fault is normal in every mature toolchain; rustc's E0027 gives both "include the missing fields" and "ignore them with `..`". The menu order puts `..` first, so the 90% user takes the first entry and never reads the second." And on min's "a tool can build it": "each tool then builds the edit its own way (`f`, `f: _`, with or without a trailing comma, where to insert). The compiler holds the span and the field order; one exact edit from it is the whole point of §8.6."
- **Minimalism** moved: "devops cites 01_philosophy.md:82: "When multiple fixes are possible, the diagnostic enumerates them." I checked it; it is a standing rule, so a second structured fix follows existing policy and adds no new mechanism." And: "My C concern (which fix comes first) is answered if the spec fixes the order [...]: `..` first and machine-applicable, `f: _` second and not."
- **Web/Scripting** moved: "My Phase C concern was my own best argument against my vote: without a one-click closed form, teams press `..` and lose the review. [...] Because `f: _` is not machine-applicable and `..` stays first, the 90% user sees `..` at the top and never needs to read further. I take min's concern: the spec must say that `..` is the preferred fix, so tools that take "the first fix" all behave the same."
- **Systems, PLT, DevOps, AI/ML** held A.
- Concern (devops, plt, aiml, min): the spec must fix the order and the flags (`..` first and machine-applicable, `f: _` second and never machine-applicable).

#### AI-First Review

Learnability: the pattern checks use the names of the literal checks, and the one new name says the fix. Consistency: the order and the nearest-name rule mirror the literal field checks. Generability: the common error (`Point { x }`) has a machine fix. Debuggability: `..` and the punned label have machine fixes that add no new error. Token efficiency: one new row, no extra help lines. 5/5 pass.

### Final Spec

```blink
type Point { x: Int, y: Int }

fn sum(p: Point) -> Int {
    match p {
        Point { x, y } => x + y             // pun form
    }
}

fn sum_long(p: Point) -> Int {
    match p {
        Point { x: px, y: py } => px + py   // long form
    }
}

fn first(p: Point) -> Int {
    match p {
        Point { x } => x                    // error[PatternMissingRest]: `y` is left out
    }
}
```

Locked points:

- The checks cover a struct pattern and a variant brace pattern, bare and qualified, at every depth and in every pattern position (match arms, nested patterns, `let`, `for`, each OR-pattern alternative). The grammar gains `TYPE_NAME "." IDENT "{" field_patterns "}"`.
- Order, after the type-name checks (E0507, E0547, E0300): duplicate (E0316), then unknown (E0525), then missing rest (E0319).
- E0525 uses the nearest-name rule of the literal checks; the candidates are the declared fields the pattern does not already label; one suggestion is machine-applicable. For a punned label (`Point { x, yy }`) the machine fix writes `y: yy`; the binder and the arm body stay. No rename of uses. No "or rename the binder" line (Q2). No "or add the field to `T`" line for a pattern label.
- E0316 at the second label, with a `note:` at the first.
- `PatternMissingRest` (E0319, Q1): one per pattern, at the type or variant name; it lists each missing field and its type in declaration order. A field that is the one suggestion of an unknown label in the same pattern is not reported missing. A field default does not count as naming the field. Fixes in a fixed order: (1) add `..`, machine-applicable, the preferred fix; (2) `f: _` for each omitted field, in structured output, never machine-applicable (Q3).
- E0525 and E0316 make a bad arm (the E0547 rules: it covers nothing, an unguarded one turns off E0004, no unreachable report). `PatternMissingRest` alone does not: the compiler checks the arm as if `..` were there.
- Poison: only binders under an unknown label have the poison type. Binders under known or duplicate labels keep their field types.
- §3.5 shows the pun form and the long form side by side. The E0315 catalog row points to E0319 in one sentence.

### Concerns for implementation

- The fix order stays fixed: `..` first, the only machine-applicable fix. A tool that ignores the applicability flag may apply `f: _` (PLT).
- On a wide struct the `f: _` fix writes a long run of items (PLT, DevOps). The LSP label for it must say that it keeps the pattern closed, and the one for `..` that it ignores the rest (Web).
- The E0525 explain page can show the step from `y: yy` to the short form `y`, with its capture caveat (AI/ML).
- The convergence rule (the one suggestion for an unknown label is not missing) needs its own golden test, as for literals.

### Related

- Implementation bug (unknown field ICE; omitted fields pass check) is blocked on this decision.
- `let` with a struct pattern does not parse; the `let` position of these rules takes effect when it does.
