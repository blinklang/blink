#!/bin/sh
# Semantic test: formatted output still compiles and passes
f="$1"
blinkc="$2"
skip_file="$3"
name=$(basename "$f" .bl)
[ -f "$skip_file" ] && grep -qw "$name" "$skip_file" && { echo "SKIP sem_${name}"; exit 0; }
src_dir=$(dirname "$f")
fmt_src=$(mktemp "$src_dir/fmt-sem-XXXXXX.bl")
fmt_c=$(mktemp .tmp/fmt-sem-XXXXXX.c)
fmt_bin=$(mktemp .tmp/fmt-sem-XXXXXX)
if ! "$blinkc" "$f" "$fmt_src" --emit blink 2>/dev/null; then
  rm -f "$fmt_src" "$fmt_c" "$fmt_bin"
  echo "SKIP sem_${name}"
  exit 0
fi

# Re-linking the 10MB monolith for every fixture dominates this script's cost,
# so prefer archive mode when the artifacts exist; fall back to monolith so the
# script stays self-contained.
archive_a="build/libblink_std.a"
archive_h="build/libblink_std.h"
use_archive=0
[ -f "$archive_a" ] && [ -f "$archive_h" ] && use_archive=1

# blinkc_ok <source> <c output>
if [ "$use_archive" = 1 ]; then
  blinkc_ok() { "$blinkc" --link-archive "$archive_h" "$1" "$2" >/dev/null 2>&1; }
else
  blinkc_ok() { "$blinkc" "$1" "$2" >/dev/null 2>&1; }
fi
# A formatted file that no longer compiles is a formatter bug only when the
# original compiles; otherwise the compiler cannot build this program yet.
if ! blinkc_ok "$fmt_src" "$fmt_c"; then
  if blinkc_ok "$f" "$fmt_c"; then
    rm -f "$fmt_src" "$fmt_c" "$fmt_bin"
    echo "FAIL (fmt breaks compile) ${name}"
    exit 1
  fi
  rm -f "$fmt_src" "$fmt_c" "$fmt_bin"
  echo "SKIP sem_${name}"
  exit 0
fi

if [ "$use_archive" = 1 ]; then
  # monolith.o is built with BLINK_USE_SQLITE=1 and pulls in curl-using stdlib
  # paths, so it has undefined refs to sqlite3_*/curl_* whenever a fixture
  # touches those symbols. --gc-sections drops the unreferenced ones; the rest
  # need real libs. Always linking both is cheaper than scanning fixtures.
  cc_cmd="cc -o $fmt_bin $fmt_c -Ibuild $archive_a -lm -lgc -lsqlite3 -lcurl -pthread -Wl,--gc-sections"
else
  link_flags="-lm -lgc"
  grep -q BLINK_USE_CURL "$fmt_c" && link_flags="$link_flags -lcurl"
  grep -q BLINK_USE_SQLITE "$fmt_c" && link_flags="$link_flags -lsqlite3"
  cc_cmd="cc -o $fmt_bin $fmt_c -I bootstrap $link_flags"
fi

if ! $cc_cmd 2>/dev/null; then
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
