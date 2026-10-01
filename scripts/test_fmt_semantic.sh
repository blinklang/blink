#!/bin/bash
# Proves scripts/run_fmt_semantic.sh fails a file only when the formatted
# program behaves differently from the original: a test that fails on its own,
# or prints FAIL inside a passing run, is not a formatter bug. Also proves the
# test binary finds the prelude, which a probe suite needs to compile programs
# in process. Runs an unmodified copy of the script in a throwaway root with a
# fake compiler whose C output acts on markers in the source.
set -u
cd "$(dirname "$0")/.."

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
fail=0

R="$WORK/root"
mkdir -p "$R/scripts" "$R/tests" "$R/.tmp" "$R/lib/std" "$R/fake"
cp scripts/run_fmt_semantic.sh "$R/scripts/"

# The fake formatter turns SELFTEST_FMT_BREAKS_RUN into SELFTEST_FAILS and adds
# a line, so line numbers in the formatted copy differ from the original.
cat > "$R/fake/blinkc" <<'EOF'
#!/bin/bash
if [ "$3" = "--emit" ]; then
    { echo "// formatted"; sed 's/SELFTEST_FMT_BREAKS_RUN/SELFTEST_FAILS/' "$1"; } > "$2"
    exit 0
fi
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
    if grep -q SELFTEST_MAIN_AND_TESTS "$src"; then
        echo '    if (argc < 2 || strcmp(argv[1], "--test") != 0) { printf("main ran\n"); return 0; }'
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
# A file with a main and test blocks runs its tests; the main would hide the
# formatted copy's failing test.
printf 'test "probe" {\n    // SELFTEST_MAIN_AND_TESTS SELFTEST_FMT_BREAKS_RUN\n}\n\nfn main() {\n}\n' > "$R/tests/test_main_and_tests.bl"

expect() {
    local name="$1" want="$2" got
    got=$(cd "$R" && ./scripts/run_fmt_semantic.sh "tests/$name.bl" "$R/fake/blinkc" /dev/null 2>&1 | tail -1)
    if [ "${got%% *}" != "$want" ]; then
        echo "test_fmt_semantic: $name: want $want, got: $got"
        fail=1
    fi
}
expect test_plain_pass PASS
expect test_fails_on_its_own PASS
expect test_prints_fail_in_a_pass PASS
expect test_needs_prelude PASS
expect test_fmt_breaks_run FAIL
expect test_main_and_tests FAIL

leftover=$(ls "$R/tests" | grep -c fmt-sem- || true)
if [ "$leftover" -ne 0 ]; then
    echo "test_fmt_semantic: $leftover formatted scratch file(s) left in tests/"
    fail=1
fi

if [ "$fail" -eq 0 ]; then
    echo "test-fmt-semantic: ok"
fi
exit "$fail"
