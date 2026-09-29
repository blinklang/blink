[< All Decisions](../DECISIONS.md)

# `Bool` Distinct from `Int` — Design Rationale

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated
in independent-proposal → debate → vote rounds. The gap (br `td3yx5`): `types_compatible` in
`src/typecheck.bl` carried an Int/Bool carve-out ("Int and Bool are interchangeable in Blink
(C-style truthiness)"), plus a comparison carve-out and `is_bool_compat` accepting Int in
conditions. All three contradict the 5-0 "No truthiness" vote in §2.

**Twelve facts were verified by the moderator and surfaced to the panel:**
- **F1** (correction to Phase A facts): in the current codegen a Bool lowers to C `int` (`src/layout.bl:836`), and to `intptr_t` in one word-slot context (`src/layout.bl:649`) — not `int64_t` as the Phase A facts said.
- **F2** struct-literal field values are still NOT type-checked (br x231pe, P0, open, blocked). Measured with gen1 today: `type P { flag: Bool }` then `P { flag: 2 }` and `P { flag: "x" }` both pass `blink check`.
- **F3** `sections/07_trust_modules_metadata.md:711` lists `Bool` among the allowed `@ffi.struct` field types; no spec text states which C type `Bool` maps to.
- **F4** the enum match-scrutinee enforcement ticket (qsb7ca) is still open and blocked.
- **F5** sys and plt each reported, measured with gen1: `let b: Bool = 2` then an exhaustive `match b { true => ... false => ... }` takes neither arm and reads an uninitialized value (sys_A.md shows the emitted C); `Set[Bool]` with `true` and `b` has len 1.
- **F6** V1 (only the `types_compatible` arm deleted): 26 sites, all "return value type Bool does not match return type Int" on `-> Int` predicates returning a comparison. src 18, lib/std 8 (json, semver, toml), lib/pkg 0, tests 0 own sites (109 test checks fail transitively via lib/std).
- **F7** V2 (also comparison carve-out deleted, `is_bool_compat` Bool-only):

  | Location | Bool vs Int ==/!= | Int in if/while/&&/\|\| | Assignability | Total |
  |---|---|---|---|---|
  | src | 94 | 311 | 18 | 423 |
  | lib/std | 0 | 19 | 8 | 27 |
  | lib/pkg | 1 | 0 | 0 | 1 |
  | tests | 73 | 0 | 0 | 73 |
  | total | 168 | 330 | 26 | 524 |

- **F8** src/parser.bl holds 285 of the condition sites, mostly `if at(..)`; `at(kind) -> Int` (parser.bl:703) is `peek_kind() == kind`, so its one signature change removes about 270. About 25 `-> Int` predicates (`at`, `is_digit`, `file_exists`, `is_keyword`, ...) account for most condition sites.
- **F9** tests: 14 files have own-text errors (all Bool-vs-Int ==/!=, 73 sites; tests/test_term.bl has 39).
- **F10** with both arms deleted, `match b { 0 => .. }` on a Bool, `match n { true => .. }` on an Int, and `!n` on an Int still compile. Neither `types_compatible` nor `is_bool_compat` covers match patterns or `!`; they need their own checks.
- **F11** sites the measurer found without an obvious mechanical rewrite (from samples, not all 524): src/compiler.bl:596 `let local_exists = if is_std_ns { 0 } else if bl_exists { 1 } else { .. }` (Int-encoded flag with mixed branches); `assert(tty == 0 || tty == 1)` in tests/test_cross_module_private.bl:6 (an Int from an external call). All other sampled sites rewrote mechanically (`x.contains_key(k) != 0` -> `x.contains_key(k)`, `-> Int` -> `-> Bool`, `if f(..)` -> `if f(..) != 0`).
- **F12** in both variants, gen1's own stdlib archive build fails (V1: 8 errors, V2: 27, all lib/std), so the lib/std sites must be migrated before the arms are deleted.

The F6–F12 counts are unique file:line sites not in baseline, measured with gen1 builds of two variants in a separate worktree, by `blink check` over src/compiler.bl, src/cli.bl, lib/std (44), lib/pkg (6), tests (1575; test_cg_/layout_/typecheck_ skipped). They are LOWER BOUNDS (cascades hide sites).

#### Phase A — Independent proposals

- **Systems:** "**S1: Delete the assignability carve-out, as enum decision A did (main proposal)** — Delete the Int/Bool arm in `types_compatible` (~line 15605). Bool then falls to the `ka == kb` check, the same branch that sized ints and enums use. … Hard flip with no warning phase, and fix the compiler, stdlib and test sites in the same PR. … **Codegen cost: zero.** This is a frontend-only rule. No representation or runtime check changes." Recommended: "Adopt S1+S2+S3 together: delete both carve-outs and require exactly `Bool` in conditions. It is one flat rule that deletes code and adds none: "Bool is a nominal type with two values; there is no mixing with Int anywhere, including `==`.""

  ```blink
  fn takes_bool(b: Bool) -> Int { if b { 1 } else { 0 } }

  fn main() {
      takes_bool(7)            // error: expected Bool, got Int
      let n: Int = true        // error: expected Int, got Bool
      let xs: List[Bool] = [1, 0]   // error
  }
  ```

- **Web/Scripting:** "A Bool is `true` or `false`, and never a number." Most JS, Python and TS developers already expect this, and §2.19 already says it. … "**Proposal W1 (preferred): Bool is fully distinct from Int, for assignment and for comparison** 1. Delete the Int/Bool arm in `types_compatible`. Bool falls to `ka == kb`, the same path as sized ints and enums after dhggkg. … 2. Also delete the `==`/`!=` carve-out. `b == 1`, `flag == 0` and `set.contains(x) != 0` become compile errors. **Here I intentionally depart from the enum precedent**, for the reasons below. … 4. Add no conversion methods. There is no `Bool.to_int()` and no `Bool.from_int()`." One-sentence rule: "`Bool` is not a number: it never converts to or compares with `Int`. Write `n != 0` or `if b { 1 } else { 0 }`."

  ```blink
  fn main() {
      let flags = [true, false, true]
      let n = 3
      if n != 0 { io.println("nonzero") }                      // Int -> Bool: say what you mean
      let bit = if flags[0] { 1 } else { 0 }                   // Bool -> Int, already in §3
      if !is_ready(s) { io.println("waiting") }                // was: is_ready(s) == 0
  }
  ```

- **PLT:** "> **Adequacy.** Type-directed compilation (match lowering, display dispatch, `==`, exhaustiveness) is sound only if every runtime value is in its static type's set of values. Bool's set is {0, 1}. The carve-out lets its runtime values be all of ℤ." "**P1 (recommended): Bool is fully nominal. Delete both carve-outs, `==` included** … `true` and `false` are the only closed terms of type `Bool`. An integer literal is never `Bool`."

  ```blink
  fn main() {
      let n: Int = true        // error[TypeError]: declared type Int but got Bool
      let b: Bool = 2          // error[TypeError]: declared type Bool but got Int
      takes_bool(7)            // error[TypeError]: argument 1 expects Bool, got Int
      if 0 { }                 // error[TypeError]: if condition must be Bool, got Int
      let flag = true
      if flag == 0 { }         // error[TypeError]: cannot compare Bool with Int
      …
  }
  ```

- **DevOps:** "**Proposal DT-1: delete all three carve-outs, and make every rejection carry a fix that a tool can apply** … `Bool` and `Int` are distinct types in every position: `let`, argument, return, assignment, list element, `if`/`while` condition, and `==`/`!=`. There are three edits in `src/typecheck.bl`: 1. Delete the Int/Bool arm in `types_compatible` (line 15605). 2. Make `is_bool_compat` accept only `Bool` (plus the no-info fail-open). … 3. Delete the Int/Bool arm in the comparison-operand check (line 16023). `Bool == Bool` and `Int == Int` stay legal. `b == 1` does not." Reuse E0300 TypeError; "The new part is the `note: Blink has no truthiness` line, whose text stays fixed, so `blink explain` and LLMs learn it as one phrase."

  ```
  error[TypeError]: if condition must be Bool, got Int
    --> a.bl:3:8
    |
  3 |     if n { io.println("x") }
    |        ^ Int
    note: Blink has no truthiness; an Int is never a condition
    help: compare explicitly: `n != 0`            [machine-applicable]
  ```

- **AI/ML:** "**Proposal AI-1 (preferred): Bool and Int are fully distinct, with no comparison carve-out** 1. Delete the Int/Bool arm in `types_compatible`. Bool is compatible only with Bool at let, arg, return, assignment, field, collection element and generic argument sites. 2. Delete the Int/Bool carve-out in the `==`/`!=` operand check. `b == 1` and `contains(x) != 0` become errors. 3. `if`/`while`/`&&`/`||`/`!` accept only Bool. This includes integer literals: `if 1` is an error, and there is no special case for the literals `0` and `1`. 4. Add no new conversion method. … 5. Every rejection names both types and gives the exact rewrite (see Diagnostics). An LLM repairing its own code reads the diagnostic, not the spec."

  ```blink
  let seen = Set.new()
  seen.insert(3)
  if seen.contains(3) != 0 { }        // error: cannot compare Bool with Int
  if seen.contains(3) { }             // ok
  ```

- **Minimalism:** "**Proposal M1 (preferred): delete both carve-outs, add nothing** - `Bool` and `Int` become nominally distinct everywhere: let, arg, return, field, list element, **and** `==`/`!=` operands. - No conversion method, no new syntax. The crossing idioms already exist and one is already spec-prescribed in §3: - Int → Bool: `n != 0` (a comparison — it says what it means) - Bool → Int: `if b { 1 } else { 0 }` (§3's own text) … Net language surface change: −2 rules, +0 features."

  ```blink
  fn main() {
      takes_bool(7)              // error[E0300]: expected Bool, got Int
      let b: Bool = 2            // error[E0300]: expected Bool, got Int
      let n: Int = true          // error[E0300]: expected Int, got Bool
      if 0 { }                   // error: if condition must be Bool, got Int
      let done = false
      if done == 0 { }           // error: cannot compare Bool with Int
      …
  }
  ```

#### Phase B — Debate highlights

One round ran. All six panelists ended `STABLE: yes`.

- **Systems:**
  - *"**Q4: I withdraw `Bool.to_int()`.** Four panelists are against it, and my own Phase A text admitted that it only names the conversion. `if b { 1 } else { 0 }` compiles to `setcc`/`movzx` at -O2, which is the same code `to_int` would give. It adds nothing at run time, and it makes §3 ("a `Bool` never reads as 0 or 1") need an exception."*
  - *"**Q3: I drop my `==` fallback.** I no longer make the choice depend on the site count. Every rewrite (`x != 0` → `x`, `x == 0` → `!x`) is already legal under the pinned gen0, and devops' fixer makes the count cost almost nothing. A large count therefore cannot justify a permanent spec exception. I vote Q3-reject with no condition."*
  - *"aiml is correct for C functions that return an `int` flag. The C type there is `int`, so the Blink signature is `I32` and the caller writes `!= 0`. That is honest, and it needs no new mechanism. I accept it."*
  - Q7 layout finding: *"- `src/layout.bl:836` spells `Bool` as C `int` (4 bytes). - `src/cg_decl.bl:355-366`: an `@ffi.struct` mirror emits its own typedef from the Blink field types, and then `_Static_assert`s its layout against the header's struct. So a `Bool` field that mirrors a C `bool` field (1 byte) has the wrong size and offset. The asserts will refuse to compile it, which is safe but means the feature cannot be used. A `Bool` field only compiles against a C `int` field, and C can write any value there. In practice, the only `Bool` mirror that works today is the one that can hold 2."*
- **Web:**
  - *"I now **withdraw W2** (staged comparison). Staging a rule we can apply with a fixer in one PR just adds a ticket and a period where the spec and compiler disagree, which is the exact state this gap is about."*
  - *"This is not a hill. `to_int` is total and additive, so if the panel splits I would accept it (never `from_int`), as a separate additive vote. It must not block Q1-Q3."*
  - *"Support plt: enforce **now**."* on Q6, and on Q7: *"Defer to sys on the C type; I support the shape sys, plt, min and devops agree on: **normalize inbound Bool to 0/1 at the FFI boundary**"*
- **PLT:**
  - *"**Q3 fallback:** I withdraw P2 (keep Bool==Int for enum parity). web's W2 (staged enforcement, spec says "error" now) is my only fallback."*
  - *"**Q4 `Bool.to_int()`:** I move from "add" to **"do not add now"**. I accept devops' help line for `b.to_int()`."*
  - Q6 probe, measured with gen1: *"Both of these compile and run:"*

    ```blink
    fn main() {
        let b = true
        let r = match b {
            1 => "one"          // int literal pattern against a Bool scrutinee: accepted
            _ => "other"
        }
        let n = 1
        let s = match n {
            true => "t"         // Bool pattern against an Int scrutinee: accepted
            _ => "o"
        }
        io.println("{r} {s}")   // prints: one t
    }
    ```

  - *"I ask the panel to vote this explicitly. It is part of Q1, not a staged follow-up."* And: *"My Phase A option "reject Bool in `@ffi` signatures" is withdrawn."*
- **DevOps:**
  - *"I withdraw "build the fixer first" as a condition. I have not confirmed that `blink check --json` applies fixes today, and blocking a type-rule fix on building fixer machinery is scope creep."* (heading: *"Migration order: I adopt the AI/ML and PLT order, and drop "fixer first" as a gate"*)
  - *"I move from "defer to sys" to a firm position. Normalising on read is required, not optional."*
  - *"Q6: enforce now (joins PLT)."*
- **AI/ML:**
  - *"My Phase A text ("C `int` flags stay `Int`, no new mechanism") missed F3: `Bool` is already allowed in `@ffi.struct` fields and `@ffi` signatures. So the spec must say what it means."* (heading: *"Q7: FFI. Position change: I adopt sys S5"*)
  - *"sys and plt make a real point for LLMs: after `Enum.to_int()` and the sized-int `.to_int()` table, a model will guess `b.to_int()`."* … *"My vote is **no `to_int` + the fix-it**."* (heading: *"Q4: `Bool.to_int()`. Position softened: I lean no, but I will not block"*)
- **Minimalism:**
  - *"**I withdraw M2 (keep Int==Bool as a fallback).** F5 (sys and plt, measured) changes the question. … So no site count makes a permanent second `==` exception cheaper than a one-time edit. I vote Q3-reject whatever number comes back."*
  - *"**Q4 `Bool.to_int()` — I still say no, and I will not block**"*, and on Q7: *"**Invariant (in scope, adopt now):** every Bool-typed value is 0 or 1. … **ABI mapping (out of scope, give it its own spec ticket)**"*

#### Phase C — Final vote

- **Q1: Assignability — Delete the `types_compatible` Int/Bool arm in both directions (let / arg / return / assign / field / element).** (6-0)
  - **Systems:** A — The match lowering emits two compares and no default arm because exhaustiveness says `{true, false}` covers every value. That proof holds only if the frontend keeps every Bool at 0 or 1, and this arm is the main way a 2 gets in (F5). Deleting it costs nothing at run time: no representation change, no added check. *Concern:* F6 shows 26 sites break on this arm alone, and F12 shows the stdlib archive build fails on them, so if lib/std is not migrated first, the flip breaks every downstream build at once.
  - **Web:** A — "A Bool is true or false, never a number" is the rule a JS/Python/TS dev can learn in one line, and it is what §2.19 already says. F6 shows the cost is 26 sites, all one shape (`-> Int` predicate returning a comparison), which is a signature fix. Keeping the arm keeps `let b: Bool = 2`, which is a bug, not a feature. *Concern:* F2 (`P { flag: 2 }`) stays open until x231pe lands, so for a while the docs say "never a number" while one path still lets a number in.
  - **PLT:** A — Adequacy of type-directed compilation needs every runtime value to be in its static type's value set, and Bool's set is {0, 1}. The arm puts all of ℤ into Bool, and F5 shows the result: an exhaustive match that takes no arm and reads an uninitialised value. No rule that keeps the arm is sound. *Concern:* F10 shows `types_compatible` is not the only place the carve-out lives, so deleting this one arm can look complete while copies remain in other checkers.
  - **DevOps:** A — Every rejected shape has an exact rewrite (`n != 0`, `if b { 1 } else { 0 }`, `true`/`false` for literals), so each error can carry a machine-applicable fix. F6 shows the V1 face is 26 sites, all one message ("return value type Bool does not match return type Int"). One message with one fix is the easiest error surface to teach. *Concern:* The fix for a Bool returned from an `-> Int` fn is a wrap, while the right fix is often to retype the fn; users (and LLMs) will take the wrap if the `help:` does not also say "consider `-> Bool`".
  - **AI/ML:** A — The rule becomes one flat line that a model can learn from the spec alone: a type is compatible only with itself, as for sized ints and enums. F6 shows the whole cost is 26 `-> Int` predicates that return a comparison, and each is fixed by retyping the signature. Retyping also removes the wrong idiom from the source that future models train on. *Concern:* The migration may wrap call sites (`if f(x) != 0`) instead of retyping the `-> Int` predicates, so the corpus keeps teaching Int flags.
  - **Minimalism:** A — The arm is implementation surface that the spec never granted; §2 and §3 already forbid it. Deleting it removes a rule and adds none. F6 shows only 26 sites, all `-> Int` predicates that return a comparison, which is debt that the retype pays off. *Concern:* F12: the lib/std sites must be migrated before the arm goes, or the stdlib archive build breaks mid-PR.

- **Q2: Conditions — `if` / `while` / `&&` / `||` / `!` / match guards accept exactly `Bool`; `is_bool_compat` rejects Int, literals included (`while 1 { }` becomes an error).** (6-0)
  - **Systems:** A — `if n` on an Int and `if n != 0` compile to the same `test`/`jcc`, so exact `Bool` costs nothing in the output. It removes the last place where the frontend lets C truthiness through, and §2 already says so. *Concern:* F8 shows 285 parser sites hang on `at() -> Int`; if the migration wraps them in `!= 0` instead of retyping `at` to `-> Bool`, the compiler source keeps the Int-flag style we are removing.
  - **Web:** A — TypeScript and Kotlin users already know "the condition must be a boolean"; only C and Python/JS users expect truthiness, and those are exactly the users the note `Blink has no truthiness` is for. F8 shows the 311 src sites mostly go away with one signature change (`at() -> Bool`), so the count looks bigger than the work. *Concern:* `while 1 { }` is a common habit from C and shell; if the help line does not say `while true { }` plainly, it becomes a frequent beginner question.
  - **PLT:** A — The typing rule is `Γ ⊢ e : Bool` for every condition position, with no Int premise. F10 shows `!n` on an Int still compiles with both arms deleted, so `!` needs its own check. It is part of this rule, not a follow-up. *Concern:* The 311 src condition sites (F7) invite a wrapper like `truthy(n)` in place of the retype of `-> Int` predicates to `-> Bool` that F8 shows removes most of them.
  - **DevOps:** A — `if n` has one fix, `n != 0`, and it needs no knowledge of the program. F8 shows 285 of 330 condition sites come from about 25 `-> Int` predicates, so the error list is the worklist: fix the signatures and most sites go away. `while 1 { }` as an error is fine; `loop` and `while true` exist. *Concern:* 330 errors from a few predicate signatures will read as a wall of noise; the diagnostic for a condition whose operand is a call to an `-> Int` fn should point at the callee's signature, or users fix 270 call sites instead of one line.
  - **AI/ML:** A — Truthiness is the bug that models most often carry into a new language from C, Python and JS. Only a hard error with a rewrite in the help line stops that habit in a self-repair loop. No literal special case: legality must not depend on a literal's value, since that is one more decision point. *Concern:* F8 shows 311 condition sites in src; if the migration wraps them with `!= 0` rather than retyping about 25 predicates (`at`, `is_digit`, ...), the compiler source will be full of noise that models copy.
  - **Minimalism:** A — A condition that takes Int is truthiness, which the 5-0 §2 vote rejected. F8 shows the count is small in cause: about 25 `-> Int` predicates produce most of the 330 sites, and retyping `at()` alone removes about 270. One signature change is cheaper than a permanent exception. *Concern:* F10: `!n` on an Int is not covered by `is_bool_compat`, so the PR can look finished while `!` still accepts Int unless it gets its own check and test.

- **Q3: `==` / `!=` between Bool and Int — Reject, enforced in the same change.** (6-0)
  - **Systems:** A — Once Q1 holds, `b == 1` is `b`, `b == 0` is `!b`, and `b == 2` is a dead branch the compiler should refuse. All forms emit the same code. Staging (B) or keeping (C) leaves a rule in place whose only new effect is to accept an always-false compare, and it contradicts §3. *Concern:* F7's 168 comparison sites include some where the Bool side is an Int in disguise (F11's `tty == 0 || tty == 1`); a blind sed that rewrites `x != 0` to `x` there changes meaning, so each rewrite must follow the operand's real type from the error list.
  - **Web:** A — `b == 1` is truthiness through a side door, and `true == 1` is the JS/Python surprise we should not copy; TS already rejects it (TS2367). F7 gives 168 comparison sites, and F11 shows nearly all rewrite mechanically (`contains(k) != 0` → `contains(k)`). A staged rule (my withdrawn W2) only adds a period where spec and compiler disagree. *Concern:* tests/test_term.bl alone has 39 sites, so a rushed migration could rewrite a test's meaning, not only its spelling; each test rewrite needs a reviewer to check it still proves the same thing.
  - **PLT:** A — `==` is `Eq.eq(self, other: Self)`; a mixed-type comparison is a second rule outside the trait system, and it contradicts §3's "a Bool never reads as 0 or 1". F7 counts 168 sites, all mechanical (`x != 0` → `x`, `flag == 0` → `!flag`), so the cost is paid once, and a spec exception would last forever. With reject, `b == 2` is a plain type error and needs no range analysis. *Concern:* tests/test_term.bl alone has 39 sites (F9); a rushed migration could rewrite a test's intent along with its spelling.
  - **DevOps:** A — The 168 sites in F7 are all in two shapes that rewrite by operand shape alone (`x != 0` / `x == 1` → `x`, `x == 0` / `x != 1` → `!x`). A count of mechanical rewrites is not a cost that justifies a spec exception. With the arm gone, `b == 2` gets a plain "cannot compare Bool with Int" error, and needs no always-false analysis. *Concern:* tests/test_term.bl alone has 39 sites (F9); if they are rewritten by a careless sed rather than by operand shape, an `== 0` can turn into `x` instead of `!x` and flip a test's meaning without any error.
  - **AI/ML:** A — Int == Int and Bool == Bool stay legal, so the only code Q3-B/C would keep is `bool_expr != 0`, which is C truthiness itself. F7's 168 sites all have a local rewrite (`x != 0` → `x`, `x == 0` → `!x`); the count means edits, not a design problem. Staging leaves a period where spec and compiler disagree, which is exactly the state that makes a language hard to learn. *Concern:* The 73 test sites (39 in tests/test_term.bl) may get rewritten in bulk without a check that each one still tests what its name says.
  - **Minimalism:** A — One flat rule ("Bool is not a number") beats a two-face rule. Keeping the comparison would write a clause into the spec that contradicts §3, and staging it adds a ticket and a period where spec and compiler disagree, for 168 sites that each have a local rewrite (`x != 0` → `x`, `x == 0` → `!x`). A migration cost is paid once; a spec exception is paid forever. *Concern:* tests/test_term.bl alone holds 39 of the 73 test sites, so a careless bulk rewrite there could change what those tests prove; review each hunk.

- **Q4: `Bool.to_int() -> Int` — Do not add. `if b { 1 } else { 0 }` stays the only spelling; "no method `to_int` on Bool" carries a machine-applicable help to that rewrite.** (6-0)
  - **Systems:** A — I withdrew it in B1. `if b { 1 } else { 0 }` gives `setcc`/`movzx` at -O2, the same code a method would give, so the method adds surface and no speed. The help line on "no method `to_int`" handles LLM guesses. *Concern:* Counting code will drift to `filter(..).len()`, which allocates; the docs must show the branch or a loop sum as the way to count.
  - **Web:** A — One spelling is easier to teach than two, and §3 stays true without a footnote. The help line on "no method `to_int` on Bool" meets users and LLMs where they guess. I accept sys's point: the docs should show the §3 conditional (or a loop adding `if f { 1 } else { 0 }`) for counting, not `filter(...).len()`, which allocates. *Concern:* LLMs trained on `Enum.to_int()` and sized ints will keep typing `b.to_int()`, so the help line must be machine-applicable from day one or this becomes a steady source of friction reports.
  - **PLT:** A — My Phase A case for a named injection was aesthetic, not about soundness; `if b { 1 } else { 0 }` is total and correct. Adding the method later is purely additive, and removing it later would break code. The machine-applicable help on `b.to_int()` catches the guess LLMs will make by analogy with enums. *Concern:* If codecs and FFI glue start to need the conversion often, the branch spelling becomes noise and the question comes back without a record of this reasoning.
  - **DevOps:** A — The repair already exists, so §3 rule 1 holds without new surface. The "no method `to_int` on Bool" error must carry `help: use \`if b { 1 } else { 0 }\`` as a machine-applicable fix; that one arm also catches `.to_bool()` and `.from_int()` guesses. It is additive, so it can land later if real code asks for it. *Concern:* If the help arm is not built with the flip, LLMs guess `b.to_int()` and get a bare "no method" error with no repair, which breaks rule 1 in practice.
  - **AI/ML:** A — One spelling for one operation is fewer decision points and fewer choices for a model to get "wrong" by style. Models will guess `b.to_int()` by analogy with enums, but a machine-applicable help on "no method `to_int` on Bool" repairs that guess in one step. The method is additive, so it can come later if real code needs it. *Concern:* If the help line for the missing method is not built in the same PR, models will hit a bare "no method" error with no hint and will guess other spellings (`as Int`, `Int(b)`).
  - **Minimalism:** A — §3 already names the one spelling, `if b { 1 } else { 0 }`; a method gives two spellings for one operation and invites `from_int` "for symmetry". The help line on "no method `to_int` on Bool" catches the LLM guess at the moment it matters. The method is purely additive, so if post-migration counts show a real counting pattern, add it then; removing it later would break users. *Concern:* If the help line does not ship with the flip, every model that guesses `b.to_int()` hits a bare "no method" error with no rewrite, and pressure to add the method will grow for the wrong reason.

- **Q5: `Bool.from_int` / `Int.to_bool` — Do not add.** (6-0)
  - **Systems:** A — Int to Bool loses information, and the rule for which nonzero means true belongs at the call site as `n != 0`. Zig, Rust and Go give no such conversion. *Concern:* None from the systems side.
  - **Web:** A — `from_int` makes the library pick which Ints are true, which is truthiness as a method. `n != 0` is shorter and says what it means. *Concern:* Users coming from Python may look for `bool(n)` and find nothing; the "expected Bool, got Int" help must name `n != 0`.
  - **PLT:** A — Int→Bool is not one map but a choice of predicate (`!= 0`, `> 0`, `== 1`); a method hides which one. `n != 0` states it and is already total. *Concern:* None of substance; users who reach for `to_bool` need the help line to show `n != 0`.
  - **DevOps:** A — `n != 0` says which Ints count as true; a method name hides that choice. The same help arm as Q4 covers the guess. *Concern:* None beyond Q4's: the help arm must name `n != 0` for `Int.to_bool()` / `Bool.from_int(n)`.
  - **AI/ML:** A — `n != 0` states the question the code asks, and a `from_int` would force a choice between nonzero-is-true and `Option`, a new decision point with no gain. *Concern:* The help text for `Int.to_bool()` guesses must give `n != 0`, or models will invent a helper function in each program.
  - **Minimalism:** A — `Int.to_bool()` puts the truthiness question back as API (is `2.to_bool()` true?); `n != 0` states intent with no rule to learn. Unanimous, nothing to add. *Concern:* None specific; the risk is only that Q4 later reopens this by symmetry.

- **Q6: Match patterns — Enforce now: an int-literal pattern against a Bool scrutinee and a `true`/`false` pattern against an Int scrutinee are type errors, with help lines; an exhaustive Bool match stays exhaustive without `_` (no codegen default arm as the fix).** (6-0)
  - **Systems:** A — This is the face where the UB lives: the lowering trusts exhaustiveness, so pattern typing must be exact. F10 shows `match b { 0 => .. }` and `match n { true => .. }` still compile with both arms deleted, so this needs its own check now. Staging it leaves the measured UB open with no blocker named. *Concern:* Someone may "fix" a failing match by adding a codegen default arm; that hides the bug and adds a compare to every Bool match, which the option text correctly forbids.
  - **Web:** A — `match b { 0 => .. }` compiling (F10) is the same bug as `if 0 {}`, in a spot users are less likely to look at. There is no known blocker like the enum case had, so staging only leaves a known hole. An exhaustive `true`/`false` match without `_` is what users expect, and it must stay that way. *Concern:* F10 shows match and `!` need their own checks outside `types_compatible`/`is_bool_compat`; if the implementation misses one path (for example nested patterns in tuples), the hole stays open without a test to show it.
  - **PLT:** A — A literal pattern checks against the scrutinee type by the same judgment as `let`, so this is Q1 applied to patterns, not a new rule. F10 confirms the pattern checker has its own path and needs its own check. The fix must restore the invariant, not hide it: an exhaustive Bool match stays exhaustive without `_`, and codegen gets no default arm. *Concern:* An implementer could "fix" F5 by adding a codegen default arm, which makes the symptom vanish while a non-canonical Bool still reaches the match.
  - **DevOps:** A — F10 proves the pattern face and `!n` survive both arm deletions, so they need their own checks; if they are staged, the F5 UB stays reachable through `match`. The fixes are exact: pattern `1`/`0` on a Bool becomes `true`/`false`, and `true`/`false` on an Int becomes `match n != 0 { ... }`. No blocker like `node_kind_name` has been named. *Concern:* `!n` on an Int is not listed in the ballot text of Q6 or Q2 enforcement, and F10 shows no current check covers it; it could ship still accepted unless the PR has a test for `!n` rejected.
  - **AI/ML:** A — This is Q1 applied to patterns; staging it would bring back "compatible here but not there", the shape we are removing. `match b { 0 => .. 1 => .. }` is the C carry-over a model will write, and today it reads uninitialized memory (F5). F10 confirms patterns and `!` need their own checks, so the ticket must name them explicitly. *Concern:* F10's `!n` on an Int is not listed in any option's face; if the PR deletes the two arms and stops, `!n` stays legal as a truthiness side door.
  - **Minimalism:** A — This is Q1 applied to patterns, not a new rule, and F10 shows it needs its own check because neither deleted arm covers it. The enum delay had a named self-host blocker; nobody has named one here, so staging would only keep a known UB open. An exhaustive Bool match must stay exhaustive without a codegen default arm. *Concern:* An implementer may "fix" the F5 UB by emitting a default arm in codegen, which hides the broken invariant; the required test must fail on that shortcut.

- **Q7a: FFI inbound values — Every Bool that enters from FFI (FFI return, `@ffi.struct` field read) is 0 or 1; codegen guarantees it. A C `int` used as a flag is declared `Int`/`I32` in Blink and converted with `!= 0`.** (6-0)
  - **Systems:** A — After Q1–Q6 and x231pe, FFI is the only way a 2 can reach a Bool. The guarantee costs at most one `setne` or byte load on FFI reads, and nothing in pure Blink code. Without it, `@trusted` code gets the F5 UB back from any C library. *Concern:* If Q7b goes to B and Bool stays C `int` in mirrors, codegen must add an explicit `!= 0` on every `@ffi.struct` Bool field read, and it is easy to miss one read path (field of a field, pointer deref) with no test to catch it.
  - **Web:** A — A user who declares a C flag as `Bool` expects it to act like a Bool, and the spec (07:711) already lets them. The boundary is the one place the check belongs; "declare it as `I32`" is good advice for docs but does not close the hole. *Concern:* Users will still declare C `int` flags as `Bool` by habit, so the FFI docs must show the `I32` + `!= 0` pattern next to the `Bool` one.
  - **PLT:** A — The type system can only guarantee canonicity for values it produced; FFI is the trust boundary, so the invariant must be enforced there, once, by normalising with `!= 0`. Without it, F5's UB comes back through any C library that writes 2 into a field the spec already lets users type `Bool` (F3). *Concern:* The normalisation could be applied to FFI returns but missed on `@ffi.struct` field reads or pointer-derived reads, which leaves a quiet hole.
  - **DevOps:** A — F3 says the spec already allows `Bool` in `@ffi.struct`, so "declare it as I32" relies on users choosing well. Codegen must guarantee 0/1 on every inbound read, or the typechecker's guarantee is false at the one place no diagnostic can see. *Concern:* A Bool that comes back through a callback argument or an out-pointer (`Ptr[Bool]` read) is also inbound; if the rule lists only returns and struct fields, one entry point stays open.
  - **AI/ML:** A — Bool is already legal in `@ffi.struct` fields (F3), so the spec must say what it means; a model binding a stdbool function will write `-> Bool` and that must be correct. A C `int` flag as `I32` plus `!= 0` is just the Q1 rule stated once for FFI, with no case left to guess. *Concern:* A binding that declares a C `int` flag as `Bool` will still pass typecheck, and the guarantee holds only if the C type really is `_Bool`.
  - **Minimalism:** A — The invariant "every Bool is 0 or 1" is the whole point of this decision; F3 says the spec already lets users put Bool at the FFI boundary, so without a boundary guarantee F5's UB comes back through any C library. This is a codegen rule, not new surface. *Concern:* If Q7b is decided separately, the normalization must still land with td3yx5 (as `!= 0` on read while Bool lowers to C `int`), not wait for the layout ticket.

- **Q7b: C type of `Bool` at the FFI boundary — This decision states it now: `Bool` in an FFI position (`@ffi.struct` field, `@ffi` param, `@ffi` return) is C `bool` (`_Bool`); FFI mirrors and foreign prototypes spell it `bool`. Internal lowering stays unspecified.** (5-1; Minimalism dissent)
  - **Systems:** A — Today a Bool mirror compiles only against a C `int` field (`src/layout.bl:836` spells Bool as `int`, and the `_Static_assert`s in `src/cg_decl.bl` reject a 1-byte C `bool`), so the only `@ffi.struct` Bool that works is the one that can hold 2. The spec already lists `Bool` as an FFI field type (07:711) and names no C type; that silence is the bug. Stating `_Bool` now fixes the rule, and C then makes 0/1 a property of the load. The implementation and its layout test can still land in a separate PR, which answers devops' bisect concern. *Concern:* Any existing `@ffi.struct` that mirrors a C `int` flag as `Bool` fails its layout assert after the change and must be retyped to `I32`; we need a count of those before the layout PR lands.
  - **Web:** A — A user writing an `@ffi.struct` mirror for a C header with `bool verbose;` should be able to read in the spec what `Bool` means there, and sys shows that today the mirror fails its layout assert (Bool is C `int`). Stating the mapping now costs one sentence of spec; the codegen change can still land in its own PR with its own layout test, which answers devops's bisect concern without leaving the spec silent. *Concern:* If the spec says `_Bool` before the codegen change lands, a user who follows the spec gets a layout assert failure, so the implementation ticket must be linked and not left to drift.
  - **PLT:** A — A type in an FFI position with no stated C meaning has no semantics there; the spec must say what `Bool` denotes at the boundary, and C `bool` is what C headers mean by it. Stating the meaning now does not force the layout change into td3yx5's PR: the implementation and its layout test can land as a separate change, which answers devops' bisection point. Deferring the text leaves `@ffi.struct { flag: Bool }` legal with an undefined layout. *Concern:* If B wins, the spin-out ticket can sit open while users write `@ffi.struct` Bool fields whose 4-byte layout silently disagrees with the C side.
  - **DevOps:** A (position change from B1) — I checked lib/: no `@ffi.struct` field and no `@ffi` return uses `Bool` today, so stating C `_Bool` now breaks no in-tree code. Sys's point decides it for me: with Bool as C `int`, a mirror of a C `bool` field fails only at a `_Static_assert` in the emitted C, which is an error the user cannot act on. Stating the mapping now lets the checker give a real diagnostic. My bisect concern holds for the code, not for the spec text: the layout change must land in its own PR, owned by systems, with a layout test against a real C struct that has a `bool` field. *Concern:* If the layout change rides in the same diff as the Q1–Q3 flip, a corpus move cannot be traced to one cause.
  - **AI/ML:** A — A model writing bindings needs one sentence that maps `Bool` to a C type; "decided later" leaves it to guess, and the guess today (C `int`, F1) is wrong for any header that declares `bool`. Stating it in this decision does not force the layout change into the same commit; the implementation can land as its own change with its own layout test, which answers the bisect concern. *Concern:* Existing `@ffi.struct` mirrors that pair a Blink `Bool` with a C `int` field will break on the layout assert, and their error must say "declare it `I32`" rather than show only a size mismatch.
  - **Minimalism:** *(dissent)* B — My lean for the answer is C `bool` (sys's evidence that a Bool mirror cannot match a C `bool` field today is convincing). But that is a layout change to every `@ffi.struct` with a Bool field, a separate ABI question with its own layout test, and it should not ride inside a type-rule flip. Two unrelated changes in one diff are hard to bisect when the corpus moves; a separate ticket keeps each decision small. *Concern:* If A wins, the layout change and the type flip share one PR, and a corpus regression in an FFI test will be hard to assign to either cause.

  *Soft consensus:* all five majority ballots state the layout change lands in its own PR with its own layout test, which is Minimalism's concern; recorded as an implementation constraint, no Phase D.

- **Q8: Struct-literal field checking (x231pe) — Hard `br dep`: td3yx5 cannot close before x231pe lands; the rule change can land first. x231pe's acceptance includes `P { flag: 2 }` rejected.** (6-0)
  - **Systems:** A — F2 shows `P { flag: 2 }` still passes, so the 0/1 invariant is not sound until x231pe lands. The rule change closes most paths now, and the hard dep stops anyone from calling the gap closed early. *Concern:* x231pe is P0 and blocked; td3yx5 may sit open a long time, and the known hole must stay visible in the ticket, not only in the dep graph.
  - **Web:** A — Land the rule now so users get the error on the 99% of paths it covers; do not let a blocked P0 hold every other fix. The hard `br dep` keeps anyone from claiming "a Bool is always 0 or 1" before it is true. *Concern:* x231pe is blocked, so td3yx5 may sit open for a long time and people may forget why.
  - **PLT:** A — td3yx5 only deletes rules, so it can land first; but its claim "every Bool is 0 or 1" is false while `P { flag: 2 }` passes (F2), which keeps F5's UB reachable. A hard `br dep` stops the ticket from closing on a false soundness claim. x231pe should also record that it is now a memory-safety hole. *Concern:* x231pe is blocked, so td3yx5 may stay open for a long time and people may read "landed" as "sound".
  - **DevOps:** A — Waiting on a blocked P0 keeps every other hole open. The `br dep` stops td3yx5 from closing while `P { flag: 2 }` passes, and x231pe's struct-field error reuses the same E0300 message and fix table with no new diagnostic work. *Concern:* td3yx5's decision text will say "a Bool is always 0 or 1" while x231pe is open; the record must state the exception, or readers take the claim as true now.
  - **AI/ML:** A — Each closed entry point stops wrong idioms from entering the corpus now, so the rule change should land first. But a model that sees `P { flag: 2 }` accepted learns that Bool holds integers, so td3yx5 cannot close before x231pe. *Concern:* x231pe is P0 and blocked, so the soundness claim may stay false for a long time while the spec text says it holds.
  - **Minimalism:** A — Deleting rules depends on nothing; the soundness claim does. A hard `br dep` stops td3yx5 from closing while `P { flag: 2 }` passes, without holding back the entry points the flip closes now. x231pe's acceptance must include the Bool face. *Concern:* x231pe is P0 and blocked, so td3yx5 may sit open a long time and its "Bool is always 0 or 1" claim may get cited as true before it is.

- **Q9: Migration — Rewrite sites first (legal under pinned gen0; retype `-> Int` predicates to `-> Bool` rather than wrap), then delete the carve-outs, one PR, no warning phase.** (6-0)
  - **Systems:** A — Every rewrite is legal under the pinned gen0, so this is a normal migrate-then-delete with no re-pin and no warning phase. F12 forces lib/std first. A fixer tool built for one in-tree migration is not worth gating on. *Concern:* F11's mixed-branch flag (`src/compiler.bl:596`) and similar Int-encoded flags need a real retype, not a mechanical rewrite, and a rushed PR may encode them as `!= 0` wrappers that keep the Int style alive.
  - **Web:** A — Every rewrite is legal under gen0, so migrate first and flip second; no warning phase, since there are no external users to warn. F12 makes the order forced for lib/std anyway. The help lines are what users see, so they ship with the flip; a fixer tool is nice to have, not a gate. *Concern:* F11's `local_exists` (Int-encoded flag with mixed branches) is the kind of site a mechanical pass rewrites wrongly; hand-review the non-mechanical ones.
  - **PLT:** A — Every rewrite is legal under the pinned gen0, so migrate-then-delete is sound for bootstrap and needs no three-step dance. F12 forces the order anyway: lib/std must migrate before the arms go, or the archive does not build. Retyping `-> Int` predicates to `-> Bool` fixes the cause; wrapping in `!= 0` only moves the Int-encoded flag. *Concern:* Sites like src/compiler.bl:596 (F11), an Int-encoded tri-state, need a real type (an enum), and a mechanical pass may force them into Bool and lose a state.
  - **DevOps:** A — Every rewrite is legal under the pinned gen0, so migrate first and delete the arms after, in one PR. F12 makes the order a requirement: lib/std must be migrated before the arms go, or the archive build fails. Machine-applicable `help:` text ships with the flip and is part of done; the fixer tool is not a gate. *Concern:* F11 shows sites with no mechanical rewrite (compiler.bl:596 mixed-branch Int flag); if the migration applies wraps there instead of retyping, the corpus keeps the Int-flag idiom we are removing.
  - **AI/ML:** A — Every rewrite is legal under the pinned gen0, so migrate, then delete the arms, in one PR with no warning phase. Retyping `-> Int` predicates matters most for my seat: signatures are what a model copies. F12 requires lib/std to migrate first. *Concern:* F11's mixed-branch Int flags (src/compiler.bl:596) may get a quick `!= 0` wrap instead of a real Bool, leaving a three-state flag hidden in an Int.
  - **Minimalism:** A — Every rewrite is legal under the pinned gen0, so migrate first, then delete the arms, in one PR, no warning phase and no re-pin. Building a fixer for one in-tree migration with no external users is YAGNI; the typechecker's own error list is the worklist. Retype `-> Int` predicates to `-> Bool` rather than wrap, because our source is training data. *Concern:* F11: a few sites (compiler.bl:596's mixed-branch Int flag) have no mechanical rewrite, and a rushed migration may wrap them in `!= 0` instead of retyping the flag properly.

- **Q10: Diagnostics — Reuse E0300; caret on the offending operand (not the keyword); fixed `note: Blink has no truthiness`; `help:` rewrites per devops' table.** (6-0)
  - **Systems:** A — E0300 reuse adds no new code path. A caret on the operand gives the fix a correct replace range, and a fixed note plus exact `help:` rewrites cost nothing at run time and remove the need for `to_int`. *Concern:* The help for `boolexpr == 2` must say the compare is always false and give no rewrite; a generic `!flag` suggestion there would silently turn a dead branch into a live one.
  - **Web:** A — The help lines are the whole learning cost of this change: a user who sees `help: write n != 0` fixes it in five seconds and never files a question. Caret on the operand, not the keyword, points at what to change. Reusing E0300 keeps one "type mismatch" code to look up. *Concern:* The literal-specific hints (`b == 1` → `b`, `b == 0` → `!b`) need their own tests, or a later refactor of E0300 will drop them without anyone seeing it.
  - **PLT:** A — Reusing E0300 keeps one code for one judgment (type mismatch); the caret on the operand points at the term that fails the premise. The pattern-face rows need help lines too: `true` for pattern `1` on a Bool, and `match n != 0 { ... }` or a guard for `true` on an Int. *Concern:* A help that proposes `n != 0` for every Int condition is correct only when the predicate is nonzero; for `-> Int` predicates the better fix is the retype, and the help cannot see that.
  - **DevOps:** A — One code (E0300), one fixed note (`Blink has no truthiness`) that `blink explain` and LLMs learn as one phrase, and the caret on the operand so the LSP quick-fix has a replace range. Add two rows to my table: `!n` on an Int → `n == 0`, and a condition whose operand calls an `-> Int` predicate → a secondary label at the callee's return type with "consider `-> Bool`". *Concern:* If the caret stays on the `if` keyword (column 5 today), the `help:` text is right but the JSON fix has the wrong span, and the code action replaces the keyword instead of the operand.
  - **AI/ML:** A — In a self-repair loop the model reads the diagnostic, not the spec, so each error must name both types and give the rewrite as code. The caret on the operand gives tools a correct replace range, and the fixed note teaches the rule in five words. *Concern:* The help table may miss faces that do not route through E0300 today (`!n`, match patterns, `.to_int()` on Bool), so those errors ship with no rewrite.
  - **Minimalism:** A — Reusing E0300 adds no new code; the help lines are what make Q4-A viable, and the caret on the operand gives a correct replace range. A fixed `note: Blink has no truthiness` teaches the rule once, in the same words, every time. *Concern:* The help table grows one row per face (assign, condition, `==`, `!`, pattern, method guess); if one face ships without its row, that face gives a bare error.

Phase D was not triggered: every question was 6-0 or 5-1.

### AI-First Review

**5/5 pass.**

- **Learnability:** pass. One rule, stated in the spec (`Bool` is not a number). No other-language guessing.
- **Consistency:** pass. It matches sized-int and enum assignability. The one departure, no `Bool == Int` comparison, follows from `Eq.eq(self, other: Self)` and §3's "a Bool never reads as 0 or 1".
- **Generability:** pass. Every rewrite is local: `x != 0` → `x`, `x == 0` → `!x`.
- **Debuggability:** pass. E0300 with a machine-applicable help per shape.
- **Token efficiency:** pass. `if b { 1 } else { 0 }` is rare; the deleted `!= 0` suffixes save tokens.

### Final Spec

```blink
fn is_ready(n: Int) -> Bool { n > 0 }        // predicates return Bool, never Int

fn main() {
    let n = 3
    let b: Bool = n != 0                      // Int -> Bool: compare explicitly
    let bit: Int = if b { 1 } else { 0 }      // Bool -> Int: branch explicitly
    if is_ready(n) { io.println("ready") }
    if !b { io.println("zero") }              // was: b == 0
    let s = match b {
        true => "yes"
        false => "no"                         // exhaustive: no `_` needed
    }
    io.println("{bit} {s}")

    // Each line below is error[E0300]:
    // let x: Bool = 1          help: `true`
    // let y: Int = b           help: `if b { 1 } else { 0 }`
    // if n { }                 help: `n != 0`
    // if b == 1 { }            help: `b`
    // !n                       help: `n == 0`
    // match b { 0 => ... }     help: pattern `false`
    // b.to_int()               help: `if b { 1 } else { 0 }`
}
```

- `Bool` and `Int` are not assignable to each other in either direction, at any site (§3.4 *`Bool` Is Distinct from `Int`*).
- Conditions (`if`, `while`, match guards) and the operands of `&&`, `||` and `!` take exactly `Bool`. Integer literals get no special case (§2.19 *No Truthiness*).
- `==` and `!=` between `Bool` and `Int` are errors. Enums keep tag comparison with `Int`; `Bool` does not, because it has no numeric identity.
- No `to_int`, `from_int`, `to_bool` or cast. The `.to_int()` attempt gets a help line.
- Match patterns are checked in both directions now. An exhaustive `Bool` match needs no `_`, and codegen adds no default arm.
- Every `Bool` value is `true` or `false`. At the FFI boundary `Bool` is C `bool` (`_Bool`); a C `int` flag is `I32` plus `!= 0` (§9.1.3). The layout change lands in its own PR with its own layout test.
- The invariant is sound only when struct-literal field values are type-checked; the implementation ticket closes only after that check lands.
- Migration: rewrite sites under the pinned gen0 first (lib/std before the archive build breaks; `-> Int` predicates become `-> Bool`), then delete the three carve-outs in one PR, with no warning phase.
- Diagnostics: E0300, caret under the operand, fixed `note: Blink has no truthiness`, one machine-applicable `help:` per shape.
