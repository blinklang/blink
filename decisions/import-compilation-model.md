[< All Decisions](../DECISIONS.md)

# Import Compilation Model — Design Rationale

### Panel Deliberation

Five panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML) voted independently on 3 questions. All votes unanimous.

**Context:** Friction log (Feb 7, 2026) identified a critical flaw: the import system only brings `pub`-marked items into the merged C output, but when those `pub` functions reference module-internal helpers, the helpers are missing — gcc reports undefined symbols. The workaround was making everything `pub`, defeating visibility entirely. Root cause: the import mechanism filters AST declarations by visibility, but function bodies contain unresolved references to their module's private symbols. Three options were proposed: (a) transitive closure — call-graph analysis to include non-pub dependencies of pub items, (b) emit-all — include everything from imported modules, (c) separate compilation — each module to its own `.c` file.

**Q1: Which compilation model? (5-0 for B: emit-all)**

- **Sys (B):** Emit-all unblocks the compiler with a one-line semantic change. Transitive closure (a) requires call-graph analysis — a subset of name resolution that doesn't exist yet. Separate compilation (c) introduces linker orchestration and header generation, a massive yak-shave. Layer on dead-code elimination later when you have a symbol table.
- **Web (B):** TypeScript/JavaScript bundlers do emit-all — pull in entire modules, optionally tree-shake later. Python and Go load entire modules. Developers expect "import a module, it just works." Transitive closure is an optimization for later, not a prerequisite.
- **PLT (B):** Analogous to MLton's whole-program compilation or OCaml's bytecode `.cmo` files. Transitive closure conflates reachability (operational) with visibility (semantic) and breaks with function pointers, vtable dispatch, or indirect effect handlers. Emit-all is sound if pub is enforced at the type-checking level. *(noted: separate compilation is the principled v2 target)*
- **DevOps (B):** Dead simple to implement, eliminates linker errors immediately. Separate compilation requires a symbol table, header generation, and build graph — all missing. Ship (b) now, migrate to (c) when compile times demand it.
- **AI (B):** Simplest mental model for LLM code generation: import a module, everything works. Transitive closure introduces subtle dependency analysis where the AI must reason about call graphs to predict what gets included — exactly the hidden coupling that causes mysterious failures LLMs can't self-diagnose.

**Q2: Should `pub` be enforced or advisory? (5-0 for A: enforced at compile time)**

- **Sys (A):** Every modern systems language enforces visibility at compile time. Advisory means accumulating tech debt in downstream modules that accidentally depend on internals. Design `pub` as enforced from day one.
- **Web (A):** TypeScript enforces `export`, Go enforces capitalization. Advisory visibility leads to "just make it public" culture. Clear error messages enable fast self-correction.
- **PLT (A):** Information hiding is a soundness property, not convenience. Mitchell & Plotkin (1988) showed abstract types are existentials — leaked private constructors break representation independence. Pact's effect system makes this critical: leaked private handlers break effect encapsulation.
- **DevOps (A):** Compile-time enforcement means LSP flags private access instantly, import suggestions only offer pub items, and CI catches violations before anything hits the linker.
- **AI (A):** LLMs handle "clear error, fix it" far better than "works but subtly wrong." Enforced `pub` produces actionable errors ("item `foo` is private, add `pub`") that LLMs self-correct on in one retry.

**Q3: Symbol naming in C output? (5-0 for B: module-qualified for all items)**

- **Sys (B):** Flat names are a collision timebomb. Two modules defining `parse` or `init` cause silent C-level redefinition. Module-qualifying everything matches Rust (mangled), Go (package-prefixed), and makes separate compilation trivial to add later since symbols are already globally unique.
- **Web (B):** `pact_auth_token_validate` in a gcc error immediately tells you where to look. Name collisions between modules are inevitable in real projects. Consistent naming eliminates ambiguity.
- **PLT (B):** Alpha-equivalence tells us binding identity is scope, not string. Private symbols are *more* collision-prone (common names like `helper`, `impl`, `inner`) and need qualification more than pub symbols. Mixed schemes (c) are incoherent.
- **DevOps (B):** At 2 AM staring at a gdb backtrace, `pact_auth_token_validate` tells you exactly which module crashed. Flat `pact_validate` tells you nothing. Consistent naming prevents the two-tier debugging experience where private helper crashes produce useless stack frames.
- **AI (B):** When AI-generated code hits C compiler errors, module-qualified names let the LLM map symbols back to Pact source unambiguously. Mixed naming means reasoning about pub/private just to parse gcc errors.

### Cross-language Survey

| Language | Compilation Unit | Visibility Enforcement | Symbol Naming |
|----------|-----------------|----------------------|---------------|
| C | Translation unit (`.o`) | `static`/`extern` at link time | Flat (collision is programmer's problem) |
| Rust | Crate (whole-crate) | `pub` enforced at compile time | Fully mangled with crate+module path |
| Go | Package (all files) | Capitalization enforced at compile time | Package-qualified |
| Zig | Per-file modules | `pub` enforced at comptime | Fully-qualified mangled names |
| OCaml | Separate (`.cmo`/`.cmx`) | `.mli` interface files | Module-qualified |
| Haskell (GHC) | Separate (`.hi` interface) | Export list enforced by type checker | Fully-qualified z-encoded |
| TypeScript | Module-level | `export` enforced at compile time | Bundler-mangled unique identifiers |
| Python | Module-level (load all) | `_prefix` advisory (widely criticized) | Module-qualified at runtime |
| Swift | Whole-module default | `public`/`internal`/`private` enforced | Module-qualified mangled |

Universal pattern: compile the whole module, enforce visibility in the front-end, qualify all symbols.

### Resolution

The Pact compiler uses **emit-all** compilation: when any item from a module is imported, all items (pub and non-pub) are included in the generated C output. The `pub` keyword controls **Pact-level visibility** — using a non-pub item from outside its module is a compile error, enforced by name resolution. In generated C, all symbols use **module-qualified names** (`pact_<module_path>_<item_name>`) to prevent collisions and enable debuggability. Separate compilation (one `.c` per module, link together) is the planned v2 optimization when compile times warrant it. See §10.8 for the full specification.

