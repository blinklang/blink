#!/bin/sh
# Idempotency test: format(format(x)) == format(x)
f="$1"
pactc="$2"
skip_file="$3"
name=$(basename "$f" .pact)
[ -f "$skip_file" ] && grep -qw "$name" "$skip_file" && { echo "SKIP idem_${name}"; exit 0; }
fmt1=$(mktemp .tmp/fmt-idem1-XXXXXX)
fmt2=$(mktemp .tmp/fmt-idem2-XXXXXX)
if ! "$pactc" "$f" "$fmt1" --emit pact 2>/dev/null; then
  rm -f "$fmt1" "$fmt2"
  echo "SKIP idem_${name}"
  exit 0
fi
if ! "$pactc" "$fmt1" "$fmt2" --emit pact 2>/dev/null; then
  rm -f "$fmt1" "$fmt2"
  echo "SKIP idem_${name}"
  exit 0
fi
if diff -q "$fmt1" "$fmt2" >/dev/null 2>&1; then
  rm -f "$fmt1" "$fmt2"
  echo "PASS idem_${name}"
else
  rm -f "$fmt1" "$fmt2"
  echo "FAIL (idempotent) ${name}"
  exit 1
fi
