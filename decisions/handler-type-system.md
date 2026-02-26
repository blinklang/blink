[< All Decisions](../DECISIONS.md)

# Handler Type System — Design Rationale

### Panel Deliberation

Five panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML) voted independently on 5 questions.

**Q1: Handler[E] type identity (5-0 for generic type)**

- **Systems:** `Handler[E]` compiles to one vtable struct per effect. The type parameter is erased at codegen — at C level, `Handler[DB]` and `Handler[IO]` are different structs with different function pointer layouts. The generic type constructor is a source-level abstraction over effect-specific vtables. Correct and zero-cost.
- **Web/Scripting:** A single `Handler[E]` type makes the mental model simple — handlers are values, parameterized by which effect they handle. No need for separate `DBHandler`, `IOHandler` types. Matches how TypeScript generics work.
- **PLT:** `Handler[E]` is a type constructor indexed by effect declarations, analogous to `List[T]` indexed by types. The kinding rule is `Handler : Effect -> Type`. Standard parametric polymorphism over the effect namespace.
- **DevOps:** One type constructor means one autocomplete pattern, one hover format, one diagnostic template. LSP shows `Handler[DB]` uniformly regardless of which effect.
- **AI/ML:** `Handler[E]` is the pattern in every code example. LLMs already generate it correctly from existing spec examples. Formalizing what's already in practice.

**Q2: Effect subtyping on handlers (3-2 for implicit projection)**

- **Systems:** Implicit projection. `Handler[DB]` used where `Handler[DB.Read]` expected → compiler extracts `read` slot from the DB vtable and builds a projected handler. Not subtyping — a mechanical extraction. No runtime dispatch, no vtable indirection. Clean codegen.
- **Web/Scripting:** Covariant subtyping. If `DB > DB.Read` in the effect hierarchy, then `Handler[DB]` should be a subtype of `Handler[DB.Read]` — standard variance. Projection is an implementation detail that shouldn't leak into the mental model. *(dissent)*
- **PLT:** Implicit projection. True subtyping on handlers would require the type system to track variance of the handler type constructor with respect to effects — complexity that buys nothing over mechanical slot extraction. Projection is semantically transparent and verifiable.
- **DevOps:** Implicit projection. The compiler generates the projected vtable — users see a clean "OK" at the call site. Error messages for the reverse direction ("Handler[DB.Read] cannot satisfy Handler[DB]") are precise and actionable.
- **AI/ML:** Covariant subtyping. "DB is bigger than DB.Read, so Handler[DB] works where Handler[DB.Read] is needed" is the simplest mental model. LLMs reason about subtyping better than projection mechanics. *(dissent)*

**Q3: Generic handler parameters (4-1 for no generics v1)**

- **Systems:** No generics v1. Effect-kinded generics require a kinding system (`E: Effect`), monomorphization over effects, and interaction with evidence-passing. Doable but adds compiler complexity. Ship concrete handlers, add generics with named effect variables in v2.
- **Web/Scripting:** No generics v1. `Handler[DB]` and `Handler[IO]` are what people write. Generic-over-effect functions are a library-author concern, not a day-one need.
- **PLT:** Effect-kinded generics now. `fn apply_handler[E: Effect](h: Handler[E], f: fn() ! E)` is the principled way to write handler combinators. Without it, every handler combinator must be written per-effect, defeating the purpose of first-class handlers. *(dissent)*
- **DevOps:** No generics v1. Simpler LSP, simpler diagnostics. Concrete handler types are easier to display and reason about in tooling. Generics can be added without breaking changes.
- **AI/ML:** No generics v1. Effect-kinded generics have zero training data. LLMs would hallucinate syntax. Concrete handlers cover all practical v1 use cases (testing, DI, sandboxing).

**Q4: Handler storage (4-1 for full first-class)**

- **Systems:** Restricted. Handlers stored in long-lived data structures (struct fields, collections) risk holding stale vtable references if the handler's captured state is invalidated. Limit to local variables, function parameters, and `with` blocks. Storing in structs requires `'static`-like lifetime guarantee. *(dissent)*
- **Web/Scripting:** Full first-class. Handlers are GC-managed values — no dangling references by construction. Storing a handler in a struct field is identical to storing any other GC-managed value. Restricting storage would make the `TestEnv` pattern impossible.
- **PLT:** Full first-class. In a GC'd language, all values have the same storage semantics. Artificially restricting handler storage introduces a second class of values — exactly the complexity Pact rejected by choosing GC over ownership. Handlers are values; values can be stored anywhere.
- **DevOps:** Full first-class. The `TestEnv { db: Handler[DB], io: Handler[IO] }` pattern is the natural way to build test fixtures. Restricting it forces workarounds (factory functions, closures) that are strictly worse.
- **AI/ML:** Full first-class. Every GC'd language allows storing any value anywhere. Restrictions would be a novel pattern with zero training data, guaranteed to confuse LLMs.

**Q5: Handler completeness (5-0 for partial with auto-delegation)**

- **Systems:** Partial + auto-delegation. Most handler use cases override 1-2 operations (logging wrapper, restricted sandbox). Requiring all operations makes simple wrappers verbose. Auto-delegation to `default.op(args)` is the evidence-passing equivalent of prototype chain delegation — the enclosing handler's vtable slot is called.
- **Web/Scripting:** Partial + auto-delegation. Middleware pattern: override what you care about, pass through everything else. Express/Koa devs write `next()` constantly — `default.op(args)` is the same concept. Full completeness would make every handler as verbose as the full effect definition.
- **PLT:** Partial + auto-delegation. The handler algebra requires a default case for compositional reasoning — a handler that only overrides `read` should compose with any handler that provides `write` and `admin`. Auto-delegation provides this. Explicit `default.op(args)` remains available for custom forwarding logic.
- **DevOps:** Partial + auto-delegation. Compiler generates the forwarding code, zero boilerplate. Diagnostics can still warn when a handler overrides nothing (likely a mistake). LSP can show which operations are auto-delegated on hover.
- **AI/ML:** Partial + auto-delegation. LLMs generating test handlers will typically only mock the operations under test. Requiring completeness means the model must generate stubs for every operation — more tokens, more error surface, more maintenance burden when operations are added to an effect.

