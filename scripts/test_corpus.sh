#!/bin/bash
# Proves scripts/corpus.sh reports a failing file through its exit code under
# --only, keeps exit 0 for a full run (corpus-check judges that), and that
# corpus_sample.sh still holds a subset to its floor instead of stopping on
# that exit code. Runs an unmodified copy of the scripts in a throwaway root
# with a fake compiler, so it takes seconds and never touches this checkout's
# build/corpus, which a real corpus run beside it may be writing.
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
cp scripts/corpus.sh scripts/corpus_one.sh scripts/corpus_sample.sh "$R/scripts/"
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

if [ "$fail" -ne 0 ]; then
    echo "test_corpus: FAILED"
    exit 1
fi
echo "test_corpus: all checks passed"
