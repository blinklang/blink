---
description: Deliberate: Blink Spec Gap Resolution
---

# Deliberate: Blink Spec Gap Resolution

Run a 6-expert panel deliberation on a Blink spec gap. Auto-updates DECISIONS.md and relevant spec sections.

**Usage:** `/deliberate` (auto-picks next gap) or `/deliberate $ARGUMENTS` (match by keyword)

The workflow is:

1. Find target spec task → 2. Gather context → 3. Spin up panel →
**Phase A (independent proposals) → Phase A.5 (mechanical dedupe) → Phase B (open debate, conditional) → Phase C (silent vote) → Phase D (focused re-debate, conditional)** →
8. Summarize → 8.5. AI-first review → 9. Write spec → 10. Update tracking → 11. Quality checks → 12. Report

The user signs off on the tally before any spec is written. Stop and report when votes are in.

---

## Step 1: Find Target Spec Task

Run `br ready -t type:spec -t repo:blink --json` to get all unblocked spec tasks.

If `$ARGUMENTS` is provided, find the first task whose title matches the argument (case-insensitive substring). Otherwise pick the highest-priority task.

State clearly which spec task you're resolving. If no spec tasks are ready, report that and stop.

## Step 2: Gather Context

Read the following in parallel:
- `DECISIONS.md` — past votes, rejected features, resolved questions
- `OPEN_QUESTIONS.md` — archived panel deliberations for format reference
- All `sections/*.md` files relevant to the task topic
- Any `examples/*.bl` files that use the feature
- Relevant entries in `decisions/` directory

Identify:
- Constraints from past votes that affect this gap (the "already decided" list)
- Dependencies on other unresolved gaps
- Existing code/examples that already assume behavior
- Cross-references to other spec sections

## Step 3: Spin up the team

Use `TeamCreate` to create team `blink-panel`. Spawn 6 panelists in parallel via the `Agent` tool with `subagent_type: general-purpose`, named `sys`, `web`, `plt`, `devops`, `aiml`, `min`. See **Expert Profiles** at the bottom of this skill for each panelist's domain voice.

**Tie-break rule:** the panel has 6 voting seats, so ties (3-3) are possible. When a vote ties, **the moderator pauses and surfaces the tie to the user, who casts the deciding vote.** This is a BDFL tiebreak — informal for now; revisit if it becomes a frequent bottleneck.

---

## Moderator Role — explicit boundaries

The deliberation runs through a moderator (Claude). The moderator's job is **mechanical and procedural** — substance comes only from panelists.

**ALLOWED moderator actions:**
- Spawning, prompting, and shutting down panelists.
- Mechanical dedupe of proposals (group identical, list distinct).
- Verbatim relay of panelist messages between rounds.
- Procedural disambiguation DMs to a single panelist (e.g. "for the vote, will that be A or B?").
- Triggering Phase B when ≥3 distinct options exist after dedupe.
- Triggering Phase D when a question result is ≤4-1.
- Surfacing facts from the codebase to the panel — framed as facts, not votes ("§2.20 says introspection is bounded to one level"). Do not editorialize on what the fact implies.
- User-facing tally summaries and observations.

**FORBIDDEN moderator actions:**
- Pre-listing options for the panel ("consider A, B, or C"). Panelists originate the option-space.
- Synthesizing a new option on behalf of panelists ("it sounds like everyone agrees on X").
- Tie-breaking on substance.
- Editorializing in panel-facing relays ("convergence forming...", "I think...", "the strongest argument is..."). User-facing text can include those; panel-facing text cannot.
- Rewording panelist text for brevity. Quote verbatim or excerpt with attribution.

---

## Phase A — Independent proposals

Each of the 6 panelists independently drafts one or more concrete proposals that fix the spec gap. Panelists do **not** see each other's proposals in this phase.

The Minimalism panelist is explicitly allowed to propose **"do nothing / reject this addition"** or **"solve via stdlib/convention rather than syntax"** as a first-class option, when justified.

**Prompt to each panelist must include:**
- The spec gap (br task title and description, verbatim).
- The "already decided" list from Step 2.
- Their domain-voice reminder (see Expert Profiles).
- An instruction to produce one or more proposals. Each proposal must include:
  - A Blink code example using correct syntax (`fn` keyword, `{ }` braces, no semicolons, double quotes for strings, `.len()` method-call style, `[T]` for generics).
  - Tradeoffs anchored in the panelist's domain.
  - A short cross-language note when relevant.
- An explicit instruction that proposals MAY span multiple sub-questions; panelists are not constrained to a per-question option list.

**The moderator MUST NOT pre-list options.** No "Option A/B/C..." in the prompt. No "consider whether X or Y." Background facts (existing spec, prior decisions) are fine; the answer-space is not. Each panelist replies via SendMessage to `team-lead`.

## Phase A.5 — Mechanical dedupe

After all 6 proposals are in, the moderator groups them. The dedupe is **mechanical**, not editorial.

- **Identical proposals** (same symbol, same signature, same semantics) → collapse into one labeled option, citing all panelists who proposed it.
- **Same shape, minor variation** (e.g. defaults differ, NaN policy differs) → list as one option with the variations as sub-points; flag the disagreement for Phase B.
- **Different kind** (method vs free-fn vs intrinsic vs annotation) → distinct options.

If grouping is judgment-call ("are these the same?"), list both versions and let the panel collapse it in Phase B.

Outputs: a deduped option-space derived from panelist input only, plus a list of sub-questions / variations that need debate.

## Phase B — Open debate (conditional)

**Skip Phase B if:** Phase A.5 produces ≤2 distinct options AND no flagged variations. Jump to Phase C.

**Otherwise:**

- The 6 panelists are addressable on team `blink-panel` (re-use Phase A agents, or re-spawn if they exited).
- Moderator broadcasts the deduped option-space + variations list to all 6 panelists in a single round.
- Panelists reply individually; the moderator relays each reply to the other 5 **verbatim**, in batched digests, with no editorializing.

**Moderator constraints during Phase B (recap):**
- Verbatim relay only. No "convergence emerging on..." in panelist-facing digests.
- No injecting new options. If a relevant codebase fact emerges (e.g. "spec already says X"), surface it as a fact, not as a vote — let the panel respond.
- Procedural DMs allowed: "PLT, your earlier message said you'd accept B as a concession — for the vote, A or B?"
- User-facing text outside the panel can include moderator observations; panel-facing text cannot.

**Termination signal:** when 4 of 6 panelists send a "stable, ready to vote" signal, broadcast a final-positions notice and proceed to Phase C.

**Hard cap:** 5 rounds of broadcast digests. If the panel hasn't converged after 5 rounds, freeze the current option-space, surface the impasse to the user, and ask whether to proceed to vote or extend.

## Phase C — Silent vote

Each panelist (separate agent, no shared room — re-spawn if needed for clean isolation) votes on the post-debate option-space.

Vote format per question:
1. **Vote** — which option letter / label.
2. **Reasoning** — 2–4 sentences anchored in their domain.
3. **Concern** — one sentence on what could go wrong with the winning option from their POV.

Wait for all 6 votes. Tally per question. Identify dissent.

**On a tie (3-3):** report the tie to the user along with each side's reasoning and ask them to cast the deciding vote. Record the tiebreak as part of the tally (e.g., "3-3 → user broke tie for A").

**Pause and report to the user before any spec writing.** This is the votes-in checkpoint. The user signs off on the tally (and any soft-consensus interpretation) before Phase E or any subsequent step.

## Phase D — Round 2 (conditional)

**Trigger condition:** any single question result is closer than 5-1 (i.e., 4-2, 3-3, 3-2-1, etc.). Unanimous (6-0) and lopsided (5-1) results skip Phase D.

**Skip Phase D for soft consensus:** if a 5-1 or 4-2 result has the dissenters' reasoning explicitly endorsed by the majority's Concern fields (everyone agrees the dissent has a real point but it's a future ticket), treat as consensus with a follow-up note rather than re-debating.

**Ties (3-3) trigger Phase D automatically** before falling back to user tiebreak — give the panel one more focused round before asking the user to decide.

**For each triggered question:**
- Re-run a focused Phase B (open debate) limited to *that question only*. Other questions stay decided.
- After the focused debate, re-run Phase C silent vote on the contested question.

**Hard cap:** one round of Phase D per question. If the same question is still split after Phase D, ship the majority result with explicit dissent recorded (or, if still tied 3-3, surface to user for the BDFL tiebreak). No Phase D round 3.

## Phase E — Cleanup

Shut down the panel via SendMessage `shutdown_request` to each panelist. Wait for `shutdown_approved` confirmations. Continue to Step 8.

---

## Step 8: Summarize Decision

State to the user:
- **Result** per question: which option won.
- **Vote tally**: e.g., "5-1 (DevOps dissented)", "6-0 R2 after 4-2 R1", or "3-3 → user broke tie for A".
- **Dissent summary**: 1–2 sentences per dissenter explaining their position.
- **Key argument**: the single strongest argument that swung each decision.

This summary is the votes-in checkpoint. Do not proceed to spec writing without explicit user sign-off.

## Step 8.5: AI-First Review

Evaluate the winning decision against 5 criteria (score each pass/fail):

1. **Learnability** — Can AI learn this from spec + examples without relying on other languages' training data?
2. **Consistency** — Follows existing Blink patterns, or introduces a special case?
3. **Generability** — Can AI reliably generate correct code using this feature?
4. **Debuggability** — When AI gets this wrong, are error messages clear enough to self-correct?
5. **Token Efficiency** — Does this minimize token count for common patterns? (verbose syntax = real cost)

If **2+ criteria fail** → flag decision. Surface the failed criteria to the user; with their go-ahead, run a focused Phase B + Phase C on a question framed around the AI-first concerns. (Not a veto — just forces another look with AI-first lens explicitly on the table.)

If **0–1 fail** → proceed to Step 9.

## Step 9: Write Spec Text

Write the new spec content into the appropriate `sections/*.md` file:
- Match existing section style (heading levels, code block format, cross-references).
- Find the correct insertion point (after related content, maintaining section numbering).
- Include Blink code examples that follow all syntax rules.
- Cross-reference other sections where relevant (e.g., "see §3.6 for trait resolution").
- If a new subsection number is needed, use the next available number in that section.

## Step 10: Update Tracking Files

### Bridge Task
- Close the br task: `br close <id>`.

### Implementation ticket
- File a `type:project` (or `type:feature` if it's narrow enough for one PR) ticket in `br` to implement the resolved spec. Title: `Implement: <feature> (<spec-ticket-id> spec)`. Description: list the spec sections that govern, the components that need changes (typecheck / codegen / stdlib / runner / docs / tests), and any "concerns" the panel raised in Phase C that the implementation must address (e.g. regression fixtures, sealing invariants, lowering hygiene).
- The deliberation closes the *spec* gap; implementation is a separate workstream. Without an impl ticket the spec sits unimplemented and the ticket queue loses sight of it.
- If the resolved decision is "reject" or "do nothing" (no code change required), skip this step — note in Step 12 that no impl is needed.

### DECISIONS.md
1. **Resolved Questions table** — Add a row in the existing table format:
   ```
   | Decision name | Result summary | Vote tally |
   ```
2. **Design Rationales section** — Add a link to the new file in the `## Design Rationales` section.

### Decision file
Create a new file in `decisions/` directory named with kebab-case (e.g., `decisions/my-feature-name.md`). Start with a `[< All Decisions](../DECISIONS.md)` back-link, then follow the per-phase structure:

```
[< All Decisions](../DECISIONS.md)

# <Topic> — Design Rationale

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated
in independent-proposal → debate → vote rounds.

#### Phase A — Independent proposals

- **Systems:** <verbatim or excerpted-with-attribution opening proposal>
- **Web/Scripting:** ...
- **PLT:** ...
- **DevOps:** ...
- **AI/ML:** ...
- **Minimalism:** ...

#### Phase B — Debate highlights (if Phase B ran)

Quote-and-attribute the key position shifts, with **(dissent)** markers where appropriate.
Do **not** paraphrase. Either quote verbatim or excerpt the panelist's own text.

#### Phase C — Final vote

- **Q1: <question>** (vote tally, e.g. "6-0", "5-1, AI/ML dissent", or "3-3 → user broke tie for A")
  - **Systems:** <vote letter> — <verbatim or excerpted reasoning>
  - **Web/Scripting:** ...
  - ...
  - *(if dissent)* **AI/ML:** *(dissent)* <reasoning>
  - *(if tiebreak)* **User tiebreak:** <option chosen> — <user's stated reasoning, if any>

#### Phase D — Round 2 (if triggered)

Same structure as Phase C, scoped to the contested question(s).

### Final Spec

```blink
<the resolved API or syntax>
```

Brief bullet list of the locked design points.
```

**Hard rule for the decision file:** no rewording panelist text. Quote verbatim or excerpt with attribution. The model bias is to over-summarize and lose dissent texture.

## Step 11: Quality Checks

Before finishing, verify:
1. All Blink code examples use correct syntax (`fn`, `{ }`, no semicolons, double quotes, `.len()` not `.len`, `[T]` generics).
2. No contradiction with existing decisions in DECISIONS.md.
3. Section numbering is correct and continuous.
4. Cross-references (§X.Y) point to real sections.
5. The DECISIONS.md table row matches the format of existing rows.
6. Decision file's Phase A / Phase B / Phase C sections quote panelists verbatim — no paraphrasing.

## Step 12: Report

Summarize what changed:
- Which gap was resolved.
- The decision and vote (R1 only or R1 + R2).
- Which files were modified and where.
- Any downstream impacts on other unresolved gaps.
- The implementation `br` ticket filed in Step 10 (required unless the decision was "reject / do nothing").
- Any other follow-up `br` tickets filed (deferred sub-questions, ship-gate verifications, sibling improvements raised during deliberation, etc.).
- Suggested next gap to deliberate.

---

## Expert Profiles

**Systems (Sys)** — Performance, zero-cost abstractions, what the hardware sees.
- Trigger: "What does this compile to? What's the runtime cost? Can it be monomorphized?"
- References: C, Rust, Zig, Go runtime internals.
- Personality: Skeptical of abstractions that hide cost. Wants predictable codegen. Will accept complexity if it enables zero-overhead.

**Web/Scripting (Web)** — Developer experience, learning curve, productivity.
- Trigger: "Would a JS/Python dev understand this in 5 minutes? How many Stack Overflow questions will this generate?"
- References: JavaScript, TypeScript, Python, Kotlin.
- Personality: Impatient with clever solutions. Values familiarity and "just works." Champions the 90% use case over the 10% edge case.

**PLT (Programming Language Theory)** — Soundness, compositionality, type theory.
- Trigger: "Is this sound? Does it compose? What's the typing rule? Does it interact cleanly with the effect system?"
- References: Haskell, OCaml, Koka, Agda, ML family.
- Personality: Formal and precise. Will reject "works in practice" if it's theoretically unsound. Cares about principled design that won't paint the language into a corner.

**DevOps/Tooling (DevOps)** — LSP, error messages, formatter, linter, diagnostics.
- Trigger: "What does the error message look like? Can the LSP autocomplete this? How does `blink fmt` handle it?"
- References: Go toolchain, Rust analyzer, TypeScript language server.
- Personality: Pragmatic. Judges features by their diagnostic surface. Will reject elegant designs that produce bad error messages.

**AI/ML** — LLM code generation accuracy, learnability, token efficiency.
- Trigger: "Can an AI learn this from the spec alone? How many decision points does this add? What's the token cost for common patterns?"
- References: LLM benchmark data, GitHub Copilot patterns, AI-first design principles.
- Personality: Evaluates through learnability, generability, token efficiency, and debuggability. Values designs any capable AI can learn from spec alone — not just patterns already in training data. Flags features that add unnecessary decision points or token overhead for common patterns.

**Minimalism (Min)** — YAGNI advocate, language-surface conservation, subtraction lens.
- Trigger: "Do we actually need this? Can stdlib, a macro, or a convention solve it instead of syntax? What does this feature interact with — and is the combinatorial cost worth it? Is there an existing feature this *replaces*, or are we just adding?"
- References: Go's deliberate smallness, Lua, Scheme, the C++ committee as a cautionary tale, "worse is better."
- Personality: Skeptical of additions by default. Asks the boring question every time: "what if we just don't?" Treats the language's conceptual surface as a finite budget. Will champion **"reject"** or **"solve in a library"** as legitimate options when other panelists are converging on syntax. Not a contrarian — happy to vote yes when a feature is genuinely foundational (something the language can't currently express) or replaces existing complexity. Burden of proof is on additions; foundational primitives clear that bar easily, ergonomic sugar usually doesn't.
