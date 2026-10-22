[< All Decisions](../DECISIONS.md)

# Variant and Static Method Name Case — Design Rationale

The compiler accepted `type T { foo, Bar(Int) }`, and `match t { foo => ... }` tested the variant. No spec text set a case rule for variant names. The *Variant spelling and the uppercase pattern rule* ruling made a bare name with an uppercase first character in a refutable pattern always a variant, so a typo there is E0547. A bare lowercase name kept the type-directed rule, so `fooo =>` on that enum still bound a value with no error. Its Q4 sent lowercase variant names to a separate question. This ruling answers it: keep lowercase variants, or make an uppercase first letter a declaration rule.

A second fault came with it. *Qualified variants in expressions* spells every user variant `K.Name` in an expression, which is also how a static method is called (`Duration.ms(100)`). With `type K { A(Int), B }`, `let k = K.zed` passed `blink check` and failed in the build with an internal compiler error: the checker did not report a missing variant for a lowercase member, because a lowercase name might be a static method.

This ruling amends Q4 of [Variant Spelling and the Uppercase Pattern Rule](variant-spelling-and-pattern-case.md) and the `K.name` lookup of [Qualified Variants in Expressions](qualified-variants.md).

## Summary

| Q | Question | Result | Vote |
|---|---|---|---|
| Q1 | The case rule for variant names | A variant name must start with `Lu`/`Lt`, else `LowercaseVariant` at the declaration; a bare lowercase name in a pattern is a binding (E0547 or E0308 with a payload); `K.lower` never names a variant | 6-0 |
| Q2 | `K.Upper` in an expression, and static methods named with an uppercase first letter | A static method name must not start with `Lu`/`Lt`; `K.Upper` never names a function, and a miss is E0547 | 6-0 R2 after 4-2 R1 |
| Q3 | Help when `K.lower` finds no static method | Only the nearest-name convention, with the variants of `K` added to its candidates | 6-0 R2 after 4-2 R1 |
| Q4 | When the rename fix for `LowercaseVariant` is machine-applicable | Only when the first character maps to exactly one `Lu`/`Lt` character and `K` has no member with the new name; renames every use | 6-0 |

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated
in independent-proposal → debate → vote rounds.

#### Phase A — Independent proposals

- **Systems:**

  > ## Proposal S1 (my vote): a variant name must start with an uppercase letter
  >
  > Rule: the first character of a variant name in a type declaration must be Unicode `Lu` or `Lt` — the same test the pattern rule uses (03_types.md:3069). One predicate, one place, no type lookup.
  >
  > ```blink
  > type Token {
  >     eof                 // error[LowercaseVariant]
  >     Num(Int)
  > }
  > ```
  >
  > ```
  > error[LowercaseVariant]: variant `eof` of `Token` must start with an uppercase letter
  >   help: rename to `Eof`   (machine-applicable within the module)
  > ```
  >
  > New code: `LowercaseVariant`, next free E05xx, emitted by the parser or the declaration pass (it needs no types).
  >
  > **What it buys (the reason this is a systems point):** case becomes a lexical fact. Then:
  >
  > 1. **Patterns:** a bare lowercase name with no payload in a refutable pattern is *always* a binding. Delete the type-directed clause (3070, 3135, 3145, and the W1011 text at 07:2860). The typo hole `fooo =>` goes away. There are no lowercase variants left to mistype. The checker no longer needs the scrutinee type to know what an arm binds. That is a real simplification for the checker, the LSP and any tool that reads Blink without running the type checker.
  > 2. **`K.zed`:** variants and static methods share one member namespace today. With S1 the case of the first letter splits it. `K.Upper` is only ever a variant (else E0547). `K.lower` is only ever a static method (else the existing undefined-method error). The checker never has to guess, so the "skip NoSuchVariant because it might be a method" branch that causes the NoTypeForNode ICE has nothing left to guess. The fix is a hard rule, not a heuristic. A static method may not start with an uppercase letter. That is a convention today. Under S1 it can be a lint or a rule; I would make it a rule so the namespace split holds both ways.
  > 3. **Lowercase name with a payload in a pattern** (`foo(x)`): keep E0547, with help "variant names start with an uppercase letter".
  >
  > **No case:** "uppercase" means `Lu`/`Lt` only. `_X`, `_x`, a digit-free CJK or other `Lo` first letter all fail the rule. A Japanese author writes `T名前` or `K変数` style, the Haskell/OCaml answer. This costs those authors something, but the other choice (let `Lo` through) brings the typo hole back for exactly those names, with no lexical way to see it. One predicate, used the same way everywhere, is the cheaper rule to keep correct.
  >
  > **Migration:** the facts say no enum in src/, lib/, tests/, sections/ or examples/ declares a lowercase variant. Cost ≈ 0. The gen1 acceptance of `type T { foo }` becomes an error. No runtime or ABI change: variant C symbols come from cname mangling, not from source case.
  >
  > **FFI note:** C enums use lowercase or ALL_CAPS constants. An ALL_CAPS name passes (`EAGAIN` is `Lu`). A binding that wants a lowercase C constant maps it via `@ffi` or a const, not via a Blink variant name. That is fine: the source name is not the C name.
  >
  > **Cross-language:** Haskell, OCaml, Elm, PureScript make this syntax and have no hole. Rust lets lowercase through with a lint and keeps a real ambiguity in patterns: a misspelled or unimported variant name binds and matches everything, and only lints catch it (a known Rust footgun). Swift's lowercase cases work because Swift requires `.case` in patterns. Blink chose bare patterns, so it needs the Haskell rule, not the Swift one.
  >
  > ## Proposal S2 (fallback, I vote against): keep lowercase variants
  >
  > Keep 3070 as is, and fix `K.zed` by making the checker look up both namespaces and report E0547/undefined-method on a miss. This closes the ICE but leaves the binder typo hole and the type-dependent meaning of every lowercase arm name. Cost: a permanent exception in the spec, the checker and every tool, for a feature no code uses.

- **Web/Scripting:**

  > ## Proposal W1 (my pick): a variant name must start with an uppercase letter
  >
  > Make it a declaration rule. A variant name's first character must be Unicode `Lu` or `Lt` — the same test the pattern rule (§3.5 *Bare names*) already uses.
  >
  > ```blink
  > type Shape {
  >     circle(Float)       // error[VariantNameNotUppercase]
  >     Square(Float)
  > }
  > ```
  >
  > ```
  > error[VariantNameNotUppercase]: variant `circle` must start with an uppercase letter
  >   --> shape.bl:2:5
  >   help: rename it `Circle`        (machine-applicable)
  >   note: an uppercase first letter is how a pattern tells a variant from a new binding
  > ```
  >
  > **Why, from where a JS/Python dev sits.** Today the rule a newcomer must learn has an asterisk: "`Red =>` is checked, `red =>` might be a variant or might silently match everything, depending on the type." Nobody gets that in 5 minutes, and the failure mode is silent. One rule with no asterisk is easier: *Capitalized means variant. lowercase means variable.* Every Python/TS dev already reads `Foo` as "a type-ish thing" and `foo` as "a value". Swift devs write `case circle` by habit, but the error fires once, at the declaration, with a one-key fix. That is a cheap lesson. A silent catch-all arm is an expensive one.
  >
  > **Typo hole.** Closed. With no lowercase variants, a lowercase bare name in a refutable pattern is always a binding, so `fooo =>` cannot "almost match" a variant `foo`. The type-directed branch in §3.5 goes away, and the rule becomes context-free: the reader knows what each arm binds without knowing the scrutinee type. W1011 still catches a binder that hides a local.
  >
  > **`K.zed`.** Under the qualified-variants ruling, a lowercase member after `K.` can only be a static method; an uppercase one can only be a variant. The checker no longer has to guess, so `let k = K.zed` gets a plain "no static method `zed` on `K`" error (the existing unknown-method code) in `check`, not an ICE in build. That fixes the open bug by design, not by special case. `K.Zed` keeps E0547.
  >
  > **No-case first character (`_x`, `数`, `ñ`?).** `ñ` is `Ll` — rejected like any lowercase name. `_x`, digits-after-underscore, and CJK/no-case letters (`Lo`) are also rejected: "uppercase" means `Lu`/`Lt`, nothing else. This matches the pattern rule exactly (no-case = binding), so a variant named `数` could never be matched bare anyway — allowing it would rebuild the hole. Cost: a CJK-only codebase must prefix with a Latin capital (`V数`). I accept that; Haskell and Elm impose the same.
  >
  > **Spec/code changes.**
  > - §3.x enum declaration: add the rule + new code (next free E055x, e.g. `VariantNameNotUppercase`). ERROR_CATALOG row.
  > - §3.5 *Bare names*: drop the second bullet's type-directed branch; a non-uppercase bare name with no payload is always a binding; a non-uppercase name with a payload is E0547 / E0308 as now (or a parse-level hint "variants start uppercase").
  > - §3.5 E0547 list: remove "lowercase … never gets E0547" sentence; simplify.
  > - DECISIONS.md row.
  >
  > **Migration.** Zero known: no enum in src/, lib/, tests/, examples/ declares a lowercase variant. FFI-mirrored C enums (`O_rdonly`-style) already need renaming to fit, and `O_RDONLY` passes (`O` is `Lu`).
  >
  > **Cross-language.** Haskell, OCaml, Elm, PureScript: uppercase by syntax — same as W1. Rust: allowed with a lint, and Rust has the exact same pattern hole (lowercase variant vs binding), which is why the lint exists. Swift/Kotlin/TS: any case, but they lack Blink's bare-name patterns, so they do not have the hole.
  >
  > ## Proposal W2 (fallback): keep lowercase, add a lint
  >
  > Warn `W____ LowercaseVariant` at the declaration; keep the type-directed rule. Cheaper to spec, but the hole and the `K.zed` ambiguity stay, and a warning that every project should fix is a rule wearing a disguise. I vote against W2 unless the panel finds a real use case for lowercase variants.

- **PLT:**

  > ## Proposal 1 (recommended): a variant name must start with Lu or Lt
  >
  > A variant name must start with a Unicode `Lu` or `Lt` letter. This is the predicate §3.5 *Bare names* already uses, so one test decides the class of a name in a declaration, a pattern and a member access.
  >
  > ```blink
  > type T { foo, Bar(Int) }       // error
  > type T { Foo, Bar(Int) }       // OK
  > ```
  >
  > ```
  > error[LowercaseVariant]: variant name `foo` must start with an uppercase letter
  >   help: rename to `Foo`
  > ```
  >
  > New code: next free E05xx. Fix is machine-applicable when the first character has an uppercase mapping.
  >
  > **Why (soundness and compositionality).** Today the meaning of `foo =>` depends on the declarations of the scrutinee type. Adding a variant `foo` silently turns an arm in another module from a binding (matches all) into a variant test. That is not compositional. Under this rule, pattern classification is syntactic and scope-free: uppercase = constructor, else = binder. Haskell, OCaml, Elm and PureScript use exactly this split, for this reason.
  >
  > **Pattern effects.** The type-directed bullet in §3.5 goes. A lowercase bare name with no payload is always a binding. A lowercase name with a payload (`foo(x)`) is E0547 on an enum (no enum can declare it) and E0308 elsewhere, as now. The typo hole closes by construction: `fooo =>` is a binder by intent, and the arms after it get the unreachable-arm warning. No variant can be lowercase, so no variant typo can be lowercase.
  >
  > **`K.zed`.** The member namespace splits by case. `K.Upper` is a variant lookup (E0547 if `K` has none). `K.lower` is a static-member lookup only (no-such-method error if absent). The checker no longer guesses which kind a lowercase member is, so the NoTypeForNode ICE class goes away. Follow-up (not this ticket): an uppercase-initial static fn name would sit in the variant half; recommend a separate lint or rule.
  >
  > **Caseless first character** (`_Foo`, CJK `Lo` such as `数`): rejected. The pattern rule already treats them as non-uppercase; any other choice puts a name in two classes. Tradeoff: CJK authors need a Latin or other cased first letter (Haskell has the same limit). Wire spelling is not a reason for lowercase variants: Str-backed enums give each variant its own wire text (§3.6).
  >
  > **Spec and code changes.** sections/03_types.md: variant declaration rule; *Bare names* drops the type-directed bullet and the "uppercase only" caveat; E0547 bullets simplify. sections/07 W1011 text: a refutable-pattern binder can no longer name a variant, so that clause drops. ERROR_CATALOG: new code. Compiler: one declaration check.
  >
  > **Migration.** Zero known declarations (search found none). Valid uppercase code does not change.
  >
  > ## Proposal 2 (rejected): keep lowercase variants, add a lint
  >
  > Keeps the non-compositional pattern meaning, the binder-typo hole, and a type-directed `K.zed` lookup over merged variants and static methods. A lint warns at the declaration, not at the distant arm whose meaning changes. Rust takes this path.
  >
  > ## Vote: Proposal 1.

- **DevOps:**

  > ## P1 (my pick): an uppercase first letter is a declaration rule for variants
  >
  > A variant name must start with a Unicode `Lu` or `Lt` letter: the same test as the pattern rule in §3.5 *Bare names*. `_x`, `x`, and a caseless first letter (CJK) are not uppercase, so they are errors.
  >
  > ```blink
  > type K { A(Int), zed }
  > ```
  > ```
  > error[LowercaseVariantName]: variant name `zed` must start with an uppercase letter
  >   --> k.bl:1:18
  >   help: rename to `Zed`   (machine-applicable when `K` has no `Zed`)
  > ```
  >
  > New code E05xx `LowercaseVariantName` (number TBD). The checker still registers `zed` under its spelling, and uses of it report nothing more: one mistake, one diagnostic. The LSP offers the fix as a workspace rename. A caseless first letter gets no automatic fix, only "start the name with an uppercase letter".
  >
  > **`K.zed`.** The first letter of the member decides which table the checker searches. An uppercase member is a variant lookup, and a miss is E0547. A lowercase member is a static-method lookup, and a miss is the static-member code, with the variants of `K` in the help (`did you mean the variant K.Zed?`). Each miss has exactly one owner, so the skipped-check ICE (NoTypeForNode) cannot occur. With the qualified-variants ruling, every expression use is `K.Zed`, so a reader can tell `Duration.ms(100)` from `K.Zed` without types.
  >
  > **Binder typo hole.** Closed. No variant can have a lowercase name, so in a refutable pattern a bare lowercase name with no payload is always a binding. Remove the type-directed branch. A lowercase name with a payload (`zed(x)`) is E0547, and the nearest-name help (case-insensitive) suggests `Zed`. This also makes semantic highlighting, `blink fmt`, and a parse-only LSP (no types yet, file mid-edit) agree on "variant or binding" from the token alone. Tools that run before typecheck stop guessing.
  >
  > **Spec changes.** §3.4 enum declaration: add the rule and the code. §3.5 *Bare names*: second bullet loses the type-directed branch. Delete "The protection against a typo covers variants whose names start with an uppercase letter only" and the line-3145 sentence on lowercase names. §2 syntax table: add a "Variant names" row next to "Type names". ERROR_CATALOG: new entry.
  >
  > **Migration cost.** About zero: the heuristic search found no lowercase variant in src/, lib/, tests/, examples/. `.from_str` and JSON already take wire spelling from backing literals (`InProgress = "in_progress"`), so interop does not need lowercase names. A future C-header binding generator must capitalize C enum names.
  >
  > **Tradeoffs.** Against: Swift writes lowercase cases; a CJK author cannot use a native first letter (Go has the same complaint for exports, Haskell for constructors). For: Haskell, OCaml, Elm, PureScript all make this a syntax rule; their tools never resolve a constructor by type.
  >
  > ## P2 (rejected): keep lowercase variants, add a warning lint (Rust `non_camel_case_types`)
  >
  > `W-LowercaseVariantName`, `@allow`-able. The hole stays open wherever the lint is off. The checker keeps two lookups for `K.zed` and the ICE class stays. The LSP still needs types to color a pattern name.

- **AI/ML:**

  > ## Proposal P1 (recommend): an uppercase first letter is a declaration rule for variants
  >
  > A variant name must start with an uppercase letter: Unicode `Lu` or `Lt`, the same test the pattern rule uses (sections/03_types.md 3069). Anything else is an error at the declaration: a lowercase letter, `_` (so `_x`), or a letter with no case (CJK `東`). No exemption for caseless scripts: the pattern rule already treats them as not uppercase, so they would re-open the hole. Such a user writes a Latin capital prefix (`V東`).
  >
  > ```blink
  > type K { foo, Bar(Int) }
  > ```
  >
  > ```
  > error[LowercaseVariant]: variant name `foo` must start with an uppercase letter
  >   --> k.bl:1:10
  >   help: rename the variant: `Foo`
  > ```
  >
  > New code `LowercaseVariant` (next free E05xx after the qualified-variants codes).
  >
  > **K.zed.** After this rule, a member of a type that starts with a lowercase letter is never a variant. `K.zed` looks up static methods only; with no method, it is the existing no-such-method error, never E0547 and never an ICE. `K.Zed` looks up variants first, so a typo is E0547. The checker's current guess ("lowercase may be a static method, skip NoSuchVariant") becomes a sound rule instead of a guess, which removes the cause of the NoTypeForNode ICE. (Uppercase static methods: out of scope.)
  >
  > **Typo hole.** In a refutable pattern, a bare lowercase name with no payload is then always a new binding, and a bare lowercase name with a payload is always E0547. The type-directed branch of the pattern rule (3070, 3145) goes away. `fooo =>` can no longer be a misspelled variant, because no variant `foo` exists.
  >
  > **Spec changes.** ERROR_CATALOG row. §3.1/§3.3 enum declaration: add the rule. §3.5 *Bare names*: replace the second bullet with "a bare name whose first character is not uppercase is a binding; with a payload, E0547". Delete the "covers uppercase variants only" sentence. §7 W1011 text at 2860: drop the "type at that position has no variant of that name" clause. §2 table row: "Type and variant names: PascalCase, enforced for variants".
  >
  > **Migration.** No lowercase variant found in the repo; cost near zero. A lowercase JSON tag is a JSON-derive question, not a reason to keep lowercase variants.
  >
  > **Why, from my seat.** One rule, decided by the first character, with no type lookup: a model (and a human reader) knows what every bare name in a pattern means from the token alone. Today a model must know the variant list to tell if `foo =>` binds or tests. Models trained on Swift will emit lowercase cases; a hard error with a machine rename teaches the convention in one round trip. A warning would not: warnings are ignored in generated code, and the two-mode pattern rule stays in the spec. Haskell, OCaml, Elm, PureScript do the same.
  >
  > ## Proposal P2 (reject): keep lowercase variants, add a lint
  >
  > Keeps the type-directed branch, the hole, and the `K.zed` ambiguity (both namespaces for lowercase members). Adds a decision point per enum. Rust's `non_camel_case_types` is often silenced.

- **Minimalism:**

  > ## Proposal M1 (my pick): a variant name must start with an uppercase letter
  >
  > One declaration check; two rules deleted.
  >
  > ```blink
  > type Shape {
  >     Dot
  >     circle(Float)      // error[LowercaseVariant]
  > }
  > ```
  >
  > ```
  > error[LowercaseVariant]: variant name `circle` must start with an uppercase letter
  >   help: rename to `Circle`
  > ```
  >
  > "Uppercase" uses the same test as the pattern rule: first character is Unicode `Lu` or `Lt`. `_x`, `x` and a caseless first letter (CJK) all fail. One definition of "uppercase" for declarations and patterns.
  >
  > **What it deletes.**
  > 1. The type-directed fallback in refutable patterns. Today a lowercase bare name "is a variant only when the type has one of that name". Under M1 no variant has a lowercase name, so the second bullet of *Bare names: variant or binding* collapses to: "a bare name with no payload whose first character is not uppercase is a new binding." The sentence "The protection against a typo covers variants whose names start with an uppercase letter only" goes away: the protection covers all variants.
  > 2. The variant/static-method overlap in `K.name`. A lowercase member is never a variant, so `K.zed` is a method lookup only; a miss is NoSuchMethod. The checker skip behind today's NoTypeForNode ICE loses its reason; the fix becomes "always report".
  >
  > **Typo hole.** Closed. `fooo =>` on an enum is a binding, as it is for every other lowercase name; it cannot be a misspelled variant because no lowercase variant exists.
  >
  > **Spec change.** §3.5 declaration grammar: one sentence + new code (writer picks the number, E05xx range). §3.5 *Bare names*: shorten bullet 2 and drop the "uppercase only" caveat. §7 W1011 text: the "first character is not uppercase and the type has no variant of that name" clause loses its second half. ERROR_CATALOG: one new entry.
  >
  > **Migration.** None found in src/, lib/, tests/, examples/. Cost is the new check plus deleting the fallback branch in the pattern checker.
  >
  > **Tradeoffs.** A team that writes identifiers in a caseless script cannot name a variant in that script. Go has the same limit on exported names; the fix is a Latin prefix. Swift-style lowercase cases are lost, but with qualified variants the case now tells the reader `Color.Green` (variant) from `Duration.ms(...)` (method).
  >
  > **Cross-language.** Haskell, OCaml, Elm, PureScript make this syntax and need no type-directed pattern rule. Rust allows lowercase and pays with a lint plus the binder hazard.
  >
  > ## Proposal M0 (do nothing), rejected
  >
  > Keep lowercase variants. Zero spec text now, but the residual type-directed rule, the "uppercase only" caveat, the `K.zed` namespace ICE and a future lint all stay. Doing nothing here keeps more language, not less.
  >
  > ## Proposal M2 (lint only), rejected
  >
  > A warning on lowercase variants keeps every rule M1 deletes and adds a lint. Strictly more surface than M1.

#### Phase B — Debate highlights

One round. Each seat read all six Phase A texts and answered four open variations inside U: the diagnostic name, static methods named with an uppercase first letter, the help on a `K.lower` miss, and when the rename fix is machine-applicable. All six seats still backed U. All six took the name `LowercaseVariant`. Seats split on static methods. Sys proposed a rule in Phase A but accepted a separate ticket; plt moved to the rule; web, aiml, devops and min wanted a separate ticket.

- **Systems:**

  > Systems, B1. I still back U (S1).
  >
  > 1. Name: `LowercaseVariant`. Four seats already use it, and it is shorter. Code: next free E05xx.
  >
  > 2. Uppercase static methods: I accept a separate ticket for the rule. One condition: this ruling must say what `K.Upper` means. My text: "`K.Upper` looks up variants only." Without that sentence, an uppercase static fn makes `K.Foo` search both tables again, and the namespace split only works one way. That is the same guess that caused the ICE. Cost today is zero: `rg '^\s+(pub )?fn [A-Z]'` over src, lib, tests, examples and sections finds nothing. The follow-up ticket should cover every fn name, not only static ones.
  >
  > 3. Help on a `K.lower` miss: I back devops. List a variant whose name matches case-insensitively (`did you mean the variant K.Zed?`). It is help text and not machine-applicable, because the help changes the kind of member, not only the spelling.
  >
  > 4. Machine-applicable rename: only when the first character maps to exactly one `Lu`/`Lt` character and `K` has no variant of the new name. A caseless first letter gets help text only. I back devops' "uses of it report nothing more": the checker registers the variant under the spelling as written, so we get one mistake and one diagnostic.
  >
  > Objection to web, which wrote: "W1011 still catches a binder that hides a local". W1011 is ShadowedVariant. It fires when a binding hides a variant, not a local. Under U, a binder in a refutable pattern never gets W1011. The writer should not carry that sentence.
  >
  > stable, ready to vote

- **Web/Scripting:**

  > I still back U (my W1).
  >
  > 1. **Name:** I drop `VariantNameNotUppercase` and take `LowercaseVariant`. It is the majority choice and short. The message text covers `_x` and CJK ("must start with an uppercase letter").
  >
  > 2. **Uppercase static methods:** split them into a separate ticket (plt, aiml). Do not widen this one. But the text must not overclaim. aiml writes "`K.Zed` looks up variants first", which implies a fallback to methods. Under U, `K.Upper` is a variant lookup only, and a miss is E0547. Until the follow-up ticket lands, the spec should say that an uppercase static method is not reachable as `K.Upper`, not stay silent. Then nobody has to guess.
  >
  > 3. **`K.lower` miss help:** yes to devops ("did you mean the variant K.Zed?"). Coming from JS, `Color.green` is the first mistake a dev makes, and this help turns it into a one-step fix. Use a nearest-name match that ignores case.
  >
  > 4. **Machine-applicable rename:** I concede my unconditional claim. Take devops and plt: the rename is machine-applicable only when the first letter has an uppercase mapping and `K` has no variant with the new name. A caseless first letter gets help text only. For a `pub` type the fix is a rename across the workspace, so sys's "within the module" is too narrow. Also endorse devops: "uses of it report nothing more" (one mistake, one diagnostic).
  >
  > stable, ready to vote

- **PLT:**

  > PLT, B1.
  >
  > 1. Name: `LowercaseVariant`, with the majority. It is less exact than `VariantNameNotUppercase` (`_Foo` and `東` are not lowercase), but the message "must start with an uppercase letter" covers them. I will not block on it.
  >
  > 2. Uppercase static methods: I now back sys and want the rule in this ruling. The member lookup only splits cleanly if `K.Upper` never resolves to a method. aiml writes "`K.Zed` looks up variants first". That implies a fallback to methods, so the meaning of `K.Zed` goes back to depending on declarations. Without the rule, a static fn `Zed` on an enum is either uncallable or ambiguous. Rule: a static method name must not start with `Lu`/`Lt`, same predicate, same kind of error. I found no uppercase static method in the repo; the `Duration_ms` free fns in lib/std/time.bl are mangled names, not method names. If the panel wants it out of scope, then `K.Upper` must still be variant-only (a miss is E0547), with no fallback.
  >
  > 3. devops help on a `K.lower` miss that lists the variants: yes, as help text only, never as a fallback lookup.
  >
  > 4. Machine-applicable fix: devops's condition is correct ("when `K` has no `Zed`"). web's unconditional "(machine-applicable)" is wrong when the uppercased name collides. The fix must rename uses too, so it is a rename refactor. Caseless first letter: no fix.
  >
  > Objection, aiml: "a bare lowercase name with a payload is always E0547". It is E0308 when the scrutinee is not an enum (§3.5, already in my and web's text).
  >
  > I still back U (my P1).
  >
  > stable, ready to vote

- **DevOps:**

  > DevOps B1. I still back U.
  >
  > 1. Name: I concede to `LowercaseVariant` (four seats). Condition: the message must say "must start with an uppercase letter", not "is lowercase", because `_X` and `東` are not lowercase. The `blink explain` text must list the three cases.
  >
  > 2. Uppercase static methods: give them a separate ticket, as plt and aiml say. Until that lands, `K.Upper` looks up variants first, then static methods, so working code does not break. A miss in both is E0547 and is never skipped, so each miss still has exactly one error. sys's "make it a rule" is a good idea, but it changes the spec for functions too, so it gets its own ticket.
  >
  > 3. Keep my help on a `K.lower` miss. It costs one case-insensitive lookup, and it catches the most likely error: a user who wrote Swift-style `K.zed`. Use the same help for a pattern `zed(x)` that gets E0547.
  >
  > 4. Machine-applicable only when the first character maps to exactly one uppercase character, and `K` has no variant or static member with the new name. Objection to web's bare "(machine-applicable)": it needs the collision condition. Objection to sys's "machine-applicable within the module": for a `pub` enum, the fix must rename every use in the package, or it leaves code that does not compile. The LSP does this as a workspace rename. If the fix cannot reach a use, it is a suggestion, not machine-applicable.
  >
  > stable, ready to vote

- **AI/ML:**

  > I still back U (my P1).
  >
  > 1. **Name: `LowercaseVariant`.** Shortest; four seats use it. `VariantNameNotUppercase` is more exact for `_X` and `東`, but the message text ("must start with an uppercase letter") already covers those cases. A model reads the message, not only the name.
  >
  > 2. **Uppercase static methods: a separate ticket, but this ruling must not leave a gap.** If `K.Upper` looks up variants only, then an existing `fn K.New()` can no longer be called, and its call gets a false E0547. Interim rule: `K.Upper` looks up variants first. On a miss it looks up static methods. Only when both miss is it E0547. `K.lower` looks up static methods only. sys's "make it a rule" is good long term (one predicate in both directions), but it renames methods, so it belongs in its own ticket.
  >
  > 3. **devops help on a `K.lower` miss: yes.** Nearest-name over both tables, case-insensitive (`did you mean the variant K.Zed?`). One round trip to fix it is the best case for generated code.
  >
  > 4. **Machine-applicable rename: conditional.** I object to web's unconditional "rename it `Circle` (machine-applicable)". The fix is machine-applicable only when (a) the first character maps to exactly one `Lu`/`Lt` character (no fix for `ß`, `東` or `_x`), and (b) `K` has no member with that name already. The fix renames the declaration and every use the compiler sees. Then agents can apply it safely.
  >
  > stable, ready to vote

- **Minimalism:**

  > I still back U (my M1).
  >
  > 1. **Name:** `LowercaseVariant`. It is the shortest name and three other seats chose it.
  >
  > 2. **Uppercase static methods:** out of scope, and no rule now. Sys says: "I would make it a rule so the namespace split holds both ways." That adds a rule to fix a case that no code has. But the option text "`K.Upper` = variant lookup" also makes it unclear what happens to a static `fn K.Make()`: it reads as if `K.Make()` gives E0547. My smaller fix: **the checker searches both tables, and the first letter decides only which error a miss gets** (uppercase gives E0547, lowercase gives the no-such-method error). This still removes the ICE, because a miss always gets one error from one owner. It also keeps uppercase methods working, and it needs no second rule. AI/ML's "`K.Zed` looks up variants first" already reads this way. If the panel wants the hard split, it should go in a separate ticket.
  >
  > 3. **Help on a `K.lower` miss:** OK only through the existing nearest-name convention (ERROR_CATALOG *Conventions*), with the variants added to the candidates. No new help text in the spec.
  >
  > 4. **Machine-applicable fix:** yes when the first letter has a one-character uppercase mapping and the new name does not clash with a member of `K` (devops and PLT conditions combined). A caseless first letter gets help text only.
  >
  > No other objections.
  >
  > stable, ready to vote

#### Phase C — Final vote

Each seat voted alone on a silent ballot.

- **Q1: The casing rule for variant names** (6-0, for A)

  > - A: U. A variant name must start with a Unicode `Lu` or `Lt` letter; `x`, `_x`, `_X` and a caseless first letter are errors at the declaration, `LowercaseVariant` (next free E05xx; message "must start with an uppercase letter"). The type-directed branch of the pattern rule goes away: in a refutable pattern a bare lowercase name with no payload is a binding; with a payload it is E0547, or E0308 when the type at that position is not an enum (§3.5; plt B1 correction). `K.lower` looks up static methods only.
  > - B: Keep lowercase variants; add a warning lint.
  > - C: Keep the current rule; fix only the ICE.

  - **Systems:** A
    - Reasoning: Case becomes a lexical fact. The checker, the LSP and the formatter know whether an arm name binds or tests from the token alone, without the scrutinee type. That one predicate removes the type-directed branch, closes the typo hole, and takes away the guess behind the `K.zed` NoTypeForNode ICE. The repo has no lowercase variants, so migration costs nothing.
    - Concern: Authors who write in a caseless script must use a Latin prefix, and some may see the rule as hostile.
  - **Web/Scripting:** A
    - Reasoning: A JS or Python dev can learn "Capitalized = variant, lowercase = variable" in five minutes. "It depends on the scrutinee type" takes longer, and when they get it wrong nothing tells them. A fails loudly, once, at the declaration, and the fix is one key. B and C keep a silent catch-all arm in the language for a feature nobody uses.
    - Concern: Devs coming from Swift or Kotlin, and models trained on them, will hit the error often at first. So the message and the rename fix must be good from day one.
  - **PLT:** A
    - Reasoning: With U, the first character alone sets what a name means in a pattern or member access, and no declaration elsewhere can change that. Today, adding a variant `foo` silently changes an existing `foo =>` arm from a binding into a variant test. U gets rid of that, along with the binder typo hole and the guess behind the `K.zed` crash. Haskell, OCaml, Elm and PureScript take the same approach.
    - Concern: Authors who write in a caseless script need a Latin capital prefix on variant names, and some will find this hostile.
  - **DevOps:** A
    - Reasoning: The first letter tells highlighting, the formatter and a language server working on a file mid-edit whether a name is a variant or a binding, with no types needed. One predicate (`Lu`/`Lt`) for declarations, patterns and member access gives each miss exactly one error and removes the code path behind the NoTypeForNode ICE. A lint (B) keeps two modes in every tool.
    - Concern: Users of caseless scripts get a hard error with no automatic fix, so the `blink explain` text must show the Latin-prefix workaround.
  - **AI/ML:** A
    - Reasoning: The first character alone tells a model whether a bare pattern name binds or tests a variant, with no lookup of the variant list. A hard error with a rename teaches the convention to a model trained on Swift in one round trip. A lint (B) is ignored in generated code, and C keeps both the typo hole and the two-mode rule.
    - Concern: A team that writes names in a caseless script must add a Latin capital in front, and some will find that hostile.
  - **Minimalism:** A
    - Reasoning: U adds one check at the declaration and deletes the type-directed branch of the pattern rule, the "uppercase only" caveat, and the reason for the checker to skip errors on `K.zed`. The language ends up with fewer rules than with B or C. No code in the repo uses a lowercase variant, so the cost is near zero.
    - Concern: Authors who write names in a caseless script must add a Latin first letter, and some may see that as a reason to stay away from the language.

- **Q2: `K.Upper` in an expression, and static methods named with an uppercase first letter** (4-2 for C, AI/ML and Minimalism for B; went to Phase D)

  > - A: Variants only; a miss is E0547. The spec says an uppercase static method is not reachable as `K.Upper`; a rule on static method names goes to a separate ticket (sys, web; plt fallback).
  > - B: Variants first, then static methods; E0547 only when both miss, never skipped; a rule on static method names goes to a separate ticket (aiml, devops, min).
  > - C: In this ruling, a static method name must not start with `Lu`/`Lt` (same kind of error), so `K.Upper` is variants only; a miss is E0547 (sys Phase A, plt B1).

  - **Systems:** C
    - Reasoning: The split only holds if it holds both ways. Under A, a declared static method can never be called, which is a quiet trap. Under B, `K.Upper` searches two tables again, the same dual lookup that caused the ICE. C costs nothing today (no uppercase-initial fn exists in src, lib, tests, examples or sections) and gives one table per first-letter class.
    - Concern: If A or B wins, the follow-up ticket may stall, and the gap stays for good. If C wins, the static-method rule may look out of scope and need a clear cross-reference.
  - **Web/Scripting:** C
    - Reasoning: Under A, a dev writes `fn Default() -> K` and it compiles. Then `K.Default()` reports "no such variant", and the declaration itself is a method nobody can call. That is a trap: the error shows up far from the mistake. C reports the problem at the declaration and gives a clean split by case in both directions, so a reader always knows what `K.X` means without looking it up. B brings back the guessing between two namespaces that caused the ICE.
    - Concern: A dev used to C# or Go writes PascalCase factory methods (`K.New()`) and has to rename them. The error must say why ("an uppercase name after `K.` is a variant").
  - **PLT:** C
    - Reasoning: Under A, a static method named `Zed` compiles but can never be called. A declaration that can never be referenced is a defect in the rules, and A just records it in the spec. Under B, `K.Upper` again means a variant or a method depending on what the type declares, which is the kind of meaning U exists to remove. C uses the same Lu/Lt test on the other half of the member namespace, so the split holds in both directions with no lookup order.
    - Concern: If A or B wins, the deferred ticket on static method names could stall. Then the spec would keep an unreachable declaration (A) or a lookup that depends on declarations (B).
  - **DevOps:** C (changed from my B1 position, B)
    - Reasoning: I checked: no `fn` in an impl block in src/, lib/, tests/ or examples/ starts with an uppercase letter, so B's "do not break working code" protects nothing. Given that, C is best for tooling: the error fires at the declaration, which is where the mistake is, and the case split holds both ways, so `K.Upper` and `K.lower` each search one table. A leaves an uppercase static method declared but unreachable, with no diagnostic where it is declared. That is the worst diagnostic surface of the three.
    - Concern: If A wins, the spec must still add a warning at the declaration of an uppercase static method. Otherwise the user only sees E0547 at a distant call site.
  - **AI/ML:** B
    - Reasoning: No existing call breaks, and no name becomes unreachable. A makes a declared `fn K.New()` impossible to call, so the spec would hold a declaration that cannot be used, and that confuses both models and users. C is the cleanest final state, but it decides a rule for method names that the panel did not deliberate; it belongs in its own ticket.
    - Concern: Until the follow-up ticket lands, `K.Upper` still needs two lookups, so a reader cannot tell a variant from a method by case alone in that rare spelling.
  - **Minimalism:** B
    - Reasoning: B keeps every existing static method reachable and adds no second naming rule; the ICE goes away because each miss still gets exactly one error. A makes a declared method silently unreachable, which is a worse hole than the one we close. C adds a rule for a case no code has; if it is needed, a separate ticket can add it later.
    - Concern: A variant and an uppercase static method with the same name on one type need the existing duplicate-member error to catch them, or the "variants first" order hides the method.

- **Q3: Help when `K.lower` finds no static method** (4-2 for A, PLT and Minimalism for B; went to Phase D)

  > - A: The help names a variant of `K` whose name matches ignoring case ("did you mean the variant K.Zed?"); help only, not machine-applicable (devops, web, sys, aiml).
  > - B: Only the existing nearest-name convention (ERROR_CATALOG Conventions), with the variants of `K` added to the candidates; no new help text in the spec (min).

  - **Systems:** A
    - Reasoning: The likely mistake is the case of the first letter (`K.zed` for `K.Zed`), and a case-insensitive match finds it with certainty, where a distance-based nearest name may not. Help only is right, because the fix changes the kind of member, not just the spelling.
    - Concern: The case-insensitive help and the nearest-name help may both fire and print two suggestions for one miss. The writer should say which one wins.
  - **Web/Scripting:** A
    - Reasoning: `Color.green` will be the most common slip under this rule. A help line that names `Color.Green` directly fixes it in one read. Plain nearest-name may rank a static method above the variant, or miss the variant because the case differs.
    - Concern: If the help also suggests a static method, the line gets noisy. Keep the variant line first and on its own.
  - **PLT:** B
    - Reasoning: The nearest-name convention already suggests `Zed` for `zed`, because they differ by one edit. Adding the variants of `K` as candidates gets the same result without new help text that applies to one case only. One help mechanism is simpler to specify and keeps the diagnostics consistent.
    - Concern: If several static methods are about as close as the variant, the variant may not be the first suggestion.
  - **DevOps:** A
    - Reasoning: The most likely `K.lower` miss is a Swift-style spelling of an existing variant. A help line that matches ignoring case names the exact repair. It costs one lookup and stays help-only, so nothing changes code without the user.
    - Concern: A type with both a variant `Zed` and a near-named static method may get two suggestions, so the spec should say the case-insensitive variant match comes first.
  - **AI/ML:** A
    - Reasoning: A case-insensitive match against the variants is the most common slip (`K.zed` for `K.Zed`), and it is worth naming directly. Help only is right: a method miss could also be a missing method, so the tool must not apply the fix automatically.
    - Concern: The help could compete with the nearest-name suggestion for a method, so the spec must say which line comes first.
  - **Minimalism:** B
    - Reasoning: The nearest-name convention already finds `K.Zed` from `K.zed` once the variants are candidates; a special help sentence for one case adds spec text with no new effect. Less text to keep in step with the catalog.
    - Concern: If the nearest-name distance does not treat a case-only change as close, the help may not suggest the variant, and A would have been needed.

- **Q4: When the rename fix for `LowercaseVariant` is machine-applicable** (6-0, for A)

  > - A: Only when the first character maps to exactly one `Lu`/`Lt` character and `K` has no variant or static member with the new name; the fix renames the declaration and every use (every module in the package for a `pub` type). Otherwise help text only. One mistake, one diagnostic: uses of the misnamed variant report nothing more.
  > - B: Machine-applicable with no condition (web W1, withdrawn in B1).

  - **Systems:** A
    - Reasoning: A fix the tool applies by itself must never produce code that does not compile. A collision with an existing member, or a first letter with no single uppercase form, breaks that guarantee. Renaming every use in the package keeps the fix to one step, and "one mistake, one diagnostic" keeps the output small.
    - Concern: A rename across modules for a `pub` type may touch files outside the user's view. Tools must show the full edit set before they apply it.
  - **Web/Scripting:** A
    - Reasoning: An automatic fix that collides with an existing name, or changes only the declaration, does damage while it looks safe. A applies the rename only when it is sound, applies it everywhere, and reports one error per mistake, not a cascade.
    - Concern: A rename across modules must also cover pattern uses and qualified `K.foo` uses. If the LSP or `--fix` misses one, the user is left with a half-renamed package.
  - **PLT:** A
    - Reasoning: A rename is only safe when the new name is new: if `K` already has a member with that name, the fix would bind uses to a different entity. Requiring exactly one Lu/Lt character as the uppercase form keeps the fix deterministic. Renaming every use, with no extra diagnostics at those uses, keeps it to one mistake and one fix.
    - Concern: Renaming every use of a `pub` type across all modules of a package means the fix depends on whole-package analysis, which a single-file LSP session may not have.
  - **DevOps:** A
    - Reasoning: A fix that is machine-applicable must leave code that compiles. A rename that collides with an existing member, or that misses uses in other modules of a `pub` type, breaks that promise. The LSP and `blink fix` both need the exact condition.
    - Concern: "Every module in the package" can miss code that depends on the package from outside, so the note must say that renaming a published `pub` variant changes the package's public API.
  - **AI/ML:** A
    - Reasoning: Agents apply machine-applicable fixes without review, so each fix must be safe. The conditions exclude `ß`, caseless letters and name clashes, which are exactly the cases where an automatic rename goes wrong. One diagnostic per mistake keeps the error output short for a model.
    - Concern: A package-wide rename of a `pub` variant still breaks other packages that depend on it, and the fix cannot see them.
  - **Minimalism:** A
    - Reasoning: A machine fix that collides with another member or picks among several uppercase forms would break code; the conditions are the smallest set that makes the fix safe. "One mistake, one diagnostic" keeps the output short.
    - Concern: A rename across every module of a package is a large edit for a tool to apply on its own, and the LSP must get every use right.

#### Phase D — Round 2 (Q2 and Q3)

Q1 and Q4 stayed decided. Q2 and Q3 had no 5-1 majority, so the moderator ran one focused round on them. Each seat read the six Phase C texts for Q2 and Q3, replied, and then voted again on a silent ballot with the Phase C options.

Fact from the moderator, from the repo: ERROR_CATALOG.md:28 (*Conventions*, Nearest-name suggestion): "A diagnostic that suggests a name compares the written name with its candidate names after it ignores case, `_` and `-`. If exactly one candidate is nearest, and it is near enough, the `help:` line names it. If two or more candidates are equally near, or no candidate is near enough, there is no suggestion."

Fact from DevOps (Phase C): "no `fn` in an impl block in src/, lib/, tests/ or examples/ starts with an uppercase letter".

Debate:

- **Systems:**

  > Systems, Phase D.
  >
  > Q2: I keep C. To aiml ("it decides a rule for method names that the panel did not deliberate"): C is on this ballot, and four seats argue for it, so the panel is deliberating it now. To min ("adds no second naming rule"): B adds a lookup order (variants first, then methods), and that order is also a rule. B is the dual lookup U was meant to remove, and it needs a duplicate-member check to stop a variant hiding a method. C costs zero migration and gives one table per first-letter class.
  >
  > Q3: I change my vote from A to B. The moderator's fact (ERROR_CATALOG.md:28) shows that nearest-name ignores case before it compares. So `zed` and `Zed` are distance 0. Under Q1 A plus Q2 C, no other member of `K` can tie at 0 (a lowercase method `zed` would be a hit, not a miss), so the variant is always the single nearest candidate. B gives the same help with no new text, and it removes my own concern about two help lines for one miss. The only change B needs is to add the variants of `K` to the candidate set.
  >
  > stable, ready to vote

- **Web/Scripting:**

  > **Q2: I stay with C.** Objection to aiml, "it decides a rule for method names that the panel did not deliberate": the panel is deliberating it now. It is on this ballot, with arguments from every seat. Objection to min, "adds no second naming rule": C uses the same Lu/Lt test that Q1 already adopted, applied to the other half of the same member namespace. That is one rule used in both directions, not a second rule. B keeps `K.Upper` meaning "variant or method, depending on what the type declares". That is the same kind of type-directed meaning that Q1 removed 6-0. A dev who writes `fn New()` gets the error at the declaration, which is the best place for it.
  >
  > **Q3: I change my vote from A to B.** The moderator's fact settles it. The nearest-name convention already ignores case, so `zed` and `Zed` compare as equal. Once the variants of `K` are candidates, the variant wins every time: a static method `zed` cannot also exist, or the lookup would have found it. So my A reasoning, "may ... miss the variant because the case differs", was wrong. B gives the same help line with no extra spec text, and it removes the question of which of two help lines comes first (sys, devops, aiml concerns).
  >
  > stable, ready to vote

- **PLT:**

  > PLT, Phase D. No vote change: Q2 C, Q3 B.
  >
  > Q2: C. min writes "C adds a rule for a case no code has". U, which min voted for, is also a rule for a case no code has (no lowercase variant exists). So that test cannot tell C from U. aiml writes "it decides a rule for method names that the panel did not deliberate". Q2 is that deliberation. Under B, `K.Upper` means a variant or a method depending on what the type declares, which is what U exists to remove.
  >
  > Q3: B. By the moderator's fact (ERROR_CATALOG.md:28), the nearest-name check ignores case, so `zed` and `Zed` count as an exact match. Then B gives the same help as A in every case: a single case-folded match is the only nearest candidate, and two (`Zed`, `ZED`) are a tie under both. Objections: web writes nearest-name may "miss the variant because the case differs", and sys writes "a distance-based nearest name may not". Both are false under :28. The ordering problem that sys, devops and aiml raise only exists under A, which adds a second help path. B has one, so nothing needs ordering.
  >
  > stable, ready to vote

- **DevOps:**

  > DevOps D.
  >
  > Q2: I keep C. Objection to aiml, "it decides a rule for method names that the panel did not deliberate": C was on the ballot, and we have now debated it in B1, C and D. That is deliberation. Under C, min's concern ("a variant and an uppercase static method with the same name ... the 'variants first' order hides the method") cannot happen, because no such method can exist. No code uses an uppercase static method, so C costs nothing and removes the only two-table lookup that is left.
  >
  > Q3: I change to B. The moderator's fact settles it. Nearest-name already ignores case, so `zed` and `Zed` are at distance 0, and the convention suggests `Zed` alone. My Phase C concern (two help lines, and which one wins) goes away with one mechanism: the convention gives one suggestion or none. One condition: the help must write the suggestion qualified, `K.Zed`. A bare `Zed` hides that the fix changes a method call into a variant. That is a wording rule in the catalog, not new spec text.
  >
  > stable, ready to vote

- **AI/ML:**

  > **Q2: I change from B to C.** My reason for B was "no existing call breaks". devops removed that reason: "no `fn` in an impl block in src/, lib/, tests/ or examples/ starts with an uppercase letter". With nothing to protect, C is best for models. The same Lu/Lt test applies to both halves of the member namespace, so a model knows what `K.X` means from the token alone, with no lookup order to learn. The error fires at the declaration, which is where the mistake is. My scope objection is weak: the ticket is about the variant and member namespace, and C finishes that split instead of handing it to another ticket.
  >
  > **Q3: I change from A to B.** The moderator fact settles it. The nearest-name convention already "ignores case, `_` and `-`", so `zed` and `Zed` compare as equal. Under C, no static method can be named `Zed`, so the variant is the one nearest candidate. B gives the same help as A with no new spec text, and it also removes my Phase C concern about which of two help lines comes first. One help mechanism is easier for a model to learn than two.
  >
  > stable, ready to vote

- **Minimalism:**

  > **Q2: I change my vote from B to C.** Devops checked that no uppercase-initial static method exists. So the main reason for B, "keeps every existing static method reachable", protects nothing. Under C the checker has no lookup order, no hidden-method case, and no need for a follow-up ticket. The rule is one sentence on the same Lu/Lt test. C has less total rule surface than B.
  >
  > **Q3: I stay on B.** ERROR_CATALOG:28 settles my Phase C concern. Nearest-name ignores case, so `zed` vs `Zed` is distance 0 and the help names the variant. Option A gives the same output through a second help mechanism. Sys, devops and aiml all worry that A and nearest-name both fire and need a priority rule. B has no such conflict.
  >
  > Objection: web says "Plain nearest-name may ... miss the variant because the case differs". That is false per ERROR_CATALOG:28. Under C, no static method can be uppercase, so a case-insensitive exact match on a variant is the nearest candidate, except in a tie with a member that differs only by `_` or `-`.
  >
  > stable, ready to vote

Re-vote:

- **Q2: `K.Upper` in an expression, and static methods named with an uppercase first letter** (6-0, for C)

  > - A: Variants only; a miss is E0547. The spec says an uppercase static method is not reachable as `K.Upper`; a rule on static method names goes to a separate ticket (sys, web; plt fallback).
  > - B: Variants first, then static methods; E0547 only when both miss, never skipped; a rule on static method names goes to a separate ticket (aiml, devops, min).
  > - C: In this ruling, a static method name must not start with `Lu`/`Lt` (same kind of error), so `K.Upper` is variants only; a miss is E0547 (sys Phase A, plt B1).

  - **Systems:** C
    - Reasoning: With the same Lu/Lt test on both halves of the member namespace, `K.Upper` and `K.lower` each search one table and need no lookup order. That removes the dual lookup that caused the ICE, and the error fires at the declaration, where the mistake is. Migration is zero: no fn in the repo starts with an uppercase letter.
    - Concern: Users of C# or Go who write PascalCase factory methods (`K.New()`) will need the error to say why the rule exists, or it will feel arbitrary.
  - **Web/Scripting:** C
    - Reasoning: A dev who writes `fn New() -> K` gets the error at the declaration, which is where the mistake is. Under A it shows up as a confusing E0547 at a distant call. Under B, the meaning of `K.Upper` again depends on what the type declares. C applies the Q1 test to the other half of the member namespace, so `K.X` is readable by case alone. No code in the repo has an uppercase static method, so nothing breaks.
    - Concern: Devs coming from C# or Go will write PascalCase factories, so the error must say why: "an uppercase name after `K.` is a variant".
  - **PLT:** C
    - Reasoning: Under C, the same Lu/Lt test splits the member namespace in both directions. `K.Upper` is always a variant and `K.lower` is always a static method, and no declaration elsewhere can change which one a name means. A leaves a static method that is declared but can never be called. B makes the meaning of `K.Upper` depend on what the type declares, which is what U removes. No existing code breaks.
    - Concern: A user from C# or Go who writes `fn New()` gets an error, and that error must explain why ("an uppercase name after `K.` is a variant").
  - **DevOps:** C
    - Reasoning: The error fires at the declaration, where the mistake is, not as an E0547 at a call site far away. The case split then holds both ways, so `K.Upper` searches variants only and `K.lower` searches static methods only, with no lookup order and no two-table search. No static method in the repo starts with an uppercase letter, so the rule breaks nothing.
    - Concern: A user who comes from C# or Go and writes `K.New()` must get a message that says why: an uppercase name after `K.` is a variant.
  - **AI/ML:** C
    - Reasoning: One Lu/Lt test decides both halves of the member namespace, so a model knows from the token alone that `K.Upper` is a variant and `K.lower` is a static method. No uppercase static method exists in the repo, so the rule breaks nothing. The error fires at the declaration, where the mistake is, not at a distant call.
    - Concern: A model trained on C# or Go writes `K.New()` factory methods, so the error must say why ("an uppercase name after `K.` is a variant") and give the lowercase rename.
  - **Minimalism:** C
    - Reasoning: No static method in the repo starts with an uppercase letter, so B protects no real code and keeps a lookup order and a case where a variant hides a method. C reuses the Lu/Lt test that Q1 already adopts, so each member table is chosen by the first letter and the checker has one lookup with one error owner. Compared with B, C has less total rule surface and needs no follow-up ticket.
    - Concern: A user from C# or Go who writes `fn New()` gets an error at the declaration, so the message must say why an uppercase member name after `K.` is a variant.

- **Q3: Help when `K.lower` finds no static method** (6-0, for B)

  > - A: The help names a variant of `K` whose name matches ignoring case ("did you mean the variant K.Zed?"); help only, not machine-applicable (devops, web, sys, aiml).
  > - B: Only the existing nearest-name convention (ERROR_CATALOG Conventions), with the variants of `K` added to the candidates; no new help text in the spec (min).

  - **Systems:** B
    - Reasoning: The nearest-name convention (ERROR_CATALOG.md:28) ignores case before it compares, so `zed` matches `Zed` at distance 0. Under Q1 A and Q2 C, no other member of `K` can tie. So adding the variants of `K` to the candidates gives the same help as A with no new spec text, and only one suggestion mechanism.
    - Concern: If Q2 C does not win, an uppercase static method could tie with the variant, and then the convention gives no suggestion.
  - **Web/Scripting:** B
    - Reasoning: The nearest-name convention already ignores case (ERROR_CATALOG.md:28), so with the variants of `K` as candidates, `K.zed` suggests `K.Zed` every time. B gets the same help line as A with no new spec text and no question of which of two lines comes first.
    - Concern: The help line should name the candidate's kind ("the variant `K.Zed`"), or a dev may not see that the fix changes a method call into a variant.
  - **PLT:** B
    - Reasoning: ERROR_CATALOG.md:28 says the nearest-name check ignores case, so `zed` finds `Zed` as an exact match. B gives the same help as A in every case, through one help path. A adds a second path that the writer must then rank against the first, which adds rules but gives the user nothing new.
    - Concern: If the catalog convention ever stops ignoring case, B loses the case-only suggestion, so the spec should keep :28 as is.
  - **DevOps:** B
    - Reasoning: The nearest-name convention (ERROR_CATALOG.md:28) already ignores case, so `K.zed` gets the suggestion `Zed` with no new help text. One mechanism gives one suggestion or none, so two help lines can never compete. The help must write the suggestion qualified, `K.Zed`, so the user sees that the fix turns a method call into a variant.
    - Concern: A tie that is equally near after ignoring case, `_` and `-` (for example a static method `z_ed`) gives no suggestion at all, and the user loses the help that matters most.
  - **AI/ML:** B
    - Reasoning: The nearest-name convention already ignores case, so `zed` and `Zed` compare as equal, and under Q2 C the variant is the only candidate that close. B gives the same help as A with no new spec text and no second help line to order. One help mechanism is easier for a model to learn.
    - Concern: If a later change to the convention stops ignoring case, the case-only slip loses its suggestion, so the writer should add a test that pins `K.zed` to "did you mean `K.Zed`".
  - **Minimalism:** B
    - Reasoning: ERROR_CATALOG:28 says nearest-name ignores case, so `K.zed` already suggests `K.Zed` once the variants are candidates. A gives the same result through a second help mechanism, and then the spec needs a rule for which help wins. One mechanism is less text and stays consistent with every other suggestion.
    - Concern: If a static method differs from the variant only by `_` or `-`, the tie removes the suggestion where A would still name the variant.

### Final Spec

```blink
type Shape {
    circle(Float)                        // error[E0555]: variant name must start with an uppercase letter
                                         // help: rename the variant to `Circle`
    Square(Float)
}

type Level { Low, High }

fn Level.parse(s: Str) -> Level? { /* ... */ }
fn Level.Default() -> Level { Level.Low } // error[E0556]: type-scoped function `Default` must not start with an uppercase letter
                                          // note: an uppercase name after `Level.` is a variant or a constant, never a function
                                          // help: rename the function to `default`

fn describe(l: Level) -> Str {
    match l {
        Low => "low"
        other => "not low"               // a binding: no variant starts with a lowercase letter
    }
}

fn main() {
    let a = Level.Hihg                   // error[E0547]: `Level` has no variant `Hihg`
    let b = Level.high                   // error: `Level` has no member `high`; the help suggests `Level.High`
}
```

- A variant name must start with a Unicode `Lu` or `Lt` letter. `x`, `_x`, `_X` and a name whose first letter has no case are `LowercaseVariant` (E0555) at the declaration, with the message "variant name must start with an uppercase letter".
- In a refutable pattern, a bare name that does not start with an uppercase letter never names a variant. With no payload it is a binding. With a payload it is E0547 when the type at that position is an enum, and E0308 when it is not.
- The name after `T.` in `fn T.name` must not start with `Lu` or `Lt` (`UppercaseTypeScopedFn`, E0556). The error says that an uppercase name after `K.` is a variant and gives the lowercase name.
- `K.Upper` never names a function. On an enum, a miss is E0547. `K.lower` never names a variant, so it never gets E0547.
- A miss on `K.lower` uses only the nearest-name convention (ERROR_CATALOG.md *Conventions*), with the variants of `K` among the candidates. The spec adds no other help text.
- The rename fix is machine-applicable only when the first character maps to exactly one `Lu`/`Lt` character and `K` has no variant or static member with the new name. It renames the declaration and every use, in every module of the package for a `pub` type. Otherwise the help names the rename. One mistake gives one diagnostic: uses of the misnamed variant report nothing more.

Writer's reading, not voted:

- A type-scoped constant (`const T.NAME`, such as `Float.INF`) stays reachable under either case. `K.Upper` names a variant or a constant; E0547 applies only when `K` is an enum and has neither.
- The Q2 rule also covers an associated function that a trait declares, because a call to it has the same `K.name` form.
- New codes: E0555 `LowercaseVariant` and E0556 `UppercaseTypeScopedFn`, two sibling codes, because they report different declarations.

Concerns the panel raised, not added as spec text (Q3 forbids new help text):

- The help names the kind and writes it qualified ("the variant `K.Zed`") (Web, DevOps).
- Two candidates that differ only by `_` or `-` tie, so no suggestion appears (Minimalism, DevOps).
- The nearest-name convention must keep ignoring case, or Q3 loses the case-only suggestion (PLT, AI/ML).
