#!/bin/bash
# Fails when a commit message on this branch names a br ticket or project.
# br is local-only, so an id in history means nothing to another reader or to
# this repo as training data. The link lives in a br note instead.
#
# Range: COMMIT_MSG_BASE_REF..HEAD (default main). When that is empty, HEAD is
# on the base, as in the main gate after a merge, and the range is HEAD^..HEAD:
# the merge commit and every branch commit it brought. That is where a merge
# message is checked; on the branch it does not exist yet.
#
# Two checks:
#   - forms that need no br: `br <id>`, `ticket: <id>`, `#<id>`, the pattern of
#     lint_codegen.sh row L10;
#   - every standalone six-character token that is a br ticket or project id.
#     This needs the id list from br. Without br it says so and runs the first
#     check alone, because a shape test cannot tell an id from a word: one id in
#     nine has no digit.
#
# Env overrides (used by scripts/test_lint_commit_messages.sh):
#   COMMIT_MSG_BASE_REF  the ref the range starts from. Default: main
#   COMMIT_MSG_BR        the br command. Default: br
#   COMMIT_MSG_IDS       a file of ids, one per line, read in place of br
set -u
cd "$(dirname "$0")/.." || exit 2

base_ref="${COMMIT_MSG_BASE_REF:-main}"
br_cmd="${COMMIT_MSG_BR:-br}"

if ! git rev-parse --verify --quiet "${base_ref}^{commit}" >/dev/null 2>&1; then
    echo "lint_commit_messages: warning: '$base_ref' does not resolve; nothing to check" >&2
    exit 0
fi
range="${base_ref}..HEAD"
if [ -z "$(git rev-list "$range")" ]; then
    git rev-parse --verify --quiet 'HEAD^' >/dev/null 2>&1 || exit 0
    range='HEAD^..HEAD'
fi

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

ids="$work/ids.txt"
if [ -n "${COMMIT_MSG_IDS:-}" ]; then
    sort -u "$COMMIT_MSG_IDS" > "$ids"
elif command -v "$br_cmd" >/dev/null 2>&1; then
    {
        "$br_cmd" list --all 2>/dev/null | grep -oP '^\[.\]\s+\K[0-9a-z]{6}(?=\s)'
        "$br_cmd" project ls 2>/dev/null | grep -oP '^[0-9a-z]{6}(?=\s)'
    } | sort -u > "$ids"
    if [ ! -s "$ids" ]; then
        echo "lint_commit_messages: '$br_cmd' listed no ids; checking the br-free forms only" >&2
    fi
else
    : > "$ids"
    echo "lint_commit_messages: '$br_cmd' is not on PATH; checking the br-free forms only" >&2
fi

context='\bbr [0-9a-z]{6}\b|\b(ticket|bug|task|issue|fixes|closes)[: ]+#?(?=[0-9a-z]{6}\b)(?=[a-z]*[0-9])[0-9a-z]{6}\b|#(?=[0-9a-z]{6}\b)(?=[a-z]*[0-9])[0-9a-z]{6}\b'

fail=0
for c in $(git rev-list "$range"); do
    git log -1 --format='%B' "$c" > "$work/msg"
    hits=$(
        grep -oP -- "$context" "$work/msg"
        if [ -s "$ids" ]; then
            grep -oP '(?<![0-9A-Za-z_])[0-9a-z]{6}(?![0-9A-Za-z_])' "$work/msg" | grep -xFf "$ids"
        fi
    )
    if [ -n "$hits" ]; then
        echo "$(git log -1 --format='%h %s' "$c"): $(printf '%s\n' "$hits" | sort -u | tr '\n' ' ')"
        fail=1
    fi
done

if [ "$fail" -ne 0 ]; then
    echo "lint_commit_messages: FAIL. The commits above name a br id. Reword them, and keep the link in a br note."
    exit 1
fi
echo "lint_commit_messages: ok ($range)"
