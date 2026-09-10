#!/bin/bash
# The monotonicity gate for the corpus. Compares build/corpus.json against
# two references: the committed baseline scripts/corpus_baseline.json, and
# the baseline as it stood in the previous commit. The pass count may not
# drop against either, and no file may flip from pass to anything else.
#
#   scripts/corpus_check.sh            gate
#   scripts/corpus_check.sh --update   write the baseline from build/corpus.json
#
# The baseline lives under scripts/ because build/ is gitignored as a whole
# directory and git cannot re-include a file under an ignored directory.
#
# Previous-commit reference: HEAD when the tree has uncommitted changes
# under src/, tests/ or scripts/ (the script runs before the commit that
# would land them, so HEAD is the real parent), else HEAD~1. Override with
# CORPUS_HEAD1_REF. A ref with no baseline file skips that half.
#
# Env:
#   CORPUS_JSON       result file (default build/corpus.json)
#   CORPUS_BASELINE   baseline file (default scripts/corpus_baseline.json)
#   CORPUS_HEAD1_REF  git ref for the previous-commit baseline
set -u
cd "$(dirname "$0")/.." || exit 2

json="${CORPUS_JSON:-build/corpus.json}"
baseline="${CORPUS_BASELINE:-scripts/corpus_baseline.json}"

if [ ! -f "$json" ]; then
    echo "corpus-check: no $json; run 'task corpus' first" >&2
    exit 2
fi

# well_formed <json file>: the fields the gate reads exist and have the
# right types. Without this a truncated file compares as 0/0 and passes.
well_formed() {
    jq -e '(.total|type=="number") and (.passed|type=="number") and (.files|type=="array")' "$1" >/dev/null 2>&1
}
if ! well_formed "$json"; then
    echo "corpus-check: $json is malformed; run 'task corpus' again" >&2
    exit 2
fi

if [ "${1:-}" = "--update" ]; then
    # Only what the gate reads: the summary and each file's status. Timings
    # and error lines change run to run and would make every diff noisy.
    jq '{
          compiler, blinkc_sha256_prefix, git_head, generated_utc,
          total, passed,
          files: (.files | map({file, status}))
        }' "$json" > "$baseline"
    echo "corpus-check: baseline written: $(jq -r '"\(.passed)/\(.total)"' "$baseline") passed"
    exit 0
fi

if [ ! -f "$baseline" ]; then
    echo "corpus-check: no baseline at $baseline; run scripts/corpus_check.sh --update" >&2
    exit 1
fi

if [ -z "$(git status --porcelain -- src tests scripts 2>/dev/null)" ]; then
    default_ref=HEAD~1
else
    default_ref=HEAD
fi
head1_ref="${CORPUS_HEAD1_REF:-$default_ref}"

fail=0

# compare <label> <reference json file>
compare() {
    label="$1"
    ref="$2"
    if ! well_formed "$ref"; then
        echo "corpus-check: FAIL $label reference is malformed"
        fail=1
        return
    fi
    now_passed=$(jq -r .passed "$json")
    now_total=$(jq -r .total "$json")
    ref_passed=$(jq -r .passed "$ref")
    ref_total=$(jq -r .total "$ref")
    printf 'corpus-check: %-9s passed %s/%s, now %s/%s\n' "$label" "$ref_passed" "$ref_total" "$now_passed" "$now_total"
    if [ "$now_passed" -lt "$ref_passed" ]; then
        echo "corpus-check: FAIL pass count dropped against $label ($ref_passed -> $now_passed)"
        fail=1
    fi
    # A file that passed in the reference must still pass, and must still
    # exist: a test that vanished from the corpus is a regression too.
    flips=$(jq -r --slurpfile now "$json" '
        ($now[0].files | map({key: .file, value: .status}) | from_entries) as $cur
        | .files[]
        | select(.status == "pass")
        | . as $f
        | ($cur[$f.file] // "missing") as $s
        | select($s != "pass")
        | "  \($f.file): pass -> \($s)"' "$ref")
    if [ -n "$flips" ]; then
        echo "corpus-check: FAIL files that passed in $label and no longer do:"
        printf '%s\n' "$flips"
        fail=1
    fi
    new_files=$(jq -r --slurpfile ref "$ref" '
        ($ref[0].files | map(.file)) as $known
        | .files[] | select(.file as $f | $known | index($f) | not) | .file' "$json" | wc -l | tr -d ' ')
    [ "$new_files" -gt 0 ] && echo "corpus-check: $new_files file(s) not in the $label baseline (new tests)"
}

compare baseline "$baseline"

if git rev-parse --verify --quiet "${head1_ref}^{commit}" >/dev/null 2>&1; then
    head1_file=$(mktemp)
    trap 'rm -f "$head1_file"' EXIT
    if git show "${head1_ref}:$baseline" > "$head1_file" 2>/dev/null; then
        compare "$head1_ref" "$head1_file"
    else
        echo "corpus-check: no baseline in $head1_ref; skipping the previous-commit comparison"
    fi
else
    echo "corpus-check: '$head1_ref' does not resolve; skipping the previous-commit comparison"
fi

if [ "$fail" -ne 0 ]; then
    echo "corpus-check: FAIL. Fix the regression; the baseline only moves up (scripts/corpus_check.sh --update after a real gain)."
    exit 1
fi
echo "corpus-check: ok"
