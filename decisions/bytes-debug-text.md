[< All Decisions](../DECISIONS.md)

# The Debug Text of a `Bytes` Value — Design Rationale

`Bytes` implements `Debug` (§3.2.3), but no section gave its debug text. The *Container Debug Rendering* table had no `Bytes` row, and §8.15.9 said only that `Bytes` has its own `Debug`. The text is the one text that `.debug()`, a `@derive(Debug)` field, the container rows, the failure messages of `unwrap` and `assert_eq`, and a trace value string all write, so the panel had to pick the form.

```blink
@derive(Debug)
type W { b: Bytes }

fn main() ! IO {
    io.println(Bytes.from_str("hi").debug())   // which text?
    io.println(W { b: Bytes.new() }.debug())   // which text?
}
```

Two facts bound the choice. The language has no bytes literal (§2.4), so a `b"..."` text would look like source that does not parse. `Str` and `Char` debug text is valid literal text (§3.6.1 *Scalar debug-forms*), and `Bytes` cannot keep that rule unless its text is a call.

## Summary

| Q | Question | Result | Vote |
|---|---|---|---|
| Q1 | The debug text of a `Bytes` value | A: `"Bytes(" + b.to_hex() + ")"`; empty is `Bytes()`; `Bytes.from_str("hi")` is `Bytes(6869)` | 4-2 in Phase D (Phase C was 2-2-2). Dissent: PLT and Minimalism, for C |

All six seats agreed on four points, so they were not on the ballot:

- `debug()` never cuts its output. Any cut happens at the sink (a trace already cuts at 200 characters).
- The text is the same on every path: `.debug()`, `@derive(Debug)` fields, `List`, `Option` and `Map` elements, `unwrap` and `assert_eq` messages, and trace values.
- There is no `b"..."` form.
- The spec says in one line that the debug text of a `Bytes` value is not source and does not rebuild the value.

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated in independent-proposal, debate, ballot and focused-round phases. Quotes are verbatim; a long reply is cut to the excerpt that carries the position.

#### Phase A — Independent proposals

Five seats proposed a type tag plus the digits of `to_hex`, with four different texts. PLT proposed a constructor expression. No seat proposed a `b"..."` form, a bare `[104, 105]` list, or a cut in `debug()`.

| Seat | Text for `Bytes.from_str("hi")` | Empty |
|------|----------------------|-------|
| Systems | `Bytes("6869")` | `Bytes("")` |
| Web | `Bytes(6869)` | `Bytes()` |
| DevOps | `Bytes(6869)` | `Bytes()` |
| Minimalism | `Bytes(6869)` | `Bytes()` |
| AI/ML | `Bytes[68 69]` | `Bytes[]` |
| PLT | `Bytes.from_list([104, 105])` | `Bytes.from_list([])` |

- **Systems:**

  > Eq agreement (fact 5): equal bytes give equal hex, and different bytes give different hex. It is injective, so assert_eq never shows two identical texts for unequal values. This is why I reject truncation in debug itself: `...` after N bytes would make two unequal buffers render the same, and a failing assert_eq would hide the difference.

- **Web:**

  > Debug must agree with Eq. Truncation, an ellipsis, or a "...(1000 bytes)" summary would make two different buffers print the same text. So no cutting in debug. The trace code already cuts at 200 characters (§8.15.9), so long buffers stay safe there.

- **PLT:**

  > Re-readable, like Str and Char (fact 3). There is no bytes literal (fact 2), so a `b"hi"` form would print something the lexer cannot read. That breaks the invariant "debug output is valid source". The honest source form of a Bytes is its constructor call.

- **DevOps:**

  > One text on every path. debug(), derive, containers, assert_eq text, unwrap panic text and trace all call the same function. The trace's 200-char cut (8.15.9) already bounds length. A second cut in debug() would make two different texts, and would break "Debug agrees with Eq": two Bytes that differ only after the cut would print the same. So debug() is injective and never cuts.
  >
  > Not re-readable as source: there is no bytes literal, so the invariant "debug rebuilds the value" does not apply to Bytes. The spec sentence should say so in one line.

- **AI/ML:**

  > No false literal. Blink has no bytes literal (§2.4). A `b"hi"` debug text would look like source code that does not parse. This breaks the Str/Char principle that debug text is valid source. For Bytes that principle cannot hold, so the form should not look like source. `Bytes[68 69]` is clearly not code. I did not choose `Bytes("6869")` because `Bytes()` is an E0504 error form in §3.2.

- **Minimalism:**

  > Proposal: `Bytes(` + `self.to_hex()` + `)`. One rule, no exceptions, same text on every path (direct debug(), containers, derive, trace, unwrap/assert_eq panic text).
  >
  > Truncation of long buffers: no. Debug must agree with Eq (fact 5); a cut text would make unequal buffers print equal. The trace layer already cuts at 200 chars (fact 6), so the long case is handled where it belongs. Do not add a second cut here.

#### Phase B — Debate highlights

The digest sorted the proposals into option H (a type tag and `to_hex` digits, in variations V1a `Bytes(6869)`, V1b `Bytes("6869")` and V1c `Bytes[68 69]`) and option C (the constructor expression). Systems moved from V1b to V1a. Web moved from V1a to V1c. Minimalism moved from H to C.

- **Systems, on dropping the quotes:**

  > I withdraw my claim that the quoted form "looks like a Str literal". That is a defect, not a benefit. `Bytes("6869")` reads as the 4-character text "6869", and a reader could take it for source that builds a Bytes from the Str "6869". Neither V1a nor V1b is valid source, so the quotes only add false hints.

- **Systems, on the rule:**

  > That rule is the one that is easy to test: `b.debug() == "Bytes(" + b.to_hex() + ")"`.

- **AI/ML, for V1c:**

  > The text must not look like source. `Bytes(6869)` and `Bytes("6869")` have the shape of a call, and the spec makes `Bytes()` an E0504 error form. A model that sees `Bytes(00ff0a)` in a panic text will try to paste it into code. Square brackets with spaced hex cannot be mistaken for code, and they cannot be mistaken for Str, List or Int.

- **Web, moving to V1c:**

  > aiml's E0504 point is right. `Bytes()` is a compile error in §3.2, so V1a prints text that looks like code and fails if a developer pastes it.

- **PLT, for C:**

  > Str and Char debug text is valid source (spec fact 3). C is the only Bytes form that keeps this law. It is also built only from existing parts, `Bytes.from_list` plus the List[U8] debug row. It needs no new notation and no `from_hex`.

- **Minimalism, moving to C:**

  > C adds no new notation and no exception to document. The spec already says debug text is source the lexer accepts (Str and Char). C keeps that rule true for Bytes, and it uses only existing API (`from_list`). H needs a new notation that a reader must learn, plus one spec line saying "Bytes is the exception". Fewer rules is the smaller answer.

- **DevOps, against C:**

  > For Bytes, C prints a call to `from_list` with a full decimal list, 4 to 5 chars per byte. In an assert_eq diff of two 64-byte buffers, a reader must compare decimal numbers by eye, and hex is the form every wire spec and hexdump uses.

- **Systems, against C:**

  > Hex is exactly 2n+7 chars, one pass.

All six ended round 1 with "STABLE, ready to vote".

#### Phase C — Silent ballot

The ballot had three options: A (`Bytes(6869)`), B (`Bytes[68 69]`) and C (`Bytes.from_list([104, 105])`).

| Seat | Vote | Second choice |
|------|------|---------------|
| Systems | A | C |
| DevOps | A | B |
| Web | B | A |
| AI/ML | B | A |
| PLT | C | A |
| Minimalism | C | B |

Result: A 2, B 2, C 2. No option had a majority, so the panel ran Phase D.

- **Systems (A):**

  > A writes exactly 2n+7 chars in one pass with no per-byte branch, so the sink can size the buffer from n. A is also tied to `to_hex()` by a one-line rule that a test can check.

- **DevOps (A):**

  > In a failing assert_eq, a trace or a CI log, A gives fixed-width hex that equals to_hex(), so a reader can paste it into xxd or a wire spec and find byte N at char 2N.

- **Web (B):**

  > `Bytes[68 69]` is clearly not code, so nobody pastes it and meets an E0504-style error from `Bytes()`.

- **AI/ML (B):**

  > `Bytes[68 69]` cannot be mistaken for code, a Str, a List or an Int.

- **PLT (C):**

  > C is the only option that keeps the law that debug text is valid source, which already holds for Str and Char.

- **Minimalism (C):**

  > C adds no new notation. It uses only `Bytes.from_list`, which exists, and it keeps the rule "debug output is valid source" true for Bytes, so the spec needs no exception clause.

#### Phase D — One focused round

Each seat read all six Phase C replies and answered once. Web and AI/ML moved from B to A. The other four kept their votes. The second choices were: B for Systems, DevOps, Web and AI/ML; A for PLT and Minimalism.

| Seat | Vote | Second choice |
|------|------|---------------|
| Systems | A | B |
| DevOps | A | B |
| Web | A | B |
| AI/ML | A | B |
| PLT | C | A |
| Minimalism | C | A |

Result: A 4, C 2. Option A wins.

- **AI/ML, B to A:**

  > sys and devops show that A has the smaller rule: `b.debug() == "Bytes(" + b.to_hex() + ")"`. It has one hex format, a test can check it, and a model can predict it without a second spacing rule. That was the risk I named in my own concern about B, and it weighs more for a model than the call-shape look-alike. The look-alike costs one spec line ("Bytes debug text is not source"), which sys, devops and plt already accept.

- **Web, B to A:**

  > aiml's concern decides it for me. A developer writes `assert_eq` expectations by hand, so a one-token form with no spaces (`Bytes(6869)`) is easier to type and compare than spaced hex, and it equals `to_hex()` with one wrapper, so there is a single hex format. The E0504 look-alike worry is real, but one doc line ("Bytes debug text is not source") answers it, and a tag on a hex string is not likely to be pasted as code.

- **DevOps:**

  > The E0504 look-alike point (aiml, plt, min) is real but small. Nobody reads debug text as source today: a panic or log line is read by eye, not parsed or pasted. Law "debug is valid source" holds for Str and Char because those literals exist; for Bytes there is no literal, so C keeps the law only by printing a long constructor call.

- **Systems:**

  > The source-validity law (plt, min) is the strongest case against A. But Sha256, which has Debug and no source form, already breaks the law, and the rule "debug rebuilds the value" has no force for a type with no literal.

  The spec text does not rest on this Sha256 claim. The spec does not give the debug text of `Sha256`, so it is not a precedent here.

##### Dissent

- **PLT (C):**

  > Three seats (sys, devops, plt) now say A needs a spec line that Bytes debug text does not rebuild the value. That is an exception clause to the debug-is-source law, and only C removes it. B has the same exception and also a second hex format next to `to_hex`. The size argument is the best case against C. But the panel already agreed that sinks cut, so C's extra length is a sink-policy cost and not a property of debug().

  Concern:
  > if the sinks (panic printer, assert_eq) do not cut, C's 4.5x text makes large-buffer failures hard to read.

- **Minimalism (C):**

  > Three seats (sys, devops, plt) name the E0504 look-alike as the main flaw of A. That flaw is the reason I hold C: it is the only option that needs no "this is not source" disclaimer in the spec. The length cost of C (4.5 chars per byte against 2) is real, but the panel already agreed that cuts happen at the sink, and a sink cut is one rule that applies to every type. A "Bytes is an exception" clause is a rule that applies to Bytes only.

  Concern:
  > if A wins, the spec must state that Bytes debug text does not rebuild the value, and `Bytes()` for empty bytes will keep looking like the E0504 form.

PLT and Minimalism both accept A as their second choice, so neither dissent blocks the text.

Concerns on the winning side, verbatim. Systems: "A's `Bytes()` and `Bytes(6869)` look like calls that §3.2 makes E0504, so the spec needs one line saying the text is not source." DevOps: "A's Bytes() looks like the E0504 form, so the spec must say in one line that Bytes debug text is not re-readable as source." The spec carries that line (the third bullet of *Bytes* in *Container Debug Rendering*).

### Final Spec

- §3.6.1 *Container Debug Rendering*: a `Bytes` row in the table (`"Bytes(" + b.to_hex() + ")"`, empty `"Bytes()"`), and a *Bytes* paragraph that states four rules and gives an example for the empty value, `"hi"`, `[0, 255, 10]`, a derived field, `List[Bytes]`, `Option[Bytes]` and a 1000-byte value. The rules: `debug()` never cuts; the text is the same on every path; the text is not source and does not rebuild the value; the text agrees with `Eq`.
- §3.6.1 *Debug agrees with Eq*: the statement stays. One sentence adds `Bytes` as a type that obeys it.
- §3.2.3 `Bytes`: one line that points at the `Bytes` row.
- §8.15.9: `Bytes` takes the Display-then-Debug chain, its `Debug` text is the `Bytes` row, and the 200-character cut applies to it.
