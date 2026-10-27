#!/bin/bash
# Proves scripts/corpus.sh reports a failing file through its exit code under
# --only, keeps exit 0 for a full run (corpus-check judges that), and that
# corpus_sample.sh still holds a subset to its floor instead of stopping on
# that exit code. Also proves each file's known-failure count (test.failing
# rows that still fail) comes from the test binary's report, and that
# corpus_check.sh holds the corpus to all-pass. Runs an unmodified copy of the
# scripts in a throwaway root with a fake compiler, so it takes seconds and
# never touches this checkout's build/corpus, which a real corpus run beside
# it may be writing.
set -u
cd "$(dirname "$0")/.."

for tool in parallel jq bc timeout; do
    command -v "$tool" >/dev/null 2>&1 || { echo "test_corpus: missing tool: $tool" >&2; exit 2; }
done

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
fail=0

R="$WORK/root"
mkdir -p "$R/scripts" "$R/tests" "$R/build" "$R/fakec/lib/std" "$R/src"
cp scripts/capped.sh scripts/corpus.sh scripts/corpus_one.sh scripts/default_jobs.sh scripts/inner_jobs.sh scripts/corpus_std_pch_key.sh scripts/corpus_sample.sh scripts/corpus_check.sh scripts/corpus_per_module_check.sh scripts/corpus_per_module_slice_entries.sh "$R/scripts/"
: > "$R/build/gc_unity.c"
# corpus.sh takes the compiler archive roots from the compiler binary's imports.
printf 'import std.fs\nimport lexer.{Lex}\nimport cg\n\nfn main() {}\n' > "$R/src/blinkc_main.bl"

# A marker in the test file picks the outcome, so each fixture file says what
# it expects.
cat > "$R/fakec/blink" <<'EOF'
#!/bin/bash
if [ "$1" = "__build-compiler-archive" ]; then
    [ -n "${SELFTEST_ARCHIVE_FAIL:-}" ] && { echo "error: fake compiler archive failure" >&2; exit 1; }
    dir="$2"; shift 2
    mkdir -p "$dir" && : > "$dir/libblink_compiler.a" && echo "$*" > "$dir/roots"
    # The archive's cc line passes -g as a --debug build does.
    printf 'int f(void) { return 0; }\n' > "$dir/unit.c"
    cc -pipe -g -O0 -DBLINK_DEBUG -c -o "$dir/unit.o" "$dir/unit.c" || exit 1
    readelf -S "$dir/unit.o" > "$dir/unit.sections"
    exit 0
fi
out=""; src=""; debug=0
while [ $# -gt 0 ]; do
    case "$1" in
        -o) out="$2"; shift 2 ;;
        --debug) debug=1; shift ;;
        build) shift ;;
        *) src="$1"; shift ;;
    esac
done
if grep -q SELFTEST_COMPILE_FAIL "$src"; then echo "error[E0000]: fake compile failure"; exit 1; fi
if grep -q SELFTEST_RUN_FAIL "$src"; then
    printf '#!/bin/sh\necho "FAIL: fake run failure"\nexit 1\n' > "$out"
elif grep -q SELFTEST_RUN_HANGS "$src"; then
    printf '#!/bin/sh\nexec sleep 30\n' > "$out"
elif grep -q SELFTEST_RUN_HOG "$src"; then
    # A command substitution holds its whole output in memory.
    printf '#!/bin/bash\nx=$(head -c 512M /dev/zero | tr "\\0" a)\necho "${#x}"\n' > "$out"
elif grep -q SELFTEST_BAD_REPORT "$src"; then
    printf '#!/bin/sh\ncase " $* " in *" --test-json "*) echo "{\\"results\\":[{\\"name\\":\\"a\\"b\\"}]}";; esac\nexit 0\n' > "$out"
elif n=$(grep -o 'SELFTEST_XFAIL=[0-9]*' "$src" | cut -d= -f2) && [ -n "$n" ]; then
    # A test body that prints lands between two records; SELFTEST_NOISY puts
    # such a line in the report.
    noise=""
    grep -q SELFTEST_NOISY "$src" && noise='FAIL: a probe line\n'
    rows='{"name":"plain","status":"passed"}'
    i=0
    while [ "$i" -lt "$n" ]; do
        rows="$rows$noise,{\"name\":\"known $i\",\"status\":\"passed\",\"expected_fail\":true,\"xfail_reason\":\"r\"}"
        i=$((i + 1))
    done
    printf '{"results":[%s],"summary":{"total":%d}}\n' "$rows" "$((n + 1))" > "$out.report"
    printf '#!/bin/sh\ncase " $* " in *" --test-json "*) cat "%s";; esac\nexit 0\n' "$out.report" > "$out"
elif grep -q SELFTEST_COMPILER_ARCHIVE "$src"; then
    # The build links the archive the run built, which it finds through the
    # env var the run exports.
    [ -f "${BLINK_COMPILER_ARCHIVE:-}/libblink_compiler.a" ] || { echo "error[E0000]: no compiler archive in the env"; exit 1; }
    # corpus_one.sh reads the archive's init fn from the binary's symbols, so
    # this fixture must be a real binary that defines it.
    printf 'void __blink_init_compiler_globals(void) {}\nint main(void) { __blink_init_compiler_globals(); return 0; }\n' > "$out.c"
    cc -o "$out" "$out.c" || exit 1
elif grep -q SELFTEST_STD_PCH "$src"; then
    # The prologue of a user unit and the cc line of `blink build --debug`. The
    # -H trace, kept beside the binary, names each header file cc read. A gated
    # unit defines a macro the header tests before the include, as a native dep
    # gate does.
    gate=""
    grep -q SELFTEST_STD_PCH_GATED "$src" && gate='#define BLINK_TEST_BUILD 1\n'
    printf "#define BLINK_USE_EXTERN_RUNTIME_STORAGE 1\n${gate}#include \"libblink_std.h\"\nint main(void) { return std_marker() - STD_MARKER; }\n" > "$out.c"
    cc -pipe -g -O0 -DBLINK_DEBUG -H -o "$out" "$out.c" -I"$(dirname "$0")" -Wl,--gc-sections -lm -pthread 2> "$out.trace" || { cat "$out.trace"; exit 1; }
    cat "$out.trace"
elif grep -q SELFTEST_DEBUG_INFO "$src"; then
    # The cc line `blink build --debug` runs. The row deletes the binary when
    # it ends, so its section table is kept beside it.
    [ "$debug" = 1 ] || { echo "error[E0000]: built without --debug"; exit 1; }
    printf 'int main(void) { return 0; }\n' > "$out.c"
    cc -pipe -g -O0 -DBLINK_DEBUG -o "$out" "$out.c" || exit 1
    readelf -S "$out" > "$out.sections"
elif grep -q SELFTEST_ENV "$src"; then
    printf '#!/bin/sh\necho "${BLINK_JOBS:-unset} ${GC_MARKERS:-unset}" >> "$SELFTEST_ENV_OUT"\nexit 0\n' > "$out"
else
    printf '#!/bin/sh\nexit 0\n' > "$out"
fi
chmod +x "$out"
# A per-module build, blink's default, leaves its units beside the binary. A
# compiler archive in the env makes it fall back to one unit.
[ "${BLINK_PER_MODULE:-1}" != 0 ] && [ -z "${BLINK_COMPILER_ARCHIVE:-}" ] && mkdir -p "$out.units"
exit 0
EOF
cp "$R/fakec/blink" "$R/fakec/blinkc"
cat > "$R/fakec/libblink_std.h" <<'EOF'
#include "runtime.h"
#ifdef BLINK_TEST_BUILD
#define STD_MARKER 1
#else
#define STD_MARKER 0
#endif
static inline int std_marker(void) { return STD_MARKER + RT_ZERO; }
EOF
printf '#define RT_ZERO 0\n' > "$R/fakec/runtime.h"
chmod +x "$R/fakec/blink" "$R/fakec/blinkc"

echo '// passes' > "$R/tests/test_selftest_ok.bl"
echo '// SELFTEST_RUN_FAIL' > "$R/tests/test_selftest_run_fail.bl"
echo '// SELFTEST_COMPILE_FAIL' > "$R/tests/test_selftest_compile_fail.bl"

printf 'tests/test_selftest_ok.bl\n' > "$WORK/all_pass.txt"
printf 'tests/test_selftest_ok.bl\ntests/test_selftest_run_fail.bl\n' > "$WORK/run_fail.txt"
printf 'tests/test_selftest_ok.bl\ntests/test_selftest_compile_fail.bl\n' > "$WORK/compile_fail.txt"

run_corpus() {
    (cd "$R" && CORPUS_COMPILER=fakec CORPUS_JOBS=2 ./scripts/corpus.sh "$@") > "$WORK/out.log" 2>&1
}

expect() {
    name="$1"; want="$2"; got="$3"
    if [ "$got" -eq "$want" ]; then
        echo "PASS $name: exit $got"
    else
        echo "FAIL $name: want exit $want, got $got"
        sed 's/^/    /' "$WORK/out.log"
        fail=1
    fi
}

run_corpus --only "$WORK/all_pass.txt" --no-lint
expect "only-all-pass" 0 $?

run_corpus --only "$WORK/run_fail.txt" --no-lint
expect "only-run-fail" 1 $?
# The exit code must not stand in for the record: the JSON still says 1/2.
if [ "$(jq -r '"\(.passed)/\(.total)"' "$R/build/corpus_subset.json" 2>/dev/null)" != "1/2" ]; then
    echo "FAIL only-run-fail-json: corpus_subset.json does not record 1/2"
    fail=1
else
    echo "PASS only-run-fail-json: corpus_subset.json records 1/2"
fi

run_corpus --only "$WORK/compile_fail.txt" --no-lint
expect "only-compile-fail" 1 $?

# A full run's judge is corpus-check, so a failing file leaves the exit at 0.
# The fixture root has no lint script, so --no-lint keeps this about corpus.sh.
run_corpus --no-lint
expect "full-run-with-failure" 0 $?

# Instructions and CPU time come from perf stat. A fake perf pins the parse;
# a perf that is missing, denied or unreadable must leave the result and the
# exit code as they are, with the fields null.
cat > "$WORK/fake_perf" <<"FEOF"
#!/bin/bash
[ "${FAKE_PERF_MODE:-}" = deny ] && exit 255
out=/dev/null
while [ $# -gt 0 ]; do
    case "$1" in
        -o) out="$2"; shift 2 ;;
        --) shift; break ;;
        *) shift ;;
    esac
done
if [ "${FAKE_PERF_MODE:-}" = uncounted ]; then
    printf "<not counted>,,instructions:u,0,0.00,,\n<not supported>,msec,task-clock:u,0,0.00,,\n" > "$out"
else
    printf "# started on now\n\n2500000000,,instructions:u,1,100.00,,\n4500.50,msec,task-clock:u,1,100.00,,\n" > "$out"
fi
"$@"
FEOF
chmod +x "$WORK/fake_perf"
perf_case() {
    name="$1"; mode="$2"; perf="$3"; ins="$4"; cpu="$5"; note="$6"
    (cd "$R" && PERF="$perf" FAKE_PERF_MODE="$mode" CORPUS_COMPILER=fakec CORPUS_JOBS=2 ./scripts/corpus.sh --only "$WORK/run_fail.txt" --no-lint) > "$WORK/out.log" 2>&1
    got=$?
    gi=$(jq -c .instructions_u "$R/build/corpus_subset.json" 2>/dev/null)
    gc=$(jq -c .cpu_seconds "$R/build/corpus_subset.json" 2>/dev/null)
    gp=$(jq -r "\"\(.passed)/\(.total)\"" "$R/build/corpus_subset.json" 2>/dev/null)
    if [ "$got" -eq 1 ] && [ "$gp" = "1/2" ] && [ "$gi" = "$ins" ] && [ "$gc" = "$cpu" ] \
            && grep -qF "passed in" "$WORK/out.log" && grep -qF "($note)" "$WORK/out.log"; then
        echo "PASS perf-$name: exit $got, instructions_u $gi, cpu_seconds $gc"
    else
        echo "FAIL perf-$name: exit $got, passed $gp, instructions_u $gi, cpu_seconds $gc"
        sed "s/^/    /" "$WORK/out.log"
        fail=1
    fi
}
perf_case parsed ok "$WORK/fake_perf" 2500000000 4.50 "cpu 4.50s, 2.50 G instructions"
perf_case missing ok "$WORK/no_such_perf" null null "perf n/a"
perf_case denied deny "$WORK/fake_perf" null null "perf n/a"
perf_case unreadable uncounted "$WORK/fake_perf" null null "perf n/a"

(cd "$R" && CORPUS_COMPILER=missing ./scripts/corpus.sh --only "$WORK/all_pass.txt" --no-lint) > "$WORK/out.log" 2>&1
expect "no-compiler" 2 $?

# corpus_sample.sh runs under set -e. A failing file at the floor must reach
# the floor check and pass, not stop on the subset's exit code.
{ echo '# floor: 1'; cat "$WORK/run_fail.txt"; } > "$WORK/sample_at_floor.txt"
(cd "$R" && CORPUS_COMPILER=fakec CORPUS_JOBS=2 ./scripts/corpus_sample.sh "$WORK/sample_at_floor.txt") > "$WORK/out.log" 2>&1
expect "sample-at-floor" 0 $?
{ echo '# floor: 2'; cat "$WORK/run_fail.txt"; } > "$WORK/sample_below_floor.txt"
(cd "$R" && CORPUS_COMPILER=fakec CORPUS_JOBS=2 ./scripts/corpus_sample.sh "$WORK/sample_below_floor.txt") > "$WORK/out.log" 2>&1
expect "sample-below-floor" 1 $?
# Callers accept exit 1 alone; a runner error (exit 2) must still fail them.
(cd "$R" && CORPUS_COMPILER=missing ./scripts/corpus_sample.sh "$WORK/sample_at_floor.txt") > "$WORK/out.log" 2>&1
got=$?
if [ "$got" -eq 0 ]; then
    echo "FAIL sample-runner-error: corpus_sample.sh passed on a runner error"
    sed 's/^/    /' "$WORK/out.log"
    fail=1
else
    echo "PASS sample-runner-error: exit $got"
fi

# Known failures. A test.failing row that still fails reads as a pass, so the
# record carries the count from the binary's --test-json report.
xfail_src() { printf '// SELFTEST_XFAIL=%s\ntest.failing("r") "row" {\n}\n' "$1"; }
xfail_src 2 > "$R/tests/test_selftest_xfail.bl"
{ echo '// SELFTEST_NOISY'; xfail_src 3; } > "$R/tests/test_selftest_xfail_noisy.bl"
printf '// SELFTEST_BAD_REPORT\ntest.failing("r") "row" {\n}\n' > "$R/tests/test_selftest_bad_report.bl"
printf 'tests/test_selftest_ok.bl\ntests/test_selftest_xfail.bl\ntests/test_selftest_xfail_noisy.bl\ntests/test_selftest_bad_report.bl\n' > "$WORK/xfail.txt"
run_corpus --only "$WORK/xfail.txt" --no-lint
expect "only-xfail" 0 $?
kf() { jq -r --arg f "$1" '.files[] | select(.file == $f) | .known_failures' "$R/build/corpus_subset.json" 2>/dev/null; }
for row in "tests/test_selftest_ok.bl 0" "tests/test_selftest_xfail.bl 2" "tests/test_selftest_xfail_noisy.bl null" "tests/test_selftest_bad_report.bl null"; do
    set -- $row
    if [ "$(kf "$1")" = "$2" ]; then
        echo "PASS known-failures $1: $2"
    else
        echo "FAIL known-failures $1: want $2, got '$(kf "$1")'"
        fail=1
    fi
done
if grep -q '^corpus: known failures 2 in 1 file(s), 2 unreadable report(s)$' "$WORK/out.log"; then
    echo "PASS known-failures-summary"
else
    echo "FAIL known-failures-summary: no summary line with the count"
    sed 's/^/    /' "$WORK/out.log"
    fail=1
fi

# Each record says whether the binary linked the compiler archive, read from
# the binary itself, and the summary counts them.
echo '// SELFTEST_COMPILER_ARCHIVE' > "$R/tests/test_selftest_compiler_archive.bl"
printf 'tests/test_selftest_ok.bl\ntests/test_selftest_compiler_archive.bl\ntests/test_selftest_compile_fail.bl\n' > "$WORK/archive.txt"
run_corpus --only "$WORK/archive.txt" --no-lint
ca() { jq -r --arg f "$1" '.files[] | select(.file == $f) | .compiler_archive' "$R/build/corpus_subset.json" 2>/dev/null; }
for row in "tests/test_selftest_ok.bl false" "tests/test_selftest_compiler_archive.bl true" "tests/test_selftest_compile_fail.bl false"; do
    set -- $row
    if [ "$(ca "$1")" = "$2" ]; then
        echo "PASS compiler-archive $1: $2"
    else
        echo "FAIL compiler-archive $1: want $2, got '$(ca "$1")'"
        fail=1
    fi
done
if grep -q '^compiler-archive: linked 1 files$' "$WORK/out.log" && [ "$(jq -r .compiler_archive_linked "$R/build/corpus_subset.json")" = 1 ]; then
    echo "PASS compiler-archive-summary"
else
    echo "FAIL compiler-archive-summary: no summary line or JSON count of 1"
    sed 's/^/    /' "$WORK/out.log"
    fail=1
fi

# A row still builds with --debug, for debug_assert, but neither its binary
# nor the compiler archive carries debug info: nothing in the corpus reads it,
# and it costs cc and link time.
echo '// SELFTEST_DEBUG_INFO' > "$R/tests/test_selftest_debug_info.bl"
printf 'tests/test_selftest_debug_info.bl\n' > "$WORK/debug_info.txt"
run_corpus --only "$WORK/debug_info.txt" --no-lint
expect "debug-build" 0 $?
sections="$R/build/corpus/work/test_selftest_debug_info/build/test_selftest_debug_info.sections"
if [ ! -s "$sections" ]; then
    echo "FAIL debug-build-no-debug-info: no section table at $sections"
    fail=1
elif grep -q '\.debug_info' "$sections"; then
    echo "FAIL debug-build-no-debug-info: the row binary has a .debug_info section"
    fail=1
else
    echo "PASS debug-build-no-debug-info"
fi
sections="$R/build/corpus/compiler_archive/unit.sections"
if [ ! -s "$sections" ]; then
    echo "FAIL compiler-archive-no-debug-info: no section table at $sections"
    fail=1
elif grep -q '\.debug_info' "$sections"; then
    echo "FAIL compiler-archive-no-debug-info: the archive object has a .debug_info section"
    fail=1
else
    echo "PASS compiler-archive-no-debug-info"
fi

# Each row's unit includes the stdlib archive header first, so the run
# precompiles it once and the row's cc reads the PCH in its place.
printf '// SELFTEST_STD_PCH\n' > "$R/tests/test_selftest_std_pch.bl"
printf '// SELFTEST_STD_PCH SELFTEST_STD_PCH_GATED\n' > "$R/tests/test_selftest_std_pch_gated.bl"
printf 'tests/test_selftest_std_pch.bl\ntests/test_selftest_std_pch_gated.bl\n' > "$WORK/std_pch.txt"
pch_trace="$R/build/corpus/work/test_selftest_std_pch/build/test_selftest_std_pch.trace"
pch_used() { head -1 "$pch_trace" 2>/dev/null | grep -q '^! .*/libblink_std\.h\.gch$'; }
# run_pch_row <label> <why>: one row through corpus_one.sh alone, which must
# pass without reading a PCH.
run_pch_row() {
    (cd "$R" && ./scripts/corpus_one.sh tests/test_selftest_std_pch.bl fakec build/corpus/results) > "$WORK/out.log" 2>&1
    if [ "$(jq -r .status "$R/build/corpus/results/test_selftest_std_pch.json")" = pass ] && [ -s "$pch_trace" ] && ! pch_used; then
        echo "PASS $1"
    else
        echo "FAIL $1: $2"
        sed 's/^/    /' "$WORK/out.log" "$pch_trace"
        fail=1
    fi
}
run_corpus --only "$WORK/std_pch.txt" --no-lint
expect "std-pch-build" 0 $?
if pch_used; then
    echo "PASS std-pch-used"
else
    echo "FAIL std-pch-used: the row did not read a PCH of libblink_std.h"
    sed 's/^/    /' "$pch_trace" 2>/dev/null | head -5
    fail=1
fi
# gcc drops a PCH whose pre-include macros differ and reads the header; the
# corpus cc warns, so the row's log says why.
if grep -q 'libblink_std\.h\.gch.*not used because' "$R/build/corpus/logs/test_selftest_std_pch_gated.build.log"; then
    echo "PASS std-pch-rejected-warns"
else
    echo "FAIL std-pch-rejected-warns: no -Winvalid-pch line in the gated row log"
    sed 's/^/    /' "$R/build/corpus/logs/test_selftest_std_pch_gated.build.log"
    fail=1
fi
# gcc never compares a PCH with the headers it was built from, so a row whose
# compiler ships another libblink_std.h or runtime.h must not get the run's PCH.
cp "$R/fakec/libblink_std.h" "$WORK/std.h.orig"
cp "$R/fakec/runtime.h" "$WORK/runtime.h.orig"
printf 'static inline int std_other(void) { return 0; }\n' >> "$R/fakec/libblink_std.h"
run_pch_row "std-pch-other-header" "the row used a PCH of another libblink_std.h, or failed"
cp "$WORK/std.h.orig" "$R/fakec/libblink_std.h"
printf '#define RT_ZERO (0)\n' > "$R/fakec/runtime.h"
run_pch_row "std-pch-other-runtime" "the row used a PCH of another runtime.h, or failed"
cp "$WORK/runtime.h.orig" "$R/fakec/runtime.h"
rm -rf "$R/build/corpus/pch"
run_pch_row "std-pch-missing" "the row failed with no PCH"

# The run builds the compiler archive from the compiler binary's imports and
# the codegen test helpers, and stops when it cannot.
roots="$(cat "$R/build/corpus/compiler_archive/roots" 2>/dev/null)"
if [ "$roots" = "cg lexer cg_test_helpers lower_test_helpers cname_test_helpers" ]; then
    echo "PASS compiler-archive-roots"
else
    echo "FAIL compiler-archive-roots: got '$roots'"
    fail=1
fi
(cd "$R" && SELFTEST_ARCHIVE_FAIL=1 CORPUS_COMPILER=fakec CORPUS_JOBS=2 ./scripts/corpus.sh --only "$WORK/all_pass.txt" --no-lint) > "$WORK/out.log" 2>&1
expect "compiler-archive-build-fails" 2 $?
if grep -q "fake compiler archive failure" "$WORK/out.log"; then
    echo "PASS compiler-archive-build-fails-says-why"
else
    echo "FAIL compiler-archive-build-fails-says-why: the archive's error is not in the output"
    sed 's/^/    /' "$WORK/out.log"
    fail=1
fi

# A run told to skip the archive builds none and exports no path to one.
(cd "$R" && rm -rf build/corpus/compiler_archive && SELFTEST_ARCHIVE_FAIL=1 CORPUS_COMPILER_ARCHIVE=0 BLINK_COMPILER_ARCHIVE=/nonexistent \
    CORPUS_COMPILER=fakec CORPUS_JOBS=2 ./scripts/corpus.sh --only "$WORK/archive.txt" --no-lint) > "$WORK/out.log" 2>&1
if [ ! -e "$R/build/corpus/compiler_archive" ] && [ "$(ca tests/test_selftest_compiler_archive.bl)" = false ] \
        && [ "$(ca tests/test_selftest_ok.bl)" = false ]; then
    echo "PASS compiler-archive-off"
else
    echo "FAIL compiler-archive-off: the run built or linked a compiler archive"
    sed 's/^/    /' "$WORK/out.log"
    fail=1
fi

# The per-module mode: every build takes the per-module path, with no compiler
# archive, into its own result file, and each record says whether its build
# left units. The default mode builds one unit even when the caller's env asks
# for units.
pmr() { jq -r --arg f "$1" '.files[] | select(.file == $f) | .per_module' "$R/build/corpus_per_module_subset.json" 2>/dev/null; }
(cd "$R" && rm -rf build/corpus/compiler_archive build/corpus_per_module_subset.json && SELFTEST_ARCHIVE_FAIL=1 CORPUS_PER_MODULE=1 \
    CORPUS_COMPILER=fakec CORPUS_JOBS=2 ./scripts/corpus.sh --only "$WORK/compile_fail.txt" --no-lint) > "$WORK/out.log" 2>&1
expect "per-module-run" 1 $?
if [ ! -e "$R/build/corpus/compiler_archive" ] && [ "$(jq -r .per_module "$R/build/corpus_per_module_subset.json")" = true ] \
        && [ "$(pmr tests/test_selftest_ok.bl)" = true ] && [ "$(pmr tests/test_selftest_compile_fail.bl)" = false ] \
        && [ "$(jq -r .per_module_built "$R/build/corpus_per_module_subset.json")" = 1 ] \
        && grep -q '^per-module: built 1 files in units$' "$WORK/out.log"; then
    echo "PASS per-module-records"
else
    echo "FAIL per-module-records: no per-module result file, a wrong per_module flag, or an archive was built"
    sed 's/^/    /' "$WORK/out.log"
    fail=1
fi
(cd "$R" && BLINK_PER_MODULE=1 CORPUS_COMPILER=fakec CORPUS_JOBS=2 ./scripts/corpus.sh --only "$WORK/all_pass.txt" --no-lint) > "$WORK/out.log" 2>&1
if [ "$(jq -r '.files[0].per_module' "$R/build/corpus_subset.json")" = false ] && [ "$(jq -r .per_module "$R/build/corpus_subset.json")" = false ]; then
    echo "PASS default-mode-ignores-caller-per-module-env"
else
    echo "FAIL default-mode-ignores-caller-per-module-env: the default mode built units"
    sed 's/^/    /' "$WORK/out.log"
    fail=1
fi
(cd "$R" && env -u BLINK_PER_MODULE CORPUS_COMPILER_ARCHIVE=0 CORPUS_COMPILER=fakec CORPUS_JOBS=2 ./scripts/corpus.sh --only "$WORK/all_pass.txt" --no-lint) > "$WORK/out.log" 2>&1
if [ "$(jq -r '.files[0].per_module' "$R/build/corpus_subset.json")" = false ] && [ "$(jq -r .per_module "$R/build/corpus_subset.json")" = false ]; then
    echo "PASS default-mode-without-archive-builds-one-unit"
else
    echo "FAIL default-mode-without-archive-builds-one-unit: the default mode built units"
    sed 's/^/    /' "$WORK/out.log"
    fail=1
fi
# A test binary that runs its own per-module build would start one cc per CPU
# in each of the sweep's workers, and Boehm one marker per CPU: every row, in
# each mode, gets its share of the worker budget and one marker.
echo '// SELFTEST_ENV' > "$R/tests/test_selftest_env.bl"
printf 'tests/test_selftest_env.bl\n' > "$WORK/env.txt"
# 64 open CPUs and a 12G gate at 2G a worker give a budget of 6, so each of 2
# workers gets 3; a share taken from the CPUs alone would be 32. A caller's
# BLINK_JOBS of 24 must not raise it.
mkdir -p "$WORK/cpus"
printf '#!/bin/sh\necho 64\n' > "$WORK/cpus/nproc"
chmod +x "$WORK/cpus/nproc"
want_jobs=3
# <name> <CORPUS_PER_MODULE> <want> [corpus.sh args]: the slice run has a
# plain row and a per-module row of the same file.
for run in "plain 0 1" "per-module 1 1" "slice 0 2 --per-module-slice $WORK/env.txt"; do
    set -- $run
    name=$1 pm=$2 rows=$3
    shift 3
    : > "$WORK/env.out"
    (cd "$R" && env -u GC_MARKERS PATH="$WORK/cpus:$PATH" BLINK_JOBS=24 BLINK_GATE_MEMORY_MAX=12G \
        BLINK_GATE_WORKER_MEMORY=2G SELFTEST_ENV_OUT="$WORK/env.out" CORPUS_PER_MODULE=$pm \
        CORPUS_COMPILER=fakec CORPUS_JOBS=2 ./scripts/corpus.sh --only "$WORK/env.txt" --no-lint "$@") > "$WORK/out.log" 2>&1
    want_env=$(for _ in $(seq "$rows"); do echo "$want_jobs 1"; done)
    got_env=$(cat "$WORK/env.out")
    if [ "$got_env" = "$want_env" ]; then
        echo "PASS row-gets-worker-budget ($name)"
    else
        echo "FAIL row-gets-worker-budget ($name): the test binaries saw [$got_env], want [$want_env]"
        sed 's/^/    /' "$WORK/out.log"
        fail=1
    fi
done
(cd "$R" && CORPUS_PER_MODULE=yes CORPUS_COMPILER=fakec ./scripts/corpus.sh --only "$WORK/all_pass.txt" --no-lint) > "$WORK/out.log" 2>&1
expect "per-module-bad-value" 2 $?

# --per-module-slice runs each listed file a second time, on the per-module
# path, in the same sweep: the main rows stay one unit and link the archive,
# the slice rows build in units with no archive, and each goes to its own JSON.
printf '# fixture slice\ntests/test_selftest_ok.bl\ntests/test_selftest_run_fail.bl  # manual: a marked line still runs\n# exclude tests/test_selftest_compile_fail.bl: an exclude line runs nothing\n' > "$WORK/slice.txt"
echo '// SELFTEST_COMPILER_ARCHIVE' > "$R/tests/test_selftest_slice_archive.bl"
printf 'tests/test_selftest_ok.bl\ntests/test_selftest_slice_archive.bl\n' > "$WORK/slice_main.txt"
printf 'tests/test_selftest_slice_archive.bl\n' >> "$WORK/slice.txt"
rm -f "$R/build/corpus_per_module_slice.json"
run_corpus --only "$WORK/slice_main.txt" --no-lint --per-module-slice "$WORK/slice.txt"
got=$?
main_pm=$(jq -c '[.files[] | [.file, .status, .per_module, .compiler_archive]]' "$R/build/corpus_subset.json" 2>/dev/null)
slice_rows=$(jq -c '[.files[] | [.file, .status, .per_module]]' "$R/build/corpus_per_module_slice.json" 2>/dev/null)
if [ "$got" -eq 0 ] \
        && [ "$main_pm" = '[["tests/test_selftest_ok.bl","pass",false,false],["tests/test_selftest_slice_archive.bl","pass",false,true]]' ] \
        && [ "$slice_rows" = '[["tests/test_selftest_ok.bl","pass",true],["tests/test_selftest_run_fail.bl","run_fail",true],["tests/test_selftest_slice_archive.bl","compile_fail",false]]' ] \
        && [ "$(jq -r .per_module "$R/build/corpus_per_module_slice.json")" = true ] \
        && grep -q '^per-module slice: 1/3 passed, 2 built in units -> build/corpus_per_module_slice.json$' "$WORK/out.log"; then
    echo "PASS slice-rows: exit 0, main rows one unit, slice rows per-module with no archive"
else
    echo "FAIL slice-rows: exit $got, main $main_pm, slice $slice_rows"
    sed 's/^/    /' "$WORK/out.log"
    fail=1
fi
(cd "$R" && CORPUS_PER_MODULE=1 CORPUS_COMPILER=fakec CORPUS_JOBS=2 ./scripts/corpus.sh --only "$WORK/all_pass.txt" --per-module-slice "$WORK/slice.txt") > "$WORK/out.log" 2>&1
expect "slice-in-per-module-mode" 2 $?
run_corpus --only "$WORK/all_pass.txt" --no-lint --per-module-slice "$WORK/no_such_slice.txt"
expect "slice-list-missing" 2 $?

# corpus_check.sh on hand-written result files. The fixture root holds one
# stub tests/test_check_N.bl per record, so the total can match the tests on
# disk. The fixtures above sit in the same tests/ directory, so the check runs
# in its own root.
C="$WORK/checkroot"
mkdir -p "$C/scripts" "$C/tests"
cp scripts/corpus_check.sh "$C/scripts/"
floor() { printf '# fixture floor\n%s\n' "$1" > "$C/scripts/corpus_compiler_archive_floor.txt"; }
floor 0
stubs() { # <n>: leave exactly n test files in the check root
    rm -f "$C"/tests/test_*.bl
    i=1
    while [ "$i" -le "$1" ]; do : > "$C/tests/test_check_$i.bl"; i=$((i + 1)); done
}
rec() { printf '{"file":"%s","status":"%s","known_failures":%s,"compiler_archive":%s}' "$1" "$2" "$3" "${4:-false}"; }
corpus_file() { # <out> <record>...
    out="$1"; shift
    printf '%s\n' "$@" | jq -s '{total: length, passed: (map(select(.status == "pass")) | length), files: .}' > "$out"
}
run_check() {
    (cd "$C" && CORPUS_JSON="$WORK/now.json" ./scripts/corpus_check.sh) > "$WORK/out.log" 2>&1
}
names() { # <label> <file>: the failure line names the file
    if grep -q "^  $2" "$WORK/out.log"; then
        echo "PASS $1"
    else
        echo "FAIL $1: the failure does not name $2"
        sed 's/^/    /' "$WORK/out.log"
        fail=1
    fi
}

stubs 2
corpus_file "$WORK/now.json" "$(rec tests/test_check_1.bl pass 1)" "$(rec tests/test_check_2.bl pass 0)"
run_check; expect "check-all-pass" 0 $?
if grep -q '^corpus-check: ok 2/2 passed$' "$WORK/out.log" && grep -q 'known failures.*: 1$' "$WORK/out.log"; then
    echo "PASS check-all-pass-summary"
else
    echo "FAIL check-all-pass-summary: no ok line or known-failure count"
    sed 's/^/    /' "$WORK/out.log"
    fail=1
fi
corpus_file "$WORK/now.json" "$(rec tests/test_check_1.bl pass 0)" "$(rec tests/test_check_2.bl run_fail null)"
run_check; expect "check-run-fail" 1 $?
names "check-run-fail-names-file" "tests/test_check_2.bl: run_fail"
corpus_file "$WORK/now.json" "$(rec tests/test_check_1.bl pass 0)"
run_check; expect "check-total-below-tests" 1 $?
if grep -q 'covers 1 file(s); tests/ holds 2' "$WORK/out.log"; then
    echo "PASS check-total-names-both-numbers"
else
    echo "FAIL check-total-names-both-numbers"
    sed 's/^/    /' "$WORK/out.log"
    fail=1
fi
stubs 1
corpus_file "$WORK/now.json" "$(rec tests/test_check_1.bl pass 0)" "$(rec tests/test_check_2.bl pass 0)"
run_check; expect "check-total-above-tests" 1 $?
stubs 0
printf '{"total":0,"passed":0,"files":[]}\n' > "$WORK/now.json"
run_check; expect "check-total-zero" 1 $?
stubs 2
corpus_file "$WORK/now.json" "$(rec tests/test_check_1.bl pass null)" "$(rec tests/test_check_2.bl pass 0)"
run_check; expect "check-known-unreadable" 1 $?
names "check-known-unreadable-names-file" "tests/test_check_1.bl$"
grep -q 'printed to stdout' "$WORK/out.log" || { echo "FAIL check-known-unreadable-cause: no cause given"; fail=1; }
echo '{"total":' > "$WORK/now.json"
run_check; expect "check-malformed" 2 $?

# The compiler-archive floor.
corpus_file "$WORK/now.json" "$(rec tests/test_check_1.bl pass 0 true)" "$(rec tests/test_check_2.bl pass 0 false)"
floor 1
run_check; expect "check-archive-at-floor" 0 $?
grep -q '^corpus-check: compiler archive linked 1 file(s), floor 1$' "$WORK/out.log" || { echo "FAIL check-archive-count-line: no count line"; fail=1; }
floor 2
run_check; expect "check-archive-below-floor" 1 $?
grep -q 'below the floor of 2' "$WORK/out.log" || { echo "FAIL check-archive-below-floor-cause: no cause given"; fail=1; }
floor 0
corpus_file "$WORK/now.json" "$(rec tests/test_check_1.bl pass 0)" '{"file":"tests/test_check_2.bl","status":"pass","known_failures":0}'
run_check; expect "check-archive-unflagged" 1 $?
names "check-archive-unflagged-names-file" "tests/test_check_2.bl$"
corpus_file "$WORK/now.json" "$(rec tests/test_check_1.bl pass 0)" "$(rec tests/test_check_2.bl pass 0)"
floor x
run_check; expect "check-archive-floor-unreadable" 2 $?
floor 0

# corpus_per_module_check.sh: every file passes in units, except the listed
# known failures, which must still fail.
cp scripts/corpus_per_module_check.sh scripts/corpus_per_module_slice_entries.sh scripts/corpus_per_module_slice_drift.sh "$C/scripts/"
known() { printf '# fixture\n%s' "$1" > "$C/scripts/corpus_per_module_known_failures.txt"; }
pmrec() { printf '{"file":"%s","status":"%s","known_failures":%s,"compiler_archive":false,"per_module":%s,"first_error_line":"e"}' "$1" "$2" "$3" "$4"; }
pm_file() {
    printf '%s\n' "$@" | jq -s '{per_module: true, total: length, passed: (map(select(.status == "pass")) | length),
        per_module_built: (map(select(.per_module == true)) | length), files: .}' > "$WORK/now.json"
}
run_pm_check() {
    (cd "$C" && CORPUS_JSON="$WORK/now.json" ./scripts/corpus_per_module_check.sh) > "$WORK/out.log" 2>&1
}
stubs 2
known ""
pm_file "$(pmrec tests/test_check_1.bl pass 0 true)" "$(pmrec tests/test_check_2.bl pass 0 true)"
run_pm_check; expect "pm-check-all-pass" 0 $?
grep -q '^corpus-per-module-check: ok 2/2 passed, 0 known failure(s) still fail, 2 built in units$' "$WORK/out.log" \
    || { echo "FAIL pm-check-all-pass-summary"; sed 's/^/    /' "$WORK/out.log"; fail=1; }
pm_file "$(pmrec tests/test_check_1.bl pass 0 true)" "$(pmrec tests/test_check_2.bl compile_fail null false)"
run_pm_check; expect "pm-check-unlisted-failure" 1 $?
names "pm-check-unlisted-failure-names-file" "tests/test_check_2.bl: compile_fail"
known "tests/test_check_2.bl"
run_pm_check; expect "pm-check-listed-failure" 0 $?
pm_file "$(pmrec tests/test_check_1.bl pass 0 true)" "$(pmrec tests/test_check_2.bl pass 0 true)"
run_pm_check; expect "pm-check-listed-file-passes" 1 $?
names "pm-check-listed-file-passes-names-file" "tests/test_check_2.bl$"
known "tests/test_check_9.bl"
run_pm_check; expect "pm-check-listed-file-missing" 1 $?
names "pm-check-listed-file-missing-names-file" "tests/test_check_9.bl"
known ""
pm_file "$(pmrec tests/test_check_1.bl pass 0 true)" "$(pmrec tests/test_check_2.bl pass 0 false)"
run_pm_check; expect "pm-check-one-unit-pass" 1 $?
names "pm-check-one-unit-pass-names-file" "tests/test_check_2.bl$"
pm_file "$(pmrec tests/test_check_1.bl pass 0 true)"
run_pm_check; expect "pm-check-total-below-tests" 1 $?
pm_file "$(pmrec tests/test_check_1.bl pass 0 true)" "$(pmrec tests/test_check_2.bl pass null true)"
run_pm_check; expect "pm-check-known-unreadable" 1 $?
corpus_file "$WORK/now.json" "$(rec tests/test_check_1.bl pass 0)" "$(rec tests/test_check_2.bl pass 0)"
run_pm_check; expect "pm-check-default-mode-json" 2 $?

# --slice holds the files a list names to the same rules, in place of every
# test on disk, and holds the list itself to naming files that exist.
slice() { printf '# fixture slice\n%s' "$1" > "$WORK/slice.txt"; }
run_slice_check() {
    (cd "$C" && CORPUS_JSON="$WORK/now.json" ./scripts/corpus_per_module_check.sh --slice "$WORK/slice.txt") > "$WORK/out.log" 2>&1
}
stubs 3
known ""
slice "tests/test_check_1.bl
tests/test_check_2.bl
"
pm_file "$(pmrec tests/test_check_1.bl pass 0 true)" "$(pmrec tests/test_check_2.bl pass 0 true)"
run_slice_check; expect "slice-check-all-pass" 0 $?
grep -q "^corpus-per-module-check: ok (slice $WORK/slice.txt) 2/2 passed, 0 known failure(s) still fail, 2 built in units$" "$WORK/out.log" \
    || { echo "FAIL slice-check-all-pass-summary"; sed 's/^/    /' "$WORK/out.log"; fail=1; }
pm_file "$(pmrec tests/test_check_1.bl pass 0 true)" "$(pmrec tests/test_check_2.bl run_fail null true)"
run_slice_check; expect "slice-check-failing-row" 1 $?
names "slice-check-failing-row-names-file" "tests/test_check_2.bl: run_fail"
known "tests/test_check_2.bl"
run_slice_check; expect "slice-check-known-failure" 0 $?
known ""
pm_file "$(pmrec tests/test_check_1.bl pass 0 true)" "$(pmrec tests/test_check_2.bl pass 0 false)"
run_slice_check; expect "slice-check-one-unit-pass" 1 $?
names "slice-check-one-unit-pass-names-file" "tests/test_check_2.bl$"
pm_file "$(pmrec tests/test_check_1.bl pass 0 true)"
run_slice_check; expect "slice-check-listed-file-not-run" 1 $?
names "slice-check-listed-file-not-run-names-file" "tests/test_check_2.bl$"
pm_file "$(pmrec tests/test_check_1.bl pass 0 true)" "$(pmrec tests/test_check_2.bl pass 0 true)"
slice "tests/test_check_1.bl
tests/test_check_2.bl
tests/test_check_9.bl
"
run_slice_check; expect "slice-check-listed-file-missing" 1 $?
names "slice-check-listed-file-missing-names-file" "tests/test_check_9.bl$"
slice "tests/test_check_1.bl
tests/test_check_2.bl   # manual: picked by hand
# exclude tests/test_check_3.bl: a comment line, not an entry
"
run_slice_check; expect "slice-check-marked-lines" 0 $?
slice "
"
run_slice_check; expect "slice-check-empty-list" 1 $?
grep -q "names no test file" "$WORK/out.log" \
    || { echo "FAIL slice-check-empty-list-says-why"; sed 's/^/    /' "$WORK/out.log"; fail=1; }
rm -f "$WORK/slice.txt"
run_slice_check; expect "slice-check-no-list" 1 $?

# The drift check holds the list to what the selection rule picks now. The
# fixture stands in a file of picks for the rule (SLICE_PICKED).
picked() { printf '%s' "$1" > "$WORK/picked.txt"; }
run_drift() {
    (cd "$C" && SLICE_PICKED="$WORK/picked.txt" ./scripts/corpus_per_module_slice_drift.sh "$WORK/slice.txt") > "$WORK/out.log" 2>&1
}
stubs 4
picked "tests/test_check_1.bl
tests/test_check_2.bl
"
slice "tests/test_check_1.bl
tests/test_check_2.bl
tests/test_check_4.bl  # manual: picked by hand
"
run_drift; expect "drift-in-step" 0 $?
grep -q "^corpus-per-module-slice-drift: ok 2 picked by the rule, 1 by hand, 0 excluded$" "$WORK/out.log" \
    || { echo "FAIL drift-in-step-summary"; sed 's/^/    /' "$WORK/out.log"; fail=1; }
picked "tests/test_check_1.bl
tests/test_check_2.bl
tests/test_check_3.bl
"
run_drift; expect "drift-picked-not-listed" 1 $?
names "drift-picked-not-listed-names-file" "tests/test_check_3.bl$"
grep -q "scripts/corpus_per_module_slice_select.sh" "$WORK/out.log" \
    || { echo "FAIL drift-picked-not-listed-says-refresh"; sed 's/^/    /' "$WORK/out.log"; fail=1; }
slice "tests/test_check_1.bl
tests/test_check_2.bl
# exclude tests/test_check_3.bl: its slice row adds nothing
tests/test_check_4.bl  # manual: picked by hand
"
run_drift; expect "drift-excluded" 0 $?
grep -q "^corpus-per-module-slice-drift: ok 2 picked by the rule, 1 by hand, 1 excluded$" "$WORK/out.log" \
    || { echo "FAIL drift-excluded-summary"; sed 's/^/    /' "$WORK/out.log"; fail=1; }
slice "tests/test_check_1.bl
tests/test_check_2.bl
tests/test_check_3.bl
tests/test_check_4.bl
"
run_drift; expect "drift-unmarked-unpicked" 1 $?
names "drift-unmarked-unpicked-names-file" "tests/test_check_4.bl$"
picked "tests/test_check_1.bl
"
slice "tests/test_check_1.bl
# exclude tests/test_check_2.bl: the rule no longer picks it
"
run_drift; expect "drift-stale-exclude" 1 $?
names "drift-stale-exclude-names-file" "tests/test_check_2.bl$"
picked "tests/test_check_1.bl
tests/test_check_2.bl
"
slice "tests/test_check_1.bl
tests/test_check_2.bl
# exclude tests/test_check_2.bl: listed and excluded at once
"
run_drift; expect "drift-excluded-and-listed" 1 $?
names "drift-excluded-and-listed-names-file" "tests/test_check_2.bl$"
rm -f "$WORK/slice.txt"
run_drift; expect "drift-no-list" 1 $?

# A row that runs past its time limit, or that its child cap kills, fails as
# that one row, and its first error line names the limit.
echo '// SELFTEST_RUN_HANGS' > "$R/tests/test_selftest_run_hangs.bl"
printf 'tests/test_selftest_ok.bl\ntests/test_selftest_run_hangs.bl\n' > "$WORK/hangs.txt"
start=$EPOCHSECONDS
(cd "$R" && CORPUS_RUN_TIMEOUT=2 CORPUS_COMPILER=fakec CORPUS_JOBS=2 ./scripts/corpus.sh --only "$WORK/hangs.txt" --no-lint) > "$WORK/out.log" 2>&1
expect "run-time-limit" 1 $?
row=$(jq -r '.files[] | select(.file == "tests/test_selftest_run_hangs.bl") | "\(.status)|\(.first_error_line)"' "$R/build/corpus_subset.json" 2>/dev/null)
case "$row" in
    "timeout|capped.sh: the child ran past its time limit (2s)"*)
        if [ $((EPOCHSECONDS - start)) -lt 20 ]; then
            echo "PASS run-time-limit-row: $row"
        else
            echo "FAIL run-time-limit-row: the run took $((EPOCHSECONDS - start))s"
            fail=1
        fi
        ;;
    *) echo "FAIL run-time-limit-row: got [$row]"; sed 's/^/    /' "$WORK/out.log"; fail=1 ;;
esac
rm -f "$R/tests/test_selftest_run_hangs.bl"

# The memory case needs a cgroup per child, so it starts a gate run of its own.
if command -v systemd-run >/dev/null 2>&1 &&
    systemd-run --user --scope -q -p Delegate=yes -p MemoryMax=64M -p MemorySwapMax=0 -p TasksMax=64 -p OOMPolicy=continue true >/dev/null 2>&1; then
    echo '// SELFTEST_RUN_HOG' > "$R/tests/test_selftest_run_hog.bl"
    printf 'tests/test_selftest_ok.bl\ntests/test_selftest_run_hog.bl\n' > "$WORK/hog.txt"
    (cd "$R" && env -u BLINK_GATE_SCOPE -u BLINK_GATE_CAP -u BLINK_CHILD_CAP_MODE -u BLINK_CHILD_CGROUP -u BLINK_CHILD_CAPPED \
        BLINK_CHILD_MEMORY_MAX=64M BLINK_CHILD_SWAP_MAX=0 CORPUS_COMPILER=fakec CORPUS_JOBS=2 \
        timeout 120 ./scripts/capped.sh ./scripts/corpus.sh --only "$WORK/hog.txt" --no-lint) > "$WORK/out.log" 2>&1
    expect "run-memory-cap" 1 $?
    row=$(jq -r '.files[] | select(.file == "tests/test_selftest_run_hog.bl") | "\(.status)|\(.first_error_line)"' "$R/build/corpus_subset.json" 2>/dev/null)
    case "$row" in
        "run_fail|capped.sh: the child hit its memory cap (MemoryMax=64M)"*) echo "PASS run-memory-cap-row: $row" ;;
        *) echo "FAIL run-memory-cap-row: got [$row]"; sed 's/^/    /' "$WORK/out.log"; fail=1 ;;
    esac
    rm -f "$R/tests/test_selftest_run_hog.bl"
else
    echo "SKIP run-memory-cap: no systemd user scope with delegation on this machine"
fi

if [ "$fail" -ne 0 ]; then
    echo "test_corpus: FAILED"
    exit 1
fi
echo "test_corpus: all checks passed"
