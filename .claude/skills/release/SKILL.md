---
description: Release: Prepare and Ship a Blink Version
---

# Release: Prepare and Ship a Blink Version

Codify the full release process: version bump, docs update, CI, cross-compile, tag, GitHub release.

**Usage:** `/release` (auto-detects version bump) or `/release $ARGUMENTS` (force specific version like `0.7.0`)

---

## Step 1: Classify commits

Run `git log --no-merges $(git describe --tags --abbrev=0 --match 'v*')..HEAD --oneline` to list commits since the last release tag. The `--match 'v*'` matters: the repo also carries `gen0-*` pin tags, and without it `describe` picks the newest pin, not the release.

A range of a few hundred commits is too big to read in this session. Hand the read to one subagent, read-only: it reads every body, writes a per-commit classification file (sha, kind, user-facing, reason) and a draft section, and checks each claim against the tree. Check its draft before you edit anything.

**Read each commit body** with `git show --format=%B --no-patch <sha>` before classifying. Do not classify from subject alone — internal refactors routinely have user-sounding subjects. Past examples:

- "Resolve arena allocation semantics" — was spec-only, no user-visible change
- "Fix with-block leak" — was a `__blink_ev` codegen detail, invisible to users
- "Remove dead `__blink_ue_*` globals" — internal symbol cleanup

Classify each commit as **breaking**, **feature**, **fix**, or **chore** — then apply the filter in Step 1b.

## Step 1b: Filter for user-facing changes

Apply this filter before drafting notes. A commit is **internal** (drop from notes) if any of these apply:

- **Codegen plumbing.** Changes only in the codegen layer (`src/cg*.bl`, `src/ir.bl`, `src/mono.bl`, `src/layout.bl`, `src/cname.bl`) that don't add builtins/methods or alter emitted user-observable behavior. A fix that makes a program build or run right where it failed cc or gave wrong output is user-facing: keep one line per class of fix, not one per commit. Telltales: "Replace parallel arrays with struct pools", "Remove dead `__blink_*` globals", "Erase `tp_get_kind`", "Switch X dispatch from globals to evidence parameter".
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

Prepend a new section to `CHANGELOG.md` (at repo root). Format matches prior entries — `## Breaking Changes (vX.Y.Z)` or `## What's New (vX.Y.Z)` with bullet-list body from Step 1c. If CHANGELOG.md has a `## Changes (unreleased)` section, fold its entries into the new section and remove that heading.

End every CHANGELOG heading for the release with `(vX.Y.Z)`. `task release` prints those sections as the GitHub release notes (`scripts/release_notes.sh`) and refuses to start when it finds none.

`CHANGELOG.md` is the single source of truth for release history. Both `blink llms` and `blink llms --full` append it automatically; `llms.md` and `llms-full.md` hold only a `## Recent Changes` stub pointing here. **Do not edit the stub in `llms.md` / `llms-full.md`.**

Also bump the version in the header of `llms-full.md` (line 3, `**Compiler vX.Y.Z**`).

Also bump the Docker tag list in `llms.md` and `llms-full.md` (the `Tags: \`latest\`, \`X.Y\`, \`X.Y.Z\`` line in the Install section).

## Step 6: Refresh the full reference

In `llms-full.md`, check what changed since the last release tag (`git diff v<last>..HEAD -- <path>`):
1. **Builtin functions** — `is_builtin_fn` and `get_builtin_fn_ret` in `src/typecheck.bl` against the Builtin Functions table.
2. **Builtin namespaces** — `is_builtin_namespace` in `src/typecheck.bl` against Namespace Methods.
3. **Methods** — `is_builtin_method` in `src/typecheck.bl`, and the sealed ops traits (`StrOps`, `BytesOps`, `StringBuildOps`) in `lib/std/traits.bl`, against the per-type method tables.
4. **Stdlib** — `pub fn` in `lib/std/*.bl` against the Standard Library section.
5. **CLI** — new flags and env vars (`src/cli.bl`, `build/gen1/bin/blink --help`) against Build & Run.
6. **Diagnostics** — new codes in `ERROR_CATALOG.md` that a user can hit.

Add what is missing. Remove what no longer exists. `src/codegen.bl` and `src/codegen_methods.bl` are gone since the codegen rewrite; do not look for `reg_fn`.

## Step 7: Review CLAUDE.md

Check that the Architecture and Build & Verify sections still name files and tasks that exist (`rg` each path and `task --list`). Update if needed.

## Step 8: Commit Prep

Stage all changes and commit with: `Prepare vX.Y.Z release`

## Step 8b: Scan for br IDs

br is local-only, so a ticket ID in pushed text means nothing to a reader. Before the push, collect every ID (`br list --all --json`) and `rg -wf` them against the commit messages, the added lines and the added file names in `origin/main..HEAD`. Fix new hits in docs and changelog text. Report hits in `decisions/` and in existing test names to the user; never rename tests.

## Step 9: Push

Ask the user before the push: it is public. Then `git push origin main`.

## Step 10: Execute Release

Run `task release -- vX.Y.Z`

This will:
- Run full CI (`task ci-release`; its regen step needs a seeded build/, see CLAUDE.md Bootstrap)
- Cross-compile binaries (`task build-binaries`)
- Create git tag
- Push tag
- Create GitHub release with binaries + llms-full.md; the notes come from the CHANGELOG.md sections for the version

Run `task ci-release` on HEAD early, while Step 1 runs, so a failure shows before the release commit.

## Step 11: Verify

Run `gh release view vX.Y.Z` and show the user the release URL.

---

## Checklist

- [ ] VERSION bumped
- [ ] `CHANGELOG.md` updated with new release section (the unreleased section folded in)
- [ ] `llms-full.md` header `**Compiler vX.Y.Z**` bumped
- [ ] Docker tag list bumped in `llms.md` and `llms-full.md`
- [ ] `llms-full.md` builtins, namespaces and method tables match `src/typecheck.bl` and `lib/std/traits.bl`
- [ ] `llms-full.md` stdlib docs match `lib/std/*.bl` pub functions
- [ ] New CLI flags, env vars and user diagnostics documented
- [ ] CLAUDE.md paths and tasks current
- [ ] No new br IDs in the pushed range
- [ ] `task ci-release` passes
- [ ] Release created on GitHub with binaries

### Anti-pattern check (reject the draft if any hit)

- [ ] No commit referencing `__blink_*` symbols in notes
- [ ] No "parallel arrays", "struct pools", "tp_get_kind", "evidence passing" in notes
- [ ] No external tooling (Linguist, TextMate, editor plugins) in notes
- [ ] Each line answers "what does the user do/see differently?"
