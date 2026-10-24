[< All Decisions](../DECISIONS.md)

# Grammar of Numeric Literals — Design Rationale

The spec had no grammar for `INT_LIT` or `FLOAT_LIT`. Examples used `0x0F`, `0xD800`, `1e-7` and `1.0e9`, and the
Float Text Form prints `1.0e16`. The lexer read `0xFF` as `0` followed by the name `xFF`, so this program failed with
`UndefinedVariable`:

```blink
fn main() {
  let a = 0xFF
  let b = 1_000
  io.println("{a} {b}")
}
```

The panel took three open questions together, because each asks what text the lexer accepts as a numeric literal:
whether hex, binary, octal and digit-separator integers exist, whether an exponent is part of `FLOAT_LIT`, and how
those forms meet the integer range rule (E0318) and the `parse_float` law.

## Summary

| Q | Question | Result | Vote |
|---|---|---|---|
| Q1 | Octal (`0o`) | A: `0o` is an integer base, with `0x` and `0b` | 5-1 (Minimalism dissent: B) |
| Q2 | Uppercase exponent mark `E` | A: `e` only; `1E5` is an error with a fix | 5-1 (Web dissent: B) |
| Q3 | `+` in the exponent | A: `-` only; `1e+5` is an error with a fix | 5-1 (Web dissent: B) |
| Q4 | `_` in the exponent digits | A: allowed between two digits, as in every digit run | 6-0 |
| Q5 | The `--seed` line in 06_tooling | Tie: A (sys, plt, min) against C (web, devops, aiml); the writer sets the wording | 3-3 after Phase D |
| Q6 | A sentence in the Float Text Form | A: every printed text, after the optional `-`, is a valid `FLOAT_LIT` | 6-0 |

Points all six seats stated by the end of Phase B, not balloted:

- Integer literals are decimal, `0x` hex and `0b` binary (Minimalism conceded `0b`). Prefixes are lowercase only;
  hex digits take either case.
- `_` stands only between two digits of one run and has no meaning.
- A decimal integer part of more than one digit may not start with `0`. `0`, `0.5` and `0e5` lex; `007` and `00.5`
  are errors.
- A float literal is `digits.digits` with an optional exponent, or `digits` with an exponent. `1e5` is a `Float`
  (Minimalism conceded). `.5` and `1.` are not literals; a `.` joins a literal only when a digit follows.
- A literal in any base is a value, never a bit pattern. E0318 is unchanged. There is no suffix and no hex float.
- The Literals law of §3.2.1 becomes: "The text of every Blink `Float` literal, with its `_` separators removed,
  parses with `parse_float` to the value of that literal. This law does not require the literal grammar to accept
  every text that `parse_float` accepts."
- A float literal that rounds to infinity is an error, `FloatLiteralOutOfRange`. Underflow rounds, with no error.
- A malformed form gives one error, `MalformedNumericLiteral`, with one message per cause. The lexer consumes the
  whole run and recovers with one token, so no `UndefinedVariable` follows.
- W0706: `Z` is "a FLOAT_LIT whose mantissa digits are all zero, with any exponent".
- `blink fmt` keeps the spelling as written.
- The grammar goes in a new "Numeric literals" subsection of §2.4. §3 links to it. Every spec example stays valid with
  no edit.
- Float-bits Q7 ("spec examples avoid literals at or above `0x8000000000000000`") no longer applies, because the
  integer literal range record makes such a literal valid under `U64`. The old record text stays.

### Compiler behavior before the decision

With the gen1 compiler, `0xFF`, `1_000`, `1.0e16` and `1e5` each lex as a number followed by a name (`xFF`, `_000`,
`e16`, `e5`) and give `UndefinedVariable`; `007` lexes as 7. No code in `lib/` or `tests/` uses a hex, binary, octal, `_` or
exponent literal outside comments.

## Panel Deliberation

The panel has six seats: sys (systems), web (web and scripting), plt (language theory), devops (DevOps and tooling),
aiml (AI and ML) and min (Minimalism).

#### Phase A — Independent proposals

Each seat wrote one proposal. Headlines, as the seats wrote them:

| Seat | Headline |
|---|---|
| sys | "C-shaped literals, minus every C trap". `0x`, `0b`, `0o`; leading zeros stay decimal; `e` or `E` and `+` or `-` in the exponent; `1e999` is an error |
| web | "the grammar a JS/Python/Rust dev already types, with the footguns shut". `DEC ::= "0" \| [1-9] ("_"? DIGIT)*`; `1e5` is a `Float`; suffixes and `007` are errors with a fix |
| plt | "one grammar, value-first, `_` is invisible". A `.` joins only when a digit follows; `FloatLiteralOutOfRange` for infinity; the Literals law gains "with its `_` separators removed" |
| devops | "Hex, binary, octal, `_` and exponent are literals; every near-miss gets one named error". One code family, `MalformedNumericLiteral`; the lexer consumes the whole `[0-9A-Za-z_.]` run |
| aiml | "one rule per feature, every form an LLM already writes, one spelling each". `DEC ::= "0" \| NZ ("_"? DIGIT)*`; `EXP ::= "e" "-"? DIGITS` |
| min | "hex and `_` for integers; exponent only after a fraction; no binary, no octal". `1e5` is not a literal, so the text alone tells `Int` from `Float` |

#### Phase B — Debate, round 1

The seats read all six proposals and replied once. The moderator's digest of the movement, which fixed the "Points all
six seats stated" list above:

- min conceded `0b` and conceded that `1e5` is a `Float`. min kept `0o` as a point it "will not block".
- sys, plt and devops moved from "leading zeros stay decimal" to the leading-zero error, because `010` reads as 8 to
  a C programmer.
- Seats split on `0o`, `E`, `+`, `_` in the exponent, the `--seed` line and the Float Text Form sentence. Those six
  items became Q1 to Q6.

#### Phase C — Final vote

Each seat voted alone and in writing. The votes below are verbatim.

##### Q1. Octal (`0o`)

Options: A, include `0o`. B, no octal.

**Result: A, 5-1 (Minimalism dissent).**

- **sys: A.** "`0o` costs one lexer branch and no run-time cost: the IR holds the exact value and the base leaves no trace in C. With leading zeros now an error, `0o` is the one spelling a C or Go user needs for a file mode, and the error hint can name it. A base added later breaks every tool that lexes Blink, so decide the set once." Concern: "A third rarely used base adds a row to every diagnostic table and every lexer test for a form that no lib/ or tests/ code uses today."
- **web: A.** "`0x`, `0b` and `0o` form one rule that a JS, Python or Rust dev already knows. With the leading-zero error in place, `0o755` is the only readable way to write a file mode, and the `0755` error hint points at it. A list with a gap makes users ask why." Concern: "`0o` has no use in the spec, lib/ or tests/, so it adds a lexer branch and a test row that nothing exercises."
- **plt: A.** "The range rule already says \"in every base that the literal grammar allows\". One digit-run shape per base keeps the value function and the E0318 check in one place. The leading-zero error that all six seats accepted names `0o` as the fix, so a missing `0o` leaves that message without a target." Concern: "A base that no code in the repo uses becomes permanent surface, because removing it later breaks every tool that lexes Blink."
- **devops: A.** "The leading-zero rule is an error that tells the user \"write `0o755`\". That hint needs `0o` to exist, or the error points at a form the language rejects. One rule for `0x`, `0b` and `0o` also gives one \"digit not valid in base N\" message for all three, so the diagnostic table has no gap." Concern: "`0o` has no use in the repo today, so the lexer and its tests carry a branch that nothing exercises."
- **aiml: A.** "A model learns one rule, \"`0x`, `0b`, `0o`\", with no gap to remember or to guess about. The leading-zero error needs a fix to name, and \"write `0o755`\" gives a model a one-turn repair. Adding a base later would split the training corpus into old code where `0o` is an error and new code where it is valid." Concern: "`0o` has no use in the spec, lib/ or tests/, so it adds a base that only file-mode code uses."
- **min: B.** "`0o` has no use in the spec, lib/ or tests/. It exists only for file modes, and Blink has no `chmod` literal need that `0x1ED` or a named constant cannot meet. Adding a base later is a pure addition and breaks nothing; cutting one later breaks code. The leading-zero error can name the plain decimal alone. I do not block if the panel keeps it." Concern: "With `0o` in, the next ticket will ask why `0o` has no lint, no `chmod` helper and no `fmt` rule, and the base set can never shrink."

##### Q2. Uppercase exponent mark `E`

Options: A, `e` only; `1E5` is an error with a fix. B, `e` or `E`.

**Result: A, 5-1 (Web dissent).**

- **sys: A.** "One spelling per value gives the same lexer path and the same text in every source file. It matches the lowercase-only prefix rule. `1E5` gets an error with a machine fix, so the cost is one edit." Concern: "A user who types `1E5` from habit gets an error where `parse_float` and most languages accept the text."
- **web: B.** "`parse_float` already takes `E`, and JS and Python devs type `1E5` and `2.5E-3` without thinking. A rejected literal that `parse_float` accepts is a \"just works\" failure. `fmt` keeps the spelling, so two spellings cost little." Concern: "Option A (lowercase only) gives each value one spelling, so the corpus is more uniform, and the diagnostic with a fix costs a user one edit."
- **plt: A.** "The Literals law is a subset law: it does not need the grammar to accept every `parse_float` text, so `parse_float` taking `E` is no argument. One spelling per value matches the lowercase prefixes, and `blink fmt` keeps spelling, so a second spelling stays in code for good. The error carries a machine fix." Concern: "JS and Python users type `1E5` and hit an error, which adds one lex-error turn for them."
- **devops: A.** "The prefix is lowercase only, so `E` lowercase only gives one rule for case. `blink fmt` keeps spelling and cannot fold `1E5` to `1e5`, so two spellings would stay in every codebase. `1E5` gets a message with a machine fix to `1e5`, so the cost to a user is one edit." Concern: "JS and Python users type `1E5` and meet an error, which makes one more support question."
- **aiml: A.** "One spelling per value keeps generated code uniform, and `blink fmt` keeps the spelling as written so it cannot normalize `E` later. It matches the lowercase-only prefixes. The error on `1E5` offers a fix, so a model repairs it in one turn." Concern: "JS and Python authors type `1E5` by habit, so they will meet the error often at first."
- **min: A.** "One spelling per value. Float Text Form never prints `E`, and the lowercase-only prefix rule already sets the pattern. The error carries a machine fix, so the cost to a JS or Python writer is one edit." Concern: "JS and Python users type `1E5` by reflex, and the error will meet them often at first."

##### Q3. `+` in the exponent

Options: A, `-` only; `1e+5` is an error with the hint "write `1e5`". B, `+` or `-`.

**Result: A, 5-1 (Web dissent).**

- **sys: A.** "`-` only matches the Float Text Form that Blink prints, so output and source use the same form. It removes one lexer branch and one spelling. `1e+5` gets the hint \"write `1e5`\"." Concern: "Python `repr` and C `printf` write `1e+16`, so users who paste such output into source will hit the error."
- **web: B.** "`1e+5` is what Python `repr`, C `printf` and JS output print for large floats. A user who pastes such output into source should get a literal, not an error. The lexer rule is one optional sign." Concern: "If A wins, a dev who copies `1e+16` from a Python log gets an error on valid-looking input, and the hint \"write `1e5`\" reads as pedantic."
- **plt: A.** "`-` only matches the Float Text Form at 03_types.md, which never prints `+`, so the literal grammar and the display grammar differ by nothing except `_`. The sign is part of the exponent rule, and a sign that carries no information is one more production to specify. The hint \"write `1e5`\" fixes it in one edit." Concern: "Python `repr` and C output write `1e+16`, so pasted text fails until the user removes the `+`."
- **devops: A.** "Float Text Form prints `-` only, so `-` only keeps the printed form and the literal form the same. `1e+5` gets the hint \"write `1e5`\", and the fix is mechanical. This matches the lowercase-only choice: one spelling per value." Concern: "Python `repr` writes `1e+16`, so pasted output fails to lex and the user needs the hint to recover."
- **aiml: A.** "`-` only matches Float Text Form, which never prints `+`, and it leaves one spelling per value. The hint \"write `1e5`\" names the fix exactly. I said in Phase B that I would not block `+`; I still prefer A." Concern: "Python `repr` writes `1e+16`, so models that copy printed floats will hit this error before they learn the rule."
- **min: A.** "`-` only matches Float Text Form, which never prints `+`. The hint \"write `1e5`\" is exact. Every extra spelling is a surface that fmt cannot normalize, because fmt keeps spelling." Concern: "Python `repr` writes `1e+16`, so pasted output fails to lex until the user reads the hint."

##### Q4. `_` inside the exponent digits

Options: A, allowed between two digits, as in every digit run; `1e_5` is an error. B, not allowed in the exponent.

**Result: A, 6-0.**

- **sys: A.** "One rule for every digit run (`_` only between two digits) is one lexer routine, reused for mantissa, fraction and exponent. A carve-out for the exponent adds a second routine and a second rule to the spec. The `_` leaves no trace in the generated C." Concern: "`1e1_0` is legal and helps no reader, so style drifts and nothing flags it."
- **web: A.** "One digit-run rule everywhere is easier to teach than a rule with an exception. `1e_5` stays an error, as in every other run." Concern: "If B wins, the grammar has a second digit-run shape for a case (`1e1_0`) that nobody writes."
- **plt: A.** "One rule for every digit run, \"`_` only between two digits of one run\", is the compositional choice. Excluding the exponent adds a second run rule and a second error cause for no soundness gain. `1e_5` stays an error under the shared rule." Concern: "`1e1_0` is legal and helps no reader, so a style lint may be wanted later."
- **devops: A.** "One digit-run rule everywhere gives one message, \"`_` must sit between two digits\", and the lexer needs no special case for the exponent. A second rule for the exponent would need a second message and a second test row." Concern: "`1e1_0` is legal and helps no reader, so a style lint may be needed later."
- **aiml: A.** "One rule for every digit run, \"`_` only between two digits\", is fewer decision points than a rule with an exponent exception. A model need not remember where `_` stops being legal. `1e_5` stays an error under the same rule." Concern: "`1e1_0` helps no reader, so the rule allows a form no one will write."
- **min: A.** "I argued `1e1_0` helps no reader, and I still think so. But a rule \"every digit run takes `_` between digits, except this one\" is a second rule, and an exception adds more surface than the uniform shape does. I yield to the single `DIGITS` form." Concern: "The grammar now accepts `1e1_0`, a form no one will write, and a later style lint may want to forbid it."

##### Q5. The `--seed` line (06_tooling.md, §8.10.4)

Text today: "The `--seed` flag accepts either a `0x`-prefixed hex literal or a decimal integer."

Options: A, no change. B, add: "The `--seed` value follows the integer literal grammar of §2.x, so `0x1234` and `1_000` both work." C, add the parenthetical "(CLI flag, parsed by the CLI, not the language)".

Phase C result: A 3 (sys, plt, min), B 1 (web), C 2 (devops, aiml). The Phase D result follows below.

- **sys: A.** "The line states CLI behavior, and the language grammar does not govern it. Binding the CLI to the literal grammar in spec text fixes an implementation choice (a shared lexer routine) that the spec should not state. Today the line says `0x`-prefixed hex or decimal, and that stays true." Concern: "The line does not say whether `--seed 1_000` works, so the CLI and the lexer can drift apart."
- **web: B.** "A user who reads \"`0x`-prefixed hex literal or decimal integer\" will try `1_000` and `0x1234` next. One sentence tells them both work, and it ties the flag to one grammar. This only holds if the CLI reuses the lexer routine; if it does not, C is the safe wording." Concern: "If the CLI parses the seed by a separate routine, B makes the spec promise a behavior that can drift from the language rule."
- **plt: A.** "The line describes a CLI flag, not the language. Option B states a coupling to the integer literal grammar that is true only while the CLI reuses the lexer routine, which is an implementation fact and does not belong in sections/. Option C adds words the line does not need." Concern: "The CLI may accept `0x1234` and `1_000` differently from the language, with no spec text to say which is right."
- **devops: C.** "I checked src/cli*.bl: no `--seed` parser exists, so no code reuses the lexer routine. My condition for B is not met. Without B, aiml's parenthetical stops a reader from taking `0x1234` there as proof that the language grammar governs the flag." Concern: "The CLI parser, when written, may accept forms that differ from the language grammar, and the parenthetical then hides the drift."
- **aiml: C.** "The sentence says \"0x-prefixed hex literal\" in a section where \"literal\" now has a formal grammar. A model that reads both will ask whether `--seed 1_000` or `0b101` works. The parenthetical says the CLI flag is outside the language grammar, so the model does not infer a shared rule that may not exist. Option B is only right if the CLI reuses the lexer routine, and the ballot does not say it does." Concern: "If the CLI later reuses the lexer routine, the parenthetical goes stale and needs an edit."
- **min: A.** "The line is CLI text, not language text. The spec states the language rule, not what the CLI shares with the lexer. Adding a sentence about the CLI parser ties the spec to an implementation fact that may change. No change costs nothing." Concern: "A user may wonder if `--seed 1_000` works, and the spec will not say."

##### Q6. Float Text Form sentence (§3.6)

Options: A, add "Every such text is a valid FLOAT_LIT." B, add nothing.

**Result: A, 6-0.** plt's Phase C vote asks that the final text say "after the optional `-`", because the pattern starts with `-?` and `-` is the unary operator, not part of a `FLOAT_LIT`. The other five seats' votes do not conflict with this wording, and the final spec uses it.

- **sys: A.** "The sentence \"Every such text is a valid FLOAT_LIT.\" states a round-trip property: printed output lexes back. It costs one line and a test can check it. The new grammar makes the sentence true." Concern: "If a later change widens the printed form (for example a `+` in the exponent), the sentence turns false without a compile error to warn the author."
- **web: A.** "A dev who copies printed output (`1.0e16`) back into source expects it to work. One sentence states that guarantee, and it costs nothing." Concern: "If the lexer grammar and the Float Text Form drift later, the sentence becomes a false law, so a corpus test of print-then-lex must back it."
- **plt: A.** "The sentence is a checkable theorem: every finite output has digits with no leading zero beyond a lone `0`, one `.`, and an optional `e` with `-`, so it lexes under the new grammar. It links the display grammar to the literal grammar and gives the Literals law a converse for output text. The wording must exclude the sign, since `-` is the unary operator and not part of a FLOAT_LIT." Concern: "As quoted (\"Every such text is a valid FLOAT_LIT\") the sentence is false for the leading `-?` of the pattern, so the final text must say \"after the optional `-`\"."
- **devops: A.** "The sentence states the round trip: printed text lexes back. A tool author, for example a code generator or a golden-file test, can rely on it without reading the grammar. It costs one line, and the corpus can test it." Concern: "The sentence is a new promise, and any later change to the grammar or to float printing must keep it true."
- **aiml: A.** "The sentence tells a model that every printed float is valid source, so it can paste output into code without a check. It costs one line and states a property of the spec that holds with this grammar." Concern: "If a later change adds a printed form that the lexer rejects, the sentence becomes false and needs a test to guard it."
- **min: A.** "One sentence turns the round-trip fact into a stated rule: printed output is valid source. It costs nothing and gives the Literals law a converse for this form. It also guards against a later edit that makes the printer and the lexer disagree." Concern: "The sentence becomes a spec promise, so any future change to the print format must also change the literal grammar."

#### Phase D — Focused round on Q5

Q5 split 3-1-2 in Phase C. The seats read all six Phase C votes and each answered the strongest argument against their
own vote. The replies below are verbatim, with `[...]` where a passage is cut.

- **sys (A, kept).** "The collision in the word \"literal\" is real, but it is a small flaw. Option C answers it with a parenthetical that names an implementation fact (\"parsed by the CLI\"). The spec then carries a claim that goes stale the day the CLI reuses the lexer. Option A leaves the old sentence, which stays true: the flag takes a `0x` hex value or a decimal integer, and it says no more. If the sentence misleads a reader, the better fix is to reword \"literal\" to \"value\" in a later chore. That fix needs no vote, because it changes no rule. Option B is now out for me. It is false today. [...] If A loses, C is my second choice."
- **web (B to C).** "B would make the spec promise that `1_000` and `0x1234` work in a place where no code backs the promise. The project rule is that spec text states the language rule, not an implementation choice, so B is the wrong text for this line. [...] aiml's point stands. The line says \"hex literal\" in a section where \"literal\" now has a formal grammar. [...] I change my Q5 vote from B to C. C keeps the user from taking the language grammar as the rule for the flag. It adds no coupling that can drift." Remaining concern: "With C, a user who types `--seed 1_000` still gets no answer from the spec, and the CLI behavior should be set by its own ticket."
- **plt (A, kept).** "The sentence does not leave that open. It names two accepted forms: a `0x`-prefixed hex literal, or a decimal integer. By the rule that a list states the whole set, `0b101` and `1_000` are not in it. The line sits in a CLI flag description, under tooling, and a flag description defines the flag's own input. A language grammar defines program text, not command-line text. So the line is already self-contained and needs no scope note. [...] Option B is the one I oppose: [...] B would state something false. [...] A stays. If A loses to C, I accept C stripped to \"(a CLI flag, not language syntax)\", with no claim about who parses it."
- **devops (C, kept).** "It does cost one thing: the line uses the word \"literal\" (\"`0x`-prefixed hex literal\"), and after this decision \"literal\" names a formal grammar. A reader, human or model, will take the line as a cross-reference and try `--seed 1_000` or `0b101`. Under A the spec does not say. Under C it says the flag is outside the language grammar, and the same words stay true if the CLI later reuses the lexer. [...] The stale risk of A is larger: a spec line that reads as a promise the CLI never made. [...] I keep C. I accept A as second choice; I do not support B."
- **aiml (C, kept).** "C does not answer that question. C answers a different one: which grammar governs the flag. Today the sentence calls `0x...` a \"literal\" in a spec where \"literal\" now has a formal grammar. A model that reads both will infer that the flag follows the language grammar, and will try `0b101` and `1_000`. [...] C does not state an implementation fact. It states a scope fact: the language grammar does not govern this flag. [...] I keep C. If the panel picks A, I accept it."
- **min (A, kept).** "B is out for the reason plt gives: it states an implementation coupling that does not exist. The gap in C is smaller than C's fix. The line says what the flag takes: a `0x` hex number or a decimal. It does not claim the flag takes every form of the grammar [...]. A fix that may need its own fix is not a subtraction. If the panel wants the ambiguity closed, C is the only wording I accept, because it makes no claim about code. But I do not think the ambiguity earns an edit. Vote: unchanged, A."

Moves: web B to C. No other seat moved. All six seats rejected B by the end of Phase D.

##### Phase D2 ballot, Q5 only

The seats voted alone. The votes below are verbatim.

- **sys: A.** "The line lists the two forms the flag takes, a `0x` hex value or a decimal integer, and a list states the whole set, so `0b101` and `1_000` are already out. The language grammar defines program text, not command-line text, and nothing in src/cli*.bl links the two. The word \"literal\" is a small flaw; a later chore can change it to \"value\" with no vote, because that change adds no rule. Option C would put a claim about who parses the flag into sections/, and that claim can go stale." Concern: "If C wins on a tie-break, the spec carries a scope note that the CLI owner must edit the day the flag reuses the lexer routine, and the line still does not say whether `--seed 1_000` works."
- **web: C.** "The line says \"`0x`-prefixed hex literal\" in a spec where \"literal\" now names a formal grammar. A JS or Python dev who reads both will try `--seed 1_000` and `0b101` next, and will assume the language rule applies. The parenthetical tells them the flag is outside the language grammar, so they read the line as written and do not extend it. B is out: devops found no `--seed` parser in src/cli*.bl, so B would promise behavior that no code backs. Plt and sys accept C as a harmless second choice, so C costs the panel little." Concern: "With C, a user who types `--seed 1_000` still gets no answer from the spec, and the CLI can drift from the lexer until its own ticket sets the behavior."
- **plt: A.** "The line lists two accepted inputs, a `0x`-prefixed hex number and a decimal integer. A list of accepted forms states the whole set, so `0b101` and `1_000` are not in it, and a flag description defines the flag's own input, not program text. Option B is false today, because no `--seed` parser reuses the lexer routine (devops, D1), and all six seats now reject it. Option C states a true scope fact but adds words to a line that is already self-contained, and its \"parsed by the CLI\" form can go stale." Concern: "If C wins, the parenthetical goes stale the day the CLI reuses the lexer routine, and the spec still does not say whether `--seed 1_000` works."
- **devops: C.** "The line calls `0x...` a \"literal\" in a spec where \"literal\" now names a formal grammar, so a reader or a model will try `1_000` or `0b101` and expect them to work. No `--seed` parser exists in src/cli*.bl, so nothing reuses the lexer routine and B would promise behavior that no code backs. The parenthetical says which grammar does not govern the flag, makes no claim about who parses it, and the person who writes the `--seed` parser can then give it its own diagnostic that names the flag, not \"malformed numeric literal\"." Concern: "If A wins, the spec line reads as a cross-reference to the literal grammar, and the future `--seed` parser will either accept forms the line never promised or reject forms a reader expects, with no spec text to settle it."
- **aiml: C.** "After this decision, \"literal\" names a formal grammar in 02_syntax.md. A model that reads \"`0x`-prefixed hex literal\" in the CLI section will take it as a cross-reference and try `1_000` or `0b101`. The parenthetical states that the flag is outside the language grammar, so the model reads the line as written and does not extend it. No `--seed` parser exists, so B would state something false. D1 shows C is second choice for sys, plt and min, so it is the option with the widest support. plt's stripped wording, \"(a CLI flag, not language syntax)\", also meets my goal, and I accept it." Concern: "If the CLI later reuses the lexer routine, the parenthetical goes stale, so the change that adds the `--seed` parser must edit that line."
- **min: A.** "The line at 06_tooling.md:1381 is CLI text and it is true as written: the flag takes a `0x` hex number or a decimal integer, and a list that names its forms excludes the rest. A flag description defines the flag's own input, so the language grammar does not govern it. The word \"literal\" in that line may cause a wrong guess, but a user who tries `--seed 1_000` gets the CLI's own error. The cheapest fix is to change \"literal\" to \"value\" in a later chore, which needs no vote (sys makes the same point). Adding a parenthetical to a correct line adds words that go stale if the CLI later reuses the lexer. A fix that may need its own fix is not a subtraction." Concern: "If C wins, the spec carries a scope note that the CLI owner must edit when the `--seed` parser is built, and a note that hedges about who parses the flag will drift from what the code does."

**Result: A 3 (sys, plt, min), C 3 (web, devops, aiml). Tie, 3-3.**

**Tiebreak.** The wording of the line went to the writer. The constraints were: the line must not read as a
cross-reference to the literal grammar; it must not claim a parser that does not exist; it should list its inputs
with an example. Changing "literal" to "value" is the fix that sys and min named as costless, and it removes the
cross-reference that aiml and devops feared. The line now reads: "The `--seed` flag accepts either a `0x`-prefixed hex
value or a decimal integer, for example `--seed 0x2A` or `--seed 42`." It adds no parenthetical and no claim about
who parses the flag. The line still does not say whether `--seed 1_000` works; seats on both sides named that gap, and
the CLI owner sets it.

### Dissents

Each dissent is in the dissenting seat's own words, from the Phase C votes above.

- **Q1, min (B):** "`0o` has no use in the spec, lib/ or tests/. It exists only for file modes, [...] Adding a base later is a pure addition and breaks nothing; cutting one later breaks code. [...] I do not block if the panel keeps it."
- **Q2, web (B):** "`parse_float` already takes `E`, and JS and Python devs type `1E5` and `2.5E-3` without thinking. A rejected literal that `parse_float` accepts is a \"just works\" failure."
- **Q3, web (B):** "`1e+5` is what Python `repr`, C `printf` and JS output print for large floats. A user who pastes such output into source should get a literal, not an error."

### Reading gaps

Points where the ruling did not settle the text, and how the writer read them:

- The brief's malformed run is "the `[0-9A-Za-z_.]` run that starts with a digit". Read as written, that run would
  swallow the `..` of `1..3`, the `.0` of `t.0` and the `.max` of `1.max(2)`. The spec says a `.` joins the run only
  when a digit follows, and that the sign of an exponent joins a decimal run only after `e` with a digit after it. So
  `1..3`, `t.0` and `1.max(2)` read as before.
- The ruling names the error `FloatLiteralOutOfRange` and does not say which phase finds it. The text alone decides
  it, so the spec makes it a lexer error.
- The ruling names no code numbers. The spec uses E1137 for `MalformedNumericLiteral` and E1138 for
  `FloatLiteralOutOfRange`.
- Q5 ended 3-3. The wording follows the Tiebreak above.

### Final Spec

- §2.4.4 *Numeric Literals* defines `INT_LIT` and `FLOAT_LIT`:

```
INT_LIT   = DEC | "0x" HEX | "0b" BIN | "0o" OCT
DEC       = "0" | NZ ( "_"? DIGIT )*
FLOAT_LIT = DEC "." DIGITS EXP? | DEC EXP
EXP       = "e" "-"? DIGITS
DIGITS    = DIGIT ( "_"? DIGIT )*
```

```blink
let mask = 0x0F       // Int, value 15
let mode = 0o755      // Int, value 493
let big = 1_000_000   // Int
let tiny = 1e-7       // Float
let bad = 0755        // error[MalformedNumericLiteral] (E1137): leading zero
```

- A literal is a value, never a bit pattern. E0318 is unchanged. There is no suffix and no hex float.
- `MalformedNumericLiteral` (E1137, Lexer) covers every malformed text, with one message per cause and one-token
  recovery. The fixes for an uppercase prefix, `E` and `+` are machine-applicable.
- `FloatLiteralOutOfRange` (E1138, Lexer) covers a `Float` literal that rounds to infinity. Underflow rounds.
- §3.2.1 *Literals* law: the text of every `Float` literal, with its `_` separators removed, parses with `parse_float`
  to the value of that literal.
- §3.2 *Literal syntax* and *Integer literal range* link to §2.4.4.
- W0706 (§3.6): `Z` is a `FLOAT_LIT` whose mantissa digits are all zero, with any exponent.
- §3.6 *Float Text Form*: after the optional `-`, every such text is a valid `FLOAT_LIT`.
- §8.10.4: the `--seed` line says "value" and gives `--seed 0x2A` and `--seed 42` as examples.
- `blink fmt` keeps the spelling of a literal.
- ERROR_CATALOG.md has a row for E1137 and a row for E1138.


