[< All Decisions](../DECISIONS.md)

# Pattern Matching Grammar — Design Rationale

### Panel Deliberation

Five panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML) voted independently on 5 questions. Each expert ran as a separate agent and returned votes without seeing other experts' reasoning.

**Q1: OR-patterns (5-0 for `|` separator)**

- **Systems:** OR-patterns compile to merged branches/jump tables — zero runtime cost. Duplicate arms make the optimizer deduplicate what the programmer already expressed. `|` is universally understood, trivially parseable.
- **Web/Scripting:** Every JS/Python dev who has touched Python 3.10 `match` knows `|` as "or" in type contexts. Comma-separated (C) would be a trap — Pact already uses commas inside tuples. `|` is unambiguous and Pact doesn't use it as a bitwise operator.
- **PLT:** OR-patterns mirror the algebraic sum type structure. The typing rule is well-studied: all alternatives must bind the same variables at the same types. This is a standard judgment in ML-family pattern calculi.
- **DevOps:** Universal syntax, LSP can offer "merge duplicate arms" quick-fixes, formatter has clear precedent from every language that supports it.
- **AI/ML:** Overwhelming training data signal from Rust, OCaml, Scala, Python 3.10, C#. LLMs will generate `|` in match arms regardless — better to accept it than produce confusing errors.

**Q2: Range patterns (5-0 for `..`/`..=`)**

- **Systems:** Range patterns = two comparisons, predictable branch. Without them, guards are opaque to exhaustiveness checker — compiler can't verify completeness or optimize dispatch. For integer-heavy matching (protocol codes, byte ranges), this matters.
- **Web/Scripting:** Guards are where developer productivity goes to die. `n if n >= 1 && n <= 5` is 21 tokens for something that should be `1..=5`. HTTP status code matching is a bread-and-butter web dev task.
- **PLT:** Exhaustiveness over discrete types with range patterns is decidable via interval arithmetic. Guards defeat the purpose of exhaustiveness checking — the compiler cannot reason about their truth. Range patterns preserve the safety guarantee.
- **DevOps:** Diagnostic goldmine. When a range match misses `256..=511`, the compiler can say exactly which interval is uncovered. Guards produce only "non-exhaustive, add wildcard" — useless.
- **AI/ML:** Fewer decision points than guards, reduces off-by-one bugs in generation. LLMs handle Rust range patterns reasonably well — decent training signal.

**Q3: Pattern binding (4-1 for `as` keyword)**

- **Systems:** `@` conflicts with annotation prefix — parsing ambiguity. `as` is already a Pact keyword, no new token. Binding+destructure is just aliasing a pointer/value — zero cost either way.
- **Web/Scripting:** Pact already uses `as` in `with...as`. It reads naturally: "match this config AS a ServerConfig with these fields." Python devs know `as` from `import x as y`. Meanwhile `@` is the annotation prefix — LLMs would hallucinate annotations inside match arms.
- **PLT:** `@` conflicts with the annotation sigil. The typing rule for `as` binding is trivial: bound name gets the scrutinee type. No interaction with the type system beyond standard variable introduction.
- **DevOps:** Context-dependent `@` is a diagnostic nightmare. Is `@foo` an annotation or a pattern binding? LSP go-to-definition, syntax highlighting, and error recovery all suffer. `as` has clear precedent.
- **AI/ML:** Pattern binding is rare — thin training data even in Rust. Fewer features = fewer decision points for LLM generation. Defer to v2. *(dissent)*

**Q4: Struct patterns in match (5-0 for full)**

- **Systems:** Gives the compiler complete visibility — direct field-offset comparisons vs opaque guard calls. Already have struct destructuring in `let`; refusing it in `match` is artificial and costs optimization opportunity.
- **Web/Scripting:** If I can destructure an enum, I should be able to destructure a struct. Field punning (`User { name, .. }`) is exactly how JS destructuring works and every web dev already knows it.
- **PLT:** Restricting struct patterns to `let` breaks compositional nested matching. `Ok(User { name, .. })` is a nested pattern — disallowing the struct layer while permitting the enum layer is unprincipled.
- **DevOps:** Inconsistency between `let` and `match` is a diagnostics anti-pattern. LSP can autocomplete field names in struct patterns, and error messages can point to specific non-matching fields.
- **AI/ML:** Rust has strong training data for struct patterns in match. LLMs handle `Struct { field, .. }` well from Rust exposure. Restricting to `let`-only contradicts what models have learned.

**Q5: Refutable vs irrefutable (5-0 for strict compile error)**

- **Systems:** `let` that can fail = hidden panic = unpredictable codegen. Strict separation means `let` always succeeds (no hidden branches, no dead panic code), `match` handles all refutable logic. Clean CFG.
- **Web/Scripting:** JS devs have been burned by "undefined is not a function" for decades. `let Some(x) = val` panicking at runtime is exactly the "works in dev, crashes in prod" bug Pact's type system prevents. The language already rejected `if let` — allowing refutable `let` would be backdooring it as a runtime panic.
- **PLT:** Refutable `let` is type-theoretically unsound — it introduces a partial function into a total context. Non-negotiable. Pattern is irrefutable iff it covers all values of the scrutinee type; single-variant enums are naturally irrefutable by this definition.
- **DevOps:** Compile error + actionable fix is the gold standard. `"refutable pattern in let, use match or ?? instead"` with a code suggestion. Warnings get ignored — developers tune them out.
- **AI/ML:** Binary rules (error vs not-error) are easiest for LLMs. Warnings are invisible during generation — the model doesn't see them in compile output. Errors feed back into iterative fix cycles.

