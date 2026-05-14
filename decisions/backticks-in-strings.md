[< All Decisions](../DECISIONS.md)

# Backticks in String Literals — Design Rationale

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated
in independent-proposal → debate → vote rounds on whether markdown-style backticks inside
`"..."` strings should suppress interpolation parsing.

#### Phase A — Independent proposals

- **Systems:** "Reject the proposal. Status quo wins on Systems grounds... The string scanner is one of the hottest loops in the lexer. Adding a fourth delimiter character means either (a) another branch on every byte, or (b) carrying a `in_backtick_span: Bool` flag that gets consulted inside the `{` branch — which kills the run-batching optimization at `_run_start` because `{` is no longer always-special... For the rare case where a docstring/test name *really* wants pristine markdown, `#"..."#` already exists and already does exactly this." Recommended: **S1 — Reject, document `\{` and `#"..."#`**.

- **Web/Scripting:** "Reject backtick-as-suppressor. Document `#"..."#` as the answer, and improve the `\{` error message so the 90% case self-heals in ~30 seconds. Backticks earning lexer semantics is a footgun that will haunt every doc-string and test name forever... The bug today is that the user hits a parse error with no idea `\{` or `#"..."#` exist. That is the actual bug. Fix the diagnostic; the spec gap evaporates." Recommended: **Proposal A — Reject + better diagnostic**.

- **PLT:** "Reject. Don't make backticks a lexer-level interpolation suppressor. The right answer is already in the language: `#"..."#`. Adding context-sensitive backtick semantics to the *interpolation grammar* of `"..."` breaks compositionality, fights `Template[C]` decomposition, and buys you a markdown convention at the cost of a non-regular substring rule... A `Template[C]` is morally `(parts: [Str], holes: [C])`. The whole point is that holes are *syntactically* identified at lex time... If `{x}` inside `` `...` `` is suddenly *not* a hole, the template's `holes` array depends on prose content. That's exactly the bug class `Template[C]` was designed to eliminate." Recommended: **Option A — Reject + docs-only**.

- **DevOps/Tooling:** "Reject 'backticks suppress interpolation' inside `"..."`. Instead: (a) lint-nudge users toward `#"..."#` for the documented-code-in-string idiom, (b) add a focused diagnostic when `{` immediately follows a `` ` `` inside a `"..."` string, (c) leave the lexer state machine alone... A 'region inside a string is treated specially' is exactly the construct that bricks textmate-style highlighters... Today, a `"..."` token ends at the next unescaped `"` or `{`. With backtick-suppression, the lexer state at column N depends on whether an *odd* number of `` ` `` characters appeared before it. Typing one backtick re-lexes everything to the closing quote. This is the rust-analyzer 'why did my whole file go red' footgun." Recommended: **Proposal 1 — Diagnostic + lint, no lexer change** (β+γ combined).

- **AI/ML:** "REJECT. Keep `\{` as the single escape. Add lint + docs... The spec already says one thing — `"..."` interpolates, `\{` escapes. Adding '...except inside backticks' introduces a context-sensitive rule that an LLM cannot infer from the local token stream. It's the kind of rule humans absorb from markdown training data but that requires lookbehind to a paired delimiter to apply correctly. Token-position-dependent semantics with delimiter pairing is exactly the class of rule where AI codegen breaks down... An AI reading the spec sees backtick is 'not special' 99% of the time and 'deeply special' inside strings. That's the worst possible learnability profile." Recommended: **Option A — Reject + lint W0421 + docs** (γ).

- **Minimalism:** "Reject. Do nothing. Cost of adding backtick suppression: permanent. Every future reader of the lexer learns a new mode. Every formatter, syntax highlighter, LSP, doc generator, and AI training pipeline must model it... Cost of doing nothing: a backslash. `\{` already works... `#"..."#` already exists and is the documented escape hatch for 'I have a lot of braces and quotes.' That is *literally what it's for*. We have **two** mechanisms already (`\{` and `#"..."#`). Adding a third because someone wants markdown-flavored test descriptions is the definition of language-surface creep." Recommended: **M1 — Reject and close as wontfix**.

#### Phase A.5 — Mechanical dedupe

Q1 (suppression?) collapsed unanimously to **Option A: Reject suppression**. Q2 (companion action) split three ways:

- **α — Docs-only spec paragraph** (plt, min)
- **β — Docs + targeted diagnostic on interp-parse-failure** (sys, web; devops minimum, plt fallback, aiml fallback, min fallback acceptable)
- **γ — Docs + lint warning W0421** (devops preferred, aiml preferred)

#### Phase B — Debate highlights

The Q2 debate centered on whether the silently-wrong failure mode (where `"see `{flag}` here"` interpolates successfully when `flag` is in scope) warrants a lint pass.

- **devops (γ camp):** "The markdown-trap is a *silently-wrong* failure mode, not a parse failure. Consider `"see `{flag}` in config"` where `flag` happens to be a real identifier in scope — under α and β this compiles cleanly and silently interpolates inside what the author clearly intended as a code span... That's the exact class of bug LSP-grade diagnostics exist to catch: locally repairable, single-line, zero recovery cascade, false-positive rate bounded by 'did the user type `` ` ` ``.'"

- **aiml (γ camp):** "The AI/ML failure mode here is *silently wrong*, not *fails to compile*. When a model writes `"rendered as `{x}` in markdown"` it expects backtick-suppression by pattern-match on training data; the code parses fine (interpolates `x`), and the bug only surfaces at runtime... β only fires on parse failure, which means it catches the loud case and misses the quiet one. That inverts the difficulty curve: easy bugs get a hint, hard bugs get silence. γ catches both."

- **plt (α camp), countering γ:** "A W0421 lint that fires on `{` between unescaped backticks in well-formed code re-introduces the exact thing Q1 rejected, just behind a warning instead of a syntax rule. It tells the user 'the compiler noticed your backticks,' which trains them to believe backticks have semantic weight — the worst-of-both-worlds outcome aiml flagged about learnability, now baked into the toolchain."

- **min (β camp), countering γ:** "γ is the wrong shape and I'll fight it. Adding W0421 means: (1) a new warning code in the diagnostic catalog... (2) a lexer or post-lex pass that *tracks unescaped backtick pairs* — i.e., we're forced to implement exactly the state machine we just rejected in Q1... (3) false positives: any legitimate string containing `` `literal {variable} text` `` where the user *wants* interpolation now eats a warning and needs a suppression comment."

- **web (β camp), countering γ:** "γ smuggles the rejected Q1 semantics back in via the linter, with a false-positive rate that will train users to ignore warnings... Every legitimate `"price is ${total} (was `{old}`)"` markdown-flavored string that *does* want interpolation now gets a warning. Users will either disable W0421 wholesale (training them to ignore lints — terrible DX outcome) or contort their strings to silence it."

- **sys (β camp), countering γ:** "γ I reject on Systems grounds. A lint that 'fires whenever `{` appears between an unescaped pair of backticks' requires the lexer or a post-lex pass to scan *every* string literal for backtick pairs and then check what's between them. That's an unbounded-distance scan added to clean-code compilation — i.e., the case where there *is* no error. It re-introduces the same 'meaning of `{` depends on prior backtick state' coupling that we just rejected in Q1, only relocated from the lexer to a warning pass."

#### Phase C — Final vote

- **Q1: Should backticks suppress interpolation inside `"..."`?** (vote tally: **6-0** for A — reject)
  - **Systems:** A — "Backtick suppression adds a second mode to the hottest loop in the lexer and makes the meaning of `{` depend on an unbounded-distance prior-byte scan. `\{` already handles inline cases and `#"..."#` already handles markdown-prose strings; a third mechanism is pure surface-area cost with no codegen win."
  - **Web/Scripting:** A — "Backticks must remain ordinary characters. A region-based, unbounded-distance toggle on `{` is exactly the kind of context-sensitive rule that wrecks learnability and tooling for a 1% aesthetic win; `#"..."#` already covers the literal-`{` case cleanly. The 90% user expects one rule per delimiter, and A preserves that."
  - **PLT:** A — "Backtick suppression would break the `Template[C]` hole-bijection (holes determined by prose context, not source `{}`s), destroy substring/concat compositionality of `"..."`, and add unbounded-region lexer state for a markdown convention. `#"..."#` already covers the prose-with-literal-`{` use case cleanly."
  - **DevOps:** A — "Suppression is a tooling tarpit. It bricks incremental relex (lexer state at column N would depend on backtick parity earlier in the string), forces an embedded-grammar branch in the LSP/tree-sitter, and creates fmt round-trip ambiguity. We already have `#"..."#` and `\{`; a third mechanism is pure surface-area cost for zero capability gain."
  - **AI/ML:** A — "Reject. Backtick-suppression is a context-sensitive lexer rule with delimiter pairing for a character with zero syntactic role elsewhere in Blink, which is the worst possible learnability profile for AI codegen."
  - **Minimalism:** A — "Reject. The language already has two adequate escape hatches (`\{` and `#"..."#`) for literal-brace cases; adding context-sensitive backtick suppression spends permanent language-surface budget to fix an aesthetic complaint about test titles. Backticks meaning 'nothing special, always' is a property worth preserving — every tool (lexer, formatter, highlighter, LSP, training data) benefits from the single mode."

- **Q2: Companion action?** (vote tally: **3-2-1 soft consensus β** — β: sys/web/min; γ: devops/aiml; α: plt)
  - **Systems:** β — "The targeted diagnostic rides the error edge the parser already takes, so it costs nothing on the steady-state hot path while killing the exact ergonomic trap that motivated this whole deliberation. γ relocates the rejected-in-Q1 region-based rule from the lexer into a warning pass and forces an unbounded-distance scan over every clean-code string literal."
  - **Web/Scripting:** β — "The actual bug users hit is a parse error with no signpost to `\{` or `#"..."#`; β fixes that at the one moment the user is paying attention, with zero hot-loop cost and no state machine. α alone optimizes for readers of §2.4, who are by definition not the population getting bitten."
  - **PLT:** α *(with β acceptable iff trigger = parse-failure-only)* — "A spec paragraph pointing at `#"..."#` is the only companion action that fully preserves the Q1 invariant ('backticks have no semantic role'). Diagnostics and lints both teach the user that the compiler *notices* backticks, which is exactly the learnability trap aiml flagged."
  - **DevOps:** *(dissent toward γ; β fallback)* γ — "The markdown-trap is silently-wrong, not a parse failure... β never fires when the parser succeeded. β is my acceptable fallback if the panel only funds one action, since at minimum the existing parse-failure path needs a real suggestion instead of 'unexpected .'"
  - **AI/ML:** *(dissent toward γ; β fallback)* γ — "The AI/ML failure mode is silently-wrong (code parses, runtime is subtly off), not parse-fail; β catches only the loud case and leaves the quiet one for users to discover at runtime. γ's cost lands in the lint pass, not the hot scanner loop, and a warning (not error) preserves the escape hatch while making every fire a teaching moment whose text AIs read as authoritative."
  - **Minimalism:** β — "Docs paragraph plus a hint on the existing interpolation-parse-failure path. Zero new grammar, zero new lexer state, zero new warning class — just a better message on an error the compiler already emits, which solves the actual UX gap (user surprise) at the moment of impact... γ is a firm no because it forces us to build the exact backtick-balancing state machine we just rejected in Q1, plus a new warning code with a configurability surface and a false-positive class on legitimate interpolating strings."

#### Phase D — Round 2

Not triggered. Q1 was unanimous (6-0). Q2 was 3-2-1, which would normally trigger Phase D, but the skill's soft-consensus carve-out applies: β is the first preference of 3 panelists *and* explicitly endorsed as acceptable fallback by both γ voters and the α voter (with the trigger-scoping caveat plt added, which β satisfies by design). The γ camp's silently-wrong concern is acknowledged as legitimate by majority β voters and is documented as a future follow-up ticket. Phase D would re-litigate a question whose dissent is already endorsed — no productive output expected.

### Final Spec

```blink
// Backticks have no special meaning inside "..." or #"..."#.
// Short inline span with literal { — escape with \{:
test "pool usage: `with pool.scoped() \{ pg.query(...) }`" {
    assert(true)
}

// Prose-heavy span with literal { — use #"..."# (extended delimiter):
test #"pool usage: `with pool.scoped() { pg.query(...) }`"# {
    assert(true)
}
```

Locked design points:

- Backticks (`` ` ``) are ordinary characters inside `"..."` and `#"..."#`. **No suppression of interpolation.** (6-0)
- `\{` remains the inline escape for literal `{` in `"..."`.
- `#"..."#` remains the prose-heavy form (literal `{`, interpolation via `#{expr}`).
- A new spec paragraph in §2.4 documents the rule and points users at both escape hatches.
- A targeted diagnostic on interpolation-parse-failure inside `"..."` suggests both `\{` and `#"..."#` at the moment of confusion. The diagnostic fires only on actual parse failure (not on backtick presence in well-formed code), preserving the "backticks have no semantic role" invariant.
- The W0421 lint that fires on `{` between backticks in well-formed code (γ) is **deferred** to a future ticket after the lint framework matures. Both γ voters (devops, aiml) flagged the silently-wrong case as a legitimate long-term concern; β voters acknowledged the concern but rejected the implementation cost given current lint infrastructure.
