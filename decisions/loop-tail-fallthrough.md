[< All Decisions](../DECISIONS.md)

# Loop-Tail Fall-Through in Value-Returning Functions — Design Rationale

## The gap

A value-returning `fn -> T` whose tail is a loop that can complete normally passed the
declared-return check, then fell off the end of the emitted C function and returned
whatever sat in the return register — stack garbage. `blink check` said OK; `blink run`
printed garbage.

```blink
fn h(n: Int) -> Int {
    while n > 0 {
        if n > 0 { return 7 }
    }
}
// h(0) prints 94068637258176
```

The same shape held for `for i in [1,2] { return ... }` (an iterable can exhaust) and any
`loop`/`while true` a `break` targets. §2.11 stated loop semantics but said nothing about
falling off the end of a value-returning function, and `tests/test_loop_return_type.bl`
had *asserted since 2026-03-27* that this shape was accepted. Each candidate answer changed
the language, so it went to the panel.

Three answers were on the record as background (not offered to the panel as an option
list): **(a)** reject unless the loop provably diverges; **(b)** accept + emit a
fall-through panic; **(c)** accept + zero-init the return.

## Already-decided constraints the panel respected

- **Under-determined types are a hard error E0301 — no silent default, no surface
  `unknown`** (`8vcj2c`, 6-0). Bars (c): a zero-init return fabricates a value the program
  never wrote.
- **`panic()` → `Never`**, untracked divergence, test runner catches / production
  terminates (5-0). Bears on (b).
- **Loops are statements, evaluate to `()`; no break-with-value, no labeled break, no
  while-let** (`while-loop.md`, §2.11). Bounds the shape of any fix.

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated
in independent-proposal → dedupe → debate → vote rounds.

#### Phase A — Independent proposals / Phase B — Debate

Independent proposals converged on a single mechanism rather than the three recorded
candidates: type a loop as `Never` when it provably diverges, else `()`; delete the
bespoke return-scan (`infer_loop_return_type`); and let the ordinary declared-return
subtyping compare fire (`typeof(tail) <: R`, with `Never <: R`). Phase A.5 dedupe plus
open debate refined the remaining disagreements into five voting questions: the disposition
(reject vs accept-and-fabricate), the scope of the rule (general vs loop-only), the
diagnostic (reuse the existing mismatch code vs a dedicated one), a codegen hardening rider,
and the treatment of `while true`.

#### Phase C — Final vote

**Q1 — Disposition: A (static reject), 6-0.**

- **Minimalism:** *"This is the rare deliberation where the correct answer shrinks the
  language — the fix deletes the bespoke return-scan and lets an existing type compare fire,
  with zero runtime machinery. B and C both fabricate a value the program never wrote and
  collide with settled decisions (5-0 panic->Never, 6-0 E0301). Reject is subtraction of a
  wrong acceptance, not an addition."* Concern: *"A is only as sound as the divergence check;
  a false 'diverges' lets a program fall through, which is why the Q4 backstop matters."*
- **AI/ML:** *"A compile-time error is the only disposition that lets a model self-correct at
  generation time; B defers the latent bug to a runtime panic on the not-found path, far from
  the cause, and C returns a value the program never wrote. Since this codebase is training
  data, accepting the incomplete idiom would teach the model the bare form is correct."*
- **DevOps:** *"A static error at `blink check` is the only answer the LSP can surface as a
  red squiggle before the code ships, and it's the only one that gives a machine-applicable
  quick-fix (insert `panic(...)`, which always compiles). B and C both push the failure past
  the checker into runtime."*
- **Systems, Web, PLT:** A.

**Q2 — Scope: GENERAL body-completeness rule, 6-0.**

- **Minimalism:** *"NARROW saves no machinery — same divergence analysis, applied only to
  loop tails, leaving `if`-without-else and partial-`match` tails as live holes that each
  become a future ticket. One subtyping rule (tail <: R, Never <: R) covers every construct
  and lets us delete infer_loop_return_type outright."*
- **AI/ML:** *"Generation reliability scales with rule COUNT, not generality — one
  body-completeness rule is fewer decision points than a loop-specific carve-out the model
  must remember is special, and it reuses the exhaustiveness intuition already applied to
  `match`/`if`-without-else."* Concern: *"One rule over all tail kinds risks a diagnostic too
  generic to name the loop, which is why I pair it with Q3=NEW."*
- **DevOps:** *"One reachability rule yields one error code and one quick-fix family for
  every 'control reaches the end without a value' shape — loop, `if`-without-else, partial
  `match`. A narrow rule leaves the other tails emitting garbage or a worse error later."*
- **Systems, Web, PLT:** GENERAL.

**Q3 — Diagnostic: 3-3 tie (REUSE: sys, plt, min · NEW: web, devops, aiml) → Phase D.**

See Phase D below for the resolved vote and full rebuttals.

**Q4 — Codegen rider: YES (`__builtin_unreachable()` + debug ICE backstop), 6-0.**

- **Minimalism:** *"`__builtin_unreachable()` in release plus a debug-only ICE assert is
  invisible codegen — it spends none of the language-surface budget I guard, and it is cheap
  insurance on the exact soundness edge Q1's concern names. It turns 'silent stack garbage if
  the analysis is ever wrong' into 'loud ICE in debug.'"* Concern: *"The debug backstop must
  stay an ICE/assert and never a release runtime panic, or it quietly becomes option (b)
  through the back door."*
- **DevOps:** *"`__builtin_unreachable()` after a provably-diverging tail is a free release
  optimization, and the debug-only ICE backstop gives a labeled crash if our divergence
  analysis is ever wrong."* Concern: *"If the divergence analysis has a bug,
  `__builtin_unreachable()` in release turns it into UB rather than a clean error — so the
  debug backstop must be real and actually exercised, not nominal."*
- **AI/ML:** *"Orthogonal to the typing rule and pure upside — guarantees we never regress to
  stack garbage even under a future analysis hole, without weakening the static contract or
  letting an incomplete program pass `check`."*
- **Systems, Web, PLT:** YES.

**Q5 — `while true`: LOOP-ONLY, 5-1 (DevOps dissent).**

- **AI/ML:** *"'Only `loop {}` diverges; every `while`/`for` can finish' is a bright line
  statable from spec alone; typing `while true` as `Never` forces an unanswerable question
  about how far the analysis folds the condition (`true` only? `while 1 < 2`?). The linter
  already redirects `while true`→`loop`, where it works."*
- **Minimalism:** *"`loop` is already THE canonical diverging form and §2.11's linter already
  auto-fixes `while true` -> `loop`, so blessing `while true` adds a second spelling the
  analysis must recognize while undercutting the linter's own canonicalization. A user who
  writes a divergent `while true` tail gets auto-migrated and then accepted, so rejecting it
  costs them nothing."*
- **DevOps:** *(dissent)* *"A `while true {}` with no reachable break genuinely never exits —
  it IS `Never` — and rejecting a function that provably diverges is a false positive, the
  cardinal sin in my domain. Type soundness and style belong in separate layers: the checker
  folds the literal `true` (bounded — §2.11 already bans `while 1`), and the existing §2.11
  lint independently nudges `while true`→`loop`."* Concern: *"It asks the type checker to
  constant-fold one condition form, and someone could later expect that folding to extend to
  `while 1 < 2`, which it must not."*
- **Systems, Web, PLT:** LOOP-ONLY.

#### Phase D — Round 2 (Q3 only, tie-break)

Q3 tied 3-3 in Phase C, triggering one focused debate round. Both camps agreed the
mechanism is the `()`-vs-`R` subtyping compare and both ship a tailored help line; the only
split was whether the diagnostic gets a **NEW** dedicated code or **REUSE**s the existing
mismatch code.

- **Systems:** *"the causal chain and the fix live in the tailored help line, which both
  camps are shipping — and that help hangs off the reused code identically, so a dedicated
  code buys only a stable machine key, not one extra word of explanation. An LSP quick-fix or
  a model can key on the code plus a structured sub-diagnostic tag ('tail-kind: loop')
  without minting a new top-level code ... The one place NEW genuinely wins — a distinct
  machine key — is real but modest, and does not outweigh that error codes are permanent
  contract surface. FINAL VOTE: REUSE."* *(dissent)*
- **PLT:** *"a quick-fix can key on the structured `(mismatch-code, found=(), tail-kind)`
  triple, and the tailored help line carries 'add a trailing `return <Int>`' identically
  under either option, so the dedicated code buys tooling nothing ... What a new code *does*
  buy is permanent public surface asserting this is a distinct KIND of error, when the theory
  says it is one instance of the ordinary `()`-vs-`R` mismatch — minting a category for a
  non-category is the anti-compositional move I want to avoid. FINAL Q3 vote: REUSE."*
  *(dissent)*
- **Web:** *"The permanence cuts the other way — a stable code is exactly what an LSP
  quick-fix and an AI one-shot repair key on, so the code IS the durable interface, not dead
  surface. And 'Rust does this' is the wrong bar for an AI-first language ... 'found `()`' at
  a brace where the dev wrote no `()` fails the 5-minute test no matter how good the help
  line is, because the headline still names a cause the user never created. FINAL VOTE:
  NEW."*
- **DevOps:** *"permanence is exactly why this needs its own code — a code is the stable
  machine key that a quick-fix, an LSP filter, and any future suppression bind to, and help
  text carries none of that. Folding this into the generic mismatch code means no tool can
  tell 'you returned a String where Int was declared' apart from 'your loop can fall
  through' ... 'Buys no soundness' is the wrong yardstick: error codes exist for
  diagnosability and tooling, not soundness — by that test we'd have one code for
  everything. FINAL VOTE: NEW."*
- **AI/ML:** *"soundness isn't the axis — machine-actionability is. A stable dedicated code
  is exactly the durable, keyable anchor an LSP quick-fix and a model's error-pattern matcher
  latch onto; 'expected `R`, found `()`' collides with every genuine unit mismatch (a `()`
  tail expr, a misassigned statement), so no tool can tell 'you forgot a return' from 'you
  wrote the wrong expression' without re-parsing prose that the REUSE camp itself admits must
  carry the real explanation. FINAL VOTE: NEW."*
- **Minimalism:** *(flipped REUSE → NEW, breaking the tie)* *"My own REUSE ballot already
  conceded 'the help line must carry the real explanation' — that is an admission the generic
  mismatch code is inadequate alone and I was leaning on help text to rescue it. If tailored
  help is present either way, the only live question is whether the diagnostic has a stable
  identity a tool can key on ... I was guarding the wrong budget — a single error code that
  fires on one structural condition (tail cannot complete with R) is a non-interacting
  diagnostic leaf, not the conceptual/language surface Min actually protects; it composes
  with nothing, so its cost is near-zero, while the fix-loop benefit is real. FINAL VOTE:
  NEW. ONE Min constraint on my yes: exactly ONE new code keyed on the completeness
  condition, with tail-kind carried as help-text/quick-fix DATA — not a family
  (MissingReturnLoop / MissingReturnIf / ...)."*

**Q3 resolved 4-2 for NEW** (dissent: Systems, PLT), with Minimalism's constraint carried
into the spec and the implementation ticket: exactly **one** code (`MissingReturn`, E0311),
tail-kind as structured diagnostic data, not a per-tail-kind family.

### Final Spec

- **Disposition (Q1, 6-0):** a value-returning `fn -> R` whose body can complete normally
  with `()` is a compile-time error, never accepted-and-fabricated.
- **Mechanism / scope (Q2, 6-0):** one body-completeness rule. A block in value position has
  a *tail type*; the body type-checks only when `tail <: R`. `Never <: R` for all `R`; `()`
  is a subtype only of `()`. The bespoke loop return-scan is deleted. Covers loop,
  `if`-without-`else`, and completing-arm tails uniformly. (§3.3)
- **Divergence (Q5, 5-1):** a construct is `Never` only when it provably diverges — `panic`/
  `env.exit`, a tail `return`/`?`/`break`/`continue`, an `if`/`match` whose reachable arms
  all diverge, or a `loop {}` no `break` targets. `while`/`for` are always `()`; `while true`
  is not special (no condition-folding) — the linter bridges it to `loop`. The break-target
  search does not descend nested loops or closures. (§2.11)
- **Diagnostic (Q3, 4-2 after tie-break):** one dedicated code
  `error[MissingReturn]` (E0311); the headline names the cause, tail-kind is structured data,
  the first-named repair (trailing `return`/value, or `Option[R]` + `None`) always compiles.
  (§3.3, ERROR_CATALOG)
- **Codegen rider (Q4, 6-0):** after a provably-diverging accepted tail, emit
  `__builtin_unreachable()` in release plus a debug-only ICE backstop — never a release
  runtime panic.
