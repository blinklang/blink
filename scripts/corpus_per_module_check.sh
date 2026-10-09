#!/bin/bash
# The gate for the per-module corpus mode (CORPUS_PER_MODULE=1 scripts/corpus.sh):
# every tests/test_*.bl must pass in build/corpus_per_module.json and must have
# built in units, except the files named in
# scripts/corpus_per_module_known_failures.txt, which must still fail.
#
# The list is how this mode holds a known per-module bug without changing a
# test: a test.failing row would change the test for both modes. A file on the
# list that passes fails the gate, so the fix that makes it pass also takes it
# off the list, the same rule test.failing keeps. A line must name a test file
# that exists, or the list could hide a file it no longer names.
#
# A passing file that did not build in units fell back to one unit, so it
# tested nothing in this mode, and fails the gate.
#
#   scripts/corpus_per_module_check.sh [--slice <list file>]
#
# --slice judges the per-module slice that `corpus.sh --per-module-slice`
# runs inside the default corpus, by the same rules, over the files the list
# names in place of every test on disk. The list must name at least one file,
# and every file it names must exist: a slice that lost its files would pass
# by testing nothing.
#
# Env:
#   CORPUS_JSON        result file (default build/corpus_per_module.json, or
#                      build/corpus_per_module_slice.json under --slice)
#   CORPUS_PM_KNOWN    known-failure list (default
#                      scripts/corpus_per_module_known_failures.txt)
set -u
cd "$(dirname "$0")/.." || exit 2

slice=""
while [ $# -gt 0 ]; do
    case "$1" in
        --slice) slice="$2"; shift 2 ;;
        *) echo "corpus-per-module-check: unknown argument $1" >&2; exit 2 ;;
    esac
done

if [ -n "$slice" ]; then
    json="${CORPUS_JSON:-build/corpus_per_module_slice.json}"
    run_hint="task corpus"
else
    json="${CORPUS_JSON:-build/corpus_per_module.json}"
    run_hint="task corpus-per-module"
fi
known_file="${CORPUS_PM_KNOWN:-scripts/corpus_per_module_known_failures.txt}"

if [ -n "$slice" ]; then
    if [ ! -f "$slice" ]; then
        echo "corpus-per-module-check: FAIL no slice list $slice"
        exit 1
    fi
    listed=$(grep -vE '^[[:space:]]*(#|$)' "$slice" | sort -u)
    if [ -z "$listed" ]; then
        echo "corpus-per-module-check: FAIL $slice names no test file"
        exit 1
    fi
    absent=""
    for f in $listed; do
        [ -f "$f" ] || absent="$absent  $f\n"
    done
    if [ -n "$absent" ]; then
        echo "corpus-per-module-check: FAIL $slice names files that do not exist:"
        printf "$absent"
        exit 1
    fi
fi

if [ ! -f "$json" ]; then
    echo "corpus-per-module-check: no $json; run '$run_hint' first" >&2
    exit 2
fi
if ! jq -e '(.total|type=="number") and (.passed|type=="number") and (.files|type=="array")' "$json" >/dev/null 2>&1; then
    echo "corpus-per-module-check: $json is malformed; run '$run_hint' again" >&2
    exit 2
fi
# A run of the default mode under this name would pass every row through one unit.
if [ "$(jq -r .per_module "$json")" != true ]; then
    echo "corpus-per-module-check: $json is not from a per-module run (CORPUS_PER_MODULE=1)" >&2
    exit 2
fi
if [ ! -f "$known_file" ]; then
    echo "corpus-per-module-check: no $known_file" >&2
    exit 2
fi

fail=0
known=$(grep -vE '^[[:space:]]*(#|$)' "$known_file" | sort -u)

missing=""
for f in $known; do
    [ -f "$f" ] || missing="$missing  $f\n"
done
if [ -n "$missing" ]; then
    echo "corpus-per-module-check: FAIL $known_file names files that do not exist:"
    printf "$missing"
    fail=1
fi

total=$(jq -r .total "$json")
if [ -n "$slice" ]; then
    unrun=$(printf '%s\n' "$listed" | jq -R . | jq -s . \
        | jq -r --slurpfile r "$json" '. - [$r[0].files[].file] | .[] | "  \(.)"')
    if [ -n "$unrun" ] || [ "$total" -ne "$(printf '%s\n' "$listed" | wc -l | tr -d ' ')" ]; then
        echo "corpus-per-module-check: FAIL the run covers $total file(s), not the files $slice names; missing:"
        [ -n "$unrun" ] && printf '%s\n' "$unrun"
        fail=1
    fi
else
    on_disk=$(find tests -maxdepth 1 -name 'test_*.bl' | wc -l | tr -d ' ')
    if [ "$total" -eq 0 ] || [ "$total" -ne "$on_disk" ]; then
        echo "corpus-per-module-check: FAIL the run covers $total file(s); tests/ holds $on_disk test_*.bl file(s)"
        fail=1
    fi
fi

known_json=$(printf '%s\n' "$known" | jq -R . | jq -s 'map(select(. != ""))')

failing=$(jq -r --argjson k "$known_json" '.files[] | select(.status != "pass" and (.file | IN($k[]) | not)) | "  \(.file): \(.status): \(.first_error_line)"' "$json")
if [ -n "$failing" ]; then
    echo "corpus-per-module-check: FAIL files that do not pass:"
    printf '%s\n' "$failing"
    fail=1
fi

fixed=$(jq -r --argjson k "$known_json" '.files[] | select(.status == "pass" and (.file | IN($k[]))) | "  \(.file)"' "$json")
if [ -n "$fixed" ]; then
    echo "corpus-per-module-check: FAIL known failures that now pass; take them off $known_file:"
    printf '%s\n' "$fixed"
    fail=1
fi

one_unit=$(jq -r '.files[] | select(.status == "pass" and .per_module != true) | "  \(.file)"' "$json")
if [ -n "$one_unit" ]; then
    echo "corpus-per-module-check: FAIL passing files that built one C unit, not units:"
    printf '%s\n' "$one_unit"
    fail=1
fi

unreadable=$(jq -r '.files[] | select(.status == "pass" and (.known_failures | type) != "number") | "  \(.file)"' "$json")
if [ -n "$unreadable" ]; then
    echo "corpus-per-module-check: FAIL passing files whose known-failure report did not read:"
    printf '%s\n' "$unreadable"
    fail=1
fi

n_known=$(printf '%s\n' "$known" | grep -c . || true)
if [ "$fail" -ne 0 ]; then
    exit 1
fi
echo "corpus-per-module-check: ok${slice:+ (slice $slice)} $(jq -r '"\(.passed)/\(.total)"' "$json") passed, $n_known known failure(s) still fail, $(jq -r .per_module_built "$json") built in units"
