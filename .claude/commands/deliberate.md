# Deliberate: Pact Spec Gap Resolution

Run a 5-expert panel deliberation on a Pact spec gap. Auto-updates GAPS.md, DECISIONS.md, and relevant spec sections.

**Usage:** `/deliberate` (auto-picks next gap) or `/deliberate $ARGUMENTS` (match by keyword)

---

## Step 1: Find Target Gap

Read `GAPS.md`. If `$ARGUMENTS` is provided, find the first `- [ ]` item whose text matches the argument (case-insensitive substring). Otherwise pick the first unchecked `- [ ]` item, preferring Tier 1 > Tier 2 > Tier 3.

State clearly which gap you're resolving and which tier it belongs to. If no unchecked gaps remain, report that and stop.

## Step 2: Gather Context

Read the following in parallel:
- `DECISIONS.md` — past votes, rejected features, resolved questions
- `OPEN_QUESTIONS.md` — archived panel deliberations for format reference
- All `sections/*.md` files referenced by the gap's `§` markers
- Any `examples/*.pact` files that use the feature

Identify:
- Constraints from past votes that affect this gap
- Dependencies on other unresolved gaps
- Existing code/examples that already assume behavior
- Cross-references to other spec sections

## Step 3: Design Option Space

Propose 2-4 concrete options (A/B/C/D). Each option MUST include:
- A Pact code example using correct Pact syntax (fn keyword, { } braces, no semicolons, "double quotes", x.len() method-call, square bracket generics)
- Tradeoffs (complexity, learnability, compiler difficulty, interaction with effects/traits/GC)
- Cross-language survey (how do 3+ other languages handle this?)
- Impact on other unresolved gaps

## Step 4: Run Panel (Team-Based)

Five experts vote **independently as separate agents**. Use the Teammate tool to spawn a team, then dispatch each expert as a parallel agent. Experts MUST disagree where their values genuinely conflict — do not converge to consensus artificially.

### 4a: Spawn the team

Use the Teammate tool with `operation: "spawnTeam"` and `team_name: "pact-panel"`.

### 4b: Create expert tasks

Create 5 tasks using TaskCreate, one per expert. Each task description MUST include:
1. The expert's full profile (name, domain, trigger question, references, personality) from the profiles below
2. The full option space from Step 3 (all options with code examples and tradeoffs)
3. Relevant context: Pact syntax rules, key past decisions that constrain this gap, cross-references
4. The voting format instructions (vote letter, reasoning, concern per question)
5. Instruction: "Vote on each question independently. Return your votes in the specified format. Do NOT try to reach consensus — vote based on YOUR domain priorities."

### 4c: Spawn 5 expert agents in parallel

Use the Task tool 5 times in a **single message** (parallel), each with:
- `team_name: "pact-panel"`
- `name`: the expert name (e.g., "systems", "web", "plt", "devops", "aiml")
- `subagent_type: "general-purpose"`
- A prompt containing: the expert profile, option space, context, and voting instructions from their task

Each expert agent should return their votes in this format per question:
1. **Vote** (which option letter)
2. **Reasoning** (2-4 sentences, anchored in their domain)
3. **Concern** (what could go wrong with the winning option, from their POV)

### 4d: Collect votes

Wait for all 5 experts to return. Collect their votes. Tally results per question. Identify dissent.

### 4e: Cleanup

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

**AI/ML** — LLM code generation accuracy, training data representation, decision points.
- Trigger: "How often will an LLM get this wrong? Is there training data for this pattern? How many decision points does this add?"
- References: LLM benchmark data, GitHub Copilot patterns, training corpus statistics
- Personality: Statistical thinker. Values patterns with high representation in training data. Suspicious of novel syntax or semantics LLMs haven't seen.

## Step 5: Summarize Decision

State:
- **Result**: Which option won
- **Vote tally**: e.g., "4-1 (DevOps dissented)"
- **Dissent summary**: 1-2 sentences per dissenter explaining their position
- **Key argument**: The single strongest argument that swung the decision

## Step 6: Write Spec Text

Write the new spec content into the appropriate `sections/*.md` file:
- Match existing section style (heading levels, code block format, cross-references)
- Find the correct insertion point (after related content, maintaining section numbering)
- Include Pact code examples that follow all syntax rules
- Cross-reference other sections where relevant (e.g., "see §3.6 for trait resolution")
- If a new subsection number is needed, use the next available number in that section

## Step 7: Update Tracking Files

### GAPS.md
- Change `- [ ]` to `- [x]` for the resolved gap
- Append resolution note in the same format as existing resolved items: `*(Resolved: §X.Y, panel vote N-M description)*`

### DECISIONS.md
Two updates:

1. **Resolved Questions table** — Add a row in the existing table format:
```
| Decision name | Result summary | Vote tally |
```

2. **Full deliberation section** — Add a new `## Section Title — Design Rationale` section at the end (before the `## Open Questions` section), following the exact format of existing deliberations (see While/Loop, If/Else, Iterator, Type Conversions sections as templates). Include:
   - `### Panel Deliberation` header
   - One subsection per question voted on (if multiple sub-questions)
   - Each expert's reasoning as a bullet under the question
   - `*(dissent)*` marker on dissenting votes

## Step 8: Quality Checks

Before finishing, verify:
1. All Pact code examples use correct syntax (fn, braces, no semicolons, double quotes, .len() not .len, square bracket generics)
2. No contradiction with existing decisions in DECISIONS.md
3. Section numbering is correct and continuous
4. Cross-references (§X.Y) point to real sections
5. The GAPS.md checkbox is actually checked off
6. The DECISIONS.md table row matches the format of existing rows

## Step 9: Report

Summarize what changed:
- Which gap was resolved
- The decision and vote
- Which files were modified and where
- Any downstream impacts on other unresolved gaps (e.g., "resolving tuple types may unblock destructuring and pattern matching grammar")
- Suggested next gap to deliberate
