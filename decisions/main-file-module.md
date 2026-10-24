[< All Decisions](../DECISIONS.md)

# The File That Declares `fn main` Is an Ordinary Module — Design Rationale

§10.1 showed `src/main.bl  # module: main (entry point)` in its example tree, while §10.5 *Package Entry Resolution*
and §2 W0705 name the package entry `src/<name>.bl`. The spec did not say which module name a file that declares
`fn main` has when it is not `src/<name>.bl`, and it did not say what `main.x` means in a sibling that imports that
file. The compiler gave the file given to `blink build`/`blink run` an internal key, not a path-derived name. So in a
sibling, `import main` then `main.secret()` found the private `fn main` and reported `PrivateItemAccess` on `main`,
and E1006 for a name of that module left out its "or use qualified access" clause.

## Summary

| Q | Question | Result | Vote |
|---|---|---|---|
| Q1 | The file that declares `fn main` | A: an ordinary module. Its name comes from its path under `src/` or `@module`; the file given to `blink build`/`blink run` keeps it. A sibling imports it selectively and by qualifier. In a sibling, `main` binds only the qualifier. E1012 covers a sibling that declares its own `fn main` and imports `main`. E1006 keeps its qualified-access clause | 6-0 |
| Q2 | The §10.1 example tree | A: `src/myapp.bl  # module: myapp (package entry)`; the tree does not show `main.bl` | 6-0 |
| Q3 | A file outside `src/` | A: no module name; no file can import it; diagnostics name it by path; `ModuleNotFound` gets the help "files outside `src/` are not modules; move the file under `src/`" | 6-0 |
| Q4 | "One file is one module" | A: one sentence in §10.1 next to the path rule; no sentence on internal keys | 5-1 (DevOps dissent: B) |
| Q5 | `main.x` inside the file that declares `fn main` | A: no spec sentence; existing scope rules decide it | 6-0 in Phase D after 4-2 in Phase C |

Out of scope: a module that imports itself (`import auth` inside `auth.bl`). All six seats asked in Phase D for a
separate ticket on it; one exists. This decision writes no rule on it.

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated in
independent-proposal, debate, vote rounds. Phase A is excerpted from each panelist's own text. Phases B, C and D
are quoted in full from each panelist's file, without its heading line.

#### Phase A — Independent proposals

All six seats put first the same proposal: the file that declares `fn main` is an ordinary module. Five listed
"forbid importing the entry file" (the Go rule) only to oppose it; web called it an "acceptable fallback".

- **Systems** (`A/sys.md`):

> ## sys-1 (preferred): the root file keeps its path name; no special case

> **Rule.** Being the build root changes nothing about a file's module name. The name comes from §10.1 as for any file:

> A sibling imports the root file like any other module, selectively or by qualifier. The root file and the imported file are **one module with one instance**: one copy of each module-level `let mut`, one set of symbols. This is the line I care most about. Python runs a script as `__main__` and, when a sibling imports it by name, loads it a second time with a second copy of every global. Blink must not do that. The spec says so in one sentence.

> **`main.x` when `fn main` exists.** No conflict exists, and no tie-break rule is needed. In `helper.bl`, the only binding named `main` is the qualifier. The private `fn main` of module `main` is not in `helper`'s scope: it is not imported and it is private (§10.2). Today's PrivateItemAccess on `main` is a resolver bug: it looks up a bare name in another module.

> ## sys-2 (fallback): forbid importing the root file

> That last point is the worst: the same tree type-checks or not depending on the command line. I vote sys-1.

- **Web/Scripting** (`A/web.md`):

> ## web-1 (preferred): the entry file is an ordinary module. Its name comes from its path, like every other file.

> Rule: "The module name is derived from the file path relative to `src/`" applies to the file that holds `fn main` with no exception. `src/myapp.bl` is module `myapp`. `src/main.bl` is module `main`. `src/tools/gen.bl` is module `tools.gen`. Which file you pass to `blink build`/`blink run` does not change its name. The internal `__main__` key is a compiler detail. The spec does not mention it, and every import path that names the file resolves to that same key, so the file has one identity.

> A file outside `src/` (a script, or a file under `examples/`) takes its file stem as its name. Other files cannot import it, so the name shows only in diagnostics.

> Spec edit: change the §10.1 tree to `src/myapp.bl  # module: myapp (entry point)` with `blink.toml` `name = "myapp"`, so it agrees with §10.5's four-way invariant and §2 W0705. The example teaches the rule a reader will copy, so it must be the right one.

> ## web-2 (acceptable fallback): forbid imports of the file that holds `fn main` (Go rule)

> Go users know this rule, and its error tells you what to do. But it removes `import main.{secret}`, which works today, and it adds an exception to "a file is a module". I vote web-1 over web-2. I oppose "do nothing": a qualifier that silently binds to a fn gives the worst error a user can see.

- **PLT** (`A/plt.md`):

> ## plt-1 (recommended): `fn main` does not change a module's name or identity

> **Rule.** A module's name comes from its path under `src/` (§10.1), and from nothing else. Holding `fn main`, or being the file given to `blink build`/`blink run`, does not rename the module.

> **Identity.** A module has one identity. Under `blink run src/main.bl`, a sibling's `import main` names the same module: one copy of its module-level `let`s, one set of types. The internal `__main__` key must never reach a diagnostic. This is the soundness point: two identities would make two nominal types from one `type T` declaration (Python's `__main__.T` vs `foo.T`).

> **What `main.x` means.** Scope decides it; there is no ambiguity. In `worker.bl`, `main` binds only the qualifier; the private `fn main` is in module `main`'s scope, not `worker`'s. So `main.secret()` is qualified access. Today's compiler finds `fn main` across a module boundary: a scope bug, not a spec question. Inside `main.bl`, `main` is the fn, so `main.secret()` there is a field access on a fn value and an error.

> **Spec text to align.** §10.1's tree is correct about the name (`main.bl` is module `main`) but wrong to call it "the entry point": §10.5 and §2 W0705 define the package entry as `src/<name>.bl`. Change the comment to `main.bl  # module: main`, and add `myapp.bl  # module: myapp (package entry)`.

> ## plt-2 (fallback, oppose): forbid importing the file given on the command line

> Sound but not compositional: legality would depend on the CLI argument, not the source. One tree would pass under `blink run src/other.bl` and fail under `blink run src/main.bl`. Meaning must not depend on invocation.

- **DevOps/Tooling** (`A/devops.md`):

> ## devops-1 (recommend): the entry file is an ordinary module. Its name comes from its path. It has no special key.

> 2. One file is one module instance. If the root file is also imported by a sibling, both paths reach the same module: one set of module-level `let` values, one set of types. The spec must say this in words.

> 4. A file outside any `src/` (a script) has the file stem as its display name in diagnostics. No other file can import it, because it has no package.

> - LSP: go-to-definition, find-references, and rename work from one table, keyed by module name. An internal `__main__` key that only the root file has means the LSP sees a different module graph than `blink build` sees, depending on which file you ran. That gives wrong hovers and missed references.
> - Diagnostics: no message can show `__main__` to a user. Every message names a module that the user can type in an `import`.

> ## devops-2 (oppose, listed for the record): forbid importing the file that holds `fn main`

> Go does this (`package main` cannot be imported). It removes the question but adds an error code, breaks the legal intra-package cycle, and forces users to move shared items into a third file only to satisfy the tool.

- **AI/ML** (`A/aiml.md`):

> ## aiml-1 (recommended): the entry file is an ordinary module. No special case.

> **Rule.** The file that holds `fn main` gets its module name the same way as every other file: from its path relative to `src/` (§10.1), with `@module` as usual. Holding `fn main`, or being the root given to `blink build`/`blink run`, changes nothing.

> - `import script` for a file outside `src/`: UnresolvedModule, with a note: "files outside `src/` are not modules; move the file under `src/`".

> **Tradeoffs (my domain).** Zero new decision points and zero new tokens. A model that learned "path = module name" from §10.1 gets the entry file right with no extra fact. Each special case (a `__main__` name, a reserved qualifier, a ban) is one more fact a model must recall, and the ticket shows the cost: the special internal key is what broke `main.x`. One name per file also means a module never has two identities.

> ## aiml-3 (reject): a reserved qualifier (`__main__`, `entry`, `crate`)

> A second name for one module. More tokens, one more decision ("which name do I write?"), and it repeats Python's dual-identity trap.

- **Minimalism** (`A/min.md`):

> ## min-1 (recommended): the entry file is an ordinary module. No special name, no new rule.

> The file that holds `fn main` gets its module name the same way as every other file: from its path relative to `src/` (§10.1), or from `@module`. `fn main` makes a package an application (§2 W0705). It does not change the module name.

> **What `main.x` means.** In `helper.bl`, the name `main` is bound only by the import, so it is the qualifier. `fn main` is an item *inside* module `main`: its qualified name is `main.main`, and it is private like any other fn (§10.2). In `main.bl` itself, `main` is the fn, and `main.x` is member access on a fn value, the same as in any module that declares a fn.

> **Tradeoffs.** Adds zero syntax, zero names, zero diagnostics. It removes one special case from the compiler (the root-file key in name resolution). Cost: `src/main.bl` remains a legal non-entry module name, so a package can have both `myapp.bl` and `main.bl`. That is harmless, and forbidding it would be a new rule.

> ## min-2 (rejected): forbid importing the entry file

> Go does this: `package main` cannot be imported. But it adds a new error, it contradicts "intra-package cycles are allowed" (§10.5), and the import already works for the selective form. Only add a rule when a real bug needs it, and nobody has shown one.

##### Phase A options (after dedupe)

- **Option 1:** the file with `fn main` is an ordinary module (first choice of all six).
- **Option 2:** forbid importing the file with `fn main` (the Go rule).
- Variations inside Option 1, flagged for debate: V1 the §10.1 example tree; V2 a file outside `src/`; V3 write
  "one file is one module" into the spec; V4 `main.x` inside the file that declares `fn main`.

#### Phase B — Debate, round 1

One round. All six seats ended `STABLE: yes`. Web withdrew Option 2 as a fallback; sys and devops moved V2 to
"no module name"; aiml conceded V3; plt moved V1 to (a).

- **Systems** (`B1/sys.md`):

> **Option 1, support. Option 2, oppose.** No change from Phase A. plt states my main objection to Option 2 well: legality would depend on the file passed to `blink run`, not on the source. A build tool must be able to compile a module once and reuse the object for each root. A rule that changes per root breaks that.
>
> **V1: (a), and I accept (b).** Both fix the real defect, which is that "entry point" sits on the wrong file. (b) shows more: `main.bl` is a legal ordinary module next to the entry. I take (b) if plt and aiml want it. The words "package entry" must go on `myapp.bl` in both.
>
> **V2: (a), changed from Phase A.** A file outside `src/` has no module name. I proposed the file stem for diagnostics, but a diagnostic can name the file path, which is more exact than a stem. A stem name that no import can use is a fact with no use. aiml's note on the unresolved-module error ("files outside `src/` are not modules; move the file under `src/`") is good; I support it.
>
> **V3: yes, one sentence in §10.1, required.** Proposed text: "A file is one module. When a file is the root of a build and another file imports it, both name the same module: one copy of each module-level `let`, one declaration of each type." Without this sentence, an implementation that compiles the root twice (once as the root, once as an import) conforms to the spec. It would give two copies of every `let mut` and two nominal types from one `type T`. That is Python's `__main__` bug. The compiler already uses a separate internal key for the root, so this is not a theory. Keep the key out of the spec; state only the identity.
>
> **V4: no sentence needed.** Inside `main.bl`, `main` is the fn and `main.x` is member access on a fn value, by the rules that cover every module. plt and min agree on the result. A special note would suggest that a special case exists.
>
> STABLE: yes

- **Web/Scripting** (`B1/web.md`):

> **Option 1: support. Option 2: now oppose.** I called web-2 an acceptable fallback in Phase A. I withdraw that. plt-2 shows the flaw: if the ban keys on the file given on the command line, the same tree compiles under `blink run src/other.bl` and fails under `blink run src/main.bl`. A JS/Python dev would read that as a flaky build. If the ban keys on "declares `fn main`", it contradicts §10.5's intra-package cycles and breaks `import main.{secret}`, which works today. Both forms add an exception for no gain.
>
> **V1 (example tree): (a), and I accept (b).** The tree is the first thing a reader copies. It should show the one entry convention from §10.5 and §2: `src/myapp.bl  # module: myapp (package entry)`. plt's (b) also lists `main.bl  # module: main` to show that `main.bl` is not special. That teaches the right thing too, but it puts a `main.bl` next to the real entry and new users will ask which one runs. I prefer (a). I would vote for either over the current text.
>
> **V2 (file outside `src/`): change to (a).** I proposed "file stem, shown only in diagnostics". On reflection that is a name nobody can use, and a name you cannot use makes people try to use it. "No module name; no file can import it" is shorter and more honest. Diagnostics can name the file path. I support aiml's note on the unresolved-module error ("files outside `src/` are not modules; move the file under `src/`"). That is the error a Python dev will hit when they try `import utils` from a script.
>
> **V3 (one file, one module): yes, one sentence in §10.1.** For example: "The file that declares `fn main` takes its module name by the same rule as every other file. An import of that file names the same module: one copy of each module-level `let`, one set of types." The Python double-load trap is common enough to rule out in plain words.
>
> **V4 (`main.x` inside the file with `fn main`): no sentence needed.** Scope decides it. In that file `main` is the fn, and `.x` on a fn value fails the same way as for any fn. A special sentence would suggest that `main` is special, which is the opposite of Option 1.
>
> STABLE: yes

- **PLT** (`B1/plt.md`):

> **Option 1 vs 2.** Option 1. Six of six agree, and the rule is the one that composes: a module's name is a function of its path, never of the command line. Option 2 makes legality depend on invocation; I oppose it.
>
> **V1 (example tree).** I move to (a). (b) was meant only to avoid deleting `main.bl` from the tree; (a) teaches one entry rule in one line, and that matters more. `src/main.bl` stays legal as an ordinary module; the rule needs no example to say so.
>
> **V2 (file outside `src/`).** (a), with one condition for (b). Such a file is not a module of any package, so it has no module name; that keeps the set of module names equal to the set of importable paths. If the compiler needs a label, the diagnostic should show the file path (`script.bl`), not "module `script`". A message that says "module `script`" invites `import script`, which can never resolve. If the panel picks (b), I ask the text to say the stem is a display label, not a module name.
>
> **V3 (one file, one module).** Yes, a sentence is needed; it is the soundness fact of this ticket. Without it, a conforming compiler may load the root twice and get two nominal types from one `type T`. Place it in §10.1 next to the path rule: "A file is one module, however the build reaches it. The file given to `blink build` or `blink run` and an import of that file name the same module: one copy of each module-level binding, one set of types."
>
> **V4 (`main.x` inside the file with `fn main`).** min and I agree on the result. I would state the general rule, not a `main` rule: "A module does not bind its own name as a qualifier." That covers `main.x` in `main.bl` (here `main` is the fn, so `main.x` is member access on a fn value and fails as any such access does) and `auth.x` inside `auth.bl` alike. One sentence, no special case. If the panel thinks §10.6 scope rules already imply it, I accept leaving it out.
>
> No other change from Phase A.
>
> STABLE: yes

- **DevOps/Tooling** (`B1/devops.md`):

> **Option 1, yes. Option 2, no.** All six seats agree on Option 1. plt and sys make the strongest case against Option 2: it makes a file legal or illegal depending on the command line. Then `blink check`, the LSP, and `blink build` disagree about one tree, because the LSP has no "root file". That alone kills it for tooling.
>
> **V1: (a), and I accept (b).** (a) shows readers the one entry convention that §10.5 and §2 require, and readers copy example trees. (b) is also correct and shows that `main.bl` is not special. I can vote for either. The rule is what counts: the tree must not label `main.bl` as the entry point.
>
> **V2: I change to (a).** A script has no module name. My concern was only what a diagnostic prints. The answer is the file path (`script.bl:3:5`), which every diagnostic already prints. A message that would say "in module `X`" says "in `script.bl`". That is diagnostic wording, not a module name, so the spec needs no stem rule. I support aiml's note on the unresolved-module error ("files outside `src/` are not modules").
>
> **V3: yes, one sentence in §10.1, next to the path rule.** "A file given to `blink build` or `blink run` is the same module as an import of that file: one name, one copy of each module-level `let`, one set of types." Add: "No diagnostic shows an internal module key." The ticket is exactly that leak, so the spec must forbid it.
>
> **V4: no new rule.** In `main.bl`, `main` is the fn, and `main.x` is member access on a fn value. That uses the existing error. I ask for one help line, as diagnostic wording only: when `x` is an item of the current module, add "help: `main` here is `fn main`; write `x`". This is a hint, not spec text, and it can go in the impl ticket.
>
> STABLE: yes

- **AI/ML** (`B1/aiml.md`):

> **Option 1, support. Option 2, oppose.** No change from Phase A. plt-2 and sys-2 add the strongest point against Option 2: legality would depend on which file the user passes to `blink run`. A model reads source, not the command line, so it cannot predict that error from the spec.
>
> **V1: (a).** The example tree is the text a model copies. If `src/main.bl` stays in it next to `myapp.bl`, a model will sometimes make `main.bl` the entry, and §10.5 says "no fallback". Show `src/myapp.bl  # module: myapp (package entry, §10.5)` and leave `main.bl` out. The new §10.1 sentence ("a file that declares `fn main` is an ordinary module") already covers `src/main.bl`. I can live with (b) if the majority wants it.
>
> **V2: (a).** A file outside `src/` has no module name. A stem name that only diagnostics show is a name no code can use; once the spec gives it, a model will try `import script`. The diagnostic can name the file by path, which says more than a stem. Keep my note on the unresolved-module error: "files outside `src/` are not modules; move the file under `src/`". If (b) wins, the spec must say the stem name is not importable, in the same sentence.
>
> **V3: yes, concede.** I left it out; the other five are right. Models trained on Python carry the `__main__` two-copy model. One sentence in §10.1, next to the ordinary-module sentence: "The root file and an import of it are one module: one copy of each module-level `let`, one set of types."
>
> **V4: yes, one clause.** plt and min say the same thing in different words: inside the file that declares `fn main`, `main` is that fn, like any module-level name, so `main.x` is member access on a fn value and the usual error follows. Add it as a clause on the ordinary-module sentence. No new rule; it closes the one question a reader will ask.
>
> STABLE: yes

- **Minimalism** (`B1/min.md`):

> **Option 1, support. Option 2, oppose.** plt's point settles it for me: under Option 2 the same tree checks or fails depending on which file you pass to `blink run`. A rule whose meaning depends on the command line is a new concept, not a subtraction. No change from Phase A.
>
> **V1: (a).** The example teaches the one entry convention §10.5 and §2 define. (b) adds a `main.bl` line whose only job is to say "this is not special". That invites the question it tries to answer. `src/main.bl` stays legal because the path rule covers it; the tree need not show it. I accept (b) if the panel wants it. It does no harm.
>
> **V2: (a).** (b) adds a "display name" that only diagnostics use, which is a second naming rule. Diagnostics already print the file path, and that is enough. aiml's help note on the unresolved-module error ("files outside `src/` are not modules") is fine as help text with no new code.
>
> **V3: yes, one sentence.** I concede it is needed. It is not a new rule, but the ticket exists because the compiler gave the root file a second key, and a Python reader will expect two copies. Join it with the naming sentence in §10.1, so it is one place, not two:
>
> > A file keeps its path-derived module name when it is the file given to `blink build` or `blink run`. It is one module: an import of it reaches the same module-level values and types.
>
> **V4: no sentence.** It follows from scope: in the file that declares `fn main`, `main` is the fn, and `main.x` is member access on a fn value. That is an error, as plt says. I wrote "as in any module", which means the same thing. Spec text for a case that existing rules decide is surface we must keep in sync for no gain.
>
> STABLE: yes

#### Phase C — Final vote

Ballot options:

- **Q1.** A: an ordinary module (name from path or `@module`; the root keeps it; a sibling imports it selectively
  and by qualifier; in a sibling `main` binds only the qualifier; E1012 for a sibling with its own `fn main`; E1006
  gets back its clause). B: forbid importing the file that declares `fn main` (Go rule).
- **Q2.** A: replace the tree line with `src/myapp.bl  # module: myapp (package entry)`; the tree does not show
  `main.bl`. B: keep `main.bl` with `# module: main` and add `myapp.bl  # module: myapp (package entry)`.
- **Q3.** A: no module name; no file can import it; diagnostics name it by path; the unresolved-module error gets
  the help "files outside `src/` are not modules; move the file under `src/`". B: the file stem, shown only in
  diagnostics; no file can import it.
- **Q4.** A: the one-module sentence only. B: that sentence plus "No diagnostic shows an internal module key."
- **Q5.** A: no spec sentence. B: "A module does not bind its own name as a qualifier." C: a clause on the
  ordinary-module sentence saying that inside that file `main` is the fn.

- **Q1: the file that declares `fn main`** (A, 6-0)
  - **Systems:** A — "One rule for every file means a module compiles to the same symbols whatever root the user passes, so the object cache and archive links can reuse it. B makes legality depend on the command line and breaks `import main.{secret}`, which works today. A adds no runtime cost and no codegen case." Concern: "The compiler keeps a separate internal key for the root file, and if any path still treats the root and its import as two modules, we get two copies of each `let mut` without a test to catch it."
  - **Web/Scripting:** A — "A JS or Python dev learns nothing new: the entry file is a file, its name is its path, and you import it like any other file. It fixes the ticket's bug (`main.secret()` resolving to `fn main`) by deleting a special case, not by adding one. The Go ban would make a build pass or fail depending on which file you run, or contradict §10.5's intra-package cycles." Concern: "The compiler's root-file key must truly merge with the path key, or users get Python's double-load bug (two copies of a module-level `let`) with no warning."
  - **PLT:** A — "A module's name must be a function of its path, never of the command line; that makes the meaning of a program independent of how it is invoked. Under A, `main.x` in a sibling needs no precedence rule, because the qualifier and the other module's private `fn main` never share a scope. Every case reduces to rules the spec already has (E1012, §10.2 privacy, qualified access)." Concern: "The compiler fix may keep the internal root key and alias it to `main`, which could still let the root and an import of it diverge in symbols or state."
  - **DevOps/Tooling:** A — "The LSP, `blink check`, and `blink build` must see one module graph for one tree. Option B makes importability depend on which file the user passes on the command line, and the LSP has no such file. A also uses only error codes we already have, and E1006 gets its full help text back." Concern: "The resolver must stop looking up a bare name inside the target module. If the fix covers only `main`, the same leak can appear for any qualifier that matches a private item of its own module."
  - **AI/ML:** A — "\"Path gives the module name\" is already in §10.1; A adds no fact a model must learn, so a model that read the spec once gets the entry file right. B makes legality depend on the command line, which a model reading source cannot see. A also keeps `import main.{secret}`, which works today." Concern: "The compiler keeps a special internal key for the root file, and a model sees two names for one module in some diagnostic or generated symbol."
  - **Minimalism:** A — "A adds no syntax, no name and no error code; it removes a special case (the root-file key) from name resolution. Every behavior it needs comes from rules the spec already has: the path rule, privacy, E1012, E1006. B adds an error and an exception to \"a file is a module\", and makes legality depend on the command line." Concern: "the compiler fix must give the root file the same key as an import of it, or we ship the Python two-copies bug that the spec now forbids."

- **Q2: the §10.1 example tree** (A, 6-0)
  - **Systems:** A — "The defect is the \"entry point\" label on the wrong file, and A fixes it with the least text. B is also correct, but showing `main.bl` in the canonical tree invites users to copy it as the entry." Concern: "Users who already have `src/main.bl` may read the new tree as saying that file is now wrong, when it is only an ordinary module."
  - **Web/Scripting:** A — "People copy the example tree first, so it must show the one entry convention that §10.5 and §2 define. A `main.bl` next to `myapp.bl` makes new users ask which one runs." Concern: "Users who come from Go or Rust will still create `src/main.bl` by habit and wonder why `import myapp` does not reach it, so the E1011/entry diagnostics must name the expected `src/<name>.bl` file."
  - **PLT:** A — "The example must teach the one entry rule that §10.5 and §2 W0705 state. A tree that shows `main.bl` beside the entry invites the reading that `main.bl` is special. `src/main.bl` stays legal as an ordinary module with no example needed." Concern: "A reader may now think `src/main.bl` is forbidden; one clause in prose would prevent that."
  - **DevOps/Tooling:** A — "Readers copy the example tree. The tree must show the one entry convention that §10.5 and §2 W0705 require, with no extra file to ask about." Concern: "With `main.bl` gone from the tree, a reader can think `src/main.bl` is forbidden. The new §10.1 sentence must make clear that any file, `main.bl` included, follows the path rule."
  - **AI/ML:** A — "The example tree is the text a model copies. With `main.bl` in the tree next to `myapp.bl`, a model will sometimes make `main.bl` the entry, and §10.5 has no fallback. The ordinary-module sentence already covers `src/main.bl`." Concern: "A reader who already has `src/main.bl` thinks the file is now illegal, because the tree no longer shows it."
  - **Minimalism:** A — "The example should teach the one entry convention that §10.5 and §2 define, and nothing else. A `main.bl` line that exists only to say \"not special\" adds a question to the example. The path rule already covers `src/main.bl`." Concern: "readers who learned `src/main.bl` from the old tree may think it is now forbidden; the new §10.1 sentence must make clear any file may hold `fn main`."

- **Q3: a file outside `src/`** (A, 6-0)
  - **Systems:** A — "A name that no import can use is a fact with no use; the file path is more exact in a diagnostic. The help text points the user to the one fix." Concern: "`tests/` and `examples/` files that import their package must still resolve against the package root (§10.5), and the help text must not fire for those valid imports."
  - **Web/Scripting:** A — "A name nobody can use only makes people try to use it. \"Not a module; move it under `src/`\" is the exact help a Python dev needs when `import utils` fails from a script." Concern: "Scripts that grow into small projects hit this wall at once, so the help text must say what to do (`blink init`, or move into `src/`), not only what is wrong."
  - **PLT:** A — "The set of module names should equal the set of importable paths. A display name that looks like a module name but can never resolve breaks that equality and invites `import script`. Naming the file by path is exact." Concern: "The help text must not fire for a misspelled module inside `src/`, where \"move the file under `src/`\" would mislead."
  - **DevOps/Tooling:** A — "Every diagnostic already prints the file path, so a script needs no invented name. The help line on the unresolved-module error tells the user the fix." Concern: "`tests/` and `examples/` files can still import from `src/` (§10.5 peers). The help text must not suggest that they cannot import, only that no file can import them."
  - **AI/ML:** A — "A name no code can use still invites `import script` from a model. The file path in a diagnostic says more than a stem. The help text tells the model the fix in one step." Concern: "Users of `examples/` want to share code between example files and find no way to do it."
  - **Minimalism:** A — "A file that no import can reach needs no name. Diagnostics already print the file path, so a stem \"display name\" would be a second naming rule with no user. The help text is a hint on an existing error, not new surface." Concern: "if a later feature (such as importing `tests/` helpers) needs these files to have names, we must revisit this rule instead of patching around it."

- **Q4: "one file is one module"** (A, 5-1, DevOps dissent)
  - **Systems:** A — "The identity sentence is the load-bearing rule: it forbids a conforming compiler from loading the root twice. \"Internal module key\" is an implementation term and does not belong in the spec; a diagnostic that names a module already must use its §10.1 name." Concern: "Without a test that checks one copy of a module-level `let mut` across root and import, the sentence will be true on paper only."
  - **Web/Scripting:** A — "The sentence states the user-visible rule: one file, one module, one copy of its state. An internal key is a compiler detail and does not belong in the spec; a test can hold that line." Concern: "Without a spec line, a diagnostic could leak `__main__` again, so the fix should add a test that checks every diagnostic for a main-file item names the path-derived module."
  - **PLT:** A — "The one-module sentence is the soundness fact: it forbids two nominal types from one `type T` declaration. \"Internal module key\" names a compiler detail, and the spec should not name what it does not define. The one-module sentence already implies that every diagnostic names a path-derived module." Concern: "Without an explicit line, an implementation may still leak `__main__` into a message, so the conformance test must check the message text."
  - **DevOps/Tooling:** *(dissent)* B — "This ticket exists because an internal key (`__main__`) reached the user as a wrong PrivateItemAccess and a cut-down E1006. One sentence makes that a spec violation that a test can check, not only a code-quality wish. Without it the next internal key can leak again with no rule to cite." Concern: "If A wins, the sentence about one module instance does not by itself stop diagnostics from printing an internal key, so the impl ticket must add a test for it."
  - **AI/ML:** A — "The sentence states the user-visible rule: one module, one copy of each binding, one set of types. The \"internal module key\" is a term the spec does not define, so B puts an implementation detail in the spec. If one module has one name, a diagnostic that shows a second name already breaks the A sentence." Concern: "Without the explicit line, a diagnostic that leaks `__main__` passes review because no spec text names it."
  - **Minimalism:** A — "The spec never names an internal module key, so a sentence that forbids showing one describes the compiler, not the language. \"One file is one module\" already implies that every diagnostic names the one real module. Implementation details belong in a codegen chore, not in sections/." Concern: "without the explicit line, a diagnostic that leaks `__main__` may survive, so the compiler fix needs a test that checks the module name in E1006 and PrivateItemAccess text."

- **Q5: `main.x` inside the file that declares `fn main`** (A 4, B 2, C 0; went to Phase D)
  - **Systems:** A — "The scope rules already decide it, and a note would suggest a special case where none exists. Fewer sentences, fewer places for the spec to drift." Concern: "A reader may still expect `main.x` inside `main.bl` to mean qualified access, and the error for member access on a fn value should say why."
  - **Web/Scripting:** A — "Existing scope rules already decide it: in that file `main` is the fn. A sentence about `main` would hint that `main` is special, which is the opposite of Q1 A." Concern: "Users may try `myapp.foo()` inside `myapp.bl` to mean \"this module\", and with no spec line the error they get may not tell them to drop the qualifier."
  - **PLT:** B — "The general rule states the result for every module, not only `main.bl`, and it also settles a self-import (`import auth` inside `auth.bl`), which the current text does not address. A rule about `main` alone (C) would be a special case of a general fact. If existing rules already imply it, the sentence costs one line and removes a question." Concern: "If A wins, a later reader may still ask whether a module's own name is in scope as a qualifier, and the answer will rest on inference from \"only imports bind qualifiers\"."
  - **DevOps/Tooling:** A — "Existing scope rules already decide `main.x` in the file that declares `fn main`. A help line (\"`main` here is `fn main`; write `x`\") is diagnostic wording for the impl ticket, not spec text." Concern: "Without a help line the user sees a plain \"no member `x` on fn type\" error, which does not explain the cause."
  - **AI/ML:** B — "I change from my clause (C) to plt's general sentence. One rule for every module (`token.x` inside `auth/token.bl` too) costs a model fewer facts than a clause that holds only for `main`. It answers the question a reader will ask and needs no special case." Concern: "A reader takes \"does not bind its own name\" to mean the module's items are unreachable by any qualified path from inside the module, and asks for a self-qualifier later."
  - **Minimalism:** A — "Qualifiers come only from imports (§10.1 *Qualified Access*), so a module has no qualifier for its own name, and inside it `main` is the fn by plain scope. B restates a rule that already holds, and C writes a special case into the sentence whose purpose is to say \"no special case\". Each redundant sentence is text we must keep in sync." Concern: "a reader may still ask what `main.x` means inside the entry file; if that becomes a real friction report, add an example, not a rule."

#### Phase D — Round 2 (Q5 only)

Q1-Q4 stayed closed. The moderator gave each seat the six Phase C Q5 texts and two facts: sections/07 says "every
import binds its qualifier" and "a whole-module import binds only its qualifier", and no text in sections/07 rules on
a module that imports itself. All six seats ended the debate `STABLE: yes`. PLT and AI/ML moved from B to A.

##### Debate

- **Systems** (`D/sys-debate.md`):

> **Position: A, no change.**
>
> plt's self-import point is real, but B does not settle it. Take `import auth` inside `auth.bl`. §10.5 :2459 says every import binds its qualifier. B says a module does not bind its own name. Those two sentences now conflict, and a reader must guess which wins: is the import an error, a no-op, or a binding of `auth`? B moves the gap; it does not close it.
>
> Self-import needs its own rule. My view: it is an error (a one-file cycle that adds nothing), with a machine-applicable fix that deletes the line. That is a new diagnostic and belongs in its own ticket, not in a clause added to settle Q5.
>
> Without a self-import, A already gives the answer: qualifiers come only from imports, so `main.x` inside `main.bl` resolves `main` by plain scope to the fn. The concerns that web and devops raised are about help text ("`main` here is `fn main`; write `x`"). That is wording for the impl ticket.
>
> I ask the moderator to log self-import as a separate spec gap whatever Q5 decides.
>
> STABLE: yes

- **Web/Scripting** (`D/web-debate.md`):

> I stay with **A**, and I ask the moderator to file self-import as its own ticket.
>
> plt has found a real gap: the spec says nothing about `import auth` inside `auth.bl`. But B does not close it. It closes it in a way readers can take two ways. "A module does not bind its own name as a qualifier" could mean `import auth` in `auth.bl` is an error, or that the import is legal and binds nothing, or (to a Node dev, where a self-import is legal and returns the same module) that it is legal and `auth.x` works. Three readings make three Stack Overflow questions. A rule that answers self-import must say which one, with an error code if it is an error, and that is more than one sentence on a qualifier.
>
> Without a self-import, the case Q5 asks about is already decided: qualifiers come only from imports (:2459, :2531), and inside `main.bl` the name `main` is the fn. No reader of those two lines asks what `main.x` means.
>
> So: Q5 A, plus a separate spec ticket "a module that imports itself", which the panel can decide on its own terms (my early lean: error, with help "drop the import; refer to the item by its bare name").
>
> STABLE: yes

- **PLT** (`D/plt-debate.md`):

> I move to A.
>
> min is right on the typing rule: :2459 and :2531 make imports the only source of qualifiers, so a module with no import of itself has no qualifier for its own name, and inside `main.bl` the name `main` is the fn by plain scope. B restates a consequence, not a new rule.
>
> My one real argument for B was the self-import (`import auth` inside `auth.bl`). On a second reading, B does not settle it. It would contradict :2459: that import binds the qualifier `auth` by the import rule, and B says the module does not. Whether a self-import is legal, an error, or a no-op is a separate question with its own answer, and a sentence written for Q5 should not decide it by accident.
>
> So: Q5 A, and I ask the moderator to file the self-import case as a friction ticket for its own panel (a gap the Phase D search confirmed). I also back devops's point that the impl ticket should give the fn-member error a help line ("`main` here is `fn main`; write `x`").
>
> STABLE: yes

- **DevOps/Tooling** (`D/devops-debate.md`):

> I stay on **A**.
>
> plt found a real gap: the spec has no rule for `import auth` inside `auth.bl`. But B does not close it. B says a module "does not bind its own name as a qualifier". A self-import is an explicit import, and every import binds its qualifier (:2459). So B and :2459 now disagree on that line, and a reader cannot tell which wins: is the import legal and inert, legal and binding, or an error? A tool needs one answer, and it needs an error code and a span to report it.
>
> Without a self-import, B only restates the fact that qualifiers come from imports, and A already covers that.
>
> So the self-import is its own question, not a clause on Q5. I propose a friction or spec ticket: "a module that imports itself". My expected answer is an error, with the primary span on the import and the machine-applicable fix "remove the import; write `x`". That ticket also gives the help line I asked for in Phase C ("`main` here is `fn main`; write `x`") a home in the diagnostic table.
>
> If the panel wants the self-import settled in this decision, I would vote for a self-import rule with a diagnostic, not for B's wording.
>
> STABLE: yes

- **AI/ML** (`D/aiml-debate.md`):

> I move from B to A.
>
> min's point holds: qualifiers come only from imports (:2459, :2531), so a module never has a qualifier for its own name unless it imports itself. B restates that fact. A model that learned "imports bind qualifiers" already gets `main.x` inside `main.bl` right. A second sentence is one more fact to recall, and it adds no new result.
>
> plt's strongest point is the self-import (`import auth` inside `auth.bl`). That is a real gap, but B does not settle it: "every import binds its qualifier" and "a module does not bind its own name" then contradict each other, and a reader cannot tell which wins. A self-import needs its own decision (error, or no-op), with its own diagnostic. I ask the moderator to file it as a separate friction ticket, not to settle it inside Q5.
>
> The real model risk is `myapp.foo()` inside `myapp.bl` (Rust `self::`/`crate::` habit). A help line on the member-access error fixes that: "`main` here is `fn main`; to call `x` in this module, write `x`". That is diagnostic wording for the impl ticket, as devops says.
>
> STABLE: yes

- **Minimalism** (`D/min-debate.md`):

> I stay on A.
>
> plt's new point is real: the spec says nothing on a self-import (`import auth` inside `auth.bl`). But B does not settle it. It creates a conflict. :2459 says "every import binds its qualifier". If a self-import is legal, it binds `auth`, and B says the module does not bind its own name. One of the two sentences must then lose, and the spec does not say which. If a self-import is an error, B is still not the rule we need: we need "a module may not import itself" and its diagnostic.
>
> So the self-import is a separate question with its own answer (error, warning, or a no-op import). It deserves a friction ticket and its own panel item, not a sentence slipped into a ticket about `fn main`.
>
> Without a self-import, A already holds by the text: qualifiers come only from imports (:2459, :2531), and a module that does not import itself has no qualifier for its own name. A sentence that restates that adds drift risk and no meaning.
>
> Request to the moderator: file the self-import gap as a separate friction ticket, whatever Q5's result is.
>
> STABLE: yes

##### Re-vote

- **Q5: `main.x` inside the file that declares `fn main`** (A, 6-0)
  - **Systems:** A — "Qualifiers come only from imports, so inside `main.bl` the name `main` resolves by plain scope to the fn, with no new text. B conflicts with :2459 (\"every import binds its qualifier\") when a file imports itself, so it moves the self-import gap rather than closing it. Self-import needs its own rule and diagnostic, in a separate ticket." Concern: "If no one files the self-import gap, `import auth` inside `auth.bl` stays undefined, and the compiler's behavior there becomes the spec by accident."
  - **Web/Scripting:** A — "Qualifiers come only from imports (:2459, :2531), so inside `main.bl` the name `main` is the fn, and no reader of those lines needs more. B's sentence reads three ways on a self-import (an error, a no-op, or legal like Node), so it raises the question it means to settle. Self-import is a real gap, but it needs its own ticket and a clear answer with a diagnostic, not one sentence on qualifiers." Concern: "If no one files the self-import ticket, `import auth` inside `auth.bl` stays unspecified, and the compiler's current behavior becomes the rule by accident."
  - **PLT:** A — "Imports are the only source of qualifiers (sections/07 :2459, :2531), so a module has no qualifier for its own name. Inside `main.bl`, `main` is the fn by plain scope, and `main.x` fails as member access on a fn value. B states a result the rules already give, and it would contradict :2459 for a self-import (`import auth` inside `auth.bl`), which binds the qualifier by the import rule. That self-import case needs its own ruling, not an accidental one." Concern: "If no one files the self-import gap, its meaning will stay undefined, and the compiler will pick an answer that no panel chose."
  - **DevOps/Tooling:** A — "Existing scope rules already decide `main.x` inside the file that declares `fn main`: no import binds `main` there, so `main` is the fn. B does not settle the self-import. It conflicts with \"every import binds its qualifier\" (:2459) on exactly that line, and it gives no error code or span for a tool to report. The self-import needs its own ticket with a diagnostic, and the \"`main` here is `fn main`; write `x`\" help line goes in the impl ticket." Concern: "If nobody files the self-import ticket, `import auth` inside `auth.bl` stays unspecified and each tool will guess differently."
  - **AI/ML:** A — "Qualifiers come only from imports (§10.1 *Qualified Access*, §10.5 :2459), so a model that learned that rule already knows `main` inside `main.bl` is the fn. B restates the rule and, for a self-import, conflicts with \"every import binds its qualifier\", so it adds a fact without settling the one open case. The model risk (`myapp.foo()` inside `myapp.bl`, from Rust `self::` habits) is best fixed by a help line on the member-access error, which belongs to the impl ticket." Concern: "The self-import case (`import auth` inside `auth.bl`) stays unspecified unless someone files it as its own ticket."
  - **Minimalism:** A — "Qualifiers come only from imports (sections/07 :2459, :2531). So a module that does not import itself has no qualifier for its own name, and inside the entry file `main` is the fn by plain scope. B does not settle the self-import case. If a self-import is legal, B conflicts with \"every import binds its qualifier\", so the self-import needs its own rule and its own panel item, not a sentence added here." Concern: "If nobody files the self-import gap as a separate ticket, A leaves `import auth` inside `auth.bl` unspecified, and the compiler will pick a meaning by accident."

### AI-First Review

| Criterion | Result |
|---|---|
| Learnability | Pass: the path rule in §10.1 already gives the name; the decision adds no new fact for the file that declares `fn main` |
| Consistency | Pass: the decision removes a special case |
| Generability | Pass: `import main` and `main.shared()` work as for any module |
| Debuggability | Pass: E1003 names the item, E1006 keeps its qualified-access help, E1200 gets a help line for a file outside `src/` |
| Token Efficiency | Pass: no new syntax |

### Final Spec

```blink
// src/main.bl, given to `blink run src/main.bl`
import helper

pub fn shared() -> Int {
    7
}

fn secret() -> Int {
    42
}

fn main() {
    let n = helper.twice()
    io.println("{n}")
}
```

```blink
// src/helper.bl
import main

pub fn twice() -> Int {
    main.shared() * 2      // qualified access to module `main`
}

fn peek() -> Int {
    main.secret()          // error E1003 PrivateItemAccess: `secret` is private to module `main`
}
```

```blink
// src/myapp.bl; the package also has examples/util.bl and no src/util.bl
import util              // error E1200 ModuleNotFound
                         // help: files outside `src/` are not modules; move the file under `src/`
```

- The file that declares `fn main` is an ordinary module. Its name comes from its path under `src/` or from
  `@module`. The file given to `blink build` or `blink run` keeps that name. Any file under `src/` may declare
  `fn main`; `src/main.bl` is a legal ordinary module.
- The §10.1 example tree shows `src/myapp.bl  # module: myapp (package entry)` and does not show `main.bl`.
- A sibling imports that file selectively or by qualifier. In a sibling, `main` binds only the qualifier.
  E1012 covers a sibling that declares its own `fn main` and imports `main`. E1006 keeps its qualified-access help.
  E1003 for `main.secret` names the item `secret` in module `main`.
- A file is one module however the build reaches it: one copy of each module-level binding and one set of types.
- A file outside `src/` has no module name, and no file can import it. Diagnostics name it by its path.
  E1200 gets the help "files outside `src/` are not modules; move the file under `src/`" only when the import
  path matches a `.bl` file under the package root but outside `src/`.
- No spec sentence covers `main.x` inside the file that declares `fn main`. Existing scope rules decide it.
- Out of scope: a module that imports itself.