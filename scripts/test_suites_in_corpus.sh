#!/bin/bash
# Proves scripts/suites_in_corpus.sh reads build/corpus.json only when it
# describes this tree: written at HEAD, or written at an earlier commit by a
# sweep whose input stamp still matches (ci skips the sweep then, so the JSON
# keeps the old commit). A different compiler, a stale stamp, a missing stamp
# or a JSON that is not the stamped output stays stale.
# Runs unmodified copies of the scripts in a throwaway git repo, so it takes
# seconds and never touches this checkout's build/.
set -u
cd "$(dirname "$0")/.."
SRC="$PWD/scripts"

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
fail=0

R="$WORK/repo"
mkdir -p "$R/scripts" "$R/src" "$R/sections" "$R/build/gen1" "$R/tests"
cp "$SRC/suites_in_corpus.sh" "$SRC/ci_corpus_stamp.sh" "$R/scripts/"
cd "$R" || exit 2
cat > scripts/rewrite_suite_list.sh <<'EOF'
#!/bin/bash
echo tests/test_b.bl > build/rewrite_suite_list.txt
echo build/rewrite_suite_list.txt
EOF
chmod +x scripts/rewrite_suite_list.sh
echo tests/test_a.bl > scripts/typecheck_suite.txt
echo a > tests/test_a.bl
echo b > tests/test_b.bl
echo a > src/a.bl
echo a > sections/x.md
echo blinkc > build/gen1/blinkc
git init -q .
git config user.email t@t
git config user.name t
printf 'build/\n' > .gitignore
git add -A
git commit -q -m init

S=./scripts/ci_corpus_stamp.sh
sha=$(sha256sum build/gen1/blinkc | cut -c1-16)

write_json() {
    # write_json <path> <head>
    printf '{"compiler":"build/gen1","blinkc_sha256_prefix":"%s","git_head":"%s","files":[{"file":"tests/test_a.bl","status":"pass"},{"file":"tests/test_b.bl","status":"pass"}]}\n' \
        "$sha" "$2" > "$1"
}

# A ci sweep: begin, write the outputs at the current HEAD, commit.
sweep() {
    rm -f build/ci_corpus.stamp build/ci_corpus.pending
    $S begin >/dev/null 2>&1
    sleep 0.02
    write_json build/corpus.json "$(git rev-parse --short HEAD)"
    echo '{}' > build/corpus_per_module_slice.json
    sleep 0.02
    $S commit >/dev/null 2>&1
}

commit_edit() {
    echo b >> "$1"
    git commit -q -am "edit $1"
}

expect() {
    # expect ok|stale "label" [CORPUS_OUT]
    want="$1"; label="$2"; out="${3:-build/corpus.json}"
    err=$(CORPUS_OUT="$out" ./scripts/suites_in_corpus.sh 2>&1 >/dev/null)
    rc=$?
    if [ "$rc" = 0 ]; then got=ok
    elif grep -q 'is stale' <<< "$err"; then got=stale
    else got="error($rc): $err"
    fi
    if [ "$got" = "$want" ]; then
        echo "PASS: $label"
    else
        echo "FAIL: $label (want $want, got $got)"
        fail=1
    fi
}

sweep
expect ok "corpus written at HEAD -> ok"

commit_edit sections/x.md
expect ok "doc-only commit after a stamped sweep -> ok"

commit_edit src/a.bl
expect stale "src commit after a stamped sweep -> stale"

sweep
commit_edit sections/x.md
rm -f build/ci_corpus.stamp
expect stale "earlier commit and no stamp -> stale"

sweep
commit_edit sections/x.md
write_json build/other.json "$(git rev-parse --short HEAD~1)"
expect stale "earlier commit, JSON is not the stamped output -> stale" build/other.json

sweep
commit_edit sections/x.md
echo other > build/gen1/blinkc
expect stale "doc-only commit but another blinkc -> stale"
echo blinkc > build/gen1/blinkc

if [ "$fail" = 0 ]; then echo "suites_in_corpus: all passed"; else echo "suites_in_corpus: FAILED"; fi
exit "$fail"
