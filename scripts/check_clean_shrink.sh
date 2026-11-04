#!/bin/bash
# Fails the gate when scripts/check_clean_known_failures.txt grows. A count row would
# pass a swap of one entry for another, so this compares the paths themselves.
# It reads history, which an input stamp or task checksum does not hash, so it
# runs on every gate.
#
# Each commit in the range, then the working tree, may not add a path to the
# list, and may not drop a path whose program is gone: deleting a probe does
# not fix the fault. Once the list exists, deleting it and adding it again is
# red too; only the commit that first adds it is exempt.
#
# Range: CHECK_CLEAN_BASE_REF..HEAD (default main). When that is empty, HEAD is
# on the base, as in the main gate after a land. A land brings a stack with no
# merge commit, so the range is then @{upstream}..HEAD, each commit not pushed.
# With no such commit, or no upstream, it is HEAD^..HEAD.
#
# Exit 0 green, 1 red, 2 when it cannot name a range: a base ref that does not
# resolve must not read as a pass, and neither must a shallow clone, where a
# commit at the boundary shows no parent.
set -u
cd "$(dirname "$0")/.." || exit 2

list=scripts/check_clean_known_failures.txt
base_ref="${CHECK_CLEAN_BASE_REF:-main}"

if [ "$(git rev-parse --is-shallow-repository 2> /dev/null)" = true ]; then
    echo "check-clean-shrink: this is a shallow clone, so the check cannot read the parents of the range" >&2
    exit 2
fi
if ! git rev-parse --verify --quiet "${base_ref}^{commit}" > /dev/null 2>&1; then
    echo "check-clean-shrink: base ref '$base_ref' does not resolve, so the check cannot run (set CHECK_CLEAN_BASE_REF)" >&2
    exit 2
fi
range="${base_ref}..HEAD"
if [ -z "$(git rev-list "$range")" ]; then
    if [ -n "$(git rev-list '@{upstream}..HEAD' 2> /dev/null)" ]; then
        range='@{upstream}..HEAD'
    elif ! git rev-parse --verify --quiet 'HEAD^' > /dev/null 2>&1; then
        echo "check-clean-shrink: HEAD is '$base_ref' and has no parent, so the check cannot run" >&2
        exit 2
    else
        range='HEAD^..HEAD'
    fi
fi

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
fail=0

paths_in() {
    awk '!/^[[:space:]]*(#|$)/ { print $1 }' | LC_ALL=C sort -u
}

# compare <label> <old paths> <new paths> <test that a path still exists>
compare() {
    label="$1"
    for p in $(LC_ALL=C comm -13 "$2" "$3"); do
        echo "check-clean-shrink: RED $label adds $p; the list only shrinks. Fix the fault or file it; do not list it."
        fail=1
    done
    for p in $(LC_ALL=C comm -23 "$2" "$3"); do
        if ! "$4" "$p"; then
            echo "check-clean-shrink: RED $label drops $p and deletes its program; keep the probe."
            fail=1
        fi
    done
}

exists_in_commit() { git cat-file -e "$commit:$1" 2> /dev/null; }
exists_on_disk() { [ -f "$1" ]; }

# Only a commit that touches the list can change a verdict.
for commit in $(git rev-list --reverse --full-history "$range" -- "$list"); do
    label="commit $(git log -1 --format=%h "$commit")"
    parent=$(git rev-parse --verify --quiet "$commit^") || continue
    if ! git cat-file -e "$parent:$list" 2> /dev/null; then
        if [ -n "$(git log -1 --format=%h "$parent" -- "$list")" ]; then
            if git cat-file -e "$commit:$list" 2> /dev/null; then
                echo "check-clean-shrink: RED $label adds the list again after a commit deleted it"
                fail=1
            fi
        fi
        continue
    fi
    if ! git cat-file -e "$commit:$list" 2> /dev/null; then
        echo "check-clean-shrink: RED $label deletes the list"
        fail=1
        continue
    fi
    git show "$parent:$list" | paths_in > "$work/old"
    git show "$commit:$list" | paths_in > "$work/new"
    compare "$label" "$work/old" "$work/new" exists_in_commit
done

if git cat-file -e "HEAD:$list" 2> /dev/null; then
    if [ ! -f "$list" ]; then
        echo "check-clean-shrink: RED the working tree deletes the list"
        fail=1
    else
        git show "HEAD:$list" | paths_in > "$work/old"
        paths_in < "$list" > "$work/new"
        compare "the working tree" "$work/old" "$work/new" exists_on_disk
    fi
fi

if [ "$fail" -ne 0 ]; then
    echo "check-clean-shrink: FAIL ($range, then the working tree)"
    exit 1
fi
echo "check-clean-shrink: ok ($range, then the working tree)"
