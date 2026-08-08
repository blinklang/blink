[< All Decisions](../DECISIONS.md)

# Compiler Internal Type Representation — Design Rationale

### Panel Deliberation

Five panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML) independently proposed and voted on replacing the compiler's `CT_*` flat integer type system with a proper recursive type representation.

**Background:** The compiler's codegen represents types as flat integer constants (`CT_INT = 0` through `CT_FFI_SCOPE = 18`). Variables are tracked via `ScopeVar` with 5 overloaded fields (`inner1`, `inner2`, `sname`, `sname2`, `extra`) where each field has 5+ different meanings depending on the `ctype` value. 17+ parallel registry lists exist for ad-hoc type tracking. This representation cannot express nested parameterized types like `List[Option[Int]]`, `Result[List[Str], MyError]`, or `Map[Str, List[Int]]`.

**Cross-language survey:** Every surveyed compiler uses a recursive type representation — Rust (`ty::TyKind` enum, interned in `TyCtxt`), Go (`types.Type` interface with child pointers), Zig (`InternPool` flat array of tagged indices), TypeScript (`Type` objects with `TypeFlags` + child references), OCaml (`type_desc` recursive variant), GHC (interned type nodes). The flat-constant approach is universally outgrown once parameterized types are needed.

All 5 experts independently converged on the same fundamental design: **interned type node pool with integer handles and recursive child references.** Three sub-questions were voted on.

---

**Q1: Pool implementation style (4-1 for C: parallel arrays now, enum later)**

- **Systems (A — parallel arrays):** Cache-friendly access patterns. Matches parser node pool. "Plan to refactor later" becomes "maintain two code paths forever." Build what works with current constraints. *(dissent)*
- **Web/Scripting (C):** Shipping beats elegance. Parallel arrays work now. But planning the migration to enum-based API is responsible — developers expect self-documenting APIs.
- **PLT (C):** Parallel arrays are an SoA encoding of a sum type. The semantic design is an algebraic data type; the implementation should converge toward it. Without a migration plan, the encoding calcifies.
- **DevOps (C):** Parallel arrays match existing tooling introspection patterns. But `tp_child1[id]` is meaningless without documentation. Migration to enum prevents every new tool author from reverse-engineering layout.
- **AI/ML (C):** Parallel arrays are a known antipattern for learnability. But the pattern exists in the parser pool, providing consistency. Migration target prevents permanent technical debt.

**All experts agreed:** The "migrate later" trigger must be concrete — a br task gated on struct-in-list compiler support landing.

---

**Q2: Unify typecheck and codegen type representations (5-0 for C: unified pool + phase side tables)**

- **Systems:** TK_*/CT_* numbering mismatch is a real bug source. Single pool eliminates translation layer. Side tables keep phase-specific data (C type names, sizeof) separate from identity.
- **Web/Scripting:** TK_VOID=4 vs CT_VOID=5 is a debugging nightmare. Unified pool eliminates that confusion. Side tables keep phases cleanly separated.
- **PLT:** Type identity should be established once (Appel's principle). Separate numbering violates single-source-of-truth. Typecheck needs variance/constraints, codegen needs C emission — side tables indexed by shared type-id give both.
- **DevOps:** Mismatched IDs produce misleading LSP hover info and confusing error output. Unified pool fixes that. Side tables need debug-mode assertions for population.
- **AI/ML:** Implicit TK_*/CT_* mapping is exactly the kind of confusion that makes AI debugging unreliable. One canonical identity with phase-isolated side tables minimizes decision points.

---

**Q3: Interning / deduplication (5-0 for A: full interning via Map)**

- **Systems:** Type equality as integer comparison is the biggest win. Every trait bound check, overload resolution hammers equality. O(1) vs O(depth). Textbook zero-cost-at-use-site trade-off.
- **Web/Scripting:** Every scripting language developer's model is "same type." O(1) equality makes error messages, IDE tooling, and query system faster. String atoms are the same idea.
- **PLT:** Canonical representation eliminates bugs where structurally equal types fail referential equality. Used by every serious compiler (Rust, GHC, Java). Future concern: sharded interning for parallel compilation.
- **DevOps:** LSP lookup, diagnostics dedup, incremental dirty-set computation all become integer comparisons. Difference between responsive and laggy for daemon workloads.
- **AI/ML:** `a == b` for type equality is fewer decision points, fewer tokens. Canonical representations make diagnostics deterministic and debugging output cacheable.

**Shared concern:** Interning map key construction must be canonical. Compound types constructed in different orders must produce the same key. Inference variables should not be interned — only fully-resolved types.

**Implementation status (br v76b0b):** Q3 is implemented for `ty_pool` compound types
(`List`, `Option`, `Result`, `Map`, `Set`, `Tuple`, struct/enum instances, `Fn`, and typevars).
Each `make_*_type` constructor delegates to a shared `ty_intern` (`Map[Str,Int]`) keyed on the
raw child tids as stored — never `tc_resolve`'d, never over recursive structure. `new_type`
itself remains un-interned, so `make_metavar` (fresh inference variables) can never be swept
into interning, per the "inference variables should not be interned" concern above. Corpus-wide
same-type mono-registry slot-conflicts went from 25 to 0.

**Known incompleteness, accepted for v1:** a compound minted wrapping an unbound metavar (e.g.
`Option[α]` from a bare `None`) is correctly left un-interned at construction time. If that
metavar is later bound to a concrete type, the existing compound tid still carries the old,
metavar-keyed identity — a later canonical construction of the same now-resolved type mints a
second tid. Closing this needs rehash-on-bind plus a tid-forwarding/union-find layer (no
existing holder of the old tid gets rewritten). Tracked as follow-up `98nsfa`. Until it lands,
`tc_tid_same_type` (structural comparison) remains the sanctioned way to compare tids that may
predate a metavar bind site — `a == b` is not a safe universal replacement, only a fast path
for canonically-constructed compounds.

---

### AI-First Review

| Criterion | Score | Notes |
|-----------|-------|-------|
| Learnability | PASS | Mirrors existing parser node pool (`np_*` arrays). One rule: types are tree nodes with integer handles. |
| Consistency | PASS | Parallel-array pools + accessor functions match established codebase pattern. |
| Generability | PASS | Bottom-up construction: `type_list(type_option(type_int()))`. No overloaded fields. |
| Debuggability | PASS | Recursive `type_display()` prints any type at any depth. Mismatch diagnostics pinpoint divergence. |
| Token Efficiency | PASS | ~30-40% reduction in type-construction code. `ScopeVar` shrinks from 8 fields to 3. |

Score: 5/5 pass. No reconsideration needed.

### Implementation Notes

**Pool design (parallel arrays, interned):**

```blink
pub let mut tp_kind: List[Int] = []
pub let mut tp_child1: List[Int] = []
pub let mut tp_child2: List[Int] = []
pub let mut tp_sname: List[Str] = []
pub let mut tp_count: Int = 0
pub let mut tp_intern: Map[Str, Int] = Map()
```

**Nested type construction:**

```blink
// List[Option[Int]]
let t_int = type_int()
let t_opt = type_option(t_int)
let t_list = type_list(t_opt)

// Result[Map[Str, List[Int]], MyError]
let t_map = type_map(type_str(), type_list(type_int()))
let t_result = type_result(t_map, type_struct("MyError"))
```

**ScopeVar simplification:**

```blink
// Before: 8 fields, 5 overloaded
type ScopeVar { name: Str, ctype: Int, is_mut: Int, inner1: Int, inner2: Int, sname: Str, sname2: Str, extra: Str }

// After: 3 fields, zero overloading
type ScopeVar { name: Str, ty: Int, is_mut: Int }
```

**Bootstrap protocol (5-step):**

1. Add `tp_*` pool alongside old `CT_*` system; bridge functions convert between them → `task regen`
2. Migrate compiler source to dual-write both old fields and new `type_id` → `task regen`
3. Switch readers to prefer `type_id`, fall back to old fields → `task regen`
4. Remove writes to old fields; `type_id` is authoritative → `task regen`
5. Remove old fields from ScopeVar, delete `CT_*` constants, remove 17+ parallel registries → `task regen`

**Migration trigger for enum upgrade:** When the compiler supports struct-in-list / enum-with-data in lists, migrate from parallel arrays to `List[TypeInfo]` enum representation.
