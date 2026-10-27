#!/bin/bash
# The br ticket ids, and where they occur in a set of files. br is a tracker
# local to one machine, so an id in pushed text tells a reader nothing; the
# rows that hold source to zero ids (ratchet.sh br_ids_in_source and
# lint_codegen.sh L10) read through this script.
#
# An id is six [0-9a-z] with no fixed shape: some are all letters, some are
# hex, and most such tokens in source are plain words. So a token counts only
# when it is an id br knows. A token is bounded by any character that is not
# a letter or a digit, so `_` and `-` end it: `abc123_run` holds an id.
#
#   scripts/br_ids.sh list               print every id, one per line
#   scripts/br_ids.sh scan <ids> <file>  print file:line:id for each occurrence
#
# BR_IDS_FILE names a file of ids for `list` to print instead of asking br
# (the self-tests use it). `list` exits 1 with a message on stderr when br is
# missing or knows no ids; the caller decides what that means for its row.
set -u

case "${1:-}" in
list)
    if [ -n "${BR_IDS_FILE:-}" ]; then
        [ -f "$BR_IDS_FILE" ] || { echo "br_ids: BR_IDS_FILE '$BR_IDS_FILE' does not exist" >&2; exit 1; }
        cat "$BR_IDS_FILE"
        exit 0
    fi
    command -v br > /dev/null 2>&1 || { echo "br_ids: br is not on PATH" >&2; exit 1; }
    ids=$(br list --all --json 2>/dev/null | grep -oP '"id":"\K[0-9a-z]{6}(?=")' | sort -u)
    [ -n "$ids" ] || { echo "br_ids: br list --all --json gave no ids" >&2; exit 1; }
    printf '%s\n' "$ids"
    ;;
scan)
    ids="$2"; shift 2
    [ $# -eq 0 ] && exit 0
    [ -s "$ids" ] || exit 0
    grep -nHoP '(?<![A-Za-z0-9])[0-9a-z]{6}(?![A-Za-z0-9])' -- "$@" 2>/dev/null |
        awk 'NR == FNR { id[$1] = 1; next } { n = split($0, f, ":"); if (f[n] in id) print }' "$ids" -
    ;;
*)
    echo "usage: scripts/br_ids.sh list | scan <ids file> <file>..." >&2
    exit 2
    ;;
esac
