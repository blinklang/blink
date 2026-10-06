#!/bin/bash
# The spec names the `byte_` Str methods in four places: a closed-list
# sentence, the method table, the StrOps trait block, and the StrOps trait in
# lib/std/traits.bl that the compiler checks against. A method added to one
# and not the others (a `byte_split`, or a byte_at that still returns Int)
# drifts silently, so this compares names and signatures across all four.
#
# Exit codes: 0 all agree, 1 they disagree, 2 a source could not be read.
# STR_BYTE_SPEC / STR_BYTE_TRAITS override the inputs for the self-test.
set -u
cd "$(dirname "$0")/.."

SPEC="${STR_BYTE_SPEC:-sections/03_types.md}"
TRAITS="${STR_BYTE_TRAITS:-lib/std/traits.bl}"

for f in "$SPEC" "$TRAITS"; do
  if [ ! -f "$f" ]; then
    echo "check_str_byte_methods: cannot read $f" >&2
    exit 2
  fi
done

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# Only the first sentence: the next one names methods that must NOT exist.
grep -m1 'The `byte_` methods are exactly' "$SPEC" \
  | sed 's/\. .*//' \
  | grep -o '`byte_[a-z_]*`' | tr -d '`' | grep -v '^byte_$' | sort > "$WORK/sentence"

grep -E '^\| `byte_[a-z_]+` \| `fn\(' "$SPEC" \
  | sed -E 's/^\| `(byte_[a-z_]+)` \| `([^`]*)`.*/\1 \2/' | sort > "$WORK/table"

# Trait lines drop parameter names so they read like the table's fn types.
trait_sigs() {
  sed -n "/$2/,/^}/p" "$1" \
    | grep -E '^ *fn byte_[a-z_]+\(' \
    | sed -E 's/^ *fn (byte_[a-z_]+)\((.*)$/\1 fn(\2/; s/[a-z_]+: //g; s/ +$//' | sort
}
trait_sigs "$SPEC" '^trait StrOps {' > "$WORK/spec_trait"
trait_sigs "$TRAITS" '^pub trait StrOps {' > "$WORK/lib_trait"

for src in sentence table spec_trait lib_trait; do
  if [ ! -s "$WORK/$src" ]; then
    echo "check_str_byte_methods: found no byte_ methods in the $src source" >&2
    exit 2
  fi
done

fail=0
cut -d' ' -f1 "$WORK/table" > "$WORK/table_names"
if ! diff -u --label "spec sentence" --label "spec table" "$WORK/sentence" "$WORK/table_names" > "$WORK/d"; then
  echo "FAIL: the spec sentence and the spec table name different byte_ methods"
  cat "$WORK/d"
  fail=1
fi
for src in spec_trait lib_trait; do
  if ! diff -u --label "spec table" --label "$src" "$WORK/table" "$WORK/$src" > "$WORK/d"; then
    echo "FAIL: the spec table and $src disagree on byte_ methods"
    cat "$WORK/d"
    fail=1
  fi
done

if [ $fail -eq 0 ]; then
  echo "check_str_byte_methods: $(wc -l < "$WORK/table") byte_ methods agree"
fi
exit $fail
