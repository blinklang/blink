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
mkdir -p "$R/scripts" "$R/tests" "$R/build" "$R/fakec/lib/std"
cp scripts/corpus.sh scripts/corpus_one.sh scripts/corpus_sample.sh scripts/corpus_check.sh "$R/scripts/"
: > "$R/build/gc_unity.c"

# A marker in the test file picks the outcome, so each fixture file says what
# it expects.
cat > "$R/fakec/blink" <<'EOF'
#!/bin/bash
out=""; src=""
while [ $# -gt 0 ]; do
    case "$1" in
        -o) out="$2"; shift 2 ;;
        build|--debug) shift ;;
        *) src="$1"; shift ;;
    esac
done
if grep -q SELFTEST_COMPILE_FAIL "$src"; then echo "error[E0000]: fake compile failure"; exit 1; fi
if grep -q SELFTEST_RUN_FAIL "$src"; then
    printf '#!/bin/sh\necho "FAIL: fake run failure"\nexit 1\n' > "$out"
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
else
    printf '#!/bin/sh\nexit 0\n' > "$out"
fi
chmod +x "$out"
EOF
cp "$R/fakec/blink" "$R/fakec/blinkc"
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

# corpus_check.sh on hand-written result files. The fixture root holds one
# stub tests/test_check_N.bl per record, so the total can match the tests on
# disk. The fixtures above sit in the same tests/ directory, so the check runs
# in its own root.
C="$WORK/checkroot"
mkdir -p "$C/scripts" "$C/tests"
cp scripts/corpus_check.sh "$C/scripts/"
stubs() { # <n>: leave exactly n test files in the check root
    rm -f "$C"/tests/test_*.bl
    i=1
    while [ "$i" -le "$1" ]; do : > "$C/tests/test_check_$i.bl"; i=$((i + 1)); done
}
rec() { printf '{"file":"%s","status":"%s","known_failures":%s}' "$1" "$2" "$3"; }
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

if [ "$fail" -ne 0 ]; then
    echo "test_corpus: FAILED"
    exit 1
fi
echo "test_corpus: all checks passed"
