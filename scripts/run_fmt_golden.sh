#!/bin/sh
# Golden test: format input, compare against expected output
input="$1"
blinkc="$2"
name=$(basename "$input" .bl | sed 's/^input_//')
expected="tests/fmt/expected_${name}.bl"
[ ! -f "$expected" ] && exit 0
actual=$(mktemp "${TMPDIR:-/tmp}/fmt-golden-XXXXXX")
# child <command...>: run the command as a capped child (scripts/capped.sh
# --child). Its stderr, with the line capped.sh prints for a cap it hit, goes
# to $child_err; check_limit fails the file when such a line is there, so a
# runaway file fails as itself and names the limit.
child_err=$(mktemp "${TMPDIR:-/tmp}/fmt-child-XXXXXX")
child() { "$(dirname "$0")/capped.sh" --child "$@" 2>>"$child_err"; }
if ! child "$blinkc" "$input" "$actual" --emit blink; then
  limit=$(grep '^capped.sh: the child' "$child_err" | tail -1)
  rm -f "$actual" "$child_err"
  [ -n "$limit" ] && { echo "FAIL ($limit) golden_${name}"; exit 1; }
  echo "FAIL (format) golden_${name}"
  exit 1
fi
rm -f "$child_err"
if diff -u "$expected" "$actual" >/dev/null 2>&1; then
  rm -f "$actual"
  echo "PASS golden_${name}"
else
  diff -u "$expected" "$actual" | head -20 >&2
  rm -f "$actual"
  echo "FAIL (golden) ${name}"
  exit 1
fi
