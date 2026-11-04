[< All Decisions](../DECISIONS.md)

# Variant Names and the End of `@module` — Design Rationale

**Gap:** Two spec rules gave errors for programs that have one clear reading. E0518 made a struct and a variant of one name an error at every reach, also when the variant is in a private enum of another file, so a rename of a private item in one file changed whether another file compiled. `@module` let two files claim one module name, but the spec did not say what such a merge means. Two files of one `@module("pg")` gave `helper` to one file and hid it from the other. The spec also showed `main.shared()` in a form that did not work.

**Result:**

| Q | Question | Result | Tally |
|---|---|---|---|
| Q1 | E0518 Case 2: a variant with the name of its own enum | Stays: the declaration is an error | 5-1, Minimalism dissents |
| Q2 | The diagnostic for a remaining `@module` | `InvalidModuleAnnotation` (E1008); the annotation is removed syntax | 4-2, PLT and Minimalism dissent |
| Q3 | The duplicate pin key rule | Stays, with a same-file example | settled in round 1; no ballot |
| Q4 | A bare name that another file declares (E0504) | The error gets a help that names the file | 6-0 (Minimalism changed to A in Phase C) |

Points that all six seats accepted without a vote:

- The E0518 struct clause goes at every reach: same module, another module with a private or `pub` enum, a dependency, a prelude enum. The import-entry clause goes with it. E1016 still covers a type, value or import entry named `Some`, `None`, `Ok` or `Err`.
- A pattern resolves its variant by the type of the matched value. A bare `Lit { v: 1 }` in an expression is the struct. A bare `Click(3)` is E0554, with the help `Event.Click(3)`. A struct literal of the wrong type, where an enum with a variant of that name is expected, is a type error whose help writes `Hid.Lit { v: 1 }`. The help is machine-applicable only when the literal's field names are the fields of that variant; otherwise it is a suggestion.
- A pattern on a value whose type is not yet known: a brace head means a struct, and sets the type. A variant head has no enum to search, so the error says the type is not known, and the help annotates. The panel fixed this behavior and gave it no code; the spec reports it under `CannotInferType` (E0301), the row whose repair is an annotation.
- Two files are never one module. `@module` is removed, and the path alone names a module.
- `helper` must become `pub`; there is no third visibility level. The repair for `src/pg.bl` is `pub import pg.conn.{run}`, and `conn.bl` has `import pg.util.{helper}`.
- E1001 and "`@module` Resolution" are deleted. "Merges into pg" becomes module `pg.protocol`.
- A pin goes stale when a callee moves (the import line changes). It stays fresh when a callee body changes.
- A delete of `@module` is machine-applicable only when its argument equals the last segment of the path of the file.
- The struct clause goes from the compiler only after E0554 and E1016 are enforced. This is an order for the implementation, not text of the spec.

**What this replaces:**

- [Newtype: One-Field Struct](newtype.md), Follow-up Q2 (6-0): it widened E0518 to cover a variant with its own enum's name. That case stays as E0518. This ruling replaces the rest of the E0518 rule that the row *A type named like a variant* and the row *Struct-vs-variant collision reach* in DECISIONS.md describe: the struct clause, its reach (package and prelude) and the import-entry clause. Q1 of that decision (the newtype is a one-field struct) is not changed.
- [Qualified Variants in Expressions](qualified-variants.md), Q7 (6-0): it sent E0518 to "a follow-up". This is that follow-up. E0519 and the E1016 and W1011 narrowing of Q7 are not changed.
- The `@module` rows of DECISIONS.md and the E1008 and E1001 text of §10.1 are replaced. They stay in the table as history.

**Case 2 and its old reason (for the owner).** The old reason for Case 2 was the sentence "within one package, a name is never both a product type and a sum injection". With the struct clause gone, that sentence is false. `type Token { Token(Str), End }` has one reading at every site; `Token.Token("a")` is clear, and the panel agreed on this in Phase A. The spec keeps only this reason: *a sum type is never one of its own injections*. The practical reason the five seats gave for keeping the error is that a person who writes `type Errno { Errno(Int) }` wants a newtype, and the declaration error gives the one-field struct help once, on the line just written. That reason now survives in the help only, and the help prints only for one variant with one payload. Minimalism's dissent on Q1 rests on this (see *Dissents*). `type Shape { Circle(Circle) }` is legal: the variant `Shape.Circle` is an injection of `Shape`, and the struct `Circle` is a different type.

**Phase D did not run.** Q1 was 5-1 and Q4 was 6-0. Q2 was 4-2, and the two dissenting seats (PLT and Minimalism) endorsed a follow-up ticket for the `UnknownAnnotation` route once `UnknownAnnotation` has an emit site. The panel treated this as a soft consensus, so no Phase D vote was held.

**Order of work for the implementation (not spec text).** `lib/std/{fs,net,http,term}.bl` have no declarations and use `@module`; the removal takes the 3-step bootstrap dance. The struct clause goes after E0554 and E1016 are enforced. Case 2 and E1001 have no emit site today, so a sweep of the corpus comes first. A struct and a variant of one name must not share a C symbol; a test comes first.

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated in independent-proposal, debate and silent-ballot rounds. Each panelist's text below is a verbatim excerpt of the panelist's own reply. Ticket identifiers and scratch paths are removed.


#### Phase A — Independent proposals

Each panelist's text is a verbatim excerpt of the panelist's own reply; `…` marks a cut. Ticket identifiers and scratch paths are removed.

- **Systems:**

  > Summary: remove the struct clause of E0518 for every reach, keep Case 2, one file is one module, remove `@module`.
  >
  > …
  >
  > **Case 2 stays, as the only E0518 case.** A variant with the name of its enum is a check on one declaration, with no cross-module cost. Its reason is the help text: `type Errno { Errno(Int) }` is usually a newtype written by mistake. Measured C for a one-variant enum has `int32_t tag` beside the payload; a one-field struct has no tag. The help moves the user to the form with no extra cost. Compiler and semantics do not need the rule, and `Token.Token("ab")` runs today.
  >
  > …
  >
  > ## `@module` after this
  >
  > It goes. It can only restate the path or lie about it. Trace names lose the special case in `tr_module_name` (`dotted.replace(".", "_") == m`).
  >
  > Migration is the 3-step dance. It touches 4 std files (`fs`, `net`, `http`, `term`) and 8 test files. Their C keys change (`net` becomes the `std.net` key). I did not measure what depends on those keys. Tests that prove merging, such as the two-file E1016 row and the shared-module trace row, need an owner decision: rewrite them to the new rule, not delete them without asking.
  >
  > Fallback if the panel wants the name kept: `@module(x)` is legal only when `x` equals the path's dotted name, and it changes nothing. I do not recommend this. It is a line with no effect on the output.

- **Web/scripting:**

  > Short form: remove E0518's struct clause everywhere, keep Case 2. One file is one module, with no exceptions, and retire `@module`, because the path already names the module.
  >
  > …
  >
  > **Case 2 stays.** `type Errno { Errno(Int) }` is what a TS or Kotlin dev types when they want a newtype. Without the error, `Errno(3)` gives E0554 and the fix is `Errno.Errno(3)`, which teaches the wrong lesson. With it, they get the struct-newtype help at the declaration. It is a one-declaration check and it never crosses a file.
  >
  > …
  >
  > ## 5. What `@module` is for: nothing, so retire it
  >
  > Its stated main use is src/auth/auth.bl as `auth`, and that does not resolve (measured). `src/auth.bl` beside `src/auth/` already does the job. Everything else about it is a second way to spell a name.
  >
  > - The 5-minute rule: "your path is your module name." No exceptions to learn.
  > - The module-table ticket gets injective keys for free: the key is the path.
  > - The cost is small: `rg '^@module'` finds 4 files in src, lib and tests (lib/std term, http, fs, net), each one file per name. Not measured: whether C names change for them (a comment in `cg_reg.bl` ties mangling to `@module`). The sys seat should check. Follows the 3-step bootstrap dance.
  >
  > **Second choice:** `@module("x")` only checks that `x` equals the path's last segment; a mismatch is E1008. Noise, but better than merging.

- **PLT:**

  > Summary: retire E0518 in full. Keep one file = one module without exception. Remove `@module`, so the
  > map from path to module name is injective by construction and E1001 cannot occur.
  >
  > …
  >
  > **Case 2 goes too.** `type Token { Token(Str), End }` has one reading at each site: `Token` in a type
  > position, `Token.Token("x")` in an expression, `Token(s)` at type `Token` in a pattern. Haskell and
  > OCaml accept this form as normal. Measured: gen1 accepts it and prints `x`, and
  > tests/test_typecheck_payload_variant_is_not_a_value.bl has a row where a type named like its own
  > payload variant heads a static call. The spec may lead the compiler, so the absence of an ambiguity decides this, not the measurement. Its one real job is to steer a user toward a newtype. A
  > diagnostic can do that with no ban: bare `Errno(5)` gets the E0504/E0554 help "to wrap one value, use a
  > one-field struct". The E0518 code retires and is not used again.
  >
  > Tradeoff: `Red { x: 1 }` next to `Paint.Red { r: 1 }` reads less plainly; that is style, and the existing
  >
  > …
  >
  > **`@module`: remove it.** Its jobs after this ruling:
  >
  > - The "primary file" job: `src/pg.bl` plus `src/pg/util.bl` already works with no annotation (measured,
  >   prints `1 2`). `src/pg/pg.bl` with `@module("pg")` already fails `import pg` (ModuleNotFound).
  > - Entry file: `src/<package>.bl` is set by its path. E1008 only checks a claim the path already makes.
  > - Stdlib: `lib/std/fs.bl` has `@module("fs")`, but the qualifier defaults to the leaf name `fs` anyway.
  > - `resolve("auth")` in §10.1 lists two candidates. The annotation is the only source of the second.
  >
  > With no `@module`, name = f(path), f is injective, and the module table waiting on this ticket gets

- **DevOps/tooling:**

  > **Proposal: remove the struct clause at all reaches, and the import-entry clause. Keep Case 2.**
  >
  > …
  >
  > **Case 2 stays, as an error.** Honest reason: it is not an ambiguity; `Token.Token("a")` is clear. It catches a person who wants a newtype. Without it, `type Errno { Errno(Int) }` passes, then `Errno(3)` gives E0554 with help `Errno.Errno(3)`, a poor repair. E0518 gives the correct repair (a one-field struct) at the declaration, from that declaration alone.
  >
  > Cross-language: Rust and Swift allow a struct and a variant of one name, because variants are qualified.
  >
  > …
  >
  > ## What `@module` is for
  >
  > Nothing. Measured: `import auth.auth` for `src/auth/auth.bl` binds the qualifier `auth`, and the last-segment rule gives that with or without the annotation. On `src/pg.bl` it restates the path. Its stated main use, `import auth` finding `auth/auth.bl`, does not work. With it gone, the module name is a pure function of the path: the module table gets injective keys with no conflict check, and each tool knows a module without a file read. The stdlib files use it for short names and C prefixes: a compiler matter, not user syntax. Removal is a 3-step bootstrap dance. `test_module_annotation.bl` and `test_entry_module_mismatch.bl` become tests of the new error; any test deletion goes to the owner first.
  >
  > Tradeoff: no entry at `auth/auth.bl`. One location, one rule.

- **AI/ML:**

  > Summary: retire E0518 Case 1, keep Case 2. Two files may not share a module. Retire `@module`: the path alone names a module.
  >
  > …
  >
  > ### Case 2: keep, and implement
  >
  > `type Token { Token(Str), End }` stays E0518. It has no parse ambiguity. It has a learner reason: a model from Haskell writes `type Errno { Errno(Int) }` and then `Errno(5)`. The declaration error gives the one-field struct help at once, which is better than E0554 at each use. The panel already voted to remove this exemption (DECISIONS, "A type named like a variant"). E0518 then has one meaning: a sum type is never one of its own injections.
  >
  > …
  >
  > ### What `@module` is for: nothing, so remove it
  >
  > Measured: `src/auth/auth.bl` with `@module("auth")` alone gives ModuleNotFound, so its stated main use does not work. `src/auth.bl` and `src/auth/token.bl` give the same tree with no annotation. In lib/std, the 4 uses (`fs`, `net`, `http`, `term`) each repeat the leaf name that the qualifier already has.

- **Minimalism:**

  > Summary: remove rules. Delete E0518 Case 1 at every reach. Keep Case 2. Two files never share a module. Retire `@module`.
  >
  > …
  >
  > **Case 2 stays.** `type Token { Token(Str), End }` stays E0518. It has a different reason: it steers away from a newtype written as an enum. It won 6-0 on 2026-10-22 (decisions/newtype.md), after the closed list was already known, and I have no new fact. It is one sentence and one check. E0518 then means only that, so the catalog row gets shorter.
  >
  > …
  >
  > **5. `@module` is for nothing, so retire it.** Measured, its one effect is to rename the qualifier: `import pg.pg` then `pg.a()`, and `import pg.util` binds `pg`, not `util`, so a reader cannot trust the import line. On the entry file and on `lib/std/{fs,net,http,term}.bl` the name is what the path gives already (`src/m4.bl` with `@module("m4")` runs the same).
  >
  > What goes: the annotation row, E1008, E1001, the "four-way invariant" (now three-way), the audit hash note on `@module`, and the pin-key row wording "no `@module`" (now "a file outside `src/`").
  >
  > Module identity then needs no duplicate check: path to module is injective, which is what the module-table ticket wants.

#### Phase B — Round 1

- **Systems:**

  > Q1: A (keep Case 2). plt is correct that no ambiguity exists. The rule still has a cost reason: measured, a one-variant enum has `int32_t tag` beside the payload, and a one-field struct has no tag. decisions/newtype.md voted 6-0 on this, and plt brings no new fact. It needs an emit site.
  >
  > Q2: A (E1008). No new code: B gives one retired annotation a catalog row for no gain. C depends on `UnknownAnnotation`, which gen1 does not have. Fix `@mdule` as its own bug, not as a blocker. Machine-applicable delete: web's condition, only when the argument equals the path's module. If it differs, the delete changes the qualifier (`import pg.util` binds `pg` today, `util` after), so the importers need edits.
  >
  > Q3: A. Pin reads the parse tree with no typecheck, so plt's "E1016 now covers it" does not stop a pin. One file with two `fn connect` reaches the rule. If the writer finds min's `src/a/B.bl` `fn m` against `src/a.bl` `fn B.m` reachable, add it as a second example; it would be a two-file case that E1016 misses. I did not measure it.
  >
  > P0: no objection. I take the `pub import pg.conn.{run}` repair over my own shape; the two are equal in cost.
  >
  > P4: no objection to any item.
  >
  > Order of work: the struct clause goes only after E0554 and E1016 are enforced. Today a bare `Box { w: 5 }` still resolves to a variant, so removal before that gives a real ambiguity.
  >
  > Changes from Phase A, with measurements:
  >
  > 1. Correction. Phase A said "separate C names", but I had only run the program. I have now read the C. For `type Lit { A, B }` + `type Hid { Lit(Int), O }` in one module (legal today, prints `4 2`):
  >    - type: `blink_Lit`
  >    - tag: `blink_Hid_Lit_TAG`
  >    - union member: `b_Lit`
  >
  >    A dep variant gives `blink_dep_Shape_Lit_TAG`. A struct is `blink_Lit` with no other symbol of that name. No collision, so plt's precondition holds. Also measured: a struct `Hid_Lit` beside variant `Hid.Lit` prints `1 2`.
  >
  > 2. Retraction. Phase A's `import std.term as st` row (prints `8 7 false`) proves nothing about key collision. `lib/std/term.bl` declares no items.
  >
  > 3. New fact on the "not measured" row. `lib/std/{fs,net,http,term}.bl` have 0 declarations each, only `pub import`. So these four files emit no item symbols under a `@module` key, and their qualifier is the leaf name with or without it. Removal renames no function or type symbol from these files. I did not check header and guard names that use the key (`c_module_header_name`); the 3-step dance will show them.
  >
  > The ICE in `import term` + `import std.term` stays a ticket for the lead.
  >
  > Stable, ready to vote.

- **Web/scripting:**

  > # Web seat, Phase B round 1
  >
  > **Q1: A, keep Case 2.** plt is right that nothing is ambiguous. The reason is where the help lands. A declaration error gives the newtype fix once, on the line just written. plt's form gives a clean declaration, then an error at each `Errno(5)`, far from the cause. The rule won 6-0 on 2026-10-22, and plt brings no new fact. It has no emit site, so it needs a ticket.
  >
  > **Q2: A, E1008.** Users read the message and the help, not the code. B adds a catalog row for one annotation. C gives the same text but waits on `UnknownAnnotation`: `@mdule("x")` passes check today. Fix that bug anyway, but this ruling should not depend on it.
  >
  > **Q3: A, the rule stays, with the same-file example.** The hash reads the parse tree, and the pin section says a name error in an unrelated file does not stop a pin. So plt's E1016 point needs proof that pin sees it first. aiml could not measure this; the writer should run it. The rule costs one paragraph, and "pin refuses" is safer than "pin picks". Against C: min's own `src/a/B.bl` against `src/a.bl` `fn B.m` may be reachable, one more reason not to delete.
  >
  > **P0:** no objection.
  >
  > **P4:** no objection. I most want the note for `import pg` with only `src/pg/pg.bl` (`index.js` and `__init__.py` habit), and the `TypeMismatch` help for `fn f() -> Hid { Lit { v: 1 } }`.
  >
  > One change to sys's E0504 help. After a user deletes `@module`, nothing may load util.bl, and that is when they need the help. So the help may read sibling files on the error path only; a successful build never reads them. Show it only in the root package, as for other helps that edit a declaration.
  >
  > **Changes from Phase A:**
  > 1. Machine-applicable delete. I said "argument equals the path's module". Corrected: the argument equals the file's last path segment, so the qualifier does not change, and no other file claims that name (devops: a sibling may read a private item). aiml's "always" is wrong: on `src/pg/util.bl` the delete moves the qualifier from `pg` to `util` and breaks callers.
  > 2. My count of `@module` uses was low: 4 std files, plus 8 tests. My search matched only the start of a line, and the tests hold it in strings.
  > 3. My lambda side finding now sits with devops's defect 4. I support that diagnostic.
  >
  > Stable, ready to vote.

- **PLT:**

  > plt seat, Phase B round 1. I change all of Q1, Q2 and Q3.
  >
  > **Q1: A (keep Case 2). Changed from B.**
  > My Phase A test, "an error needs an ambiguity", was too strong. It is correct for Case 1, because Case 1 is non-local: a private edit in one file breaks another file. Case 2 reads one declaration, so scope and imports cannot change it, and it does no harm to modularity. decisions/newtype.md has it 6-0, with this seat voting for it, and I brought no new fact.
  > One correction to the old reason: the "bare in a pattern, qualified in an expression" asymmetry now applies to every user variant, so that does not justify Case 2. What remains: the form has no purpose, it costs `Token.Token`, and the help moves a user to the newtype form.
  > The catalog sentence "a name is never both a product type and a sum injection" is false after P0 and must go. Keep only "a sum type is never one of its own injections". Own-enum exemption text stays gone.
  >
  > **Q2: C (`UnknownAnnotation` with a fixed hint). Changed from A; A is my second choice.**
  > Once `@module` is removed it is a name not in the §11.1 table, and §11.1 rule 1 already allows a fixed hint for such a name. A keeps a catalog row for an annotation that does not exist. B adds a code with no job. Condition, as min says: gen1 must emit `UnknownAnnotation` first (`@mdule("x")` passes check today, and the spec already requires the error). Otherwise a module changes its name with no message.
  > Machine-applicable delete: web's limit, only when the argument equals the path's module. Otherwise the imports change.
  >
  > **Q3: A (the rule stays, with a same-file example). Changed from B.**
  > My claim was wrong. E1016 is a compile error, and pin reads the parse tree, so one file with two `fn connect` still reaches the refusal. My `test` example has the same flaw, and E0851 exists for it.
  > min's second case supports the rule: `src/a/B.bl` `fn m` and `src/a.bl` `fn B.m` both give `a.B.m` under the key table. So module names are injective, but item keys are not. I measured it: gen1 does not parse `fn B.m` today (`expected (, got .`), so this clash is reachable under the spec only. The writer may add it as a second example.
  >
  > **P0: no objection.** Order condition: the struct clause goes only with or after E0554 and E1016 are enforced. Today gen1 reads `Box { w: 5 }` as a variant, so removal first makes a real ambiguity.
  >
  > **P4: no objection.** Each help runs only after a site has failed and never gives a site a meaning. I support devops's unknown scrutinee rule: a paren or variant head needs a known type, and a brace head on an unknown type means a struct only. That keeps inference free of a search through variants. sys's sibling help is out of scope for dependency packages.
  >
  > Stable, ready to vote.

- **DevOps/tooling:**

  > **Q1: A (keep Case 2).** plt is right that there is no ambiguity. But plt's replacement help fires at a bare use only. A user who writes `Errno.Errno(3)` from the start never sees it. The declaration error fires once, at the cause, from one declaration. decisions/newtype.md is 6-0 from 2026-10-22, and I see no new fact.
  >
  > **Q2: A (E1008).** It has an emit site now, needs no other work, and the name stays true. Against B: a new code for one retired annotation adds a row and a number for no gain. Against C: it is the correct end state for `@mdule`, but it ties this ruling to a feature gen1 lacks. File `@mdule("x")` passing check as its own bug. Once `UnknownAnnotation` exists, E1008 can retire into it with no vote.
  >
  > **Change from Phase A (machine-applicable delete):** I take web's condition, the delete is machine-applicable only when the argument equals the path's module. It is better than mine, because one file can decide it, and because no importer changes then. Against aiml's "always": deleting `@module("pg")` from src/pg/util.bl renames the module, so importers break. A fix marked machine-applicable must not break another file. In the other case it is a suggestion.
  >
  > **Q3: A, plus min's case as a second example if the writer confirms it.** Pin reads the parse tree and runs no typecheck, so one file with two `fn connect` reaches pin although E1016 rejects the file at check. That alone answers C: the rule stays.
  >
  > Against B: two `test` names that decode to one text have the same status as `fn connect`, because the spec makes them E0851. They are no better an example. Note that gen1 passes `test "x\u{41}"` beside `test "xA"`: check says ok. The spec's escape list has `\u` for a control character only, so this probe may be a bad case; the writer checks.
  >
  > min's `a.B.m` is the one case from a program with no error: `src/a/B.bl` `fn m` against `src/a.bl` `fn B.m`. So "injective keys for free" holds for module keys, but not for pin keys. The writer must not say that pin keys are injective. Not measured: gen1 rejects `pub fn B.m()` ("expected (, got ."), though §2.12.3 shows that form. `blink audit pin` is also absent from gen1 ("file not found: pin"), as aiml saw.
  >
  > **P0: no objection.**
  >
  > **P4: no objection, two limits.**
  > - aiml's `Hid.Lit { v: 1 }` help: machine-applicable only when the literal's field names are the fields of that variant. Otherwise a suggestion.
  > - sys's E0504 help: only for a file of the same package, never a dependency's. A user cannot make a dependency's item `pub`. This keeps it away from the bad advice in my defect 5 (E1003 "mark the enum as `pub`").
  >
  > stable, ready to vote.

- **AI/ML:**

  > aiml, Phase B round 1. I read all six replies.
  >
  > **Q1: A, keep Case 2.** plt is correct that it has no ambiguity. The reason is the repair: `type Errno { Errno(Int) }` gets the one-field struct help at the declaration, from that declaration alone. plt's alternative puts the help at each bare `Errno(5)`, after a model has already generated the wrong shape, and `Errno.Errno(5)` also compiles, so that path can end in the wrong form. decisions/newtype.md was 6-0 two weeks ago, and I see no new fact.
  >
  > **Q2: A, E1008. I change from B.** A new code buys nothing: E1008 has no other job once the entry-file check goes, so the same row carries this message. C depends on a code that gen1 does not have, and old `@module` lines in training data deserve a searchable name.
  >
  > **Second change: I withdraw "delete this line" as always machine-applicable.** That was wrong. Deleting `@module("auth")` from src/auth/login.bl changes the qualifier from `auth` to `login`, and every importer breaks. I take web's condition: machine-applicable only when the argument equals the path's module. That also makes devops's condition unneeded in practice: a file with a private item that a sibling reads has an argument that differs from the path, or is the entry file, and I accept review of that edge by the writer.
  >
  > **Q3: A, the rule stays, with the same-file example.** `fn connect` twice in one file reaches pin, because pin works from the parse tree and E1016 runs later. So plt's reason against this example does not hold. Against C: the rule came from a panel vote and costs one sentence. Keep it whatever the answer on reachability. min's clash is real on paper by the key table: `src/a/B.bl` `fn m` and `src/a.bl` `fn B.m` both give `a.B.m`. This one is a valid program, so the writer may add it as a second example. Not measured: gen1 rejects `fn B.m()` with a parse error, and `blink audit` has no `pin` subcommand (it shows only `--ffi`, `--json`, `--baseline`). That is a correction to my Phase A, where I treated "file not found: pin" as unexplained.
  >
  > **P0: no objection, one precision.** "A pattern resolves by the matched type" needs devops's rule for an unknown type: a brace struct head sets the type (I measured `fn(x) { match x { Lit { v } => v } }` prints `3`), and a variant head gives devops's error, not today's ICE. Without this sentence a model cannot predict that case from the spec.
  >
  > **P4: no objection.** I support all of it. The TypeMismatch help and sys's E0504 sibling help have the highest value, because each lets a model fix the code in one turn.
  >
  > **Order:** the struct clause goes only after E1016 and E0554 are enforced, as the facts section says.
  >
  > Stable, ready to vote.

- **Minimalism:**

  > # min, Phase B round 1
  >
  > **Q1: B, retire Case 2. I change from Phase A, for two reasons.**
  > - My Phase A text was wrong. I wrote that Case 2 won "after the closed list was already known". The git log shows the newtype ruling at 12:35 and qualified-variants at 14:11 on 2026-10-22.
  > - The recorded reasons do not hold now. decisions/newtype.md says "No other variant has this asymmetry" (bare in a pattern, qualified in an expression). Now every user variant has it. It also says "the same overlap" as the struct clause, which we are deleting. I also called it "one check", but it has no emit site, so keeping it is new work.
  >
  > What remains is steering: `type Errno { Errno(Int) }` is usually a newtype by mistake. That needs a help, not a ban:
  > ```blink
  > type Errno { Errno(Int) }
  > fn main() { let e = Errno(3) }
  > ```
  > ```
  > error[UnqualifiedVariant]: variant `Errno` needs its enum
  >   help: write `Errno.Errno(3)`
  >   help: to wrap one value, use a one-field struct: `type Errno { code: Int }`
  > ```
  > The second help appears only for one variant with one payload, the same condition as today's text. The cost is style: `Token.Token("a")` is legal and reads badly. No site has two readings. E0518 retires. This reopens a 6-0 vote, and the new fact is the closed list. If the panel keeps Case 2, the owner must see that its reason is now the help only.
  >
  > **Q2: C, `UnknownAnnotation` with a fixed hint.** A and B both keep a code for a thing that no longer exists; C keeps none. The dependency is a bug we owe anyway: §11.1 requires `UnknownAnnotation`, and gen1 has no such name. Second choice A. Against B: one new code to say "removed".
  > Machine fix: web's condition, sharpened. The delete is machine-applicable only when the argument equals the last path segment, because the qualifier then does not change. aiml's "always" is wrong: measured, `import pg.util` with `@module("pg")` binds `pg`, so a delete breaks call sites.
  >
  > **Q3: A, change from Phase A.** My test was "delete unless reachable", and it is reachable. Pin reads the parse tree with no typecheck, so one file with two `fn connect` reaches it. E1016 stops only `check`. The example is the simplest and needs no decode rule. I could not measure pin: `blink audit pin K-1` under gen1 printed "file not found: pin".
  >
  > **P0:** no objection.
  >
  > **P4:** one objection: sys's E0504 help. To find `helper`, a failed lookup must scan sibling files, which is the directory scan this ruling removes. Drop it. No objection to the others, as implementation tickets; none of them should block the ruling.
  >
  > Stable, ready to vote.

#### Phase C — Silent ballots

The ballot asked Q1, Q2 and Q4 (Q3 and the P0 and P4 items were settled in round 1). Each reply below is the whole ballot text.

- **Systems:**

  > Q1: A
  > Q2: A
  > Q4: A
  > Reasoning:
  > Q1: The error moves a user from a tagged enum to a one-field struct at the declaration, where the fix is cheapest. Measured, the one-variant enum has `int32_t tag` beside the payload, and the struct has no tag. Under B the user can keep the extra tag, because `Errno.Errno(3)` compiles and the struct help is only a second line. The check reads one declaration, so it adds no cross-module cost.
  > Q2: E1008 has an emit site now, so the end state needs no new compiler work and no order dependency. C ties this ruling to a separate fix: `UnknownAnnotation` does not exist in gen1. That bug must get its own fix, but `@module` removal must not wait for it. The row costs one catalog line.
  > Q4: The cost falls on the error path only, and a successful build reads no extra file. This is a different thing from the directory scan that this ruling removes, because that scan set the meaning of a program and this one only words a message. The help gives the exact repair for the users this ruling breaks. Limit it to the root package, as web, devops and plt said.
  > Concern:
  > Q1: Case 2 has no emit site today, so the spec and gen1 stay apart until a ticket adds it, and any lib or test that uses the form breaks at that time.
  > Q2: E1008 stays as a row for a name that no longer exists, and a typo such as `@mdule("x")` still passes check unless its own bug gets fixed.
  > Q4: A help that scans siblings can name a stale or wrong file if two siblings declare `helper`, so it must list every match or name none, and it must not change the error code.
  > Objections: none

- **Web/scripting:**

  > Q1: A
  > Q2: A
  > Q4: A
  >
  > Reasoning:
  > - Q1: A TS or Kotlin dev writes `type Errno { Errno(Int) }` when they want a newtype, so that is the mistake to catch. Under A they get the one-field struct fix once, on the line they just wrote. Under B the declaration passes, and the first error comes later at a use, with `Errno.Errno(3)` listed as the first help. That is the wrong lesson to show first.
  > - Q2: Users read the message and the help, and both options can show the same text, so the code alone is not worth a dependency. A has an emit site now, so this ruling can land without waiting on another fix. C needs `UnknownAnnotation` in gen1 first. That bug should be fixed on its own ticket, whichever option wins.
  > - Q4: The user who has just deleted `@module` is the one who hits this error, and the bare `helper` gives no clue where it went. "It is in src/pg/util.bl, make it `pub`, add this import" fixes it in one read, and it is the question people would otherwise go and search for. min's objection is about a scan that changes what a program means. A scan on the error path cannot change the meaning of a program that compiles, and a successful build never does it.
  >
  > Concern:
  > - Q1: A dev who wants a real enum with a variant of its own name, such as `type Token { Token(Str), End }`, gets a help about one-value structs that does not fit, so the struct help must appear only for one variant with one payload.
  > - Q2: E1008's name `InvalidModuleAnnotation` will outlive the feature and read oddly once nobody writes `@module`, so the row may become dead weight that a later cleanup must retire.
  > - Q4: If the error path reads sibling files that do not parse, or several siblings define `helper`, the help can mislead, so it must skip a file that does not parse and must not pick one of two candidates as the only answer.
  >
  > Objections: none

- **PLT:**

  > Q1: A
  > Q2: C
  > Q4: A
  >
  > Reasoning:
  > Q1: The check reads one declaration, so scope and imports cannot change its result, and it has none of the non-locality that condemns the struct clause. The form has no semantic use: it gives `Token.Token` and nothing that a different variant name or a one-field struct does not. B moves the same help to each use site and leaves a declaration legal that has no purpose. Soundness does not force either option, and decisions/newtype.md already has this at 6-0.
  > Q2: After removal, `@module` is a name outside the §11.1 table, and one rule covers every such name, with the fixed hint that rule 1 already allows. A keeps a catalog row whose only trigger is an annotation that does not exist, which is a rule with an empty domain. The emit site is the only argument for A, and the spec already requires `UnknownAnnotation`, so that work is owed either way.
  > Q4: A help cannot change what a program means, so reading sibling files on the error path leaves name resolution a function of the import block. The directory scan that this ruling removes is one that decides meaning; min's objection treats the two as the same. The limit to the same package is needed, because a dependency's private layout is not the user's to edit.
  >
  > Concern:
  > Q1: The ballot says "and one payload", but the rule in sections/03_types.md and decisions/newtype.md covers any variant with its enum's name, so `type Unit { Unit }` and `type Token { Token(Str), End }` are also E0518; if the writer takes the narrow wording, `type Unit { Unit }` becomes legal by accident.
  > Q2: If the removal lands before gen1 emits `UnknownAnnotation`, a remaining `@module` is silently ignored and the module changes its name with no message, so the order must be a blocking dependency on the ticket.
  > Q4: The help's text now depends on the directory listing, so its output needs a defined order when two siblings declare `helper`, and a test that a successful build does not read those files.
  >
  > Objections: none to the settled or P4 items. I ask the writer to state Case 2 as "any variant with its enum's name", as noted under Q1.

- **DevOps/tooling:**

  > Q1: A
  > Q2: A
  > Q4: A
  >
  > Reasoning:
  > Q1: The declaration error fires once, at the cause, and needs one declaration. The help in B fires at a bare use only, so a user who writes `Errno.Errno(3)` from the start never sees the struct advice, and a model repeats the poor form. No new fact since the 6-0 vote in decisions/newtype.md.
  >
  > Q2: A dedicated code lets `blink fix`, the LSP code action and `--json` consumers key on this one migration, and not on the hint text of a general error. E1008 has an emit site now, so this ruling waits on nothing. `@mdule("x")` passing check is a real bug, but it gets its own ticket and must not hold this one. E1008 can retire into `UnknownAnnotation` after the migration, once that error exists.
  >
  > Q4: This is the one error a user with conn.bl and util.bl hits after the migration, so it is the most useful help in the ruling. Without it they get "undefined function `helper`" for a name they can see in the next file. The scan runs on the error path only, so a successful build reads no sibling and the rule "one file's names come from its imports" stays true. min's objection is about meaning, and a help line does not change meaning.
  >
  > Concern:
  > Q1: Case 2 has no emit site today, so the fix can turn code in the corpus or in user trees that compiles now into errors, and it needs a sweep first.
  > Q2: The E1008 row can stay forever if no ticket retires it, which leaves a code for an annotation that no longer exists.
  > Q4: An LSP can cache this help for conn.bl and show it after util.bl changes, so the help must be recomputed when a sibling changes, and with two siblings that declare `helper` it must list both and not pick one.
  >
  > Objections: none

- **AI/ML:**

  > Q1: A
  > Q2: A
  > Q4: A
  >
  > Reasoning:
  > - Q1: The error fires when a model writes the wrong shape, and it names the correct shape from one declaration. Under B the declaration compiles and a first help offers `Errno.Errno(3)`, which also compiles, so a model takes the first repair and keeps the stutter. A rule that fires once at the declaration is also simple to learn from the spec.
  > - Q2: `@module` is in existing code and training data, and a name of its own says what happened and is searchable. C has the same hint, but it makes the fix depend on first building `UnknownAnnotation`, which gen1 does not have. That missing check is a real bug, but it needs its own ticket and should not hold this ruling. With A, E1008 has one job, and its row can say so.
  > - Q4: A model from Go or from the old spec example will write a bare `helper`, and this help gives the exact file and both edits in one turn. Without it, the model must search the directory, so the scan moves from the compiler to the model at a higher token cost. A scan on the error path does not break the ruling: a successful build never reads siblings, so a module's meaning still comes from its own file and imports.
  >
  > Concern:
  > - Q1: A model may still read Case 2 as an ambiguity rule, and may then expect `type Shape { Circle(Circle) }` to be an error too, so the spec text must state the reason and show that example as legal.
  > - Q2: A later reader sees a catalog row for an annotation that does not exist, so the row must say it is there for removed syntax, or it reads as a live feature.
  > - Q4: The help can name the wrong file when two siblings declare `helper`, so it must list all of them or none, in a fixed order.
  >
  > Objections: none. I support devops's limit on the machine-applicable `Hid.Lit { v: 1 }` help.

- **Minimalism:**

  > Q1: B
  > Q2: C
  > Q4: A
  >
  > Reasoning:
  > Q1: With Case 1 gone, no site has two readings, and the recorded asymmetry reason now applies to every user variant. What remains is steering, and steering is the job of a help, not of a ban. Case 2 also has no emit site, so keeping it is new work and leaves a code with one job. devops is right that a user who writes `Errno.Errno(3)` from the start never sees my help; I accept that, because the result is legal, correct code with poor style.
  > Q2: After removal, `@module` is a name not in the §11.1 table, and rule 1 already gives such a name `UnknownAnnotation` with a fixed hint. C needs no carve-out and leaves no code behind. A works today, but it keeps a catalog row for an annotation that no longer exists. The gen1 gap is a bug we owe in any case.
  > Q4: I change to A. My objection was the directory scan, and web's limit answers it: the help reads sibling files on the error path only, so a successful build never reads them and no site changes its meaning. A help adds no language surface, and every user who migrates from `@module` hits this exact error.
  >
  > Concern:
  > Q1 (A expected): the catalog and spec must state only the reason that holds now ("a sum type is never one of its own injections"), and the rows in tests/test_typecheck_payload_variant_is_not_a_value.bl that declare `type Errno { Errno(Int) }` must be rewritten when the emit site lands.
  > Q2 (A expected): §11.1 rule 1 then needs an explicit exception for `@module`, as `@effects` has, or the spec gives two codes for one name; retire E1008 into `UnknownAnnotation` once gen1 emits it.
  > Q4 (A expected): the scan must add no diagnostic of its own when a sibling file fails to read or parse, and must list two matches in a fixed order, or the error output changes with the state of the directory.
  >
  > Objections: none

#### Dissents

**Minimalism, Q1 and Q2** (from the ballot):

> Q1: With Case 1 gone, no site has two readings, and the recorded asymmetry reason now applies to every user variant. What remains is steering, and steering is the job of a help, not of a ban. Case 2 also has no emit site, so keeping it is new work and leaves a code with one job. devops is right that a user who writes `Errno.Errno(3)` from the start never sees my help; I accept that, because the result is legal, correct code with poor style.
> Q2: After removal, `@module` is a name not in the §11.1 table, and rule 1 already gives such a name `UnknownAnnotation` with a fixed hint. C needs no carve-out and leaves no code behind. A works today, but it keeps a catalog row for an annotation that no longer exists. The gen1 gap is a bug we owe in any case.

**PLT, Q2** (from the ballot):

> Q2: After removal, `@module` is a name outside the §11.1 table, and one rule covers every such name, with the fixed hint that rule 1 already allows. A keeps a catalog row whose only trigger is an annotation that does not exist, which is a rule with an empty domain. The emit site is the only argument for A, and the spec already requires `UnknownAnnotation`, so that work is owed either way.

#### Concerns and where each is met

- Minimalism, Q1: the spec states only the reason that holds now, "a sum type is never one of its own injections" (§3, *Name collisions*). The rows of the payload-variant test that declare `type Errno { Errno(Int) }` are an implementation matter, and go to the implementation ticket.
- Minimalism, Q2: §11.1 rule 1 now names `@module` as an exception, as it does for `@effects`, so one name never has two codes.
- PLT, Q2: a follow-up may move `@module` to `UnknownAnnotation` once that diagnostic has an emit site. The order of work (the removal must not land before a remaining `@module` gets an error) is an implementation matter and goes to the implementation ticket.
- DevOps/tooling, Q1: a person who writes `Errno.Errno(3)` from the start never sees the one-field struct help. The panel accepted this; the help is a guide, not a rule.
- DevOps/tooling, Q4: the sibling help adds no diagnostic and no code, runs on the error path only, lists every match in a fixed order and skips a file that does not parse (§6.3.5 *A name that another file declares*).
- Web/scripting, Q1: the one-field struct help prints only for one variant with one payload (§3, *Name collisions*; the E0518 row).
- AI/ML, Q1: the spec shows `type Shape { Circle(Circle) }` as legal and gives the reason.
- AI/ML, Web/scripting, Systems, DevOps/tooling, Q2: the E1008 row says it is for removed syntax. A later cleanup may retire it. A machine-applicable delete applies only when the argument equals the last segment of the file path.
- Systems, DevOps/tooling, Q1: Case 2 and E1001 have no emit site today. A sweep of the corpus and of user trees before the emit site lands goes to the implementation ticket.
- Systems, Q2: a typo such as `@mdule("x")` is not covered by E1008. This is the open `UnknownAnnotation` gap, and goes to the follow-up ticket.
- Systems, Web/scripting, AI/ML, DevOps/tooling, Q4: the help lists every match in a fixed order or none, skips a file that does not parse, adds no code, and is recomputed by a tool (such as the language server) when a sibling changes.
