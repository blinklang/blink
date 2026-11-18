[< All Decisions](../DECISIONS.md)

# A Missing Key in a Derived `from_json` — Design Rationale

**Gap:** §3.6.2 says `null` decodes as `None` for `Option[T]`. It did not say what a derived `from_json` does when the object has no entry for a field, for any field type. It did not say what the reader does with an entry that names no field, and it did not link the field defaults of §2.14 to the reader. PATCH bodies and model output leave out keys often.

## Summary

| Q | Question | Result | Vote |
|---|---|---|---|
| Q1 | An `Option` field with no default and no key | `None`: the field decodes as `None` | 6-0 |
| Q2 | Which fields an absent key fills when there is no default | `AsNull`: the reader calls `F.from_json(JsonValue.Null)`. `Ok(v)` gives `v`. `Err` gives the *missing field* `JsonError` | 5-1 (DevOps dissent for `Written`) |

Shared by all six seats (not on the ballot):

- A field with a §2.14 default takes the default when its key is absent.
- A key that is present with `null` is not absent. The default does not apply, and the field type reads the `null`.
- A key that names no field is skipped, with no error.
- A missing key that no rule fills gives `Err(JsonError)` with `path` `$.field` and a message with `at $.field`.
- Encode does not change.

## Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated in independent-proposal → debate → vote rounds. There was no Phase D. Each panelist's text below is a verbatim excerpt of the panelist's own reply.

### Phase A — Independent proposals


- **Systems:**

> ## G1: absent keys in a derived `from_json`
>
> ### Proposal G1-A (my pick): the written field type decides; defaults fill; unknown keys are skipped
>
> Behavior, per field of a derived `from_json`, when the object has no entry with the field's name:
>
> 1. The field has a default (§2.14): the field takes the default.
> 2. Else, the field's declared type is `Option[T]` (read after alias expansion, before generic substitution, the same read as the `T??` E1401 check): the field is `None`.
> 3. Else: `Err(JsonError)` with `path` set to the field's path and a `message` that names the field and contains `at <path>`.
>
> An object entry whose key names no field is skipped. No error.
>
> A key that is present with `null` is not "absent": rules 1 and 2 do not apply. `null` into `Option[T]` is `None` (today's rule); `null` into `Float` is the error *NaN and Infinity* already gives, even when the field has a default.
>
> ```blink
> import std.json
>
> @derive(Serialize, Deserialize)
> type UserPatch {
>     name: Str?
>     age: Int?
>     role: Str = "member"
>     id: Int
> }
>
> fn main() {
>     let a = json.decode[UserPatch]("\{\"id\": 1}")
>     // Ok(UserPatch { name: None, age: None, role: "member", id: 1 })
>
>     let b = json.decode[UserPatch]("\{\"id\": 1, \"name\": null, \"extra\": true}")
>     // Ok(UserPatch { name: None, age: None, role: "member", id: 1 }); "extra" is skipped
>
>     let c = json.decode[UserPatch]("\{\"name\": \"ann\"}")
>     // Err(JsonError { path: "$.id", message: "missing field `id` at $.id" })
>     // the wording is not fixed; "at $.id" is
>
>     let d = json.decode[UserPatch]("\{\"id\": 1, \"role\": null}")
>     // Err: `role` is Str, null is not a Str; the default does not apply to a present key
> }
> ```
>
> Generic field: in `type Box[T] { v: T }`, `Box[Int?]` with no `"v"` key is `Err(missing field)`. The field is written `T`, not `Option`.
>
> Systems tradeoffs:
>
> - Cost. The derived decoder holds one slot per field, initialized before the scan: the const default, or `None`, or "unset". One pass over the entries fills the slots (first entry wins, as today). After the pass, one check per required field. No heap work, no second pass. A field default is a const expression, so rule 1 is a store of a constant.
> - Unknown keys skipped: zero extra cost. Refusing them needs a "matched" test per entry and an error path; it also breaks every reader that is older than its writer. Go and serde both skip by default.
> - Why the written type, not the instance: the derive emits one generic `impl[T: Deserialize] Deserialize for Box[T]`. §3.6 *Polymorphic Trait Implementations* says that body may vary on `T` only through a bound. "Is `T` an Option?" is not a bound. So a rule that reads the instance needs specialization or a new trait hook (G1-B). Reading the written type keeps one body per derive and matches the E1401 check.
> - `T??` stays E1401, so "absent" vs "null" never meets a nested Option in a derive. `Patch[T]` remains the way to tell them apart.
>
> Cross-language: serde: `Option` fields default to `None` when absent, `#[serde(default)]` fills, unknown keys skipped. Go `encoding/json`: absent leaves the zero value, unknown keys skipped. Pydantic v2: `Optional[X]` with no default is REQUIRED; Blink here is closer to serde.
>
> ### Proposal G1-B (acceptable): a static hook on `Deserialize` for absence
>
> Same rules 1 and 3 and the same unknown-key rule, but rule 2 goes through the trait: `Deserialize` gets a final-overridable static method, for example `fn from_absent() -> Option[Self]`, default `None`; `Option[T]` gives `Some(None)`. A derived decoder calls `T.from_absent()` for a missing key. Then `Box[Int?]` with no `"v"` decodes as `v: None`.
>
> Cost: after mono, `T.from_absent()` is a direct call to a constant; it inlines to the same store as G1-A. Price: a new method on a core trait, which every hand-written impl can see. This is serde's route (its `missing_field` hook). I rank it second: more surface for one generic edge case.
>
> ### Not proposed
>
> "Absent is an error for every field, Option too" (pydantic-style). It makes `None` encode as `null` but forces every PATCH-style client to send explicit nulls. Cheap, but it fights the common input the ticket names.
>
> ---

- **Web/Scripting:**

> ## G1: a missing key in derived from_json
>
> ### Proposal G1-A (my pick): absent key = field default, else None for Option, else error. Extra keys are skipped.
>
> A derived `from_json` reads an object. For each field:
>
> 1. The key is there (first entry wins, as now): decode the value. `null` into `T?` is `None`, as now.
> 2. The key is absent and the field has a default (§2.14): the field takes its default. Same rule as a struct literal that leaves the field out.
> 3. The key is absent, no default, and the field type is `Option[T]`: the field is `None`.
> 4. The key is absent in every other case: `Err(JsonError)` with `path` set to the field's path and a `message` that says the field is missing and names its type.
>
> An object entry whose key names no field is skipped. No error.
>
> ```blink
> import std.json
>
> @derive(Serialize, Deserialize)
> type UserUpdate {
>     name: Str?
>     nickname: Str? = Some("anon")
>     tags: List[Str] = []
>     id: Int
> }
>
> fn main() {
>     let a = json.decode[UserUpdate]("\{\"id\": 1}")
>     // Ok(UserUpdate { name: None, nickname: Some("anon"), tags: [], id: 1 })
>
>     let b = json.decode[UserUpdate]("\{\"id\": 1, \"name\": null, \"nickname\": null}")
>     // Ok(UserUpdate { name: None, nickname: None, tags: [], id: 1 })
>     // null is a value, so the default does not apply
>
>     let c = json.decode[UserUpdate]("\{\"name\": \"Al\"}")
>     // Err(JsonError { path: "$.id", message: "missing field `id` (Int) at $.id" })
>
>     let d = json.decode[UserUpdate]("\{\"id\": 2, \"role\": \"admin\"}")
>     // Ok(...): "role" names no field, so the reader skips it
> }
> ```
>
> Nested: a missing key inside `$.owner` gives `path: "$.owner.id"` by the rule that already exists.
>
> Tradeoffs (DX):
> - This is what a JS, Python or Rust dev expects. In TS, `name?: string` reads an absent key as `undefined`. serde reads an absent `Option` field as `None` and skips unknown keys. A PATCH body and an AI tool call leave keys out all the time; an error there would be the first Stack Overflow question about Blink JSON.
> - Pydantic v2 made `Optional[X]` with no default a REQUIRED field. That is a top source of confusion in Pydantic ("why is my Optional field required?"). Do not copy it.
> - Reusing §2.14 field defaults means one idea to learn: "left out = default", in a struct literal and in JSON. No new annotation.
> - Skipping extra keys: an API adds a field, and old clients keep working. A strict mode (reject unknown keys) is a real need for some, but YAGNI for v1. A hand-written `from_json` can check `j.keys()` today.
> - Cost: `T?` no longer tells "absent" from `null`. The spec already sends that case to the `Patch[T]` enum, and serialization already writes `None` as `null` (decided). Round trip stays exact: encode writes every key, so decode never sees an absent key for its own output.
>
> Side note, not for this vote: the `Patch[T]` help gives the tagged-object JSON `{"variant": "Clear", "fields": {}}`. No web client sends a PATCH body like that. A real PATCH API cannot use it. I would like a friction ticket on "absent vs null" with a shape a web client can send.
>
> ### Proposal G1-B (reject): absent key is always an error unless the field has a default.
>
> Same as A without step 3. `name: Str?` with no default and no key is `Err`. To make it optional, write `name: Str? = None`.
>
> I list it only to say no. It is explicit, but every user hits the error once, then writes `= None` on every `Option` field forever. That is boilerplate to fix a case nobody asked for.

- **PLT:**

> ## G1: a missing key in a derived `from_json`
>
> First, a fact the options must respect. `Option[T].from_json` takes a `JsonValue`. An absent key has no `JsonValue`. So no rule on the `Option` instance can cover absence. The rule belongs to the derived struct reader, which sees the object and knows the key is absent.
>
> ### G1-A (my pick): default first, then "absent reads as `null`"
>
> For each field, the derived reader finds the first entry with the field's name (as now). When there is none:
>
> 1. The field has a §2.14 default: the field takes the default.
> 2. Else the reader calls `F.from_json(JsonValue.Null)` for the field type `F`. On `Ok(v)` the field is `v`. On `Err(_)` the reader drops that error and returns its own: `path` is the field's step (`$.age`), and `message` contains `missing field` and `at $.age`. A nested reader adds its step as now (`$.owner.age`).
>
> An object entry whose key names no field is ignored. Encode does not change: `None` still writes `null` (decided).
>
> ```blink
> import std.json
>
> @derive(Serialize, Deserialize)
> type User {
>     name: Str
>     age: Int?
>     role: Str = "member"
>     score: Int? = Some(0)
> }
>
> fn main() {
>     // {"name": "ana", "extra": 1}
>     match json.decode[User]("\{\"name\": \"ana\", \"extra\": 1}") {
>         Ok(u) => {
>             let a = match u.age { Some(n) => n, None => -1 }
>             let s = match u.score { Some(n) => n, None => -1 }
>             io.println("{u.role} {a} {s}")    // prints: member -1 0
>         }
>         Err(e) => io.println(e.message)
>     }
>     // {"name": "ana", "score": null}
>     match json.decode[User]("\{\"name\": \"ana\", \"score\": null}") {
>         Ok(u) => {
>             let s = match u.score { Some(n) => n, None => -1 }
>             io.println("{s}")                  // prints: -1   (null is None; absent was Some(0))
>         }
>         Err(e) => io.println(e.message)
>     }
>     // {"age": 3}
>     match json.decode[User]("\{\"age\": 3}") {
>         Ok(_) => io.println("ok")
>         Err(e) => io.println(e.path)           // prints: $.name   (message: "missing field `name` at $.name")
>     }
> }
> ```
>
> Generic field, `type Box[T] { v: T }`, input `{}`:
> - `Box[Int?]`: `Ok(Box { v: None })`.
> - `Box[Int]`: `Err`, path `$.v`, "missing field".
>
> PLT tradeoffs:
> - **Parametric.** Step 2 goes through `F.from_json`, a trait call. The derived `impl[T: Deserialize] Deserialize for Box[T]` never asks what `T` is, so it obeys the rule at 03:7849 (no dispatch on a type parameter's identity). A rule that keys on "the field type is `Option`" must pick a time to read the type. Before substitution, `Box[Int?]` and `age: Int?` differ for no reason the user can see. After substitution, the derive must inspect `T`, which the language forbids.
> - **No new trait method, no type test.** It reuses the decided `null -> None` rule (J1). Absent and `null` mean one thing unless the author asks to tell them apart.
> - **Absent vs `null` without `T??`.** A default gives the split: `score: Int? = Some(0)` reads absent as `Some(0)` and `null` as `None`. Defaults are const and fit every instance (§2.14, §2.13), so step 1 is sound for a generic type too.
> - **`Patch[T]` (03:~8967).** `Patch[T]` is a tagged object. With no default, an absent `Patch` field goes to step 2, `Patch.from_json(JsonValue.Null)` fails, and the result is "missing field". So the claim that `Patch[T]` tells "absent" from "null" holds only with `name: Patch[Str] = Patch.Keep`. I ask that the E1401 help write the field with that default. Without it, the claim at ~8967 is false under any rule.
> - **Asymmetry with struct literals.** A struct literal that leaves out `age: Int?` (no default) is E0315. Decode accepts the same omission. I accept this. A literal is source the author writes, so a compile error is cheap to fix. JSON is foreign input, where an absent key and `null` are routine (JS `undefined` drops the key).
> - **Unknown keys ignored.** Decode is a projection onto the declared fields. Ignoring extra keys makes it total over wider objects, like width subtyping on records. A strict mode is a later, separate feature.
> - **Error text.** A missing `Point` field would otherwise report "expected object, got null at $.p". That is false: the input had no `null`. Step 2 replaces it.
>
> Cross-language: Haskell aeson 2.2 added `omittedField :: Maybe a` to `FromJSON`; the `Maybe` instance gives `Just Nothing`, so a generic field gets the right answer through the class, not through a type test. Rust serde does the same by trait dispatch: a missing field runs the field type's `Deserialize` on a "missing" input, and `Option` answers `None`. Both are parametric; G1-A is that design with `null` as the "missing" input.
>
> ### G1-B (sound alternative): only defaults fill a missing key
>
> An absent key takes the field's default. With no default it is `Err` "missing field `x` at $.x", for `Option` fields too. To make `age` optional, the author writes `age: Int? = None`. Unknown keys ignored, as in G1-A.
>
> - Pro: decode matches construction exactly. "Decode builds the literal from the present keys" is one rule, and an omission is legal in JSON exactly when it is legal in a literal.
> - Con: every panel seat predicted users and models will read `age: Int?` as optional. G1-B fails them at run time, in production, on the input that triggered the ticket. I rank it second.

- **DevOps:**

> ## G1: a missing key in a derived `from_json`
>
> ### Proposal G1-A (my pick): an absent key does what a struct literal does when it leaves the field out; an unknown key is skipped
>
> A derived `from_json` reads each field from the first entry with that name (current text). When **no** entry has the field's name:
>
> 1. The field has a default (§2.14): the field takes the default.
> 2. Else the field's declared type is `Option[T]`: the field is `None`.
> 3. Else: `Err(JsonError)`. `path` is the path of the missing field (`$.age`, `$.owner.age`). `message` says the field is missing, names its type, and has `at <path>`. One error: the first missing field in declaration order.
>
> An object entry whose key names no field is skipped. Encode does not change: every field is written, `None` as `null` (decided).
>
> ```blink
> import std.json
>
> @derive(Serialize, Deserialize, Debug)
> type User {
>     name: Str
>     age: Int
>     nick: Str?
>     role: Str = "member"
> }
>
> fn main() {
>     println("{json.decode[User]("{\"name\": \"ann\", \"age\": 3}")}")
>     println("{json.decode[User]("{\"name\": \"ann\", \"age\": 3, \"nick\": null, \"extra\": 1}")}")
>     match json.decode[User]("{\"name\": \"ann\"}") {
>         Ok(u) => println("{u}")
>         Err(e) => println("{e.path}: {e.message}")
>     }
> }
> ```
>
> Prints (the error wording is not fixed, only its content):
>
> ```
> Ok(User { name: "ann", age: 3, nick: None, role: "member" })
> Ok(User { name: "ann", age: 3, nick: None, role: "member" })
> $.age: missing field `age` (Int) at $.age
> ```
>
> Rule 1 comes before rule 2. `nick: Str? = Some("anon")` reads an absent key as `Some("anon")` and `null` as `None`. That is the only way a derive tells "absent" from "null", and it costs no new syntax.
>
> Tradeoffs from my seat:
> - **One rule to teach and to show on hover.** "Absent key = the field left out of a literal" is the rule users already know from §2.14. The language server can show a three-line table on hover over `@derive(Deserialize)`: per field, "absent -> default / None / error". A rule that ignores defaults (G1-B) makes that hover say "this field has a default, but not for JSON", which users will file as a bug.
> - **Defaults are const (§2.14), so the decode stays pure and deterministic.** No call runs during decode to fill a field.
> - **The error points at the missing field.** `$.age` is the place a reader goes to fix. pydantic does the same (`loc: ("age",)`, "Field required"). serde only says "missing field `age`" at a line and column, which is less help for a nested value.
> - **Skipping unknown keys** keeps API version skew and AI output with extra keys working. The cost: a typo in a key (`"nmae"`) is silent, and then shows up as "missing field `name`" if `name` has no default. That second error is the one that tells the user, so the typo is not lost when it matters. A strict mode needs an annotation or a config knob; that is a v2 question, not this ticket.
> - **E1401's `help:` gets better.** With rule 1, `name: Patch[Str] = Patch.Keep` decodes an absent key as `Keep`. The help can show that default. (The help still overstates what `Patch[T]` does for a real PATCH body: `null` gives `Err`, and `Replace` needs the tagged-object form, which no web client sends. I flag this for the writer, not for this vote.)
>
> Cross-language: serde: absent `Option` -> `None`, `#[serde(default)]` for the rest, unknown keys skipped. Go `encoding/json`: absent -> zero value, unknown skipped. pydantic: absent `Optional` without a default is an error in v2 (`Field required`), defaults apply, unknown keys skipped. Kotlin serialization: defaults apply, unknown keys are an error unless `ignoreUnknownKeys`.
>
> ### Proposal G1-B (not my pick): `Option` only
>
> Absent key -> `None` for an `Option` field. Every other absent key is `Err`, defaults or not. Unknown keys skipped. Smaller, but the hover/teaching cost above, and `role: Str = "member"` fails on `{"name": "ann", "age": 3}`.
>
> ### Proposal G1-C (reject): every absent key is `Err`
>
> Breaks PATCH bodies and AI output for no gain; `null` and "absent" then differ for `Option` with no way to say which you want.
>
> ---

- **AI/ML:**

> ## G1: absent key in a derived `from_json`
>
> Facts I checked: §3.6.2 says how `null` decodes into `Option[T]` and that a derived `from_json` "reads each field from the first object entry with that field's name". It says nothing about an absent key or an extra key. §2.14 field defaults are const expressions, so a decoder can fill them with no effect and no call.
>
> ### G1-P1 (my pick): absent key = field default, else `None` for a declared `Option`, else an error. Extra keys are ignored.
>
> For each field, a derived `from_json` does this when the object has no entry with the field's name:
>
> 1. The field has a default (§2.14): the field takes the default.
> 2. Else the field's **declared** type is `Option[T]` (read after alias expansion, before generic substitution, the same read as the E1401 `T??` check): the field is `None`.
> 3. Else: `Err(JsonError)` with `path` = the path of the missing key (`$.city`) and a `message` that says the key is missing and contains `at $.city`.
>
> An object entry whose key names no field is skipped. Duplicate keys keep the current rule (first entry wins).
>
> ```blink
> import std.json
>
> @derive(Serialize, Deserialize)
> type User {
>     name: Str
>     email: Str?
>     role: Str = "member"
>     tags: List[Str] = []
> }
>
> @derive(Deserialize)
> type Box[T] {
>     v: T
> }
>
> fn main() {
>     let a = json.decode[User]("{\"name\": \"ann\"}")
>     // Ok(User { name: "ann", email: None, role: "member", tags: [] })
>
>     let b = json.decode[User]("{\"name\": \"bo\", \"email\": null, \"age\": 40}")
>     // Ok(User { name: "bo", email: None, role: "member", tags: [] })  -- "age" is skipped
>
>     let c = json.decode[User]("{\"email\": \"x@y.z\"}")
>     // Err: missing key "name" at $.name
>
>     let d = json.decode[Box[Int?]]("{}")
>     // Err: missing key "v" at $.v  -- `v` is declared `T`, not `Option`
> }
> ```
>
> Why, from my seat:
>
> - **Priors.** The JSON code models have seen most is serde (Rust), Go `encoding/json`, and pydantic. Serde reads an absent `Option` field as `None`. Go reads every absent field as the zero value. Rules 1 and 2 match what a model already expects. A model writes `email: Str?` for "may be absent" and almost never adds `= None`. Under a stricter rule that habit fails at run time, on real input, where no compiler can catch it.
> - **The input is the AI's own output too.** LLM-generated JSON leaves out keys it thinks are empty and adds keys nobody asked for. Rule 2 and the skip rule make that input decode. A strict rule turns each of those into a production error.
> - **Few choices.** The author makes one choice per field, and it is a choice they already make for struct literals: write a default or not. Rule 2 adds no syntax.
> - **Round trip holds.** `None` encodes as `null` (decided), and `null` decodes as `None`. The absent case only adds input that decodes; it changes no output.
> - **Generic fields.** Rule 2 reads the declared type for the same reason E1401 does: a derived impl for `Box[T]` cannot look inside `T`. `Box[Int?]` with no `v` is an error. This is the one sharp edge. The error names the key, so a model can repair the input or the type in one step.
> - **Typos.** A sender who writes `emial` gets `email: None` and no error. That is the cost of skipping extra keys. I accept it: v1 has no field attributes, so there is no way to say "strict" per type, and a strict default breaks the common case to catch the rare one. A later panel can add a strict mode.
>
> Cross-language: serde (absent `Option` = `None`, extra keys skipped unless `deny_unknown_fields`); Go (absent = zero value, extra skipped); pydantic v2 (an `Optional` with no default is required; extra keys ignored by default); kotlinx.serialization (an absent nullable with no default is an error).
>
> ### G1-P2: absent key = struct literal that leaves the field out
>
> Same as P1 without rule 2. An absent key takes the field default; with no default it is an error, `Option` or not. To accept an absent `email`, the author writes `email: Str? = None`.
>
> ```blink
> @derive(Deserialize)
> type User {
>     name: Str
>     email: Str?           // absent -> Err: missing key "email" at $.email
>     phone: Str? = None    // absent -> None
> }
> ```
>
> Tradeoffs: one rule, shared with §2.14, so it is easy to state. But the common model output (`email: Str?`) fails at run time on the most common input (an omitted key). If the panel picks P2, the error `message` should say: the field is `Option` and has no default; add `= None` to accept an absent key. That gives a model a one-step repair, but only after a failure in the field.
>
> ### Note on `Patch[T]`
>
> Under P1 or P2, `name: Patch[Str] = Patch.Keep` decodes an absent key as `Keep`. That makes the E1401 help work for a PATCH body's "absent" case. I do not propose more here.
>
> ---

- **Minimalism:**

> ## G1: missing key in derived `from_json`
>
> The spec must say something. Today the reader for a missing key is undefined for every field type, and a P0 waits on it. But we do not need a JSON-specific rule. §2.14 already says what happens when a field is left out: a struct literal that omits a field takes its default, and a field with no default is `MissingField`. Use that.
>
> ### Proposal G1-A (my pick): an absent key is a field left out of a struct literal
>
> - Key absent, field has a default (§2.14): the field takes the default.
> - Key absent, field has no default: `Err(JsonError)`. The `path` names the missing field, the `message` says the key is missing and contains `at <path>`.
> - This holds for every field type. `Option[T]` gets no special case. An `Option` field that may be absent writes `= None`, as it must in a struct literal.
> - Key present with `null`: unchanged (`None` for an Option field, `Err` for a `Float` field, and so on).
> - A key that names no field: ignored. Duplicate keys: first wins (already in the spec).
>
> ```blink
> import std.json
>
> @derive(Serialize, Deserialize)
> type UserUpdate {
>     id: Int
>     name: Str? = None
>     nickname: Str?
>     active: Bool = true
> }
>
> fn main() {
>     let a = json.decode[UserUpdate]("\{\"id\": 1, \"nickname\": null, \"x\": 5}")
>     // Ok(UserUpdate { id: 1, name: None, nickname: None, active: true })
>     // "x" is ignored; name and active take their defaults
>
>     let b = json.decode[UserUpdate]("\{\"id\": 1}")
>     // Err: message contains "missing field `nickname`" and "at $.nickname"
>     // nickname has no default, so the key must be there (null is fine)
>
>     let c = UserUpdate { id: 1 }
>     // error[MissingField]: `UserUpdate` literal is missing field `nickname` (Option[Str])
>     // the same rule as b, at compile time
> }
> ```
>
> Tradeoffs:
> - One rule for literals and for decode. A reader who knows §2.14 knows the decoder. No "Option means optional" exception to learn, and no second meaning of `?`.
> - The author chooses, per field, "may be absent" (`= None`) or "must be sent, may be null" (no default). G1-B cannot express the second case at all.
> - Defaults on non-Option fields (`active: Bool = true`) come for free. Field defaults are const (§2.14), so the decoder can always fill them.
> - Cost: an author who wants every Option field optional writes `= None` on each one. That is a few characters, and it is visible in the type.
> - The derived reader for a missing key needs no new code path: it builds the same value the literal would.
> - `Patch[T]` (Keep / Clear / Replace) stays the tool for "absent vs null". G1-A gives it a clean meaning: `patch: Patch[Str] = Patch.Keep`, and absent decodes as `Keep`. That is the PATCH case web and aiml raised, solved with features we have.
>
> Cross-language: Pydantic v2 does exactly this (`x: int | None` is required, `x: int | None = None` is optional). Go fills the zero value for every missing key, which hides missing data. serde treats a missing `Option` as `None` by a special case, and needs `#[serde(default)]` for the rest; G1-A gets both from one rule.
>
> ### Proposal G1-B (acceptable): Option implies "may be absent"
>
> As G1-A, plus: an absent key for an `Option` field with no default decodes as `None`.
>
> Tradeoffs: what most web code expects (serde, TypeScript `?:`). But it adds a JSON-only exception to §2.14 (a literal still needs the field, the decoder does not), and it removes the "required but nullable" case. I vote against it, but it is better than leaving the gap.
>
> ### Not proposed
> - A strict mode that refuses unknown keys, or a `@json(...)` field annotation: YAGNI in v1. A user who needs it writes `from_json` by hand.
> - Absent `Option` field with no default as a compile error: no, the type is fine; only the input is wrong.
>
> ---


### Phase B — Debate highlights

The Phase B digest split the group into G1-Q1 (`None` or `Strict`) and G1-Q2 (`Written`, `AsNull` or `Hook`). All six seats marked STABLE in round 1.


- **Systems:**

> ## G1-Q1: Option field with no default, key absent
>
> Position: **G1-None** (unchanged).
>
> Against G1-Strict (min): its one real gain is "required but nullable" (the key must be sent, `null` is fine). That gain is a contract on the sender's key set, which the type cannot see and the receiver almost never needs. Its cost lands at run time, in production, on the input the ticket names (PATCH bodies, model output that drops null keys). min's "one rule with struct literals" is true but the two cases differ: a literal is source the compiler checks before it runs; JSON is foreign input checked only when it arrives. A compile error is cheap to fix, a 400 on a live request is not. Code cost is equal; both are one constant store per slot.
>
> Reply to min: I grant that G1-None makes `age: Int?` and `age: Int? = None` decode the same way. Under G1-AsNull (below) the author still gets the split that matters for PATCH: `score: Int? = Some(0)` reads absent as `Some(0)` and `null` as `None`.
>
> ## G1-Q2: which fields count as "Option"
>
> Position: **G1-AsNull** (plt). I move from G1-Written. G1-Hook drops to third.
>
> plt's design beats my pick. It is parametric (one generic body for `Box[T]`, no test on `T`), needs no new trait method, and gets `Box[Int?]` right, which my G1-Written got wrong for no reason a user can see. Systems check of its cost:
> - After mono, `F.from_json(JsonValue.Null)` is a direct call. For `Option[T]` it returns `Ok(None)` at once: the same work as my constant store, plus one branch.
> - For a required field (`Str`, `Int`, a struct), the call builds a `JsonError` that the reader drops, then the reader builds its own. That is one wasted message string, only on a path that is about to return `Err` anyway. Acceptable. A writer note: the derive may skip the call when `F` is a known non-null-accepting builtin; the result must be the same.
> - A hand-written `from_json` that accepts `null` (for example a `JsonValue` field, which gives `JsonValue.Null`) also accepts an absent key. That is consistent, and the writer should say it.
>
> Against G1-Written (my old pick): it keys on the written type, so `age: Int?` and `v: T` with `T = Int?` act differently. That split is visible only in the type declaration, not at the use site.
> Against G1-Hook (my old G1-B): it reaches the same behavior as AsNull, at the cost of a new method on a core trait. AsNull reuses the decided `null -> None` rule (J1) instead.
>
> Writer note: I back plt on the E1401 help. `Patch[T]` tells absent from null only with `= Patch.Keep`, so the help must write that default.

- **Web/Scripting:**

> ## G1-Q1: Option field, no default, key absent
>
> **Position: G1-None.**
>
> Against G1-Strict (min): the struct-literal parallel does not hold where it counts. A literal that leaves out `nickname` fails at compile time, in front of the author, and the fix is five characters. A JSON body that leaves out `nickname` fails at run time, in production, on input the author does not control. That is the exact input the ticket names (PATCH bodies, AI-made JSON). min cites Pydantic v2 as a model. It is the opposite. "Why is my Optional field required?" is one of the most asked Pydantic v2 questions, and the docs needed a special page for it. Every JS/TS dev reads `name: Str?` as "may be absent", because `name?: string` means exactly that. Strict also makes `= None` boilerplate on nearly every Option field in every API type, so the "required but nullable" case that min keeps costs everyone a lot to serve a rare need. A hand-written `from_json` still covers that rare case.
>
> ## G1-Q2: which fields count as Option when the key is absent
>
> **Position: G1-AsNull (plt). I move from my Phase A wording, which was G1-Written in effect.**
>
> Rule for users, in one line: "a missing key is the field default; with no default it reads as `null`". A JS dev gets that in five seconds, and it matches what `JSON.stringify` does to `undefined` in many clients (drops the key) and what the server then sees.
>
> Against G1-Written: generic envelopes are the common web shape, not an edge case.
>
> ```blink
> @derive(Serialize, Deserialize)
> type ApiResponse[T] {
>     data: T
>     error: Str?
> }
>
> fn main() {
>     let r = json.decode[ApiResponse[User?]]("\{\"error\": \"not found\"}")
>     // AsNull:  Ok(ApiResponse { data: None, error: Some("not found") })
>     // Written: Err "missing field `data` at $.data", because `data` is written `T`
> }
> ```
>
> Under Written, `ApiResponse[User?]` and a struct with `data: User?` behave differently for no reason a user can see. That is a Stack Overflow question with a "the spec reads the type before substitution" answer, which no web dev wants to read.
>
> Against G1-Hook: a new method on a core trait that every hand-written `from_json` author sees in docs and completions, for the same behavior AsNull gives with no new surface.
>
> One cost of AsNull I accept: a `JsonValue` field with no default reads an absent key as `JsonValue.Null`. That is what a JS dev expects anyway.

- **PLT:**

> ## G1-Q1: Option field, no default, key absent
>
> Position: **G1-None**.
>
> Against G1-Strict (min). min makes two good points:
> - decode matches a struct literal;
> - "must be sent, may be null" can be stated (no default) only under Strict.
>
> Both points are true. But the second case buys only validation. Absent and `null` give the same value (`None`) under every option, so the program cannot act on the difference. The cost lands on the input class the ticket names (PATCH bodies, model output), and it lands at run time in production, not at check. The literal analogy also breaks down. A literal is code the author writes, so its omission is a compile error the author fixes at once. JSON is input from someone else, and the type `Str?` already says "this may have no value". I keep Strict as an acceptable second. It is sound.
>
> ## G1-Q2: which fields count as Option when the key is absent
>
> Position: **G1-AsNull**, then G1-Hook, then G1-Written.
>
> Against G1-Written (sys, aiml). sys argues that reading the instance needs specialization or a new hook. That is true for a rule that asks "is `T` an Option?". AsNull does not ask that. It calls `F.from_json(JsonValue.Null)` through the `T: Deserialize` bound the derive already has. One generic body, no type test, no new trait method. It obeys §3.6 *Polymorphic Trait Implementations* as written.
>
> Written has a cost that sys and aiml do not price. It makes instantiation visible:
>
> ```blink
> @derive(Deserialize)
> type Box[T] { v: T }
>
> @derive(Deserialize)
> type IntOptBox { v: Int? }
>
>     json.decode[IntOptBox]("{}")    // G1-Written: Ok(IntOptBox { v: None })
>     json.decode[Box[Int?]]("{}")    // G1-Written: Err "missing field `v` at $.v"
>                                     // G1-AsNull: both Ok(.. { v: None })
> ```
>
> `Box[Int?]` and `IntOptBox` have the same fields at the same types, and Written decodes them differently. A user who makes a struct generic changes its decode behavior without a visible cause. This is the same loss that the E1401 `T??` check accepts. But that check only refuses a derive at compile time. Written changes what runs, with no diagnostic.
>
> AsNull's own cost, stated so that no seat has to find it: a hand-written `from_json` that accepts `null` also accepts an absent key. A `JsonValue` field that is absent becomes `JsonValue.Null`. I count this as correct: under the decided J1 rule, `null` is already the value for "nothing here".
>
> G1-Hook gives the same behavior as AsNull in every case that I can construct. Its only extra power is that a hand-written type could answer "absent" and `null` differently. That power costs a new method on a core trait. AsNull gets the same answers with no new surface. Hook is my second.

- **DevOps:**

> ## G1-Q1: Option field, no default, key absent
>
> **Position: G1-None.**
>
> Against G1-Strict (min): it moves the error from a place tools can see to a place they cannot. A struct literal that leaves out `nickname` is E0315 at `blink check`, with a span and a fix. A JSON body that leaves out `nickname` is an `Err` at run time, in production, on the input class that raised this ticket (PATCH bodies, model output). No check, lint or hover can warn about it, because the input does not exist at build time. "The same rule as a literal" is true for the rule and false for the cost: one failure costs a keystroke, the other costs an incident. min's "required but nullable" case is real but rare, and a hand-written `from_json` covers it. Most of the panel predicts that users read `T?` as "may be absent"; Strict makes that reading fail only at run time.
>
> ## G1-Q2: which fields count as Option
>
> **Position: G1-Written. Second: G1-AsNull. Against: G1-Hook.**
>
> - For Written: the rule is readable from the declaration alone. The language server can show, on hover over a field or the `@derive`, "absent -> default / None / missing-field error" with no instance in hand. The same read as the E1401 `T??` check, so one front-end walk serves both, and the docs say "written type" once.
> - On plt's parametricity point: Written does not inspect `T`. It reads the declaration before substitution, so the derived generic body is one body and calls nothing type-specific. `Box[Int?]` with `v` absent is "missing field `v` at $.v", which a user can fix by writing `v: T?` or a default. The case is rare and the error names the field.
> - Against AsNull (mild): a field `data: JsonValue` with the key absent decodes as `JsonValue.Null`, and any hand-written `from_json` that accepts `null` turns absent into a value with no error. Absent and null become one thing for every type whose reader takes `null`, which the author of that reader did not choose. The hover cannot say what absent does without knowing every instance. If AsNull wins, the reader must still replace the inner error with "missing field" (plt says so); I hold that as required.
> - Against Hook: a new method on a core trait shows in completion, docs and every hand-written impl for one generic corner case.

- **AI/ML:**

> ## G1-Q1: Option field, no default, key absent
>
> **Position: G1-None.**
>
> Against G1-Strict (min): min is right that Strict is one rule shared with §2.14, and that it can say "required but nullable". But think about who writes the type and who writes the input. A model writes `email: Str?` and almost never adds `= None`, because serde, TypeScript `?:` and Go all taught it that `?` means "may be left out". Under Strict, that habit compiles, passes check and tests that use full fixtures, and then fails at run time on the first real body that leaves the key out. That is the worst place for an error: late, on foreign input, and in production. "Required but nullable" is a rare API contract. A hand-written `from_json` can enforce it. I would not make the common case fail at run time to give the rare case a derive.
>
> min cites pydantic v2. That is a fair example, but pydantic is the outlier among the big three priors (serde, Go, pydantic), and its own users file the "Optional is required?" question often. That counts against copying it, not for.
>
> ## G1-Q2: which fields read an absent key as None
>
> **Position: I move from G1-Written to G1-AsNull (plt).**
>
> Reasons:
> - **It is shorter to learn.** AsNull says: "An absent key reads as `null`, unless the field has a default. If that read fails, the error is 'missing field'." Written says: "The declared type, after alias expansion and before generic substitution, is `Option`." The first is one sentence a model can apply to any type. The second needs the reader to know three compiler phases.
> - **It gives the same answer for every field a model writes by hand.** A field written `T?` gives `None` under both, because `Option.from_json(JsonValue.Null)` is `Ok(None)`. They differ only for a generic field (`Box[Int?]`) and for a hand-written `from_json` that accepts `null`. In both cases AsNull gives the answer a user expects (`None`, or what the impl says `null` means). Written gives a "missing key" error that a user cannot explain from the field's type at the use site (`Box[Int?]`).
> - **Its error text is true.** When the read fails, the error says "missing field" and does not say "got null".
>
> Against G1-Hook: it gives the same result as AsNull for every built-in type, but it adds a method to a core trait that every hand-written impl sees. More surface for no extra behavior a user would want.

- **Minimalism:**

> ## G1-Q1: G1-None (moved from G1-Strict)
>
> I drop G1-Strict. The case it alone keeps, "the key must be sent, but may be null", is one that nobody in Phase A asked for. Keeping a rule for it is the YAGNI mistake I am supposed to catch. Also, encode writes `null` for `None` (the decided vote). So "absent" and "null" already mean the same thing for an Option on the wire, and a decoder that treats them alike is the smaller rule. A `= None` on every Option field is noise that only exists to make two cases differ.
>
> Against G1-Strict (my old pick): it makes every model-written and hand-written PATCH type grow `= None` on each field, to protect a case nobody needs.
>
> ## G1-Q2: G1-AsNull (plt)
>
> My pick is the smallest rule of the three: "an absent key with no default reads as `null`. If the field type refuses `null`, the error is 'missing field'." The derive does not need to know what an Option is. It has no syntax test on the written type, and no new trait method. It also gives one meaning for every type: `Box[Int?]` with `v` absent is `None`, because `Int?` accepts `null`, and `Box[Int]` is "missing field". A hand-written `from_json` that accepts `null` also accepts absent, which is consistent.
>
> - Against G1-Written: it adds a second front-end read of the written type to the decoder. The same value then decodes differently by how the field was spelled (`v: T` with `T = Int?` vs `v: Int?`). The E1401 check reads the written type because it has to reject a declaration. The decoder has no such need.
> - Against G1-Hook: it adds a new method to a core trait that every hand-written impl sees, for behavior AsNull gets with no new method. This is the serde route that minimalism exists to avoid.
>
> ```blink
> @derive(Deserialize)
> type Box[T] {
>     v: T
> }
>
> @derive(Deserialize)
> type Req {
>     id: Int
>     age: Int?
>     score: Int? = Some(0)
> }
>
> fn main() {
>     print(json.decode[Box[Int?]]("{}"))            // Ok(Box { v: None })
>     print(json.decode[Box[Int]]("{}"))             // Err: missing field `v` at $.v
>     print(json.decode[Req]("\{\"id\": 1}"))        // Ok(Req { id: 1, age: None, score: Some(0) })
>     print(json.decode[Req]("\{\"id\": 1, \"score\": null}"))   // Ok(Req { id: 1, age: None, score: None })
>     print(json.decode[Req]("{}"))                  // Err: missing field `id` at $.id
> }
> ```
>
> The `score` row also answers web and aiml's PATCH point with no `T??` and no `Patch[T]`. A default tells absent apart from null. I support plt's writer note: the E1401 help should show this (`= Some(..)` or `= Patch.Keep`), because the help as written overstates `Patch[T]`.


### Phase C — Silent ballot

| Question | Sys | Web | PLT | DevOps | AI/ML | Min | Result |
|----------|-----|-----|-----|--------|-------|-----|--------|
| Q1. Option field, no default, key absent | None | None | None | None | None | None | None, 6-0 |
| Q2. Which fields an absent key fills | AsNull | AsNull | AsNull | Written | AsNull | AsNull | AsNull, 5-1 |


- **Systems:**

> ## G1-Q1
> **Vote:** None
> **Reasoning:** Both options compile to the same per-field slot and one pass over the entries, so the choice is about the input, not the cost. JSON is foreign input checked only when it arrives. Strict moves the failure for a dropped key to run time, on the PATCH and model-output bodies the ticket names. The "required but nullable" contract that Strict keeps is about the sender's key set, which the type cannot see.
> **Concern:** An author who truly needs "the key must be sent" has no derive form for it and must write `from_json` by hand.
>
> ## G1-Q2
> **Vote:** AsNull
> **Reasoning:** After mono, `F.from_json(JsonValue.Null)` is a direct call. For `Option` it returns `None` at once, which is about the cost of a constant store. A derived generic body stays one body that never tests `T`, as §3.6 requires, and `Box[Int?]` gets the same answer as `age: Int?`. A required field pays for one dropped `JsonError`, and only on a path that already returns `Err`.
> **Concern:** A hand-written `from_json` that accepts `null` now silently accepts an absent key too, and the spec must say that in plain words.

- **Web/Scripting:**

> ## G1-Q1
> **Vote:** None
> **Reasoning:** A JS/TS dev reads `name: Str?` as "may be absent", because `name?: string` means that. PATCH bodies and AI-made JSON leave keys out all the time. Strict turns that into a run-time error in production, on input the author does not control. Pydantic v2's "Optional is still required" is a top FAQ, so it is a reason against Strict, not a model for it.
> **Concern:** Users lose the "key required, null allowed" case and must write `from_json` by hand for it, and the docs must say so plainly.
>
> ## G1-Q2
> **Vote:** AsNull
> **Reasoning:** The rule a user learns is one line: "a missing key takes the default, or else it reads as null." Generic envelopes like `ApiResponse[T] { data: T }` are the common web shape. Under Written, `ApiResponse[User?]` would give "missing field" where a plain `data: User?` gives None, and no user could guess why. Hook gives AsNull's behavior and adds a new method to a core trait.
> **Concern:** A hand-written `from_json` that maps `null` to a value now also fills an absent key, and an author may not expect that unless the `Deserialize` docs say it.

- **PLT:**

> ## G1-Q1
> **Vote:** None
> **Reasoning:** `Str?` already says "this field may have no value". Absent and `null` give the same `None` under either option, so Strict adds only a run-time failure on the inputs the ticket names (PATCH bodies, model output). JSON is foreign input, not source, so the struct-literal analogy does not carry over.
> **Concern:** No one can write "the key must be sent, null is fine" without a hand-written `from_json`, and someone may need that later.
>
> ## G1-Q2
> **Vote:** AsNull
> **Reasoning:** AsNull goes through the `T: Deserialize` bound that the derive already has. So one generic body serves every instance, with no type test and no new trait method. Written makes `Box[Int?]` and a struct with `v: Int?` decode `{}` differently, so making a struct generic changes what runs, with no diagnostic. Hook gives the same answers as AsNull, but it puts a new method on a core trait.
> **Concern:** A hand-written `from_json` that accepts `null` also accepts an absent key; the spec text must say so in plain words, or users will be surprised.

- **DevOps:**

> ## G1-Q1
> **Vote:** None
> **Reasoning:** A literal that leaves out a field fails at `blink check` with a span and a fix. A JSON body that leaves out a key fails at run time, in production, on the input class that raised this ticket (PATCH bodies, model output), and no check, lint or hover can warn first. Strict gives the same rule in both places but very different costs. The rare "required but nullable" case can use a hand-written `from_json`.
> **Concern:** A client that drops a key it should send gets a silent `None`, not an error, so a broken client takes longer to find.
>
> ## G1-Q2
> **Vote:** Written
> **Reasoning:** You can tell what an absent key does from the declaration alone, so hover and docs can show "absent -> default / None / missing field" per field, without an instance. It is the same front-end read as the E1401 `T??` check, and it does not look inside `T`. AsNull silently turns an absent `JsonValue` field, and any reader that accepts `null`, into a value. Hook adds a core-trait method for one corner case.
> **Concern:** `Box[Int?]` with `v` absent gives "missing field `v`", which surprises a user who reads the instance type and not the declaration, so the message must name the declared type (`T`).

- **AI/ML:**

> ## G1-Q1
> **Vote:** None
> **Reasoning:** Models write `email: Str?` and almost never add `= None`, because serde, TypeScript `?:` and Go teach that `?` means "may be left out". Under Strict that habit checks clean and then fails at run time, on foreign input, in production, which is the worst place for an error. "Required but nullable" is rare, and a hand-written `from_json` can enforce it.
> **Concern:** A typo in a key (`emial`) decodes to `None` with no error, and v1 has no strict mode to catch it.
>
> ## G1-Q2
> **Vote:** AsNull
> **Reasoning:** It is one sentence a model can apply to any type: "an absent key reads as `null` unless the field has a default; if that read fails, the error is 'missing field'". Written needs the reader to know alias expansion and generic substitution, and it gives `Box[Int?]` an error the user cannot explain from the field's type. AsNull and Written agree on every field written `T?`, and Hook adds a trait method for no extra behavior.
> **Concern:** A hand-written `from_json` that maps `null` to a real value also gets that value for an absent key, which its author may not expect.

- **Minimalism:**

> ## G1-Q1
> **Vote:** None
> **Reasoning:** Encode already writes `None` as `null`, so absent and null carry the same meaning for an Option on the wire. A decoder that treats them alike is the smaller rule. Strict exists to protect "the key must be sent, but may be null", and no seat asked for that case. It also makes authors write `= None` on every Option field, which is noise.
> **Concern:** A client that drops a required Option key by mistake gets None silently, not an error.
>
> ## G1-Q2
> **Vote:** AsNull
> **Reasoning:** One rule with no type test: an absent key reads as `null`, and if the field type refuses `null` the error is "missing field". The derive needs no idea of what an Option is. It reads no written type and adds no trait method. The same value decodes the same way however the field was spelled (`Box[Int?]` and `v: Int?` agree). Written adds a spelling-based split, and Hook adds a core-trait method for no extra behavior.
> **Concern:** A hand-written `from_json` that accepts `null` for its own reasons now also accepts absence, and that author may not expect it.


#### Concerns and notes the writer carried into the spec

- **Systems, Web, PLT, Minimalism, AI/ML** (Q2 concern): a hand-written `from_json` that accepts `null` also accepts an absent key. The spec says so in plain words, with an example.
- **DevOps** (Q2 dissent for `Written`, concern): the missing-field message names the type as the declaration writes it (`T` for `v: T`), not the type of the instance. The spec writes this into the message form.
- **PLT, DevOps, Web, AI/ML** (Phase B, writer note): the `Patch[T]` help of E1401 overstated what `Patch` does for a real PATCH body. The help now writes the field with `= Patch.Keep`, and the spec claims only what the rules give: an absent key gives `Keep`, and a present key (`null` too) goes to `Patch[T].from_json`.
- **Web** (Q1 concern, docs note): the case "the key must be present, `null` is allowed" has no derived form. The author writes `from_json` by hand. The spec has an example.
- **AI/ML** (Q1 concern): a typo in a key (`emial`) decodes to `None` with no error, and v1 has no strict mode. This is noted here and in the spec text. No spec rule changes.

## Final Spec

The rule is in `sections/03_types.md`, §3.6.2 *Missing and Extra Keys*, with a message line in *JsonError*, a line in *Option and Result in JSON*, and the changed `Patch[T]` help of E1401. `sections/02_syntax.md` §2.14 has a one-line pointer.

```blink
@derive(Serialize, Deserialize)
type UserUpdate {
    id: Int
    name: Str?
    nickname: Str? = Some("anon")
}

json.decode[UserUpdate]("{\"id\": 1}")                       // Ok(UserUpdate { id: 1, name: None, nickname: Some("anon") })
json.decode[UserUpdate]("{\"id\": 1, \"nickname\": null}")    // Ok(... nickname: None): `null` is present, the default does not apply
json.decode[UserUpdate]("{\"id\": 1, \"emial\": \"x\"}")    // Ok(... name: None ...): `emial` is skipped
json.decode[UserUpdate]("{}")                                  // Err: missing field `id` (Int) at $.id
```

Locked points, one line each:

- Present key: the reader calls `F.from_json(value)`, `null` included. The default never applies to a present key.
- Absent key with a default: the field takes the default. Each decode builds a new value.
- Absent key with no default: the reader calls `F.from_json(JsonValue.Null)`. `Ok(v)` gives `v`. `Err` gives the *missing field* error.
- An `Option` field with no default and no key is `None`.
- `Box[Int?]` with `v` absent is `None`, the same as a plain `v: Int?`.
- `Box[Int]` with `v` absent is `missing field `v` (T) at $.v`.
- An absent `JsonValue` field is `JsonValue.Null`.
- `score: Int? = Some(0)` with the key absent is `Some(0)`. With `null` it is `None`.
- A key that names no field is skipped with no error and no warning.
- The *missing field* error has `path` `$.field` and the message ``missing field `field` (Type) at $.field``. `Type` is the type as the declaration writes it, before generic substitution.
- A hand-written `from_json` that accepts `null` also accepts an absent key.
- "Key required, `null` allowed" needs a hand-written `from_json`.
- The E1401 help writes `name: Patch[Str] = Patch.Keep`.
- Encode does not change.

Not decided here: whether the same key rules apply to the named fields of an enum variant in the tagged-object form. The spec text names struct fields only.
