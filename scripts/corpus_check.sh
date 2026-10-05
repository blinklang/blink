#!/bin/bash
# The gate for the corpus: every tests/test_*.bl must pass in build/corpus.json,
# and the run must cover every test file, so a partial run cannot pass.
#
# A passing file whose known-failure count did not read fails the gate, because
# null would hide any count. The count of test.failing rows that still fail is
# printed for information only: it changes when a test file changes, and a
# stale test.failing row that starts passing already fails its own file.
#
# The number of binaries that linked the prebuilt compiler archive must reach
# the floor in scripts/corpus_compiler_archive_floor.txt. Each file whose
# build falls back to one unit compiles the whole compiler again, so a drop is
# a slowdown no test result would show.
#
# Env:
#   CORPUS_JSON  result file (default build/corpus.json)
set -u
cd "$(dirname "$0")/.." || exit 2

json="${CORPUS_JSON:-build/corpus.json}"

if [ ! -f "$json" ]; then
    echo "corpus-check: no $json; run 'task corpus' first" >&2
    exit 2
fi

# Without this a truncated file reads as 0/0.
if ! jq -e '(.total|type=="number") and (.passed|type=="number") and (.files|type=="array")' "$json" >/dev/null 2>&1; then
    echo "corpus-check: $json is malformed; run 'task corpus' again" >&2
    exit 2
fi

fail=0

total=$(jq -r .total "$json")
on_disk=$(find tests -maxdepth 1 -name 'test_*.bl' | wc -l | tr -d ' ')
if [ "$total" -eq 0 ] || [ "$total" -ne "$on_disk" ]; then
    echo "corpus-check: FAIL the run covers $total file(s); tests/ holds $on_disk test_*.bl file(s)"
    fail=1
fi

failing=$(jq -r '.files[] | select(.status != "pass") | "  \(.file): \(.status)"' "$json")
if [ -n "$failing" ]; then
    echo "corpus-check: FAIL files that do not pass:"
    printf '%s\n' "$failing"
    fail=1
fi

unreadable=$(jq -r '.files[] | select(.status == "pass" and (.known_failures | type) != "number") | "  \(.file)"' "$json")
if [ -n "$unreadable" ]; then
    echo "corpus-check: FAIL passing files whose known-failure report did not read"
    echo "  (most often a test printed to stdout, which lands inside the --test-json report):"
    printf '%s\n' "$unreadable"
    fail=1
fi

floor_file=scripts/corpus_compiler_archive_floor.txt
floor=$(grep -v '^#' "$floor_file" 2>/dev/null | tr -d '[:space:]')
case "$floor" in
    ''|*[!0-9]*)
        echo "corpus-check: $floor_file does not hold a number" >&2
        exit 2 ;;
esac
# A record with no flag would read as "not linked" and hide in the count.
unflagged=$(jq -r '.files[] | select((.compiler_archive | type) != "boolean") | "  \(.file)"' "$json")
if [ -n "$unflagged" ]; then
    echo "corpus-check: FAIL files whose record does not say whether the compiler archive linked:"
    printf '%s\n' "$unflagged"
    fail=1
fi
linked=$(jq -r '[.files[] | select(.compiler_archive == true)] | length' "$json")
echo "corpus-check: compiler archive linked $linked file(s), floor $floor"
if [ "$linked" -lt "$floor" ]; then
    echo "corpus-check: FAIL compiler archive linked $linked file(s), below the floor of $floor"
    fail=1
fi

known=$(jq -r '[.files[] | select((.known_failures | type) == "number") | .known_failures] | add // 0' "$json")
echo "corpus-check: known failures (test.failing rows still failing): $known"

if [ "$fail" -ne 0 ]; then
    exit 1
fi
echo "corpus-check: ok $(jq -r '"\(.passed)/\(.total)"' "$json") passed"
