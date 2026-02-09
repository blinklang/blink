# Friction Log

AI + human friction encountered while building the Pact compiler. Captures pain points, ambiguities, and surprises for future spec revision.

Format: append new entries at the bottom.

Categories: `syntax` | `types` | `codegen` | `ergonomics` | `ambiguity` | `tooling` | `spec-gap`
Severity: `papercut` | `annoying` | `blocking`
Source: `ai` (Claude) | `human` | `both`

---

### 2026-02-07 — Sublist API is a silent corruption footgun
- **Category:** `codegen`
- **Severity:** `annoying`
- **Source:** `ai`
- **Context:** Implementing `merge_programs()` for multi-file imports
- **Description:** The sublist system (`new_sublist` / `sublist_push` / `finalize_sublist`) uses a shared `sl_items` array. If you create multiple sublists upfront and then interleave pushes to them, all sublists get the same `sl_start` and `finalize_sublist` computes wrong lengths. There's no error — you just get silently corrupted data that crashes later in `generate()` with an opaque "list index out of bounds: -1". Had to restructure to collect into Pact `List[Int]` temporaries first, then build each sublist sequentially (create → fill → finalize, one at a time). The API shape invites the wrong usage pattern. Consider: (a) making `new_sublist` set `sl_start` at finalize-time instead of creation-time, or (b) adding a runtime check that no other sublist is "open" when pushing.
- **Update 2026-02-08:** This bug resurfaced in the pattern parser — struct/tuple/enum/or-pattern parsing all called `parse_pattern()` inside open sublists, causing silent corruption (pact-203). Fixed all pattern sublist sites to use the collect-then-build pattern. The API footgun remains; all current call sites are now safe.

### 2026-02-07 — Module-level `let mut` redeclaration semantics are confusing
- **Category:** `ambiguity`
- **Severity:** `papercut`
- **Source:** `ai`
- **Context:** Understanding how parser and codegen share the `np_*` node pool arrays in the amalgamated compiler
- **Description:** The amalgamated `pactc.pact` has duplicate `let mut np_kind: List[Int] = []` declarations (one from parser section, one from codegen section). The codegen deduplicates these to a single C variable, and only the first initialization runs. This works but is confusing — nothing in the spec or the code makes it obvious that the second declaration is a no-op rather than creating a new binding. This is an artifact of the amalgamation process, but it exposed a spec gap: what *should* happen when a module-level `let` name is declared twice? Error? Shadow? Merge? The spec should clarify.

### 2026-02-07 — Import system defeats `pub` visibility by requiring everything be `pub`
- **Category:** `spec-gap`
- **Severity:** `annoying`
- **Source:** `ai`
- **Context:** Splitting pactc.pact into 6 multi-file modules using the import system
- **Description:** The import system only brings `pub`-marked items into the merged program. But when an imported `pub fn` references module-internal helpers (non-pub functions, constants), those helpers are missing from the merged C output — the codegen emits calls to undeclared symbols. The fix was making *everything* `pub` in every module, which defeats the purpose of `pub` entirely. Root cause: the import mechanism operates at the AST declaration level (filtering which top-level nodes to include), but function bodies contain unresolved references to their module's internal symbols. Either: (a) the import system needs to transitively include non-pub items that pub items depend on, (b) codegen needs to emit all items from a module when any item from it is imported, or (c) the compilation model should change so each module is compiled to C independently and linked, rather than merging ASTs.

### 2026-02-08 — Closure const-qualifier warnings flood every call site
- **Category:** `codegen`
- **Severity:** `annoying`
- **Source:** `ai`
- **Context:** Implementing HOF support (pact-222) and immutable captures (pact-218)
- **Description:** Closures are emitted as `const pact_closure*` variables (since the binding is immutable `let`), but calling through `fn_ptr` requires casting and passing `self` as the first argument — which expects `pact_closure*` (non-const). Every single closure call site generates a `-Wdiscarded-qualifiers` warning. Similarly, `pact_list_len`/`pact_list_get` in runtime.h don't accept `const pact_list*`, so any list stored as `const` triggers the same warning. The bootstrap output has dozens of these. Fix options: (a) make runtime.h functions accept `const` pointers where they don't mutate, (b) emit closures as non-const `pact_closure*`, (c) generate explicit casts at call sites to suppress warnings.

