[< All Decisions](../DECISIONS.md)

# Keywords as Member Names — Design Rationale

The spec gap: the §4 `Route` example declares a field named `handler`, and `handler` is a keyword. The lexer makes every keyword a keyword token without context, and the parser rejects a keyword token wherever it expects a name (E1103). The spec had three keyword lists that did not agree (§10.6, the E1103 explain text, and the lexer), and it used the term "soft keyword" with no definition. With no `@json("name")` field rename in v1, a `@derive(Deserialize)` type also could not model a JSON key such as `"type"`.

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated
in independent-proposal → debate → vote rounds. Each section below quotes the panelist's own text in full.

#### Phase A — Independent proposals

All six panelists proposed, on their own, the same core rule: a keyword may name a member, never a binding. They differed on method names, call-site labels, `mod`, and how to keep the keyword list in sync.

##### Systems

> **Implementation facts I verified.** The lexer turns `handler` into a keyword token without looking at context, and it should keep doing that. The error comes from one place: `expect_value(TokenKind.Ident)` (src/parser.bl:727) rejects any keyword token. The parser already has an exception for this. Annotation names at src/parser.bl:916 take a keyword token and use its text (`if is_keyword(peek_kind()) { advance_value() }`). Codegen also has no problem with the name: `c_field_name` (src/cname.bl:927) already renames any field that clashes with a C reserved word, and C has its own `for`, `if`, `while` and `return`. A field called `handler` or `type` therefore costs nothing at runtime and nothing in the C output.
>
> ### Proposal S1 (preferred): keywords are allowed as labels, never as bindings
>
> The lexer stays as it is. In a **label position** the parser accepts any keyword token as a name. A label is a position where the grammar has already chosen "a name comes next" before it reads the token:
>
> 1. A field declaration in a `type` body. This is the start of a line inside a type body, and the name is always followed by `:`.
> 2. A member name after `.`: `r.handler` and `r.handler(x)`.
> 3. A field name in a struct literal, where the name is followed by `:`: `Route { handler: f }`.
> 4. A field name in a struct pattern, only with an explicit binding: `Route { handler: h, .. }`.
> 5. A call-site label and a keyword-param label after `--`.
>
> Every one of these checks is a single `is_keyword(peek_kind())` test, and at most one token of lookahead. There is no backtracking and no lexer state. Existing precedent: the annotation-name parse at :916.
>
> A **binding** is still never a keyword. That covers `let`, fn params, pattern punning (`Route { handler }` → E1103 with the suggestion "write `handler: h`"), and top-level names. This keeps the one hard rule anyone needs: a keyword never names a value in scope.
>
> ```blink
> type Route {
>     method: Str
>     pattern: Str
>     handler: fn(Request) -> Response
>     error_handler: Option[fn(Request, ServerError) -> Response] = None
> }
>
> fn dispatch(r: Route, req: Request) -> Response {
>     r.handler(req)
> }
>
> fn pick(r: Route) -> Str {
>     match r {
>         Route { handler: _, pattern: p, .. } => p
>     }
> }
> ```
>
> **Method declaration names** (`fn type(self)`) stay excluded in v1. `fn` followed by a keyword looks too much like a grammar error, and nobody has asked for it. An edition can add it later (§6 editions).
>
> **Spec changes:**
> - Add a single "Reserved words" table to sections/02_syntax.md.
> - §10.6 links to that table and stops keeping its own copy.
> - Make the table match the lexer. Take `async` out. Put `const`, `self`, `assert`, `assert_eq`, `assert_ne`, `assert_panics` in.
> - Remove `enum` from the E1103 explain text.
> - Add one sentence: "A reserved word may appear as a field or member label (positions 1–5); it may never be a binding."
> - The Route example stays exactly as it is. The spec was right and the parser was wrong.
>
> **Tradeoffs (systems view):**
> - Grammar cost: about 5 call sites switch from `expect_value(Ident)` to an `expect_label()` helper. The cost is fixed and fully predictable.
> - Tooling: the lexer stays context-free, so syntax highlighters and tree-sitter grammars can colour `handler` as a keyword everywhere. A highlighter will colour the label `handler` like a keyword. That looks odd but does no harm. Rust has the same problem with raw idents.
> - Serialization: the no-`@json`-rename rule (F6) makes this important. A JSON key called `type`, `handler`, `match` or `test` is very common (`{"type": "..."}` is everywhere). Without S1, `@derive(Deserialize)` cannot model those payloads at all, and Blink has no escape hatch. That is a hard wall, not something that just looks bad.
>
> **Cross-language note:**
> - Go and C reserve names hard everywhere, and Go users rename to `Type` with a struct tag. Blink has no tags, so that path is closed.
> - Rust needs `r#type`, which is ugly, and every serde user hits it.
> - Kotlin, Swift and C# allow keywords after `.` or with backticks.
> - JavaScript allows any reserved word as a property name after `.` and in object literals. That is the closest match to S1, and it has had no parsing problems for 15 years.
>
> ### Proposal S2 (rejected): an escape form (`r#handler`, `` `handler` ``)
>
> This gives a second way to spell every name (Principle 2), and it adds lexer state. It also leaks into serialized keys unless the escape is stripped. It gives nothing that S1 does not already give.
>
> ### Proposal S3 (rejected): rename the spec field and add `handler` to the reserved list
>
> This is the cheapest option today. But it leaves `type`, `test`, `match` and `effect` blocked as field names for good, with no rename attribute, so JSON interop breaks. It also makes the spec's most natural example model the workaround.
>
> ### Preference
>
> **S1.** Keywords are allowed as labels in positions 1–5. Bindings stay hard-reserved. There is one canonical reserved-word table in §02 that matches `keyword_lookup`, and the Route example does not change. Punning a keyword field gets E1103 with a fix-it pointing to the `field: name` form.

##### Web/Scripting

> ## The 90% case is not `handler`. It is `type`.
>
> `@derive(Serialize, Deserialize)` uses the field name as the JSON key, and v1 has no `@json("name")` rename (F6). Most webhook and event payloads a web developer handles have a `"type"` key: Stripe events, GitHub webhooks, Slack events, JSON:API, OpenAI and Anthropic message blocks. Under today's rule a Blink user cannot model those payloads with a derive at all. `match`, `test`, `with`, `in`, `for`, `import`, `as` and `return` also show up as JSON keys. Renaming the spec example and reserving `handler` (resolution 2) does not fix this. It only writes down that the door is locked.
>
> ## Proposal A (preferred): member names may be keywords (the ES5 rule)
>
> A keyword is allowed wherever a name can only be a member name. It is never allowed where a name is a local binding or a bare expression.
>
> ```blink
> @derive(Serialize, Deserialize)
> type Event {
>     type: Str
>     id: Str
>     handler: Option[Str] = None
> }
>
> type Route {
>     method: Str
>     pattern: Str
>     handler: fn(Request) -> Response
>     error_handler: Option[fn(Request, ServerError) -> Response] = None
> }
>
> impl Route {
>     fn match(self, path: Str) -> Bool { path == self.pattern }
> }
>
> fn dispatch(r: Route, req: Request) -> Response {
>     let e = Event { type: "route", id: "1" }
>     io.println(e.type)
>     if r.match(req.path) { (r.handler)(req) } else { not_found() }
> }
>
> fn kind(e: Event) -> Str {
>     match e {
>         Event { type: t, .. } => t
>     }
> }
> ```
>
> **Allowed positions** (a subset of F7):
> - Field declaration in a type body.
> - `name:` in a struct literal.
> - The name after `.`: field access, method call, `m.x`.
> - A method name declared in an `impl` or `trait` body. Callers reach it only through `.`.
> - A field name in a destructuring pattern, in the long form `type: t`.
>
> **Still rejected**, with a better E1103:
> - `let`/`mut`/`const` bindings.
> - Free function names, fn parameter names and keyword-param labels. The body would need to refer to them as bare names, and a bare `type` cannot be an expression.
> - Shorthand forms that create or read a local: `Event { type }` in a pattern or in a literal.
>
> Parser cost: after `.`, and at the start of a type-body field or struct-literal field, accept any keyword token as a name. Blink has no postfix keyword syntax (I searched sections/ for `.match` and similar and found no hits), so there is nothing ambiguous after `.`. In a type body, `handler:` can only be a field, because `name :` is the only production there.
>
> **Diagnostic.** A user who writes `let type = ...` should get:
>
> ```
> error[KeywordAsIdentifier]: `type` is a keyword and cannot name a variable
>   help: keywords are allowed as field and method names (`e.type`), not as local names; try `kind` or `type_`
> ```
>
> The help line answers the Stack Overflow question before anyone posts it.
>
> **Spec work (required in all proposals):**
> - Put one reserved-word table in `sections/02_syntax*.md`. It must match the lexer: add `const`, `self`, `assert`, `assert_eq`, `assert_ne`, `assert_panics`; drop `async` (an ordinary name per F1). Add a note: "Keywords may be used as member names (fields, methods, after `.`)".
> - Point §10.6 and the E1103 explain text (drop `enum`) at that table.
> - The Route example stays as written. The 597kj0 test row can go back to `handler`.
> - F5's "soft keyword" is still undefined. Don't define it: this rule is about positions, not a second keyword class.
>
> Cross-language:
> - JS/TS have allowed `obj.class` and `{ default: 1 }` since ES5. Nobody asks about it. It just works.
> - Python forbids `obj.class`. That is why `class_` and `from_` litter pydantic models and why `Field(alias="from")` exists. That is the Python pain we would copy.
> - Kotlin and Swift need backticks.
>
> Tradeoffs:
> - (+) Zero new syntax. A JS or Python dev never learns a rule, because the natural code compiles.
> - (+) Adding a keyword in a later edition breaks no existing field names.
> - (+) One way to do it: there is no escape spelling next to the plain one.
> - (−) A method named `match` reads a little odd. That is a style question for a lint, not a grammar question.
> - (−) `self` as a field (`r.self`) is legal but silly. I accept it; excluding it adds a rule to learn.
> - (−) The parser must accept keyword tokens as names in about 5 places. That is one helper, `expect_member_name()`, called at those places.
>
> ## Proposal B (rejected): escape syntax (`r#type`, backticks)
>
> ```blink
> type Event { `type`: Str }
> io.println(e.`type`)
> ```
>
> It is general, but it is the Kotlin and Rust tax: a second way to spell a name, noise in every JSON model, and a guaranteed FAQ entry. The only position it adds over A is locals, and nobody needs a local named `type`.
>
> ## Proposal C (rejected): rename + reserve (ticket option 2)
>
> It is cheap today, but it makes a common JSON key impossible to model under the no-rename decision. Every new keyword then risks breaking user fields. This is the choice that generates the most Stack Overflow questions.
>
> ## Preference
>
> **Proposal A**, plus the single reserved-word table that matches the lexer, and the E1103 help text.

##### PLT

> ## Framing
>
> The gap is not "which words are taken". Blink has no written rule for which positions take a word that names something, as opposed to one that binds a local. Today one lexical class does both jobs, so each keyword removes a word from both jobs. The principled fix splits the class in two:
>
> - **Identifier:** a name that binds a value, or that a bare expression can refer to. Keywords are excluded.
> - **Label:** a name that picks a member of a type, record or module. Any identifier or any keyword is a label.
>
> ECMAScript has had this split since ES5 (`IdentifierName` versus `Identifier`), which is why `obj.class` and `{ default: 1 }` are legal JavaScript. Swift does the same after `.`. OCaml and Python do not, and that is why they need `type_` and `class_`, a wart we can see coming.
>
> ## Proposal 1 (preferred): keywords are legal in label positions
>
> **Label positions**, where any keyword is legal:
>
> - a field declaration in a type body
> - a field name in a struct literal or struct pattern, when an explicit `:` follows it
> - a member after `.`, as in `r.x`, `r.x()` and `m.x`
> - a method name declared in `impl` or `trait`, since the method is only reachable through `.`
>
> **Binder positions**, where keywords stay illegal:
>
> - `let` and `for` binders, and function and closure parameters
> - top-level `fn`, `type` and `effect` names (a bare reference must resolve)
> - keyword-param names. The label and the local are the same name in Blink, and I do not propose splitting them the way Swift does.
>
> ```blink
> type Route {
>     method: Str
>     pattern: Str
>     handler: fn(Request) -> Response
>     error_handler: Option[fn(Request, ServerError) -> Response] = None
> }
>
> @derive(Serialize, Deserialize)
> type Event {
>     type: Str            // JSON key "type", with no rename attribute
>     id: Int
> }
>
> fn dispatch(r: Route, req: Request) -> Response {
>     let h = r.handler            // label after `.`
>     h(req)
> }
>
> fn mk(f: fn(Request) -> Response) -> Route {
>     Route { method: "GET", pattern: "/", handler: f }   // explicit `:`
> }
>
> fn kind(e: Event) -> Str {
>     match e {
>         Event { type: t, .. } => t   // pattern with explicit `:`
>     }
> }
> ```
>
> **Punning rule.** Shorthand `R { x }`, in a literal or a pattern, means `R { x: x }`, where the second `x` is an identifier. So `R { handler }` is ill-formed, because `handler` cannot be an identifier. The shorthand is only well-formed when the label is also a legal identifier. The error must be specific, not a generic parse error: "field `handler` cannot use shorthand because `handler` is a keyword; write `handler: <name>`".
>
> **Why it is sound and composes:**
>
> - It is purely a grammar change. Type, effect and name resolution do not change.
> - There is no ambiguity and no backtracking. Every label position is fixed by the token before it (`.`, or `fn` inside impl/trait) or by the token after it (`:` in a type body, literal or pattern). No keyword starts a production at those points. `handler E {` never appears after `.` or before `:`.
> - Labels and identifiers live in separate namespaces. A field called `type` can never shadow the keyword, so §10.6's "cannot be used as identifiers" stays true word for word.
> - It frees the cases that matter most for a derive-based JSON design. `type`, `test`, `effect`, `with`, `match` and `handler` are common wire keys. The 3-2 decision against `@json("name")` renames is only tenable if field names can equal any JSON key a user will meet. Without this proposal, that decision gets reopened the first time someone deserializes `{"type": ...}`.
> - It closes the whole class of problem. `effect` and `with` (the ticket's second concern) get the same fix.
>
> **Cost:** one helper, `expect_label()` (an identifier or any keyword token), called at the positions listed above instead of `expect_value(Ident)`. The ticket's "complexity at every such position" is this one helper; no position needs lookahead.
>
> ## Spec edits that come with either proposal
>
> 1. Add a **§2 Lexical: Keywords** subsection with one reserved list that matches the lexer: `fn let mut const type trait impl if else match for in while loop break continue return pub with handler self test import as mod effect assert assert_eq assert_ne assert_panics`.
>    - List `true` and `false` as literals.
>    - Remove `async`. It is an ordinary identifier (an effect handle), and fields named `async` are accepted today.
>    - Define **soft keyword** (today only `final`, and only in trait bodies). This gives §6 Editions' "promote a soft keyword" a referent.
> 2. Replace §10.6's list with a pointer to the §2 list, so there is only one source of truth.
> 3. Correct the E1103 explain text, which lists `enum`, a word that is not a keyword anywhere.
>
> ## Proposal 2 (fallback): reserve the word and rename the field
>
> Rename the Route field (for example to `on_request`), add `handler` to the reserved list, and apply spec edits 1 to 3.
>
> - For: it is the smallest grammar, and it is what OCaml does.
> - Against: it leaves a corner that only gets tighter. Every future keyword permanently removes a field name and a JSON key. Combined with the no-rename decision, a Blink type cannot model a common wire format. I would vote for this only if the panel wants to reopen `@json("name")` at the same time.
>
> ## Rejected: raw identifiers (`r#type`, as in Rust)
>
> This adds a second spelling for the same name. That breaks Principle 2 and puts noise into derive output.
>
> ## Preference
>
> **Proposal 1** plus spec edits 1 to 3. Also fix §04_effects Route in the same change, so the spec's own example becomes the conformance test for label positions. That test should include the punning diagnostic and a negative test that `let handler = 1` still fails with E1103.

##### DevOps

> ## Facts that drive my view
> - Three keyword lists disagree: lexer (`src/tokens.bl`), spec §10.6, and the E1103 `explain` text (`src/diagnostics.bl:1112`, which lists `enum` — not a keyword — and omits `with`, `self`, `mod`, `assert*`). A user has no list to trust.
> - Every name position funnels through `expect_value(TokenKind.Ident)` (`src/parser.bl:731`), which emits one context-free E1103. On a field declaration, the user sees "cannot be used as an identifier" — true, but useless.
> - No `@json("name")` rename (F6) + derived Serialize uses the field name as the key. `type` is the most common discriminator key in real JSON (`"type": "message"`). Today Blink cannot model it.
>
> ## Proposal A (preferred): keywords are legal in member-name positions
>
> A *member-name position* is a name that is only reached through a qualifier, never as a bare local:
> 1. field declaration in a `type` body
> 2. field name in a struct literal: `Route { handler: f }`
> 3. member access after `.`: `r.handler`, `r.type`
> 4. field name in a struct pattern, **only in `name: binding` form**
>
> All *binding* positions stay reserved: `let`, params, pattern shorthand, free `fn` names, keyword-param labels (a label binds a local in the body).
>
> ```blink
> type Event {
>     type: Str
>     handler: fn(Str) -> Str
> }
>
> fn dispatch(e: Event) -> Str {
>     match e {
>         Event { type: t, handler: h } => h(t)
>     }
> }
>
> fn main() {
>     let e = Event { type: "ping", handler: fn(s: Str) -> Str { s } }
>     io.println(e.handler(e.type))
> }
> ```
>
> The spec's Route example (§4, 04_effects.md:454) then parses as written — no spec change there.
>
> **Parser cost:** one helper `expect_member_name()` that accepts `Ident` or any keyword token, called at ~4 sites. Not "complexity at every position".
>
> **Diagnostics:** E1103 gains context and a fix that names the legal form:
> ```
> error[KeywordAsIdentifier]: `handler` is a keyword and cannot name a local binding
>   --> main.bl:7:24
>    |
>  7 |         Route { handler } => handler(req)
>    |                 ^^^^^^^ shorthand binds a local named `handler`
>    = help: write `Route { handler: h }` to bind the field to another name
> ```
> For `let type = ...`: help says keywords are allowed as field names (`e.type`), not as local names.
>
> **LSP / highlighting:** completion after `.` already lists fields — keyword fields appear with no extra work. Semantic tokens must tag a keyword in member position as `property`, not `keyword` (a small change; the parse tree already knows). TextMate grammars need two rules (`\.\s*\w+` and `^\s*\w+\s*:` inside a type body); tree-sitter gets it free from the node kind. `blink fmt`: no change; it prints tokens as-is.
>
> **Spec change:** add one normative "Reserved words" section to sections/02_syntax with the list plus the member-name exception; §10.6 points to it and changes "cannot be used as identifiers" to "cannot name a binding". Define "soft keyword" there (§6 Editions, 06_tooling.md:1772, already uses the term undefined). Add a CI lint that checks the spec list and the `explain` text against `keyword_lookup` in `src/tokens.bl` (or generate both from it) so the three lists cannot drift again. Remove `async` from §10.6 (it is an identifier, F1).
>
> **Cross-language:** JS/TS allow reserved words as property names in declaration, literal, and access (`obj.class`, `{ default: 1 }`) — nobody complains. Swift/Kotlin allow them after `.`. Go reserves all 25 everywhere and users write `Type`/`typ` — but only because Go has struct tags to rename JSON keys. Blink has no struct tags.
>
> ## Proposal B (rejected): raw-identifier escape (`r#type`, Swift backticks)
> Two spellings for one name breaks Principle 2. Serialize must strip the prefix. Highlighters and LSP rename must treat `r#type` and `type` as one symbol. Much tooling surface for a rare case.
>
> ## Proposal C (rejected): reserve `handler`, rename the spec field
> The ticket's option 2. Cheap, but it makes JSON keys like `type`/`handler` a permanent dead end (no rename attribute), and leaves the same trap for `effect`, `with`, `test`. The next spec example will hit it too.
>
> ## Sub-question: method names
> `impl T { fn type(self) }` is reachable only as `x.type()` / `T.type(x)`, so it could qualify as a member-name position. I defer it (YAGNI): no current case needs it, and `fn <keyword>` next to top-level free `fn` makes the error rules harder to learn. Adding it later breaks nothing; taking it back would.
>
> ## Preference
> **Proposal A**, with the single spec list generated from the lexer and the context-specific E1103 help. It fixes the Route example, allows real JSON shapes, and the new tooling work is one semantic-token rule and one diagnostic hint.

##### AI/ML

> ## Core observation (LLM codegen)
>
> LLMs choose field names from the domain, not from a keyword list. `type`, `handler`, `test`, `match`, `self` are among the most frequent field names in HTTP, JSON, AST, and test-runner code. The dominant training corpora (TS/JS, Kotlin, C#) allow keywords after `.` and before `:` in object shapes, so models have a strong prior that `obj.type` and `{ type: "x" }` are legal. Blink today breaks that prior silently: the keyword list is not in 02_syntax, and the three existing lists (lexer, §10.6, E1103 explain) disagree. A model *cannot* learn the rule from the spec, because the spec does not state it correctly.
>
> Second, the JSON consequence: with `@json("name")` renaming rejected for v1 (F6) and `@derive(Serialize, Deserialize)` keying on the field name, a JSON payload `{"type": "message"}` is **unrepresentable** in Blink today. That shape is in nearly every webhook, event, and chat-API payload. An LLM asked to model such an API has no correct answer.
>
> ## Proposal A (preferred): keywords are free in member positions
>
> Spec rule (one sentence): *"A keyword may be used as a name in a member position — after `.`, or as a field/label name followed by `:` — but never in a binding position."*
>
> - **Member positions (keyword allowed):** field declaration in a `type` body; struct-literal field `R { type: 1 }`; member access / method call `r.type`, `r.handler(req)`; field names in destructuring patterns (with explicit rename); call-site labels; method names declared in `impl`/`trait` bodies (only reachable via `.`).
> - **Binding positions (still reserved):** `let` names, parameter names (including keyword params — the body could not refer to them), free function names, type names, pattern bindings.
>
> ```blink
> type Event {
>     type: Str
>     handler: fn(Request) -> Response
>     test: Bool
> }
>
> fn route(e: Event, req: Request) -> Response {
>     if e.test { io.println("test event {e.type}") }
>     let Event { handler: h, .. } = e
>     h(req)
> }
>
> let e = Event { type: "push", handler: on_push, test: false }
> ```
>
> Shorthand `Event { handler }` / `let Event { handler } = e` would need a binding named `handler`, which cannot exist, so it is an error whose diagnostic offers a mechanical fix-it (`handler: h`). One way to write it remains.
>
> **Tradeoffs (AI/ML lens):**
> - Learnability: best. A model needs the keyword list only for naming *variables* — a habit it already has from every C-family language. It removes a decision point rather than adding one.
> - Token cost: zero. No escape syntax, no suffix convention (`type_` / `kind` / `ty`) to guess between.
> - Parser cost: bounded. After `.`, and at a name followed by `:` inside a type/literal/pattern body, accept any keyword token as a name. Each position already has an unambiguous leading token.
> - Debuggability: E1103 then fires only in binding positions, and its message can say so: "`type` is a keyword and cannot name a variable; keywords are allowed only as field and method names."
>
> ## Proposal B: rename the example + document reserved words (reject)
>
> Rename the Route field (e.g. `on_request`) and add `handler` to a reserved-word list. Cheap, but it leaves JSON `type` keys unrepresentable and forces models to memorise ~30 words for a position where no mainstream language requires that. Models will keep getting it wrong, because their training data says it is fine.
>
> ## Proposal C: raw identifiers `r#type` / backticks (reject)
>
> Swift/Rust style. Adds a second way to spell a name (Principle 2), costs tokens at every use, is rare in training data so models forget it or overuse it, and under A there is nothing left for it to solve.
>
> ## Required regardless of outcome: one canonical keyword list
>
> An AI learning from the spec can only be as accurate as the spec.
> - Put one list in sections/02_syntax.md that matches `keyword_lookup` exactly: drop `async` (the lexer treats it as an identifier); add `const`, `self`, and the `assert*` words.
> - Make §10.6 point to that list; generate the E1103 explain text from it; remove `enum` from the E1103 text (it is not a keyword anywhere).
> - Mark `mod` as "reserved, unused".
> - Define "soft keyword" (F5) or remove the term from the editions section.
>
> ## Route example
>
> Keep sections/04_effects.md unchanged — it becomes valid under A. Revert the `on_error` rename in the existing test row to `handler` and remove its inline comment (edit in place; do not rename the test file).
>
> ## Cross-language note
>
> A matches TS/JS, Kotlin (soft keywords), and C# (contextual keywords) in member positions — the largest "object with fields" training corpora. Python (`type_`) and Rust (`r#type`) show the friction B and C cause: frequent Stack Overflow questions and inconsistent workarounds in LLM output.
>
> ## Preferred
>
> **Proposal A, plus the single canonical keyword list.**

##### Minimalism

> I start from subtraction. Before we add parser positions or reserve more words, ask which keywords earn their place.
>
> ## Proposal M1: a name after `.` or before `:` is never a keyword (preferred)
>
> The rule is one sentence: **"In a member name position, any word is a name. Member name positions are the word after `.` and the word before `:` in a field list, struct literal, struct pattern, or call-site label."** Keywords stay hard everywhere else: bindings, parameters, fn names, type names and expression starts.
>
> ```blink
> type Route {
>     method: Str
>     pattern: Str
>     handler: fn(Request) -> Response
>     error_handler: Option[fn(Request, ServerError) -> Response] = None
> }
>
> type Event {
>     type: Str          // the most common JSON key there is
>     payload: Str
> }
>
> fn dispatch(r: Route, req: Request) -> Response {
>     (r.handler)(req)
> }
>
> fn kind(e: Event) -> Str {
>     match e {
>         Event { type: t, .. } => t      // explicit binding: OK
>     }
> }
> ```
>
> There is one interaction to close. Field punning (`Event { type, .. }`, see 03_types.md:1942) would make the keyword a local binding, so a punned keyword field gets E1103 with the hint "write `type: <name>`". The fix is a single check at the pun site. I would not add a new feature for it.
>
> **Why this is the smaller surface overall:**
> - The spec's own Route example is correct as written. We fix the parser to match the spec, not the other way round.
> - F6 tells us there is no `@json("name")` rename, and derive uses the field name as the JSON key. Under the alternative, `{"type": ...}` and `{"handler": ...}` can never be derived. The pressure to add a rename attribute then comes back, and that is new surface. M1 closes that door for free.
> - It adds no new syntax: no Rust `r#type`, no Swift backticks. An escape sigil is a second way to spell a name, which goes against Principle 2.
> - Cost: one `expect_member_name()` helper in the parser that takes Ident or any keyword token, used at about 5 call sites. That is less code than the per-keyword diagnostics already at parser.bl:3374–3552.
>
> **Cross-language:** ES5 did exactly this. It split *IdentifierName* (property positions) from *Identifier* (bindings), so `obj.class` and `{ class: 1 }` became legal. It has held up for 15 years with no trouble. Kotlin and C# use broader soft keywords, which cost more. Go refuses and makes you write `Type`/`typ`, but Go has struct tags for JSON renaming. Blink rejected renaming, so the Go answer does not carry over.
>
> ## Proposal M2: shrink and unify the keyword list (do this in any case)
>
> This one is pure subtraction:
> - **Keep one list.** Today there are three: the lexer (F1), §10.6 (F2), and the E1103 explain text, which includes `enum`, a keyword nowhere. The spec list should be generated from, or tested against, `keyword_lookup`. Move it to sections/02_syntax.md, where users look.
> - **Unreserve `mod`.** It is "reserved but unused in v1". YAGNI. Editions (F5) exist to reserve it later if we ever need it.
> - **Remove `async` from §10.6.** It is an ordinary identifier, and the list is simply wrong.
> - **Delete "soft keyword" from §6**, or define it. An undefined term in a normative section is a bug.
>
> I do not propose making `handler`, `effect` or `test` contextual in expression or statement position. That is Python's `match` path, and it creates ambiguity (`handler E { }` compared with a call named `handler`) that costs every reader, human or LLM. Hard keywords in expression position are the simple, predictable choice.
>
> ## Proposal M3: do nothing to the grammar, fix the spec (fallback)
>
> Rename the Route field to `on_request`, list `handler` in the reserved words, and ship M2. This is the cheapest option today. But it makes `type`, `handler`, `effect`, `test` and `match` impossible as JSON-derived field names forever, and there is no rename escape. I would vote for it only if M1 is rejected, because it moves the cost onto every user who models an external API.
>
> ## Tradeoff summary
>
> | | Grammar cost | User trap | Future surface pressure |
> |---|---|---|---|
> | M1 | 1 helper, ~5 sites, 1 pun check | none | removes need for `@json` rename |
> | M3 | zero | permanent (`type`!) | pushes toward a rename attribute |
> | Contextual keywords everywhere | high, ambiguous | subtle | "soft keyword" taxonomy |
>
> **Preferred: M1 + M2.** M1 is the minimal grammar change that makes the spec's own example correct and avoids a future rename feature. M2 deletes one dead reservation, one false entry and one undefined term, and collapses three keyword lists into one.

#### Phase B — Debate (round 1)

After dedupe, the variations for debate were: method names (V1), keyword-param names and call-site labels (V2), `mod` (V3), the term "soft keyword" (V4), and how to keep the table in sync (V5). All six panelists reported "stable, ready to vote" after one round. Position shifts, in the panelists' words, are in the full text below: Web/Scripting and Minimalism moved toward excluding method names while Systems and DevOps moved toward including them; Minimalism and Web/Scripting moved to keeping `mod`; Minimalism and AI/ML withdrew call-site labels.

##### Systems

> ### (1) Objections to Option K
>
> None. All six texts agree on the core, and the implementation facts support it:
> - The lexer stays context-free.
> - The parser changes one helper at a few call sites.
> - The annotation-name parse (src/parser.bl:916) already accepts keyword tokens as names.
> - `c_field_name` (src/cname.bl:927) already escapes C reserved words.
>
> The rule costs nothing at runtime and nothing in codegen.
>
> One precision for the normative text. Web says K is about positions and not a second keyword class, and I agree. K must not be described as "soft keywords". Every keyword stays hard in the lexer. K only defines positions where any word token is accepted as a name. This matters for V4.
>
> Out of scope, flagged: the examples differ on how to call a fn-typed field. Mine used `r.handler(req)`, web used `(r.handler)(req)` and PLT used `let h = r.handler; h(req)`. Whatever the spec says today for calling a fn-typed field applies unchanged under K. K does not touch that rule, and the conformance test should use the spec's form.
>
> ### (2) Variations
>
> **V1: method declaration names in `impl`/`trait`. I change my position to INCLUDE.**
> I deferred this because `fn <keyword>` looked like a grammar error. Web, PLT and AIML persuaded me with an argument about asymmetry, not about need:
> - Under K, `x.match(...)` is legal after `.`, but a user cannot declare the method that call resolves to. That is a hole in the rule, not a smaller rule.
> - The rule also becomes easier to state: "a name reached only through a qualifier".
>
> The parser cost is still one-token lookahead. Inside an impl or trait body, `fn` is always followed by the method name. A closure `fn(` never appears in item position there, so `fn` plus a keyword token is unambiguous.
>
> Condition: this applies only to methods in `impl`/`trait` bodies. Free top-level `fn` names stay reserved, because a bare reference must resolve to them.
>
> DevOps's YAGNI argument ("adding later breaks nothing") is true, but it leaves a known asymmetry in v1 for no saving. The saving is one extra call site of the same helper.
>
> **V2: keyword-param labels and call-site labels. I change my position to EXCLUDE BOTH.**
> I included both in Phase A, and that was wrong:
> - DevOps and PLT are right about declarations. `-- type: Str` binds the local `type` in the body. A bare `type` cannot be an expression, so the parameter would be unreachable. Fixing that needs a Swift-style split between the external label and the internal name, which is new surface. I reject it.
> - The call-site label follows from that. If a keyword can never be a parameter name, then `f(x, type: 1)` can never match a parameter. Accepting it in the parser only moves the error from E1103 at parse time to "no parameter named `type`" at typecheck. That is a position that can never be valid, so the parser should reject it at once with E1103.
>
> I disagree with AIML and Min on keeping call-site labels. Min's one-sentence rule ("before `:`") should list the positions, not describe a token shape.
>
> **V3: `mod`. KEEP IT RESERVED. Do not unreserve it.**
> The parser does use it. src/parser.bl:1123 matches `TokenKind.Mod`, which lets sections/07:1421 give a targeted diagnostic when a Rust user writes `mod name { }`. Unreserving `mod` would turn that into a soft keyword (a keyword only at item position), which is exactly the class of rule Min argues against elsewhere. Reserving it costs almost nothing:
> - Under K, a field named `mod` is legal anyway.
> - Only a local named `mod` is blocked, and `m` or `modulus` is the everyday name for that.
>
> I agree with AIML's wording: "reserved; used only for a diagnostic in v1".
>
> **V4: "soft keyword". DEFINE IT narrowly.**
> §6 Editions uses the term, and one soft keyword already exists (`final`, a modifier only inside a trait body). Deleting the term leaves `final` without a category. Proposed definition:
>
> > "A soft keyword is a word that has keyword meaning in one named grammar position and is an ordinary identifier everywhere else. Soft keywords in v1: `final` (modifier in a trait body)."
>
> K must not be described with this term (see (1)). Web's "don't define it" is fine for K itself, but the term is already in the spec and needs a referent.
>
> **V5: keeping the list in sync. Add a TEST, not generation.**
> - The spec is hand-written markdown, so generating it from `keyword_lookup` adds a build step to the docs for 30 words.
> - A CI check that parses the §02 table and the E1103 explain text and compares both with `keyword_lookup` is enough to stop drift. It catches exactly the three-way mismatch we found.
> - The E1103 explain text can be built from the token table in the compiler, because both live in src/.
>
> All six agree on the list itself: one table in §02, matching the lexer, `async` dropped, `const`/`self`/`assert*` added, `enum` removed from the explain text, and §10.6 pointing to the table.
>
> ### Consolidated position
>
> K, with these positions:
> - field declaration in a type body
> - struct-literal `name:`
> - the name after `.`
> - struct-pattern `name: binding`
> - method declaration names in `impl`/`trait`
>
> Parameter names and call-site labels stay reserved. Keyword punning gives E1103 with the `name: <binding>` fix-it. `mod` stays reserved. "Soft keyword" gets a narrow definition (`final`). A CI test compares the spec table and the explain text with `keyword_lookup`. The Route example is unchanged, and the test row reverts to `handler`, edited in place.
>
> ### (3) Status
>
> Stable, ready to vote.

##### Web/Scripting

> ## (1) Option K itself
>
> I have no objection. All six of us arrived at the ES5 split independently, and that is the result I want. One requirement from my domain is non-negotiable: the punned-shorthand error (`R { handler }`) must carry the fix-it text (`write handler: <name>`). Without it, K swaps one Stack Overflow question ("why can't I name a field type?") for another ("why does `{ type }` fail when `{ id }` works?").
>
> ## (2) Variations
>
> ### V1: method declaration names (`fn type(self)`). Change: I will accept exclude-in-v1
>
> In Phase A I included them. Sys and devops convinced me it can wait:
> - Nobody has shown a case that needs it. The pressure behind K is JSON wire keys, and those are fields, not methods.
> - Adding it later breaks nothing. Removing it later would break code.
> - `fn` followed by a keyword at the impl level, while a top-level `fn` followed by a keyword is an error, is one more rule to learn. I care about that.
>
> One note for the spec text: `r.handler(req)` on a field of fn type still works under K because it is a member name after `.`. The 90% case (callbacks in a Route-style struct) is covered with no method rule. I prefer excluding, but not strongly. I would not block include.
>
> ### V2: labels. Keep keyword-param names AND call-site labels reserved
>
> A call-site label only has meaning if it matches a declared keyword-param name (F6: "labels are part of call syntax"). Keyword-param names stay reserved: sys is the only one who frees them, and plt and devops are right that such a name binds a local that the body could never refer to. So a keyword call-site label can never match anything. Allowing it in the parser (aiml, min) only moves the error from "keyword" to "no such parameter", which is a worse message. Against sys: allowing `-- type: Str` as a declaration needs Swift-style split external/internal names. That is new syntax and a second way to do it, which Principle 2 rules out. For both label forms, the rule should say "reserved, because a label binds a local".
>
> ### V3: `mod`. Unreserve it, weak preference (with min)
>
> "Reserved but unused" is a trap developers remember from JS: `enum`, `implements`, `package` and `interface` were reserved for years and did nothing. A user can't tell why `let mod = x % 7` fails, and the error can only say "this word does nothing but you can't use it". Editions (F5) exist for reserving a word later. If the panel wants to keep it reserved, the table must say "reserved for future use" next to it (aiml's wording) so the error message can say that too. Either choice beats listing it silently.
>
> ### V4: "soft keyword". Change: define it, narrowly (with plt)
>
> I said "don't define it". Plt showed the term already has one real referent: `final`, which is a keyword only as a modifier in a trait body. So define it as "a word that is a keyword only in one stated position, and an ordinary identifier everywhere else. Today: `final`." The spec must state that K's member-name rule does not make keywords soft: `type` is still a hard keyword, and member names are simply not identifiers. Keeping those two ideas apart stops readers from treating K as "every keyword is soft".
>
> ### V5: sync with the lexer. Test it; don't hand-maintain (with devops, min, aiml)
>
> Put one table in sections/02_syntax. Add a CI check that diffs it, and the E1103 explain text, against `keyword_lookup`. Three lists drifted apart once already, and they will drift again. Whether we generate the table or test it is an implementation choice. A test is enough and keeps the spec hand-written.
>
> ## (3) Status
>
> **Stable, ready to vote.** K; V1 exclude (weak); V2 both reserved; V3 unreserve `mod` (weak); V4 define narrowly as above; V5 CI check against `keyword_lookup`.

##### PLT

> ## (1) Option K itself
>
> No objection. All six of us reach the same underlying rule: keywords are illegal in **binder** positions and legal in **label** positions. That is the ES5 split between `Identifier` and `IdentifierName`. I want the spec to state the rule, not only list positions, so that a later construct gets classified by the rule rather than by a new vote:
>
> > A **label** is a name that is only ever reached through a qualifier, or that is declared as a member of a type. A **binder** is a name that introduces something into lexical scope, or that a bare expression can refer to. Keywords may be labels. They may never be binders.
>
> Every V below follows from that sentence. I take each one in turn.
>
> Two edge cases need a line in the spec so nobody has to guess:
>
> - **Punning.** A shorthand field is a label and a binder at once, so the binder rule wins. All six agree.
> - **`m.x` with a keyword member.** A top-level name is a binder, so a module can never export `type`. `m.type` is then a name-resolution error ("no member"), not a parse error. That is correct, and it needs no special case.
>
> ## (2) The variations
>
> ### V1, method names in `impl` and `trait`: include
>
> The rule gives a clear answer. A method is declared as a member and reached only through `.` or `T.m`, so it is a label.
>
> Excluding methods would add an arbitrary asymmetry. `r.type` would be legal when `type` is a field, and illegal as a declaration when `type` is a method. The call site `x.type()` is already legal under K, because the name after `.` is a label. A call that parses but that nobody can declare is a hole in the grammar, not a conservative choice.
>
> On sys's point that "`fn` followed by a keyword looks like a grammar error": inside an `impl` or `trait` body, the token after `fn` is always a name. There is no production where `fn` is followed by a keyword with any other meaning, so the parser has no ambiguity and needs no lookahead. What remains is how it looks, and web is right that how it looks belongs to a lint.
>
> On devops's point that "adding later breaks nothing, taking back would": true, but that argument would defer every label position. We are choosing a rule, and the rule includes this one.
>
> Scope limit: this covers `impl`/`trait` method names only. Effect operation names stay binders until someone confirms that ops are only ever called qualified. I would not widen the rule on an unverified premise.
>
> I will not block on V1. If the majority defers it, the rule sentence still holds, and V1 becomes a documented exception to it.
>
> ### V2, keyword-param labels and call-site labels: keep both reserved
>
> This one is about soundness, not taste. In Blink the keyword-param name is both the call-site label and the local inside the body (F6). So:
>
> - **Keyword-param declaration** (`-- type: Str`). This binds `type` as a local, which makes it a binder. Allowing it would give you a parameter the body cannot refer to, because bare `type` is not an expression. The only way out is a Swift-style split between an external label and an internal name. That is new syntax and a second name for one parameter, and nobody proposed it.
> - **Call-site label** (`f(x, type: 1)`, from sys, aiml and min). If no parameter can be named `type`, a call-site label `type:` can never match anything. Allowing it in the grammar only turns a clear E1103 at the parse into a worse "no such parameter" error later. The permission is empty.
>
> To sys specifically: position 5 needs the label/binder split before it means anything. If the panel wants keyword params, that is a separate spec question (a new syntax), not part of K.
>
> To min: M1's one sentence ("before `:` in … call-site label") is attractive, but here it grants a permission that can never be used. I would amend the sentence to "field list, struct literal, struct pattern".
>
> ### V3, `mod`: keep it reserved, weakly held
>
> Under K, keeping `mod` reserved costs only locals, parameters and top-level names called `mod`. Fields and members named `mod` become legal, so almost all of the cost goes away.
>
> Unreserving it now and reserving it again later is exactly the break that editions exist to manage, so min's M2 is sound. It still spends an edition bump on a word that K has already made cheap. I prefer to leave it reserved, but either answer is consistent, so this is not a blocker.
>
> ### V4, "soft keyword": define it
>
> Blink already has a soft keyword: `final`, which is a keyword only as a modifier in a trait body and an identifier everywhere else. §6 uses the term in normative text. An undefined normative term is a spec bug, and deleting the term would make Blink's own `final` impossible to name.
>
> I disagree with web that "this rule is about positions, not a second keyword class". That is true of K, and it is the reason the definition is needed: it has to separate two things that people will confuse.
>
> - **Hard keyword:** reserved in every binder position and in the expression grammar. Legal as a label (the K rule).
> - **Soft keyword:** an ordinary identifier except in one named grammar slot. Today the only one is `final`.
>
> That takes two sentences in §02, next to the table.
>
> ### V5, keeping the list in sync: one table in §02, checked by a test
>
> The spec is the authority and the lexer implements it. So a CI test should read the §02 table and compare it both ways against `keyword_lookup` and against the E1103 explain text. Generating the spec from the lexer turns the authority upside down. Generating the explain text from a shared constant is fine as a way to implement that test.
>
> This matches devops, min and aiml in substance. The only difference is the direction of authority.
>
> ## (3) Status
>
> Stable, ready to vote. My position:
>
> - Option K, stated as the label/binder rule
> - V1 include (not blocking)
> - V2 both reserved
> - V3 keep `mod` (weak)
> - V4 define "soft keyword"
> - V5 one §02 table plus a two-way CI test

##### DevOps

> ## (1) Option K itself
> No objection. All six texts say the same thing, and the only remaining work is at the edges (V1–V5). I want one addition carried into the final text: the punned-shorthand error (`R { handler }`, literal or pattern) must be its own E1103 message with a machine-applicable fix-it (`handler: <name>`). A generic "keyword as identifier" at that point is the exact trap this ticket reports. A negative test must also show that `let handler = 1` still fails (PLT's point).
>
> ## (2) Variations
>
> ### V1 — method declaration names in impl/trait: INCLUDE (I change my position)
> In Phase A I deferred this with Sys. Web, PLT and AI/ML changed my mind, for a tooling reason. Under K, `r.match(x)` already parses, because the name after `.` is a label. If a method cannot be declared with that name, the position parses but can never resolve. The user then gets "no method `match` on Route" instead of a grammar error, and the LSP can never complete it. A position that parses but can never be valid is worse than either choice.
>
> The rule is also simpler to state and to test: "a label is a name the program only reaches through a qualifier (`.` or `Type.`)". Methods meet that rule. Free fns do not.
>
> Sys says "`fn` followed by a keyword looks like a grammar error". The parser knows it is inside an impl/trait body, so the only cost is one more `expect_label()` call site. Semantic tokens colour the name as `method`.
>
> One condition: the text must say what happens to effect-operation declarations (`fn op` in an `effect` body) and to handler-op bodies. If a program only calls ops through a qualifier, they follow the same rule. If a bare call can reach them, they stay reserved. The moderator should check how ops are called and write it down. The rule must not stay silent on them.
>
> ### V2 — labels: EXCLUDE both keyword-param labels and call-site labels
> A call-site label must match a parameter name. A keyword-param name binds a local in the body, and the body can never refer to a local named `type`. That makes the parameter illegal, so a call-site label `type:` can never match anything.
>
> - Allowing call-site labels only (AI/ML, Min) adds a position that parses but is always wrong. The user then gets "no parameter `type`" instead of the clearer E1103. That is the same dead-position problem as in V1.
> - Allowing both (Sys) needs a split between label and local that Blink does not have. That is new surface and a spec change on its own. I reject it for this ticket.
>
> K should cover labels only when Blink separates the external label from the internal name, and nobody proposes that.
>
> ### V3 — `mod`: KEEP RESERVED, and mark it "reserved, unused" (AI/ML)
> Min's YAGNI point is fair in general, but the tooling cost goes the other way. Unreserving `mod` now and reserving it again in a later edition breaks every local named `mod`, and every edition migration needs a `blink fix` rewrite. Keeping it reserved costs almost nothing under K: `x.mod` and a field named `mod` both become legal, and a local named `mod` is rare. Marking it "unused" in the table tells users and LLMs why it is there.
>
> ### V4 — "soft keyword": DEFINE it
> An undefined term in a normative section is a spec bug (Min, AI/ML), so the choice is to define it or delete it. `final` is a real soft keyword today (a keyword only as a trait-body modifier), and §6 Editions needs the term to describe promotion. Define it as "a word that is a keyword only in one named context; elsewhere it is an identifier", and list `final`.
>
> Web is right that K's label rule is *not* a soft-keyword mechanism, so the spec must keep the two apart. Labels are a position rule that applies to every keyword. Soft keywords are words that are identifiers everywhere except in one context. Deleting the term would leave §6 without a word for what editions do.
>
> ### V5 — sync: ONE table in §02, plus a CI test against the lexer
> A table that no one checks will drift again. It has already drifted three ways. I prefer a test over generating the Markdown. Generating Markdown adds a build step for docs. A test is a few lines that read the table from `sections/02_syntax*.md` and compare it, as a set, with `keyword_lookup`, and it fails `task ci` on any difference.
>
> The same test should check the E1103 `explain` text and the `blink llms` keyword topic, or those should print the table from the same source. Then there are three consumers and one source, and a gate enforces it.
>
> ## (3) Status
> Stable, ready to vote: K + V1 include (with the effect-op rule written down) + V2 exclude both + V3 keep `mod` reserved, marked "unused" + V4 define "soft keyword" + V5 one §02 table with a CI test against `keyword_lookup`, E1103 explain and `blink llms`.

##### AI/ML

> ## (1) Objection to Option K
>
> None on substance. All six panelists reached K separately, which is good evidence that it is the rule a reader expects.
>
> One precision request for the spec text. "The word before `:`" is not enough as a rule. In `let x: Int`, in `fn f(a: Int)` and in `-- b: Int`, the word before `:` is a binding. A model that learns the rule as "before `:` means any word" will write `fn f(type: Str)`. The normative text must list the positions, not describe them by the tokens around them. I propose:
>
> > A keyword may be used as a **member name**: (a) a field declaration in a `type` body, (b) a field name in a struct literal, (c) a field name in a struct pattern in `name: binding` form, (d) the name after `.`, and (e) a method name declared in an `impl` or `trait` body (see V1). Keywords are never bindings: `let`/`for` names, parameter and keyword-param names, pattern shorthand, and top-level `fn`/`type`/`effect` names.
>
> One test to see if a model can learn it: "can this name only be reached through a type (`.`, `R { }`)? Then any word works." The list above is exactly that test.
>
> ## (2) Positions on V1–V5
>
> ### V1: method declaration names (`fn type(self)`). Include. Weak preference; I will not block.
>
> - **The rule is incomplete without it.** Under K, `r.match(path)` parses because it comes after `.`. If `fn match(self, …)` cannot be declared, that call can only mean "call a field of fn type". The model must then remember an asymmetry: a name can be *called* as a method but not *declared* as one. That is an extra decision point, and it is exactly the kind a model gets wrong.
> - **The PLT argument holds.** Methods are reached only through `.` or `T.name(x)`, so they are labels by the same test as fields.
> - **Reply to sys and devops** ("`fn <keyword>` next to free `fn` makes errors harder to learn"): the line is not hard to learn. Inside `impl`/`trait` the name is a member, and at top level it is a binding. Models already learn that split for `self`. E1103 on a top-level `fn type()` can say "keywords can name methods, not free functions".
> - **Their other point is true:** adding it later breaks nothing. If the vote goes the other way, I accept deferral. Then the spec must say in one line that method names stay reserved, so that the asymmetry is at least stated.
>
> ### V2: keyword-param labels and call-site labels. Keep both reserved. I withdraw my Phase A inclusion of call-site labels.
>
> - devops and plt are right. In Blink the keyword-param label *is* the local in the body, so a keyword there can never be referred to. Swift splits the external label from the internal name, and Blink does not (F6: labels are call syntax). K should not bring that split in.
> - **Call-site labels alone would be vacuous.** If no parameter can be named `type`, then `f(x, type: 1)` can never match a parameter. Allowing it only moves the error from parse time ("keyword") to resolution time ("no parameter named `type`"). That diagnostic is worse and the rule is more confusing.
> - **Reply to sys (who includes both):** allowing keyword-param names needs either a label/local split or an unusable local. Neither is worth it for v1. The JSON case that drives K is about fields, not parameters.
> - **Reply to min's M1:** min lists call-site labels, which has the same vacuity problem.
> - **So:** labels are allowed if and only if parameter names are allowed. Today that means neither.
>
> ### V3: `mod`. Keep it reserved, and mark it "reserved, unused" in the table.
>
> - The purpose of a reserved-unused word is to avoid a breaking change later. The spec already signals a future use for `mod`.
> - **Reply to min** (editions can reserve it later): that is true, but an edition migration costs every user who named a local `mod`. Most code models are trained partly on Rust, and in Rust `mod` is a keyword, so they already avoid `mod` as a local. Keeping it reserved costs almost nothing in practice.
> - K also removes most of the cost: a *field* named `mod` becomes legal.
> - If the panel prefers min's subtraction, I will not block. I rank it below keeping the reservation.
>
> ### V4: "soft keyword". Define it in §02.
>
> - **Proposed definition:** "A soft keyword has keyword meaning only in one stated context, and elsewhere it is an ordinary identifier. v1 has one: `final`, as a modifier inside a `trait` body."
> - **Reply to web** (don't define it; K is positional, not a keyword class): I agree that K does *not* make any keyword soft. The spec should say that in one sentence, because a model that sees `e.type` legal will guess "`type` is soft" and then write `let type = …`.
> - But `final` already *is* a soft keyword, and §6 Editions uses the term. An undefined term in a normative section is worse for a spec-only learner than a one-line definition with its single example.
> - **Reply to min** (delete it): deleting the term leaves `final`'s status undocumented.
>
> ### V5: keep the list in sync with the lexer. Test it rather than generate it. Either is acceptable.
>
> - A spec that a model learns from is only as accurate as its keyword table. Three lists have already drifted apart, including one that contains `enum`. A written rule without a check will drift again.
> - **Proposal:** a CI check that extracts the §02 table and the E1103 explain text and compares them to `keyword_lookup` in src/tokens.bl.
>   - This is cheaper than generating Markdown from compiler source.
>   - It keeps the spec as hand-written prose.
>   - It catches drift in both directions.
> - If devops prefers generation, I am fine with that too.
> - **Reply to the others:** the one-table-plus-pointer idea (sys, web, plt) is necessary, but it does not *prevent* drift. Add the check.
>
> ## Related, and not in contention
>
> - E1103 message text should depend on position. I support the diagnostics devops and web sketched: "cannot name a local binding", a pun fix-it to `name: <binding>`, and for `let type` the help line "keywords are allowed as field and method names". For LLM repair loops, one short, concrete fix-it gets fixed on the next try. A generic "cannot be used as an identifier" costs extra rounds.
> - **Tests:**
>   - The §04 Route example should be the positive conformance test.
>   - `let handler = 1` and `Route { handler }` should be the negative tests.
>   - The `on_error` test row should be edited in place, back to `handler`.
>
> ## (3) Status
>
> **Stable, ready to vote.** I vote for K with these choices:
> - V1 include (deferral acceptable)
> - V2 both reserved
> - V3 keep `mod` reserved
> - V4 define "soft keyword" and state that K does not create soft keywords
> - V5 a CI check against `keyword_lookup`

##### Minimalism

> ## (1) Option K itself
>
> I have no objection. All six texts agree on the core, and I support it. I also accept every other panelist's argument that K is the smallest total surface. K fixes the parser to match the spec. It adds no syntax. It also removes the pressure to reopen `@json("name")`, which is the larger feature it would otherwise create.
>
> I have one scope request so that K stays small. Say it as one rule, not a list: **"A keyword may name a member. It may never name a binding."** Then list the positions under that rule. Each variation below should be judged by one test: *does the name, in that position, ever have to be referred to as a bare word?* If yes, it is a binding and stays reserved.
>
> ## (2) V1 to V5
>
> **V1: method declaration names (`fn type(self)`). Exclude for now. I agree with sys and devops.**
> - There is no demand. The ticket, the Route example and the JSON argument are all about *fields*. No one showed a real program that needs a method named `match`.
> - The change is additive. Adding it later breaks no program. Removing it later would break programs. With no demand, the reversible choice wins.
> - web, plt and aiml argue that the method is only reachable through `.`, so it is a label. That is true, and I accept it as the rule we would use *if* we add it. But `fn <keyword>` in an impl body looks the same as the free-fn case, which stays reserved. So the user must learn "`fn type` is fine here but not there". That is a rule we would teach for no user gain today.
> - Leaving it out creates no inconsistency. `r.match()` parses under the after-`.` rule, and it gives "no method `match`", the same as any unknown method.
>
> **V2: labels. Reserve keyword-param names, and do NOT include call-site labels. I withdraw "call-site label" from my M1.**
> - A keyword-param name binds a local in the body (devops and plt are right), so it fails the test above.
> - A call-site label must match a parameter name. If parameter names cannot be keywords, then `f(x, type: 1)` can never be well-formed. Allowing it in the grammar only adds a parse position whose sole result is a later "no such parameter" error. That is dead grammar. The clear error is the existing E1103, at the label.
> - sys's inclusion of both only works if labels and locals are split (Swift's `func f(type t: Str)`). No one proposes that, and it would be a second naming feature. I reject it.
> - aiml includes call-site labels but reserves param names. That combination can never succeed, so I ask aiml to drop it.
> - The §2.15 struct shorthand (`f({ type: "x" })`) is a struct-literal field, which K already covers. Nothing is lost.
>
> **V3: `mod`. I still prefer to unreserve it, but it is separable and not a blocker.**
> - It is reserved and does nothing. `mod` is also a natural *local* name (modulus, module), and K does not free local names.
> - I accept the counter-argument: un-reserving now and re-reserving later needs an edition, which is why languages pre-reserve. So if the majority wants "reserved, unused" (aiml), I accept it. But the spec must then say *why* it is held: "held for a future module feature". It must not appear as a keyword with no grammar.
> - Either way the list must match the lexer. If we unreserve it, the lexer change goes in the same change.
>
> **V4: "soft keyword". Define it in one sentence. I move from "delete or define" to define, following plt.**
> - `final` already is one (trait bodies only), so the concept exists in the compiler whether the spec names it or not. §6 Editions uses the term.
> - Deleting the term leaves `final` undescribed. That is worse.
> - Proposed text: *"A soft keyword is a word with keyword meaning only in one stated position, and an ordinary name everywhere else. Today the only soft keyword is `final`, in a trait body."*
> - web says not to define it because K is about positions, not a keyword class. That is correct, and the definition must not be used to describe K. K does not make any word soft. Keywords stay hard. K only says which positions take a *member name*.
>
> **V5: keep the list in sync. Use a CI check against `keyword_lookup`, not generation.**
> - A check is one lint (it compares the §02 table and the E1103 explain text to the lexer set). Generation adds a build step and a generated file to commit.
> - The repo already gates the embedded stdlib registry in `task ci`, so the check pattern is familiar.
> - One table in §02. §10.6 and E1103 point to it.
> - Drop `async` and `enum`. Add `const`, `self` and the `assert*` words.
>
> ## Small additions to K (from the other texts, which I endorse)
>
> - **Negative tests are part of the spec change** (plt): `let handler = 1` → E1103, `Route { handler }` pun → E1103 with the `handler: <name>` fix-it. The §4 Route example is the positive test.
> - **Revert the test row's `on_error` rename in place** (aiml). Edit the file content only. Do not rename the file.
> - **Scope E1103's message to bindings** (web, devops, aiml): "cannot name a variable/binding; keywords may name fields and members". The explain text states the rule once.
>
> ## (3) Status
>
> I am **stable and ready to vote**. My position:
>
> - **K** as the rule "a keyword may name a member, never a binding".
> - **V1:** exclude method declaration names.
> - **V2:** exclude call-site labels and keyword-param names.
> - **V3:** unreserve `mod`. I accept "reserved, unused, with a stated reason" if outvoted.
> - **V4:** define soft keyword in one sentence, with `final` as the only one.
> - **V5:** one §02 table, CI-checked against the lexer.

#### Phase C — Final vote

Every question passed 6-0. No Phase D ran.

- **Q1: Resolution of the gap (K: keywords as member names / R: rename the Route field / E: escape spelling)** (6-0)
  - **Systems:**

    Q1: K
    Reasoning: The lexer stays context-free, and the parser change is one `expect_label()` helper at a few call sites. Each site is decided by the token before it (`.`, `fn` in an impl body) or the token after it (`:`), so there is no backtracking. Codegen already escapes C reserved words in field names (`c_field_name`, src/cname.bl:927), so the change has zero runtime and zero C-output cost. R leaves `{"type": ...}` impossible to model under the no-rename decision, and E adds lexer state and a second spelling for every name.
    Concern: The punned-shorthand case (`R { handler }`, in a literal and in a pattern) is a separate parser path from the explicit `name:` form. If it is not covered by its own negative test, one of the two will silently accept or wrongly reject a keyword.

  - **Web/Scripting:**

    Q1: K
    Reasoning: `{"type": ...}` is the most common discriminator key in web JSON. With no `@json` rename in v1, K is the only option that lets a derive model it. It is also the ES5 rule that every JS/TS developer already expects (`obj.class`, `{ default: 1 }`). They will never know there was a rule to learn.
    Concern: the error for the shorthand `Event { type }` could ship as a generic E1103 without the `type: <name>` fix-it, and that becomes the new Stack Overflow question.

  - **PLT:**

    Q1: K
    Reasoning: K is the ES5 split between two classes: labels (any word, keywords included) and binders (identifiers only). It is a grammar-only change. Type, effect and name resolution do not change, and every label position is fixed by one token (`.` before it, or `:` after it), so the parser needs no backtracking. It is also the only option under which the no-`@json`-rename decision still holds up, because a derived type can then model any JSON key.
    Concern: the spec text may list positions without stating the rule "a keyword may name a member, never a binding". The next construct would then be classified by a new vote instead of by the rule.

  - **DevOps:**

    Q1: K
    Reasoning: K makes the natural code compile, including the spec's own Route example and JSON `type` keys. Because Blink has no rename attribute, those keys are otherwise impossible to model. The tooling cost is small: one `expect_label()` helper, one semantic-token rule (keyword in a member position → `property`/`method`), and completion after `.` needs no change. R keeps a trap that users hit and cannot get around. E adds a second spelling that the highlighter, LSP rename and Serialize must all handle.
    Concern: if the punned-shorthand case (`R { handler }`) ships with the generic E1103 text instead of a dedicated message and a machine-applicable fix-it `handler: <name>`, users still hit the trap this ticket reports.

  - **AI/ML:**

    Q1: K
    Reasoning: LLMs pick field names from the domain. Their largest training corpora (TS/JS, C#, Kotlin) let keywords appear after `.` and before `:` in object shapes, so `e.type` and `Event { type: "x" }` are what a model will write. Under the no-rename decision, K is also the only option that lets a model represent `{"type": ...}` JSON at all. It adds no escape syntax and costs no tokens. It removes a decision point where R and E add one.
    Concern: if the spec states K as "the word before `:`" instead of listing the positions, models will over-generalise to `fn f(type: Str)` and `let type: Int`, so the normative text must list the positions.

  - **Minimalism:**

    Q1: K
    Reasoning: K adds no syntax and fixes the parser to agree with the spec's own example. It also removes the pressure to reopen `@json("name")`, and that feature would be larger than K. R looks cheaper, but it moves the cost onto every user who models a JSON key `type`. E adds a second spelling for every name.
    Concern: the normative text could describe positions by their tokens ("before `:`"), so a reader extends it to params. Write it as the binder/label rule plus the listed positions.


- **Q2: Method declaration names in `impl`/`trait` bodies** (6-0)
  - **Systems:**

    Q2: Include
    Reasoning: Under K, `x.match()` already parses after `.`, so excluding the declaration leaves a call site that parses but can never resolve. That is a hole in the grammar, not a saving. Inside an `impl`/`trait` body the token after `fn` is always the method name, so accepting a keyword there costs the same one-token check as the other positions. Free top-level `fn` names and effect-operation names stay reserved.
    Concern: If Exclude wins, the spec must say in one line that method names stay reserved. Otherwise users will read `r.match()` as proof that `fn match` is legal.

  - **Web/Scripting:**

    Q2: Include
    Reasoning: I change from weak-exclude to include. Devops's point is a DX point: under K, `r.match(x)` already parses. Excluding the declaration means the user gets "no method `match`" on code that looks right, instead of a clear rule. "Anything you reach through `.` may be a keyword" is one sentence a JS dev learns in five seconds; "except you can't declare it" is a footnote.
    Concern: users will read `fn match(self)` legal in impl as `fn match()` legal at top level, so that E1103 message must say "only inside impl/trait".

  - **PLT:**

    Q2: Include
    Reasoning: under K, `x.match()` already parses, because the name after `.` is a label. If no one can declare `fn match(self)`, that call parses but can never resolve. That is a hole in the grammar, not a smaller rule. A method is declared as a member and reached only through a qualifier, so it is a label by the same test as a field. Effect operation names stay binders until someone confirms that ops are only ever called qualified.
    Concern: the effect-op carve-out may not get written down. Then a later reader applies "`fn` in a body = label" to `effect` bodies, where a bare call could reach the op.

  - **DevOps:**

    Q2: Include
    Reasoning: Under K, `r.match(x)` already parses. If no method can be declared with that name, the position parses but can never resolve. The user then gets "no method" instead of a clear rule, and the LSP can never complete it. Including methods keeps one simple rule ("a name reached only through a qualifier may be a keyword") and costs one more call site of the same helper. Effect operation names stay reserved, as in PLT's text, until someone checks that ops are only ever called through a qualifier.
    Concern: if Q2 defers, the spec must say plainly that `.keyword(...)` can reach only a field of function type. Otherwise the "no method" error looks like a compiler bug.

  - **AI/ML:**

    Q2: Include
    Reasoning: under K, `r.match(x)` already parses because the name after `.` is a label. If `fn match(self)` cannot be declared, a model must learn an asymmetry: a name it can call as a method but cannot declare as one. That is an unlearnable-from-the-rule decision point, which is exactly what models get wrong. "Any name reached only through a qualifier" is one test, and methods pass it.
    Concern: the effect-operation case (`fn op` in an `effect` body) must be stated explicitly as reserved, or models will generalise "method-like" names into effect ops.

  - **Minimalism:**

    Q2: Include
    Reasoning: I change from exclude. The rule "a keyword may name a member, never a binding" is shorter with no exception. Methods are members that code reaches only through `.` or `T.m`. Excluding them would add a stated exception, and `x.match()` would parse but could never resolve, which is more to learn, not less. The cost is one more call site of the same helper. Effect operation names stay reserved, as plt says, until someone confirms that code only calls them qualified.
    Concern: someone later reads "methods are labels" as a reason to free effect ops or free-fn names without checking the binder test.


- **Q3: Keyword-param names and call-site labels** (6-0)
  - **Systems:**

    Q3: Reserved
    Reasoning: I withdraw my Phase A inclusion. A keyword-param name binds a local that a bare expression can never refer to, and a call-site label must match a parameter name, so a keyword label could never be valid. Accepting it in the parser would only replace a clear E1103 at the parse with a later "no such parameter" error.
    Concern: None material. If the language later splits external labels from internal names, this must be revisited as its own spec question, not added to K.

  - **Web/Scripting:**

    Q3: Reserved
    Reasoning: keyword-param names bind a local, and the body can never refer to a local named `type`. A keyword call-site label therefore can never match a declared parameter. Allowing it only swaps a clear "keyword" error for a confusing "no such parameter" error.
    Concern: none of substance. The spec text should give the reason ("a label binds a local") so the asymmetry with struct fields does not look arbitrary.

  - **PLT:**

    Q3: Reserved
    Reasoning: in Blink the keyword-param name is both the call-site label and the local in the body. A keyword there would be a local the body cannot refer to. A keyword call-site label can then never match a parameter, so allowing it only swaps a clear E1103 for a worse "no such parameter" error. Allowing either would first need a Swift-style split between the external label and the internal name. That is new syntax and a separate spec question.
    Concern: the spec may give "the word before `:`" as the rule, which would make `fn f(type: Str)` look legal. The normative text must list the positions.

  - **DevOps:**

    Q3: Reserved
    Reasoning: A keyword-param name binds a local in the body that the body can never refer to. A call-site label must match a parameter name, so a keyword call-site label can never be valid. Allowing it would swap the clear E1103 for a misleading "no such parameter" error. Opening this needs a split between label and local, which is a separate spec question.
    Concern: users who write `f(x, type: 1)` should get E1103 with a note that parameter names follow binding rules, not the generic text.

  - **AI/ML:**

    Q3: Reserved
    Reasoning: in Blink, a keyword-param name is also the local in the function body, so a keyword there is a binding the body can never refer to. A keyword call-site label could then never match a parameter. Allowing it would only replace a clear parse-time E1103 with a worse "no such parameter" error. I withdrew my Phase A inclusion of call-site labels for this reason.
    Concern: the E1103 message at a call-site label must say "keywords cannot name parameters", not the generic text, or a repair loop will try renaming the wrong thing.

  - **Minimalism:**

    Q3: Reserved
    Reasoning: A keyword-param name binds a local that the body cannot refer to, and a call-site label must match a parameter name. So a keyword label could never compile, and allowing it is dead grammar. I withdrew call-site labels from my M1 in round 1.
    Concern: none of note. The E1103 message at a label must say why ("a label names a parameter, which is a local").


- **Q4: `mod`** (6-0)
  - **Systems:**

    Q4: Keep
    Reasoning: The parser uses `TokenKind.Mod` (src/parser.bl:1123) to give a targeted diagnostic when a Rust user writes `mod name { }` (sections/07:1421). Unreserving `mod` would turn that into a soft keyword or lose the diagnostic. Under K, fields and members named `mod` become legal, so the reservation now costs only locals. The table must state the reason: "reserved; used only for a diagnostic in v1, held for a future module feature".
    Concern: If the table lists `mod` with no stated reason, users will see it as a keyword that does nothing.

  - **Web/Scripting:**

    Q4: Keep
    Reasoning: I change from weak-unreserve. Under K, fields and members named `mod` become legal, so almost all the cost goes away. Unreserving now and reserving again in an edition would break real locals. If the table marks it "reserved for future use", the error can explain itself, which fixes the JS `enum`/`implements` trap I raised.
    Concern: if the table omits the "reserved, unused" note, users will hit a word that does nothing and cannot find out why.

  - **PLT:**

    Q4: Keep
    Reasoning: sys verified that the parser uses `TokenKind.Mod` (src/parser.bl:1123) for a targeted diagnostic on Rust-style `mod name { }`. Unreserving `mod` would make it a soft keyword in effect, a rule the panel otherwise avoids. Under K, fields and members named `mod` become legal, so the reservation only blocks binders. The table must state the reason: "reserved; used only for a diagnostic in v1".
    Concern: if the table does not state the reason, users will hit the web panelist's "reserved but does nothing" trap with `let mod = x % 7`.

  - **DevOps:**

    Q4: Keep
    Reasoning: reserving `mod` again in a later edition breaks every local named `mod` and makes a `blink fix` migration mandatory. Keeping it reserved costs almost nothing under K, because fields and members named `mod` become legal. Marking it "reserved, unused" with the reason tells users and LLMs why it is taken.
    Concern: the table entry must state the reason, or users read `mod` as a feature that does not work.

  - **AI/ML:**

    Q4: Keep
    Reasoning: most code models are also trained on Rust, where `mod` is a keyword, so they already avoid it as a local, and keeping it reserved costs almost nothing. Under K, a field named `mod` is legal anyway. Unreserving it now and reserving it again in an edition would force a migration. The parser also uses `TokenKind.Mod` for a targeted Rust-user diagnostic.
    Concern: without a stated reason next to `mod` in the table, a model has no way to tell why `let mod = x % 7` fails.

  - **Minimalism:**

    Q4: Keep
    Reasoning: I change from unreserve. Sys showed that the parser uses `TokenKind.Mod` (src/parser.bl:1123) for a targeted diagnostic, so `mod` is not dead. Unreserving it would make it a soft keyword, which is the extra category I argued against. Under K a field named `mod` is legal, so the remaining cost is only a local named `mod`. The table must state the reason ("reserved; v1 uses it only for a diagnostic").
    Concern: if the table lists `mod` with no reason, users hit the JS "reserved for nothing" trap.


- **Q5: "soft keyword" (§8.16.1 Editions)** (6-0)
  - **Systems:**

    Q5: Define
    Reasoning: `final` already behaves as a soft keyword (a trait-body modifier only), and §6 Editions uses the term in normative text. A two-sentence definition gives the term a real example. The spec must also state that K makes no keyword soft: hard keywords stay hard in the lexer, and member names are a position rule.
    Concern: Readers may still confuse "legal as a member name" with "soft keyword" unless the definition sits next to the K rule and names the difference.

  - **Web/Scripting:**

    Q5: Define
    Reasoning: `final` is already a soft keyword, so the term has a referent and §6 needs it. The definition must sit next to one sentence saying K makes no keyword soft. Otherwise readers (and models) will see `e.type` legal and then try `let type = ...`.
    Concern: a loose definition could let later proposals turn `handler` or `test` into expression-position soft keywords, which is Python's `match` ambiguity.

  - **PLT:**

    Q5: Define
    Reasoning: `final` is already a soft keyword (a keyword only as a modifier in a trait body), and §6 Editions uses the term in normative text. An undefined normative term is a spec bug, and deleting the term leaves `final` without a category. The definition must say that K makes no keyword soft: every keyword stays hard, and member names are labels, which is a different class of name.
    Concern: readers may still merge "label position" with "soft keyword" unless the one sentence that separates them sits right next to the table.

  - **DevOps:**

    Q5: Define
    Reasoning: an undefined term in a normative section is a spec bug. §6 Editions needs a word for promotion, and `final` is a real soft keyword today. Deleting the term would leave `final` undocumented. The definition must say that K is a position rule, not a soft-keyword mechanism, so the two concepts stay apart.
    Concern: if the definition is loose, readers will take K's member positions to mean every keyword is "soft", and the two concepts will blur in docs and `blink llms`.

  - **AI/ML:**

    Q5: Define
    Reasoning: `final` already is a soft keyword and §6 uses the term. A spec-only learner needs the term defined with its one example rather than left undefined. The definition must also say that K makes no keyword soft. Otherwise a model that sees `e.type` legal will infer "`type` is soft" and write `let type = ...`.
    Concern: if the soft-keyword text and the K text sit apart in the spec, readers may still merge the two ideas, so they belong in the same §02 subsection.

  - **Minimalism:**

    Q5: Define
    Reasoning: `final` already is a soft keyword, and §6 uses the term in normative text. Deleting the term leaves `final` with no category. One sentence costs less than that gap. The text must say that K makes no keyword soft: keywords stay hard, and member names are simply not identifiers.
    Concern: later proposals use "soft keyword" as a cheap way to free words, and the category grows by drift.


- **Q6: Keeping the one reserved-word table in sync** (6-0)
  - **Systems:**

    Q6: CI-check
    Reasoning: The spec is hand-written prose and is the authority. A CI test that compares the §02 table and the E1103 explain text with `keyword_lookup` in both directions stops the three-way drift we found. Generating Markdown from the compiler would add a build step for 30 words. The explain text can still be built from the token table inside src/ as the way to satisfy the test.
    Concern: A test that only checks one direction (spec ⊆ lexer) would miss a new lexer keyword that nobody documented, so the comparison must be an exact set equality.

  - **Web/Scripting:**

    Q6: CI-check
    Reasoning: three lists have already drifted, including a keyword (`enum`) that does not exist. A test that diffs the §02 table and the E1103 explain text against `keyword_lookup` stops that for good. A hand-written spec table also keeps room for the per-word notes ("reserved, unused", "literal").
    Concern: the check could compare only the word sets and miss a missing "unused" note, so it should also require every lexer-unused keyword to carry one.

  - **PLT:**

    Q6: CI-check
    Reasoning: the spec is the authority and the lexer implements it. So the check must compare the §02 table with `keyword_lookup` in both directions, and must not generate the spec from the lexer. The same test should also cover the E1103 explain text. That catches exactly the three-way drift this ticket found.
    Concern: a check that tests only one direction (table ⊆ lexer) would miss a keyword the lexer adds but the spec leaves out.

  - **DevOps:**

    Q6: CI-check
    Reasoning: the three lists already drift, so a table nobody checks will drift again. A CI test in `task ci` that compares the §02 table and the E1103 explain text, as sets, against `keyword_lookup` is a few lines and fails the gate on any difference. Generating Markdown would add a docs build step for no extra safety. The `blink llms` keyword topic should also be in the test's scope.
    Concern: if the test parses the Markdown table loosely (for example a regex on backticks), a formatting change can make it pass on nothing; it must assert a non-empty set that equals the lexer set.

  - **AI/ML:**

    Q6: CI-check
    Reasoning: a model learning from the spec can only be as accurate as its keyword table, and three lists have already drifted, one of them listing `enum`. A CI test comparing the §02 table and the E1103 explain text with `keyword_lookup` (plus the `blink llms` topic, per devops) stops drift in both directions and keeps the spec as hand-written prose. Generating the Markdown adds a docs build step for about 30 words.
    Concern: if the check only compares against the §02 table and not the `blink llms` output, the most-read source for LLMs could still drift.

  - **Minimalism:**

    Q6: CI-check
    Reasoning: A check is one lint that compares the §02 table and the E1103 explain text to `keyword_lookup`. Generating them adds a build step and a generated artifact. `task ci` already checks the embedded stdlib registry this way. Three lists disagree today, so some automatic check is required, and the check is the smaller one.
    Concern: the check could compare only word sets and miss the notes ("reserved, unused", soft keywords), so it must at least fail when a word is missing or extra.


### AI-First Review

| Criterion | Result |
|---|---|
| Learnability | Pass. One rule ("a keyword may name a member, never a binding") and a closed list of five positions. |
| Consistency | Pass. Same split as ES5 `IdentifierName` vs `Identifier`; the annotation-name parse already accepts keyword tokens. |
| Generability | Pass. Code that mirrors JSON keys (`type`, `match`, `handler`) now compiles as written. |
| Debuggability | Pass, on the condition that the punned-field E1103 ships with its fix-it. |
| Token Efficiency | Pass. No escape spelling, no rename annotation. |

### Final Spec

```blink
type Event {
    type: Str
    id: Int
}

impl Route {
    fn match(self, path: Str) -> Bool {
        path == self.pattern
    }
}

fn kind(e: Event) -> Str {
    match e {
        Event { type: t, .. } => t      // Event { type, .. } is E1103 with fix-it `type: <name>`
    }
}
```

- A keyword may name a member, never a binding (§2.23 *Members and Bindings*).
- Member-name positions, closed list: field declaration in a type body; struct-literal field with `:`; the name after `.`; struct-pattern field with `:`; method name in an `impl` or `trait` body.
- Reserved (E1103): `let`/`for` names, pattern bindings, fn and closure params, keyword-param names, call-site labels, top-level names, effect operation names, punned shorthand of a keyword field.
- One keyword table in §2.23, equal to the lexer set; `async` is not a keyword; `true`/`false` are literals; `mod` is reserved and unused, with its reason stated.
- "Soft keyword" means a word that is a keyword in one position only. Today only `final` in a trait body. The member-name rule makes no keyword soft.
- A CI test checks exact two-way set equality between the §2.23 table, the E1103 explain text and the lexer.
