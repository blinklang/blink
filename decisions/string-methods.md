[< All Decisions](../DECISIONS.md)

# String Methods — Design Rationale

### Panel Deliberation

Five panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML) voted independently on 5 questions. Resolves Tier 2 gap: "String methods".

**Q1: Trait organization (5-0 for generic Sized + StrOps)**

- **Systems:** Generic `Sized` trait. `.len()` and `.is_empty()` compile to one vtable slot per collection type. Sharing the trait across `Str`, `List`, `Map`, `Set` means one evidence-passing path for size checks in generic code. The `StrOps` catch-all avoids vtable fragmentation — one struct with all string function pointers, cache-friendly.
- **Web/Scripting:** Generic `Sized` + `StrOps`. Every web developer expects `.len()` to work the same way on strings and arrays. A shared `Sized` trait makes this intuition correct. `StrOps` as a single trait mirrors how Iterator works — one import, all methods available via LSP autocomplete.
- **PLT:** `Sized` as a generic trait is well-founded — it provides a uniform interface for the cardinality observation on finite containers. Separating it from `StrOps` respects the trait coherence model: `Sized` is implementable by any container, while `StrOps` is string-specific. This is the standard algebraic factoring.
- **DevOps:** `Sized` + `StrOps`. LSP autocomplete on `s.` shows `len()` and `is_empty()` from `Sized`, plus all string methods from `StrOps`. Two traits, clean categorization. Resolving the Collection methods gap simultaneously is a tooling win — `.len()` hover shows `Sized.len` for all types.
- **AI/ML:** Shared `Sized` trait matches training data where `.len()` works uniformly across collection types. One `StrOps` trait minimizes import decisions — LLMs don't need to choose which string trait to import. Follows the Iterator precedent that models already understand.

**Q2: v1 method surface area (5-0 for 15 existing methods)**

- **Systems:** Codify what exists. The self-hosting compiler already uses these 15 methods; each maps to a C runtime function. No speculative surface area — every method has a known caller. Adding methods later is additive; removing is breaking.
- **Web/Scripting:** The 15 existing methods cover the JS/Python string API core that web developers reach for daily. `trim_start`/`trim_end` and `pad_left`/`pad_right` are nice-to-have but not blocking — they can be added in a point release. Ship what's tested.
- **PLT:** Minimal committed API surface. Each method in the trait is a coherence obligation — every implementor must provide it. Starting with 15 well-understood methods minimizes the proof burden. Default methods can extend the surface later without breaking existing impls.
- **DevOps:** 15 methods = manageable autocomplete list. Expanded 22 would add noise. Every method in the spec needs LSP descriptions, error messages, and documentation. Ship the known set, extend based on friction logs.
- **AI/ML:** 15 methods match the common string operations in training data. Expanding to 22 adds methods with lower frequency in training data (`pad_left`, `repeat`) increasing hallucination risk for parameter order. The Iterator pattern proved that starting minimal and extending works.

**Q3: Unicode semantics (3-2 for codepoint-default dual API)**

- **Systems:** Byte-oriented defaults with honest names (Option D). `.len()` = `strlen()` is O(1) and maps to a single C call. Codepoint-length is O(n) — hiding that behind `.len()` violates the principle that simple syntax implies simple cost. Name the operations honestly: `.byte_len()`, `.byte_at()`, `.codepoint_at()`. *(dissent)*
- **Web/Scripting:** Dual API with codepoint default (Option C). Web developers think in characters, not bytes. Python, JavaScript (mostly), and Ruby all have codepoint-oriented `.length`. `.len()` returning bytes would surprise 90% of users — "hello" should have length 5, and "café" should have length 4, not 5. Byte access via `byte_` prefix for the rare cases that need it.
- **PLT:** Byte-oriented defaults with honest names (Option D). The type system should not lie about complexity. If `.len()` is O(n), that's a hidden cost the type signature doesn't reveal. Naming matters: `.byte_len()` is honest about what it counts, `.codepoint_count()` is honest about its cost. Option D preserves the correspondence between names and semantics. *(dissent)*
- **DevOps:** Dual API with codepoint default (Option C). Codepoint `.len()` matches what developers expect in diagnostics and error messages — "string has length 4" should mean 4 characters. The `byte_` prefix is clear and discoverable via LSP autocomplete. Performance-sensitive code can opt into byte methods explicitly.
- **AI/ML:** Dual API with codepoint default (Option C). Training data overwhelmingly associates `.len()` with character count. LLMs generating `if name.len() > 50` mean "50 characters" not "50 bytes." Byte-oriented default would cause systematic off-by-one bugs in every non-ASCII context. The `byte_` prefix is unambiguous and won't be hallucinated by models trained on Python/JS patterns.

**Q4: Parsing methods (4-1 for named methods on Str)**

- **Systems:** Named methods. `.parse_int()` compiles to a direct C function call — no vtable dispatch, no generic monomorphization overhead. The method name in the binary's symbol table is greppable. Delegating to `TryFrom` under the hood keeps the trait system consistent while giving call sites zero-cost direct dispatch.
- **Web/Scripting:** Named methods. `str.parse_int()` is exactly what Python's `int(str)` and JS's `parseInt(str)` developers expect, just in method-call form. LSP autocomplete on `s.parse_` shows available parse targets. Far more discoverable than `Int.try_from(s)` which requires knowing the target type has a `TryFrom` impl.
- **PLT:** TryFrom only (Option A). Named methods on `Str` create ad-hoc coupling — `Str` must know about `Int` and `Float` at definition time. `TryFrom` is parametric: the conversion knowledge lives with the target type, not the source. Adding `parse_int()` to `Str` violates the open-world assumption of trait-based dispatch. *(dissent)*
- **DevOps:** Named methods. `s.parse_` in autocomplete immediately shows `parse_int`, `parse_float` — zero lookup cost. `Int.try_from(s)` requires the developer to know both the target type and that `TryFrom` exists. Named methods are the discoverability sweet spot for tooling.
- **AI/ML:** Named methods. `s.parse_int()` is a single-token decision that models get right from Python/JS training data. `Int.try_from(s)` requires generating the correct target type first, then knowing the trait — two decision points. Generic `.parse[T]()` requires type inference context that models frequently get wrong.

**Q5: String building (5-0 for join now, StrBuf deferred)**

- **Systems:** `List[Str].join()` is O(n) with a single allocation — measure total length, allocate, copy. No intermediate allocations, no amortized realloc. `StrBuf` adds a mutable type to the language surface that requires growth-factor decisions and realloc strategy — defer until profiling data from real Pact programs shows it's needed.
- **Web/Scripting:** `.join()` is the pattern every web developer knows from `Array.join()`. It covers the 95% case (building strings from parts). `StrBuf` is a premature optimization for v1 — most programs build strings with interpolation and occasionally join a list. YAGNI, ship `join()`, add `StrBuf` when someone needs it.
- **PLT:** `List[Str].join()` is a fold with a separator — algebraically clean. It doesn't require new types or mutable state. `StrBuf` would be the first mutable non-collection type in the language, requiring design decisions about growth semantics and trait implementations. Defer to v1.1 when the design space is better understood.
- **DevOps:** `join()` now. One method, one signature, one autocomplete entry. `StrBuf` is an entire type with its own methods, its own documentation, its own error messages. Ship the simple thing, add complexity when the friction log demands it.
- **AI/ML:** `join()` has massive training data from every language. LLMs generate `parts.join(", ")` correctly at near-100% rates. `StrBuf` would be a novel type with zero training data — guaranteed hallucination target. Defer until there's enough Pact-specific training data to teach models the builder pattern.

