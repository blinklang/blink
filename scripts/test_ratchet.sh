#!/bin/sh
# Proves scripts/ratchet.sh actually catches a regression: a synthetic +1 on
# any single tracked row must fail the script, and the HEAD~1 comparison must
# catch a regression even when the baseline has unrelated headroom. Uses a
# tiny synthetic fixture (RATCHET_SRC_DIR/RATCHET_HEAD1_DIR/RATCHET_BASELINE
# overrides) instead of the real repo, so this runs in a few seconds. The
# env-var overrides bypass git entirely, so a separate block near the end
# runs an unmodified copy of ratchet.sh inside a small throwaway git repo to
# exercise the adaptive HEAD-vs-HEAD~1 selection those overrides skip.
set -u
cd "$(dirname "$0")/.."
# The lint has its own proofs; keep this self-test about ratchet.sh alone.
export RATCHET_NO_LINT=1

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
fail=0

write_base() {
  dir="$1"
  mkdir -p "$dir/src"
  cat > "$dir/src/codegen.bl" <<'EOF'
pub let mut other_global: Int = 0
EOF
  cat > "$dir/src/mono.bl" <<'EOF'
// mono placeholder fixture, deliberately no pub let mut here
EOF
  # A decline that IS handled: diag_ice within three lines of the read.
  cat > "$dir/src/cname.bl" <<'EOF'
let d = layout_of(t)
if d.declined {
    let why = d.decline_reason
    diag_ice("LayoutDeclined", why)
}
EOF
  : > "$dir/Taskfile.yml"
}

BASE="$WORK/base"
write_base "$BASE"

BASELINE="$WORK/baseline.txt"
RATCHET_SRC_DIR="$BASE" RATCHET_BASELINE="$BASELINE" ./scripts/ratchet.sh --update > /dev/null

if ! RATCHET_SRC_DIR="$BASE" RATCHET_BASELINE="$BASELINE" RATCHET_HEAD1_DIR="$BASE" ./scripts/ratchet.sh > /dev/null 2>&1; then
  echo "FAIL sanity: unperturbed fixture did not pass ratchet.sh against itself"
  fail=1
fi

# A synthetic +1 on each row, in turn, must fail the script.
check_row() {
  row="$1"; file="$2"; extra="$3"
  d="$WORK/row_$row"
  rm -rf "$d"
  cp -r "$BASE" "$d"
  printf '%s\n' "$extra" >> "$d/src/$file"
  if RATCHET_SRC_DIR="$d" RATCHET_BASELINE="$BASELINE" RATCHET_HEAD1_DIR="$BASE" ./scripts/ratchet.sh > /dev/null 2>&1; then
    echo "FAIL $row: a +1 on this row did not fail ratchet.sh"
    fail=1
  else
    echo "PASS $row: +1 correctly failed ratchet.sh"
  fi
}

check_row pub_let_mut              codegen.bl   'pub let mut other_global2: Int = 0'
check_row br_ids_in_source         codegen.bl   '// also see br xyz987'
check_row layout_decline_unhandled cname.bl     'let swallowed = d.decline_reason'

# A decline read whose ICE sits four lines away is unhandled: the window is
# the same line plus the next three, so this must count.
check_row layout_decline_unhandled cname.bl     'let far = d.decline_reason
// one
// two
// three
diag_ice("TooLate", far)'

# br_ids_in_source is an absolute zero gate: it must fail even when the
# baseline and HEAD~1 both already read 1, where the plain non-increasing
# rule alone would pass.
STALE_ID_DIR="$WORK/stale_id"
rm -rf "$STALE_ID_DIR"
cp -r "$BASE" "$STALE_ID_DIR"
printf '%s\n' '// see br abc123' >> "$STALE_ID_DIR/src/codegen.bl"
STALE_ID_BASELINE="$WORK/stale_id_baseline.txt"
RATCHET_SRC_DIR="$STALE_ID_DIR" RATCHET_BASELINE="$STALE_ID_BASELINE" ./scripts/ratchet.sh --update > /dev/null
if RATCHET_SRC_DIR="$STALE_ID_DIR" RATCHET_BASELINE="$STALE_ID_BASELINE" RATCHET_HEAD1_DIR="$STALE_ID_DIR" ./scripts/ratchet.sh > /dev/null 2>&1; then
  echo "FAIL br_ids_in_source-absolute-zero: baseline=1, head~1=1, now=1 should still fail (must-be-zero, not merely non-increasing)"
  fail=1
else
  echo "PASS br_ids_in_source-absolute-zero: a steady nonzero count fails even though it does not increase"
fi

# The HEAD~1 check must catch a regression independently of the baseline,
# even when the baseline has generous headroom banked from elsewhere.
LOOSE_BASELINE="$WORK/loose_baseline.txt"
awk '{print $1, $2+100}' "$BASELINE" > "$LOOSE_BASELINE"
NOW="$WORK/now_headroom"
rm -rf "$NOW"
cp -r "$BASE" "$NOW"
printf '%s\n' 'pub let mut headroom_global: Int = 0' >> "$NOW/src/codegen.bl"
if RATCHET_SRC_DIR="$NOW" RATCHET_BASELINE="$LOOSE_BASELINE" RATCHET_HEAD1_DIR="$BASE" ./scripts/ratchet.sh > /dev/null 2>&1; then
  echo "FAIL head1-independent: a regression inside baseline headroom was not caught by the HEAD~1 check"
  fail=1
else
  echo "PASS head1-independent: HEAD~1 check caught a regression the loose baseline alone would have missed"
fi

# A root path with a space must error loudly, not silently undercount (cnt()
# passes its file-list argument to rg unquoted).
SPACEY="$WORK/spa ced"
cp -r "$BASE" "$SPACEY"
if RATCHET_SRC_DIR="$SPACEY" RATCHET_BASELINE="$BASELINE" RATCHET_HEAD1_DIR="$BASE" ./scripts/ratchet.sh > /dev/null 2>&1; then
  echo "FAIL space-in-path: a root path containing a space should error, not silently pass"
  fail=1
else
  echo "PASS space-in-path: a root path containing a space errors instead of silently undercounting"
fi

# Real git-backed checks: the earlier checks all bypass git entirely via
# RATCHET_HEAD1_DIR, so they never exercise the adaptive HEAD-vs-HEAD~1
# selection or the git plumbing (materialize_ref) that only runs without it.
# Run a copy of ratchet.sh inside a small throwaway repo instead, so its own
# `cd "$(dirname "$0")/.."` and git commands operate on that repo.
GITWORK="$WORK/gitrepo"
mkdir -p "$GITWORK/scripts" "$GITWORK/src"
cp ./scripts/ratchet.sh "$GITWORK/scripts/ratchet.sh"
chmod +x "$GITWORK/scripts/ratchet.sh"
echo 'pub let mut a: Int = 0' > "$GITWORK/src/codegen.bl"
: > "$GITWORK/src/mono.bl"
: > "$GITWORK/Taskfile.yml"
(
  cd "$GITWORK" || exit 1
  git init -q .
  git config user.email t@example.com
  git config user.name t
  git add -A
  git commit -q -m one

  # A single-commit repo has no HEAD~1. That must be skipped gracefully
  # instead of comparing against an empty tree and failing every row.
  ./scripts/ratchet.sh --update > /dev/null
  if ! ./scripts/ratchet.sh > /dev/null 2>&1; then
    echo "FAIL git-unresolvable-ref: single-commit repo should pass when HEAD~1 does not exist"
    exit 1
  fi
  echo "PASS git-unresolvable-ref: unresolvable HEAD~1 skipped instead of failing every row"

  # Land a real regression in a second commit, then re-baseline to match it
  # (a baseline that was not updated when the regression landed).
  printf '%s\n' 'pub let mut b: Int = 0' >> src/codegen.bl
  printf '%s\n' 'pub let mut c: Int = 0' >> src/codegen.bl
  git add -A
  git commit -q -m two
  ./scripts/ratchet.sh --update > /dev/null

  # Clean tree: must pick HEAD~1 (commit one), which lacks the regression
  # that landed in commit two, and fail despite the baseline being fresh.
  if ./scripts/ratchet.sh > /dev/null 2>&1; then
    echo "FAIL git-clean-picks-head1: a clean tree should compare the landed commit against its own parent and catch the regression"
    exit 1
  fi
  echo "PASS git-clean-picks-head1: clean tree compared HEAD against HEAD~1 and caught the regression"

  # Dirty tree: must pick HEAD (commit two), not the older HEAD~1, or a
  # no-op edit would spuriously fail against a stale reference.
  printf '%s\n' '// a comment, no count change' >> src/codegen.bl
  if ! ./scripts/ratchet.sh > /dev/null 2>&1; then
    echo "FAIL git-dirty-picks-head: a dirty tree should compare against HEAD, not the older HEAD~1"
    exit 1
  fi
  echo "PASS git-dirty-picks-head: dirty tree compared against HEAD rather than HEAD~1"

  # A row the commit under test ADDS has no previous-commit count: computing
  # it over the reference commit's files answers 0 for a metric nobody was
  # tracking, which must not fail the row for the fact of existing.
  # The marker the new row counts is introduced by this same uncommitted edit, so the
  # reference commit counts 0 of it and the row would be failed for rising 0 -> 1 if a row
  # this commit adds were compared at all.
  printf '%s\n' '// newrow_marker' >> src/codegen.bl
  awk '/^ROWS$/ { print "newrow $(cnt \047newrow_marker\047 \"$allbl\")" } { print }' scripts/ratchet.sh > new.sh
  cat new.sh > scripts/ratchet.sh
  rm -f new.sh
  ./scripts/ratchet.sh --update > /dev/null
  newrow_out=$(./scripts/ratchet.sh 2>&1)
  if [ $? != 0 ]; then
    echo "FAIL git-new-row: a row absent from the reference commit should have no previous-commit reference"
    printf '%s\n' "$newrow_out"
    exit 1
  fi
  if ! printf '%s\n' "$newrow_out" | rg -q '^newrow +1 +1 +1$'; then
    echo "FAIL git-new-row: the new row did not count the marker this edit added, so the check was vacuous"
    printf '%s\n' "$newrow_out"
    exit 1
  fi
  echo "PASS git-new-row: a row this commit adds is not failed against a commit that never tracked it"

  # The converse: once the reference commit defines the row, it is checked
  # like any other, so a real rise still fails.
  git add -A
  git commit -q -m three
  printf '%s\n' '// newrow_marker' >> src/codegen.bl
  ./scripts/ratchet.sh --update > /dev/null
  conv_out=$(./scripts/ratchet.sh 2>&1)
  if [ $? = 0 ]; then
    echo "FAIL git-new-row-then-checked: a row the reference commit defines must be compared against it"
    printf '%s\n' "$conv_out"
    exit 1
  fi
  if ! printf '%s\n' "$conv_out" | rg -q '^newrow .*UP\(head~1\)'; then
    echo "FAIL git-new-row-then-checked: the run failed, but not on the row under test"
    printf '%s\n' "$conv_out"
    exit 1
  fi
  echo "PASS git-new-row-then-checked: once the reference commit tracks the row, a rise fails"
)
if [ $? != 0 ]; then fail=1; fi

if [ "$fail" != 0 ]; then
  echo "test_ratchet: FAILED"
  exit 1
fi
echo "test_ratchet: all checks passed"
