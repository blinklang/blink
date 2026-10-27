#!/bin/bash
# Proves scripts/run_fmt_semantic.sh fails a file only when the formatted
# program behaves differently from the original: a test that fails on its own,
# or prints FAIL inside a passing run, is not a formatter bug. Also proves the
# test binary finds the prelude, which a probe suite needs to compile programs
# in process. Proves both scripts/run_fmt_semantic.sh and
# scripts/run_fmt_idempotent.sh fail a file the formatter cannot format, so a
# formatter abort never reads as a skip. Proves a test that names its own file
# keeps passing in the formatted copy. Proves a formatter or test binary that
# runs past the child time limit fails the file with the limit named, in all
# three fmt scripts. Runs unmodified copies of the scripts
# in a throwaway root with a fake compiler whose C output acts on markers in
# the source.
set -u
cd "$(dirname "$0")/.."

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
fail=0

R="$WORK/root"
mkdir -p "$R/scripts" "$R/tests" "$R/lib/std" "$R/fake"
mkdir -p "$R/tests/fmt"
cp scripts/capped.sh scripts/run_fmt_semantic.sh scripts/run_fmt_idempotent.sh scripts/run_fmt_golden.sh "$R/scripts/"

# The fake formatter turns SELFTEST_FMT_BREAKS_RUN into SELFTEST_FAILS and adds
# a line, so line numbers in the formatted copy differ from the original. It
# aborts on SELFTEST_FMT_ABORTS, and turns SELFTEST_FMT_OUTPUT_ABORTS into
# SELFTEST_FMT_ABORTS, so the second pass of the idempotency check aborts.
cat > "$R/fake/blinkc" <<'EOF'
#!/bin/bash
if [ "$3" = "--emit" ]; then
    grep -q SELFTEST_FMT_HANGS "$1" && exec sleep 30
    grep -q SELFTEST_FMT_ABORTS "$1" && exit 101
    if grep -q SELFTEST_FMT_OUTPUT_ABORTS "$1"; then
        sed 's/SELFTEST_FMT_OUTPUT_ABORTS/SELFTEST_FMT_ABORTS/' "$1" > "$2"
        exit 0
    fi
    { echo "// formatted"; sed 's/SELFTEST_FMT_BREAKS_RUN/SELFTEST_FAILS/' "$1"; } > "$2"
    exit 0
fi
test_build=0
[ "$1" = "--test-build" ] && { test_build=1; shift; }
[ "$1" = "--link-archive" ] && shift 2
src="$1"; out="$2"
{
    echo '#include <stdio.h>'
    echo '#include <stdlib.h>'
    echo '#include <string.h>'
    echo '#include <unistd.h>'
    echo 'int main(int argc, char **argv) {'
    printf '    printf("  --> %s:3:1\\n");\n' "$src"
    if grep -q SELFTEST_NEEDS_PRELUDE "$src"; then
        echo '    const char *r = getenv("BLINK_ROOT"); char p[4096];'
        echo '    if (!r) { printf("test probe ... FAIL\n\n0 passed, 1 failed (of 1)\n"); return 1; }'
        echo '    snprintf(p, sizeof p, "%s/lib/std", r);'
        echo '    if (access(p, F_OK) != 0) { printf("test probe ... FAIL\n\n0 passed, 1 failed (of 1)\n"); return 1; }'
    fi
    # Only a test build runs the tests; any other build of a file with a main runs main.
    if grep -q SELFTEST_MAIN_AND_TESTS "$src" && [ "$test_build" = 0 ]; then
        echo '    printf("main ran\n"); return 0;'
    fi
    # A test that pins its own file name, as a panic location match does, fails
    # unless the source it was built from keeps that name.
    if grep -q SELFTEST_NAMES_ITS_FILE "$src"; then
        case "$src" in
            *_test_names_its_file.bl|tests/test_names_its_file.bl) ;;
            *) echo '    printf("test probe ... FAIL\n\n0 passed, 1 failed (of 1)\n"); return 1;' ;;
        esac
    fi
    if grep -q SELFTEST_RUN_HANGS "$src"; then
        echo '    sleep(30);'
    fi
    if grep -q SELFTEST_FAILS "$src"; then
        echo '    printf("test probe ... \033[31mFAIL\033[0m\n\n0 passed, 1 failed (of 1)\n"); return 1;'
    fi
    if grep -q SELFTEST_PRINTS_FAIL "$src"; then
        echo '    printf("FAIL: this probe no longer needs to allow one\n");'
    fi
    echo '    printf("test probe ... \033[32mok\033[0m\n\n1 passed, 0 failed (of 1)\n"); return 0;'
    echo '}'
} > "$out"
EOF
chmod +x "$R/fake/blinkc"

fixture() { printf 'test "probe" {\n    // %s\n}\n' "$2" > "$R/tests/$1.bl"; }
fixture test_plain_pass "nothing"
fixture test_fails_on_its_own SELFTEST_FAILS
fixture test_prints_fail_in_a_pass SELFTEST_PRINTS_FAIL
fixture test_needs_prelude SELFTEST_NEEDS_PRELUDE
fixture test_fmt_breaks_run SELFTEST_FMT_BREAKS_RUN
fixture test_fmt_aborts SELFTEST_FMT_ABORTS
fixture test_fmt_output_aborts SELFTEST_FMT_OUTPUT_ABORTS
fixture test_names_its_file SELFTEST_NAMES_ITS_FILE
fixture test_fmt_hangs SELFTEST_FMT_HANGS
fixture test_run_hangs SELFTEST_RUN_HANGS
fixture input_hangs SELFTEST_FMT_HANGS
mv "$R/tests/input_hangs.bl" "$R/tests/fmt/input_hangs.bl"
fixture expected_hangs nothing
mv "$R/tests/expected_hangs.bl" "$R/tests/fmt/expected_hangs.bl"
# A file with a main and test blocks runs its tests; the main would hide the
# formatted copy's failing test.
printf 'test "probe" {\n    // SELFTEST_MAIN_AND_TESTS SELFTEST_FMT_BREAKS_RUN\n}\n\nfn main() {\n}\n' > "$R/tests/test_main_and_tests.bl"

# expect <runner> <fixture> <verdict>
expect_run() {
    local runner="$1" name="$2" want="$3" got
    got=$(cd "$R" && "./scripts/$runner" "tests/$name.bl" "$R/fake/blinkc" /dev/null 2>&1 | tail -1)
    if [ "${got%% *}" != "$want" ]; then
        echo "test_fmt_semantic: $runner $name: want $want, got: $got"
        fail=1
    fi
}
expect() { expect_run run_fmt_semantic.sh "$1" "$2"; }
expect test_plain_pass PASS
expect test_fails_on_its_own PASS
expect test_prints_fail_in_a_pass PASS
expect test_needs_prelude PASS
expect test_names_its_file PASS
expect test_fmt_breaks_run FAIL
expect test_main_and_tests FAIL
expect test_fmt_aborts FAIL
expect_run run_fmt_idempotent.sh test_fmt_aborts FAIL
expect_run run_fmt_idempotent.sh test_fmt_output_aborts FAIL

# expect_limit <runner> <fixture path>: the file fails, names the time limit,
# and ends long before the 30s the fake sleeps.
expect_limit() {
    local runner="$1" path="$2" got start
    start=$EPOCHSECONDS
    got=$(cd "$R" && BLINK_CHILD_TIMEOUT=2 BLINK_CHILD_KILL_AFTER=1 "./scripts/$runner" "$path" "$R/fake/blinkc" /dev/null 2>&1 | tail -1)
    case "$got" in
        "FAIL "*"ran past its time limit (2s)"*)
            if [ $((EPOCHSECONDS - start)) -ge 20 ]; then
                echo "test_fmt_semantic: $runner $path: took $((EPOCHSECONDS - start))s"
                fail=1
            fi
            ;;
        *) echo "test_fmt_semantic: $runner $path: want a FAIL naming the time limit, got: $got"; fail=1 ;;
    esac
}
expect_limit run_fmt_semantic.sh tests/test_fmt_hangs.bl
expect_limit run_fmt_semantic.sh tests/test_run_hangs.bl
expect_limit run_fmt_idempotent.sh tests/test_fmt_hangs.bl
expect_limit run_fmt_golden.sh tests/fmt/input_hangs.bl

leftover=$(ls "$R/tests" | grep -c fmt-sem- || true)
if [ "$leftover" -ne 0 ]; then
    echo "test_fmt_semantic: $leftover formatted scratch file(s) left in tests/"
    fail=1
fi

if [ "$fail" -eq 0 ]; then
    echo "test-fmt-semantic: ok"
fi
exit "$fail"
