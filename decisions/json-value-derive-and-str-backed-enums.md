[< All Decisions](../DECISIONS.md)

# JsonValue Derive Signatures and Str-Backed Enums — Design Rationale

## The gap

§3.6.2 declares `to_json(self) -> JsonValue` and `from_json(json: JsonValue) -> Result[Self, JsonError]`. The compiler emits Str for both: a derived `to_json` returns JSON text, and a derived `from_json` takes a `Str` and returns `Result[Self, Str]`. About 110 call sites in 19 test files use the Str form. Neither `JsonValue` nor `JsonError` exists in `src/` or `lib/`, and `lib/std/json.bl` ships an integer-handle API (`json_parse`, `json_get`, `json_clear`, ...) in place of the §3.6.3 module surface.

The spec also had two `JsonValue` shapes that did not agree: a user-written example under §3.4 *Recursive Types* (`Boolean`, `Number`, `Object(Map[Str, JsonValue])`) and the compiler-known enum in §3.6.2 (`Bool`, `Int`, `Float`, `Object(List[(Str, JsonValue)])`). The §3.5 nested-pattern example used the first shape.

Second gap: Str-backed enums (`type Status { Open = "open" }`, with a synthesized `to_str` and `from_str`) had no spec text. `tests/test_str_backed_enum.bl` was the feature's only definition.

Decisions already in force: `@derive(Serialize, Deserialize)` generates trait impls (5-0); `Serialize` is JSON-specific and returns `JsonValue` (5-0); Tier 1, compiler-known (5-0); `None` is JSON `null` (5-0); no `@json("name")` field renaming in v1 (3-2); one `JsonError` for both directions (4-1); serialization is pure (5-0); `json.parse` and `json.decode[T]` are peer entry points (4-1); the five-function module surface (4-1); `Option`-returning navigation (5-0); parse then `T.from_json` is canonical and `decode[T]` is sugar (5-0).

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated in independent-proposal → debate → vote rounds. Phase B took one round; every panelist was stable after it. Phase C split closer than 5-1 on five questions (Q3a, Q5, Q6, Q13, Q15), which went to one Phase D round and a silent re-vote. No tie remained, so no tiebreak was needed.

#### Phase A — Independent proposals

Each panelist wrote alone. Text is verbatim, up to each proposal's `Preferred:` line.

##### Systems

> **Sys (systems panelist): Phase A proposal for 169kjt**
>
> The real question is what the machine does between a struct and the bytes on the wire. Today's derive is Str-typed, and the Str part is a type-system bug. The streaming part is correct, and the spec's own model gets that part wrong. So I don't pick (a) or (b) as written.
>
> What the codebase shows:
> - `cg_derive.bl` emits `to_json` as a direct writer: it escapes each field and appends it to one buffer. This is one pass, allocates only the output, and needs no intermediate tree.
> - §3.6.2 builds `JsonValue.Object(List[(Str, JsonValue)])` for every struct and then stringifies it. That is two passes, with one heap node per field, per list and per tuple. On a hot HTTP response path that is pure overhead.
> - `lib/std/json.bl` is a global, process-wide arena with Int handles. `json_clear()` invalidates every live handle, and the arena is not reentrant under `async.spawn`. This API must not become the spec'd surface. At most it can back something as a private detail.
>
> ---
>
> ### Proposal S1: JsonValue as the data model, fused encode/decode paths per type (preferred)
>
> Keep the recorded decisions: `to_json(self) -> JsonValue`, one `JsonError`, the five-function module. Add one rule that says what they compile to.
>
> ```blink
> @derive(Serialize, Deserialize)
> type User { id: Int, name: Str, email: Option[Str] }
>
> // Dynamic path: tree, when the shape is unknown
> let v: JsonValue = u.to_json()
> match v {
>     JsonValue.Object(fields) => io.println("{fields.len()} fields")
>     _ => {}
> }
>
> // Typed path: the one servers use; monomorphized, no tree
> let body: Str = json.encode(u)
> let back: Result[User, JsonError] = json.decode[User](body)
> match back {
>     Ok(user) => io.println(user.name)
>     Err(e) => io.println("bad input: {e.message}")
> }
> ```
>
> Spec changes:
> 1. **Signatures stay as in §3.6.2.** nxnnxe's table flips `to_json` to `-> JsonValue` and `from_json` to `(JsonValue) -> Result[Self, JsonError]`.
> 2. **Specify `encode`/`decode` by result, not by method.** "`json.decode[T](s)` behaves as `json.parse(s)` then `T.from_json(v)`: same accepted inputs, same `Ok` values, same error message." The implementation may fuse the two steps. Derive emits a per-type direct writer and a direct reader, which is today's codegen moved behind `encode`/`decode`. The 5-0 "two-step canonical, decode is sugar" decision holds as semantics. I only argue that "sugar" must not force the implementation to build a tree. Rust serde draws this same line: `serde_json::Value` exists, but `to_string(&T)` never builds one.
> 3. **Keep one JsonValue shape: the §3.6.2 compiler-known one.** Keep the separate `Int`/`Float` variants: i64 IDs above 2^53 survive, unlike in JS and Go `interface{}`. Keep `Object` as `List[(Str, JsonValue)]`: it preserves insertion order and needs no hashing at build time. Linear lookup is fine for typical object sizes. Rename the §3.4 (~1707) recursive-type example to `type Json { ... }` so the spec no longer shows a user declaration that shadows a compiler-known name with a different shape.
> 4. **Make `JsonError` a struct: `type JsonError { message: Str, offset: Int }`.** `offset` is the byte position; use -1 for errors in the tree step. It costs one word, and without it an error on a 2 MB payload is not actionable. Callers can match on a typed error, not on free text. If the panel wants only `message`, per the 4-1 vote, I accept that. A `Str` error is the one thing I reject.
> 5. **Migration:** about 110 test call sites change from `u.to_json()` / `User.from_json(s)` to `json.encode(u)` / `json.decode[User](s)`. This is mechanical. No lib/std code calls these methods.
>
> Tradeoffs:
> - The typed path costs zero extra: output-sized allocation, and monomorphized per T, so no vtable or reflection.
> - The dynamic path pays for the tree only when a user asks for a tree.
> - The cost is two derived bodies per type (tree plus streaming). That is more codegen, but both bodies come from the same field walk.
>
> ---
>
> ### Proposal S2: keep text, give it a type (alternative if S1 is too much work for v1)
>
> This reverses the 5-0 "to_json returns JsonValue" decision, and I argue it explicitly as a reversal. Add a transparent newtype `type JsonText(Str)`. At runtime it is a bare `const char*`, so it costs zero.
>
> ```blink
> let t: JsonText = u.to_json()
> let s: Str = t.to_str()
> let r: Result[User, JsonError] = User.from_json(t)
> ```
>
> - **What it fixes:** double-encoding. With plain `Str`, `Response.json(u.to_json())` quietly escapes an already-encoded string, and the type checker cannot see it. It also fixes the untyped error.
> - **What it costs:** users lose a navigable tree from derive. `JsonValue` then comes only from `json.parse`.
> - **Cross-language note:** this is Go's `json.RawMessage` idea, made nominal.
>
> ---
>
> ### Rejected: plain (a), Str/Str
>
> It fixes the text of the spec by making the language worse. The type checker cannot tell a `Str` that holds JSON from one that doesn't, and a `Str` error cannot be matched on without parsing it. It also locks the arena API's weaknesses into the user contract.
>
> ---
>
> ### Str-backed enums: spec them now, in §3 next to enums
>
> ```blink
> type Status {
>     Open = "open"
>     InProgress = "in_progress"
> }
>
> let s: Str = Status.InProgress.to_str()            // "in_progress"
> let p: Option[Status] = Status.from_str("open")    // Some(Status.Open)
> let q: Option[Status] = Status.from_str("Open")    // None: exact, case-sensitive
> ```
>
> Rules to write down:
> 1. Either every variant has a string literal, or none does. Payload variants are not allowed: it is a compile error.
> 2. Duplicate strings are a compile error. Without this rule, `from_str` is ambiguous, and a match written by hand would pick the first variant silently.
> 3. `to_str` returns a static string with no allocation. It compiles to an array of `const char*` indexed by tag.
> 4. `from_str` is an exact byte comparison. It compiles to a length check plus `memcmp`, or a switch on length. It returns `Option`, not `Result`, which matches `Decimal.from_str`.
> 5. Forced by this gap: `@derive(Serialize)` on a str-backed enum emits the backing string, `"in_progress"`. It must not emit the tagged-object form `{"variant": ...}` from the type-mapping table. That is the whole reason to back an enum with strings, and today the spec's type-mapping table contradicts it. Add a row to that table.
>
> ---
>
> **Preferred:** S1: keep `JsonValue`/`JsonError` as spec'd with one canonical shape, specify `json.encode`/`json.decode[T]` by result so the derive can fuse into a monomorphized streaming writer and reader, and spec str-backed enums, with Serialize emitting the backing string.

##### Web/Scripting

> # Web/Scripting panelist: Phase A proposal for spec gap 169kjt
>
> My test is whether a JS or Python developer gets it right in five minutes, without a Stack Overflow question.
>
> Most web code needs JSON for two jobs:
>
> - turn a struct into text for a response body;
> - turn a request body into a struct, with an error you can show to the client.
>
> Both jobs use text at the edges. Few people ever touch a JSON tree by hand. Everything below serves those two jobs first.
>
> ## Proposal W1: keep JsonValue in the traits, and make `json.encode` / `json.decode` the everyday path (option (b), with the user surface stated plainly)
>
> ```blink
> import std.json
>
> @derive(Serialize, Deserialize)
> type User {
>     name: Str
>     age: Int
>     status: Status
> }
>
> type Status {
>     Active = "active"
>     Banned = "banned"
> }
>
> fn handle(body: Str) -> Str {
>     match json.decode[User](body) {
>         Ok(u) => json.encode(u)
>         Err(e) => "bad request: {e.message}"
>     }
> }
>
> // Dynamic path, for payloads you do not want to model:
> fn city_of(body: Str) -> Option[Str] {
>     let v = json.parse(body).ok()?
>     v.get("address")?.get("city")?.as_str()
> }
> ```
>
> Rules:
>
> - `u.to_json()` returns `JsonValue`. JS works the same way: `toJSON()` returns a value, and `JSON.stringify` makes the text.
> - `json.encode(u)` returns `Str`. This matches Python `json.dumps`, Kotlin `Json.encodeToString` and Rust `serde_json::to_string`.
> - `json.decode[User](s)` returns `Result[User, JsonError]`, the same as Kotlin `decodeFromString<User>`.
> - `JsonError` implements Display, so `"{e}"` works. It carries `message: Str`, which a handler can put straight into a 400 response. A Str error cannot give a handler anything to match on later. A struct can gain fields (path, line) without breaking callers.
> - Writing `User.from_json(text)` with a `Str` must give a specific diagnostic: "`from_json` takes JsonValue; to parse text, use `json.decode[User](text)`". Without that message, this is the single most likely SO question for the feature.
>
> **The two JsonValue shapes.** Keep §3.6.2 as the only compiler-known shape: separate `Int` and `Float`, and `Object` as a list of pairs.
>
> - Separate `Int`/`Float` means an ID such as `9007199254740993` round-trips exactly. JS developers lose data to this bug all the time, so Blink should fix it.
> - Ordered pairs keep key order, which Python and JS developers expect. `.get("key")` covers lookup, so nobody has to walk the pairs.
> - Rename the example at ~1707 (for example, `type Doc { ... }`). A teaching example that re-declares a compiler-known name with a different shape guarantees confused readers, even though §10.6 makes it legal.
>
> **Migration.** About 110 test call sites change mechanically:
>
> - `u.to_json()` becomes `json.encode(u)`;
> - `User.from_json(s)` becomes `json.decode[User](s)`.
>
> No lib/std code calls these methods, and there are no users yet, so this is the cheapest time to break. If we ship the Str signatures and move to JsonValue later, every real user's code breaks.
>
> **Tradeoffs.**
>
> - Cost: much more work. We must build a real `JsonValue` and the 5-function module, and retire the Int-handle arena API in lib/std/json.bl or make it private. That arena API (`json_parse -> Int`) is the worst possible web DX, and nobody coming from any language will guess it.
> - Benefit: it keeps all 12 recorded decisions and needs no reversal.
>
> ## Proposal W2: spec the str-backed enum in §3, including how it maps to JSON
>
> Add a new subsection. The rules:
>
> - `type Status { Open = "open"  InProgress = "in_progress" }` synthesizes `to_str(self) -> Str` and `Status.from_str(s: Str) -> Option[Self]`.
> - `from_str` is case-sensitive and exact. `from_str("Open")` returns None, and the spec must say so, because Python's `Enum("Open")` teaches people to expect a fallback.
> - It is all or nothing: every variant has a string value, and no variant has a payload. Mixing forms is a compile error.
> - Duplicate string values are a compile error.
> - A field of this type serializes as `JsonValue.Str(to_str())`. Deserialize fails with a JsonError that lists the valid values: `unknown value "x" for Status; expected one of: "open", "in_progress"`.
>
> Status and role fields are most of the enums in real APIs, so this mapping matters more than the enum feature itself. This matches TypeScript string enums and Python `class Status(str, Enum)`.
>
> **Open question for the panel:** should `"{status}"` print `open` or `Open`? TS and Python `str`-enums print the value. I lean towards the value, but I will not force it into this ticket.
>
> ## Proposal W3 (fallback only): option (a), Str/Str for v1
>
> ```blink
> let j = u.to_json()               // Str
> match User.from_json(j) {
>     Ok(u) => ...
>     Err(msg) => ...               // Str, cannot match on it
> }
> ```
>
> - Benefit: familiar on day one, the same as Python `dumps`/`loads`, and it matches the code as it is now.
> - Cost:
>   - It reverses three 5-0 votes (JSON-specific trait returning JsonValue, pure `to_json`, two-step canonical parse).
>   - There is no typed error.
>   - There is no dynamic path. Users would fall back to the Int-handle API, and `json_get(json_get(root, "a"), "b")` is not something a web developer should ever write.
>   - Changing to JsonValue later breaks every user.
>
> Take this only if the panel agrees (b) cannot land before v1. Even then, the spec should say "Str in v1, a reserved change later", not quietly drop JsonValue.
>
> **Preferred:** W1 (JsonValue traits, with `json.encode`/`json.decode[T]` as the documented everyday path and a targeted `from_json(Str)` diagnostic), together with W2 (spec the str-backed enum and its JSON mapping).

##### PLT

> Phase A proposal from the PLT panelist (soundness, compositionality, type theory). Verdict: keep `JsonValue` and `JsonError`, retire the Str signatures in three steps, and write the missing Str-backed enum section with explicit laws.
>
> ## The gap in type-theory terms
>
> The Str signatures are not merely out of date. They are the weaker design, and choosing them would reverse four recorded 5-0 and 4-1 votes.
>
> 1. **They do not compose.** `to_json : T -> Str` does not follow the structure of the value. To serialize `List[User]`, each element must be joined as text, and the escaping and nesting rules exist only in codegen, where the type system cannot check them. With `to_json : T -> JsonValue`, the derive for `List[T]` is `Array(items.map(to_json))`. The result is correct because of how it is built.
> 2. **Str carries no meaning here.** Under the current typing, `User.from_json(user.name)` typechecks. "JSON text" and "any string" are the same type, so the type proves nothing.
> 3. **Some decided features cannot be written.** The spec's "Mixed" example (`data: JsonValue` inside a derived struct) and deserializing a subtree of already-parsed JSON (the PLT argument that carried `decode = from_json ∘ parse`, 5-0) both need a tree type. Str-in/Str-out cannot express either.
> 4. **A Str error cannot be matched on.** Callers can only compare text. `JsonError` gives the error a name and a place to add structure later.
>
> ## Proposal P1: realize §3.6.2, and fix the spec where it is unsound or silent (preferred)
>
> **P1.1 One JsonValue shape.** Keep the §3.6.2 enum. Change the §3.4 "Recursive Types" example so it does not declare the compiler-known name. Today that example teaches, without saying so, a §10.6 shadowing of a compiler-known type. Rename it `Tree`, or use any other shape:
>
> ```blink
> type Tree {
>     Leaf(Int)
>     Node(List[Tree])
> }
> ```
>
> `Object(fields: List[(Str, JsonValue)])` is the right choice over `Map`. RFC 8259 allows duplicate keys and keeps key order in the text. A list keeps both, so `stringify(parse(s))` round-trips. A Map would silently lose both. `get(key)` returns the first match, and the spec must say so.
>
> **P1.2 Specify the number split.** JSON has one number type. The Int/Float split is sound only if the spec states a total rule:
> - `parse` gives `Int` when the literal has no fraction and no exponent and fits in i64. It gives `Float` in every other case.
> - Derived `from_json` for a `Float` field accepts `JsonValue.Int` and widens it. Without this rule, `{"temp_c": 20}` fails to decode into `temp_c: Float`, and that is a real bug users will hit.
> - `as_float()` returns `Some` for `Int` too. `as_int()` never narrows a Float.
>
> **P1.3 Migration without a wrong typing in between.** The current codegen already does what `json.encode` and `json.decode` are specified to do. The existing Str behavior can therefore become those two functions, and `to_json`/`from_json` never need a published Str type:
>
> ```blink
> import std.json
>
> @derive(Serialize, Deserialize)
> type User { id: Int, name: Str }
>
> fn main() {
>     let u = User { id: 1, name: "Ann" }
>     let text = json.encode(u)                     // today's u.to_json()
>     match json.decode[User](text) {               // today's User.from_json(text)
>         Ok(back) => io.println(back.name)
>         Err(e) => io.println(e.message)           // JsonError, not Str
>     }
>     let tree = u.to_json()                        // JsonValue
>     let name = tree.get("name")?.as_str() ?? ""
> }
> ```
>
> This follows the 3-step bootstrap:
> 1. Add `json.encode` and `json.decode` over the current Str codegen, with `JsonError { message }`.
> 2. Migrate the ~110 test call sites, which is a mechanical rewrite.
> 3. Retype `to_json`/`from_json` to `JsonValue`. Per the brief, nxnnxe's typecheck table is the one place the derive return types change.
>
> **P1.4 Say which parts are implemented.** Section 3.6.3 is spec-only today, and the spec should mark it that way. The spec defines the language. A gap in the implementation calls for an implementation ticket, not a weaker specification.
>
> Tradeoffs: this is the largest implementation cost. It needs a recursive enum with `List` payloads in the compiler-known prelude, which the boxing work (e1f78s) already makes possible. It also needs a real parse into a tree. In return, every JSON operation is either a total function or an explicitly partial one returning `Option`/`Result`, and the operations compose.
>
> Cross-language: this matches Rust serde_json's `Value` plus `to_value`/`from_value` and Haskell aeson's `ToJSON :: a -> Value`. aeson made the same choice for the same compositional reason, and its `encode` is `toJSON` followed by rendering.
>
> ## Proposal P2: accept Str, done correctly (not preferred)
>
> If the panel reverses the decisions, at least do not use bare Str. Add a newtype `JsonText` so that `from_json(user.name)` is a type error, and make the error `JsonError`, not `Str`. This still loses subtree decoding and the Mixed example, and it contradicts the effect-free "data → data" purity story only in name. I would dissent.
>
> ## Proposal S: spec section for Str-backed enums
>
> This belongs in §3.4 as a sibling of enums. Its typing rules:
> - **All or none.** Every variant has a Str literal, or none does.
> - **No payloads.** Every variant is nullary. A payload variant with `= "x"` is a compile error.
> - **Distinct literals.** Duplicate literals are a compile error. Without this rule, `to_str` is not injective and `from_str` is not a function.
> - **Synthesized surface.** `fn to_str(self) -> Str` and `fn from_str(s: Str) -> Option[Self]`. `Option` is correct because the only failure is "not a member", which is the same partiality rationale as the 5-0 navigation vote.
> - **Laws, stated in the spec and testable:**
>   - `Status.from_str(x.to_str()) == Some(x)` for every `x`.
>   - `from_str(s).map(fn(v) { v.to_str() })` is `Some(s)` or `None`.
>   - Matching is exact bytes and case-sensitive.
> - **Serialize interaction.** A Str-backed enum with `@derive(Serialize)` serializes to `JsonValue.Str(self.to_str())`, not to the tagged object. This is the reason the feature exists (wire enums).
>
> ```blink
> @derive(Serialize, Deserialize)
> type Status {
>     Open = "open"
>     InProgress = "in_progress"
> }
>
> fn main() {
>     let s = Status.from_str("in_progress") ?? Status.Open
>     io.println(s.to_str())                  // in_progress
>     // json.encode(s) == "\"in_progress\""
> }
> ```
>
> Two open questions for the panel:
> 1. Does `"{s}"` (Display) print the backing literal? I say yes, derived, so that interpolation and `to_str` cannot disagree.
> 2. `Decimal.from_str` and `Bytes.from_str` already exist. If their return types differ from `Option`, three `from_str` methods with different codomains get in the way of any future `FromStr` trait. That should be a friction ticket, not a reason to block this section.
>
> Cross-language: TypeScript string enums and Python `StrEnum` (`Status("open")` raises an exception). Rust `#[serde(rename)]` together with `FromStr` is the closest match to these laws.
>
> Preferred: P1 (keep JsonValue/JsonError per §3.6.2, rename the §3.4 example, specify the Int/Float number rules, migrate Str callers to json.encode/decode[T] in three steps), plus S.

##### DevOps

> **Devops/tooling panelist: Phase A proposal (169kjt)**
>
> I judge each option by what a user sees in hover, completion, and error text. The current Str-typed derive is the worst of the three on that measure. `u.to_json()` hovers as `-> Str`, so the IDE can't tell JSON text from a user's name. `User.from_json(name)` type-checks. The error is also a Str, which means a caller can only match on text, and Blink's own diagnostics can't be good either. The derive also needs `import std.json`, and without it the user gets a codegen "not built" message instead of a front-end error.
>
> ---
>
> ### Proposal 1: Rebind the Str path to the spec's own Str entry points, keep JsonValue as the canonical form (no reversal)
>
> The spec already defines two Str-facing functions: `json.encode[T](T) -> Str` and `json.decode[T: Deserialize](Str) -> Result[T, JsonError]`. What codegen emits today is the body of those two functions under the wrong names. So we rename what exists and don't bend the spec to fit it:
>
> ```blink
> import std.json
>
> @derive(Serialize, Deserialize)
> type User {
>     name: Str
>     age: Int
> }
>
> fn main() {
>     let u = User { name: "Alice", age: 30 }
>     let text = json.encode(u)                 // Str
>     match json.decode[User](text) {
>         Ok(u2) => io.println(u2.name)
>         Err(e) => io.println(e.message)       // JsonError, not Str
>     }
> }
> ```
>
> - `JsonError` ships now as the spec's minimal `type JsonError { message: Str }`. I'd like a `path: Str` field (`"age"`, `"items[3].id"`) as well, which is a small new decision to put to a vote. The derive already knows the field path, so the message can read `field 'age': expected Int, found string`. Go gives `cannot unmarshal string into Go struct field User.age of type int`, and serde gives `invalid type: string "x", expected i64 at line 1 column 20`. Both are the level of detail users expect.
> - `to_json(self) -> JsonValue` and `from_json(JsonValue)` stay in the spec as they are. Until `JsonValue` lands, a call to them must fail with a clear front-end error, not an ICE:
>   `error[E….]: 'to_json' needs JsonValue, which this compiler does not build yet; use json.encode(u)`. It carries a machine-applicable fix, so the LSP code action and `blink fix` can rewrite each call site.
> - Migration: about 110 call sites across 19 test files, all in two shapes (`x.to_json()` becomes `json.encode(x)`, `T.from_json(s)` becomes `json.decode[T](s)`). A codemod handles it, and the nxnnxe signature table changes in one place.
> - Tradeoffs: the user can use the full Str round trip today, and no voted decision is reversed. The work is to make generic `json.decode[T]` work under the `T: Deserialize` bound and to add one new diagnostic. The code a user writes today still compiles unchanged once `JsonValue` ships, because encode and decode keep their signatures.
>
> ### Proposal 2 (fallback): the ticket's option (a), correct the spec to Str/Str
>
> This reverses the recorded 5-0 votes on "to_json returns JsonValue" and "single JsonError", so it has to be argued as a reversal. From the tooling side I'm against it. It fixes a public signature (`from_json(Str) -> Result[Self, Str]`) into the language, and moving to `JsonValue` later breaks every caller. Hover and completion show `Str`, which reveals nothing about what the value is. Error handling becomes string matching, which is TypeScript's `JSON.parse` in its `any` form, and people spent years undoing that. If the panel still picks it, at minimum make the error arm `JsonError` and not `Str`.
>
> ### Proposal 3 (sub-question): one JsonValue shape in the spec
>
> The spec has two `JsonValue` declarations. The Recursive Types example at 03_types.md ~1707 declares a user type with a compiler-known name. That is a shadow governed by §10.6, and it has a different shape. Two effects on tooling: go-to-definition and doc search on `JsonValue` in the spec now find two conflicting answers, and the example teaches users to shadow a built-in. Rename the example to a neutral recursive type:
>
> ```blink
> type Tree {
>     Leaf(Int)
>     Node(List[Tree])
> }
> ```
>
> §3.6.2 then holds the only `JsonValue`. Its `Object(fields: List[(Str, JsonValue)])` keeps key order, and that matters for stable `blink fmt`-style output and for deterministic snapshot tests.
>
> ### Proposal 4 (second gap): spec the Str-backed enum, with its diagnostics
>
> Add a short subsection in §3.4 so that `tests/test_str_backed_enum.bl` is no longer the feature's only definition:
>
> ```blink
> type Status {
>     Open = "open"
>     InProgress = "in_progress"
> }
>
> fn parse_status(s: Str) -> Status {
>     Status.from_str(s) ?? Status.Open
> }
> ```
>
> The spec should state:
> - The synthesized methods: `to_str(self) -> Str` and `from_str(Str) -> Option[Self]`, with an exact, case-sensitive match.
> - The shape: every variant has a Str literal or none does. No payloads.
> - Serialize/Deserialize on such an enum uses the string value.
> - The compile errors, each with a precise span:
>   - two variants with the same string (point at both spans, like rustc's duplicate discriminant error);
>   - a mixed enum (some variants assigned, some not);
>   - an assigned variant that has a payload;
>   - a value that is not a literal.
> - LSP: hover on a variant shows its value (`Status.Open = "open"`), and completion in `Status.from_str("…")` offers the known strings.
> - `blink fmt` keeps one variant per line and does not align the `=` signs, so a new variant doesn't cause diff churn (the same rule as gofmt's struct tags).
>
> Side note: the test does `import std.json` without needing it. Worth checking whether `from_str` depends on it. If it does, that's a bug.
>
> ---
>
> **Cross-language:** Go (`json.Marshal` / `json.Unmarshal` over `[]byte`, with a typed `*json.UnmarshalTypeError`) and Rust (serde over `serde_json::Value` with `to_string` / `from_str` sugar) both keep the text API as sugar over a typed tree or reflection, with a structured error. Neither exposes "Str in, Str error out" as the trait signature. Proposal 1 is that model.
>
> **Preferred:** Proposal 1: rename the Str-based derive output to `json.encode` / `json.decode[T]` with a real `JsonError`, keep `to_json` / `from_json` over `JsonValue` in the spec with a clear "not built yet" diagnostic that carries a fix, plus Proposals 3 and 4.

##### AI/ML

> # AI/ML panelist, Phase A proposal (ticket 169kjt)
>
> ## The problem, from my side
>
> The spec is the thing a model learns from. Today it shows three versions of one concept: the §3.4 `JsonValue` (`Boolean`, `Number`, `Map`), the §3.6.2 `JsonValue` (`Bool`, `Int`, `Float`, `List[(Str, JsonValue)]`), and the Str-typed code the compiler actually builds. A model that reads the spec writes `json.parse(s)?` and `JsonValue.Number(3.0)`, and both fail. A model trained on this repo's tests writes `User.from_json("...")`. The biggest cost is the disagreement between these sources, whichever one we pick. The fix must leave one spelling everywhere: spec, `blink llms`, tests and stdlib.
>
> ## Proposal 1 (preferred): keep the decided JsonValue design, remove every other spelling, and give the Str habit a targeted diagnostic
>
> Path (b), with three changes.
>
> 1. **One JsonValue shape.** The §3.6.2 enum is the only JsonValue. Rename the §3.4 "Recursive Types" example to a name that is not compiler-known (for example `type Expr { Num(Int)  Add(Expr, Expr) }`). An example that redeclares a compiler-known name with a different shape teaches models to write variants that do not exist.
>
> 2. **The two one-liners models reach for first are the canonical Str path.** They are already decided:
>
> ```blink
> import std.json
>
> @derive(Serialize, Deserialize)
> type User { id: Int, name: Str }
>
> fn main() {
>     let u = User { id: 1, name: "Al" }
>     let s = json.encode(u)                  // Str: what JSON.stringify / json.dumps users expect
>     let back = json.decode[User](s)         // Result[User, JsonError]
>     match back {
>         Ok(v) => print(v.name)
>         Err(e) => print(e.message)
>     }
>     let tree = u.to_json()                  // JsonValue: pure data -> data
>     let name = tree.get("name")?.as_str()   // Option navigation
> }
> ```
>
> 3. **A targeted diagnostic for the Ruby/Rails habit.** Rails `to_json` returns a String, and so does pydantic's `model_dump_json`. Models will write `let s: Str = u.to_json()` and `User.from_json(s)` with `s: Str`. The type mismatch there must say, in one line: "`to_json` returns `JsonValue`; use `json.encode(u)` to get `Str`", and the same for `from_json` pointing at `json.decode[T]`. A model can fix a precise diagnostic in one step. A generic "expected JsonValue, found Str" costs a retry loop. This is cheap to build, and it is what makes the JsonValue signature safe for generated code.
>
> **Keep `to_json` as the name.** Renaming it to `to_json_value` adds tokens on every call and throws away the "to_json produces JSON" signal. With the diagnostic in place, the Ruby prior becomes a one-step fix, not a trap.
>
> **JsonError: add `path: Str`** (for example `"$.users[2].age"`) next to `message`. This extends the decided single-type design; it does not reverse it. Models debug from error text, and "field age: expected Int, got Str at $.users[2]" is enough to locate the bad field without a retry.
>
> **Migration.** Use the 3-step dance: land JsonValue plus parse/stringify/encode/decode in lib/std/json.bl; switch the derive output and the one typecheck table that nxnnxe added; migrate the ~110 test call sites to `json.encode` / `json.decode[T]` / `to_json()`. Until the switch, file the Str registration as a bug linked to 169kjt. The spec must not describe the stopgap.
>
> **Tradeoffs (AI lens):**
> - Plus: it matches the two dominant priors. Python and JS models use parse/stringify; Rust and Go models use typed decode. Both were argued this way in the codec vote.
> - Plus: no second migration later, so no poisoned corpus.
> - Minus: one more type to learn.
> - Minus: the Int-handle `json_*` API in lib/std/json.bl must be deprecated, or it becomes a third spelling. Mark it internal or remove it in step 3.
>
> ## Proposal 2 (fallback, an explicit reversal I argue against): spec the Str signatures for v1
>
> Change the table to `to_json(self) -> Str` and `from_json(Str) -> Result[Self, Str]`, and delete JsonValue, JsonError and the json module from v1.
>
> - **Cost:** this reverses the 5-0 votes on "to_json returns JsonValue" and on the canonical two-step flow, plus the 4-1 vote on the 5-function surface.
> - **Cost:** `Result[Self, Str]` leaves no structure for a model or a tool to act on.
> - **Cost:** `from_json` merges parsing and decoding, so the "not JSON" and "wrong shape" failures look the same.
> - **Worst cost:** this repo is training data. If we spec Str now and move to JsonValue later, models learn the dead API from a large corpus, and every later model inherits it. A stopgap in the spec does more lasting harm than the gap does now.
>
> Cross-language: Rust serde keeps `to_string` and `Value` apart for the same reason; merging them is what Go's `map[string]interface{}` code suffers from.
>
> ## Proposal 3 (both proposals need it): give Str-backed enums a spec section
>
> Put it in §3 next to enums:
>
> ```blink
> @derive(Serialize, Deserialize)
> type Status {
>     Open = "open"
>     InProgress = "in_progress"
> }
>
> fn main() {
>     assert(Status.Open.to_str() == "open")
>     assert(Status.from_str("Open") == None)      // case-sensitive, exact match
>     let s = json.encode(Status.InProgress)       // "\"in_progress\"", not a tagged object
> }
> ```
>
> The section must define:
> - `to_str(self) -> Str` and `from_str(Str) -> Option[Self]`. Option is correct: there is one way to fail, so there is no error payload to carry.
> - Backing strings must be unique; a duplicate is a compile error.
> - Every variant takes a backing value, or none does.
> - No payload variants.
> - **Serialize/Deserialize use the backing string.** This decision is forced: without it, the §3.6.2 table says "tagged object `{"variant": ...}`", and no model or API client expects that for a string enum. TypeScript string enums, serde `rename_all`, and Python `Enum(str)` all serialize to the bare string.
>
> One risk: Rust's `FromStr::from_str` returns `Result`. The spec should state that the Option return is intentional, so models do not write `Status.from_str(x)?` expecting an Err value.
>
> **Preferred:** Proposal 1 plus Proposal 3. Keep the decided JsonValue design with one JsonValue shape, make `json.encode` / `json.decode[T]` the canonical Str path, add a targeted diagnostic for Str misuse of `to_json`/`from_json`, add `JsonError.path`, and spec Str-backed enums so they serialize as their backing string.

##### Minimalism

> ## Minimalism panelist (Min): Phase A proposal on 169kjt
>
> **My angle:** does each option shrink the language the user has to learn, or only move the size somewhere else? On that count, option (a) "Str everywhere" looks small but is not.
>
> ### Fact that decides it for me
>
> `lib/std/json.bl` already ships a dynamic JSON type: about 27 `pub fn`s over `Int` handles into a global arena. Examples are `json_new_object`, `json_set`, `json_get`, `json_as_str` and `json_clear()`. Users need dynamic JSON, so the language already has a JsonValue. It is an untyped, stateful one that needs manual `json_clear()`. Option (a) keeps that surface and adds a stringly typed trait on top. Option (b) swaps 27 functions and hidden global state for one enum plus the 5-function surface the panel already chose. That is a subtraction, which is why I support it.
>
> ---
>
> ### Proposal M1 (preferred): one real `JsonValue`, replace the handle API, keep every recorded decision
>
> 1. **Normative spec stays §3.6.2.** `to_json(self) -> JsonValue` and `from_json(JsonValue) -> Result[Self, JsonError]`. The Str signatures that typecheck registers today are a tracked implementation gap. They are not the language. The spec must not carry two truths.
> 2. **Exactly one `JsonValue` shape**, the §3.6.2 one: `Int` and `Float` kept separate, `Object` as an ordered `List[(Str, JsonValue)]`. Rename the §3.4 "Recursive Types" example to a name that is not compiler-known (for example `Tree` or `Expr`). An example in the spec must not shadow a compiler-known type. Today it silently teaches a second, conflicting shape.
> 3. **`JsonError` stays minimal:** `{ message: Str }`, as specified. Add no path or offset fields until someone needs them. It is still worth a nominal type over bare `Str`. Every other stdlib failure is nominal (`FsError`, `NetError`, `DBError`, `ConversionError`), and `Result[T, Str]` would be the only exception.
> 4. **Delete the `Int`-handle API** once `JsonValue` lands, or mark it deprecated in the same release. Two dynamic-JSON models in one stdlib is the kind of accretion C++ is known for.
> 5. **Migration cost is contained.** No lib/std code calls `to_json`/`from_json`. About 110 test call sites change mechanically, and nxnnxe's table is the single typecheck point.
>
> ```blink
> import std.json
>
> @derive(Serialize, Deserialize)
> type User {
>     name: Str
>     age: Int
> }
>
> fn main() {
>     let u = User { name: "ann", age: 3 }
>     let text = json.encode(u)                 // Str
>     let v = u.to_json()                       // JsonValue
>     match json.parse(text) {
>         Ok(tree) => {
>             let name = tree.get("name")?.as_str() ?? ""
>             match User.from_json(tree) {
>                 Ok(back) => print(back.name)
>                 Err(e) => print(e.message)
>             }
>         }
>         Err(e) => print(e.message)
>     }
> }
> ```
>
> **Why Str is the wrong minimal choice:**
> - **The contract lives in prose, not the type.** A Str-typed `to_json` must return well-formed JSON text, and the compiler cannot check that. A hand-written `impl Serialize` that returns `"oops"` gets embedded raw into its parent's derived output and produces broken JSON with no diagnostic. A typed tree makes that bug impossible to write.
> - **No sub-tree decoding.** With `Str`, you cannot decode a sub-tree of JSON you already parsed. Every nested decode re-parses text, and the two-step pipeline (voted 5-0) cannot be expressed.
> - **It reverses five unanimous votes** to save work that the handle API proves we need anyway.
>
> **Cross-language:** Go's `encoding/json` shows that a stringly or reflection-based surface keeps growing over time (`RawMessage`, `Number`, `json.Unmarshaler`). Serde and Elm both converge on one value tree plus typed decode. Lua and Scheme stay small by having one data model, not two.
>
> ---
>
> ### Proposal M2 (fallback if M1 is judged too large for v1): spec the Str form honestly, as an explicit reversal
>
> If the panel will not build `JsonValue` now:
> - Fix the table to `to_json(self) -> Str` and `from_json(Str) -> Result[Self, JsonError]`. Keep `JsonError` nominal even here, because it costs one line of stdlib.
> - Remove `JsonValue` from §3.6.2, §4 `Request.json`, and the §7 compiler-known list completely. Do not leave it "reserved for later", because a spec-only type misleads users and LLMs.
> - Record this as a reversal of the 5-0 "to_json returns JsonValue" and "two-step canonical" votes.
>
> I rank this below M1. It keeps the 27-function handle API as the only dynamic surface, so the language ends up bigger in practice.
>
> ### Reject: status quo
>
> Leaving the spec on JsonValue while typecheck and 110 tests lock in Str is the worst option. It fixes an accidental design into the training corpus.
>
> ---
>
> ### Proposal M3: str-backed enums get a narrow spec section, with no new rules
>
> This feature is the Str twin of an existing feature: enums already convert through `.to_int()` / `.from_int`. That keeps its novelty cost low, so I would spec it rather than remove it. I would spec only what the tests already define:
>
> ```blink
> type Status {
>     Open = "open"
>     InProgress = "in_progress"
> }
>
> fn parse_status(s: Str) -> Status {
>     Status.from_str(s) ?? Status.Open
> }
> ```
>
> Rules:
> - Payloadless variants only.
> - Either every variant has a Str literal or none does. A mix is an error.
> - Values must be unique, which is a compile error otherwise.
> - `to_str(self) -> Str`.
> - `from_str(Str) -> Option[Self]` uses an exact, case-sensitive match. `Option` rather than `Result` is right because there is only one failure mode.
> - Under `@derive(Serialize)` the variant encodes as its string value.
>
> **Flag for the panel:** str-backed values are effectively wire-name renaming for variants, while `@json("name")` field renaming was rejected 3-2 for v1. That is defensible, because the feature is general-purpose (CLI args, DB columns) and not JSON-specific. The spec section should still state that reasoning so nobody later cites it as precedent for field renaming.
>
> Do not add implicit `Display`, `From[Str]`, or a trait for these methods in v1 (YAGNI).
>
> ---
>
> **Preferred:** M1: make `JsonValue`/`JsonError` real as the single §3.6.2 shape, use it to replace (not add alongside) the Int-handle json API, rename the conflicting §3.4 example, and spec str-backed enums narrowly (M3).

#### Phase B — Debate (round 1)

Each panelist read all six Phase A texts and replied once. All six ended `STABLE: yes`. Text is verbatim.

##### Systems

> Sys Phase B round 1: OPT-1, a change on V1 (path not offset), STABLE yes.
>
> **1. OPT-1/2/3**
> OPT-1. All six of us prefer it, and it reverses no recorded vote. OPT-3 stays my fallback, above OPT-2. Min's point settles OPT-2 for me: the Int-handle arena is a dynamic JsonValue already, just a worse one. It has a global mutable store, handles that `json_clear()` invalidates, and it is not reentrant under `async.spawn`. OPT-2 keeps that store as the only dynamic path.
>
> **2. Variations**
>
> - **V2 (mine; I need it in the spec text).** PLT cites aeson, where encode is toJSON then render. That describes the semantics, and V2 keeps it. The spec says `json.encode(x)` equals `json.stringify(x.to_json())`, and `json.decode[T](s)` equals `json.parse(s)` then `T.from_json(v)`, in output, in Ok/Err, and in `message`. It does not say how they are built, so a derive can emit a streaming writer and reader per type with no tree. That makes V3 and V7 load-bearing: a fused decoder must reach the same answer as the tree path.
> - **V3 (PLT number rules).** Yes. They also say what a fused decoder must do. An Int field given `1e2` is an error on both paths, because as_int never narrows. A Float field given `20` widens on both.
> - **V7 (duplicate keys).** Yes, and extend it to derived `from_json`: on a duplicate key it takes the first match, the same as `get`. Without that rule the tree path and the fused path could disagree. serde errors on duplicates, JS takes the last one, so the spec must choose. First-match is the cheapest rule for a streaming reader, which can skip later duplicates.
> - **V1 (JsonError).** I change my position below. Now: `{ message: Str, path: Str }`.
> - **V4.** Delete the handle API when JsonValue lands. Do not keep it as a private backing store. A tree of enum values needs no global arena, and a global arena is a data race waiting to happen.
> - **V5.** Yes. It is a front-end diagnostic with zero runtime cost, and while JsonValue is unbuilt it keeps users from hitting an ICE.
> - **V6.** Yes, as one marker per subsection. The spec text itself does not get weaker.
> - **V8.** No view on the name. Any name that is not compiler-known works.
>
> **Str-backed enums (E items)**
>
> - **E2 (laws).** Yes. They cost nothing and the corpus can test them.
> - **E4 (error lists valid values).** Yes. It costs something only on the error path.
> - **E6 (codegen cost).** Put it in a non-normative note ("to_str allocates nothing"), not in the rules.
> - **E7.** Option is correct. The moderator's `from_int -> Option` fact is the direct precedent. File a friction ticket for the odd `Decimal.from_str`.
> - **E1 (Display).** Weak yes with PLT. A derived Display that prints the literal is one static-string load, and it stops `"{s}"` and `to_str()` from disagreeing. I would not block on it.
> - **E3.** Yes, one sentence.
> - **E5, E8.** No view. E5 is tooling, not the language spec.
>
> **3. Changed position: V1, from `offset` to `path`**
> A byte offset is free in a streaming decoder. The tree path cannot supply one unless every JsonValue node carries a span, and that costs a word per node on every tree. So offset would break V2's rule that both paths return the same error. Path is available on both paths at no extra cost, because the derive knows the field chain.
>
> I want path decided now, not later. `JsonError` is a struct that users build by hand in `impl Deserialize`. Adding a field later breaks every `JsonError { message: ... }` literal, which is the same break-it-later cost we are rejecting for OPT-2. Hand-written impls may pass `path: ""`.
>
> STABLE: yes. V1 (`message` only vs `message` + `path`) needs its own vote item. I also need V2's "equal by result" wording in whatever OPT-1 text goes to the vote.

##### Web/Scripting

> Web Phase B round 1: OPT-1 still, with a short list of positions on the variations.
>
> 1. OPT-1/2/3
> OPT-1. All six already prefer it, and nothing in the other texts moves me off it. If a fallback is ever needed, I rank OPT-3 (JsonText newtype) above OPT-2. Sys and PLT convinced me: with plain Str, `Response.json(u.to_json())` silently double-encodes, and that bug reads fine to a JS developer. OPT-2 is last.
>
> 2. Variations
> - V1 JsonError fields: `message` plus `path: Str` (for example `"users[2].age"`). A 400 response that names the bad field is the thing web clients want. `offset` is second-best: useful for parse errors, useless for shape errors. I can accept `{ message }` only, if the panel will add `path` in a later minor version without it counting as a break. Adding a field to a struct that users only read is not a breaking change.
> - V2 encode/decode specified by result: yes. Users see only the result. A fused writer is how `json.encode` stays as fast as today's der
> Web Phase B round 1, part 2 (my last message was cut off in V2; this continues from there).
>
> - V2 (continued): A fused writer keeps `json.encode` as fast as today's derive. Yes to V2.
> - V3 number rules: yes, strongly. `{"temp_c": 20}` failing to decode into a Float field would be a top Stack Overflow question on day one. Widening Int to Float on decode, plus `as_float()` returning Some for an Int, is what Python and JS developers assume.
> - V4 Int-handle API: remove it, or make it private in the same release that lands JsonValue. Two dynamic JSON APIs means half of the examples online use the wrong one.
> - V5 targeted diagnostic: yes. This is my must-have. I accept DevOps' interim "not built yet" error with a machine-applicable fix, as long as it is a front-end error and not an ICE.
> - V6 mark spec-only parts: no view on the form. Fine with PLT's wording.
> - V7 duplicate keys, `get` returns the first match: yes. Say so in the spec in one sentence.
> - V8 rename: any neutral name. I drop `Doc` and take `Tree`, since the most panelists named it.
> - E1 Display: I now lean yes, derived, with the output equal to `to_str()`. PLT's point decides it for me: interpolation and `to_str` must never disagree. `"{status}"` printing `InProgress` while the JSON says `"in_progress"` is exactly the confusion I want to prevent. Min's YAGNI objection is fair for `From[Str]` and a trait, but Display is what users hit first. If the panel splits on this, move it to its own vote and do not block the ticket on it.
> - E2 laws: yes. They are cheap and double as test cases.
> - E3 not precedent for `@json`: yes, one sentence.
> - E4 error lists the valid values: yes. I keep this.
> - E5 tooling: hover and completion yes. The fmt rule: no view.
> - E6 codegen cost statements: no view, but keep them out of normative text.
> - E7 Option vs Result: yes to an explicit note, and yes to a friction ticket about the `Decimal`/`Bytes` from_str codomains.
> - E8 placement: §3.4, beside enums.
>
> 3. Changed positions
> - E1: from "lean yes, not in this ticket" to "yes, derived Display equals to_str", reasons above.
> - Fallback ranking: OPT-3 above OPT-2, because of the double-encoding bug.
> - V8: `Doc` dropped in favour of `Tree`.
>
> STABLE: yes (E1 can go to a separate vote if the panel splits on it).

##### PLT

> PLT Phase B round 1: OPT-1 holds. Two added constraints on V2, one softened position on E1. STABLE: yes.
>
> **1. OPT-1/2/3**
> OPT-1, and all six agree. For OPT-2 and OPT-3, the arguments against from Sys, Min and AI/ML add to mine. The "contract lives in prose" point is the core one: a hand-written `impl Serialize` that returns `"oops"` gives broken JSON, and no type error catches it. OPT-3 (`JsonText`) is the lesser evil if the panel reverses, but I vote against both.
>
> **2. Variations**
>
> - **V1 (JsonError fields).** Yes to `message: Str, path: Str`. No to `offset: Int` with a -1 sentinel. A sentinel value inside Int is not principled typing. If a byte position is wanted, it must be `Option[Int]`.
>   - Why decide now: users can build struct literals and match on fields, so the field set is public API. Adding a field later breaks their code. Min's YAGNI argument does not hold here.
>   - `path` is well defined in both steps. In the tree step it is the path in the tree. In the parse step it is the path of the container open when the error happened.
> - **V2 (fused encode/decode).** Support, with two constraints the spec must state, or the fusion is unsound:
>   - (a) Equivalence is observable. The fused path must accept the same inputs, give the same Ok values, and give the same Err path as `parse` then `from_json`. The message text may differ.
>   - (b) Only derived impls may fuse. A field whose type has a hand-written `Deserialize` must go through parse-subtree then `from_json`. Otherwise the fused reader bypasses user code, and `decode` is no longer the composition that was voted 5-0.
>   - The V3 number rules must also hold on the fused path.
> - **V3 (number rules).** Keep, and Sys's i64 > 2^53 point supports it. One addition: an integer literal outside i64 becomes `Float` (lossy), and the spec says so. The alternative is an error. I prefer Float for RFC 8259 conformance.
> - **V4 (Int-handle API).** Remove or make private. The global arena that `json_clear()` resets is not reentrant (Sys), so it cannot be a spec'd surface. No view on which release.
> - **V5 (targeted diagnostic).** Support. It is tooling, not a typing rule.
> - **V6 (mark unbuilt parts spec-only).** Keep.
> - **V7 (duplicate keys).** Keep, and extend it: derived `from_json` must use the same first-match rule as `get`. If they differ, `T.from_json(v)` and `v.get(k)` disagree on the same tree.
> - **V8 (renaming the §3.4 example).** Any name that is not compiler-known. `Tree` is fine.
> - **E1 (Display).** I change this; see section 3.
> - **E2 (laws in the spec).** Keep. Add the Deserialize law: `T.from_json(JsonValue.Str(s))` is `Ok(v)` exactly when `T.from_str(s) == Some(v)`. The type-mapping table gains a row for Str-backed enums.
> - **E3 (not a precedent for `@json("name")`).** Agree with Min, and state the reason in the spec.
> - **E4 (error lists valid values).** Fine, but the message text should not be normative.
> - **E5 (tooling rules), E6 (codegen costs).** No view. They belong in docs, not the spec.
> - **E7 (existing `from_str` codomains).** The moderator's facts matter here:
>   - `from_int -> Option` is the precedent, and `from_str -> Option` matches it.
>   - `Bytes.from_str` is total, and that is fine. It converts a value; it does not parse and cannot fail.
>   - `Decimal.from_str` has no return type in the spec. Sys says it returns Option, and I have not checked that. It needs a friction ticket either way.
> - **E8 (placement).** §3.4, beside `to_int`/`from_int`.
>
> **3. Changed position**
> E1: I now accept Min's position of no implicit Display in v1. I keep one conditional law: if an enum ever gets Display (derived or stated in the spec), the Display output of a Str-backed enum must equal `to_str()`. That rules out an incoherent pair later without adding a feature now.
>
> STABLE: yes (V1 and the two V2 constraints are my conditions; I can vote with them as separate items)

##### DevOps

> Devops Phase B round 1: OPT-1, one position changed (V5), a narrower E5; STABLE: yes.
>
> **1. OPT-1/2/3**
> OPT-1, with no change. All six of us arrived at the same design on our own, and PLT's 3-step migration (P1.3) is the right order. I reject OPT-2: hover shows `Str`, `from_json(user.name)` type-checks, and the error arm tells the user nothing. If the panel still reverses, I take OPT-3 over OPT-2. `JsonText` at least makes double-encoding (`Response.json(u.to_json())`) a type error with a real message, not bad output at run time.
>
> **2. Variations**
> - V1: `JsonError` fields. Vote this as its own item so it doesn't block OPT-1. My position: `{ message, path }`. A decode error without a path is not actionable. `path` covers errors in the tree step and `offset` covers parse errors, so they don't compete. If we add only one, add `path`. Whichever way it goes, the spec should require the message text to include the location ("line L, column C" for parse, "at $.a.b" for decode), so the error is useful even with `{ message }` alone.
> - V2: yes. Sys already requires the same error message on both paths. I need that: a fused decoder that reports different text from parse plus `from_json` gives users two error texts for one bug.
> - V3: yes. Without the widening rule, `{"temp_c": 20}` gives an error message the user can't understand ("expected Float, found Int" on input they know is correct).
> - V4: deprecate in the same release that `JsonValue` lands. Put a warning on each `json_*` function that names its replacement, then remove it. Don't do a silent delete.
> - V5: see section 3.
> - V6: yes. The flag must also reach `blink llms`, so the docs never show spec-only API as working.
> - V7: yes, first match wins, stated in the spec.
> - V8: `Tree`. Not `Json`: in completion, `Json…` would sit next to `JsonValue`, `JsonError` and the `json` module, which recreates the confusion we're removing.
> - E1: lean no implicit Display in v1 (Min). The change is one-way: we can add Display later without breaking code, but we can't take it back. The E0523 error on `"{s}"` must suggest `.to_str()`.
> - E2: yes. Each law becomes a corpus test.
> - E3: yes.
> - E4: yes, strongly. `unknown value "x" for Status; expected one of: "open", "in_progress"` is exactly the kind of error message I'm here to get. Put the format in the spec.
> - E5: narrowed (see section 3).
> - E6: no view. Fine as a note that is not normative.
> - E7: yes, a friction ticket plus the spec note. A `?` on an Option inside a fn that returns Result should say "from_str returns Option; use `.ok_or(...)`".
> - E8: §3.4.
>
> **3. Changes**
> - V5: I drop my interim "not built yet" error. Under PLT's 3 steps, `to_json`/`from_json` stay Str-typed until step 3 retypes them, so no build ever has JsonValue in the spec but not in the compiler at the call site. The permanent diagnostic from Web and AI/ML replaces it: a Str passed to `from_json`, or `to_json` used as a Str, gives one line that names `json.encode(u)` / `json.decode[T](s)`, with a fix that tools can apply automatically. The same fix is how the ~110 test call sites migrate.
> - E5: I cut my own tooling rules down. Hover and completion are not language spec, so they go to tooling tickets. The spec keeps only the list of compile errors (duplicate literal pointing at both spans, mixed enum, payload with a literal, a value that is not a literal) and the fmt rule.
>
> STABLE: yes. V1 (fields on JsonError) should be voted on its own; it does not block me.

##### AI/ML

> aiml Phase B round 1: OPT-1, ready to vote.
>
> 1. OPT-1/2/3
> OPT-1. All six of us independently arrived at the same user code: `json.encode(u)`, `json.decode[T](s)`, `u.to_json() -> JsonValue`. A model is most likely to get right the spelling that every source agrees on, so this agreement is itself evidence for OPT-1. OPT-2 is my fallback only if (b) cannot land. OPT-3 (`JsonText`) is last for me. It adds a type that no training data contains, and `.to_str()` becomes a mandatory hop that models will forget, so each call site pays a retry.
>
> 2. Variations
> - V1: I want `path: Str`. Models debug from error text, and "field age at $.items[2]" gives them a fix in one step. `offset` answers a different question (where the parse failed, not where the decode failed), so I would take both. Min's minimal floor is acceptable if the spec requires `message` to include the location. Whichever fields we pick, the spec must fix the content of `message`.
> - V2: Yes. Specifying the functions by their result changes nothing a user writes, and it removes Sys's cost objection.
> - V3: Strongly yes. `{"temp_c": 20}` failing to decode into a `Float` field is exactly the input that generated fixtures and LLM-written tests produce. Without the widening rule, this becomes the most common false failure.
> - V4: Delete it, or make it private. If `json_*` stays public, that is a third spelling. Models pick up whatever appears in the stdlib and in `blink llms`.
> - V5: Yes, and I merge it with DevOps's point: the interim "not built yet" error and the permanent Str-misuse error should be one diagnostic, pointing at `json.encode` / `json.decode[T]`, with a machine-applicable fix. The same message stays useful before and after JsonValue lands.
> - V6: Yes, but only if `blink llms` carries the same "spec-only" marker. The spec feeds LLM context, and an unmarked unbuilt API is what makes models generate calls that fail. This is compatible with Min's "no spec-only types": we keep the type and mark its implementation status, rather than dropping it.
> - V7: Yes. `get` returns the first match, stated in one sentence.
> - V8: `Tree`. Not `Json` (Sys): a user type called `Json` next to a compiler-known `JsonValue` recreates the confusion we are trying to remove.
>
> - E1: Make Display follow what plain enums do. If `"{e}"` prints the variant name for a plain enum, then a Str-backed enum must print its backing literal (the TS and Python StrEnum expectation). If plain enums have no Display, add none (Min). The rule we must avoid is one where the same `"{x}"` prints the variant name for one enum and the literal for another without the spec saying so.
> - E2: Yes. The laws are cheap, testable, and read as a precise definition.
> - E3: Yes, one sentence.
> - E4: Yes, strongly. Listing the valid values lets a model repair its input without looking anything up.
> - E5, E6: No normative view; they are fine as notes.
> - E7: Yes to the friction ticket. Different codomains for `from_str` across Decimal, Bytes and enums are a learnability hazard. The spec anchor should be `Enum.from_int -> Option` (03_types.md:1212), the direct twin, not Rust's FromStr.
> - E8: §3.4, directly beside `to_int`/`from_int`, so the parallel is visible.
>
> 3. Changes
> - I adopt V2 and V3, which I did not cover in Phase A.
> - I merge my Str-misuse diagnostic with DevOps's interim diagnostic into one (V5).
> - I soften `JsonError.path` from a requirement to "path, or a message whose location content the spec fixes" (V1).
> - I drop Rust FromStr as the justification for `Option` and cite `from_int` instead.
>
> STABLE: yes

##### Minimalism

> Min, Phase B round 1: I back OPT-1. I now rank OPT-3 over OPT-2 as fallback. STABLE: yes.
>
> 1. OPT-1/2/3
> - OPT-1: yes. All six panelists prefer it, and it reverses no recorded vote. It also subtracts: one enum plus the already-voted module replaces the 27-function Int-handle API.
> - Fallback order: OPT-3 first, then OPT-2. This is a change (see 3).
> - Status quo, with the spec and the implementation split: reject.
>
> 2. Variations
> - V1 JsonError fields: `{ message }` only. Offset and path are YAGNI for v1. Users read JsonError and seldom build one, so a field added later breaks almost nothing.
> - V2 encode/decode specified by result: yes. It adds no surface, and it lets the implementation skip the tree.
> - V3 number rules: yes. A total rule costs a few lines, and without it `{"temp_c": 20}` fails to decode into a Float field.
> - V4 Int-handle API: remove it from the public surface. A private backing detail (Sys) is acceptable to me. Two public dynamic-JSON models is not.
> - V5 targeted diagnostic: yes. It is tooling and does not change the language. DevOps's interim "not built yet" error is an implementation matter, not spec text.
> - V6 mark spec-only parts: mild no. The spec states the language, and implementation status belongs in the tracker. An inline note turns stale and teaches models a stopgap. I will not block on this.
> - V7 duplicate keys, first match: yes. One sentence.
> - V8 rename: `Tree`. I oppose `Json`: it sits too close to `JsonValue` and keeps the confusion alive.
>
> Str-backed enums:
> - E1 Display: no in v1. Plain enums already have a Display story. Str-backed ones printing the backing value would add a second rule. Defer it to its own ticket.
> - E2 laws: yes. They are cheap, testable, and they define the feature.
> - E3 non-precedent sentence: keep.
> - E4 error text listing valid values: good implementation quality, but no spec rule. At most one example.
> - E5 hover, completion and fmt rules in the spec: no. Tooling behaviour is not language spec. Put it in tooling docs or a ticket.
> - E6 codegen cost statements: no, same reason.
> - E7 codomain mismatch: yes to a friction ticket, and yes to one sentence saying Option is intentional. Its rationale matches `Enum.from_int -> Option` at 03_types.md:1212. That precedent is the strongest argument, and the spec should cite it.
> - E8 placement: §3.4 beside enums, next to `to_int`/`from_int`, so the reader sees one conversion family, not a new feature.
>
> 3. Changes
> - I change my fallback ranking from M2 (Str plus nominal JsonError) to OPT-3 (`JsonText`) first. Sys's double-encoding point convinced me: with plain Str, `Response.json(u.to_json())` escapes text that is already JSON, and the checker cannot see it. A zero-cost newtype removes that bug class for one extra type. My burden-of-proof test passes because it prevents a silent wrong result, not because it adds convenience.
> - No other changes.
>
> STABLE: yes

#### Phase C — Final vote

The ballot put these questions to the panel. Every option was raised by a panelist in Phase A or B.

- **Q1.** Core resolution: OPT-1 keeps §3.6.2 (`to_json -> JsonValue`, `from_json(JsonValue) -> Result[Self, JsonError]`) and moves the Str behavior to `json.encode(x) -> Str` / `json.decode[T](s) -> Result[T, JsonError]`; OPT-2 reverses to Str signatures with a nominal `JsonError`; OPT-3 reverses to a transparent newtype `JsonText(Str)`.
- **Q2.** `JsonError` fields: `{ message: Str }` or `{ message: Str, path: Str }`.
- **Q2b.** The spec fixes the location content of `message` ("line L, column C" for parse errors, "at <path>" for decode errors).
- **Q3.** `encode`/`decode` are specified by observable result; an implementation may fuse them into a per-type writer/reader with no tree.
- **Q3a.** The equivalence also covers the exact `message` text.
- **Q3b.** Only derived impls may fuse; a field whose type has a hand-written `Deserialize` goes through parse-subtree then `from_json`.
- **Q4.** Number rules: Int iff no fraction/exponent and fits i64, else Float; derived `from_json` widens Int into a Float field; `as_float()` on Int is `Some`; `as_int` never narrows a Float; an integer outside i64 parses as Float (lossy) and the spec says so.
- **Q5.** The integer-handle `json_*` API: A removed from the public surface (private backing allowed), B deleted outright, C deprecated then removed.
- **Q6.** Targeted diagnostic for a Str meeting `to_json`/`from_json`: A normative, B implementation ticket only.
- **Q7.** The spec marks unbuilt §3.6.2 parts as spec-only, and `blink llms` carries the same marker.
- **Q8.** Duplicate object keys: `get(key)` and derived `from_json` both take the first match.
- **Q9.** Rename the §3.4 *Recursive Types* example from `JsonValue` to `Tree`.
- **Q10.** A §3.4 subsection for Str-backed enums with the common rules and three laws.
- **Q11.** Display: A no implicit Display, and with `@derive(Display)` the output equals `to_str()`; B defer; C implicit Display.
- **Q12.** One sentence: backing literals are not precedent for `@json("name")`.
- **Q13.** The unknown-literal `Deserialize` error lists the valid values: A normative format, B non-normative example.
- **Q14.** Compile errors in the spec, and a `blink fmt` rule: A both, B compile errors only, C neither.
- **Q15.** Codegen cost statements: A non-normative note, B omit.
- **Q16.** A sentence saying `Option` is intentional, citing `Enum.from_int`, plus a friction ticket on the `Decimal.from_str` / `Bytes.from_str` codomains.

Tally (order: Sys, Web, PLT, DevOps, AI/ML, Min):

| Q | Result | Tally |
|---|--------|-------|
| Q1 | OPT-1 | 6-0 |
| Q2 | `{ message, path }` | 5-1 (Minimalism: `message` only) |
| Q2b | YES | 6-0 |
| Q3 | YES | 6-0 |
| Q3a | YES 4 / NO 2 (PLT, Minimalism) | 4-2 → Phase D |
| Q3b | YES | 6-0 |
| Q4 | YES, all clauses | 6-0 |
| Q5 | A 4 / B 1 (Systems) / C 1 (DevOps) | 4-1-1 → Phase D |
| Q6 | A 3 (Web, DevOps, AI/ML) / B 3 (Sys, PLT, Min) | 3-3 → Phase D |
| Q7 | YES | 5-1 (Minimalism) |
| Q8 | YES | 6-0 |
| Q9 | YES (`Tree`) | 6-0 |
| Q10 | YES, all three laws | 6-0 |
| Q11 | A | 5-1 (Minimalism: B, defer) |
| Q12 | YES | 6-0 |
| Q13 | A 3 (Web, DevOps, AI/ML) / B 3 (Sys, PLT, Min) | 3-3 → Phase D |
| Q14 | B | 5-1 (DevOps: A, both) |
| Q15 | A 4 / B 2 (PLT, Minimalism) | 4-2 → Phase D |
| Q16 | YES | 6-0 |

Each ballot, verbatim:

##### Systems

> Sys Phase C ballot, part 1/2 (Part 1 — JSON, Q1-Q9).
>
> Q1: A
> Reasoning: OPT-1 keeps a real type between the struct and the wire, and it reverses no recorded vote. With Q3 it costs nothing on the typed path, because json.encode/decode[T] can compile to today's direct writer and reader. The Int-handle arena is a global mutable store that is not reentrant under async.spawn, so OPT-2 would leave the only dynamic path unsafe.
> Concern: the migration can stall between steps and leave to_json typed JsonValue in the spec while the compiler still emits Str. The 3-step order has to land as one sequence.
>
> Q2: B
> Reasoning: path is available on both the tree path and the fused path at no cost, because the derive knows the field chain. A byte offset is not available on the tree path unless every node carries a span, which costs a word per node. Users build JsonError literals in hand-written impls, so adding a field later is a break. Decide it now.
> Concern: hand-written impls will pass path: "", so path is only reliable for derived types.
>
> Q2b: YES
> Reasoning: line/column costs nothing until an error happens. A streaming reader keeps a newline counter or rescans the input on the error path. A fixed location format also makes Q3a something you can test.
> Concern: "line L, column C" has to say whether it counts bytes or codepoints. If it does not, two implementations will disagree on non-ASCII input.
>
> Q3: YES
> Reasoning: this is my core item. The semantics stay parse then from_json (the 5-0 vote), and the machine is free to emit one monomorphized pass with no tree and allocations sized to the output, which is serde's line. Without it, every HTTP response pays one heap node per field.
> Concern: a fused path can drift from the tree path without anyone noticing. The corpus needs differential tests that run both paths on the same inputs, including numbers, duplicate keys and bad input.
>
> Q3a: YES
> Reasoning: one bug should give one error text. Once Q2b fixes the location content, a matching message costs nothing at run time: the fused reader formats the same string on the error path. It is also the only way to test equivalence completely.
> Concern: this puts a small burden on the fused reader: after a parse succeeds, a decode error has to report "at <path>", not the byte position it happens to hold.
>
> Q3b: YES
> Reasoning: a fused reader that skips a user's Deserialize is unsound, and decode stops being the composition we voted for. The extra cost is a subtree allocation only at fields whose type has a hand-written impl. The derived fields stay fused.
> Concern: the implementation has to find hand-written impls per field type at mono time, and a generic field (Option[Custom], List[Custom]) is the case that will get it wrong.
>
> Q4: YES (all clauses, including lossy Float for integers outside i64)
> Reasoning: separate Int and Float variants keep i64 IDs above 2^53 exact, and the rules also tell a fused decoder exactly what to do per field. Lossy Float outside i64 follows RFC 8259 and costs no branch the parser does not already have.
> Concern: a u64 ID above i64 max silently loses precision. The spec sentence has to be explicit, or users will learn it from a production incident.
>
> Q5: B
> Reasoning: a tree of enum values needs no global arena. json_clear() invalidating every live handle is a data race under async.spawn, and a private backing store keeps that hazard in the runtime. Delete it.
> Concern: other code may use json_* outside lib/std (tests, tools in src/). Grep before deleting, and move them first.
>
> Q6: B
> Reasoning: the diagnostic has zero runtime cost and I want it built, but its wording and fix-its are implementation quality. A catalog entry in the spec would freeze text that tooling should be free to improve.
> Concern: without spec text the diagnostic could slip. The ticket must be a blocker on the step that retypes to_json/from_json.
>
> Q7: YES
> Reasoning: one marker per subsection keeps the spec normative and stops users and models from calling API that does not exist.
> Concern: the markers go stale when features land. Removing a marker must be part of each landing ticket's definition of done.
>
> Q8: YES
> Reasoning: first match is the cheapest rule for a streaming reader, which can skip later duplicates without buffering. Using the same rule in get and in derived from_json keeps the tree path and the fused path in agreement.
> Concern: this is a silent choice that serde (error) and JS (last wins) make differently, so porters will be surprised. One spec sentence and one test are enough.
>
> Q9: YES
> Reasoning: a user declaration that shadows a compiler-known name with a different shape is a bad teaching example. Tree is fine, and I drop Json.
> Concern: none of substance.
> Sys Phase C ballot, part 2/2 (Part 2 — Str-backed enums, Q10-Q16).
>
> Q10: YES (keep all three laws)
> Reasoning: the rules match what the codegen already does: a static const char* table indexed by tag, and a length check plus memcmp. The duplicate-literal error is what makes from_str well defined. The laws cost nothing, the corpus can test them, and the from_json law holds the fused decoder to the same answer as from_str.
> Concern: "exact" must mean byte-exact with no Unicode normalization. If the spec does not say so, someone will add NFC later and change results.
>
> Q11: A
> Reasoning: the moderator fact decides it for me. @derive(Display) prints the variant name today, so without a rule, "{s}" and to_str() disagree the moment someone derives it. A costs nothing (the Display body is the same static string load as to_str) and adds no implicit feature. I drop my weak yes to C.
> Concern: the override changes what an existing @derive(Display) on these enums prints. Any test that expects the variant name has to change in the same step.
>
> Q12: YES
> Reasoning: one sentence, no cost, and it stops a scope creep argument before it starts.
> Concern: none.
>
> Q13: B
> Reasoning: listing the valid values costs something only on the error path, and I want it built. The exact format is implementation quality, in the same way as Q6.
> Concern: if nothing requires it, the fused decoder may ship with a bare "unknown value" message. The implementation ticket should require it.
>
> Q14: B
> Reasoning: the four compile errors are language rules and belong in the spec. The fmt layout is tooling, not language.
> Concern: "duplicate literal pointing at both spans" is a diagnostic-shape detail. Keep the spec to the error condition and let the implementation choose the spans.
>
> Q15: A
> Reasoning: to_str allocates nothing and from_str is a length switch plus memcmp. That is useful to users who pick this over a Map[Str, T], but a codegen strategy must not be normative.
> Concern: a note can turn into a promise people rely on. Word it as "the reference implementation".
>
> Q16: YES
> Reasoning: from_int -> Option is the direct twin, and Option has no error payload to allocate. The friction ticket is needed because the spec gives Decimal.from_str no return type.
> Concern: the friction ticket could settle Decimal.from_str on Result and reopen this codomain choice. Tie the ticket to this decision.

##### Web/Scripting

> Web Phase C ballot, part 1/2 (Q1-Q9, JSON).
>
> Q1: A
> Reasoning: With OPT-1 the everyday web path is `json.encode(u)` / `json.decode[User](body)`, the same as Python dumps/loads and Kotlin encodeToString/decodeFromString. It reverses no recorded vote. There are no users yet, so migrating ~110 test call sites now is the cheapest break we will ever get.
> Concern: JsonValue stays spec-only for a long time. In that window the docs describe an API that nobody can call, and users fall back to the json_* handles.
>
> Q2: B
> Reasoning: A 400 response has to name the bad field ("users[2].age"), and `path` is what makes a decode error something a client can act on. PLT and Sys are right that users build JsonError literals in hand-written impls, so adding the field later is a real break. Decide it now.
> Concern: hand-written impls will pass `path: ""` everywhere, so path is empty exactly on the custom types where it would help most.
>
> Q2b: YES
> Reasoning: Whatever the field set, `"{e.message}"` is the thing most handlers print. Fixing where the location goes in that text means even a lazy handler returns a useful error.
> Concern: normative message text freezes wording that we may want to improve later.
>
> Q3: YES
> Reasoning: Users only see the result. A fused writer is how `json.encode` stays as fast as today's derive on a hot response path.
> Concern: two code paths for one behavior means the corpus must test both, or they will drift.
>
> Q3a: YES
> Reasoning: One bad payload must give one error text, whether it went through decode or through parse then from_json. Two different messages for the same bug is exactly the kind of thing that turns into a Stack Overflow question and breaks snapshot tests.
> Concern: it constrains the fused reader's error wording, which is extra work for the implementer.
>
> Q3b: YES
> Reasoning: If a fused reader skipped a user's hand-written Deserialize, their custom validation would silently not run. To a web developer that is a security bug, not a performance detail.
> Concern: types with one custom field lose the fast path, and nobody will be able to tell why decode got slower.
>
> Q4: YES (all clauses, including the lossy last one)
> Reasoning: `{"temp_c": 20}` failing to decode into a Float field would be a day-one Stack Overflow question, so widening is a must. Out-of-range integers becoming Float is what JS and Python users already expect, and the spec saying so out loud is enough.
> Concern: a silently lossy huge ID still bites someone who expected an error.
>
> Q5: A
> Reasoning: Two public dynamic-JSON APIs means half the examples online use the wrong one, so json_* has to leave the public surface in the release where JsonValue lands. With no real users yet, a deprecation cycle buys nothing. Whether it survives privately is an implementation detail I do not care about.
> Concern: a private arena kept as a backing store keeps the non-reentrant global state that Sys warned about.
>
> Q6: A
> Reasoning: This is my must-have. `User.from_json(text)` with a Str is the single most likely mistake for this feature, and its message plus the machine-applicable fix belongs in the diagnostic catalog, where tooling and `blink llms` can rely on it.
> Concern: a normative diagnostic that names json.encode/decode must be updated if those names ever change.
>
> Q7: YES
> Reasoning: Marking what does not work yet keeps a user (or a model) from spending an hour on an API the compiler does not build. `blink llms` has to carry the same marker, or the marker is useless.
> Concern: the markers go stale when features land and nobody removes them.
>
> Q8: YES
> Reasoning: One sentence, and `get` and derived from_json can never disagree on the same payload. Pick one rule and write it down.
> Concern: JS users expect last-wins, so someone will be surprised once. At least the spec will say what happens.
>
> Q9: YES
> Reasoning: A teaching example that redeclares a compiler-known name with a different shape guarantees confused readers. `Tree` is neutral.
> Concern: none of substance; old links and quotes of the example go stale.
> Web Phase C ballot, part 2/2 (Q10-Q16, Str-backed enums).
>
> Q10: YES (keep all laws)
> Reasoning: Status and role fields make up most of the enums in real APIs, and a single test file is not a definition. The laws are cheap, they double as corpus tests, and the from_json law pins down the JSON mapping web users care about.
> Concern: the section must say plainly that from_str is case-sensitive, because Python's Enum habits make people expect a fallback.
>
> Q11: A
> Reasoning: My goal is that `"{status}"` never prints `InProgress` while the JSON says `"in_progress"`. A guarantees that whenever Display exists, and it matches my Phase B position ("derived, equal to to_str"). Implicit Display (C) would be nicer for the 90% case, but A is compatible with adding it later, and it avoids a second implicit rule now.
> Concern: users will write `"{status}"`, get E0523, and be annoyed that they have to add @derive(Display). The error must suggest `.to_str()` or @derive(Display).
>
> Q12: YES
> Reasoning: One sentence stops someone from citing backing literals as a reason to reopen field renaming. It costs nothing.
> Concern: none.
>
> Q13: A
> Reasoning: `unknown value "x" for Status; expected one of: "open", "in_progress"` is what lets an API client fix its request without reading source. If only an example shows it, implementations will drop the list. Put the format in the spec.
> Concern: a long enum produces a long message. The spec may need a cap or an ellipsis rule later.
>
> Q14: B
> Reasoning: Users meet the four compile errors, so the spec must list them. The fmt rule is tooling, and I have no view on it; it belongs in fmt docs.
> Concern: leaving the fmt rule out means aligned `=` churn can creep in through the formatter with no spec text to point at.
>
> Q15: A
> Reasoning: "to_str allocates nothing" is useful to know on a hot path, but it is not a language rule. A note is enough.
> Concern: a note can turn false after a codegen change, and nobody checks notes.
>
> Q16: YES
> Reasoning: Rust users will write `Status.from_str(x)?` expecting an Err, so one sentence citing `Enum.from_int -> Option` saves them the confusion. Three from_str methods with different return types is a learnability hazard that deserves a friction ticket.
> Concern: the friction ticket sits unowned, and the Decimal inconsistency ships anyway.

##### PLT

> PLT Phase C ballot, part 1/2 (Q1-Q9, JSON).
>
> Q1: A
> Reasoning: `to_json : T -> JsonValue` follows the structure of the value, so the derive for a container is correct because of how it is built; with Str, the correctness lives in codegen where the checker cannot see it. Str also makes `from_json(user.name)` well-typed, so the type proves nothing. OPT-1 reverses no recorded vote and keeps `decode = from_json . parse` (5-0).
> Concern: the 3-step migration may stall at step 2, leaving Str-typed to_json/from_json published for a long time; the step-3 retype needs a ticket with a date, not a promise.
>
> Q2: B
> Reasoning: users build JsonError in hand-written `impl Deserialize` and match on its fields, so the field set is public API; adding a field later breaks every struct literal. `path` is well defined on both the tree step and the parse step, and needs no sentinel (unlike `offset: Int` with -1).
> Concern: hand-written impls will pass `path: ""` everywhere, so path is reliable only for derived impls; the spec should say "" means unknown.
>
> Q2b: YES
> Reasoning: parse errors have no structured position field (I rejected a sentinel offset), so the message is the only place their location can live, and fixing its content (not its full text) is a weak, checkable rule. For decode errors it duplicates `path`, which is harmless.
> Concern: "content" can drift into "exact wording"; the spec must fix what the message contains, not its format, or it collides with Q3a.
>
> Q3: YES
> Reasoning: the semantics stay `encode = stringify . to_json` and `decode = from_json . parse`, which is what aeson and serde do. Specifying by observable result gives the implementation room to fuse without changing the denotation.
> Concern: without Q3b and the Q4/Q8 rules also holding on the fused path, "same observable result" is untestable in practice and the two paths will drift.
>
> Q3a: NO
> Reasoning: the equivalence that matters for soundness is the set of accepted inputs, the Ok values, and the Err path; those are what a program can branch on. Binding message text as well turns an implementation-quality string into a semantic obligation that forces the fused reader to reproduce tree-path wording byte for byte.
> Concern: if NO wins, DevOps's "two texts for one bug" is real; Q2b's location-content rule is the mitigation.
>
> Q3b: YES
> Reasoning: a fused reader that skips a hand-written `Deserialize` bypasses user code, so `decode[T]` stops being the composition that was voted 5-0. Only derived impls have a known shape the fusion can inline; everything else must go through parse-subtree then from_json.
> Concern: this makes a derived type containing one hand-written field pay the tree cost for that subtree; someone will later ask to relax it, and the answer must stay no.
>
> Q4: YES (all clauses, including the out-of-i64 -> Float lossy clause)
> Reasoning: JSON has one number type; the Int/Float split is sound only with a total rule. Widening Int into a Float field fixes the `{"temp_c": 20}` bug; `as_int` never narrowing keeps Int exact. Out-of-range integers as Float follow RFC 8259 (which permits limited precision) rather than rejecting valid JSON.
> Concern: silent precision loss on large ids (> 2^53) will surprise users; the spec sentence must be prominent, and a later `Decimal`/BigInt path may be wanted.
>
> Q5: A
> Reasoning: the spec defines the public surface; what backs JsonValue privately is an implementation matter. The global, non-reentrant arena cannot be a spec'd surface, which A already guarantees.
> Concern: a private arena backing JsonValue would carry the same reentrancy hazard under `async.spawn` (Sys's point), so "private allowed" must not become "private and still shared-mutable".
>
> Q6: B
> Reasoning: it is a diagnostic, not a typing rule; the typing rule (Str is not JsonValue) is already in §3.6.2. Diagnostic wording belongs to the implementation and can improve without a spec change.
> Concern: as an implementation ticket it may never be built, and the ~110-site migration then relies on users reading a plain type error.
>
> Q7: YES
> Reasoning: the spec should state the language at full strength and say plainly which parts are not built, rather than weakening the language to match the implementation. The same marker in `blink llms` keeps generated code from calling unbuilt API.
> Concern: markers go stale; removing each one must be part of the ticket that builds that part.
>
> Q8: YES
> Reasoning: `Object(fields: List[(Str, JsonValue)])` keeps duplicates, so a lookup rule is required. If `get` and derived `from_json` used different rules, `T.from_json(v)` and `v.get(k)` would disagree on the same tree, which is incoherent.
> Concern: serde rejects duplicates and JS takes the last; users porting code will hit the difference, so the spec must state it in one visible sentence.
>
> Q9: YES
> Reasoning: the §3.4 example today silently teaches a §10.6 shadowing of a compiler-known type with a different shape. `Tree` is neutral and not near any compiler-known name.
> Concern: none of substance.
> PLT Phase C ballot, part 2/2 (Q10-Q16, Str-backed enums).
>
> Q10: YES (keep every law; drop none)
> Reasoning: distinct literals are what make `to_str` injective and `from_str` a function; without that rule the laws are false. The three laws are the definition of the feature and each becomes a corpus test. The Deserialize law ties the enum to the JSON derive so the two cannot drift.
> Concern: the second law's `.map(...)` spelling must match Blink's closure syntax exactly in the spec text, or the law itself will not typecheck.
>
> Q11: A
> Reasoning: no new implicit feature in v1 (Min's point), but one conditional law that rules out an incoherent pair: if Display exists, it equals `to_str()`. The moderator's fact makes the law load-bearing, since `@derive(Display)` today would print `InProgress` while JSON says `in_progress`. B leaves that incoherence in the spec; C adds an implicit trait impl that behaves differently from plain enums.
> Concern: the spec must edit the §3.6 `@derive(Display)` row ("variant name for unit variants") to name the exception, or the two rules contradict each other.
>
> Q12: YES
> Reasoning: a backing literal is a value-level bijection declared on the type; `@json("name")` is a codec-specific rename on a field. They are different mechanisms, and one sentence stops the first being cited as precedent for the second (3-2 vote).
> Concern: none of substance.
>
> Q13: B
> Reasoning: listing valid values is good error quality, but fixing message format in the spec is the same prose-as-semantics problem as Q3a. One example shows intent without binding the text.
> Concern: implementations may omit the list entirely; the example should be written as the expected default.
>
> Q14: B
> Reasoning: the compile errors are typing rules (all-or-none, nullary only, distinct literals, literal values) and belong in the spec. Formatter layout is tooling, not language.
> Concern: the duplicate-literal error pointing at both spans is itself a diagnostic-quality detail; the spec should require the error, and treat the two-span shape as guidance.
>
> Q15: B
> Reasoning: cost statements are not part of the semantics and constrain nothing a program can observe. They belong in implementation docs.
> Concern: users who care about allocation get no guarantee; acceptable for v1.
>
> Q16: YES
> Reasoning: `Enum.from_int -> Option` (03_types.md:1212) is the direct twin, and citing it shows the codomain is chosen, not accidental. `Bytes.from_str` is total because it converts rather than parses, which is fine, but `Decimal.from_str` has no stated return type, and three different codomains under one method name block any future `FromStr` trait; that needs a friction ticket.
> Concern: the friction ticket may settle on Result for Decimal, leaving the family split between Option and Result with no rule for which to use.

##### DevOps

> DevOps Phase C ballot, part 1/2 (Q1-Q9, JSON).
>
> Q1: A
> Reasoning: With OPT-1, hover and completion show what the value is. `to_json` returns JsonValue, `json.encode` returns Str, and the error arm is a type a tool can inspect. OPT-2 and OPT-3 put the JSON contract in prose, so no diagnostic can fire when a hand-written impl returns bad text.
> Concern: The ~110 test call sites migrate by hand, not through the Q6 fix, and the corpus churns during the rewrite.
>
> Q2: B
> Reasoning: A decode error without a path cannot be acted on. `at $.items[2].age` is the difference between one fix and a bisect of the input. JsonError is a struct users build by hand, so adding `path` later breaks every literal. The field set has to be decided now.
> Concern: Hand-written impls will pass `path: ""` everywhere, and paths through nested hand-written impls come out empty unless the spec says the caller prefixes its own path segment.
>
> Q2b: YES
> Reasoning: Fixing where the location goes in `message` makes the error useful on its own: in a log line, in a 400 body, in LSP text. It also gives tests and tools a stable format to parse.
> Concern: Parse errors and decode errors can then drift into two location formats, unless the spec gives both formats in one table.
>
> Q3: YES
> Reasoning: Users see results, not how they are built. Specifying encode and decode by what they return lets derive stay as fast as it is today, and nothing the user writes changes.
> Concern: A fused path that diverges will only surface as a hard-to-reproduce bug, unless the corpus runs every decode test down both paths.
>
> Q3a: YES
> Reasoning: This one is mine. If one bad input gives one message from `json.decode[T]` and a different one from `parse` + `from_json`, users get two texts for one bug, and snapshot tests and docs break depending on the call path. The message is the part users actually read, so it has to be the same on both paths.
> Concern: This ties the fused reader to the tree path's exact wording, so any wording change has to land in both code paths at once.
>
> Q3b: YES
> Reasoning: If the fused reader skips a hand-written `Deserialize`, the user's error text never appears and their breakpoints never hit. From the user's side, that is a silent miscompile. Going through parse-subtree then `from_json` keeps user code, and the user's diagnostics, on the path.
> Concern: The equivalence rules must still hold where a derived type contains a hand-written one; the message and path must join cleanly across that boundary.
>
> Q4: YES (all clauses, including the lossy out-of-i64 clause)
> Reasoning: Without widening, `{"temp_c": 20}` into a Float field gives "expected Float, found Int" on input the user knows is correct, and no error text can explain that. With the lossy clause stated in the spec, the precision loss is documented behavior, not a surprise.
> Concern: A silent loss of precision on big integers (IDs over 2^53) will still bite. A lint or doc note pointing users to a Str field for big IDs should follow.
>
> Q5: C
> Reasoning: A silent delete turns every existing `json_parse` call into "unknown function" with no way forward. A deprecation warning that names the replacement tells the user exactly what to change, and it can carry a machine-applicable fix. This is how tooling handles removing public API.
> Concern: The deprecated path must not stay around for years. The removal release has to be picked when the deprecation lands, or the global arena lives on.
>
> Q6: A
> Reasoning: The diagnostic catalog is where users and tools look up codes. A named code with a stable fix is something `blink fix` and the LSP can depend on. If it exists only as an implementation ticket, it can be dropped or reworded without anyone noticing, and this is the one mistake every Str-era user will make.
> Concern: Having it in the spec forces the catalog to list the fix text too, and a later rename of `json.decode` means editing the spec, not only the code.
>
> Q7: YES
> Reasoning: `blink llms` and the spec feed users' and models' context. An unbuilt API with no marker produces calls that fail with codegen errors, not front-end ones. The marker must be in both places, or the docs lie.
> Concern: Markers go stale. Removing each marker should be part of the ticket that builds that part.
>
> Q8: YES
> Reasoning: If `get` and derived `from_json` pick different keys on one input, a user who debugs with `get` sees a value the decoder did not use. That kind of disagreement cannot be diagnosed. One rule, stated once, removes it.
> Concern: Users coming from JS expect last-wins. A lint or note on duplicate keys would help, but it is out of scope here.
>
> Q9: YES
> Reasoning: Two conflicting `JsonValue` declarations in the spec give two answers for go-to-definition and doc search, and the example teaches users to shadow a compiler-known name. `Tree` does not collide in completion.
> Concern: None worth mentioning. The only risk is missing another reference to the old example.
> DevOps Phase C ballot, part 2/2 (Q10-Q16, Str-backed enums).
>
> Q10: YES (keep all three laws)
> Reasoning: The rules replace a test file as the feature's only definition, and each law turns into a corpus test, which is how tooling keeps the rules honest. The Deserialize law ties the Q13 error to from_str: every string from_str rejects gets that error.
> Concern: The second law is written loosely (`from_str(s).map(...)`). The spec text needs it in exact form, or readers will argue about what it means.
>
> Q11: A
> Reasoning: The moderator's fact decides it: `@derive(Display)` exists today and would print `InProgress` while the JSON says `"in_progress"`. That is a mismatch users will see in logs, and no diagnostic can explain it. A adds no implicit feature but closes the gap now. B leaves the mismatch shipping, and C adds a second implicit rule. Separately, the E0523 error on `"{s}"` for an enum with no Display should suggest `.to_str()`.
> Concern: A user who writes `@derive(Display)` wanting the variant name can't get it. The docs for derive Display must state the override.
>
> Q12: YES
> Reasoning: One sentence heads off the obvious feature request and the follow-up "why does enum renaming work but field renaming doesn't" question.
> Concern: None.
>
> Q13: A
> Reasoning: `unknown value "x" for Status; expected one of: "open", "in_progress"` fixes the problem in one step for humans and models. If the format isn't normative, it will decay to "invalid value". With Q3a, the text also has to match across the fused and tree paths, so it needs a fixed format.
> Concern: Enums with many variants give long messages. The spec may need a cap on how many values it lists ("... and N more").
>
> Q14: A
> Reasoning: Each compile error needs a span rule, or the implementation will report the duplicate on only one site. The fmt rule (one variant per line, `=` not aligned) keeps adding a variant a one-line diff, which gofmt learned the hard way. I already moved hover and completion out to tooling tickets.
> Concern: The panel may think a fmt rule does not belong in the language spec. If so, put it in the fmt section, not §3.4.
>
> Q15: A
> Reasoning: No tooling stake. A non-normative note is harmless and helps users reason about performance.
> Concern: Notes read as promises. Mark it clearly as non-normative.
>
> Q16: YES
> Reasoning: Citing `from_int -> Option` shows the family pattern. The friction ticket catches the Decimal/Bytes mismatch, where `?` on an Option in a function that returns Result gives a confusing error. That error should also suggest `.ok_or(...)`.
> Concern: If the friction ticket has no owner, the mismatched codomains ship as they are.
>
> End of ballot.

##### AI/ML

> aiml Phase C ballot, part 1/2 (Part 1 — JSON, Q1-Q9)
>
> Q1: A
> Reasoning: All six Phase A texts arrived at the same user code: json.encode / json.decode[T] / to_json() -> JsonValue. A model gets right the spelling that every source agrees on. A spec'd Str stopgap would train a corpus on a dead API that every later model inherits.
> Concern: The ~110 test call sites stay Str-typed until migration step 3. If migration stalls, the repo keeps teaching the old spelling, and that repo is the training data.
>
> Q2: B
> Reasoning: Models debug from error text, and "at $.items[2].age" lets a model fix the input in one step with no retry. Sys and PLT showed that the field set is public API: users build JsonError literals in hand-written impls. So a field added later breaks their code, and we should decide it now.
> Concern: Hand-written impls pass path: "" and give empty paths, so the location falls back to message text. Q2b covers that.
>
> Q2b: YES
> Reasoning: A fixed location format in message is the floor that makes every error useful, even with an empty path. A model can also learn to parse a fixed format.
> Concern: The spec can drift into specifying full message text. It should fix only the location part.
>
> Q3: YES
> Reasoning: Nothing a user writes changes. It removes the cost objection to OPT-1 at no learnability cost.
> Concern: A fused decoder that differs from the tree path in edge cases (numbers, duplicate keys) gives two behaviours for one call. Q4 and Q8 must bind both paths.
>
> Q3a: YES
> Reasoning: One bug must give one message. If json.decode[T](s) and parse-then-from_json report different text for the same bad input, a model's learned repair works on one path and fails on the other. DevOps's point matches mine.
> Concern: It constrains the fused implementation. If the text cost proves too high, the fallback is to fix only the location part (Q2b), not free-form text.
>
> Q3b: YES
> Reasoning: A fused reader that bypasses a user's hand-written Deserialize makes decode[T] silently disagree with the user's own code. That is the hardest kind of bug for a model to diagnose from the source.
> Concern: Mixed derived and hand-written trees lose some speed. That is acceptable.
>
> Q4: YES, all clauses including the lossy outside-i64 clause.
> Reasoning: {"temp_c": 20} into a Float field is exactly what generated fixtures and LLM-written tests produce. Without widening it becomes the most common false failure. Stating the lossy case gives the model a rule to know, not a surprise to find.
> Concern: Silent precision loss on huge integer IDs (for example Twitter-style IDs > 2^53) can surprise users. The spec example should show the Str-field workaround.
>
> Q5: A
> Reasoning: What matters for models is that no second public dynamic-JSON spelling appears in the stdlib or in blink llms. Whether a private backing store exists is invisible to them. A satisfies that and leaves the implementation free.
> Concern: A private detail that lib/std or the compiler still calls can leak back into examples. Nothing outside json.bl should call it.
>
> Q6: A
> Reasoning: blink llms and the diagnostic catalog feed model context. A spec'd, stable diagnostic with a machine-applicable fix is what turns the Rails/pydantic "to_json returns a string" prior into a one-step repair, not a retry loop. It is the price of keeping the to_json name.
> Concern: Spec text that is too specific (exact wording) could freeze a message we later want to improve. Spec the trigger and the named replacement, not the prose.
>
> Q7: YES
> Reasoning: An unmarked, unbuilt API in LLM context is what makes models generate calls that fail. The marker must also reach blink llms, or it has no effect for models.
> Concern: Markers go stale (Min). Remove each one in the same change that builds the part, and have CI or a test check this if possible.
>
> Q8: YES
> Reasoning: One rule for both get and derived from_json means one fact to learn and no tree-vs-typed disagreement on the same input.
> Concern: Users coming from JS expect last-wins, so a line in the spec example helps.
>
> Q9: YES
> Reasoning: An example that redeclares a compiler-known name with a different shape (Boolean, Number) teaches models variants that do not exist. Tree carries no JSON association.
> Concern: None material. Also check blink llms and the tests for the old shape.
> aiml Phase C ballot, part 2/2 (Part 2 — Str-backed enums, Q10-Q16)
>
> Q10: YES, all three laws, no drops.
> Reasoning: Today the feature exists only in one test file, so a model has nothing to learn it from. Placing it beside to_int/from_int shows one conversion family. The laws are compact, exact definitions that the corpus can test, and the Deserialize law ties JSON behaviour to from_str so there is one rule, not two.
> Concern: The second law as written ("from_str(s).map(...) is Some(s) or None") is loose. It should read "from_str(s).map(to_str) is Some(s) or None" so it is not misread.
>
> Q11: A
> Reasoning: My Phase B rule was "Display follows what plain enums do". The moderator fact says plain enums have no Display unless declared, so no implicit Display follows. Once @derive(Display) is present, "{s}" printing InProgress while the JSON says "in_progress" is exactly the kind of mismatch that makes a model write wrong assertions. The conditional law prevents it at no cost now.
> Concern: Users will write "{status}" expecting the literal and hit E0523. That error must suggest .to_str() or @derive(Display).
>
> Q12: YES
> Reasoning: Without it, a model generalizes Open = "open" into field-level @json("name") renaming, which the panel rejected 3-2. One sentence closes that gap.
> Concern: None.
>
> Q13: A
> Reasoning: An error that lists the valid values lets a model (or a web client) repair its input with no lookup. A normative format also makes the message stable enough to learn.
> Concern: Enums with many variants give long messages. The spec could allow truncation after N values with a count.
>
> Q14: B
> Reasoning: Listing the compile errors gives models the exact failure set for the feature, and each maps to a diagnostic they can learn. A fmt rule is tooling, not language. It belongs with the formatter goldens.
> Concern: If the fmt rule is not recorded anywhere, the formatter's choice drifts. File it as a tooling ticket.
>
> Q15: A
> Reasoning: Harmless as a note and useful to systems readers. It must not be normative, so implementations stay free.
> Concern: A note may be read as a guarantee. Label it clearly as non-normative.
>
> Q16: YES
> Reasoning: from_int -> Option is the direct precedent. Stating it stops models from writing Status.from_str(x)? in a Result fn (the Rust FromStr prior). The Decimal/Bytes from_str mismatch is a real learnability hazard and deserves the friction ticket.
> Concern: Until the friction ticket closes, the spec shows three from_str codomains side by side, which is itself a teaching hazard.
>
> End of aiml ballot.

##### Minimalism

> Min Phase C ballot, part 1/2 (Q1-Q9, JSON)
>
> Q1: A
> Reasoning: OPT-1 reverses no recorded vote. It also subtracts from the language: one enum plus the 5-function surface replaces 27 Int-handle functions and a global arena. Of the three options it is the only one that shrinks what a user must learn.
> Concern: JsonValue stays spec-only for a long time while ~110 Str-typed call sites keep teaching the old shape.
>
> Q2: A ({ message: Str })
> Reasoning: The burden of proof is on the new field. I grant Sys and PLT's point: hand-written impls build JsonError literals, so adding a field later breaks them. But Q2b gets the location to users with no new field. If the panel wants path, the break can be avoided later with a constructor fn and not a public literal.
> Concern: if A wins and path is added in v2, every hand-written `JsonError { message: ... }` literal breaks.
>
> Q2b: YES
> Reasoning: It carries the location, the one real need behind `path`, as part of the message contract, and it adds no type surface. It is the cheap way to satisfy DevOps and AI/ML.
> Concern: spec-fixed wording in message turns into a de facto parse format that users grep.
>
> Q3: YES
> Reasoning: It adds no user-visible surface and lets the implementation skip the tree. The composition that was voted 5-0 stays the meaning.
> Concern: a fused path drifts from the tree path, and only the corpus catches it.
>
> Q3a: NO
> Reasoning: Requiring exact message text equality puts implementation detail in normative text. Inputs accepted, Ok values and Err location are what programs depend on. With Q2b, both paths must still name the location.
> Concern: users see two different message texts for the same bad input and file them as bugs.
>
> Q3b: YES
> Reasoning: This is a soundness rule, not a feature. Without it a fused reader bypasses user code, and decode stops being parse-then-from_json.
> Concern: a slow path for any field whose type has a hand-written impl surprises users who measure performance.
>
> Q4: YES (with the last clause)
> Reasoning: A total number rule costs a few lines and prevents the `{"temp_c": 20}` false failure. The lossy large-integer clause states behaviour that is otherwise undefined, and one sentence is cheaper than an error class.
> Concern: silent precision loss on large ids (e.g. >2^53 snowflake ids) surprises users who never read the clause.
>
> Q5: A
> Reasoning: Two public dynamic-JSON models is the accretion I object to, and removal from the public surface fixes that. Whether a private backing store stays is an implementation choice, not a spec one. A deprecation cycle (C) keeps two models public for a release, for a pre-1.0 API that no lib/std code calls.
> Concern: "private backing detail" becomes the permanent excuse to keep the global arena and its reentrancy bug.
>
> Q6: B
> Reasoning: A diagnostic is tooling quality, not language. The catalog should list codes that the language defines, not every helpful hint. File it as a ticket; the machine-applicable fix is also how the tests migrate.
> Concern: without spec text the diagnostic never gets built, and users get a plain type mismatch.
>
> Q7: NO
> Reasoning: The spec states the language, and implementation status belongs in the tracker and in `blink llms` generation. Inline markers go stale and get learned as permanent. I will not object if blink llms marks it on its own.
> Concern: if NO wins, LLMs generate calls to unbuilt json.parse/decode from the spec and fail.
>
> Q8: YES
> Reasoning: One sentence decides behaviour that would otherwise differ between get and from_json on the same tree. First-match is also the cheapest rule.
> Concern: users coming from JS expect last-wins and get the first value without a warning.
>
> Q9: YES
> Reasoning: An example in the spec must not shadow a compiler-known type or teach a second, conflicting shape. `Tree` is neutral.
> Concern: none worth naming.
> Min Phase C ballot, part 2/2 (Q10-Q16, Str-backed enums)
>
> Q10: YES (keep all three laws)
> Reasoning: The section only writes down what the tests already define, beside to_int/from_int, so the reader sees one conversion family and not a new feature. The laws are the cheapest precise definition, and each one becomes a corpus test.
> Concern: the Deserialize law ties enum semantics to JsonValue, so it becomes spec-only for as long as JsonValue is.
>
> Q11: B
> Reasoning: The moderator's fact cuts my way. Today one Display rule covers every enum: `@derive(Display)` prints the variant name. A overrides that rule for one kind of enum, which makes a second rule. C adds implicit behaviour. Silence keeps the single existing rule, and `to_str()` already gives the literal. Whether Str-backed enums should print their literal deserves its own ticket, and the panel should vote it on its own terms.
> Concern: if B wins, `"{s}"` under @derive(Display) prints `InProgress` while JSON says `in_progress`, and users call that a bug before the follow-up ticket lands.
>
> Q12: YES
> Reasoning: Backing literals rename variants on the wire, and `@json("name")` field renaming lost 3-2. One sentence stops someone later citing this feature as precedent for reopening that vote.
> Concern: none worth naming.
>
> Q13: B
> Reasoning: Listing the valid values is good implementation quality, but message format in normative text freezes wording that should be free to improve. One example shows the intent.
> Concern: an implementation ships a bare "invalid value" message and cites the non-normative status.
>
> Q14: B (compile errors only)
> Reasoning: The four compile errors define which programs are legal, so they are language. The fmt rule is tooling style and belongs in fmt docs or goldens.
> Concern: the duplicate-literal error does not say "points at both spans" in the spec, so tools may report one span only.
>
> Q15: B (omit)
> Reasoning: Cost statements are not language semantics, and the spec should not promise codegen shape. They go stale the first time the backend changes.
> Concern: none worth naming; if A wins, keep it clearly non-normative.
>
> Q16: YES
> Reasoning: `Enum.from_int -> Option` (03_types.md:1212) is the direct precedent, and one sentence citing it makes the choice look deliberate, not accidental. The Decimal/Bytes codomain question is real drift and belongs in a friction ticket, not this change.
> Concern: the friction ticket stays open for a long time, and three from_str codomains keep confusing users.

#### Phase D — Round 2 on Q3a, Q5, Q6, Q13, Q15

Each panelist read the other five's Phase C text on these five questions, named the strongest opposing argument, and offered narrower wording. The re-vote ballot quoted each proposed wording with its author.

Re-vote options:

- **Q3a.** A (PLT; Minimalism and Systems support the same rule): equal `Result` values on both paths, including every `JsonError` field; the spec fixes only the location content of `message`, and the rest of the wording is free but the same on both paths. B (DevOps): location and `path` normative, identical text non-normative. C (AI/ML): same location content and same expected/found kinds; other wording may differ.
- **Q5.** A1: removed from the public surface, and a private store, if kept, is not global shared-mutable state. A2 (Minimalism): A1 plus a spec rule that a removed name is a compile error naming its replacement. A3 (DevOps): A1 plus an implementation ticket for a removed-name error for one release. B: delete outright. C: deprecate, then remove.
- **Q6.** A-code: a normative catalog entry fixes the code, the trigger, the named replacements and a machine-applicable fix; prose is not normative. A-nocode: the same, without a fixed code number. B: implementation ticket only.
- **Q13.** A-content: the error names the rejected value, the enum type and every valid literal; truncation after N with a count is allowed; the example is non-normative. A-content-ordered (Systems): A-content, with the literals in declaration order. B: example only.
- **Q15.** A: non-normative note headed "Reference implementation:". B: omit.

Results:

| Q | Result | Tally |
|---|--------|-------|
| Q3a | A | 6-0 (PLT and Minimalism moved from NO) |
| Q5 | A3 | 6-0 (Systems moved from B, DevOps from C) |
| Q6 | A-code | 6-0 (Systems, PLT, Minimalism moved from B) |
| Q13 | A-content-ordered | 6-0 (Systems, PLT, Minimalism moved from B) |
| Q15 | A | 4-2 (PLT, Minimalism: omit). The Phase D cap was reached, so the majority ships and the dissent is recorded |

##### Arguments

##### Systems

> Sys Phase D replies (Q3a, Q5, Q6, Q13, Q15).
>
> Q3a
> 1. PLT's point is the strongest one: programs branch on accepted inputs, Ok values and Err path, not on the prose. But requiring equal text costs nothing at run time. Both paths call one shared error formatter on the error path, so the "byte-for-byte reproduction" burden is one function, not two wordings kept in sync.
> 2. Not changed: YES.
> 3. Narrower wording: "Both paths build `message` with the same formatter from the same (location, kind, found, expected) data, so for one input they produce equal `JsonError` values. The spec fixes that data (Q2b), not the prose around it."
>
> Q5
> 1. DevOps (C): a deprecation cycle keeps the global, non-reentrant arena public for one more release. That is for a pre-1.0 API that no lib/std code calls. The machine-applicable fix DevOps wants can hang on the "unknown function json_parse" error just as well.
> 2. Changed from B to A, with a condition. PLT and Min both named my real concern, and I only need that one hazard closed. I do not need a delete.
> 3. Narrower wording: "A, and a private backing store, if one exists, holds no process-global mutable state: each JsonValue owns its storage, and no operation invalidates another live value."
>
> Q6
> 1. AI/ML's argument is the strongest: "spec the trigger and the named replacement, not the prose." That removes my objection, which was about freezing wording.
> 2. Changed from B to a narrowed A.
> 3. Narrower wording: "A diagnostic catalog entry with a stable code. Trigger: a Str expression used where to_json's result or from_json's argument is expected. It must name json.encode / json.decode[T] and carry a machine-applicable fix. Message prose is not normative."
>
> Q13
> 1. DevOps's argument is the strongest, and it follows from my own Q3a vote: if both paths must produce equal messages, the content of this message has to be fixed somewhere.
> 2. Changed from B to a narrowed A.
> 3. Narrower wording: "Normative content, not format: the error names the rejected value, the enum type, and every valid literal in declaration order. An implementation may truncate after N values with a count of the rest. The spec shows one example string as non-normative."
>
> Q15
> 1. Min's argument is the strongest: the notes go stale the first time the backend changes. The fix for that is the label, not leaving the note out. Users choosing between a Str-backed enum and a Map[Str, T] on a hot path need the cost, and a note is the only place they get it.
> 2. Not changed: A.
> 3. Narrower wording: "Non-normative note, headed 'Reference implementation:', stating that to_str does not allocate and from_str does not allocate or hash. It makes no promise about other implementations."

##### Web/Scripting

> Web Phase D replies (Q3a, Q5, Q6, Q13, Q15).
>
> Q3a
> 1. PLT's argument is the strongest: a program branches only on inputs, Ok values and Err path, so byte-equal text is a quality string made into law. But under Q3b both paths are compiler-generated code for derived impls only, so one shared error formatter meets the rule at almost no cost, and users read the text, not the path.
> 2. Unchanged: YES.
> 3. Narrower wording that should resolve the split: "Both paths give the same normative content in `message`: the location from Q2b, and for an unknown enum literal the valid values from Q13. Other wording may differ."
>
> Q5
> 1. Sys's argument is the strongest: a private arena keeps the non-reentrant global state alive under async.spawn. DevOps's deprecation cycle protects users we do not have, since no lib/std code calls json_* and the language is pre-1.0.
> 2. Unchanged: A, but I accept Sys's hazard as a constraint on A.
> 3. Narrower wording: "A, and any private backing store must not be process-global shared mutable state (no json_clear()-style global reset)." That gives Sys the safety point and still leaves the implementation free.
>
> Q6
> 1. PLT and Min make the strongest argument: diagnostic wording is implementation quality and should not freeze in the spec. I agree about the prose. What must not be optional is that this mistake gets a named code and a fix that tools can apply automatically, because every Str-era user and the ~110-site migration will hit it.
> 2. Unchanged: A, narrowed as follows.
> 3. Narrower wording (AI/ML's point): "The catalog specifies the trigger (a Str where to_json/from_json need JsonValue), the replacement it names (json.encode / json.decode[T]) and that it carries a machine-applicable fix. The message prose is not normative."
>
> Q13
> 1. PLT and Min's argument is the strongest: a normative message format is prose-as-semantics, as in Q3a. The content (type name plus every valid literal) is what lets a client fix its request. The punctuation is not, and I will give that up.
> 2. Changed from "format in the spec" to "content in the spec".
> 3. Narrower wording: "The Deserialize error for an unknown literal must name the enum type and list its valid literals. An implementation may truncate after N values if it gives the remaining count. Exact wording is not normative; one example shows the expected default."
>
> Q15
> 1. Min's argument is the strongest: cost notes go stale when the backend changes, and they constrain nothing a program can observe. I hold A only weakly, because the "allocates nothing" fact helps a web dev choose this over a Map, but I will not block on it.
> 2. Unchanged but weak: A, and I can accept B.
> 3. Narrower wording (Sys's): "A, worded as 'In the reference implementation, ...' and marked non-normative."

##### PLT

> PLT Phase D replies for Q3a, Q5, Q6, Q13, Q15. I changed my position on Q3a, and on Q6 and Q13 I propose narrower wordings.
>
> Q3a (CHANGED: NO -> YES). The strongest argument is DevOps's "one bug, one text", and on reflection it is also the PLT argument: `message` is a field of the JsonError value, so a program can observe it, and "same Ok values" but "only same Err path" is an equivalence that stops halfway. Denotational equivalence means the whole Err value is equal, message included. Narrower wording, if it helps Min: "json.decode[T](s) and json.parse(s) then T.from_json(v) return equal Result values, including every JsonError field; the spec fixes the location content of message (Q2b) and leaves the rest of the wording to the implementation, but it must be the same on both paths."
>
> Q5 (UNCHANGED: A). DevOps argues for C: a silent delete leaves users with "unknown function". But no lib/std code calls json_*, it is pre-1.0, and a deprecation cycle keeps two public dynamic-JSON models for a release, which Min rightly objects to. Sys's reentrancy point is real, and it is about the private store, not the public surface. Narrower A that covers Sys: "removed from the public surface in the release JsonValue lands; any private backing store must not be global mutable state shared across tasks (no json_clear-style reset)."
>
> Q6 (MOVED toward a narrow A). DevOps's argument is the strongest: tools such as `blink fix` and the LSP can depend only on a stable code, and a ticket can be dropped silently. What I object to is freezing prose, and AI/ML's own concern already names the fix. Narrower A: "the diagnostic catalog defines a code for a Str passed to from_json, or to_json's result used as Str, with a machine-applicable fix naming json.decode[T] / json.encode; the message wording is not normative." I would vote for that.
>
> Q13 (MOVED toward a narrow A). DevOps says a non-normative format "decays to invalid value", and Min's own concern admits the same; I accept that an example alone does not stop this. DevOps's link to Q3a needs equal text on both paths, not a fixed format. Narrower A, stating content not format like Q2b: "the error message names the enum type, the rejected string, and the valid literals (an implementation may list the first N and give the count of the rest); the wording is not normative." I would vote for that over both A and B.
>
> Q15 (UNCHANGED: B, low stakes). The strongest argument is Sys's: users choosing this over a Map[Str, T] want to know the cost. But a note constrains nothing that is observable, and it goes stale without anyone checking. If A wins, use Sys's wording: "Non-normative: in the reference implementation, to_str allocates nothing and from_str compares by length and bytes." I will not block on it.

##### DevOps

> DevOps Phase D replies (169kjt): Q3a, Q5, Q6, Q13, Q15.
>
> Q3a
> 1. PLT's argument is the strongest one: a program can branch only on accepted inputs, Ok values and the Err path, so making prose normative is the wrong layer. That is correct for the spec, but Blink has one implementation, and users still see two texts for one bug if nothing enforces it.
> 2. Changed: from a plain YES to the narrower wording below. What I need is enforcement, and a test can give that without the spec binding prose.
> 3. Narrower wording: "Normative: inputs accepted, Ok values, Err `path`, and the Q2b location content of `message` match on both paths. Non-normative: the reference implementation produces identical `message` text on both paths, and the corpus runs each decode error test down both paths and asserts equal text."
>
> Q5
> 1. Min's and Web's argument is the strongest: this is a pre-1.0 API with no lib/std callers, so a deprecation cycle keeps two public dynamic-JSON models alive for a release and buys nothing. I accept that. My real concern was the bare "unknown function" error with no way forward, and a deprecation cycle is not the only fix for that.
> 2. Changed: C to A, with the addition below. I also back Sys and PLT that any private store must not be a global shared-mutable arena.
> 3. Narrower wording: "A, plus: for one release after removal, a call to a removed `json_*` name gives a front-end error that names its replacement (for example `json_parse` -> `json.parse`). This is an implementation ticket, not spec text."
>
> Q6
> 1. Sys and PLT make the strongest argument: a catalog entry freezes wording that tooling should be free to improve. AI/ML's concern already answers it: spec the trigger and the replacement it names, not the prose.
> 2. Changed: A narrowed. The exact wording can stay free, but the trigger and the fix must not be able to slip away unnoticed.
> 3. Narrower wording: "§3.6.2 states: when a Str is passed to `from_json`, or the result of `to_json` is used as a Str, the compiler reports an error that names `json.encode` / `json.decode[T]` and offers a machine-applicable fix. The message wording and code number are implementation quality."
>
> Q13
> 1. PLT makes the strongest argument: a fixed message format is the same prose-as-semantics problem as Q3a. The same split applies here as there: bind the content, not the wording.
> 2. Changed: A narrowed to content only.
> 3. Narrower wording: "Normative: the Deserialize error for an unknown literal names the rejected value, the enum type, and every valid backing literal (an implementation may list the first N followed by a count of the rest). Non-normative: one example of the format, `unknown value \"x\" for Status; expected one of: \"open\", \"in_progress\"`."
>
> Q15
> 1. Min's argument is the strongest: notes go stale the first time the backend changes. Sys's wording, "the reference implementation", keeps the note honest about what it describes.
> 2. Unchanged, A, but I have no tooling stake here and won't block B.
> 3. Narrower wording: "A, worded as: 'Non-normative: in the reference implementation, to_str allocates nothing and from_str compares lengths and then bytes.'"

##### AI/ML

> aiml Phase D replies (Q3a, Q5, Q6, Q13, Q15)
>
> Q3a
> 1. PLT's argument is the strongest: programs branch on accepted inputs, Ok values and the Err path, not on prose, so byte-for-byte text is a heavy obligation. But a model repairs its input from the facts in the message, so what must match is those facts, not the wording.
> 2. Changed: I move from full text equality to the narrower wording below.
> 3. Narrower wording: "Both paths give messages with the same location content (Q2b) and name the same expected kind and found kind (for example 'expected Float, found Str'); other wording may differ."
>
> Q5
> 1. Sys's argument is the strongest: a private arena keeps the json_clear() reentrancy hazard, and Min and PLT flagged the same risk. DevOps's silent-delete worry has little weight for a pre-1.0 API that no lib/std code calls, and the Q6 diagnostic can cover a stale json_parse call anyway.
> 2. Unchanged: A.
> 3. Narrower wording: "A, and a private backing store, if one is kept, must not be global shared-mutable state (no store that one call like json_clear() empties for every caller)." That keeps A's freedom and closes Sys's hazard.
>
> Q6
> 1. PLT's argument is the strongest: the typing rule is already in §3.6.2, and wording is implementation quality. I agree the wording must stay free. But Min and PLT both named the concern that without spec text the diagnostic never gets built, and it is the one mistake every Str-trained model will make.
> 2. Unchanged in substance, and I accept the narrower form below.
> 3. Narrower wording: "Normative: when a Str meets to_json's result type or from_json's parameter, the compiler reports a diagnostic that names json.encode / json.decode[T] and offers a machine-applicable fix. The wording and the code number are not normative."
>
> Q13
> 1. PLT's argument is the strongest: a fixed message format is the same prose-as-semantics problem as Q3a. The content (the bad value and the valid set) is what a client or model acts on, and that is a fact, not prose.
> 2. Changed: I move from a normative format to normative content.
> 3. Narrower wording: "Normative: the error names the unknown value and lists the valid literals (an implementation may truncate after N and give a count). The format is not normative; the spec shows one example."
>
> Q15
> 1. Min's argument is the strongest: notes go stale when the backend changes. Sys's "the reference implementation" wording limits that risk.
> 2. Unchanged: A, but this is low stakes for me and I will not block on B.
> 3. Narrower wording: "A, worded as: 'Non-normative: in the reference implementation, to_str allocates nothing and from_str compares lengths and then bytes.'"

##### Minimalism

> Min Phase D replies (169kjt): Q3a changes to YES; Q6 and Q13 move to narrower wordings; Q5 and Q15 hold.
>
> Q3a
> 1. The strongest argument is Sys's: once Q2b fixes the location content, a matching message costs nothing, and it is the only complete equivalence test. My objection was "implementation detail in normative text", but Q3a fixes no wording. It only says both paths give the same text, whatever that text is, and that adds nothing a user must learn.
> 2. Changed: NO -> YES.
> 3. No narrower wording needed.
>
> Q5
> 1. The strongest argument is DevOps's: a silent delete turns `json_parse` into "unknown function" with no way forward. That is a diagnostic problem, not a reason to keep two public models for a release. Sys's reentrancy point is also real, and one clause handles it without the spec choosing the backing design.
> 2. Unchanged (A), but I would take this narrower A.
> 3. Wording: "In the release that lands JsonValue, the json_* functions leave the public surface. Any private backing store must not be shared mutable global state. A call to a removed json_* name is a compile error that names its replacement."
>
> Q6
> 1. The strongest argument is DevOps's: a named code in the catalog is something `blink fix` and the LSP can depend on, and a ticket can be dropped without anyone noticing. AI/ML's scope answers my freeze objection. If the entry fixes the trigger and the replacement names, not the prose, it binds no wording and adds one catalog row.
> 2. Changed: B -> A, on the narrower wording only.
> 3. Wording: "A normative catalog entry fixes the code, the trigger (a Str where to_json/from_json requires JsonValue, or to_json used as Str) and the named replacements json.encode / json.decode[T], with a machine-applicable fix. Message prose is not normative."
>
> Q13
> 1. The strongest argument is Web's: if only an example shows the list, implementations drop it. I voted YES on Q2b, which fixes the content of a message and not its wording, and the same line works here. DevOps's claim that Q3a needs a fixed format is wrong: Q3a is relational, so it needs the same text on both paths, not a spec'd text.
> 2. Changed: B -> A, on the narrower wording only.
> 3. Wording: "The error for an unknown literal must contain the rejected value, the enum name and the valid literals. An implementation may truncate a long list with a count of the omitted values. Exact wording is not normative; the spec gives one example."
>
> Q15
> 1. The strongest argument is Sys's: users who choose this over a Map[Str, T] want to know the cost. That belongs in a guide or in `blink llms` performance notes. Web and DevOps both name the risk themselves: a note goes stale and gets read as a promise.
> 2. Unchanged (B).
> 3. If A wins, use Sys's wording: "Non-normative: in the reference implementation, to_str allocates nothing and from_str compares lengths, then bytes."

##### Re-vote ballots

##### Systems

> Sys Phase D re-vote (169kjt): Q3a A, Q5 A3, Q6 A-code, Q13 A-content-ordered, Q15 A.
>
> Q3a: A
> Reasoning: equality of the whole Result, JsonError included, is the complete equivalence, and it is what I argued for. It binds no prose: one shared formatter on the error path meets it at zero run-time cost. B only makes the equal text a matter of test hygiene, and C lets two error values differ for the same input, so the relation stops halfway.
> Concern: the fused reader must record the same (location, kind) data as the tree path at the point of failure, and a fast path that bails out early will be tempted to skip that.
>
> Q5: A3
> Reasoning: my only hard requirement was that no global shared-mutable arena survives, and A1 covers that. The removed-name hint is useful for one release, but it is tooling, so it belongs in an implementation ticket. A2 would put a permanent spec rule in place for a transition that ends.
> Concern: the private store may keep a lazily initialized global cache "for speed", so the no-global-state clause has to be read as covering caches too.
>
> Q6: A-code
> Reasoning: `blink fix` and the LSP key on a stable code, not on prose, and a catalog row costs nothing at run time. Fixing the trigger, the replacements and the fix while leaving the prose free answers my Phase C objection completely.
> Concern: the trigger has to be scoped to the to_json/from_json signatures, so it does not fire on unrelated Str/JsonValue mismatches.
>
> Q13: A-content-ordered
> Reasoning: declaration order makes the list deterministic, and under Q3a A both paths must produce equal text. It also costs nothing, since the literal table the codegen emits is already in declaration order. Without an order, a hash-ordered implementation passes A-content and still breaks snapshot tests.
> Concern: the truncation cap N is left to the implementation, so two implementations may still differ on long enums.
>
> Q15: A
> Reasoning: users choosing a Str-backed enum over a Map[Str, T] on a hot path need the cost, and the "Reference implementation:" heading keeps it honest.
> Concern: the note goes stale after a codegen change, so a corpus or bench check that it holds would be the ideal. That is out of scope for this ticket.

##### Web/Scripting

> Web Phase D re-vote (Q3a, Q5, Q6, Q13, Q15).
>
> Q3a: A
> Reasoning: One bad payload must give one error text, whichever call path it went through. PLT's point is right: `message` is a field of the Err value a program can see, so the whole JsonError must be equal. A still fixes only the location content and leaves the wording free, so it binds no prose. B and C allow two texts for one bug, which is the Stack Overflow question and the broken snapshot test I want to prevent.
> Concern: the fused reader needs one shared error formatter, and if an implementer writes a second one the two will drift.
>
> Q5: A3
> Reasoning: The json_* functions leave the public surface, and the private store is not global mutable state, so Sys's hazard is closed. A user with an old `json_parse` call should get an error that names `json.parse`, not a bare "unknown function". That is good DX, but a one-release migration aid does not belong in the spec for all time, so an implementation ticket (A3) is the right home, not spec text (A2).
> Concern: the ticket for the removed-name error gets dropped, and the few early users get "unknown function" with no hint.
>
> Q6: A-code
> Reasoning: A stable code is what users search for and what `blink fix` and the LSP key on. Leaving the code number free (A-nocode) lets it change under the tools. The prose stays free in both options, so the code costs nothing that matters and gives this, the most common mistake of the feature, a fixed handle.
> Concern: the catalog entry names json.encode / json.decode[T], so a later rename means a spec edit too.
>
> Q13: A-content-ordered
> Reasoning: The rejected value, the type and the valid literals are what let an API client fix its request, and that is the content I care about, not punctuation. Declaration order makes the message deterministic, so snapshot tests and API docs stay stable, and it costs the implementation nothing.
> Concern: with truncation allowed, a long enum may hide the value the user meant behind "and N more".
>
> Q15: A
> Reasoning: "to_str allocates nothing" helps a web developer choose a Str-backed enum over a Map[Str, T] on a hot path. The "Reference implementation:" heading keeps it honest as a description rather than a promise. This matters little to me, and B is acceptable.
> Concern: the note goes stale after a backend change, and nobody checks notes.

##### PLT

> PLT Phase D re-vote: Q3a A, Q5 A3, Q6 A-code, Q13 A-content-ordered, Q15 B.
>
> Q3a: A
> Reasoning: `message` is a field of the JsonError value, so a program can read it. An equivalence that covers Ok values but only part of the Err value stops halfway. A states the full rule (equal Result values, every field) and still leaves the wording free, because it is a relation between the two paths and binds no prose. B puts the text equality in a test rather than in the spec, and C does not state the whole equality.
> Concern: the implementation must route both paths through one error formatter, or a wording change on one path breaks the rule without anyone noticing.
>
> Q5: A3
> Reasoning: removing json_* from the public surface and banning a global shared-mutable backing store closes both real hazards: two public models and Sys's reentrancy problem. A diagnostic for a name that is no longer part of the language is a transition aid, not language, so it belongs in an implementation ticket (A3) rather than in the spec (A2).
> Concern: an implementation ticket can slip, so the removal release may ship with a bare "unknown function" error.
>
> Q6: A-code
> Reasoning: DevOps's argument moved me: `blink fix` and the LSP can depend only on a stable code, so the code is the part worth making normative. A-nocode keeps the trigger but drops the one thing tools can key on. Leaving the prose non-normative answers my original objection.
> Concern: the catalog entry names json.encode / json.decode[T], so renaming either later needs a spec edit.
>
> Q13: A-content-ordered
> Reasoning: fixing content rather than format is the same line as Q2b. Declaration order makes the listed set deterministic, which Q3a's equality between the two paths needs, and "truncate after the first N" is only well-defined with a fixed order.
> Concern: users may read declaration order as a meaningful order for the enum, but it is only a listing order.
>
> Q15: B
> Reasoning: a cost note constrains nothing a program can observe, and no check keeps it true after a backend change. Performance guidance belongs in a guide or in `blink llms`, not the spec.
> Concern: if B wins, users who choose between this and a Map[Str, T] on a hot path get no stated cost; acceptable for v1.

##### DevOps

> DevOps Phase D re-vote (169kjt): Q3a A, Q5 A3, Q6 A-code, Q13 A-content-ordered, Q15 A.
>
> Q3a: A
> Reasoning: A gives me what I asked for in Phase C, one text for one bug, and it gives it on PLT's grounds: `message` is a field of an observable value, so equal Result values include it. That beats my own B, which only enforced the rule through a non-normative corpus test. C lets the wording differ, and that is exactly what breaks snapshot tests.
> Concern: Both paths must share one error formatter (Sys's point), or wording changes will drift between the fused reader and the tree path.
>
> Q5: A3
> Reasoning: I keep my own wording. The "names its replacement" error is a migration aid with a limited life, and a spec rule about functions that no longer exist (A2) would stay in the spec forever. A3 still carries A1's rule that no private store may be global shared-mutable state.
> Concern: An implementation ticket can slip. It should block the release that lands JsonValue.
>
> Q6: A-code
> Reasoning: I move from my Phase D A-nocode wording to Min's. `blink fix`, the LSP, suppression lists and docs all key on a stable code, and that is the exact reason I wanted this in the catalog. A-code fixes the code, the trigger, the replacement names and the fix, and it leaves the prose free, so Sys's and PLT's freeze objection is still answered.
> Concern: The code number is frozen for good, so choose it deliberately, not from the next free slot.
>
> Q13: A-content-ordered
> Reasoning: Declaration order makes the list deterministic. Snapshot tests need that, and Q3a now requires equal text on both paths, which is impossible if one path lists the values in a different order. The ordering rule costs nothing.
> Concern: The truncation threshold N is still left to the implementation, so it has to be the same on both paths as well.
>
> Q15: A
> Reasoning: The note carries the "Reference implementation:" heading and promises nothing about other implementations. It helps users choose between a Str-backed enum and a Map[Str, T]. I have no tooling stake here.
> Concern: The note goes stale unless a codegen change to to_str/from_str also updates it.

##### AI/ML

> aiml Phase D re-vote (Q3a, Q5, Q6, Q13, Q15)
>
> Q3a: A
> Reasoning: My Phase D narrowing (C) answered a cost objection, and Sys's shared-formatter point removes that cost: one formatter fed the same data gives the same text for free. PLT's point also holds: message is an observable field, so an equivalence that covers every field is the complete rule. For models this is the best outcome: one bad input, one text, so a repair learned on one path works on the other.
> Concern: Nothing tests this until the fused reader exists. The corpus needs decode-error tests that run both paths and compare the whole JsonError.
>
> Q5: A3
> Reasoning: A1's no-global-state clause closes Sys's reentrancy hazard. Models trained on today's repo will emit json_parse for a long time, so an error that names json.parse turns that stale prior into a one-step fix. That belongs in an implementation ticket, not the spec: a spec rule about a removed stopgap API is exactly the kind of stopgap text I argued should stay out of the spec (against A2).
> Concern: The removed-name error may stay in the compiler long after it is useful. The ticket should state when it goes.
>
> Q6: A-code
> Reasoning: I drop my no-code wording. A stable code is a lookup key: blink llms, `blink fix`, the LSP and a model's learned repairs can all attach to it, while the prose stays free. Sys, Min and PLT all accept this form, so it settles the split and loses nothing I asked for.
> Concern: The code gets spent on a shape that the spec could later change. If to_json is ever renamed, the entry must be retired, not reused.
>
> Q13: A-content-ordered
> Reasoning: Declaration order makes the message deterministic, and that matters for the Q3a equality rule, for snapshot tests, and for truncation (which N values get listed). It costs nothing and removes a nondeterminism a model could not predict.
> Concern: None material. Truncation must also take the first N in declaration order.
>
> Q15: A
> Reasoning: The "Reference implementation:" label keeps it honest, and the fact helps a reader choose between a Str-backed enum and a Map[Str, T]. Low stakes for me.
> Concern: The note goes stale after a backend change, and nothing checks it.

##### Minimalism

> Min Phase D re-vote (169kjt): Q3a A, Q5 A3, Q6 A-code, Q13 A-content-ordered, Q15 B.
>
> Q3a: A
> Reasoning: PLT has it right that message is a field of JsonError, so "equal Result values" is the only equivalence that does not stop halfway. A fixes no prose. It only requires one text per input, and Sys showed that one shared formatter meets that at no cost. B splits the rule into normative and non-normative halves for the same property, and C adds a new "expected/found kind" content rule that nobody needs.
> Concern: a later wording change must land in the shared formatter, and a second hand-written error site on the fused path would break equality without anyone noticing.
>
> Q5: A3
> Reasoning: This changes the wording I proposed in Phase D (A2). A diagnostic for a removed name is migration tooling, and a spec that records the history of every removed API grows forever. A3 gets DevOps the named-replacement error and Sys the no-global-state rule, and the spec states only the surface and the hazard.
> Concern: a ticket has no deadline, so the removal release may ship with a bare "unknown function json_parse".
>
> Q6: A-code
> Reasoning: DevOps's own argument for A was that `blink fix` and the LSP need a stable code they can depend on. A-nocode removes exactly that and keeps only the part that was never contested. The prose stays free in both options, so the code number is the one thing the catalog entry adds.
> Concern: the code number is permanent even if json.encode / json.decode are renamed later.
>
> Q13: A-content-ordered
> Reasoning: Declaration order costs nothing, and it makes the list deterministic. Q3a needs that for equal text on both paths, and truncation needs it too, so that the first N values are always the same ones. Without it, an implementation could list values in hash order, and snapshot tests would flake.
> Concern: long enums still give long messages if N is set high.
>
> Q15: B
> Reasoning: A cost note constrains nothing that a program can observe, and it goes stale the first time the backend changes. The "reference implementation" label admits this but does not fix it. The fact belongs in a guide or in a `blink llms` performance topic, where a backend change can update it.
> Concern: users who choose between a Str-backed enum and a Map[Str, T] for speed get no cost statement from the spec.

#### AI-First Review

Five checks, zero fails:

- **Learnability:** pass. One conversion family (`to_int`/`from_int`, `to_str`/`from_str`); the laws are exact.
- **Consistency:** pass. `from_str -> Option` matches `from_int`; `encode`/`decode` mirror `stringify`/`parse`.
- **Generability:** pass with mitigation. The Rails/pydantic habit (`to_json` returns text) is strong; `JsonTextForValue` (E0537) turns it into a one-step repair.
- **Debuggability:** pass. `path`, fixed location content, the valid-literal list, a stable code.
- **Token efficiency:** pass. `json.encode(u)` and `json.decode[User](body)` are short.

### Final Spec

Governing text: sections/03_types.md §3.4 *Str-Backed Enums* and *Recursive Types*, §3.5 *Nested patterns*, §3.6.1 *Sum Type Codegen* (`Display` row), §3.6.2 (spec-only note, `JsonValue` key order and first match, `JsonError`, *Numbers*, *Str-Backed Enums*, *Type Mapping*, *JSON Text Is Not a `JsonValue`*), §3.6.3 (spec-only note, no global state, *Typed Decoding and Encoding*); ERROR_CATALOG.md E0537.

```blink
import std.json

@derive(Serialize, Deserialize)
type Status {
    Open = "open"
    InProgress = "in_progress"
}

@derive(Serialize, Deserialize)
type Ticket { id: Int, status: Status }

fn handle(body: Str) -> Result[Str, JsonError] {
    let t = json.decode[Ticket](body)?     // was: Ticket.from_json(body)
    Ok(json.encode(t))                     // was: t.to_json()
}
```

- **Q1:** `to_json(self) -> JsonValue` and `from_json(JsonValue) -> Result[Self, JsonError]` stay. Today's Str behavior is `json.encode(x) -> Str` and `json.decode[T](s) -> Result[T, JsonError]`. The ~110 test call sites migrate; none are deleted.
- **Q2, Q2b:** `JsonError { message: Str, path: Str }`; `path: ""` means unknown. A parse error's `message` contains `line L, column C`; a decode error's contains `at <path>`.
- **Q3, Q3a, Q3b:** `encode`/`decode` are defined by result. Both paths return equal `Result` values, every `JsonError` field included. Only location content is fixed; the rest of the wording is free but equal on both paths. Only derived impls fuse; a hand-written `Deserialize` field goes through parse-subtree then `from_json`.
- **Q4:** Int iff no fraction, no exponent, fits `Int`; else Float. Out-of-range integers become a lossy Float, stated plainly, with a Str-field workaround for big IDs. A Float field accepts Int; nothing narrows a Float.
- **Q5:** `json_*` leaves the public surface in the release where `JsonValue` lands. No private store or cache holds global shared mutable state. The removed-name error is an implementation ticket.
- **Q6:** `error[JsonTextForValue]` (E0537): stable code, trigger, named replacements, machine-applicable fix. Prose is not normative.
- **Q7:** Spec-only notes on §3.6.2 and §3.6.3. Each part goes when the compiler builds that part; `blink llms` carries the same marker (implementation ticket).
- **Q8:** Duplicate keys: first match, in `get` and in derived `from_json`.
- **Q9:** The §3.4 example is `Tree`. The §3.5 nested-pattern example now uses the §3.6.2 shape.
- **Q10, Q16:** §3.4 *Str-Backed Enums*: declaration rules, `to_str`/`from_str`, byte-exact matching with no Unicode normalization, the three laws, and `Option` on purpose, citing `Enum.from_int`.
- **Q11:** No implicit `Display`; with `@derive(Display)` the output equals `to_str()`.
- **Q12:** Backing literals are not precedent for `@json("name")`.
- **Q13:** The unknown-literal error names the rejected value, the enum type, and every valid literal in declaration order; it may truncate after N with a count. The example is not normative.
- **Q14:** The declaration errors are in the spec. Only `InvalidStringBackedEnum` (E1201) has a code today, so the other three are stated as error conditions. No `blink fmt` rule.
- **Q15:** A "Reference implementation:" note on `to_str`/`from_str` cost, not normative.

#### Editor's choices (not panel votes)

The panel did not vote on these details. The editor filled them in while writing the spec text, choosing the reading that follows from the votes:

- **`path` format:** rooted at `$`, `.name` for a key, `[i]` for an index (`$.items[2].age`). Panelists wrote both `$.items[2].age` and `items[2].age`. A bare form has no spelling for an error at the root, which would then collide with `""` (unknown), so the rooted form wins. A key that is not an identifier is written `["key"]` in JSON string syntax.
- **Nested paths:** a derived `from_json` puts its own step into a nested error's `path`, and turns `""` into its own step. This follows from Q2 and Q3b and answers DevOps's Phase C concern that paths through hand-written impls come out empty.
- **Column unit:** columns count bytes from the start of the line, 1-based, the unit of `Str.len()`. Lines split at `\n`. Systems asked that the spec pick one unit.
- **Int field and Float input:** a derived `from_json` for an `Int` field rejects `JsonValue.Float`, even `3.0`. This follows from "never narrows" in Q4.
- **Diagnostic name and code:** `JsonTextForValue`, E0537. E0534–E0536 are taken by the Template surface.
- **§3.5 example:** it used the old `JsonValue` shape; it now matches §3.6.2, with qualified variant names.

#### Dissent

- **Minimalism** on Q2 (wanted `message` only), Q7 (no spec-only marker), and Q11 (defer Display).
- **DevOps** on Q14 (wanted the `blink fmt` rule in the spec too).
- **PLT and Minimalism** on Q15 (omit the cost note).
- Round-1 splits, all 6-0 after Phase D: Q3a 4-2, Q5 4-1-1, Q6 3-3, Q13 3-3.

#### Follow-ups

- Implementation project: typecheck derive signature table, `cg_derive` `to_json`/`from_json`, `lib/std/json.bl` surface and retiring the handle API, the E0537 diagnostic (blocks the step that retypes `to_json`/`from_json`), the three-step test migration, `blink llms` markers. Panel concerns to carry: one shared error formatter, with the corpus running each decode-error test down both paths and comparing the whole `JsonError`; hand-written impl detection per field at mono time, `Option[Custom]` and `List[Custom]` included; no global mutable state in any private store; each spec-only marker removed by the ticket that builds that part; the migration lands as one dated sequence.
- A removed-name error for `json_*` for one release, stating when it goes (Q5 A3).
- Friction: the `Decimal.from_str` / `Bytes.from_str` codomains (Q16); `blink fmt` layout for Str-backed enums (Q14 dissent).
