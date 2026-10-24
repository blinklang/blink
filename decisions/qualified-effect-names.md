[< All Decisions](../DECISIONS.md)

# Module-Qualified Effect Names — Design Rationale

The spec lets a module qualifier stand before a type name and a trait name in every slot (§10.1). It said nothing
about effect names. In the compiler, `! lib.Log` passed `check` and then failed with a false `UndeclaredEffect`.
`with handler lib.Log` stopped with an internal error. `lib.Store.Read` was a parse error, because the second `.` in
a row has one meaning today: parent.child. `! Nope`, `! nosuch.Log` and `! lib.Nope` all passed `check`, because
E0538 had no emit site.

The panel decided whether a qualified effect name is legal, what handle it gives, and how each failure is reported.

### Panel Deliberation

Six panelists voted: Systems, Web/Scripting, PLT, DevOps/Tooling, AI/ML and Minimalism. Four phases ran: A
(independent proposals), B (debate), C (silent ballot) and D (a second round on Q4 only). Phase A and Phase B below
are excerpts, with the seat named. Phase C and Phase D are the votes in full.

#### Phase A — Independent proposals

- **Systems**: "A qualified effect name works in every slot that takes the bare name: the `!` row, `handler`,
  `with handler`, `Handler[...]`, `@capabilities(...)`, `Template[C]`. The qualifier is the import's leaf name or
  alias (§10.1). The spelling does not change identity. Identity is the declaration: module plus effect name (plus
  child path)." Handle: "The handle is the lowercase leaf effect name, never the qualified form: `! lib.Log` gives
  `log.log("x")`." Parse rule by case: "a lowercase segment before a `.` is a module qualifier."
- **Web/Scripting**: "A JS or Python developer writes `lib.Log` in a type position and in an effect row the same
  way. Two rules for effect names would cause questions. So one rule: an effect name is `Name` or `qualifier.Name`,
  with the same qualifier that §10.1 already gives." On a handle that has the spelling of a module: "in a function
  that declares the effect, the handle wins (§3c.4, reserved namespace). The user aliases the import: `import
  std.path as paths`."
- **PLT**: "Spelling does not change identity. Two names are the same effect only if they resolve to the same
  declaration (§3b: \"the module qualifies the name\")." Grammar: "If the first segment is an import qualifier in
  scope, it is the module, and the rest is `Effect` or `Effect.Child`. Otherwise it is `Effect.Child` as today." Two
  effects with one handle: "an error at the row (new code), because the handle would not be unique." Failures:
  "all E0538 (UnknownEffect) with a distinct message: unknown qualifier, name not exported, name is a type or
  trait, not an effect."
- **DevOps/Tooling**: "A feature the user can write, that parses, and then crashes in codegen is the worst result."
  "A bare `! Log` that was not imported gives E0538 with a hint \"did you mean `lib.Log`?\" when exactly one import
  exports it." "Subsumption and handler match compare declaration ids, never strings."
- **AI/ML**: "One rule, \"qualify like any other name\", adds almost no decision points." The handle:
  "`lib.log.log(\"x\")` passes `check` and then ICEs. It becomes a diagnostic: \"the handle is `log`; write
  `log.log(...)`\"."
- **Minimalism**: "Reject. An effect name in any effect slot is bare. A module qualifier is a compile error."
  "A qualified sub-effect `lib.Store.Read` needs a new three-segment grammar rule in a row where `x.Y` already means
  parent.child. This is the real cost of the other option. Rejecting costs zero grammar." Rule 2 of the proposal:
  "The handle is the lowercase of the effect name as bound in the file. For an aliased effect, that is the alias
  (`OtherLog` gives `otherlog`)."

#### Phase B — Debate highlights

- **Case or lookup (V2)**: Five seats first wrote a case rule (a lowercase first segment is a module). Then Systems
  wrote: "The spec fixes no case rule for module names or aliases (fact, section 10.1 and 10.5), so a parse rule by
  case would add a new naming rule." PLT: "A rule that depends on convention is not a rule. Resolve the first
  segment: if it is an import qualifier in scope, it is the module; else parent.child. If it is both, reject as
  ambiguous. Case may serve as a diagnostic hint only." DevOps, AI/ML, Web and Minimalism moved to lookup.
- **Alias and handle (V3)**: PLT took Minimalism's rule 2: "A selective alias `Log as OtherLog` gives `otherlog`.
  It stays local (§4.4) and it is never qualified." DevOps opposed: "One effect would have two handle names in two
  files. Grep, LSP rename and a reader of §4.4 would all lose." Web: "Today's rule is one effect, one handle."
  Minimalism withdrew rule 2. PLT asked for a vote on the question.
- **Handle or qualifier (V5)**: Minimalism: "One rule for one problem. plt's \"reject the row as ambiguous\" is the
  smallest. web/devops/aiml add context-dependent precedence (handle wins here, module wins there)." DevOps:
  "a row has no handle, so no clash exists there."
- **Diagnostic code (V6)**: DevOps: "One code gives one `blink explain` page and one LSP quick-fix family. The
  generic unknown-module error does not tell the user that an effect was expected." Web and PLT first held the
  unknown-module error for an unknown qualifier.
- **Extras (V7)**: Minimalism opposed the `did you mean` hint and the `lib.log.log` diagnostic: "One help line,
  \"import the effect and use its bare name\", covers both." Systems: the vtable C name must include the module,
  "a required precondition, not optional."

#### Phase C — Final vote

Silent ballot. Each seat read the Phase A proposals and the Phase B replies, then voted alone. The text of each vote
is the seat's own.

**Q1. Is a module-qualified effect name valid in every effect slot (row, `handler`, `with handler`, `Handler[...]`,
`@capabilities(...)`, `Template[...]`)?** A: valid in every slot. B: reject; an effect name is bare. **Result: A, 5-1
(Minimalism dissents).**

- **Systems — A.** Reasoning: A qualified name costs one compile-time map from spelling to declaration. The evidence
  slot and the vtable are chosen by declaration, so the layout and the run-time cost do not change. Reject leaves
  `import lib` with no way to name an effect, and it makes effects an exception to the rule that qualified traits and
  types set. Concern: Three-segment names (`lib.Store.Read`) share one dotted grammar with parent.child, so the
  resolver, not the parser, decides the meaning, and a bug there picks the wrong vtable slot.
- **Web/Scripting — A.** Reasoning: A JS, TS or Kotlin developer writes `lib.Log` where `lib.Token` works. The trait
  decision set that rule, and an exception for effects makes one more Stack Overflow question. Reject (B) also fails
  the first time two modules export `Log` and the user imports whole modules. Concern: The three-segment row
  `lib.Store.Read` plus the import-lookup rule is more parser and resolver work than min's reject, and it must not
  break `FS.Read`.
- **PLT — A.** Reasoning: Types and traits take a qualifier in every slot, and an effect name resolves to a
  declaration in the same way. Two typing rules for one namespace (§3b says types, traits and effects share it) would
  differ for no typing reason. With identity fixed as the declaration, the three-segment path is one grammar
  production, and it resolves by import lookup. Concern: If the implementation compares spellings anywhere (vtable C
  names, evidence slots), a qualified and a bare name for one effect become two effects, and handlers silently fail
  to match.
- **DevOps/Tooling — A.** Reasoning: Today `! lib.Log` passes check and then fails with a wrong `UndeclaredEffect`,
  and `with handler lib.Log` ends in an ICE. One rule (qualify like a type or trait) gives one diagnostic surface,
  one LSP completion path (after `lib.`, offer that module's effects) and one `blink explain` page. E1005 rejects two
  same-name selective imports, so the qualifier is the only way to name two same-name effects in one file. Concern:
  The new error for a row with two effects and one handle forces the user to restructure code, and the error text
  must say so plainly or it reads as a compiler bug.
- **AI/ML — A.** Reasoning: A model that learns "qualify any name" from the trait decision will write `! lib.Log`.
  Option B makes effects an exception to that rule, so it adds a decision point and a rule to recall. Today gen1
  accepts `! lib.Log` in check and fails later, so the form is already what a model writes. A makes it work, and one
  rule covers every slot. Concern: The qualified sub-effect `lib.Store.Read` has three segments, and models may still
  write `lib.Store.Read.x` or put the qualifier on the handle, so the diagnostics must catch both.
- **Minimalism — B.** Reasoning: Today's gen1 is half-built, and A needs a three-segment row grammar, a
  handle-collision error, a qualifier-versus-effect ambiguity error and a new "did you mean" path. B needs none of
  these. It needs only one sentence in §4.3 and the E0538 emit site that every seat wants anyway. A user with two
  same-name effects imports one selectively and uses a bare name, or puts each use in its own function. Concern: A
  user who writes `import lib` and `! lib.Log` finds that it fails, although `lib.Token` works, and that gap costs
  more support questions than the grammar would have.

**Q2. Does an `as` alias on a selectively imported effect (`import other.{Log as OtherLog}`) change the handle?** A:
no; the handle is the lowercase of the declared effect name. B: yes; the handle is the lowercase of the name as bound
in the file. C: an `as` alias on an effect is rejected. **Result: A, 5-1 (PLT dissents).**

- **Systems — A.** Reasoning: The handle is a field on the evidence vector, chosen at compile time from the
  declaration. If an `as` alias changed the handle, one effect would have two handle names in two files, and codegen
  and tools would have to track a per-file name for no run-time gain. One handle per declaration keeps generated code
  and C names predictable. Concern: The collision error forces the user to split a function when two same-name
  effects meet, and the spec must say the alias renames the name in the file only.
- **Web/Scripting — A.** Reasoning: One effect, one handle. A user who reads `log.log(...)` must predict the handle
  from the declared name, not from the import line of that file. An alias that changes the handle makes the same code
  read differently in two files, and a dev cannot grep for it. Concern: Under A the only fixes for `a.Log, b.Log` are
  to rename an effect or split the function, which is harsher for a user who does not own the effect declaration.
- **PLT — B.** Reasoning: §10.5 already lets an import rename any listed name, and the handle is a file-local name in
  the reserved namespace (§3c.4). Deriving the handle from the name bound in the file keeps §4.4 true with no import
  resolution beyond the file's own import line. It also gives `! a.Log, b.Log` a fix that needs no new rule: `import
  b.{Log as BLog}`. The spec must state this, because §10.5 is silent. Concern: One effect has two handle spellings
  in two files, so grep and LSP rename must follow the import line to link them.
- **DevOps/Tooling — A.** Reasoning: One effect gets one handle, the lowercase of its declared name, in every file.
  Grep, LSP rename, `blink fmt` output and a reader of §4.4 all depend on that. An alias changes the spelling in the
  file only, and the collision error names the fix: put each use in its own function, or rename one effect. Concern:
  A user who aliases `Log as OtherLog` and then writes `otherlog.log(...)` gets an unknown-handle error, so that error
  must say "the handle is `log`".
- **AI/ML — A.** Reasoning: The handle is the lowercase of the declared effect name, whatever the spelling. A model
  can then predict `log` from the effect declaration alone, in every file. Option B gives one effect two handles in
  two files, and the model cannot know which without reading the import line. Option C removes the choice but adds a
  rule that is a new surprise (the alias is legal on a type but not on an effect). Concern: A user who writes `import
  other.{Log as OtherLog}` may expect `otherlog`, so the collision error must name the real fix (put each use in its
  own function, or rename one effect).
- **Minimalism — A.** Reasoning: The handle is the lowercase of the declared effect name, whatever the spelling. A
  handle that follows the import line gives one effect two handles in two files, and §10.5 does not say that. I
  withdraw min-1 rule 2. Rejecting the alias (C) is smaller still, but it leaves two same-name effects with no way to
  coexist in one file, so A is the smallest rule that works. Concern: Under A, an aliased effect is named `OtherLog`
  in the row but `log` in the body, and a reader may find that odd.

**Q3. In an expression, a module qualifier and a reserved handle have one spelling (`path.path_stem` in a function
that declares `Path`, with `import std.path`).** A: the handle wins (§3c.4), with a hint that names the alias fix. B:
reject the ambiguous use. **Result: A, 5-1 (Minimalism dissents).**

- **Systems — A.** Reasoning: Handles are a reserved namespace (§3c.4), and the compiler already knows which handles
  a function declares. The handle wins in an expression, so a call site resolves in one step with no extra pass. The
  hint names the alias fix. Concern: A module used both as a qualifier and as a handle in one function becomes
  unreachable without an alias, and the user may find that surprising.
- **Web/Scripting — A.** Reasoning: In an expression inside a function that declares the effect, the handle wins
  (§3c.4). It is the same shadowing rule a dev knows from locals. The hint names the alias fix (`import std.path as
  paths`), so the user fixes it in one step. B's reject would make a legal-looking `path.path_stem` an error with no
  module in the user's mind. Concern: The same spelling means the handle in one function and the module in another,
  so a user who adds an effect to a row can break a call below it.
- **PLT — A.** Reasoning: In an expression, §3c.4 already reserves the handle in the scope of a function that
  declares the effect, so the handle wins like any local. One precedence rule that already exists is smaller than a
  new rejection. The hint names the alias fix so the module stays reachable. Concern: A reader sees `path.path_stem`
  resolve differently in two functions of one file, depending on the row.
- **DevOps/Tooling — A.** Reasoning: §3c.4 already reserves the handle in a function that declares the effect, so the
  handle wins and no new precedence is invented. The hint names the alias fix (`import std.path as paths`), which the
  LSP can offer as a quick-fix. Rejecting the use (B) would make a valid function body an error for a clash the user
  cannot see in the row. Concern: The module call `path.path_stem(...)` silently changes meaning inside functions that
  declare `Path`, so the hint must fire at every such use.
- **AI/ML — A.** Reasoning: In an expression, the handle wins (§3c.4) and a hint names the alias fix. This is the
  rule the spec already has for reserved handles, so a model learns no new precedence. Option B rejects a use that
  has one clear reading by an existing rule and costs the user a rename. Concern: A model that has seen
  `path.path_stem` work as a module call in another file may not expect the handle to shadow it, so the hint text
  must be good.
- **Minimalism — B.** Reasoning: One rule for one problem: reject the ambiguous use, and name the alias fix in the
  error. A precedence rule that depends on whether the function declares the effect is a second rule that a reader
  must also know. It also means the same spelling changes meaning between two functions of one file. Concern:
  Rejecting means a function that declares `Path` cannot call `path.path_stem` without an alias, which is a hard
  error where the handle-wins rule would have been silent.

**Q4. The diagnostic for an unknown qualifier in an effect slot (`! nosuch.Log`).** A: E0538 for every failure in an
effect slot, with a distinct message per cause (unknown qualifier, name not exported, not an effect). B: the existing
unknown-module error for an unknown qualifier, as in a type; E0538 for a known module with no such effect or a name
that is not an effect. **Phase C result: A, 4-2 (Web and PLT voted B). Phase D re-voted this question; see below.**

- **Systems — A.** Reasoning: One code for every failure in an effect slot means one check path in the front end, one
  `blink explain` page and one place that needs an emit site (today E0538 has none). A distinct message per cause
  keeps each case clear. Concern: An unknown qualifier gets a different code in a type slot than in an effect slot,
  and that difference is a small inconsistency to document.
- **Web/Scripting — B.** Reasoning: An unknown qualifier is the same mistake as `nosuch.Token` in a type, so it gets
  the same message the dev already knows. E0538 stays for "known module, no such effect" and "not an effect", one
  diagnostic per cause. A qualifier in an effect slot still names a module, so the module error is not wrong.
  Concern: A user who types `! nosuch.Log` gets a module error that does not say an effect was expected, and devops
  may be right that this slows them down.
- **PLT — B.** Reasoning: An unknown qualifier is the same fault in a type slot and in an effect slot, so it keeps one
  diagnostic. E0538 stays for a known module with no such effect, or a name that is not an effect: one diagnostic per
  cause. This matches the typing rule: the qualifier is resolved first, the effect second. Concern: A user who writes
  `! nosuch.Log` gets a module error with no hint that an effect was expected.
- **DevOps/Tooling — A.** Reasoning: One code for every failure in an effect slot gives one `blink explain` page and
  one quick-fix family. A distinct message per cause (unknown qualifier, name not exported, not an effect) keeps each
  message exact. The generic unknown-module error does not tell the user that an effect was expected. Concern: A tool
  that groups errors by code will mix three different causes under E0538, so the messages must stay distinct.
- **AI/ML — A.** Reasoning: One code, E0538, for every failure in an effect slot gives a model one place to look, and
  one `blink explain` page. A distinct message per cause keeps the fix clear. Option B splits the same slot across
  two codes, and a model must learn which cause gets which. Concern: The unknown-module error in type slots and E0538
  in effect slots differ for the same typo class, so a model may expect the same code in both.
- **Minimalism — A.** Reasoning: One code for every failure in an effect slot, with a distinct message per cause. In
  an effect position an unknown qualifier is not a module-name problem, and the generic unknown-module error would
  mislead. One code gives one `blink explain` page. Concern: Under B, a user who mistypes the module in an effect row
  gets an error that does not say an effect was expected.

**Q5a. `lib.log.log("x")` gets a diagnostic that names the handle: "the handle is `log`; write `log.log(...)`".** A:
yes. B: no. **Result: A, 5-1 (Minimalism dissents).**

- **Systems — A.** Reasoning: `lib.log.log("x")` passes check and then ICEs today. Any error here is better than a
  crash, and a message that names the handle costs one string in the diagnostic and no run-time cost. Concern: The
  hint is one more special case in the diagnostic code that needs a test.
- **Web/Scripting — A.** Reasoning: `lib.log.log("x")` is the first thing a dev writes, because `lib.Token` taught
  them to qualify. Today it ICEs. One line, "the handle is `log`; write `log.log(...)`", fixes it at once. Concern:
  This is one more special-case message to keep in the compiler.
- **PLT — A.** Reasoning: `lib.log.log("x")` passes check today and then ICEs, so a user will write it. A diagnostic
  that names the handle costs one message and removes a crash path. Concern: The check must run before lowering, or
  the ICE stays reachable.
- **DevOps/Tooling — A.** Reasoning: `lib.log.log("x")` passes check today and ICEs at run. A diagnostic that names
  the handle ("the handle is `log`; write `log.log(...)`") is the cheapest fix for a user and for a model, and it
  costs one help line. Concern: If the check is added as a special case, it may miss other qualified-handle spellings
  (`o.log.log`).
- **AI/ML — A.** Reasoning: `lib.log.log("x")` is the likely error a model makes after it learns `lib.Log`. A
  diagnostic that states the correct spelling, `log.log(...)`, is the cheapest fix a model can read and apply. It
  costs one message and no new rule. Concern: The diagnostic must fire only when `lib` is an import qualifier and
  `log` is the handle of an effect in the row, or it will give false hints.
- **Minimalism — B.** Reasoning: `lib.log.log("x")` is a rare slip, and the existing error plus one help line covers
  it. Each special-case message adds a diagnostic path to maintain and to test. Concern: A user who writes
  `lib.log.log(...)` gets a plain unresolved-name error and has to work out the handle rule alone.

**Q5b. A bare `! Log` that was not imported gets E0538 with "did you mean `lib.Log`?" when exactly one import exports
it.** A: yes. B: no. **Result: A, 5-1 (Minimalism dissents).**

- **Systems — A.** Reasoning: The compiler already has the export table of every import, so the lookup is a
  compile-time scan with no cost to generated code. It turns a bare E0538 into a fix the user can apply. Concern: The
  hint is wrong when two imports export the same name, so it must stay limited to exactly one match.
- **Web/Scripting — A.** Reasoning: Forgetting an import is the most common mistake. "did you mean `lib.Log`?" is the
  same help rust-analyzer and TS give, and it costs little. It applies only when exactly one import exports the name,
  so it does not guess. Concern: A hint that suggests the qualified form may lead users to write `lib.Log` where a
  selective import is what the code base uses.
- **PLT — A.** Reasoning: The hint fires only when exactly one import exports the name, so it is never wrong. It costs
  no grammar and helps the user who forgot the qualifier. Concern: Under Q2 B the hint might name `lib.Log` where the
  user had aliased it to another name in this file.
- **DevOps/Tooling — A.** Reasoning: The compiler knows which imports export the name, so "did you mean `lib.Log`?"
  is a mechanical suggestion for the LSP quick-fix. It fires only when exactly one import exports the name, so it
  never guesses. Concern: With two candidate imports the hint is silent, and the user sees a bare E0538 with no help.
- **AI/ML — A.** Reasoning: A bare `! Log` that was never imported is a common model error. "Did you mean `lib.Log`?"
  gives the fix at once and lowers retry count. It fires only when exactly one import exports the name, so it is
  never a guess. Concern: If two imports export `Log`, the hint is silent and the model gets the bare E0538 with no
  direction.
- **Minimalism — B.** Reasoning: The "did you mean" hint needs an index of every import's exports to be searched on
  each failure, and it covers a case that the plain E0538 message already makes clear. No other name kind in the spec
  has this hint. Concern: A user who forgets the import gets only "unknown effect" and must find the module on their
  own.

**Q5c. A bare name and a qualified name for one declaration may mix in one row and deduplicate.** A: yes, in the spec
text. B: no. **Result: A, 6-0.**

- **Systems — A.** Reasoning: Identity is the declaration, so the compiler dedups by declaration id when it builds
  the row. A bare name and a qualified name for one declaration then give one evidence slot, not two. Concern: A
  reader can mistake `Log, lib.Log` for two effects, so the formatter or a lint may need to warn about the duplicate.
- **Web/Scripting — A.** Reasoning: Rejecting a mixed row (`! Log, lib.Log`) for one declaration punishes a user for
  a harmless spelling choice and would show up after a refactor. Dedup matches "spelling does not change identity",
  which Q1 A already sets. Concern: Two spellings of one effect in one row hurt readability, and a lint may be needed
  later.
- **PLT — A.** Reasoning: Identity is the declaration, so a bare and a qualified spelling of one declaration are one
  row item. Rejecting the mix would make spelling observable and contradict the agreed rule on identity. Concern:
  Deduplication hides a redundant row entry that a linter should flag.
- **DevOps/Tooling — A.** Reasoning: A formatter and a linter cannot require one spelling if the spec rejects the
  mix. Declaration identity already makes `Log` and `lib.Log` equal, so deduplication is the consistent result. The
  spec text should say it, so the LSP does not flag a duplicate row entry as an error. Concern: A row that mixes both
  spellings of one effect is legal but confusing, so `blink lint` may need a style warning later.
- **AI/ML — A.** Reasoning: Mixing a bare and a qualified name for one declaration in one row follows from "identity
  is the declaration". Stating it in the spec removes a case a model would otherwise have to guess. Without the text,
  a model may think the mix is an error and rewrite working code. Concern: Deduplication hides a redundant row entry,
  so a linter should flag the duplicate or the row grows noise.
- **Minimalism — A.** Reasoning: Identity is the declaration, so a mixed row falls out of that rule. Saying it in the
  spec text costs one sentence and stops an implementer from adding a duplicate-name error. This is not new surface;
  it records a consequence. Concern: The sentence is dead text if Q1 is B, because no qualified spelling exists to
  mix.

#### Phase D — Round 2 on Q4

Phase C left Q4 at 4-2. A focused debate (D1) and a second silent vote (D2) ran on Q4 only. The other questions stood.

**D1 highlights.**

- **Web/Scripting** (changed from B to A): "a dev does not learn a code number. They read the message text. An E0538
  message can keep the familiar words and add the one fact the dev needs: \"unknown module `nosuch` in effect
  `nosuch.Log`\"." Condition for the spec text: "the unknown-qualifier message under E0538 must name the qualifier as
  an unknown module, in the same wording as the type-slot error, and must say an effect was expected."
- **Systems** (kept A): "The argument is right about the resolution step. It is wrong about the code the user sees.
  In B, one effect slot can give two codes: the unknown-module error for a bad qualifier, and E0538 for a bad
  name." Request: "the unknown-qualifier message in an effect slot uses the same
  cause wording as the type slot, so the two slots differ in the code only."
- **PLT** (kept B): "The typing fault is the same in both slots: the qualifier names no import. Resolution has two
  steps, qualifier first, effect second. Step one does not depend on the slot, so its error should not depend on the
  slot." "If A wins, I have no soundness objection."
- **DevOps/Tooling** (kept A): "In an effect slot, the user knows only that the slot takes an effect, and the useful help lists the imports that
  export effects, or says \"no import exports an effect named `Log`\"." The message
  names the failing step: "unknown module `nosuch` in an effect name; expected an effect".
- **AI/ML** (kept A): "For `! nosuch.Log` the compiler does not know that `nosuch` was meant as a module. It reads
  `nosuch` as a parent effect and `Log` as its child." "With A, every effect-slot failure is E0538."
- **Minimalism** (kept A): "B gets the same result only if the module error grows effect-specific text, and then B
  is A with a second code."

**D2 re-vote.** Result: **A, 5-1 (PLT dissents).**

- **Systems — A.** Reasoning: Every failure in an effect slot reports one code, E0538, so the front end has one check
  path and one emit site. E0538 has none today, so A gives that fix a single scope and B would split it across two
  checks. The qualifier-resolution routine stays shared with the type slot; the effect slot reports its failure as
  E0538 with the same cause wording ("no module `nosuch` in scope"), so only the code differs and the code says an
  effect was expected. Nothing in codegen changes: the declaration is the identity, so the diagnostic choice has no
  run-time cost. Concern: An unknown qualifier gets a different code in a type slot than in an effect slot, and the
  spec and the `blink explain` page for E0538 must document that three distinct causes share one code.
- **Web/Scripting — A.** Reasoning: A developer reads the message text and does not learn code numbers. An E0538
  message can keep the module wording they know from a type slot ("unknown module `nosuch` in effect `nosuch.Log`")
  and add the one fact the type error lacks: an effect was expected. B gives them the first only, and it splits one
  slot across two codes for no gain the developer sees. A also gives one emit site for E0538, which has none today.
  Concern: The same typo, `nosuch.Token` and `nosuch.Log`, gets two codes in two slots, so the E0538 text must keep
  the type-slot module wording and name the qualifier as an unknown module, or the familiarity is lost.
- **PLT — B.** Reasoning: Resolving a qualified name has two steps: the qualifier names an import, then the name is an
  effect of that module. The first step does not depend on the slot, so its fault should keep one diagnostic in a
  type slot and in an effect slot. E0538 then keeps one meaning, "this is not an effect", and the unknown-module
  error keeps one meaning, "this is not a module". B allows a slot-aware line in the unknown-module message ("an
  effect was expected here"), which answers the devops point without a second code for one fault. Concern: If A wins,
  E0538 covers a module fault as well as an effect fault, and `nosuch.Token` and `nosuch.Log` get two codes for one
  typo; I have no soundness objection, but the A text must say that the E0538 message for an unknown qualifier names
  the missing module.
- **DevOps/Tooling — A.** Reasoning: Under the agreed rule, a first segment that is not an import qualifier makes
  `nosuch.Log` read as parent.child, so the compiler cannot claim the user meant a module. One code for every
  effect-slot failure gives one emit site (E0538 has none today), one `blink explain` page and one LSP quick-fix
  family (add import, did-you-mean). A distinct message per cause keeps each error exact. The message for an unknown
  qualifier should use the type-slot wording ("unknown module `nosuch`") and add that an effect was expected, as web,
  sys and plt asked. Concern: Tools that group diagnostics by code will put three causes under E0538, and a user who
  typos a module in a type slot and in an effect slot sees two codes for one typo class, so the messages must stay
  distinct and the explain page must list all three causes.
- **AI/ML — A.** Reasoning: One code for every failure in an effect slot gives a model one rule: a bad effect name is
  E0538, and the message says which cause. B makes the code depend on whether the first segment resolved, and that is
  one more decision point for a model to learn. Under the agreed rule, `nosuch` in `! nosuch.Log` can read as a parent
  effect, so the fault the compiler can state is "no effect or module `nosuch`", and E0538 fits that. The D1 replies
  from web, sys and min show the type-slot wording can carry over into the E0538 message, so a model that knows the
  type-slot error still recognizes the cause. Concern: The same typo gets a different code in a type slot than in an
  effect slot, so a model may expect the type-slot code and must read the message text to find the cause.
- **Minimalism — A.** Reasoning: An effect row holds only effects, so every failure in it has one kind: the name does
  not resolve to an effect. A single code, E0538, with a distinct message per cause (unknown qualifier, name not
  exported, not an effect) costs one check path and one `blink explain` page. B needs the module-error path to know it
  was called from an effect slot, or the message loses the "effect expected" text. B then becomes A with a second
  code. Concern: The same typo class (`nosuch.Token` and `nosuch.Log`) gets two codes in two slots, and users and
  tools that group by code must learn that E0538 names the slot kind, not the cause.

### Final Spec

| Question | Result | Dissent |
|---|---|---|
| Q1 qualified effect name in every effect slot | A, 5-1 | Minimalism |
| Q2 an `as` alias does not change the handle | A, 5-1 | PLT |
| Q3 a handle wins over a qualifier in an expression, with the alias hint | A, 5-1 | Minimalism |
| Q4 E0538 for every failure in an effect slot, one message per cause | A, 5-1 after Phase D (Phase C was 4-2) | PLT |
| Q5a `lib.log.log(...)` gets "the handle is `log`; write `log.log(...)`" | A, 5-1 | Minimalism |
| Q5b a bare name that no import brings in gets "did you mean `lib.Log`?" | A, 5-1 | Minimalism |
| Q5c a bare and a qualified spelling of one effect deduplicate | A, 6-0 | none |

What the spec now says:

- **§10.1.** A qualified effect name works in every slot that takes the bare effect name. The qualifier does not
  change the handle.
- **§4.3.** The first part of a dotted name resolves by import lookup, not by case. An import qualifier in scope is
  the module; otherwise the name is parent.child. A spelling that is both is `AmbiguousEffectQualifier` (E0561), and
  the error names the alias fix. A bare and a qualified spelling of one effect are one effect. E0538 covers every
  failure in an effect slot, with a distinct message for each of three causes. A bare name that no import brings in
  gets "did you mean `lib.Log`?" when exactly one import exports it.
- **§4.12.** The handle is the lowercase declared effect name, whatever the spelling or alias. A qualified handle is
  not valid, and gets the help line. Two effects with one handle in one row are `EffectHandleCollision` (E0562). In
  an expression a reserved handle wins over a module qualifier of the same spelling.
- **ERROR_CATALOG.** E0538 grows to cover the causes. E0561 and E0562 are new.

Dissents, in the seats' own words:

- **Minimalism, Q1:** "A needs a three-segment row grammar, a handle-collision error, a qualifier-versus-effect
  ambiguity error and a new \"did you mean\" path. B needs none of these."
- **PLT, Q2:** "§10.5 already lets an import rename any listed name, and the handle is a file-local name in the
  reserved namespace (§3c.4)." Concern: "One effect has two handle spellings in two files, so grep and LSP rename
  must follow the import line to link them."
- **Minimalism, Q3:** "A precedence rule that depends on whether the function declares the effect is a second rule
  that a reader must also know."
- **PLT, Q4:** "E0538 then keeps one meaning, \"this is not an effect\", and the unknown-module error keeps one
  meaning, \"this is not a module\"." PLT has no soundness objection, and asks that the E0538 message for an unknown
  qualifier names the missing module. The spec text does this.
- **Minimalism, Q5a and Q5b:** "Each special-case message adds a diagnostic path to maintain and to test." "No other
  name kind in the spec has this hint."

The seats set one condition on Q4: the E0538 message for an unknown qualifier uses the wording of the type slot and
says that an effect was expected (Web, Systems, DevOps, PLT in D2; Minimalism and DevOps as a fallback if B won).
DevOps also asked that the explanation of E0538 list all three causes. The catalog row and §4.3 state both.

### Reading Gaps

- The ruling text and the panel files differ in places. The panel files and the tally above decide.
- The spec fixes no case rule for module names or aliases. For that reason the first part of a dotted effect name
  resolves by import lookup, and case is a style rule only.
- Under that rule, `nosuch` in `! nosuch.Log` can also read as a parent effect (AI/ML in Phase D). The E0538 message
  for this case still names `nosuch` as an unknown module and says that an effect was expected, as all six seats
  asked.
- A stray qualifier on a handle with an alias (`o.log.log`) is a variant of Q5a (DevOps raised it as a concern). The
  panel did not vote on it. The spec text names `lib.log.log(...)` only.
- The panel did not fix the error code for a handle call that names a missing operation, or for the use of a module
  call that a handle hides (Q3). The spec says that the diagnostic gives the alias fix and names no code.
- The panel files do not fix the wording of the help lines. The spec gives the wording that the votes quote.
- The §4.3 text sits after the paragraph on a parent effect, not directly after "An effect name must exist". A
  parallel change inserts a paragraph in the second place, and this order avoids a merge conflict.
- Effect vtable C names that include the module are an implementation chore. They are not in the spec.
