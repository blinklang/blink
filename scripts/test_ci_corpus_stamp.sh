#!/bin/bash
# Proves scripts/ci_corpus_stamp.sh skips the corpus only when nothing the
# corpus reads has changed: any tracked or new file edit busts the stamp, an
# edit under the doc-only paths does not, a stamp never covers a tree edited
# mid-run, a rewrite of an output file by another corpus run busts it, and so
# does a child cap knob.
# Runs an unmodified copy of the script in a throwaway git repo, so it takes
# seconds and never touches this checkout's build/.
set -u
cd "$(dirname "$0")/.."
SCRIPT="$PWD/scripts/ci_corpus_stamp.sh"

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
fail=0

R="$WORK/repo"
mkdir -p "$R/scripts" "$R/src" "$R/sections" "$R/decisions" "$R/docs" "$R/build"
cp "$SCRIPT" "$R/scripts/" 2>/dev/null
cd "$R" || exit 2
git init -q .
git config user.email t@t
git config user.name t
printf 'build/\n' > .gitignore
echo a > src/a.bl
echo a > sections/x.md
echo a > llms.md
echo a > Taskfile.yml
echo a > decisions/x.md
echo a > docs/x.md
echo a > DECISIONS.md
echo a > OPEN_QUESTIONS.md
echo a > gone.txt
git add -A
git commit -q -m init

S=./scripts/ci_corpus_stamp.sh

fresh() {
    rm -f build/ci_corpus.stamp build/ci_corpus.pending
    $S begin >/dev/null 2>&1
    # The sweep writes its outputs between begin and commit.
    sleep 0.02
    echo '{}' > build/corpus.json
    echo '{}' > build/corpus_per_module_slice.json
    sleep 0.02
    $S commit >/dev/null 2>&1
}

expect() {
    # expect pass|fail "label"
    want="$1"; label="$2"
    if $S check >/dev/null 2>&1; then got=pass; else got=fail; fi
    if [ "$got" = "$want" ]; then
        echo "PASS: $label"
    else
        echo "FAIL: $label (check should $want, did $got)"
        fail=1
    fi
}

# 1
fresh_none() { rm -f build/ci_corpus.stamp build/ci_corpus.pending; }
fresh_none
expect fail "no stamp -> check fails"
fresh
expect pass "begin+commit -> check passes"

# 2
echo b >> src/a.bl
expect fail "edit tracked src file -> fails"
git checkout -q src/a.bl

# 3
for f in llms.md Taskfile.yml; do
    fresh
    echo b >> "$f"
    expect fail "edit $f -> fails"
    git checkout -q "$f"
done

# 4
for f in sections/x.md decisions/x.md docs/x.md DECISIONS.md OPEN_QUESTIONS.md; do
    fresh
    echo b >> "$f"
    expect pass "edit $f -> still passes"
    git checkout -q "$f"
done

# 5
fresh
echo n > newfile.txt
expect fail "new untracked file -> fails"
rm newfile.txt
fresh
echo n > build/ignored.txt
expect pass "ignored file under build/ -> passes"

# 6
fresh
sleep 1
touch build/corpus.json
expect fail "output newer than stamp -> fails"
fresh
sleep 1
touch build/corpus_per_module_slice.json
expect fail "second output newer than stamp -> fails"
fresh
rm build/corpus.json
expect fail "missing output -> fails"

# 7
fresh
rm -f build/ci_corpus.stamp
$S begin >/dev/null 2>&1
echo mid >> src/a.bl
$S commit >/dev/null 2>&1
rc=$?
[ "$rc" = 0 ] || { echo "FAIL: commit after mid-run edit exits $rc"; fail=1; }
if [ -e build/ci_corpus.stamp ] || [ -e build/ci_corpus.pending ]; then
    echo "FAIL: commit after mid-run edit left a stamp or pending file"; fail=1
else
    echo "PASS: file changed between begin and commit -> no stamp"
fi
expect fail "check after mid-run edit fails"
git checkout -q src/a.bl

# 8
fresh
rm gone.txt
if $S key >/dev/null 2>&1; then
    echo "PASS: deleted tracked file does not crash key"
else
    echo "FAIL: key crashed on deleted tracked file"; fail=1
fi
expect fail "deleted tracked file -> fails"
git checkout -q gone.txt

# 9
fresh
if CORPUS_FOO=1 $S check >/dev/null 2>&1; then
    echo "FAIL: CORPUS_FOO=1 -> should fail"; fail=1
else
    echo "PASS: CORPUS_FOO=1 -> fails"
fi
expect pass "stamp still valid without CORPUS_FOO"

# 10: a child cap knob decides whether a row passes; the run's cgroup path does not.
fresh
if BLINK_CHILD_MEMORY_MAX=64M $S check >/dev/null 2>&1; then
    echo "FAIL: BLINK_CHILD_MEMORY_MAX=64M -> should fail"; fail=1
else
    echo "PASS: BLINK_CHILD_MEMORY_MAX=64M -> fails"
fi
if BLINK_CHILD_CGROUP=/sys/fs/cgroup/other BLINK_CHILD_CAP_MODE=rlimit $S check >/dev/null 2>&1; then
    echo "PASS: BLINK_CHILD_CGROUP and BLINK_CHILD_CAP_MODE -> stamp still valid"
else
    echo "FAIL: BLINK_CHILD_CGROUP or BLINK_CHILD_CAP_MODE busts the stamp"; fail=1
fi
# corpus_one.sh gives each row its CORPUS_*_TIMEOUT, so BLINK_CHILD_TIMEOUT
# reaches no row.
if BLINK_CHILD_TIMEOUT=5 $S check >/dev/null 2>&1; then
    echo "PASS: BLINK_CHILD_TIMEOUT -> stamp still valid"
else
    echo "FAIL: BLINK_CHILD_TIMEOUT busts the stamp"; fail=1
fi

# override outputs
fresh
if CI_STAMP_OUTPUTS="build/nope.json" $S check >/dev/null 2>&1; then
    echo "FAIL: CI_STAMP_OUTPUTS with missing file should fail"; fail=1
else
    echo "PASS: CI_STAMP_OUTPUTS override is honoured"
fi

if [ "$fail" = 0 ]; then echo "ci_corpus_stamp: all passed"; else echo "ci_corpus_stamp: FAILED"; fi
exit "$fail"
