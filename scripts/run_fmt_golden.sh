#!/bin/sh
# Golden test: format input, compare against expected output
input="$1"
blinkc="$2"
name=$(basename "$input" .bl | sed 's/^input_//')
expected="tests/fmt/expected_${name}.bl"
[ ! -f "$expected" ] && exit 0
actual=$(mktemp "${TMPDIR:-/tmp}/fmt-golden-XXXXXX")
# child <command...>: run the command as a capped child (scripts/capped.sh
# --child). When a cap ends it, $limit_file holds the line that names the cap,
# so a runaway file fails as itself and names the limit.
capped="$(dirname "$0")/capped.sh"
limit_file=$(mktemp "${TMPDIR:-/tmp}/fmt-limit-XXXXXX")
child() { "$capped" --child --report "$limit_file" "$@"; }
if ! child "$blinkc" "$input" "$actual" --emit blink 2>/dev/null; then
  limit=$(cat "$limit_file")
  rm -f "$actual" "$limit_file"
  echo "FAIL (${limit:-format}) golden_${name}"
  exit 1
fi
rm -f "$limit_file"
if diff -u "$expected" "$actual" >/dev/null 2>&1; then
  rm -f "$actual"
  echo "PASS golden_${name}"
else
  diff -u "$expected" "$actual" | head -20 >&2
  rm -f "$actual"
  echo "FAIL (golden) ${name}"
  exit 1
fi
