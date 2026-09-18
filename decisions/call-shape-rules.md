[< All Decisions](../DECISIONS.md)

# Four Call-Shape Rules — Design Rationale

The ticket asked the panel to state four rules the compiler enforces and `sections/` does not:
`BareGenericFnAsValue` (E0517), `InvalidKeywordArg` (E0511), `FfiScopeNotWithResource` (E0819),
and `RawBypassesParam` (W0310). It framed the request as "state each rule or tell us the rule is
wrong and should go." The panel verified the ticket's premises against the tree, found several of
them false, and answered the second half of the question three times out of four.

**A note on quotation.** Panelist text below is verbatim. The single exception is `br` ticket
identifiers: `br` is local-only, so per the repo rule that keeps local IDs out of spec, decisions,
and source, each is replaced by a bracketed description of the ticket. No other substitution was
made, and no panelist text was reworded or shortened without an ellipsis.

---

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated in
independent-proposal → debate → vote rounds. Phase A produced six independent proposal sets;
Phase A.5 deduped them into seven ballot lines; Phase B ran two rounds; Phase C was a silent vote.
No line came back closer than 5-1, so Phase D did not trigger.

#### Phase A — Independent proposals

- **Systems:** "I read the four rules against what each one costs at runtime and what the emitted C
  actually has to be. Two of the four rules are defensible on cost. Two are not, and one of those is
  enforcing a rule the spec never wrote while leaving the rule the spec *did* write completely
  unenforced." Its Proposal S1: "E0517 BareGenericFnAsValue: **the rule is wrong and should go**…
  The rule's own explainer (`src/diagnostics.bl:895`) justifies itself on codegen… Per D13 I have
  to say plainly that this is a codegen-capability argument with a shelf life — but it is worse than
  that, because **it is not true even of today's representation.**" Established S-F1 (`TyKind.Fn` is
  always a heap-allocated boxed closure), S-F2 (`Raw(x)` is typed as the identity of `x`, so there
  is no `Raw[T]` marker type), S-F3 ("The `--` separator is parsed and then dropped on the floor…
  **Both** of §2.13's normative rules are therefore unenforced today"), S-F4, S-F5 (W0600 taken),
  S-F6.

- **Web/Scripting:** "My yardstick throughout: a JS/TS/Python developer meets this rule for the
  first time, reads the diagnostic, and either fixes it in 30 seconds or opens a Stack Overflow tab.
  Rules that pass that test should be stated. Rules that fail it should be amended or deleted, not
  documented. … Two of the four rules are good rules that sections/ merely forgot to say. One is a
  rule whose only repair is a transformation the compiler could perform itself. One fires in the
  wrong place and is suppressed through a channel the spec does not describe." On E0517: "Delete
  E0517. The case it refuses is decided by ordinary unification against the parameter type, and the
  residual case — the parameter type does not determine the instantiation — is already E0301
  CannotInferType under D5. One code less, not one more."

- **PLT:** "Three of these four rules share one defect. Each restricts a construct that is **spelled
  as an expression** but is **not usable as an expression**. `identity` is a term of a polytype that
  may not stand as a value. `ffi.scope()` is a call whose result may not be bound. `Raw(e)` is a
  call whose result has no meaning outside one coercion site. In each case the compiler enforces the
  restriction with a **syntactic test on the AST node**, not a typing rule." Its three objections:
  "**Syntactic gates are not stable under equivalence.** E0517 tests `node_kind == Ident`.
  η-expansion (`fn(x) { identity(x) }`) escapes it; so does a `let` binding… A rule that two
  η-equivalent programs disagree about is not a rule about the language; it is a rule about one
  parser." / "**Syntactic gates do not compose.** E0819 tests `node != tc_with_resource_node`. It
  says nothing about `fn make() -> FfiScope`, about an `FfiScope` field, or about an `FfiScope` type
  argument. A typing rule on the *type* covers all of them and needs no enumeration." / "**Syntactic
  gates cannot be stated in the spec without describing the AST.** That is why sections/ does not
  state them. The gap in this ticket is a *symptom*: you cannot write spec text for a rule whose
  only formulation is a node test."

- **DevOps/Tooling:** "Four rules, four positions. Three survive with amended diagnostics; one code
  gets split into three (four, if the panel accepts my §2.13 finding). Everything below is anchored
  on §3.1 *Diagnostic Discipline*… which is the normative authority my domain owns, and which
  **three of the four rules violate in the tree today**." Its findings: "**(1) E0517's only
  prescribed repair does not parse.** Both the emitted help (`src/typecheck.bl:3994`) and the
  explainer (`src/diagnostics.bl:895`) prescribe `{ x => identity(x) }`. §2.8… says: 'Closures use
  the `fn` keyword… There is no alternate short form' — 5-0." / "**(2) `identity[Int]` is not
  available as a repair.** `error[CallSiteTypeArgs]` E0307 is live… **`json.decode[Forecast](body)`
  is the same literal example in both** — normative in §3.4, refused by the compiler with a code
  whose own text calls the form an open question."

- **AI/ML:** "Three of the four rules ship a `help:` line that teaches a repair which is **wrong**,
  in two different ways… For a model in a compile-repair loop these are worse than no diagnostic. No
  diagnostic costs one round trip and the model re-reads the spec. A wrong diagnostic costs two or
  more round trips and it *poisons the prior* — the wrong form arrives with compiler authority
  behind it, and this codebase is training data." Its **Proposal A0 — extend D12 to diagnostics**:
  "Every Blink fragment in a diagnostic message, help line, or explainer is a spec example and obeys
  the same gate: it passes `blink check`, or it is marked as an intentional-error example. The first
  `help:` of a diagnostic names a repair that compiles."

- **Minimalism:** "Four rules, five codes, zero spec sentences. The temptation is to write four new
  spec subsections and call the gap closed. That trades a documentation debt for a permanent
  conceptual debt — four more rules a reader must hold, three of which are special cases of rules
  the spec already states. My ledger across all four proposals: **−1 error code, −2 standalone
  concepts, +0 new syntax, +1 general sentence that pays for itself three times over.**" Its five
  defects: X1 (the E0517 repair does not compile), X2 ("The compiler accepts labels on parameters
  declared *before* `--`… §2.13 states the opposite in as many words"), X3 ("`Raw(x)` is not a
  marker type… There is no such type. Raw is a name the interpolation walker looks for"), X4
  ("Any proposal that folds E0819 'into W0600' is folding into a hole"), X5 ("`@trusted` with no
  `audit:` argument suppresses W0310 exactly as well as `@trusted(audit: \"ID\")`… The audit trail —
  the entire stated justification for using `@trusted` rather than `@allow` — is optional").

#### Phase B — Debate highlights

**DevOps reversed on Q1 in round 1:** "I was wrong in Phase A and plt is right on the substance. My
premise — 'the parameter type says nothing about which instantiation the caller meant' — is false.
`fn(α) -> α` unified against `fn(Int) -> Int` yields `α := Int`; it is first-order, decidable, and
total on the binder set."

**DevOps raised the blocking condition on Q4 (D-F4):** "Q4-A as drafted imports a D9 rule-1
violation, and it lands on the ticket's own MVCE. See the Q4 section — this is the one thing I want
fixed before Q4-A is voted." Five of the six panelists made their Q4-A vote conditional on it.

**DevOps introduced the §7 unsilenceable list in round 2 (M16), which flipped a 3-3 split to 6-0:**
"`@allow` is the general warning channel, promised in §7 and implemented generically over every
warning name; carving one name out of it puts an exception in the general rule that a user finds
only by hitting it, which is the defect this whole ticket exists to close. It also does not work:
`[lints] W0310 = \"off\"` in `blink.toml` reaches the same suppression through a channel nobody
proposes to carve. If the panel wants W0310 unsilenceable without a record, the honest mechanism is
a **stated list in §7 of warnings that no suppression channel can turn off**, applying uniformly to
`@allow` and `[lints]` alike. I will vote for that if it is offered."

**DevOps on striking the non-existent tool (M4):** "Do not make the panel's decision wait on a tool.
**Strike the reference now** from `sections/03b_contracts.md:510` and from the shipped W0310
explainer — a spec sentence and a shipped diagnostic must not instruct the reader to run a
subcommand that does not exist (§3.1 rule 1 again, one level up). File the tool as its own ticket.
If it is built later, the sentence comes back."

**Moderator relays that changed votes.** M6 (E0517's shipped repair does not parse). M7 (E0517 is
defeated by one `let`). M8 (§2.13 states two normative rules and the compiler enforces zero). M9
(zero `--` declarations in `src/` or `lib/`). M12 (a bogus method label makes `check_arg_shapes`
skip that argument's entire type check — P1). M15 (`Crate.Box(h: 4, w: 3)` ICEs on a field read,
falsifying three panelists' "checks clean today"). M16 (the `[lints]` channel reaches the same
suppression as `@allow`).

**Two panelists retracted on the record after M15.** Systems: "M15 is a fair correction and I accept
it. My round-2 L2 called `Crate.Box(h: 4, w: 3)` a working surface on the strength of 'ok, exit 0';
I did not read the value back, and with a field read it ICEs exactly as `Circle(radius: 5)` does.
'Exits 0' is not 'is checked.'" DevOps: "**M15 reproduces.** … My round-2 claim that this surface
'checks clean today' was wrong; what I measured was a value never read."

#### Phase C — Final vote

##### Q1: E0517 `BareGenericFnAsValue` — delete the code; the residual falls to E0301 (**6-0, option A**)

- **Systems:** A — "A `fn` value in this tree is a heap-allocated `blink_closure*`… and E0517's
  mandated repair wraps the name in a closure that lowers to the same allocation and the same
  indirect call. The rule therefore buys nothing the hardware can see — it refuses one spelling of a
  machine-identical program. M7 finishes it: `apply(identity, 3)` is refused and
  `let f = identity; apply(f, 3)` is accepted, one line apart, same value. A rule one `let` defeats
  is not protecting an invariant, and the spec should not acquire a sentence claiming it does."
  *Concern:* "the residual case… falls to E0301 whose only repair is `probe[Int]`, which E0307
  refuses; R1 puts that outside this ticket, so Q1-A ships with a known repair gap."
- **Web/Scripting:** A — "`fn(Int) -> Int` fixes `T = Int` by first-order unification against a
  fully concrete type, so there is no determinacy failure for a rule to refuse… The same value,
  refused in one spelling and accepted in the other, is a syntax rule wearing a semantics rule's
  diagnostic. Passing a named function where a function is expected is the most common higher-order
  idiom a JS, TS, Python or Kotlin developer brings with them."
- **PLT:** A — "The parameter type determines the instantiation by first-order unification… A rule
  that distinguishes η-equivalent terms is not a typing rule; it is a syntactic filter that happens
  to sit where a typing rule should be. Where no expected type exists the residual is a genuine
  failure of inference and E0301 already names it."
- **DevOps:** A — "M7 settles it… Its shipped repair `{ x => identity(x) }` does not parse under
  §2.8 (M6), so as it stands E0517 is a §3.1 rule-1 violation on every firing. The residual E0301
  has a first-named repair I verified compiles in this tree — `let f: fn(Int) -> Int = identity`,
  exit 0 — so deleting E0517 costs no diagnostic quality." *Concern:* "E0301's help must name the
  annotation and **omit** the bracket form entirely while E0307 stands, or we delete one
  unparseable repair and ship another."
- **AI/ML:** A — "A rule with a legal bypass that costs fewer tokens than the prescribed repair does
  not teach the rule — it teaches the bypass, because hoisting to a `let` is a standard repair
  reflex and it works."
- **Minimalism:** A — "The expected type at a call is a source of type information, and Blink
  already relies on that: the repair E0517 itself recommends, `fn(x) { identity(x) }`, only
  typechecks because the expected type propagates into a function-typed argument. So E0517 refuses a
  program the language can already type."

##### Q2-count: split the call-site label rules into **four** codes (**6-0, all conditional on Q2-enf carrying Yes**)

The contested code is the fourth, `UnlabeledKeywordArg` — the case no three-code scheme catches. With the pre-existing `MissingKeywordArg` (E0510), the family is five.

- **Systems:** Four — "No code in the three-code scheme catches `transfer(300, alice, bob)` under
  `fn transfer(amount: Int, -- from: Account, to: Account)`… That program is §2.13's own headline
  example under §2.13's own signature, and M8 confirms it compiles today. It cannot fold into
  E0510: the parameters did receive arguments, so E0510's 'add `from: <value>`' repair produces an
  arity error."
- **Web/Scripting:** Four — "Folding it into E0510 would print 'missing keyword argument `from`' at
  a call that supplied a value for `from` and omitted only the label: a message naming a mistake the
  user did not make, which is character-for-character why I split `DuplicateKeywordArg` out of E0510
  in the first place. I cannot hold that split and refuse this one."
- **PLT:** Four (conditional) — "My test throughout has been: same repair, same code; different
  repair, different code. `MissingParameterLabel` passes it — the repair is *annotate an argument
  that is already written*, which is a different edit from E0510's *insert a missing argument*."
- **DevOps:** Four — "The missing-label code is the only one of the four whose repair is
  machine-applicable — the parameter names and positions are both known, the edit is one insertion
  per argument, and the result compiles without asking the user's intent… `blink fix` and every
  editor quick-fix list key on the code, so merging them means either never offering the safe fix or
  offering it on clauses where it is unsafe." *Concern (carried into the implementation ticket):*
  "Its name must not ship as `MissingParameterLabel` beside the existing E0510 `MissingKeywordArg`…
  two codes differing by one word, where one means 'the value is absent' and the other 'the value is
  present and unlabelled', will be confused in every `blink explain` session; `UnlabeledKeywordArg`
  or `KeywordArgNeedsLabel` avoids it."
- **AI/ML:** Four — "A diagnostic code is not a decision point: it is read only on failure and costs
  zero generation-time choices, so the frugality argument that would drop the fourth is the one
  argument I am not entitled to make twice after leaning on its inverse for my own three."
- **Minimalism:** Four — "Four codes replacing one is +3 on the cheap axis and −1 on the expensive
  one: once `--` is enforced, 'positional argument in a post-`--` position' is a single fact that
  the missing-label code can name precisely, including *which* label is missing, and a help line
  that compiles (D9)."

##### Q2-enf: enforce **both** §2.13 rules in `blink check` (**5-1, PLT dissents**)

- **Systems:** Yes — "M8 verifies that §2.13 states two normative rules and the compiler enforces
  zero, in both directions… Dead normative text is worse than silence, because a reader who trusts
  it writes a calling discipline the compiler will not hold up. The `--` bit is already parsed and
  stamped… and then never read by typecheck, so the declaration-site information exists and is being
  discarded — enforcement is a read, not new machinery."
- **Web/Scripting:** Yes — "E0511's spec text cannot be written honestly without deciding this: 'a
  label must name a parameter' codifies the current behaviour and kills §2.13; 'a label must name a
  keyword parameter' specifies something nothing enforces. That is why the question is not
  separable, and a spec section that ships with a recorded known-wrong rule is the worst outcome for
  a codebase that is training data — D12's principle applied to prose."
- **PLT:** ***(dissent)*** No — "M12 shows `tc_check_keyword_args` has exactly one call site, the
  bare-Ident free-function path, so enforcement added there would hold for `f(x: 1)` and not hold
  for `b.f(x: 1)`. That is not a migration inconvenience, it is **non-compositionality** — the same
  function, the same label, the same parameter, two behaviors selected by the receiver's spelling —
  and it is the identical defect I voted to delete E0517 for. Enforcing a rule on half of the call
  forms writes spec text that is false of the language as a whole." *Concern:* "I am one against
  five, and the cost of my being right in principle is that F5 stays open and §2.13 keeps stating
  two normative rules the compiler enforces zero of… **If Yes carries I do not obstruct it**, but I
  ask that the resolution record one sentence: enforcement applies to the call forms that reach
  `tc_check_keyword_args`, and [the method-path keyword-check ticket] is a prerequisite for it
  applying to methods." *(Recorded in §2.13's "Extent of enforcement" paragraph, and as a blocking
  dependency on the implementation ticket.)*
- **DevOps:** Yes — "M12 turns this from a tidiness question into a correctness one: an unrecognised
  label does not merely go unreported, it makes `check_arg_shapes` skip that argument's type check
  entirely, so a `Str` reaches an `Int` parameter and `blink check` exits 0. The comment authorising
  that skip names a back end we deleted, which is precisely the class of rule this ticket was opened
  to repatriate." *Concern:* "the two shipped explainer examples that are themselves illegal under
  the new rule — E0510's `open(path:, mode:)  // OK` at `src/diagnostics.bl:1144` and E0511's
  prescribed repair `greet(name: ...)` at `:1147` — must land in the same change set or `task ci`
  goes red on our own diagnostics."
- **AI/ML:** Yes, with the clause that enforcement covers method calls — "Recording rules in the
  spec while the compiler enforces neither of them (M8) publishes a separator that does nothing and
  trains every model on this tree in both forbidden forms. The clause is not optional for me…
  enforcing there alone yields a rule that holds for `greet(...)` and not for `b.greet(...)` — the
  same position-sensitivity that decided Q1 against E0517, reproduced deliberately."
- **Minimalism:** Yes, scoped to "calls against a declared `fn` signature, method calls included" —
  "M8 measured both §2.13 rules violated in both directions and accepted, so today the section is
  advice; an unenforced normative sentence is worse than no sentence, because this repo is training
  data and it teaches that §2.13 need not hold. The cost is two assertion lines in one test file, so
  devops's warn-then-error ramp protects nobody — a ramp exists for existing code, and there is
  none."

##### Q3: restate E0819 over the **`FfiScope` type**, not over the `ffi.scope()` call (**6-0, option B**)

- **Systems:** B — "The rule today is a spelling match… That tests how the call is written, not what
  the value is, so any binding or indirection walks past it while the hazard it guards is unchanged;
  the hazard is a libc `malloc`/`free` arena whose extent must be lexical, which is a property of
  the value, not of the callee's spelling."
- **Web/Scripting:** B — "'This one function call is legal in one syntactic slot' is trivia a
  developer memorises after being burned; '`FfiScope` is scope-bound, its values exist only as a
  `with` resource' is a fact about a type, which is where a developer already looks when something
  is refused… the enumeration was the tell that I was writing a type rule by listing its cases."
- **PLT:** B — "The property `ffi.scope` needs is a property of the *value*, not of the syntax that
  produced it: a `FfiScope` is region-delimited, and its lifetime must be bracketed the way `runST`,
  `withFile` and `thread::scope` bracket theirs." *Concern:* "The §9.1.1 text must cross-reference
  §5.5's Closeable-without-scope warning **by name, not by number**, because M5 (W0600
  double-assigned) is out of scope and I will not have this ticket's text depend on a code number
  another ticket may reassign." *(Honoured — §9.1.1 names §5.5 in prose and cites no W-number.)*
- **DevOps:** B — "A rule stated over the `FfiScope` type produces a diagnostic at every position
  where a scope can wrongly appear — field, parameter, return, type argument — whereas a rule stated
  over the `ffi.scope()` call site produces one only at the `let`… It also gives the rule a subject
  that survives someone writing a second scope-producing function." *Concern (all three message
  conditions recorded in §9.1.1):* "carry the user's own binder into the shown repair rather than
  the hardcoded `scope`; do **not** mark the `let` → `with ... as` rewrite machine-applicable, since
  no fixer can decide where the block ends; and… §9.1.1's severity contrast must refer to §5.5's
  rule in prose, never by the number W0600."
- **AI/ML:** B — "Stating the rule over the `FfiScope` type rather than over the `ffi.scope()` call
  is one rule a model applies by knowing a type, and D11 prefers one general rule over a per-case
  carve-out… I carry three drafting points into it: the explicit 'and nothing else' exclusivity
  sentence, because models never infer exclusivity from positive examples however many you print;
  one marked intentional-error example per D12; and `alloc_ptr[T]()` as the second help so the
  writer who wanted a plain allocation is not taught to wrap a `with` around the rest of the
  function." *Concern:* "The restatement needs `FfiScope` to be a named type a reader can look up,
  and if the spec has no such entry the rule floats free of anything the user can see in a
  signature." *(Addressed: `FfiScope` is now named in the §9.1.1 operations-table heading and given
  its own block.)*
- **Minimalism:** B — "B replaces the ad-hoc `node != tc_with_resource_node` identity gate with a
  statement about a type, which is the cheaper thing to carry."

##### Q4: make `Raw[T]` a **real marker type** (**6-0, option A; five of six blocking-conditional**)

Five panelists made their A vote conditional on a dedicated misplaced-`Raw` diagnostic shipping in
the same change set, falling to B without it. DevOps alone voted A unconditionally. The condition is
met: `RawOutsideTemplate` is specified in §3b.5 and is a blocking item on the implementation ticket.

- **Systems:** A, conditional — "Making `Raw[T]` a real marker type is right and free: as a
  transparent newtype it lowers to bare `T` exactly as `Errno(Int)` does — no box, no tag, no layout
  change, no indirection — so the trigger becomes a type question instead of a match on the callee's
  spelling… But D-F4 is correct that Q4-A as drafted lets the ticket's own MVCE fall into E0523 with
  `@derive(Display)`, `impl Display for Raw[T]` and `.debug()` — three repairs that are all
  impossible on a compiler-known marker type… I withdrew this code once on a false economy that
  counted codes instead of repairs, and D9 is about repairs."
- **Web/Scripting:** A, conditional — "Narrowing to the `Template[C]` coercion takes the
  false-positive rate to zero, and that is the whole mechanism: a security warning that fires on
  `io.println(\"hi {Raw(x)}\")` teaches people it is noise, someone sets it off project-wide, and
  then it protects nobody… The marker type is the typing mechanism and the dedicated diagnostic is
  the message; neither substitutes for the other, and A without the second is strictly worse than
  today."
- **PLT:** A, conditional — "W0310 today is neither sound nor complete: it fires on a plain `Str`
  that no template consumes, and it misses `let t = Raw(table)` entirely because `Raw` is the
  identity function at `src/typecheck.bl:14331`. No amount of message-fixing closes the false
  negative — only carrying the taint in the type does… The fix is to specify the diagnostic, not to
  keep the unsound trigger: one warning, 'a `Raw[T]` reached a position that does not consume it',
  first help **remove the `Raw(...)` wrapper** — a repair that compiles."
- **DevOps:** A, **unconditional** — "plt's false negative is decisive and no help-line ordering
  answers it — because `Raw` is the identity…, `let t = Raw(table)` then interpolating `t` launders
  past the warning entirely, which is the one case the rule exists to catch. Q4-A and my Q4-B were
  never rivals: A is the trigger, B was the message, and the message work composes onto A rather
  than competing with it. A trigger that fires on the wrong programs cannot be repaired by improving
  what it says."
- **AI/ML:** A, conditional — "reusing E0523 reuses its help, and 'add `@derive(Display)` /
  `impl Display` / call `.debug()`' is three impossible repairs on a compiler-known marker — a §3.1
  rule-1 violation, the same class as M6, on the ticket's own MVCE… That costs one code and I
  withdraw my round-1 'zero new codes' claim."
- **Minimalism:** A, conditional — "§3b.5 already claims `Raw[T]` is a compiler-known marker type
  and `src/typecheck.bl:14331` makes it the identity function, so A closes a gap between the spec
  and the tree rather than adding anything… Absent both, A converts the ticket's own MVCE from a
  false-positive warning with a working repair into a type error with three impossible ones, and I
  would rather keep the false positive."

##### Q4-supp-allow: the **§7 unsilenceable list** (**6-0 — was 3-3 before DevOps's M16**)

- **Systems:** §7 unsilenceable list — "A hard error on `@allow` alone therefore closes the door a
  reader reaches for and leaves a whole-project switch standing — it reads as a guarantee and is not
  one, which is the failure mode I object to most." *Clause:* "'Unsilenceable' must mean *no channel
  that records nothing*, not *no channel at all* — `@trusted(audit: K)` has to remain available for
  the legitimate case, or the list is a wall rather than a turnstile." *Concern:* "A warning no
  channel can turn off does not remove the pressure to silence it, it relocates it into source — an
  indirection or a helper that launders the value past the trigger — and that leaves no audit record
  at all."
- **Web/Scripting:** §7 unsilenceable list — "hard-erroring `@allow` closes one of two open channels
  and leaves the other wide — a door bolted next to an open window… the §7 list answers that
  objection directly, because it is not a property of `@allow` at all but a property of the warning,
  stated once and applying to every channel." *Concern:* "A list in §7 with no stated membership
  criterion becomes the place to park any warning an author feels strongly about, so it needs the
  criterion written alongside it — a warning belongs on the list only when suppressing it silently
  would destroy a record the language promises exists."
- **PLT:** §7 unsilenceable list — "M16 falsifies my position as a matter of quantification, and I
  would rather say so than defend it… A carve-out written per channel is a rule quantified over the
  channels someone happened to think of; it silently fails on the next one. The list states the
  property where it belongs — **on the warning**… The refusal clause matters because a suppression
  that silently fails to suppress and one that silently succeeds are equally bad: the author cannot
  tell which happened."
- **DevOps:** §7 unsilenceable list — "The hard error does not achieve its own goal… refusing
  `@allow` moves the escape hatch rather than closing it. It also puts an exception inside the
  general warning channel that a user discovers only by hitting it — the exact defect this ticket
  was opened to close, reintroduced one level down." *Concern:* "the list needs a test that asserts
  it against the implementation, not just prose."
- **AI/ML:** §7 unsilenceable list — "I voted hard error in round 2 and M16 is the fact that moves
  me… A hard error on `@allow` fixes the narrow channel and leaves `[lints] W0310 = \"off\"`
  reaching the same `lint_apply_override` path — a project-wide silence with no record and no
  diagnostic, which is a strictly larger instance of the hole I objected to."
- **Minimalism:** §7 unsilenceable list — "A hard error on `@allow` alone carves one channel and
  leaves a second wide open, which is the worst outcome available — a rule that looks enforced and
  is defeated by a two-line TOML edit… I have now held three positions on this sub-item and each
  move was forced by a fact I did not have — M3 in round 2, the `[lints]` channel now — so I will
  state the trajectory rather than bury it."

##### Q4-supp-rest: adopt all four uncontested sub-items (**6-0**)

`audit:` mandatory and non-empty; `@trusted(audit: K)` the sole channel; the channel stated once in
§7 rather than restated per diagnostic; `test` blocks annotatable.

- **Systems:** Adopt — "a mandatory non-empty `audit:` is what makes the annotation a record rather
  than a mute button." *Concern:* "Making `audit:` mandatory guarantees a string exists, not that it
  identifies anything."
- **Web/Scripting:** Adopt — "All four are corrections to things the spec already claims rather than
  new policy… making `test` blocks annotatable dissolves F14's unsuppressible position instead of
  documenting it, which D9 requires because a repair that cannot be written in a position is not a
  repair."
- **PLT:** Adopt — "one channel, one statement, no unsuppressible case left to document. I withdraw
  my round-1 conditioning of this on `blink audit --raw-queries` existing: the annotation is a
  **written assertion**, greppable and diff-reviewable, and a tool is a reader, not the meaning."
  *Concern:* "Removing W0310 from `@allow`'s reachable domain is a **breaking change that removes a
  working capability** (M3), not a clarification, and the resolution should say so in those words."
  *(Honoured — §9.1 says exactly that.)*
- **DevOps:** Adopt — "naming the channel once in §7 is how §3b.5 came to assert `@trusted` is the
  only channel while the implementation has two." *Concern:* "`blink audit --raw-queries` does not
  exist… so the reference must be struck from `sections/03b_contracts.md:510` and from the W0310
  explainer in this change set, with the tool filed separately." *(Done; the tool is a separate
  ticket.)*
- **AI/ML:** Adopt — "stating it once in §7 lets a model derive the channel instead of memorizing a
  table."
- **Minimalism:** Adopt — "All four are subtractions or statements of something already true."
  *Concern:* "'Stated once in §7' is only a subtraction if §3b.5's copy is actually deleted and
  replaced with a cross-reference, and spec edits that add a pointer while leaving the old prose in
  place are the normal outcome." *(Honoured — §3b.5 and §9.3 now point at §9.1 and carry no copy.)*

#### Phase D

Not triggered. No line came back closer than 5-1.

---

### Final Spec

```blink
// Q1 -- a generic function's name is a value; the expected type solves its binders
fn identity[T](x: T) -> T { x }
fn apply(f: fn(Int) -> Int, n: Int) -> Int { f(n) }

let r = apply(identity, 3)            // OK -- the parameter type fixes T = Int
let g: fn(Str) -> Str = identity      // OK -- the annotation fixes T = Str
let f = identity                      // error[CannotInferType] -- nothing fixes T
                                      // help: `let f: fn(Int) -> Int = identity`

// Q2 -- both §2.13 rules are enforced; five codes divide the call-site label mistakes
fn transfer(amount: Int, -- from: Account, to: Account) -> Int { amount }

transfer(300, from: alice, to: bob)   // OK
transfer(300, alice, bob)             // error[UnlabeledKeywordArg]
transfer(300, frm: alice, to: bob)    // error[InvalidKeywordArg]
transfer(300, from: alice, bob)       // error[PositionalAfterKeyword]
transfer(300, from: alice, from: bob) // error[DuplicateKeywordArg]
transfer(amount: 300, ...)            // error[InvalidKeywordArg] -- `amount` is positional

// Q3 -- the rule is stated over the FfiScope type, not over the ffi.scope() call
with ffi.scope() as scope { ... }     // OK -- the only position an FfiScope may occupy
let arena = ffi.scope()               // error[FfiScopeNotWithResource]

// Q4 -- Raw[T] is a real marker type; the trigger is the value's type
let t = Raw(table)                    // t : Raw[Str] -- the marker survives the binding
db.query_one("... {t} ...")           // warning[RawBypassesParam] -- audit-gated
io.println("scanning {Raw(table)}")   // error[RawOutsideTemplate]

@trusted(audit: "DB-003")             // the sole suppression channel for an audit-gated diagnostic
@trusted                              // error[TrustedRequiresAudit]
```

**Locked design points**

- E0517 `BareGenericFnAsValue` is **deleted**. A generic function's name is a value wherever a
  function value is expected, and its binders are solved by unifying against the expected type. The
  residual — no expected type fixes the binders — is `CannotInferType` (E0301), reported at the
  reference, with the **annotation** form as its first `help:` and no bracket form while E0307
  stands. Per the catalog convention, E0517 is never reused.
- Both §2.13 rules are **enforced by `blink check`**: a label on a positional parameter is rejected,
  and a keyword parameter supplied without its label is rejected. Neither is a formatter concern.
- A call-site label resolves in the callee's **keyword-parameter namespace** — the parameters after
  `--`, and nothing else. The rule governs calls to functions **and methods**. Labels in
  variant-payload applications and struct literals name **fields** and are outside it.
- Five codes divide the call-site label mistakes: `MissingKeywordArg` (E0510),
  `UnlabeledKeywordArg` (E0529), `InvalidKeywordArg` (E0511), `PositionalAfterKeyword` (E0527),
  `DuplicateKeywordArg` (E0528). `UnlabeledKeywordArg` is the only one whose fix is
  machine-applicable.
- `ffi.scope()` returns a value of type **`FfiScope`**, which is scope-bound: it may occur only as
  the resource of a `with ... as` block, and nowhere else — not `let`-bound, passed, returned,
  stored in a field, or written as a type argument. The rule is stated over the **type** because the
  hazard belongs to the value. It is an error where the `Closeable`-without-scope rule is a warning
  because an `FfiScope` used outside `with ... as` releases **nothing**.
- `Raw[T]` is a **real marker type** with no `Display`. The marker survives a binding, and nothing
  strips it implicitly. `RawBypassesParam` fires on the `Template[C]` coercion and only there. A
  `Raw[T]` in a position that does not consume it is `RawOutsideTemplate` (E0530), which exists
  because `MissingDisplayImpl`'s repairs are all impossible on a marker type.
- **Audit-gated diagnostics** are stated once, in §9.1. `@trusted(audit: K)` is their sole
  suppression channel; `@allow(Name)` and `[lints]` do not reach them, and naming one there is
  **refused, not ignored**. `@trusted` without a non-empty `audit:` is `TrustedRequiresAudit`
  (E0836). Membership criterion: a diagnostic belongs on the list only when silently suppressing it
  would destroy a record the language promises exists. Unsilenceable means **no channel that records
  nothing**, not no channel at all. Removing `@allow`'s reach over these warnings is a **breaking
  change**, and release notes must say so in those words.
- `blink audit --raw-queries` and `--no-unaudited-raw` are **struck from the spec**; neither flag
  exists. The tool is filed as its own ticket, and the sentence returns when the tool ships.
