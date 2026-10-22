[< All Decisions](../DECISIONS.md)

# Handler Clause Diagnostics — Design Rationale

A handler clause implements one operation of an effect. The spec said nothing about a clause whose header differs from the operation, a clause that names no operation, or two clauses for one operation.

Facts before the vote:

- A wrong clause header failed in different ways for different effects. For `FS`, the front end gave E0300 (TypeError) for a parameter, count or result mismatch. For an unknown operation it gave E0505. For user effects and for `IO.Print`, no Blink diagnostic fired and the C compiler failed on a generated file.
- Only `FS` and `IO.Read` were checked. A handler for `IO` print operations, `Time` and `Env` was not.
- A duplicate clause gave no diagnostic. The last clause won with no warning.
- §4.7 said: "A handler must implement all operations for the effect it covers [...] The compiler checks completeness." §4.7.1 says handlers may be partial. The two texts disagreed.
- §3.1 *Diagnostic Discipline* binds a new diagnostic: a repair must exist, the front end must see the rule, and diagnostics at one point must converge.
- The trait-contract rules already give each impl-versus-trait mismatch its own codes (E0900 to E0906). A separate ruling on keyword parameters in trait impls (E0914, E0915) awaits owner approval and is not on main.

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated in independent-proposal, debate, vote rounds. Quoted text is each panelist's own, verbatim. `[...]` marks a cut. Where a source line wrapped, the quote joins it with a space. Moderator text is plain and short.

Four questions went to a vote.

- **Q1** Code shape. S3: three codes (signature, unknown operation, duplicate). S5: five codes (arity, parameter type and result type split).
- **Q2** Names. N1: `HandlerClauseMismatch`, `HandlerClauseUnknownOp`, `DuplicateHandlerClause`. N2: `HandlerClauseMismatch`, `UnknownHandlerOp`, `DuplicateHandlerClause`. N3: `HandlerClauseMismatch`, `HandlerClauseUnknownOp`, `HandlerClauseDuplicate`.
- **Q3** The `*,` marker and keyword names in a clause. K1: the clause writes `*,` where the operation does, then the operation's keyword names in order. K2: `*,` as the operation, all names free. K3: no `*,`, names free. K4: `*,` optional, names free.
- **Q4** The missing-parameter fix. M1: machine-applicable when the name is not used in the body. M2: a suggestion only.

#### Phase A — Independent proposals

All six seats put the same shape first: one rule in §4.7 for user effects and every built-in effect, and three new codes. The seats differed in names and numbers. aiml wrote `HandlerClauseSignatureMismatch`, `HandlerClauseUnknownOp` and `DuplicateHandlerClause`. devops wrote `HandlerClauseMismatch`, `UnknownHandlerOperation` and `DuplicateHandlerClause`. min wrote `HandlerClauseSignature`, `UnknownHandlerOp` and `DuplicateHandlerClause`. plt wrote `UnknownHandlerOp` (E0548), `DuplicateHandlerClause` (E0549) and `HandlerClauseSignature` (E0550). sys wrote `HandlerClauseMismatch`, `HandlerClauseUnknownOp` and `HandlerClauseDuplicate`. web wrote `HandlerClauseMismatch`, `HandlerClauseUnknownOp` and `DuplicateHandlerClause`. Excerpts:

- **AI/ML:**

> What an agent needs from a code: **one code per repair**. The code is the cheapest token an agent reads; it keys the fix. When two codes take the same repair, the model must learn a split that buys it nothing.

- **DevOps:**

> the first need is one check, keyed on the declared ops of the handled effect node, that runs in typecheck for user effects and for every built-in (FS, IO, Time, Env) from the same table.

- **Minimalism:**

> **Few codes.** The trait-contract family spent seven codes (E0900-E0906) on one concept. That is the warning, not the template. Arity, parameter type and result type have one repair: "make the clause's signature equal the op's signature, which the message prints". One repair, one code.

- **PLT:**

> So the fix is a typing rule first. The codes follow from that rule.

- **Systems:**

> Any rule looser than "exact match" (a covariant result, a contravariant parameter, an implicit widening) needs a compiler-made thunk between the slot and the clause. That is a hidden extra call on every operation, plus a rule that users must learn for little gain. I want exact match.

- **Web:**

> My test for the slicing: one code per thing the user must *do*. A code is a search key ("blink E0548"), so it should land on one page with one fix.

**Phase A.5 (moderator dedupe).** Points all six seats raised, with no objection: one rule in §4.7; a clause matches the operation in count, order and type, and parameter names are free; types compare exactly; unknown operation leaves E0505; signature leaves E0300; a duplicate clause is an error; the new text replaces the completeness sentence; a missing clause stays legal. Second choices: five codes (sys, plt, aiml; devops wrote it down), one code (min), two codes (web). Keeping E0300 and E0505 with spec text only: opposed by all six.

#### Phase B — Debate (one round)

Every seat read the other five files. Five of six seats sent `STATUS: ready to vote`. sys sent `not ready` until the keyword-name question was settled.

**Machine-applicable header rewrite.** devops, Phase A:

> The `help:` is a suggestion, not machine-applicable: the body was written against the wrong types, so a header rewrite can move the error into the body.

devops, Phase B:

> The test for machine-applicable is: the edit, applied with no human, cannot make a new error or change what the program does. A header type rewrite fails that test. The body was written against the wrong type: `fn greet(name: Int) -> Str { int.to_str(name) }` rewritten to `name: Str` moves the error into the body.

aiml, sys, web and plt moved to this position. sys:

> devops is right, and my Phase A claim ("each repair is a local, machine-applicable edit") was too broad.

**A default on a clause parameter.** plt withdrew its "separate ticket" alternative:

> Reject it, under the signature code. My Phase A note sent this to another ticket. I withdraw that: the moderator's facts show the rule is short, and four seats want it here. The reason, in type terms: a default is not part of the function type (DECISIONS.md:71, 02_syntax.md:1271). A call goes through the op, never through the clause, so a clause default can never apply. It is dead text that can disagree with the op's default.

aiml withdrew its fallback:

> I drop my fallback ("may repeat the exact default"): it adds a second legal spelling, and two spellings for one meaning is the decision point my seat exists to remove.

**Keyword parameters.** sys raised the case that decided Q3:

> In the slot, keyword parameters are positional: `run(cmd, args, *, stdin: Str?, env: ChildEnv, cwd: Str?)` is a five-argument C function. Two of them, `stdin` and `cwd`, are both `Str?`. If the clause needs no `*` and keyword names are free, then this clause passes the type check:
>
> ```blink
> let mock = handler Process {
>     fn run(cmd: Str, args: List[Str], cwd: Str?, env: ChildEnv, stdin: Str?) -> Result[ProcessResult, ProcessError] {
>         Ok(ProcessResult { out: "", err_out: "cwd={cwd}", exit_code: 0 })
>     }
> }
> ```
>
> It compiles to the right slot type, and at run time `cwd` holds the caller's `stdin`. Equal types in another order give a silent swap that no type check can see. The names are the only thing that catches it.

**A duplicate with a mismatch.** web moved to the form that aiml, plt, sys, min and devops already held:

> With aiml: E0550 fires on the second clause only, and that clause gets no E0548 check. One error per clause is what a user wants to see. If the second clause is also wrong in its header, the user deletes it (the E0550 repair) and the E0548 is gone too.

**Numbers.** Five seats wrote E0548 for the signature, E0549 for the unknown operation and E0550 for the duplicate. plt withdrew its own order:

> I withdraw my numbering. I take the majority: E0548 signature, E0549 unknown op, E0550 duplicate.

#### Phase C — Silent vote

Moderator facts given with the ballot:

> 04_effects.md:1563-1574 (the Process mock) writes `fn run(cmd: Str, args: List[Str], stdin: Str?, env: ChildEnv, cwd: Str?)` with no `*`, for the op `run(cmd, args, *, stdin, env, cwd)`. [...] It does not say whether that fix is machine-applicable.

> The trait-impl keyword ruling (worktree `trait-impl-keyword-params`, DECISIONS row "Keyword parameters in trait impls") is written but waits for owner approval; it is not on main.

| Seat | Q1 | Q2 | Q3 | Q4 |
|---|---|---|---|---|
| aiml | S3 | N2 | K1 | M1 |
| devops | S3 | N3 | K1 | M1 |
| min | S3 | N1 | K1 | M2 **(dissent)** |
| plt | S3 | N3 | K1 | M1 |
| sys | S3 | N1 | K1 | M1 |
| web | S3 | N2 | K1 | M1 |
| **Result** | **S3 6-0** | **2-2-2** | **K1 6-0** | **M1 5-1** |

**Q1.** devops:

> One code per repair. A clause that differs from its op in two ways (say arity and result) gets one diagnostic whose first help, "write the op's header", clears every difference, so §3.1 rule 3 holds with no ordering rule.

web:

> TS reports a bad implementation of an interface member under one code (TS2416) and puts the detail in the message. Five codes would make a clause that is wrong in count and in type fire two or three errors at one point, all with the same fix.

**Q2.** The split was 2-2-2. min (N1):

> `Duplicate*` reads like its neighbors E0316 DuplicateField and E0543 DuplicateEffectOp, and the other two share a `HandlerClause` prefix, so one grep finds the family. Names are cheap; I will take whichever wins without complaint.

aiml (N2):

> A model learns the catalog's naming rule once and then predicts names: "not found by name" is `Unknown*` (`UnknownEffect` E0538), and a repeat is `Duplicate*` (`DuplicateField`, `DuplicateEffectOp`, `DuplicateSymbol`). N2 keeps both prefixes.

devops (N3):

> A shared `HandlerClause*` prefix puts the three rows next to each other in `blink explain` listings, LSP diagnostic filters and a plain `rg HandlerClause`, which is how `TraitContract*` already works.

Phase D re-voted Q2 only.

**Q3.** Every seat voted K1. Five of them moved from another option. min moved from K3:

> For a positional parameter the contract is its position, so names can be free. For a keyword parameter the contract is its *name*: the caller writes `cwd: "/x"`, never a position. If clause names are free, a clause that writes `cwd` and `stdin` (both `Str?`) in each other's place typechecks and swaps silently at run time, and no other check can catch it.

aiml moved from K2:

> Models are trained mostly on Python and Kotlin, where keyword arguments bind by name in any order, so the most likely AI mistake in a clause is to reorder keyword parameters and expect them to bind by name. Under K2, K3 and K4 that program type-checks and silently swaps two `Str?` values at run time. Under K1 it is a loud E0548.

plt moved from K4:

> Requiring the op's keyword names in the op's order makes the name the clause reads equal to the name the caller wrote, so that swap cannot happen. Positional names stay free, because positional binders are only alpha-renamable binders.

web moved from K4:

> That is the worst bug for my seat: no error, wrong behavior, and a "why is my mock getting the wrong value" question that takes an hour to find.

All six said the §4.4.8 Process mock changes: it gains `*,` before `stdin`.

**Q4.** plt (M1):

> Adding a parameter is safe to apply mechanically only when the new binder cannot change what any name in the body means. So the condition must be "the name does not occur free in the body". That covers a captured outer binding of the same name too, which the new parameter would shadow.

min **(dissent)** (M2):

> "Which parameter is missing" is a guess when two adjacent op parameters have the same type: a clause `fn two(a: Int) -> Int` for `two(a: Int, b: Int)` could be missing either one. A machine-applicable insert that guesses wrong compiles and binds the body's `a` to the caller's `b`. That is §3.1 rule 1's worst case and the same silent swap that decided Q3.

devops, who voted M1 and added the same condition on the place of the parameter:

> The fix should also be machine-applicable only when the place of the missing parameter is unique. With two parameters of one type, the tool cannot know which one the clause left out.

#### Phase D — Q2 only

Facts given by the moderator:

> Names in ERROR_CATALOG.md that start or end with "Unknown" or "Duplicate", and the trait-contract family:
> - `Unknown*` first: UnknownType E0507, UnknownEffect E0538, UnknownDiagnosticName E0842, UnknownDependencyField E1014, UnknownIntrinsic E1111, UnknownDerive E1112, UnknownEscape E1123.
> - "Unknown" inside the name: AuditRecordUnknownKey E0830, FfiOffsetUnknownStride E0838.
> - `Duplicate*` first: DuplicateField E0316, DuplicateKeywordArg E0528, DuplicateEffectOp E0543, DuplicateSymbol E1012, DuplicateModuleBinding E1016. No name ends in "Duplicate".
> - Shared prefix family: TraitContractMissingMethod E0900 ... TraitContractArgArity E0910 (nine codes; E0905 TraitContractExtraMethod is the trait family's "unknown method" case).

| Seat | Vote | Moved from |
|---|---|---|
| aiml | N3 **(dissent)** | N2 |
| devops | N2 | N3 |
| min | N2 | N1 |
| plt | N2 | N3 |
| sys | N2 | N1 |
| web | N2 | N2 |
| **Result** | **N2 5-1** | |

aiml **(dissent)**:

> devops and plt: the closest analogue to a handler clause is a trait impl method, and that family already uses one shared prefix for all its failure modes, including its "unknown" case (`TraitContractExtraMethod` E0905, not `UnknownTraitMethod`). I accept this argument; it beats mine. My `Unknown*`/`Duplicate*` rule holds for standalone codes. But for a family of codes on one judgment, the catalog's pattern is one prefix, and a model that maps "clause vs op" onto "impl vs trait" predicts `HandlerClause*` for all three names. N1, which mixes both conventions in one family of three, is the one option no rule predicts.

min, leaving N1:

> One naming rule for the whole catalog beats one per family: `Unknown*` for a name that resolves to nothing (E0507, E0538, seven codes) and `Duplicate*` for a repeat (five codes, no exception). N2 follows both and adds no exception; N1, my own vote, follows one and breaks the other, so it was the worst of the three, and aiml is right about that.

plt, leaving N3:

> Names should follow the most general rule the catalog already obeys, so `UnknownHandlerOp` and `DuplicateHandlerClause` sit beside `UnknownEffect` E0538 and `DuplicateEffectOp` E0543.

devops, leaving N3:

> My reason for a shared prefix was grouping, but the codes give that already: E0548–E0550 are one block of three numbers, and the catalog lists them as adjacent rows.

### Final Spec

```blink
effect Shell {
    fn run(cmd: Str, *, cwd: Str? = None, stdin: Str? = None) -> Result[Str, Str]
    fn read(path: Str) -> Str
    fn stop(code: Int) -> Never
}

fn broken_shell() -> Handler[Shell] {
    handler Shell {
        fn run(cmd: Str, *, stdin: Str?, cwd: Str?) -> Result[Str, Str] { Ok("") }   // error[E0548]
        fn read(path: Int) -> Str { "" }                                            // error[E0548]
        fn stop(code: Int = 1) -> Never { panic("stop") }                           // error[E0548]
        fn stop(code: Int) -> Never { panic("stop") }                               // error[E0550]
        fn remove(path: Str) -> Int { 0 }                                           // error[E0549]
    }
}
```

Locked points:

- One rule in §4.7 covers user effects and every built-in effect. A clause names one operation of the handled effect. Its parameters match the operation in count, order and type, and its result type equals the result type of the operation. Types compare by exact equality after alias expansion, with no variance. Names of positional parameters are free.
- K1: the clause writes `*,` where the operation does, then the keyword names of the operation in the operation's order. A missing or moved `*,`, or a different keyword name, is E0548. The §4.4.8 Process mock gains `*,`.
- A clause writes no default. A default applies at the call site only. A default on a clause parameter is E0548.
- A clause for a `-> Never` operation writes `-> Never`. A `-> Never` clause for an operation with another result type is E0548. The divergence rule stays in §4.4.3.
- A missing clause stays legal (§4.7.1). The completeness sentence in §4.7 is gone.
- E0548 `HandlerClauseMismatch`: arity, a parameter type, the result type, the `*,` marker, a keyword name or a default differs. The message and the JSON output name the part that differs. The `help:` prints the header of the operation as one line to copy.
- E0549 `UnknownHandlerOp`: the clause names no operation of the handled effect. The `note:` lists the operations. E0549 replaces E0505 for a clause.
- E0550 `DuplicateHandlerClause`: a second or later clause for one operation. It fires on the second and later clauses only, with a `note:` at the first. Only the first clause is checked for E0548. E0548 and E0549 never fire on one clause. Two clauses that name the same name, which is no operation, get E0549 each and no E0550.
- E0548 replaces E0300 for a clause.
- Machine-applicable fixes: delete a default; add, delete or move `*,` and order the keyword names as the operation does; rename a keyword parameter when the rename is one to one and the new name is free in the body (the fix also renames the uses); rename a clause to the suggested operation (E0549) when the clause already matches that operation and no other clause names it; add a missing parameter when its name does not occur free in the clause body and the place of the parameter is clear.
- Not machine-applicable: a header rewrite that changes a parameter type or the result type. The `help:` prints the header, and a code action the user picks can offer it. E0550 has no machine-applicable fix.

### Concerns

- E0548 must name the part of the header that differs, in the message and in the JSON output (sys, plt, web, aiml, min). sys: "The JSON output must name the part that differs, not leave it to the message text."
- K1 depends on the trait-impl keyword ruling, which awaits owner approval. If the owner changes that ruling, change both rules in one edit (plt, min, web, devops, sys). The §4.7 text does not say that the rule matches trait impls, because the trait-impl rule is not in the spec yet.
- The add-parameter test is "does not occur free in the body", not "is not used in the body". A use in a closure and a use of a captured outer name count (plt, devops, sys). devops: the check must run on resolved names, not on text.
- The add-parameter fix inserts the parameter at the position of the operation, after `*,` for a keyword parameter. A fix that appends at the end or gets `*,` wrong makes a new E0548 (web).
- An inserted keyword name that hides an outer name the body uses makes the fix a suggestion (aiml).
- min (Q4): the add-parameter fix must require that the missing parameter is unambiguous, or the fix guesses. The spec text requires a clear place.
- The E0548 row can grow into a catch-all. Each new header part must stay a label with its own message, not a new code and not a vague "signature differs" (min, plt). devops: the catalog row and `blink explain` must list each sub-message and say which one is machine-applicable.
- A search for `HandlerClause` finds only E0548. The E0548 catalog row and the §4.7 text must name E0549 and E0550 as sibling codes (devops, plt, sys).
- The spelling must be the same in the catalog, the diagnostic constants and the spec (sys, min, web).
- aiml (Phase D): a model may spell the duplicate code `HandlerClauseDuplicate`, because the other two names start with `HandlerClause` in the model's guess. The catalog row and `blink explain` should accept only `DuplicateHandlerClause`, and the spec paragraph should name all three codes together.
- aiml (Phase C): K1 adds one exception to "names are free". The §4.7 text states the exception and the reason in one sentence.

### Follow-ups

- Implement E0548 to E0550 in the front end for user effects and for every built-in effect. This replaces E0300 and E0505 on the clause check for `FS` and `IO.Read` and adds the check for the rest.
- An operation default that a call site omits is a separate question.
- Whether an operation can carry its own type parameters is a separate spec question. A clause header rule for type parameters would be a new label on E0548.

#### AI-first review

| Criterion | Result | Note |
|---|---|---|
| Learnability | Pass | One rule: copy the header of the operation, delete the defaults, rename only positional parameters. |
| Consistency | Pass | Names follow `Unknown*` and `Duplicate*` as in E0538 and E0543. Keyword names follow the trait-impl rule once it lands. |
| Generability | Pass | A model that copies the operation header gets a legal clause after it deletes the defaults. |
| Debuggability | Pass | Each fault gets a front-end error at the clause, not a C compiler error. The message names the part that differs. |
| Token efficiency | Pass | Three codes. One `help:` line holds the whole header. |

0 of 5 failed.
