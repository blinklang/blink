#!/bin/bash
# Run each argument as a shell command, all at once, and print each one's
# output in argument order once all have ended, so the log reads as if they
# had run one after another.
#
#   scripts/run_together.sh <command> [<command> ...]
#
# Exit 1 when any command fails, after naming each one that did.
set -u

[ $# -gt 0 ] || { echo "run_together: no commands" >&2; exit 2; }
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

pids=()
i=0
for c in "$@"; do
    bash -c "$c" > "$work/$i.out" 2>&1 &
    pids+=("$!")
    i=$((i + 1))
done

failed=()
i=0
for c in "$@"; do
    wait "${pids[$i]}"
    rc=$?
    cat "$work/$i.out"
    [ "$rc" -ne 0 ] && failed+=("$c (exit $rc)")
    i=$((i + 1))
done

if [ "${#failed[@]}" -gt 0 ]; then
    echo "run_together: FAIL"
    printf '  %s\n' "${failed[@]}"
    exit 1
fi
exit 0
