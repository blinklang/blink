#!/bin/bash
# Proves scripts/lint_codegen.sh catches each construct it forbids: on a
# clean fixture every row is 0 and the lint passes; each injected violation
# turns exactly its row red. The env overrides (LINT_SRC_DIR, LINT_HEAD1_DIR,
# LINT_BASELINE, LINT_ALLOWLIST) keep this off the real tree and off git,
# so it runs in a few seconds.
set -u
cd "$(dirname "$0")/.."

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
fail=0

write_clean() {
    rm -rf "$1"
    mkdir -p "$1/src" "$1/tests"
    printf 'fn ok() -> Int { 1 }\n' > "$1/src/cg_a.bl"
    : > "$1/tests/test_fixture.bl"
}

CLEAN="$WORK/clean"
write_clean "$CLEAN"
BASELINE="$WORK/baseline.txt"
ALLOW="$WORK/allow.txt"
printf 'cg_out\n' > "$ALLOW"

run_lint() {
    LINT_SRC_DIR="$1" LINT_HEAD1_DIR="$CLEAN" LINT_BASELINE="$BASELINE" LINT_ALLOWLIST="$ALLOW" \
        ./scripts/lint_codegen.sh "${2:-}"
}

# Baseline from the clean fixture: every row 0.
run_lint "$CLEAN" --update > /dev/null
if awk '$2 != 0 { bad = 1 } END { exit bad }' "$BASELINE"; then
    echo "ok   clean fixture: every row is 0"
else
    echo "FAIL clean fixture has a non-zero row:"; cat "$BASELINE"; fail=1
fi
if run_lint "$CLEAN" > "$WORK/clean.out" 2>&1; then
    echo "ok   clean fixture passes the gate"
else
    echo "FAIL clean fixture does not pass:"; cat "$WORK/clean.out"; fail=1
fi

# expect_red <row name> <file under src/> <content>
expect_red() {
    row="$1"; file="$2"; content="$3"
    dir="$WORK/case_$row"
    write_clean "$dir"
    printf '%s\n' "$content" > "$dir/src/$file"
    if run_lint "$dir" > "$dir.out" 2>&1; then
        echo "FAIL $row: lint passed with the violation present"; cat "$dir.out"; fail=1
    elif grep -qE "^L[0-9]+ +$row .*OVER" "$dir.out"; then
        echo "ok   $row goes red"
    else
        echo "FAIL $row: lint failed but not on this row:"; cat "$dir.out"; fail=1
    fi
}

expect_red ct_or_string_types  cg_b.bl 'fn k() -> Int { CT_INT }'
expect_red sentinel_answers    cg_b.bl 'let t = TYPE_UNKNOWN'
expect_red pub_let_mut_unlisted cg_b.bl 'pub let mut stray: Int = 0'
expect_red typename_compares   cg_b.bl 'if name == "Option" { 1 }'
expect_red no_infer            cg_b.bl 'fn infer_kind(x: Int) -> Int { x }'
expect_red layout_outside_layer cg_b.bl 'let s = "int64_t"'
# single_producer: the same producer defined in two files is a twin.
dir="$WORK/case_single_producer"
write_clean "$dir"
printf 'fn c_fn_name(x: Int) -> Str { "" }\n' > "$dir/src/cg_b.bl"
printf 'fn c_fn_name(x: Int) -> Str { "" }\n' >> "$dir/src/cg_a.bl"
if run_lint "$dir" > "$dir.out" 2>&1 || ! grep -qE '^L7 +single_producer .*OVER' "$dir.out"; then
    echo "FAIL single_producer: twin definition not caught:"; cat "$dir.out"; fail=1
else
    echo "ok   single_producer goes red (twin)"
fi
expect_red import_dag          cg_b.bl 'import codegen'
# import_dag also carries scripts/lint_import_dag.sh: layout.bl must import cname.
dir="$WORK/case_import_dag_shared"
write_clean "$dir"
printf 'import typecheck.{tc_x}\npub fn layout_of() -> Int { 1 }\n' > "$dir/src/layout.bl"
printf 'pub fn c_fn_name() -> Str { "" }\n' > "$dir/src/cname.bl"
if run_lint "$dir" > "$dir.out" 2>&1 || ! grep -qE '^L8 +import_dag .*OVER' "$dir.out" || ! grep -q 'must import cname' "$dir.out"; then
    echo "FAIL import_dag: missing layout -> cname edge not caught:"; cat "$dir.out"; fail=1
else
    echo "ok   import_dag goes red through lint_import_dag.sh"
fi
long_fn=$(printf 'fn long() -> Int {\n'; for i in $(seq 1 80); do printf '    let v%d = %d\n' "$i" "$i"; done; printf '    1\n}')
expect_red fn_length           cg_b.bl "$long_fn"
expect_red br_ids_in_source    cg_b.bl '// tracked as br abc123'
expect_red untested_pub_fns    mono.bl 'pub fn mono_orphan() -> Int { 1 }'

# pub_let_mut_new: eight allowlisted globals pass, a ninth is over the cap.
dir="$WORK/case_cap"
write_clean "$dir"
: > "$ALLOW"
for i in 1 2 3 4 5 6 7 8 9; do echo "g$i" >> "$ALLOW"; done
for i in 1 2 3 4 5 6 7 8; do echo "pub let mut g$i: Int = 0" >> "$dir/src/cg_b.bl"; done
if run_lint "$dir" > "$dir.out" 2>&1; then
    echo "ok   pub_let_mut_new: eight allowlisted globals pass"
else
    echo "FAIL pub_let_mut_new: eight allowlisted globals rejected:"; cat "$dir.out"; fail=1
fi
echo "pub let mut g9: Int = 0" >> "$dir/src/cg_b.bl"
if run_lint "$dir" > "$dir.out" 2>&1 || ! grep -qE '^L3 +pub_let_mut_new .*OVER' "$dir.out"; then
    echo "FAIL pub_let_mut_new: ninth global not caught:"; cat "$dir.out"; fail=1
else
    echo "ok   pub_let_mut_new goes red at nine"
fi
printf 'cg_out\n' > "$ALLOW"

# Debt semantics: a row above its threshold in the baseline may stay flat
# (DEBT, pass) but may not rise above the previous commit (UP, fail).
dir="$WORK/case_debt"
write_clean "$dir"
printf '// br abc123\n' > "$dir/src/cg_b.bl"
LINT_SRC_DIR="$dir" LINT_HEAD1_DIR="$dir" LINT_BASELINE="$BASELINE" LINT_ALLOWLIST="$ALLOW" \
    ./scripts/lint_codegen.sh --update > /dev/null
if LINT_SRC_DIR="$dir" LINT_HEAD1_DIR="$dir" LINT_BASELINE="$BASELINE" LINT_ALLOWLIST="$ALLOW" \
    ./scripts/lint_codegen.sh > "$dir.out" 2>&1 && grep -qE '^L10 +br_ids_in_source .*DEBT' "$dir.out"; then
    echo "ok   flat debt passes and is marked DEBT"
else
    echo "FAIL flat debt:"; cat "$dir.out"; fail=1
fi
# Baseline with headroom (2) but the previous commit had 1: rising to 2 is UP.
printf 'br_ids_in_source 2\n' > "$BASELINE"
dir2="$WORK/case_up"
write_clean "$dir2"
printf '// br abc123\n// br def456\n' > "$dir2/src/cg_b.bl"
if LINT_SRC_DIR="$dir2" LINT_HEAD1_DIR="$dir" LINT_BASELINE="$BASELINE" LINT_ALLOWLIST="$ALLOW" \
    ./scripts/lint_codegen.sh > "$dir2.out" 2>&1 || ! grep -qE '^L10 +br_ids_in_source .*UP' "$dir2.out"; then
    echo "FAIL rise above previous commit not caught:"; cat "$dir2.out"; fail=1
else
    echo "ok   rise above the previous commit fails as UP"
fi

# Git-backed checks. Everything above bypasses git through LINT_HEAD1_DIR,
# so it never exercises materialize_ref or the new-row exemption that reads
# the lint script as it stood in the previous commit. Run a copy inside a
# throwaway repo so its own `cd "$(dirname "$0")/.."` lands there.
GITWORK="$WORK/gitrepo"
mkdir -p "$GITWORK/scripts" "$GITWORK/src" "$GITWORK/tests"
cp ./scripts/lint_codegen.sh "$GITWORK/scripts/lint_codegen.sh"
cp ./scripts/lint_pub_let_mut_allow.txt "$GITWORK/scripts/lint_pub_let_mut_allow.txt"
: > "$GITWORK/tests/test_fixture.bl"
printf '// br abc123\n' > "$GITWORK/src/cg_a.bl"
(
    cd "$GITWORK" || exit 1
    git init -q .
    git config user.email t@example.com
    git config user.name t
    git add -A && git commit -qm base
)
# Case 1: the previous commit has no lint script at all. Every row is new,
# so a row already in debt in the baseline written now must pass.
(cd "$GITWORK" && git rm -q --cached scripts/lint_codegen.sh && git commit -qm "no lint" && git add scripts/lint_codegen.sh)
(cd "$GITWORK" && ./scripts/lint_codegen.sh --update > /dev/null)
if (cd "$GITWORK" && ./scripts/lint_codegen.sh > "$WORK/git1.out" 2>&1) && grep -qE '^L10 +br_ids_in_source .*DEBT' "$WORK/git1.out"; then
    echo "ok   git: first commit with a lint script treats every row as new"
else
    echo "FAIL git: first commit with a lint script:"; cat "$WORK/git1.out"; fail=1
fi
(cd "$GITWORK" && git add -A && git commit -qm "lint lands")
# Case 2: the previous commit tracked the row at 1; rising to 2 with a
# baseline of 2 is UP against the previous commit.
printf '// br abc123\n// br def456\n' > "$GITWORK/src/cg_a.bl"
printf 'br_ids_in_source 2\n' > "$GITWORK/scripts/lint_codegen_baseline.txt"
if (cd "$GITWORK" && ./scripts/lint_codegen.sh > "$WORK/git2.out" 2>&1) || ! grep -qE '^L10 +br_ids_in_source .*UP' "$WORK/git2.out"; then
    echo "FAIL git: rise above a tracked previous-commit row not caught:"; cat "$WORK/git2.out"; fail=1
else
    echo "ok   git: rise above a tracked previous-commit row fails as UP"
fi
# Case 3: a row the previous commit's script did not have is exempt from UP.
(cd "$GITWORK" && git checkout -q -- src scripts && sed -i '/^L10 br_ids_in_source 0$/d' scripts/lint_codegen.sh && git add -A && git commit -qm "drop row")
cp ./scripts/lint_codegen.sh "$GITWORK/scripts/lint_codegen.sh"
printf '// br abc123\n// br def456\n' > "$GITWORK/src/cg_a.bl"
(cd "$GITWORK" && ./scripts/lint_codegen.sh --update > /dev/null)
if (cd "$GITWORK" && ./scripts/lint_codegen.sh > "$WORK/git3.out" 2>&1) && grep -qE '^L10 +br_ids_in_source .*DEBT' "$WORK/git3.out"; then
    echo "ok   git: a row new in this commit is exempt from the previous-commit rule"
else
    echo "FAIL git: new-row exemption:"; cat "$WORK/git3.out"; fail=1
fi

if [ "$fail" -ne 0 ]; then
    echo "test_lint_codegen: FAIL"
    exit 1
fi
echo "test_lint_codegen: all checks pass"
