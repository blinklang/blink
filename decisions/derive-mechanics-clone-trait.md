[< All Decisions](../DECISIONS.md)

# Derive Mechanics + Clone Trait — Design Rationale

### Panel Deliberation

Five panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML) voted independently on 4 questions. Resolves two Tier 2 gaps: "Derive mechanics" and "Clone trait".

**Q1: Clone semantics in GC context (3-2 for logical copy)**

- **Systems:** Logical copy (Option C). In a GC'd runtime, "clone" means allocate a new struct shell, copy field values (GC pointers). Deep copy is an O(n×m) allocation storm for nested collections with cycle risk. The C backend emits a single `malloc` + `memcpy` for struct fields — clean, predictable, zero recursion. If users need deep independence, a separate `DeepClone` trait with explicit recursion is the right tool.
- **Web/Scripting:** Logical copy (Option C). This is exactly JS's `{...obj}` spread or Python's `copy.copy()`. Web developers already understand one-level semantics — the clone shares nested references. This is the dominant pattern in GC'd languages and matches the largest body of LLM training data.
- **PLT:** Logical copy (Option C). In ML/OCaml tradition, record copy is structural — `{r with field = new_value}` copies the record, shares nested references. Deep copy is a separate concern requiring recursion schemes. The distinction is principled and well-understood in PL literature.
- **DevOps:** Deep copy (Option B). A `clone()` that doesn't give you an independent value is semantically vacuous — it's just aliasing with extra allocation. When you clone a config struct, you expect modifying the clone doesn't affect the original. Shallow clone violates the principle of least surprise. *(dissent)*
- **AI/ML:** Deep copy (Option B). Training data overwhelmingly associates "clone" with "independent copy." When an LLM generates `let backup = config.clone()` and then mutates `backup`, it expects isolation. Shallow clone causes aliasing bugs that are invisible at the call site. *(dissent)*

**Q2: Debug trait design (5-0 for separate trait)**

- **Systems:** Separate `Debug` trait with `fn debug(self) -> Str`. No supertrait relationship with `Display`. Debug emits structural representation (`TypeName { field: value }`), Display emits user-facing strings. At C level, separate vtable slots — no coupling. The compiler can optimize away unused Debug impls in release builds.
- **Web/Scripting:** Separate `Debug`. Maps to `console.log()` vs `.toString()` distinction in JavaScript. Developers expect one format for logging/debugging and a different one for user-facing output. No supertrait means implementing Display doesn't require Debug and vice versa.
- **PLT:** Separate `Debug`. Haskell's `Show` conflates both roles and regrets it. Rust's `Debug` vs `Display` split is one of its best ergonomic decisions. The structural representation is mechanical and derivable; the user-facing string requires human judgment.
- **DevOps:** Separate `Debug`. Structured logging needs consistent machine-parseable output. `Debug` gives `"User { name: \"Alice\", age: 30 }"` which tools can parse. `Display` gives `"Alice (alice@example.com)"` for humans. Different audiences, different traits.
- **AI/ML:** Separate `Debug`. LLMs generating debug output and user-facing output are clearly different tasks. Having them in separate traits means the model picks the right one from context. No ambiguity about which to call.

**Q3: Derive codegen algorithm (5-0 for inferred bounds + auto supertrait)**

- **Systems:** Inferred bounds. The compiler scans field types, collects trait requirements, emits `where` clauses. For `@derive(Eq)` on `Pair[A, B]`, field `first: A` needs `A.eq()` → emit `where A: Eq`. Supertrait auto-derivation: `@derive(Ord)` checks for existing `Eq` impl, derives one if missing. Mechanical, deterministic, zero user annotation.
- **Web/Scripting:** Inferred bounds. "It just works" — the developer writes `@derive(Eq)` and the compiler figures out the bounds. No manual `where` clauses on derived impls. This is TypeScript-level ergonomics applied to trait derivation.
- **PLT:** Inferred bounds with auto supertrait. This follows the standard derivation algorithm from Haskell/Rust: derive obligations propagate through field types and supertrait relationships. Sound and complete for the derivable trait set.
- **DevOps:** Inferred bounds. LSP can show the inferred bounds on hover. Error messages point to the specific field that can't satisfy the bound. Clean diagnostic story.
- **AI/ML:** Inferred bounds. LLMs write `@derive(Eq)` and move on. No need to think about generic constraints — the compiler handles it. Reduces token count and error surface.

**Q4: Error reporting for non-derivable fields (5-0 for field-level errors)**

- **Systems:** Report all failing fields in one pass. The compiler walks every field, collects failures, emits a single diagnostic with all of them. No "fix one, compile, find the next" loop. Batch error reporting matches the existing diagnostic strategy.
- **Web/Scripting:** All fields at once. TypeScript shows all type errors in one pass. Developers expect to see the full picture, not a drip feed.
- **PLT:** All fields. Standard practice — GHC, rustc, and OCaml all report multiple derivation failures in a single compilation unit.
- **DevOps:** All fields. CI pipelines get a complete error list in one build. No wasted cycles on iterative fix-compile cycles.
- **AI/ML:** All fields. An AI agent in a generate-compile-fix loop needs all errors at once to fix them in a single pass. Reporting one at a time forces O(n) compilation rounds for n failing fields.

