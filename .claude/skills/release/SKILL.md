---
description: Release: Prepare and Ship a Pact Version
---

# Release: Prepare and Ship a Pact Version

Codify the full release process: version bump, docs update, CI, cross-compile, tag, GitHub release.

**Usage:** `/release` (auto-detects version bump) or `/release $ARGUMENTS` (force specific version like `0.7.0`)

---

## Step 1: Determine Changes

Run `git log $(git describe --tags --abbrev=0)..HEAD --oneline` to see all commits since the last release tag.

Classify each commit as: **breaking**, **feature**, or **fix/chore**.

Recommend a semver bump based on:
- Any breaking change → minor bump (pre-1.0) or major bump (post-1.0)
- New features → minor bump
- Only fixes/chores → patch bump

If `$ARGUMENTS` is provided, use that as the target version instead.

## Step 2: Confirm Version

Show the user:
- Current version (from `VERSION` file)
- Recommended version + rationale
- List of changes by category

Ask to confirm or override the version.

Warn if `VERSION` already matches the last tag (nothing to release).

## Step 3: Bump VERSION

Update the `VERSION` file to the confirmed version.

## Step 4: Update llms.md

In `llms.md`, update the "Recent Breaking Changes" or "Recent Changes" section:
- If breaking changes exist: rename section to "Recent Breaking Changes (vX.Y)"
- If no breaking changes: rename to "What's New (vX.Y)"
- List the notable changes (features, important fixes)

## Step 5: Update llms-full.md

In `llms-full.md`:
1. Update the version in the header line (`Compiler vX.Y`)
2. Update the "Recent Breaking/Changes" section (same as llms.md but with the migration table format)
3. **Scan the diff for new builtins**: check `src/codegen.pact` `reg_fn()` calls against the Builtin Functions table — add any missing
4. **Scan for new methods**: check `src/codegen_methods.pact` against method tables — add any missing
5. **Scan for new stdlib functions**: check `lib/std/*.pact` pub functions against docs — add any missing
6. **Check runtime.h**: look for new functions that should be documented

## Step 6: Review CLAUDE.md

Check if any new files were added that should appear in the [Docs Index]. Update if needed.

## Step 7: Commit Prep

Stage all changes and commit with: `Prepare vX.Y.Z release`

## Step 8: Push

`git push origin main`

## Step 9: Execute Release

Run `task release -- vX.Y.Z`

This will:
- Run full CI (`task ci`)
- Cross-compile binaries (`task build-binaries`)
- Create git tag
- Push tag
- Create GitHub release with binaries + llms-full.md

## Step 10: Verify

Run `gh release view vX.Y.Z` and show the user the release URL.

---

## Checklist

- [ ] VERSION bumped
- [ ] llms.md changes section updated
- [ ] llms-full.md changes section updated
- [ ] llms-full.md builtins table matches `src/codegen.pact` reg_fn() calls
- [ ] llms-full.md method tables match `src/codegen_methods.pact`
- [ ] llms-full.md stdlib docs match `lib/std/*.pact` pub functions
- [ ] CLAUDE.md [Docs Index] current
- [ ] `task ci` passes
- [ ] Release created on GitHub with binaries
