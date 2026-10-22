[< All Decisions](../DECISIONS.md)

# Read_line Migration Help Sites — Design Rationale

The Migration paragraph of §4.4.9 said that code which uses the `io.read_line()` result as a `Str` gets a type error with a note and a `match` help. The compiler attached them to type errors only. Two old `Str` uses are not type errors: a method call on the value and an interpolation of the value. The decision names the diagnostics that carry the note and help, and the values that count. It amends the Q9 result of [decisions/stdin-io-read.md](stdin-io-read.md), which voted the targeted `match` help and left its sites open.

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated in independent-proposal → debate → vote rounds. Phase B ran one round. No Phase D was needed.

Panelist text below is quoted verbatim, each reply whole. Only the heading levels are changed, to bold lines, to fit this file, and the local ticket ID is left out of the page titles.

Notes for readers of the record:

- The Q2 option B ("in only if the check is one call to the same helper; otherwise out") won 6-0. The spec cannot depend on how the checker code is shaped, so the spec text does not list `+` as covered. It says that `+` is not covered by this rule.
- Six points were stated by all six Phase B replies or by the lead and were not balloted: the golden fixes only the note and help lines; read_line stays a special case; origin is one step (a direct call, or a name bound by `let` to it); the match help replaces the E0523 `.debug()` suggestion on a read_line value; naming `Option[Str]` in the `+` message is a separate wording fix; the general "Option[T] used where T is expected" help is a separate open matter.

### Tally

| Question | Result | Vote |
|---|---|---|
| Q1 Which diagnostics carry the note and help | A: E0300 TypeError, E0505 UnresolvedMethod on an `Option[Str]` receiver, E0523 MissingDisplayImpl in interpolation, when the value comes from `io.read_line()` | 6-0 |
| Q2 `+` (StrPlusUnsupported) | B: in only if one call to the same helper; the spec text leaves `+` out and says it is not covered | 6-0 |
| Q3 When E0505 carries the help | A: receiver is a read_line value of type `Option[Str]` and `Str` has that method; the spec lists no method names | 6-0 |
| Q4 A `let mut` binding that the code reassigns | A: it does not count; the help does not show when a reassignment can reach the use | 5-1 (Minimalism dissents for B) |
| Q5 `return` and named-argument positions | A: the spec lists them | 6-0 |
| Q6 The general E0523 `.debug()` bug | A: its own ticket; not part of this decision | 6-0 |

**Dissent (Q4, Minimalism, Phase C):** "The spec rule is "a name bound by `let` to the call". A clause for reassignment needs flow analysis, which is the machinery this decision refuses. The cost of the gap is one help line on a rare shape, and the probe shows the type error itself stays correct."

#### The question


> Title: "io.read_line migration help: spec silent on Str method calls and interpolation of the Option[Str] value"
>
> sections/04_effects.md 4.4.9 "Migration" says code that uses the io.read_line() result as a Str gets a type error with the note and the match help. The compiler (stdin-reader branch, 2026-10-18) attaches them to TypeError mismatches: let with declared Str, argument, return, assignment, and == / != against a Str. Two old Str uses are not TypeErrors and get no note:
>   let line = io.read_line()
>   io.println(line.trim())        // E0505 UnresolvedMethod `.trim` on type Option[Str]
>   io.println("got {line}")      // MissingDisplayImpl (help suggests .debug(), which Option[Str] lacks; see [...])
> Question: should these diagnostics also carry the read_line note and match help, or is the rule TypeError-only? Also the spec golden shows message "mismatched types" with a caret label; the compiler keeps its own TypeError wording ("binary `==`: incompatible types Option[Str] and Str"). Pick nothing until the panel rules.

#### Phase A — Independent proposals

##### Systems

**sys-1: Static origin, three sites, no flow analysis**

**Rule.** The read_line note and match help attach to every diagnostic that rejects an `Option[Str]` value as a `Str`, when the value has a static origin of `io.read_line()`. Three sites:

1. TypeError mismatches (today's sites: let with declared Str, argument, return, assignment, `==` / `!=`).
2. E0505 UnresolvedMethod when the receiver is an origin value of type `Option[Str]`.
3. E0523 MissingDisplayImpl for an origin value in `"{...}"`.

`line + "!"` (StrPlusUnsupported) gets it too if the check is one call to the same helper. If it is not one call, it stays out.

```blink
fn main() ! IO.Read, IO.Print {
    let line = io.read_line()
    io.println(line.trim())
    io.println("got {line}")
}
```

User sees:

```
error[UnresolvedMethod]: unresolved method `.trim` on type Option[Str]
  = note: `io.read_line()` returns `None` at end of input and `Some("")` for a blank line
  = help: match on it: `match io.read_line() { Some(line) => ..., None => break }`
```

For E0523 the migration help replaces the `.debug()` suggestion. `Option[Str]` has no Debug, so that suggestion is wrong here. The general `.debug()` bug stays a separate ticket.

**Origin test.** Use the existing `tc_is_read_line_value`: a direct call, a `let` whose initializer is the call, `return`, and named args. It is a syntactic walk over the AST. It adds no runtime cost, no type-level tag, and no flow analysis. Do not follow a second binding (`let b = line`), fields, or function returns. Past one `let`, the user sees the plain error. That error is already correct, since the type is named. A wrong help is worse than a missing one, so the test errs toward silence. An origin tag on `Option[Str]` would split one type into two in mono and layout. I reject that outright: it would make equal types differ.

**Receiver rule.** Only the type check matters at sites 2 and 3: the receiver or interpolated value is an origin value AND its resolved type is `Option[Str]`. Without the type check, the help would fire on a user's own `read_line` that returns `Option[Int]`. `tc_is_read_line_call` already guards a shadowed `io`.

**Scope: keep the special case.** Do not generalize now. The open "shared Option[T] where T expected" ticket is a separate decision: it needs `unwrap_or` and `match` forms, and `?? ""` is banned only for read_line. The generic note would have to carry a different, weaker message. Keep the read_line help as a layer over it. The `recv` help at typecheck.bl:8287 is the precedent: origin-keyed, narrow, and the compiler already has two of them.

**Wording.** The golden fixes the note and help lines only. The header "mismatched types" and the caret label are illustrative. The compiler keeps its per-site message (`binary == : incompatible types ...`), which names the exact rule that failed and is more useful. Change the spec golden to say "the header text varies by site" and show the real header from probe d. Do not rewrite compiler messages to match a golden.

**Spec and catalog.**
- 04_effects.md 4.4.9 Migration: replace "gets a type error" with "gets an error", list the three sites, state the origin rule (direct call or one `let`), and say that other paths get the plain error.
- ERROR_CATALOG: add a line to E0300, E0505, E0523 pointing at 4.4.9 for the read_line note.

**Tradeoffs (sys).** Cost is compile-time only: one AST walk on an error path. No effect on codegen. Predictable: the rule is a syntactic test a user can predict.

**Cross-language.** Rust E0599 on `Option<String>` suggests `expect` with no origin tracking. TypeScript says "possibly undefined" with no origin. Both are type-only. Blink's origin help is an extension, justified because a prior API changed meaning (the Migration case).

**sys-2 (fallback): TypeError only**

The rule stays TypeError-only, and the spec says so. It is the cheapest option. Reject it: the ticket's two examples are the most common old uses (`line.trim()`), and users hit them first.

##### Web/Scripting

**web-1 (recommended): the note and help ride on every error whose cause is "an Option[Str] from `io.read_line()` was used as a Str". Origin is tracked by the type's origin tag, not by the shape of the call.**

A JS or Python dev wrote this for years:

```blink
fn main() {
    let line = io.read_line()
    io.println(line.trim())
    io.println("got {line}")
    if line.len() == 0 { return }
}
```

They do not read the error as "TypeError". They read it as "my line code broke". Today `.trim` says only "unresolved method on Option[Str]". That is the exact Stack Overflow question this ticket will create: "why does read_line have no trim?" The note must be there.

**Which diagnostics.** Carry the note and match help on:
1. TypeError mismatches (already done).
2. E0505 UnresolvedMethod, when the receiver type is `Option[Str]` from read_line and the method exists on `Str` (`trim`, `len`, `split`, ...).
3. E0523 MissingDisplayImpl for interpolation of that value.
4. StrPlusUnsupported (`line + "!"`) too, when an operand has that origin.

Rule in one line: if the diagnostic is caused by treating the read_line value as a Str, it gets the note and help. Do not special-case by error code in the spec. Say it by cause.

**Origin.** Cheap and predictable: the value has read_line origin if it is the direct call, or a `let` binding (no declared type) of it, in the same function. Do not chase fields, returns, or reassignment. A user who passes it through a helper function has left the migration case; they get the plain error. Predictable beats clever. Do not run flow analysis for a one-release migration aid.

**Help text for method and interpolation.** Reuse the same match line, and the same note. For Display, drop the `.debug()` suggestion when the type has no Debug impl (this fixes the open bug in the same change).

```
error[UnresolvedMethod]: unresolved method `.trim` on type Option[Str]
 --> a.bl:3:20
  |
3 |     io.println(line.trim())
  |                     ^^^^ `line` is `Option[Str]`, not `Str`
  |
  = note: `io.read_line()` returns `None` at end of input and `Some("")` for a blank line
  = help: match on it: `match io.read_line() { Some(line) => ..., None => break }`
```

**Wording.** The golden fixes the note and help lines only. The headline and caret label stay the compiler's own per-kind wording. "mismatched types" cannot be the headline for an unresolved method. Change the spec golden to say "the first line and caret label vary by error" so spec and compiler agree.

**Special case or general.** Keep read_line special for this ticket (its help names `io.read_line()`, and `?? ""` is wrong there). The blocked ticket (shared Option help) can add `unwrap_or` for the general case later. Do not mix them: read_line is a migration aid with a time limit; the general help is permanent.

**Tradeoffs.** Pro: one mental model for users ("Option from read_line misuse = this help"). Con: more diagnostic sites call the helper; each needs a test. Cost is small.

**Cross-language.** Rust's E0599 on `Option<String>` adds "consider using `Option::expect`". TypeScript's "possibly undefined" fires on property access and on assignment alike; users never see it as two kinds of error. Kotlin and Swift also treat `s.length` on nullable the same as passing it to a `String` parameter. Same cause, same help.

**web-2 (fallback): TypeError only**

Simplest, but the two most common old uses (`.trim()`, interpolation) get nothing. I reject it. DevOps already said in the stdin-io-read record that method calls on the value must carry the help.

**Spec and catalog changes**
- sections/04_effects.md 4.4.9: say "any error caused by using the result as a `Str`"; list method call, interpolation, `+`, and mismatch; state the origin rule (direct call or un-annotated `let`); mark golden headline as example.
- ERROR_CATALOG.md: add a note under E0300, E0505, E0523, StrPlusUnsupported that they may carry the read_line note and help.

##### PLT

**plt-1: Help follows the type origin, on every diagnostic that reports Option[Str] where Str was used**

**Rule.** A diagnostic carries the read_line note and match help when both hold:
1. The diagnostic reports a use that needs `Str` but the value has type `Option[Str]`. This covers TypeError mismatch, a Str method call on the value (E0505 UnresolvedMethod, receiver `Option[Str]`), interpolation (E0523 MissingDisplayImpl), and `+` (StrPlusUnsupported).
2. The `Option[Str]` value has the `IO.Read` origin.

The help is not tied to one diagnostic code. It is tied to one fact: the value is the result of `io.read_line()`.

**Origin tracking.** Origin is a property of the type-checker's value, not of syntax. It is a tag on the expression type: `Option[Str]` born from the `IO.Read` op. The tag survives `let` bindings and copies (`let a = io.read_line()`, `let b = a`). It drops at any other boundary: a function return, a field, a collection element, a generic instantiation. After that boundary the type is plain `Option[Str]` and the help does not show. The compiler must never claim an origin it cannot prove. A note that says "`io.read_line()` returns None at end of input" on a value from `fetch_name()` is a false statement.

```blink
fn main() {
    let line = io.read_line()
    io.println(line.trim())
}
```

```
error[UnresolvedMethod]: unresolved method `.trim` on type Option[Str]
  |
  = note: `io.read_line()` returns `None` at end of input and `Some("")` for a blank line
  = help: match on it: `match io.read_line() { Some(line) => ..., None => break }`
```

For interpolation, the help must replace the current `.debug()` suggestion. `Option[Str]` has no Debug impl, so that suggestion is itself wrong (this is the open bug). On an origin-tagged value, the match help wins. On an untagged `Option[T]`, drop `.debug()` unless a Debug impl exists.

**Typing rule.** There is one judgment: `e : Option[Str]` used at `Str`. All four diagnostics are different views of that one judgment. The help should attach where the judgment fails, not per diagnostic code. Implementation: one function `option_origin_help(expr)` that each of the four sites calls. This also makes the open "shared help note for every Option[T] where T expected" ticket the natural generalisation. plt-1 does not block it. The generalisation adds `unwrap_or` or `match` forms for untagged values, and keeps the read_line note for tagged ones.

**Spec golden.** The golden fixes only the note and help lines. The first line and caret label are an example of one diagnostic, not a contract. The compiler's TypeError wording is more precise ("incompatible types Option[Str] and Str" names both types). Spec text should say: "The error has this note and help." Show the golden, and mark the headline as illustrative. Consequence for the spec: 4.4.9 lists the covered uses (mismatch, method call, interpolation, `+`) and states the origin rule (direct call, or a `let` or copy of it; not across a function, field, or collection).

**ERROR_CATALOG.** Add to E0300, E0505, E0523 and StrPlusUnsupported: "May carry the `io.read_line()` migration note and help."

**Tradeoffs.** Pro: sound (no false claim, because the tag is proven), compositional (one judgment, one help), matches the DevOps Phase A text the 6-0 vote accepted (`l.len()` / `l.trim()`). Con: one tag in the type representation, so a place where types are unified or erased must keep or drop it on purpose. Unification of two Option[Str] with different origins drops the tag.

**plt-2 (fallback): TypeError only**
If the tag cannot be added cheaply, narrow the spec to TypeError and file the method and interpolation cases as separate tickets. This is sound but leaves the two most common old uses (`.trim()`, `"{line}"`) without help. I rank it second.

**Cross-language**
Rust E0599 on `Option<String>` says "consider using `Option::expect`" for any receiver, with no origin. That is the general form. TypeScript "possibly undefined" fires at the use, not the origin. Swift suggests `?` or `!` as fix-its. None of them name the source API, because none keep the origin. Blink can, because the effect op is in the type.

##### DevOps

Judge by what the user sees. A user who ported `let line = io.read_line()` then `line.trim()` sees "unresolved method `.trim` on type Option[Str]" with no hint. That is the most common old Str use. It is the exact case DevOps Phase A (decisions/stdin-io-read.md:358-373) promised. Q9 voted "targeted help" 6-0. A help that fires on only 4 of 7 misuse shapes is a half-delivered vote.

**Rule**

1. **Trigger.** Any diagnostic whose offending value has type `Option[Str]` AND whose type origin is a call to `io.read_line()`. Diagnostics: TypeError (existing), UnresolvedMethod (receiver), MissingDisplayImpl (interpolation), StrPlusUnsupported (either operand). The code does not change. The note and help attach to the existing diagnostic.
2. **Origin.** Track it as a flag on the binding, not on the type: direct call expression, or a `let`/`let mut` bound to one (also through `let b = line`). Stop at function returns, struct fields, collections, and closures. No flag means no note. A wrong note is worse than none, and a narrow trigger is cheap to explain.
3. **Special case now, general later.** Keep the read_line text. The open ticket "one shared help note for Option[T] used where T is expected" owns the general form. Build the origin check as one function `read_line_origin(expr)`, so the shared note replaces it later without a second migration.
4. **Wording.** The spec golden fixes the note and help lines only. The headline stays compiler wording (`variable line: declared type Str but got Option[Str]`), because it names the exact site and the compiler has several TypeError shapes. Re-label the golden: "illustrative headline; note and help lines are normative". Never promise a caret label.
5. **MissingDisplayImpl.** When the origin flag is set, the read_line help REPLACES the `.debug()` suggestion. For other types fix the open bug separately: suggest `.debug()` only if Debug exists.

**Diagnostic the user sees**

```blink
fn main() {
    let line = io.read_line()
    io.println(line.trim())
}
```
```
error[UnresolvedMethod]: unresolved method `.trim` on type Option[Str]
  |
3 |     io.println(line.trim())
  |                ^^^^
  = note: `io.read_line()` returns `None` at end of input and `Some("")` for a blank line
  = help: match on it: `match io.read_line() { Some(line) => ..., None => break }`
```

**Tradeoffs**
- LSP: the note shows in hover for all four codes with one code path. Quick-fix stays absent (not machine-applicable, per Q9).
- Cost: four emit sites call one helper. A ratchet row should count sites without the helper.
- Risk: false positives from flag tracking. Mitigation: direct call and let-chain only.
- The `+` case: say `Option[Str]` in the message too. Today it never mentions Option. That is a separate wording fix.

**Spec and catalog**
- 04_effects.md 4.4.9: replace "gets a type error" with "gets an error"; list the four shapes; mark headline illustrative; state the origin rule (direct call or let chain).
- ERROR_CATALOG E0300, E0505, E0523, StrPlusUnsupported: add "read_line migration note" line to each.

**Cross-language**
Rust E0599 on `Option<String>` adds "consider using `Option::expect`" on the method call, not only on mismatches. Swift fix-its fire on any optional misuse. TypeScript's "possibly undefined" covers methods and templates alike. No mainstream tool limits the hint to type mismatches.

**Alternative (devops-2, fallback)**
TypeError only (current). Cheap, but the two most common old shapes stay unhelpful. I oppose it.

##### AI/ML

**aiml-1: carry the note and match help on every misuse of the value, by origin, not by diagnostic kind**

**Rule.** Any diagnostic whose cause is "the value of an `io.read_line()` call used as a `Str`" carries the same note and the same `match` help. This covers:
- TypeError mismatches (today),
- E0505 UnresolvedMethod when the receiver type is `Option[Str]` and `Str` has that method (`.trim`, `.len`, ...),
- E0523 MissingDisplayImpl for interpolation,
- StrPlusUnsupported (`line + "!"`).

**Origin.** The checker tags the binding, not the type. A `let` whose initializer is a direct `io.read_line()` call keeps the tag. Flow through other bindings, fields and function returns does not carry the tag. Those cases get the general rule in aiml-2 only. A narrow tag is predictable. A reader (human or model) can state it in one sentence.

**aiml-2 (companion, same decision): one shared "Option[T] used where T is expected" help.** For any other `Option[T]` receiver or operand that would be valid on `T`, the diagnostic gets a generic help: `match on it, or use .unwrap_or(default)`. The read_line origin tag upgrades this to the targeted note and `match` form, and the `?? ""` form stays out. This is the open ticket's shape, so the rule is not a read_line special case with a second code path.

**Interpolation.** E0523 for an `Option[T]` where `T: Display` must not suggest `.debug()` when `Option[T]` has no Debug impl. Under this rule the help line becomes the match help.

```blink
import std.io

fn main() ! IO {
    let line = io.read_line()
    io.println(line.trim())
}
```

```
error[UnresolvedMethod]: unresolved method `.trim` on type Option[Str]
 --> a.bl:5:16
  |
4 |     let line = io.read_line()
5 |     io.println(line.trim())
  |                ^^^^^^^^^^^ `Option[Str]` has no `.trim`
  |
  = note: `io.read_line()` returns `None` at end of input and `Some("")` for a blank line
  = help: match on it: `match io.read_line() { Some(line) => ..., None => break }`
```

**Wording.** The spec golden fixes the note and help lines (they are the contract). Headline and caret label stay compiler wording per diagnostic. The spec golden is an example for the TypeError case. Add one sentence: "The note and help lines are fixed. The headline and label depend on the diagnostic."

**Spec and catalog.** In 4.4.9 Migration, replace "gets a type error" with "gets an error", list the four diagnostics, and state the origin rule. In ERROR_CATALOG, add one cross-reference line under E0300, E0505, E0523 and StrPlusUnsupported.

**AI-learnability argument**

Models write `line.trim()` after `read_line()` from old training data. That is the most common failure after this change. The method-call error is the first diagnostic they see, so it is the one that must carry the fix. A TypeError-only rule gives the fix in the rare case and an unhelpful error in the common one. A model reading the error needs one self-contained next step: the match form. The same text in every case also costs few tokens in the spec: one rule, one golden.

Decision points kept low: one origin rule (direct `let` binding), one help text, no `?? ""`.

**Tradeoffs**
- Cost: the checker must track one tag on a binding. Mitigation: it is a flag set at one site.
- Risk: a user who renamed through a function loses the targeted help. They still get the generic help in aiml-2.

**Cross-language**
- Rust E0599 on `Option<String>` suggests `Option::expect` on method calls, so rustc does attach help to method errors, not only mismatches.
- TypeScript says "possibly undefined" at the method site, which is the same place.
- Kotlin and Swift flag the nullable receiver at the call, with a fix-it.
Every language points at the method call, since that is where users hit it.

**Alternative (rejected)**
aiml-0: TypeError only. Rejected: the ticket shows the method and interpolation cases are the likely first error.

##### Minimalism

**min-1: Keep the rule TypeError-only. Reject the extension. Fix the golden wording in the spec.**

**Rule.** The `io.read_line()` note and match help attach to `TypeError` (E0300) only. E0505 (`.trim`, `.len`) and E0523 (`"got {line}"`) stay as they are. They already name the type: "unresolved method `.trim` on type Option[Str]". The spec says "type error", so the compiler already matches the text.

```blink
fn main() {
    let line = io.read_line()
    io.println(line.trim())   // E0505 on Option[Str]: no read_line help
    if line == "" { return }  // E0300: note + match help
}
```

**Why not extend.**
1. Provenance. A TypeError names the expression at the mismatch site. A method call or interpolation needs a "this type came from IO.Read" tag that flows through `let`, fields, returns and calls. Nobody has defined "origin". Once defined, it has no stopping point: `lines.first()`, `stdin_from`, a wrapper `fn next() -> Option[Str]`. Each flow rule is new compiler surface and new spec text.
2. The help is a transition aid for code written against the old `Str` return. A permanent provenance mechanism for it costs too much.
3. The general fix is already ticketed: one shared "Option[T] used where T is expected" note. Do not build a read_line path that ticket then deletes.

**Two small fixes I support.**
- The open bug: E0523 must not suggest `.debug()` for a type with no Debug impl. It is a correctness bug, not a feature.
- A generic E0505 hint for an `Option[T]` receiver ("unwrap it first") belongs to the shared-note ticket. Decide it there.

**How the compiler decides "comes from read_line".** Keep today's behavior: the mismatch-site expression is a direct `io.read_line()` call, or an identifier whose `let` initializer is one. No flow analysis beyond that. The spec says so in one sentence.

**Golden wording.** The golden fixes the note and help lines only. The headline and caret label vary by site ("variable `line`: declared type...", "binary `==`: ..."). Diagnostic wording is not a language contract. Do not change the compiler to match the golden. Change the golden text to say the headline and label depend on the site.

**Spec and catalog edits.**
- 04_effects.md 4.4.9: "gets a type error (E0300) at a declared `let`, argument, return, assignment, or `==`/`!=`". Add: "A method call or interpolation on the value gives E0505 or E0523, without the note."
- ERROR_CATALOG E0300: one line that the read_line note and help attach to it. E0505 and E0523 unchanged, except the `.debug()` fix.

**Cross-language.** Rust E0599 on `Option<String>` gives a generic "consider using `Option::expect`" for any Option, with no knowledge of its source. That is the shared-note ticket. TypeScript "possibly undefined" and Kotlin nullable-receiver errors also ignore the producing function. Go would add no diagnostic.

**Tradeoff.** A user who writes `line.trim()` on old code sees no `match` form and must read the type. Cost: one lookup, once, per migrating user. Benefit: no provenance machinery, no new spec rule, nothing to remove later.

#### Phase B — Debate highlights

One round. Each seat read all six Phase A texts and replied. Replies are quoted whole.

##### Systems

**Option 1 over Option 2.** I keep sys-1. min is right that origin tracking has no natural stopping point, but the answer is a fixed, syntactic stopping point, not no help. The ticket's two examples (`line.trim()`, `"got {line}"`) are the most common old uses of a `Str`-returning `read_line`. Option 2 leaves them with a bare error and no explanation of the change. The cost is one AST walk on an error path. The `tc_is_read_line_value` helper already exists and has four callers. I add two more.

**V2 (origin paths): hold at one step.** I oppose plt-1 and devops-1 on `let b = line`. plt-1 wants a tag on the expression type. That is the mechanism I reject: it makes two `Option[Str]` types that differ only in origin, which splits them in mono and layout, and complicates unification for a diagnostic. devops-1 and aiml-1 want a flag on the binding. That is cheaper, but it needs a second table and a rule for `let mut` reassignment (`line = other()`), where the flag would lie. The syntactic walk never lies: it reads the initializer once. I concede one point to web-1: state in the spec that a `let` with a declared type is out, since E0300 on the declared type already covers it. The spec says "a direct call, or a name bound by `let` to a direct call". Anything else gets the plain error.

**V1 (`+`).** In only if it is one helper call, as in sys-1. Agree with devops-1 that the message should say `Option[Str]`; that is a separate wording ticket.

**V3.** Read_line stays a special case. I oppose aiml-2 in this decision. It adds an untargeted help for every `Option[T]`. That is the blocked ticket's content, and its unwrap forms are a new decision. Do not bundle it.

**V4.** The read_line help replaces `.debug()` on origin values. The general `.debug()` bug is a separate fix. I do not oppose web-1 fixing it in the same change if it is a one-line condition, but the decision must not depend on it.

**V5.** I accept web-1 and aiml-1: fire E0505 only when `Str` has the method. A help that says to match, followed by `.frobnicate()`, would be misleading. The `Option[Str]` type check stays.

STATUS: ready to vote

##### Web/Scripting

**Options.** I support Option 1 and oppose Option 2. min-1 says to reject the extension. But the two most common old uses are `line.trim()` and `"got {line}"`. Under Option 2 both give a bare "no method on Option[Str]" or "no Display" error. A user then asks "why did read_line stop working?" and finds nothing. DevOps already wrote in the stdin-io-read record that `l.len()` and `l.trim()` get the help. Option 1 keeps that promise. The cost is two more calls to a helper that exists today.

**V1 (`+`).** In, if it is one call to the same helper, as sys-1 says. I agree with devops-1 that the message should also name `Option[Str]`. That is a separate wording fix and does not block this decision.

**V2 (origin).** Change from Phase A: I drop "no declared type". The checker does not test for it, and `let line: Str = ...` already errors at the let. My rule is now: the direct call, or a `let` whose initializer is the call. I do not follow `let b = line`. I side with sys-1 and aiml-1 over plt-1 and devops-1. A copy chain needs a rule that users must learn and that we must keep stable. The spec states the paths: "the call, or a name bound by `let` to the call". I did not propose a type tag and I join sys-1 in rejecting one. It would split `Option[Str]` into two types.

Note: today's code also looks through `return` and named arguments (typecheck.bl:8241). The spec should list these, or the checker should drop them. I prefer the spec lists them, since both are one step from the call.

**V3.** Keep read_line special. Reject aiml-2's generic help in this decision. It belongs to the blocked shared-help ticket. A migration aid and a permanent help should not share one vote.

**V4.** Change from Phase A. For a read_line value, the match help replaces `.debug()`. The general fix (`.debug()` suggested for a type with no Debug impl) goes in its own ticket, since it touches every type. I withdraw "same change".

**V5.** The help fires on E0505 only when `Str` has the method. For `line.frobnicate()` the user gets the plain error. Otherwise the help would claim a Str fix that does not exist.

**Spec.** 4.4.9 lists the diagnostics by cause, lists the paths, and marks the golden headline as one example.

STATUS: ready to vote

##### PLT

**Option 1 over Option 2.** One typing judgment (`Option[Str]` used at `Str`) fails at four sites. The help should not depend on which site reports it. Option 2 splits one failure into two user experiences by diagnostic code, and the Q9 record (DevOps text, `l.len()` / `l.trim()`) already told the voters the help covers method calls. min's point about provenance has no stopping point is answered by V2 below: the rule has a stopping point, and the spec states it.

**Change from Phase A: no tag on the type.** sys is right that a type-level origin tag splits equal types in mono and layout. I withdraw that wording. My requirement is the soundness property, not the mechanism: the note says "`io.read_line()` returns `None` at end of input". The checker may print that only when the value is provably the result of that call. A syntactic origin test over the AST meets this, and `tc_is_read_line_value` is that test. The type stays `Option[Str]`. I support sys's mechanism.

**V2.** I accept the existing `tc_is_read_line_value` set as the spec rule: the direct call, or an identifier bound by a `let` whose initializer is the call. Silence is sound; a false claim is not. One condition: a `let mut` binding that the code reassigns is not provably the call's result, so it must not count. Today's check looks at the binder's initializer only. The panel should check this case with a probe and, if it fires on a reassigned `let mut`, file a bug. For `let b = line` I do not insist. A chain of `let` copies is still a true claim, but the simple rule (one step) is easier to state in the spec, and I give up my copy rule for it.

**V1.** `+` is in, if it is one call to the shared helper. Same as sys. Separately, its message should name `Option[Str]`.

**V3.** Keep read_line special in this decision. The general help belongs to the blocked ticket, which can then layer on this one. I drop my "plt-1 does not block it" claim as a requirement; it was a design note.

**V4.** On a read_line value the match help replaces `.debug()`. On any `Option[T]` without a Debug impl the `.debug()` suggestion is false. That is a bug in its own right; I support web: fix it in the same change if it is one line, else its own ticket. Not a reason to hold this decision.

**V5.** Fire E0505 only when the receiver's resolved type is `Option[Str]` and `Str` has that method. On `.map` or `.unwrap_or` (valid on Option) there is no error, and on a method `Str` lacks, the help would mislead.

**Spec.** 4.4.9 says "gets an error", lists the sites, states the origin rule in language terms (not checker terms), and says the golden fixes the note and help lines only.

STATUS: ready to vote

##### DevOps

**Options 1-2.** I support Option 1. I oppose Option 2. Min's point that the rule needs a limit is right, and the limit is the origin check, not the diagnostic code. Option 2 leaves the two most common old Str uses, `line.trim()` and `"got {line}"`, with no help. The 2026 stdin panel already promised the method case (decisions/stdin-io-read.md:373). Q9 voted a targeted help, not a TypeError-only help.

**V1 (StrPlusUnsupported).** In, on one condition. I agree with sys-1: if the check calls the same helper, it gets the note. If it needs separate logic, it stays out and gets its own ticket. The message wording ("never mentions Option") is a separate fix and should not block this decision.

**V2 (origin paths).** I change my Phase A position. I now support one step: the direct call, or a `let` whose initializer is the call. This is what `tc_is_read_line_value` does today. The `let b = line` copy needs new code and adds no benefit I can show. A missing note is safe. A wrong note is not. I also drop "flag on the binding" as a spec term. The spec states which paths count. It does not state how the checker tracks them. I accept sys-1's point that a tag on the type would split `Option[Str]` in mono. A syntactic walk costs nothing there.

**V3.** The note stays read_line only. The general help belongs to the blocked ticket. I oppose aiml-2: it adds a second help text (`unwrap_or`) that Q9-sub did not vote on for read_line, and it widens this decision. Plt-1's "does not block it" is fine.

**V4.** On a read_line value, the match help replaces `.debug()`. The general `.debug()` bug is a separate fix. I oppose web-1 folding it in: that changes diagnostics for every type and needs its own test row.

**V5 (E0505).** Fire the note when the receiver is an origin value of type `Option[Str]`. Web and aiml add "only when `Str` has the method". I accept that: if `Str` has no `.foo`, the user did not port an old Str use, so the note misleads. Check by looking up the method on `Str`. The check is cheap and the LSP shows the right hover.

**Spec text needed.** Section 4.4.9 lists the shapes (type mismatch, method call, interpolation, `+`), the origin rule, and "headline is illustrative". ERROR_CATALOG gets one line per code.

STATUS: ready to vote

##### AI/ML

**Options 1-2.** I vote Option 1. I oppose Option 2 (min-1).

min-1 says the origin rule has no stopping point. The repo shows it does. `tc_is_read_line_value` (src/typecheck.bl:8241) already exists and has 4 call sites. Sites 2 and 3 would call the same helper. No new flow rule is needed. The provenance cost min-1 fears is already paid.

min-1 also calls the help a transition aid. That supports Option 1. The old-code case that models and people hit first is `line.trim()`. A TypeError-only rule gives the fix only in the rare case. The spec is silent today, so I want the spec to state the rule in one sentence, not leave it to the checker.

**Change from Phase A.** I drop aiml-2 (the generic `unwrap_or` help) from this decision. sys-1, web-1, devops-1 and min-1 are right: the open ticket owns it. Adding it here would also decide the `unwrap_or` wording without that ticket's debate. Phase A text on aiml-2 is withdrawn.

**V1.** `+` is in, if it is one call to the same helper. That matches sys-1. devops-1's point also stands: the message should name `Option[Str]`. Today it does not. Treat that as a separate wording fix.

**V2.** I accept the existing helper's reach: a direct call, or a `let` whose initializer is the call. I no longer ask for a narrower rule than the code has. The spec lists the paths in plain words: direct call, `let` binding of it, and nothing else. I oppose plt-1's `let b = line` copy rule. It adds a decision point to the spec and the checker, and the plain type error still names `Option[Str]`. Mechanism is the checker's concern. I agree with sys-1: no tag on the type itself.

**V3.** Read_line stays special in this decision. The general help goes to the blocked ticket.

**V4.** On a tagged value, the match help replaces `.debug()`. The general `.debug()` bug is its own open bug. I would not tie it to this decision. A fix there is welcome and small, so either path is fine.

**V5.** The E0505 help fires only when the receiver is a tagged value of type `Option[Str]` and `Str` has that method. If `Str` has no such method, a read_line note would mislead. Both web-1 and sys-1 add a version of this guard.

STATUS: ready to vote

##### Minimalism

**Change from Phase A: I concede Option 1, narrowly.** Two facts moved me. First, the recorded DevOps text that the 6-0 Q9 vote built on says the help "fires on `l.len()` / `l.trim()`". The spec's "type error" sentence undersold that vote. Second, `tc_is_read_line_value` already exists with four call sites, and `tc_recv_option_help` already attaches an origin-keyed help to an unresolved method. My cost argument was "new provenance machinery". That machinery is built. A reused predicate adds no new concept.

**Option 1, with limits I will hold to:**
- Sites: E0505 on an `Option[Str]` receiver, and E0523 in interpolation. Both call the existing predicate. No new tag.
- V2: the predicate stays exactly as today (direct call, or a `let` initialized by it). I oppose plt-1's "copies" (`let b = line`) and any tag on the type. sys-1 is right that a tag splits `Option[Str]` in mono and layout. Following `let b = line` is a new flow rule and the spec would have to define it. Reject it.
- V5: E0505 gets the help only when the receiver is the origin value. Whether `Str` has the method does not matter. A method `Str` lacks is still wrong code, and the match form still helps. If the checker needs that test to be cheap, web-1's condition is acceptable. I do not insist.
- V1 (`+`): in only if it is a single call to the same helper, as sys-1 says. No new `+` code path. The wording fix ("mentions Option") is a separate chore.
- V3: read_line stays special. The general "Option[T] where T expected" help belongs to the blocked ticket. aiml-2 and plt-1's generalisation add surface to this decision. Out.
- V4: on a read_line value, the match help replaces `.debug()`. The general `.debug()` bug is a separate fix. Do not bundle it into this decision.
- Spec: state which sites and paths count, not how the checker tracks them. List the sites in 4.4.9, name the one-step rule, and keep the golden's note and help lines fixed with the headline free.

**Option 2** stays my fallback only if the panel rejects reusing the predicate as-is.

STATUS: ready to vote

#### Phase C — Final vote

The questions, as balloted:

**Q1. Which diagnostics carry the read_line note and match help.**
- A: Option 1 — TypeError, plus E0505 UnresolvedMethod on an `Option[Str]` receiver and E0523 MissingDisplayImpl in interpolation, when the value comes from `io.read_line()` (sys-1, web-1, plt-1, devops-1, aiml-1; min in B1 "I concede Option 1, narrowly").
- B: Option 2 — TypeError (E0300) only (min-1 Phase A; min B1 "my fallback only if the panel rejects reusing the predicate as-is").

**Q2. StrPlusUnsupported (`line + "!"`) (V1).**
- A: In: the spec lists `+` among the covered uses (web-1, plt-1, devops-1, aiml-1 Phase A).
- B: In only if the check is one call to the same helper; otherwise out and its own ticket (sys-1; web, plt, devops, aiml, min in B1).
- C: Out (min-1 Phase A).

**Q3. When E0505 carries the help (V5).**
- A: Only when the receiver is a read_line value of type `Option[Str]` and `Str` has that method (web-1, aiml-1; sys, plt, devops in B1).
- B: Whenever the receiver is a read_line value of type `Option[Str]`, whatever the method (min B1, "I do not insist").

**Q4. A `let mut` binding that the code reassigns (raised by plt B1).**
- A: It does not count as a read_line value; the help does not fire after a reassignment can reach the use (plt B1: "a `let mut` binding that the code reassigns is not provably the call's result, so it must not count").
- B: The one-step rule reads the `let` initializer only; no extra clause for reassignment (the rule as the other five B1 texts state it).

**Q5. `return` and named-argument positions (raised by web B1).**
- A: The spec lists them: a direct call in a `return` or as a named argument counts (web B1 "I prefer the spec lists them"; sys-1 Phase A lists them).
- B: The spec does not list them, and the checker drops them (web B1: "The spec should list these, or the checker should drop them").

**Q6. The general E0523 `.debug()` bug (a type with no Debug impl) (V4).**
- A: Its own ticket; not part of this decision (sys, devops, aiml, min, web in B1).
- B: Fold it into the impl of this decision if it is a one-line condition (plt B1 "fix it in the same change if it is one line, else its own ticket").

- **Q1: Which diagnostics carry the read_line note and match help** (6-0)
  - **Systems:** Vote A
    > Reasoning: The cost is one AST walk on an error path, with no effect on codegen, mono or layout. One typing failure (`Option[Str]` used as `Str`) should give one help at every site that reports it. The two most common old uses are `line.trim()` and `"got {line}"`.
    > Concern: Each new site is one more place where the origin test and the type test can drift apart, and a help that fires wrongly is worse than none.
  - **Web/Scripting:** Vote A
    > Reasoning: `line.trim()` and `"got {line}"` are the two most common old Str uses. A user who hits a bare "no method on Option[Str]" has no way to learn that read_line changed. The user sees one cause, so the help should not depend on the error code. The predicate already exists, so the cost is small.
    > Concern: Each added site is one more place that can drift from the spec wording, and each needs its own test row.
  - **PLT:** Vote A
    > Reasoning: One typing judgment (`Option[Str]` used at `Str`) fails at several sites, and the help should not depend on which diagnostic code reports it. The origin test is the soundness gate, so reusing it at E0505 and E0523 adds no new claim the checker cannot prove.
    > Concern: Each added site is one more place where the note can print on a value whose origin the checker did not prove.
  - **DevOps:** Vote A
    > Reasoning: The user sees one failure (`Option[Str]` used as `Str`) and expects one help, whatever code reports it. The two most common old Str uses, `line.trim()` and `"got {line}"`, give a bare error under B. The Q9 record promised the method case. The predicate exists, so the cost is a call at two more sites.
    > Concern: Each emit site that skips the helper gives a silent gap, so a ratchet row must count sites without the helper.
  - **AI/ML:** Vote A
    > - Reasoning: The first error a model or user meets after porting old code is `line.trim()` or `"got {line}"`, so the fix must sit there. The predicate and its call sites exist, so the spec rule stays one sentence: same note and help wherever the read_line value is misused. The Q9 record already promised the method case.
    > - Concern: Each new site is a place where wording can drift from the golden, so a test row per site must pin the note and help lines.
  - **Minimalism:** Vote A
    > Reasoning: The origin predicate exists and has four callers. Two more calls to it add no new concept and no new spec rule. The 6-0 Q9 record promised the help on `l.trim()`, so a TypeError-only rule would leave that promise unkept.
    > Concern: Each new site is a precedent that the help follows `io.read_line()` wherever a diagnostic appears, and the blocked general "Option[T] used where T is expected" ticket must then delete or absorb all of them.

- **Q2: StrPlusUnsupported (`line + "!"`)** (6-0)
  - **Systems:** Vote B
    > Reasoning: One call to the shared helper costs nothing at run time and is predictable. If the `+` site needs its own logic, it must not carry a second copy of the origin rule. In that case it goes out and gets its own ticket.
    > Concern: The panel states a spec rule ("`+` is covered") that the compiler may not meet until the follow-up lands.
  - **Web/Scripting:** Vote B
    > Reasoning: `line + "!"` is a common old use, so I want it covered. But it must be one call to the same helper. If it needs its own logic, it becomes a separate ticket and does not hold this decision.
    > Concern: If `+` ends up out, a JS/Python dev who writes `line + "!"` still gets a message that never mentions Option.
  - **PLT:** Vote B
    > Reasoning: `+` is the same judgment, so it belongs in if one call to the shared helper covers it. If it needs separate logic, it carries its own proof burden and should be its own ticket.
    > Concern: The spec will list `+` while the headline still does not name `Option[Str]`, so the user sees a help line under a message that omits the type.
  - **DevOps:** Vote B
    > Reasoning: `+` is in if it is one call to the same helper. Separate logic would add a fourth origin path to keep in sync, so then it stays out under its own ticket. The message should name `Option[Str]` as a separate wording fix.
    > Concern: If `+` ends up out, the spec text that lists the covered uses must say so, or it will promise a help that does not fire.
  - **AI/ML:** Vote B
    > - Reasoning: `+` belongs in the rule only if it costs one call to the shared helper, so no new decision point reaches the spec or the checker. If it needs separate logic, a ticket gives it a proper test.
    > - Concern: If `+` lands out, the spec sentence must list the sites exactly, or a reader assumes `+` is covered.
  - **Minimalism:** Vote B
    > Reasoning: `+` goes in only as a single call to the same helper. If it needs its own logic, it is new surface and gets its own ticket.
    > Concern: "One call" can slide into a second code path, and nobody re-checks at implementation time.

- **Q3: When E0505 carries the help** (6-0)
  - **Systems:** Vote A
    > Reasoning: The help says "match on it" and the user then calls a `Str` method on the unwrapped value. For a method `Str` lacks, that advice leads nowhere. The check is one method lookup on an error path.
    > Concern: A `Str` method added later changes which wrong calls get the help, so the spec must not list method names.
  - **Web/Scripting:** Vote A
    > Reasoning: If `Str` has no such method, the user did not port an old Str use. A help that says "match on it" and then a `.frobnicate()` call would mislead. The `Str` method lookup is cheap.
    > Concern: The method-exists test adds a second condition that the spec text and the LSP hover must both state correctly.
  - **PLT:** Vote A
    > Reasoning: The help says "match on it", which is a fix for a `Str` use. On a method that `Str` lacks, that advice names a repair that does not exist. Requiring both `Option[Str]` and the method on `Str` keeps the diagnostic true.
    > Concern: The `Str` method lookup is one more condition to keep in step with the `Str` method set.
  - **DevOps:** Vote A
    > Reasoning: If `Str` has no such method, the user did not port an old Str use, and the match help would claim a fix that does not exist. The lookup on `Str` is cheap. The hover in the LSP then shows the right text.
    > Concern: The `Str` method lookup must use the same method table as E0505 itself, or the two can disagree.
  - **AI/ML:** Vote A
    > - Reasoning: The help says "match on it" as the Str fix. For a method `Str` lacks, that claim misleads, and a model would follow it into a wrong rewrite. The lookup is cheap.
    > - Concern: A reader of the spec must learn a second condition (the method exists on `Str`), so the 4.4.9 text must state it in one line.
  - **Minimalism:** Vote A
    > Reasoning: I said I do not insist on B. A needs one method lookup on `Str`, and it stops the help from claiming a `Str` fix that does not exist. That keeps the help true.
    > Concern: The `Str` method lookup is one more condition to keep in step with the `Str` method set.

- **Q4: A `let mut` binding that the code reassigns** (5-1, Minimalism dissent)
  - **Systems:** Vote A
    > Reasoning: I argued that the syntactic walk never lies. Probe g.bl shows I was wrong for `let mut`: after `line = Some("x")` the note still says `read_line()` returns `None` at end of input, and the claim is false. The fix has no run-time or type-level cost. The simplest form is to exclude a `let mut` binding that any assignment can reach, and the spec states it in language terms (the name is bound by `let` and not reassigned).
    > Concern: A reassignment check that needs a scan of the function body adds a second pass, so the simplest safe rule (no `let mut` at all) may be the one that ships.
  - **Web/Scripting:** Vote A
    > Reasoning: The note says read_line returns `None` at end of input. A `let mut` that the code reassigns is not provably the call's result, and a false claim is worse than a missing note. Reassigning an input line is rare, so the clause costs the 90% case nothing. The spec can say "a name bound by `let` to the call and not reassigned".
    > Concern: The extra clause adds a rule that users and the checker must both learn, for a case that almost never happens.
  - **PLT:** Vote A
    > Reasoning: The note says the value is the result of `io.read_line()`. A `let mut` binding that the code reassigns is not provably that result, so the claim can be false. The spec states this in language terms: a `let mut` binding that is assigned again does not count. The probe g.bl shows gen1 fires today, so this is a checker fix with a test.
    > Concern: A syntactic rule ("assigned anywhere in scope") is conservative, so some correct uses lose the help, and the checker needs a scan for assignments.
  - **DevOps:** Vote A
    > Reasoning: The note states a fact about `io.read_line()`. After a reassignment the value may not come from that call, so the note could be false. A wrong note is worse than none. The spec can state this in language terms: a binding that code reassigns does not count.
    > Concern: A reassignment check needs more checker code than the one-step rule, and a path-sensitive version (reassignment "can reach the use") may be harder to state and test than a simple "any assignment to the binding" rule.
  - **AI/ML:** Vote A
    > - Reasoning: The note says the value is the call's result. After a reassignment that claim can be false, and a false help costs more tokens and trust than none. The spec can say "a `let` binding that no code reassigns" in plain words, one clause.
    > - Concern: The checker may need a reassignment scan it lacks today, so the clause must come with a test row for the `let mut` case, or the spec leads the compiler.
  - **Minimalism:** *(dissent)* Vote B
    > Reasoning: The spec rule is "a name bound by `let` to the call". A clause for reassignment needs flow analysis, which is the machinery this decision refuses. The cost of the gap is one help line on a rare shape, and the probe shows the type error itself stays correct.
    > Concern: The note says `io.read_line()` returns `None` at end of input, and on a reassigned `let mut` that line may refer to a value the call did not produce.

- **Q5: `return` and named-argument positions** (6-0)
  - **Systems:** Vote A
    > Reasoning: The checker already looks through `return` and a named argument, and both are one step from the call. A spec that lists them describes the behaviour users see. Dropping them removes help from working cases for no gain.
    > Concern: Each listed position is a promise, so a later refactor of the walk must keep all of them or change the spec.
  - **Web/Scripting:** Vote A
    > Reasoning: A direct call in `return` or as a named argument is one step from the call. The checker already looks through them (typecheck.bl:8244). The spec should say what the compiler does, so users and models see one rule.
    > Concern: The list of paths in the spec grows, and a later path added to the checker without a spec edit would make them differ again.
  - **PLT:** Vote A
    > Reasoning: A direct call in a `return` or as a named argument is the same one-step shape as a direct call elsewhere. The origin is proven. The spec lists the positions, so the language text matches the checker.
    > Concern: The list of positions grows the spec text, and a new call position later will need the spec edited.
  - **DevOps:** Vote A
    > Reasoning: A direct call in `return` or as a named argument is one step from the call, the same as a positional argument. The checker already looks through them. Listing them in the spec removes the mismatch between spec and checker, and users get the note in the same cases they see today.
    > Concern: Every listed position is a spec promise, so each needs a test row, or the next refactor drops one silently.
  - **AI/ML:** Vote A
    > - Reasoning: A direct call in a `return` or a named argument is still "a direct call". One rule with no hidden exceptions is easier to learn than a rule the checker breaks silently. Dropping them in the checker adds a special case for no gain.
    > - Concern: The listed positions must stay consistent with the positional-argument case, or the spec reads as if only named arguments count.
  - **Minimalism:** Vote A
    > Reasoning: The checker already looks through `return` and named arguments. Listing them in the spec costs one phrase. Dropping them costs checker changes and a test row for no gain.
    > Concern: Each listed position is a promise, and a future refactor of the helper must keep all of them.

- **Q6: The general E0523 `.debug()` bug** (6-0)
  - **Systems:** Vote A
    > Reasoning: The `.debug()` bug touches every type with no Debug impl, so its test surface is wider than this decision. Bundling it ties a narrow migration aid to a general fix and its regressions.
    > Concern: Until the separate ticket lands, non-read_line values still get a false `.debug()` suggestion.
  - **Web/Scripting:** Vote A
    > Reasoning: The `.debug()` bug touches every type without a Debug impl, so it needs its own test rows and its own review. On a read_line value the match help replaces `.debug()`, so this decision does not depend on the fix.
    > Concern: Until the separate ticket lands, other types without Debug still get a false `.debug()` suggestion.
  - **PLT:** Vote A
    > Reasoning: I withdraw the fold-in. Five seats say the fix touches every type and needs its own test row, and this decision does not depend on it. The false `.debug()` suggestion stays a real bug and keeps its own ticket.
    > Concern: The `.debug()` suggestion stays false for types with no Debug impl until that ticket lands.
  - **DevOps:** Vote A
    > Reasoning: The `.debug()` bug changes diagnostics for every type and needs its own test rows. Keeping it out keeps this change reviewable. A one-line fix can land as its own commit under its own ticket.
    > Concern: Until the ticket lands, a type with no Debug impl still gets a false `.debug()` suggestion.
  - **AI/ML:** Vote A
    > - Reasoning: The `.debug()` bug affects every type and needs its own test rows. Bundling it hides a wide change inside a narrow migration decision.
    > - Concern: Until its own ticket lands, non-read_line `Option[T]` interpolation keeps the false `.debug()` help.
  - **Minimalism:** Vote A
    > Reasoning: The `.debug()` bug touches every type without a Debug impl. It needs its own test row and its own review, and this decision must not depend on it.
    > Concern: The false `.debug()` suggestion stays live on non-read_line values until someone picks up the separate ticket.

### Final Spec

```blink
fn show() ! IO.Read, IO.Print {
    let line = io.read_line()
    io.println(line.trim())
    io.println("got {line}")
}
```

- Three diagnostics carry the read_line note and the `match` help: E0300 on an `Option[Str]` and `Str` mismatch, E0505 on a method call on an `Option[Str]` value, and E0523 on an `Option[Str]` value in an interpolation. The codes do not change. No fix is machine-applicable. The help does not show `?? ""`.
- E0505 carries them only when `Str` has a method of that name. The spec lists no method names.
- A value counts when it is a direct `io.read_line()` call (also as the value of a `return` or of a named argument), or a name bound by `let` to that call. A copy, a struct field, a function result and a collection element do not count. A `let mut` name that the code assigns again does not count, and the help does not show when an assignment can reach the use.
- `+` is not covered by this rule.
- On a read_line value the `match` help replaces the E0523 `.debug()` suggestion. The general `.debug()` bug is not part of this decision.
- The golden fixes only the note and help lines. The headline and the caret label are the compiler's own wording for each site.
- Read_line stays a special case. The general "Option[T] used where T is expected" help is a separate open matter.
