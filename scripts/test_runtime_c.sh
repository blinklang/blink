#!/bin/bash
# Builds each tests/runtime_c/*.c against bootstrap/runtime.h with BLINK_DEBUG and runs it with
# no argument. Each file checks its own cases and exits 0 only when all pass. These tests hold
# runtime faults that no Blink program can cause, such as a Str whose bytes a foreign write
# changed, so they cannot be Blink tests.
set -u
cd "$(dirname "$0")/.."

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
fail=0
count=0
for src in tests/runtime_c/*.c; do
    [ -e "$src" ] || continue
    name=$(basename "$src" .c)
    count=$((count + 1))
    if ! ${CC:-cc} -DBLINK_DEBUG -Ibootstrap -o "$WORK/$name" "$src" -lm -lgc -pthread > "$WORK/$name.cc.log" 2>&1; then
        echo "FAIL runtime-c $name: does not compile"
        cat "$WORK/$name.cc.log"
        fail=1
        continue
    fi
    if ! "$WORK/$name" > "$WORK/$name.log" 2>&1; then
        echo "FAIL runtime-c $name"
        cat "$WORK/$name.log"
        fail=1
    fi
done
if [ "$count" -eq 0 ]; then
    echo "FAIL runtime-c: no tests/runtime_c/*.c found"
    exit 1
fi
[ "$fail" -eq 0 ] && echo "runtime-c: ok $count/$count"
exit "$fail"
