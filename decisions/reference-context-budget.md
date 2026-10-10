[< All Decisions](../DECISIONS.md)

# Reference Context Budget — Design Rationale

## Gap

An agent could not load the full language reference into its context. `sections/` was 983,465 bytes, about 245k tokens. `llms-full.md` was 72,163 bytes, about 31k tokens, and people wrote it by hand, so it drifted from the spec. The ticket asked for a normative core under 20k tokens, with `llms-full.md` generated from that core and not written by hand.

## Result

| Question | Result | Vote |
|---|---|---|
| Q1 Source of the core | **A**: marked core blocks in `sections/` with stable semantic IDs; a generator builds `llms-full.md`; `sections/` is the only normative source | 6-0 |
| Q2 Core cap | **46,000 bytes**, hard fail, raised only by a panel vote; bytes per token reported at each release, not checked | 6-0 |
| Q2b Topic and index caps | **CAPS**: 12 KiB per topic, 6 KiB for the index | 5-1 (Minimalism dissent) |
| Q3 API content inside the core | **NAMES**: prelude type and trait names plus one line per prelude trait. An API-shape divergence is a core block in the head list, with a fence that pins the shape; no lib/std marker | Phase C 3-3; Phase D 6-0 |
| Q4 Non-language content | **YES**: install, flags, emit modes, daemon, FFI and arena leave the core; one pointer line per topic; CLI-flag topics generated from the CLI registrations | 6-0 |
| Q5 Checks | **BASE+CLOSURE**: cap, fences compile, error fences fail with the stated code, regen-diff, unique and resolving IDs, diagnostic codes in the catalog, plus closure over explicit references only | Phase C 4-1-1; Phase D 6-0 |
| Q6 Order | **YES**: spec order; divergence list at the head and common-errors list at the tail, each bullet citing a core ID; the inclusion rule is authoring guidance | 6-0 |
| Q7 CLI | **FULL**: `--full` is the core; new `--all`; `--list` shows byte sizes | 6-0 |
| Q8 Model eval | **OUT**: not in the decision; a separate release chore records model ID, sampling settings and a prompt-set hash | Phase C 4-2; Phase D 6-0 |
| Q9 Landing order | **STAGED**: cap today's hand-trimmed file first, then the extractor | 6-0 |
| Q10 "*Rationale (normative)*" label | **DROP**: the two labelled paragraphs in `03_types.md` become `*Rationale.*` | 6-0 |

Phase D ran on Q3, Q5 and Q8. AI-first review: 5/5 pass. The user approved the tally (Q2b split 5-1).

Process note: in Phase C, PLT said it voted without reading the other five Phase B replies, which the ballot required. In Phase D, all six ballots name the other panelists' replies.

Per the Q8 result, the rationale records this: a proposal to raise the core cap should bring compile-rate data from the release eval, with the model ID, the sampling settings and a hash of the prompt set.

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated in independent-proposal → debate → vote rounds. Each panelist's text below is verbatim.

#### Phase A — Independent proposals

**Systems:**

Sys proposals for 2xvan0 (normative core under an in-context budget)

**Framing.** The ticket mixes up two costs. sections/ is about 983 KB, roughly 245k tokens, and most of that is rationale, vote notes and tooling text. An agent never needs those to write correct code. llms-full.md is 72 KB, about 31k tokens, and roughly half of it is per-type method tables (lines 393–850), which are stdlib API rather than language. Go handles this split well: its spec is about 45k tokens, covers no stdlib, and the stdlib API comes from source with `go doc`. Rust's and Zig's references are each several hundred KB and mix both, and nobody can load either one in full. So I accept the 20k figure, but only for the language. The API surface must be generated from lib/std and fetched on demand.

---

**Proposal S1: one source, three tiers, budgets enforced by bytes in CI**

Tiers:

1. **Core (normative, always loaded).** Syntax, types, inference rules, effects, error model, contracts surface, modules and imports, and the trust annotations a user writes. It also holds the prelude signatures: the type and trait names, plus one line per prelude trait. It does not hold method tables.
2. **API (normative, generated, loaded per topic).** One block per stdlib type or module, generated from the `pub` signatures and doc comments in lib/std/*.bl. That is the same data `blink query` and `blink doc` already read. These blocks are never hand-written.
3. **Elaboration (sections/, normative blueprint).** Rationale, edge cases, panel notes and tooling. It stays the full spec, and nobody is expected to load it whole.

**Where the core lives.** Inside sections/, marked in place. It does not go in a separate file, because a second hand-written copy drifts, as llms-full.md already shows (d191er). A core rule is a fenced region:

````
<!-- core:3.2.literals -->
Integer literals have type `Int` unless the expected type is a sized integer.
An out-of-range literal is E0xxx.

```blink
fn main() {
    let a = 42          // Int
    let b: U8 = 200     // U8, checked at compile time
    let n = "hi".len()  // Int
}
```
<!-- /core -->
````

`scripts/gen_llms.sh` concatenates the core regions in section order and appends the generated API index, a list of topics with one-line summaries. `blink llms --full` prints that result. `blink llms --topic List` prints the generated API block for one type. llms-full.md becomes a build artifact; we stop editing it by hand. For release, it gets generated and attached as now.

**Budget, measured in bytes rather than tokens.** Each vendor's tokenizer counts differently and they change between model releases, so a token cap cannot be reproduced. Bytes can. Code-heavy text averages about 3.3 bytes per token, so:

- Core: at most **64 KiB** (about 20k tokens), counted over the extracted output of gen_llms. `task ci` fails if the core goes over.
- Each API topic block: at most **6 KiB**, so one `--topic` call costs under 2k tokens.
- llms.md (the index): at most **4 KiB**. It is about 4 KB today.

The cap is a hard gate. There is no warning stage and no allowlist. A new feature that pushes the core over the cap must cut text elsewhere. That ties this ticket to h313w9 (surface reduction) on purpose: the budget prices the language surface. Go's spec has stayed small for 15 years because adding text to it costs something.

**Mechanical guarantees (all in `task ci`):**

- The extracted core is within its byte cap.
- Every ```` ```blink ```` block in the core and in the API blocks compiles. Blocks marked `// error: E0xxx` must fail with exactly that code. This takes over d191er's proposal.
- Every diagnostic code named in the core exists in the catalog. This extends the W0610 check, which already exists.
- The checked-in llms-full.md (if we keep a copy) equals the generated output, using the same derived-projection check as the bridge-alphabet stanza.
- Every `pub` item in lib/std appears in exactly one API block, which closes xb1crm's omission class.

**Cost.** Agents: about 20k tokens up front, then roughly 2k per API topic they need. A typical task needs 3–5 topics, about 30k total, which is close to today's cost but now complete and correct. Maintainers: a new feature means writing one core region, and the cap makes them justify its size. Build time: one extraction pass plus snippet compiles, a few seconds against the existing corpus.

**Risks.** Markers in sections/ add some noise. A core region can also disagree with the elaboration around it. That is acceptable: both sit in the same file, so a reviewer sees both in one diff.

---

**Proposal S2 (fallback): separate hand-written `sections/00_core.md`**

Same caps and checks, but the core is one file. It is easier to read straight through, and the budget is obvious (`wc -c`). The cost is a second normative text, and every rule then exists twice. I would accept it only with an extra CI rule: every `core:` rule ID must match a heading anchor in sections/. Even then, nothing checks that the wording agrees. **I prefer S1.**

---

**Against parts of the ticket:**

- "Hold the whole normative language in context" is achievable for the language, not for the stdlib. lib/std is already about 231 KB of source, so any budget that includes the API either cuts the API or fails. The API has to be retrieved, not loaded up front.
- Leave install, CLI flags and build modes (llms-full.md lines 1164–1336) out of the core. They describe the tool, not the language. Route them to `blink llms --topic build`.
- Treat FFI (lines 31–153, about 9 KB) as an API topic. Most programs never use it, so it should not take a permanent slot in context.

**Rough core split:** syntax 14 KiB, types and traits 18 KiB, effects and handlers 10 KiB, errors, Result and contracts 8 KiB, modules, trust and annotations 6 KiB, prelude signatures 6 KiB. That totals 62 KiB. If it does not fit, the language is too big, and h313w9 should cut it before we raise the cap.

**Vote position:** S1 with hard byte caps (64 KiB core, 6 KiB per topic) and generated llms-full.md, measured with `wc -c` on the generated output.

**Web/Scripting:**

**Web/Scripting panelist: Phase A proposals for the reference-docs gap**

**Position on the premise.** The problem is real. The proposed fix as worded would leave Blink with two normative texts. If a "normative core" exists next to `sections/`, a user eventually asks which one wins, and you get a Stack Overflow thread on day one. Neither JS nor Python devs learn their language from the normative text. They learn from MDN and the Python tutorial, not ECMA-262 or the language reference. An LLM is in the same position. What it needs is a short text that is always correct. Calling that text normative does not make it correct. Deriving it from the spec and compiling every example in CI does.

My proposals keep `sections/` as the only normative text and make the in-context reference a projection of it, with a size limit that CI enforces.

---

**Proposal W1 (preferred): `core` blocks in `sections/`, llms-full.md generated from them**

1. **Source of truth.** `sections/` stays the only normative text. Authors mark short spans in it as core:
   ````
   <!-- core: option-default -->
   `a ?? b` gives the value in `a` when `a` is `Some`, else `b`.
   `b` is evaluated only when `a` is `None`.
   ```blink
   fn port(cfg: Map[Str, Str]) -> Str {
       cfg.get("port") ?? "8080"
   }
   ```
   <!-- /core -->
   ````
   Each block is one rule of 1–3 sentences plus at most one example. Because the text is copied word for word from the spec, it is normative by origin. No second source exists, so the two cannot conflict.

2. **What else goes into llms-full.md:**
   - **Core blocks**, in spec order, grouped under the current headings (Syntax, Types, Effects, Errors, Modules).
   - **Method tables** (Str, List, Map, Option, Result, and so on), generated from the prelude/stdlib signatures that `blink doc` already reads. Hand-maintained method tables are the main source of drift today (see d191er and xb1crm). Signatures are facts the compiler already holds, so they should never be written by hand.
   - **A short hand-written frame**: a 1-paragraph intro and a "Gotchas" list. Every gotcha must point to a core block id, so the list cannot invent rules.

3. **Size limit.** The generated llms-full.md must stay at or under **20,000 tokens**. `task ci` enforces this as a **byte cap of 46,000 bytes**. This repo's code-heavy markdown runs about 2.3 bytes per token: 72,163 bytes is about 31k tokens. A byte cap keeps CI deterministic and free of a tokenizer dependency. At each release, the release task records a real token count and adjusts the ratio. Exceeding the cap is a CI failure, not a warning, so adding a core block means cutting or tightening another one. That pressure also helps h313w9 (surface size).

4. **What leaves the core:** install, Docker, CLI flags, emit modes, daemon, cross-compile, `blink audit`, `shim init`, and the deeper FFI material (`@ffi.struct`, native dependencies). All of it stays reachable through `blink llms --topic <name>`, under a separate 8k-token cap per topic. Core keeps only `@ffi` and `Ptr[T]` in about 10 lines. Most Blink programs never touch these features, so they should not take up space in the core budget.

5. **Correctness gates in `task ci`:**
   - Every `blink` fence in a core block compiles. If the fence has an `// expect:` line, it also runs and its output matches. This takes over d191er's proposal.
   - Every `core:` id is unique.
   - `llms-full.md` equals what the generator produces. Do not edit it by hand; CI fails if it differs.

6. **CLI.** `blink llms --full` prints the generated core. `--topic` prints the generated topic files. The output format stays the same, so agents already following CLAUDE.md need no changes.

**Tradeoffs (DX view):**
- (+) A model, or a person, reads one 20k-token file and gets rules that are spec text plus examples that compile.
- (+) Spec authors keep writing in one place. Marking text as core is cheap: one comment pair.
- (−) Prose copied out of the spec can read as choppy, because spec sentences assume the text around them. The fix is to write each core block to stand alone, which is a review rule for spec authors.
- (−) The 46KB cap will cause fights over what counts as core. That is the point: the cap forces a decision about the 90% case.

**Cross-language notes.** The TypeScript handbook is what people actually use, and TS dropped its formal spec, so drift between the two stopped being a question. Go is the exception that proves the point: its spec is about 30k words and readable, and its example-heavy core is what people quote. Rust's "Reference vs Book" split shows the failure mode: the Book drifts and nothing checks it.

---

**Proposal W2 (fallback if the panel insists on a separately normative core): `sections/00_core.md`**

- A new spec file, normative, capped at 46,000 bytes by the same CI check.
- Rule: every other section *elaborates* on core and may not contradict it. CI checks that every `core:` id is cited by at least one later section.
- llms-full.md = `00_core.md` + generated method tables, built by the same generator as W1.

I rank W2 below W1. It puts the same rule in two places, written in different words, which is exactly the drift we are trying to stop. Pick it only if the panel judges that W1's copied blocks read too badly.

---

**What I reject:**
- **Summarising `sections/` with an LLM at build time.** The output changes from build to build, nobody can review it, and it can invent rules.
- **Keeping a hand-written llms-full.md and only adding a size check.** That leaves d191er and xb1crm unfixed.
- **Leaving the cap unenforced.** A size limit stated in docs will be exceeded within two releases.

**Vote preference:** W1 > W2 > status quo.

**PLT:**

**PLT panelist: Phase A proposals for 2xvan0**

**Position on the premise.** The ticket is right that the model needs the whole normative language in context. It is wrong to treat "core" and "llms-full.md" as two documents to keep in sync. If you have two normative texts, they will disagree, and then the language has no definition, only two drafts. Haskell 98 avoided this. The Report defines a small kernel, and each derived form is given as a translation into that kernel. The Definition of Standard ML fits static and dynamic semantics into about 100 pages because rationale lives in a separate *Commentary*. Go's whole spec is about 25k tokens. A sub-20k core is possible only if (a) rationale, tooling and stdlib API are out of scope and (b) derived forms are written as translations, not as their own prose.

---

**Proposal P1: Kernel + derived forms, as one source with a projection (recommended)**

*What is normative.* Exactly three kinds of marked blocks in sections/:
1. **Rule blocks**, each with a stable ID (the C++ standard's `[stmt.return]` labels are the model), e.g. `[types.match.exhaustive]`. A rule states one typing, evaluation or well-formedness rule.
2. **Derivation blocks**, which define a surface form by translation into kernel forms. Example:

   ```
   [effects.try.desugar]
   e?  ≡  match e { Ok(v) => v, Err(x) => return Err(x) }
   ```
   The derived form then needs no typing rule of its own. Its typing follows from the kernel's typing of `match` and `return`. That is compositional by construction, and it is the main way to get under budget: much of 02_syntax becomes one-line translations.
3. **Diagnostic bindings**: each rule names the diagnostic code it raises when violated (`E####`). These bind to the catalog that W0610 already checks.

Everything else is non-normative: rationale, panel-vote notes, extended examples, tooling/CLI, and implementation commentary. That includes the "*Rationale (normative)*" paragraphs. Each one is either a rule (rewrite it as a rule block) or it is not normative (drop the label). "Normative rationale" is a category error.

*Where it lives.* It stays in sections/. The core is **extracted** (`blink llms --core`, generated at build time) by concatenating rule, derivation and diagnostic blocks in section order. It is never hand-written. The full spec is defined as a **conservative extension** of the core: it may add explanation, examples and rationale keyed to rule IDs, but no `must`/`must not`/`is an error` sentence may appear outside a rule block. A CI lint checks this lexically.

*Size.* The extracted core must be ≤ 45,000 bytes. Measured: llms-full.md is 72,163 B ≈ 31k tokens, about 2.3 B/token for this code-heavy text, so 45 KB ≈ 19.5k tokens. Enforce on bytes, not tokens, because a byte count is deterministic and does not depend on any tokenizer version. Record the ratio in the check's comment and re-measure it when a tokenizer changes. `task ci` fails above the limit. That makes surface growth (h313w9) show up as a measured cost: a new feature has to pay for itself in core bytes.

*Consistency checks (all in `task ci`):*
- **Closure.** Every term and rule ID that the core references is defined in the core. An extracted core that points into rationale is not self-contained, so the build fails.
- **Example soundness.** Every code fence in a rule block compiles and runs. A fence tagged `expect E0306` must produce exactly that diagnostic. This covers d191er for the core.
- **Rule coverage.** Every rule ID is cited by at least one tests/ file (`// rule: [types.match.exhaustive]`), and every cited ID exists. This is the only checkable link between the spec and the compiler, and it doubles as a spec-coverage metric.
- **Derivation agreement** (later work, not MVP): for derivations, a test asserts that the sugar and its expansion typecheck and run the same.

---

**Proposal P2: Split language from library, each with its own budget**

The model must *hold* the language. It may *retrieve* the library. The stdlib method tables and per-type APIs in llms-full.md are signatures, not semantics. Generate them from lib/std declarations through the `blink doc` / `blink query` machinery, with a separate budget (say ≤ 40 KB for prelude-visible types only), served by `blink llms --api`. A signature generated from source cannot drift from it. xb1crm then becomes a generator coverage check, not a hand edit.

`llms-full.md` = extracted core (P1) + generated prelude API (P2) + a short non-normative "patterns/gotchas" appendix with a hard cap (≤ 8 KB, every snippet compiled). Install, FFI how-to and CLI flags move to `blink llms --topic tooling`, outside the core. 06_tooling is not language semantics.

---

**Proposal P3 (rejected alternative, for the record): hand-curated short core plus a "full spec prevails" clause**

This is the ticket's proposal as written. I reject it. The precedence clause makes the short core non-normative in fact, because any reader has to check it against 245k tokens to know it is true. That defeats the principle the ticket starts from, and CI cannot check "the summary is faithful". Do not adopt it.

---

**Tradeoffs from the PLT side**
- P1 forces a real kernel/derived split. This will expose surface forms that cannot be written as a translation, i.e. forms with their own semantics. That is a feature: each one is a candidate for h313w9 or a missing kernel rule. Cost: rewriting the rules in 02/03/04 is substantial work.
- Rule IDs must stay stable: renumbering breaks tests and decision links. Use semantic IDs, never section numbers.
- 45 KB is tight. If the kernel cannot fit, that is evidence the language is too big. It is not grounds to raise the limit quietly. Raising it should need a panel vote.
- The prose/rule split depends on the authors' discipline. The lexical `must` lint catches most leaks but not implicit rules in examples. Rule-coverage tests are the backstop.

**Cross-language:** Haskell Report (kernel + translation scheme), SML Definition plus a separate Commentary (rules apart from rationale), C++ standard (stable bracketed rule labels), Go spec (an existence proof that about 25k tokens is enough for a complete production language spec), and Koka's small core calculus with surface sugar.

**Vote I am arguing for:** P1 + P2 together. Reject P3.

**DevOps:**

I recommend Proposal 1, which splits the reference into tiers with separate budgets. Proposals 2 and 3 are needed to make that budget hold over time.

**Premise check.** "20k tokens" can't be enforced in CI because token counts depend on the tokenizer. CI can't call a model API, and pinning a tokenizer version is a hidden dependency. Measured here, llms-full.md is 72,163 bytes for about 31k tokens, so about 2.3 bytes per token, since code-heavy text tokenizes densely. The cap should therefore be in **bytes**, with the token figure only a calibration note.

Today llms-full.md mixes four kinds of content:
- normative language rules
- stdlib method tables
- CLI and build flags
- install steps

Only the first belongs under a "hold the whole language in context" budget. The method tables (about 300 lines, `## String Methods` through `## Instant Methods`) and the build flags are reference data. An agent can look them up, and the toolchain already has the source of truth for them.

---

##### Proposal 1: three tiers, each with a size cap

| Tier | Command | Content | Hard cap (bytes, checked in `task ci`) |
|---|---|---|---|
| T0 | `blink llms` | orientation (today's llms.md) | 6 KiB |
| T1 | `blink llms --core` | the **normative language core**: syntax, types, effects, contracts, modules, error model, one way per construct | **44 KiB** (about 19k tokens at 2.3 B/tok) |
| T2 | `blink llms --topic X`, `blink doc std.X` | stdlib APIs, method tables, CLI flags, FFI detail, install | no global cap; 12 KiB per topic |

`--full` stays and prints T1 plus all of T2. It is only for convenience and has no budget promise. The CLAUDE.md template text in `cmd_init` (src/cli.bl:4369) changes to "Load `blink llms --core` once. Use `--topic` / `blink doc` for APIs."

**Where it lives.** The T1 source is `sections/00_core.md`, which is normative and in the spec. It is written for density, not argument. The other sections stay the blueprint and the place for rationale. The rule: **when 00_core and a later section conflict, the spec has a bug, and the panel must fix it.** That is the same rule the bridge-alphabet decision uses for projections.

---

##### Proposal 2: generate the bulky parts, hand-write only the rules

"Generate llms-full.md from the core, not by hand" is half right. You can't mechanically extract a readable core from 245k tokens of mixed rationale. Pulling out paragraphs tagged "normative" gives fragments with no flow. Instead:

- **Hand-written:** `00_core.md` (prose rules + examples).
- **Generated:** every table that has a single source in the compiler:
  - **Method tables:** from the prelude/stdlib signatures, using the same data `blink doc` reads.
  - **CLI flags:** from the `add_command`/`command_add_flag` registrations in src/cli.bl (around line 5033).
  - **Diagnostic codes:** from the catalog (the W0610 check already matches against it).
- **Assembled:** `scripts/gen_llms.sh` (later `blink llms --emit`) builds `llms-full.md` from `00_core.md` plus the generated topics. CI runs it and fails on any diff. This is the same pattern as `gen_embedded_stdlib.sh` and the registry check that already exist.

This removes most of the hand-maintained drift surface. d191er (contradictions) and zj4jgw (commands the CLI does not have) then become impossible for generated tables, not just detectable.

---

##### Proposal 3: CI enforcement in `task ci`

Four checks, each with an actionable message:

1. **Size cap:** fail if `00_core.md` (rendered T1 output) is over 45056 bytes.
   ```
   error[DOC001]: llms core is 46,210 bytes; budget is 45,056 (44 KiB)
     largest sections: §Effects 9,812  §Types 8,440  §Contracts 6,120
     help: move API detail to a --topic, or cut a rule (needs panel vote)
   ```
   A budget increase needs a panel vote, recorded in DECISIONS.md.
2. **Snippets compile:** every fenced `blink` block in T1/T2 runs through `blink check`. Blocks marked `blink,fail(E0306)` must fail with exactly that code. This is the d191er proposal; it belongs in the same gate.
3. **Rule anchors resolve:** each core rule carries an ID, and each ID must name a real heading in sections/:
   ```
   ### If expressions {#core.syntax.if}
   See: §2.9
   ```
   The checker fails on a dangling `§` reference or a sections/ heading tagged `{core}` that has no core rule.
4. **Regeneration diff:** generated topics must equal the committed file.

Example core entry, showing the target density. The body is one rule, one example and no rationale:

```blink
// Core 2.9: `if` is an expression; both arms must have the same type.
fn sign(n: Int) -> Str {
    if n < 0 { "neg" } else { "non-neg" }
}
```

---

##### Tradeoffs (tooling view)

- **Byte cap vs. true tokens.** Bytes are deterministic and need no dependency, but the ratio shifts as the prose/code mix changes. Recalibrate at each `task ci-release` and log the measured ratio in the release notes; don't make CI depend on it.
- **A second normative text means two places to edit.** That is real cost. The anchor and snippet checks make drift loud, but they can't prove two prose rules agree semantically. The alternative, rule-tagged extraction from sections/, keeps one copy but gives an unreadable artifact, so I reject it.
- **The 44 KiB cap may not fit the current surface.** Effects plus types alone may not fit. If so, that is a real signal for h313w9 (surface reduction), not a reason to raise the cap. The DOC001 per-section breakdown shows where the size goes.
- **LSP/tooling bonus:** rule IDs (`core.syntax.if`) let diagnostics link to the rule. `blink explain E0306` can print the core rule and its `§` reference, which pays for the anchor work twice.

##### Cross-language note

The Rust Reference and the Ferrocene Language Spec added stable rule IDs (`r[expr.if.cond]`) for this reason: tooling and tests can cite and check individual rules. Go keeps the spec to one document of about 110 KB with no rationale; rationale lives in design docs and the FAQ. That is the model for "core vs. sections/ rationale," at roughly half Go's size. `go doc` holds the API surface outside the spec, which is the T2 split proposed here.

**Vote position:** for a normative core under a CI-enforced byte cap, with tables generated from compiler sources. Against deriving the core by extraction from sections/.

**AI/ML:**

**AI/ML panelist, Phase A: proposals for 2xvan0**

**Premise check.** The ticket says the model must hold the whole normative language in context. That is half right, and both halves matter.

- Current windows (200k to 1M) could technically hold sections/ (about 245k tokens). The real limits are different:
  - **Attention dilution and lost-in-the-middle.** Recall of rules buried mid-context drops measurably.
  - **Competition with the user's code.** An agent session spends its context on the codebase, tool output and a plan. A reference that costs 30k+ tokens in every session gets dropped or truncated by harnesses.
- A model writes code mostly from examples and from its pretrained priors. Prose rules mostly decide edge cases. A good in-context core is therefore not "the spec, made smaller". It is the set of facts where Blink differs from what the model already believes, plus enough examples to anchor the syntax.

So I support a small core of about 20k tokens. I reject calling it "the normative language". sections/ stays the only normative source. The core is a **derived, normative-consistent subset**: every statement in it must be true per the spec, and it is not complete.

---

**Proposal 1: three tiers, with byte budgets that CI enforces**

| Tier | File | Hard cap | Approx. tokens | Loaded |
|---|---|---|---|---|
| 0 | llms.md | 6 KB | ~2.5k | always (key facts, links) |
| 1 | llms-full.md (the core) | 48 KB | ~20k | default for any code generation |
| 2 | `blink llms --topic X`, sections/ | none | — | on demand, by retrieval |

**How to measure: bytes, not tokens.**
- There is no neutral tokenizer. Each model family counts differently, and pinning tiktoken or Claude's tokenizer adds an external, versioned dependency to `task ci`.
- Bytes are deterministic and need no dependency.
- I calibrated the ratio on the current file: 72,163 bytes is about 31k real tokens, so about 2.3 bytes per token for code-heavy markdown. 48 KB × (1 / 2.3) ≈ 20.9k tokens, which is close to the ticket's target.
- The CI check is one line: `wc -c llms-full.md <= 49152`.
- At each release the release task records the measured token count for two reference tokenizers in CHANGELOG. This is a report, not a gate, so drift in the ratio shows up.

**Why a hard cap.** Without one, every "xb1crm: add missing feature" fix grows the file without limit. A cap forces a trade: to add a rule, demote another rule to Tier 2.

---

**Proposal 2: generate the core. Never write it by hand.**

The core comes from three sources, and the generator joins them in a fixed order:

1. **Prose rules come from sections/ through markers.** Mark the core-relevant paragraphs in place:
   ```
   <!-- core:strings -->
   Strings use double quotes only. Interpolation is universal: "Hello, {name}!".
   There is no `+` on Str; use interpolation or `.concat()`.
   <!-- /core -->
   ```
   The generator extracts the marked blocks into llms-full.md under the given topic. Panel-vote notes, rationale and tooling text are never marked, so they never cost tokens.
2. **Method tables come from the compiler.** Signatures come from the same registry that `blink doc` uses. They are the largest single cost in llms-full.md today and the part most likely to drift (d191er). The compact form is one signature per line, with no prose unless the name is ambiguous:
   ```
   List[T].get(i: Int) -> Option[T]
   Map[K, V].remove(k: K) -> Option[V]
   ```
3. **Examples come from compiled files.** Every code block in the core is pulled from `docs/core/*.bl` files that `task ci` compiles and runs. This closes d191er by construction.

Then the precedent applies: CI regenerates the core and diffs it against the checked-in file, the same way the embedded stdlib registry is checked. A hand edit to llms-full.md fails CI.

---

**Proposal 3: choose and order core content by how far it departs from model priors**

**Inclusion rule.** A rule goes in the core if, and only if, a capable model with no Blink knowledge would probably get it wrong. Examples:
- `io.println` and not `print`
- no string `+`
- `[T]` generics
- `m.insert(k, v)` and not `m[k] = v`
- `Float` has a total order (`NaN == NaN`)
- keyword parameters after `--`
- `E0301` on an untyped `[]`

Rules that match Rust, Python or Go priors (`if`, `for`, closures, match arms) get one example and no prose. This is where most of the token savings come from.

**Ordering, to work around lost-in-the-middle:**
1. Prior-divergence list first, as about 40 bullets.
2. Syntax by example.
3. Types and effects.
4. Method tables.
5. A short "most common errors" list last, with code and fix.

The head and the tail get the strongest attention, so the facts that a model most often gets wrong sit at both ends. The middle holds reference tables, which a model looks up rather than recalls.

**Example density.** About 40% of the bytes should be compiled code. One correct 6-line program teaches more than 200 words of rule text.

```
fn main() ! IO {
    let names: List[Str] = ["a", "b"]
    for n in names {
        io.println("hi {n}")
    }
}
```

---

**Proposal 4: an empirical check (advisory, not a gate)**

Keep a fixed suite of about 50 task prompts in `docs/core/eval/`. At each release, a script runs a reference model with only Tier 0 and Tier 1 in context and records first-try compile rate and test-pass rate. Track the trend in CHANGELOG.

It is not a CI gate because model calls are non-deterministic and cost money. But it is the only real measure of whether the core is the right 20k. Byte caps measure size, not coverage.

---

**Tradeoffs**
- **Markers in sections/ make the spec noisier.** Markers are HTML comments, invisible when rendered. The cost is small next to the cost of drift, and the alternative (a second hand-written file) is the problem this ticket exists to fix.
- **The 48 KB cap will hurt.** Some features will live only in Tier 2. That is acceptable if `--topic` retrieval is reliable. Make topic names match core section headings exactly, so the core can say "see `blink llms --topic ffi`", and an agent learns the retrieval path from the core itself.
- **This interacts with h313w9 (surface reduction).** Each feature removed from the language gives back core budget. The cap makes the cost of a large surface visible.
- **The token ratio may drift** as the content mix changes. The per-release report catches that.

**Cross-language notes**
- The Go spec (about 25k tokens) proves that a whole-language spec near this size is possible, but Go has no effects and no contracts.
- Gleam's language tour shows that example-first teaching works well for models.
- Zig's langref (over 150k tokens) is the counter-example: models routinely write stale Zig because nobody loads the full reference.
- The llms.txt convention (llms.txt plus llms-full.txt) already expects exactly this two-tier split, so Blink keeps its file names and tooling.

**Recommendation.** Adopt Proposals 1, 2 and 3 as normative process: the caps, the generation and the CI diff check. Adopt Proposal 4 as an advisory release step. Reword the ticket from "normative core" to "derived core, consistent with the spec".

**Minimalism:**

**Minimalism (Min): Phase A proposals for gap 2xvan0**

**Premise check.** The ticket asks for a "normative core under 20k tokens" and wants llms-full.md generated from it. That creates a second normative text. Two normative texts will drift, and "which one wins?" becomes a new spec question. sections/ is normative and it is the blueprint. It does not need to fit in context, just as nobody loads ISO C into a prompt. What has to fit is the text an agent reads to write correct code, and that text is llms-full.md. So the fix is to cut and cap llms-full.md, not to add a third layer.

Measured facts. llms-full.md is 72,163 bytes, about 31k tokens, or about 2.3 bytes per token because it holds a lot of code. Four of its sections are not language at all: Build & Run (6.9k), FFI (6.4k), Arena (5.3k) and Install. Together they are about 19k bytes, roughly 26%. The hand-kept method and stdlib tables (Namespace Methods, the per-type tables and Standard Library) are about 25k bytes more, roughly 35%, and they duplicate lib/std signatures that `blink doc` can already print.

---

**Proposal M1 (preferred): cap llms-full.md, cut what is not language, add no new document**

Normative text goes in §6 (tooling), as one short paragraph:

1. `blink llms --full` prints the **agent reference**, an *informative* summary of the language. When it conflicts with sections/, sections/ wins and the conflict is a bug.
2. The agent reference has a hard **budget of 20,000 tokens**. Tokens are not portable across models, so `task ci` enforces a byte proxy of **46,000 bytes** (20k × 2.3, today's measured ratio). The test fails the build if the file grows past the cap. Any change to the cap needs a panel vote, because the cap is a statement about how big the language surface is.
3. Content rule: the agent reference holds only what an agent needs to write correct code. That means syntax, the type system, effects, contracts, modules, error handling, a short gotchas list, and one line per stdlib module. These topics move out to `blink llms --topic <name>` and do not count against the budget: install, the CLI and build flags (`blink --help` already covers them), FFI, arena details, and release notes.
4. Per-type method tables leave the hand-written file. `blink doc <module>` and `blink doc <Type>` print them from lib/std signatures, so they cannot drift.

This adds no new machinery beyond one byte-count check. The snippet-compile check belongs to d191er, and this proposal leans on it rather than repeating it.

How it reads to an agent:

```
$ blink llms --full          # ≤ 20k tokens, the whole language
$ blink llms --topic ffi     # pulled only when needed
$ blink doc List             # generated method table
```

```blink
fn main() {
    let xs = [1, 2, 3]
    println("{xs.len()}")
}
```

An agent writes this from the core. It looks up `List.windows` with `blink doc List` and does not hold every method in context.

**Tradeoffs.**
- The budget becomes a ratchet on language growth, and I count that as a feature. If a new feature cannot be explained inside 20k tokens, the panel has to cut something or pay for the addition out loud. This ties directly to h313w9 (surface reduction), whose subtraction work then shows up as headroom under the cap.
- llms-full.md stays hand-written, so drift between it and the spec stays possible. d191er (compile every snippet) and the existing W0610 catalog check cover the worst axes. I accept the remaining risk over building an extractor.
- A byte proxy is crude. It is also deterministic, adds no dependency and is easy to read in CI output. Re-measure the ratio once per edition, not per commit.

---

**Proposal M2 (fallback, if the panel insists on derivation): mark core spans in sections/ and extract them**

If the panel wants llms-full.md generated rather than hand-kept, do the minimal version:
- Wrap each core passage in sections/ with a fence: `<!-- core -->` … `<!-- /core -->`.
- A script concatenates the fenced passages, in file order, into the generated part of llms-full.md. The output must be byte-identical to the committed file. This follows the llms.txt `language:` stanza precedent: a derived copy, checked by test.
- The same 46,000-byte cap applies to the extracted output.
- Rationale paragraphs, panel-vote notes and tooling text may not sit inside a core fence.

**Cost.** Every spec edit now carries a second question: is this core? The spec prose also has to read well with no surrounding text, which sections/ is not written for today. I count this as heavier than M1 and only weakly better, because spec prose is written to settle edge cases, not to teach an agent.

---

**Proposal M0 (stated so it gets a vote): reject the ticket as framed**

The principle "the model must hold the whole normative language in context" is wrong as stated. No human or model holds all of ISO C++ in context either. What matters is that the *teaching* text fits and stays honest. If the panel agrees, close 2xvan0 into d191er and xb1crm, plus a one-line budget check. I would accept M0+M1 merged as the outcome.

---

**Cross-language notes**
- Go has a spec of about 100 pages and a "Tour" that is separate and informative. Nobody calls the Tour normative, and it does not drift into a second spec.
- Lua 5.4's reference manual is around 100 pages, and the language stays small because the manual stays small. The size of the doc acts as the brake on the language.
- R5RS is about 50 pages.
- The C++ committee is the cautionary tale: the standard grew past what any one reader can hold, and no reference document fixes that after the fact.

---

**Vote position.** M1 first, M0 acceptable in combination with M1, M2 only as a fallback. I oppose a separate normative "core" document in any form.

#### Phase A.5 — Mechanical dedupe

All six full Phase A texts, verbatim: scratchpad/panel/{sys,web,plt,devops,aiml,min}_A.md
(same directory as this file). Read them before replying.

##### Q1 — Source and status of the in-context reference

- **Option A — marked core spans in sections/, extracted by a generator; sections/ is the only normative source; llms-full.md is a generated artifact checked by regen-diff.**
  Proposed by: Sys (S1), Web (W1), PLT (P1), AI/ML (P2); Min lists it as fallback (M2).
  Variations to settle:
  - A-kernel (PLT P1): blocks are typed (rule / derivation / diagnostic binding) with stable semantic IDs like `[types.match.exhaustive]`; derived forms written as translations into kernel forms; no `must`/`must not`/`is an error` sentence outside a rule block (lexical CI lint); "*Rationale (normative)*" label removed; closure check; every rule ID cited by a tests/ file.
  - A-plain (Sys S1, Web W1, AI/ML P2, Min M2): `<!-- core:id -->` … `<!-- /core -->` comment fences around prose + example; no kernel/derivation discipline.
  - Example source: inline fences in the core block (Sys, Web, PLT) vs. pulled from compiled `docs/core/*.bl` files (AI/ML P2.3).
- **Option B — a separate hand-written normative file `sections/00_core.md`; other sections elaborate; a conflict is a spec bug; rule IDs must anchor to sections/ headings.**
  Proposed by: DevOps (P1/P2, preferred). Listed as fallback by Sys (S2) and Web (W2).
  DevOps text: "You can't mechanically extract a readable core from 245k tokens of mixed rationale."
- **Option C — keep llms-full.md hand-written and *informative*; sections/ wins on conflict; trim and cap it; no new document or extractor.**
  Proposed by: Min (M1, preferred). Min M0: close 2xvan0 into d191er + xb1crm plus a budget check ("M0+M1 merged").
  PLT P3 describes the same shape as "hand-curated short core plus a 'full spec prevails' clause" and rejects it.

##### Q2 — Budget: unit and number

- Unit: bytes, checked in `task ci`, hard fail, no allowlist — all six agree. Token figure only as calibration.
- Core cap numbers proposed (differ):
  - 44 KiB = 45,056 B (DevOps), 45,000 B (PLT), 46,000 B (Web, Min), 48 KiB = 49,152 B (AI/ML) — all at 2.3 B/token.
  - 64 KiB (Sys) — at "about 3.3 bytes per token".
- Per-topic cap: 6 KiB (Sys), 8k tokens (Web), 12 KiB (DevOps), none (AI/ML), not stated (PLT, Min).
- llms.md cap: 4 KiB (Sys), 6 KiB (DevOps, AI/ML).
- Raising the core cap needs a panel vote: stated by Min, DevOps, PLT.
- Ratio re-measurement: per release (Web, DevOps, AI/ML report two tokenizers in CHANGELOG), per edition (Min), on tokenizer change (PLT).

##### Q3 — Stdlib method tables / API

- All six: generated from lib/std signatures (the data `blink doc` / `blink query` read), never hand-written.
- Variation — inside or outside the core cap:
  - Outside the core budget, fetched on demand (`--topic` / `blink doc`): Sys, DevOps, Min.
  - Inside the capped llms-full.md: Web (W1.2), AI/ML (P2.2, ordered 4th in P3).
  - Separate budget "≤ 40 KB for prelude-visible types only" via `blink llms --api`: PLT (P2).
  - Sys adds: core holds prelude type/trait names plus one line per prelude trait; every `pub` lib/std item appears in exactly one API block.

##### Q4 — Non-language content (install, CLI/build flags, emit modes, daemon, FFI detail, arena)

- All six: out of the core, reachable via `blink llms --topic <name>`.
- Variation: Web keeps `@ffi` and `Ptr[T]` in about 10 core lines; Min also moves arena detail out; DevOps generates CLI-flag topics from cli.bl registrations.

##### Q5 — CI checks beyond the cap

- Every `blink` fence compiles; error-tagged fences must fail with exactly that code: Sys, Web, PLT, DevOps, AI/ML. Min: leave to d191er.
- Regen-diff (committed artifact equals generator output): Sys, Web, DevOps, AI/ML, Min (M2).
- Unique / resolving rule IDs: Web, PLT, DevOps.
- Diagnostic codes in the core exist in the catalog (extend W0610 check): Sys, PLT.
- PLT only: closure check; `must` lint; rule-coverage citations from tests/.
- Sys only: every lib/std `pub` item in exactly one API block.

##### Q6 — Content selection and ordering (AI/ML P3)

- AI/ML: include a rule iff a capable model without Blink knowledge would probably get it wrong; prior-divergence list first, common-errors list last; about 40% compiled code. No other panelist addressed this.

##### Q7 — CLI surface

- DevOps: new `blink llms --core` is the budgeted tier; `--full` = core + all topics, no budget promise; cmd_init CLAUDE.md text changes.
- Sys, Web, Min, AI/ML: `--full` itself is the budgeted core.

##### Q8 — Advisory eval (AI/ML P4)

- AI/ML: ~50 fixed task prompts; at each release, record first-try compile rate with only Tier 0+1 in context; advisory, not a gate. No other panelist addressed this.

#### Phase B — Debate (round 1)

All six replies ended STABLE; the panel went to the vote after one round.

**Systems:**

**Sys, Phase B round 1**

**Concession first (Q2).** My 64 KiB cap rested on a guess of 3.3 B/token. The measured figure is 2.3 B/token (72,163 B ≈ 31k tokens), so 64 KiB is about 28k tokens, which misses the ticket's target. I withdraw it and take **46,000 B** (Web, Min). The 44/45/46/48 KiB numbers differ by under 2k tokens, so the exact figure is noise; 46,000 is the round number at 20k × 2.3. I agree with Min, DevOps and PLT that **raising the cap needs a panel vote**, and with Web, DevOps and AI/ML that the release task **reports** real token counts without gating on them.

**Q1: A-plain, plus three PLT pieces. Against B and C.**

- **Against C (Min M1).** A hand-written "informative" llms-full.md with "sections/ wins" is exactly the arrangement that produced d191er (P1: it contradicts the spec). PLT P3 makes the right point: if an agent has to check the summary against 245k tokens to trust it, the summary does nothing for it. A byte cap on a hand-kept file controls size, not truth.
- **Against B (DevOps).** DevOps writes "you can't mechanically extract a readable core." Extraction does not mean pulling out existing paragraphs. Each core block gets written to stand alone (Web's review rule) and placed inside sections/ next to its elaboration. That gives one copy, edited in one diff. 00_core.md gives two copies of every rule in different words, and DevOps admits no check can prove they agree. Readability is a writing discipline; drift is a structural flaw. I take the cost that can be fixed.
- **From PLT I take:**
  1. Stable semantic IDs (`core:types.match.exhaustive`), never section numbers.
  2. Diagnostic bindings checked against the catalog. This extends the W0610 check, which already exists.
  3. Dropping the "*Rationale (normative)*" label: each such paragraph is either rewritten as a rule or stops claiming to be normative.
- **From PLT I reject for the MVP:**
  1. The kernel/derivation rewrite. It is good design, but it rewrites 02/03/04 and blocks this ticket on months of spec work. Let it come in block by block where it saves bytes; the cap will push that way.
  2. The lexical `must` lint. sections/ uses "must" in rationale and in tooling text, so it will produce false positives at once and people will learn to dodge the word. The gate would be noisy and teach nothing.
  3. The closure check. Defer until IDs are stable.
  4. Rule-coverage citations from tests/. Worth a follow-up chore, not a gate on day one.

**Example source (Q1 variation).** Use inline fences inside the core block, compiled by extraction. AI/ML's `docs/core/*.bl` puts the rule and its example in two files, which makes a second drift axis.

**Q3: tables outside the core cap.** Min measured the method and stdlib tables at about 25k of the 72k bytes. Web W1.2 and AI/ML P2.2 put them **inside** the 46,000 B cap. That leaves about 21k bytes (about 9k tokens) for the whole language, effects and contracts included, which cannot work. The tables have to be retrieved: `--topic` or `blink doc`, generated from lib/std. PLT P2's separate prelude-API budget is the same idea and I accept it. I withdraw my "every pub item in exactly one block" check: if the generator emits every pub item, the check is a tautology.

**Per-topic cap.** 6 KiB is about 2.6k tokens, too small for List or Str with their signatures. I move to **12 KiB** (DevOps), about 5k tokens. One topic call should stay a small, predictable cost.

**Q4.** Agreed: tooling, install, CLI flags, arena and FFI detail go out of the core. Web's ~10 lines of `@ffi`/`Ptr[T]` cost about 1 KB. I don't object, but they must pay for themselves under the cap like everything else.

**Q5.** Every core and topic fence compiles; error-tagged fences fail with exactly the stated code; the regen diff must be clean; IDs must be unique. Min's "leave snippets to d191er" splits one gate across two tickets for no gain. This ticket's generator is where that check belongs.

**Q6 (AI/ML ordering).** I accept the inclusion rule ("include a rule only if a model would get it wrong") as authoring guidance, not a gate. For ordering, the generator can emit blocks tagged `core:diverge.*` first and `core:errors.*` last, with everything else in spec order. That is cheap and deterministic, so I support it.

**Q7: side with DevOps.** Add `blink llms --core` as the budgeted tier; `--full` becomes everything, with no budget promise. Reason: a name should state its cost. If `--full` quietly turns into "partial", any agent following the old CLAUDE.md text loses the tables with no signal. Update the cmd_init template and the project CLAUDE.md to say `--core`.

**Q8.** Fine as an advisory release step. It is process, not spec, so keep it out of the vote text, or record it as non-binding.

**My vote shape:** A-plain + PLT IDs/diagnostic binding + label removal; core 46,000 B hard cap (raising it needs a panel vote); tables generated and outside the cap; 12 KiB per topic; llms.md 6 KiB; `--core` as the new budgeted flag.

**Web/Scripting:**

**Web, Phase B round 1**

**Q1: Option A-plain. I drop my W2 fallback.**

- **Min (C/M1).** Min's own example disproves M1. `println("{xs.len()}")` fails `blink check` today with `error[UndefinedFunction]: undefined function println`, because Blink spells it `io.println`. That snippet was hand-written by a careful author while arguing that hand-written is safe enough. d191er's compile check would have caught that one, but no compile check catches prose that is *wrong but compiles* ("Map.remove returns Bool"). Only a single source catches that. "sections/ wins on conflict" just means the model must check 245k tokens to trust 20k, which is PLT's P3 objection, and I agree with it.
- **DevOps (B).** "You can't extract a readable core from mixed rationale" is the strongest argument against A. I concede the risk, but not the conclusion. B does not remove the readability work. It moves the work into a second file whose words nobody checks against the spec. A-plain makes authors write each core block so it stands alone, which also improves the blueprint. DevOps's own anchor check "can't prove two prose rules agree". A has nothing to prove.
- **PLT (A-kernel).** I accept **stable semantic IDs** (`core:types.match.exhaustive`). They are cheap and pay off in `blink explain` (DevOps's point). I reject making derivation notation the reader-facing form. `e? ≡ match e { ... }` is exact, but a JS/Python dev, and a model trained on them, learns `?` from a 4-line example, not from a translation scheme. A derivation may *appear* inside a block next to an example. It must not *replace* the example. The `must` lint, closure check and rule-coverage citations are good later work but not MVP. File them as follow-ups, not as gates on this ticket.
- **Example source (AI/ML).** Use inline fences compiled by CI rather than `docs/core/*.bl`. Rule and example then sit in one diff, with no file to cross-reference. Either way meets d191er. I won't block on it.

**Q2: budget.** Sys's 3.3 B/token conflicts with the measured repo figure (2.3). 64 KiB ≈ 28k tokens, which misses the ticket's target by 40%. I will move from 46,000 to **45,056 B (44 KiB)** to converge with DevOps/PLT. Any value from 44–46 KB is fine with me; 48 KiB is too loose. Raising the cap needs a panel vote (Min, DevOps, PLT): agree. Per-topic cap: I concede to DevOps's **12 KiB**. llms.md: 6 KiB. Re-measure the ratio at each release and report it; it is not a gate.

**Q3: method tables. I partly revise my position.** Sys, DevOps and Min are right that the full tables do not belong in the core: they are about 35% of today's file. But the 90% case is Str/List/Map/Option/Result, and models guess (`.length()`, `.push_str()`, `m[k] = v`) instead of making a lookup call. Proposal: the core holds a **generated** signature list, one line per method in AI/ML's compact format, for the **prelude collection and error types only**: Str, List, Map, Set, Option, Result. It counts against the 44 KiB cap. Every other type and module goes through `--topic` / `blink doc`. This is Sys's "prelude signatures" tier taken one step further, and it stays generated, so it cannot drift.

**Q4.** I drop my "10 lines of FFI". The core gets one pointer line: "FFI: `blink llms --topic ffi`". Arena moves out too (Min). I back DevOps's plan to generate CLI-flag topics from cli.bl registrations, which closes zj4jgw for the generated part.

**Q5.** Yes to: compile every fence, with exact-code failure for tagged fences; regen-diff; unique and resolving IDs; diagnostic codes present in the catalog (an extension of W0610). Defer PLT's extra checks (see Q1). Defer Sys's "every pub item in exactly one API block" to the API-topic follow-up. It does not apply to the core.

**Q6: AI/ML ordering. Strong yes.** Put the prior-divergence list first and the common-errors list last. This is the DX "Gotchas" section done right. It reconciles with extraction like this: the head and tail lists are the only hand-written frame, and **every bullet must cite a core ID** (my W1 rule, checked by the ID-resolve check). The body stays in spec order. The selection rule ("include it if a model would probably get it wrong") is good review guidance for authors, not something CI checks.

**Q7.** Keep `--full` as the budgeted core (Sys, Min, AI/ML). Every CLAUDE.md out there, this repo's included, already says `blink llms --full`. Redefining it as "no budget promise" (DevOps) quietly makes every existing agent setup worse. If an unbudgeted dump is wanted, name it `--all`.

**Q8.** Support AI/ML's eval as an advisory release step only. It must not be a gate and must not block this ticket. YAGNI until the core exists.

**Position:** A-plain + semantic IDs + 44 KiB cap + generated prelude signature lines inside the cap + head/tail lists citing IDs + `--full` stays the core.

STABLE — ready to vote.

**PLT:**

**PLT, Phase B round 1**

**Revision first.** My P1 assumed the core could be *complete*: every normative rule inside 45 KB. AI/ML is right that this does not hold for the current surface. Edge-case rules (exhaustiveness corner cases, effect-row details) will stay outside. So I revise the claim. The core is a **sound subset** of sections/: every sentence in it is spec text, so it is true by origin, but it is not complete. That relation is well defined and checkable. "Complete and under 20k" is not, until h313w9 shrinks the surface. Given that, I drop two parts of P1 that only made sense under completeness:
- the lexical `must` lint (normative rules outside the core are now allowed),
- mandatory kernel/derivation discipline. Derivation blocks stay a *recommended* way to write a core block when a form really is sugar (`e?`, `??`), because one line of translation is cheaper than a paragraph. No mandate.

**Q1: Option A, A-plain plus stable IDs.** I join Sys, Web, AI/ML.
- *Against B (DevOps).* Two normative texts in different words have no defined relation. "A conflict is a spec bug" does not define one; it only tells you who cleans up. CI can check that anchors resolve, as DevOps says, but not that the wording agrees, and DevOps admits this. DevOps's real objection is readability. Web's review rule answers it: each core block must stand alone, one rule plus one example. That is an authoring rule, not grounds for a second source.
- *Against C (Min).* An "informative" hand-written summary has the same problem in weaker form. Nothing ties a sentence in it to a spec sentence, so "sections/ wins" can only be checked by a human reading 245k tokens. Min's own M2 is the fix, and it costs one comment pair per block.
- *Variations.* IDs must be semantic (`core:types.int-literal`), never section numbers (Web, DevOps, and Rust's `r[...]` precedent). For examples, inline fences (Sys, Web) are enough provided they compile. AI/ML's `docs/core/*.bl` adds a second place to edit, and it gains nothing that the fence-compile check does not already give.

**Q2: 46,000 B, hard fail, raising it needs a panel vote.** I move from 45,000 to Web/Min's figure so a number can carry. Sys's 64 KiB rests on 3.3 B/token, but this repo measured 2.3 (72,163 B ≈ 31k). At the measured ratio, 64 KiB is about 28k tokens, which fails the ticket's own target. Re-measure the ratio at each release and report it; that is not a gate.

**Q3: generated, outside the core cap.** I concede to Sys/DevOps/Min and withdraw my separate `--api` tier with its 40 KB budget. Signatures are retrieved, not held. Per-topic cap: Sys's 6 KiB is fine. Sys's check "every `pub` lib/std item in exactly one API block" is the right completeness property *for the API side*, and I support it.

**Q4: agree with all.** Web's ~10 core lines for `@ffi`/`Ptr[T]` are fine as long as they are core blocks under the same cap.

**Q5: the CI set I vote for.**
1. Byte cap on the generated output.
2. Every `blink` fence compiles; an error-tagged fence fails with exactly that code.
3. Regen-diff: committed llms-full.md equals generator output.
4. Core IDs are unique, and every ID referenced inside the core resolves inside the core. This is my closure check, now cheap: a dangling reference means the subset is not self-contained.
5. Diagnostic codes in the core exist in the catalog (extend W0610).

I move my rule-coverage citations from tests/ to a follow-up ticket. They are valuable but not needed to close this gap.

**Q6: accept AI/ML's inclusion criterion as authoring guidance** ("would a capable model get this wrong?"). Ordering: a prior-divergence list at the head is fine **only if** every bullet cites a core ID, as with Web's gotchas rule. Otherwise the list becomes an unchecked third text that can state rules the spec does not have.

**Q7: `--full` is the budgeted core.** Adding `--core` next to `--full` gives two flags for the "load this" step, which goes against Principle 2. Topics stay under `--topic`. I reject DevOps's tier, where `--full` means "everything, no promise".

**Q8: fine as an advisory release step, not part of the spec decision.** It measures coverage, which byte caps cannot. It should not block anything.

**Ticket wording.** Change "normative core" to "spec-derived core, a sound subset of sections/". AI/ML and Min are right on this point.

STABLE: ready to vote on A-plain + stable IDs, 46,000 B, API outside the cap, CI checks 1–5, `--full` as the core.

**DevOps:**

**DevOps, Phase B round 1**

**Q1: I concede Option B and move to Option A-plain, with PLT's stable IDs.**
Sys's point holds: in 00_core.md every rule exists twice, and my anchor check proves only that a heading exists, not that the wording agrees. PLT is also right that two normative texts mean "two drafts". With fences in sections/, a reviewer sees the core rule and its elaboration in one diff. My readability worry is an authoring rule, not a reason for a second file: core blocks must read standalone, and the closure check (below) enforces the mechanical part.

From A-kernel I take:
- Semantic IDs (`<!-- core:types.match.exhaustive -->`), never section numbers, so renumbering breaks nothing.
- The closure check: every ID the core cites resolves inside the core.

I would not gate on the rest for this ticket:
- **The `must` lint:** it fires on hundreds of existing sentences on day one. Ship it as a ratchet that may not grow, as other lints already do.
- **Derivation blocks:** good authoring practice, not a gate.
- **Rule coverage from tests/:** a report, not a gate. It is valuable, but it would block every spec PR until the corpus is tagged.

I reject Min's Option C. A hand-written informative file is exactly the status quo that produced d191er and xb1crm. "Sections/ wins" gives the agent no tool to find out it lost.

Examples: inline fences, compiled by CI (Sys/Web/PLT), not `docs/core/*.bl` (AI/ML). One edit site per rule beats two. The fence runner compiles and runs, and `expect E####` fences must fail with exactly that code.

**Q2: 46,000 bytes for the core, hard fail, and a panel vote to raise it.**
I drop 44 KiB to converge with Web/Min; the gap is noise. I rebut Sys's 64 KiB: the 3.3 B/token figure is not measured. The repo's own measured ratio is 2.3, so 64 KiB is about 28k tokens and misses the ticket's target by 40%. Per-topic cap: 12 KiB. Sys's 6 KiB cannot hold the List table plus Iterator, and splitting one type across topics is worse for retrieval than a 5k-token topic. llms.md: 6 KiB. Re-measure the ratio at release and record it, as AI/ML proposes; never gate on a tokenizer.

**Q3: method tables stay outside the core cap.**
This rebuts Web W1.2 and AI/ML P2.2. Min measured the tables at about 25k bytes, roughly 35% of today's file. Putting them inside 46,000 B leaves about 20k bytes for the whole language, and then the cap goes up within a year. I take Sys's split:
- The core holds prelude type and trait names, plus one line per prelude trait.
- Generated API blocks are served by `--topic <Type>` and `blink doc`.

AI/ML's real concern, the high-divergence API facts (`m.insert(k, v)` not `m[k] = v`, no string `+`), belongs in the core's divergence list as rules, not as tables. I adopt Sys's check that every `pub` lib/std item appears in exactly one API block. It costs nothing because the generator produces the blocks.

**Q4: agreed.** CLI and build flags are generated from the `add_command`/`command_add_flag` registrations in src/cli.bl, which closes zj4jgw's class for the generated part. FFI and arena become topics. I don't object to Web's ten core lines for `@ffi`/`Ptr[T]`, if they fit.

**Q5: the gate set for `task ci`:**
1. Byte cap.
2. Fences compile, with exact-code error fences.
3. Regen-diff of llms-full.md against the generator (a hand edit fails).
4. Unique IDs plus closure.
5. Core diagnostic codes exist in the catalog (extends W0610).
6. Every `pub` item in exactly one API block.

The CI message format from my Phase A (DOC001 with a per-section byte breakdown) applies to check 1. Without the breakdown, an over-cap failure tells the author nothing about what to cut.

**Q6: adopt AI/ML's inclusion rule and order as authoring guidance in §6, not as a gate.**
CI cannot decide "a capable model would probably get it wrong". The ordering is mechanical, though. The generator emits a fixed topic order: divergence list first, common errors last. That order lives in the generator config, not in file order.

**Q7: I concede. `--full` is the budgeted core; drop my `--core` flag.**
This is a tooling argument against my own proposal. `cmd_init` (src/cli.bl:4369) has already written "Run `blink llms --full`" into every user project's CLAUDE.md. Changing what `--full` means to "core + everything, unbudgeted" would silently push those agents to about 60k+ tokens. Keep `--full` = core, keep `--topic`/`--list`, and add nothing new. `--list` should print topic byte sizes, so an agent can budget its retrieval.

**Q8: yes, as advisory only.**
It runs in the release checklist, never in `task ci`, because it needs a model API and is nondeterministic. Record first-try compile rate next to the byte and token figures in CHANGELOG, so a cap change has data behind it.

**Position now:** A-plain plus semantic IDs plus closure; 46,000 B core; tables and tooling outside the cap as generated topics; `--full` stays the budgeted core; `must` lint and rule coverage as a ratchet or report, not gates.

**AI/ML:**

**AI/ML, Phase B round 1**

**Q1 — Source: Option A-plain, plus stable IDs. I concede on example source.**

- **A over B (rebut DevOps).** DevOps says extraction "gives fragments with no flow." Models do not need flow; they need each block to stand alone. Web's review rule ("write each core block to stand alone") fixes that. A second hand-written normative file repeats what llms-full.md does today, which produced d191er. Anchor checks prove that an ID resolves, not that the two texts agree.
- **Against Min M1 as the end state.** d191er only checks snippets. Prose claims ("`Map.remove` returns `V`") still drift, and prose is what a model trusts most. But Min's point on cost is fair, so I propose **staging**: land the byte cap first, on today's hand-written file, then the extractor. The cap alone forces the cuts Min lists (build, FFI, arena, tables).
- **IDs (concede to PLT and DevOps).** Give every core block a stable semantic ID (`core:types.match.exhaustive`). For agents this has real value. A diagnostic or `blink explain E0306` can print the exact rule, and an agent can retrieve one rule by ID instead of a whole topic. Retrieval of small, exact units beats retrieval of whole sections.
- **A-kernel: partly.** Derivation blocks (`e? ≡ match e {...}`) are token-cheap, and models read them well. Use them where they replace prose. PLT's `must` lint and rule-coverage citations are good later work, but they are not needed to close this ticket. Do not gate 2xvan0 on rewriting 02/03/04 into kernel form.
- **Example source (concede to Sys, Web and PLT).** Inline fences, compiled in CI. Separate `docs/core/*.bl` files add an indirection with no gain once the fences compile.

**Q2 — Budget: I revise from 48 KiB to 46,000 B.**

- **Rebut Sys's 3.3 B/token.** It is wrong for this text. The measured ratio is 2.3, so 64 KiB is about 28.5k tokens, 40% over the target. Sys's split of 62 KiB would then not fit at the target size, and that is the real signal for h313w9.
- **Converge on 46,000 B** (Web and Min). It sits in the middle of the 44–48k cluster.
- llms.md: 6 KiB.
- Per topic: **12 KiB** (DevOps). At 6 KiB, FFI does not fit in one topic, and an agent that needs FFI then makes several fetches.
- Raising the cap needs a panel vote: agree.
- Re-measure the ratio at each release, as a report and not a gate.

**Q3 — Method tables: I revise. They go outside the core cap** (Sys, DevOps, Min, PLT's separate budget).

- 46k cannot hold both the language and the tables. Most method names match model priors (`len`, `push`, `map`, `contains`), and a wrong guess gives a compile error that `blink doc` fixes in one step.
- **One exception, which I hold.** The core keeps a generated **"divergent API" list**: the methods whose shape departs from priors. Examples: `Map.remove -> Option[V]`, `m.insert(k, v)` and not `m[k] = v`, `ch.recv() -> Option[T]`, `List.new[T]()`. That is about 1–2 KB.
- A model can never recover a silent semantic mismatch by a lookup, because it does not know to look. It recovers a missing name easily.
- Mark these in lib/std with a doc attribute so the list is generated, not hand-kept.

**Q4 — Non-language content.** I agree with all of it. Web's ~10 lines on `@ffi`/`Ptr[T]` are acceptable; only the pointer to `--topic ffi` is essential.

**Q5 — CI checks.**

Required:
- the cap
- every fence compiles, and error-tagged fences fail with exactly that code
- regen-diff
- unique, resolving IDs
- diagnostic codes exist in the catalog

Also cheap and worth having: PLT's closure check. A core that refers to an undefined term makes a model fill the gap from priors, which is exactly the error we want to stop.

Later, not gating: Sys's "each `pub` item in one API block", and PLT's `must` lint and coverage.

**Q6 — Selection and ordering. I hold this, and ask the others to adopt it.**

Nobody argued against it, but nobody adopted it either, and it decides *which* 46k we keep.

- **Selection rule for review:** a span earns a core marker if a capable model without Blink knowledge would probably get it wrong. Rules that match Rust, Python or Go get one example and no prose.
- **Ordering:** spec order for the body (Sys and Web), plus Web's gotchas frame placed at the **head and the tail**, with each gotcha pointing to a core ID. This is the cheap fix for lost-in-the-middle, and it adds no generator complexity.

**Q7 — CLI. `--full` stays the budgeted core. Against DevOps's `--core`.**

- Every existing CLAUDE.md, agent prompt and future training sample says `blink llms --full`.
- If `--full` becomes "core plus all topics, no budget", each of those agents loads 70k+ tokens without warning. That is the failure this ticket exists to fix.
- Add `--all` if someone wants everything.

**Q8 — Eval.** I hold this as advisory and outside the vote's gating terms. Nobody objected. The byte cap measures size, and only an eval measures whether we kept the right bytes. A release-task script with recorded compile rates is cheap.

**My position after this round:**
- A-plain with stable IDs, inline compiled fences, and derivation blocks allowed.
- 46,000 B core, 12 KiB per topic, 6 KiB llms.md.
- Tables outside the cap, plus a generated divergent-API list inside it.
- Gotchas at head and tail.
- `--full` is the core.
- Staged landing: cap first, then the extractor.
- Advisory eval.

**Minimalism:**

**Min, Phase B round 1**

**Revision.** I drop M1 (hand-written, capped llms-full.md) as my first choice. Web is right that a cap alone leaves d191er and xb1crm open. A hand-written text with "sections/ wins" is, as PLT says, true only if someone checks it against 245k tokens. Four of six already back A-plain, which was my M2. A-plain adds the least machinery that removes the second text. **My position is now Q1 Option A-plain.** M0 is withdrawn.

**Q1: A-plain, not A-kernel, not B.**
- **Against B (DevOps).** `00_core.md` is a second normative text. Every rule then lives twice in different words, and no check can prove the two agree. DevOps admits this ("can't prove two prose rules agree"). The claim that extraction gives "fragments with no flow" is a writing-discipline problem. Web's review rule fixes it: each core block must stand alone. That costs one review norm. B costs a permanent duplicate.
- **Against A-kernel as MVP (PLT).** The derivation idea is sound, and I like it as a way to cut bytes: `e?` as one translation line beats a paragraph. But the closure check, the lexical `must` lint, mandatory rule-coverage citations from tests/ and removing every "Rationale (normative)" label are four new mechanisms and a rewrite of 02/03/04 before any agent benefits. YAGNI. Allow derivation-style blocks inside A-plain fences where they fit. File the rest as a follow-up only if drift shows up.
- **Example source.** Inline fences, compiled in CI (Sys, Web, PLT). AI/ML's `docs/core/*.bl` adds a second place to edit for each example. Rejected.

**Q2: budget.** Generated core ≤ **46,000 bytes**, hard fail, no allowlist. Sys's 64 KiB rests on 3.3 B/token, but this repo measures 2.3, so 64 KiB is about 28k tokens and misses the ticket's target. The differences among 44 KiB, 45,000, 46,000 and 48 KiB are noise; I accept any of them and default to 46,000. Raising the cap needs a panel vote. llms.md ≤ 6 KiB. **No per-topic cap**: topics are fetched on demand, and nobody has shown that a topic grows too large. Add one when that happens. The token ratio is re-measured as an advisory number in release notes, not a gate.

**Q3: method tables generated, outside the core cap** (with Sys and DevOps). Web and AI/ML put them inside: about 25k of today's 72k bytes are tables, which leaves about 21k bytes for the whole language. That does not fit. PLT's separate `--api` budget of 40 KB is a second number to defend for no gain; on-demand topics need no budget. The core keeps prelude type and trait names only (Sys).

**Q4: all non-language content out**, arena included. Against Web's 10 FFI lines in the core: most programs never use FFI, and `--topic ffi` exists. DevOps's CLI-flag generation from cli.bl registrations: yes, it is cheap and fixes zj4jgw by construction.

**Q5: CI checks.** I concede: fold d191er into this decision, so every core fence compiles and error-tagged fences fail with that exact code. Also keep:
- the regen-diff;
- unique core IDs, which the extractor needs anyway;
- the diagnostic-code catalog check, which is the existing W0610 check pointed at the generated file, so no new cost.

I reject:
- PLT's closure check, `must` lint and coverage citations (see Q1);
- Sys's "every pub item in exactly one API block": a generator that walks every `pub` item covers this by construction, so a second check proves nothing.

**Q6: AI/ML's inclusion rule.** Good as a **review guideline** for what to mark core: "a capable model would get it wrong". It is not normative spec text, because nobody can decide "probably get it wrong" mechanically. The core goes out in spec order. One short hand-written head, a prior-divergence list, is acceptable only under Web's rule: every bullet links to a core ID, so it cannot invent rules. It counts against the 46,000-byte cap.

**Q7: no `--core` flag.** `--full` is the budgeted core (Sys, Web, AI/ML). DevOps's proposal makes two flags where one did the job, and leaves `--full` with no promise. Agents already call `--full`, and existing CLAUDE.md files keep working.

**Q8: AI/ML's eval suite.** Not part of this decision. It is a fine release chore if someone wants it, but it is not spec. It is non-deterministic, costs money and can't gate anything. File it separately or drop it.

**Proposed package:** A-plain with inline compiled fences, a 46,000 B cap with panel vote to raise, generated method tables and CLI flags outside the cap, `--full` as the core, and checks for compile, regen-diff, unique IDs and W0610.

#### Phase C — Silent vote

Ballot:

All six round-1 replies are in scratchpad/panel/*_B1.md. Read the ones you have not read before voting.
Vote alone. For EACH question give: **Vote** (option label), **Reasoning** (2–4 sentences, your domain),
**Concern** (one sentence on what could go wrong with the option you expect to win).

Q1 — Source and status of the in-context reference
- A: core spans fenced in sections/ (`<!-- core:<semantic.id> -->` … `<!-- /core -->`) with stable semantic IDs; each block reads standalone; examples are inline fences; a generator builds llms-full.md; sections/ is the only normative source. Derivation lines (`e? ≡ ...`) may appear inside a block beside an example.
- B: separate hand-written normative sections/00_core.md (DevOps Phase A; withdrawn in B1).
- C: hand-written informative llms-full.md, capped, sections/ wins (Min Phase A; withdrawn in B1).

Q2 — Core byte cap (hard fail in `task ci`; raising it needs a panel vote; ratio re-measured and reported at release, not gated)
- 46000: 46,000 bytes
- 45056: 45,056 bytes (44 KiB)

Q2b — Per-topic cap / llms.md cap
- CAPS: 12 KiB per `--topic` output; 6 KiB for llms.md
- NOTOPIC: 6 KiB for llms.md; no per-topic cap until a topic grows too big (Min B1)

Q3 — What API content sits inside the core cap (all full tables are generated from lib/std and served outside the cap by `--topic` / `blink doc`)
- NAMES: only prelude type and trait names plus one line per prelude trait (Sys S1)
- DIVERGE: NAMES + a generated "divergent API" list of methods whose shape departs from model priors, marked in lib/std (AI/ML B1)
- PRELUDE-SIGS: NAMES + generated one-line signatures for every method of Str, List, Map, Set, Option, Result (Web B1)

Q4 — Non-language content (install, CLI/build flags, emit modes, daemon, FFI, arena) leaves the core; the core keeps one pointer line per topic (e.g. "FFI: `blink llms --topic ffi`"); CLI-flag topics are generated from src/cli.bl registrations
- YES / NO

Q5 — Gate set in `task ci`. Base set (cap; every core/topic `blink` fence compiles, error-tagged fences fail with exactly the stated code; regen-diff of llms-full.md; unique and resolving IDs; core diagnostic codes exist in the catalog).
- BASE: base set only; closure check, `pub`-item coverage, `must` lint, test rule-citations are follow-up tickets
- BASE+CLOSURE: base set + closure check (every term/ID the core references resolves inside the core); others follow-ups
- BASE+CLOSURE+PUB: base + closure + every lib/std `pub` item appears in exactly one API block; others follow-ups

Q6 — Ordering: body in spec order; a hand-written divergence list at the head and a common-errors list at the tail, every bullet citing a core ID (checked by the ID-resolve gate); AI/ML's inclusion rule ("a capable model without Blink knowledge would probably get it wrong") is authoring guidance in the spec, not a CI check
- YES / NO

Q7 — CLI surface
- FULL: `blink llms --full` prints the budgeted core; add `--all` for core + every topic; `--list` shows each topic's byte size
- CORE: new `blink llms --core` is the budgeted core; `--full` becomes core + every topic with no budget promise; update cmd_init and CLAUDE.md text

Q8 — AI/ML's model eval (~50 prompts, first-try compile rate with Tier 0+1 only)
- ADVISORY: recorded in the decision as a non-binding release step; never a gate
- OUT: not part of this decision; file separately if wanted

Q9 — Landing order (AI/ML B1)
- STAGED: land the byte cap on today's hand-trimmed llms-full.md first, then the extractor
- ONESHOT: the cap applies to the generated output only; no interim cap on the hand-written file

Q10 — "*Rationale (normative)*" label in sections/ (PLT A, Sys B1)
- DROP: each such paragraph is either rewritten as a rule or loses the "normative" label
- KEEP: leave the label as is

**Systems:**

**Sys ballot, Phase C**

**Q1 — Vote: A**
Reasoning: Keep one source per rule. With a second copy (B or C), the drift that d191er shows comes back as a lasting maintenance cost. With fences, the rule and its elaboration sit in one diff, and the generator is a few-second concatenation that is easy to predict. Derivation lines inside a block are fine if they cost fewer bytes than prose.
Concern: authors may fence spec prose that only reads correctly in its context; a "reads standalone" review rule then becomes the only defence.

**Q2 — Vote: 46000**
Reasoning: At the measured 2.3 B/token, 46,000 B is about 20k tokens, and the gap to 45,056 is about 400 tokens, which is noise. A round decimal number is easier to cite in DECISIONS.md and in CI output. What matters is the hard fail plus a panel vote to raise it, and both options have that.
Concern: the ratio drifts as the mix of code and prose changes, so the true token cost slides while the byte cap stays green.

**Q2b — Vote: CAPS**
Reasoning: I want each retrieval to cost a predictable amount. 12 KiB is about 5k tokens, so an agent can budget a `--topic` call before making it. Without a cap, the first topic that grows to 40 KiB, a dump of every method of every type, surprises everyone, and by then the cap fight is harder. A cap costs one more `wc -c` in the same check.
Concern: a single type with a large API, such as Str, may need a split topic, which costs retrieval round trips.

**Q3 — Vote: NAMES**
Reasoning: Every byte inside the core cap is a byte taken from the language. Facts about diverging APIs, such as `m.insert(k, v)` and not `m[k] = v`, belong in the Q6 divergence list as core rules that cite IDs. That needs no new lib/std attribute and no second generator input. PRELUDE-SIGS spends about 5–8 KB of a 46 KB budget on signatures that one lookup returns.
Concern: models guess method names they never look up, so first-try compile rates on collection-heavy code stay lower than with PRELUDE-SIGS.

**Q4 — Vote: YES**
Reasoning: Tooling and FFI are pay-only-if-you-use costs, so they belong behind a fetch. One pointer line per topic is enough for an agent to find them. Generating CLI-flag topics from the cli.bl registrations removes zj4jgw's class at no ongoing cost.
Concern: a pointer line alone may not be enough for an agent to know when it needs FFI.

**Q5 — Vote: BASE+CLOSURE**
Reasoning: Closure is a cheap pass over IDs the generator already holds. It stops a model from filling an undefined term from its priors, which is the failure we pay tokens to avoid. The `pub`-coverage check is a tautology when the generator walks every `pub` item, so I withdraw it.
Concern: the closure check needs a precise definition of a "term" reference; if it means more than an ID, it gets noisy.

**Q6 — Vote: YES**
Reasoning: Head and tail placement is a zero-cost order change in the generator with a measured attention benefit. Requiring each bullet to cite a core ID keeps the hand-written lists from turning into a third text. Both lists count against the cap.
Concern: the head list will grow into a second summary of the core and use up its budget unless review keeps it short.

**Q7 — Vote: FULL**
Reasoning: I switch from CORE. The argument from Web, AI/ML and DevOps holds on cost: under CORE, every existing `--full` caller silently loads 70k+ tokens. Under FULL, they lose tables, which they can fetch and which the core points to. An unpredictable cost increase is worse than a smaller default with a fetch path. Byte sizes in `--list` let an agent budget.
Concern: older agent prompts may expect method tables in `--full` and guess rather than fetch them.

**Q8 — Vote: OUT**
Reasoning: The eval is nondeterministic, needs a paid model API and is not spec text, so it has no place in a spec decision. If someone wants it as a release chore, file it on its own.
Concern: without any measure of coverage, the cap optimises size alone, and nobody can see whether we kept the right 46k.

**Q9 — Vote: STAGED**
Reasoning: A `wc -c` gate on today's file costs one line and stops growth at once. Otherwise every xb1crm fix landed before the extractor enlarges the file. The trims it forces (build, FFI, arena, tables) are the same cuts the extractor needs, so they are not wasted work.
Concern: the interim hand-trimmed file may become the long-term state if the extractor work stalls.

**Q10 — Vote: DROP**
Reasoning: Text is either a rule or it is not. A "normative rationale" label leaves readers and the core gate unsure whether to extract it. Rewriting each such paragraph as a rule, or dropping its label, is a one-time edit that makes the core boundary checkable.
Concern: some of these paragraphs hold real rules that get dropped with the label rather than rewritten as rules.

**Web/Scripting:**

**Web, Phase C ballot (2xvan0)**

**Q1. Vote: A**
Reasoning: There is one source, and each core block is readable and compiles. A JS/Python dev gets what they get from MDN, short text with an example next to it, without a second text that can drift away from the spec. Min's hand-written `println(...)` example fails `blink check`, which shows that a hand-kept text drifts even when a careful author writes it. Semantic IDs are cheap and later give `blink explain` exact rule links.
Concern: authors may fence spec sentences that only make sense with the text around them, so the "reads standalone" review rule has to be enforced in review, not just stated.

**Q2. Vote: 46000**
Reasoning: Five of six panelists converged on it, and it is 20k × the measured 2.3 B/token. The gap from 45,056 is under 500 tokens, which is noise. I prefer a round number that is easy to state.
Concern: the current surface may not fit, and people may push to raise the cap instead of cutting text (h313w9).

**Q2b. Vote: CAPS**
Reasoning: An agent fetching `--topic` needs a predictable cost. If topics have no cap, the next 30k-token dump simply moves to a new place. 12 KiB holds List or FFI in one fetch, and 6 KiB covers today's llms.md with room to spare.
Concern: a type that outgrows 12 KiB gets split into topics with odd names that agents cannot guess.

**Q3. Vote: DIVERGE**
Reasoning: I concede the full prelude signature list. Sys, DevOps and Min showed that the tables cost about 35% of the budget. AI/ML found the real failure: a model guesses `m[k] = v` or uses `Map.remove` as if it returned `Bool`, and it never looks those up because it does not know it is wrong. A generated, lib/std-marked divergent-API list fixes exactly that case for about 1–2 KB.
Concern: if nobody owns the lib/std markers, they lag behind new APIs and the list quietly goes stale.

**Q4. Vote: YES**
Reasoning: Install, flags and emit modes describe the tool, not the language, and most programs never touch FFI or arenas. I drop my 10 FFI lines. One pointer line per topic teaches the agent where to retrieve the rest. Generating CLI topics from cli.bl closes zj4jgw's class of bug.
Concern: topic names must match what an agent would guess (`ffi`, `build`, `cli`), or the pointer lines lead nowhere.

**Q5. Vote: BASE+CLOSURE**
Reasoning: Closure is cheap and protects the user experience. A core that cites an undefined term makes the model fill the gap from priors, which produces the confident wrong code we are trying to stop. The `pub` coverage check holds by construction once a generator emits every `pub` item, so it adds nothing.
Concern: the closure check may flag terms like `Int` or `match` unless the generator has a clear list of built-in terms that always count as defined.

**Q6. Vote: YES**
Reasoning: This is the "Gotchas" section done right. The facts a model most often gets wrong sit where attention is strongest. Each bullet must cite a core ID, so the lists cannot invent rules. Keeping the inclusion rule as authoring guidance is the honest choice, because CI cannot decide what a model would get wrong.
Concern: the head and tail lists grow until they crowd out body rules within the cap.

**Q7. Vote: FULL**
Reasoning: Every CLAUDE.md that `cmd_init` has written already says `blink llms --full`. Keeping that name as the budgeted core fixes every existing agent with no migration. `--all` gives the unbudgeted dump an honest name, and byte sizes in `--list` let agents plan their retrieval.
Concern: an existing user who expects `--full` to contain method tables gets fewer of them, so CHANGELOG has to say so clearly.

**Q8. Vote: ADVISORY**
Reasoning: Byte caps measure size, not whether we kept the right bytes. A recorded first-try compile rate is the only DX number that tells us. Calling it non-binding in the decision costs nothing and keeps it from being lost.
Concern: nobody runs it, and the advisory line becomes dead text.

**Q9. Vote: STAGED**
Reasoning: Agents start paying 31k tokens less soon, not only once the extractor lands. The cap on today's file forces the cuts everyone already agrees on (build, FFI, arena, tables) with almost no machinery.
Concern: the interim hand trim brings in new drift that the extractor stage then has to find and undo.

**Q10. Vote: DROP**
Reasoning: A reader cannot tell what "normative rationale" obliges them to do, and a model reading it will either over-apply it or ignore it. Rewriting each such paragraph as a rule, or removing the label, makes the spec say one thing clearly.
Concern: a few of these paragraphs hide real rules, and they get relabeled as informative instead of rewritten.

**PLT:**

**PLT ballot, Phase C**

**Q1: A**
Reasoning: One normative source with a mechanical projection gives a defined relation: the core is a sound subset of sections/, true by origin. B and C each create a second text, and nothing can check that its wording agrees with the spec. Derivation lines inside a block are the cheapest correct way to state sugar.
Concern: Authors may write core blocks that lean on the prose around them, so the extracted core reads as fragments.

**Q2: 46000**
Reasoning: It sits at the measured 2.3 B/token for 20k tokens. The difference from 45,056 is noise. What matters is a hard failure plus a panel vote to raise it.
Concern: The ratio may drift as the share of code changes, so the cap stops meaning 20k tokens without anyone noticing.

**Q2b: CAPS**
Reasoning: A topic is one retrieval unit. Without a cap, the material we push out of the core just regrows in one topic and costs as much on fetch. 12 KiB keeps one fetch well under 6k tokens.
Concern: A large topic (effects detail, FFI) may need splitting, which adds more topic names.

**Q3: NAMES**
Reasoning: Signatures are retrievable facts, not semantics, and the core budget should price the language, not the library. A "divergent" mark in lib/std adds a new annotation channel and a judgment call per method. Prelude-wide signatures spend about a quarter of the cap on lookup data.
Concern: Agents may skip `--topic` and guess method names, so the common-errors list must cover the worst cases.

**Q4: YES**
Reasoning: Tooling and install are not language semantics. One pointer line per topic keeps the core closed under retrieval: the agent learns where to look from the core itself.
Concern: The CLI-flag generator from cli.bl registrations is new machinery and may slip behind the rest.

**Q5: BASE+CLOSURE+PUB**
Reasoning: Closure is what makes "self-contained subset" a checked property and not a hope, and it costs little once IDs resolve. `pub` coverage is the completeness property for the API side, where completeness can be achieved, and it closes xb1crm's omission class by construction.
Concern: The `pub` coverage check may force noisy blocks for internal-but-`pub` items unless "exactly one block" allows a generated catch-all.

**Q6: YES**
Reasoning: Spec order keeps the projection deterministic. The head and tail lists are acceptable only because every bullet must cite a core ID, so they cannot state rules the spec lacks. The inclusion rule is editorial; it cannot be a decidable check.
Concern: The hand-written lists may restate a rule in looser words than the block they cite.

**Q7: FULL**
Reasoning: One flag for "load the language" (Principle 2), and agents' existing instructions stay valid. `--all` and byte sizes in `--list` make the cost of retrieval visible.
Concern: Old external docs that say `--full` means "everything" will mislead until updated.

**Q8: ADVISORY**
Reasoning: Byte caps measure size, and closure measures self-containment. Neither measures whether the subset is the *right* subset; only an eval does. Recording it as non-binding costs nothing.
Concern: A noisy eval may get treated as a gate in practice.

**Q9: STAGED**
Reasoning: An interim cap stops llms-full.md growing while the extractor is built, and the cut list it forces is the same one the core blocks need. The cap then moves to the generated output without changing its number.
Concern: The hand-trim may be done twice if the extracted blocks differ a lot from the trimmed text.

**Q10: DROP**
Reasoning: "Normative rationale" is a category error. A sentence either constrains programs (a rule) or explains a choice (rationale). Each such paragraph gets rewritten as a rule or loses the label.
Concern: A rewrite may quietly change a rule's meaning, so each one needs review against the tests that cover it.

**DevOps:**

**DevOps, Phase C ballot**

**Q1: A**
Reasoning: One source removes a whole class of drift that no CI check can catch, namely two prose texts that disagree. Semantic IDs let `blink explain` and diagnostics link to the exact rule, and renumbering sections breaks nothing. Regen-diff makes a hand edit to llms-full.md fail the build, so the artifact cannot rot quietly.
Concern: Authors will fence prose that does not stand alone, and no check enforces "reads standalone", so review must hold that line.

**Q2: 46000**
Reasoning: The figure follows from the repo's measured 2.3 B/token and meets the 20k target. Bytes are deterministic and need no tokenizer dependency in `task ci`. The gap between 45,056 and 46,000 is noise, and 46,000 has the wider support.
Concern: The first extraction may land well over the cap, and pressure to "just raise it" will skip the panel vote unless the failure message (DOC001 with a per-section breakdown) makes the cut obvious.

**Q2b: CAPS**
Reasoning: A topic is retrieval-sized only if something keeps it so. A cap that already exists costs one line in the same check, while "add one when it grows" means nobody notices until an agent pulls 30k tokens for `--topic std`. With 12 KiB, the List+Iterator and FFI topics fit in one fetch each.
Concern: Generated API topics for large modules may breach 12 KiB on day one and force a split policy (per type, not per module) that we have not specified.

**Q3: DIVERGE**
Reasoning: A model recovers a wrong name in one step (compile error, then `blink doc`), but a silent shape mismatch it never thinks to look up. So the divergent list is the only API content that earns core bytes. It is generated from a marker in lib/std, so it cannot drift, and it costs about 1–2 KB, against an estimated 8–10 KB for PRELUDE-SIGS.
Concern: The "divergent" marker is a human judgment on lib/std items and will be applied unevenly unless the review rule says who adds it and when.

**Q4: YES**
Reasoning: Install, flags, emit modes and FFI describe the tool, not the language, and the CLI already has the source of truth. Generating flag topics from the cli.bl registrations closes zj4jgw for that part by construction. One pointer line per topic keeps the content discoverable at about 50 bytes each.
Concern: Flag help strings in cli.bl are terse, so the generated topics may need a richer description field in the registration API.

**Q5: BASE+CLOSURE**
Reasoning: Closure is cheap: one pass over IDs that the extractor already parses. It catches the failure that matters most for agents, a core that points at an undefined term, so the model fills the gap from its priors. I drop `pub` coverage as a gate here. Min is right that a generator walking every `pub` item covers it by construction, and it belongs with the API-topic work.
Concern: "Every term" is hard to define lexically, so the closure check may end up as IDs only, which is weaker than its name suggests.

**Q6: YES**
Reasoning: The head and tail lists are the only hand-written frame, and the ID-resolve gate already checks every bullet, so they add no unchecked text. The selection rule cannot be mechanized, so it belongs in authoring guidance, not CI.
Concern: The divergence list will grow by accretion and eat the cap, so it needs its own soft line count in review.

**Q7: FULL**
Reasoning: cmd_init has already written `blink llms --full` into user CLAUDE.md files, so changing its meaning would silently blow every installed agent's budget. `--all` gives the unbudgeted dump an honest name. Byte sizes in `--list` let an agent plan its retrieval.
Concern: The release task attaches llms-full.md, and people will assume it is "everything", so the release asset name and description must say "core".

**Q8: ADVISORY**
Reasoning: The byte cap measures size; only an eval measures whether we kept the right bytes. It needs a model API and is nondeterministic, so it can never sit in `task ci`. Recording the rate next to byte and token figures gives a cap-change vote real data.
Concern: The advisory step will get skipped at release unless the release skill runs it and writes the number.

**Q9: STAGED**
Reasoning: A gate should exist before the work it protects. Without an interim cap, every xb1crm fix grows the hand file while the extractor is being built. Landing the 46,000-byte check first also forces the tooling and table cuts that the final design wants anyway.
Concern: Today `--topic` only serves headings of llms-full.md, so content cut in stage one has no home until the topic generator lands. Stage one must keep it reachable (a temporary hand-written topics file) rather than delete it.

**Q10: DROP**
Reasoning: A label that mixes rule and rationale can't be checked: tooling can't tell which sentence binds. Rewriting each one as a rule block or demoting it gives the extractor and any future `must` lint a clean line to work from.
Concern: Only 2 paragraphs carry the label (both in 03_types.md), but a careless conversion may demote a real rule to rationale. Each conversion should cite the test that pins the rule.

**AI/ML:**

**AI/ML, Phase C ballot**

**Q1: Vote A.**
Reasoning: Use one source, with each core block written to stand alone. That gives a model text that is true by origin, and that is the property it needs to trust 20k tokens without checking 245k. Stable IDs also let a model fetch one exact rule, and small exact units retrieve better than whole sections.
Concern: Authors may wrap existing spec paragraphs as they are, and those paragraphs assume the text around them. The core then reads as fragments, and a model fills the gaps from its priors.

**Q2: Vote 46000.**
Reasoning: It is 20k tokens at the measured 2.3 bytes per token. The 1k-byte gap from 45056 means nothing to a model. Most panelists converged on 46000.
Concern: The bytes-per-token ratio rises as the core becomes more prose and less code, so the real token count can drift above 20k without anyone noticing. The release report must actually be read.

**Q2b: Vote CAPS.**
Reasoning: An agent plans a context budget per fetch. A known ceiling of about 5k tokens per `--topic` makes retrieval predictable. Without a cap, one bloated topic, such as an FFI dump, costs as much as half the core with no warning.
Concern: 12 KiB may split a large type, such as List with Iterator, across two topics, and then a model fetches one and misses the other.

**Q3: Vote DIVERGE.**
Reasoning: A model recovers from a guessed method name that does not exist, because it gets a compile error and then runs `blink doc`. It does not recover from a method that exists with a shape it did not expect, such as `Map.remove` returning `Option[V]` or `m[k] = v` being an error, because nothing tells it to look. Only those facts earn bytes in the core. PRELUDE-SIGS spends about 10 KB on names the model already guesses right.
Concern: The "divergent" marker in lib/std depends on judgement, so it may grow until it is the full tables again under another name.

**Q4: Vote YES.**
Reasoning: Most generated programs never touch FFI, build flags or arena, so these spend core budget for nothing. One pointer line per topic teaches the model where to retrieve them.
Concern: If topic names drift from the pointer lines, a model asks for a topic that does not exist. The ID-resolve gate should also cover the pointer lines.

**Q5: Vote BASE+CLOSURE.**
Reasoning: A dangling reference in the core is exactly where a model fills in a rule from its priors. Closure is therefore the check that most directly protects generation accuracy, and it costs little once IDs exist. `pub`-item coverage is true by construction for a generator.
Concern: The closure check may force authors to pull too many definitions into the core and use up the budget, instead of moving those references to an explicit `--topic` pointer.

**Q6: Vote YES.**
Reasoning: The head and the tail of a context get the most attention (lost-in-the-middle), so the facts that a model most often gets wrong belong there. Requiring an ID citation keeps those lists from becoming a third, unchecked text.
Concern: The hand-written head list can drift toward restating rules in different words. Reviewers must keep each bullet to one line plus the ID.

**Q7: Vote FULL.**
Reasoning: Every existing CLAUDE.md, cmd_init output and future training sample says `blink llms --full`. If that flag stops having a budget, every one of those agents loads 70k+ tokens without warning. Showing byte sizes in `--list` lets an agent plan what it retrieves.
Concern: Training data from before this change teaches that `--full` means "complete", so models may assume the core has every rule and not fetch topics.

**Q8: Vote ADVISORY.**
Reasoning: The byte cap measures size, and only an eval measures whether we kept the right bytes. A recorded first-try compile rate gives the panel data when someone next asks to raise the cap. It is never a gate, because it is not deterministic.
Concern: Nobody runs it, because a step that nothing enforces decays. Put it in the release checklist so that skipping it is visible.

**Q9: Vote STAGED.**
Reasoning: Agents get a smaller core within days, and the hand cuts (build, FFI, arena, tables) are needed anyway. The extractor then lands against content that already fits.
Concern: The interim hand-trimmed file may become the de facto core, and the extractor may stall. Link it as a blocking follow-up.

**Q10: Vote DROP.**
Reasoning: A model cannot act on a "normative" label attached to rationale. It either treats the paragraph as a rule or ignores it, so the label adds ambiguity at no gain. Each such paragraph should become a rule a model can apply, or plain rationale.
Concern: Some of these paragraphs hide real rules, and those rules may lose their normative status by accident if the label is dropped without rewriting them.

**Minimalism:**

**Min, Phase C ballot**

**Q1: A**
Reasoning: A has one normative source and one comment pair per block. It also removes the second text instead of maintaining it. B duplicates every rule. C, my own withdrawn proposal, leaves prose drift unchecked, as Web's `println` catch showed. Derivation lines are allowed but not required, which keeps the cost low.
Concern: authors will fence large blocks of existing prose instead of writing standalone rules, so the cap fills with rationale-flavoured text.

**Q2: 46000**
Reasoning: It is 20k tokens at the measured 2.3 B/token. The 1 KB gap to 45,056 is noise, and a round decimal number is easier to cite. Raising it by panel vote only keeps it a price on language surface.
Concern: the first extraction may not fit, and the pressure will go to raising the cap rather than to h313w9 cuts.

**Q2b: NOTOPIC**
Reasoning: Topics are fetched on demand and no topic has been shown to grow too large. A per-topic cap is a second number to defend, and it forces type splits (List plus Iterator) before anyone has seen a problem. Add it when a topic actually bloats.
Concern: if CAPS wins, 12 KiB becomes a reason to split generated API blocks along arbitrary lines.

**Q3: NAMES**
Reasoning: DIVERGE adds a new doc attribute to lib/std just to steer a doc generator, which is new surface for a docs concern. The divergent facts (`m.insert`, `Map.remove -> Option[V]`, no string `+`) fit as core rules in the head divergence list, citing IDs, as DevOps said. PRELUDE-SIGS puts tables back inside the cap.
Concern: the divergence list may miss API shape facts that a marked-attribute list would have caught.

**Q4: YES**
Reasoning: The core describes the language, and tooling is not language. Generating CLI topics from the cli.bl registrations removes a hand-kept table instead of adding one. One pointer line per topic costs almost nothing.
Concern: pointer lines may accumulate one per topic and grow into a second table of contents.

**Q5: BASE**
Reasoning: "Unique and resolving IDs" already catches dangling ID references. A closure check over *terms* has no mechanical definition yet. The `pub` coverage check is true by construction if the generator walks every `pub` item. Each follow-up should earn its gate by finding a real bug first.
Concern: the base gate passes while a core block leans on an undefined term.

**Q6: YES**
Reasoning: Head and tail lists are the only hand-written frame, and the ID-resolve gate keeps them from inventing rules. The inclusion rule as authoring guidance costs nothing and tells authors what to leave out, which is the hard part.
Concern: the head list grows into a hand-written second core with ID citations attached for form.

**Q7: FULL**
Reasoning: Every existing CLAUDE.md says `--full`, so changing its meaning silently breaks every agent setup. One flag for "load this" follows Principle 2. I would drop `--all` as YAGNI, but FULL is clearly better than CORE.
Concern: `--all` gets used in agent prompts and brings back the 70k-token load this ticket removes.

**Q8: OUT**
Reasoning: An eval suite is release process, not spec, and it is non-deterministic and costs money. Recording it, even as non-binding, makes it look like a commitment. File it separately if someone wants to own it.
Concern: with no measure of coverage, the panel may defend the wrong 46k with confidence.

**Q9: STAGED**
Reasoning: A `wc -c` check is one line, and it forces the cuts (build, FFI, arena, tables) now, not after the extractor lands. The trimming chooses the same content the extractor needs, so the work is not wasted. Agents get a smaller file within days.
Concern: the interim hand-trimmed file becomes "good enough" and the extractor never lands; give it a dependent ticket.

**Q10: DROP**
Reasoning: "Normative rationale" is a category error. Removing a label is pure subtraction. Each paragraph either becomes a rule or stops claiming authority, and the spec gets smaller and clearer.
Concern: a paragraph that hides a real rule may lose its label without the rule being extracted.

#### Phase D — Focused debate on Q3, Q5 and Q8

**Systems:**

**Sys, Phase D round 1**

**Q3: I still vote NAMES.**
The strongest argument for DIVERGE comes from AI/ML and DevOps: a model recovers from a wrong name, but not from a "silent shape mismatch". In Blink that mismatch is rarely silent. If code uses `Map.remove` as a `Bool`, it fails to typecheck. `m[k] = v` is a compile error too. Both fail on the first compile, and the diagnostic leads to `blink doc`, a one-step recovery like any wrong name. The mismatches that really are silent are semantic: Float total order, `NaN == NaN`, integer overflow behaviour. Those are language rules and already go in the core's divergence list. That leaves DIVERGE paying for a new lib/std attribute, a judgement call on each method, and a second generator input. All of that is needed only for a class of error the type checker already catches. If the panel wants specific API facts up front, write them as rules in the Q6 head list, which already cites IDs and already counts against the cap. That costs nothing new.

**Q5: I still vote BASE+CLOSURE, with closure defined as an ID check only.**
Min's strongest point is right: closure over "terms" has no mechanical definition (DevOps and Web raise the same concern). So define it as: every `core:` ID that a core block cites must itself be a core block. A reference to an ID that exists only in sections/ fails. That is mechanical, one pass over IDs the extractor already holds. It differs from "resolving IDs" in the base set, which only checks that an ID exists somewhere in sections/. Such a reference resolves, but the model cannot see the target and fills the gap from its priors.
Against PLT's PUB: a generator that walks every `pub` item closes xb1crm's omission class by construction. A second check asserts what the generator already does and costs CI time for no signal.

**Q8: I still vote OUT, and I will not block a conditioned ADVISORY.**
The strongest argument for ADVISORY: only an eval tells us whether we kept the right 46k, and recording it costs nothing. My objection is that a nondeterministic measurement has no stable baseline. First-try compile rate moves when the model, the prompts or the sampling settings change, whether or not the core changed. Across releases the trend line mostly measures model upgrades, and a cap-raise vote should not rest on that. It also belongs to release process, not to a spec decision (Min).
I would accept ADVISORY only if the decision text requires each run to record the model ID, the sampling settings and a hash of the prompt set. The step would live as a release chore ticket and stay out of DECISIONS.md as a commitment. Without those conditions, OUT.

**Web/Scripting:**

**Web, Phase D round 1**

**Q3: changed from DIVERGE to NAMES, on one condition.**
Min and Sys make the strongest argument on the other side. The divergent facts (`m.insert(k, v)`, `Map.remove -> Option[V]`, `ch.recv() -> Option[T]`) already fit as rules in the Q6 head list, each citing a core ID. DIVERGE adds a lib/std doc attribute that users reading the stdlib will see and ask about ("what is `divergent`?"). That is new surface whose only job is to steer a docs generator. AI/ML's own concern also holds: the marker is a judgment call and will grow back into the full tables. My reason for DIVERGE was drift: a hand-written bullet stating a return type can go stale. The Q1 machinery already fixes that if each API-shape rule has a compiled fence that pins the shape, e.g. `let v: Option[Int] = m.remove("k")`. If `Map.remove` changes, the fence fails CI. **Condition:** state in the decision that API-shape rules in the core carry a fence that exercises the shape.

**Q5: same, BASE+CLOSURE, with closure defined as IDs only.**
The strongest objection is Min's: "resolving IDs" already catches dangling references, and "term closure" has no mechanical definition. Half of that holds. "Term" is undefined, so drop terms (DevOps's and Sys's concern too). The ID half is not redundant, though. In BASE, "resolving" means the ID exists *somewhere in sections/*. Closure means it resolves *inside the extracted core*. A core block that says "see `core:effects.handler-scope`", when that block was never fenced as core, passes BASE, yet the model meets a reference to text it does not have and fills the gap from its priors. Closure is one set-difference over IDs the extractor already holds. Cross-references out of the core must be written as `--topic` pointers, which answers AI/ML's concern about pulling in too much. `pub` coverage holds by construction, so it moves to the API-topic follow-up.

**Q8: same, ADVISORY.**
Sys and Min make the strongest argument: it is release process, not spec, and recording it implies a commitment. But this decision is already mostly process: CI gates, a ratio re-measured at release, a panel vote to raise the cap. A spec-only decision would hold none of those. Their own concerns grant the risk: "the cap optimises size alone" and "the panel may defend the wrong 46k with confidence". The next time someone asks to raise the cap, a vote with no coverage data is a vote on taste. The wording I would accept: "non-binding; run from the release checklist; never in `task ci`; result recorded next to byte and token figures." If OUT wins, the chore ticket must be filed in the same change, so the idea does not vanish.

**PLT:**

**PLT, Phase D**

**Q3: changed, NAMES → DIVERGE**
The strongest argument is AI/ML's asymmetry. A wrong name gets a compile error and then a lookup. A wrong *shape* (`Map.remove` returning `Option[V]`, no `m[k] = v`) gives nothing that prompts a lookup. That is correct. Sys and Min answer it by putting those facts into the hand-written divergence list as core rules. But a method's return type is a fact about the lib/std *signature*, not the spec. Restating it in hand-written prose creates exactly the kind of unchecked second copy that Q1 rejected. If `Map.remove` changes type, the hand-written bullet still compiles as prose and goes stale. A generated list cannot. So the single-source argument that decided Q1 decides this one too. To meet AI/ML's own concern that the list grows back into full tables, I want the generated block under a hard sub-cap counted inside the 46,000 bytes (2 KiB), with a review rule that a marker needs a known prior it departs from.

**Q5: changed, BASE+CLOSURE+PUB → BASE+CLOSURE**
I concede `pub` coverage. If the generator walks every `pub` item, the property holds by construction, and a gate that cannot fail is noise. Against Min's BASE: "unique and resolving IDs" asks whether an ID resolves *somewhere* in sections/. Closure asks whether it resolves *inside the core*. Those are different properties, and only closure makes "the core stands alone" true. The definition is mechanical if we fix it now: closure is over explicit references only (core IDs and `--topic` pointers), never free-text terms. Prelude names and keywords count as defined. A reference to a non-core ID fails, and the fix is either to pull the block in or to replace the reference with a `--topic` pointer. That answers DevOps's and AI/ML's concerns: IDs only, honestly named, with a cheap escape that costs no budget.

**Q8: same, ADVISORY**
The strongest argument (Sys, Min) is that an eval is not spec text and that a recorded step looks like a commitment. But this decision already records process, not semantics: a byte cap, a panel vote to raise it, release-time ratio reports. The eval belongs in that same category. It is the only evidence a future cap-raise vote can use about *which* bytes matter. Without it, the panel argues about coverage from intuition. Keep it non-binding with no threshold and no gate, run from the release checklist (AI/ML) so a skip is visible. If the majority prefers OUT, I would not oppose filing it separately. The loss is small, but real.

**DevOps:**

**DevOps, Phase D round 1**

**Q3: changed, from DIVERGE to NAMES.**
The strongest argument comes from Min and Sys. DIVERGE adds a new lib/std doc attribute only to steer a doc generator. The divergent facts already have a checked home: the Q6 head list, as core rules that cite IDs. That was my own B1 position ("belongs in the core's divergence list as rules, not as tables"), and I drifted off it in C. A new attribute is user-visible surface: third-party packages would see it and ask what it means. It also needs a generator input, an owner, and a policy for what counts as "divergent". Web and AI/ML both flagged that the markers would go stale or grow. The head list gets the gates for free: ID-resolve, closure, and fence compile.
Condition: API-shape facts (`Map.remove -> Option[V]`, `m.insert(k, v)`, no Str `+`) must be allowed as core rule blocks in the stdlib spec text, so the head list can cite them.

**Q5: same, BASE+CLOSURE, with closure defined as IDs only.**
The strongest argument comes from Min: "unique and resolving IDs" already catches dangling references, and closure over *terms* has no mechanical definition. On terms, I concede. But resolving IDs is not closure. An ID in a core block can resolve to a non-core heading in sections/, which the base gate accepts. The agent then gets a pointer to text that is not in its context, which is exactly the leak. The real definition is one line: every ID cited from a core block must name a core block. That is mechanical, takes one set lookup in the extractor, and answers Sys's and Web's noise concern. A term-level check stays a follow-up.

**Q8: same, ADVISORY.**
The strongest argument comes from Min: recording the eval, even as non-binding, makes it look like a commitment, and it is not spec. Answer: it goes in the DECISIONS.md entry, never in sections/, so no spec text commits to it. The cap's whole justification is "these 46k are the right 46k". A decision that sets a hard size gate and records no way to test that claim invites a future cap-raise vote with no data. One non-binding line costs nothing. I accept AI/ML's condition: it is a release-checklist item, so skipping it is visible. If the panel splits 3-3, I can live with OUT plus a separately filed chore.

**AI/ML:**

**AI/ML, Phase D round 1**

**Q3: I change to NAMES, on one condition.**

Strongest argument on the other side (Sys and Min): the divergent facts already have a home. They go in the Q6 head divergence list, which passed 6-0, as core rules that cite IDs. That needs no new lib/std attribute and no second generator input. I accept it.

My concern was never where the list lives. It was that a model has no means to find a silent shape mismatch. The head list covers that, provided each API-shape bullet cites a core block, and that block has a fence using the real API. For example, `let v: Option[Int] = m.remove("k")` and an error-tagged `m["k"] = 1` fence. The fence-compile gate then catches drift against lib/std with no marker, which is stronger than my attribute. With that, NAMES gives the same model-facing result with less machinery.

**Condition:** the decision text says that API-shape divergences belong in the head list, each backed by a compiled core fence.

**Q5: I stay with BASE+CLOSURE, with a narrow, mechanical definition.**

Strongest argument on the other side (Min, with DevOps's concern): ID resolution already catches dangling IDs, and "term" has no mechanical definition.

Answer: define closure narrowly. Every core ID reference, and every backticked type or trait name in core prose, must resolve to one of two things: a core block, or the NAMES list (prelude types and traits plus builtins such as `Int`). This is a lexical check over data the generator already holds. It fixes Web's `Int`/`match` worry through an explicit builtin list, and it is more than ID resolution. From a model's view, an unexplained `Handle[T]` in the core is exactly what it fills in from priors.

**PUB:** I agree with Sys, DevOps and Min that `pub` coverage is true by construction, so it is a follow-up.

**Q8: I change to OUT.**

Strongest argument on the other side (Min): even a non-binding line in a spec decision reads as a commitment, and an eval is release process, not language. That is right. The decision is about what the spec and CI promise, and an eval promises neither.

Two panelists who vote OUT (Sys and Min) name the same concern I have: without coverage data, we defend the wrong 46k with confidence. So I ask for a separate chore ticket, filed along with this decision. The decision rationale should note that a future vote to raise the cap should bring compile-rate data. That keeps the idea alive without a promise in the decision text.

**Current positions:** Q3 NAMES (with the condition above), Q5 BASE+CLOSURE (with the narrow definition above), Q8 OUT (with a separate chore ticket).

**Minimalism:**

**Min, Phase D round 1**

**Q3: same, NAMES**

The strongest DIVERGE argument comes from AI/ML and DevOps. A model recovers from a wrong name, but not from a shape mismatch it never thinks to look up.

In Blink, most shape mismatches are not silent. The typechecker rejects `m[k] = v`, and using `Map.remove`'s `Option[V]` as a `Bool` is a type error. The model gets a diagnostic and then runs `blink doc`, which is the same recovery path as for a wrong name.

The truly silent cases are semantic, such as `NaN == NaN` under a total order or how `??` evaluates. Those are language rules, so they belong in core blocks and the Q6 head list anyway, with no lib/std marker.

DIVERGE adds a new annotation channel to lib/std that rests on human judgement. Its own supporters list the risks: markers lag (Web), get applied unevenly (DevOps), and grow back into the full tables (AI/ML).

If an API fact really does fail silently, write it as a core rule and cite its ID.

**Q5: changed, to BASE+CLOSURE, if closure means IDs only**

The strongest argument (Sys, Web, DevOps, AI/ML) is that a dangling reference makes the model fill the gap from its priors. That is right, and it costs one pass over IDs the extractor already parses.

My BASE vote was against "every term" closure, which has no mechanical definition. Sys and DevOps both flag that same problem.

**Definition I accept:** every ID or `§` reference in the generated core resolves to a block inside the core, or to an explicit `--topic` pointer. There is no closure over free-text terms. A follow-up adds terms only if this check misses a real bug.

**Against PLT's PUB:** a generator that walks every `pub` item makes this check true by construction, so it proves nothing. Three of PLT's own co-voters dropped it.

**Q8: same, OUT, and I will not block ADVISORY**

The strongest argument (Web, PLT, DevOps, AI/ML) is that the byte cap measures size, and only an eval measures whether we kept the right bytes. I agree the measurement has value.

The problem is where it lives. A decision records rules. A non-binding line about a nondeterministic, paid process is dead text, and its own supporters predict it: "nobody runs it" (Web, AI/ML) and "gets skipped" (DevOps). Their fix is to put it in the release checklist. That is a chore ticket with an owner, not decision text.

**Position:** file it as a release chore that depends on the extractor landing, and keep it out of the decision.

If the majority holds at ADVISORY, I ask for one condition: name the release step that records the number. Otherwise the line does nothing.

#### Phase D — Re-vote on Q3, Q5 and Q8

Result: Q3 NAMES 6-0, Q5 BASE+CLOSURE 6-0, Q8 OUT 6-0.

**Systems:**

**Sys, Phase D re-vote**

**Q3 — Vote: NAMES**
Reasoning: I accept the condition from Web and AI/ML. An API-shape divergence goes in the Q6 head list as a core rule, and its compiled fence uses the real API (`let v: Option[Int] = m.remove("k")`, plus an error-tagged `m["k"] = 1`). That answers PLT's single-source objection: the fence-compile gate checks the shape against lib/std, so a stale bullet fails CI with no new attribute, no generator input and no per-method judgement call. The bytes count inside the 46,000 cap like every other rule.
Concern: authors may write the API-shape bullet without a fence that pins the shape, so the decision text must require one.

**Q5 — Vote: BASE+CLOSURE**
Reasoning: Closure means explicit references only. Every core ID or `§` reference in the generated core must resolve to a core block, or be written as an explicit `--topic` pointer. Prelude names and keywords count as defined. This is one set-difference over IDs the extractor already holds. It differs from base resolution, which accepts a target that exists only in sections/. AI/ML's backticked-name check is a reasonable follow-up, but I would not gate on it before it finds a real bug.
Concern: authors may "fix" closure failures by pulling referenced blocks into the core rather than writing a `--topic` pointer, which uses up the budget.

**Q8 — Vote: OUT**
Reasoning: The eval is a nondeterministic, paid release process whose result moves with model upgrades, so it records no rule and belongs in no decision. File a separate release chore with an owner, as AI/ML and Min propose. It depends on the extractor, and it records the model ID, sampling settings and a prompt-set hash so runs can be compared. The decision rationale can note that a future vote to raise the cap should bring compile-rate data.
Concern: the chore ticket sits unowned, and the cap gets defended with no coverage data.

**Web/Scripting:**

**Web, Phase D re-vote (2xvan0)**

**Q3. Vote: NAMES** (condition: API-shape divergences go in the Q6 head list, each citing a core block whose compiled fence uses the real API, e.g. `let v: Option[Int] = m.remove("k")` and an error-tagged `m["k"] = 1`)
Reasoning: Sys and Min showed that most API shape mismatches in Blink are type errors and not silent, so the recovery path is the same one as for a wrong name. The facts that really are silent are language rules and belong in core blocks anyway. A compiled fence pins the API shape against lib/std with no new user-visible attribute, which is less surface for users to puzzle over and a stronger check than a marker.
Concern: authors may write a divergence bullet without a fence that exercises the shape, so review must reject bare prose claims about return types.

**Q5. Vote: BASE+CLOSURE** (closure = every ID or `§` reference in the generated core names a core block or is an explicit `--topic` pointer; prelude names, builtins and keywords count as defined; no free-text term closure)
Reasoning: Six panelists now agree on this narrow definition. It is one set lookup over IDs the extractor already holds. It closes the real leak: a reference that resolves in sections/ points at text the model does not have, and the model fills the gap from priors. `pub` coverage holds by construction and stays a follow-up for the API-topic work.
Concern: authors may "fix" closure failures by pulling whole blocks into the core instead of using a `--topic` pointer, and so eat the budget.

**Q8. Vote: OUT** (condition: a release chore ticket filed in the same change, and the decision rationale says a future cap-raise vote should bring compile-rate data recorded with model ID, sampling settings and a prompt-set hash)
Reasoning: I change from ADVISORY. Min's argument holds: a decision records rules, and a non-binding line is dead text that its own supporters predict will be skipped. Sys's baseline point also holds: without a pinned model and pinned settings, the trend mostly measures model upgrades. A chore with an owner and the rationale note keep the idea alive and attached to the one moment it matters, a cap-raise vote.
Concern: the chore ticket sits unowned in the backlog, and the next cap-raise vote happens with no data anyway.

**PLT:**

**PLT, Phase D re-vote**

**Q3: NAMES** (changed from DIVERGE)
Reasoning: My only reason for DIVERGE was that a hand-written API-shape bullet can go stale against lib/std. Web's and AI/ML's condition removes that. Each API-shape rule in the core carries a compiled fence that pins the shape (`let v: Option[Int] = m.remove("k")`, plus an error-tagged `m["k"] = 1`). The fence-compile gate then catches drift with no lib/std marker, and that check is stronger than the marker because it checks the actual type. Sys and Min are also right that most shape mismatches already surface as type errors.
Condition: the decision text states that API-shape divergences live in the head list as core rule blocks, each backed by a compiled fence that exercises the shape.
Concern: authors may write the fence too loosely (e.g. `let v = m.remove("k")`) so it no longer pins the type, so the review rule must require an annotated type or an error tag.

**Q5: BASE+CLOSURE** (changed from BASE+CLOSURE+PUB), closure defined as IDs only
Reasoning: I concede PUB. It holds by construction once the generator walks every `pub` item. The definition I vote for is the one Sys, DevOps and Min converged on: every core ID or `§` reference in the generated core resolves to a core block or is written as an explicit `--topic` pointer. That is one set-difference over data the extractor already holds, and it is distinct from BASE's "resolves somewhere in sections/". AI/ML's extension (backticked type and trait names checked against core plus the NAMES list) is sound and lexical, but it should be a follow-up that earns its place by catching a real miss.
Concern: authors may turn every outbound reference into a `--topic` pointer to pass the gate, which keeps the core closed only in name.

**Q8: OUT** (changed from ADVISORY), with the chore filed along with the decision
Reasoning: Sys's argument on measurement validity decides it for me. First-try compile rate across releases moves with model ID, sampling and prompt set, so without those held fixed the trend measures model upgrades, not the core. A non-binding line in the decision cannot impose that rigor. A release chore with an owner and recorded model/settings/prompt-hash can. Per AI/ML, the decision rationale should note that a future cap-raise vote should bring compile-rate data.
Concern: the chore ticket is filed and never picked up, and the next cap-raise vote proceeds on taste.

**DevOps:**

**DevOps, Phase D re-vote**

**Q3: NAMES**
Reasoning: The divergent API facts go in the Q6 head list as core rules that cite IDs, so no new lib/std attribute is needed. PLT's single-source objection holds against a bare prose bullet, but not against Web's and AI/ML's condition, which I adopt. Each API-shape rule carries a compiled fence that uses the real API (`let v: Option[Int] = m.remove("k")`, plus an error-tagged `m["k"] = 1`). If lib/std changes, the fence-compile gate fails, which is stronger drift protection than a marker.
Concern: The decision text must state the fence requirement explicitly, or API-shape bullets will land as unchecked prose.

**Q5: BASE+CLOSURE**
Reasoning: Closure is over explicit references only. Every core ID or `§` reference in the generated core must resolve to a core block or to an explicit `--topic` pointer, and prelude names and keywords count as defined (the PLT/Min definition). This differs from the base gate, which accepts an ID that resolves anywhere in sections/, text the model cannot see. AI/ML's extension to backticked type names is a reasonable follow-up, not part of this gate.
Concern: Authors may "fix" closure failures by pulling whole blocks into the core instead of writing a `--topic` pointer, and so spend the budget.

**Q8: OUT (changed from ADVISORY)**
Reasoning: Sys's point moved me. First-try compile rate shifts with the model, the sampling settings and the prompt set, so a trend line across releases mostly measures model upgrades. That is a weak basis for a cap vote, and that use was my whole argument for ADVISORY. AI/ML's form keeps the value without decision text: file a release chore in the same change, and note in the rationale that a cap-raise proposal should bring compile-rate data, recorded with model ID, settings and prompt-set hash.
Concern: The chore ticket gets filed and never run, so the next cap-raise vote has no data anyway.

**AI/ML:**

**AI/ML, Phase D re-vote**

**Q3: Vote NAMES** (on condition that API-shape rules in the core carry a compiled fence that exercises the shape)
Reasoning: PLT's stale-prose objection fails once each API-shape bullet cites a core block whose fence uses the real signature, for example `let v: Option[Int] = m.remove("k")`. Any change in lib/std then fails CI, so nothing is an unchecked copy. Sys and Min add a point I underweighted: in Blink most shape mismatches are type errors and not silent, so a model recovers by the same compile-then-`blink doc` path it uses for a wrong name. The truly silent cases are semantic rules, which belong in the core anyway.
Concern: authors may write API-shape bullets without the backing fence, so the review rule or the ID-resolve gate must reject a head-list bullet whose cited block has no fence.

**Q5: Vote BASE+CLOSURE** (closure over explicit references only)
Reasoning: I drop my extension to backticked type names and converge on the definition that Sys, Web, PLT, DevOps and Min accept. Every core ID or `§` reference in the generated core must resolve to a core block or to an explicit `--topic` pointer, and free-text terms are not checked. This is one set-difference over data the extractor already holds. It is the only check that makes "the core stands alone" true for the model reading it.
Concern: an undefined type name in prose still slips through, so the follow-up for term closure should be filed rather than forgotten.

**Q8: Vote OUT** (on condition that the release chore ticket is filed in the same change)
Reasoning: The decision records spec and CI rules, and an eval is neither. Sys's baseline point is decisive for me: first-try compile rate moves with model upgrades, prompts and sampling more than with the core, so a trend line in DECISIONS.md would be misread. The chore ticket should require each run to record the model ID, the sampling settings and a hash of the prompt set, and it should depend on the extractor landing.
Concern: if the chore is not filed in the same change, the only coverage signal for a future cap-raise vote vanishes.

**Minimalism:**

**Min, Phase D re-vote**

**Q3: NAMES**
Reasoning: The divergent API facts go in the Q6 head list as core rules that cite IDs. That needs no new lib/std attribute, which would be user-visible surface whose only job is to steer a docs generator. I accept the Web, DevOps and AI/ML condition: each API-shape rule carries a compiled fence that uses the real API, e.g. `let v: Option[Int] = m.remove("k")` plus an error-tagged `m["k"] = 1`. Those fences sit under the existing compile gate, so the condition costs nothing new. It also answers PLT's drift point, because a change to the signature breaks the fence in CI.
Concern: the head list may collect API-shape bullets until it becomes a hand-picked method table that eats the core budget.

**Q5: BASE+CLOSURE**
Reasoning: Sys, Web, PLT and DevOps are right that "resolves somewhere in sections/" and "resolves inside the core" are different properties. Only the second stops the model from meeting a reference it cannot see. Closure must be IDs only: every ID cited from a core block names a core block, or the citation becomes a `--topic` pointer. I do not adopt AI/ML's extension to backticked type names in this decision; it can come as a follow-up if the ID check misses a real case.
Concern: if the decision text does not pin "IDs only", the check will grow into term-level closure and turn noisy.

**Q8: OUT**
Reasoning: A spec decision records what the spec and CI promise, and a nondeterministic paid eval promises neither. Sys's point also holds: across releases, the trend tracks model upgrades more than core quality. I support AI/ML's form of OUT. File a separate release chore in the same change, and note in the rationale that a future vote to raise the cap should bring compile-rate data.
Concern: the chore ticket is filed but never run, so a cap-raise vote still arrives with no coverage data.

### Final Spec

§8.17 *In-Context Language Reference* in `sections/06_tooling.md`; `blink llms` rows in §8.14; §8.17 *Summary* renumbered to §8.18.

```blink
fn main() ! IO {
    let mut m = Map.new[Str, Int]()
    m.insert("k", 1)
    let v: Option[Int] = m.remove("k")    // an API-shape core block pins the type
    io.println("{v ?? 0}")
}
```

- The core is marked blocks in `sections/` (`<!-- core:<id> -->` … `<!-- /core -->`), with stable semantic IDs. A generator builds the core text; nobody edits it by hand.
- The core is at most 46,000 bytes. Each topic is at most 12 KiB; the index is at most 6 KiB. Only a panel vote raises the core cap.
- The core holds the language, prelude type and trait names, one line per prelude trait, and one pointer line per topic. Method tables, tooling, FFI, install and arena detail are topics.
- Method tables are generated from lib/std; CLI-flag topics are generated from the CLI registrations.
- A divergence list heads the core and a common-errors list ends it. Each bullet cites a core ID. An API-shape divergence has a fence that pins the shape.
- Checks: caps, fences compile, error fences fail with the stated code, regen-diff, unique and resolving IDs, closure over explicit references, diagnostic codes in the catalog.
- `blink llms --full` is the core; `--all` prints everything; `--list` shows sizes.
- A paragraph that explains a rule is `*Rationale.*`, never normative.
- Landing order (implementation): cap the hand-trimmed file first, then build the extractor.
