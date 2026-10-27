#!/bin/sh
# Print how many processes each of <workers> workers may start at once (for
# example the cc units of a per-module build, through BLINK_JOBS), so the
# workers together stay within the gate's worker budget: the budget divided by
# the workers, at least 1. See scripts/default_jobs.sh.
#
#   scripts/inner_jobs.sh <workers>
case "${1:-}" in
    '' | *[!0-9]* | 0) echo "usage: inner_jobs.sh <workers>, a positive whole number" >&2; exit 2 ;;
esac
b=$("$(dirname "$0")/default_jobs.sh")
i=$((b / $1))
[ "$i" -lt 1 ] && i=1
echo "$i"
