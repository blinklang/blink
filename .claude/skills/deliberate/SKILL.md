---
description: Deliberate: Pact Spec Gap Resolution
---

# Deliberate: Pact Spec Gap Resolution

Run a 5-expert panel deliberation on a Pact spec gap. Auto-updates GAPS.md, DECISIONS.md, and relevant spec sections.

**Usage:** `/deliberate` (auto-picks next gap) or `/deliberate $ARGUMENTS` (match by keyword)

---

## Step 1: Find Target Spec Task

Run `br ready -t type:spec -t repo:pact --json` to get all unblocked spec tasks.

If `$ARGUMENTS` is provided, find the first task whose title matches the argument (case-insensitive substring). Otherwise pick the highest-priority task.

State clearly which spec task you're resolving. If no spec tasks are ready, report that and stop.

## Step 2: Gather Context

Read the following in parallel:
- `DECISIONS.md` — past votes, rejected features, resolved questions
- `OPEN_QUESTIONS.md` — archived panel deliberations for format reference
- All `sections/*.md` files relevant to the task topic
- Any `examples/*.pact` files that use the feature

Identify:
- Constraints from past votes that affect this gap
- Dependencies on other unresolved gaps
- Existing code/examples that already assume behavior
- Cross-references to other spec sections

### Step 3: Spin up the team

Use the teammate tool to spawn a team (experts as defined in project). `team_name: "pact-panel"`

## Step 4: Design Option Space (team-based)

Each teammate, independently as a seperat agent, should be spawned to propose an idea. Each option MUST include:
- A Pact code example using correct Pact syntax (fn keyword, { } braces, no semicolons, "double quotes", x.len() method-call, square bracket generics)
- Tradeoffs (complexity, learnability, compiler difficulty, interaction with effects/traits/GC)
- Cross-language survey (how do 3+ other languages handle this?)
- Impact on other unresolved gaps

## Step 5: Run Panel (Team-Based)

The five experts vote **independently as separate agents**. Experts MUST disagree where their values genuinely conflict — do not converge to consensus artificially.
Instruction: "Vote on each question independently. Return your votes in the specified format. Do NOT try to reach consensus — vote based on YOUR domain priorities."

Each expert agent should return their votes in this format per question:
1. **Vote** (which option letter)
2. **Reasoning** (2-4 sentences, anchored in their domain)
3. **Concern** (what could go wrong with the winning option, from their POV)

### Step 6: Collect votes

Wait for all 5 experts to return. Collect their votes. Tally results per question. Identify dissent.

### Step 7: Cleanup

After collecting all votes, shut down all expert agents and clean up the team using `Teammate` with `operation: "cleanup"`.


### Expert Profiles

**Systems (Sys)** — Performance, zero-cost abstractions, what the hardware sees.
- Trigger: "What does this compile to? What's the runtime cost? Can it be monomorphized?"
- References: C, Rust, Zig, Go runtime internals
- Personality: Skeptical of abstractions that hide cost. Wants predictable codegen. Will accept complexity if it enables zero-overhead.

**Web/Scripting (Web)** — Developer experience, learning curve, productivity.
- Trigger: "Would a JS/Python dev understand this in 5 minutes? How many Stack Overflow questions will this generate?"
- References: JavaScript, TypeScript, Python, Kotlin
- Personality: Impatient with clever solutions. Values familiarity and "just works." Champions the 90% use case over the 10% edge case.

**PLT (Programming Language Theory)** — Soundness, compositionality, type theory.
- Trigger: "Is this sound? Does it compose? What's the typing rule? Does it interact cleanly with the effect system?"
- References: Haskell, OCaml, Koka, Agda, ML family
- Personality: Formal and precise. Will reject "works in practice" if it's theoretically unsound. Cares about principled design that won't paint the language into a corner.

**DevOps/Tooling (DevOps)** — LSP, error messages, formatter, linter, diagnostics.
- Trigger: "What does the error message look like? Can the LSP autocomplete this? How does `pact fmt` handle it?"
- References: Go toolchain, Rust analyzer, TypeScript language server
- Personality: Pragmatic. Judges features by their diagnostic surface. Will reject elegant designs that produce bad error messages.

**AI/ML** — LLM code generation accuracy, learnability, token efficiency.
- Trigger: "Can an AI learn this from the spec alone? How many decision points does this add? What's the token cost for common patterns?"
- References: LLM benchmark data, GitHub Copilot patterns, AI-first design principles
- Personality: Evaluates through learnability, generability, token efficiency, and debuggability. Values designs any capable AI can learn from spec alone — not just patterns already in training data. Flags features that add unnecessary decision points or token overhead for common patterns.

## Step 8: Summarize Decision

State:
- **Result**: Which option won
- **Vote tally**: e.g., "4-1 (DevOps dissented)"
- **Dissent summary**: 1-2 sentences per dissenter explaining their position
- **Key argument**: The single strongest argument that swung the decision

## Step 8.5: AI-First Review

Evaluate the winning decision against 5 criteria (score each pass/fail):

1. **Learnability** — Can AI learn this from spec + examples without relying on other languages' training data?
2. **Consistency** — Follows existing Pact patterns, or introduces a special case?
3. **Generability** — Can AI reliably generate correct code using this feature?
4. **Debuggability** — When AI gets this wrong, are error messages clear enough to self-correct?
5. **Token Efficiency** — Does this minimize token count for common patterns? (verbose syntax = real cost)

If **2+ criteria fail** → flag decision. Panel reconsiders with those specific concerns addressed (not a veto — just forces another look with AI-first lens explicitly on the table).

If **0-1 fail** → proceed to Step 9.

## Step 9: Write Spec Text

Write the new spec content into the appropriate `sections/*.md` file:
- Match existing section style (heading levels, code block format, cross-references)
- Find the correct insertion point (after related content, maintaining section numbering)
- Include Pact code examples that follow all syntax rules
- Cross-reference other sections where relevant (e.g., "see §3.6 for trait resolution")
- If a new subsection number is needed, use the next available number in that section

## Step 10: Update Tracking Files

### Bridge Task
- Close the br task: `br close <id>`

### DECISIONS.md
Two updates:

1. **Resolved Questions table** — Add a row in the existing table format:
```
| Decision name | Result summary | Vote tally |
```

2. **Design rationale file** — Create a new file in `decisions/` directory named with kebab-case (e.g., `decisions/my-feature-name.md`). Start the file with a `[< All Decisions](../DECISIONS.md)` back-link, then follow the exact format of existing deliberation files (see existing files in `decisions/` as templates). Include:
   - `### Panel Deliberation` header
   - One subsection per question voted on (if multiple sub-questions)
   - Each expert's reasoning as a bullet under the question
   - `*(dissent)*` marker on dissenting votes

3. **Design Rationales section** — Add a link to the new file in the `## Design Rationales` section of DECISIONS.md

## Step 11: Quality Checks

Before finishing, verify:
1. All Pact code examples use correct syntax (fn, braces, no semicolons, double quotes, .len() not .len, square bracket generics)
2. No contradiction with existing decisions in DECISIONS.md
3. Section numbering is correct and continuous
4. Cross-references (§X.Y) point to real sections
5. The GAPS.md checkbox is actually checked off
6. The DECISIONS.md table row matches the format of existing rows

## Step 12: Report

Summarize what changed:
- Which gap was resolved
- The decision and vote
- Which files were modified and where
- Any downstream impacts on other unresolved gaps (e.g., "resolving tuple types may unblock destructuring and pattern matching grammar")
- Suggested next gap to deliberate
