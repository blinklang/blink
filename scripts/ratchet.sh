#!/bin/sh
# Ratchet on flat type-channel counts and known compiler-debt idioms. Each
# row must not go up against two references: the stored baseline, and the
# same count computed on the files as they stood in the previous commit.
# The second check catches a regression that fits inside headroom banked by
# an earlier, unrelated deletion instead of paying for itself.
#   scripts/ratchet.sh            compare current counts against both references
#   scripts/ratchet.sh --update   rewrite the baseline from the current counts
#
# The "previous commit" reference is HEAD when the working tree has
# uncommitted changes under src/ or Taskfile.yml (the normal case: this
# script runs before a commit, so the commit-to-be's real parent is HEAD,
# not HEAD~1), and HEAD~1 when the tree is clean (so a check run against an
# already-landed commit still validates that commit against its own
# parent). Override with RATCHET_HEAD1_REF to pin one or the other. If the
# resolved ref does not exist (shallow clone, or a repo with too few commits
# for HEAD~1), the previous-commit comparison is skipped for that run instead
# of failing every row against an empty tree. Known gap: on a clean tree with
# several unpushed local commits, only the tip is checked against its
# immediate parent — a regression in an earlier commit of that stack is not
# independently re-audited once the tree is clean.
#
# Env overrides (used by scripts/test_ratchet.sh; normal runs need none):
#   RATCHET_SRC_DIR   root dir standing in for the repo root when computing
#                     "now" (must contain src/ and Taskfile.yml). Default: .
#   RATCHET_BASELINE  baseline file path. Default: scripts/ratchet_baseline.txt
#   RATCHET_HEAD1_DIR root dir standing in for the previous-commit snapshot,
#                     bypassing git entirely. Default: unset (materialize
#                     RATCHET_HEAD1_REF via git into .tmp/ratchet_head1).
#   RATCHET_HEAD1_REF git ref to materialize when RATCHET_HEAD1_DIR is unset.
#                     Default: HEAD if src/ or Taskfile.yml has uncommitted
#                     changes, else HEAD~1 (see above).
set -u
cd "$(dirname "$0")/.."

update_flag="${1:-}"
baseline="${RATCHET_BASELINE:-scripts/ratchet_baseline.txt}"
now_root="${RATCHET_SRC_DIR:-.}"
if [ -z "$(git status --porcelain -- src Taskfile.yml 2>/dev/null)" ]; then
  default_head1_ref=HEAD~1
else
  default_head1_ref=HEAD
fi
head1_ref="${RATCHET_HEAD1_REF:-$default_head1_ref}"

cnt() { rg -o "$1" $2 2>/dev/null | wc -l | tr -d ' '; }

# cnt() relies on unquoted word-splitting to pass multiple files to rg, so a
# root containing a space would silently undercount instead of erroring. This
# must run OUTSIDE any $(...) — compute_rows is always invoked inside a
# command substitution, where `exit` would only kill that subshell and let
# the script carry on with an empty result instead of actually stopping.
check_root() {
  case "$1" in
    *[[:space:]]*)
      echo "ratchet: error: '$1' contains whitespace, which this script cannot count reliably. Rerun from a path with no spaces." >&2
      exit 1
      ;;
  esac
}

# Takes a root dir instead of reading the repo directly, so the same row
# definitions run against the real tree, a materialized historical ref, or a
# synthetic test fixture without duplicating the row list three times.
compute_rows() {
  root="$1"
  cg="$root/src/codegen*.bl"
  mono="$root/src/mono.bl"
  tc="$root/src/typecheck.bl"
  allbl="$root/src/*.bl"
  tf="$root/Taskfile.yml"

  eg=$(rg -o '^pub let mut (expr_[a-z_0-9]+)' -r '$1' "$root/src/codegen_expr.bl" 2>/dev/null | paste -sd'|')
  if [ -n "$eg" ]; then eg_count=$(cnt "\\b(${eg})\\b" "$cg"); else eg_count=0; fi

  cat <<ROWS
ct_refs $(cnt '\bCT_[A-Z_]+\b' "$cg")
type_from_name $(cnt '\btype_from_name(_tag)?\(' "$cg")
tc_tid_ct $(cnt '\btc_tid_ct\(' "$cg")
expr_result_type $(cnt '\bexpr_result_type\b' "$cg")
expr_globals $eg_count
flat_scopevar_accessors $(cnt '\b(get|set)_(var|sv|list_elem|map_key|map_value|set_elem|option_inner|result_ok|result_err|tuple_elem)[a-z_0-9]*\(' "$cg")
typename_string_compares $(cnt '== "[A-Z][A-Za-z]*"' "$cg")
lossy_ann_string_reads $(cnt '\bnode_(type_name|return_type)\(' "$cg")
pub_let_mut $(cnt '^pub let mut' "$cg $mono")
set_var_sites $(cnt '\bset_var\(' "$cg")
flat_fallback_idiom $(cnt 'if [a-z_]+ >= 0 \{ [a-z_]+ \} else' "$cg")
return_type_unknown $(cnt 'return TYPE_UNKNOWN' "$tc")
str_keyed_type_facts $(( $(cnt '^let mut [a-z_]+: Map\[Str' "$tc") + $(cnt '^pub let mut [a-z_]+: Map\[Str' "$tc") ))
downgrade_calls $(cnt '\btc_tid_[a-z_]*_(ct|ct_resolved|struct|struct_head|struct_mono|tuple)\(' "$cg")
br_ids_in_source $(( $(cnt '\bbr [0-9a-z]{6}\b' "$allbl $tf") + $(cnt '\b(g3sba0|qf1vzx|0kpmac)\b' "$allbl $tf") ))
ROWS
}

# Writes a plain copy of every tracked .bl file plus Taskfile.yml, as they
# stood at $1, into $2. A file that does not exist at $1 is simply absent,
# which compute_rows treats as a zero contribution.
materialize_ref() {
  ref="$1"
  outdir="$2"
  rm -rf "$outdir"
  mkdir -p "$outdir"
  git ls-tree -r --name-only "$ref" -- src Taskfile.yml 2>/dev/null | while IFS= read -r path; do
    case "$path" in
      *.bl|Taskfile.yml) ;;
      *) continue ;;
    esac
    mkdir -p "$outdir/$(dirname "$path")"
    git show "$ref:$path" > "$outdir/$path" 2>/dev/null
  done
}

check_root "$now_root"
rows_now=$(compute_rows "$now_root")

if [ "$update_flag" = "--update" ]; then
  printf '%s\n' "$rows_now" > "$baseline"
  echo "ratchet: baseline written"
  printf '%s\n' "$rows_now"
  exit 0
fi

[ -f "$baseline" ] || { echo "ratchet: no baseline; run scripts/ratchet.sh --update"; exit 1; }

if [ -n "${RATCHET_HEAD1_DIR:-}" ]; then
  head1_root="$RATCHET_HEAD1_DIR"
  check_root "$head1_root"
  rows_head1=$(compute_rows "$head1_root")
elif git rev-parse --verify --quiet "${head1_ref}^{commit}" >/dev/null 2>&1; then
  head1_root=.tmp/ratchet_head1
  materialize_ref "$head1_ref" "$head1_root"
  rows_head1=$(compute_rows "$head1_root")
else
  # $head1_ref does not resolve (shallow clone, or a repo with too few
  # commits for HEAD~1 to exist). Skip the previous-commit comparison for
  # this run rather than treating the whole reference tree as empty, which
  # would fail every nonzero row for a reason unrelated to any regression.
  echo "ratchet: warning: '$head1_ref' does not resolve; skipping the previous-commit comparison for this run" >&2
  rows_head1="$rows_now"
fi

failmark=$(mktemp)
trap 'rm -f "$failmark"' EXIT

printf '%-26s %8s %8s %8s\n' metric baseline 'head~1' now
printf '%s\n' "$rows_now" | while read -r name now; do
  base=$(awk -v n="$name" '$1==n{print $2}' "$baseline")
  [ -z "$base" ] && base=0
  h1=$(printf '%s\n' "$rows_head1" | awk -v n="$name" '$1==n{print $2}')
  [ -z "$h1" ] && h1=0
  mark=""
  [ "$now" -gt "$base" ] && mark="$mark UP(baseline)"
  [ "$now" -gt "$h1" ] && mark="$mark UP(head~1)"
  # br_ids_in_source is an absolute zero gate (br is local-only; an id means
  # nothing to another reader or to training data), not merely non-increasing.
  [ "$name" = "br_ids_in_source" ] && [ "$now" -gt 0 ] && mark="$mark NONZERO(must-be-zero)"
  printf '%-26s %8s %8s %8s%s\n' "$name" "$base" "$h1" "$now" "$mark"
  [ -n "$mark" ] && printf x >> "$failmark"
done

if [ -s "$failmark" ]; then
  echo "ratchet: a tracked count went up against the baseline or the previous commit. Remove the new use, or lower another row."
  exit 1
fi
echo "ratchet: ok"
