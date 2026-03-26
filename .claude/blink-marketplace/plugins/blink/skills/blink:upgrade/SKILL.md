---
name: blink:upgrade
description: Guided migration assistant for upgrading Blink projects to a new version
---

# Blink Upgrade Guide

Guided migration assistant for upgrading Blink projects to a new version.

## Instructions

Follow these steps in order. Do not skip steps.

### Step 1: Determine Version Range

Find the **current** project version and the **target** version:

- **Target version**: Run `blink --version` to get the installed Blink version.
- **Current version**: Check `blink.toml` for a `blink-version` field. If no toml exists, ask the user what version they are upgrading from.

If both versions are the same, tell the user they are already up to date and stop.

### Step 2: Get Breaking Changes

Run these commands to retrieve changes between the current and target versions:

```bash
blink llms --topic "new"
blink llms --topic "breaking"
```

Read the output carefully. Identify each breaking change and note:
- The **before** pattern (old syntax/behavior)
- The **after** pattern (new syntax/behavior)
- Which versions introduced the change

Filter to only changes between the current and target versions.

If there are no breaking changes, tell the user their code should be compatible and stop.

### Step 3: Scan Project

For each breaking change identified in Step 2:

1. Use `Glob **/*.bl` to find all Blink source files (also check `**/*.pact` for legacy files).
2. Use `Grep` to search for the "before" pattern from each breaking change.
3. Record every match with file path and line number.

### Step 4: Present Checklist

Present a checklist grouped by breaking change:

```
## Upgrade from vX.Y.Z → vA.B.C

### [Change title]
[Brief description of what changed and why]

- [ ] `src/foo.bl:42` — [matched pattern context]
- [ ] `src/bar.bl:17` — [matched pattern context]

### [Next change title]
- [x] No affected files found — already clean
```

Show already-clean items as checked. Ask the user if they want to proceed with fixes.

### Step 5: Apply Fixes

For each group of changes:

1. Show the affected code with surrounding context.
2. Show the proposed replacement.
3. Wait for user confirmation before editing.
4. Apply the fix using the Edit tool.
5. Move to the next group.

Do NOT batch all changes at once. Go one category at a time.

### Step 6: Verify

After all fixes are applied:

1. Run `blink check <file>` on each modified file to verify it compiles.
2. If a `blink.toml` exists with test configuration, run `blink test`.
3. Report results. If any checks fail, help the user fix the remaining issues.

Run `blink update` to update the `blink-version` field in `blink.toml` and re-resolve dependencies.
