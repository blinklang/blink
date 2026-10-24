[< All Decisions](../DECISIONS.md)

# Variant Spelling and Pattern Case — Design Rationale

The ticket said that a variant needs a qualified spelling to construct (`Shape.Circle(5.0)`) and a bare spelling in a pattern (`Circle(r)`). It asked whether Blink should keep two spellings, and it set one test: keep a form only if it prevents a bug class.

Premise fact: the ticket is wrong about the rule. §3.4 (*Variant Construction*) and gen1 already accept the bare and the qualified spelling at construction and in patterns. The "two spellings" impression came from three stale examples. The panel found a different bug class in patterns: a bare name with no payload is a new binding, so a typo or a constant name can become a catch-all.

Facts before the vote:

- Probe `pe3.bl`: `Dott =>` (a typo for `Dot`) on a `Shape` scrutinee compiles. It is a new binding that matches every value. The only report is `UnusedVariable`, and that report goes away when the arm body reads the name.
- Probe `plt/p1.bl`: with the typo arm first, the two later arms are dead. Nothing reports them.
- Probes `aiml/pk.bl` and `web/w1.bl`: `const MAX = 10` and `MAX =>` on an `Int` scrutinee compile. `MAX` is a new binding that hides the constant. The arm matches every value and the `_` arm is dead.
- Probe `plt/p2.bl`: `code` (an `Int` scrutinee with the arms `Ready` and `Failed`) compiles with no report at all. `pick` (a type-parameter scrutinee with `None =>`) compiles as a variant test, passes the exhaustiveness check and panics at run time.
- Probe `pe2.bl`: after an `Int`-scrutinee binder `Dot =>`, gen1 resolves `{Dot}` to the variant. The spec says it is the binder.
- Probe `lc.bl`: gen1 accepts a lowercase variant (`type T { foo, Bar(Int) }`). No spec text sets a casing rule for variant names.
- Blink has no `if let` and no `while let`. `let` and `for` need irrefutable patterns. `assert_matches(expr, pat)` takes "a **pattern** (same syntax as `match` arms)".
- A payload typo (`Circel(r)`) and a qualified typo (`Shape.Dott`) already give E0547. The bare unit name is the only hole.
- Corpus counts from the panel brief: tests/ has about 2351 bare arms and 790 qualified arms, and about 950 qualified constructions.

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated in independent-proposal, debate and vote rounds. Quoted text is each panelist's own, verbatim. `…` marks a cut. No Phase D ran: all four questions passed 6-0 in Phase C.

The questions were:

- Q1, the two spellings: K (keep both at both sites, fix the examples), or require one spelling.
- Q2, the typo binder: T-lex (an uppercase-initial bare name in a pattern is a variant, at every type), T-enum (the same rule only where the type is an enum), or no change. Two fallbacks were also named in Phase A: T-near (an error when the name is not the last arm or is near a variant name) and T-warn (a warning that defaults to error).
- Q3, the scope of the Q2 rule: S-match (match arms) or S-refutable (match arms and the `assert_matches` pattern).
- Q4, lowercase variant names: keep the type-directed rule for a lowercase bare name, and send the casing question to a separate ticket.

#### Phase A — Independent proposals

All six seats said that the ticket premise is false and that both spellings stay (Q1). All six proposed to close the typo hole. Systems, Web, DevOps and AI/ML proposed T-enum. PLT and Minimalism proposed a lexical rule (PLT for match arms, Minimalism for every pattern).

- **Systems:**

> The ticket says construction needs `Shape.Circle` and patterns use `Circle`. That is not the spec and not the compiler.
> 03_types.md:1963 accepts the bare and the qualified spelling at both sites, and probes pa.bl / pc.bl / pf.bl confirm gen1 does
> the same.
>
> …
>
> So this is not "two ways to do one thing" in the Principle 2 sense. It is one way (bare) plus a disambiguator that exists only
> because names can collide — the same shape as Rust's `Some(x)` vs `Option::Some(x)`, or Go's `fmt.Println` vs a dot import.
> Principle 2 is honoured by the examples teaching one default, not by deleting the escape hatch.
>
> …
>
> `Dott` is a catch-all. The match is "exhaustive", so E0005 never fires. Worse, the failure is **delayed**: when someone later
> adds `Triangle(Float)` to `Shape`, every match with such a typo silently routes `Triangle` to the wrong arm, with no
> exhaustiveness error at any of them. That defeats the one guarantee that makes `match` safer than a C `switch` with `default:`.

- **Web/Scripting:**

> The ticket premise is false. The spec (03_types.md:1951-1963) and gen1 already accept the bare and the
> qualified spelling at construction and in patterns (probes pa.bl, pc.bl, pf.bl, g/). There is no
> "qualified to construct, bare to match" rule. The confusion comes from our own teaching text:
> llms-full.md:230 writes `let s = Shape.Circle(5.0)` and then matches with bare `Circle(r) =>` four
> lines later.
>
> …
>
> This compiles. The match is now exhaustive because `Dott` is a catch-all, so the exhaustiveness check
> (the one safety net a dev trusts) goes quiet. `k(Square(2.0))` returns `"dot"`. The only signal is
> `UnusedVariable`, which a dev learns to ignore, and which goes away the moment the arm body reads the
> name.
>
> …
>
> I reject a `RedundantQualifier` lint. It would fire on thousands of lines in our own tree for no
> bug it prevents, and a dev who writes `Shape.Circle` to be explicit gets nagged for being clear.

- **PLT:**

> This is coherent. Bare and qualified are not two constructs. They are the short name and the full path of one entity, the same relation as `login()` after `import auth.{login}` vs `auth.login()`. The rule "a bare name at a site denotes exactly one entity, decided statically" (03_types.md:1971, DECISIONS.md:437 Q8) holds in both positions. Principle 2 forbids two constructs for one job. It does not forbid a qualified path for a name, or every module-qualified call in the language would break it.
>
> …
>
> The root cause: whether a pattern binds a name depends on the type at the position. So the set of names a pattern binds is not known from syntax. That hurts compositionality: OR-pattern binding checks (E0005), scope, the LSP's binder list and the W1011 rule for pattern binders (07:2625) all need the type first. An exhaustiveness check cannot catch the typo, because a binder is irrefutable and makes the match total.
>
> Rule (the Haskell/OCaml lexical split, scoped to match patterns):
>
> > In a `match` arm pattern, at any depth, a bare name whose first character is an uppercase letter is a variant reference, never a binder. If the type at that position has no variant of that name, it is `NoSuchVariant` (E0547), with the existing `note:` and a near-miss suggestion. A binder in a match pattern starts with a lowercase letter or `_`.

- **DevOps/tooling:**

> Write the bare form. Write the qualified form only where the bare form does not reach the variant: an ambiguous
> name (E0519), a name that a value hides (§3.4 *Values come first*), or a site with no expected type that a reader
> must resolve. Examples in this specification use the bare form unless they show one of these cases.
>
> …
>
> The qualified form is the target of every machine-applicable fix in this area:
> - E0519 AmbiguousConstruction: `help: qualify as JobState.Pending or NetState.Pending` (probe pf2.bl).
> - §3.4 :1981-1992: a value hides a variant, `help: write Tone.Warm`.
> - E0547 / DECISIONS.md:463: wrong-enum pattern gets the fix `T.Q`.
> - E1007: `mod.T.V` is repaired to `T.V`.
>
> …
>
> **Rule (amends 03_types.md:2781).** When the type at the pattern position is an enum (a user enum or a prelude enum,
> after aliases), a bare name with no payload whose first character is an uppercase letter must be a variant of that
> enum. Else it is `NoSuchVariant` (E0547). A bare name that starts with a lowercase letter or `_` stays a binder.

- **AI/ML:**

> Exemplar consistency is the real fix. Principle 2's corollary (01:40) is about what the model *sees*. If every
> example is bare, models converge on bare. The mixed llms-full.md:230 exemplar teaches "construct qualified,
> match bare", which is the false rule in this ticket.
>
> …
>
> Misspelling or mis-remembering a unit variant (`Dott`, `Pending` on an enum that
> calls it `Queued`, `NotFound` on an enum that calls it `Missing`) is a common generation error, because the
> model recalls the variant set from a distant declaration or from a different library. Today that error compiles,
> runs, and silently matches every value. It is the worst class for an agent: no compile error to repair from, and
> a test that may pass by luck.
>
> …
>
> **Alternative I would also accept (aiml-2b):** apply the rule at every pattern position, so a bare PascalCase
> binder is never legal (Haskell/OCaml model). Cleaner, but it overturns the `show(n: Int)` example and the
> pattern-binder half of W1011 (DECISIONS.md:437 Q4w/Q6), so it needs those rows reopened. I prefer aiml-2 for scope.

- **Minimalism:**

> Principle 2 forbids two mechanisms for one job; it does not forbid a qualifier.
>
> …
>
> Otherwise a bare name with no payload is a new binding if its first character is lowercase or `_`. A bare name with no payload whose first character is uppercase must name a variant of the type at that position; if it does not, the pattern is `NoSuchVariant` (E0547), with the existing `note:` that names a visible enum that declares it (03_types.md:2834).
>
> …
>
> What it removes:
> - The form "uppercase binder." No code in tests/, lib/std or examples needs it (each binder in an arm is snake_case by convention); I see no use for it except the spec's own example at 03_types.md:2794-2797, which exists only to show the trap.
> - The W1011 pattern-binder trigger at 03_types.md:2801 …
> - The pe2.bl spec/compiler divergence (`{Dot}` after a binder `Dot` on an Int scrutinee) has no case left to diverge on.

#### Phase B — Debate highlights

All six seats supported K for Q1. The debate was on Q2 and Q3. Four seats moved from T-enum to T-lex, and Systems and DevOps withdrew their fallbacks.

- **Systems** moved from T-enum to T-lex and withdrew T-near:

> **T-near (my fallback):** withdrawn. "Edit distance 2 of a variant" makes a program legal or illegal according to the
> spelling of a distant declaration; adding a variant `Dat` could break a far-off arm. That is the non-locality §3.4 step 2
> exists to prevent.

- **Web/Scripting** moved to T-lex on the evidence of probe `web/w1.bl`:

> It compiles and prints `max`. `MAX =>` is a new binder that catches every Int, and `_ => "other"` is dead.
> The only output is `warning[ShadowedVariable]` and `warning[UnusedVariable]`. No error, and no
> unreachable-arm report (plt's side finding).
>
> That is the exact mistake a JS or Python dev makes: JS `switch (n) { case MAX: ... }` compares to the constant,
> and Python's `case MAX:` is the capture footgun that PEP 636 warns about. Blink has no constant patterns
> (I found no spec rule for them in 03_types.md), so a dev who wants to compare must write a guard. T-enum does
> not help here, because `Int` is not an enum. T-lex makes it an error, and the error can teach the guard:

- **AI/ML** moved to T-lex on the evidence of probe `aiml/pk.bl`:

> This is a worse LLM trap than the `Dott` typo. The typo is a random error. `MAX =>` is a *systematic* one: in Rust,
> `const MAX: i64 = 10; match n { MAX => .. }` compares against the constant, and Swift, Kotlin (`when (n) { MAX -> }`),
> C/Java/Go `switch` (`case MAX:`) and Scala (uppercase = stable identifier) all do the same. Every model trained on that
> code will write it, and Blink will compile it into a catch-all with no error.
>
> **T-enum does not catch this**, because `Int` is not an enum. T-lex does. That one fact settles Q2 for me.

- **PLT** brought probe `plt/p2.bl` (`code` and `pick`):

> **`code`, the hole T-enum leaves open.** This is the refactor case. The scrutinee was a `Status` and its type changed to `Int` (a field type changed, or a `.to_int()` was added upstream). Every unit arm turns into a catch-all binder. Gen1 gives no warning at all here, not even `UnusedVariable`.
>
> …
>
> On a type-parameter scrutinee, the spec (:2781) makes `None` a binder (with W1011, prelude variant). Gen1 compiles it as a `None` variant test instead, accepts the match as exhaustive, and panics at run time. The typechecker statically accepted a non-exhaustive match. That is unsound, so it is a `type:bug` whatever we vote. But it is the second time (after pe2) that gen1 and the spec disagree on what a bare uppercase name means at a non-enum position.

- **PLT** gave the wording that the vote used:

> In a `match` arm pattern, at any depth, a bare name whose first character is an uppercase letter (Unicode `Lu` or `Lt`) names a variant of the type at that position, with or without a payload. If that type is not an enum, it is `EnumPatternNeedsEnumScrutinee` (E0308). If the enum has no variant of that name, it is `NoSuchVariant` (E0547). Any other bare name with no payload is a new binding. Bindings by `let`, parameters and closure parameters are unchanged.

- **PLT** put the lowercase edge on the record:

> Open edge I want on the record: if the grammar admits a lowercase variant name, a bare lowercase name stays type-directed (today's rule), so the binding structure stays type-dependent for that case only. If no lowercase variant exists in practice, a separate ticket can make variant names uppercase-initial at declaration. That is out of scope here.

- **DevOps/tooling** moved to T-lex for a tooling reason and withdrew T-warn:

> **Under T-lex, the set of names a pattern binds is known from the syntax alone.** Under T-enum it is known only
> after the typechecker resolves the scrutinee type. That matters to every tool that does not run a full typecheck,
> or that runs on broken code:
>
> …
>
> **T-warn** (my own devops-2b): I withdraw it. A warning on this is the `UnusedVariable` we already have with a
> better name, plus a `[lints]` knob. Web said the same.

- **DevOps/tooling** added `assert_matches` to the scope:

> **Not "match arms" only (plt-2).** Blink has one more refutable pattern position: the pattern operand of
> `assert_matches` (02_syntax.md:2209). `assert_matches(r, Dott)` has the same hole: a typo binds and the assertion
> always passes, which is worse, because a test that cannot fail looks green. The rule must cover it.

- **AI/ML** also asked for `assert_matches`, and withdrew its own "every pattern" alternative:

> So the line is "refutable positions": match arm patterns at any depth, and the pattern operand of `assert_matches`,
> which is also refutable. I ask plt to say whether plt-2 means to include `assert_matches`; I think it must.

- **Minimalism** narrowed its scope from "every pattern" to the refutable patterns, and counted the rules:

> I concede to plt's scope: match arm patterns, at any depth. My min-2 said "in a pattern"; I withdraw that.
>
> …
>
> T-enum leaves two rules for a bare no-payload name in a pattern … T-lex leaves one rule: uppercase means variant, lowercase or `_` means binder. The type at the position decides only *which* variant, never *whether*.
>
> T-enum is an addition on top of today's rule. T-lex replaces today's rule.

- **Web/Scripting** gave the cost count for the "every pattern" scope:

> Eight are local lets, and each is a deliberate test of a value named like a type or variant
> (e.g. tests/test_typecheck_value_named_like_a_variant.bl:126 `let Red = 5`). If "every pattern" includes a `let`
> name, we break hundreds of lines and the ALL_CAPS style that devs bring from every C-family language.

#### Phase C — Final vote

| Q | Result | Tally |
|---|---|---|
| Q1 | **K**: keep bare and qualified at both sites; no rule change; examples write bare and qualify only where a case needs it; `blink fmt` does not canonicalize | 6-0 |
| Q2 | **T-lex**: in a refutable pattern, a bare uppercase-initial name (Unicode `Lu`/`Lt`) names a variant of the type at that position, with or without a payload; not an enum, E0308; no such variant, E0547; any other bare no-payload name binds | 6-0 |
| Q3 | **S-refutable**: every refutable pattern position (today the match-arm pattern at any depth and the `assert_matches` pattern operand) | 6-0 (PLT moved from S-match) |
| Q4 | **yes**: a bare name that does not start with an uppercase letter keeps the type-directed rule; a separate ticket asks about lowercase variant names; the spec says in one sentence that the guarantee covers uppercase-initial variants only | 6-0 |
| AI-First | 5/5 pass | |

Each seat voted K, T-lex, S-refutable, yes. The reasoning and the concern of each seat follow.

- **Systems:**
  - Q1: "Bare and qualified resolve statically to the same variant tag and emit byte-identical C, so there is no runtime reason to delete either." Concern: "With no fmt canonicalization and no lint, user code will keep mixing spellings, so the bare default holds only as long as every spec and llms example honours it."
  - Q2: "T-lex makes the binder set of an arm a property of the syntax, so scope building, OR-pattern binder checks and the LSP need no type first." Concern: "The type-parameter case in plt/p2.bl (`None =>` compiles as a variant test, then panics non-exhaustive at run time) needs the E0308 path to fire before mono, or T-lex moves a bug instead of closing it."
  - Q3: "A typo binder there makes the assertion pass for every value: a test that cannot fail, which is the same bug class as a catch-all arm." Concern: "The spec must say "every refutable pattern site" as the rule, not list two sites, or a future refutable site will repeat this gap."
  - Q4: "no spec text sets a casing rule for variants, so making that call here would decide an unasked question without a probe-backed debate." Concern: "Until that ticket closes, a lowercase variant keeps the typo hole T-lex closes for PascalCase ones."
- **Web/Scripting:**
  - Q1: "Both spellings match a large group of dev priors (`Color.Red` from TS/Kotlin/Swift/Python, bare `Some`/`Ok` from Rust/ML), and they give the same value and the same C." Concern: "If the example chore stops at three sites, other mixed snippets stay in the docs and teach the false "qualified to build, bare to match" rule again."
  - Q2: "It is the one-sentence rule a dev already assumes: in a match, a capitalized name is a variant." Concern: "The E0308 message for `MAX =>` on an Int must say "use a guard to compare, or a lowercase name to bind"; a bare "Int is not an enum" will confuse the exact dev this rule is for."
  - Q3: "The spec tells devs that the `assert_matches` pattern uses "same syntax as `match` arms" (02_syntax.md:2043), so it must follow the same rule, or we create a second pattern dialect." Concern: "If a future refutable form appears (some later `if let`-style form), the spec must name this rule there too, or the dialect split returns."
  - Q4: "Lowercase variants compile today (lc.bl) and no spec text forbids them, so a casing rule for variant names is a separate language question for its own ticket." Concern: "Until that ticket is decided, a lowercase variant keeps the typo hole, and an LLM that sees one in a codebase may conclude the casing rule is not real."
- **PLT:**
  - Q1: "A bare variant and its qualified form are one entity, written by its short name and by its full path. Both resolve statically to the same injection, so Principle 2 is not broken." Concern: "A plain spelling default in prose does not reach code that LLMs or users write. Mixed spellings can still appear in the corpus, and `blink fmt` (by design) will not make them consistent."
  - Q2: "The type-directed rule has already split the spec and gen1 twice (pe2, p2 `pick`), and the second split is a match that the compiler accepts as exhaustive but that is not. T-lex removes that whole class." Concern: "If T-enum wins, the non-enum seam stays in the language."
  - Q3: "I change from S-match to S-refutable because of this fact." (The fact: the `assert_matches` operand is a refutable position, and 02_syntax.md:2043 says it uses the same syntax as a match arm.) Concern: "The spec text should say "every refutable pattern position", not list the positions one by one."
  - Q4: "gen1 accepts `type T { foo, Bar(Int) }` (lc.bl), and the spec has no casing rule for variant names. So a bare lowercase name must keep today's type-directed rule, or a lowercase variant could never be matched bare." Concern: "Until that ticket is decided, a lowercase variant reopens the typo hole (`fooo =>` binds silently), so the guarantee T-lex gives is complete only for uppercase-initial variants."
- **DevOps/tooling:**
  - Q1: "`blink fmt` must not rewrite either form, because fmt has no types and a rewrite can change which entity a name resolves to." Concern: "If the doc chore does not also say that `help:` lines write the qualified form, a reader can take `Shape.Dot` in a fix as a second rule and the ticket comes back."
  - Q2: "It reuses the existing codes (E0547, E0308, E0301), so `Dott`, `Dott(x)` and `Shape.Dott` get one diagnostic family." Concern: "The E0308 text for `MAX =>` or `Red =>` on an `Int` must say "to bind the value, write a lowercase name", or users who meant a binder will read it as a type error and not know the repair."
  - Q3: "Naming the operand in the rule text costs one clause and stops an implementer from checking only `NodeKind.Match`." Concern: "If S-match wins, the spec text must still say that `assert_matches` uses match-arm patterns under this rule, or the typecheck path for `assert_matches` will skip the check."
  - Q4: "A lowercase variant compiles today (lc.bl), and no casing rule for variants exists in sections/." Concern: "the diagnostic surface treats `foo =>` and `Dott =>` differently for the same mistake."
- **AI/ML:**
  - Q1: "A model learns from what it sees, so every example must write the bare form, and llms-full.md:230 must stop teaching "qualified to construct, bare to match"." Concern: "The bare-first sentence is guidance with no check behind it, so stale qualified examples can come back."
  - Q2: "T-lex is one sentence a model can apply while it writes the arm, before it knows the scrutinee type: "uppercase is a variant, lowercase binds"." Concern: "The E0308 for an uppercase name on a non-enum type must carry a help line with the guard repair (`n if n == MAX =>`) when a value of that name is in scope. Without it, an agent will guess, and may invent a const-pattern feature or rename the const."
  - Q3: "`let` and `for` stay out, because their patterns cannot fail to match and `let MAX_RETRIES = 3` is a common Python/JS prior that is not a bug." Concern: "If S-match wins, the spec must still say whether "match pattern" includes `assert_matches`."
  - Q4: "A lowercase variant is outside this ticket, and no example or prior uses one." Concern: "the spec must say so in a single sentence and not leave it implicit."
- **Minimalism:**
  - Q1: "The ticket's "two spellings" came from three stale examples, so the fix is a doc chore, not a language change." Concern: "With no lint and no fmt canonicalization, mixed spellings will creep back into examples unless the chore also states the bare-first sentence once in §3.4 so reviewers have a rule to point at."
  - Q2: "T-lex replaces today's type-directed binder rule with one rule; T-enum keeps today's rule and adds a second one beside it. … No seat found a real uppercase catch-all binder, so the capability T-enum keeps has no user." Concern: "The `MAX =>` case under T-lex becomes E0308 on an Int position, and the message must say "to bind the value, use a lowercase name" and not only "Int is not an enum", or users will read it as a bug in the compiler."
  - Q3: "Excluding it would create a second pattern rule for one syntax, which is the opposite of what Q2 buys." Concern: "A future refutable position (if the language ever adds one) must join this list by name; the spec text should define the set as "refutable patterns" so it does not need editing each time."
  - Q4: "Keeping today's type-directed rule for lowercase bare names changes no program, and a separate type:spec ticket can ask whether to require PascalCase variants, which would make T-lex complete." Concern: "the T-lex rule text must not claim it closes the class for every variant."

### Final Spec

Q1, spelling:

- Both spellings stay legal at construction and in patterns. The rule of §3.4 does not change.
- Write the bare form. Write the qualified form only where the bare form does not reach the variant: an ambiguous name (E0519), a variant that a value hides, a user variant named like a prelude variant.
- A diagnostic `help:` writes the qualified form because it is the full name of the variant. It is not a second rule.
- Spec and `llms` examples follow this. `blink fmt` does not change the spelling.

Q2, Q3 and Q4, the pattern rule (§3.5 *Bare names: variant or binding*):

- In a refutable pattern, a bare name whose first character is an uppercase letter (Unicode `Lu` or `Lt`) names a variant of the type at that position, with or without a payload.
- If that type is not an enum, the pattern is E0308 `EnumPatternNeedsEnumScrutinee`. If the enum has no such variant, the pattern is E0547 `NoSuchVariant`.
- Every refutable pattern position follows this rule. Today these are the match-arm pattern at any depth and the pattern operand of `assert_matches`. A future refutable form uses the same rule.
- `let`, parameters, closure parameters and `for` are irrefutable. Any bare name with no payload binds there, and W1011 applies as §10.6 says.
- A bare name that does not start with an uppercase letter (a lowercase letter, `_`, or a letter with no case) keeps the type-directed rule. The protection against a typo covers variants with an uppercase first letter only.
- The E0308 help says "to bind the value, write a lowercase name". When a value of that name is in scope, it also shows the guard `n if n == MAX =>`.

```blink
type Shape { Circle(Float), Square(Float), Dot }

const MAX = 10

fn area(s: Shape) -> Float {
    match s {
        Circle(r) => 3.14159 * r * r
        Square(w) => w * w
        Dot => 0.0
    }
}

fn origin() -> Shape {
    Shape.Dot                      // qualified: always legal; the full name
}

fn typo(s: Shape) -> Float {
    match s {
        Circle(r) => r
        Dott => 0.0                // error[NoSuchVariant]: `Shape` has no variant `Dott`
                                   // help: did you mean `Dot`?
        _ => 1.0
    }
}

fn limit(n: Int) -> Str {
    match n {
        MAX => "at the limit"      // error[EnumPatternNeedsEnumScrutinee]
        _ => "below"
    }
}

fn bind(n: Int) -> Str {
    match n {
        max => "n is {max}"        // OK: a lowercase name binds
    }
}

fn compare(n: Int) -> Str {
    match n {
        m if m == MAX => "at the limit"   // OK: a guard compares with the value
        _ => "below"
    }
}
```

Locked points:

- The first character of a name, not the type, decides whether an uppercase bare name in a refutable pattern is a variant.
- The set of names that a refutable pattern binds is known from the syntax alone, except for names that do not start with an uppercase letter.
- No new diagnostic code. E0308 and E0547 carry the new cases.
- The program-wide search of §3.4 step 3 never runs in a pattern.
- No lint for a redundant qualifier, and no `blink fmt` rule for the spelling.
- T-near and T-warn are rejected.

### Amendments

- DECISIONS.md "Bare variant and value names" row, Q7 (patterns): the clause "else a new binding" no longer holds for a bare name with an uppercase first letter in a refutable pattern. That name is a variant, or an error.
- The pattern-binder part of W1011 (§10.6, §3.5): a binder in a refutable pattern cannot have the name of an uppercase variant. W1011 for a pattern binder applies only to irrefutable patterns, and to names that do not start with an uppercase letter. The `let`, parameter and closure-parameter parts of W1011 stand (Q4w, Q6).
- E0547 `NoSuchVariant` (decisions/no-such-variant-diagnostic.md): the bare payload pattern on a struct, tuple or type parameter was E0547. It is now E0308 `EnumPatternNeedsEnumScrutinee`, because T-lex says "not an enum is E0308, with or without a payload". The cases on an enum position do not change. The struct message "`Point` is a struct; it has no variants" stays. A lowercase bare name with a payload also names a variant (§3.5 says a payload name must), so it gets the same split: E0308 at a type that is not an enum, E0547 at an enum. This sentence is the moderator's reading for consistency, not a panel vote.
- The §3.5 example with `Red =>` on `show(n: Int)` was a binder with W1011. It is now E0308; the repair is `red =>`, which binds. The guard repair is shown only on the `MAX` example, because a guard needs a value of the scrutinee's type. The `let Red = 5` example, where `Red =>` on a `Color` is still the variant, stays.
- The E0308 change above covers a bare name with a paren payload or no payload. The brace form on a struct (`Point { x, .. }` on a `Point`) was never E0308: it is a struct pattern. decisions/brace-pattern-head.md gives the rule for a brace head.
- ERROR_CATALOG.md gets a row for E0308 `EnumPatternNeedsEnumScrutinee`. The catalog had none.

### Implementation notes

Not spec text.

- The E0308 check must fire before mono. Then the type-parameter case (`plt/p2.bl` `pick`, `None =>` on `x: T`) is a compile error where the generic function is defined, not a run-time panic after mono (Systems).
- gen1 bug `pe2.bl`: `{Dot}` resolves to the variant after an `Int` binder `Dot`. The case becomes E0308 under this ruling.
- gen1 bug `plt/p2.bl` `pick`: gen1 compiles `None =>` on a type-parameter scrutinee as a variant test, accepts the match as exhaustive and panics at run time. This is a soundness bug. The new E0308 removes the program, but the exhaustiveness check should not accept it.
- The typecheck path for `assert_matches` must run the same pattern check as a match arm (DevOps).
- The first-character test uses Unicode `Lu` and `Lt`. A letter with no case (`Lo`) is not uppercase.
- The guard help line appears only when a value of that name is in scope.

### Open cases and follow-ups

- Lowercase variant names: gen1 accepts a lowercase variant, and the spec has no casing rule. A separate `type:spec` ticket asks whether a variant name must start with an uppercase letter. If it says yes, T-lex is the whole rule.
- No named unreachable-arm diagnostic: arms after a catch-all are dead and nothing reports them. A real catch-all `other =>` placed first still gets no report.
- `plt/p2.bl` `pick` soundness bug: the match on a type-parameter scrutinee that gen1 accepts as exhaustive.
- W1011 implementation: its scope shrinks. The pattern-binder branch applies only to irrefutable patterns and to names that do not start with an uppercase letter. Trim the ticket before building.
