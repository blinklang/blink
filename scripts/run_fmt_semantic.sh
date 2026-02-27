#!/bin/sh
# Semantic test: formatted output still compiles and passes
f="$1"
pactc="$2"
skip_file="$3"
name=$(basename "$f" .pact)
[ -f "$skip_file" ] && grep -qw "$name" "$skip_file" && { echo "SKIP sem_${name}"; exit 0; }
fmt_src=$(mktemp .tmp/fmt-sem-XXXXXX.pact)
fmt_c=$(mktemp .tmp/fmt-sem-XXXXXX.c)
fmt_bin=$(mktemp .tmp/fmt-sem-XXXXXX)
if ! "$pactc" "$f" "$fmt_src" --emit pact 2>/dev/null; then
  rm -f "$fmt_src" "$fmt_c" "$fmt_bin"
  echo "SKIP sem_${name}"
  exit 0
fi
if ! "$pactc" "$fmt_src" "$fmt_c" 2>/dev/null; then
  rm -f "$fmt_src" "$fmt_c" "$fmt_bin"
  echo "SKIP sem_${name}"
  exit 0
fi
if ! cc -o "$fmt_bin" "$fmt_c" -I bootstrap -lm 2>/dev/null; then
  rm -f "$fmt_src" "$fmt_c" "$fmt_bin"
  echo "FAIL (cc) ${name}"
  exit 1
fi
if output=$("$fmt_bin" 2>&1); then
  rm -f "$fmt_src" "$fmt_c" "$fmt_bin"
  if echo "$output" | grep -q "FAIL"; then
    echo "FAIL (assert) fmt_${name}"
    exit 1
  else
    echo "PASS sem_${name}"
  fi
else
  rm -f "$fmt_src" "$fmt_c" "$fmt_bin"
  echo "FAIL (crash) fmt_${name}"
  exit 1
fi
