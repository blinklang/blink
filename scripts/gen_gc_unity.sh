#!/bin/bash
# Write the single-file GC translation unit that src/cli.bl embeds as
# ../build/gc_unity.c. bootstrap/bootstrap.sh does the same inline; this copy
# exists so the corpus harness and the gen0-compiles-src check can produce
# the file without running a full bootstrap.
#
#   scripts/gen_gc_unity.sh [out file]    (default build/gc_unity.c)
set -eu
cd "$(dirname "$0")/.."
out="${1:-build/gc_unity.c}"
gc_extra="bootstrap/vendor/gc/extra"
mkdir -p "$(dirname "$out")"
tmp="$out.tmp.$$"
trap 'rm -f "$tmp"' EXIT
while IFS= read -r line; do
    inc_path=$(printf '%s\n' "$line" | sed -n 's/^#[[:space:]]*include[[:space:]]*"\(\.\.\/[^"]*\.c\)".*/\1/p')
    if [ -n "$inc_path" ]; then
        echo "/* === inlined: $inc_path === */"
        cat "$gc_extra/$inc_path"
        echo "/* === end: $inc_path === */"
    else
        printf '%s\n' "$line"
    fi
done < "$gc_extra/gc.c" > "$tmp"
mv "$tmp" "$out"
