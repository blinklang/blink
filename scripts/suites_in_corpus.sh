#!/bin/bash
# Require that every typecheck-suite and rewrite-suite file passed in the
# whole-tree corpus run, in place of running the suites again under gen0.
#
#   scripts/suites_in_corpus.sh
#
# Env:
#   CORPUS_OUT  corpus JSON to read (default build/corpus.json)
#
# The corpus compiles and runs every tests/test_*.bl under gen1, whose lib/ is
# this checkout's lib/, so each suite file already ran there against this
# tree's stdlib. That holds only for a corpus of THIS tree under gen1: the
# compiler, the blinkc hash and the commit in the JSON must all match, or the
# check reads results that no longer describe the code.
set -u
cd "$(dirname "$0")/.." || exit 2

json="${CORPUS_OUT:-build/corpus.json}"
comp=build/gen1

for tool in jq sha256sum awk grep git; do
    command -v "$tool" >/dev/null 2>&1 || { echo "suites-in-corpus: missing tool: $tool" >&2; exit 2; }
done

if [ ! -f "$json" ]; then
    echo "suites-in-corpus: ERROR no $json; run the corpus first" >&2
    exit 2
fi

want_sha=$(sha256sum "$(readlink -f "$comp/blinkc")" | cut -c1-16) || exit 2
want_head=$(git rev-parse --short HEAD) || exit 2
got_comp=$(jq -r .compiler "$json")
got_sha=$(jq -r .blinkc_sha256_prefix "$json")
got_head=$(jq -r .git_head "$json")
if [ "$got_comp" != "$comp" ] || [ "$got_sha" != "$want_sha" ] || [ "$got_head" != "$want_head" ]; then
    echo "suites-in-corpus: ERROR $json is stale: compiler $got_comp blinkc $got_sha head $got_head," >&2
    echo "suites-in-corpus:       want compiler $comp blinkc $want_sha head $want_head" >&2
    exit 2
fi

rewrite_list=$(./scripts/rewrite_suite_list.sh) || exit 2

# Prints "<ok> <total>" and one "MISSING|<status> <file>" line per miss.
check() {
    jq -r --rawfile want "$1" '
        ([.files[] | {key: .file, value: .status}] | from_entries) as $got
        | [$want | split("\n")[] | select(test("^[[:space:]]*(#|$)") | not)] | unique
        | map({file: ., status: ($got[.] // "MISSING")}) as $rows
        | "\([$rows[] | select(.status == "pass")] | length) \($rows | length)",
          ($rows[] | select(.status != "pass") | "\(.status) \(.file)")
    ' "$json"
}

fail=0
for suite in typecheck rewrite; do
    if [ "$suite" = typecheck ]; then list=scripts/typecheck_suite.txt; else list=$rewrite_list; fi
    out=$(check "$list") || exit 2
    counts=$(head -n1 <<< "$out")
    ok=${counts% *}
    total=${counts#* }
    if [ "$total" -eq 0 ]; then
        echo "suites-in-corpus: FAIL $suite suite selects no file"
        fail=1
    elif [ "$ok" != "$total" ]; then
        echo "suites-in-corpus: FAIL $suite $ok/$total"
        tail -n +2 <<< "$out" | sed 's/^/suites-in-corpus:   /'
        fail=1
    else
        echo "suites-in-corpus: $suite ok $ok/$total"
    fi
done
exit "$fail"
