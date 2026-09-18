#!/bin/sh
# Ratchet on the compiler-debt counts that survive the codegen rewrite. Each
# row must not go up against two references: the stored baseline, and the
# same count computed on the files as they stood in the previous commit.
# The second check catches a regression that fits inside headroom banked by
# an earlier, unrelated deletion instead of paying for itself.
#   scripts/ratchet.sh            compare current counts against both references
#   scripts/ratchet.sh --update   rewrite the baseline from the current counts
#
# Rows:
#   br_ids_in_source         a br ticket id anywhere in src/ or Taskfile.yml;
#                            absolute zero gate (br is local-only)
#   pub_let_mut              mutable module globals anywhere in src/. Scoped to the
#                            whole surface on purpose: a row named after the files it
#                            exists to empty reads 0 by construction once they are
#                            deleted, and then gates nothing. The codegen-surface half
#                            of this rule lives in lint_codegen.sh rows L3, which hold
#                            src/cg*.bl to an allowlist and an absolute zero
#   layout_decline_unhandled a layout decline read outside layout.bl that no
#                            diag_ice within the next three lines turns into
#                            an ICE (a swallowed decline is a guessed answer)
#   cg_name_string_compares  dispatch keyed on a spelled-out method or fn name:
#                            `\b(method|name)\s*==\s*"` anywhere in src/cg_*.bl.
#                            The rewrite answers these from a tid, so every one
#                            left is a question asked of a string. Scoped to the
#                            whole codegen surface rather than to cg_call.bl,
#                            where all but six of them sit today: a row that
#                            counts one file pays a ladder moved to a sibling as
#                            a deletion, and the debt would read as repaid for
#                            having been relocated
#   typecheck_str_keyed_tables
#                            module-scope Map[Str, _] fact tables in
#                            src/typecheck.bl: `^(pub )?let mut <name>: Map[Str`.
#                            A fact filed under a spelled name is a fact the tid
#                            cannot answer, and each table is a second place for
#                            a type to be described
#
# After its own rows, this script runs scripts/lint_codegen.sh, the L1-L11
# lint over the rewrite's files, and fails if that fails. RATCHET_NO_LINT=1
# skips it (the self-test uses this; the lint has its own proofs).
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
# immediate parent.
#
# Env overrides (used by scripts/test_ratchet.sh; normal runs need none):
#   RATCHET_SRC_DIR   root dir standing in for the repo root when computing
#                     "now" (must contain src/ and Taskfile.yml). Default: .
#   RATCHET_BASELINE  baseline file path. Default: scripts/ratchet_baseline.txt
#   RATCHET_HEAD1_DIR root dir standing in for the previous-commit snapshot,
#                     bypassing git entirely. Default: unset (materialize
#                     RATCHET_HEAD1_REF via git into .tmp/ratchet_head1).
#   RATCHET_HEAD1_REF git ref to materialize when RATCHET_HEAD1_DIR is unset.
#   RATCHET_NO_LINT   1 to skip scripts/lint_codegen.sh.
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
# must run OUTSIDE any $(...): compute_rows is always invoked inside a
# command substitution, where `exit` would only kill that subshell.
check_root() {
  case "$1" in
    *[[:space:]]*)
      echo "ratchet: error: '$1' contains whitespace, which this script cannot count reliably. Rerun from a path with no spaces." >&2
      exit 1
      ;;
  esac
}

# Reads of a layout decline outside layout.bl with no diag_ice on the same
# line or the next three. The window is short on purpose: the ICE must be
# the direct answer to the decline, not something a later branch may reach.
decline_unhandled() {
  total=0
  for f in "$1"/src/cname.bl "$1"/src/mono.bl "$1"/src/ir.bl "$1"/src/cg_*.bl; do
    [ -f "$f" ] || continue
    n=$(awk '
      { line[NR] = $0 }
      END {
        c = 0
        for (i = 1; i <= NR; i++) {
          if (line[i] !~ /decline_reason/) continue
          ok = 0
          for (j = i; j <= i + 3 && j <= NR; j++) if (line[j] ~ /diag_ice/) ok = 1
          if (!ok) c++
        }
        print c
      }' "$f")
    total=$((total + n))
  done
  echo "$total"
}

# Takes a root dir instead of reading the repo directly, so the same row
# definitions run against the real tree, a materialized historical ref, or a
# synthetic test fixture without duplicating the row list three times.
compute_rows() {
  root="$1"
  allbl="$root/src/*.bl"
  cgbl="$root/src/cg_*.bl"
  tcbl="$root/src/typecheck.bl"
  tf="$root/Taskfile.yml"

  cat <<ROWS
br_ids_in_source $(( $(cnt '\bbr [0-9a-z]{6}\b' "$allbl $tf") + $(cnt '\b(g3sba0|qf1vzx|0kpmac)\b' "$allbl $tf") ))
pub_let_mut $(cnt '^pub let mut' "$allbl")
layout_decline_unhandled $(decline_unhandled "$root")
cg_name_string_compares $(cnt '\b(method|name)\s*==\s*"' "$cgbl")
typecheck_str_keyed_tables $(cnt '^(pub )?let mut [A-Za-z_][A-Za-z_0-9]*: Map\[Str' "$tcbl")
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

head1_tracked=""
if [ -n "${RATCHET_HEAD1_DIR:-}" ]; then
  head1_root="$RATCHET_HEAD1_DIR"
  check_root "$head1_root"
  rows_head1=$(compute_rows "$head1_root")
elif git rev-parse --verify --quiet "${head1_ref}^{commit}" >/dev/null 2>&1; then
  head1_root=.tmp/ratchet_head1
  materialize_ref "$head1_ref" "$head1_root"
  rows_head1=$(compute_rows "$head1_root")
  # A row added by the commit under test has no previous-commit count:
  # computing it over the older files answers 0 for a metric nobody tracked,
  # which would fail the new row for the fact of existing. Its baseline,
  # written in the same commit, is its first reference.
  head1_tracked=$(git show "${head1_ref}:scripts/ratchet.sh" 2>/dev/null |
    sed -n 's/^\([a-z_][a-z_0-9]*\) \$.*/\1/p' | tr '\n' ' ')
else
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
  # Absolute zero gates: an id means nothing to another reader or to training
  # data, and a swallowed decline is a wrong answer waiting to be found.
  case "$name" in
    br_ids_in_source|layout_decline_unhandled)
      [ "$now" -gt 0 ] && mark="$mark NONZERO(must-be-zero)" ;;
  esac
  printf '%-26s %8s %8s %8s%s\n' "$name" "$base" "$h1" "$now" "$mark"
  [ -n "$mark" ] && printf x >> "$failmark"
done

if [ -s "$failmark" ]; then
  echo "ratchet: a tracked count went up against the baseline or the previous commit. Remove the new use, or lower another row."
  exit 1
fi
echo "ratchet: ok"

if [ "${RATCHET_NO_LINT:-0}" != 1 ] && [ -x scripts/lint_codegen.sh ]; then
  ./scripts/lint_codegen.sh || exit 1
fi
