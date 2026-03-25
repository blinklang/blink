#!/bin/sh
# Golden test: format input, compare against expected output
input="$1"
blinkc="$2"
name=$(basename "$input" .bl | sed 's/^input_//')
expected="tests/fmt/expected_${name}.bl"
[ ! -f "$expected" ] && exit 0
actual=$(mktemp .tmp/fmt-golden-XXXXXX)
if ! "$blinkc" "$input" "$actual" --emit blink 2>/dev/null; then
  rm -f "$actual"
  echo "FAIL (format) golden_${name}"
  exit 1
fi
if diff -u "$expected" "$actual" >/dev/null 2>&1; then
  rm -f "$actual"
  echo "PASS golden_${name}"
else
  diff -u "$expected" "$actual" | head -20 >&2
  rm -f "$actual"
  echo "FAIL (golden) ${name}"
  exit 1
fi
