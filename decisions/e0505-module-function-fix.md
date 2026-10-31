[< All Decisions](../DECISIONS.md)

# The E0505 Fix for a Module Function Called Through an Effect Handle — Design Rationale

**Gap:** §4.4.7 gave the E0505 fix for `rand.shuffle(deck)` as "add `import std.random.{shuffle}` and call `shuffle(deck)`", with no exception. When the file already binds `shuffle` (a local, a file-level `fn`, another import), the fix gave code that did not compile or that called the wrong function. A selective import also binds its qualifier `random`, so a name `random` that the file binds broke the fix as well. The spec did not say which fix the diagnostic prints in these cases, or when the fix is machine-applicable.

**Result:** Q1 6-0 for 1A (the fix is the qualified call). Q2 5-1 for 2A (a local `random` at the call falls back to the selective form); Minimalism dissents for help only. Six rules (P1–P6) passed 6-0. DevOps/Tooling and PLT moved from 1B to 1A in Phase B, and Systems moved from 2B to 2A. No Phase D.

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated in independent-proposal → debate → vote rounds. The excerpts below are verbatim.

#### Phase A — Independent proposals

Four seats put the qualified call first (option 1A: Systems, Web/Scripting, AI/ML, Minimalism). PLT and DevOps/Tooling put the selective form first, with the qualified call when `shuffle` is bound (option 1B). Every seat said that a fix must not write code that fails to compile or that calls another function, and that the tool must not make up an alias.

- **Systems (1A):**
  > One rule for every `std.random` helper (`shuffle`, `choice`, later ones). The fix calls `random.<name>(args)`. Only one name matters: the qualifier `random` at the call site.

- **Systems (1A), on cost:**
  > Cost first: every option compiles to the same direct call of one mono instance of `std.random.shuffle[T]`. There is no runtime difference. The only cost is in the tool. The fix must come from a lookup the checker already does at the error site (scope chain + file import table), and its output must be correct by construction. A fix that compiles but calls a different function is worse than no fix.

- **Web/Scripting (1A):**
  > A Python dev types `rand.shuffle(deck)` because Python has `random.shuffle(x)`. The fix that is closest to what they meant is `random.shuffle(deck)`: one letter group off from what they typed. It also avoids most clashes, because `shuffle` is a common local or fn name and `random` is less common.

- **Web/Scripting (1A), on a made-up alias:**
  > **Why no auto alias:** a tool that invents `rng` or `random2` writes a name nobody chose. That is cruft in the user's file. The rare double clash is the 1% case; a human picks the name.

- **AI/ML (1A):**
  > The fix calls the function through the module qualifier. It does not add a bare name. A whole import `import std.random` binds only `random` (07 ~3270), so the conflicts with `shuffle` are gone.

- **AI/ML (1A), on the two names:**
  > - **Risk.** `rand` and `random` differ by three letters. The help line must show both names, as above, so the model sees which one is the handle and which one is the module.

- **Minimalism (1A):**
  > What if we just don't use the selective form in the fix? The spec already has a form that `shuffle` collisions cannot break: the qualified call. `import std.random` binds `random`, and `random.shuffle(deck)` does not look at the name `shuffle` in the file. Locals, `fn shuffle`, and other imports of `shuffle` stop mattering.

- **PLT (1B):**
  > §10.1: a selective import binds its qualifier too. So the fix the spec prints today (`import std.random.{shuffle}`) binds `shuffle` AND `random`. It breaks in two more cases than the ticket lists: a file-level `fn random`/`type random`/`let random` (E1012), and another import whose qualifier is `random` (E1005). Any rule must check both names.

- **PLT (1B), the check:**
  > A fix is machine-applicable only if it is **resolution-checked**: after the edit, (1) the new callee resolves at the call site to `std.random.shuffle`, and (2) the edit adds no E1005/E1012.

- **PLT (1B), on the arguments:**
  > - **Scope:** the arguments are not rewritten. If the rewritten call would not type-check (wrong arity), demote to help only, like the existing "two matching effects" rule.

- **DevOps/Tooling (1B):**
  > A tool already has the resolver. Rule for every "this is a function in module M" fix: try the forms below in order. The fix uses the first form where (1) the rewritten callee resolves to `std.random.shuffle` **at the call site** and (2) the edit adds no new diagnostic (no E1012, E1005, no shadowing). That form is machine-applicable. If no form passes, there is no fix; the help names what blocks each form.

- **DevOps/Tooling (1B), on a wrong fix:**
  > - A fix that gives E1012 or calls a local `Int` is worse than no fix: `blink fix` applies it with no human in the loop. D1 never emits one.

- **DevOps/Tooling (1B), on the help:**
  > - The `= help:` line names the blocking binding with a location, so the user (or an AI agent) knows why the short form was skipped.


Phase A found two options for the case where nothing conflicts and two for the case where a local `random` hides the qualifier. The moderator put them to the panel as Q1 and Q2:

- *Q1, option 1A:* the fix is the qualified call, ``add `import std.random` and call `random.shuffle(deck)` ``, also when `shuffle` is bound.
- *Q1, option 1B:* the fix is the selective import when nothing is bound, and the qualified call when `shuffle` is bound.
- *Q2, option 2A:* when a local `random` hides the qualifier and `shuffle` is free, fall back to `import std.random.{shuffle}` and `shuffle(deck)`, because it passes the check.
- *Q2, option 2B:* help only, no fix.

#### Phase B — Debate highlights

Round 1. The moderator posted the option space and the facts. PLT and DevOps/Tooling moved from 1B to 1A. Systems moved from 2B to 2A. All six replies ended `STABLE: ready to vote`.

- **PLT (moves 1B → 1A):**
  > **Q1: I move from 1B to 1A.** Both forms are sound under the resolution check. 1A is better because its check reads fewer names. The validity of `import std.random` + `random.shuffle(deck)` depends on one binding (`random`). The selective form binds `shuffle` AND `random`, so its check is a strict superset of 1A's. Where 1A fails, 1B also fails, with one exception (Q2). A smaller check means fewer places for the fix code to be wrong.

- **DevOps/Tooling (moves 1B → 1A):**
  > The plt fact decides it. The selective fix needs `shuffle` AND `random` free. The qualified fix needs only `random` free. So 1A passes in a strict superset of the files where 1B's first form passes. 1B gives no case a fix that 1A does not.

- **DevOps/Tooling, on its Phase A table:**
  > plt: "a selective import binds its qualifier too. So the fix the spec prints today (`import std.random.{shuffle}`) binds `shuffle` AND `random`." Right. My row "`random` bound to something else, `shuffle` free → form 4, yes" is wrong for a file-level `random`: the added import gives E1012/E1005. Only a local `random` lets it pass.

- **Systems (moves 2B → 2A):**
  > **Q2: I move from 2B to 2A.** I picked 2B to keep one branch. But the agreed rule (the callee resolves to `std.random.shuffle` at the call site, with no new E1005/E1012) already gives the checker a fixed candidate list. A second candidate costs one more scope lookup on a path that already has an error, not a new mechanism. plt is right that only a *local* `random` lets 2A pass: the new file-level import binds `random`, the local shadows it inside its own scope, and the bare `shuffle` resolves to the import. That fix is provably correct, and giving help only there drops it for no reason.

- **Systems, a condition on 2A:**
  > One condition on 2A: "no new diagnostic" must include warnings. If a local that shadows an imported qualifier gives a warning in some later lint, 2A fails the check and falls through to help only. The rule then stays correct with no special case.

- **PLT, on 2A as one rule:**
  > The rule is not two rules. It is one rule: "the first form in a fixed list that passes the check". The list is data. The selective form with a local `random` at the call passes the same check that every seat accepts as the soundness bar. To refuse a fix that is provably correct gives the user less and buys no safety. The selective form is a fallback only: file-level `random` still blocks it (it binds the qualifier), as web and aiml say.

- **PLT, the order:**
  > Order: (1) reuse an existing binding (bare `shuffle` already bound to `std.random.shuffle`, else the existing qualifier or alias); (2) `import std.random` + `random.shuffle`; (3) `import std.random.{shuffle}` + `shuffle`; (4) help only, with an alias example.

- **Web/Scripting, on 2A:**
  > **Q2: 2A, scoped as the digest states it.** The fallback to `import std.random.{shuffle}` + `shuffle(deck)` applies only when the `random` that clashes is a local at the call site. A file-level `random` blocks both forms, so the case gets help only.

- **AI/ML, on 2A:**
  > the `random` conflict that models produce most is a local, e.g. `let random = rand.int(..)` or `let random = choice(xs)`. With 2B, exactly that case gets no fix, and the agent must pick an alias with no guidance.

- **Minimalism (holds 2B):**
  > Under 1A, the only case the extra candidate saves is a *local* `random` at the call site with `shuffle` free (plt: a file-level `random` blocks both forms). That is one more candidate, one more check and one more golden, all for a rare shape. The help still tells the user what to do. YAGNI: 2B. If the majority picks 1B, then 2A follows from it at no extra cost, and I do not object.

- **Systems, on the alias name in the help:**
  > Writer note: use a placeholder (`as <name>`), not `rng`. An example name is one that agents copy as written.

- **Web/Scripting, on the alias name in the help:**
  > Use a concrete alias in the help example (`rng`), not `<name>`: people copy-paste, and a placeholder gives a parse error.

- **Minimalism, on the alias name in the help:**
  > For the alias help I prefer a concrete example name (`rng`) over `<name>`, because a placeholder in diagnostic text looks like syntax.


These facts come from the spec (07_trust_modules_metadata.md, §10.1) and were true before Phase B:

- A selective import binds its qualifier (§10.1 *Qualified Access*), so `import std.random.{shuffle}` binds `shuffle` and `random`.
- A local that hides a module qualifier is a shadow between nested scopes: it is legal and gets no warning at the binding (§10.1 *Qualified Access*).

#### Phase C — Final vote

- **Q1: The fix when nothing conflicts.** (6-0 for 1A)
  - *Option 1A:* the qualified call, ``add `import std.random` and call `random.shuffle(deck)` ``; the same text when `shuffle` is bound.
  - *Option 1B:* the selective import when nothing is bound; the qualified call when `shuffle` is bound.
  - **Systems:** 1A. — Every form compiles to the same direct call of one mono instance, so the cost is only in the fix code and its tests. 1A depends on one name (`random`). 1B depends on two (`shuffle` and its bound qualifier `random`), which means more branches, more goldens and more cases that fall to help only. One main shape is the most predictable output for `blink fix` and the LSP. *Concern:* The fix text no longer matches the selective style of the §4.4.7 example, so the writer must show both forms there, or users will think the selective import is wrong.
  - **Web/Scripting:** 1A. — The fix prints one text in nearly every file, and `random.shuffle(xs)` is what a Python developer already types. Under 1B the fix changes shape when a far-off `fn shuffle` appears, and users will ask why. The qualified call also shows at the call site where the function comes from. *Concern:* The §4.4.7 example uses the selective form, so the spec must show both forms near each other, or readers will think the fix's style is the only valid one.
  - **PLT:** 1A. — Both forms are sound under P1, but the qualified form's check depends on one binding (`random`) and the selective form's check depends on two (`shuffle` and `random`). A smaller check gives less room for the fix code to be wrong. 1A also composes: fixes from one pass for `shuffle` and `choice` add the same `import std.random` line, so applying them together is idempotent and the tool needs no merge logic. *Concern:* the fix text no longer matches the §4.4.7 example, which uses the selective style; the writer must show both forms there, or readers will think the selective form is wrong.
  - **DevOps/Tooling:** 1A. — The qualified fix needs only `random` to be free, and the selective fix needs both `shuffle` and `random`, so 1A passes in every file where 1B passes. One fix text in almost every file gives one golden per case and an LSP code action that keeps its shape when the file changes. The fix never edits an existing import list, so the tool does not need to keep comments, commas and `blink fmt` order in a list edit. *Concern:* The fix text differs from the §4.4.7 example (`import std.random.{shuffle, choice}`), and users can think one style is wrong; the writer must show that both are valid.
  - **AI/ML:** 1A. — One fix shape for one mistake in almost every file, so an agent that learns from fix output learns one pattern. The fix checks one name (`random`), not two. `random.shuffle` is the Python spelling that models already use, so code after the fix matches what models expect. *Concern:* Models may confuse `rand` (handle) and `random` (module), because the names differ by three letters. The help line must name both.
  - **Minimalism:** 1A. — A selective import binds its qualifier too, so every name that blocks the qualified form also blocks the selective form. 1B never gives a fix where 1A gives none; it only adds a second fix shape, a ranked ladder and more goldens. With one shape, the fix is easier to predict: an E0505 module-function fix always reads `random.<name>(...)`. *Concern:* The fix text will not match the selective style of the §4.4.7 example, and users may read that as the house style changing. The writer must show both forms there.

- **Q2: A local `random` hides the qualifier at the call, and `shuffle` is free.** (5-1 for 2A; Minimalism for 2B)
  - *Option 2A:* fall back to ``add `import std.random.{shuffle}` and call `shuffle(deck)` ``, because it passes the check.
  - *Option 2B:* help only, no fix.
  - **Systems:** 2A. — Under P1 the checker already tries a fixed candidate list, so this fallback costs one more scope lookup on a path that already has an error, not a new mechanism. The fix is provably correct: the local `random` shadows the new file-level qualifier only in its own scope, and bare `shuffle` resolves to the import. Help only would drop a correct fix for no gain. *Concern:* If a later lint warns on a local that shadows an imported qualifier, 2A must fall through to help only. This works only if P1's "no new diagnostic" really includes warnings, and a test pins it.
  - **Web/Scripting:** 2A. — A fix that is provably correct exists in this case, and help with no text to type is the worst result for the common user. The fallback is one more candidate in the same checked list, not new logic. *Concern:* If a local that shadows a file-level import qualifier gives a shadowing warning, then under P1 (warnings count) 2A never passes in this case. The writer must check that, so the rule does not promise a fix that the check always rejects.
  - **PLT:** 2A. — The selective form with a local `random` at the call passes the same check (P1) that every seat accepts as the soundness bar, so refusing it buys no safety and gives the user less. "First form in a fixed list that passes the check" is one rule; the list is data, not a second rule. *Concern:* if 2B wins, the spec must still say why a provably correct fix is withheld, or a later reader will "fix" the gap and make the rule inconsistent.
  - **DevOps/Tooling:** 2A. — The selective form passes the agreed check (P1) here, so the tool can prove the fix is correct; with 2B the user gets no code action in a case where a correct one exists. It is one more candidate in the same ranked list and costs one resolver query. The order stays fixed, so the output is deterministic for tests. *Concern:* If 2B wins, the help line must name the local `random` and its location, or the user does not know why the fix was skipped.
  - **AI/ML:** 2A. — The local `random` is the conflict that models produce most (`let random = rand.int(..)`). 2B leaves exactly that case with no fix, and an agent must pick an alias with no guidance. 2A uses the same P1 check, so it cannot apply a wrong edit. *Concern:* With 2A, one mistake has two fix shapes. The spec and the tests must show the fallback, or the second shape will look like a bug.
  - **Minimalism:** 2B. — Under 1A this case is a local named `random` plus a call to `rand.shuffle` with `shuffle` free, which is rare. A second candidate form costs one more check and one more golden for each module-function fix, and the help already tells the user what to do. YAGNI. *Concern:* If 2A wins, the "one fix shape" property breaks for this one case, and implementers may grow the fallback into a full ladder. Keep 2A to exactly this one fallback.

- **P1–P6: the rules.** (6-0 on each: all six seats Agreed)
  - *P1, the check:* a fix is machine-applicable only if, after the edit, the callee resolves at the call site to `std.random.shuffle`, and the edit adds no new diagnostic: no E1005, no E1012, and no new warning.
  - *P2, reuse:* if bare `shuffle` already resolves to `std.random.shuffle`, the fix is `shuffle(deck)` with no import edit; if the file already imports `std.random` (whole, with a list, or `as r`), there is no import edit and the call goes through the existing qualifier or alias.
  - *P3, no made-up alias:* when no form passes, there is no fix line; the help shows the alias form.
  - *P4, one rule:* the same rule for `choice`, every later `std.random` name, and every "`X` is a function in module `M`" help.
  - *P5, type check:* if the rewritten call would not type-check (wrong arity), the fix is help only.
  - *P6, location:* the help names the blocking binding and its location.

#### Phase D

Not triggered. Q1 passed 6-0, and Q2 passed 5-1 with one stated dissent.

### Minimalism's Dissent on Q2

Minimalism voted 2B. Its reasoning and Concern, verbatim:

  > Under 1A this case is a local named `random` plus a call to `rand.shuffle` with `shuffle` free, which is rare. A second candidate form costs one more check and one more golden for each module-function fix, and the help already tells the user what to do. YAGNI.
  >
  > *Concern:* If 2A wins, the "one fix shape" property breaks for this one case, and implementers may grow the fallback into a full ladder. Keep 2A to exactly this one fallback.

The panel kept 2A. The rule is written as a fixed list of four candidates, with the selective import as the one fallback after the qualified call. It is not an open ladder, which is Minimalism's Concern.

### Facts From Other Languages

The panelists named these. The moderator did not check them.

- rustc marks its "consider importing" suggestions `MaybeIncorrect` unless the path resolves cleanly, and suggests the full path when a `use` would clash (AI/ML, PLT, Systems).
- Go's `goimports` adds the package and calls through the package name; it never renames (DevOps/Tooling, Minimalism).
- TypeScript's auto-import offers a qualified or namespace form on a name clash (DevOps/Tooling, Web/Scripting).
- Python code says `random.shuffle(xs)`; Go code says `rand.Shuffle`, which is a reason that models write `rand.shuffle` (AI/ML).

### Concerns Carried Into the Spec

- **Style (all of Systems, Web/Scripting, PLT, DevOps/Tooling, Minimalism):** the fix prints the qualified call, but §4.4.7 shows `import std.random.{shuffle, choice}`. A reader may think one style is wrong. The spec says that both forms are valid and why the fix prints the qualified one.
- **`rand` and `random` (AI/ML):** the help names both spellings.
- **Two shapes (AI/ML) and the extra candidate (Minimalism):** the spec shows the fallback as an example and states the candidate list as fixed, so the fallback does not grow into a ladder.
- **A later warning (Systems, Web/Scripting):** if a later lint warns on a local that hides an imported qualifier, P1 ("no new warning") makes candidate 3 fall through to help only. The rule needs no change. Today §10.1 *Qualified Access* says such a local gets no warning.
- **Why 2A exists (PLT, DevOps/Tooling):** the spec states that candidate 3 passes only where a local `random` hides the qualifier, so a reader does not "fix" the gap.
- **Help with no fix (DevOps/Tooling):** the help names the blocking binding and its position.

### Final Spec

```blink
fn deal(deck: List[Card]) -> List[Card] ! Rand {
    rand.shuffle(deck)
}
// = fix: add `import std.random` and call `random.shuffle(deck)`

fn deal2(deck: List[Card]) -> List[Card] ! Rand {
    let random = 7
    rand.shuffle(deck)
}
// = fix: add `import std.random.{shuffle}` and call `shuffle(deck)`
```

- The fix is the first of four candidates, in a fixed order, that meets P1: (1) reuse a binding the file has; (2) `import std.random` and `random.shuffle(deck)`; (3) `import std.random.{shuffle}` and `shuffle(deck)`; (4) none.
- A file-level `random` (a function, a `let`, a type, or the qualifier of another import) makes candidates 2 and 3 fail. The result is help only, with an alias import as the example.
- The tool makes up no alias. The example name in the help is a concrete name that is not bound in the file, `rng` when it is free.
- The rule is not special to `shuffle`. It holds for `choice`, for later `std.random` names, and for every E0505 whose help says that a name is a function in a module.
- Spec: §4.4.7 *Helpers in `std.random`* (04_effects.md). Catalog: the `UnresolvedMethod` (E0505) row.
