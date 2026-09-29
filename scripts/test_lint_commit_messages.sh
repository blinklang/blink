#!/bin/bash
# Proves scripts/lint_commit_messages.sh catches a br id in a branch commit
# and in a merge message on main, lets a word that only looks like an id
# through, and still catches the br-free forms when br is missing. Runs an
# unmodified copy of the script in a throwaway git repo with a fixed id list,
# so it never reads the real br database.
set -u
cd "$(dirname "$0")/.."

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
fail=0

R="$WORK/repo"
mkdir -p "$R/scripts"
cp scripts/lint_commit_messages.sh "$R/scripts/"
printf 'abc123\nactjah\n' > "$WORK/ids.txt"

lint() {
    (cd "$R" && COMMIT_MSG_IDS="$WORK/ids.txt" ./scripts/lint_commit_messages.sh) > "$WORK/out.log" 2>&1
}

expect() {
    name="$1"; want="$2"; got="$3"; pattern="${4:-}"
    if [ "$got" -ne "$want" ]; then
        echo "FAIL $name: want exit $want, got $got"
        sed 's/^/    /' "$WORK/out.log"
        fail=1
    elif [ -n "$pattern" ] && ! grep -qE -- "$pattern" "$WORK/out.log"; then
        echo "FAIL $name: exit $got, but the output lacks /$pattern/"
        sed 's/^/    /' "$WORK/out.log"
        fail=1
    else
        echo "PASS $name"
    fi
}

commit() { : > "$R/f_$RANDOM$RANDOM"; (cd "$R" && git add -A && git commit -qm "$1"); }

(
    cd "$R" || exit 1
    git init -q -b main .
    git config user.email t@example.com
    git config user.name t
)
commit "Base commit that names abc123 before the check existed"

(cd "$R" && git checkout -q -b clean)
commit "Count inner1 and child2 slots the same way"
lint
expect "branch-clean" 0 $? 'ok \(main\.\.HEAD\)'

(cd "$R" && git checkout -q -b bare_id main)
commit "Fix the carrier spelling"
commit "Reject the bare form

The ticket actjah asked for it."
lint
expect "branch-bare-id" 1 $? 'Reject the bare form: actjah'

(cd "$R" && git checkout -q -b digit_id main)
commit "Close the gap (abc123)"
lint
expect "branch-id-in-parens" 1 $? 'Close the gap \(abc123\): abc123'

# On main the branch range is empty; the merge and what it brought are checked.
(cd "$R" && git checkout -q main && git merge -q --no-ff clean -m "Merge rewrite/clean (abc123)")
lint
expect "main-merge-message" 1 $? 'Merge rewrite/clean \(abc123\): abc123'

(cd "$R" && git reset -q --hard HEAD^ && git merge -q --no-ff clean -m "Merge rewrite/clean")
lint
expect "main-merge-clean" 0 $? 'ok \(HEAD\^\.\.HEAD\)'

# Without br the id list is empty: a bare id passes, the br-free form fails.
(cd "$R" && git checkout -q -b no_br main)
commit "Follow up on br zz9zz9"
(cd "$R" && COMMIT_MSG_BR=no-such-br-command ./scripts/lint_commit_messages.sh) > "$WORK/out.log" 2>&1
expect "no-br-context-form" 1 $? 'br zz9zz9'
if ! grep -q 'is not on PATH' "$WORK/out.log"; then
    echo "FAIL no-br-says-so: the run did not say the id check was skipped"
    fail=1
else
    echo "PASS no-br-says-so"
fi

if [ "$fail" -ne 0 ]; then
    echo "test_lint_commit_messages: FAILED"
    exit 1
fi
echo "test_lint_commit_messages: all checks passed"
