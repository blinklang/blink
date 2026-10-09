#!/bin/bash
# Hold the per-module slice list to what its selection rule picks now, so a new
# test the rule picks cannot miss the slice unseen.
#
#   scripts/corpus_per_module_slice_drift.sh <list>
#
# Fails when the rule (scripts/corpus_per_module_slice_select.sh) picks a file
# the list neither runs nor excludes, when the list runs a file the rule does
# not pick and no "# manual" marks, or when an "# exclude" line names a file the
# rule does not pick or the list also runs. scripts/corpus_per_module_slice_entries.sh
# reads the markers.
#
# SLICE_PICKED names a file of picks to use in place of running the rule
# (scripts/test_corpus.sh uses it).
set -u
cd "$(dirname "$0")/.." || exit 2

list="${1:-}"
if [ -z "$list" ] || [ ! -f "$list" ]; then
    echo "corpus-per-module-slice-drift: FAIL no slice list ${list:-(none given)}"
    exit 1
fi

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
if [ -n "${SLICE_PICKED:-}" ]; then
    LC_ALL=C sort -u "$SLICE_PICKED" | grep -v '^$' > "$work/picked"
else
    ./scripts/corpus_per_module_slice_select.sh > "$work/picked.raw" || {
        echo "corpus-per-module-slice-drift: FAIL the selection rule did not run"
        exit 2
    }
    LC_ALL=C sort -u "$work/picked.raw" > "$work/picked"
fi
./scripts/corpus_per_module_slice_entries.sh "$list" | LC_ALL=C sort -u > "$work/entries"
./scripts/corpus_per_module_slice_entries.sh "$list" --manual | LC_ALL=C sort -u > "$work/manual"
./scripts/corpus_per_module_slice_entries.sh "$list" --excluded | LC_ALL=C sort -u > "$work/excluded"

fail=0
report() { # <header> <file of paths>
    [ -s "$2" ] || return 0
    echo "corpus-per-module-slice-drift: FAIL $1"
    sed 's/^/  /' "$2"
    fail=1
}

LC_ALL=C sort -u "$work/entries" "$work/excluded" > "$work/covered"
LC_ALL=C comm -23 "$work/picked" "$work/covered" > "$work/missing"
report "the rule picks files $list lacks. Run scripts/corpus_per_module_slice_select.sh and add each file below to $list, or an '# exclude <path>: <why>' line:" "$work/missing"

LC_ALL=C comm -23 "$work/entries" "$work/picked" | LC_ALL=C comm -23 - "$work/manual" > "$work/unpicked"
report "$list runs files the rule does not pick and no '# manual' marks. Mark each hand-picked file '# manual: <why>', or remove it:" "$work/unpicked"

LC_ALL=C comm -23 "$work/excluded" "$work/picked" > "$work/stale"
report "$list excludes files the rule does not pick. Remove these '# exclude' lines:" "$work/stale"

LC_ALL=C comm -12 "$work/excluded" "$work/entries" > "$work/both"
report "$list both runs and excludes these files:" "$work/both"

[ "$fail" -eq 0 ] || exit 1
n_rule=$(LC_ALL=C comm -12 "$work/entries" "$work/picked" | wc -l | tr -d ' ')
n_manual=$(LC_ALL=C comm -23 "$work/entries" "$work/picked" | wc -l | tr -d ' ')
n_excluded=$(wc -l < "$work/excluded" | tr -d ' ')
echo "corpus-per-module-slice-drift: ok $n_rule picked by the rule, $n_manual by hand, $n_excluded excluded"
