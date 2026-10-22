[< All Decisions](../DECISIONS.md)

# String Brace Escapes — Design Rationale

Spec ticket: universal string interpolation forces escapes in brace text. Every `"..."` literal treats `{expr}` as a hole, so JSON, C and Blink source in a string need `\{` or a `#"..."#` literal. The ticket proposed an explicit interpolation marker, or keeping only one escape form.

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated in independent-proposal → debate → vote rounds. Panelist text below is verbatim. The moderator changed only heading levels, and replaced local ticket IDs with a short name in square brackets.

#### Result

| Q | Question | Result | Vote |
|---|---|---|---|
| Q1 | The ticket's two changes | K: keep universal interpolation, `\{` and `#"..."#`; no marker | 6-0 |
| Q2a | Lint for an escape-heavy `"..."` | L: 3+ counted escapes, only when the `#"..."#` rewrite is exact; machine fix | 6-0 |
| Q2b | Level of that lint | I: info | Phase C 3-2-1 (LW) → Phase D 5-1 LW (min dissent I) → user-ordered re-vote 6-0 I |
| Q2c | Escapes that count | QBS: `\"`, `\{`, `\\` | 6-0 |
| Q3 | `\}` | a: keep it; `blink fmt` leaves `\}` and `}` as written | 5-1 (sys dissent b) |
| Q4a | A hole that starts with a block | E: error `InterpDoubleBrace` | 6-0 |
| Q4b | Scope of that error | ALL: every string form and depth | 6-0 |
| Q5 | Where the "which form" rule lives | S: normative rule in the spec; `blink llms` and help texts copy it | 6-0 |
| Q6a | Renumber W1111 | Phase C 4-2 Y → Phase D 6-0 N (keep W1111) | 6-0 N |
| Q6b | Formatter rule | B: fmt changes neither the kind nor the body of a literal | 5-1 (sys dissent K) |

AI-first review: 0 of 5 criteria fail.

#### Process notes

- Phase D ran the focused debate and the re-vote in one step: each panelist answered the strongest argument against their vote, then voted.
- After Phase D, the minimalism panelist raised facts no ballot showed: §6 says "The CLI and the LSP always give the same diagnostics", and `blink lint` is not in the spec. The moderator traced the §6 sentence: a chore commit (2026-10-02, no vote) changed "They are always consistent" to that sentence. The user ordered one more silent vote on Q2b only, past the one-round Phase D cap.
- During that vote the user (BDFL) ruled: "not voted technically means not really spec." The moderator relayed the ruling to all six, and all six confirmed that their votes were written after they read it.
- Correction: in Phase D, several panelists wrote that none of the five shared-digit E/W pairs are related. E0310 `TemplateMismatch` and W0310 `RawBypassesParam` both cover templates. The Q6a result does not rest on that claim.
- Code letter: some panelists did not want an info code under `V`, which the catalog uses for contract verification. The catalog Conventions list only E, W and V, so the spec uses a new `V11xx` range. A separate letter for style hints needs its own catalog decision.

#### Phase A — Independent proposals

##### Systems

Phase A proposal from the Systems panelist (Sys) on [the brace-escape ticket].

**Measured first.** I ran a probe with the current compiler. `#"{"k": #{n}}"#` and `"\{\"k\": {n}}"` both print `{"k": 3}`. Neither form costs anything at runtime: both reduce to the same parts list (literal segments plus hole expressions) before codegen. Interpolation cost depends only on the holes, not on the syntax around the text.

###### Proposal S1: keep universal interpolation and both escape forms; give each form a clear job (RECOMMENDED)

There is no runtime cost question here. Both forms compile to the same thing, so the choice is about how people and the lexer read the text. I keep the locked §2.4 decision: a marker for interpolation is the `f"..."` prefix again, which §2.4 rejected for a good reason (a missing `f` compiles and gives wrong output with no error).

The ticket says "two escape forms" break "one way to do it". They do not. They do different jobs:

- `\{` escapes one character in a normal string. You need it now and then, for example one brace in a diagnostic message.
- `#"..."#` is a raw region for brace-heavy and quote-heavy text: JSON, C, regex. Removing it puts you back to `\"` on every quote, and the brace rule does not change that.

```blink
fn diag(name: Str) -> Str {
    "expected `\{` after {name}"
}

fn payload(id: Int, tag: Str) -> Str {
    #"{"id": #{id}, "tag": "#{tag}"}"#
}

fn c_stub(sym: Str) -> Str {
    #"void #{sym}(void) { return; }"#
}
```

What changes is convention plus diagnostics:

1. **Lint W11xx:** warn when a normal `"..."` literal has 3 or more `\{`, or any `\{` together with `\"`. Suggest `#"..."#`, with an automatic fix the formatter can apply. Text-dense code then moves to one form by rule, not by taste.
2. **Docs:** one rule in §2.4: "one escaped brace: `\{`. Brace text: `#"..."#`." The 669 test files that use `\{` and never `#"` show that people do not know the raw form exists. That is a teaching gap, not a language gap.
3. **Migration:** run the automatic fix on `src/diagnostics.bl`, `src/formatter.bl` and `tests/` as a chore. The fix only rewrites how the literal is written; the string value does not change.

Tradeoffs:
- Lexer: no change to the hot loop. The lint is a count kept while the string is scanned, then one compare at the closing quote.
- Codegen: none.
- Risk: two forms stay in the language, but the lint turns the choice between them into a rule.

Cross-language: Rust has `"\{"`-style escapes plus `r#"..."#`, and Swift has `\(x)` plus `#"..."#` with `\#(x)`. Both kept two forms because they cover different text densities, and neither caused confusion. Swift's design is the model for ours.

###### Proposal S2: remove `\{` and keep only `#"..."#` for literal braces

This meets the ticket's "one escape form" literally. A `{` in `"..."` always starts a hole.

```blink
fn diag(name: Str) -> Str {
    #"expected `{` after #{name}"#
}
```

Tradeoffs:
- About 656 rewrites in src and about 11k in tests, and every compiler bootstrap stage needs the 3-step migration.
- One literal brace in a message now changes the delimiter and the hole syntax of the whole string. That is a bad trade for local edits.
- The `\}` asymmetry stays: a bare `}` is already literal, so `\}` would be the only brace escape left and would do nothing.
- No runtime gain.

I vote against S2.

###### Proposal S3: a `{` that is not followed by an identifier or expression start is literal

`"{}"` and `"{ "` would be literal, so JSON-shaped text needs fewer escapes.

Tradeoffs:
- The lexer needs lookahead at every `{`, and the rule has edge cases. `"{x}"` is a hole; is `"{ x }"`?
- The meaning of a string then depends on what follows the brace. That is the class of silent bug §2.4 exists to prevent.
- JSON still needs `\"`, so it gains nothing in practice.

I strongly vote against S3.

###### Proposal S4: an explicit marker for interpolation (the ticket's first option)

This is `f"..."` again. I vote against it for the reasons §2.4 gives: a forgotten marker compiles and gives wrong output with no error. The `t"..."` prefix is acceptable only because a forgotten `t` is a compile error. That property does not carry over to an interpolation marker.

###### My votes

| Proposal | Vote |
|---|---|
| S1: keep both forms, add lint + docs + migration chore | **For (recommended)** |
| S2: keep only `#"..."#` | Against |
| S3: a `{` with no expression after it is literal | Strongly against |
| S4: explicit interpolation marker | Against |

The one sub-question I want the panel to vote on is the lint threshold: 3 `\{`, or any `\{` plus `\"`.

##### Web/Scripting

###### Web/Scripting panelist — Phase A proposal ([the brace-escape ticket])

I ran a probe on the current compiler and both forms print the same JSON:

```blink
fn main() {
    let name = "ada"
    let n = 3
    let a = "\{\"name\": \"{name}\", \"n\": {n}\}"
    let b = #"{"name": "#{name}", "n": #{n}}"#
    io.println(a)
    io.println(b)
    io.println("fn main() \{ }")
}
```

Output: `{"name": "ada", "n": 3}` twice, then `fn main() { }`.

The probe shows the ticket's real problem. JSON is hard to read in a plain string because of `\"`, not because of `\{`. Even with no brace rule at all, string `a` would still need eight `\"` escapes. Changing how braces work does not fix JSON. Choosing `#"..."#` does fix it, and that choice already exists.

###### Proposal A: an explicit interpolation marker (`f"..."`, `$"..."`, `${}`). Reject.

This reopens a locked 2.4 decision without new evidence. The forgotten `f` is the most common Python string bug, and an LLM will repeat it. JS has the same issue: `"${x}"` inside plain quotes compiles and prints `${x}`. Both fail silently, which is the worst kind of failure. The two places where Blink already uses a prefix (`t"..."`) or extended delimiters are allowed for one reason: getting them wrong is a compile error. A missing `f` would not be.

###### Proposal B: keep one escape form only

- **B1: remove `\{` and require `#"..."#` for any literal brace.** Reject. src/ has about 656 `\{` uses. Most are one brace in a diagnostic or a code snippet, such as `"expected \{ after fn"`. Making that `#"expected { after fn"#` adds a delimiter pair to escape one character. Every JS, Python, Kotlin or C developer, and every LLM, already reads backslash as "the next character is literal".
- **B2: remove `#"..."#`.** Reject. JSON, regex and generated code then need `\"` and `\\` everywhere, which is what the ticket complains about.

###### Proposal C (RECOMMENDED): close as already decided, and add a nudge diagnostic

**1. Close the "two escape forms" point.** `\{` and `#"..."#` do different jobs, so they are not two ways to do one thing:
- `\{` escapes a single character in an ordinary string.
- `#"..."#` makes a whole block of text literal.

Rust has the same split (`\"` and `r#"..."#`), so does Python (`\\` and `r"..."`), and so does C# (`{{` and `"""`). Swift is the closest match. It has universal interpolation `\(x)`, plus `#"..."#` with `\#(x)`, and it has never needed a prefix. Blink copies Swift's model and gets the same result.

**2. Add a new lint, W11xx "escape-heavy string".** It fires when a plain `"..."` holds 3 or more `\"`/`\{` escapes and converting it to `#"..."#` would remove all of them. It carries a fix that `blink fix` can apply. Example message:

```
warning[W11xx]: string has 6 escapes; an extended string needs none
  help: #"{"name": "#{name}", "n": #{n}}"#
```

This works on the 90% case where it hurts: a developer, or an LLM, pastes JSON into `"..."`, sees backslashes everywhere and dislikes the language. The lint teaches `#"..."#` at the moment they need it, without blocking them. The threshold keeps it quiet for one-brace strings like the `\{` uses in diagnostics.bl.

**3. Docs.** Put one table in the 2.4 string section and in `blink llms`: "one brace → `\{`; JSON, regex or code → `#"..."#`; templates → `t"..."`". Of the 669 test files that use `\{` and never `#"`, many are code-in-string cases, which is the trap the lint finds. Migrating them is an optional chore, not a spec change.

**4. Sub-question: `\}`.** Keep accepting it, and keep a bare `}` literal. LLMs write `\{ ... \}` in pairs, and rejecting `\}` would cause pointless Stack Overflow questions. The formatter should leave both spellings unchanged. I am not proposing a rule here: it costs little and it is not a "two ways" problem worth a panel's time.

###### How developers will find it

- A JS or Python developer understands `\{` in 5 seconds and `#"..."#` in under a minute, as long as the error or lint shows them the exact rewrite.
- The existing `InterpParseFailure` help already names both forms.
- With W11xx added, the "how do I write JSON in Blink" question gets answered by the compiler before it reaches Stack Overflow.

**Cost:** one lint and one table. No grammar change, no migration, no new prefix vote.

##### PLT

**PLT panelist: Phase A proposal ([the brace-escape ticket], brace escapes in interpolated strings)**

**My reading of the gap.** The ticket counts two "escape forms" for a brace. In type-theory terms they are not two ways to do one thing. They sit on two different axes:

- `\{` escapes one character inside a *cooked* string, where `\` is the escape character and `{` opens a hole.
- `#"..."#` is a *raw* string. It does not escape `{`. It moves the hole opener to `#{` and turns off every escape.

Each mature language has this same cooked/raw split. Swift is the closest match: `"\(x)"` against `#"\#(x)"#`, with depth that you can adjust. Rust has `"..."` and `r#"..."#`, C# has `"..."` and `"""..."""`, Python has `"..."` and `r"..."`. So "one way to do it" holds on each axis. The real problem is smaller, and it is mostly in usage and docs.

The current lexical rule is sound and total. I checked it today:

- In a cooked string, each `{` must be either `\{` or the start of a hole that parses. `"x {} y"` is a hard error, InterpParseFailure.
- A bare `}` outside a hole is literal.
- In `#"..."#`, `{` is literal and only `#{` opens a hole. W1111 catches the reverse mistake.

One silent case is left: `"{id}"` with `id` in scope and `T: Display` interpolates when you meant literal text. No lexical rule can decide what the author meant there, so a better grammar cannot fix it. Only the choice of string form can.

---

**Proposal 1 (RECOMMENDED): Keep the grammar. Make one form canonical for each kind of content, and normalize the redundant spelling.**

1. Close the "explicit marker" branch. A required `f`/`i` marker is the same thing §2.4 rejected: if the marker is missing, the program compiles and prints the wrong text. That is the exact failure §2.4.3 uses to tell `t` (compile error) apart from `f` (silent). Reopening it would undo a locked decision with no new evidence.
2. Do not remove a form. Each form is the only one that composes on its axis:
   - Remove `\{`, and a string that needs both `\n` and a literal `{` has to switch to raw mode and spell the newline as `#{"\n"}`.
   - Remove `#"..."#`, and regex and C emission need `\\` and `\"` everywhere. Those are the use cases §2.4.2 lists.
3. Fix the one real duplicate: `}` and `\}` give the same text. Keep `\}` in the escape table, because the 6-0 unicode-escape decision put it there. Have `blink fmt` rewrite `\}` to `}`, so source has one spelling.
4. Add a lint that suggests `#"..."#` for a cooked string literal with 3 or more `\"`/`\{` escapes. This makes the rule total and easy to learn: content with `"` or `\` goes raw, everything else stays cooked. It also builds on the Q2 decision (diagnostics that suggest both forms).
5. Template interaction: `t"..."` and `t#"..."#` already share the hole grammar with `Str` at each depth. Item 3 must apply the same way to template literals, so that `Str` and `Template[C]` keep one lexical rule.

```blink
fn render(name: Str, items: [Str]) -> Str {
    let header = "Total: {items.len()} items"
    let json = #"{"name": "#{name}", "count": #{items.len()}}"#
    let set_text = "\{a, b}"
    header + "\n" + json + "\n" + set_text
}
```

In `set_text`, the `}` is bare. The formatter writes it that way even if the source had `\}`.

Tradeoffs:
- Sound and compositional, no migration, no new syntax.
- The lint adds noise in tests that embed source text. Tests can silence it with `@allow`, or the threshold can be raised.
- It does not close the silent `"{id}"` case. Nothing short of an `f` prefix closes it, and an `f` prefix brings a worse silent case.

---

**Proposal 2 (REJECT): Required interpolation marker, for example `i"..."`.**

```blink
let greeting = i"Hello, {name}"
```

Unsound in the sense §2.4.3 defines: `"Hello, {name}"` without the marker is valid and silently wrong. It also adds a third string prefix, after `t` and `#`, and the formatter has to keep two cooked syntaxes. Python's f-string history is the warning case.

---

**Proposal 3 (REJECT): One escape form only.**

- (a) Drop `\{`: about 656 uses in src/ and about 787 test files have to move to raw strings, and you can no longer mix escapes with a literal brace (see item 2 above).
- (b) Drop `#"..."#`: raw strings are gone, and so is the main reason W1111 exists.
- (c) Python-style `{{`: it gives `{{` a second meaning, and the lexer must tell it apart from a hole whose expression starts with `{`. That is a lexical rule that needs extra lookahead, which I will not accept in a core token.

---

**Cross-language note.** Swift solved this problem in SE-0200 with the same design Blink already has: cooked strings, `#`-delimited raw strings, and a hole sigil that moves with the delimiter depth. It has stayed stable for eight years. Blink should not paint itself into the Python corner, where `f`, `r` and `rf` combine into a 2×2 grid of prefixes.

**Vote: Proposal 1.**

##### DevOps/Tooling


###### What I measured (current compiler, build/blink)
- `#"x {name} y #{name}"#` prints `x {name} y Al` and gives **no W1111**. The spec calls for that warning (§2.4.2), but the compiler does not have it, and it is not in ERROR_CATALOG.md. Its number also matches `E1111 UnknownIntrinsic`, so a reader can confuse the two codes.
- `"{ \"k\": 1 }"` gives E1106 InterpParseFailure. The help names both `\{` and `#"..."#`. `blink fmt` stops with "formatting failed" on such a file.
- The LSP already sends machine-applicable quickfixes (`fix_action`/`fix_text` in src/lsp.bl:1046), so a fix-it for E1106 has a place to go.
- Most brace text in JSON or C fails at compile time and does not pass in silence. The one silent hazard is `{ident}` written as literal text when `ident` is in scope and is `Display`. No marker scheme removes that hazard. A marker only turns it around into the `f"..."` bug.

###### Proposal A: keep the syntax, fix the diagnostic surface (RECOMMENDED)
I see no new syntax and no removed form. The two forms do different jobs, so they are not "two ways" to do one thing. `\{` escapes one character in a short string. `#"..."#` changes the rules of the whole literal (`"`, `\` and `{` are all literal), and that is the real fix for JSON, because JSON needs `\"` in `"..."` whatever the brace rule is.

```blink
fn main() ! IO {
    let name = "Al"
    let short = "fn f() \{ }"
    let json = #"{"name":"#{name}","active":true}"#
    io.println(short)
    io.println(json)
}
```

Tooling work, all `type:chore`/`type:bug`, with no spec text change except item 1's code:
1. **Implement W1111.** Give it a code that does not match E1111's digits, and add it to ERROR_CATALOG.md. This is the safety net that makes `#"..."#` safe to recommend.
2. **Add a quickfix "convert to extended string" on E1106.** It rewrites `"..."` → `#"..."#`. It removes `\"`/`\{`/`\}` and changes each `{expr}` hole to `#{expr}`. It picks the smallest depth whose closer does not appear in the body. It is offered only when the body has no escape that `#"` cannot hold (`\n`, `\t`, `\u{..}`). Keep the existing `\{` insert fix as the second option.
3. **Add a "prefer extended string" lint (info level, with autofix).** It fires on a `"..."` literal with 3 or more `\"`/`\{` escapes. It is the same rewrite as item 2, run across a file, so `blink lint --fix` cleans tests/ and src/diagnostics.bl in one pass.
4. **`blink fmt` never changes the kind of a literal.** The formatter keeps the form the author wrote, and only the lint rewrites one form to the other. One owner per change keeps fmt idempotent and its goldens stable.
5. **Recovery:** after E1106, keep lexing the string as literal text up to its closing `"`, so one bad brace gives one error and fmt and the LSP still work on the rest of the file.

Tradeoffs: no migration, and no change for LLMs, which already write `"...{x}..."` as Swift/Kotlin/C# code does. The escape cost stays in place, but the tools pay it: one keystroke for the fix, or `lint --fix` for a corpus. The silent `{ident}` hazard stays in plain strings.

###### Proposal B: an explicit interpolation marker (`f"..."` / `$"..."`): reject
This reopens §2.4's locked decision for the reason that decision gave: a missing marker compiles and gives wrong output with no error. Code with a missing marker is valid, so no compiler error can catch it. The best tooling could do is a heuristic "looks like a hole" lint on every plain string, and that is W1111 again with more false positives (JSON keys, C code). Migration means a codemod over about 656 src sites and about 11k test hits, plus a 3-step bootstrap dance. Cross-language: Python's own linters (Ruff F-string rules) exist to catch this exact bug. C#'s `$""` has the same failure mode.

###### Proposal C: keep one escape form only: reject
- If `\{` goes, every short code-in-prose string (formatter.bl, diagnostics.bl) must become `#"`, even a one-brace string.
- If `#"..."#` goes, JSON and regex fall back to escaping every `"`, `\` and `{`, and `t#"..."#` (6-0) goes with it.

Neither option takes out a diagnostic. Both make the fix-it worse.

###### Proposal D: context-sensitive `{` ("literal if not an expression start"): reject
A brace's meaning would then depend on the characters after it. A typo inside `{expr}` would stop being an error and become silent literal text. The highlighter and the LSP's hole detection would have to parse to know which kind of token they hold. Error recovery would also get worse.

###### Vote I put forward
Close [the brace-escape ticket] with no change to the language. File these as follow-ups: W1111 build plus a new code (bug, because the spec requires it), the E1106 convert quickfix, and the prefer-extended-string lint with `--fix`. Add one spec line to §2.4.2: "fmt does not change literal kind; the lint does."

##### AI/ML


###### New fact (measured today)

`io.println("a {{x}} b")` with `x = 5` prints `a 5 b`, with no error and no warning. The lexer reads `{{x}}` as a hole that holds the block expression `{x}`, then a bare `}` (literal). `"{{1, 2}}"` gives InterpParseFailure, but `{{name}}` compiles.

`{{` is the strongest LLM prior for "literal brace": Python str.format and f-strings, Rust `format!`, C# `$""`, Kotlin and Java formatters. Handlebars and Jinja give `{{x}}` its own meaning. So the most likely LLM mistake is a silent wrong output. That is the bug class §2.4 names against `f"..."` ("get no error, and ship broken output"). Universal interpolation brings it back through a prior from other languages. Neither the ticket nor the spec mentions it.

###### Proposal A: close as already decided

Keep both forms and change nothing. Tradeoff: no churn, but the `{{x}}` silent bug stays.

###### Proposal B: explicit interpolation marker (`f"..."`, or Swift `\(x)`)

This reverses a locked vote. It brings back the bug where a missing prefix compiles and is wrong, the top issue in §2.4. It also breaks LLM output like `"Hello, {name}"`, which works today. **Reject.**

###### Proposal C: one escape form only

- Remove `\{`: about 656 src uses and about 787 test files change, and the most common short case needs raw-string syntax.
- Remove `#"..."#`: JSON needs `\"` on every quote whatever the brace rule is, and JSON is the use case that started this ticket.
- The two forms do different tasks. `\{` escapes one character. `#"..."#` changes the literal kind, so `"`, `\` and `{` are all literal.
- This is the same as `\n` versus a raw string, which every LLM knows (Python `r""`, Rust `r#""#`, Swift `#""#`). "One way to do it" means one task, not two tasks that look alike. **Reject.**

###### Proposal D (RECOMMENDED): keep both forms, make `{{` a hard error, write one rule for each form

1. **A hole may not start with `{`.** In `"..."` and `t"..."`, a `{` directly after a hole's opening `{` is a compile error (suggested name `InterpDoubleBrace`):

   ```
   error[InterpDoubleBrace]: `{{` does not escape a brace in Blink
     help: for a literal `{`, write `\{`: "a \{x} b"
     help: or use an extended string, where braces are literal: #"a {x} b"#
   ```

   A block expression in a hole is never needed, because the expression can go in the hole directly. In `#"..."#` the hole is `#{`, so `#"{{x}}"#` stays literal text, and W1111 already warns about `{x}` there. The worst silent failure becomes a loud one, with the fix in the help text.

2. **One rule for the docs and for `blink llms`:**
   - Use `\{` for one or two braces in a normal string.
   - Use `#"..."#` when the text has quotes, backslashes, or a lot of braces (JSON, regex, C, Blink source).
   - Use `#embed` for large blocks of text.

   That is one decision point, decided by what the text contains.

3. **Keep `\}`.** A bare `}` is literal, but LLMs write `\{` and `\}` as a pair. Rejecting `\}` adds an error that teaches nothing. A minimalist could call this "two ways to write `}`". I accept that cost on purpose.

```blink
fn render(name: Str, count: Int) -> Str {
    let greeting = "Hello, {name}! Use \{ for a brace."
    let body = #"{"user":"#{name}","count":#{count}}"#
    // "{{name}}" is now error[InterpDoubleBrace], not silent "Alice"
    greeting + body
}
```

Tradeoffs from my domain:

- **Learnability from the spec:** part 1 adds no syntax. It removes a misparse that a reader of the spec cannot predict. Part 2 is one sentence that an LLM can apply without patterns from training data.
- **Token cost:** no change for correct code.
- **Loud vs silent failure:** part 1 closes the one silent failure in the brace story that I found today. Writing `"{name}"` when the literal text `{name}` was intended stays silent. That cannot be detected, and §2.4 already accepts that cost.
- **Churn:** none expected, because no code in the repo uses `{{`. A grep to confirm this goes in the implementation ticket.

Cross-language note: Swift has the same split, `\(x)` in `"..."` and `\#(x)` in `#"..."#`, and its `#"..."#` form is the model for ours. C# and Rust escape braces with `{{`, so our design must handle that prior, not ignore it.

**Recommendation: D.** File the `{{x}}` silent misparse as a type:bug, whatever the result of this vote.

Probe: /tmp/claude-1000/-home-nhumrich-blinklang-blink/ef6430d6-9d5d-4756-b3d4-d68123ee8e5d/scratchpad/aiml_p.bl

##### Minimalism

###### Minimalism panelist (Min): Phase A proposal on [the brace-escape ticket]

The ticket asks for one of two changes: add an interpolation marker, or cut one of the two escape forms. I checked both against decisions the panel already made. Both lose, and only one small subtraction is left worth voting on.

###### Proposal M1: Close as already decided (RECOMMENDED)

The two parts of the ticket are both decided already.

- **"Require an explicit marker"** is the `f"..."` design. §2.4 rejected it in a locked vote, for reasons that still hold. A missing `f` compiles with no error and gives wrong output. LLMs make that mistake more often than any other string mistake in Python. `t"..."` was accepted only because forgetting `t` is a compile error. A plain-string marker cannot have that property.
- **"Keep one escape form only"** assumes `\{` and `#"..."#` do the same job. They do not:
  - `\{` escapes one brace inside a normal string.
  - `#"..."#` is a raw string. It removes the need for `\"`, `\\` and `\{` all at once, and that is what JSON actually needs.

  Cutting either one costs something real.
  - Without `\{`, every one-brace string must be a raw string. src/ has about 656 `\{` uses, and 669 test files use `\{` with no `#"`.
  - Without `#"..."#`, JSON and regex go back to escaping every quote and backslash. §2.4.2 lists exactly those use cases, and the 5-0 vote accepted it for them.

The compiler already does the diagnostic part. `"x {} y"` gives `InterpParseFailure`, and its help text names both remedies. Inside raw strings, W1111 catches a forgotten `#`. This matches the Q2 soft consensus: docs plus a targeted diagnostic.

```blink
fn main() {
    let name = "ada"
    let greeting = "hello {name}, set is \{a, b}"
    let body = #"{"user": "#{name}", "tags": ["x", "y"]}"#
    print(greeting)
    print(body)
    print(body.len())
}
```

Rule for users and docs: one literal brace takes `\{`. Brace-heavy or quote-heavy text takes `#"..."#`.

**Tradeoffs**
- Nothing new to learn, implement or format.
- It keeps the "compile error over silent bug" principle, which the `t` vote treats as the boundary.
- The ticket's "one way to do it" principle mixes up two things. "One way" means one way per problem. A single brace and a JSON blob are two different problems.

**Cross-language:**
- Rust has `\\`-style escapes plus `r#"..."#`, both kept since 1.0.
- Swift has `\(x)` interpolation plus `#"..."#` with `\#(x)`. Blink copied this model, and Swift never found a reason to merge the two forms.
- Python's f-string history is the cautionary tale behind §2.4.

###### Proposal M2: Remove the `\}` escape (subtraction, optional)

This is the one real duplicate in the area. A bare `}` is already literal (`"a } b"` prints `a } b`), so `\}` is a second spelling of the same text.

If we remove it:
- `\}` becomes a compile error with a fix-it: "`}` needs no escape".
- `blink fmt` rewrites old uses.

```blink
fn main() {
    let set_text = "\{1, 2}"
    print(set_text)
}
```

**Tradeoffs**
- **For:** it is a true "one way" cut and costs users nothing.
- **Against:**
  - Many people write `\{...\}` by habit for symmetry.
  - The 6-0 escape-table vote included `\}` on purpose.
  - Removing it needs a 3-step migration across src/ and tests/.
  - Each `\}` the formatter strips is a diff that teaches nothing.

**Cross-language:** C# `$"..."` needs `{{` and `}}` both doubled. Swift leaves a bare `)` alone. Precedent is split.

I vote **no** on M2 if nobody else raises it: it is churn for very little gain. I list it so the panel can see a true subtraction option next to the false one in the ticket.

###### Proposal M3: Docs-only follow-up (fold into M1)

Make the existing rule one table in the string section of `blink llms`: "1 brace → `\{`. Braces or quotes in bulk → `#"..."#`. Large files → `#embed`". This needs no spec change, so it is a chore, not a vote.

###### What I reject

- **An `f`/`i`/`$` marker on plain strings:** it brings back the silent bug that §2.4 removed, and it is a second string type.
- **Dropping `\{`:** it forces a raw string for one character.
- **Dropping `#"..."#`:** it brings the quote-escape problem back for JSON.
- **A third delimiter:** the rejected table says "One string syntax".

**Recommendation: M1, with M3 as a chore. M2 as an optional separate vote; I lean no.**

#### Phase A.5 — Deduped option space (moderator)


Full Phase A texts: scratchpad/phaseA_{sys,web,plt,devops,aiml,min}.md. Read the others' files before replying.

###### Facts surfaced by panelists in Phase A (moderator re-checked the first)
- (aiml) `"a {{x}} b"` with `x = 5` prints `a 5 b`, no error, no warning: `{{x}}` lexes as a hole holding the block `{x}`, then a literal `}`. `"{{1, 2}}"` is InterpParseFailure. Moderator re-ran it: prints `a 5 b`.
- (devops) W1111 (`{ident}` without `#` inside `#"..."#`) is in §2.4.2 but has no emit site and no ERROR_CATALOG.md row; its digits match `E1111 UnknownIntrinsic`.
- (devops) `blink fmt` stops with "formatting failed" on a file with an E1106 string.

###### Q1 — The ticket's two changes
- **Q1-K: keep universal interpolation and both `\{` and `#"..."#`; reject an interpolation marker** — sys (S1), web (C), plt (1), devops (A), aiml (D), min (M1).
- Proposed and rejected by their own authors (no panelist recommends them): explicit marker (sys S4, web A, plt 2, devops B, aiml B); drop `\{` (sys S2, web B1, plt 3a, devops C, aiml C, min); drop `#"..."#` (web B2, plt 3b, devops C, aiml C, min); `{` literal when no expression follows (sys S3, devops D); Python `{{` as escape (plt 3c).

###### Q2 — A lint that suggests `#"..."#` for an escape-heavy plain string
- **Q2-L: add it** — sys, web, plt, devops. Variations to settle:
  - trigger: sys "3 or more `\{`, or any `\{` together with `\"`"; web "3 or more `\"`/`\{` and converting removes all of them"; plt "3 or more `\"`/`\{`"; devops "3 or more `\"`/`\{`".
  - level: sys/web warning (W11xx); devops info level.
  - fix: all four attach a machine-applicable rewrite; devops adds the same rewrite as a quickfix on E1106, offered only when the body has no escape `#"` cannot hold (`\n`, `\t`, `\u{..}`).
- **Q2-N: no lint; docs only** — min (M1/M3); aiml did not propose a lint.

###### Q3 — `\}` (a bare `}` is already literal)
- **Q3-a: keep `\}`; fmt leaves both spellings** — web, aiml.
- **Q3-b: keep `\}` in the escape table; `blink fmt` rewrites `\}` to `}`** — plt (applies to `t"..."` too).
- **Q3-c: remove `\}` (error + fix-it)** — min M2 (listed; min leans no).
- Related, devops: "`blink fmt` never changes the kind of a literal; only the lint rewrites one form to the other" (proposed as a spec line in §2.4.2).

###### Q4 — `{{` at the start of a hole
- **Q4-E: a hole may not start with `{`; new error `InterpDoubleBrace`, help names `\{` and `#"..."#`** — aiml.
- No other panelist addressed it in Phase A.

###### Q5 — Where the "which form when" rule lives
- sys: one rule in §2.4 spec text. web: a table in §2.4 and `blink llms`. aiml: docs and `blink llms`. min: `blink llms` table, a chore, no spec change.

###### Q6 — DevOps tooling items (devops)
- Implement W1111 and give it a code whose digits do not match E1111; add the catalog row.
- Spec line: "fmt does not change literal kind; the lint does."
- E1106 recovery: lex the rest of the string as literal text to its closing `"`.
- devops files these as bug/chore follow-ups, not spec votes, except the fmt line and the W1111 code.

#### Phase B — Debate (round 1)

##### Systems


###### New fact (measured today)

`"a { {x} } b"` also prints `a 5 b`, the same as `"a {{x}} b"`. The `{{` hazard is not only about two bytes next to each other. It is "the hole's expression is a block". A rule that checks only the byte pair `{{` would leave the spaced form silent.

###### Q1: Q1-K (keep universal interpolation and both forms; no marker)

All six of us agree. The cost argument settles it for me: both forms reduce to the same parts list before codegen, so neither form carries a runtime cost. Choosing between them is about what the text contains, and that is not "two ways to do one thing".

###### Q2: Q2-L (add the lint)

I drop my own trigger and take web's: **3 or more `\"`/`\{` escapes, and converting to `#"..."#` removes all of them**. It is better than mine for two reasons:

- It never suggests a rewrite that cannot hold the body. `\n`, `\t` and `\u{..}` stop the rewrite, which is devops's precondition stated as part of the trigger.
- The fix is always machine-applicable, so `blink lint --fix` can migrate tests/ in one pass.

Level: **warning**, not info. Min, here is my answer to you: §2.4 and the Q2 soft consensus both assume that a diagnostic teaches the form at the moment of need. An info-level hint does not reach an LLM's repair loop, but a warning does. For tests that embed source, the fix is `--fix`, not `@allow`. If the corpus has too many hits to migrate now, put an allowance on the test directory and track the clean-up as a chore. Do not raise the threshold to hide them.

Lexer cost: one escape counter while scanning, plus a flag that the first non-convertible escape sets. This adds nothing measurable to the hot loop.

###### Q3: Q3-b (keep `\}` in the table; fmt rewrites `\}` to `}`)

- Accepting `\}` costs nothing and matches the LLM habit of writing `\{...\}` in pairs.
- One spelling in formatted source matters here because this repo is training data. If the source uses both spellings, an LLM keeps writing both.
- This is consistent with devops's line: `\}` to `}` changes spelling, not literal kind.
- I am against Q3-c. An error that teaches nothing fails the "loud only when useful" test.

###### Q4: Q4-E (error when a hole starts with a block), widened

I support aiml's error and widen it: **in `"..."` and `t"..."`, it is an error when the first token of a hole's expression is `{`, whitespace allowed.** With that wording, `"{ {x} }"` is caught too.

- Cost: one token check when the hole's parse begins. There is no lexer lookahead, which answers plt's objection to `{{` as an escape (3c). We do not give `{{` a meaning. We forbid it.
- What it removes: Blink has no brace map literal, so a hole whose expression is a block is never needed. The expression can go in the hole directly.
- This is the only silent wrong output found in this round, and it hits the strongest LLM prior (Python, Rust, C#). It must be an error, and the fix belongs in the help text.
- It is a bug fix to make the current behaviour match the spirit of §2.4. It also needs one spec sentence in §2.4, so it gets a vote.

###### Q5: one rule sentence in §2.4, and the same table in `blink llms`

Web and aiml's table goes in both places. Spec text is what the panel votes on and what `blink llms --full` draws from. If the rule lives only in docs, it goes out of date.

###### Q6: support all of devops's items

- W1111 has a rule in the spec but no emit site. That is a bug; file it as one.
- Renumbering W1111 so its digits do not match E1111 is a spec vote. Yes.
- "fmt does not change literal kind" goes into §2.4.2. Yes.
- E1106 recovery (lex the rest of the string as literal text up to its closing `"`) is a chore. Yes. It also fixes the "formatting failed" stop.

###### Position

| Q | Position |
|---|---|
| Q1 | K |
| Q2 | L, using web's trigger, at warning level |
| Q3 | b |
| Q4 | E, widened to "the first token of a hole is `{`" |
| Q5 | spec sentence plus `blink llms` table |
| Q6 | all items |

Stable, ready to vote.

##### Web/Scripting

###### Web/Scripting panelist (Web): Phase B round 1

The panel agrees on the main question: all six of us keep universal interpolation and both escape forms. The open work is in the tooling, and in one real bug that aiml found.

###### Q1: Q1-K (keep everything, no marker). Yes.
I have nothing to add. All six Phase A texts reject the marker for the same reason §2.4 gives.

###### Q2: Q2-L (add the lint). Yes.
To min: docs are not enough. A developer who pastes JSON into `"..."` does not read §2.4. They read the red text in their editor. The lint is how the docs reach that developer.

On the variations to settle:
- **Trigger.** Fire on 3 or more `\"`/`\{` escapes, and only when converting removes all of them. That means the body has no `\n`, `\t` or `\u{..}`, which is devops' condition and my "removes all" written another way. Sys' "any `\{` together with `\"`" fires on short diagnostic strings like `"expected \"\{\""`. That string reads fine as it is, so the rule is too eager.
- **Level.** I want warning. An info-level lint is one that nobody sees, and the whole purpose of this lint is to be seen. It must stay in the lint category, so it can be turned off and never blocks a build. If the panel picks info level with the fix attached, I can accept that.
- **Fix.** Attach a machine-applicable rewrite. I support devops' plan to put the same rewrite on E1106 as a quickfix, under the same guard.

###### Q3: Q3-a (keep `\}`, fmt leaves both spellings). Yes.
To plt (Q3-b): rewriting `\}` to `}` in fmt makes diff churn on code that is already correct. A JS developer who writes `\{...\}` and sees fmt delete half the pair gets confused ("why is my escape gone?"). Also, devops' rule "fmt does not change how a literal is written; the lint does" is simple, and I want to keep it simple. No to Q3-c.

###### Q4: Q4-E (`InterpDoubleBrace`). Strong yes.
This is the most important new fact in this debate, and I missed it in Phase A. `{{x}}` is the escape that Python, C#, Rust and Kotlin developers reach for before any other. In Blink it compiles today and prints the value with no warning. That is the "ship broken output with no error" bug that §2.4 was written to stop. Making it an error costs nothing:
- no code in the repo uses a block as a hole;
- `"{{1, 2}}"` already fails;
- the help text names both fixes.

```blink
fn greet(name: Str) -> Str {
    // was silent "Hi ada"; now error[InterpDoubleBrace] with help `\{` / #"..."#
    "Hi \{{name}}"
}
```

The example produces `Hi {ada}`, which is the correct way to write it. I also support filing the current behaviour as a type:bug, whatever the vote result.

###### Q5: Both. Yes.
Put one normative sentence in §2.4 (sys) and the table in `blink llms` (min, aiml). The sentence: "one brace: `\{`; quotes, backslashes or many braces: `#"..."#`; large files: `#embed`". These two do not conflict. The spec is the source and `blink llms` is how people find it.

###### Q6: Yes to all devops items.
- W1111 with a code whose digits differ from E1111, plus its catalog row. This is a bug, because the spec requires it and the compiler does not have it. Without W1111, recommending `#"..."#` is less safe.
- The fmt line in §2.4.2.
- E1106 recovery. "formatting failed" on a whole file because of one brace is the kind of failure that makes people leave a language in its first hour.

**Position: Q1-K, Q2-L (warning, devops guard), Q3-a, Q4-E, Q5 both, Q6 all.**

##### PLT


###### New fact (measured today)
The `{{` misparse is not limited to plain strings, and spaces do not change it:
- `#"a #{{x}} b"#` with `x = 5` prints `a 5 b`.
- `"c { {x} } d"` prints `c 5 d`.

At every depth, the hole grammar lets a block be the hole's expression. So Q4 is a hole-grammar rule and not a rule about the `"..."` lexer. It has to apply the same way to `"..."`, `t"..."`, `#"..."#` and `t#"..."#` at every depth, or `Str` and `Template[C]` stop sharing one hole grammar.

###### Q1: Q1-K (keep both forms, no marker)
All six of us agree. Nothing new for me to argue.

###### Q4: Q4-E, with a precise rule (my strongest point this round)
aiml found the one silent failure that a lexical rule *can* close. I support it, stated so it does not depend on whitespace or depth:

> The first token of a hole's expression must not be `{`. This holds in every string form and at every depth.

Error `InterpDoubleBrace`. The help names `\{` and `#"..."#`, and also "write the expression directly, or wrap it in `( )`".
- It is sound: a hole that holds the block `{e}` means the same as a hole that holds `e`, so the rule loses no expressiveness.
- An expression that has to start with a brace form can still be written as `({ ... })`.
- `\{{x}` keeps its meaning: an escaped brace, then a hole.
- It must cover `{ {x} }`. If the rule checks only the characters `{{`, its behavior then depends on whitespace, which is the kind of rule I reject on principle.

###### Q2: Q2-L, with web's trigger
- **Fire only when the rewrite is total:** 3 or more `\"`/`\{`/`\\` escapes, and no escape that `#"` cannot hold (`\n`, `\t`, `\u{..}`). A lint whose fix does not apply in every case where it fires is noise.
- **Level:** warning, with a machine-applicable fix.
- **Also** adopt devops's E1106 quickfix, under the same rule for when it is offered.
- To min: a doc does not run. The Q2 soft consensus (2026) asked for targeted diagnostics, and this is one.

###### Q3: I move from Q3-b to Q3-a
devops is right: one owner for each kind of rewrite. I generalize their line: **"`blink fmt` never changes a literal's kind or its escape spelling."**
- My Q3-b breaks that line for a one-character gain.
- aiml's point holds too: LLMs write `\{ \}` as a pair, and a fmt diff that strips `\}` teaches nothing.

Q3-c (remove `\}`) re-opens the 6-0 escape-table vote with no new evidence. No.

###### Q5: one normative sentence in §2.4, and the same table in `blink llms`
The spec is the blueprint, so the "which form when" rule goes in the spec. `blink llms` is generated from it, not written as a second source. The rule:

> One or two literal braces: `\{`. Text with `"`, `\`, or many braces: `#"..."#`. Large blobs: `#embed`.

###### Q6: support all of it
- Build W1111 under a code whose digits do not match E1111, and add its catalog row. The spec promises it today, and `#"..."#` is only safe to recommend with it.
- E1106 recovery that lexes the rest of the string as literal text up to its closing `"`.
- The fmt spec line, in the generalized form from Q3.
- Treat the `{{` misparse as type:bug, whatever the vote. The spec never says a hole may hold a bare block, so the current behavior is an accident, not a decision.

```blink
fn render(name: Str, count: Int) -> Str {
    let a = "set: \{a, b}"
    let b = #"{"user":"#{name}","n":#{count}}"#
    // "{{name}}"      -> error[InterpDoubleBrace]
    // "{ {name} }"    -> error[InterpDoubleBrace]
    // #"#{{name}}"#   -> error[InterpDoubleBrace]
    a + b
}
```

**Position: stable, ready to vote.** Q1-K, Q2-L (total-rewrite trigger, warning), Q3-a, Q4-E (token rule, all forms and depths), Q5 spec sentence plus llms, Q6 all.

##### DevOps/Tooling


###### Corrections to the record
- Min (M1) and PLT say "W1111 catches a forgotten `#`". It does not. The spec has the warning, but the compiler has no emit site for it: `#"x {name} y #{name}"#` prints `x {name} y Al` and gives no warning. So in raw strings the safety net that M1 relies on is not there. Building W1111 is a precondition of Q1-K, not an extra.
- Today the toolchain has two diagnostic gaps where the panel's Phase A texts assumed working diagnostics: W1111 (missing) and `{{x}}` (silent; AIML's find). Q4 and Q6 fill them.

###### Q1 — **Q1-K: for.**
All six agree, and I have no more to add.

###### Q2 — **Q2-L: for, with this shape**
- **Trigger: Web's version.** It fires on 3 or more `\"`/`\{` escapes, and only when converting to `#"..."#` removes all of them. That is, the body has no `\n`, `\t`, `\u{..}` or other escape that `#"` cannot hold. This is the same condition I gave for the E1106 quickfix, so one rewrite routine serves both. A lint must never suggest a fix that does not apply.
  - Sys's "any `\{` plus `\"`" fires on two-escape strings such as `"\{\"k\""`. That is too noisy for the 669 test files.
- **Level: a `blink lint` warning, not a compile warning.** If `blink build` printed it, every test that holds embedded source would flood compile output. As a lint finding with a machine-applicable fix, it shows in the LSP as a squiggle with a one-click fix, and `blink lint --fix` migrates the corpus as a chore. Gate rule: the CI lint gate may baseline existing hits, so no stop-the-world migration.
- To Min's Q2-N: docs alone failed already. 669 test files use `\{` and never use `#"`, and the authors had the docs. The diagnostic reaches people at the moment they need it, and docs do not.

###### Q3 — **Q3-a: for. Q3-b: against. Q3-c: against.**
Today `blink fmt` never changes the bytes inside a string literal. That is a property worth keeping: a fmt run can never change a string's meaning, and goldens stay simple. Q3-b breaks that property for no change in value, and it puts diff churn into every test that embeds `\{...\}`. If the panel wants one canonical spelling, put it in the Q2 lint as a fix, not in fmt.

My spec line for Q6 says the same thing, more strictly: **"`blink fmt` does not change the kind or the body of a literal."**

###### Q4 — **Q4-E: strongly for**, with two details for the panel
1. **Scope of the rule.** It should cover "the first token of the hole expression is `{`", not only "`{` directly after `{`". Then `"{ {x} }"` is caught too. A hole that really needs a leading block or map literal can start with `(`, as in `"{({x})}"`, and the help text says so. This is the precise rule.
2. **Fix-it.** The fix is machine-applicable: rewrite `{{x}}` → `\{x}`. The second help line names `#"..."#`.

This is the only option on the table that turns a silent wrong output into a loud error. That is the same test §2.4.3 used to pass `t"..."`. It changes which programs the compiler accepts, so it needs a spec vote. Separately, it should go in as a type:bug with an MVCE.

###### Q5 — **§2.4.2's existing "When to use which string form" list, tightened to one rule, with `blink llms` copying it word for word.**
- The list is already there, so this is an edit, not a new section. Keep one source of truth: the llms topic should be generated from, or checked against, the spec text, so the two cannot drift.
- The help texts for E1106, InterpDoubleBrace and the Q2 lint must use the same wording.

###### Q6 — items, as I proposed them
- **W1111:** build it (type:bug, because the spec requires it). Give it a code whose digits do not match E1111. This code change is the one spec vote here.
- **Spec line (vote):** "`blink fmt` does not change the kind or the body of a literal; the lint does."
- **E1106 recovery (chore):** after E1106, treat the rest of the string as literal text up to its closing `"`. Then `blink fmt` and the LSP still work on the rest of the file.
- **E1106 quickfix (chore):** convert to `#"..."#`, using the shared rewrite from Q2.

###### Position summary
| Q | Position |
|---|---|
| Q1 | K |
| Q2 | L: Web trigger, `blink lint` warning, autofix |
| Q3 | a |
| Q4 | E: first-token rule, `(` escape hatch, autofix |
| Q5 | tighten the §2.4.2 list; llms copies it; diagnostics use the same words |
| Q6 | as listed; the fmt line and the W1111 code are the only votes |

Stable, ready to vote.

##### AI/ML


###### Q4 first, because no other panelist has addressed it

The moderator re-ran my probe and confirmed the result: `"a {{x}} b"` prints `a 5 b`.

This is the one silent failure in the brace story that the grammar CAN close. Devops and PLT both wrote that the only silent hazard is `"{id}"`, meaning literal text that happens to be a name in scope. That is not true. `{{id}}` is a second silent hazard, and it differs from the first in two ways:

- It is the most likely way an LLM writes a literal brace: Python format and f-strings, Rust `format!`, C# `$""`, and the Jinja and Handlebars habit.
- The author's intent is not in doubt. Nobody writes `{{x}}` to get the value of `x`.

On PLT 3c ("`{{` needs extra lookahead"): Q4-E is the opposite of 3c. It does not make `{{` an escape. It rejects `{{`.

- The check runs in the parser, at the token after the hole's opening `{`. The parser already reads that token.
- The lexer does not change.
- The rule takes away nothing: a block expression in a hole is never needed, because the expression can go in the hole directly.

I ask sys, plt and devops to vote on Q4 directly and not treat it as a side issue. The ticket's own principle is "match LLM priors". Q4 is the one option on the table that deals with a prior that collides with ours.

###### Positions

- **Q1 — Q1-K, for.** All six panelists agree. Nothing to add.

- **Q2 — Q2-L, for**, with web's trigger: "3 or more `\"`/`\{`, AND converting to `#"..."#` removes all of them."
  - This trigger never fires on a string that also needs `\n`/`\t`/`\u{..}`. Code-in-test strings often need those, so the trigger does not fire on the noisy test cases PLT is worried about.
  - It fires only when the fix is complete.
  - Level: **warning**, not info. LLM agents and CI read warnings and skip info lines. A lint that agents cannot see teaches nothing.
  - The fix is machine-applicable, and it is the same rewrite as devops's E1106 quickfix (Q6), so the code has one implementation.
  - Min's Q2-N leaves the 669 test files in their current state. Those files are a fair sample of what LLMs see today.

- **Q3 — Q3-b, mild preference; Q3-a is acceptable.** This is a change from my Phase A position, which was Q3-a.
  - The reason is the training data. Formatted Blink source becomes the corpus that future models learn from, and one spelling in that corpus is worth more than symmetry.
  - Keep `\}` valid. No error, so a model that writes `\{...\}` still compiles.
  - Q3-c (error) is against: it would reject an escape that does no harm.
  - Q3-b fits devops's rule: fmt changes the spelling of an escape, not the kind of the literal.

- **Q4 — Q4-E, for.** I propose the name `InterpDoubleBrace`. The help text names `\{` and `#"..."#`. Attach the same convert quickfix from Q6.

- **Q5 — §2.4 gets one normative sentence, and `blink llms` gets the table.**
  - `blink llms` is the surface that LLMs actually load into context, so the table must be there.
  - A spec sentence keeps the two from drifting apart.
  - I can accept min's position (chore only) if the `blink llms` table is required.

- **Q6 — for all items.**
  - Implement W1111 under a code whose digits do not match E1111.
  - Add the line "fmt does not change literal kind; the lint does."
  - E1106 recovery: one bad brace gives one error. Cascades of errors after it confuse agents more than anything else in a diagnostic stream.
  - The E1106 convert quickfix.
  - W1111 matters for my domain because it is the safety net under Q2. If the lint pushes code to `#"..."#`, then a `{name}` with the `#` forgotten must be loud.

###### Summary

| Q | Position |
|---|---|
| Q1 | K |
| Q2 | L (web trigger, warning, autofix) |
| Q3 | b (a acceptable) |
| Q4 | E |
| Q5 | spec sentence + `blink llms` table |
| Q6 | all items |

Stable, ready to vote.

##### Minimalism

###### Min — Phase B round 1

All six of us land on Q1-K. The open work is in the small items. I change my position on two of them (Q2, Q3).

###### Q1 — Q1-K: keep both forms, no marker. **Yes.**
Nothing to add. Every panelist rejected the marker and each single-form cut for the same reasons.

###### Q2 — escape-heavy lint. **Yes, with limits (moved from Q2-N).**
A diagnostic is the tool I asked for over syntax, so I cannot oppose one that adds no surface. My conditions:
- **Trigger:** web's form. Fire on 3 or more `\"`/`\{` escapes, and only when converting to `#"..."#` removes all of them. Without the second clause, the lint suggests a rewrite that keeps `\n` or `\u{..}`, and that rewrite cannot be done.
- **Level:** devops's info level, not a warning. Hundreds of test files embed Blink and C source in `"..."`. A warning makes all of them noise or `@allow` clutter in the gate, and people learn to ignore a lint that fires on every test.
- **Fix:** one machine-applicable rewrite, shared with the E1106 quickfix (devops). One rewrite engine, two entry points.

I reject sys's "any `\{` together with `\"`" trigger. One brace and one quote is not a case for a raw string.

###### Q3 — `\}`. **Q3-b (moved from M2).**
plt's option beats my M2. `\}` stays legal, so nothing breaks, no migration, and LLM habit (`\{x\}`) still compiles. `blink fmt` rewrites `\}` to `}`, so source keeps one spelling. It gets the subtraction with no error code. This does not conflict with devops's rule: `\}` to `}` keeps the literal a plain `"..."`, so the literal kind does not change. I withdraw M2.

###### Q4 — `{{` at the start of a hole: Q4-E. **Yes, strongly.**
This is the most important finding of the session, and it removes a form instead of adding one. I checked:
- The spec has no expression that starts with `{` other than a block. Struct literals start with the type name, and lambdas start with `fn`.
- So a hole that starts with `{` is never needed. `"{x}"` already says what `"{{x}}"` says.
- Rejecting it costs nothing, and it closes a silent wrong-output bug that §2.4's own reasoning forbids.

Two notes:
- The `{{x}}` misparse is a bug whatever the vote decides. File it as `type:bug` now.
- Rule: the first non-space character of a hole may not be `{`, so `"{ {x} }"` is caught too. Inside `#"..."#` the hole is `#{`, so `#"{{x}}"#` stays literal, as aiml says.

###### Q5 — where the rule lives. **One sentence in §2.4, mirrored in `blink llms`.**
I move a little toward sys. A one-sentence rule in the spec is cheap and gives the llms table one source to copy. No new subsection, no table in the spec:
- one brace → `\{`
- quotes, backslashes or many braces → `#"..."#`
- large text → `#embed`

###### Q6 — devops tooling items.
- **Implement W1111:** yes, as a `type:bug` (the spec requires it). No vote needed.
- **Renumber W1111 away from E1111:** **no.** Shared digits across W and E are normal in this catalog already (0310, 0501, 0601, 0610, 0700 and more). Renumbering one code is churn and breaks the existing pattern.
- **Spec line "fmt does not change literal kind; the lint does":** yes. It is one line, and it fixes who owns each rewrite, which keeps the fmt goldens stable. It fits with Q3-b, as shown above.
- **E1106 recovery:** a `type:bug`/chore, not a vote. One bad brace must not stop `blink fmt` on the file.

###### Position summary
Q1-K yes · Q2-L yes (web trigger, info level, shared fix) · Q3-b · Q4-E yes · Q5 one §2.4 sentence + llms mirror · Q6: W1111 bug yes, renumber no, fmt line yes, recovery chore.

Stable, ready to vote.

#### Phase C — Silent vote

Ballot: see the Result table above. Each panelist's full vote:

##### Systems


###### Q1: K
**Reasoning:** `\{` and `#"..."#` reduce to the same literal-segment and hole list before codegen, so neither costs anything at runtime. Each does a separate job: `\{` escapes one character, and `#"..."#` changes the literal kind. A marker brings back the silent missing-`f` bug that §2.4 rejected.
**Concern:** The silent `"{id}"` case stays, and no grammar can catch it. Docs and the lint must make `#"..."#` the reflex for brace text.

###### Q2a: L
**Reasoning:** The check costs one counter and one flag in the string scan, with nothing measurable in the lexer hot loop. Because of the "removes all of them" condition, the rewrite always applies and stays safe, so `--fix` can migrate the corpus in one pass.
**Concern:** The tests/ corpus may give thousands of hits on day one. The migration chore must land with the lint, or people learn to ignore it.

###### Q2b: W
**Reasoning:** A diagnostic teaches the form at the moment of need only if the author or the LLM repair loop sees it. `blink build` output is where that loop looks. A warning does not block the build, so the cost is only noise, and `--fix` removes that noise.
**Concern:** If the corpus migration lags, build output gets noisy and people turn on a blanket `@allow`, which hides the lint everywhere.

###### Q2c: QBS
**Reasoning:** `#"..."#` removes `\\` as well, and regex and C emission are the main producers of `\\`. Counting it costs the same as counting the other two. It also matches the rule wording in Q5: "text with `"`, `\` or many braces".
**Concern:** Regex strings with only `\\` will start to warn where some authors prefer the plain form, so the threshold of 3 must hold.

###### Q3: b
**Reasoning:** The escape is valid and costs nothing, so the LLM habit of writing `\{...\}` in pairs still compiles. This repo is training data, and one spelling in formatted source stops the two-spellings pattern from spreading. The literal value does not change, so this is a spelling normalization, not a kind change.
**Concern:** A one-time fmt diff across src/ and tests/, plus fmt golden churn. Land it as one chore commit.

###### Q4a: E
**Reasoning:** This is the only silent wrong output found here, and it hits the strongest cross-language prior (`{{` in Python, Rust and C#). The cost is one token check at hole-parse start, with no lexer lookahead. Blink has no brace map literal, so a block as a hole's first token is never needed, and `( )` covers any odd case.
**Concern:** Some user may have used a block in a hole on purpose. The help text must show the `( )` and plain-expression rewrite.

###### Q4b: ALL
**Reasoning:** PLT measured `#"a #{{x}} b"#` printing `a 5 b`, so the same silent bug exists at every depth. A single rule is one check in the shared hole parser, with no branch per string form. A rule scoped to plain strings would keep the same bug at every depth.
**Concern:** None from my side. The check is in one shared code path.

###### Q5: S
**Reasoning:** `blink llms --full` and the diagnostic help texts both derive from the spec. A rule that lives only in docs goes out of date and splits from the help wording. One normative sentence costs nothing to keep.
**Concern:** The spec sentence, the `blink llms` table and the E1106/lint help texts must use the same words, or we have three slightly different rules.

###### Q6a: N
**Reasoning:** I checked ERROR_CATALOG.md: E0501 CapabilityBudgetExceeded and W0501 UnknownMethod are not related, so unrelated pairs that share digits are already normal practice. Renumbering only W1111 makes it an exception. If shared digits are a problem, that is a catalog-wide question for its own ticket.
**Concern:** Readers can still confuse W1111 with E1111 UnknownIntrinsic. The help text and the catalog name carry the difference.

###### Q6b: K
**Reasoning:** "fmt does not change the kind" keeps fmt idempotent and gives the lint sole ownership of form changes. B also locks the body spelling, which blocks Q3-b, and I voted for Q3-b. Normalizing a no-op escape is formatter work. It does not change the kind and needs no lint.
**Concern:** If Q3-a wins, K is still correct but weaker than B. The spec line must then say fmt keeps the escape spelling, so that later fmt work does not rewrite it in silence.

##### Web/Scripting


**Q1. Vote: K.**
Reasoning: An LLM or a JS/Python/Kotlin developer writes `"Hello, {name}"` and it works, so the 90% case costs nothing. Adding a marker brings back the silent bug where a missing `f` compiles. Removing either form makes a common case worse: one brace in a message, or JSON.
Concern: people will keep pasting JSON into `"..."` and say the language has "too many backslashes" until the lint ships.

**Q2a. Vote: L.**
Reasoning: Users do not read §2.4. They read what their editor shows them. A lint with a one-key fix is how they learn `#"..."#` at the moment they need it. The guard that the conversion must remove every escape keeps the lint from pushing a rewrite that only partly helps.
Concern: the threshold of 3 can still flag short strings whose author is happy with them, so the lint must be easy to turn off.

**Q2b. Vote: LW.**
Reasoning: In the editor it shows where it helps, with the fix attached. It keeps `blink build` output clean, so nobody learns to ignore build warnings because of a style hint. This is how ESLint and Ruff style rules work, and web developers expect that.
Concern: someone who never runs `blink lint` or the LSP will never see it, so the `blink llms` table must carry the same rule.

**Q2c. Vote: QBS.**
Reasoning: Regex is the second big use case in §2.4.2. In regex the pain is `\\`, not `\{`. Python developers already reach for `r"..."` because `"\\d+\\.\\d+"` is hard to read. Counting `\\` catches that case, and the conversion is safe, because `#"..."#` holds a backslash as is.
Concern: Windows-path strings like `"C:\\x\\y\\z"` will be flagged, but the rewrite is correct and easier to read, so I accept that.

**Q3. Vote: a.**
Reasoning: Writing `\{...\}` as a pair is a strong habit. If fmt deletes half the pair, people ask "where did my escape go?", and every one of those rewrites is diff churn on correct code. The formatter should leave both spellings alone.
Concern: codebases will mix `\}` and `}`, but that mix is harmless and reads the same.

**Q4a. Vote: E.**
Reasoning: `{{x}}` is the brace escape that Python, C#, Rust and Kotlin developers try first. Today it compiles and prints the value with no warning, which is the "ship broken output with no error" bug that §2.4 exists to stop. A block as a hole's first token has no real use, and the help tells the user to wrap the expression in `( )` if they need to.
Concern: some generated or templated Blink could depend on `{ {x} }` today, so the implementation ticket must grep the repo and the examples first.

**Q4b. Vote: ALL.**
Reasoning: The rule "a hole may not start with a block" is one sentence with no exceptions, and an LLM can apply it everywhere. `#"#{{x}}"#` is the same silent bug at depth 1. Leaving it legal makes the rule depend on which string form you are in, and that is how Stack Overflow questions start.
Concern: an error inside `#"..."#` could surprise someone who thought braces are always literal there, so the help text must say that `#{` opens a hole.

**Q5. Vote: S.**
Reasoning: One sentence in the spec, copied word for word into `blink llms` and the help texts, means the docs, the tools and the LLM all give the same answer. A table that exists only in `blink llms` will drift from the spec.
Concern: "one or two braces" is a soft number, and the help texts must not contradict the lint's threshold of 3.

**Q6a. Vote: Y.**
Reasoning: The existing pairs that share digits (E0310/W0310 and the others) describe one problem at two severities. W1111 and E1111 UnknownIntrinsic have nothing to do with each other. Someone who searches for "1111" finds the wrong page, so the code should change before W1111 is built and anyone depends on it.
Concern: if nobody updates §2.4.2 at the same time as the catalog row, the spec keeps the old number.

**Q6b. Vote: B.**
Reasoning: This follows from my Q3-a vote. Fmt must keep whatever the author typed, so the result is stable and nothing surprises the author. Every rewrite of a literal goes through the lint, where the user sees it and chooses it.
Concern: none worth noting, except that it rules out Q3-b by design.

##### PLT


###### Q1: K
**Reasoning.** `\{` and `#"..."#` are not two ways to do one thing. `\{` escapes one character in a cooked string. `#"..."#` changes the literal kind and moves the hole opener. Each is the only form that composes on its own axis. A marker reopens §2.4, and it brings back the silent-wrong-output case that §2.4.3 uses to tell `t` apart from `f`.
**Concern.** The silent case `"{id}"`, with `id` in scope, stays open. No lexical rule can close it.

###### Q2a: L
**Reasoning.** The trigger fires only when the rewrite is total, so the lint's claim ("this converts cleanly") is true each time it fires. That makes the diagnostic a sound suggestion and not a heuristic guess. It also carries out the Q2 soft consensus for targeted diagnostics.
**Concern.** A test file full of embedded source can get many hits. The fix must be correct at every depth: it must choose the smallest depth whose closer does not occur in the body.

###### Q2b: LW
**Reasoning.** This lint is about style, not meaning. Both forms denote the same `Str`. `blink build` output should report problems with what the program means. Style suggestions belong in `blink lint` and the LSP, where the fix can be applied.
**Concern.** If the lint never shows in `blink build`, users who only build never see it. That lowers its value as a way to teach the forms.

###### Q2c: QBS
**Reasoning.** Count every escape that the rewrite removes. `\\` goes away exactly as `\"` and `\{` do. If `\\` does not count, the trigger is an arbitrary subset of the rewrite it offers. Regex and C emission strings are mostly `\\`, and §2.4.2 lists them as main use cases.
**Concern.** If this loses, regex-heavy strings that convert cleanly are never flagged.

###### Q3: a
**Reasoning.** One owner for each rewrite: fmt keeps literal bodies as written. Q3-b breaks the Q6b-B rule for a one-character gain. It also strips the `\{ \}` pairs that LLMs write on purpose, and that diff teaches nothing.
**Concern.** `}` and `\}` remain two spellings of the same text, and a minimalist can fairly call that a "one way" defect.

###### Q4a: E
**Reasoning.** A hole whose expression is the block `{e}` means the same as a hole whose expression is `e`, so the rule removes no expressiveness. An expression that must start with a brace form can be written as `({ ... })`. The rule turns the strongest LLM prior for a literal brace, `{{`, from silent wrong output into a compile error. That is the same principle that admitted `t"..."`.
**Concern.** A future brace-led expression form, such as a map or record literal, would need the `( )` wrap inside holes, so new syntax must account for this rule.

###### Q4b: ALL
**Reasoning.** Today `Str` and `Template[C]` share one hole grammar at every depth. A rule that applies only to some forms splits that grammar in two, and the spec must then say which grammar applies where. `#"a #{{x}} b"#` prints `a 5 b` today, so the misparse exists in raw strings too. Only the hole opener differs between depths. What may go inside a hole must not differ.
**Concern.** In raw strings the error may catch text that someone wrote deliberately, although none exists in the repo today.

###### Q5: S
**Reasoning.** The spec is the blueprint, and `blink llms` and the help texts derive from it. With the rule in the spec there is one source and copies of it, not two sources that drift apart. The rule is total, since what the text contains decides the form, so it can be written as normative text.
**Concern.** Words like "one or two" and "many" are fuzzy at the edges. The spec text must make clear that this is guidance, so that no one treats it as a compile rule.

###### Q6a: Y
**Reasoning.** The catalog convention is that shared digits mark the same concept with two severities: E0310/W0310, E0601/W0601 and the other listed pairs. W1111 (forgotten `#` in a raw string) and E1111 (UnknownIntrinsic) are not related, so sharing digits breaks the convention. The fix is free now, because W1111 has no emit site and no catalog row.
**Concern.** The spec text, the docs and any test that names W1111 must all change in the same commit, or the old code remains as a dangling reference.

###### Q6b: B
**Reasoning.** If fmt keeps both the kind and the body of a literal, fmt is the identity on literal content. That is simple to state, it gives fmt one less way to fail its idempotency check, and it is the only form consistent with Q3-a. K alone leaves open whether fmt may change escape spellings.
**Concern.** fmt has some normalization of literals today, such as unicode escape case. Check for it before the spec states B, or the spec will describe a formatter that does not exist.

##### DevOps/Tooling


###### Q1 — K
**Reasoning:** A marker can be missing while the code is still valid, so no diagnostic can catch the missing case, and it gives the formatter a second cooked syntax. Removing either form makes the fix-it worse: the help line would have to send people to a form that does not fit what they wrote.
**Concern:** The silent `"{id}"` case (literal text meant, but `id` is in scope) stays open, and no tool can flag it.

###### Q2a — L
**Reasoning:** Docs did not work: 669 test files use `\{` and never use `#"`. A lint with a machine-applicable fix teaches `#"..."#` at the moment it is needed, in the editor. The "removes all escapes" condition means the fix is always valid, and it shares one rewrite routine with the E1106 quickfix.
**Concern:** The rewrite has to pick the delimiter depth correctly when the body contains `"#`. A test for each depth must gate it.

###### Q2b — LW
**Reasoning:** It is a style finding, not a correctness finding. In `blink build` output it would flood every test that embeds source text and bury real warnings. In `blink lint` and the LSP, it shows where the person can apply the fix with one click, or across a corpus with `--fix`.
**Concern:** If W wins, the CI lint and build gates will need a baseline or a mass migration in the same change, or they go red.

###### Q2c — QBS
**Reasoning:** Regex and C emission are escape-heavy because of `\\`, and §2.4.2 lists them as `#"..."#` use cases. A count that leaves out `\\` misses half the target strings. The "removes all escapes" guard already keeps strings with `\n` out of the count.
**Concern:** Windows paths and short regexes cross 3 often, so the lint may feel noisy until people learn the raw form.

###### Q3 — a
**Reasoning:** Today a fmt run never changes the bytes inside a literal, so fmt can never change what a string means, and goldens stay simple. Q3-b breaks that property for no change in value and causes churn in every test that embeds `\{...\}`.
**Concern:** Source keeps two spellings of `}`, so a corpus-trained model sees both. That is a small cost.

###### Q4a — E
**Reasoning:** It is the only option on the ballot that turns a silent wrong output (`"a {{x}} b"` → `a 5 b`) into a loud error. The fix-it is precise: rewrite to `\{x}`, or wrap the expression in `( )`. A block expression is never needed in a hole, so no valid use is lost.
**Concern:** A hole that starts with a map or record literal now needs `( )`. The help text must say this, or users will read the error as a bug.

###### Q4b — ALL
**Reasoning:** The moderator measured `#"a #{{x}} b"#` → `a 5 b`, which is the same silent bug at depth 1. One rule for every form and depth is one diagnostic, one catalog row, and one test matrix. `#"{{x}}"#` stays literal text with no hole, so W1111 covers it.
**Concern:** The parser must apply the check after each depth's hole opener and must not apply it to literal `{` text. Its tests must cover depths 1 through 3 and `t#` forms.

###### Q5 — S
**Reasoning:** The help texts for diagnostics need one wording to cite. If the rule lives only in a `blink llms` chore, it drifts from §2.4.2's existing "When to use which" list. Tightening that list is an edit, not a new section, and llms should copy it word for word.
**Concern:** A normative "should" in the spec with nothing enforcing it may go stale. The Q2 lint is the part that keeps it true.

###### Q6a — Y
**Reasoning:** W1111 has no emit site and no catalog row, so a new number costs nothing now and costs real migration later. Other E/W pairs share digits, but for W1111 and E1111 (UnknownIntrinsic) the two concepts are not related. `blink explain 1111` and searches would mix them up.
**Concern:** If the catalog's convention is that shared digits mean related concepts, the new number must follow it. Verify this before assigning.

###### Q6b — B
**Reasoning:** "Body unchanged" is the stronger and simpler invariant to test. Fmt goldens can check it by comparing each literal's raw bytes before and after formatting. The lint owns every change to how a literal is spelled, so each change has an owner and a fix-it.
**Concern:** If Q3-b wins, B cannot pass with it. The moderator must then fall back to K, with one exception for `\}`.

##### AI/ML


**Q1 — Vote: K**
- **Reasoning:**
  - Universal interpolation keeps the most common LLM output, `"Hello, {name}"`, correct.
  - A marker would make a missing marker the silent bug.
  - `\{` and `#"..."#` do different jobs, so keeping both adds no decision point for a given text.
- **Concern:** the silent `"{id}"` case, where literal text happens to be a name in scope, stays open, and only docs can reduce it.

**Q2a — Vote: L**
- **Reasoning:**
  - The lint teaches `#"..."#` at the moment an agent or developer pastes JSON or regex into a plain string, with a fix that a machine can apply.
  - The "removes all escapes" condition keeps it quiet on strings that also need `\n`, so the noise stays low.
- **Concern:** the 669 test files that use only `\{` may produce many hits until a `lint --fix` chore cleans them.

**Q2b — Vote: W**
- **Reasoning:**
  - LLM agents mostly run `blink build`, `blink run` and `blink test`, not `blink lint`.
  - Under LW, the agent that writes the escape-heavy string never sees the lint, so it does not learn.
  - Info level is filtered out even more.
- **Concern:** warnings in build output from old test files could hide more important warnings until the migration chore runs.

**Q2c — Vote: QBS**
- **Reasoning:**
  - §2.4.2 lists regex as a primary use of `#"..."#`, and regex text is full of `\\`, not `\"`.
  - If `\\` does not count, the lint misses the regex case it exists for.
  - The count rule stays one sentence: every escape `#"` makes needless.
- **Concern:** C-emission strings with `\\n` meant as literal backslash-n may trigger the lint, and the rewrite reads less clearly to some people.

**Q3 — Vote: a**
- **Reasoning:**
  - I move from b to a so that the formatter rule stays coherent with Q6b-B. "fmt never touches a literal's body" is one rule that an agent can predict.
  - Both spellings compile, so the training-data cost of two spellings is small.
- **Concern:** the corpus keeps `\{...\}` and `\{...}` mixed, and models will copy both.

**Q4a — Vote: E**
- **Reasoning:**
  - `{{x}}` is the strongest literal-brace prior from Python, Rust, C# and Jinja, and today it prints the value with no error.
  - That is the exact failure §2.4 exists to prevent.
  - The rule takes nothing away, because `( )` or the bare expression covers every real use.
  - It turns the most likely LLM mistake in this area into a compile error with the fix in the help text.
- **Concern:** a hole that starts with a map, set or struct literal (if Blink has `{`-initial literals) would need `( )`. That is a small and documented cost.

**Q4b — Vote: ALL**
- **Reasoning:**
  - One rule for every form and depth is one fact to learn; a rule scoped to some forms is a second decision point.
  - The moderator confirmed that `#"a #{{x}} b"#` gives the same silent `a 5 b`, so the hazard exists at every depth.
- **Concern:** none of note. `#"{{x}}"#` stays literal text, so the rule does not affect JSON-in-raw-string use.

**Q5 — Vote: S**
- **Reasoning:**
  - `blink llms` is generated from the spec, and diagnostic help texts should quote one source.
  - A normative sentence keeps the spec, the docs and the diagnostics from drifting into three slightly different rules.
  - The rule is short and is decided by what the text contains.
- **Concern:** the spec could become prescriptive about style, and a later reader could take the rule as a compiler-enforced restriction.

**Q6a — Vote: Y**
- **Reasoning:**
  - Agents look up codes by number (`blink explain`, grepping the catalog).
  - The existing pairs that share digits (E0310/W0310 and others) look like related diagnostics.
  - W1111 (forgotten `#` in a hole) has no relation to E1111 (UnknownIntrinsic), so the shared digits suggest a link that does not exist.
- **Concern:** if the catalog's intent is that digits are independent for each prefix, then renumbering breaks that convention for no gain.

**Q6b — Vote: B**
- **Reasoning:**
  - A formatter that never changes a literal's body is easy to predict and keeps fmt goldens stable.
  - Every change to a literal then comes from the lint, with an explicit diagnostic, which agents can trace.
  - This is consistent with my Q3 vote.
- **Concern:** the redundant `\}` spelling never converges in the corpus unless someone later adds a lint for it.

##### Minimalism


###### Q1 — K
**Reasoning:** The two forms do different jobs, so the ticket's "one way" premise does not hold. A marker brings back the silent missing-prefix bug that §2.4 removed in a locked vote. Removing either form costs hundreds of rewrites and takes out nothing complex.
**Concern:** Plain strings keep the silent `"{name}"`-meant-literally hazard, and no rule can catch it.

###### Q2a — L
**Reasoning:** A diagnostic adds no language surface, and that is the remedy I prefer over syntax. The clause "converting removes all escapes" means it never suggests a rewrite that cannot be done.
**Concern:** It could become a long-lived nag in test files that embed source text, if the threshold proves too low.

###### Q2b — I
**Reasoning:** This is a style hint, not a hazard. The code is correct, and the warning tier should stay for likely bugs. Info level stays out of gate noise and avoids `@allow` clutter in hundreds of test files. It still shows the fix in the LSP and `blink lint`.
**Concern:** Info-level hints are easy to miss, so the lint may teach `#"..."#` to fewer users than it should.

###### Q2c — QBS
**Reasoning:** Regex is a use case §2.4.2 lists, and its pain is `\\`, not `\{`. A raw string makes `\\` literal too, so counting it is the correct measure of "escapes this rewrite removes". Leaving it out means the lint misses the case that benefits most.
**Concern:** A Windows-path or C-escape string with three `\\` gets flagged where some authors prefer the plain form.

###### Q3 — a
**Reasoning:** I proposed the subtraction and then backed plt's fmt rewrite, but Q6b-B is the smaller and cleaner contract: fmt never touches a literal's body. That keeps fmt idempotent and its goldens stable. It also avoids a mass diff over src and tests that teaches nothing. Two spellings of `}` is a cosmetic cost, and a fmt rule is not worth it.
**Concern:** `\}` and `}` stay mixed in source, and that duplication is small but permanent.

###### Q4a — E
**Reasoning:** This removes a form and closes a silent wrong-output bug. No expression other than a block starts with `{`, so no valid use is lost. The help text names `( )` for the rare block-expression case. This is the most valuable change on the ballot.
**Concern:** The lexer and parser must agree on "first token of the hole", or `"{ {x} }"` and comments inside holes slip through.

###### Q4b — ALL
**Reasoning:** The moderator measured that `#"a #{{x}} b"#` gives the same silent `a 5 b`. One rule for every hole in every form is simpler to state, implement and teach than a per-form exception. `#"{{x}}"#` stays literal because it is not a hole.
**Concern:** A deeper delimiter like `##"..."##` may use a separate hole-scan path that the rule misses, unless tests cover each depth.

###### Q5 — S
**Reasoning:** One normative sentence is cheap. It gives `blink llms` and the diagnostic help texts one source to copy, so they cannot drift. Tightening the existing §2.4.2 list adds no new section.
**Concern:** The spec sentence may grow into a style guide over time, so it should stay at the three cases.

###### Q6a — N
**Reasoning:** The catalog already pairs W and E codes with the same digits five times. The prefix letter tells them apart. Renumbering breaks the pattern and causes churn for no gain.
**Concern:** Someone searching only for the digits "1111" finds both codes, which is the same small cost the other five pairs already carry.

###### Q6b — B
**Reasoning:** One owner for each kind of change: fmt owns layout, and the lint owns literal content. This is the smallest fmt contract. It goes with my Q3-a vote and avoids churn in every file that holds an escape.
**Concern:** Users who expect fmt to normalize everything may file "fmt missed `\}`" requests, and the spec line must answer them.

#### Phase D — Focused round on Q2b and Q6a

##### Systems


###### Q2b: answer to the strongest argument against W

The strongest argument came from plt, devops and web: the lint flags a style choice on code that compiles correctly, and putting it in `blink build` trains people to ignore warnings. I accept it. The case that needs teaching in build output is already covered. A plain string with an unescaped `{` fails E1106, and E1106's help names `#"..."#`, so the build-only LLM loop still learns the form when it breaks something. The lint fires only on strings that already compile and print correctly. That makes it a hint about how the code reads, and hints belong where the fix applies with one click: `blink lint` and the LSP.

**Final vote: LW** (I change from W.)
**Concern:** Users who only run `blink build` never see the hint, so the §2.4 rule sentence and the `blink llms` table must carry it, and the E1106 help must use the same words.

###### Q6a: answer to the strongest argument against N

The strongest argument came from plt, web and aiml: shared digits in the catalog mean "the same concept at two severities", so W1111 next to E1111 breaks that convention. The moderator's table disproves that premise. None of the five existing pairs is related: TemplateMismatch/RawBypassesParam, CapabilityBudgetExceeded/UnknownMethod, CloseableEscapesScope/SetButNotRead, MutationRequiresMut/ScopedValueWithoutWith, ArenaValueEscapes/UnreachableCode. The real convention is that digits are independent per prefix. Renumbering W1111 would be the only exception, and it rests on a rule the catalog does not follow. Devops's "free now" point is true, but it does not make the change correct. If shared digits do confuse people, fix that across the whole catalog in its own ticket, not for one code.

**Final vote: N** (unchanged)
**Concern:** A search for "1111" finds both codes. That is the same small cost the other five pairs carry, so the catalog row and `blink explain` should print the code with its prefix and name.

##### Web/Scripting


###### Q2b: the strongest argument against LW (aiml, sys)
Their argument: LLM agents and repair loops read `blink build` output, not `blink lint`, so under LW the author who writes the escape-heavy string never sees the lint.

My answer: a repair loop acts on failures. An escape-heavy string that compiles is not a failure, so the loop has nothing to repair. When the string does break, the E1106 help and its quickfix already name `#"..."#` in build output. Agents learn the rule before they write anything from the Q5 sentence in the spec and in `blink llms`. With W, about 787 test files that embed source text would flood every build. That is how developers learn to skim past warnings, or to add a blanket `@allow` (sys names this risk in their own concern). Real warnings would then get lost in the noise.

**Final vote: LW.**
Concern: someone who never opens an editor with the LSP and never runs `blink lint` will not get the nudge, so the Q5 rule has to do that teaching alone.

###### Q6a: the strongest argument against Y (sys, min)
Their argument: shared digits already mark unrelated codes, so renumbering only W1111 makes it the exception.

My answer: they are right, and my Phase C reason was wrong. I claimed that the five existing pairs describe one problem at two severities. The moderator's table shows that each pair is unrelated: TemplateMismatch/RawBypassesParam, CapabilityBudgetExceeded/UnknownMethod, and the others. So E and W numbers are separate namespaces, and the prefix letter is what tells them apart. Renumbering W1111 alone would suggest a convention the catalog does not have. If shared digits ever confuse users, that is a catalog-wide question for its own ticket.

**Final vote: N (changed from Y).**
Concern: `blink explain 1111` without a prefix is ambiguous, so the explain command must ask which code the user means, or list both.

##### PLT


###### Q2b: answer to the strongest argument against LW
**The argument (sys, aiml):** the LLM repair loop reads `blink build` output, so a lint shown only by `blink lint` never teaches the agent that wrote the string.

**My answer:** The moment of need is a brace that fails to parse. That is E1106, an error in build output, and its help text and quickfix already name `#"..."#`. A string with many escapes that compiles has the right meaning, so build output has nothing to tell its author. If build output also carries style findings, thousands of them across tests/, the loop learns to skip warnings. That cost falls on the warnings about meaning, which are what build output is for. The `blink llms` rule (Q5-S) teaches the agent before it writes, which is a better time than after.

###### Q6a: answer to the strongest argument against Y
**The argument (sys, min):** the moderator's table shows that the five E/W pairs sharing digits are all unrelated, for example 0501 CapabilityBudgetExceeded and UnknownMethod. So shared digits do not mean "related" in this catalog.

**My answer:** That fact refutes my Phase C reasoning, which said shared digits mark one concept at two severities. That claim was wrong. With the actual convention ("the letter prefix names the code, and digits are independent for each prefix"), renumbering W1111 alone makes it an exception to the convention for no gain. If shared digits confuse people, that is a question for the whole catalog and needs its own ticket. I change my vote.

###### Final votes
- **Q2b: LW.** Concern: someone who never runs `blink lint` or the LSP sees the rule only in `blink llms` and in the help text for E1106.
- **Q6a: N** (changed from Y). Concern: a reader who searches only for the digits "1111" can still find UnknownIntrinsic, so the catalog row and the help text for W1111 must carry its name.

##### DevOps/Tooling


###### Q2b: answer to the strongest argument against LW
**Argument (sys, aiml):** LLM repair loops read `blink build` output. Under LW, the agent that writes the escape-heavy string never sees the lint.

**Answer:** That loop exists to fix what is wrong, and this string is not wrong: it compiles and gives the right value. If a style hint appears in `blink build` output, the repair loop treats it as something it must fix. The loop spends turns on rewrites that do nothing, and people learn to filter build warnings, which hides the real ones (W1111, the unused-variable class). A W-level hint is also useless for teaching in this corpus: hundreds of test files that embed source would fire it on every build until a mass migration lands. The teaching path for agents that never run the linter is the Q5 rule in `blink llms` plus the E1106 help text and quickfix. Those reach the agent at the moment the agent really fails.

###### Q6a: answer to the strongest argument against Y, and a changed vote
**Argument (sys, min):** E/W pairs with the same digits are already unrelated: all five pairs in the moderator's table, for example E0501 CapabilityBudgetExceeded and W0501 UnknownMethod. So the digits are independent for each prefix.

**Answer:** The fact holds, and it removes my Phase C reason. I had assumed shared digits meant related diagnostics, and none of the five pairs are related. I also checked the tool surface: `blink explain 0501` gives "unknown error code", and `blink explain W0501` works. Lookup always needs the prefix, so no tool confuses the two codes. Renumbering W1111 alone would make it an exception to a convention that already holds. If digit collisions are ever a real cost, that is a question for the whole catalog, in its own ticket.

###### Final votes
- **Q2b: LW.** Concern: users who never run `blink lint` or the LSP never see the hint, so the `blink llms` table and the E1106 help text must carry the same rule word for word.
- **Q6a: N** (changed from Y). Concern: the W1111 catalog row needs a clear name, so that the name, not the digits, keeps it apart from E1111 UnknownIntrinsic in searches.

##### AI/ML


###### Q2b: the strongest argument against W

**The argument (plt, web, devops):**
- The lint is about style, not meaning.
- In `blink build` output it fills the build with hits from test files and buries real warnings.
- It teaches people to ignore build warnings.

**My answer:**
- I accept this argument for my own domain as well. Agent repair loops treat each build warning as something to fix.
- A style warning in build output pulls the agent into rewrites that change no meaning. It also teaches the agent that some warnings are noise, so it cares less about real warnings like W1111.
- The teaching I wanted from a warning in build output can come from somewhere else: the Q5-S normative rule, copied into `blink llms`. That is the text agents load before they write code.

I change my vote to LW.

###### Q6a: the strongest argument against Y

**The argument (sys, min):** the moderator's table shows that the five pairs that share digits are all unrelated concepts. Examples: E0501 CapabilityBudgetExceeded / W0501 UnknownMethod, and E0700 ArenaValueEscapes / W0700 UnreachableCode. So digits are independent for each prefix.

**My answer:**
- My Phase C reasoning depended on the opposite premise: that shared digits meant related concepts. The catalog shows that premise is false.
- If W1111 alone is renumbered, it becomes the exception to a pattern that already exists everywhere.
- If shared digits cause confusion in lookups, then all five pairs cause it. That is a catalog-wide question for its own ticket, not for [the brace-escape ticket].

I change my vote to N.

###### Final votes

| Q | Vote | Concern |
|---|---|---|
| Q2b | **LW** | An agent that only runs `blink build` never sees the lint, so the `blink llms` copy of the Q5 rule must ship in the same change. |
| Q6a | **N** | An agent searching for "1111" finds UnknownIntrinsic first, so W1111's catalog row and `blink explain` text must state the prefix and the name clearly. |

##### Minimalism


###### Q2b — answer to the strongest argument against I

The strongest argument against I is aiml's and sys's: info level is filtered out, so the author or LLM repair loop never sees the hint. That cost is real, but LW has the same cost. LW also leaves the hint out of `blink build`, which is where aiml says agents look. So on visibility, LW is no better than I. The LW voters and I agree on the goal: keep it out of build output, and show it in the LSP and in structured output.

The difference is mechanism, and on mechanism I wins:
- The info tier already exists and already has that behavior. ERROR_CATALOG.md says "Info diagnostics never fail a build. They are silent in terminal output by default and show in reports and structured output."
- LW invents a new kind of diagnostic: a warning that `blink build` hides but `blink lint` and the LSP show.
- That contradicts §6: "The CLI and the LSP always give the same diagnostics." If the panel wants LW, it needs a spec change to that rule. I am against adding that for one style hint.

One cost of I: today the info codes are all V-prefixed (contract verification). This lint then needs a new info code under *Info Names*. That is one catalog row, which is smaller than a new severity mode.

**Final vote: I.**
**Concern:** Info diagnostics are silent in the terminal by default, so the `blink llms` table and the E1106 help text must carry the rule, or few people learn it.

###### Q6a — answer to the strongest argument against N

The strongest argument for Y is plt's and web's: the catalog convention is that shared digits mark the same concept at two severities, and W1111/E1111 would break it. The moderator's table shows this convention does not exist. None of the five pairs are related:
- TemplateMismatch / RawBypassesParam
- CapabilityBudgetExceeded / UnknownMethod
- CloseableEscapesScope / SetButNotRead
- MutationRequiresMut / ScopedValueWithoutWith
- ArenaValueEscapes / UnreachableCode

Digits are independent for each prefix. W1111 alongside E1111 follows the actual practice, and renumbering it is the exception.

The "it is free now" argument is true, but something being free is no reason to change it. If shared digits confuse `blink explain 1111`, the problem affects six pairs, and the fix is in the catalog: `blink explain` takes the full code with its prefix. That is a separate ticket, not a one-off renumber.

**Final vote: N.**
**Concern:** If Y wins on a convention that the catalog does not follow, a later reader will treat "related concepts share digits" as a rule and keep enforcing it from this vote.

#### Q2b re-vote (user-ordered, after the BDFL ruling)

##### Systems


**Vote: I** (I change from LW.)

**Reasoning:** I read the user ruling: the §6 sentence does not bind this vote. My vote does not rest on that sentence. It rests on mechanism. The info tier already has the behavior LW asks for: it never fails a build, it is silent in terminal output, and it shows in reports, structured output and the LSP. LW would add a new rule where the severity depends on which command runs, and every tool would have to carry that rule. I also gives the LLM loop more than LW does: agents read the structured JSON output (§6), and info diagnostics appear there even under `blink build`, but LW leaves them out of build entirely. Keeping one set of diagnostics for the CLI and the LSP makes the output predictable. I keep that property whether or not the panel voted on the sentence.

**Concern:** Today the only info codes are V-prefixed contract-verification codes. This lint needs a new info code under *Info Names*, with its own prefix and a catalog row. The terminal stays silent by default, so the `blink llms` table and the E1106 help text must carry the rule.

##### Web/Scripting


**Vote: I (changed from LW).** I wrote this after the user ruling, and the ruling does not change my vote.

**Reasoning:** I voted LW for one result: the hint shows in the editor, with the fix attached, and stays out of terminal build output. Min shows that the info tier already does exactly that, as ERROR_CATALOG.md states: "never fail a build, silent in terminal output by default, show in reports and structured output". LW would build the same result as a new kind of diagnostic, a warning that some commands hide. That extra concept is what turns into "why does lint show a warning that build doesn't?" questions. The ruling frees us from the §6 sentence, but we should not override a rule just to rebuild a tier we already have. Agents that read structured output still get the hint.

**Concern:** today the only info codes are V-prefixed (contract verification), so the new info code and its catalog row must make sure the LSP shows info diagnostics as visible hints, not hide them.

##### PLT


**Vote: I** (changed from LW). I revised this file after the user's ruling, and the vote stays I.

**Reasoning.** The ruling says §6:31 does not bind this vote, so I drop that argument. The vote rests on facts 3 and 4.
- LW depends on a `blink lint` tier that the spec does not define, and it would make the set of diagnostics depend on which tool runs.
- Info level already exists in the catalog with the exact behavior LW was reaching for. It never fails a build, it is silent in terminal output by default, and it shows in reports and structured output, which is what the LSP reads.
- I gets the result through a mechanism the spec already defines. LW would need a new one. When two options give the same observable behavior, the one that adds no rule is the principled choice.

**Concern.** The only info codes today are contract-verification codes (V…), so the catalog must say which prefix and number range a style info code gets. The machine-applicable fix must also reach users through structured output, or the hint shows with no way to apply it.

##### DevOps/Tooling


I wrote this after the user's ruling. The ruling means the §6 sentence does not bind this vote. My vote still changes, for the reasons below, not because of §6.

**Vote: I** (changed from LW)

**Reasoning:** LW and I aim at the same result: keep the hint out of `blink build` terminal output and show it with its fix in the editor. The info tier already does this with a severity the spec defines: "silent in terminal output by default and show in reports and structured output". LW would invent a new kind of diagnostic whose visibility depends on the command. It would also need spec text for a `blink lint` command that §6 and ERROR_CATALOG.md never mention. I also reaches agents better than LW: §6 says agents read the structured JSON output, and info diagnostics appear in that output, while under LW `blink build --json` would leave the hint out. Keeping one diagnostic set for the CLI and the LSP is also sound tooling design whether or not it is spec. A rust-analyzer that disagrees with cargo is the failure it prevents.

**What it needs:** one row under *Info Names* with a non-V code. V marks contract verification, so the panel or catalog must pick a prefix for lint-class info codes. The LSP shows info diagnostics as hints with the machine-applicable fix. The `--fix` path applies that fix in bulk.

**Concern:** Info diagnostics are silent in the terminal by default, so a person who only reads terminal output never sees the hint. The `blink llms` rule and the E1106 help text must carry it word for word.

##### AI/ML


**Vote: I** (I change my vote from LW.)

###### Reasoning

LW asks for two things the spec does not have:
- A split between the CLI and the LSP. Fact 1 forbids that.
- A `blink lint` surface. Fact 3 shows the spec does not have one.

To allow LW, the spec would need to add a diagnostic class and a new command. Neither has had a panel vote.

The info tier already exists in the catalog. It gives the result LW was meant to give:
- It never fails a build.
- It is silent in terminal build output, so build output stays clean, and agents do not learn to ignore warnings.
- It shows in the LSP, so the fix is one click away.
- It shows in structured and report output. Agent tools are more likely to read that output than the human-readable terminal text.

So info level reaches the LLM repair loop through the JSON channel, which LW would never reach.

###### After the user ruling

My vote stays I.

- The ruling removes one of my two reasons: the §6 sentence was never voted, so it does not bind this vote.
- The deciding reason still holds. Info level gives every result LW gives, through a tier the catalog already has.
- LW would still need a `blink lint` command that the spec does not have (fact 3), and a new diagnostic class.
- Only info level reaches agents through structured output.

###### Concern

V0001 and V0004 are verification codes, and this would be the first info diagnostic outside verification. It needs a name and a code family that fit the *Info Names* section of the catalog, or it will look like a verification result.

##### Minimalism


**Vote: I**

I have read the user's ruling: the §6 sentence was never voted, so it does not bind this vote. That removes one of my two arguments. My vote does not change, because the other argument still stands.

**Reasoning:**
- `blink lint` does not appear in sections/ or ERROR_CATALOG.md (fact 3). So LW cannot just name an existing surface. It must spec a command and a new severity mode: a warning that one front end hides and another shows.
- The info tier already exists in the catalog and already has the behavior that all six of us want: it never fails a build, is silent in terminal output by default, and shows in reports, structured output and so in the LSP.
- I costs one new row under *Info Names*. LW costs a new command in the spec plus a split warning tier, all for one style hint. The smaller change that does the same job wins.

**Concern:** Info has held only V-prefixed contract-verification codes until now. The new code needs a prefix and number range the catalog can grow into, or the first style info code becomes a one-off.

### Final Spec

```blink
fn main() {
    let x = 5
    io.println("a {x} b")       // a 5 b
    io.println("a \{x} b")      // a {x} b
    io.println(#"{"k": #{x}}"#) // {"k": 5}
    io.println("v={({ x + 1 })}") // v=6
    // io.println("a {{x}} b")   -- E1130 InterpDoubleBrace
}
```

- Every `"..."` literal interpolates `{expr}`. `\{` writes one literal brace; `#"..."#` (depths 1–3, holes `#{ }`, `##{ }`, `###{ }`) holds brace-heavy text. No interpolation marker; no form removed (§2.4).
- The first token of a hole's expression must not be `{`, whitespace skipped, in every string form and depth: E1130 `InterpDoubleBrace`. `#"{{x}}"#` holds no hole and is text. To start a hole with a block, wrap it in `( )` (§2.4).
- A bare `}` is literal text in every string form. `\}` stays valid, and `blink fmt` keeps the spelling the author wrote (§2.4).
- V1100 `EscapeHeavyString` is an info diagnostic on a `"..."` literal (not `t"..."`) with 3 or more of `\"`, `\{` and `\\`, when a `#"..."#` literal of depth 1–3 has the same value. Its machine-applicable fix writes that literal at the smallest depth that fits (§2.4.2).
- `blink fmt` does not change the kind or the body (escape spelling included) of a literal; the `EscapeHeavyString` fix does (§2.4.2).
- W1111 keeps its number (§2.4.2).
- One normative "Which string form to use" rule in §2.4.2; `blink llms` and the diagnostic help texts copy it.
