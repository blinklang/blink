# GitHub Next: Pick and Plan Issues

Fetch the next highest-priority open issues from GitHub and start working on them.

**Usage:** `/gh-next` (auto-picks top 5) or `/gh-next $ARGUMENTS` (filter by label/keyword)

---

## Step 1: Fetch Candidates

Run `gh issue list` on `nhumrich/pact` to find open, unassigned issues. Sort by priority labels: P0-critical > P1-important > P2-nice-to-have.

If `$ARGUMENTS` is provided, use it as a label or keyword filter (e.g. `/gh-next codegen` filters to the `codegen` label, `/gh-next "HTTP"` searches titles).

```
gh issue list --repo nhumrich/pact --state open --assignee "" --label P0-critical --json number,title,labels,body --limit 10
gh issue list --repo nhumrich/pact --state open --assignee "" --label P1-important --json number,title,labels,body --limit 10
gh issue list --repo nhumrich/pact --state open --assignee "" --label P2-nice-to-have --json number,title,labels,body --limit 10
```

## Step 2: Filter Blocked Issues

Read the body of each candidate. If the body contains "**Blocked by:** #N" where #N is still open, exclude it from the list. Check with:
```
gh issue view N --repo nhumrich/pact --json state -q .state
```

## Step 3: Present Top 5

Show the user the top 5 unblocked issues (priority order), formatted as:

```
#N [P0-critical] Title
   Labels: codegen, spec-gap
   Summary: (first 1-2 sentences of body)
```

Ask the user which issue(s) to work on (they can pick 1 or more).

## Step 4: Claim Issues

For each selected issue:
1. Assign it to the current user: `gh issue edit N --add-assignee @me`
2. Add an "in progress" comment: `gh issue comment N --body "Starting work on this."`

## Step 5: Gather Context

For each selected issue, read its full body to understand:
- Which files are affected
- What the expected behavior is
- Any dependencies or cross-references

Then read the referenced source files in parallel to understand current state.

Also read `FRICTION.md` for any related friction entries that provide extra context.

## Step 6: Enter Plan Mode

Enter plan mode. Design the implementation approach for the selected issue(s):
- Identify all files that need changes
- Outline the approach step by step
- Note any spec gaps or ambiguities to log in FRICTION.md
- Consider test strategy (what test_*.pact files to add/modify)

Present the plan for user approval before implementing.

## Step 7: Implement

After plan approval, implement the changes. Follow the project conventions:
- `task regen` after compiler source changes
- `task ci` to verify everything passes
- Log any friction in `FRICTION.md`
- Create bd issues for any new work discovered during implementation

## Step 8: Close Issues

After implementation is verified:
1. Close the GitHub issue(s): `gh issue close N --repo nhumrich/pact --comment "Fixed in [commit/description]."`
2. Report what changed and suggest running `/gh-next` again for the next batch.
