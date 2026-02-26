[< All Decisions](../DECISIONS.md)

# `@i` Annotation — Design Rationale

### Panel Deliberation

Five panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML) voted independently on whether to keep `@i` as a separate annotation, merge it into `///` doc comments, cut it entirely, or redesign it.

**Context:** `@i("text")` was a natural-language intent declaration on functions, types, and modules. Investigation revealed that Pact already has `///` doc comments producing structured compiler-queryable data (§2.1), and examples like `bank.pact` had both `///` and `@i` carrying duplicate information — violating Principle 2 ("one way to do everything"). The drift detection feature (the killer differentiator for `@i`) was deferred to v2+ with no concrete mechanism. `@i` was the only annotation in Pact's system carrying unstructured prose with no formal semantics — every other annotation is compiler-checkable.

**Q1: Keep @i, merge into ///, cut entirely, or redesign? (5-0 for merge into ///)**

- **Systems:** Merge. `@i` adds compiler complexity (parsing, AST storage, symbol table field) for zero runtime benefit. `///` already exists in the AST — no reason to store intent twice. Rust and Go prove doc comments handle this without a separate annotation.
- **Web/Scripting:** Merge. Every JS/Python/TS developer knows doc comments. Nobody knows `@i`. Having both `///` and `@i` is the first "wait, what?" moment for newcomers. The `bank.pact` duplication is exactly the kind of thing that makes developers distrust a language's design.
- **PLT:** Merge. `@i` is the only annotation carrying unstructured prose with no formal semantics. Every other annotation (`@requires`, `@ensures`, `@where`, `@effects`) is compiler-checkable. `@i` is categorically different — it's documentation masquerading as a formal annotation. Moving it to `///` is more honest. Haskell and OCaml use Haddock/odoc for this.
- **DevOps:** Merge. One source of truth for LSP hover, one thing for `pact fmt` to format, one lint to enforce. With `@i`, every tool must handle two parallel description systems. `pact query --intent` can query `///` first lines with identical results. Go's godoc and Rust's rustdoc extract summaries from doc comments — proven pattern.
- **AI/ML:** Merge. `@i("text")` costs ~4 extra tokens per function vs `/// text`. LLMs trained on every major language know doc comments; zero training data exists for `@i`. Having both creates a decision point with no value. Eliminating `@i` aligns with patterns LLMs already generate correctly.

**AI-First Review:** 5/5 pass (learnability, consistency, generability, debuggability, token efficiency).

**Resolution:** `@i` removed from annotation system. First line of `///` doc comment serves as the queryable intent declaration. `pact query --intent` queries `///` first lines. Annotation count reduced from 15 to 14. Canonical ordering updated. All `@i` references removed from §2.16, §8.4, §11.1, and examples.

