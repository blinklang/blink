[< All Decisions](../DECISIONS.md)

# `--trace` NDJSON Output Format — Design Rationale

### Panel Deliberation

Five panelists voted on the concrete schema for Pact's `--trace` runtime execution tracing feature. The `--trace` concept was previously approved 5-0 (C4 in synthesis_and_vote.md). This deliberation resolves the output format, event types, value serialization, filter syntax, and timestamp format.

**Context:** `--trace` emits structured NDJSON to stderr for function entry/exit, state mutations, and effect invocations. Primary consumers are AI agents debugging Pact programs (one-shot, structured, zero-residue) and developers piping through `jq`. The existing `--pact-trace` compiler flag traces compiler phases (lex/parse/typecheck/codegen) — the new `--trace` is for runtime execution of compiled programs.

---

**Q1: Event types (4-1 for B: 4 types)**

- **Systems:** Option B. Four events form a complete basis: call stack (enter/exit), store transitions (state), effect operations (effect). `assert_fail`/`panic` are program termination, not observation.
- **Web:** Option B. Effects are first-class in Pact; tracing them is a killer feature. Panics are not trace events — they're crash reports via existing diagnostics.
- **PLT:** Option B. The four types correspond to semantic domains: β-reduction boundaries, store transitions, and effect invocations. Divergence events belong in diagnostic output. *(majority)*
- **DevOps:** Option C. `assert_fail`/`panic` are the highest-value diagnostic events — users will `jq 'select(.event == "panic")'` to find crash chains. *(dissent)*
- **AI/ML:** Option B. Four types sufficient. Panic/assert are just `exit` events with error fields — dedicated types increase schema surface without adding signal.

---

**Q2: Schema shape (5-0 for B: semi-nested)**

- **Systems:** Option B. Reusing the diagnostic `span` object means tools that parse diagnostic output can reuse span-extraction code.
- **Web:** Option B. Consistency across Pact's JSON surfaces. Nobody wants `jq '.context.function'` when `jq '.fn'` works.
- **PLT:** Option B. The span is a product type in the compiler's internal representation — it should project to the same JSON shape everywhere. Semi-nesting is the coherent choice.
- **DevOps:** Option B. Non-negotiable consistency with existing diagnostic span format.
- **AI/ML:** Option B. 1-token overhead vs flat, but consistency with diagnostics is worth it. Fully nested wastes ~7 tokens per event.

---

**Q3: Value serialization (4-1 for A: string/Display)**

- **Systems:** Option A. Typed JSON has hidden costs — serializing `List[Int]` with 10K elements as a JSON array is catastrophic. String/Display is bounded and fast (a `snprintf` call). *(majority)*
- **Web:** Option A. Mapping all Pact types to JSON equivalents is massive surface area with edge cases forever. Display is always available, always correct. *(majority)*
- **PLT:** Option C. Tagged representation preserves type-theoretic identity. Needed for round-tripping and replay-based debugging. `{"type":"Int","value":42}` is the principled choice. *(dissent)*
- **DevOps:** Option A. Forward-compatible — new types don't require schema changes. String representation keeps lines short and grep-able. *(majority)*
- **AI/ML:** Option A. Tagged JSON costs ~7 tokens per value vs ~3 for strings. Over traces with hundreds of state events, that's 2-4x overhead for type info AI can infer from function signatures. *(majority)*

---

**Q4: Filter syntax (4-1 for B: colon-syntax)**

- **Systems:** Option B. Colon-syntax compiles trivially to a struct of optional match fields with short-circuit evaluation. Regex requires a regex engine in the runtime — orders of magnitude slower per-event.
- **Web:** Option B. Matches RUST_LOG, Docker, Kubernetes label selectors. Developers already know `key:value` filtering. *(majority)*
- **PLT:** Option A. Separate flags make conjunction structure syntactically explicit. The shell already provides flag composition. *(dissent)*
- **DevOps:** Option B. Single flag, composable, env-var friendly (`PACT_TRACE=fn:parse_expression,depth:3`). *(majority)*
- **AI/ML:** Option B. Single flag with structured semantics — AI can build it programmatically. Less hallucination surface than separate flag names. *(majority)*

---

**Q5: Timestamp format (5-0 for A: microseconds monotonic)**

- **Systems:** Option A. Instrumentation overhead is microsecond-order; nanoseconds give false precision. Microseconds fit in 32-bit for traces under ~70 minutes.
- **Web:** Option A. Compact, readable (`18043` vs `18043000`), sufficient precision.
- **PLT:** Option A. One canonical representation per semantic concept. Two timestamp fields for the same instant is a coherence violation.
- **DevOps:** Option A. JSON safe integers handle microseconds for ~285 years. Nanoseconds overflow after ~104 days of monotonic time.
- **AI/ML:** Option A. Smaller integers = fewer tokens. `"ts_us":14` is 2 tokens; `"ts_ns":14000` is 2-3 tokens.
