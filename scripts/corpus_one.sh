#!/bin/bash
# Compile and run ONE tests/test_*.bl file in its own sandbox and write a
# one-line JSON record for it. scripts/corpus.sh drives this in parallel.
#
#   scripts/corpus_one.sh <test file> <compiler dir> <results dir> [pm]
#
# pm builds this row on the per-module path whatever mode the sweep runs in:
# BLINK_PER_MODULE=1 for the row's build and every build its test starts
# through the CLI, no compiler archive, and BLINK_JOBS from
# CORPUS_PM_BLINK_JOBS. Its sandbox, logs and record are keyed <base>.pm, so
# the same file can also run as an ordinary row of the same sweep.
#
# <compiler dir> holds `blink`, `blinkc`, `libblink_std.a`, `libblink_std.h`
# (build/gen0 has them as symlinks into its installed layout; a flat build/
# works too). Only ABSOLUTE paths reach the compiler and the test binary,
# so this runner never depends on a `build/blink` that happens to sit in the
# caller's working directory.
#
# Why a sandbox per file: tests reach the compiler through the RELATIVE
# names `build/blink` and `build/blinkc` (src/compile_test_helpers.bl), and
# the compiler writes the objects of a native dependency under
# `build/native-cache`. Each file therefore runs with its own working directory
# that carries symlinks to the real `tests/`, `src/`, `lib/` and `blink.toml`,
# and a private `build/` whose `blink`/`blinkc` point at the compiler under
# test. A private `build/` also means a private object cache, so concurrent
# files cannot poison each other's cache entries. BLINK_ROOT is never exported:
# `blink` finds its archive from realpath(argv[0]).
#
# A test's own scratch files go under $TMPDIR (compile_test_helpers.scratch_root).
# Each file gets a TMPDIR of its own, removed when the file's row ends, so the
# sweep leaves nothing behind and two files never share a scratch directory.
#
# Pass rule: as in `blink test` directory mode, make a --debug test build, then
# run the binary, which runs the tests and never main. One exception, which
# `blink test` does not make: a file with a main and no test blocks is a plain
# program, so build it and run main.
# The build runs with the cc corpus.sh makes first on PATH, which drops the -g
# that --debug passes (see corpus.sh). The run keeps the real PATH, so a test
# that runs a build of its own gets what a user's `blink build --debug` gets.
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
# that skips has status "skipped", so it is not counted.
#
# The record also says whether the binary linked the prebuilt compiler
# archive ("compiler_archive"), read from the binary's own symbols rather than
# from how the build was asked for: a build that silently falls back to one
# unit must read false, so corpus_check.sh can hold the count to its floor.
#
# The record also says whether the build took the per-module path
# ("per_module"), read from the units directory that path leaves beside the
# binary, for the same reason: a per-module run whose build fell back to one
# unit must read false.
#
# Each build and run is a child of scripts/capped.sh --child: in a gate run
# it gets a memory and process cap of its own, and every way gets the time
# limit. A child that hits a cap fails as its own row, and the line capped.sh
# prints for the cap is the row's first error, so the row names the limit.
#
# Env:
#   CORPUS_BUILD_TIMEOUT  seconds per compile (default 900)
#   CORPUS_RUN_TIMEOUT    seconds per run (default 600)
#   CORPUS_PRELUDE_LIB    lib/ root the sandbox exposes as the prelude
#                         (default: the compiler's own lib/)
#   BLINK_COMPILER_ARCHIVE  the compiler archive corpus.sh built for the run;
#                         a build that imports the modules it holds links it
#   BLINK_PER_MODULE      1 in the per-module mode, for the row's build and
#                         every build its test starts through the CLI
#   CORPUS_PM_BLINK_JOBS  BLINK_JOBS for a pm row
set -u

file="$1"
comp_dir="$2"
results_dir="$3"
mode="${4:-}"

cd "$(dirname "$0")/.." || exit 2
root="$(pwd)"
case "$root" in *[[:space:]]*) echo "corpus_one: root path has whitespace: $root" >&2; exit 2;; esac

comp_dir="$(cd "$comp_dir" && pwd)"
results_dir="$(mkdir -p "$results_dir" && cd "$results_dir" && pwd)"
base="$(basename "$file" .bl)"
key="$base"
case "$mode" in
    "") ;;
    pm)
        key="$base.pm"
        export BLINK_PER_MODULE=1
        unset BLINK_COMPILER_ARCHIVE
        [ -n "${CORPUS_PM_BLINK_JOBS:-}" ] && export BLINK_JOBS="$CORPUS_PM_BLINK_JOBS"
        ;;
    *) echo "corpus_one: unknown mode $mode" >&2; exit 2 ;;
esac
build_timeout="${CORPUS_BUILD_TIMEOUT:-900}"
run_timeout="${CORPUS_RUN_TIMEOUT:-600}"

work="$root/build/corpus/work/$key"
log_dir="$root/build/corpus/logs"
mkdir -p "$log_dir" "$root/build/corpus/locks"
# A few tests write fixed paths outside their sandbox, under /tmp, so the two
# rows of one file must not run at once.
exec 9> "$root/build/corpus/locks/$base.lock"
flock 9
rm -rf "$work"
mkdir -p "$work/build/native-cache"
# Short, outside the sandbox: a daemon test puts a socket under its scratch dir, and a
# socket path has a length limit the sandbox path would exceed.
if [ -n "${BLINK_CORPUS_SWEEP_TMP:-}" ]; then
    scratch=$(mktemp -d "$BLINK_CORPUS_SWEEP_TMP/XXXXXX") || exit 2
else
    scratch=$(mktemp -d "${TMPDIR:-/tmp}/blink-corpus-XXXXXX") || exit 2
fi
trap 'rm -rf "$scratch"' EXIT
export TMPDIR="$scratch"
# corpus.sh builds each vendored native object once per sweep. The build skips
# its own compile when the object is no older than the source, so -p keeps the
# mtime; a link instead of a copy saves writing the object into every sandbox.
for o in "$root"/build/corpus/native/*.o; do
    [ -f "$o" ] || continue
    cp -pl "$o" "$work/build/native-cache/" 2>/dev/null || cp -p "$o" "$work/build/native-cache/"
done
# bootstrap/ is for tests that drive cc over the runtime headers directly, and
# the llms docs for tests that hold the doc examples to what the compiler does.
# The spec is not linked: it leads the compiler, so no test may hold the
# compiler to its text.
for d in tests src lib bootstrap llms.md llms-full.md blink.toml; do
    [ -e "$root/$d" ] && ln -s "$root/$d" "$work/$d"
done
# src/cli.bl embeds ../build/gc_unity.c; corpus.sh generates it once.
[ -e "$root/build/gc_unity.c" ] && ln -s "$root/build/gc_unity.c" "$work/build/gc_unity.c"
for f in blink blinkc libblink_std.a libblink_std.h skip_modules.txt runtime.h .archive-id monolith.c; do
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
# The unit's cc looks for libblink_std.h.gch beside the libblink_std.h it
# includes. corpus.sh keeps its PCH under a key of the headers it read, and a
# compiler that ships other headers finds none, so its row reads the header.
pch_key=$(./scripts/corpus_std_pch_key.sh "$comp_dir" | head -1)
pch="$root/build/corpus/pch/$pch_key/libblink_std.h.gch"
if [ -n "$pch_key" ] && [ -f "$pch" ]; then
    ln -s "$pch" "$work/build/libblink_std.h.gch"
fi
if [ ! -x "$work/build/blink" ]; then
    echo "corpus_one: no blink binary in $comp_dir" >&2
    exit 2
fi

blink_bin="$(readlink -f "$work/build/blink")"
ccdir="$root/build/corpus/cc"
if [ ! -x "$ccdir/cc" ]; then
    echo "corpus_one: no $ccdir/cc; scripts/corpus.sh makes it" >&2
    exit 2
fi
build_log="$log_dir/$key.build.log"
run_log="$log_dir/$key.run.log"
: > "$run_log"

has_tests=0
if grep -qE '^test "|^test\.failing\(' "$root/$file"; then has_tests=1; fi
has_main=0
if grep -q 'fn main(' "$root/$file"; then has_main=1; fi
has_known=0
if grep -qE '^test\.failing\(' "$root/$file"; then has_known=1; fi

json_str() { printf '%s' "$1" | jq -Rs .; }

# child <seconds> <command...>: run the command as a capped child.
child() {
    local limit=$1
    shift
    "$root/scripts/capped.sh" --child --timeout "$limit" "$@"
}

# limit_line <log>: the line capped.sh printed for a cap the child hit. The
# wrapper prints it after the child ends, so the last one is the wrapper's.
limit_line() {
    grep '^capped.sh: the child' "$1" | tail -1
}

# first_line <log> <ERE>: the first line that matches, skipping the notice
# capped.sh gives when no gate run set the way to cap a child.
first_line() {
    grep -vE '^capped.sh: (each child|no timeout)' "$1" | grep -m1 -E "$2"
}

# Only a test build keeps test blocks, and it runs them, never main. A file with a main and
# no test block gets a plain build. A file with no main gets a test build even when the grep
# above finds no test block, so a test the grep misses still runs.
build_cmd=__test-build
if [ "$has_main" -eq 1 ] && [ "$has_tests" -eq 0 ]; then build_cmd=build; fi

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
    export PATH="$ccdir:$PATH"
    child "$build_timeout" "$blink_bin" "$build_cmd" "tests/$base.bl" -o "build/$base" --debug
) > "$build_log" 2>&1
build_rc=$?
# The compiler archive's globals init fn: main calls it, so a binary that
# linked the archive always keeps it.
compiler_archive=false
if [ -f "$work/build/$base" ] && nm --defined-only "$work/build/$base" 2>/dev/null | grep -q ' __blink_init_compiler_globals$'; then
    compiler_archive=true
fi
per_module=false
[ -d "$work/build/$base.units" ] && per_module=true
build_limit=$(limit_line "$build_log")
if [[ "$build_limit" == *"ran past its time limit"* ]]; then
    status=timeout
    first_error=$build_limit
elif [ -z "$build_limit" ] && timed_out "$build_rc" "$start" "$build_timeout"; then
    status=timeout
    first_error="compile exceeded ${build_timeout}s"
elif [ "$build_rc" -ne 0 ] || [ ! -x "$work/build/$base" ]; then
    status=compile_fail
    first_error=$build_limit
    [ -z "$first_error" ] && first_error=$(first_line "$build_log" 'error\[|^error|ICE|I[0-9]{4}' || true)
    [ -z "$first_error" ] && first_error=$(first_line "$build_log" '[^[:space:]]' || true)
    [ -z "$first_error" ] && first_error="blink build exited $build_rc with no output"
else
    run_start=$(date +%s.%N)
    (
        cd "$work" || exit 2
        unset BLINK_ROOT BLINK_BIN
        export BLINK_CACHE_DIR=""
        child "$run_timeout" "./build/$base"
    ) > "$run_log" 2>&1
    run_rc=$?
    run_limit=$(limit_line "$run_log")
    if [[ "$run_limit" == *"ran past its time limit"* ]]; then
        status=timeout
        first_error=$run_limit
    elif [ -z "$run_limit" ] && timed_out "$run_rc" "$run_start" "$run_timeout"; then
        status=timeout
        first_error="run exceeded ${run_timeout}s"
    elif [ "$run_rc" -ne 0 ]; then
        status=run_fail
        first_error=$run_limit
        [ -z "$first_error" ] && first_error=$(first_line "$run_log" '\bFAIL\b|\bPANIC\b|panic|Segmentation|Aborted' || true)
        [ -z "$first_error" ] && first_error=$(grep -vE '^capped.sh: (each child|no timeout)' "$run_log" | grep -E 'error|assert' | grep -m1 -vE '\.\.\. .*ok' || true)
        [ -z "$first_error" ] && first_error=$(first_line "$run_log" '[^[:space:]]' || true)
        [ -z "$first_error" ] && first_error="test binary exited $run_rc with no output"
    else
        status=pass
    fi
fi
known=null
if [ "$status" = pass ]; then
    known=0
    if [ "$has_known" -eq 1 ]; then
        report="$log_dir/$key.report.json"
        (
            cd "$work" || exit 2
            unset BLINK_ROOT BLINK_BIN
            export BLINK_CACHE_DIR=""
            child "$run_timeout" "./build/$base" --test-json
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

printf '{"file":%s,"status":"%s","seconds":%s,"first_error_line":%s,"known_failures":%s,"compiler_archive":%s,"per_module":%s}\n' \
    "$(json_str "$file")" "$status" "$seconds" "$(json_str "$first_error")" "$known" "$compiler_archive" "$per_module" \
    > "$results_dir/$key.json"

# Keep the sandbox small: the binary and C file can be large.
rm -rf "$work/build/$base" "$work/build/$base.c" "$work/build/$base.units" "$work/build/obj-cache"
echo "$status $file"
