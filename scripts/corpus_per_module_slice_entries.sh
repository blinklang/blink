#!/bin/sh
# Read a per-module slice list (scripts/corpus_per_module_slice.txt).
#
#   scripts/corpus_per_module_slice_entries.sh <list>             the paths to run
#   scripts/corpus_per_module_slice_entries.sh <list> --manual    the paths picked by hand
#   scripts/corpus_per_module_slice_entries.sh <list> --excluded  the paths left out
#
# A path on a line runs. "# manual" after it marks a file picked by hand, not
# by scripts/corpus_per_module_slice_select.sh. A line
# "# exclude <path>: <why>" names a file the rule picks that the slice leaves
# out. Any other text after a # is a comment.
case "${2:-}" in
    "")
        sed -e 's/#.*//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' "$1" | grep -v '^$' | awk '!seen[$0]++'
        ;;
    --manual)
        grep -E '^[[:space:]]*[^#[:space:]][^#]*#[[:space:]]*manual([^a-z_]|$)' "$1" |
            sed -e 's/#.*//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' | awk '!seen[$0]++'
        ;;
    --excluded)
        sed -n 's/^[[:space:]]*#[[:space:]]*exclude[[:space:]][[:space:]]*\([^:[:space:]]*\).*/\1/p' "$1" | awk '!seen[$0]++'
        ;;
    *)
        echo "corpus_per_module_slice_entries: unknown option $2" >&2
        exit 2
        ;;
esac
