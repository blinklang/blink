[< All Decisions](../DECISIONS.md)

# Which Built-in Types Are Serialize and Deserialize — Design Rationale

Two checks gave two answers for one question. The bound check (`T: Serialize`, E0306) accepted almost every built-in
type. The derive field check (E1401) refused the same types. A `Char`, a `U8` or a `Range` passed the bound, then
`x.to_json()` failed at build with an internal error. The spec gave rows for only some built-in types, and it did not
say which JSON a `Char`, a sized integer, a `U64`, an `F32`, a `Bytes` or a `Range[T]` writes.

```blink
@derive(Serialize)
type Cached {
    h: U64        // E1401 today
}

fn store[T: Serialize](x: T) -> JsonValue {
    x.to_json()
}

fn main() {
    store('a')        // passes check today, then fails at build
}
```

The panel chose one closed list of impls. Every check reads it. A built-in type with no row has no impl.

## Summary

| Q | Question | Result | Vote |
|---|---|---|---|
| Q0 | One closed list; the rows for `Char`, `I8` `I16` `I32` `U8` `U16` `U32`, `Range[T]` | Yes. `Char` writes a one-char `Str`. The sized integers write `JsonValue.Int` and decode only an in-range `Int`. `Range[T]` has no impl. `Never` is unchanged. No rows for `Map`, `Set` or a tuple | 6-0 |
| Q1 | `U64` | No impl. E1401 at a derive field, E0306 at a bound. The help is specific to `U64` | 5-1 after Phase D (4-2 in Phase C). AI/ML dissent: `U64-str`, `dec-str-only` |
| Q2 | `F32` | `F32-short`: `to_json` gives the `Float` nearest the shortest text of the `F32`. `JsonValue` does not change | 6-0 |
| Q3 | `Bytes` | No impl. E1401 at a derive field. The help names a `Str` field and `.to_hex()` | 6-0 |
| Help | The help for each refused type | `U64`, `Bytes` and `Range[T]` each get a help that names the repair for that type | stated by all six seats, not balloted |

### Compiler behavior before the decision

The seats ran probes with the gen1 compiler.

- `fn f[T: Serialize]` accepts `'a'`, `U8`, `0..3`, `Bytes`, a tuple, `Map[Int, Int]`, `Set[Str]` and a closure today. It refuses only a user type that has no derive (E0306). `T: Deserialize` accepts `'a'` and `0..3` (PLT).
- `@derive(Serialize) type S { c: Char, b: U8 }` is E1401 on both fields (DevOps).
- `'a'.to_json()` and a `U8` `.to_json()` give an unresolved-method error today (Systems, AI/ML).
- `F32` is "reserved but not yet supported" in gen1 (Systems, PLT).

### Reading gaps

- The ballot named `I64` with the hedge "if it is a type". `sections/03_types.md` has no `I64` entry. The spec text leaves `I64` out and gives it no status.
- `hash()` and `Hash.hash` appeared in the Phase C votes as the main cost of `U64-none`. Three Phase C votes used the method `to_str` in the help. No scalar has `to_str` (`sections/03c_protocols.md`, the `to_` rule for scalars). Phase D corrected it. The spec text uses `"{h}"` and `h.to_int_checked()`.
- The spec has no `Str` to `U64` parse. `Str` has `parse_int` and `parse_float` only. A separate ticket tracks the parse. The spec text does not claim that one exists.

## Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated in independent-proposal →
debate → vote rounds. Phase D ran on `U64` only.

### Phase A — Independent proposals

Each seat's opening rule on the question "which built-in types are `Serialize` and `Deserialize`", excerpted with
attribution.

- **Systems:**
  > One table. The *Type Mapping* table is the closed list of built-in types that are `Serialize` / `Deserialize`. A type not in the table has no impl. The bound check (E0306), the derive field check (E1401), method lookup (`x.to_json()`) and codegen all read that one list. "check passes, build ICEs CodegenStageNotBuilt" must become impossible: a type with a row has a working impl; a type with no row is refused at check.

  > Rule for each row from the systems side: **`to_json` never loses data silently, and `from_json` never truncates, wraps or rounds an integer.**

- **Web/Scripting:**
  > One answer, used by both checks. A type is Serialize (Deserialize) exactly when it has a Type Mapping row or a derive. The `T: Serialize` bound check (E0306) and the derive field check (E1401) read that one list. A `Deserialize` derive that checks clean must build; the CodegenStageNotBuilt ICE goes away because each type is either built or refused at check.

- **PLT:**
  > There is one judgment, `τ : Serialize` (and `τ : Deserialize`), read from one closed instance table. E0306 (bound), E1401 (derive field), method resolution of `.to_json()` / `T.from_json`, and codegen all read that table and nothing else.

  > **A type not in the table has no instance.**

  > Each row must obey the round-trip law (§3.6.1 *Derive Laws*): `T.from_json(x.to_json()) == Ok(x)` with `==` the type's own `Eq`.

- **DevOps:**
  > My axis: **one predicate, one answer everywhere.** The bound check (E0306), the derive check (E1401), LSP hover / "implements" lists, `blink doc`, and codegen must all ask the same `implements(T, Serialize)` question. Today check is clean and build ICEs (CodegenStageNotBuilt). That breaks "check clean ⇒ build clean", and that invariant is what makes `blink check` and the LSP worth trusting.

  > A type is Serialize/Deserialize only when `JsonValue` holds every value of it exactly. Without that, a value can encode and then fail to decode, or a program can panic at run time on a large value.

- **AI/ML:**
  > One impl set. `T: Serialize` (E0306) and a `@derive(Serialize)` field check (E1401) both ask the same question: "does the prelude declare an impl of this trait for this type?" No second list. The table in §3.6.2 is that list, written out.

  > AI angle: today the model must learn two answers for one question and guess which check runs. One table that is the whole answer is the cheapest thing to learn.

- **Minimalism:**
  > Starting point: the *Type Mapping* table is the list. A type not in it is not Serialize. The bug is only that the bound check does not read the same list as the derive check. So the smallest fix adds no rows at all.

  > One list. `T: Serialize` with a built-in scalar, a `@derive(Serialize)` field, and the W[T] instance after substitution all give the same answer, from the same table. Refusal codes: E0306 at a bound, E1401 at a derive field. No new code.

After Phase A, four seats stood at `U64-none` (Systems, Web, DevOps, Minimalism) and two at `U64-str` (AI/ML, PLT). All six put
`Bytes-none` first.

### Phase B — Debate highlights

The Phase B digest listed the points all six seats stated, and the facts the probes found:

> - One closed list of Serialize/Deserialize impls; E0306 (bound), E1401 (derive field), method lookup and codegen all read it. A type with no row has no impl: refused at check, never a build ICE.
> - Char: `'é'` writes `"é"`; decode takes only a Str of exactly one scalar value; `"ab"`, `""`, `107` are JsonError.
> - I8 I16 I32 U8 U16 U32 (and I64 if it is a type): write JsonValue.Int; decode takes an in-range JsonValue.Int only; out of range is JsonError with the path (`300` into U8 at `$.r`); any Float is JsonError.
> - Range[T]: no impl (E0306 / E1401).
> - Map, Set, tuples: out of scope here; all six flag a follow-up spec ticket.

- **AI/ML, on `U64` (moves to `U64-none` in Phase B):**
  > New argument for it, from my axis: **only the refusal can change later without breaking anything.** If the spec refuses U64 now, a later vote can add `U64-str` and every program that checked before still checks.

- **DevOps, on `U64`:**
  > With U64-str, the JSON kind of a field depends on the declared type, not on the value: `I64` writes `5`, `U64` writes `"5"`. Someone who reads a payload, or a JSON-schema tool, cannot guess this.

- **PLT, on `U64` (Phase B):**
  > U64-str and U64-none are both sound. Each gives one row in the closed list, and each obeys the round-trip law (U64-none holds it vacuously). So soundness does not decide between them. What decides is the cost of "no" under the orphan rule:

- **Web, on `F32` (the fact that moved DevOps):** §3 *Float Text Form* says an `F32` that holds `0.1` renders as `0.1`. DevOps:
  > With F32-wide, `io.println("{p.gamma}")` prints `0.1` and `json.encode(p)` prints `0.10000000149011612` for the same field. Users report that kind of mismatch as a bug.

- **AI/ML, on the exact `F32` digits:**
  > Let `d` be the shortest decimal where `F32.nearest(Float.nearest(d)) == x`. Such a `d` always exists, because the exact widened value is one. Then `to_json` gives `JsonValue.Float(Float.nearest(d))`.

  > I wrote the condition "through Float". The plain shortest-F32 text, read as binary64, can land exactly on an F32 midpoint, and ties-to-even can then pick the neighbor. The "through Float" condition closes that case.

- **PLT, on `F32` (moves to `F32-short`):**
  > One fact for the writer: under F32-short, `x.to_json() != JsonValue.Float(x.to_float())` in general. That is fine, because `to_json` has no law that ties it to widening, but the spec should say it once.

- **DevOps, on `Bytes`:**
  > Bytes-array is not "free" either: it makes `Bytes` and `List[U8]` write the same JSON, so a reader of the JSON cannot tell which type wrote it. I am withdrawing my B option.

All six seats ended round 1 with `STABLE: ready to vote`.

### Phase C — Silent ballot

Each seat voted alone. Each quote below is the seat's own text from its vote file.

| Question | Sys | Web | PLT | DevOps | AI/ML | Min | Result |
|----------|-----|-----|-----|--------|-------|-----|--------|
| Q0. One closed list and its rows | Yes | Yes | Yes | Yes | Yes | Yes | Yes, 6-0 |
| Q1. `U64` | str, dec-str-or-int | none | str, dec-str-only | none | none | none | none, 4-2 |
| Q2. `F32` | short | short | short | short | short | short | short, 6-0 |
| Q3. `Bytes` | none | none | none | none | none | none | none, 6-0 |

##### Q0. One closed list and its rows — Yes, 6-0

- **Systems:**
  > **Reasoning:** One list read by the bound check, the derive check, method lookup and codegen removes the check-passes-then-build-ICEs split. Range-checked integer decode never wraps or truncates, which is the failure C-style narrowing gives. Each row costs a tag check plus one compare.
  >
  > **Concern:** If one consumer (for example codegen's derive table) keeps its own copy of the list, the split comes back. Implement the list as one compiler table, with a test that the bound check and the derive check agree for every built-in type.
- **Web:**
  > **Reasoning:** One list read by every check ends a split that would confuse every user: the bound says yes and the derive says no. A Char as a one-character string and a sized int as a range-checked number are the shapes that JS and Python devs expect without reading the docs.
  >
  > **Concern:** The range error must name the type, its range and the path (`expected U8 (0 to 255), got 300 at $.age`). Without all three, the error does not tell the user what to fix.
- **PLT:**
  > **Reasoning:** One closed impl list read by every consumer (E0306, E1401, method lookup, codegen) is what makes the bound sound. Today the bound accepts a closure, so a well-typed generic `x.to_json()` reaches codegen with no impl to call. Each agreed row obeys the round-trip law: Char is injective onto one-scalar strings, and the sized ints embed in `Int` with a range-checked partial inverse.
  >
  > **Concern:** The implementation could keep a second "is built-in" fast path in the bound check, so the two tables drift apart again. The fix should delete the bound's own answer, not patch it.
- **DevOps:**
  > Reasoning: One list read by E0306, E1401, method lookup and codegen restores "check clean ⇒ build clean". Without that, `blink check` and the LSP cannot be trusted. Each case is refused at check with a code, never a build ICE.
  >
  > Concern: The lax bound accepts closures, tuples, Map and Set today. Making it strict will surface new E0306 errors in code that "worked". The CHANGELOG line and the type-specific help must land with the change, or users see errors with no guide.
- **AI/ML:**
  > Reasoning: One closed list that every check reads is the cheapest thing for a model to learn. The rows for Char and the sized ints follow from serde, Kotlin and the decided Int rule with one range check, so a model predicts them without reading the spec.
  >
  > Concern: The list must be written as one table that every surface reads (E0306, E1401, method lookup, codegen, `blink doc`). Otherwise it drifts back into two answers, which is the bug this ticket fixes.
- **Minimalism:**
  > **Reasoning:** One closed list read by every check is the smallest fix for the actual bug, two checks that give different answers. The rows it adds (Char, the sized ints) bring in no new rule. Each one is the Int rule plus a range check, or a one-char Str.
  >
  > **Concern:** The "and I64 if it is a type" clause leaves an open fact in the spec. The writer must settle whether I64 is a type, not copy the hedge.

##### Q1. `U64` — `U64-none` 4 (Web, DevOps, AI/ML, Min), `U64-str` 2 (PLT `dec-str-only`, Systems `dec-str-or-int`)

- **Web (U64-none):**
  > **Reasoning:** A field that writes `"5"` while every other integer writes `5` looks like a server bug to any web client. The spec already sends large IDs to a Str field, so the help line repeats a rule the user knows. The choice can also be undone: a U64 row added later breaks nothing.
  >
  > **Concern:** `hash()` returns U64, so many users will hit E1401 on a stored hash. The help must give the exact one-line fix (`h: Str` with `x.to_str()`, or `Int`), or the error feels like a dead end.
- **DevOps (U64-none):**
  > Reasoning: None is the only choice we can still change without a break (adding a form later is pure addition). It keeps the JSON kind tied to the value, not to the declared type. The E1401/E0306 help ("use `Int`, or a `Str` field: `h.to_str()`") makes the user choose in plain sight.
  >
  > Concern: Users who serialize `Hash.hash` results hit the error often. If the help line is generic rather than U64-specific, it reads as an arbitrary gap.
- **AI/ML (U64-none):**
  > Reasoning: Only the refusal can change later without breaking anything. A later vote can add U64-str and break no program, but a string format shipped now can change only by quietly changing the JSON on the wire. The rule a model learns stays "a JSON number holds the Int range" and needs no exception row.
  >
  > Concern: `hash()` returns U64 and the orphan rule blocks a user impl, so models will hit this error often. The help must name the exact repair (`Int.try_from(h)` or a Str field with `h.to_str()`), or a model loops on it.
- **Minimalism (U64-none):**
  > **Reasoning:** U64 as a string is a format policy, and it splits two 64-bit integers into different JSON kinds (Int is a number, U64 is a string). That puts it in the same class as Bytes, which all seats leave out. We can add a row later. We can never remove one, and the refusal costs one E1401 with a help.
  >
  > **Concern:** If U64-str wins with dec-str-or-int, the decode has two input forms and a list of exclusions that will grow. If it wins, I would take dec-str-only.
- **PLT (U64-str, dec-str-only):**
  > **Reasoning:** Both options are sound. U64-str is the only total, injective encoding that is fixed by the type, and it needs no wrapper. A user cannot write the impl under the orphan rule. With dec-str-only, `from_json` accepts exactly the image of `to_json`, so the two are mutual inverses on canonical JSON with no second accepted form to specify.
  >
  > **Concern:** If U64-none wins, users will write ad-hoc wrappers with different shapes (number, string, object) for the same type, and no one shape will be canonical.
- **Systems (U64-str, dec-str-or-int):**
  > **Reasoning:** A user can't write `impl Serialize for U64`, so U64-none pushes the same string into user code and drops the decode range check. Always a string means the JSON shape depends on the type, never on the value, and it is lossless, as in protobuf JSON. Accepting an `Int` >= 0 on decode costs one tag check and takes what a hand-written producer sends.
  >
  > **Concern:** U64 becomes the one integer type whose JSON is not a number, so a consumer that expects a number for a `hash()` field fails at first contact. The row needs a sentence and an example in the spec.

##### Q2. `F32` — `F32-short`, 6-0

- **Systems:**
  > **Reasoning:** §3.6 *Float Text Form* already requires one text form everywhere, JSON included, and says an F32 holding 0.1 renders as `0.1`. Because the shortest F32 text has at most 9 significant digits, the nearest `Float` encodes back to exactly that text, and decode returns the same F32. JsonValue does not change. Cost: one binary32 shortest-digit pass and one decimal-to-binary64 step per value on encode.
  >
  > **Concern:** A program that reads the `JsonValue.Float` from `to_json` gets 0.1 (binary64), not the widened F32 value. Code that compares that number with `Float.from(f)` sees a mismatch, so the spec must state which `Float` `to_json` stores.
- **Web:**
  > **Reasoning:** `"{x}"` writes `0.1`, and JSON must not write `0.10000000149011612` for the same value. Under F32-wide every web and ML dev who meets that output files it as a bug. F32-short keeps JsonValue closed, and its round trip holds when the stored Float is defined as the shortest text that reads back to the same F32.
  >
  > **Concern:** If the spec says only "the nearest Float to the shortest text", a double-rounding case could break the F32 round trip. The text must state the round-trip condition, not only the method.
- **PLT:**
  > **Reasoning:** F32-short is still a function into the existing `JsonValue.Float`, and it keeps the round-trip law. The binary64 error of the shortest decimal lies far inside the F32 rounding interval, and an exact midpoint is representable, so ties-to-even returns `x`. It agrees with the F32 text form, so `"{f}"` and the JSON digits match.
  >
  > **Concern:** `x.to_json() != JsonValue.Float(x.to_float())`, so the spec must state this once. Otherwise someone will "fix" it back to widening, or write a law that assumes the two are equal.
- **DevOps:**
  > Reasoning: §3.6 Float Text Form already prints an F32 0.1 as `0.1`. F32-wide would make `"{f}"` and `json.encode` disagree for the same field, which users file as a bug and which breaks grepping logs against payloads. It needs no JsonValue change, and decode rounding to nearest keeps the round-trip law.
  >
  > Concern: An implementer may "simplify" to_json to plain widening. The spec text and a corpus test must pin `{"scale":0.1}` exactly.
- **AI/ML:**
  > Reasoning: `0.10000000149011612` is output that no model and no user predicts, and it breaks "same value, same text" between `"{f}"` and JSON. The short form needs no change to JsonValue and keeps the round trip.
  >
  > Concern: The ballot's wording ("the nearest Float to the F32's shortest text") can fail the round trip in rare cases. Read as binary64, that text can land exactly on an F32 midpoint, and ties-to-even then gives the neighbor. The writer must define the digits as the shortest decimal `d` with `F32.nearest(Float.nearest(d)) == x` (my r1 file), and the corpus needs a round-trip test near midpoints.
- **Minimalism:**
  > **Reasoning:** My round 1 objection was that F32-short changed JsonValue. As restated here, it does not: it builds a plain `JsonValue.Float` from the F32's shortest text. It reuses a rule that already exists (§3.6 *Float Text Form*, the digits of `"{f}"`), so JSON and display agree and no new concept comes in. It still round-trips, because decode rounds to nearest F32. F32-none confuses the compiler's current state with the spec.
  >
  > **Concern:** The Float that goes into the JsonValue is no longer the F32's exact value. Code that reads `to_json()` directly, not through text, sees `0.1` and not the widened value. The spec must say this in one line.

##### Q3. `Bytes` — `Bytes-none`, 6-0

- **Systems:**
  > **Reasoning:** JSON has no binary type. The array form costs one boxed JsonValue per byte and 3-5x on the wire. Base64 makes the language pick a std/url/padding policy that the user should pick.
  >
  > **Concern:** Users who need it must write a wrapper or use a Str field, and some will reach for `List[U8]` (the array form after all). The help must point at a Str encoding first.
- **Web:**
  > **Reasoning:** No shape is common across languages (Go writes base64, serde writes an array, JS writes a Buffer object, Python raises an error). A refusal with a one-line help is clearer than a format the user must look up.
  >
  > **Concern:** Without base64 in Tier 1, a user who needs compact binary JSON must hand-write a base64 helper. The help should say so, not only name `.to_hex()`.
- **PLT:**
  > **Reasoning:** Three encodings round-trip, and none follows from the type's structure, so picking one is a policy and not a typing fact. `List[U8]` already gives the array form, and a wrapper with a hand-written impl gives any other form.
  >
  > **Concern:** None from soundness. The cost is ergonomic: every Bytes field needs a wrapper or a Str field.
- **DevOps:**
  > Reasoning: There is no common wire form (Go base64, serde array, Python refuses), and Bytes-array makes Bytes and List[U8] write identical JSON. A refusal with a help that names `.to_hex()` or a Str field puts the encoding choice in the user's code, where tools and readers can see it.
  >
  > Concern: The E1401 help must name concrete methods that exist on Bytes. A help that points to a missing base64 API is worse than no help.
- **AI/ML:**
  > Reasoning: Each wire form is a guess that half the readers of the JSON get wrong (Go writes base64, serde writes a number array). A refusal with a help line makes the choice explicit in the user's code, where a model can read it.
  >
  > Concern: Bytes has no `from_hex`, so the Str-field repair cannot round-trip until a decode method exists. The help must not promise a round trip.
- **Minimalism:**
  > **Reasoning:** base64 and a number array are both reasonable, and they disagree. That shows the encoding is a policy choice, and a policy choice belongs in user code or a stdlib helper, not a built-in row. The help that points to a Str field via `.to_hex()` or base64 costs nothing.
  >
  > **Concern:** Users will write their own base64 wrappers and they will differ. If that shows up, a stdlib helper is the fix, not a language row.

### Phase D — `U64` only

Phase C left `U64` at 4-2. Every other question passed 6-0 and closed. The moderator sent each seat the Phase C reasoning
and asked for a reply on `U64` and a final vote.

- **Systems (changes to `U64-none`):**
  > The other side's strongest point is one-way reversibility (devops, aiml, min), and I can't answer it. A U64 row added later is pure addition and breaks no program. A string row shipped now can change only by changing bytes on the wire, which no compiler error catches.

  > Systems fact for the help: `Int.try_from(h)` fails for half the U64 range, so for `hash()` values the help must name the `Str` field first. `Int` comes second, only for values the user knows are below 2^63.

  > **Concern:** `hash()` returns U64, so users will hit E1401 often. The U64-specific help must lead with the Str field (`h: Str` with `x.to_str()`, decode back through the U64 parse) and say that `Int.try_from` fails above 2^63-1, or users will pick `Int` and get a runtime error on half of all hashes.

- **Web (`U64-none`; new fact on `hash()`):**
  > Four Phase C votes, mine included, used "hash() returns U64, so users will hit this often" as the main cost. sys used it as a case for U64-str. The spec says a stored hash is a bug in itself:
  >
  > - §3.6 *Hash Contract and Seeding* (sections/03_types.md:5924): "The runtime picks a random hash seed for each process."

  > Under U64-str, this compiles, writes `{"h":"9137…"}`, reads back cleanly, and the comparison silently fails. Under U64-none, the user gets E1401 at the field, and the help can say so in one line.

- **PLT (changes to `U64-none`; the condition):**
  > Measured in typing terms, it holds. Adding an instance `U64 : Serialize` later is a conservative extension of the instance list:
  >
  > - Every program that checks today still checks.
  > - None of them changes meaning: no existing derive or bound resolves to a different impl.
  > - The only change is that some programs refused with E0306 or E1401 would begin to check.

  > To keep the extension conservative, the rule must not let code observe the absence of the impl in a way that a later row would change. That holds today: there are no negative bounds, and a derive that fails is an error, not a silent skip. If either rule ever changes, revisit this vote.

- **DevOps (`U64-none`; new facts):**
  > **There is no Str → U64 parse in the spec.** `Str` has `parse_int` and `parse_float` only (sections/03_types.md:298-299). The conversion tables in 03c (:547-587) give no `Str` source for U64.

  > **The checked conversion is `h.to_int_checked()`** (03c :587), not `Int.try_from(h)` as one help draft says. The writer must use the name the spec gives, or the help points to a missing method (the concern I raised on Bytes).

  > **Concern:** If the decision ships without a ticket for a std Str → U64 parse (with a range check, `Result[U64, ConversionError]`), the help's Str route is one-way. Users then hand-roll digit loops with no range check, and that is the exact failure sys predicted. File that ticket with this decision.

- **AI/ML (changes to `U64-str`, `dec-str-only`; the dissent):**
  > **No scalar has a `to_str` method.** §3c.3 *The `to_` rule for scalars* (sections/03c_protocols.md:536): "Rendering a scalar as text is not a conversion: it goes through `Display` (`x.display()` or `"{x}"`), not through a `to_str` method."

  > That point is true, but fact 2 makes the cost of waiting larger than I counted. Until a later vote, every program that must round-trip a full-range U64 writes its own wrapper, its own string form and its own parser. plt's concern then comes true.

  > **Vote:** U64-str, dec-str-only.
  >
  > **Reasoning:** The spec has no `Str` to `U64` parse, so U64-none leaves no correct repair for a value above the Int max. Every user then builds a wrapper with its own shape, and no shape is canonical for a model to learn. One fixed form (always a decimal string, read back only as a canonical decimal string) is a single table row with a precedent in protobuf JSON, and decode is the exact inverse of encode.
  >
  > **Concern:** U64 becomes the one integer type whose JSON is not a number. A model will write `5` into a hand-built JSON body for a U64 field, so the row needs an example in the spec and a decode error that names the expected string form. Separately, whichever side wins, each help text must use the spec's own forms (`"{h}"`, `h.to_int_checked()`), never `h.to_str()` or `Int.try_from(h)`.

- **Minimalism (`U64-none`; new fact):**
  > So a `hash()` result written to JSON is a value that no other process can use. Another process, or the same program after a restart, gets a different number for the same key. In the biggest source of U64 values that people name, U64-none's E1401 does not block a valid program. It catches a bug.

  > **Vote:** U64-none
  >
  > **Reasoning:** The most common U64 value, a `hash()` result, is seeded for each process and must not go on the wire. So the refusal catches a bug, where U64-str would encode it without a word. The other U64 sources (bit patterns, FFI) have no JSON shape that the language should choose. Leaving the row out is the only choice we can reverse with no break.

Phase D result: `U64-none` 5, `U64-str` (`dec-str-only`) 1 (AI/ML).

## Final Spec

The rules are in `sections/03_types.md`, under *Built-in Types in JSON* in §3.6.2. *Type Mapping* has a row for each type that has an impl. `ERROR_CATALOG.md` adds the built-in cases to E1401 and E0306.

```blink
@derive(Serialize, Deserialize)
type Person {
    age: U8
}

let a = 'é'.to_json()                              // JsonValue.Str("é")
let b = json.decode[Person]("{\"age\": 200}")      // Ok(Person { age: 200 })
let c = json.decode[Person]("{\"age\": 300}")      // Err: expected U8 (0 to 255), got 300 at $.age
let d = json.decode[Person]("{\"age\": 3.0}")      // Err: expected U8 (0 to 255), got 3.0 at $.age
```

```blink
@derive(Serialize, Deserialize)
type Layer {
    scale: F32
}

let a = Layer { scale: F32.from(0.1) }
let b = json.encode(a)                             // {"scale":0.1}
let c = a.scale.to_float().display()               // "0.10000000149011612"
```

```blink
@derive(Serialize)
type Cached {
    h: U64        // E1401: write `"{h}"` into a `Str` field, or `h.to_int_checked()` into an `Int` field
}
```

Locked points:

- One closed list of impls. The bound check (E0306), the derive field check (E1401), method lookup and codegen read it. A built-in type with no row has no impl, and the compiler refuses it at check. It never fails at build.
- `Char` writes a one-char `JsonValue.Str`. Decode takes a `Str` of exactly one scalar value. `"ab"`, `""` and `107` are `JsonError`.
- `I8`, `I16`, `I32`, `U8`, `U16` and `U32` write `JsonValue.Int`. Decode takes an in-range `Int` only. An `Int` out of range is `JsonError` with the type, the range and the path, as in `expected U8 (0 to 255), got 300 at $.age`. A `Float` is `JsonError`.
- `I64` is not in the list. The spec gives it no status here.
- `Range[T]` has no impl. The help says to write a struct with `start` and `end` fields.
- `Never` is unchanged. `Map`, `Set` and tuples get no row in this decision.
- `U64` has no impl. `@derive(Serialize) type H { h: U64 }` is E1401, and `f(h)` with `T: Serialize` is E0306. The help leads with a `Str` field written as `"{h}"`. Second, it gives `h.to_int_checked()` into an `Int` field, which fails above 2^63 - 1 (half of all hash values). It notes that `Hash.hash` has a seed for each process, and that `Sha256` gives a stable digest. The text claims no `Str` to `U64` parse.
- A later `U64` row is a conservative change only while code cannot observe that an impl is absent. Blink has no negative bound, and a derive that fails is an error and never a silent skip. If either rule changes, revisit this decision (PLT's condition).
- `F32` writes `JsonValue.Float` that holds the nearest `Float` to the shortest decimal `d` such that rounding `d` to binary64 and then to binary32 gives back `x`. An `F32` that holds 0.1 writes `{"scale":0.1}`. `x.to_json()` is not `JsonValue.Float(x.to_float())`. Decode takes `Int` or `Float` and rounds to the nearest `F32`. A finite value out of `F32` range is `JsonError`, and so is `null`. `JsonValue` does not change.
- `Bytes` has no impl. `@derive(Serialize) type Blob { data: Bytes }` is E1401. The help names a `Str` field and `data.to_hex()`. It promises no round trip and names no base64 API.
