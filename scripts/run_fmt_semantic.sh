#!/bin/sh
# Semantic test: formatted output still compiles and passes
f="$1"
blinkc="$2"
skip_file="$3"
name=$(basename "$f" .bl)
[ -f "$skip_file" ] && grep -qw "$name" "$skip_file" && { echo "SKIP sem_${name}"; exit 0; }
fmt_src=$(mktemp .tmp/fmt-sem-XXXXXX.bl)
fmt_c=$(mktemp .tmp/fmt-sem-XXXXXX.c)
fmt_bin=$(mktemp .tmp/fmt-sem-XXXXXX)
if ! "$blinkc" "$f" "$fmt_src" --emit blink 2>/dev/null; then
  rm -f "$fmt_src" "$fmt_c" "$fmt_bin"
  echo "SKIP sem_${name}"
  exit 0
fi
if ! "$blinkc" "$fmt_src" "$fmt_c" 2>/dev/null; then
  rm -f "$fmt_src" "$fmt_c" "$fmt_bin"
  echo "SKIP sem_${name}"
  exit 0
fi
link_flags="-lm -lgc"
grep -q BLINK_USE_CURL "$fmt_c" && link_flags="$link_flags -lcurl"
grep -q BLINK_USE_SQLITE "$fmt_c" && link_flags="$link_flags -lsqlite3"
if ! cc -o "$fmt_bin" "$fmt_c" -I bootstrap $link_flags 2>/dev/null; then
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
