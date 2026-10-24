[< All Decisions](../DECISIONS.md)

# Float Finite and Infinite Tests — Design Rationale

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated
in independent-proposal → debate → vote rounds.

The question: `Float` has a built-in `is_nan` and no test for a finite value or an infinity, so a user cannot write a short guard before a JSON encode. The JSON NaN and infinity decision (Q2 6-0, no strict check now) left the guard to users. The Float total order re-audit left "`is_infinite`/`is_finite` and NaN/infinity constants" to a separate question. This is that question.

Facts at the start of the panel:

- `lib/std/float.bl` has the free fns `fabs`, `is_nan` and `close_to`, and no `is_finite` or `is_infinite`.
- The built-in `is_nan` is specified and not yet implemented. Today `x.is_nan()` needs `import std.float`.
- The spec names `Float.INF` in two places and no section defines it. `Float.INF.display()` gave an internal compiler error.
- `F32` is reserved. The *Built-in Float Methods* rows already cover both types.

Phase A excerpts below are quoted from each seat's own file; a cut is marked "…".

#### Phase A — Independent proposals

- **Systems:** "Add two rows to *Built-in Float Methods*, the same table as `is_nan`. No import. Each row covers `Float` and `F32`." … "NaN is neither finite nor infinite. `-0.0` and subnormals are finite." … "Partition: for every `x`, exactly one of `x.is_nan()`, `x.is_infinite()`, `x.is_finite()` is `true`." … "`x.is_infinite() == (x == Float.INF || x == -Float.INF)`. This holds under the total order (`NaN == NaN`, NaN is greatest, so NaN never equals `INF`)." … "Define in the prelude: `Float.INF`, `Float.NAN`, `F32.INF`, `F32.NAN`. Negative infinity is `-Float.INF`. `Float.NAN` is the canonical quiet NaN, bits `0x7FF8000000000000`. Leave `MAX`, `MIN`, `EPSILON` out." … "Today's `x != 1.0 / 0.0` guard is also cheap, so the built-in adds ergonomics, not speed. I do not claim a speed win." Guard example:
  ```blink
  fn encode_reading(x: Float) -> String {
      if x.is_finite() {
          json.stringify(x)
      } else {
          "null"
      }
  }
  ```
  Tradeoffs: "Two more built-in names in the prelude surface. The implementer must write them with the same open `is_nan` work, so land all three in one change. `Float.NAN` has a payload and a sign. Fixing the bits makes `Float.NAN.to_bits()` stable."
- **Web/Scripting:** "Add two rows to *Built-in Float Methods*, under `is_nan`. No import." … "`x.is_infinite() == (x == Float.INF || x == -Float.INF)`" … "`Float.INF` (the spec already names it at 02_syntax.md:1255 and 06_tooling.md:1067; keep that spelling, do not add `INFINITY`) and `Float.NAN`. Negative infinity is `-Float.INF`. `F32.INF`, `F32.NAN` follow when `F32` ships." … "Because `NaN == NaN` in Blink, `x == Float.NAN` is true for a NaN. Say so in one line, and say that `x.is_nan()` stays the preferred test." … "Add no `float.is_finite` free fn: one way to do it." Guard example:
  ```blink
  fn encode_checked(x: Float) -> Option[Str] {
      if x.is_finite() {
          Some(json.stringify(x))
      } else {
          None
      }
  }
  ```
  "Names match Rust, Kotlin and JS (`Number.isFinite`), so a guess works." "Cost: two methods and two constants on the surface. Both are small and fixed by IEEE 754."
- **PLT:** "Add two rows to *Built-in Float Methods* (sections/03_types.md, ~line 4416). They need no import. Each row covers `Float` and `F32`." … "**Trichotomy.** For every `x`, exactly one of `x.is_nan()`, `x.is_infinite()`, `x.is_finite()` is `true`. NaN is neither finite nor infinite." … "**Bits.** `x.is_finite()` is `true` exactly when the exponent field of `x.to_bits()` is not all ones." … "`Float.NAN`: a quiet NaN. Its sign and payload are not fixed. Every NaN is `==` every NaN, so no program can see the difference except through `to_bits`." … "I said in Phase B that `x == Float.INFINITY || x == -Float.INFINITY` is a convenience and to leave it out. I now reverse that." … "With `is_nan`, `is_infinite` and `is_finite`, the three classes partition all values. A partition is a closed set of tests. Two of three would leave a hole." Guard example:
  ```blink
  fn encode_checked(x: Float) -> Result[String, String] {
      if !x.is_finite() {
          return Err("non-finite float")
      }
      Ok(json.stringify(x))
  }
  ```
- **DevOps:** "Two rows added to *Built-in Float Methods* (sections/03_types.md). No import." … "**Classes.** For every `x`, exactly one of `x.is_nan()`, `x.is_infinite()`, `x.is_finite()` is `true`." … "As a built-in, LSP completion on any `Float` lists the whole IEEE set with no import. A free fn in `std.float` needs an import, and `UnusedImport` already misfires there (p6)." … "The correct `is_finite` expression is `!x.is_nan() && x != 1.0 / 0.0 && x != -1.0 / 0.0` (p6): three tests, a literal no JS or Python dev will guess, and a NaN trap" … "A name in the spec with no definition sends users into an ICE." … "If the panel finds this too wide, split it into its own ticket and change both spec lines to stop naming `Float.INF`. I do not accept leaving the dangling name." … "03_types.md: table, Laws, and the "To test for NaN" bullets (add "to test for a finite value, use `x.is_finite()`")."
- **AI/ML:** "Add two rows to *Built-in Float Methods*, same shape as `is_nan`, no import, both types" … "NaN: `is_finite` is false and `is_infinite` is false. Zero (+0.0, -0.0) and subnormals are finite." … "One name per concept: `INF`, not `INFINITY`, because the spec already chose `INF`, and an LLM reading the spec sees one spelling. `NAN` is the only spelling that fits `INF`." … "The method form `x.is_finite()` is the Rust spelling and matches `x.is_nan()` already in the table, so a model that learned `is_nan` guesses the other two correctly with no spec lookup." Guard example:
  ```blink
  fn encode_reading(x: Float) -> String {
      if x.is_finite() {
          json.stringify(x)
      } else {
          "null"
      }
  }
  ```
  "Two paths (`float.is_finite(x)` and `x.is_finite()`) double the decision points for a model and contradict the built-in precedent."
- **Minimalism:** "## min-1 (preferred): add one built-in method, `is_finite`. No `is_infinite`. No new constants in this ticket." … "`is_infinite(x)` = `!x.is_finite() && !x.is_nan()`. This is a rare question, and the derivation uses only built-in methods. No constant is needed." … "The spec already promises `Float.INF` in 02_syntax.md:1255 and 06_tooling.md:1067, and no section defines it (p4 is an ICE). That is a spec defect. … If the owner wants the defect closed, the minimal fix is to define `Float.INF` only (`-Float.INF` is the other infinity) and drop `Float.NAN`; NaN is `0.0 / 0.0` or `parse_float("nan")`." … "## min-2 (fallback if the panel insists on the pair): … I accept this only if the pair is the whole change: no free fns in `std.float`, no constants group." Guard example:
  ```blink
  fn encode_reading(x: Float) -> Result[Str, Str] {
    if !x.is_finite() {
      return Err("reading is not finite")
    }
    Ok(json.stringify(x))
  }
  ```

All six Phase A files rejected "reject, users write the guard" as a recommendation. No seat proposed `MAX`, `MIN`, `EPSILON`, `NEG_INF` or `INFINITY`.

#### Phase B — Debate highlights

- **Minimalism (moves to the pair):** "**O1 (methods). I concede: the pair.** I said in min-2 that I accept it if the pair is the whole change. plt's point holds: `is_nan`, `is_infinite`, `is_finite` form a closed partition, and a two-of-three set invites a user to ask for the third. The cost is one more table row."
- **Minimalism (holds on constants):** "I oppose `Float.NAN`. Nothing in this ticket needs it. A NaN is `0.0 / 0.0` or `parse_float("nan")`. web-1 itself shows the cost: because `NaN == NaN` here, `x == Float.NAN` is a second NaN test next to `is_nan`, and the spec needs a line to warn against it."
- **Web/Scripting:** "I oppose min-1. min's derivation `!x.is_finite() && !x.is_nan()` is two calls and a negation, and a JS or Python dev reading it must work out why NaN is excluded. That is the trap this ticket exists to remove." On constants: "`NaN` is `0.0 / 0.0` in min's text: the same unguessable literal form that this panel called a defect for infinity." On bits: "Drop plt's bits law: it states layout, which is codegen detail, not language behavior."
- **Systems:** "I withdraw "bits `0x7FF8000000000000`" as a spec rule. plt is right that every NaN equals every NaN, so only `to_bits` sees it. A pinned pattern is a layout rule, and `Float.NAN` costs nothing at runtime either way." On `F32`: "`F32` is reserved, so there is nothing to define yet. Say "when `F32` ships"." On the bits law: "The bits law gives the implementer a test oracle that does not depend on C `isfinite` semantics under `-ffast-math`. I want to keep it."
- **PLT:** "The partition law needs the third member to be a name, not a derivation." On `F32` and the NaN bits PLT conceded to Systems in this round: "I concede to sys: define `Float.NAN` as the quiet NaN with bits `0x7FF8000000000000`. A constant is one fixed value, so this does not conflict with the *Arithmetic* law, which concerns NaNs that operations produce." On the bits law: "The bits law is the link to the *Bits* section, so it stays." "Add a line under *Differences from IEEE 754* that `is_finite` and `is_infinite` treat NaN as neither."
- **DevOps:** "min-1 says `is_infinite` is `!x.is_finite() && !x.is_nan()`. That is the same trap one level up: two tests, and the order matters." "a dangling spec name that crashes the compiler (p4) is not left in place." "A fixed payload (sys-1) adds a promise that a test must keep." "Add plt's bit law only if the writer wants one; I do not need it."
- **AI/ML** (its file says it read the Phase A files as summarized in the Phase B digest): "`!x.is_finite() && !x.is_nan()` is two calls and a negation that a model must derive each time, and it gets the NaN clause wrong often." "I support web-1's one-line warning: `x == Float.NAN` is true for a NaN because of the total order, and `x.is_nan()` is the preferred test. That line stops the most likely model error (copying `x == NaN` from other languages, where it is always false)." "Drop the bits law from the spec text; it is an implementation fact." On the guard: "Note the else branch duplicates what encode already does for non-finite values (`null`); the guard is only useful when the user wants a different behavior (skip the field, use a default). I would use that in the spec example to avoid teaching a redundant pattern."
- **Example fixes (all seats):** `json.stringify` takes a `JsonValue`, and the type is `Str`. Web: "The `encode` form is the one that takes a `Float` (03_types.md:6328)". The corrected guards use `Str` and `json.encode(x)`. DevOps: "I did not check that `EncodeError` exists; the example declares intent only, and the writer should replace it with a real error type from the spec."

#### Phase C — Final vote

The ballot listed seven questions. Each seat gave a vote, reasoning and a concern.

- **Q1: Which methods. A: both `is_finite` and `is_infinite`. B: `is_finite` only.** (6-0 for A)
  - **Systems:** A — "Each predicate is one inline mask-and-compare (or C `isfinite`/`isinf`) with no call, branch or allocation. The derived `is_infinite` (`!x.is_finite() && !x.is_nan()`) costs two tests and a negation at every use, and the table gives the implementer a closed partition to test. min has conceded the pair." Concern: "Two more built-in names land in the prelude, and the spec rows exist before the implementation, so the impl slice must ship all three (`is_nan`, `is_finite`, `is_infinite`) together."
  - **Web/Scripting:** A — "A JS or Python dev who learns `is_nan` will type `is_finite` and `is_infinite` next. Rust, Kotlin and JS use the same names, so a guess works with no spec lookup. Deriving `is_infinite` from `!x.is_finite() && !x.is_nan()` brings back the NaN trap that this ticket exists to remove." Concern: "The pair adds a second name that few users need, but only one table row."
  - **PLT:** A — "`is_nan`, `is_infinite` and `is_finite` partition the values of `Float`. A partition is a closed set of tests, and the law "exactly one holds" needs all three as names, not as a derivation. min's own B1 concedes the pair." Concern: "none of substance; min's cost argument (one more row) is the only weight on the other side."
  - **DevOps:** A — "A user who writes `x.is_infinite()` next to `x.is_finite()` and `x.is_nan()` gets `UnresolvedMethod` if the third name is missing. With all three, LSP completion on a `Float` lists the full class set, and one help line fits: "a Float is NaN, infinite or finite". Min conceded the pair." Concern: "The three methods land in one slice with built-in `is_nan`, which is not yet implemented; if the slice splits, users see a half table."
  - **AI/ML:** A — "`is_nan`, `is_infinite` and `is_finite` form three classes that cover every value. A model that learns `is_nan` from the table guesses the other two with no lookup. The derivation `!x.is_finite() && !x.is_nan()` is the NaN-clause trap that models get wrong." Concern: "The extra row adds two built-in names to the prelude, and a later request for `is_normal` or `classify` has the same shape."
  - **Minimalism:** A — "The partition `is_nan` / `is_infinite` / `is_finite` is a closed set, and a two-of-three set invites a request for the third. The cost is one table row in a table that already exists, and no new rule. I conceded this in B1 and the pair is the whole method change." Concern: "The pair is accepted as the whole change, but a later request for `is_normal` or `classify` will cite this partition as precedent."

- **Q2: Constants. A: define `Float.INF` and `Float.NAN` in this change. B: `Float.INF` only. C: split out; both spec lines stop naming `Float.INF`.** (5-1 for A)
  - **Systems:** A — "`Float.INF` and `Float.NAN` are compile-time constants with zero runtime cost. The spec already names `Float.INF` and it ICEs today (p4). A NaN written as `0.0 / 0.0` is a literal no one can guess, and tests need a NaN value." Concern: "The constants add a prelude-constant path for builtin types that the lowering must handle (p4 is an ICE today), so the impl is larger than the two table rows suggest."
  - **Web/Scripting:** A — "`NaN` written as `0.0 / 0.0` is the same unguessable literal form that this panel called a defect for infinity. Tests need `assert(Float.NAN.is_nan())` and users need a sentinel value. The spec already names `Float.INF` twice, so a dangling name must not stay, and two constants make the laws writable." Concern: "If the panel picks INF only, `NAN` is filed again and a user from JS or Python still has no name for it."
  - **PLT:** A — "The spec uses `Float.INF` and defines it nowhere. Under a total order, NaN is the top element; the spec should be able to name a value of that class, and the `==` law for `is_infinite` is only writable with `INF`. `INF` without `NAN` leaves `0.0 / 0.0` as the only writable NaN, the same unguessable form this panel called a defect for infinity." Concern: "A adds a second constant that users may read as the NaN test, which Q6 must then warn against."
  - **DevOps:** A — "The spec names `Float.INF` twice, and `Float.INF.display()` is an internal compiler error today (p4). Defining `INF` and `NAN` together gives tests and `assert_eq(x, Float.INF)` (06_tooling.md:1067) a writable value and avoids a second ticket for `NAN`. Option C is my fallback: both spec lines must then stop naming `Float.INF`." Concern: "The prelude constants must resolve without the NoTypeForNode ICE; if the implementation ships the names with no test for `Float.INF.display()`, the user-visible failure stays."
  - **AI/ML:** A — "The spec names `Float.INF` and defines nothing, so a model that reads the spec writes a name that crashes the compiler. `INF` with `NAN` gives one spelling for each, so no one invents `INFINITY` or `nan()`. Without `NAN`, a model cannot write a test value except as `0.0 / 0.0`, which is not guessable." Concern: "The spec grows two constants with no use in this ticket's guard, and `NAN` brings the `x == Float.NAN` surprise that needs the Q6 line."
  - **Minimalism:** *(dissent)* B — "Defining `Float.INF` repairs a name the spec already uses in two places, so it adds no new surface. `Float.NAN` is new surface that nothing in this ticket needs: a NaN is `0.0 / 0.0` or `parse_float("nan")`, and the constant brings a warning line (Q6) and a bits argument (Q4) with it. If the panel wants NAN, it can go through its own ticket." Concern: "If A wins, `Float.NAN` makes `x == Float.NAN` a second NaN test next to `is_nan`, and the spec needs a warning line to stop it."

- **Q3: `F32.INF` / `F32.NAN`. A: define them when `F32` ships. B: state them now.** (5-1 for A)
  - **Systems:** A — "`F32` is reserved, so a constant on it cannot be compiled or tested. Define them when `F32` ships and its codegen is known. The method rows are different: they carry no value and cost nothing while reserved." Concern: "The table rows cover `F32` while the constants do not, so the spec is briefly uneven between the two types."
  - **Web/Scripting:** A — "`F32` is reserved, so a user cannot write the constant or test it. Define them when `F32` ships. The method rows cover `F32` already, but a constant on a reserved type has no use today." Concern: "The spec rows and the constants cover different type sets for a while, and a reader may ask why."
  - **PLT:** *(dissent)* B — "The table rows already cover `F32` while it is reserved. Constants that follow the same rule keep the text uniform, and one statement of the type's value set is easier to check than a later patch. The cost is a constant on a type no program can use yet." Concern: "A (not now) is likely to win, and then the F32 text is added in a later change, with the risk that the two types drift in spelling."
  - **DevOps:** A — "`F32` is reserved, so a constant on it gives a diagnostic nobody can reach and a test nobody can write. The method rows already cover `F32` because they are signatures only. Define the constants when `F32` ships." Concern: "When `F32` ships, someone must remember the constants; the writer should leave a note in the *Float Bits* or `F32` text so the spec does not drift."
  - **AI/ML:** A — "A constant on a reserved type cannot be tested, and the model gets a "reserved" error from it anyway. One sentence "when `F32` ships" is enough, and the table rows need no change." Concern: "The spec states methods for `F32` but no constants, so a reader may find the `F32` surface uneven until `F32` ships."
  - **Minimalism:** A — "`F32` is reserved, and a constant on a reserved type cannot be tested or reached. Define them when `F32` ships." Concern: "If B wins, the spec states constants that no program can use, and they must be re-checked when `F32` ships."

- **Q4: The bits of `Float.NAN`. A: a quiet NaN whose sign and payload the spec does not fix. B: fixed `0x7FF8000000000000`, plus a sentence on the *Arithmetic* law.** (5-1 for A)
  - **Systems:** A — "I withdrew the fixed-bits rule in B1. Every NaN is `==` every NaN, so only `to_bits` can see the pattern, and a pinned pattern is a layout promise that a test must keep for no program benefit. The compiler emits one canonical quiet NaN anyway." Concern: "`Float.NAN.to_bits()` can differ across implementations or targets, which a user hashing raw bits might notice."
  - **Web/Scripting:** A — "A JS or Python dev never looks at NaN bits. Fixing a bit pattern adds a promise, and a sentence to explain how it relates to the *Arithmetic* law, for a case outside the 90% use. `to_bits` stays available to anyone who cares about one NaN." Concern: "`Float.NAN.to_bits()` may differ between builds, and a test that pins it would break."
  - **PLT:** *(dissent)* B — "A named constant should denote one value. If the spec leaves the bits open, `Float.NAN.to_bits()` is implementation-defined, and `Float.NAN` is not one value across implementations. The sentence that the *Arithmetic* law covers NaNs that operations produce, not the constant, removes the conflict." Concern: "if A wins, a program that reads `Float.NAN.to_bits()` or serializes the bits gets a result the spec does not fix."
  - **DevOps:** A — "A fixed payload is one more promise that a test must keep and that the formatter and diagnostics must never contradict. Only `to_bits` can see the bits, and `x.is_nan()` is the test. sys withdrew the fixed bits." Concern: "A user who prints `Float.NAN.to_bits()` may see different values across targets, and no spec line will tell them why."
  - **AI/ML:** A — "Every NaN equals every NaN, so only `to_bits` sees the payload. A pinned pattern is a layout fact that a model must remember and that tests must keep, for a case almost no program has. Leaving it open adds no decision point to common code." Concern: "A user who calls `Float.NAN.to_bits()` gets an answer the spec does not promise, and a different backend could change it."
  - **Minimalism:** A — "I vote against `Float.NAN` in Q2, so this applies only if it wins. In that case a pinned bit pattern is a layout rule, and every NaN already equals every NaN, so only `to_bits` can see the difference. Leave the sign and payload unfixed." Concern: "If B wins, the spec promises a payload that a test must keep for as long as the language lives."

- **Q5: The bits law ("`x.is_finite()` is `true` exactly when the exponent field of `x.to_bits()` is not all ones"). A: keep it. B: leave it out.** (Phase C: B 4-2, web, devops, aiml and min B; sys and plt A. Phase D: A 6-0. See Phase D.)
  - **Systems:** A — "The *Bits* section already makes the IEEE layout part of the language (`to_bits`), so this law adds no new layout rule. It gives the implementer a test oracle that does not rely on C `isfinite` semantics under `-ffast-math`. It also ties the new rows to `to_bits`." Concern: "If the panel leaves it out, the tests still check the partition and the constants, but nothing links `is_finite` to the stated bit layout."
  - **Web/Scripting:** B — "The partition law and the method rows already say what `is_finite` means. The exponent-field text states layout, and a reader who wants to learn the method does not need it. The implementer can keep it as a test." Concern: "Without the bits law, the *Bits* section does not link to the new methods, and the implementer has no spec-level test oracle."
  - **PLT:** A — "`to_bits` is a specified public method, so a law over `to_bits` states behavior a user can observe, not layout. It ties the new methods to the *Bits* section and gives the implementer an oracle independent of C `isfinite` semantics." Concern: "if B wins, nothing in the text fixes `is_finite` to the bit pattern, and an implementation under fast-math flags could drift without a spec-level test."
  - **DevOps:** B — "The partition law and the `==` law give a test suite everything it needs over `[0.0, -0.0, 1.0, inf, -inf, nan]`. Exponent-field text states layout, and the repo rule keeps layout out of the spec. The implementer can keep the bits oracle as a test." Concern: "Without the bits law, an implementation on a `-ffast-math` C build could break `is_finite` and no spec line would flag it; the test list must cover NaN and both infinities."
  - **AI/ML:** B — "The law restates the table row in terms of layout. A model gains nothing from it for writing code, and it costs spec tokens in every `blink llms` read. The partition law and the table give the same test oracle through `is_nan`, `is_infinite` and the constants." Concern: "An implementer has no spec text for a test that does not depend on the C `isfinite` call, so a bug in that call could pass unseen."
  - **Minimalism:** B — "Exponent-field text states layout, and the spec carries no layout details. The partition law and the table row give the implementer an oracle already. The test suite can check the bit pattern without the spec stating it." Concern: "If A wins, the spec law fixes the binary64 layout in prose, and it must change if `F32` or another float type needs different text."

- **Q6: The `x == Float.NAN` line. A: one line: `x == Float.NAN` is `true` for every NaN in Blink, and `x.is_nan()` is the preferred test. B: no such line.** (5-1 for A)
  - **Systems:** A — "Under the total order `x == Float.NAN` is `true` for a NaN, which is the opposite of C, Rust and JS, where it is always false. One line prevents a codegen-visible surprise: a user porting a C check must not assume a comparison lowers to an IEEE `ucomisd`. It costs one sentence." Concern: "The line invites `x == Float.NAN` as a second NaN test next to `is_nan`, which may need a lint later."
  - **Web/Scripting:** A — "Every JS, Python, Rust and C dev knows `x == NaN` is always false. In Blink it is true for a NaN, so this is the most likely wrong guess in the whole area. One line stops it, and it names `x.is_nan()` as the preferred test." Concern: "Users from IEEE languages may still write `x == Float.NAN` and get the right answer by accident, then see `false` when they port the code back."
  - **PLT:** A — "Under the total order `x == Float.NAN` is `true` for a NaN. This differs from every IEEE language, so a user will expect `false`. One line removes the error, and it names `is_nan` as the preferred test." Concern: "if B wins, models and users copy the IEEE belief that `x == NaN` is always `false`, and write wrong code with no diagnostic."
  - **DevOps:** A — "Users from IEEE languages expect `x == NaN` to be `false`. One line in the spec saves a support question and gives a later lint a documented target. It applies only because Q2 defines `Float.NAN`." Concern: "The line names a second NaN test next to `is_nan`; the writer must word it as "preferred test is `x.is_nan()`" so models do not copy `== Float.NAN`."
  - **AI/ML:** A — "The most likely model error is to copy `x == NaN` from IEEE languages, where it is always false. Here it is true for a NaN, and one line stops a wrong belief in either direction. It also names `is_nan` as the one preferred test, so the model has one path." Concern: "The line tells users that a second NaN test exists, and some will use it instead of `is_nan`."
  - **Minimalism:** *(dissent)* B — "It applies only if Q2 defines `Float.NAN`, and I vote against that. Without the constant the line has nothing to describe. If A wins in Q2, I would want the line, because the total order makes `x == Float.NAN` true for a NaN, which surprises IEEE users." Concern: "If Q2 picks A and Q6 picks B, a user copies `x == Float.NAN` from another language and gets a result that the spec never explains."

- **Q7: A line under *Differences from IEEE 754*. A: add a line that `is_finite` and `is_infinite` treat NaN as neither. B: no line there.** (5-1 for B)
  - **Systems:** B — "That section lists where Blink differs from IEEE 754. `isfinite(NaN)` and `isinf(NaN)` are both false in IEEE 754 and in C, so this is not a difference. The table row already says "neither a NaN nor an infinity"." Concern: "A reader who scans only that section for NaN behavior will not find the finite/infinite rule there, but the method table states it directly."
  - **Web/Scripting:** B — "`is_finite` and `is_infinite` follow IEEE here: NaN is neither. Our own *Returns* column and the partition law already say it. That section lists where Blink differs, and this is not a difference." Concern: "A reader who scans only the *Differences* section for NaN rules will not find the new methods there."
  - **PLT:** *(dissent)* A — "The *Differences from IEEE 754* list is where a reader looks to find where Blink's float behavior departs from the norm. "NaN is neither finite nor infinite" matches IEEE `isfinite`/`isinf`, so it is not a difference, but a reader who derives these from the total order (NaN is greatest, so "above all finite values") could expect NaN to count as infinite. One line closes that." Concern: "if B wins, the NaN rule is stated only in the table row and laws, which a reader of the differences list will not see."
  - **DevOps:** B — "The table rows ("neither a NaN nor an infinity") and the partition law already say NaN is neither. A third place that says the same thing adds a line to keep in sync. The NaN-bullet line from devops-1 covers the help text." Concern: "A reader who scans only *Differences from IEEE 754* may miss that NaN is neither finite nor infinite; the *Laws* list is the single place that carries it."
  - **AI/ML:** B — "IEEE `isfinite` also gives false for NaN, so this is not a difference from IEEE. The table row and the partition law already say NaN is neither. A repeat in a section that lists differences makes the model look for a difference that is not there." Concern: "A reader who knows that NaN is the greatest value may think it is "above" infinity and so infinite, and no line in that section says otherwise."
  - **Minimalism:** B — "The table row says NaN is neither finite nor infinite, and the partition law says the same. `is_finite` and `is_infinite` follow IEEE `isfinite` and `isinf`, so NaN is not a difference from IEEE. A third statement of one fact is surface with no new content." Concern: "If A wins, the *Differences* list holds an item that is not a difference, and it blurs the list for the reader."

#### Phase D — Round 2 (Q5 only)

The moderator surfaced one fact for Q5: "The Laws list already holds: "**Sign.** `x.is_sign_negative()` is `true` exactly when the sign bit of `x` is set." The `to_bits` row returns "The IEEE 754 binary64 (binary32) bit pattern"." Debate highlights, then the silent re-vote.

- **Systems (holds A):** "The Fact decides it for me. The Laws list already has "**Sign.** `x.is_sign_negative()` is `true` exactly when the sign bit of `x` is set." That is a law over the bit pattern, and nobody objected to it as layout." "If B wins, I ask that the test list name NaN, both infinities, `0.0`, `-0.0`, a subnormal and the largest finite value, and check the result against `to_bits`, so the oracle still exists."
- **Web/Scripting (moves B to A):** "My B vote rested on "the law states layout". The fact in D1.md weakens that." "One condition for the writer: word the law for both widths ("the exponent field of `x.to_bits()` is not all ones"), with no fixed bit count, so it needs no change when `F32` ships."
- **PLT (holds A):** "So the "spec carries no layout" argument (web, devops, min) would also remove the Sign law, and nobody asks for that. The bits law adds no new layout rule." "If A loses, I accept that the implementer keeps the bits check as a test. I do not move."
- **DevOps (moves B to A):** "The rule I cited covers the second, not the first." "the partition law checks `is_nan` and `is_infinite` against each other, and both can share the same C call."
- **AI/ML (moves B to A):** "So the spec already states bit-level laws for these methods, and `to_bits` is public. My "layout" objection does not hold, because the layout is already stated." "The cost is one line, about 25 tokens, and it is in one place."
- **Minimalism (moves B to A):** "Leaving out the bits law makes `is_finite` the one classification method with no tie to the *Bits* section, while `is_sign_negative` has one. Dropping it would be the odd case, not the minimal one." "I keep one condition: the law stays one line, with no field widths and no `0x` patterns."

**Q5 re-vote: A, 6-0.**

- **Systems:** A — "The Laws list already holds the Sign law, a law over the bit pattern, and `to_bits` is public. The bits law for `is_finite` has the same form, so leaving it out makes the list uneven. It costs one line and no codegen. It also gives the implementer an oracle that does not rely on C `isfinite` under `-ffast-math`: all three predicates can share one C call, so the partition law cannot catch a fault in it." Concern: "The line may read as a promise about the C implementation and not about the observable result, and the wording must stay width-free so `F32` needs no rewrite."
- **Web/Scripting:** A — "The Laws list already holds the Sign law over the sign bit, and `to_bits` is public, so a law over `to_bits` states behavior a user can observe, not hidden layout. A JS or Python dev reads the table rows and skips the Laws list, so the extra line costs that dev nothing." Concern: "A reader may take the line as a promise about the C implementation, not only the observable result."
- **PLT:** A — "`to_bits` is a specified public method, so a law over `to_bits` states behavior a user can observe, not layout. The Laws list already holds the *Sign* law over the sign bit, so the bits law for `is_finite` has the same form and the same source." Concern: "If A wins, a reader may take the line as a promise about the C implementation and not about the observable result."
- **DevOps:** A — "The bits law is the one line a test author turns into a table-driven test, so a `-ffast-math` build that breaks `is_finite` fails a test. The partition law cannot give that oracle, because `is_nan`, `is_infinite` and `is_finite` can share one C call." Concern: "If A wins, a reader may take the line as a promise about the C implementation, and the line may need rewording when `F32` ships."
- **AI/ML:** A — "The Laws list already holds the *Sign* law, a bit-level law over a public method. A bits law for `is_finite` matches it, so the model sees one pattern for the classification methods and no gap." Concern: "A model or user may read the line as a rule about the C implementation instead of the result of `to_bits`, and may then copy bit tests into user code instead of calling `is_finite`."
- **Minimalism:** A — "A law over `to_bits` states behavior a user can observe, so it adds no name, no syntax and no new rule. Leaving it out would make `is_finite` the one classification method with no tie to the *Bits* section; the odd case is the subtraction here, not the line." Concern: "If A wins and the writer adds field widths or `0x` patterns, the law becomes a layout promise that must change when `F32` ships; it must stay one line with no widths."

### Dissents

- **Q2, Minimalism:** "`Float.NAN` is new surface that nothing in this ticket needs".
- **Q3, PLT:** "Constants that follow the same rule keep the text uniform".
- **Q4, PLT:** "A named constant should denote one value."
- **Q6, Minimalism:** conditional on Q2: "If A wins in Q2, I would want the line".
- **Q7, PLT:** "a reader who derives these from the total order (NaN is greatest, so "above all finite values") could expect NaN to count as infinite."

### AI-First Review

5/5 pass. The three names follow `is_nan` and the Rust spelling (`is_finite`, `is_infinite`), so a model that learns one guesses the others; `INF` and `NAN` give one spelling each; the guard is one call with no import.

### Final Spec

```blink
fn main() {
    assert(Float.INF.is_infinite() && (-Float.INF).is_infinite())
    assert(Float.NAN.is_nan())
    assert(!Float.NAN.is_finite() && !Float.NAN.is_infinite())
    assert(1.5.is_finite())
}
```

- `is_finite` and `is_infinite` are built-in methods on `Float` and `F32`, in the *Built-in Float Methods* table, with no import and no `std.float` free fn. A NaN is neither.
- Laws: exactly one of `is_nan`, `is_infinite`, `is_finite` holds; `x.is_infinite() == (x == Float.INF || x == -Float.INF)`; `x.is_finite()` is `true` exactly when the exponent field of `x.to_bits()` is not all ones.
- `Float.INF` and `Float.NAN` are prelude constants. `Float.NAN` is a quiet NaN with no fixed sign or payload. `F32.INF` and `F32.NAN` are not defined until `F32` ships.
- `x == Float.NAN` is `true` for every NaN; `x.is_nan()` is the preferred test.
- The NaN-test bullets gain "to test for a finite value, use `x.is_finite()`". *Differences from IEEE 754* gets no line.
- The JSON guard example uses `Str` and `json.encode` with a non-null fallback.

### Reading gaps

- The AI/ML Phase B reply read the Phase A files as the Phase B digest summarized them (its file says so). Its positions match its own Phase A file. The Phase C voters read every file in full.
- Q5 flipped between Phase C (B 4-2) and Phase D (A 6-0) on one fact that the moderator surfaced: the Sign law already in the Laws list. The fact is accurate (*Built-in Float Methods*). The swing came from that fact, not from a seat.
- Writer conditions for the bits law, from Phase D: one line, no field widths, no `0x` patterns, worded for both widths.
- Open points for the implementer: the built-in `is_nan` is not yet implemented, so the three methods land in one slice. Tests: NaN, both infinities, `0.0`, `-0.0`, a subnormal and the largest finite value, checked against `to_bits`, and `Float.INF.display()`.
- The Phase A guard examples used `String` and `json.stringify(x)`. Phase B corrected them to `Str` and `json.encode(x)`.

