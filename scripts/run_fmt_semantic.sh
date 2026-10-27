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
# The formatted copy ends in the original file name, so a test that matches its
# own file name in a panic location or diagnostic still matches.
fmt_src=$(mktemp --suffix="_$name.bl" "$src_dir/fmt-sem-XXXXXX")
fmt_c=$(mktemp "${TMPDIR:-/tmp}/fmt-sem-XXXXXX.c")
fmt_bin=$(mktemp "${TMPDIR:-/tmp}/fmt-sem-XXXXXX")
orig_c=$(mktemp "${TMPDIR:-/tmp}/fmt-sem-XXXXXX.c")
orig_bin=$(mktemp "${TMPDIR:-/tmp}/fmt-sem-XXXXXX")
# child <command...>: run the command as a capped child (scripts/capped.sh
# --child). When a cap ends it, $limit_file holds the line that names the cap,
# so a runaway file fails as itself and names the limit.
capped="$(dirname "$0")/capped.sh"
limit_file=$(mktemp "${TMPDIR:-/tmp}/fmt-limit-XXXXXX")
child() { "$capped" --child --report "$limit_file" "$@"; }
cleanup() { rm -f "$fmt_src" "$fmt_c" "$fmt_bin" "$orig_c" "$orig_bin" "$limit_file"; }
# check_limit: fail the file when a cap ended the last child. A step that a
# cap killed says nothing about the formatter, so no later verdict may stand
# in for it.
check_limit() {
  limit=$(cat "$limit_file")
  [ -z "$limit" ] && return
  [ -n "${scratch:-}" ] && rm -rf "$scratch"
  cleanup
  echo "FAIL ($limit) ${name}"
  exit 1
}
# A file the formatter cannot format is a formatter bug; only the skip list
# may excuse it.
if ! child "$blinkc" "$f" "$fmt_src" --emit blink 2>/dev/null; then
  check_limit
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

# Only a test build keeps test blocks, and it runs them, never main. A file with a main and
# no test block gets a plain build, as in the corpus.
# One word or none, left unquoted below: this is sh, which has no arrays.
test_build=--test-build
if grep -q 'fn main(' "$f" && ! grep -qE '^test "|^test\.failing\(' "$f"; then
  test_build=
fi

# blinkc_ok <source> <c output>
if [ "$use_archive" = 1 ]; then
  blinkc_ok() { child "$blinkc" $test_build --link-archive "$archive_h" "$1" "$2" >/dev/null 2>&1; }
else
  blinkc_ok() { child "$blinkc" $test_build "$1" "$2" >/dev/null 2>&1; }
fi
# A formatted file that no longer compiles is a formatter bug only when the
# original compiles; otherwise the compiler cannot build this program yet.
if ! blinkc_ok "$fmt_src" "$fmt_c"; then
  check_limit
  if blinkc_ok "$f" "$orig_c"; then
    cleanup
    echo "FAIL (fmt breaks compile) ${name}"
    exit 1
  fi
  check_limit
  cleanup
  echo "SKIP sem_${name}"
  exit 0
fi
if ! blinkc_ok "$f" "$orig_c"; then
  check_limit
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
  cc_ok() { child cc -o "$2" "$1" -Ibuild "$archive_a" -lm -lgc -lsqlite3 -lcurl -pthread -Wl,--gc-sections; }
else
  cc_ok() {
    link_flags="-lm -lgc"
    grep -q BLINK_USE_CURL "$1" && link_flags="$link_flags -lcurl"
    grep -q BLINK_USE_SQLITE "$1" && link_flags="$link_flags -lsqlite3"
    child cc -o "$2" "$1" -I bootstrap $link_flags
  }
fi
if ! cc_ok "$fmt_c" "$fmt_bin" || ! cc_ok "$orig_c" "$orig_bin"; then
  check_limit
  cleanup
  echo "FAIL (cc) ${name}"
  exit 1
fi

# outcome <binary>: the exit status plus each test's verdict and the summary
# line, colour stripped. Other output names the source file and its line
# numbers, which formatting changes by design. A file with no test blocks
# keeps its whole stdout.
#
# The binary sits in the scratch dir, which has no lib/ beside it, so a test that
# compiles a program in process finds the prelude through BLINK_ROOT.
# Both runs share one scratch path, emptied between them: a test that prints a
# path under it must print the same text from the original and the formatted copy.
scratch=$(mktemp -d "${TMPDIR:-/tmp}/blink-test-XXXXXX")
outcome() {
  rm -rf "$scratch" && mkdir -m 700 "$scratch"
  out=$(child env BLINK_TEST_SCRATCH_DIR="$scratch" BLINK_ROOT="$(pwd)" "$1" 2>/dev/null)
  rc=$?
  out=$(printf '%s\n' "$out" | sed 's/\x1b\[[0-9;]*m//g')
  if printf '%s\n' "$out" | grep -qE '^test .* \.\.\. '; then
    out=$(printf '%s\n' "$out" | grep -E '^test .* \.\.\. (ok|FAIL|PANIC|SKIP|skipped|xfail|XPASS)|^[0-9]+ passed, ')
  fi
  printf 'exit %s\n%s\n' "$rc" "$out"
}
orig_outcome=$(outcome "$orig_bin")
check_limit
fmt_outcome=$(outcome "$fmt_bin")
check_limit
rm -rf "$scratch"
cleanup
if [ "$orig_outcome" = "$fmt_outcome" ]; then
  echo "PASS sem_${name}"
else
  echo "FAIL (outcome differs) fmt_${name}"
  exit 1
fi
