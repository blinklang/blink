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
# scripts/rewrite_suite_list.sh selects the files.
set -u
cd "$(dirname "$0")/.." || exit 2

comp="${REWRITE_SUITE_COMPILER:-build/gen0}"
out="${REWRITE_SUITE_OUT:-build/rewrite_suite.json}"

# corpus.sh and rewrite_suite_list.sh check their own tools. These are the ones
# this script adds.
for tool in jq grep wc cp; do
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

# The selection lives in its own script so `task ci` can check the same files in
# the corpus results without running them here.
list=$(./scripts/rewrite_suite_list.sh) || exit 2

# set -e, or a corpus.sh that exits without writing the JSON leaves passed and
# total empty, `[ "" != "" ]` is false, and the gate reports ok on a run that
# never happened.
set -e
# CORPUS_PRELUDE_LIB: a sandbox exposes the compiler's own lib/ as the prelude by
# default, and under gen0 that is a PINNED stdlib. These probes compile programs in
# process through THIS tree's compiler sources, so they must read this tree's stdlib;
# otherwise a stdlib change here is invisible to all of them and a diagnostic this
# tree adds fires against a stdlib this tree cannot fix.
# Exit 1 is a failing file, which the count below reports; only 2 stops here.
CORPUS_PRELUDE_LIB="$(pwd)/lib" CORPUS_COMPILER="$comp" CORPUS_OUT="$out" ./scripts/corpus.sh --only "$list" --no-lint || [ $? -eq 1 ]
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
