[< All Decisions](../DECISIONS.md)

# Serialization / Deserialization Story — Design Rationale

### Panel Deliberation

Five panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML) voted independently on 7 questions. Strong consensus on all questions, with two split votes.

**Context:** Every web service needs JSON serialization, but Pact had no `@derive(Serialize)` or codec story. The `@derive` annotation already supports 6 traits (Eq, Ord, Hash, Clone, Display, Debug). Examples show `json.serialize(forecast)` and `Response.json(user)` patterns. The "One Way" principle demands a single blessed approach.

**Q1: Trait or annotation for serialization? (5-0 for A: `@derive(Serialize, Deserialize)` trait impls)**

- **Sys (A):** Trait-based dispatch monomorphizes cleanly. `to_json()` compiles to a direct function call per type — zero vtable overhead. Extends the existing `@derive` mechanism with no new compiler concepts.
- **Web (A):** `@derive(Serialize, Deserialize)` is the Rust serde pattern — massive training data. Developers get it immediately. One line on the struct and you're done.
- **PLT (A):** Traits are the principled mechanism for ad-hoc polymorphism. `Serialize` and `Deserialize` are textbook type classes. Using traits means the type system enforces serialization constraints — `fn send[T: Serialize](data: T)` statically guarantees the argument is serializable.
- **DevOps (A):** Trait-based approach produces clear error messages: "Type `Foo` does not implement `Serialize`" with "add `@derive(Serialize)`" help text. The annotation-only approach would require new diagnostic infrastructure.
- **AI (A):** `@derive(Serialize)` mirrors Rust's `#[derive(Serialize)]` — the single most common derive in Rust training data. LLMs will generate this correctly >95% of the time.

**Q2: Field customization in v1? (3-2 for B: no field renaming)**

- **Sys (B):** Field renaming is syntactic sugar with runtime cost (name lookup tables). Ship v1 without it — if struct field names match JSON keys, zero overhead. Add `@json("name")` in v2 when the derive macro system is more mature.
- **Web (A):** Real-world APIs use snake_case, camelCase, and kebab-case. Without `@json("field_name")`, every API integration requires manual serialization. This is a day-one need. *(dissent)*
- **PLT (B):** Adding field-level annotations requires the compiler to process annotation arguments at the field level — a new capability. The type-to-JSON mapping should be structural for v1. Renaming is a v2 concern once the derive system supports annotation introspection.
- **DevOps (A):** Real APIs don't match Pact naming conventions. `@json("firstName")` is essential for interop. Without it, users bypass `@derive` entirely and write manual conversion, defeating the purpose. *(dissent)*
- **AI (B):** Zero field customization means zero decision points per field. LLMs don't have to choose between `@json("name")` and no annotation. One pattern: fields always match JSON keys.

**Q3: Codec dispatch model? (5-0 for A: JSON-specific `Serialize` trait)**

- **Sys (A):** JSON-specific trait compiles to direct calls. No type erasure, no generic codec dispatch overhead. If TOML or YAML are needed later, add `TomlSerialize` — a separate trait is cheaper than a generic framework.
- **Web (A):** JSON is 99% of serialization in web services. YAGNI for codec-generic. TypeScript doesn't have a generic codec system and nobody misses it.
- **PLT (A):** A codec-generic `Serialize[Format]` requires associated types or higher-kinded types (`F.Value`, `F.Error`) which Pact doesn't have in v1. The JSON-specific trait is sound and complete for v1. Codec generics can be added in v2 without breaking changes.
- **DevOps (A):** Simple trait = simple error messages. `Serialize[Format]` would produce error messages mentioning `Format.Encoder` and `Format.Value` — confusing for new users.
- **AI (A):** JSON-specific serialization is overwhelmingly dominant in training data. Codec-generic patterns (like Swift's `Codable`) are less represented and more error-prone in LLM generation.

**Q4: Tier 1 or Tier 2? (5-0 for A: Tier 1, ships with compiler)**

- **Sys (A):** Serialization traits must be compiler-known for `@derive` to work without custom derive infrastructure. Tier 1 is the only option that makes `@derive(Serialize)` zero-config.
- **Web (A):** Every web service needs JSON. Making it Tier 2 means every project starts with `pact add std.json`. That's friction for the most common use case.
- **PLT (A):** `Serialize` and `Deserialize` interact with the type system via `@derive` — they must be compiler-known. This is analogous to `Eq` and `Hash` being Tier 1.
- **DevOps (A):** Tier 1 means `@derive(Serialize)` works in every LSP session without project configuration. Zero-config tooling support.
- **AI (A):** Tier 1 eliminates an import decision. LLMs generate `@derive(Serialize)` and it just works — no "did you add std.json to pact.toml?" failures.

**Q5: Option[T] handling in JSON? (5-0 for A: None → null)**

- **Sys (A):** `null` is a concrete JSON value with well-defined semantics. Omitting fields creates variable-width structs in the JSON, complicating parsing. `null` maps 1:1 to `None`.
- **Web (A):** JavaScript's `null` is the standard. Every JSON library in every language maps `None`/`nil`/`null` to JSON `null`. Go's `omitempty` is the exception, not the rule.
- **PLT (A):** `Option[T]` is isomorphic to `T | null` in JSON's type system. `None → null` is the natural embedding. Omitting fields requires type-level field presence tracking.
- **DevOps (A):** `null` in JSON output is inspectable. Missing fields are ambiguous — was the field removed from the schema, or is it absent because of a bug?
- **AI (A):** `None → null` matches the dominant pattern in training data (serde, Jackson, System.Text.Json). Omit-field behavior requires additional annotations, adding decision points.

**Q6: Error type? (4-1 for C: single `JsonError`)**

- **Sys (C):** One error type, one match arm. JSON errors are JSON errors whether from serialization or deserialization. A single `JsonError` with a message string is sufficient.
- **Web (C):** `JsonError` is simple and familiar. `try { json.parse(s) } catch (JsonError e)` is the pattern every web developer knows. Splitting into two types doubles the error handling surface for no user benefit.
- **PLT (B):** Serialization and deserialization are distinct operations with different failure modes. `SerializeError` occurs when a type can't be represented (e.g., infinite recursion). `DeserializeError` occurs when input doesn't match expected structure. Conflating them loses information. *(dissent)*
- **DevOps (C):** One error type means one error code range, one diagnostic message format, one thing to search for in docs. The message string carries the specifics.
- **AI (C):** Single `JsonError` is one pattern to learn. Separate types double the error handling decision points. `ConversionError` precedent (voted 3-2 for single fixed type) supports this.

**Q7: Purity of serialization? (5-0 for A: pure)**

- **Sys (A):** `to_json()` is a pure function from data to data. No allocation beyond the return value. Streaming serialization is an optimization concern for v2.
- **Web (A):** Serialization should never have side effects. `JSON.stringify()` is pure. `json.dumps()` is pure. Users expect this.
- **PLT (A):** Serialization is a morphism between data types — inherently pure. IO effects belong to the caller who writes the bytes. Mixing serialization with IO would pollute effect signatures everywhere.
- **DevOps (A):** Pure serialization is testable without effect handlers. `assert_eq(user.to_json(), expected_json)` — no mock setup needed.
- **AI (A):** Pure functions are the safest pattern for LLM generation. No effect declarations to get wrong, no handler setup to forget.

### Resolution

Serialization uses `@derive(Serialize, Deserialize)` to generate trait implementations, extending the existing derive mechanism. `Serialize` has a single method `fn to_json(self) -> JsonValue` and `Deserialize` has `fn from_json(json: JsonValue) -> Result[Self, JsonError]`. Both traits are compiler-known (Tier 1) and derivable via `@derive`. Serialization is pure — IO effects belong to the caller. `Option[T]` maps to JSON `null` for `None`. Field names must match JSON keys exactly in v1 (no `@json("name")` renaming). A single `JsonError` type covers both directions. See §3.6.2 for the full specification.

