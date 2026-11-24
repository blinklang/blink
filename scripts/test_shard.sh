#!/bin/bash
# Proves scripts/shard.sh splits a list into shards that hold every line
# exactly once, the same lines for any input order, and rejects a bad shard.
set -u
cd "$(dirname "$0")/.."

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
fail=0
bad() { echo "test_shard: FAIL $*"; fail=1; }

# Duplicates and blank lines in the input; neither may reach a shard.
{ seq -f 'tests/t_%03g.bl' 1 23; echo; echo tests/t_005.bl; echo '   '; } > "$WORK/list"
seq -f 'tests/t_%03g.bl' 1 23 | LC_ALL=C sort > "$WORK/want"

for n in 1 2 3 7 23 30; do
    : > "$WORK/union"
    for i in $(seq 1 "$n"); do
        scripts/shard.sh "$i" "$n" < "$WORK/list" > "$WORK/s$i" || bad "shard $i/$n exited $?"
        # The same list in another order gives the same shard.
        tac "$WORK/list" | scripts/shard.sh "$i" "$n" | cmp -s - "$WORK/s$i" || bad "shard $i/$n depends on input order"
        cat "$WORK/s$i" >> "$WORK/union"
    done
    LC_ALL=C sort "$WORK/union" | cmp -s - "$WORK/want" || bad "the $n shards do not hold each line exactly once"
done

for args in "0 3" "4 3" "1 0" "a 3" "1" "1 2 3" "01 3" "-1 3"; do
    # shellcheck disable=SC2086
    scripts/shard.sh $args < "$WORK/list" > /dev/null 2>&1
    [ $? -eq 2 ] || bad "shard.sh $args was not a usage error"
done

if [ "$fail" -ne 0 ]; then
    exit 1
fi
echo "test_shard: all checks passed"
