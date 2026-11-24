#!/bin/bash
# Run one task with its full output in a log file, and print a short result.
#
#   scripts/quiet.sh <task> [args ...]     same args as `task`
#
# Pass: one line, `PASS task ci (312s) - log: build/logs/ci.log`.
# Fail: the lines that look like errors (with one line of context before and
# after, de-duplicated, at most BLINK_QUIET_LINES = 40 in all), then one
# `FAIL task ci (exit 2) - full log: build/logs/ci.log` line.
# The exit code is the task's exit code.
#
# A wrapper, not a switch inside Taskfile.yml: most tasks (lint, spec-refs,
# compile-test) do not go through scripts/capped.sh, so one wrapper covers all
# of them and the default output of every task stays as it is. BLINK_QUIET_ACTIVE
# marks the outer run; a nested call runs the task as it is, so only the
# outermost run logs and prints.
set -u

[ $# -gt 0 ] || { echo "usage: scripts/quiet.sh <task> [args ...]" >&2; exit 2; }

if [ -n "${BLINK_QUIET_ACTIVE:-}" ]; then
    exec task "$@"
fi
export BLINK_QUIET_ACTIVE=1

cd "$(dirname "$0")/.." || exit 2
# Name the log after the task: the first word that is not a flag.
name=
skip=0
for a in "$@"; do
    if [ "$skip" = 1 ]; then skip=0; continue; fi
    case "$a" in
        --taskfile | -t) skip=1 ;;
        -*) ;;
        *) name=$a; break ;;
    esac
done
name=${name//[^A-Za-z0-9_.-]/_}
[ -n "$name" ] || name=task
max=${BLINK_QUIET_LINES:-40}
mkdir -p build/logs
log=build/logs/$name.log

start=$SECONDS
task "$@" > "$log" 2>&1 < /dev/null
rc=$?
secs=$((SECONDS - start))

if [ "$rc" -eq 0 ]; then
    echo "PASS task $* ($secs""s) - log: $log"
    exit 0
fi

# Patterns come from real failing gate output: `error[`/`error:` from the
# compiler, `FAIL`/`ASSERT_EQ FAILED`/`assertion failed` from tests and gates,
# `N passed, M failed`, `panic:` from runtime, `Failed to run task` from task.
# `warning[...]` lines are left out: a passing run prints hundreds of them.
pat='error[[]|error:|(^|[^a-zA-Z])(ERROR|Error)|FAIL|[Ff]ailed|panic|assert'
budget=$((max - 1))
awk -v pat="$pat" -v budget="$budget" '
    { line[NR] = substr($0, 1, 200) }
    END {
        for (i = 1; i <= NR; i++) if (line[i] ~ pat) hit[i] = 1
        n = 0
        for (i = 1; i <= NR && n < budget; i++) {
            if (!(hit[i] || hit[i-1] || hit[i+1])) continue
            key = line[i]; gsub(/[0-9]+/, "N", key)
            if (key in seen) continue
            seen[key] = 1
            print line[i]; n++
        }
        # No pattern matched: the tail is the best clue left.
        if (n == 0) {
            s = NR - budget + 1; if (s < 1) s = 1
            for (i = s; i <= NR; i++) print line[i]
        }
    }' "$log"
echo "FAIL task $* (exit $rc) - full log: $log"
exit "$rc"
