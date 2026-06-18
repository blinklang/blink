[< All Decisions](../DECISIONS.md)

# Enums Nominally Distinct from `Int` — Design Rationale

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated
in independent-proposal → debate → vote rounds. The gap (br `dhggkg`): Blink's typechecker
enforced **no** nominal distinctness between enums and `Int` — `let n: Int = some_enum`,
`takes_enum_param(22)`, and `match some_int { Variant(x) => }` all typechecked clean for every
enum. Root cause was a deliberate rule in `src/typecheck.bl` (`types_compatible`):

```
// Enums are tag-ints at runtime — Int and Enum are compatible
if (ka == TK_INT && kb == TK_ENUM) || (ka == TK_ENUM && kb == TK_INT) { return 1 }
```

The downstream `Errno(Int)` newtype (br `ja9jev`, `decisions/libc-bytes-wrapper-coverage.md` Q3)
requires nominal distinctness from `Int` to be meaningful — that guarantee held for no enum.

**Four codebase facts were verified by the moderator and surfaced to the panel:**
- **F1** Comparison ops short-circuit to `TYPE_BOOL` at `typecheck.bl:5190` *before* any
  `types_compatible` call — so `node_kind(x) == NodeKind.IntLit` is unaffected by the rule.
- **F2** Struct-literal field values are name-resolved only (`typecheck.bl:4716-4724`), with no
  value-vs-field-type check — so `AstNode { kind: NodeKind.X }` (the compiler's storage pattern)
  does not route through `types_compatible`.
- **F3 (measured)** Removing the rule and running `task regen` broke exactly **16 sites**, all in
  compiler source: 13× `new_node(NodeKind.X)` (enum→Int arg), 1× `_last_kind: TokenKind = -1`
  (Int→enum sentinel), 2× `peek_kind`/`peek_kind_at` (enum/Int return). Storage and comparison: 0.
- **F4** The only `match`-on-Int-with-enum-patterns self-host site is `ast.bl:105`
  `node_kind_name(kind: Int)`.

#### Phase A — Independent proposals

- **Systems:** "enums are literally `int` at the C level … 'Nominal distinctness from Int' therefore CANNOT mean a representation change. It is a *frontend-only* constraint." Proposed S2: make `Errno` a transparent struct newtype reusing the Instant/UUID/sized-int pattern (`types_compatible` already returns 0 for struct-vs-Int), no enum-rule change; S1 (direction-split) as fallback.
- **Web/Scripting:** "today's behavior is surprising in the direction that matters: it's *more* permissive than every language a scripting dev knows." W1: reject Int→enum, keep enum→Int. W2 (preferred at first): an opt-in `@transparent` marker — "a TS branded-type / Kotlin `value class` / Rust newtype, not an enum question." Resisted any `as` cast since "Blink has none — conversions must stay method-named."
- **PLT:** distinguished three independently-controllable judgments — assignability, equality/ordering, match-scrutinee well-typedness. P1: "delete the assignability carve-out … let it fall to `ka == kb` … This makes `Int` and any enum nominally distinct at assignability, exactly mirroring the sized-int branch one line above (4965)." P2 fallback: directional. Surfaced Finding 3 (struct-literal fields unchecked).
- **DevOps/Tooling:** "Permissiveness is real and SILENT today … The model already exists" (sized-int↔Int via E0300). Proposed a staged warning-first migration (W-warning → explicit cast → flip to E0300) and an `as` cast escape hatch. "nominal distinctness is what *creates* the autocomplete opportunity."
- **AI/ML:** narrow enforcement at let/arg, keep `==`. "An AI builds a mental model from what the compiler accepts." Rejected type-name-distinctness-only as "a semantic lie an LLM would find confusing." Required a diagnostic that names both types and points at the escape hatch.
- **Minimalism:** "163 `node_kind(x) == NodeKind.Y` sites … the compiler only relies on the **tag-only** case." Proposed B: narrow the rule to tag-only enums (payload-carrying ⇒ distinct) for zero migration; P2 fallback: do nothing, rely on type-name distinctness.

#### Phase B — Debate highlights

Once **F1–F3** were verified, the panel converged hard on PLT's Option **A** (delete the carve-out):

- **Systems** withdrew S2 and C: *"FACT 3 proves that [self-host] hedge is unnecessary: the breakage is 8 lines [later measured 16] … My Phase-B argument for C was: 'the compiler only ever uses the benign enum→Int widening direction.' FACT 3 proves that's false. The compiler uses Int→enum too — 3 sites. C does NOT actually achieve zero-migration … A wins on every axis."*
- **Web** moved off W2: *"Shipping an opt-in `@transparent` marker now would mean teaching users a new annotation to get the behavior they *already expect by default* … A deletes surface instead of adding it. This is the rare breaking change that makes the language *more* familiar."*
- **AI/ML** on A-vs-B: *"A is a FLAT rule. B is a SECOND-ORDER rule. That difference is the whole ballgame for an AI … B makes interconvertibility depend on an *invisible structural property of the enum's declaration*."*
- **PLT** rejected B on soundness: *"B makes nominal distinctness from `Int` depend on whether an enum *carries a payload* … It is not stable under refactoring — the cardinal sin. Add one payload variant to a previously tag-only enum and every `let n: Int = e` site silently changes typeability."*
- **DevOps** withdrew the warning ladder: *"With zero external dependents … the warning phase is machinery solving a problem that won't exist until v1+. That is the exact YAGNI I'd flag if someone else proposed it."* and conceded `as`: *"FACT 3 confirms we don't even need a crossing idiom for the compiler's own code."*
- **Minimalism** conceded A > B: *"I was optimizing for migration cost, not conceptual cost — and I had it backwards … A deletes a rule and adds nothing. B replaces one rule with a shape-conditional rule."*

#### Phase C — Final vote

- **Q1: the rule — A (6-0).** Delete the enum/Int assignability carve-out; enums nominally distinct from `Int` at let/arg/return; comparison stays legal; fix the 16 compiler-source sites in-PR; hard-flip migration (no warning phase).
  - **Systems:** A — *"deleting a carve-out and reusing the existing branch is lower complexity than adding directional logic."*
  - **Web:** A — *"'An enum is not a number' is the one-sentence rule a Python/JS/TS dev carries in from day one."*
  - **PLT:** A — *"the only option that states the actual property … without a representational caveat … It's monotone (B is not)."*
  - **DevOps:** A — *"reuses the existing E0300 render path … B is the worst diagnostic surface of the field — legality … depending on a sibling variant's payload is non-local and unteachable."*
  - **AI/ML:** A — *"one flat use-site predicate … generalizes the existing sized-int rule rather than adding a new category — negative marginal complexity."*
  - **Minimalism:** A — *"one uniform sentence … identical in shape to the sized-int rule (4965). The 16 sites are debt PAYDOWN, not debt."*

- **Q2: match-scrutinee enforcement timing — STAGED (5-1; PLT dissent → NOW).** The match-scrutinee distinctness rule is in the spec text now; *enforcement* is a dep-linked follow-up gated on the `kind:Int → NodeKind` migration.
  - **STAGED — DevOps:** *"NOW isn't a half-fix-versus-full-fix preference call — it is technically BLOCKED until the kind:Int→NodeKind migration retypes these scrutinees [ast.bl:105]. Shipping a rule the compiler can't itself obey is the worse diagnostic outcome."*
  - **STAGED — Minimalism:** *"shipping NOW either breaks self-host or forces us to drag the entire kind:Int→NodeKind migration into THIS PR — exactly the unbounded scope-creep the subtraction lens rejects."*
  - **STAGED — AI/ML:** *"the spec TEXT documents distinctness across all three faces NOW, so an AI learns one coherent rule today; only the match-FACE enforcement is sequenced behind the migration."*
  - **STAGED — Systems / Web:** Systems: *"that one function is load-bearing in the worst way … The clean fix … cascades into [node_kind's] hundreds of call sites. That IS the kind:Int→NodeKind migration."* Web conceded to F4.
  - *(dissent)* **PLT — NOW:** *"I was WRONG on feasibility … NOW is feasible in this PR … the self-host blast radius of match-scrutinee-NOW is a **single function** [`node_kind_name`], and the fix is the exact same one-line signature tightening already in Q1's 16-site batch … the three faces should ship as one coherent rule."* (PLT logged a caveat that a trial regen should confirm the single-site count.)

- **Q3: Errno shape — ENUM (6-0).** Keep `Errno(Int)` (positional payload, br `9g2p3j`); reject the struct-newtype workaround.
  - **PLT:** *"Struct (D) … is a *non-answer to dhggkg*: it sidesteps the spec gap and leaves every other enum still Int-compatible."* All six concurred; AI/ML: *"fix the general rule so it's honest for everyone."*

#### Phase D — Round 2 (Q2 only, triggered by the 3-3 Phase-C split)

The moderator surfaced **F4** (`ast.bl:105`). Five panelists confirmed/moved to STAGED on feasibility
grounds; **PLT** verified the site count and flipped the *other* way to NOW, arguing the single
site is fixable by Q1-style signature-tightening without the migration. Final Q2: **STAGED 5-1**.

> Implementation postscript (not part of the vote): the moderator applied the three Q1 signature
> fixes (`new_node(kind: NodeKind)`, `Token.kind: TokenKind`, `_last_kind` sentinel) and `task regen`
> reached a clean Gen1==Gen2 fixed point with **0** residual errors — confirming PLT's "contained"
> read of the *implementation*, while the STAGED *decision* stands (match-scrutinee is a separate
> enforcement path regardless, and the spec text is identical either way).

### Final Spec

Recorded in `sections/03_types.md` (*Enums Are Nominally Distinct from `Int`*):

```blink
type State { Idle, Running, Done }
fn step(s: State) -> State { s }

let n: Int = State.Idle   // error[TypeError]: declared type Int but got State
let bad = step(2)         // error[TypeError]: argument 1 expects State, got Int
let s: State = 7          // error[TypeError]: declared type State but got Int

let x = State.Running
if x == State.Running { } // OK — comparison compares the shared tag, yields Bool
```

Locked design points:

- **Enums are nominally distinct from `Int`** at let-binding, function argument, and function
  return — `types_compatible(INT, ENUM)` falls through to `ka == kb` → 0, mirroring the sized-int
  rule. No implicit coercion either direction.
- **Comparison is unaffected** (`==`/`!=`/`<`…): it short-circuits to `Bool` before
  `types_compatible`, comparing the shared tag representation. This is representation-level, not
  an assignability claim.
- **Explicit conversion only:** `Enum.to_int()` (total) and `Enum.from_int(n) -> Option[Enum]`
  (fallible). **No `as` cast operator** is added.
- **Migration: hard-flip**, no deprecation phase — the 16 affected sites are all compiler-internal
  (no external user code relied on the permissiveness) and their fixes (`new_node`/`Token.kind`/
  `peek_kind` signature tightenings) advance the planned `kind:Int → NodeKind` migration.
- **Match-scrutinee enforcement** (`match someInt { Variant => }` ill-typed) is part of the rule
  but its *enforcement* is staged behind the `kind:Int → NodeKind` migration (br `qsb7ca` depends
  on br `0khtje`).
- **`Errno` stays an enum** `Errno(Int)` — nominally distinct for free under this rule.
- **Out of scope (separate ticket, br `x231pe`):** struct-literal field values are not type-checked
  against declared field types at all (a broader soundness hole surfaced as F2).
