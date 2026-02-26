[< All Decisions](../DECISIONS.md)

# HTTP Server Routing Model — Design Rationale

### Panel Deliberation

Five panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML) voted independently on 4 questions for the `Net.Listen` effect operation table, middleware composition, error recovery, and `@requires` boundary validation.

**Q1: Server API surface (3-2 for A: minimal value-server)**

- **Systems (A):** The Server value is a flat struct with a function pointer array for routes. Effect boundary is only at `net.listen()` and `server.serve()`, keeping vtable dispatch out of the per-request hot path. Option B routes everything through effect dispatch (indirect branch per route lookup, kills branch prediction). Option C adds unnecessary abstraction — the value-server already IS a route table internally. Matches the existing web_api.pact code, minimizing codegen churn.
- **Web (A):** The existing web_api.pact already shows this pattern and it reads beautifully: `net.listen()` returns a server, you chain `.route()`/`.get()`/`.post()`, then call `.serve()`. This is the Express/Flask/Go pattern every web developer knows. Option B adds ceremony obscuring the "I'm building routes and starting a server" intent. Option C adds indirection; the value-server already lets you build routes programmatically.
- **PLT (C):** Routes-as-data is the principled choice. A `RouteTable` is a pure value admitting algebraic composition (union, intersection, prefix scoping) and compile-time analysis (exhaustiveness, overlap detection). Option A's `.route()` is imperative mutation — order-dependent, opaque to the compiler, not composable. Data admits more equational reasoning than operations. *(dissent)*
- **DevOps (C):** Routes-as-data enables compile-time conflict detection via `pact check`, LSP navigation between routes and handlers, and startup route table dumps for operational visibility. `.merge()` maps to real team composition patterns where different modules contribute routes. *(dissent)*
- **AI/ML (A):** LLMs have seen Flask's `app.route()`, Express's `app.get()`, and Go's `http.HandleFunc()` millions of times in training data. `net.listen() → Server, .route(), .serve()` is a direct structural analogue. Option B has zero training analogues — LLMs would hallucinate incorrect syntax. The existing web_api.pact reinforces this form for fine-tuning.

**Q2: Middleware model (4-1 for A: functional wrapping)**

- **Systems (A):** `fn(handler) -> handler` compiles to direct function pointer composition in C. The wrapping chain collapses at server startup, not per-request. Option B (effect handler stacking) means per-request vtable traversal through nested `with` blocks. Option C requires runtime list iteration with two indirect calls per entry per request.
- **Web (A):** Middleware as `fn(handler) -> handler` is the most proven pattern across web frameworks: Express `app.use()`, Rack, WSGI. Composes naturally, easy to understand. Effect handler stacking forces web devs to think in terms of effect layering just to add CORS headers — massive DX tax. Wrapping means middleware can short-circuit by returning early.
- **PLT (B):** Middleware is cross-cutting computation over request/response flow — precisely what algebraic effect handlers model. Handler stacking gives compositionality, well-scoped lifetimes, and the resumption/abort choice. Algebraically cleaner than functional wrapping which requires manual plumbing. *(dissent)*
- **DevOps (A):** Simple `fn(handler) -> handler` gives clear stack traces showing "logging → auth → handler" for debugging. Effect stacking makes middleware ordering opaque in diagnostics. Middleware debugging is painful enough without indirection.
- **AI/ML (A):** `fn(handler) -> handler` is the single most common middleware pattern across training corpora. Express, Go, WSGI, Rack — all follow this shape. LLMs generate it with extremely high accuracy. Effect handler stacking has essentially zero training signal.

**Q3: Error recovery (3-2 for C: typed error handler)**

- **Systems (C):** Option A (catch_panic) requires setjmp/longjmp — expensive, interacts badly with stack cleanup. Option C gives a `ServerError` tagged union with configurable error handler function pointers per route. No unwinding, predictable control flow. The sum type enables exhaustive match checking.
- **Web (B):** An `on_error` callback with a `ServerError` sum type hits the sweet spot: simple to set up, typed error variants, integrates with pattern matching. Per-route error overrides are over-engineered for the common case — most apps want one global error handler. *(dissent)*
- **PLT (C):** A `ServerError` sum type makes the error domain explicit and pattern-matchable. Placing error handlers alongside routes keeps configuration as a single coherent value. Per-route overrides are semantically important — API routes return JSON, page routes return HTML.
- **DevOps (C):** `ServerError` sum type enables exhaustive handling checks in `pact check` and LSP warnings for unhandled cases. Per-route overrides critical for real APIs (JSON errors for `/api/*`, HTML for `/pages/*`). Putting error strategy alongside routes makes it visible and inspectable.
- **AI/ML (B):** `on_error` with a `ServerError` sum type is closest to Express error middleware, which LLMs generate reliably. Per-route overrides add decision points LLMs will get wrong. One canonical error handler maps naturally onto the dominant training data pattern. *(dissent)*

**Q4: @requires auto-400 boundary detection (4-1 for B: validation effect)**

- **Systems (B):** Compiler emits `validation.contract_violation()` through existing vtable dispatch — zero additional codegen complexity. Default handler returns 400, users swap via standard `with` blocks. Reuses the effect system rather than creating a parallel dispatch mechanism. Also works outside HTTP contexts, so the investment amortizes across the whole language.
- **Web (B):** Most flexible option. `validation.contract_violation()` with default 400 handler means it works out of the box, and users can change to 422 for RFC 9110, add custom formatting (JSON:API, GraphQL errors). Plays beautifully with Pact's `with handler { }` testing pattern.
- **PLT (B):** Most compositional option. Generating `validation.contract_violation()` as an effect operation transforms a static specification (`@requires`) into a dynamic effect that participates in the handler mechanism. Reuses algebraic effect infrastructure — swappable, testable, composable.
- **DevOps (B):** Validation failures appear in effect traces for debugging. Effect handler swapping lets users customize to 422, structured JSON, localized messages without fighting the framework. Option A too rigid, option C overloads the route table.
- **AI/ML (A):** Route-registration marker requires zero effort from the developer or the LLM. Compiler auto-detects `.route()` calls and generates 400 responses for contract violations. Zero new concepts — LLMs just write `@requires` and register routes. Options B and C add concepts the LLM must learn. *(dissent)*

