[< All Decisions](../DECISIONS.md)

# JSON Encoding of NaN and Infinity — Design Rationale

JSON has no NaN and no infinity, but a `JsonValue.Float` can hold either. §3.6 *Float Text Form* left the encoding to §3.6.2, and §3.6.2 did not decide it. The parse side was already partly fixed: `json.parse` follows RFC 8259 first, and `1e999` gives `Err` (decisions/parse-float-input-grammar.md).

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated
in independent-proposal → debate → vote rounds.

#### Phase A — Independent proposals

All six put the same core first: write a non-finite Float as `null`, keep the encoders infallible, and keep `json.parse` strict.

- **Systems:** "`json.stringify`, `json.pretty` and `json.encode` write a `JsonValue.Float` that is NaN, `inf` or `-inf` as the JSON token `null`." "Keeping the signatures infallible matters for codegen. `Result[Str, JsonError]` makes the return value two words wider and puts a tag check at every call site, including `Response.json(user)` on each request." "I chose the null encoding over the bare-token encoding because valid output beats round-trip fidelity." Optional add-on S2: `fn stringify_strict(value: JsonValue) -> Result[Str, JsonError]` — "YAGNI argues for adding it only if a user asks, so I am fine either way."
- **Web/Scripting:** Proposal W1, "null, like JSON.stringify". "The message SHOULD say that JSON has no NaN/Infinity." "The message SHOULD add a hint: `expected Float, got null at $.temp_c (non-finite Floats encode as null; use Option[Float] to accept it)`." "Not a string: `"NaN"` turns a number field into a string field in the consumer's schema. Reject." Fallback W2: `json.stringify_strict` and `json.encode_strict[T]`. "I prefer W1 alone (YAGNI) and would vote W2 over any change that makes `json.encode` return `Result`."
- **PLT:** Proposal P1: a total stringify that writes `null`, and a strict parse. "The types tell the truth. The spec already calls `to_json`, `stringify` and `encode` "pure, infallible". With panic we would put hidden partiality behind a total signature." "Why not a string "NaN": it moves a value across constructors (Float -> Str), and the result collides with a real Str field holding "NaN"". Second choice P2: `json.stringify(value) -> Result[Str, JsonError]`. "Panic is the one option I vote against in every form."
- **DevOps:** "My test is the 3am page." Proposal: encode as `null`; add `json.check(value: JsonValue) -> Result[(), JsonError]`; "the error message names the token. A generic "unexpected character" is not good enough."; a `Float` field rejects `null` and "The message names the cause". "the spec should fix the content of the message (it names the token, or "non-finite" plus the path), the same way it fixes `line L, column C` today. It should not fix the wording."
- **AI/ML:** Proposal A. "Law (output validity): every Str that `json.stringify`/`json.pretty`/`json.encode` returns is text `json.parse` accepts. The law, not the null rule, is what a reader memorizes". "A generated `let body = json.encode(user)` would fail to compile in most code an AI writes, for an edge case that almost never occurs." "Silent lossy acceptance (null -> NaN on decode) would add a hidden rule a model cannot guess."
- **Minimalism:** Proposal M1: "NaN and ±inf encode as JSON null. Parse adds nothing. No signature changes." "A panic in a pure, "infallible" encoder is a trap that only shows up in production." "Option[Float] with Some(NaN) round-trips to None — "a silent change, and the spec must say it in one sentence"". "The two most-used ecosystems with infallible encoders (JS, Rust) chose null." Fallback M2: "Add one lint later, only if users report the problem (YAGNI). Do not add it now."

Every panelist rejected bare `NaN`/`Infinity` tokens, a `"NaN"` string, and a panic.

#### Phase B — Debate highlights

One round. All six signalled stable.

- **PLT** withdrew the `Result` signature: "I concede E-result. ... My one soundness objection was hidden partiality, and E-null has none." "Record `json.check` as the chosen shape, deferred."
- **Systems** dropped S2: "I concede "none now" and drop S2. If users ask for one later, I prefer devops's `json.check(value) -> Result[(), JsonError]` to `stringify_strict`/`encode_strict`." Systems also checked PLT's open round-trip points: "`-0.0` to `0.0` needs no caveat, because Blink `==` does not tell them apart" and "An integral Float reads back as Int" does not happen. Float Text Form puts a `.` in every finite output". "The law does assume that `JsonValue` uses structural `==`. If the spec does not already say that, it should state it in the same paragraph."
- **DevOps** conceded the checker on one condition: "So "none now" holds only if we file a separate chore or ticket for `Float.is_finite` / `is_infinite`."
- **Web** moved toward content rules: "**V2 (parse error content): back devops's rule.** The spec fixes the content and not the wording" and "**V3 (decode hint): content rule, not wording.** ... My `Option[Float]` hint text goes in implementation guidance or the docs, not in the spec."
- **Minimalism** *(dissent on message rules)*: "Adding a content rule for one token class sets a precedent, and every other invalid token would then want its own rule. A better message is a quality-of-implementation matter". "This decision must not add a public `is_finite`."

#### Phase C — Final vote

- **Q1: encoding rule** (6-0, E-null)
  - **Systems:** "The cost is one exponent-mask test per Float on the write path. There is no allocation, and the return value stays a plain Str".
  - **Web/Scripting:** "It matches JS `JSON.stringify` and Rust serde_json, so a web dev already expects it and needs no doc read."
  - **PLT:** "every encoder stays a total function with a defined value at every input, and `encode = stringify . to_json` composes total functions."
  - **DevOps:** "The bytes on the wire are always valid JSON, so no consumer in another language breaks on our output." Concern: "The first sign is a decode error in a different service, so the Q4 hint carries real weight."
  - **AI/ML:** "`null` is what JS and serde_json write, so models will guess it correctly without reading the spec."
  - **Minimalism:** "E-null closes the gap with no new surface and no change to any signature." Concern: "the loss is silent at write time. A NaN that comes from a bug turns into `null` far from its cause."
- **Q2: strict check in v1** (6-0, none now; `json.check` recorded as the deferred shape)
  - **Systems:** "A strict check costs a second walk over the whole tree. That is fine as an opt-in, but no user has asked for it". Concern: "Without a public `is_finite`, users can't write a cheap check of their own. That ticket must actually land."
  - **Web/Scripting:** "YAGNI. No user has asked for it". Concern: "Until `is_finite` exists, the one-line user check is really `is_nan(x) || x == inf || x == -inf`, which is clumsy."
  - **PLT:** "Q1 already makes the encoders total and sound, so a checker adds API surface without fixing a soundness problem."
  - **DevOps:** "My condition still stands: users need `Float.is_finite` to write their own guard."
  - **AI/ML:** "Each extra encoder-side function is one more choice a model must make on every JSON call."
  - **Minimalism:** Concern: "someone adds `stringify_strict` later because nobody reads the deferred note. The decision record must name `json.check` as the only approved shape."
- **Q3: parse error for `NaN`/`Infinity` tokens** (3-2-1: SHOULD 3, content rule 2, none 1 → Phase D)
  - **Systems:** P-should — "A SHOULD gives users the useful text and does not tie the impl to one way of detecting the token". Concern: "A SHOULD can be ignored. A lazy impl ships "unexpected character" and the spec says nothing against it."
  - **DevOps:** P-should — "Python and Jackson-lenient producers emit these exact tokens. That makes this the most common bad input in mixed fleets". Concern: "The implementation ticket must carry it as an acceptance test."
  - **PLT:** P-should — "A normative content rule for one token class breaks that principle and sets a precedent for every other token."
  - **Web/Scripting:** P-content — "Fix the content only, as for `line L, column C`, so a test can check it and implementations can still choose the words. A SHOULD would let an implementation skip the one part that helps."
  - **AI/ML:** P-content — "AI agents repair code from error text. ... A SHOULD gives no promise anyone can test against."
  - **Minimalism:** P-none — "Good text belongs to the implementation ticket."
- **Q4: decode error when a `Float` field reads `null`** (4-1-1: SHOULD hint 4, content rule 1, none 1 → Phase D)
  - **Systems:** H-should — "A non-finite Float coming back as `null` will be the most common surprise from this ruling". Concern: "Impls should word it as a possible cause, not a diagnosis."
  - **DevOps:** H-should — "Putting that only in docs means the person on call never sees it."
  - **AI/ML:** H-should — "SHOULD is enough here, since the fix advice is guidance and not something to test word for word."
  - **PLT:** H-should. Concern: "the hint could imply that `Option[Float]` preserves NaN. It does not (it gives `None`)".
  - **Web/Scripting:** H-content — ""got null, expected Float at $.temp_c" names the cause, and a test can check it. The `Option[Float]` advice is guidance, not a contract".
  - **Minimalism:** H-none — "It also ties the spec to one fix, which is not always the right one. A user may want an enum or a sentinel."
- **Q5: laws** (5-1, L2: valid output + replacement round trip + the `Some(NaN)` sentence; Minimalism dissent)
  - **Systems:** "The replacement law covers the finite round trip and two-way finiteness without "up to" clauses, because -0.0 == 0.0 under Blink `==` and every finite Float output contains `.`."
  - **Web/Scripting:** "Output validity is the law a user can see and test ("does my output parse?"), so state it on its own even though the replacement law implies it."
  - **PLT:** Concern: "Keep the law at the `JsonValue` level and give the `Option` effect in its own sentence."
  - **DevOps:** "I am withdrawing L3."
  - **AI/ML:** Concern: "Readers may not notice that `-0.0` comes back as `0.0`."
  - **Minimalism:** *(dissent, L1)* "The replacement law already implies output validity, because the result is `Ok`. L2 states the same fact twice, and L3 states it three times."
- **Q5b: state `JsonValue` equality** (6-0)
  - **Systems:** "A law written with `==` over `JsonValue` means nothing until the spec says which `==` that is."
  - **Web/Scripting:** Concern: "Otherwise people will expect `{"a":1,"b":2} == {"b":2,"a":1}` because JS deep-equal helpers treat them as equal."
  - **PLT:** "Object equality must compare entries in order and keep duplicates ... it must not compare as a map." Concern: "State that `JsonValue` is not `Hash`, since `Float` is not".
  - **DevOps:** "Test tooling (`assert_eq` on parsed values) also needs `JsonValue` equality to be stated."
  - **AI/ML:** "models will write `assert_eq(json.parse(s), Ok(v))` in tests."
  - **Minimalism:** "The clause must say `Eq` only."

#### Phase D — Round 2 (Q3, Q4)

Before the round, the moderator surfaced one fact: §3.6.2 *Str-Backed Enums* already fixes decode-error content beyond location (the rejected value, the enum type and every valid literal, with the wording not fixed), and that rule passed 6-0.

- **Q3** (6-0, P-content: the message names the rejected token; the wording is not fixed)
  - **Systems:** "If every SHOULD voter wants a test, the content should be in the spec where the test can point to it."
  - **Web/Scripting:** "A content rule for one well-known bad input is how §3.6.2 already works, not a break from it."
  - **PLT:** "Measured against it, a SHOULD is the odd one out: it adds normative-looking text that no conformance test can check."
  - **DevOps:** "Naming the token is always true for this input, so a content rule can never mislead."
  - **AI/ML:** "web's limit is right: this token class gets the rule because a mainstream encoder (Python `json.dumps`) produces it by default, and no other parse error gets one." Concern: "an impl might echo the token without saying that JSON has no NaN or Infinity. The example in the spec should show both."
  - **Minimalism:** "So "the spec fixes only location" was never the whole rule. I concede that point." Concern: "the one-token-class rule must stay justified by Python's default output. Without that, every parse error will ask for a content rule."
- **Q4** (3-3 → user broke tie for H-content: the message says the value was `null` and the field expects `Float`; the `Option[Float]` hint is non-normative impl text)
  - **Systems:** H-content — "The `Option[Float]` advice is guidance, and min and plt are right that it is not always the fix and can read as lossless. Keep the advice in docs and the impl. Keep the facts in the spec." Concern: "the impl ticket must still carry it, or on-call readers will never see the fix."
  - **PLT:** H-content — "`Option[Float]` is one fix among several (enum, sentinel), and pointing to a remedy is advice, not semantics."
  - **Minimalism:** H-content — "A SHOULD is spec text that no test enforces. It costs words and promises nothing."
  - **Web/Scripting:** *(dissent, H-should)* "I concede to devops: "Putting that only in docs means the person on call never sees it.""
  - **DevOps:** *(dissent, H-should)* "A content rule must always be true, and the hint is not always true. That is exactly what a SHOULD is for."
  - **AI/ML:** *(dissent, H-should)* "The part that teaches the rule is the hint, so that is the part worth a sentence of spec."
  - **User tiebreak:** H-content, as the moderator recommended: the same untestable-SHOULD reasoning moved three votes on Q3, and the content rule matches the Str-backed enum precedent.

#### AI-First Review

5/5 pass: one rule to learn (non-finite → `null`, as in JS and serde_json); no new pattern (infallible signatures stay, and the content rules follow the Str-backed enum precedent); `json.encode(x)` stays a plain `Str`, so generated code needs no `?`; the parse error names the token and the decode error gives a `$` path; no token cost on common code.

### Final Spec

```blink
json.stringify(JsonValue.Float(0.0 / 0.0))   // "null"
json.parse("\{\"a\": NaN}")                   // Err: names `NaN`, at line 1, column 7

@derive(Serialize, Deserialize)
type Reading { temp_c: Float, peak: Option[Float] }

// Reading { temp_c: 0.0 / 0.0, peak: None } encodes as {"temp_c":null,"peak":null};
// decoding that gives Err: null, expected Float, at $.temp_c.
// Reading { temp_c: 1.0, peak: Some(0.0 / 0.0) } decodes back with peak: None.
```

- `json.stringify`, `json.pretty` and `json.encode` write NaN, `inf` and `-inf` as `null` and stay infallible.
- `json.parse` rejects `NaN`, `Infinity` and `-Infinity` in any ASCII case; the message names the rejected token.
- A derived `from_json` for a `Float` field rejects `null`; the message says the value was `null` and the field expects `Float`. `Option[Float]` reads `null` as `None`.
- Laws: every output parses; `json.parse(json.stringify(v)) == Ok(w)`, with each non-finite Float in `v` replaced by `JsonValue.Null`.
- `JsonValue` has structural `Eq`: `Object` compares as a list, so order and duplicate keys count. `JsonValue` is not `Hash`.
- Deferred: if a strict check is added, its only approved shape is `json.check(value: JsonValue) -> Result[(), JsonError]`.
