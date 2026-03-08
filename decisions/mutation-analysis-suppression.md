[< All Decisions](../DECISIONS.md)

# Mutation Analysis Suppression & Precision

**Status:** Resolved
**Date:** 2026-03-08
**Triggered by:** GAPS.md — "Mutation analysis suppression / precision"

## Context

W0551 (UnrestoredMutation) fires for every function that calls anything writing 3+ globals. `diag_emit` mutates 14 globals, so virtually every function in the compiler triggers it — 2,400+ warnings on self-host, nearly all false positives. The analysis was designed to catch speculative-lookahead bugs (save `pos` but forget `pending_comments`) but the heuristic "3+ unsaved globals = warning" catches all normal code too. §4.16 specified the analysis but not how to manage its noise.

Three sub-questions: (1) suppression mechanism, (2) smarter heuristic, (3) threshold tuning.

## Questions & Votes

### Q1: Suppression Mechanism

Options: (A) `@allow(WarningName)` per-function annotation only, (B) `pact.toml` `[lints]` config only, (C) both.

| Expert | Vote | Reasoning |
|--------|------|-----------|
| Systems | C | Two-level mirrors optimization pragmas: global policy + surgical overrides. `pact.toml` alone is too coarse — can't keep W0551 on for speculative code while suppressing for normal code |
| Web/Scripting | C | Every mature linting ecosystem (ESLint, Ruff, Clippy) offers both. Having only one feels incomplete |
| PLT | C | Project-wide handles policy, per-function provides compositionality. Library authors can suppress locally without forcing downstream config changes |
| DevOps | C | `pact.toml` for CI pipelines and team policy, `@allow` for LSP inline diagnostics. `[lints]` section already has precedent for W0600 |
| AI/ML | C | `@allow` maps to Rust `#[allow]` training data — LLMs will generate it correctly. `pact.toml` handles project ergonomics |

**Result: 5-0 for C (both `@allow` + `pact.toml`)**

**Key precedence rule:** Function-level `@allow` always overrides project-level `pact.toml`.

### Q2: Smarter Heuristic for W0551

Options: (A) context-aware — only fire in functions with existing save/restore patterns, (B) keep current (any call to 3+ write-set triggers), (C) callee-pattern-aware.

| Expert | Vote | Reasoning |
|--------|------|-----------|
| Systems | A | Directly encodes intent signal. Save/restore = speculative work. No save/restore = normal mutation. 2,400 false positives prove current heuristic has zero signal-to-noise |
| Web/Scripting | A | The "just works" answer. 2,400 false positives is a DX disaster — developers disable the entire warning and miss real bugs |
| PLT | A | Soundest option. Non-speculative functions perform normal imperative mutation already governed by the write-set system. Firing on them conflates two distinct concerns |
| DevOps | A | Highest impact for diagnostic quality. False positives worse than no warning — developers ignore ALL mutation warnings including valuable W0550s |
| AI/ML | A | 2,400 false positives catastrophic for learnability. Heuristic is trivially explainable: "W0551 fires when you started saving state but missed some" |

**Result: 5-0 for A (context-aware)**

**Shared concern (all experts):** A function that *should* have save/restore but doesn't yet won't trigger W0551. Accepted tradeoff — W0550 catches incomplete patterns, and a precise tool catching 95% of bugs is better than a noisy one catching 100% that everyone ignores.

### Q3: Threshold Tuning

Options: (A) remove threshold entirely — rely on Q2 heuristic, (B) keep but raise to 5-8, (C) keep at 3.

| Expert | Vote | Reasoning |
|--------|------|-----------|
| Systems | A | Thresholds are arbitrary magic numbers. Inside speculative context, ANY unsaved mutation is potentially a bug — even 1 global. Threshold actually hides bugs |
| Web/Scripting | A | Threshold becomes irrelevant with context-aware heuristic. Extra knob creates bikeshedding. Keep mental model simple |
| PLT | A | Threshold of 3 (or 5 or 8) is unprincipled — no theoretical justification. Context-aware heuristic makes it redundant |
| DevOps | A | Threshold adds tuning knob generating perpetual bikeshedding without improving accuracy |
| AI/ML | A | Arbitrary thresholds are anti-patterns for LLM reasoning. "Incomplete save/restore pattern" is semantically meaningful; "calls function writing N+ globals" is not |

**Result: 5-0 for A (remove threshold)**

## AI-First Review

| Criterion | Pass/Fail | Notes |
|-----------|-----------|-------|
| Learnability | Pass | `@allow(WarningName)` maps to Rust `#[allow]` — massive training data |
| Consistency | Pass | `@allow` extends annotation system. `pact.toml` `[lints]` has precedent (W0600) |
| Generability | Pass | Simple annotation, invisible heuristic change |
| Debuggability | Pass | Warnings only fire in speculative contexts — advice is always relevant |
| Token Efficiency | Pass | 1 annotation line vs. explaining 2,400 false positives |

**0 failures — no reconsideration needed.**
