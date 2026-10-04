#!/bin/bash
# Compile and run ONE tests/test_*.bl file in its own sandbox and write a
# one-line JSON record for it. scripts/corpus.sh drives this in parallel.
#
#   scripts/corpus_one.sh <test file> <compiler dir> <results dir>
#
# <compiler dir> holds `blink`, `blinkc`, `libblink_std.a`, `libblink_std.h`
# (build/gen0 has them as symlinks into its installed layout; a flat build/
# works too). Only ABSOLUTE paths reach the compiler and the test binary,
# so this runner never depends on a `build/blink` that happens to sit in the
# caller's working directory.
#
# Why a sandbox per file: tests reach the compiler through the RELATIVE
# names `build/blink` and `build/blinkc` (src/compile_test_helpers.bl), and
# many write scratch files under `.tmp/`. Each file therefore runs with its
# own working directory that carries symlinks to the real `tests/`, `src/`,
# `lib/` and `blink.toml`, a private `.tmp/`, and a private `build/` whose
# `blink`/`blinkc` point at the compiler under test. A private `build/` also
# means a private object cache, so concurrent files cannot poison each
# other's cache entries. BLINK_ROOT is never exported: `blink` finds its
# archive from realpath(argv[0]).
#
# Pass rule (same as `blink test` directory mode): build with --debug, then
# run the binary; a file with test blocks and a `fn main(` runs with --test.
# A file with no test blocks is a plain program: compile and run main.
#
# Known failures: a test.failing row that still fails counts as a pass, so a
# file whose only failing rows are known failures passes. The record carries
# their number as "known_failures", read from the binary's --test-json report
# (rows with expected_fail and status "passed"); corpus_check.sh prints
# the total. Only a passing file with a top-level test.failing row runs that
# second time; any other file has no such row, so its count is 0. The files
# that test test.failing itself hold their rows in source strings, not at top
# level, so they count 0 like any other file. A report
# that does not run or does not parse gives null, never 0. A test.failing row
# that skips does not carry expected_fail in the report, so it is not counted.
#
# Env:
#   CORPUS_BUILD_TIMEOUT  seconds per compile (default 900)
#   CORPUS_RUN_TIMEOUT    seconds per run (default 600)
#   CORPUS_PRELUDE_LIB    lib/ root the sandbox exposes as the prelude
#                         (default: the compiler's own lib/)
set -u

file="$1"
comp_dir="$2"
results_dir="$3"

cd "$(dirname "$0")/.." || exit 2
root="$(pwd)"
case "$root" in *[[:space:]]*) echo "corpus_one: root path has whitespace: $root" >&2; exit 2;; esac

comp_dir="$(cd "$comp_dir" && pwd)"
results_dir="$(mkdir -p "$results_dir" && cd "$results_dir" && pwd)"
base="$(basename "$file" .bl)"
build_timeout="${CORPUS_BUILD_TIMEOUT:-900}"
run_timeout="${CORPUS_RUN_TIMEOUT:-600}"

work="$root/build/corpus/work/$base"
log_dir="$root/build/corpus/logs"
mkdir -p "$log_dir"
rm -rf "$work"
mkdir -p "$work/build" "$work/.tmp"
# corpus.sh builds each vendored native object once per sweep. The build skips
# its own compile when the object is no older than the source, so -p keeps the
# mtime; a link instead of a copy saves writing the object into every sandbox.
for o in "$root"/build/corpus/native/*.o; do
    [ -f "$o" ] || continue
    cp -pl "$o" "$work/.tmp/" 2>/dev/null || cp -p "$o" "$work/.tmp/"
done
# bootstrap/ is for tests that drive cc over the runtime headers directly.
for d in tests src lib bootstrap blink.toml; do
    [ -e "$root/$d" ] && ln -s "$root/$d" "$work/$d"
done
# src/cli.bl embeds ../build/gc_unity.c; corpus.sh generates it once.
[ -e "$root/build/gc_unity.c" ] && ln -s "$root/build/gc_unity.c" "$work/build/gc_unity.c"
for f in blink blinkc libblink_std.a libblink_std.h skip_modules.txt runtime.h .archive-id; do
    if [ -e "$comp_dir/$f" ]; then
        ln -s "$(readlink -f "$comp_dir/$f")" "$work/build/$f"
    elif [ -e "$comp_dir/share/blink/$f" ]; then
        ln -s "$(readlink -f "$comp_dir/share/blink/$f")" "$work/build/$f"
    fi
done
# blinkc reads its stdlib from <dir of argv[0]>/lib/std, so the sandbox
# build/ needs a lib/ beside the blinkc symlink. A missing one stops the file
# instead of running it: a test binary that compiles a program in process
# resolves the prelude through the same path, and with no prelude it compiles
# nothing and its assertions hold over an empty program.
#
# Which lib/ is a choice the caller makes. The default is the compiler's own,
# which is what a corpus run wants: it measures a compiler against the stdlib
# that compiler ships. A suite whose probes compile programs in process wants
# the opposite — the worktree's lib/, because the probe is testing THIS tree's
# compiler sources and a pinned prelude would make this tree's stdlib changes
# invisible to it. CORPUS_PRELUDE_LIB names that root.
prelude_lib="${CORPUS_PRELUDE_LIB:-$comp_dir/lib}"
if [ ! -d "$prelude_lib/std" ]; then
    echo "corpus_one: no stdlib at $prelude_lib/std" >&2
    exit 2
fi
ln -s "$(readlink -f "$prelude_lib")" "$work/build/lib"
if [ ! -x "$work/build/blink" ]; then
    echo "corpus_one: no blink binary in $comp_dir" >&2
    exit 2
fi

blink_bin="$(readlink -f "$work/build/blink")"
build_log="$log_dir/$base.build.log"
run_log="$log_dir/$base.run.log"
: > "$run_log"

has_tests=0
if grep -qE '^test "|^test\.failing\(' "$root/$file"; then has_tests=1; fi
has_main=0
if grep -q 'fn main(' "$root/$file"; then has_main=1; fi
has_known=0
if grep -qE '^test\.failing\(' "$root/$file"; then has_known=1; fi

json_str() { printf '%s' "$1" | jq -Rs .; }

start=$(date +%s.%N)
status=""
first_error=""

# timed_out <rc> <phase start> <budget>: rc 124 is timeout's own deadline;
# rc 137 is a SIGKILL, which is the deadline only when the budget is spent.
# An OOM kill or a crash under load must stay a failure, not a timeout.
timed_out() {
    [ "$1" -eq 124 ] && return 0
    [ "$1" -eq 137 ] || return 1
    [ "$(echo "$(date +%s.%N) - $2 >= $3" | bc)" = 1 ]
}

(
    cd "$work" || exit 2
    unset BLINK_ROOT BLINK_BIN
    export BLINK_CACHE_DIR=""
    timeout -k 10 "$build_timeout" "$blink_bin" build "tests/$base.bl" -o "build/$base" --debug
) > "$build_log" 2>&1
build_rc=$?
if timed_out "$build_rc" "$start" "$build_timeout"; then
    status=timeout
    first_error="compile exceeded ${build_timeout}s"
elif [ "$build_rc" -ne 0 ] || [ ! -x "$work/build/$base" ]; then
    status=compile_fail
    first_error=$(grep -m1 -E 'error\[|^error|ICE|I[0-9]{4}' "$build_log" || true)
    [ -z "$first_error" ] && first_error=$(grep -m1 -v '^[[:space:]]*$' "$build_log" || true)
    [ -z "$first_error" ] && first_error="blink build exited $build_rc with no output"
else
    run_args=()
    if [ "$has_tests" -eq 1 ] && [ "$has_main" -eq 1 ]; then run_args=(--test); fi
    run_start=$(date +%s.%N)
    (
        cd "$work" || exit 2
        unset BLINK_ROOT BLINK_BIN
        export BLINK_CACHE_DIR=""
        timeout -k 10 "$run_timeout" "./build/$base" "${run_args[@]}"
    ) > "$run_log" 2>&1
    run_rc=$?
    if timed_out "$run_rc" "$run_start" "$run_timeout"; then
        status=timeout
        first_error="run exceeded ${run_timeout}s"
    elif [ "$run_rc" -ne 0 ]; then
        status=run_fail
        first_error=$(grep -m1 -E '\bFAIL\b|panic|Segmentation|Aborted' "$run_log" || true)
    [ -z "$first_error" ] && first_error=$(grep -E 'error|assert' "$run_log" | grep -m1 -vE '\.\.\. .*ok' || true)
        [ -z "$first_error" ] && first_error=$(grep -m1 -v '^[[:space:]]*$' "$run_log" || true)
        [ -z "$first_error" ] && first_error="test binary exited $run_rc with no output"
    else
        status=pass
    fi
fi
known=null
if [ "$status" = pass ]; then
    known=0
    if [ "$has_known" -eq 1 ]; then
        # A fresh .tmp, so a test that creates a scratch file and asserts it
        # is new behaves as it did on the first run.
        rm -rf "$work/.tmp" && mkdir -p "$work/.tmp"
        report="$log_dir/$base.report.json"
        (
            cd "$work" || exit 2
            unset BLINK_ROOT BLINK_BIN
            export BLINK_CACHE_DIR=""
            timeout -k 10 "$run_timeout" "./build/$base" "${run_args[@]}" --test-json
        ) > "$report" 2>/dev/null
        if [ $? -eq 0 ]; then
            known=$(jq -e '[.results[] | select(.expected_fail == true and .status == "passed")] | length' "$report" 2>/dev/null) || known=null
        else
            known=null
        fi
    fi
fi
end=$(date +%s.%N)
seconds=$(printf '%.2f' "$(echo "$end - $start" | bc)")

# ANSI color codes in the first error line make the JSON hard to read.
first_error=$(printf '%s' "$first_error" | sed 's/\x1b\[[0-9;]*m//g' | cut -c1-300)

printf '{"file":%s,"status":"%s","seconds":%s,"first_error_line":%s,"known_failures":%s}\n' \
    "$(json_str "$file")" "$status" "$seconds" "$(json_str "$first_error")" "$known" \
    > "$results_dir/$base.json"

# Keep the sandbox small: the binary and C file can be large.
rm -rf "$work/build/$base" "$work/build/$base.c" "$work/build/obj-cache"
echo "$status $file"
