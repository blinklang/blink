#!/bin/sh
# Print shard <i> of <n> of the lines on stdin: the lines sorted in the C
# locale with blank lines and repeats dropped, then every n-th line from the
# i-th. The n shards of one list hold each line exactly once, and a shard holds
# the same lines on every machine, so a rerun of one shard runs the files it
# ran before.
#
#   ls tests/test_*.bl | scripts/shard.sh <i> <n>      1 <= i <= n
set -u
usage() { echo "usage: shard.sh <i> <n> (whole numbers, 1 <= i <= n), list on stdin" >&2; exit 2; }
[ $# -eq 2 ] || usage
for a in "$1" "$2"; do
    case "$a" in '' | *[!0-9]* | 0*) usage ;; esac
done
[ "$1" -le "$2" ] || usage
grep -v '^[[:space:]]*$' | LC_ALL=C sort -u | awk -v i="$1" -v n="$2" '(NR - 1) % n == i - 1'
