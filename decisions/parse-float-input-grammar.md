[< All Decisions](../DECISIONS.md)

# parse_float Input Grammar — Design Rationale

## Gap

The Float text form vote fixed what `Float.display()` writes and the round-trip law. It left open
what else `Str.parse_float` accepts: upper-case `E`, `+` in the exponent, a leading `+`, `.5` and
`1.`, surrounding whitespace, the case of specials, `Infinity`/`nan` spellings, and overflow
(`1e999` gives `Err` or inf). DevOps dissented in that vote because JSON, Python and C write `1E5`
and `1e+5`, and Blink programs must read them.

```
"1E5".parse_float()  "1e+5".parse_float()  "1e999".parse_float()  // result unspecified
```

An owner interim decision (2026-10-16) accepted a bare integer such as `"42"` while this ticket was
open.

## Result

| Q | Topic | Result | Vote |
|---|---|---|---|
| Q1 | Sign | `sign = "+" \| "-"`, one rule that `parse_int` and `parse_float` share | 5-1 (PLT dissent) |
| Q2 | `.5` and `1.` | `Err` | 4-2 R2 after 4-2 R1 for accept (Web, AI/ML dissent) |
| Q3 | Specials | `sign? ("nan" \| "inf" \| "infinity")`, ASCII A–Z case folding; a sign on `nan` has no effect | 5-1 (PLT dissent) |
| Q4 | Error message | MUST name one cause class from a closed list; no byte offset required; wording not part of the contract | 6-0 R2 after 3-2-1 R1 |
| Q5 | Message size | "The size of the message does not grow with the size of the input. If it quotes the input, it quotes a bounded excerpt." | 5-1 R2 after 4-2 R1 (Min dissent) |
| Q6 | Laws | Int text is Float text; One number reader; Literals; Finite in, finite out | 5-1 (Min dissent: only One number reader and Literals) |

All six seats agreed from Phase A on these points: `e` or `E` with an optional exponent sign; a
bare integer text; no whitespace, `_`, hex floats, `nan(...)` payloads, other decimal marks or
locale; correct rounding for any number of digits; overflow gives `Err` and underflow gives `Ok`.

AI-first review: 5/5 pass. Caveat on generability: the `.5` refusal is a fact that only Blink has,
so models will not know it from other languages.

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated
in independent-proposal → debate → vote rounds.

#### Phase A — Independent proposals

- **Systems:** "There is one firm rule from this seat. **The grammar gate stays in Blink, before strtod.**"
  ```
  float_text = sign? (number | special)
  sign       = '+' | '-'
  number     = mantissa exponent?
  mantissa   = DIGITS ('.' DIGITS?)? | '.' DIGITS
  exponent   = ('e' | 'E') sign? DIGITS
  special    = "nan" | "inf" | "infinity"     -- ASCII, any case
  ```
  "**Proposal A.** It costs nothing at run time, it parses what real producers write, and it gives a strict `Err` for overflow, whitespace, hex and `_`, so bad data fails loudly."
- **Web/Scripting:** "My test: a JS or Python dev pipes in a CSV, a JSON dump or `printf` output and calls `.parse_float()`. It should work the first time. If it fails, the error should tell them why."
  ```
  float   = sign? ( decimal exp? | special )
  sign    = '+' | '-'
  decimal = DIGITS ( '.' DIGITS? )? | '.' DIGITS
  exp     = ( 'e' | 'E' ) sign? DIGITS
  special = "nan" | "inf" | "infinity"        (ASCII, any letter case)
  ```
  "If `\"+5\".parse_float()` works and `\"+5\".parse_int()` fails, people will ask about it on Stack Overflow." "**Preferred: W1, with the `+` sign added to `parse_int` and a whitespace error message that names `.trim()`.**"
- **PLT:** "My frame: the parse_float grammar is not a matter of taste. A few laws that link it to its neighbours (display, parse_int, Blink literals, JSON) fix it."
  ```
  FLOAT   = NUMERIC | "NaN" | "inf" | "-inf"
  NUMERIC = "-"? DIGITS ("." DIGITS)? (("e" | "E") ("+" | "-")? DIGITS)?
  DIGITS  = [0-9]+
  ```
  "`parse_int` accepts exactly `\"-\"? DIGITS` with nothing before or after." "**P1 + P2 as one package**, with L2–L5 written into the spec next to the grammar so that later tickets ([the exponent-literal ticket], [the JSON NaN and inf ticket]) must keep them. If the panel wants `+` or whitespace, add them to parse_int and parse_float together, never to one alone."
- **DevOps:**
  ```
  float   := sign? ( decimal | special )
  sign    := '+' | '-'
  decimal := ( DIGITS ( '.' DIGITS? )? | '.' DIGITS ) exp?
  exp     := ( 'e' | 'E' ) sign? DIGITS
  special := 'inf' | 'infinity' | 'nan'      // ASCII, any letter case
  DIGITS  := [0-9]+
  ```
  "This is a real bug class: a Blink program reading a Prometheus scrape or a pandas CSV fails on the first large number." "**Proposal A**, with the `parse_int` rider. Refuse whitespace, refuse hex, return `Err` on overflow, and require messages that name the cause. Rust and Go have shipped this shape for years, and it reads what every common writer produces."
- **AI/ML:** "Accepting too much costs almost nothing; rejecting too much fails silently in the field."
  ```
  FLOAT   := SIGN? ( DECIMAL EXP? | SPECIAL )
  SIGN    := '+' | '-'
  DECIMAL := DIGITS ( '.' DIGITS? )? | '.' DIGITS
  EXP     := ( 'e' | 'E' ) SIGN? DIGITS
  SPECIAL := "inf" | "infinity" | "nan"     (ASCII, any letter case)
  DIGITS  := one or more ASCII '0'..'9'
  ```
  "**Preferred:** P1 + P2. P1 is the Rust grammar models already know, with overflow as a loud Err and a whitespace message that names the fix; P2 keeps `parse_int`'s sign rule aligned with it."
- **Minimalism:** "My starting point: `parse_float` is one strict grammar."
  ```
  float   = '-'? DIGITS ('.' DIGITS)? (('e' | 'E') ('+' | '-')? DIGITS)?
          | 'NaN' | 'inf' | '-inf'
  DIGITS  = [0-9]+
  ```
  "If the panel wants case-folded specials, the most I would accept is ASCII case-insensitive `nan` and `inf` with an optional `-`." "**Preferred: M1 + M1-rider.**"

Phase A.5 grouped the proposals into Option R ("Rust-shaped": Sys, Web, DevOps, AI/ML) and
Option J ("JSON number closure plus display specials": PLT, Min).

#### Phase B — Debate highlights

- **Minimalism** (moves on `+` and specials): "First, a correction to my own Phase A. I wrote that \"no common serializer writes\" a leading `+`. That is wrong: Go writes `+Inf`, and C `%+e` writes `+1.5e+00`. [...] For those forms the burden of proof is met, so I move." / "**Leading `+`: accept.** I accept it as part of one sign rule, `sign?` in front of everything." / "**`.5` and `1.`: reject. This is where I hold.** No default serializer in anyone's table writes them." / "**Move to R's rule:** `sign? (\"nan\" | \"inf\" | \"infinity\")`, ASCII, any letter case. It is one rule covering six writers."
- **Systems** (moves on `parse_int`): "I change my Phase A position, where I wanted this filed as a separate ticket. PLT's rule \"add it to both or neither\" is right." / "**`.5` and `1.`.** These are the weakest items on the list. [...] If the panel splits on this item alone, I would trade it away before I trade away `+` or the specials." / On L3: "do not say that \"the JSON Float branch *is* parse_float\". Say that `json.parse` first matches the RFC 8259 grammar, then gives the same value that parse_float gives for that text."
- **DevOps:** "**Prometheus text exposition format** writes `NaN`, `+Inf` and `-Inf` as normal values. Every histogram has a bucket with `le=\"+Inf\"`. [...] Under Option J, `\"+Inf\".parse_float()` is `Err`." / "**`.5` and `1.`: accept, but this is my weakest item.**"
- **PLT** (accepts a shared sign): "I would accept `+` if it is added under one rule: **one SIGN production, shared by parse_int and parse_float**." / "Stable, ready to vote. Order: J + laws > R + laws with shared SIGN and ASCII-only case folding > anything without the laws."
- **Web/Scripting:** "**`.5` and `1.` come from people, not serializers:** spreadsheet exports, config files, CLI flags (`--ratio .5`)." / "**L3 needs one caveat.** [...] It must not mean that json.parse accepts `+1` or `.5`. JSON stays strict."
- **AI/ML:** "**J is a grammar no language ships.** JSON has no NaN, and no language parser rejects `+1.5` while it accepts `1E+5`." / "That is a display property, not a parse property. Parse is already many-to-one."

#### Phase C — Final vote

- **Q1: Sign** (5-1, PLT dissent)
  - **Systems:** 1a — "C `%+e`/`%+g` and Go `+Inf` write a leading `+` in their normal output, so this is real data, not text people type by hand. [...] Rust, Go, C strtod/strtol and Python all accept it in both the float and the integer parser, so the \"both or neither\" rule also points to 1a." Concern: "The spec should say that a canonical check is `n.display() == s`, not a successful parse."
  - **Web/Scripting:** 1a — "People type a leading `+` in env vars, config and CLI flags, and Go writes `+Inf`. If Blink rejects it, the user gets an `Err` they did not expect, and that is a Stack Overflow question."
  - **PLT:** *(dissent)* 1b — "No text in the sets the laws require (display output, RFC 8259 numbers, Blink literals) begins with `+`. With `-` only, each Float value has one sign spelling on input as well as on output, and parse_int needs no change." Concern: "if 1a wins, the shared production must be one grammar rule cited by both parsers, not two copies that drift apart."
  - **DevOps:** 1a — "With one shared SIGN production, `+Inf`, `+1.5` and `\"+5\".parse_int()` all behave the same way, so the user has no sign rule to guess."
  - **AI/ML:** 1a — "If Blink rejects it, LLM-written code compiles and passes its tests, then fails on real data, and no model can see that from the code."
  - **Minimalism:** 1a — "Once `+` must parse in front of a special, one sign rule in front of everything is the smaller grammar." Concern: "If a later ticket wants a canonical int reader, it cannot narrow this one."
- **Q2: `.5` and `1.`** (4-2 for accept; went to Phase D)
  - **Systems:** 2a — "Every major parser (Rust, Go, C, Python, Java) accepts both, so if Blink rejects them, data that every other parser reads fails in Blink."
  - **Web/Scripting:** 2a — "People write these forms by hand in config, spreadsheets and CLI flags (`--ratio .5`)."
  - **PLT:** 2b — "With 2b, the grammar for numeric text has one shape across literals, display, parse_float and JSON." Concern: "if 2a wins, [the exponent-literal ticket] must not read L4 as a reason to admit `.5` and `1.` as source literals."
  - **DevOps:** 2a — "This is my weakest item. I vote for it because the cost is near zero."
  - **AI/ML:** 2a — "A model has a strong prior here and no reason to recall a Blink-only refusal."
  - **Minimalism:** 2b — "Widening later from Err to Ok breaks no program, but narrowing later from Ok to Err does, so the narrow choice is the safe one."
- **Q3: Specials** (5-1, PLT dissent)
  - **Systems:** 3c — "The fold runs on at most eight bytes, and only after the numeric scan fails, so the success path pays nothing. Folding only A–Z keeps the rule free of Unicode case tables."
  - **Web/Scripting:** 3c — "`Infinity` is how JS, Java and Python `json.dumps` write infinity, and pandas and numpy write `nan` for missing data."
  - **PLT:** *(dissent)* 3a — "Blink has one NaN under `==` and one spelling per value on output, and 3a keeps input the same. I accept that [the JSON NaN and inf ticket] can force `Infinity` in under L3." Concern: "if 3c wins, the spec must say \"ASCII A–Z folding only\" outright, or someone will read it as Unicode case folding."
  - **DevOps:** 3c — "Ops data uses at least six spellings [...] Only 3c reads all of them with one rule."
  - **AI/ML:** 3c — "it is the Rust rule models already know. Parse is already many-to-one, so this costs no principle."
  - **Minimalism:** 3c — "One case-folding rule over six ASCII words costs less than that adapter repeated across user code." Concern: "A sign on `nan` that has no effect is one quiet rule. The spec must state it plainly, so no one reads `-nan` as a distinct value."
- **Q4: Error message** (3-2-1; went to Phase D)
  - **Systems:** 4a — "The scanner already holds the index where it stopped, so the offset is free to report."
  - **Web/Scripting:** 4b — "A byte offset adds little for number texts that are a few characters long."
  - **PLT:** 4b — "The cause class is a closed, finite set, so a reviewer can check that a message names it while the text stays outside the contract."
  - **DevOps:** 4a — "A user who reads a log with 10k rows needs the failing byte, not just \"invalid\"." Concern: "unless the stdlib's own tests check that the cause class is present in the message."
  - **AI/ML:** 4a — "A model in an agent loop reads it and repairs its code on the next turn." Concern: "the spec example must show `match` on `Err(e)` and print `e.message`, never compare it."
  - **Minimalism:** 4c — "A MUST on free text that no test may match on cannot be checked."
- **Q5: Message size** (4-2 for 5a; went to Phase D)
  - **Systems:** 5a — "If the message quotes the input, a bad multi-megabyte field gets copied into every error and every log line, and the error path's cost grows with the input."
  - **Web/Scripting:** 5a — "A message that echoes a 10 MB bad field floods logs and terminals, and the input may hold secrets."
  - **PLT:** 5b — "The spec does not require the message to quote the input at all, so a cap on quoting governs something the spec never asked for."
  - **DevOps:** 5a — "People call parse_float on whatever a split returns, and that can be a whole file after a bad delimiter."
  - **AI/ML:** 5a — "An unbounded quote of a multi-megabyte bad field floods logs and model context windows."
  - **Minimalism:** 5b — "This is a rule about message content, and the message is not part of the contract."
- **Q6: Laws** (5-1, Min dissent)
  - **Systems:** 6a — "The gated L3 means there is one decimal-to-binary reader in the stdlib, so there is one place to optimize [...] and one place to get rounding right." Concern: "Under L3, `json.parse` now returns `Err` for `1e999`, where some JSON libraries return inf. The json section must state this."
  - **Web/Scripting:** 6a — "Users take two things for granted: \"if it is an int, it is a float\", and \"JSON numbers and parse_float agree\"."
  - **PLT:** 6a — "L2 is what makes \"both or neither\" for SIGN a checkable rule, not a promise." Concern: "L3 must stay in the gated form [...] or it will read as if parse_float decides what JSON accepts."
  - **DevOps:** 6a — "L3 gives one number reader, so json.parse and parse_float can never disagree on a value or an overflow error."
  - **AI/ML:** 6a — "A model reasons from stated laws far more reliably than from a list of cases."
  - **Minimalism:** *(dissent)* 6b — "L3 deletes a second number reader from the language, which is subtraction. L4 fences [the exponent-literal ticket] in advance for one sentence of cost. L2 and L5 follow from the grammar as written, so stating them adds lines with no new constraint."

#### Phase D — Round 2 (Q2, Q4, Q5)

Round 1 debate, key shifts:

- **Systems** (Q2, 2a → 2b): "Min wrote: \"Widening later from Err to Ok breaks no program, but narrowing later from Ok to Err does.\" In Phase B I argued that both directions are promises. That is true, but they do not cost the same." On Q5 Sys gave the wording that won: "**\"The size of the message does not grow with the size of the input. If it quotes the input, it quotes a bounded excerpt.\"**"
- **DevOps** (Q2, 2a → 2b; Q4, 4a → 4b): "None of the default serializers in my table writes `.5` or `1.`." / "Str indexing works on codepoints by default (§3.2.1), and byte access is the explicit `byte_` API. If the message gives a byte offset and a user uses it as a codepoint index, it points to the wrong place in any non-ASCII field."
- **PLT** (Q4): "It is defined for only one cause class: `\"1e999\"`, `\"\"` and `\"1e\"` have no single bad byte. [...] It is free to report, not free to promise."
- **AI/ML** (Q2 holds 2a): "That one-shape argument ended with Q1 and Q3. The parse grammar now accepts `+`, `E`, `1e+05`, `Infinity` and `-nan`, and display and literals have none of these."
- **Minimalism** (Q4, 4c → 4b): "Web's point moved me: \"If 4c wins, an implementation can ship a bare 'invalid float text' for every case. That throws away the DX win that pays for rejecting whitespace.\""

Silent re-vote:

- **Q2: `.5` and `1.`** (4-2 for reject; Web, AI/ML dissent)
  - **Systems:** 2b — "A later widening from Err to Ok breaks no correct program, but a later narrowing breaks every program that reads the data. No seat named a default serializer that writes these forms." Concern: "the message must make the cause plain. Here that means \"missing digit before '.'\"."
  - **Web/Scripting:** *(dissent)* 2a — "Parse is already the lax data grammar (`+`, `E`, `Infinity`, `-nan`), and leaving out `.5` only adds one exception that no other parser has. Min's asymmetry point is correct, and it is the best case for 2b. But my seat weighs the runtime `Err` that a JS or Python dev hits before that widening ever ships." Concern: "The \"widen on evidence\" path then needs someone to look for that evidence."
  - **PLT:** 2b — "each of those widenings had a default producer behind it, and `.5` / `1.` still have none. A form with no producer is the one to leave out until evidence comes in." Concern: "friction tickets for `.5` must be triaged as widening requests with evidence, not as bugs."
  - **DevOps:** 2b — "The machine output my seat cares about (Prometheus, Go, pandas, C, JS) is already covered by Q1 and Q3. If a widening is needed later, it breaks nothing, so 2b is the choice we can still change."
  - **AI/ML:** *(dissent)* 2a — "During that window, LLM-written ingest code fails on `.5` because every parser a model knows accepts it. [...] I hold 2a, knowing the strongest case on the other side is reversibility." Concern: "the error message for `.5` and `1.` must name the cause (\"digit required before/after '.'\")."
  - **Minimalism:** 2b — "each of those widenings was paid for with real producer output, and this one is not. Err to Ok is a compatible change later; Ok to Err never is." Concern: "`.5` friction tickets must be counted and acted on rather than closed as \"by design\"."
- **Q4: Error message** (6-0 for 4b)
  - **Systems:** 4b (from 4a) — "Blink's `Str` indexes by codepoint by default, so a required byte offset invites misuse on non-ASCII fields. An offset also has no single meaning for `\"\"`, `\"1e\"` or `\"1e999\"`." Concern: "The stdlib must ship the per-class substring tests."
  - **Web/Scripting:** 4b — "The cause class is what drives the fix (\".trim()\", \"out of range\"), and 4b requires it while still letting an implementation report a position."
  - **PLT:** 4b — "the stdlib's own conformance tests can check it while user programs stay barred from matching the text." Concern: "the spec must list the cause classes exactly (surrounding whitespace, unexpected character, missing digits, out of range)."
  - **DevOps:** 4b — "The cause class carries the fix." Concern: "The implementation ticket must include those tests."
  - **AI/ML:** 4b — "The cause class is what a model needs to repair code." Concern: "the spec example must handle `Err(e)` by printing `e.message`, never by comparing it."
  - **Minimalism:** 4b (from 4c) — "\"not part of the contract\" binds user programs, and the stdlib's own tests can check that the cause class appears." Concern: "the list of cause classes must be closed and written once."
- **Q5: Message size** (5-1 for 5a; Min dissent). Wordings ranked by each 5a seat:

  | Seat | Ranking |
  |---|---|
  | Systems | 5a-S > 5a-A > 5a-W > 5a-P |
  | Web/Scripting | 5a-S > 5a-A > 5a-W > 5a-P |
  | PLT | 5a-S > 5a-P > 5a-W > 5a-A |
  | DevOps | 5a-S > 5a-P > 5a-A > 5a-W |
  | AI/ML | 5a-S > 5a-A > 5a-W > 5a-P |

  - **Systems:** 5a — "The rule exists to stop the error path's memory use and its log output from growing with the input, and 5a-S states that property directly."
  - **Web/Scripting:** 5a — "That is a user-visible resource and data-leak property, not message style."
  - **PLT:** 5a (from 5b) — "Sys's wording answers it with an exact property: the size of the message has a bound that does not depend on the size of the input. That is a resource rule of the same kind as \"parsing is linear\", and a test can check it (feed a 1 MB bad input, check the message length)."
  - **DevOps:** 5a — "a bad split must not copy a whole file into every error and log line."
  - **AI/ML:** 5a — "5a-S states this as a resource property [...] it needs no unit."
  - **Minimalism:** *(dissent)* 5b — "The real concern, error text that grows with user data, applies to every stdlib error and not only to parse, so it belongs in one stdlib-wide rule if anywhere." Concern: "If 5a wins, the parse section will hold the only bounded-message rule in the stdlib. [...] 5a-S is the least bad wording because it states a resource property, not a style."

### Final Spec

```
int      = sign? digits
float    = sign? ( numeric | special )
sign     = "+" | "-"
numeric  = digits ( "." digits )? exponent?
exponent = ( "e" | "E" ) sign? digits
special  = "nan" | "inf" | "infinity"
digits   = one or more ASCII "0" to "9"
```

```blink
fn main() {
    match "+1.5e+3".parse_float() {
        Ok(v) => io.println("{v}")
        Err(e) => io.println(e.message)
    }
}
```

- One `sign` rule for `parse_int` and `parse_float`.
- `special` folds ASCII A–Z only. A sign on `nan` has no effect.
- `.5` and `1.` give `Err`. A later change to accept them breaks no program.
- No whitespace, `_`, hex, `nan(...)`, other decimal marks or locale.
- A finite text that rounds to ±infinity gives `Err`. Underflow gives `Ok` and keeps the sign.
- The message names one cause class: surrounding whitespace, unexpected character, missing digits,
  or out of range. The class is part of the contract; the wording is not.
- The size of the message does not grow with the size of the input.
- Laws: Round trip, Int text is Float text, One number reader (`json.parse` checks RFC 8259 first),
  Literals (literals ⊆ `parse_float` text, not the reverse), Finite in, finite out.
- A successful parse is not a canonical check; compare `n.display() == s`.

Full text: §3.2.1 *Parsing* and §3.6.2 *Numbers*.
