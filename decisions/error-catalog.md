[< All Decisions](../DECISIONS.md)

# Error Catalog — Design Rationale

### Panel Deliberation

Five panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML) voted independently on 5 questions. Resolves Tier 3 gap: "error codes referenced but no complete catalog."

**Q0: Identification scheme — names vs codes vs hybrid (3-2 for names primary)**

- **Systems:** Hybrid — both visible in terminal. Codes are searchable, greppable, copy-pastable. Names add value but shouldn't replace codes. *(dissent)*
- **Web/Scripting:** Hybrid — TS-familiar DX with both in output. *(dissent)*
- **PLT:** Names primary. Self-documenting, collision-proof by construction (namespace is unbounded). Work as suppression IDs (`@allow(NonExhaustiveMatch)`). Codes stay in JSON as compact alias.
- **DevOps:** Names primary. LSP hover shows the name, not a number. Names are stable API — frozen once published. CLI `pact explain NonExhaustiveMatch` is discoverable.
- **AI/ML:** Names primary. Python exception names are the most represented error pattern in LLM training data. `NonExhaustiveMatch` is self-explanatory; `E0004` requires a lookup table. Names survive context window compression better than codes.

**Q1: Organization — category ranges vs prefixes vs flat (4-1 for category ranges)**

- **Systems:** Clean-up-current — fix collisions, no new scheme. Adding ranges is over-engineering for 30 codes. *(dissent)*
- **Web/Scripting:** Category ranges. E00xx-E10xx gives room for growth. Browsing a range tells you the domain.
- **PLT:** Category ranges. Mirrors Rust's proven organization. Numeric ranges partition the code space cleanly.
- **DevOps:** Category ranges. CI rules like "fail on any E05xx" (effect errors) become trivial. Range-based filtering is a real operational tool.
- **AI/ML:** Category ranges. Training data from Rust/C# uses ranged codes. LLMs can infer category from code prefix.

**Q2: Collision handling — reassign vs reserve (5-0 for reassign)**

All panelists agreed: reassign unique IDs to every collision. Reserving ranges for "same code, different meaning" defeats the purpose of having codes at all. Eight reassignments were identified and applied.

**Q3: Documentation format — table vs detailed explain (4-1 for table + deferred explain)**

- **Systems:** Table. One-line descriptions suffice for a reference. Detailed `--explain` is a future tooling concern, not a spec concern.
- **Web/Scripting:** Full Rust-style explain now. Every error should have a prose explanation with examples from day one. *(dissent)*
- **PLT:** Table. The spec examples already serve as the "explain" for each error. A separate prose catalog duplicates them.
- **DevOps:** Table. Ship the catalog now, add `pact explain` tooling later. Perfect is the enemy of done.
- **AI/ML:** Table. LLMs parse tables efficiently. Prose explanations add tokens without proportional value when the spec sections already contain examples.

**Q4: Location — standalone file vs embedded in spec (5-0 for standalone)**

All panelists agreed: standalone `ERROR_CATALOG.md` at repo root. Embedding in a spec section makes the catalog hard to find and forces readers to navigate through prose. Standalone file is directly linkable, greppable, and serves as a single source of truth.

