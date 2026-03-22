[< All Decisions](../DECISIONS.md)

# Qualified Access Semantics — Design Rationale

### Panel Deliberation

Five panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML) voted independently on 4 questions.

**Q1: Should selective imports restrict qualified access? (3-2 for B: selective restricts only unqualified)**

- **Systems (A):** Single source of truth — import list IS access list. Dual-access mode complicates symbol resolution.
- **Web/Scripting (B):** Python devs expect `import os.path` to allow `os.path.join()`. Selective import's purpose is namespace hygiene, not capability restriction.
- **PLT (B):** `import foo.{bar}` is a statement about local namespace, not access control — that's what `pub` is for. Haskell behaves this way. *(winning)*
- **DevOps (B):** LSP completion should show module's full pub surface on `foo.`, not filtered by selective import variant.
- **AI/ML (A):** "What you import is what you use" is a single invariant — doubles decision surface for AI. *(dissent)*

**Q2: What does qualified access cover? (5-0 for B: functions + types + constants)**

- **Systems:** Types and constants are first-class module interface. Enum variants excluded — parser collision with existing `Trait.method(x)` syntax.
- **Web/Scripting:** Types and constants are first-class module interface. Enum variants excluded — parser collision with existing `Trait.method(x)` syntax.
- **PLT:** Types and constants are first-class module interface. Enum variants excluded — parser collision with existing `Trait.method(x)` syntax.
- **DevOps:** Types and constants are first-class module interface. Enum variants excluded — parser collision with existing `Trait.method(x)` syntax.
- **AI/ML:** Types and constants are first-class module interface. Enum variants excluded — parser collision with existing `Trait.method(x)` syntax.

**Q3: Nested module paths? (5-0 for A: leaf module name only)**

- **Systems:** `import std.num` → `num.parse_int()` works, `std.num.parse_int()` does NOT. Multi-segment paths create parser ambiguity.
- **Web/Scripting:** Multi-segment paths create parser ambiguity. Collision between same leaf names resolved by import aliases.
- **PLT:** Multi-segment paths create parser ambiguity. Collision between same leaf names resolved by import aliases.
- **DevOps:** Multi-segment paths create parser ambiguity. Collision between same leaf names resolved by import aliases.
- **AI/ML:** Multi-segment paths create parser ambiguity. Collision between same leaf names resolved by import aliases.

**Q4: Qualified resolves E1005 ambiguity? (5-0 for A: yes)**

- **Systems:** `foo.helper()` is unambiguous by construction when bare `helper()` triggers E1005. Primary motivating use case.
- **Web/Scripting:** `foo.helper()` is unambiguous by construction when bare `helper()` triggers E1005. Primary motivating use case.
- **PLT:** `foo.helper()` is unambiguous by construction when bare `helper()` triggers E1005. Primary motivating use case.
- **DevOps:** `foo.helper()` is unambiguous by construction when bare `helper()` triggers E1005. Primary motivating use case.
- **AI/ML:** `foo.helper()` is unambiguous by construction when bare `helper()` triggers E1005. Primary motivating use case.
