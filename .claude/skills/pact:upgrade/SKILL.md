---
description: Guided migration assistant for upgrading Pact projects to a new version
---

# Pact Upgrade Guide

Guided migration assistant for upgrading Pact projects to a new version.

## Instructions

Follow these steps in order. Do not skip steps.

### Step 1: Determine Version Range

Find the **current** project version and the **target** version:

- **Target version**: Run `pact --version` to get the installed Pact version.
- **Current version**: Check `pact.toml` for a `pact-version` field under `[package]`. If not found, fall back to `pact.lock` for a `pact-version` field under `[metadata]`. If neither exists, ask the user what version they are upgrading from.

If both versions are the same, tell the user they are already up to date and stop.

### Step 2: Get Breaking Changes

Run these commands to retrieve changes between the current and target versions:

```bash
pact llms --topic "new"
pact llms --topic "breaking"
```

Read the output carefully. Identify each breaking change and note:
- The **before** pattern (old syntax/behavior)
- The **after** pattern (new syntax/behavior)
- Which versions introduced the change

Filter to only changes between the current and target versions.

If there are no breaking changes, tell the user their code should be compatible and stop.

### Step 3: Scan Project

For each breaking change identified in Step 2:

1. Use `Glob **/*.pact` to find all Pact source files in the project.
2. Use `Grep` to search for the "before" pattern from each breaking change.
3. Record every match with file path and line number.

### Step 4: Present Checklist

Present a checklist grouped by breaking change:

```
## Upgrade from vX.Y.Z → vA.B.C

### [Change title]
[Brief description of what changed and why]

- [ ] `src/foo.pact:42` — [matched pattern context]
- [ ] `src/bar.pact:17` — [matched pattern context]

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

1. Run `pact check <file>` on each modified file to verify it compiles.
2. If a `pact.toml` exists with test configuration, run `pact test`.
3. Report results. If any checks fail, help the user fix the remaining issues.

Finally, update the `pact-version` field in `pact.toml` under `[package]` to match the target version. If `pact.lock` also exists, update its `pact-version` field as well.
