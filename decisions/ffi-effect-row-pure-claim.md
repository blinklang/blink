[< All Decisions](../DECISIONS.md)

# FFI Effect Row and Pure Claim — Design Rationale

**Question.** §9.1 spelled the effects of every `@ffi` decl as an annotation, `@effects(IO)`, but the compiler reads only the `!` row in the signature: an `@ffi` decl with `@effects(IO)` and no `!` fails with `FfiNoEffects` (E0802), and `@effects` on any other fn is accepted and ignored. The only compiler trace of `@effects` was a slot in the formatter's annotation ordering. The earlier ruling [@trusted and FFI: not an effect](trusted-ffi-not-an-effect.md) kept E0802 for an `@ffi` decl with no row and left the spelling of the explicit pure claim open, with one rule: it must not read as an omitted row.

**Already decided (from that ruling).** FFI is not an effect (`! FFI` is E0538 `UnknownEffect`). An `@ffi` decl must carry an explicit row. No machine-applicable fix may write a claim. The lib/std migration (118 decls, all `! FFI` today) goes decl by decl, not by sed.

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated
in independent-proposal → debate → vote rounds.

#### Phase A — Independent proposals

##### Systems
**What the hardware sees.** Rows are erased. `! IO`, `@effects(IO)` and an explicit pure claim all compile to the same direct C call. Nothing in this ticket costs anything at runtime, so the only thing it settles is what the source tells a reader and the checker. That points to one syntax.

###### Proposal S1 (preferred): `!` is the language, `@effects` is dead syntax, and the pure claim is `! ()`

```blink
@ffi("sqlite3", "sqlite3_open")
@trusted(audit: "DB-003")
fn sqlite3_open(filename: Ptr[U8], db: Ptr[Ptr[Void]]) -> Int ! IO

@ffi("c", "strlen")
@trusted(audit: "LIBC-007")
fn c_strlen(s: Ptr[U8]) -> Int ! ()

@ffi("c", "clock_gettime")
@trusted(audit: "LIBC-012")
fn c_clock_gettime(clk: Int, ts: Ptr[Void]) -> Int ! Time.Read
```

Rules:
1. An effect row is written only with `!` in the signature, on @ffi decls and everywhere else. §9.1, §9.1.1, §9.1.3, §9.1.4, the annotation table row and the two §4 cross-references move to `!` (19 sites).
2. `! ()` is the explicit empty row. It is valid only on an `@ffi` decl. On an ordinary fn it is an error, because "no row" already means the compiler proved the body pure, and two spellings of that would be noise.
3. `@effects(...)` becomes a targeted error: "effects go in the signature: write `! IO` or `! ()`". The formatter loses its `@effects` ordering slot. No autofix (Q3 holds). The help text must name both choices.
4. The E0802 help line drops the stale "add `! FFI`" and names a real effect or `! ()`.

Why `! ()` and not something else:
- It cannot be mistaken for an omitted row. There is a `!` token, which is what the eye and `rg '! '` look for.
- It parses without ambiguity. After `!`, `(` cannot start an effect name. `! {}` would clash with a body brace, and a bare `!` already fails to parse (fact 4).
- `()` already means "empty" in Blink (unit, empty param list). No new keyword, no fake effect name like `Pure`, which would repeat the mistake of `FFI`.

**Why this matters for the function type.** If `c_strlen` is used as a value, its type is `fn(Ptr[U8]) -> Int`, and a row must live in that type (§4.15). The row is a type-level fact, so it belongs in the type syntax. An annotation is not part of the type. Under `@effects`, the checker would have to copy an annotation into the fn type, so one fact would have two places it could come from. That is the same kind of split this project is removing from codegen (tid as the only authority).

**Tradeoffs.**
- For: one effect syntax across the language (Minimalism's concern is met). The row and the type agree by construction. Greps and audit tools need one pattern. The 118-decl lib/std migration edits the row that is already there (`! FFI` becomes a real row or `! ()`), so each site is a one-token decision and not a move from one syntax to another.
- Against: the claim on an @ffi decl looks the same as a proven row on an ordinary fn. I accept this. `@ffi` and `@trusted(audit:)` sit directly above the signature and already say "assumed". Q1 put the assumption in the decl, not in the row syntax.
- Risk: agents may try `! ()` on ordinary fns. Rule 2 makes that a hard error with a clear message, not silent acceptance.

###### Proposal S2 (fallback, I vote against it): `@effects` is the only form on @ffi decls

```blink
@ffi("c", "strlen")
@trusted(audit: "LIBC-007")
@effects()
fn c_strlen(s: Ptr[U8]) -> Int
```

This marks an assumed row with its own syntax, so "claimed" and "proven" look different. The cost is two effect syntaxes, an annotation that the checker must lower into the fn type, `! IO` on an @ffi decl becoming an error, and a change to all 118 decls in a second syntax. That cost buys only a visual cue, and `@trusted` already gives one. I reject it.

###### Also needed
Unknown annotations are accepted silently today (`@bogus(IO)`). That is a separate bug, and it should go on a ticket, because it is how `@effects(IO)` came to sit in the spec unnoticed.

###### Cross-language note
- **Haskell:** `foreign import ccall "strlen" c_strlen :: CString -> CSize`. Leaving out `IO` is the pure claim. This is the "omitted row means pure" mistake that Q2 rejected, and it is a well-known source of bugs.
- **Rust 2024:** `unsafe extern "C" { pub safe fn sqrt(x: f64) -> f64; }`. Each item states its claim explicitly with a keyword. This is the same idea as `! ()`.
- **Koka:** writes the empty effect row as `<>` (alias `total`) in the type, not in an annotation. This is the closest model for S1.

##### Web/Scripting
The signature `!` row is the language and `@effects` is dead syntax. A pure binding is spelled `! ()`, read as "an empty effect list".

**Proposal W1: `!` is the language, and `! ()` is the pure claim**

**1. Which form.** Effects go after `!` in the signature, for every fn, foreign or not. A JS or Python developer learns one rule in §4.2: "effects go after `!`". If `@effects(...)` also existed, it would be a second place for the same fact. The first Stack Overflow question would be "which one do I use?", and the second would be "why does `@effects` work here but not there?" Today it compiles to nothing on any fn, so it already fails the five-minute test.

**2. The explicit pure claim: `! ()`, the empty row literal.**

```blink
@ffi("sqlite3", "sqlite3_open")
@trusted(audit: "DB-003")
fn sqlite3_open(filename: Ptr[U8], db: Ptr[Ptr[Void]]) -> Int ! IO

@ffi("c", "strlen")
@trusted(audit: "LIBC-001")
fn c_strlen(s: Ptr[U8]) -> Int ! ()

@ffi("c", "explicit_bzero_noop")
@trusted(audit: "LIBC-002")
fn c_touch(p: Ptr[U8]) ! ()
```

Why this spelling:
- **It does not read as an omitted row.** You can see a `!` token and you can see its contents.
- **`()` already means "nothing" in Blink**, as the unit type. "Effects: none" carries over with no new word.
- **No fake effect name.** `! Pure` or `! None` would repeat the `! FFI` mistake Q1 just removed: a label in the row that names no effect, plus a special case in E0538.
- **It avoids the taken forms.** `! _` is the wildcard. A bare `!` reads as a typo, and the parser rejects it today ("expected IDENT").
- **A void pure fn stays clear.** In `fn c_touch(p: Ptr[U8]) ! ()`, the `!` marks it as a row, not a return type.
- **Measured today:** `-> Int ! ()` is a parse error ("expected IDENT, got ("). So this is a small grammar addition and breaks no code.

**Scope.** `! ()` is legal on every fn and every fn type, and means exactly what no row means. It is required only on `@ffi` decls. This keeps one grammar rule with no context-dependent parsing. A learner never has to ask "why is `! ()` illegal here?"

For the 90% case (ordinary fns), a style lint flags a redundant `! ()` on a non-`@ffi` fn. Its fix deletes it, and that fix is fine because Q3 covers only `@ffi` claims. The result is one idiomatic way to write pure code, plus one required way to *claim* purity at the FFI edge.

**3. What happens to `@effects`.**
- **Spec:** rewrite the 17 occurrences in sections/07 (§9.1, 9.1.1, 9.1.3, 9.1.4) to `!` rows. Delete the annotation table row "`@effects(list)` | fn (with @ffi)". Remove the `@effects` slot from the canonical ordering (sections/07 and DECISIONS.md line 13). Fix the 2 cross-refs in sections/04 to point at the §9.1 row rule. Replace the §9.1 sentence "The spelling … is fixed with the `@effects` implementation" with the `! ()` rule.
- **The ruling's Final Spec example** that uses `@effects(DB)` gets the same rewrite.
- **Diagnostic for `@effects` specifically, not a general policy on unknown annotations.** Today someone copies an old example, writes `@effects(IO)`, and gets E0802 with no hint why. E0802 notices an `@effects(...)` annotation on the decl and adds a note.
- **New E0802 text** (no autofix, per Q3):
  ```
  error[FfiNoEffects]: foreign fn 'c_strlen' must state its effects
    help: write the effects the C code has after the return type, e.g. `-> Int ! IO`,
          or claim it is pure with `! ()`. The compiler cannot check this claim;
          it is recorded under the @trusted audit key.
    note: `@effects(...)` is not Blink syntax; effects go after `!`
  ```
  The stale "add `! FFI`" text goes away.
- **lib/std:** a decision for each of the 118 decls (DevOps criterion), not a sed job.

**Cross-language note.** The closest match is TypeScript `.d.ts` files and Python `.pyi` stubs. Declarations there have no body to infer from, so they state types outright. That is the same situation as `@ffi`, and the outright form uses the *same syntax* as ordinary code, not a separate annotation. Koka writes an explicit empty effect row as `<>`, which is prior art for a distinct "empty row" literal next to an omitted one.

**Tradeoffs**
- (+) One effect syntax across the language. The error message teaches the fix in one line, and agents copying any example land on the right form.
- (+) Grep-friendly: `! ()` on `@ffi` lists every pure claim for audit.
- (-) `! ()` is mildly unusual and needs one line in §4.2.
- (-) A pure claim is easy to type, so the explicit spelling slows an agent down but does not stop it. The audit key and the no-autofix rule do that work.
- (-) Ordinary fns gain a second, linted-away way to say pure. I accept that cost to avoid grammar that changes with context.

##### PLT
**PLT proposal: one row grammar, an explicit empty row, and `@effects` removed**

**P1. `!` is the language. `@effects(...)` is dead syntax and gets deleted.**

A fn's row is part of its type. §4.2 says `fn(Int) -> Int` and `fn(Int) -> Int ! IO` are different types. Annotations are metadata about a decl, and they can never appear inside a function type. If an @ffi decl put its row in `@effects(IO)`, the decl's type would be split across two grammars. The same type, written as a fn-type value (`let f: fn(Ptr[U8]) -> Int ! IO = sqlite3_open`), would then use a third form.

One typing judgement should have one surface form. The fix goes in the spec:

- Rewrite all 17 `@effects` sites in sections/07.
- Rewrite the 2 cross-references in sections/04.
- Drop the annotation-table row and the formatter ordering slot.

`@effects` itself should then fail to compile. The diagnostic's help line points to `!` and offers no autofix (Q3). It should not fall through to the general "unknown annotation is silently accepted" behaviour (fact 4). That silence is its own soundness bug and needs its own ticket.

**P2. The pure claim is spelled `! ()`, the explicit empty row.**

```blink
@ffi("c", "strlen")
@trusted(audit: "LIBC-007")
fn c_strlen(s: Ptr[U8]) -> Int ! ()

@ffi("sqlite3", "sqlite3_open")
@trusted(audit: "DB-003")
fn sqlite3_open(filename: Ptr[U8], db: Ptr[Ptr[Void]]) -> Int ! IO

@ffi("c", "srand")
@trusted(audit: "LIBC-012")
fn c_srand(seed: Int) ! Random      // unit return: row follows params, as §4.2
```

Typing rule. Under `@trusted(audit: K)`, an @ffi decl `fn f(x̄: τ̄) -> τ ! ρ` adds the postulate `f : τ̄ → τ ! ρ` to Γ, with no body to check. `ρ` must be present in the syntax: E0802 fires when the row is absent, not when it is empty. `! ()` denotes ⟨⟩, the empty row, and it is the same ⟨⟩ that unification and the §4.5 subset check already use. No new row label, kind or law is added; this is only concrete syntax for a value the row algebra already has.

Why `()`:

1. It is unambiguous. After `!`, the parser expects IDENT or `_`, and `(` starts neither. `! {}` is ruled out because it collides with a `{}` body.
2. It reads as "an empty list of effects". It cannot be mistaken for an omitted row, which was the concern every panelist raised on Q2.
3. It composes. `! ()` is legal wherever a row is legal, including fn types, and there it means exactly what omission means: `fn(Int) -> Int ! ()` ≡ `fn(Int) -> Int`. A grammar that allows the empty row only on @ffi decls would make row syntax depend on context. That is a smell, and it breaks the rule that you can copy a decl's signature into a fn-type position.

**Two-ways cost (Minimalism's concern).** On a checked fn, `! ()` is redundant, because the compiler proves purity. The formatter normalises it away everywhere except on @ffi decls, which keeps one canonical form per context. The formatter may delete an empty row on a checked fn because that writes no claim. It must never add one, so this is consistent with Q3.

**Rejected: `! pure` (keyword or contextual word).**

- It looks like an effect label, so `! pure, IO` and `! Pure` have to be banned by special rules.
- A learner, or an AI, will read `pure` as a capability name.
- It adds a word for a value (⟨⟩) that the algebra already names.

It is weaker than `! ()` on soundness-of-reading. It is my second choice only.

**Tradeoffs**
- (+) The row grammar stays the single source of a fn's type. Annotations stay non-semantic, so dropping one can never change a type.
- (+) "The row is absent" and "the row is empty" become two different syntax trees. The checker can tell them apart, and so can `blink audit`, which can list "declared pure" bindings as their own category.
- (−) `! ()` is new surface on checked fns, where it means nothing extra. The formatter rule contains this, but the spec must say so in one line.
- (−) All 118 lib/std decls change. That is already required, and each one is a decision (DevOps criterion). `! ()` makes the pure decisions easy to grep and audit as their own category.

**Cross-language**
- **Koka:** `extern` decls carry their effect in the type, and the empty row is written `<>` (with `total` as an alias). That is the same design: an explicit empty row, inside the type grammar.
- **Haskell:** `foreign import ccall "strlen" c_strlen :: CString -> CSize` claims purity by the absence of `IO`. That is the failure mode Q2 forbids: purity is asserted by silence, and the result is the `unsafePerformIO` folklore.
- **OCaml:** `external` records no effects at all, which is exactly the gap this ruling closes.

**E0802 help-text fix (stale today):** "state the foreign code's real effects (`! IO`, `! Net`, ...) or claim purity with `! ()`". Purely advisory, with no machine-applicable fix (Q3).

##### DevOps/Tooling
###### Proposal D1 (primary): `!` is the only effect syntax. Delete `@effects`. Spell the pure claim `! Pure`.

```blink
@ffi("sqlite3", "sqlite3_open")
@trusted(audit: "DB-003")
fn sqlite3_open(filename: Ptr[U8], db: Ptr[Ptr[Void]]) -> Int ! IO

@ffi("c", "strlen")
@trusted(audit: "LIBC-007")
fn c_strlen(s: Ptr[U8]) -> Int ! Pure
```

**Why `!` wins:**
- The type checker, the LSP and the formatter already work on `!`. `@effects` does nothing today; the compiler only knows it as a slot in the formatter's ordering.
- If we keep `@effects`, every tool needs a second code path: hover, signature help, "find fns with effect X", and the function type a caller sees.
- One spelling means one rule: hover shows the same row on the declaration and on the call site.

**`Pure` rules:**
- `Pure` is a reserved row name, not an effect. It is the explicit empty row.
- It is legal only on an `@ffi` decl. Anywhere else it is an error, so ordinary code does not get a second way to say pure. This answers Minimalism's concern.
- It can't be mixed: `! Pure, IO` is an error.

**Diagnostics I want:**

```
error[E0802]: FFI function 'c_strlen' has no effect row
  --> db.bl:3:1
   |
 3 | fn c_strlen(s: Ptr[U8]) -> Int
   |                               ^ row missing
   = note: the row on an @ffi decl is a claim recorded under audit key "LIBC-007"
   = help: state the claim: `! Pure` if the C function has no side effects,
           else the effects it has (e.g. `! IO`, `! Time.Read`)
   = note: no fix is offered; each row is an audit decision
```

```
error[E0xxx]: `@effects` is not an annotation
 3 | @effects(IO)
   | ^^^^^^^^^^^^
   = help: effects go in the signature: `fn sqlite3_open(...) -> Int ! IO`
```

- The `@effects` help is display text only, never machine-applicable (Q3), even though moving the row would keep the claim the author wrote.
- `! Pure` outside `@ffi`: "`Pure` claims a foreign fn has no effects; an ordinary fn without `!` is already pure. Remove `! Pure`."
- `! FFI`: keep E0538, and replace the stale "add `! FFI`" help in E0802.

**Tooling:**
- `blink fmt` keeps `! Pure` as written and never adds or removes a row. Remove the `@effects` slot from the canonical annotation order in DECISIONS.md.
- The LSP offers `Pure` after `!` only inside an `@ffi` decl.
- Audit query: `rg '! Pure'` lists every purity claim, and the audit key sits on the line above it. A missing row is a hard error, so "unaudited pure" has no place to hide.

**Migration:** all 118 lib/std decls need a person to pick each row by hand. `! Pure` makes that choice visible in review, which meets the earlier acceptance criterion that each row is a decision.

**Cross-language:**
- Koka writes `total`.
- Rust (2024 edition) needs `unsafe extern` blocks and lets you mark single items `safe`, a keyword per item rather than a separate annotation.
- In both, the claim lives in the signature, not in metadata.

###### Proposal D2 (fallback): `! ()` for the empty row

- Same as D1, but no new reserved name.
- Cost: `()` already means unit, so `-> Int ! ()` reads like "returns unit effect". It is hard to search for. In diagnostics it renders as `! ()`, which users will take for a typo.
- I rank it below D1.

###### Rejected: keep `@effects(...)`, or `@ffi(..., pure)`

- Either one puts the row in two places, and hover, function types and transitivity need a translation layer.
- `@ffi(..., pure)` does keep the claim next to the audit key, but it splits the language's one effect row across syntax kinds.

###### Side finding (separate friction ticket, not this ruling)

The compiler silently accepts unknown annotations (`@bogus(IO)`, and `@effects` on a non-FFI fn). That silence is why §9.1 drifted. Unknown annotations should raise an error. Without that, any annotation we delete stays dead text in user code with no diagnostic.

**Spec fix:**
- Rewrite the ~17 `@effects` uses in sections/07 to `!`.
- Remove the `@effects(list)` row from the annotation table.
- Repoint the 2 cross-references in sections/04 to "§9.1 effect rows on @ffi decls".
- Fix the Final Spec example in decisions/trusted-ffi-not-an-effect.md, which uses `@effects(DB)`, or add a note there that this ruling replaces it.

**Compiler follow-ups:**
- E0802 help text: remove "add `! FFI`" and use the text in the diagnostic above.
- New error for `@effects`.
- `! Pure` reserved, legal only on @ffi.
- Remove the `@effects` slot from the formatter's annotation order.

##### AI/ML
I recommend `!` as the only effect syntax, with `! pure` as the explicit pure claim on `@ffi` decls. `@effects(...)` should be removed from the language and the spec.

###### Proposal P1: `!` is the language, `@effects` is dead syntax

`@effects(...)` is syntax the spec never migrated off. Delete it from §9.1, §9.1.1, §9.1.3 and §9.1.4, from the annotation table and from the two §4 cross-references. Also delete its slot in the formatter's ordering. An `@ffi` decl writes its claim in the same place every other fn writes its row: after the return type.

```blink
@ffi("sqlite3", "sqlite3_open")
@trusted(audit: "DB-003")
fn sqlite3_open(filename: Ptr[U8], db: Ptr[Ptr[Void]]) -> Int ! IO

@ffi("c", "clock_gettime")
@trusted(audit: "TIME-001")
fn c_clock_gettime(id: Int, ts: Ptr[Void]) -> Int ! Time.Read

@ffi("c", "strlen")
@trusted(audit: "STR-002")
fn c_strlen(s: Ptr[U8]) -> Int ! pure
```

**Pure claim: `! pure`.** It is a reserved word, written in lowercase, that is only legal as the whole row. Rules:
- `! pure` is legal only on an `@ffi` decl. Anywhere else it is an error with the help line "a fn with no `!` is already pure; remove `! pure`". This keeps one way to write "pure" on ordinary fns.
- `! pure, IO` is an error: it is a contradiction, not a row.
- An `@ffi` decl with no `!` stays E0802. Its help line names both choices: "declare what the foreign code does (`! IO`, `! Net`, ...) or claim `! pure`". It offers no autofix (Q3).

**Why the lowercase word.** Every effect name is capitalized, so an agent cannot mistake `pure` for an effect. `! _` already sets the pattern of a lowercase, non-effect form after `!`. `Pure` in capitals would invite `! Pure, IO`. An empty row is also no good: `fn f() -> Int ! {}` collides with the body brace, and `fn f() ! ()` reads as the unit type. Both look like an omitted row, which the earlier ruling forbids.

**Stale-spelling diagnostic.** Today `@effects(IO)` on a non-FFI fn, and any `@bogus(...)`, is accepted with no warning. For an AI this is the worst case. Models trained on the old §9.1 will keep writing `@effects(IO)` and get no correction. On a non-FFI fn the annotation is silently ignored. On an `@ffi` decl it fails with a message that does not mention `@effects`.
- Add a dedicated error for `@effects(...)`: "`@effects` is not Blink syntax; write the row after the return type: `-> Int ! IO`". No autofix on `@ffi` decls, so Q3 holds. Moving an author's claim is still a tool writing a claim.
- Separately, file a ticket for an unknown-annotation error. That is a general gap and outside this scope.

###### Tradeoffs from the AI/ML seat

- **Decision points.** P1 adds none to ordinary code. The rule an AI learns stays "effects go after `!`, everywhere". `@ffi` adds one fact: you cannot omit the row, and pure is written `! pure`. Keeping `@effects` adds a fork on every FFI decl, and the training data would mix both forms. Models reproduce mixed corpora as a coin flip.
- **Tokens.** `! pure` is about 2 tokens on the signature line. `@effects()` is about 4 tokens plus a whole line. On the 118 lib/std decls, P1 is shorter and the row stays on the same line as the signature. Grep and `blink query --fn` output then show the claim with no extra context.
- **Learnability from the spec alone.** One sentence covers it: "Rows are proven, except `@ffi` rows, which are claims; a pure claim is `! pure`." The fn-type and trait-method sections need no change.
- **Risk.** An agent may learn the habit "add `! pure` until it compiles", which is the same failure as the old `! FFI` habit. Two things limit this:
  - It is only legal on `@ffi`, so it never spreads into ordinary code.
  - The audit inventory lists "declared pure" bindings as their own category (DevOps's earlier point), so a false pure claim is easy to find.
- **Cost.** About 19 spec edits and one formatter slot removed. lib/std must be rewritten anyway, one decision per decl, as the DevOps criterion requires.

###### Cross-language note

- Rust 2024 `unsafe extern` blocks need each item marked `safe` or `unsafe`. That is the same shape: an explicit lowercase claim word where silence used to mean something.
- Koka spells the pure claim `total` or the empty row `<>`. Unison uses `->{}`. Both show that an empty-row form works only when it cannot be mistaken for an omitted row, and in Blink both candidates fail that test.

###### Fallback P2 (if the panel rejects a new reserved word)

Keep `!` only and spell the pure claim `! _`. I oppose this. `_` already means "forward the effects" (§4.15.2). Giving it a second meaning on `@ffi` decls creates exactly the context-dependent meaning that agents get wrong. I list it only to make clear that P1 is the minimal clean option.

**Vote intent:** P1.

##### Minimalism
**Position.** `!` is the language. `@effects(...)` is dead syntax: it predates the move of the effect row into the signature, and the compiler never read it. Delete it. For the pure claim, use the smallest addition to the `!` grammar that cannot read as a missing row.

###### M1 (first choice): delete `@effects`, spell the pure claim `! ()`, allow it only on `@ffi`

```blink
@ffi("sqlite3", "sqlite3_open")
@trusted(audit: "DB-003")
fn sqlite3_open(filename: Ptr[U8], db: Ptr[Ptr[Void]]) -> Int ! IO

@ffi("c", "strlen")
@trusted(audit: "LIBC-STRLEN")
fn c_strlen(s: Ptr[U8]) -> Int ! ()

@ffi("c", "free")
@trusted(audit: "LIBC-FREE")
fn c_free(p: Ptr[U8]) ! Mem      // returns (): row after the params, as §4.2 says
```

The rules:
1. `!` followed by `()` is the empty row. It is legal only on an `@ffi` decl. On any other fn or fn type it is an error ("no row already means pure"), so each place has one spelling.
2. An `@ffi` decl with no `!` is still E0802. Its help line names both choices: "declare the real effects (`! IO`, ...) or claim purity with `! ()`". No autofix (Q3).
3. Remove `@effects` from the spec: the 17 uses in sections/07, the 2 cross-references in sections/04, the annotation table row, and the formatter's ordering slot.

**Why this is minimal:**
- **One effect syntax.** That was my recorded Q2 concern. If `@effects()` stays next to `!`, a reader has to learn which one wins when both are there, and the formatter, LSP and typechecker all need a rule for that. Deleting `@effects` removes all of it.
- **No new name.** `()` already means "nothing" in Blink. It is not an effect name, so UnknownEffect, row unification and HM row inference need no special case.
- **It does not look like an omission.** You cannot leave `! ()` out by habit, and in a diff it stands out as a choice. That covers the concerns Sys, Web, DevOps and AI/ML each raised on Q2.
- **It is cheap to build.** It is one grammar alternative after `!`, and the check sits at the E0802 site the compiler already has. The typechecker sees an empty row, exactly as it does for a pure ordinary fn.

**Cost.** Rule 1 is a context rule: `! ()` is valid in one place only. I accept that, because allowing it everywhere would give every fn and fn type two ways to be pure. That is the very problem I am trying to remove.

###### Options I reject

- **Keep `@effects(...)` as the FFI spelling and drop `!` from `@ffi`.** That gives two effect syntaxes, chosen by which annotation sits next to them. Agents copy the shape they see most, and `!` is on thousands of fns. Every tool learns two parsers for one idea.
- **`! Pure` (or `! None`).** This is the `! FFI` mistake again: a name in the row that names no §4.3 effect, so every row rule needs an exception. It would also block a user from declaring an effect called `Pure`.
- **A bare `!`** (`-> Int !`). It reads as a typo or as a row someone forgot to finish, it parses badly before `{`, and every Q2 panelist warned against something that looks like an omission.
- **Allow `! ()` everywhere and let the formatter strip it.** A formatter that rewrites what the author claimed is a tool writing (or erasing) a claim. Q3 forbids that.

###### Housekeeping (subtraction only)
- Fix the stale E0802 help line ("add `! FFI`").
- The decision record's Final Spec example uses `@effects(DB)`. Correct it to `! DB`, so the training corpus does not keep the dead form.
- **Not in this ticket:** the compiler silently accepts unknown annotations such as `@bogus(IO)` and `@effects(IO)`. That is a real gap, because a deleted annotation that still compiles teaches nothing. File it as its own ticket. A general unknown-annotation diagnostic would catch every leftover `@effects` from the migration.

###### Migration
Converting the 118 lib/std decls means deciding, for each decl, between a real row and `! ()`. No sed can write `! ()`, so DevOps's acceptance criterion holds by construction.

###### Cross-language note
- **Go** has one way to declare a function and no annotations to drift from it.
- **Koka and Eff** write the empty effect row as `<>` or `{}`, a visible "nothing" and never an absent one. `! ()` is the Blink form of the same idea.
- **Rust** shows the cautionary case: `#[must_use]` can be ignored silently, and attributes that duplicate something in the signature drift over time. `@effects` already has drifted: nothing in the compiler reads it, yet it is all over the spec.

#### Phase A.5 — Deduped option space

###### Q1. Which form is the language?
All six proposals: the signature `!` row is the only effect syntax. `@effects(...)` is dead syntax: delete it from the spec (17 sites in sections/07, 2 cross-references in sections/04, the annotation-table row, the DECISIONS.md canonical-ordering slot, the formatter ordering slot). (sys, web, plt, devops, aiml, min)

Variation flagged for debate (Q1b): what a user who writes `@effects(...)` sees.
- Dedicated error naming `@effects` and pointing to `!`, no autofix. (sys, devops, aiml, plt)
- A note on E0802 when an `@ffi` decl carries `@effects(...)`: "`@effects(...)` is not Blink syntax; effects go after `!`". (web)
- Remove from the spec; the general "unknown annotations are accepted silently" gap goes to its own ticket. (min; the other five also want that separate ticket)

###### Q2. Spelling of the explicit pure claim on an `@ffi` decl
- A. `! ()` — the explicit empty row. (sys, min, plt, web)
- B. `! Pure` — reserved row name, not an effect; `! Pure, IO` is an error. (devops; devops fallback = `! ()`)
- C. `! pure` — lowercase reserved word, legal only as the whole row; `! pure, IO` is an error. (aiml; aiml fallback = `! _`, which aiml opposes; plt fallback = `! pure`)

###### Q3. Where the pure form is legal
- i. Only on an `@ffi` decl; an error on any other fn or fn type ("no row already means pure"). (sys, min, devops, aiml)
- ii. Legal wherever a row is legal (fn decls and fn types), meaning the same as omission; the formatter removes it on checked fns and keeps it on `@ffi` decls. (plt)
- iii. Legal wherever a row is legal; a style lint flags a redundant one on a non-`@ffi` fn, and the lint's fix deletes it. (web)
(min explicitly rejects "allow everywhere and let the formatter strip it".)

###### Common ground (no option split)
- E0802 fires when the row is absent on an `@ffi` decl; its stale "add `! FFI`" help is replaced by one that names both choices (real effects, or the pure claim). No machine-applicable fix (Q3 of the prior ruling).
- File a separate ticket: unknown annotations (`@bogus(...)`) are accepted silently.

#### Phase B — Debate

##### Round 1

All six closed round 1 with "STABLE, ready to vote". Position shifts: DevOps dropped `! Pure` and AI/ML dropped `! pure` for `! ()`; PLT and Web conceded Q3 to (i); Minimalism withdrew the argument that a formatter strip writes a claim, but kept (i) on rule count. Replies verbatim:

##### Web/Scripting
Web Phase B r1 on [this question]: Q1b I move to a dedicated error; Q2 I hold `! ()`; Q3 I move to (i), legal only on @ffi.

**Q1b: what a user who writes `@effects(...)` sees.** I CHANGE to a dedicated error (sys, devops, aiml, plt). AI/ML is right that my E0802 note only fires on @ffi decls. On an ordinary fn, `@effects(IO)` would still be ignored without a word, and that is where a model trained on the old §9.1 will keep writing it. The error must fire on any fn: "`@effects` is not Blink syntax; effects go after the return type: `-> Int ! IO`". It offers no autofix (Q3). I agree with min that the general unknown-annotation gap is a separate ticket. But a bare spec deletion leaves the most likely mistake with no diagnostic, so this one targeted error belongs in this ticket.

**Q2: spelling. I HOLD `! ()`.**
- To DevOps ("`! ()` reads like unit / a typo"): a JS or Python developer reads `()` as "empty", the same as an empty argument list or empty tuple. Nobody reads `f()` as a typo. `-> Int ! ()` puts the return type and the row on opposite sides of `!`, and the error text plus one line in §4.2 teaches it.
- `! Pure` creates a real Stack Overflow question: "why can't I write `! Pure, IO`?", or "I declared `effect Pure` and now it clashes". Min's point stands: it reserves a name users might want.
- To AI/ML (`! pure`): the lowercase word is clever, but it adds a keyword that exists in one place only. The reader must learn that `pure` is the one lowercase word after `!` that is not `_`. With `()`, the reader learns no new word. AI/ML's "contradiction" case also disappears: `! (), IO` is not valid grammar at all, so it needs no special rule.
- AI/ML says `! ()` "looks like an omitted row". I disagree. The test is "can you leave it out by habit and get the same tree?" No: without `! ()` you get E0802. It has a visible `!` token.

**Q3: where it is legal. I CHANGE to (i): only on @ffi** (sys, min, devops, aiml). Min convinced me. My lint (iii) is still two ways to write pure on ordinary fns, with a lint to clean up after it. A hard error with a clear help line is the better DX: "a fn without `!` is already pure; remove `! ()`". The learner gets one rule ("no row = pure; @ffi must say it") and one error that tells them what to do.

PLT's copy-the-signature-into-a-fn-type case is real but rare. The same error teaches the fix in one step. I also side with min against PLT's formatter strip: a formatter that silently deletes what the author wrote surprises users more than an error does.

STABLE, ready to vote


##### DevOps/Tooling
DevOps Phase B r1: I drop `! Pure` and back `! ()` (Q2), a dedicated `@effects` error (Q1b), and `! ()` legal only on @ffi (Q3).

**Q2: I concede `! ()`.** Min and Sys made the case. `Pure` is the `! FFI` mistake again: a name in the row that names no effect, so E0538, row unification and LSP completion all need an exception for it, and it blocks a user effect called `Pure`. My objection to `! ()` was that it "renders as a typo" in diagnostics, and that is weak. The diagnostic can say "the empty row `! ()`" in words. It is also easy to search for: `rg -F '! ()'` lists every pure claim, with the audit key on the line above. AI/ML's `! pure` is my second choice. Lowercase does stop `! pure, IO` from reading as a row, but it still adds a word for a value the row algebra already has (PLT's point).

**Q1b: a dedicated error, not a note on E0802 (against Web).** A note on E0802 only fires on @ffi decls that lack a `!`. It misses the two cases the training corpus will produce most: `@effects(IO)` on an ordinary fn (silent today), and `@effects(IO)` next to a correct `! IO` (silent too). The error must fire wherever `@effects` appears. On an @ffi decl that has `@effects(...)` and no `!`, report the `@effects` error alone and suppress E0802, so the user gets one error with one help line ("write the row after the return type: `-> Int ! IO`, or `! ()` for a pure claim"). No autofix (Q3); I agree with AI/ML that moving an author's claim is still a tool writing one. The general unknown-annotation ticket stays separate, but keep this specific message even after that lands. A generic "unknown annotation" message does not teach the fix.

**Q3: only on @ffi (with Sys, Min, AI/ML; against PLT and Web).**
- PLT's formatter normalisation means `blink fmt` deletes row text on some fns and keeps it on others. Today fmt never touches a row. I want to keep that invariant: a formatter that edits rows is one review away from a formatter that writes them.
- Web's lint-plus-fix leaves two grammar-legal spellings and adds a lint for the redundant one. An error does the same job with one rule and a better message.
- PLT's "copy a signature into a fn-type position" case gets its own message: "in a fn type, no row already means pure; remove `! ()`".
- On hover, show `! ()` plus the audit key on the @ffi decl, and the normal pure fn type on the value. The claim belongs to the decl, not to the type.

STABLE, ready to vote


##### PLT
PLT Phase B r1: dedicated `@effects` error (Q1b), `! ()` (Q2), and I concede Q3 to (i), legal only on @ffi.

**Q1b: a dedicated error for `@effects`, no autofix.** I agree with Sys, DevOps and AI/ML. Web's note on E0802 covers only @ffi decls. On an ordinary fn, `@effects(IO)` is accepted silently today and gets no diagnostic at all. AI/ML is right that models trained on the old §9.1 will keep writing it. One error code with a help line pointing to `!` covers every position. The general unknown-annotation gap goes to its own ticket, as all six of us agree.

**Q2: `! ()`, held.**
- **DevOps (`! Pure`):** Minimalism has the decisive point. `Pure` sits in the slot for effect labels but names no effect, which is the `! FFI` mistake again. Every row rule (E0538, unification, the subset check, HM row inference) then needs an exception for it, plus a ban on mixing (`! Pure, IO`). It also takes a name away from user effect declarations. A row is a set of labels, and the empty set needs no label.
- **AI/ML (`! pure`):** lowercase avoids the label confusion, and I rank it second. But the claim that "`! ()` reads as unit or as an omitted row" does not hold. After `!`, the parser is in row position, not type position, and `()` is the empty list of labels there, as `()` is the empty param list. Your own Unison example, `->{}`, shows that an empty-row literal is the established form. That literal is not an omitted row: the `!` token is present, and it parses as a different syntax tree.
- **DevOps D2 ("hard to grep"):** `rg '! \(\)'` is no harder to grep than `! Pure`.

**Q3: I concede to (i), legal only on @ffi.** Minimalism's objection to my (ii) is correct. Under (ii), the formatter removes text the author wrote, and the "one spelling per place" goal is lost. My composability worry also goes away on closer analysis.
- **Why the worry goes away:** `! ()` denotes ⟨⟩, the same value an omitted row denotes. So the rule "explicit row required on @ffi, explicit empty row rejected elsewhere" is a well-formedness check on decl forms. It is not a typing rule that depends on context, and the type algebra still has one empty row.
- **Signature copying still works:** `let f: fn(Ptr[U8]) -> Int = c_strlen` checks, because the types are equal.
- **Spec wording:** "`! ()` is the explicit empty row. It is required on an @ffi decl whose foreign code has no effects, and it is an error on any other fn or fn type, where omission already denotes the empty row." With that wording, the grammar admits `()` after `!` everywhere, and one check after parsing rejects it outside @ffi. Error text: "no row already means pure; remove `! ()`".

Web's (iii) is weaker than (i). It makes the same distinction, but only as a lint, so the second spelling survives in code that ignores lints.

STABLE, ready to vote


##### Systems
Systems, Phase B r1 on [this question]. Q1b: a dedicated `@effects` error. Q2: `! ()`. Q3: legal only on @ffi (i).

**Q1b: what a user who writes `@effects(...)` sees.** I keep the dedicated error. AI/ML's point decides it: models trained on the old §9.1 will keep writing `@effects(IO)`, and today they get silence on a non-FFI fn and an unrelated message on an @ffi decl. Web's E0802 note covers only the @ffi case, so it is not enough. Refinement: when an @ffi decl has `@effects(...)` and no `!`, report ONE diagnostic (the `@effects` error, with E0802's two choices in its help) and not two. No autofix, as DevOps and Minimalism say. Moving the row is still a tool writing a claim. The general unknown-annotation gap goes on its own ticket, as all six agree.

**Q2: the spelling. I hold `! ()`.**
- To DevOps ("reads like a unit effect, hard to search"): `rg '! \(\)'` is one pattern. Hover and diagnostics already have to print the empty row of a fn type somewhere. With `()`, the decl, the hover and a fn-type annotation all print the same text. With `Pure` or `pure`, the decl says `pure` but the fn type of `c_strlen` as a value is the empty row, so the tools print two spellings of one type.
- To AI/ML ("an empty row looks like an omission"): it does not. The `!` token is present, and the eye and grep both find it. The only real collision is `! {}` with the body brace, and nobody proposes that. The "unit-returning `fn f() ! ()`" case is close to empty: a pure foreign fn that returns nothing does nothing.
- To both: a label in row position, capital or lowercase, needs exception paths. "Not an effect" in E0538, "not mixable" (`! pure, IO`), and a rule for how it unifies. That is the `FFI` mistake again, at small scale. PLT is right that `()` is only concrete syntax for ⟨⟩, which the checker already has. Codegen cost is zero either way, so the tie goes to fewer rules.

**Q3: where it is legal. I hold i (only @ffi).** PLT's copy-the-signature-into-a-fn-type argument is the strongest one against me. Its cost is one error with a one-line fix ("no row already means pure; remove `! ()`"). Under ii and iii, two spellings of pure stay in user code until a formatter or lint runs, and agents copy whichever they see. Minimalism's objection to ii stands too: a formatter that deletes rows is a tool editing rows, even if it is only on checked fns. The context check costs almost nothing. It sits at the E0802 site the compiler already has. If the panel wants to relax i, the only relaxation I would accept is allowing `! ()` in fn-type positions, never on checked fn decls.

STABLE, ready to vote


##### Minimalism
Min Phase B r1: Q2 `! ()`, Q3 (i) only on @ffi, Q1b no dedicated @effects code.

**Q1b: what a user who writes `@effects(...)` sees.** AI/ML is right that models trained on the old §9.1 will keep writing `@effects(IO)`, so silence is not acceptable. But a dedicated code for one retired spelling (Sys, DevOps, AI/ML, PLT) is the same choice we rejected 6-0 on prior Q3: a code that only exists to serve a dead form stays in the catalog forever. Same fix as that ruling: ONE general unknown-annotation error (the separate ticket all six want), with a one-line help for `@effects`: "effects go after `!`: `-> Int ! IO` or `! ()`". No autofix. Interim, until that ticket lands: Web's note on E0802 covers the @ffi case at zero catalog cost. I'd also make the unknown-annotation ticket block closing [this question], so deleted syntax never compiles silently.

**Q2: spelling. `! ()`, holding.**
- DevOps's `! Pure`: a capitalised name in the row is exactly how `! FFI` looked. It steals an effect name from users (`effect Pure` becomes impossible or ambiguous), and UnknownEffect, the subset check and row unification each need a "not really an effect" branch. DevOps also needs a separate "`! Pure, IO` is an error" rule. `! ()` needs neither, because `()` cannot be combined with a label in the grammar.
- AI/ML's `! pure`: lowercase does avoid the name collision, and `! _` is real precedent. It still adds a word for a value the row algebra already has (PLT's point). AI/ML says an empty row "looks like an omitted row". It doesn't: there is a `!` token, which is the whole visual signal Q2 asked for. DevOps's "reads like returns unit": after `!` you are in row position. In `fn c_free(p) ! ()` a reader has to know `!` starts a row anyway. That is one line in §4.2.

**Q3: where it is legal. (i), holding.**
- PLT's copy-into-fn-type argument is the strongest one against me. But copying `-> Int ! ()` into a fn type gives a hard error whose fix is "delete `! ()`", and omission already means ⟨⟩ in types. So nothing is lost except one keystroke.
- I concede to PLT that a formatter stripping `! ()` from a checked fn writes no claim, so Q3 does not forbid it. I withdraw that argument. I still reject (ii) and (iii) on count. (i) is one rule: an error at a site the compiler already checks. (ii) is legal grammar plus a formatter rule that must know @ffi context. (iii) is legal grammar plus a lint plus a lint fix. Both let `! ()` sit in unformatted code, PRs and LLM training text as a second spelling of pure. Web: "why is `! ()` illegal here?" is answered by the error text itself.

STABLE, ready to vote


##### AI/ML
AI/ML Phase B r1: I concede Q2 to `! ()`, hold Q3 at (i) only on @ffi, and want a dedicated @effects error for Q1b.

**Q2 (spelling): I move from `! pure` to `! ()`.**
- PLT's argument wins it for me. Lowercase `pure` sits in the slot where an agent expects a capability name, so it will try `! pure, IO`, or `! pure` on ordinary fns. I would need special rules to block both.
- `()` cannot look like an effect name. That removes a whole class of wrong guesses for an agent, not only one bad combination.
- My real AI/ML test was "the claim must not look like an omitted row". Both spellings pass it. `! ()` passes it with no new word to learn, so it carries less risk.
- I oppose DevOps's `! Pure`. A capitalized name in the row is the `! FFI` pattern again (Min, Web). An agent that has seen `! Pure` will invent `! Pure, IO`, or declare an effect named `Pure`.
- DevOps says `! ()` reads like "unit effect". In this position, `!` before `(` and the §4.2 line make it clear, and the E0802 help line spells it out. Agents learn from the error text as much as from the spec.

**Q3 (where it is legal): I hold (i), only on @ffi. This agrees with Sys, Min and DevOps.**
- PLT's point that a signature copied into a fn type must still compile is the strongest case against (i). Copying a signature is a real agent behaviour, and I take it seriously.
- But (ii) and (iii) put two spellings of "pure" into the corpus that models train on. The formatter or a lint only cleans code that went through them, and much training text (docs, chats, snippets) never does. Models copy what they see.
- A hard error with the help line "no `!` already means pure; remove `! ()`" costs one fix cycle and teaches one canonical form. Under (i), the PLT copy case costs one deletion.
- I also agree with Min: a formatter that removes a row is a tool editing a claim. Even where that is harmless, the rule "tools never touch rows" is easier to learn with no exception.

**Q1b (what an @effects user sees): I want a dedicated error on any fn, not only Web's E0802 note.**
- Models trained on the old §9.1 will write `@effects(IO)` on ordinary fns too, and today that is accepted silently. Web's note fires only on @ffi decls.
- Help line: "effects go after `!` in the signature: `-> Int ! IO`, or `! ()` on @ffi". No autofix (Q3).
- If the general unknown-annotation error from Min's separate ticket lands at the same time, I accept that in place of the dedicated error. Removing @effects from the spec alone is not enough.

STABLE, ready to vote

#### Phase C — Final vote

- **Q1: `!` is the only effect syntax; delete `@effects`** — 6-0 YES
- **Q2: spelling of the pure claim** — 6-0 for A, `! ()`
- **Q3: where `! ()` is legal** — 6-0 for i, only on an `@ffi` decl
- **Q4: what a user who writes `@effects(...)` sees** — 5-1 for a, a dedicated diagnostic on any fn; **Minimalism** *(dissent)* for b, no dedicated code and a general unknown-annotation error with an `@effects` help line

No Phase D: no result was closer than 5-1. Four of the five Q4 majority votes say in their Concern field that the general unknown-annotation ticket must still be filed (DevOps, AI/ML), and that the `@effects` error must win where both apply (PLT, Sys). That ticket was filed with this ruling. The user signed off on the tally.

Ballots verbatim:

##### Systems
Systems votes on [this question]: Q1 YES, Q2 A, Q3 i, Q4 a.

**Q1: YES**
- Reasoning: A row is part of a fn's type, and rows are erased in codegen. `@effects` therefore buys nothing at runtime and costs a second place one fact can come from. Under `!`, the decl, its fn-type value and the checker all agree by construction. An annotation would have to be copied into the type, which is a split authority.
- Concern: the 118 lib/std decls must be decided one at a time. A rushed migration could still write wrong rows that compile to the same C and pass every gate.

**Q2: A (`! ()`)**
- Reasoning: `()` is concrete syntax for the empty row the checker already has. It adds no label, no E0538 exception and no unification rule. The decl, hover and fn type print the same text, and it parses with no ambiguity because `(` cannot start an effect name.
- Concern: `! ()` is easy to type, so an agent may write it on effectful bindings to make the code compile. Only the audit record and later tooling, such as a libc purity lint, will catch that lie.

**Q3: i**
- Reasoning: Only on an @ffi decl does an explicit empty row carry information (a claim). On a checked fn, the compiler proves purity, so a second spelling is noise that agents will copy. The check sits at the existing E0802 site and costs nothing.
- Concern: copying an @ffi signature into a fn-type annotation (`let f: fn(Ptr[U8]) -> Int ! () = c_strlen`) gives an error. The message must say "remove `! ()`" plainly so this does not become a recurring friction report.

**Q4: a**
- Reasoning: Models trained on the old §9.1 will keep writing `@effects(IO)`. A dedicated diagnostic fixes that today and does not wait on another ticket. Folding it into one error on @ffi decls keeps the output at one actionable message. No autofix, because moving a claim is still a tool writing a claim.
- Concern: once the general unknown-annotation error lands, the two paths must not both fire on `@effects`. The dedicated one must take precedence.

##### AI/ML
AI/ML Phase C ballot for [this question]: Q1 YES, Q2 A, Q3 i, Q4 a.

**Q1. Vote: YES**
- Reasoning: An agent learns one rule, "effects go after `!`", and that rule now holds on every fn, fn type and @ffi decl. If `@effects` stays, every FFI decl becomes a fork. The training corpus would then hold both forms, and models reproduce a mixed corpus by chance.
- Concern: models trained on the old §9.1 and on the prior decision record will keep writing `@effects(...)` for a long time. So the spec edits must include the decision record's `@effects(DB)` example, or the dead form stays in the corpus.

**Q2. Vote: A (`! ()`)**
- Reasoning: The claim must not look like an omitted row, and A passes that test without a new word to learn. `()` cannot be read as an effect name, so agents will not invent `! (), IO` or declare an effect named `Pure` the way B and C invite.
- Concern: `! ()` is easy to type, so an agent may learn the habit "add `! ()` until the @ffi decl compiles", which is the old `! FFI` habit again. The E0802 help text and the audit's "declared pure" category have to push back on that habit.

**Q3. Vote: i (only on @ffi)**
- Reasoning: Options ii and iii put two spellings of "pure" into docs, chats and snippets, and most of that text never goes through the formatter or a lint. Models copy what they see. A hard error with "no row already means pure; remove `! ()`" teaches one canonical form in one fix cycle.
- Concern: agents copy an @ffi signature into a fn-type position (PLT's case), so the error text must name the fn-type case and say "delete `! ()`". Otherwise the agent loops.

**Q4. Vote: a (dedicated diagnostic on any fn)**
- Reasoning: Models trained on the old spec will put `@effects(IO)` on ordinary fns too. Today that is accepted with no warning, and an E0802 note does not cover it. A dedicated error that names `@effects` and shows the `!` form is the shortest correction loop for an agent.
- Concern: if the general unknown-annotation ticket stalls, other dead or mistyped annotations still compile silently. So that ticket must still be filed and linked.

##### Web/Scripting
Web Phase C votes on [this question]: Q1 YES, Q2 A (`! ()`), Q3 i (only on @ffi), Q4 a (dedicated diagnostic).

**Q1: YES.**
Reasoning: A learner meets one rule in §4.2: "effects go after `!`". It should hold everywhere, @ffi included. A second form that the compiler ignores today would be the first Stack Overflow question ("which one do I use?"). It is also the first thing an AI copies wrongly from old examples.
Concern: Old §9.1 text stays in training data and blog posts for a long time, so the dead form will keep turning up in user code. This is why Q4 matters.

**Q2: A (`! ()`).**
Reasoning: `()` already reads as "empty" to any JS or Python developer, so the reader learns no new word. `! (), IO` is not valid grammar, so the "pure plus an effect" contradiction needs no special-case error. It reserves no name a user might want for their own effect. You cannot leave it out by habit and get the same result: leaving it out gives E0802.
Concern: Newcomers may first read `-> Int ! ()` as a unit return type. §4.2 and the E0802 help line must each state in one plain sentence that `! ()` means "no effects".

**Q3: i (only on @ffi).**
Reasoning: One rule is easiest to learn: "no row means pure; an @ffi decl must say it outright". A hard error that says "a fn without `!` is already pure; remove `! ()`" teaches the fix in one step. A lint or a silent formatter strip lets the second form spread through ordinary code.
Concern: Someone who copies an @ffi signature into a fn-type position gets an error that looks inconsistent. The error text must explain why `! ()` is valid on the decl but not there.

**Q4: a (dedicated diagnostic).**
Reasoning: The most likely mistake is a user or model writing `@effects(IO)` on an ordinary fn from the old spec. Today that is accepted silently. Option b leaves it silent until a separate ticket lands. One targeted error with a help line that points at `!` (and `! ()` on @ffi) fixes the real case now. Reporting it alone, not stacked with E0802, keeps the message to one clear action.
Concern: Once the general unknown-annotation ticket lands, this code may become a near-duplicate that shows up in the error catalog for one retired name. It should be folded in or kept on purpose, not left as a leftover.

##### Minimalism
Min Phase C votes on [this question]: Q1 YES, Q2 A, Q3 i, Q4 b.

**Q1: YES**
Reasoning: `@effects` has never had a reader in the compiler. Its only trace is a formatter slot, and the spec drifted onto it unnoticed. Deleting it removes one syntax, one annotation-table row and one formatter rule, and adds nothing. A row is part of a fn's type, so it belongs in the one place the type is written.
Concern: copies of `@effects(IO)` already sit in the corpus and in the earlier decision's Final Spec example. They will keep teaching the dead form unless every one is corrected in the same change.

**Q2: A (`! ()`)**
Reasoning: `()` adds no new name or keyword, and it is concrete syntax for the empty row the algebra already has. So UnknownEffect, the subset check and HM row inference need no new case. `()` cannot be combined with a label, so no "`! Pure, IO` is an error" rule is needed. It has a visible `!` token, so it cannot read as an omitted row.
Concern: `! ()` is easy to type, so "add `! ()` until it compiles" may become the new `! FFI` reflex. Only the audit record and the no-autofix rule stand against that.

**Q3: i (only on @ffi)**
Reasoning: (i) is one rule, an error, checked where E0802 already looks. (ii) needs grammar plus a formatter rule that knows about @ffi. (iii) needs grammar plus a lint plus a fix. Both leave `! ()` in unformatted code and training text as a second spelling of pure. The fn-type copy case costs one deletion, and the error names it.
Concern: the error must also fire on fn types and trait method signatures, not only on fn decls, or the second spelling leaks in through types.

**Q4: b (no dedicated code)**
Reasoning: a code that exists only to serve one retired spelling is the case we rejected 6-0 on the earlier Q3 (UnknownEffect, not an FFI-only code). The real gap is that every unknown annotation compiles silently, and one general error with an `@effects` help line closes that gap and this one. A dedicated `@effects` code stays in the catalog after the migration ends.
Concern: if (a) wins, the general unknown-annotation ticket loses its urgency, because the one case that hurts today is patched. `@bogus(...)` and the next deleted annotation would then stay silent.

##### DevOps/Tooling
DevOps Phase C votes on [this question]: Q1 YES, Q2 A (`! ()`), Q3 i (only on @ffi), Q4 a (dedicated diagnostic).

**Q1. Vote: YES**
Reasoning: The type checker, LSP hover, signature help and the formatter already work on the `!` row. `@effects` would need a second code path in every tool, plus a step that turns the annotation into part of the fn type. One spelling means one hover result on the decl and on the call site.
Concern: The training corpus already holds about 20 spec examples with `@effects`, and they will go on being copied. Q4 has to catch them, or deleting the syntax just turns them into silent dead text.

**Q2. Vote: A (`! ()`)**
Reasoning: It is not an effect name, so E0538, row unification and LSP completion need no special case. It cannot block a user effect named `Pure`. `rg -F '! ()'` lists every pure claim, and the audit key sits on the line above it. The diagnostic text can name it in words ("the empty row `! ()`"), and that covers my earlier objection about how it reads.
Concern: On a unit-returning fn, `fn c_touch(p: Ptr[U8]) ! ()` can read as a return type to a newcomer. §4.2 and the E0802 help line must say "empty effect row" outright, not just show the symbols.

**Q3. Vote: i (only on @ffi)**
Reasoning: Today `blink fmt` never adds or removes a row, and I want to keep that invariant. A formatter that edits rows is one change away from a formatter that writes claims (Q3 of the prior ruling). An error is one rule with one clear message. A lint plus a fix leaves two spellings that the grammar accepts, and we would carry both in every tool forever.
Concern: An author who copies an @ffi signature into a fn-type position gets an error. That error needs its own text ("in a fn type, no row already means pure; remove `! ()`"), not a generic parse error.

**Q4. Vote: a (dedicated diagnostic)**
Reasoning: A note on E0802 misses the two most common cases: `@effects(IO)` on an ordinary fn, and `@effects(IO)` next to a correct `! IO`. The compiler accepts both silently today. A dedicated code that fires on any fn, suppresses a duplicate E0802 and has a help line naming the exact fix teaches the change in one error. A generic "unknown annotation" message would not. Min's ordering point is right but does not conflict with this: both can ship, and this one is more specific.
Concern: If the unknown-annotation ticket never lands, `@effects` becomes a special case in a compiler that still accepts every other unknown annotation silently. That ticket should be filed and linked as part of this ruling, not left as a follow-up.

##### PLT
PLT Phase C vote on [this question]: Q1 YES, Q2 A (`! ()`), Q3 i (only on @ffi), Q4 a (dedicated @effects error).

**Q1. Vote: YES**
Reasoning: A fn's row is part of its type (§4.2). Function types can hold only a `!` row and can never hold an annotation. If the row lived in `@effects`, the checker would have to lower an annotation into a type, so one judgement would have two surface forms and two sources. With `!` only, annotations stay non-semantic, and the decl's signature is the postulate under its audit key.
Concern: The decision record's Final Spec example still shows `@effects(DB)`. If we don't correct it in the same change, the dead form stays in the corpus.

**Q2. Vote: A (`! ()`)**
Reasoning: `! ()` is concrete syntax for ⟨⟩, the empty row the algebra already has. It adds no label, kind or law, and E0538, unification, the subset check and HM row inference all stay unchanged. `! Pure` puts a non-effect in the label slot and repeats the `! FFI` mistake. `! pure` adds a word for a value that already has a name. "Absent row" and "empty row" become different syntax trees, and Q2 of the prior ruling requires exactly that.
Concern: Readers new to rows may first read `()` after `!` as the unit type, so the §4.2 text must define it in one line as the empty effect list.

**Q3. Vote: i (only on @ffi)**
Reasoning: `! ()` and an omitted row denote the same ⟨⟩. So the rule "explicit row required on @ffi, explicit empty row rejected elsewhere" is a well-formedness check on decl forms, not a typing rule that depends on context. Types still compare equal, and `let f: fn(Ptr[U8]) -> Int = c_strlen` checks. Option ii makes a tool erase what the author wrote, and option iii keeps the second spelling alive wherever lints are ignored.
Concern: The spec must say that the check runs after parsing, not in the grammar. Otherwise an implementation may give the row grammar a production that depends on context, and that grammar would drift between fn decls and fn types.

**Q4. Vote: a (dedicated diagnostic)**
Reasoning: `@effects` is a form the spec once taught, so code will be written in it, by models more than by people. One code that fires in every position, with a help line naming `!` and `! ()`, gives one fix for one mistake. Making it depend on a general unknown-annotation ticket leaves `@effects(IO)` silently accepted on ordinary fns until that ticket lands. Suppressing E0802 when `@effects` is present avoids reporting one cause twice.
Concern: Once the general unknown-annotation error exists, the two diagnostics may overlap, so that ticket must keep the `@effects` code as the more specific one rather than report both.

### AI-First Review

| Criterion | Result | Why |
|---|---|---|
| Learnability | Pass | One rule: effects go after `!`, on every fn, fn type and `@ffi` decl. |
| Consistency | Pass | `! ()` is concrete syntax for the empty row the checker already has; no new label. |
| Generability | Pass | `! (), IO` is not grammar; `()` cannot be taken for an effect name. |
| Debuggability | Pass | Each wrong form (`@effects`, missing row on `@ffi`, `! ()` off `@ffi`) gets one error with a one-step fix. |
| Token Efficiency | Pass | Three characters for the pure claim; no annotation line. |

### Final Spec

```blink
@ffi("c", "strlen")
@trusted(audit: "LIBC-STRLEN")
fn c_strlen(s: Ptr[U8]) -> Int ! ()

@ffi("sqlite3", "sqlite3_open")
@trusted(audit: "DB-003")
fn sqlite3_open(filename: Ptr[U8], db: Ptr[Ptr[Void]]) -> Int ! IO
```

- The `!` row in the signature is the only effect syntax. There is no `@effects` annotation (§9.1, annotation table, canonical ordering).
- An `@ffi` decl must write its row. A foreign function with no effects writes `! ()`, the explicit empty row. A missing row stays E0802, whose help names both choices; no fix is machine-applicable.
- `! ()` means "no effects", the same row as an omitted one. It is legal only on an `@ffi` decl. On any other fn, fn type or trait method signature it is `EmptyRowOutsideFfi`; the check runs after parsing, not in the grammar. In a fn type the help says "in a fn type, no row already means pure; remove `! ()`".
- `@effects(...)` on any fn is `EffectsAnnotationRemoved`, reported alone (no E0802 as well), with no autofix. When the general unknown-annotation error lands, the `@effects` error stays the more specific one.
- §4.2 and the E0802 help say in words that `! ()` is the empty effect row, not a return type.
