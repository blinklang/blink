#!/bin/sh
# Semantic test: the formatted program behaves like the original. Both are
# compiled and run the same way, and only a difference counts as a failure,
# so a test that fails on its own does not read as a formatter bug.
f="$1"
blinkc="$2"
skip_file="$3"
name=$(basename "$f" .bl)
[ -f "$skip_file" ] && grep -qw "$name" "$skip_file" && { echo "SKIP sem_${name}"; exit 0; }
src_dir=$(dirname "$f")
fmt_src=$(mktemp "$src_dir/fmt-sem-XXXXXX.bl")
fmt_c=$(mktemp .tmp/fmt-sem-XXXXXX.c)
fmt_bin=$(mktemp .tmp/fmt-sem-XXXXXX)
orig_c=$(mktemp .tmp/fmt-sem-XXXXXX.c)
orig_bin=$(mktemp .tmp/fmt-sem-XXXXXX)
cleanup() { rm -f "$fmt_src" "$fmt_c" "$fmt_bin" "$orig_c" "$orig_bin"; }
# A file the formatter cannot format is a formatter bug; only the skip list
# may excuse it.
if ! "$blinkc" "$f" "$fmt_src" --emit blink 2>/dev/null; then
  cleanup
  echo "FAIL (format) ${name}"
  exit 1
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
  if blinkc_ok "$f" "$orig_c"; then
    cleanup
    echo "FAIL (fmt breaks compile) ${name}"
    exit 1
  fi
  cleanup
  echo "SKIP sem_${name}"
  exit 0
fi
if ! blinkc_ok "$f" "$orig_c"; then
  cleanup
  echo "FAIL (fmt makes a failing compile pass) ${name}"
  exit 1
fi

# cc_ok <c file> <binary>
if [ "$use_archive" = 1 ]; then
  # monolith.o is built with BLINK_USE_SQLITE=1 and pulls in curl-using stdlib
  # paths, so it has undefined refs to sqlite3_*/curl_* whenever a fixture
  # touches those symbols. --gc-sections drops the unreferenced ones; the rest
  # need real libs. Always linking both is cheaper than scanning fixtures.
  cc_ok() { cc -o "$2" "$1" -Ibuild "$archive_a" -lm -lgc -lsqlite3 -lcurl -pthread -Wl,--gc-sections 2>/dev/null; }
else
  cc_ok() {
    link_flags="-lm -lgc"
    grep -q BLINK_USE_CURL "$1" && link_flags="$link_flags -lcurl"
    grep -q BLINK_USE_SQLITE "$1" && link_flags="$link_flags -lsqlite3"
    cc -o "$2" "$1" -I bootstrap $link_flags 2>/dev/null
  }
fi
if ! cc_ok "$fmt_c" "$fmt_bin" || ! cc_ok "$orig_c" "$orig_bin"; then
  cleanup
  echo "FAIL (cc) ${name}"
  exit 1
fi

# outcome <binary>: the exit status plus each test's verdict and the summary
# line, colour stripped. Other output names the source file and its line
# numbers, which formatting changes by design. A file with no test blocks
# keeps its whole stdout.
#
# The binary sits in .tmp/, which has no lib/ beside it, so a test that
# compiles a program in process finds the prelude through BLINK_ROOT. A file
# with both test blocks and a main runs its tests, as in the corpus.
run_args=""
if grep -qE '^test "|^test\.failing\(' "$f" && grep -q 'fn main(' "$f"; then
  run_args="--test"
fi
outcome() {
  out=$(BLINK_ROOT="$(pwd)" "$1" $run_args 2>/dev/null)
  rc=$?
  out=$(printf '%s\n' "$out" | sed 's/\x1b\[[0-9;]*m//g')
  if printf '%s\n' "$out" | grep -qE '^test .* \.\.\. '; then
    out=$(printf '%s\n' "$out" | grep -E '^test .* \.\.\. (ok|FAIL|SKIP|skipped|xfail|XPASS)|^[0-9]+ passed, ')
  fi
  printf 'exit %s\n%s\n' "$rc" "$out"
}
orig_outcome=$(outcome "$orig_bin")
fmt_outcome=$(outcome "$fmt_bin")
cleanup
if [ "$orig_outcome" = "$fmt_outcome" ]; then
  echo "PASS sem_${name}"
else
  echo "FAIL (outcome differs) fmt_${name}"
  exit 1
fi
