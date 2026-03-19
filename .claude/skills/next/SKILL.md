---
description: Next: Pick and Work Pact Tasks
---

# Next: Pick and Work Pact Tasks

Pick ready tasks from Bridge and execute the appropriate workflow based on type.

**Usage:** `/next` (auto-picks) or `/next $ARGUMENTS` (match by keyword)

---

## Step 1: Fetch Ready Tasks

Run `br ready -t repo:pact --json` to get all unblocked tasks.

If no tasks are ready, run `br blocked -t repo:pact --json`, report what's stuck, and ask the user how to proceed.

## Step 2: Select Tasks

Separate ready tasks by type tag. Priority order within each type: P0 > P1 > P2 > P3 > P4.

If `$ARGUMENTS` is provided, filter tasks whose title matches the argument (case-insensitive substring).

**Selection logic — auto-start types first:**

1. If any `type:bug` or `type:friction` tasks exist → pick up to 5 (priority-ordered, bugs before friction at same priority). These are auto-start — no confirmation needed.
2. If NO bugs/friction exist → pick up to 5 `type:feature` tasks (priority-ordered). These require confirmation.
3. If NO features either → pick 1 `type:project` task (highest priority). Requires confirmation.
4. `type:spec` tasks → tell the user to run `/deliberate`. Only work a spec task if literally nothing else is available.

## Step 3: Route by Type

### type:bug — Auto-start, parallelizable
For each bug:
1. `br start <id>`
2. Read the task description, find relevant source files
3. Write a failing test that reproduces the bug (test_*.pact)
4. Fix the bug
5. `task regen` then `task ci`
6. run `/simplify`
6. `br close <id>`

When working multiple bugs: use parallel agents with worktrees. Each agent gets one bug.

### type:friction — Auto-start, parallelizable
For each friction item:
1. `br start <id>`
2. Analyze: root cause? What should be done?
3. Create follow-up tasks:
   - Bug → `br add "..." -t repo:pact -t type:bug`
   - Needs spec deliberation → `br add "..." -t repo:pact -t type:spec`
   - Tooling improvement → `br add "..." -t repo:pact -t type:feature`
4. `br close <id>` the friction task
5. Report what was created

### type:feature — Confirm first, parallelizable
1. Present all selected features with brief proposed approaches
2. Wait for user approval of the batch
3. Each feature: plan → implement → `task regen` → `task ci` → `/simplify` → `task regen` → `task ci` → `br close <id>`

When working multiple features: use parallel agents with worktrees. Each agent gets one feature.

### type:project — Confirm first, single task
1. Present the task to the user
2. Break it down into subtasks with type tags
3. `br add` each subtask with `-t repo:pact -t type:*`
4. Add dependencies: `br dep add <blocker> <blocked>`
5. Set priorities
6. Report breakdown
7. `br close <id>` or keep as tracker

### type:spec — Defer to /deliberate
1. Tell user to run `/deliberate` for this item
2. Only work it directly if nothing else is available

## Step 4: Ship it

After completing tasks:
- Summarize what changed per task
- run `/shipit`
