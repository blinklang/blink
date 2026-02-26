[< All Decisions](../DECISIONS.md)

# JSON Codec Design — Design Rationale

### Panel Deliberation

Five panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML) voted independently on 4 questions. Each expert ran as a separate agent and returned votes without seeing other experts' reasoning.

**Q1: Dynamic vs typed entry point (4-1 for C: both as equal peers)**

- **Systems (C):** Both paths serve different codegen profiles. Dynamic parsing allocates a single GC'd JsonValue tree — predictable, one allocation pattern. Typed deserialization through `json.decode[T]` compiles to the same parse + field extraction but with monomorphized field access. Neither subsumes the other.
- **Web (C):** JS devs expect `JSON.parse()` for quick prototyping and exploration. But production code wants typed deserialization. Having both at the same level mirrors the JS → TypeScript progression. `json.parse()` for the REPL, `json.decode[User]()` for the service.
- **PLT (A):** `json.parse : Str → Result[JsonValue, JsonError]` and `from_json : JsonValue → Result[T, JsonError]` are two composable morphisms. `decode` is their composition — a derived operation, not a peer. Elevating it to "equal" status obscures the algebraic structure. *(dissent)*
- **DevOps (C):** Dynamic and typed paths produce different diagnostic surfaces. `json.parse` + navigation gives runtime path errors ("key 'age' not found"). `json.decode[User]` gives structural errors ("field 'age' expected Int, got String"). Both are valuable, neither is reducible.
- **AI (C):** `json.parse(s)` maps directly to Python/JS training data — the two dominant JSON patterns. `json.decode[User](s)` maps to Rust/Go typed patterns. Having both means LLMs can use whichever pattern has stronger signal for the context.

**Q2: Module API surface (4-1 for B: medium 5 functions)**

- **Systems (B):** `json.encode[T]` eliminates the two-step `json.stringify(x.to_json())` ceremony. The compiler can fuse these into a single pass. `json.pretty` is trivial sugar but prevents every project from writing their own indentation function.
- **Web (B):** `json.encode(user)` is the `JSON.stringify(user)` equivalent every web developer expects as a one-liner. `json.pretty()` is the first thing anyone reaches for when debugging. These five functions are the complete "80% API."
- **PLT (A):** `json.encode[T](x)` is trivially `json.stringify(x.to_json())` — a two-character pipe. Adding derivable convenience functions to the module surface violates minimality. Three functions form the algebraic basis; the rest are derived. *(dissent)*
- **DevOps (B):** Five autocomplete entries in LSP is immediately discoverable. `json.pretty` prevents the inevitable "how do I pretty-print JSON in Pact" FAQ. Every real project needs it; stdlib should provide it.
- **AI (B):** `json.encode(user)` is the single most common serialization pattern across all training data. Requiring two-step `json.stringify(user.to_json())` forces LLMs to remember method chaining order — unnecessary decision point.

**Q3: JsonValue navigation return types (5-0 for A: Option-returning)**

- **Systems (A):** Option is zero-cost — null pointer or tag bit. Result carries error string allocation overhead on every navigation call. For chains like `.get("a")?.get("b")?.as_str()`, Option avoids N error allocations for N navigation steps.
- **Web (A):** `json.get("key")?.as_str() ?? ""` is the Pact equivalent of JS optional chaining `data?.key ?? ""`. Familiar, fluent, minimal boilerplate. Result would force `.map_err()` at every step — hostile to the 90% case.
- **PLT (A):** Navigation on a sum type is inherently partial — a `JsonValue.Int` has no string projection. `Option` is the canonical encoding of partiality in type theory. Result implies a meaningful error distinct from "not applicable" — but `.as_str()` on an Int isn't an error, it's a type mismatch the caller expects.
- **DevOps (A):** Option composes with both `?` (propagate None) and `??` (provide default). Result would require matching error types with the enclosing function's error — and Pact requires exact error match, so every `.get()` would need `.map_err()`. Diagnostic-hostile.
- **AI (A):** `.get("key")?.as_str() ?? ""` is a single learnable three-part pattern (navigate, project, default). Each piece uses a Pact feature LLMs already know. Result would add error handling boilerplate that varies per context — more decision points, more generation errors.

**Q4: Two-step vs one-step deserialization (5-0 for A: two-step canonical)**

- **Systems (A):** `from_json(JsonValue)` is already the trait method — decided in §3.6.2. `json.decode[T]` is mechanically `json.parse(s) |> T.from_json()`. No new trait surface, no new codegen path. The compiler can optimize the composition.
- **Web (A):** Two-step matches the mental model every developer has: parse the text, then validate the shape. When something goes wrong, you know which step failed. `json.decode[T]` is the one-liner shortcut for when you don't care.
- **PLT (A):** Composition: `decode = from_json ∘ parse`. The Deserialize trait takes `JsonValue` (already committed). Changing to a string-based trait would contradict §3.6.2 and lose the ability to deserialize sub-trees of already-parsed JSON.
- **DevOps (A):** Two-step produces two distinct error locations: parse errors point at line/column in JSON text, type errors point at field mismatches against struct definition. Collapsing into one step merges these error domains.
- **AI (A):** Both `json.parse(s)` and `json.decode[User](s)` are reliably generated patterns. Two-step gives more explicit error handling that LLMs can reason about step by step.

