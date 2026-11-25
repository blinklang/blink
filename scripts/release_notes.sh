#!/bin/bash
# Prints the CHANGELOG.md sections for one release as GitHub release notes.
# Usage: scripts/release_notes.sh vX.Y.Z [previous-tag]
# CHANGELOG=<path> overrides the changelog file.
# GitHub refuses a release body over 125000 characters. Notes over NOTES_MAX
# (default that cap) keep each heading and the bold lead of each bullet, and
# link the full changelog at the tag. Notes that do not fit even then fail.
set -eu
cd "$(dirname "$0")/.."

if [ $# -lt 1 ] || [ $# -gt 2 ]; then
    echo "usage: $0 vX.Y.Z [previous-tag]" >&2
    exit 2
fi
VERSION="$1"
PREV="${2:-}"
CHANGELOG="${CHANGELOG:-CHANGELOG.md}"

if [ ! -f "$CHANGELOG" ]; then
    echo "release_notes: $CHANGELOG not found" >&2
    exit 1
fi

# Plain string compare on the heading tail, so the dots in the version are
# literal and v0.5.0 cannot match v0.55.0 or v0.5.01.
NOTES=$(awk -v suffix=" ($VERSION)" '
    /^## / {
        n = length($0) - length(suffix)
        on = (n > 0 && substr($0, n + 1) == suffix)
        if (on) $0 = substr($0, 1, n)
    }
    on { print }
' "$CHANGELOG")

if [ -z "$NOTES" ]; then
    echo "release_notes: $CHANGELOG has no section headed '(${VERSION})'" >&2
    exit 1
fi

MAX="${NOTES_MAX:-125000}"
# Count what the file holds, its final newline too.
chars() { printf '%s\n' "$1" | LC_ALL=C.UTF-8 wc -m; }

FOOTER=""
if [ -n "$PREV" ]; then
    FOOTER=$(printf '\n\n**Full Changelog**: https://github.com/blinklang/blink/compare/%s...%s' "$PREV" "$VERSION")
fi

# $(...) already dropped trailing blank lines; sed drops the leading ones.
BODY=$(printf '%s\n' "$NOTES" | sed '/./,$!d')
OUT="$BODY$FOOTER"

if [ "$(chars "$OUT")" -gt "$MAX" ]; then
    # A bullet keeps its first line, cut after a bold lead; other lines go.
    SHORT=$(printf '%s\n' "$BODY" \
        | awk '/^## / || /^$/ { print; next }
               /^- / { if (match($0, /^- \*\*[^*]+\*\*/)) print substr($0, 1, RLENGTH); else print }' \
        | cat -s)
    OUT=$(printf '%s\n\nThese notes keep the first sentence of each change. Each change is in full in [CHANGELOG.md](https://github.com/blinklang/blink/blob/%s/CHANGELOG.md).%s' "$SHORT" "$VERSION" "$FOOTER")
    if [ "$(chars "$OUT")" -gt "$MAX" ]; then
        echo "release_notes: the notes for $VERSION are over $MAX characters even with only the first sentence of each change" >&2
        exit 1
    fi
fi

printf '%s\n' "$OUT"
