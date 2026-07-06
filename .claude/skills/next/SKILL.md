---
description: Next: Pick and Work Blink Tasks
---

# Next: Pick and Work Blink Tasks

Pick ready tasks from Bridge and execute the appropriate workflow based on type.

`/next` **triages every picked task against the spec before working it** (Step 2.5). A ticket
is a signal, not a mandate — past-you filing it can be speculative or contradict the spec.
**Declining or reshaping a ticket is a valid, expected outcome**, not a failed run: the correct
answer is sometimes "this shouldn't be done as written," and that counts as work done.

**Usage:** `/next` (auto-picks, repo-scoped) · `/next <keyword>` (title match) · `/next <project>` (scope to a project)

---

## Step 0: Resolve Scope

Before fetching the graph, decide whether this run is **repo-scoped** or **project-scoped**.

Run `br project ls -t repo:blink --json` once. It returns only projects that have
`repo:blink` tasks, with their progress, e.g.:

```json
[{"id":"c9nw1f","name":"dataset-merge","status":"active","done":"4","total":"9"}]
```

Then:

- **If `$ARGUMENTS` is given and case-insensitively matches a project `name` or `id`** →
  **project-scoped mode**. Capture that project's `id`. Step 1 uses
  `br graph --project <id>` as the forest, and the in-flight tie-break in Step 2 is **skipped**
  (you're already inside one project, so every candidate shares it).

- **Otherwise** → **repo-scoped mode** (the default). Step 1 uses `br graph -t repo:blink`.
  The returned project list already contains **only** projects with `repo:blink` tasks, so the
  **in-flight set** = project ids where `status == "active"` AND `0 < done < total` (a project
  that's started but not finished — note `0/N` is *not* in-flight, nothing's done yet). For a
  `4/9` active project, `0 < 4 < 9` → in-flight. This filtered list is authoritative; the Step 2
  tie-break consults it directly.

  If `$ARGUMENTS` is given but matches no project, stay in repo-scoped mode and treat the
  argument as a **title keyword** (case-insensitive substring) for the filter in Step 2.

## Step 1: Fetch the Task Graph

Run the command chosen in Step 0:
- **repo-scoped:** `br graph -t repo:blink`
- **project-scoped:** `br graph --project <id>`

This gives the dependency forest. Unlike a flat ready list, the graph nests each unblocked
root (`[ ]`) above the blocked children (`[!]`) it gates — so you can see what each ready task
*unblocks*, which is the tie-breaker in Step 2.

One quirk to handle:
- **Workable tasks are the unblocked roots — rows marked `[ ]`, not `[!]`.** The nested
  `[!]` rows are *blocked* children; never select them. They exist only to show what a
  root unblocks (and to feed the leverage tie-break below).

If no `[ ]` blink roots exist, run `br blocked -t repo:blink`, report what's stuck, and ask the user how to proceed.

## Step 2: Select Tasks

Sort the unblocked roots by **priority → in-flight-project → type → leverage**. Priority is never overridden — a P0 bug still beats a P2 in-flight task.

If you're in repo-scoped mode and `$ARGUMENTS` was a keyword (matched no project in Step 0), filter tasks whose title matches the argument (case-insensitive substring).

**Selection logic — priority, then in-flight project, then type, then leverage:**

1. Sort the unblocked roots by priority (P0 > P1 > P2 > P3 > P4).
2. **In-flight tie-breaker:** within the same priority, prefer tasks belonging to an **in-flight project** (the Step 0 set) over those that don't — so `/next` finishes work it has already started rather than scattering across projects. In **project-scoped mode this tie-break is inert** (all candidates share the one project), so skip it.
3. **Type preference:** within the same (priority, in-flight) bucket, prefer: bug > friction > feature > project > spec (chore alongside bug).
4. **Leverage tie-breaker:** within the same (priority, in-flight, type) bucket, a root that unblocks more downstream work ranks higher. Count the blocked `[!]` descendants nested under each root in the graph; a root with downstream dependents outranks an equal leaf with none.
5. Walk the sorted list and pick up to 5 tasks, applying type rules:
   - `type:bug` / `type:friction` — auto-start, no confirmation needed.
   - `type:feature` — requires confirmation before starting.
   - `type:project` — requires confirmation; pick at most 1 project.
   - `type:spec` — tell the user to run `/deliberate` for this item. Only work it directly if the user confirms.
   - `type:chore` - auto-start, no confirmation needed.
6. YOU MUST NOT skip a higher-priority task just because of its type. A P2 spec should be surfaced before a P4 feature.

## Step 2.5: Triage Gate (MANDATORY before any `br start`)

Every ticket selected in Step 2 passes through this gate **before** Step 3 runs `br start`.
The gate is mandatory for `type:bug`, `type:chore`, `type:friction`, and `type:feature`.
(`type:spec` already defers to `/deliberate`; `type:project` already requires confirmation —
the spec-check still applies to their subtasks, but the "worth doing?" question is the user's
call there.)

**A ticket existing does not mean it must be done.** Past-you filing a ticket recorded observed
behavior plus a *guessed* root cause or fix — the guess can violate the spec, be obsolete, or be
subsumed by other work. DECLINE / RESHAPE / DEFER are first-class outcomes; the agent is **not
failing** by not writing code.

**Keep it lightweight — scale depth to the ticket.** For a sound, clearly-scoped ticket this is a
~30-second spec probe ending in PROCEED, *not* a mini-deliberation. Go deep only when the ticket
proposes a specific fix, looks speculative, or its premise smells off. Don't turn every run into a
panel.

### Part A — Verify against the spec (read-only first)

1. `br show <id>` — read the ticket body in full. **Note existing agent notes**: a prior triage
   may already have reached a verdict. If so, surface that verdict and confirm it rather than
   re-litigating from scratch (unless the user has since overridden it).
2. `rg` the relevant `sections/*.md` for the feature / warning code / behavior the ticket touches,
   and read the governing rule in full. Also check `decisions/*.md` and `DECISIONS.md` for any past
   vote that constrains this ticket (e.g. a 5-1 rejection of the intrinsics a migration would need).
3. Confirm the ticket's **expected behavior** *and* its **proposed fix/approach** both match the
   spec. Watch the axis-confusion trap: if the title says "X outside Y", verify which `Y` actually
   exists in code before spec-hunting.
4. If the ticket describes a fix that contradicts the spec, the real bug is often a *different* one
   (e.g. a diagnostic / help-text bug, not the behavior the ticket asserts) — surface that.

### Part B — Decide the verdict (exactly one per ticket)

| Verdict | When | Action |
|---|---|---|
| **PROCEED** | Premise + approach match the spec; worth doing as written. | Continue to Step 3, route by type as normal. |
| **RESHAPE** | Worth doing, but not the way the ticket says (wrong approach, over-scoped, partially spec-blocked). | `br note <id>` the corrected scope/approach + spec citations, then `br edit <id>` (`--title` / `--desc` / `--append`) to reflect the reshaped work. Then proceed with the reshaped version. |
| **DEFER-TO-SPEC** | Needs a language-design decision (spec gap, or contradicts a normative rule only a panel can change). | `br note <id>` the finding + spec citations, re-tag `type:spec` (`br tag <id> type:spec` + `br untag <id> type:<old>`), tell the user to run `/deliberate`. Do NOT implement. |
| **DECLINE** | Not worth doing at all — obsolete, already fixed in git, spec-blessed as-is, or subsumed by other work. | `br note <id>` the reasoning **with evidence** (git commit, spec line, superseding ticket id), then `br cancel <id>`. Report it as a legitimate `/next` outcome. |
| **UNBLOCK-ONLY** | Really blocked — a soft-block stated in the body whose dependency was never wired. | Verify the blocker exists (`br show`), `br dep add <blocker> <blocked>` to silence it, drop it from this run, pick the next candidate. |

### Rules for the gate

- **Record the verdict on the ticket with `br note`** — not in a memory file. Include spec citations
  (`sections/NN_*.md:line`) as evidence. This is the same format existing triage notes use.
- **DECLINE and DEFER-TO-SPEC require user confirmation.** They change the backlog, so the user
  keeps the final call: surface the verdict + spec evidence and **wait for the user's OK** before
  running `br cancel` (DECLINE) or the re-tag to `type:spec` (DEFER).
- **PROCEED, RESHAPE, and UNBLOCK-ONLY act without a pause.** RESHAPE keeps the ticket open and
  merely corrects it via `br note` + `br edit`; UNBLOCK-ONLY just wires the dep and moves on.
- **Batch runs:** collect all DECLINE / DEFER verdicts and confirm them together in **one** prompt
  rather than blocking per-ticket — then proceed with the PROCEED / RESHAPE tickets.
- If a prior agent note already reached a DECLINE / DEFER / RESHAPE verdict and the user hasn't
  overridden it, surface that verdict and confirm rather than re-doing the whole analysis.

## Step 3: Route by Type

### type:bug — Auto-start, parallelizable
(Step 2.5 triage must read PROCEED for this ticket — if it read RESHAPE, work the reshaped scope.
The failing test encodes the **spec's** expected behavior, not merely the ticket's asserted
behavior; they can differ, and the spec wins.)
For each bug:
1. `br start <id>`
2. Read the task description, find relevant source files
3. Write a failing test that reproduces the bug (test_*.bl)
4. Fix the bug
5. `task regen` then `task ci`
6. run `/code-review --fix`
7. `br close <id>`

When working multiple bugs: use parallel agents with worktrees. Each agent gets one bug.

### type:friction — Auto-start, parallelizable
For each friction item:
1. `br start <id>`
2. Analyze: root cause? What should be done?
3. Create follow-up tasks:
   - Bug → `br add "..." -t repo:blink -t type:bug`
   - Needs spec deliberation → `br add "..." -t repo:blink -t type:spec`
   - Tooling improvement → `br add "..." -t repo:blink -t type:feature`
4. `br close <id>` the friction task
5. Report what was created

### type:feature — Confirm first, parallelizable
(Step 2.5 triage applies here too — implement the PROCEED scope, or the reshaped scope if it read
RESHAPE, and build to what the spec says rather than the ticket's asserted approach.)
1. Present all selected features with brief proposed approaches
2. Wait for user approval of the batch
3. Each feature: plan → implement → `task regen` → `task ci` → `/code-review --fix` → `br close <id>`

When working multiple features: use parallel agents with worktrees. Each agent gets one feature.

### type:project — Confirm first, single task
A `type:project` epic becomes a **first-class `br project`**, not a loose tag.

1. Present the task to the user and confirm the breakdown.
2. `br project add "<name>" -d "<desc>"` — derive a short kebab-case `<name>` from the epic
   title. Capture the project **id** it returns.
3. `br add` each subtask with `-t repo:blink -t type:* --project <id>`.
4. Wire dependencies: `br dep add <blocker> <blocked>`.
5. Set priorities on the subtasks.
6. Keep the original `type:project` task as the tracker, **or** close it if the project fully
   represents it (`br close <id>`) — operator's call.
7. Report the breakdown and tell the user they can now run `/next <project-name>` to drain it.

**Do not** use the legacy `project:X` *tag* for new work — assign tasks to the project with
`--project <id>` instead.

### type:spec — Defer to /deliberate
1. Tell user to run `/deliberate` for this item
2. Only work it directly if nothing else is available

### type:chore - Auto-start, parallelizable
(Step 2.5 triage must read PROCEED — a chore that turns out spec-blessed-as-is or subsumed by other
work is a DECLINE, not a grind. Work the reshaped scope if it read RESHAPE.)
You can do chores and bugs at the same time.
For each chore item:
1. `br start <id>`
2. Read the task, find relevant info
3. Do the task
4. `/code-review --fix`
5. `br close <id>`

## Step 4: Ship it

After completing tasks:
- Summarize what changed per task
- run `/shipit`
