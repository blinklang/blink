[< All Decisions](../DECISIONS.md)

# HTTP Client Effect Mapping — Design Rationale

### Panel Deliberation

Five panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML) voted independently on 4 questions for the `Net.Connect` effect operation table.

**Q1: Method surface — verbs vs request() vs both (4-1 for C: both with request() as core)**

- **Systems (C):** Single `request()` vtable entry = one function pointer. Verb methods are compiler-generated wrappers that inline to direct `request()` calls with pre-populated Request structs. Zero overhead. Handler implementors write one method. The vtable stays minimal — 6 function pointers for verbs would bloat every Handler[Net.Connect] allocation.
- **Web (C):** `net.get(url)` is what every web dev reaches for first — it's the 90% case. But `net.request(req)` covers complex cases (custom methods, multipart, auth flows). Both exist in Python requests (`requests.get()` + `requests.request()`). Handler authors implementing one method is a huge win for the testing story.
- **PLT (C):** The single `request()` operation is the minimal effect interface — one typing rule, one handler obligation. Default methods on effects follow the same principle as Iterator adapters: implement `next()`, get `map`/`filter`/`collect` free. This is compositionally clean — the verb methods are derived, not primitive.
- **DevOps (C):** Handler completeness error saying "missing operation: request" + one-line hint is far better than "missing operations: get, post, put, delete, head, patch" + six-line implementation skeleton. Mock handlers in tests go from 6 methods to 1. LSP autocomplete still shows all verb methods — they're just default-implemented.
- **AI/ML (A):** `net.get(url)` maps directly to `requests.get(url)` from Python training data — the most common HTTP pattern in LLM corpora. Having `request()` as the "real" operation with verbs as sugar means LLMs must understand the desugaring relationship. The verb-method pattern from Python/Rust reqwest has overwhelming training signal. *(dissent)*

**Q2: Request configuration (4-1 for A: Request builder struct)**

- **Systems (A):** Request struct is flat data — method, url, body, headers map, timeout int. Builder methods are field writes, zero allocation beyond the struct itself. The struct compiles to a predictable C struct. Method chaining `.with_header().with_timeout()` is sugar for field assignment — inlined away.
- **Web (C):** Struct with defaults is the most Pact-native pattern. `RequestOptions { timeout: 5000 }` leverages struct defaults — no builder ceremony needed. But builder chaining is also fine for web devs used to fetch options objects. *(dissent)*
- **PLT (A):** Request as a first-class value is compositionally superior — it can be stored, passed, partially configured, and composed. The builder pattern produces a value of type Request; the struct IS the request. Both are the same underlying product type.
- **DevOps (A):** Builder has the best LSP autocomplete story. Typing `Request.new("GET", url).with_` shows all configuration options. Each `.with_*` is a named, discoverable method. Options struct requires knowing field names upfront.
- **AI/ML (A):** Builder chaining (`.with_header().with_timeout()`) is the dominant pattern for request configuration across Python requests, Go http.NewRequest, Rust reqwest, Java HttpClient. LLMs reliably generate builder chains.

**Q3: Response type (5-0 for B: transparent struct)**

- **Systems (B):** Direct field access compiles to struct member access in C — a load instruction, not a function call. `response.status` is a register read. `.status()` method would dispatch through a vtable or at minimum a call instruction. For hot paths checking status codes, this matters.
- **Web (B):** `response.status` and `response.body` are what every developer expects. Destructuring `let Response { status, body, .. } = net.get(url)?` is clean and familiar. Add `.json()` as a convenience method via trait impl — best of both worlds.
- **PLT (B):** A response is a product type (status × body × headers). Making it transparent exposes its algebraic structure for pattern matching. Behavior belongs on traits, not hidden behind opaque accessors. This is the principled separation of data from behavior.
- **DevOps (B):** Field access gives better LSP hover information — "status: Int" is self-documenting. Pattern matching on `Response { status: 404, .. }` produces excellent diagnostics when patterns don't match. Methods would hide the structure.
- **AI/ML (B):** Struct field access is the single most universal pattern across all programming languages. `response.status` has near-100% LLM generation accuracy. Method-based access adds unnecessary indirection that LLMs occasionally get wrong (`.status()` vs `.status` vs `.get_status()`).

**Q4: WebSocket/SSE separation (4-1 for C: defer to v2)**

- **Systems (C):** WebSocket requires persistent connection state, framing protocol, message buffering — completely different codegen from stateless request/response HTTP. Mixing them in the same vtable conflates two distinct runtime models. Ship HTTP, design WebSocket properly later.
- **Web (A):** Web developers expect WebSocket support. Real-time features (chat, notifications, live updates) are core to modern web apps. A separate `Net.WebSocket` sub-effect with `net.ws_connect(url)` would be clean capability separation while still being v1. *(dissent)*
- **PLT (C):** WebSocket introduces stateful bidirectional channels — algebraically different from the request/response pattern. Request/response is `A → B`, WebSocket is a session type. Rushing the design would create type-theoretic problems that are hard to fix later.
- **DevOps (C):** HTTP client is the critical path. WebSocket adds connection lifecycle management, reconnection diagnostics, message ordering tests. Each is a significant diagnostic surface. Ship HTTP, learn from it, then design WebSocket diagnostics properly.
- **AI/ML (C):** WebSocket APIs have much less training data diversity than HTTP client patterns. LLMs will struggle with novel WebSocket-over-effects patterns. Building HTTP first creates canonical training data before adding the next protocol.

