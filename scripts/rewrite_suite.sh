#!/bin/bash
# Run every rewrite unit-test file under the pinned gen0 and require that all
# of them pass. These files test the rewrite layer (cg, layout, cname, ir) by
# RUNNING, so they need a compiler that can emit C. This tree cannot, which is
# why they run under gen0.
#
#   scripts/rewrite_suite.sh
#
# Env:
#   REWRITE_SUITE_COMPILER  dir holding blink/blinkc (default build/gen0)
#   REWRITE_SUITE_OUT       output JSON (default build/rewrite_suite.json)
#
# The file list is a glob over six prefixes minus the paths named in
# scripts/rewrite_suite_exclude.txt, so a new test file joins the suite by
# existing and nobody can forget it. Every excluded path must exist and must
# match the glob, or this script stops: an exclusion that names no file hides
# a file instead of skipping it.
set -u
cd "$(dirname "$0")/.." || exit 2

comp="${REWRITE_SUITE_COMPILER:-build/gen0}"
out="${REWRITE_SUITE_OUT:-build/rewrite_suite.json}"
exclude=scripts/rewrite_suite_exclude.txt

# corpus.sh checks its own tools. These are the ones this script adds, and a
# missing one must say so: without comm the list comes out empty, which reads
# as "you excluded everything".
for tool in mktemp comm jq grep sort wc cp; do
    command -v "$tool" >/dev/null 2>&1 || { echo "rewrite-suite: missing tool: $tool" >&2; exit 2; }
done

mkdir -p build || exit 2
# A run that stops early must not leave the last run's numbers behind for
# anything that reads the JSON instead of the exit code.
rm -f "$out"

# A test binary resolves the std.* prelude through <dir of argv[0]>/lib/std,
# then $BLINK_ROOT/lib/std, then an embedded registry that a test binary
# leaves empty. With no prelude the probe compiles nothing, reports nothing
# the probe reads, and its assertions hold over an empty program. So both
# prelude roots are checked and neither may be missing.
#
# The suite reads the compiler's own lib/, which corpus_one.sh links beside
# the blinkc in each sandbox. build/lib serves the same file run straight from
# the checkout root, which is how an operator repeats a failure. Copy, not a
# link: bootstrap.sh copies lib/std/*.bl into build/lib/std, and a link to
# lib/ would make that a copy onto itself. A build/lib that someone already
# pointed at lib/ needs no copy and gets none. Otherwise the copy repeats on
# every run and removes the old .bl files first, so a module deleted or
# renamed under lib/ does not stay resolvable here. Writing through a link is
# refused: the target can be another checkout, and the copy would edit a tree
# this run was never asked to touch.
if [ "$(readlink -f build/lib 2>/dev/null)" != "$(readlink -f lib)" ]; then
    for d in build/lib build/lib/std build/lib/pkg; do
        if [ -L "$d" ]; then
            echo "rewrite-suite: ERROR $d is a link to $(readlink -f "$d" 2>/dev/null)," >&2
            echo "rewrite-suite:       which is not this checkout's lib/; refusing to copy through it" >&2
            exit 2
        fi
    done
    mkdir -p build/lib/std build/lib/pkg || exit 2
    rm -f build/lib/std/*.bl build/lib/pkg/*.bl || exit 2
    cp lib/std/*.bl build/lib/std/ || exit 2
    cp lib/pkg/*.bl build/lib/pkg/ || exit 2
fi
for root in lib build/lib "$comp/lib"; do
    if ! ls "$root"/std/*.bl >/dev/null 2>&1; then
        echo "rewrite-suite: ERROR no prelude at $root/std; a probe would compile" >&2
        echo "rewrite-suite:       nothing and its assertions would hold over an empty program" >&2
        exit 2
    fi
done

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

# set -e, or a corpus.sh that exits without writing the JSON leaves passed and
# total empty, `[ "" != "" ]` is false, and the gate reports ok on a run that
# never happened.
set -e
# CORPUS_PRELUDE_LIB: a sandbox exposes the compiler's own lib/ as the prelude by
# default, and under gen0 that is a PINNED stdlib. These probes compile programs in
# process through THIS tree's compiler sources, so they must read this tree's stdlib;
# otherwise a stdlib change here is invisible to all of them and a diagnostic this
# tree adds fires against a stdlib this tree cannot fix.
CORPUS_PRELUDE_LIB="$(pwd)/lib" CORPUS_COMPILER="$comp" CORPUS_OUT="$out" ./scripts/corpus.sh --only "$list" --no-lint
passed=$(jq -r .passed "$out")
total=$(jq -r .total "$out")
selected=$(wc -l < "$list" | tr -d ' ')
if [ "$total" != "$selected" ]; then
    echo "rewrite-suite: FAIL ran $total of $selected selected files"
    exit 1
fi
if [ "$passed" != "$total" ]; then
    echo "rewrite-suite: FAIL $passed/$total"
    exit 1
fi
echo "rewrite-suite: ok $passed/$total"
