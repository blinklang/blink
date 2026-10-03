#!/bin/bash
# Select the rewrite-suite files, write them to build/rewrite_suite_list.txt,
# and print that path. rewrite_suite.sh runs the list; suites_in_corpus.sh
# checks it against the corpus results.
#
# The list is a glob over the prefixes below minus the paths named in
# scripts/rewrite_suite_exclude.txt, so a new test file joins the suite by
# existing and nobody can forget it. Every excluded path must exist and must
# match the glob, or this script stops: an exclusion that names no file hides
# a file instead of skipping it.
set -u
cd "$(dirname "$0")/.." || exit 2

exclude=scripts/rewrite_suite_exclude.txt

# A missing tool must say so: without comm the list comes out empty, which
# reads as "you excluded everything".
for tool in mktemp comm grep sort; do
    command -v "$tool" >/dev/null 2>&1 || { echo "rewrite-suite: missing tool: $tool" >&2; exit 2; }
done

mkdir -p build || exit 2
all=$(mktemp)
ex=$(mktemp)
list=build/rewrite_suite_list.txt
trap 'rm -f "$all" "$ex"' EXIT

# Unquoted on purpose: each word is a glob for `ls` to expand. A prefix that
# matches nothing stops the run, or a whole group of the suite could leave and
# the remaining groups would still report ok. The test runs before the list is
# built, because an exit inside a pipeline exits the pipeline and not this
# script.
patterns='tests/test_cg_*.bl tests/test_layout_*.bl tests/test_cname_*.bl tests/test_ir_*.bl tests/test_mono_*.bl tests/test_diagnostics_*.bl tests/test_unparse_*.bl tests/test_ast_*.bl'
for pat in $patterns; do
    if ! compgen -G "$pat" >/dev/null; then
        echo "rewrite-suite: ERROR no file matches $pat" >&2
        exit 2
    fi
done
# shellcheck disable=SC2086
ls $patterns | LC_ALL=C sort -u > "$all"

if [ ! -f "$exclude" ]; then
    echo "rewrite-suite: ERROR missing $exclude" >&2
    exit 2
fi
grep -vE '^[[:space:]]*(#|$)' "$exclude" | LC_ALL=C sort -u > "$ex"
while IFS= read -r f; do
    [ -n "$f" ] || continue
    if [ ! -f "$f" ]; then
        echo "rewrite-suite: ERROR $exclude names $f, which does not exist" >&2
        exit 2
    fi
    if ! grep -qxF "$f" "$all"; then
        echo "rewrite-suite: ERROR $exclude names $f, which the glob does not select" >&2
        exit 2
    fi
done < "$ex"

LC_ALL=C comm -23 "$all" "$ex" > "$list"
if [ ! -s "$list" ]; then
    echo "rewrite-suite: ERROR every file is excluded" >&2
    exit 2
fi

echo "$list"
