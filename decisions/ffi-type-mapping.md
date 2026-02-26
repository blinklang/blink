[< All Decisions](../DECISIONS.md)

# FFI Type Mapping — Design Rationale

### Panel Deliberation

Five panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML) voted independently on 3 questions. Resolves Tier 3 gap: "FFI type mapping."

**Q1: Pointer type model (4-1 for non-null `Ptr[T]`, `Ptr[T]?` nullable)**

- **Systems:** Non-null default (Option B). Maps cleanly to `T*` in C. Null-checks at FFI boundaries are zero-cost for the non-null path. Separating const/mut adds type system complexity with no codegen benefit — C enforces const on its side, not Pact.
- **Web/Scripting:** Non-null default (Option B). Reuses the nullable pattern every TS/Kotlin/Swift dev already knows. `T` vs `T?` is universal. Option A (everything nullable) is C's footgun. Option C (const/mut) adds a concept nobody writing a wrapper cares about.
- **PLT:** Non-null default (Option B). Preserves the Curry-Howard correspondence Pact exploits via `Option[T]`. Nullability IS the partiality monad — encoding it in `Option` means existing elimination forms (`match`, `??`) compose with pointer types with zero ad-hoc rules.
- **DevOps:** Non-null default (Option B). Reuses existing `Option`/`?` diagnostic infrastructure. LSP hover can distinguish "guaranteed non-null" vs "may be null." Autocomplete surface stays small.
- **AI/ML:** Single nullable `Ptr[T]` (Option A). Zero decision points. LLMs generating FFI code already struggle with C pointer semantics; adding a nullability decision increases error rates. *(dissent)*

**Q2: Pointer operations (5-0 for minimal + deref/write/null)**

- **Systems:** Option B. Option A is too minimal — you'd need C shims for every pointer read/write. `deref()` and `write(T)` map to single load/store instructions in C. Option C's `cast[U]()` and `offset(Int)` are pointer arithmetic footguns in a GC'd language.
- **Web/Scripting:** Option B. Option A has no deref — can't read what a pointer points to. Option B has exactly the four things a wrapper author needs: read, write, null-check, null construction. Option C (`cast`, `offset`, `free`) are expert footguns.
- **PLT:** Option B. `deref` is correctly typed as partial — return MUST be `Option[T]`. Option A is practically unsound (can't inspect values without FFI round-trips). Option C's `cast[U]()` destroys parametricity — it's `unsafeCoerce` and cannot be given a sound typing rule.
- **DevOps:** Option B. Gives the compiler enough info to emit structured null-safety warnings. Option A has zero diagnostic story for null derefs. Option C's `cast`/`offset` create pointer arithmetic errors nearly impossible to diagnose well.
- **AI/ML:** Option B. Covers exactly the patterns LLMs reach for. Option A's 3-op minimum causes hallucination: the LLM "knows" deref should exist and will generate it anyway. Option C's full surface creates decision paralysis.

**Q3: Lifetime and cleanup (3-2 for scoped `ffi.scope()` via Closeable)**

- **Systems:** Hybrid (Option D). Two real FFI patterns: short-lived marshaling (scope/arena) and long-lived opaque handles (GC finalizer). Neither alone suffices. *(dissent)*
- **Web/Scripting:** Hybrid (Option D). "Don't think about it" (GC) for the common case, deterministic cleanup (`with` block) when C requires explicit free. Matches Python `with` and JS explicit resource management. *(dissent)*
- **PLT:** Scoped (Option C). Only choice giving lexically scoped lifetime — minimal structure for soundness without linear types. Composes with existing `Closeable`. `scope.take(ptr)` is the affine typing escape hatch. GC finalizers are unsound for ordered resources.
- **DevOps:** Scoped (Option C). Direct analog to existing `with-resource`/Closeable pattern. Reuses E0601 scope-escape diagnostics. Only option where the compiler can actually help catch leaks.
- **AI/ML:** Scoped (Option C). Maps to Python's `with`, Kotlin's `use`, C#'s `using`. LLMs generate correct scoped cleanup ~85% of the time vs ~70% for manual free. One pattern, high accuracy, zero decision points.

**Resolution:** Scoped `ffi.scope()` is the primary mechanism, with standalone `alloc_ptr` as a GC-registered fallback for trivial cases. This satisfies the Sys/Web concern (both patterns available) while maintaining the PLT/DevOps/AI preference for scope-first design.

