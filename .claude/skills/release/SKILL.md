---
description: Release: Prepare and Ship a Blink Version
---

# Release: Prepare and Ship a Blink Version

Codify the full release process: version bump, docs update, CI, cross-compile, tag, GitHub release.

**Usage:** `/release` (auto-detects version bump) or `/release $ARGUMENTS` (force specific version like `0.7.0`)

---

## Step 1: Classify commits

Run `git log $(git describe --tags --abbrev=0)..HEAD --oneline` to list commits since the last tag.

**Read each commit body** with `git show --format=%B --no-patch <sha>` before classifying. Do not classify from subject alone — internal refactors routinely have user-sounding subjects. Past examples:

- "Resolve arena allocation semantics" — was spec-only, no user-visible change
- "Fix with-block leak" — was a `__blink_ev` codegen detail, invisible to users
- "Remove dead `__blink_ue_*` globals" — internal symbol cleanup

Classify each commit as **breaking**, **feature**, **fix**, or **chore** — then apply the filter in Step 1b.

## Step 1b: Filter for user-facing changes

Apply this filter before drafting notes. A commit is **internal** (drop from notes) if any of these apply:

- **Codegen plumbing.** Changes only in `src/codegen*.bl` that don't add builtins/methods or alter emitted user-observable behavior. Telltales: "Replace parallel arrays with struct pools", "Remove dead `__blink_*` globals", "Erase `tp_get_kind`", "Switch X dispatch from globals to evidence parameter".
- **Compiler-internal symbols.** Anything mentioning `__blink_ctx`, `__blink_ev`, `__blink_ue_*`, `tp_get_kind`, parallel arrays, struct pools, evidence passing, vtable plumbing. These names never appear in user code.
- **Spec / decisions only.** Commit body says "task ci is a no-op" or only touches `sections/`, `decisions/`, `OPEN_QUESTIONS.md`, `DECISIONS.md`.
- **Compiler-internal tooling.** ICE infra, fuzzer harness, negative test scaffolding, test-only helpers. Mention only if user-visible diagnostics changed.
- **External tooling adjacent to compiler.** GitHub Linguist entries, TextMate grammar, editor integrations — these don't ship with the binary and don't affect language behavior. Drop entirely.
- **Compiler perf.** Hash-map indexes, `#embed` lookup tables, scope cleanup. Aggregate into a single "Perf" line *only* if collectively significant; otherwise drop.
- **Stale comments / dead-code cleanup.** Drop.

A commit is **user-facing** (keep) if it:

- Adds/removes/changes a language construct, builtin, method, annotation, CLI flag, env var, or stdlib function the user can call.
- Changes a diagnostic the user will see (new error code, error becoming a warning or vice versa).
- Changes runtime behavior the user can observe in their program output, performance, or memory footprint without instrumenting the compiler.
- Fixes a bug whose symptom the user could reproduce in their own code (e.g. `Map.get_opt` losing inner type → real type errors in user code).

**When in doubt, ask:** *"Could a user write a program that behaves differently because of this commit?"* If no, drop it.

## Step 1c: Reframe before writing

For each kept commit, restate the change in terms of what the user does or sees, not what the compiler does internally.

- "Switch effect dispatch from globals to evidence parameter" → drop (internal codegen)
- "Fix with-block `__blink_ev` leak" → drop (internal symbol)
- "Add `NO_COLOR` env var support" → "`std.term` honors `NO_COLOR` per no-color.org" (names the user-visible surface, not the env var parser)

The output of Step 1c is the changelog content.

## Step 2: Recommend a version bump

Based on the filtered commits:

- Any breaking change → minor bump (pre-1.0) or major bump (post-1.0)
- New features → minor bump
- Only fixes/chores → patch bump

If `$ARGUMENTS` is provided, use that as the target version instead.

## Step 3: Confirm Version

Show the user:
- Current version (from `VERSION` file)
- Recommended version + rationale
- List of **user-facing** changes by category (i.e. the output of Step 1c)

Ask to confirm or override the version.

Warn if `VERSION` already matches the last tag (nothing to release).

## Step 4: Bump VERSION

Update the `VERSION` file to the confirmed version.

## Step 5: Update CHANGELOG.md

Prepend a new section to `CHANGELOG.md` (at repo root). Format matches prior entries — `## Breaking Changes (vX.Y.Z)` or `## What's New (vX.Y.Z)` with bullet-list body from Step 1c.

`CHANGELOG.md` is the single source of truth for release history. Both `blink llms` and `blink llms --full` append it automatically; `llms.md` and `llms-full.md` hold only a `## Recent Changes` stub pointing here. **Do not edit the stub in `llms.md` / `llms-full.md`.**

Also bump the version in the header of `llms-full.md` (line 3, `**Compiler vX.Y.Z**`).

Also bump the Docker tag list in `llms.md` and `llms-full.md` (the `Tags: \`latest\`, \`X.Y\`, \`X.Y.Z\`` line in the Install section).

## Step 6: Refresh the full reference

In `llms-full.md`:
1. **Scan the diff for new builtins** — check `src/codegen.bl` `reg_fn()` calls against the Builtin Functions table; add any missing.
2. **Scan for new methods** — check `src/codegen_methods.bl` against method tables; add any missing.
3. **Scan for new stdlib functions** — check `lib/std/*.bl` pub functions against docs; add any missing.
4. **Check runtime.h** — look for new functions that should be documented.

## Step 7: Review CLAUDE.md

Check if any new files were added that should appear in the [Docs Index]. Update if needed.

## Step 8: Commit Prep

Stage all changes and commit with: `Prepare vX.Y.Z release`

## Step 9: Push

`git push origin main`

## Step 10: Execute Release

Run `task release -- vX.Y.Z`

This will:
- Run full CI (`task ci-release`)
- Cross-compile binaries (`task build-binaries`)
- Create git tag
- Push tag
- Create GitHub release with binaries + llms-full.md

## Step 11: Verify

Run `gh release view vX.Y.Z` and show the user the release URL.

---

## Checklist

- [ ] VERSION bumped
- [ ] `CHANGELOG.md` updated with new release section
- [ ] `llms-full.md` header `**Compiler vX.Y.Z**` bumped
- [ ] Docker tag list bumped in `llms.md` and `llms-full.md`
- [ ] `llms-full.md` builtins table matches `src/codegen.bl` reg_fn() calls
- [ ] `llms-full.md` method tables match `src/codegen_methods.bl`
- [ ] `llms-full.md` stdlib docs match `lib/std/*.bl` pub functions
- [ ] CLAUDE.md [Docs Index] current
- [ ] `task ci-release` passes
- [ ] Release created on GitHub with binaries

### Anti-pattern check (reject the draft if any hit)

- [ ] No commit referencing `__blink_*` symbols in notes
- [ ] No "parallel arrays", "struct pools", "tp_get_kind", "evidence passing" in notes
- [ ] No external tooling (Linguist, TextMate, editor plugins) in notes
- [ ] Each line answers "what does the user do/see differently?"
