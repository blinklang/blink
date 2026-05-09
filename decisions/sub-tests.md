[< All Decisions](../DECISIONS.md)

# Sub-tests / `subtest` — Design Rationale

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated br task **9pjamr** ("Spec: sub-tests builtin / subtest()") in independent-proposal → debate → vote rounds.

#### Phase A — Independent proposals

- **Systems:** Compiler builtin `subtest "label" { }` recognized by parser, lowered to a runtime call that opens a per-subtest reporting frame. Zero closure capture, no heap promotion of mutable parent locals (e.g., a `let p = Parser.new()` reused across cases), and parse-time literal labels enable static enumerability for IDE test gutters and CI shard planning. Initially proposed siblings-continue via a second `setjmp` at `subtest_enter`; *withdrew this in Phase B Round 1 on soundness grounds* — it would force `panic` to be user-resumable inside test blocks, contradicting §2.20 / §4.6.3.
- **Web/Scripting:** Stdlib HOF `testing.subtest(label: Str, body: fn() -> Void)`. Familiar from Go `t.Run`, pytest `subtests`, Jest `describe.each`. Ships in days; no compiler work. Pivoted halfway through Phase B once the moderator confirmed `lib/std/testing.bl:66` drops the `_label` — the actual user pain is a `for_each` reporter bug, not missing language surface.
- **PLT:** Reject. No proposal in the option-space adds expressivity that `for_each` plus N flat `test` blocks doesn't already cover. Both B and C duplicate that expressivity behind a label-shaped sugar — Principle 2 violation absent a soundness or compositional gain. Keep `panic` as untracked divergence with a single catch frame; preserve the typing rule and leave the algebraic-effects door open for the deferred recoverable-panic ticket if real signal arrives.
- **DevOps:** Two-tier proposal — P1 (preferred): reject `subtest`, fix `for_each` label propagation, runner emits per-iteration NDJSON `case` records (parent + case fields, stable `parent/case` identifier for `--rerun-failed`). P2 (fallback): if panel insists on shipping something, compiler builtin with 11 hard constraints (statement-only, literal label, flat-only, stop-on-first failure, no nesting, no conditional `subtest`, no expression-position, NDJSON `case` records, `--collect-only` lists labels, runtime label-uniqueness, `BlockHandler.exit(false)` runs at subtest boundary).
- **AI/ML:** Reject. Every primitive added to the test toolbox multiplies the LLM's per-test decision cost forever; runner-side label plumbing adds zero decision points. Keep the spec to a 2-node decision tree (`test` for heterogeneous, `for_each` for parametrized). Training-data priors pull hard toward Jest-shaped `describe`/`subtest` whenever such a symbol exists; preserving "spec-reading-as-fallback" is the highest-quality LLM behavior we can engineer for. Also flagged the `_label` drop at `lib/std/testing.bl:66` as the load-bearing bug.
- **Minimalism:** Reject. Burden of proof for new language surface was not met — no usage signal cited, the 9pjamr ticket itself says "defer until usage signal emerges." With V2 fixed, `for_each` covers homogeneous parametric cases; multiple `test` blocks + helper `fn`s cover heterogeneous scenarios. Adding B is redundant once V2 lands; adding C imports a new statement form for a problem the existing surface already solves.

#### Phase A.5 — Mechanical dedupe

Three primary options:
- **A:** Reject builtin/HOF; document `for_each` + multiple `test` blocks + helper `fn` as the canonical patterns in §2.20.
- **B:** Stdlib HOF `testing.subtest(label, fn)` (flat-only, stop-on-first, runtime label check).
- **C:** Compiler builtin `subtest "label" { }` (devops's 11 constraints, OR sys's siblings-continue variant).

Five flagged variations: V1 sibling failure semantics (stop-on-first vs continue), V2 `for_each` label propagation fix at `lib/std/testing.bl:66` (in-scope vs sibling-task), V3 `--collect-only` static enumerability (required vs punt), V4 nesting (allowed vs flat-only), V5 label uniqueness (compile-time vs runtime).

#### Phase B — Debate highlights

**Sys conceded V1 (siblings-continue) on soundness grounds, withdrawing the second-`setjmp` proposal.** Quoting plt's pushback that swung the concession:

> *(plt)* "If `subtest_enter` installs a second `setjmp`, the observable surface-language behavior is: code *after* an `assert` failure inside `subtest` *runs*. That is not 'the same panic semantics with a sneakier longjmp target.' That is, by definition, a second catch site for `panic` in the source language. It doesn't matter that the `setjmp` is in the runner's generated wrapper rather than user code; from the user's perspective, `panic` no longer means 'this function does not return.' It means 'this function does not return *unless* you're lexically inside a `subtest`.' That is a new typing/effect rule whether we write it down or not."

**Web pivoted off Option B once the moderator confirmed `lib/std/testing.bl:66` drops `_label`:**

> *(web)* "If the for_each-reporter is *already* the right answer for partial-failure attribution and just buggy, then I'm dragging Option B uphill for marginal value. I'd rather we ship one boring fix to `for_each` and call 9pjamr resolved than ship a new primitive to paper over the bug."

**Devops moved off P2/Option C entirely after sys's withdrawal:**

> *(devops)* "The moment sys claimed siblings-continue via a second setjmp, P2 stopped being the 'neutered, predictable' thing I was willing to defend. C as actually proposed is a recoverable-panic Trojan horse, and I will not co-sign that. Every NDJSON consumer downstream has to model a new state: 'test is failed, but more case records are still streaming.' Today's invariant is 'once a test record goes `fail`, the next record belongs to a different test.' Breaking that invariant breaks every CI dashboard, every `--rerun-failed` implementation, every editor test-output panel."

**Aiml's training-data point on why even the HOF surrenders the spec-reading prior:**

> *(aiml)* "Models have seen orders of magnitude more `describe`/`it`/`t.Run`/`subTest` code than they've seen `for_each`-style parametrization. If we ship *anything* called `subtest`, the prior pulls strongly toward Jest-shaped code. If we ship only `for_each` + N tests, the prior has nothing to grab and the model falls back to reading our spec. Spec-reading-as-fallback is the highest-quality LLM behavior we can engineer for. A preserves it; B and C surrender it."

**Min on V2 being load-bearing:**

> *(min)* "The destructured-but-unused `_label` at `lib/std/testing.bl:66` is a *bug*, not a design question, and fixing it is what makes A actually cover the design space. If we ship A without V2, we leave a real gap. If we ship A *with* V2, B becomes redundant."

**Sys's final stable position (post-concession):** holding Option C with devops's 11 constraints, no siblings-continue, on the strength of zero-cost lowering and parse-time static enumerability. Acknowledged: "If we ever want recoverable panics or test parallelism later, retrofitting siblings-continue onto the existing stop-on-first lowering is a real spec change, not a runtime tweak."

Termination: 6 of 6 stable signals after Round 1. Phase C silent vote.

#### Phase C — Final vote

**Q1 — Primary resolution: A wins 5-1.**

- **Web:** A — *"A JS/Python dev's mental model fits in one sentence today: 'write `test \"name\" { ... }`, use `for_each` for parametric cases, extract helpers for shared setup.' Adding a third primitive (HOF or builtin) makes that sentence longer without unlocking a 90% case."*
- **PLT:** A — *"No proposal in the space added expressivity that `for_each` plus N flat `test` blocks doesn't already provide. Both B and C duplicate that expressivity behind a label-shaped sugar — Principle 2 violation absent a soundness or compositional gain. The only candidate justification (siblings-continue) was withdrawn on soundness grounds, which removes the only thing C could do that A cannot."*
- **DevOps:** A — *"The actual user pain in 9pjamr is partial-failure attribution, not missing syntax — and that's a runner/reporter bug, not a language gap. Adding compiler surface (C) or stdlib symbol (B) for a problem that fixes in ~5 lines at `lib/std/testing.bl:66` is bad cost/benefit, and every new test-related construct is one more thing the LSP, formatter, and `--filter` parser have to learn forever."*
- **AI/ML:** A — *"From an LLM-codegen standpoint, the primitive count in the test toolbox is the dominant cost driver — every additional way to express 'run N similar checks' multiplies the per-test decision burden forever, and training-data priors pull hard toward Jest-shaped `subtest`/`describe` whenever such a symbol exists."*
- **Minimalism:** A — *"The ticket itself says 'defer until usage signal emerges,' and no usage signal has been cited in either phase. With V2 fixed, `for_each` covers homogeneous parameterized cases with full label attribution; multiple `test` blocks + helper `fn` covers heterogeneous scenarios and shared setup. Burden of proof for new language surface was not met."*
- **Systems:** *(dissent)* C with devops's 11 constraints — *"The compiler-lowered block is the only shape that gives zero-cost lowering (no closure, no capture analysis, no heap-promotion of mutable parent locals like a `let p = Parser.new()` reused across cases) while preserving static enumerability for tooling. Option B's HOF forces capture analysis on every body and gives up parse-time information we already have for free."* Concern: *"If we ever want recoverable panics or test parallelism later, retrofitting siblings-continue onto the existing stop-on-first lowering is a real spec change, not a runtime tweak."*

**Q2 — V2 (`for_each` label propagation fix at `lib/std/testing.bl:66`): in-scope wins 5-1.**

- **Web:** in-scope — *"If we ship Option A and tell users 'use `for_each` with labeled cases for parametric tests,' that advice is misleading until the label actually shows up in failure output. Splitting it off as a sibling ticket means we ship the documentation before the fix — guaranteed DX papercut."*
- **PLT:** in-scope — *"The br task itself frames `for_each` as the alternative that 'now ships' — the entire premise of deferring 9pjamr was that `for_each` covers the use case. Resolving 9pjamr as 'rejected, use `for_each`' while `for_each` itself is silently broken on labels closes the ticket on a false premise."*
- **DevOps:** in-scope — *"The label drop at `lib/std/testing.bl:66` is *the* spec gap behind 9pjamr — closing this ticket without fixing it means we re-litigate in three months when someone files 'subtest labels still missing.'"*
- **AI/ML:** in-scope — *"The br-9pjamr text reads 'richer reporting / partial failure attribution' — that's literally what the label-propagation fix delivers. Bundling the ~5-line fix with the §2.20 doc update is the only way Option A is honestly responsive to the original ask."*
- **Minimalism:** in-scope — *"The destructured-but-unused `_label` at `lib/std/testing.bl:66` is a bug, not a design question, and it is the load-bearing piece that makes A actually cover the design space. Shipping A's spec convention without V2 is shipping a half-solution."*
- **Systems:** *(dissent)* sibling-task — *"The `let (_label, _value)` drop at `lib/std/testing.bl:66` is a one-line bug with a trivial MVCE — file as `type:bug` with the unused-label repro and let it land independently. Bundling a stdlib bug fix with a spec-decision ticket muddies the decisions/ record and ties the bug fix's release cadence to whatever the subtest implementation timeline turns out to be."*

**Q3 — V3 (`--collect-only` static enumerability): punt wins 5-1.**

- **Web:** punt — *"pytest and Go both punt on static enumeration of dynamic cases and the world hasn't ended — IDE test trees just refresh after first run, which is fine. Making this a resolution requirement would push us toward the builtin (Option C) for tooling reasons that aren't load-bearing in 2026 toolchains."*
- **PLT:** punt — *"Static enumerability is only 'required' if we accept a compiler builtin; under Option A there is nothing to enumerate that the runner doesn't already enumerate at first-run time. pytest/Go precedent shows the world is fine with first-run discovery for dynamic cases, and tying spec resolution to a tooling-shaped requirement would be a tail-wags-dog move."*
- **DevOps:** punt — *"I conceded this in Phase B Round 1 and the position holds — Go and pytest both punt on dynamic case enumeration and the CI-tooling ecosystem handles `has_dynamic_cases: true` fine. Requiring static enumerability would force us into Option C with literal-label-only constraints, which the panel rejected on minimalism/cost grounds."*
- **AI/ML:** punt — *"Pytest and Go both ship without static enumeration of dynamic cases and the tooling ecosystem absorbed it without drama — IDE test-trees refresh after first run, CI shard planners use last-run timings. Making `--collect-only` a hard requirement is the single strongest argument for Option C, and conceding it now is what lets A win cleanly."*
- **Minimalism:** punt — *"pytest and Go both accept dynamic enumeration with no observed user pain; the precedent is clear. Static enumerability would only matter if it forced us into a builtin (C), and we are not choosing C."*
- **Systems:** *(dissent)* required — *"Static enumerability is the load-bearing reason to choose C over B at all — if we punt it, the whole codegen argument collapses. We're a self-hosted compiler emitting C; we have parse-time access to every literal subtest label, and voluntarily throwing that away to mirror dynamic-language precedent (pytest/Go) is exactly the kind of 'what does the hardware see' regression I'm here to push back on."*

#### Phase D — not triggered

All three results were 5-1; the dissenter (sys) consistently held the same position across questions, and the majority's Concern fields did not endorse the dissent on Q1 or Q3. Q2 has soft consensus on intent (everyone wants the fix) with disagreement only on bundling vs sibling-task release cadence — not a substantive split.

### Final Spec

```blink
test "add handles signs" {
    testing.for_each([
        ("zero",     (0, 0, 0)),
        ("positive", (1, 2, 3)),
        ("negative", (-1, -2, -3)),
    ], fn(case) {
        let (a, b, expected) = case
        assert_eq(add(a, b), expected, "case {label}")
    })
}

fn fresh_parser() -> Parser {
    Parser.new(default_config())
}

test "parser handles empty input" {
    let p = fresh_parser()
    assert_eq(p.parse(""), Ok([]))
}

test "parser handles whitespace-only input" {
    let p = fresh_parser()
    assert_eq(p.parse("   \n\t"), Ok([]))
}
```

Locked design points:

- **No `subtest` primitive in v1** — neither compiler block nor stdlib HOF.
- **Three canonical patterns documented in §2.20**: `for_each` for homogeneous parametric cases, multiple flat `test` blocks + helper `fn` for heterogeneous phases, `with` handlers for shared effectful resources.
- **`for_each` gains runtime label-uniqueness enforcement** at `lib/std/testing.bl`. Duplicate labels panic with `for_each: duplicate case label "<label>" at indices <j> and <i>`.
- **Per-iteration NDJSON `case` records and full label-prefixed failure output** are deferred to a follow-up `type:bug` against the runner/reporter — the runtime-state plumbing in `bootstrap/runtime_test.h` is out of scope for spec resolution.
- **`--collect-only` static enumerability deferred** pending usage signal. `--enumerate-cases` opt-in (run bodies with no-op assertion handlers) is a follow-up `type:spec` if real demand emerges.
- **Re-evaluation gate:** any future proposal to add a `subtest` primitive must demonstrate (a) that the §2.20 patterns provably do not cover a real, evidenced use case, and (b) that the proposed shape does not require recoverable-panic semantics that would have to clear the §4.6.3 / `BlockHandler` catchable-unwind fence first.
