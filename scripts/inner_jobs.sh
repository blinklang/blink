#!/bin/sh
# Print how many processes each of <workers> workers may start at once (for
# example the cc units of a per-module build, through BLINK_JOBS), so the
# workers together stay within the gate's worker budget: the budget divided by
# the workers, at least 1. See scripts/default_jobs.sh.
#
# A caller's BLINK_JOBS may lower the share but not raise it: a BLINK_JOBS
# left in a login shell would otherwise multiply every fan-out again. To give
# each worker more, run fewer workers.
#
#   scripts/inner_jobs.sh <workers>
case "${1:-}" in
    '' | *[!0-9]* | 0*) echo "usage: inner_jobs.sh <workers>, a positive whole number" >&2; exit 2 ;;
esac
b=$("$(dirname "$0")/default_jobs.sh")
i=$((b / $1))
[ "$i" -lt 1 ] && i=1
case "${BLINK_JOBS:-}" in
    '' | *[!0-9]* | 0*) ;;
    *) [ "$BLINK_JOBS" -lt "$i" ] && i=$BLINK_JOBS ;;
esac
echo "$i"
