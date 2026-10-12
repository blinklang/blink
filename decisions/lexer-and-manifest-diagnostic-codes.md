[< All Decisions](../DECISIONS.md)

# Lexer Error and Manifest Warning Codes — Design Rationale

The lexer reports some errors as bare `lexer error:` lines with no code and no span. These are
the malformed escapes in the Unicode Escapes table, an unknown escape such as `"\q"`, a char
literal that is empty, has more than one character, or ends at the end of the file, and a string
that ends after a backslash. The `blink.toml` loader also prints some warnings with no code: an
unknown `[lints]` level and an unknown top-level section. Because they have no code and no span,
a daemon check loses them, `check --json` gives no row for them, the LSP never shows them, and
`[lints]` and `--strict` cannot reach them. The spec already requires a code for each lexer case
("Each error kind has its own registered code in the syntax diagnostic family"), but none is
registered.

The panel answered 13 questions:

- **Q1.** `\x..` (for example `\x1b`). A: its own code, HexEscapeNotSupported. B: part of
  UnknownEscape.
- **Q2.** `''` and `'ab'`. A: two codes, EmptyCharLiteral + MultiCharLiteral. B: two codes,
  EmptyCharLiteral + MultiCharCharLiteral. C: one code, CharLiteralLength (help line differs by
  case).
- **Q3.** `"\0"` in a `Str`. A: NulInStr (same code as `"\u{0}"`). B: UnknownEscape.
- **Q4.** Unterminated literals. A: one code, UnterminatedLiteral, for every unclosed char, string
  and raw-string literal; the help names the closer to write. B: two codes, UnterminatedCharLiteral
  + UnterminatedStringLiteral (the string code covers every unclosed `"..."` and `#"..."#`).
- **Q5.** Span for an unterminated literal. A: primary span on the opening quote, plus a `note:` at
  EOF. B: span from the opening quote to EOF.
- **Q6.** Unknown top-level section in `blink.toml` (for example `[bogus]`). A: warning W1001
  UnknownManifestSection (promotable by `--strict` and `[lints]`; the help offers a did-you-mean).
  B: error E1017 UnknownManifestSection.
- **Q7.** E1200 ModuleNotFound note. When W1001 fired in the same build, E1200 adds a `note:` that
  points at the unknown section. A: yes, specify it. B: no.
- **Q8.** Unknown `[lints]` level (for example `W0703 = "loud"`). A: error E0843 InvalidLintLevel;
  no `@allow`, `[lints]` entry or `--strict` can change it. B: a warning.
- **Q9.** Manifest span rule and fallback. All proposals share the base rule: a manifest
  diagnostic carries a blink.toml line and column; the span is the value token (quotes included)
  for a value fault, the key for a key fault, the `[header]` for a section fault; manifest.bl
  returns a `ManifestIssueKind` enum and the compiler maps kind to code. A: the spec states the
  base rule only; the TOML reader must record positions, and the spec has no fallback. B: the spec
  also states a fallback: the enclosing section header line (line 1, column 1 if there is no
  header).
- **Q10.** Lexer recovery and suppression. A: emit the token (bad escape dropped / bad char
  becomes U+FFFD), keep lexing, report every error, exit non-zero; no `@allow`, `[lints]` entry or
  `--strict` can suppress or demote a lexer error. B: A, plus the spec says recovery must not
  cause a follow-on diagnostic.
- **Q11.** Help text for UnknownEscape in the spec. A: the spec says only that the help line shows
  the fix (the valid escapes for that literal kind); targeted helps are implementation and
  `blink explain` guidance. B: the spec also states the rule for targeted help (where the escape
  has a known meaning in another language, the help gives the Blink fix first); exact wording
  stays with the implementation.
- **Q12.** Name for `\u{12g}`. A: InvalidUnicodeEscapeDigit. B: InvalidHexDigit.
- **Q13.** Name for `\u0041` / `\U0001F600`. A: UnicodeEscapeNeedsBraces. B:
  UnbracedUnicodeEscape.

Names with no contest: EmptyUnicodeEscape, UnicodeEscapeTooLong, UnterminatedUnicodeEscape,
SurrogateEscape, UnicodeEscapeOutOfRange, NulInStr, UnknownEscape, InvalidLintLevel.

Two earlier decisions bound the panel. The Unicode Escapes decision gave each malformed `\u`
escape its own registered E11xx code. The Unknown Diagnostic Names decision made E0842 and E0837
errors that nothing suppresses, because a suppression that silently fails to apply is as bad as
one that silently succeeds.

**A note on quotation.** Panelist text below is verbatim. Where a quotation is shortened, an
ellipsis marks the cut. Phase A and Phase B give excerpts. Phase C and Phase D give each
panelist's ballot text in full. No panelist text was reworded.

---

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated
in independent-proposal → debate → vote rounds. Phase A produced six proposals. Phase B ran one
round, after which all six marked "STABLE — ready to vote". Phase C was a silent vote on Q1 to
Q13. Q1, Q3, Q5, Q6, Q8, Q9 and Q12 passed 6-0; Q7, Q10 and Q13 passed 5-1. Q2 (4-1-1), Q4 (3-3)
and Q11 (4-2) went to Phase D, which ran one debate round and a final vote. The user signed off
on the result.

#### Phase A — Independent proposals

- **Systems:** "Line 148 says "each error kind has its own registered code", and that rule binds
  us. Each row of the escape table therefore gets its own code." On unknown escapes: "**E1123
  UnknownEscape is an error, not a warning.** Today `"a\qb"` compiles to `a\b` and exits 0. That
  is silent miscompilation: the bytes in the binary differ from what the author wrote." On char
  literals: "**`''` and `'ab'` get separate codes.** The fixes differ: `''` has nothing to fix
  toward, but `'ab'` almost always means `"ab"`." On the unknown section: "I chose a warning over
  an error because of §8.9.7 (forward compatibility)."
- **Web/Scripting:** "My test for every code here: a JS or Python developer reads the first line
  and the `help:` line and fixes the problem without opening docs. A code should name the mistake
  the user made, not the lexer state the compiler was in when it noticed." On `\d`: "E1123 is the
  most important code in this ticket. People who come from Python or JS will hit it on their first
  day, because they write regexes:" On severity: "The distinction is easy to teach: anything that
  would silently change what the compiler enforces is an error, and anything that is only
  unrecognised is a warning."
- **PLT:** "**The rule I apply.** A diagnostic code names the rule that the source broke. It does
  not name the message, and it does not name the place in the lexer where the error is found." …
  "Two sites share a code only if they break the same rule and lead to the same fix (§3.1
  convergence)." On `"\0"`: "**`"\0"` in a `Str` is E1122, not E1123.** The only fix for it is
  the NulInStr fix ("use `Bytes`")." On the unknown section (first choice, an error): "A typo such
  as `[lint]` drops every override silently. If those overrides set lints to `"error"`, the build
  passes when it should fail. That is a silent success."
- **DevOps:** "I judge this by one test: does each diagnostic produce one `--json` row, one LSP
  squiggle on the right bytes, one `blink explain` page, and a clear answer to "can `[lints]` or
  `--strict` touch it?"" On spans: "**EOF spans point at the opening quote, not at EOF.** This
  follows rustc. A span to EOF paints the rest of the file red in the editor, so add a `note:` at
  EOF instead." On the unknown section: "**Why a warning:** §8.9.7 promises a forward-compatible
  schema. A manifest written for a newer compiler must still build on an older one, and an error
  here would break that promise."
- **AI/ML:** "An AI learns a diagnostic's meaning from its name and its first `help:` line, not
  from its number. So each code should map to one repair." On char literals: "**`'ab'` and `''`
  are separate codes.** Models trained on Python and JS write `'hello'` all the time." On the
  unknown section: "**Add-on:** when W1020 fired in the same build, E1200 adds a note that points
  at the W1020 site. Then the error the model sees first leads it to the fix."
- **Minimalism:** "I'm the Minimalism panelist, so I count catalog names: each one is permanent
  API." On the sharing rule: "I read a kind as **one distinct repair**. When two messages lead to
  the same fix, they share a code, and the `help:` line carries the detail." On `\x`: "**E1122
  covers both `\x` and `\q`.** `\x` is not a malformed known escape. It is an escape letter Blink
  lacks, just like `\q`." On the unknown section: "I named it `Entry`, not `Section`, so a later
  check for unknown keys inside known sections can reuse it with no second code."

All six agreed on a core: every lexer case in the ticket is an error that goes through
`diag_error_range` with a code from E1114 up; UnknownEscape is one code for both literal kinds;
the two char-literal EOF sites share one code; an unknown `[lints]` level is E0843 InvalidLintLevel,
an error that nothing suppresses; and manifest diagnostics carry a blink.toml file, line and column
and go through the normal `Diag` path.

#### Phase B — Debate highlights

Round 1 listed ten open points (P1 to P10). The positions below moved or hardened. All six ended
the round with "STABLE — ready to vote".

**P1, `\x..`.** Min moved to its own code. Min: "The spec table already publishes `\x1b` as its own
row, and Q7 (6-0) says one code per error. My "one repair" reading does not override a published
row." AI/ML gave the fix argument: "For `\x1b` the fix keeps the value and changes the spelling:
write `\u{1b}`. The help can give the exact replacement."

**P2, `''` and `'ab'`.** Web and PLT moved to two codes. Web: "JS and Python developers write
`'hello'` all the time, and the fix is "use double quotes". That is a different fix from the empty
literal, so it should be a different `blink explain` page and a different code that tools can match
on." PLT: "AI/ML and Sys used my own test against me, and they are right." Min held one code,
weakly.

**P3, `"\0"` in a `Str`.** Sys, Web and Min joined PLT, DevOps and AI/ML. Sys: "PLT is right. If
`"\0"` fell under UnknownEscape, its help would list valid escapes, and none of them fixes the
problem."

**P4, unterminated literals.** The moderator fact was that a plain unclosed string is E1100 at EOF
today. Min: "Given the moderator fact (a plain unclosed `"..."` is E1100 at EOF today), the lexer
must now own every unclosed `"..."`, not only backslash-then-EOF." PLT and AI/ML moved to Min's one
code; Sys, Web and DevOps kept two. Sys: "An LSP quick fix inserts `'` for one and `"` for the
other, and a code is the stable key that a tool can match on, while message text is not."

**P5, span for EOF errors.** The panel took DevOps's rule. Sys moved to it: "A span that
runs to EOF has no upper bound. The LSP sends it in every publish, and the editor paints the rest
of the file."

**P6, unknown section.** PLT withdrew its error. PLT: "My case for an error rested on an edition
check that does not exist, and the moderator's fact removes it." and "Without edition gating, an
error makes the schema closed with no way to grow." Min dropped the wide name: "I drop the wide
name `Entry`. A narrow, true name today beats a wide name for a check nobody has decided on."
AI/ML dropped W1020: "I drop W1020 because W1001 sits next to W1000."

**P7, manifest span fallback.** AI/ML moved to Sys's plumbing: "I also take Sys's
`ManifestIssueKind` enum, which the compiler maps to a code. A second list of code strings could
drift from the registry." Web: "A spec fallback to 1:1 would become the permanent behaviour."

**P8, recovery and suppression.** All agreed. AI/ML added the no-cascade rule that became Q10 B:
"recovery must not cause a cascade. A dropped escape or a U+FFFD char must not then cause a type
error."

**P10, names.** AI/ML, DevOps and PLT moved to InvalidUnicodeEscapeDigit, the name Sys and Min already held. Sys gave the reason: "The spec has
hex integer literals (`flags: 0x40`, sections/07:1283). A later `0x1g` lexer error would also be an
"invalid hex digit". Names are frozen once published."

---

#### Phase C — Final vote

##### Q1: `\x..` (**A 6-0**)

Options: A, its own code, HexEscapeNotSupported. B, part of UnknownEscape.

- **Systems:** A — "The spec table gives `\x1b` its own row and its own help line, and line 148
  gives each kind its own code. `\x` has an exact mechanical fix (`\x1b` becomes `\u{1b}`), which a
  tool can apply only if it can match on a stable code. UnknownEscape has no such fix." *Concern:*
  "A later `\x` story (for example, byte escapes in a future `Bytes` literal) would make this name a
  misnomer, and names are frozen."
- **Web/Scripting:** A — "`\x1b[31m` ANSI colour codes are pasted from Stack Overflow by every
  Python, JS and C developer. The fix is a mechanical rewrite to `\u{1b}`, not a guess like the fix
  for `\q`. The spec table already gives this case its own row." *Concern:* "none of weight. If the
  implementation reuses UnknownEscape's help text, the dedicated code adds nothing, so its help line
  must show the rewritten escape."
- **PLT:** A — "The Unicode Escapes decision (Q7) gives each table row its own code, and `\x1b` is a
  row. The fix is also different from `\q`'s: the help can compute `\u{1b}` from the source, and no
  fix can be computed for `\q`. A different fix means a different code." *Concern:* "People may read
  the name as a promise that `\x` will be supported later. Help and `blink explain` must say that
  `\u{..}` is the only numeric escape."
- **DevOps:** A — "The spec table gives `\x1b` its own row, and the binding decision says one code
  per row. The fix (`\xHH` → `\u{HH}`) is mechanical, so an LSP code action can apply it with no
  guessing. Code actions key on the code, and `\q` has no such fix." *Concern:* "Someone may later
  want `\e` → `\u{1b}` to get the same quick-fix, and pressure to add a code per foreign escape
  follows. UnknownEscape's targeted help must absorb those cases instead."
- **AI/ML:** A — "The fix for `\x1b` keeps the value and gives one exact edit, `\u{1b}`. The fix for
  `\q` is "choose a different escape", which is a different repair. With its own code, a model
  applies the edit at once and does not search a list of escapes. The spec table already gives `\x`
  its own row." *Concern:* "Other C escapes (`\e`, `\a`) then go under UnknownEscape, so they get
  their `\u{..}` fix only from help text and not from a name."
- **Minimalism:** A — "the spec table already lists `\x1b` as its own row, and Q7 (6-0) gives each
  listed error its own code. I conceded this in Phase B, and the published table outranks my "one
  repair" reading." *Concern:* "other panelists may treat this as precedent for a code per
  foreign-language escape letter (`\e`, `\a`, `\v`). Those must stay under UnknownEscape."

##### Q2: `''` and `'ab'` (**A 4-1-1**)

Options: A, two codes, EmptyCharLiteral + MultiCharLiteral. B, two codes, EmptyCharLiteral +
MultiCharCharLiteral. C, one code, CharLiteralLength.

- **Systems:** A — "Two different fixes need two codes under §3.1: `''` has no fix to point at, and
  `'ab'` means `"ab"`. The lexer needs the same look-ahead either way, so the split costs nothing.
  MultiCharLiteral is the shorter name and still clear in context." *Concern:* "The look-ahead for
  `'ab'` must stop at end of line, or an unclosed `'` that runs across lines turns into a confusing
  MultiCharLiteral."
- **Web/Scripting:** A — "JS and Python developers write `'hello'` all the time, and the fix is "use
  double quotes". That is a different fix from the one for `''`, so it needs a different `blink
  explain` page. MultiCharLiteral reads more cleanly than the stutter "CharChar"." *Concern:* "the
  MultiCharLiteral help line must actually show `"hello"`, not only say "one character". Otherwise
  the split buys nothing."
- **PLT:** A — "These are two ways to break one sentence, and each has its own fix. `''` needs a
  char written in, and `'ab'` nearly always means `"ab"`. MultiCharLiteral is shorter, and it still
  says what is wrong." *Concern:* "`'ab'` inside a match pattern or other non-expression places may
  need context-sensitive help. The code is right, but the help may be weak."
- **DevOps:** A — "`'ab'` → `"ab"` is a machine-applicable fix, and `''` has none. A `--json`
  consumer or LSP quick-fix keyed on the code must not offer "use double quotes" for `''`.
  MultiCharLiteral is the shorter name and reads the same as the B name." *Concern:* "If C wins, the
  implementation must not attach the double-quote fix to the shared code without checking the case."
- **AI/ML:** B *(dissent)* — "The Python/JS habit `'hello'` needs the fix "use double quotes", and
  the name should state that case. The name MultiCharLiteral could also describe a string, which is
  legal, so a model could read it the wrong way. MultiCharCharLiteral is clumsy, but it is exact."
  *Concern:* "The doubled "Char" may get "corrected" to MultiCharLiteral in docs or in model output,
  which gives `@allow`/`explain` lookups a near-miss name."
- **Minimalism:** C *(dissent)* — "one rule ("exactly one scalar value") and one repair in most
  cases ("use a `Str`": `''` → `""`, `'ab'` → `"ab"`). The help line can differ by case, so two
  frozen names buy nothing a help line cannot give." *Concern:* "if A wins, `EmptyCharLiteral` names
  a case where the fix is often `' '` or `'\''`, so its help must not assume `""`."

##### Q3: `"\0"` in a `Str` (**A 6-0**)

Options: A, NulInStr (same code as `"\u{0}"`). B, UnknownEscape.

- **Systems:** A — "The fix is "use `Bytes`". UnknownEscape's list of valid escapes holds no fix for
  NUL in a `Str`. A NUL in a `Str` also breaks the C-string boundary at FFI, and that cost is what
  the code names." *Concern:* "None of substance. The help line must still say that `'\0'` stays
  legal in a `Char`."
- **Web/Scripting:** A — "no escape gives NUL in a Str, so UnknownEscape's list of valid escapes
  would send the user in circles. NulInStr points at `Bytes`, which is the real fix." *Concern:*
  "users who meant a char `'\0'` but typed `"\0"` should also get a hint about the char form,
  because otherwise "use Bytes" is overkill for them."
- **PLT:** A — "UnknownEscape's help lists the valid Str escapes, and none of them gives NUL. So the
  help would point to a fix that does not exist, which §3.1 forbids. Only NulInStr names the real
  fix, `Bytes`." *Concern:* "The implementation may forget this special case and let `"\0"` fall
  through to the generic unknown-escape path. A test must pin the code."
- **DevOps:** A — "A UnknownEscape help line that lists the valid escapes contains no fix for NUL in
  a Str, so the user loops. One fact gets one code: a Str cannot hold NUL, whatever the spelling."
  *Concern:* "None from tooling, provided the `help:` line names `Bytes`."
- **AI/ML:** A — "For `"\0"` the valid-escape list in UnknownEscape offers no fix, so the model
  would only loop. NulInStr names the real fix, `Bytes`. C-trained models write `"\0"` often."
- **Minimalism:** A — "under the Diagnostic Discipline, a diagnostic points to a repair that exists.
  No valid escape gives NUL in a `Str`, so UnknownEscape's list of escapes would send the user
  nowhere. NulInStr names `Bytes`." *Concern:* "none of note. The implementer must route `"\0"`
  before the generic unknown-escape branch, and a test must lock that in."

##### Q4: unterminated literals (**3-3, went to Phase D**)

Options: A, one code, UnterminatedLiteral. B, two codes, UnterminatedCharLiteral +
UnterminatedStringLiteral.

- **Systems:** B — "I agree with the scope: the lexer owns every unclosed literal, and E1100 at EOF
  stops standing in for it. Separate codes let a tool's quick fix insert the right closer (`'`, `"`
  or `"#`) by matching on the code, not by parsing message text." *Concern:* "If A wins, the closer
  moves into the help text, and tools must parse prose for it."
- **Web/Scripting:** B — "I agree with the scope: the lexer owns every unclosed literal. Today's
  `expected STRING_END, got EOF` (E1100) is jargon placed at the wrong spot. "Unterminated string
  literal" is the wording every TS and JS developer already knows, and separate codes let an editor
  quick-fix know which closing character to insert." *Concern:* "raw strings `#"..."#` need the help
  to name the full closer (`"#`, with the matching number of `#`), not only `"`."
- **PLT:** A — "The rule is the same for char, string and raw-string literals ("close the literal"),
  and so is the fix (write the closer, which the help names). We already use one UnknownEscape code
  across literal kinds by this principle, so splitting here would apply the principle in two ways. I
  agree with the scope: the lexer owns every unclosed literal, and E1100 at EOF for `"abc` is a
  parser code reporting a lexer rule at the wrong place." *Concern:* "When the lexer finds an
  unclosed `#"` raw string, it must take the hash count into account, or the help will name the
  wrong closer."
- **DevOps:** B — "I agree with the scope: the lexer owns every unclosed literal, and the plain
  `"abc` + EOF case leaves E1100. Otherwise one fault gets two codes, chosen by the last byte. I
  keep char and string apart because an unclosed `'hello world` is almost always the Python/JS
  habit, with a different help ("use double quotes") than "close the string"." *Concern:* "The
  migration off E1100 can leave a parser path that still fires E1100 at EOF for some literal shape
  (interpolation holes, `t"..."`). The test suite must cover each literal form."
- **AI/ML:** A — "I agree with the scope: the lexer owns every unclosed literal. Every unclosed
  literal has one repair, "close it". The help line names the closer to write, so a model gets the
  exact token. Today's E1100 "expected STRING_END, got EOF" uses a token name a model cannot know
  and points at EOF. Moving the case to the lexer is the main gain here." *Concern:* "When an
  unclosed literal swallows the rest of the file, the parser could still add errors after it. The
  lexer must stop, or the parser must stay quiet, after this error."
- **Minimalism:** A — "every case has the same repair: write the closer that matches the opening
  quote. The help line already names that closer. A second frozen name adds catalog surface with no
  difference in fix. I agree with the scope: the lexer owns every unclosed literal, and E1100 at EOF
  stops firing for it." *Concern:* "if B wins, the char/string split should not grow a third name
  for raw strings. `#"..."#` must stay inside UnterminatedStringLiteral."

##### Q5: span for an unterminated literal (**A 6-0**)

Options: A, opening quote, plus a `note:` at EOF. B, opening quote to EOF.

- **Systems:** A — "The span stays bounded. An EOF span grows with the file, gets sent in every LSP
  publish, and paints the rest of the buffer. The opening quote is the actionable location."
  *Concern:* "The note must carry a real EOF position (line:col), not just the word "EOF", or a user
  with a long file still has to hunt for it."
- **Web/Scripting:** A — "a span that runs to EOF paints the rest of the file red in the LSP and
  hides where the problem starts. TS reports this error at the opening quote." *Concern:* "a
  single-character span can be hard to see. The message should quote the first few characters of the
  literal."
- **PLT:** A — "The cause is at the opening quote, and EOF is only where the lexer found the
  problem. A span to EOF adds no information, and it covers the rest of the file in every editor."
  *Concern:* "In a long file, the user who starts at the EOF note must still find the opening quote.
  The primary span must come first in every output format, `--json` included."
- **DevOps:** A — "In an editor, a span to EOF turns every later line red and hides every other
  diagnostic in the file. rustc and the TypeScript server both point at the opening quote. The
  `--json` note still carries the EOF position for tools that want it." *Concern:* "If B wins, LSP
  clients will show whole-file error ranges, and users will read that as "the whole file is
  broken"."
- **AI/ML:** A — "The opening quote is the only position the compiler knows to be right. A span to
  EOF marks most of the file and gives a model nothing to act on." *Concern:* "The real fault is
  often a missing quote far above EOF. The opening-quote span shows that well only if it is the
  first span the model sees."
- **Minimalism:** A — "the repair happens at the quote. A span to EOF marks the rest of the file in
  an editor and points at nothing the user should change." *Concern:* "when the literal opens near
  EOF, the primary span and the note land on almost the same spot. The output should not print the
  same line twice."

##### Q6: unknown top-level section (**A 6-0**)

Options: A, warning W1001 UnknownManifestSection. B, error E1017 UnknownManifestSection.

- **Systems:** A — "An error would break forward compatibility (§8.9.7) on every schema addition,
  and the edition gate that would make an error safe does not exist. The did-you-mean help and
  `--strict` cover the typo case." *Concern:* "A typo such as `[lint]` drops overrides that set
  lints to `"error"`, and a build that does not use `--strict` passes. The warning must print first
  and clearly."
- **Web/Scripting:** A — "§8.9.7 makes the schema forward-compatible, and the error option relies on
  an edition check that does not exist. Cargo and npm both warn on unknown manifest content. A
  did-you-mean warning catches the `[lint]` typo, and `--strict` / `[lints]` make it fatal for CI."
  *Concern:* "a warning is easy to miss in a noisy build, so the `[lint]` typo can still slip
  through for teams that do not use `--strict`."
- **PLT:** A — "An error would make the schema closed with no way to grow, because there is no
  edition gating. An older compiler would then refuse a valid newer manifest, against §8.9.7. A
  coded warning closes the silent case, and `--strict` and `[lints]` can promote it. Severity can be
  decided again under the same code after a type:spec ticket on edition semantics." *Concern:* "A
  `[lint]` typo still lets a build pass that the author meant to fail under their `"error"`
  overrides, unless they read the warnings."
- **DevOps:** A — "§8.9.7 promises forward compatibility, and the edition check that an error would
  rely on does not exist. Promoting a warning to an error later is cheap; demoting an error breaks
  CI configs. `--strict` in CI and the did-you-mean help catch the `[lint]` typo." *Concern:* "Teams
  that do not run `--strict` will miss a `[lint]` typo that drops an `"error"` gate. The
  did-you-mean help must be good enough to make the warning hard to ignore."
- **AI/ML:** A — "The schema is forward-compatible, and the error option needs an edition check that
  does not exist. The did-you-mean help catches the typo case, and `--strict` and `[lints]` give a
  hard gate." *Concern:* "A typo'd `[lints]` header drops every override. An agent that ignores
  warnings then ships a build that should have failed."
- **Minimalism:** A — "§8.9.7 requires a forward-compatible schema, and the edition check that B
  relies on does not exist in the spec or the compiler. Building that is a new feature, out of scope
  here. `--strict` gives CI the hard failure." *Concern:* "a `[lint]` typo still lets a build pass
  locally without `--strict`. The did-you-mean help must be good enough that people read the
  warning."

##### Q7: E1200 note (**A 5-1**)

Options: A, yes, specify it. B, no.

- **Systems:** A — "This is §3.1 convergence: two diagnostics from one root cause should point at
  one repair. Holding a list of W1001 sites from manifest load until resolution costs almost
  nothing." *Concern:* "The note must fire only when the missing module name plausibly matches a key
  under the unknown section, or it becomes noise on unrelated E1200s."
- **Web/Scripting:** A — "this connects cause and effect for the most common typo (`[dependecies]`).
  The user sees "module not found", and the note tells them why without a search." *Concern:* "the
  note must fire only when the unknown section is a near-miss of `[dependencies]` or
  `[dev-dependencies]`, or it becomes noise."
- **PLT:** A — "§3.1 asks diagnostics to lead to the fix the first `help:` names. When a module is
  missing because a section was misspelled, the fix is at the section, not the import. The note
  links the effect to its cause." *Concern:* "The note may fire on a guess when the two are not
  related. Give it only when the unknown section is the nearest-name match for a known section that
  would have supplied the module."
- **DevOps:** A — "A typo'd `[dependecies]` gives the error at the import, far from the cause. A
  note that links the two diagnostics is what makes the warning actionable, and the LSP can show it
  as related information." *Concern:* "The note should also attach to PackageNotDeclared (E1052),
  not only to E1200, or the commonest case gets no link."
- **AI/ML:** A — "This is the main defence against the concern in Q6. A model reads the first error,
  and E1200 at the `import` sends it the wrong way. The note leads it back to the blink.toml typo."
  *Concern:* "The note must fire only when W1001 fired in the same build, or it becomes noise."
- **Minimalism:** B *(dissent)* — "YAGNI. It couples two unrelated diagnostics for a rare case, and
  the W1001 warning already appears in the same output. Each cross-diagnostic note is a spec rule we
  must keep correct forever." *Concern:* "if A wins, the note's trigger ("same build") becomes
  stateful across daemon and incremental checks. The spec would have to say what happens when W1001
  is cached or suppressed."

##### Q8: unknown `[lints]` level (**A 6-0**)

Options: A, error E0843 InvalidLintLevel, nothing changes it. B, a warning.

- **Systems:** A — "An override that silently fails to apply is the §9.1 failure, and the same
  "refused, not ignored" rule as E0842 applies. A lints table that is invalid cannot be allowed to
  configure itself."
- **Web/Scripting:** A — "the level is the other half of a `[lints]` entry, and the key half is
  already "refused, not ignored". ESLint, tsconfig and Cargo all refuse a bad level. A did-you-mean
  for `"warning"` → `"warn"` covers the usual typo." *Concern:* "none. The help line should list the
  three valid levels."
- **PLT:** A — "A dropped override is a suppression that silently fails, which §9.1 rules out. Its
  key-side partner, E0842, is already "refused, not ignored". The `[lints]` family stays the same
  for keys and values." *Concern:* "None of substance. Do not let the lint machinery change the
  level of E0843 itself."
- **DevOps:** A — "This is E0842 in the value position, so the same "refused, not ignored" rule
  applies. A warning would let `"eror"` quietly remove a CI gate, which is exactly the failure §9.1
  forbids." *Concern:* "None. It must report every bad entry, not only the first."
- **AI/ML:** A — "The rule is "refused, not ignored", the same as E0842. Clippy-style `"deny"` or
  `"warning"` would otherwise do nothing, and the model could not tell."
- **Minimalism:** A — "an override that silently fails to apply is the §9.1 failure, and E0842
  already set the precedent of "refused, not ignored". A lint table must not be able to excuse its
  own typo." *Concern:* "none of note. The catalog row must say plainly that it is unsuppressible,
  as E0842's does."

##### Q9: manifest span rule and fallback (**A 6-0**)

Options: A, base rule only, no fallback in the spec. B, spec also states a fallback.

- **Systems:** A — "Spec text that states a fallback becomes an excuse never to record positions. If
  the TOML reader records line and column for every key, value and header, including entries in
  inline tables, the fallback is dead text. Three `Int`s per entry is cheap." *Concern:* "Inline
  tables and multi-line arrays must also get real positions in the reader. If they are skipped, the
  implementation will invent its own fallback with no spec text behind it."
- **Web/Scripting:** A — "a fallback written into the spec becomes the permanent behaviour.
  Recording positions in the TOML reader is a small, bounded job." *Concern:* "until positions land,
  an implementer may ship a quiet 1:1 anyway. The ticket should block on the TOML positions work."
- **PLT:** A — "A fallback in the spec would allow the implementation to skip the one piece of work
  this needs, which is recording positions in the TOML reader. A 1:1 span is a wrong answer that
  looks right. The spec should not allow it." *Concern:* "Diagnostics from the manifest may land
  before the TOML reader records positions, and the implementer may hard-code 1:1 anyway. Review
  must refuse that."
- **DevOps:** A — "Writing a fallback into the spec makes "no position" a valid permanent state, and
  the TOML reader may then never record positions. The rule should require positions, and a missing
  one is a compiler bug. Any stopgap is an implementation choice." *Concern:* "Until the reader
  records every position, the implementation may emit `1:1` ad hoc. The ticket must keep position
  recording in scope, not defer it."
- **AI/ML:** A — "I move from my Phase B position. A blink.toml issue always has a source position
  once the TOML reader records one. A fallback in the spec describes an implementation gap, and
  implementation details do not belong in the spec. The requirement "every manifest diagnostic
  carries a location" is the part a model depends on, and A keeps it." *Concern:* "If the reader
  work slips, the implementer may print a fake `1:1` with no rule to say so."
- **Minimalism:** A — "a missing position is an implementation bug, not a language case. Putting a
  fallback in the spec makes the bug into specified behavior, which no one will ever fix."
  *Concern:* "if B wins, implementers will lean on the fallback and never add positions to the TOML
  reader."

##### Q10: lexer recovery and suppression (**B 5-1**)

Options: A, emit the token, keep lexing, report every error, exit non-zero, no suppression. B, A,
plus no follow-on diagnostic from recovery.

- **Systems:** B — "A cascade is the cost here. One bad escape that triggers a type error elsewhere
  makes the user read two errors to fix one. This is a testable invariant: one malformed literal
  must give exactly one diagnostic, and the lexer-error tests can assert it." *Concern:* "An
  implementer may meet B by stopping after lexing whenever there is a lexer error. That hides real
  errors in the same build, so the corpus tests should check that other errors are still reported."
- **Web/Scripting:** B — "cascade errors are the top DX complaint about compilers. One bad escape in
  a regex must give one error, not a type error three lines later that sends the user hunting in the
  wrong place." *Concern:* "the "no follow-on" rule is hard to test exhaustively. Tests should cover
  at least a U+FFFD char used in a match and a dropped escape in an interpolated string."
- **PLT:** B — "Recovery that brings in new errors is unsound as a report: the user sees errors for
  code that is correct. Stating this costs nothing, because a dropped escape still gives a Str and
  U+FFFD is still a Char, so no type changes. The spec should make this a rule, not leave it to
  chance." *Concern:* "The rule needs a test. Without one, a later change to how literals are typed
  (for example, for refinements) could break it silently."
- **DevOps:** B — "Cascades from error recovery are the top source of LSP noise. A dropped escape
  that then causes a type mismatch sends the user to the wrong line. Stating the rule makes it
  testable." *Concern:* "The rule is hard to prove in general. Tests must cover at least escapes in
  typed contexts (Char vs Str, `match` on a char literal)."
- **AI/ML:** B — "A follow-on type error from one bad escape teaches a model to fix the wrong line.
  With one diagnostic per fault, a model can fix one error per edit and check its progress."
  *Concern:* "The rule needs a test, or it holds only in the cases someone remembered."
- **Minimalism:** A *(dissent)* — "the recovery in A (drop the escape; U+FFFD is a valid `Char`)
  already yields well-typed tokens, so follow-on type errors do not arise from it. B adds a spec
  guarantee whose only effect is a rule that must be tested and kept true, with no new behavior."
  *Concern:* "if a future recovery (for example, an unterminated literal swallowing code) does cause
  cascades, we will need a policy. That belongs in a general error-recovery section, not in this
  row."

##### Q11: help text for UnknownEscape in the spec (**B 4-2, went to Phase D**)

Options: A, the spec says only that the help shows the fix. B, the spec also states the
targeted-help rule.

- **Systems:** A *(dissent)* — "Help wording should improve without a spec change. The stable API is
  the code, the name and the requirement that the help shows a fix. Targeted helps belong in the
  implementation and in `blink explain`." *Concern:* "With no spec rule, the targeted helps may
  never get implemented, and `"\d"` users get a bare list of escapes."
- **Web/Scripting:** B — "a scripting developer meets UnknownEscape mostly through habits from other
  languages (`\d` in a regex, `\e` for ESC, `"\'"`). The fix they need is the Blink alternative, not
  a list of 10 escapes. Stating the rule in the spec, while leaving the wording to the
  implementation, keeps the help consistent and testable." *Concern:* "the "known meaning in another
  language" set could grow without bound. The catalog should list the cases covered."
- **PLT:** B — "The spec should set the rule and leave the wording to the implementation. "Give the
  Blink fix first where the escape has a known meaning elsewhere" is a rule an implementer can test,
  and it is not wording. Under A, only the generic list is required, and the help that matters most
  for code moved from C, Python or regex is left optional." *Concern:* "The list of "known meaning
  elsewhere" escapes will grow without end. Keep the spec text to the rule, and keep the examples
  non-normative."
- **DevOps:** B — "The rule ("give the Blink fix for a foreign escape first") is a stable rule of
  the diagnostic surface, and it binds tool authors and the LSP. Fixing exact wording in the spec
  would block wording improvements; B does not." *Concern:* "The list of "known foreign meanings"
  can grow without bound. The catalog should keep it to the common cases (`\e`, `\a`, `\v`, `\d`,
  quotes)."
- **AI/ML:** B — "A rule a model can learn from the spec ("a foreign escape gets its Blink fix
  first") is worth one sentence. Without it, targeted help may drift. The exact wording stays with
  the implementation." *Concern:* "The spec may grow a list of other languages. It should keep to
  the one rule."
- **Minimalism:** A *(dissent)* — "the spec should fix only what the 02_syntax table already fixes.
  Targeted help is quality work that changes over time; freezing it in the spec makes every wording
  improvement a spec change." *Concern:* "implementers may skip the targeted helps altogether. The
  catalog's `blink explain` text should carry them so the work has a home."

##### Q12: name for `\u{12g}` (**A 6-0**)

Options: A, InvalidUnicodeEscapeDigit. B, InvalidHexDigit.

- **Systems:** A — "The spec has hex integer literals (`0x40`, sections/07:1283). A later lexer
  error for `0x1g` is also an "invalid hex digit", and frozen names cannot be taken back. A name
  scoped to the escape leaves the general name free." *Concern:* "If B wins, the hex-integer case
  will need a clumsy second name, or this code will come to mean two things."
- **Web/Scripting:** A — "I move from InvalidHexDigit. Names are frozen API, and a future error for
  a hex integer literal such as `0x1g` would collide with a bare "InvalidHexDigit". The longer name
  is still clear in 5 seconds." *Concern:* "it is long. The message text, not the name, has to carry
  the quick read ("`g` is not a hex digit")."
- **PLT:** A — "The name should give the domain of the rule. A later bad-digit error in an int
  literal such as `0x1g` is a different rule, and it would want the name InvalidHexDigit."
  *Concern:* "The name is long. That is a fair price for a frozen API."
- **DevOps:** A — "Names are frozen forever. A bare InvalidHexDigit would collide with a future
  `0x12g` integer-literal diagnostic."
- **AI/ML:** A — "The name InvalidHexDigit could also describe a later numeric-literal error
  (`0x1g`). The longer name says where the fault is."
- **Minimalism:** A — "names are frozen forever and should say where they apply. `InvalidHexDigit`
  would also fit a future `0x12g` integer-literal error, which has a different repair, and the name
  would block or confuse that later code." *Concern:* "none of note. The name is long but plain."

##### Q13: name for `\u0041` / `\U0001F600` (**A 5-1**)

Options: A, UnicodeEscapeNeedsBraces. B, UnbracedUnicodeEscape.

- **Systems:** A — "The name states the fix, and it sorts next to the other `UnicodeEscape*` names
  in the catalog. I do not mind B."
- **Web/Scripting:** A — "the name states the fix, so a developer who reads only the name knows what
  to type."
- **PLT:** B *(dissent)* — "It matches the family pattern of EmptyUnicodeEscape and
  UnterminatedUnicodeEscape: an adjective, then UnicodeEscape. A consistent family is easier to
  search and to predict." *Concern:* ""Unbraced" is a less common word than "NeedsBraces". The
  message text must state the fix plainly."
- **DevOps:** A — "The name states the fix, which reads better in `blink explain` lists and in
  `--json` consumers that group by name."
- **AI/ML:** A — "A name that states the fix teaches the fix, even when the model sees only the
  name."
- **Minimalism:** A — "no difference in surface. The name states the repair, and I follow the
  majority."

#### Phase D — Round 2 (Q2, Q4, Q11)

Three questions were closer than 5-1 in Phase C: Q2 (4-1-1), Q4 (3-3) and Q11 (4-2). Each
panelist answered the other side's argument in one focused round, and then all six voted again.
For Q4, the scope was the same under both options: the lexer owns every unclosed literal, and E1100
no longer fires at EOF for any of them.

**Q2 debate.** AI/ML and Min moved to A (two codes, MultiCharLiteral). Min moved from one code:
"DevOps's argument settles it, and it rests on the same principle I used: one code per repair."
AI/ML moved on the name: "A near-miss spelling is a worse failure for a model than a slightly vague
name, because `@allow` and `explain` lookups would then fail."

**Q4 debate.** Sys and DevOps moved from two codes to one, and PLT and AI/ML moved
from one code to two. PLT: "DevOps's argument breaks my premise. I said that every unclosed literal
has the one fix "close it". That is false for char literals." Sys answered with the Q5 span and a
lexer fact. On the span: "My reason for B was that a quick fix must know the closer without parsing
prose. But Q5 passed 6-0: the primary span is the opening quote. A tool reads the span text (`'`,
`"`, `#"`, `##"`) and derives the closer from it, which is exact and needs no second code." On the
lexer: "Lexer.bl:324 and :333 fire only when `'` or `'\` is the last byte in the file. A `'hello
world` line goes to the "exactly one character" path, which becomes MultiCharLiteral under Q2 and
gets the double-quote help there." PLT did not accept the tooling argument: "A quick fix should come
from a structured suggested edit in `--json`, not from a lookup keyed on the code." Min made the
same point about raw strings: "A raw string `#"..."#` needs the closer `"#` with the matching number
of `#`, so even UnterminatedStringLiteral cannot tell a tool what to insert." In the re-vote, Web
moved to one code after Sys's fact, and PLT and AI/ML held two codes. The result is 4-2.

**Q11 debate.** Sys moved to B in the debate and Min in the re-vote. Sys: "My own Phase C concern was that the targeted helps
never get implemented, and B answers it with a testable rule." Web answered the "frozen wording"
objection: "B fixes no wording. It fixes one rule: "when the escape has a known meaning elsewhere,
show the Blink fix first"" Min set a condition on where the rule lives: "I will vote B if it means
one sentence in the catalog row with non-normative examples and no list of languages." The final
spec keeps the rule to one sentence, keeps the examples non-normative, and puts the list of covered
escapes in ERROR_CATALOG.md and `blink explain`.

##### Q2: `''` and `'ab'` (**A 6-0**)

Options: A, two codes, EmptyCharLiteral + MultiCharLiteral. B, two codes, EmptyCharLiteral +
MultiCharCharLiteral. C, one code, CharLiteralLength.

- **Systems:** A — "The two cases have different repairs: `''` becomes `' '` or `'\''`, and `'ab'`
  becomes `"ab"`. A tool keyed on the code then offers the right fix without inspecting the source.
  In the catalog and the message, the name always appears next to "char literal", so
  MultiCharLiteral is clear, and it is easy to type correctly in `@allow` and `explain` lookups."
  *Concern:* "The `'ab'` look-ahead must stop at end of line, or an unclosed `'` becomes a
  misleading MultiCharLiteral."
- **Web/Scripting:** A — "`'ab'` and `''` have different likely fixes (`"ab"` vs `' '` / `'\''`), so
  a code-keyed quick-fix must not treat them the same. MultiCharLiteral is the name a developer will
  type correctly into `@allow` or `blink explain`, and the message line already says "char
  literal"." *Concern:* "the EmptyCharLiteral help must not assume `""` as the fix."
- **PLT:** A — "`''` and `'ab'` break the one-scalar rule in two ways, and each needs a different
  fix. For `''` the fix is to write the intended char, and for `'ab'` it is to use double quotes.
  Different fixes need different codes. MultiCharLiteral cannot be misread, because a multi-char
  string is never an error, and it avoids a doubled "Char" name that tools and models will keep
  misspelling." *Concern:* "The EmptyCharLiteral help must not assume `""` is the fix. It should
  also offer `' '` and `'\''`."
- **DevOps:** A — "The two cases have different fixes. `'ab'` → `"ab"` is a mechanical edit that a
  tool can apply, and `''` has none, because the author usually meant `' '` or `'\''`. A quick fix
  keyed on one shared code would have to look inside the literal first. MultiCharLiteral avoids the
  near-miss spelling risk of "CharChar" in `@allow`." *Concern:* "EmptyCharLiteral's help may assume
  `""` when the likely intent is `' '` or `'\''`."
- **AI/ML:** A *(moved from B)* — "The fixes are different, so the codes are different. A tool or a
  model that keys on the code must not offer "use double quotes" for `''`. The message and the help
  on MultiCharLiteral leave no doubt about what it means. The stutter in "CharChar" would cause
  near-miss spellings in `@allow` and `blink explain` lookups." *Concern:* "The MultiCharLiteral
  help must show the double-quoted form (`"ab"`), or the split gives a model nothing."
- **Minimalism:** A *(moved from C)* — "`'ab'` → `"ab"` is a mechanical fix that a tool can apply,
  and `''` has none. One shared code would carry a fix that is right for only some of its cases,
  which breaks §3.1. MultiCharLiteral avoids the near-miss spelling that "CharChar" invites in
  `@allow` and `explain` lookups." *Concern:* "EmptyCharLiteral's help must not assume `""`, because
  the author often meant `' '` or `'\''`."


##### Q4: unterminated literals (**A 4-2**)

Options: A, one code, UnterminatedLiteral. B, two codes, UnterminatedCharLiteral +
UnterminatedStringLiteral.

- **Systems:** A *(moved from B)* — "Every case has one repair, "write the closer". The Q5 span on
  the opening quote already gives a tool the exact closer, including the hash count for raw strings.
  An unclosed char literal at EOF only happens when `'` or `'\` is the last byte, and the Python/JS
  `'hello` habit goes to MultiCharLiteral, so a second frozen name buys nothing." *Concern:* "The
  help must name the exact closer, hash count included, and the parser must report nothing after
  this error (Q10 B)."
- **Web/Scripting:** A *(moved from B)* — "Sys's lexer fact removes my reason for B. The Python
  `'hello world` habit does not reach the EOF path. It goes to the "exactly one character" check and
  gets MultiCharLiteral with the double-quote help under Q2. That leaves the unclosed char literal
  as a rare EOF edge case, and with the Q5 span on the opening quote, a tool reads the closer (`'`,
  `"`, `"#`) from the span text, so a second frozen name buys nothing." *Concern:* "the help must
  name the exact closer, including the `#` count for raw strings, and when an unclosed `'` holds 2+
  characters, it should say "use double quotes" first."
- **PLT:** B *(dissent)* *(moved from A)* — "An unclosed `'hello world` nearly always needs "use
  double quotes", and an unclosed `"...` needs "add the closer". The first help differs, so §3.1
  asks for separate codes. Raw strings and `t"..."` belong under the string code. The lexer owns
  every unclosed literal, so E1100 at EOF no longer fires." *Concern:* "The UnterminatedCharLiteral
  help must tell the case of a lone missing `'` (`'a` + EOF) apart from the multi-char habit
  (`'hello`), or the help will be wrong for one of the two."
- **DevOps:** A *(moved from B)* — "Since Q5 puts the primary span on the opening quote, a tool
  reads the closer from the span's text, so the code does not need to carry it. The fix is the same
  for every literal kind (write the closer), which matches the one-code UnknownEscape pattern. The
  `'hello world` habit is a help-line case, not a code case." *Concern:* "The help must name the
  exact closer, with the right `#` count for raw strings. It must also say "use double quotes" for
  an unclosed `'` that holds 2+ characters, or the single code gives worse help than the split would
  have."
- **AI/ML:** B *(dissent)* *(moved from A)* — "An unclosed `'hello world` is usually the Python/JS
  single-quoted string habit. Its fix is "use double quotes", not "close with `'`". That is a
  different repair, so it needs a different code. Two codes also let a quick fix insert the right
  closer from the code alone." *Concern:* "The help for a raw string must name the full closer with
  the right number of `#`. The char help should suggest double quotes when more than one character
  follows the `'` on that line."
- **Minimalism:** A — "Sys's lexer fact decides it. The char EOF paths (lexer.bl:324, :333) fire
  only when `'` or `'\` is the last byte of the file. A `'hello world` line takes the "exactly one
  character" path and becomes MultiCharLiteral, which already carries the double-quote fix. So the
  "Python habit" case is not an unterminated-literal case, and a second frozen name would cover only
  an EOF edge case. A tool gets the closer from the Q5 span (the opening quote), not from the code.
  This also keeps the pattern of UnknownEscape: one code across literal kinds, with the help varying
  by kind." *Concern:* "if B wins, `#"..."#` and `t"..."` must stay inside
  UnterminatedStringLiteral, with no third name."


##### Q11: help text for UnknownEscape in the spec (**B 6-0**)

Options: A, the spec says only that the help shows the fix. B, the spec also states the
targeted-help rule.

- **Systems:** B *(moved from A)* — "A one-sentence rule is testable and keeps the wording free to
  improve. It also makes sure that the targeted help actually gets built for C, Python and regex
  habits. It costs nothing at runtime: a small table in the error path." *Concern:* "The spec text
  could grow a list of other languages. Keep it to one rule, keep the examples non-normative, and
  put the list of covered escapes in the `blink explain` text."
- **Web/Scripting:** B — "regex and C escapes (`\d`, `\e`, `"\'"`) are how a scripting developer
  meets UnknownEscape. One normative rule ("the Blink fix first for an escape with a known foreign
  meaning") keeps that help from being optional, while wording stays free. I accept Min's placement:
  the rule can live as one sentence in the UnknownEscape catalog row, with non-normative examples
  and no list of languages in sections/." *Concern:* "the covered-case list may grow without bound
  unless the catalog keeps it to the common cases."
- **PLT:** B — ""A foreign escape gets its Blink fix first" is one rule that can be tested, and it
  leaves wording free. Under A, the help that matters most for code from C, Python or regex is
  optional, and both A voters named that as their own concern. The catalog and `blink explain` list
  the covered cases, and those cases are not normative." *Concern:* "The covered-case list may grow
  into a list of other languages. The spec text must stay one sentence."
- **DevOps:** B — "The rule is testable and freezes no wording. Without it, the most common
  UnknownEscape users (`\d`, `\e`, `"\'"`) may get a bare list of escapes from the LSP and `--json`,
  which both A voters named as their own concern." *Concern:* "The set of "known meanings elsewhere"
  can grow without bound. Catalog examples must stay non-normative and short."
- **AI/ML:** B — "The rule "a foreign escape gets its Blink fix first" is one sentence a model can
  learn from the spec and an implementer can test. It fixes no wording. Without it, the helps for
  the cases models hit most (`\d`, `\e`, `"\'"`) stay optional." *Concern:* "The spec must keep to
  the rule, with non-normative examples, and the list of covered cases goes in the catalog's `blink
  explain` entry."
- **Minimalism:** B *(moved from A)* — "my condition is met. Every B voter now limits it to one
  normative sentence, with non-normative examples, and with the list of covered cases in the catalog
  and `blink explain`, not in sections/. That answers my Phase C concern that the targeted helps
  never ship, at the cost of one sentence and no wording freeze." *Concern:* "later edits may still
  grow a list of foreign escapes in 02_syntax.md. Reviewers should keep the spec at the one rule."


---

### Final Spec

**Lexer codes (sections/02_syntax.md §2.4).**

- Every lexer case is an error, never a warning. Each goes through `diag_error_range` with a code
  in E1114 to E1126. No `@allow`, `[lints]` entry or `--strict` setting suppresses or demotes a
  lexer error.
- Each row of the malformed-escape table has its own code and name. `\x..` has its own code,
  HexEscapeNotSupported (Q1, 6-0).
- UnknownEscape is one code for both literal kinds. It replaces the old warn-and-drop behavior of
  `"a\qb"` and the old exit 0 of `'\q'`.
- `"\0"` in a `Str` is NulInStr, the same code as `"\u{0}"`, because no valid escape gives NUL in
  a `Str` (Q3, 6-0). In a `Char`, `'\0'` and `'\u{0}'` stay legal.
- `''` and `'ab'` have two codes, EmptyCharLiteral and MultiCharLiteral (Q2, 6-0 in Phase D). The
  help for `'ab'` shows the double-quoted form. The help for `''` does not assume `""`.
- Every unclosed char, string, `t"..."` and raw-string literal is UnterminatedLiteral, one code
  (Q4, 4-2 in Phase D). The lexer owns the case. E1100 no longer fires at EOF for any literal.
  The primary span is the opening delimiter, with its `t` or `#` prefix (Q5, 6-0). A `note:`
  marks where the literal ran out, with a real line and column. The help names the exact closer
  to write: `'`, `"`, or `"` followed by as many `#` as the opening delimiter has.
- **Char-literal extent rule (§2.4).** A char literal's text runs to the next `'` on the same line,
  or to the end of the line. If it holds 0 values and has a closer, the error is
  EmptyCharLiteral. If it holds 2 or more values, closed or not, the error is
  MultiCharLiteral. If it is unclosed and holds 0 or 1 values, the error is UnterminatedLiteral.
- **Recovery (Q10, 5-1).** After an error the lexer still emits the literal's token: it drops a
  malformed escape, and a bad char literal becomes U+FFFD. It keeps lexing, reports every lexer
  error in the file, and the compiler exits non-zero. Recovery must not cause a follow-on
  diagnostic: one bad literal gives exactly one diagnostic. Errors elsewhere in the file are still
  reported.
- **Targeted help (Q11, 6-0 in Phase D).** The spec states one rule: the help line for
  UnknownEscape lists the valid escapes for that literal kind, and where the escape has a known
  meaning in another language, the help gives the Blink fix first. The examples are not
  normative. ERROR_CATALOG.md and `blink explain` list the covered cases, and the implementation
  sets the wording.
- **Names.** `\u{12g}` is InvalidUnicodeEscapeDigit (Q12, 6-0), so the generic InvalidHexDigit
  stays free for a future hex-integer-literal error. `\u0041` and `\U0001F600` are
  UnicodeEscapeNeedsBraces (Q13, 5-1).

**Manifest codes.**

- An unknown `[lints]` level is E0843 InvalidLintLevel, an error (sections/04_effects.md §4.16.8).
  No `@allow`, `[lints]` entry or `--strict` setting can change it. It joins E0842 (bad key) and
  E0837 (audit-gated key) as the third refusal in the `[lints]` family (Q8, 6-0). The help lists
  the valid levels `"off"`, `"warn"` and `"error"`. The compiler reports every bad entry.
- An unknown top-level section is W1001 UnknownManifestSection, a warning (sections/06_tooling.md
  §8.9.8). `--strict` and `[lints]` can promote it. The help offers a did-you-mean (Q6, 6-0).
  An error would break the forward-compatible schema of §8.9.7, and no edition check exists to
  make an error safe.
- When W1001 fired in the same build, E1200 adds a `note:` that points at the unknown section. The
  spec states this note for E1200 and E1052 in §8.9.8 (Q7, 5-1).
- **Span rule (Q9, 6-0).** A manifest diagnostic carries a blink.toml file, line and column and
  goes through the normal `Diag` path, so the daemon, `check --json` and the LSP see it. The
  span is the value token, quotes included, for a value fault; the key for a key fault; and the
  `[header]` for a section fault. The spec states no fallback position. The TOML reader must
  record positions. `lib/pkg/manifest.bl` returns a `ManifestIssueKind` enum, and the compiler
  maps the kind to a code and severity.

**Code table.**

| Code | Name | Source | Severity | Spec home |
|------|------|--------|----------|-----------|
| E1114 | EmptyUnicodeEscape | `\u{}` | error | §2.4 |
| E1115 | UnicodeEscapeTooLong | `\u{1234567}` | error | §2.4 |
| E1116 | InvalidUnicodeEscapeDigit | `\u{12g}` | error | §2.4 |
| E1117 | UnterminatedUnicodeEscape | `\u{41` | error | §2.4 |
| E1118 | SurrogateEscape | `\u{d800}` | error | §2.4 |
| E1119 | UnicodeEscapeOutOfRange | `\u{110000}` | error | §2.4 |
| E1120 | UnicodeEscapeNeedsBraces | `\u0041`, `\U0001F600` | error | §2.4 |
| E1121 | HexEscapeNotSupported | `\x1b` | error | §2.4 |
| E1122 | NulInStr | `"\u{0}"`, `"\0"` | error | §2.4 |
| E1123 | UnknownEscape | `"\q"`, `'\q'`, `"\d"`, `"\e"`, `"\'"`, `'\"'` | error | §2.4 |
| E1124 | EmptyCharLiteral | `''` | error | §2.4 |
| E1125 | MultiCharLiteral | `'ab'` | error | §2.4 |
| E1126 | UnterminatedLiteral | `"abc`, `'`, `'\`, `#"abc` at the end of the file | error | §2.4 |
| E0843 | InvalidLintLevel | `W0703 = "loud"` | error, not suppressible | sections/04_effects.md §4.16.8 |
| W1001 | UnknownManifestSection | `[bogus]` | warning | sections/06_tooling.md §8.9.8 |

The spec homes: lexer codes in sections/02_syntax.md §2.4; E0843 in sections/04_effects.md
§4.16.8; W1001, the manifest span rule and the E1200/E1052 note in sections/06_tooling.md §8.9.8.

### Out of scope / follow-ups

- Unknown keys inside known sections of `blink.toml` (for example `[package] nmae = "x"`). The
  panel chose the narrow name UnknownManifestSection so that this check can get its own code and
  severity later.
- Uncoded `error:` lines in `lib/pkg/manifest.bl` for a missing `[package]` field and a bad
  dependency source. They have the same daemon, LSP and JSON gap.
- A reserved `[tool.<name>]` table that never warns.
- What a compiler does with an `edition` newer than it knows. PLT asked for a spec ticket on it,
  after which the severity of W1001 can be put to a vote again under the same code.
- Catalog rows for E1112, E1113 and W1000, and Category Ranges rows for E11xx and W10xx. The
  panel asked for these with no vote. They were added with this decision.
