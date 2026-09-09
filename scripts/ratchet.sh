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

# First line of the function that raises the total-stamp hole, or empty when this
# root has no such function. Keyed on the diagnostic rather than the function name
# so a rename cannot silently move the count.
stamp_anchor_line() {
  awk '/^(pub )?fn /{s=NR} /NodeCarriesNoType/{print s; exit}' "$1" 2>/dev/null
}

# The functions the total-stamp assert consults to decide it may SKIP a node. Every excuse the
# pass has lives in one of these, so this list is the surface a kind exemption can be written
# on. Adding an excuse elsewhere means adding it here too, which is the point: the row below
# counts kind references across exactly these, and an unlisted excuse function is an
# unmeasured one.
STAMP_EXCUSE_FNS="tc_stamp_assert tc_stamp_name_child tc_stamp_is_cascade tc_stamp_walk"

# NodeKind references inside one named function, or 0 when the file has no such function.
fn_kind_refs() {
  awk -v want="$2" '
    /^(pub )?fn /{ inside = ($0 ~ ("fn " want "\\(")) }
    inside { print }
  ' "$1" 2>/dev/null | rg -o '\bNodeKind\.[A-Za-z]+\b' | wc -l | tr -d ' '
}

# Like check_root, this must run OUTSIDE any $(...). The row it guards is the one
# a change could zero by deleting the assert it counts inside, so no anchor in the
# tree being gated is a failure, not a zero.
check_stamp_anchor() {
  if [ -z "$(stamp_anchor_line "$1/src/typecheck.bl")" ]; then
    echo "ratchet: error: no total-stamp assert in '$1/src/typecheck.bl' (no NodeCarriesNoType diagnostic), so stamp_excuse_kind_refs cannot be measured" >&2
    exit 2
  fi
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

  # Every kind reference across the whole excuse surface, not just inside the function that
  # raises the hole. Counting only the raiser is what let the original four-kind list reach zero
  # by moving one function over: the assert itself names no kind under any design, so a count
  # taken there measures an empty set by construction and a reintroduced exemption in a helper
  # is invisible. This is a ratchet, not a zero target — a kind named to LOCATE a position
  # (which parent shapes have a name child) is legitimate, so the number is held down rather
  # than driven out, and any new excuse raises it. A ref or fixture with no anchor contributes
  # 0; the tree being gated must have one, which check_stamp_anchor enforces.
  if [ -n "$(stamp_anchor_line "$tc")" ]; then
    excuse_count=0
    for f in $STAMP_EXCUSE_FNS; do
      excuse_count=$((excuse_count + $(fn_kind_refs "$tc" "$f")))
    done
  else
    excuse_count=0
  fi

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
stamp_excuse_kind_refs $excuse_count
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
check_stamp_anchor "$now_root"
rows_now=$(compute_rows "$now_root")

if [ "$update_flag" = "--update" ]; then
  printf '%s\n' "$rows_now" > "$baseline"
  echo "ratchet: baseline written"
  printf '%s\n' "$rows_now"
  exit 0
fi

[ -f "$baseline" ] || { echo "ratchet: no baseline; run scripts/ratchet.sh --update"; exit 1; }

head1_tracked=""
if [ -n "${RATCHET_HEAD1_DIR:-}" ]; then
  head1_root="$RATCHET_HEAD1_DIR"
  check_root "$head1_root"
  rows_head1=$(compute_rows "$head1_root")
elif git rev-parse --verify --quiet "${head1_ref}^{commit}" >/dev/null 2>&1; then
  head1_root=.tmp/ratchet_head1
  materialize_ref "$head1_ref" "$head1_root"
  rows_head1=$(compute_rows "$head1_root")
  # Which rows that commit defined at all. A row added by the commit under
  # test has no previous-commit count: computing it over the older files
  # answers 0 for a metric nobody tracked, which would fail the new row for
  # the fact of existing. Its baseline, written in the same commit, is its
  # first reference.
  head1_tracked=$(git show "${head1_ref}:scripts/ratchet.sh" 2>/dev/null |
    sed -n 's/^\([a-z_][a-z_0-9]*\) \$.*/\1/p' | tr '\n' ' ')
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
  if [ -n "$head1_tracked" ]; then
    case " $head1_tracked " in
      *" $name "*) ;;
      *) h1="$now" ;;
    esac
  fi
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
