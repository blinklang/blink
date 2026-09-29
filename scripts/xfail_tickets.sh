#!/bin/bash
# Checks that every test.failing row in tests/ names a br ticket that is still
# open. A row whose ticket closed is a fix nobody inverted, or a row pointing
# at the wrong ticket; a row with no ticket has nobody tracking it.
#
# Local only: br is local-only, so this is not part of task ci. Without br it
# says so and exits 0.
#
#   scripts/xfail_tickets.sh [file...]   default: every tests/**/*.bl
#
# Env overrides (for a check against a fixed list instead of br):
#   XFAIL_BR         the br command. Default: br
#   XFAIL_OPEN_IDS   a file of open ticket ids, one per line
#   XFAIL_ALL_IDS    a file of every ticket id, one per line
set -u
cd "$(dirname "$0")/.." || exit 2

br_cmd="${XFAIL_BR:-br}"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

if [ -n "${XFAIL_OPEN_IDS:-}" ] && [ -n "${XFAIL_ALL_IDS:-}" ]; then
    sort -u "$XFAIL_OPEN_IDS" > "$work/open"
    sort -u "$XFAIL_ALL_IDS" > "$work/all"
elif command -v "$br_cmd" >/dev/null 2>&1; then
    "$br_cmd" list 2>/dev/null | grep -oP '^\[.\]\s+\K[0-9a-z]{6}(?=\s)' | sort -u > "$work/open"
    "$br_cmd" list --all 2>/dev/null | grep -oP '^\[.\]\s+\K[0-9a-z]{6}(?=\s)' | sort -u > "$work/all"
else
    echo "xfail_tickets: '$br_cmd' is not on PATH; skipping (this check needs the local br database)"
    exit 0
fi

if [ $# -gt 0 ]; then
    files=("$@")
else
    mapfile -t files < <(find tests -name '*.bl' | sort)
fi

# One line per row: file, line of test.failing(, ticket or "-". A row starts
# at column 0 outside a raw string: the tests of test.failing itself carry
# rows inside #"..."# probe programs, and those name made-up tickets.
for f in "${files[@]}"; do
    awk -v file="$f" '
        {
            line = $0
            opens = gsub(/#"/, "", line)
            line = $0
            closes = gsub(/"#/, "", line)
        }
        raw == 0 && /^test\.failing\(/ { open = 1; start = FNR; ticket = "-" }
        open && match($0, /ticket:[[:space:]]*"[^"]*"/) {
            t = substr($0, RSTART, RLENGTH)
            sub(/^ticket:[[:space:]]*"/, "", t); sub(/"$/, "", t)
            ticket = t
        }
        open && /\)[[:space:]]*\{[[:space:]]*$/ { print file, start, ticket; open = 0 }
        { raw += opens - closes }
    ' "$f"
done > "$work/rows"

bad=0
while read -r file line ticket; do
    if [ "$ticket" = "-" ]; then
        echo "$file:$line: test.failing row names no ticket"
        bad=$((bad + 1))
    elif ! grep -qx -- "$ticket" "$work/all"; then
        echo "$file:$line: ticket $ticket is not a br ticket"
        bad=$((bad + 1))
    elif ! grep -qx -- "$ticket" "$work/open"; then
        echo "$file:$line: ticket $ticket is closed; invert the row if the fix landed, or point it at the open ticket"
        bad=$((bad + 1))
    fi
done < "$work/rows"

rows=$(wc -l < "$work/rows" | tr -d ' ')
if [ "$bad" -ne 0 ]; then
    echo "xfail_tickets: $bad of $rows test.failing rows need attention"
    exit 1
fi
echo "xfail_tickets: ok ($rows test.failing rows, each names an open ticket)"
