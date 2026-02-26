[< All Decisions](../DECISIONS.md)

# Trait Coherence — Design Rationale

### Panel Deliberation

Five panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML) voted independently on 3 questions. All votes unanimous.

**Q1: Orphan rules (5-0 for strict)**

- **Systems:** Strict. Evidence-passing requires exactly one vtable per (Trait, Type). Orphan ambiguity would require runtime dispatch or link-time deduplication. Newtype workaround covers the practical cases.
- **Web/Scripting:** Strict. Haskell's orphan instances are a well-known disaster. Two packages defining `impl Display for HttpResponse` and any program importing both breaks silently. The newtype pattern is a small price for deterministic behavior.
- **PLT:** Strict. Global coherence is a syntactic property under the orphan rule (package ownership), not a whole-program semantic analysis. This keeps compilation fast and decidable. Relaxing later is backwards-compatible; tightening is not.
- **DevOps:** Strict. LSP go-to-definition on a trait method needs exactly one impl target. Orphan impls mean the impl could be anywhere in the dependency graph. Strict rule bounds the search to two packages.
- **AI/ML:** Strict. LLMs generating `impl Trait for Type` need one clear rule: "is this my trait or my type?" Binary check, zero ambiguity. Orphan impls would require the model to reason about which package owns what across the entire dependency graph.

**Q2: Impl overlap (5-0 for no overlap, no specialization)**

- **Systems:** No overlap. Specialization sounds useful but Rust has kept it unstable for over a decade with multiple soundness holes. Each (Trait, Type) pair maps to one vtable entry. Zero runtime ambiguity.
- **Web/Scripting:** No overlap. "Most specific wins" rules are never intuitive. Adding an impl to a library silently changing behavior in downstream code is the opposite of locality of reasoning.
- **PLT:** No overlap. Specialization requires a partial ordering on impls that interacts with type inference in subtle ways. Without specialization, adding a new impl can only cause overlap errors (loud), never silent behavior changes. The helper-trait and newtype workarounds are compositional.
- **DevOps:** No overlap. Overlap errors at the impl site are actionable ("these two impls conflict, choose one"). Specialization errors are baffling ("this impl was silently superseded by a more specific one three dependencies deep").
- **AI/ML:** No overlap. One impl per (Trait, Type) is the only pattern with significant training data (Rust stable). Specialization has near-zero training data (Rust nightly only). LLMs would generate overlapping impls and be confused by the resolution rules.

**Q3: Impl placement and visibility (5-0 for package-scoped, auto-visible)**

- **Systems:** Package-scoped. The impl must live in the trait's package or the type's package — follows directly from the orphan rule. Within a package, any module is fine. Intra-package cycles are already allowed (§10.5).
- **Web/Scripting:** Package-scoped with auto-visibility. Requiring explicit impl imports would be boilerplate torture. Importing `User` should give you all of `User`'s behavior. This matches how JS/TS modules work — import a class, get all its methods.
- **PLT:** Package-scoped. Auto-visibility is the only principled choice: an impl is a fact about a (Trait, Type) pair, not an independent entity to be imported. The compiler discovers impls by following the import graph — importing either the trait or the type is sufficient.
- **DevOps:** Package-scoped. For LSP, "find all impls of Trait for Type" has a bounded search: check the trait's package and the type's package. Auto-visibility means go-to-definition never fails because of a missing impl import.
- **AI/ML:** Package-scoped with auto-visibility. Zero-boilerplate discovery. An AI importing a type should immediately be able to call all its trait methods without hunting for impl import paths. One import, complete behavior.

