#!/bin/bash
# Prints the CHANGELOG.md sections for one release as GitHub release notes.
# Usage: scripts/release_notes.sh vX.Y.Z [previous-tag]
# CHANGELOG=<path> overrides the changelog file.
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

# $(...) already dropped trailing blank lines; sed drops the leading ones.
printf '%s\n' "$NOTES" | sed '/./,$!d'

if [ -n "$PREV" ]; then
    printf '\n**Full Changelog**: https://github.com/blinklang/blink/compare/%s...%s\n' "$PREV" "$VERSION"
fi
