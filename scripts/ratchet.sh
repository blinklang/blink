#!/bin/sh
# Ratchet on the flat type channels in codegen. Each count may only go down.
# The exit criterion for tid-sole-authority is every row reading 0.
#   scripts/ratchet.sh            compare against scripts/ratchet_baseline.txt
#   scripts/ratchet.sh --update   rewrite the baseline from the current counts
set -u
cd "$(dirname "$0")/.."
baseline=scripts/ratchet_baseline.txt
files="src/codegen*.bl"

count() { rg -o "$1" $files 2>/dev/null | wc -l | tr -d ' '; }

expr_globals=$(rg -o '^pub let mut (expr_[a-z_0-9]+)' -r '$1' src/codegen_expr.bl | paste -sd'|')

rows=$(cat <<ROWS
ct_refs $(count '\bCT_[A-Z_]+\b')
type_from_name $(count '\btype_from_name(_tag)?\(')
tc_tid_ct $(count '\btc_tid_ct\(')
expr_result_type $(count '\bexpr_result_type\b')
expr_globals $(count "\\b(${expr_globals})\\b")
flat_scopevar_accessors $(count '\b(get|set)_(var|sv|list_elem|map_key|map_value|set_elem|option_inner|result_ok|result_err|tuple_elem)[a-z_0-9]*\(')
typename_string_compares $(count '== "[A-Z][A-Za-z]*"')
lossy_ann_string_reads $(count '\bnode_(type_name|return_type)\(')
ROWS
)

if [ "${1:-}" = "--update" ]; then
  printf '%s\n' "$rows" > "$baseline"
  echo "ratchet: baseline written"
  printf '%s\n' "$rows"
  exit 0
fi

[ -f "$baseline" ] || { echo "ratchet: no baseline; run scripts/ratchet.sh --update"; exit 1; }

fail=0
printf '%-26s %8s %8s\n' metric baseline now
printf '%s\n' "$rows" | while read -r name now; do
  base=$(awk -v n="$name" '$1==n{print $2}' "$baseline")
  [ -z "$base" ] && base=0
  mark=""
  if [ "$now" -gt "$base" ]; then mark="  UP"; fi
  printf '%-26s %8s %8s%s\n' "$name" "$base" "$now" "$mark"
done
printf '%s\n' "$rows" | while read -r name now; do
  base=$(awk -v n="$name" '$1==n{print $2}' "$baseline")
  [ -z "$base" ] && base=0
  [ "$now" -gt "$base" ] && exit 1
  :
done || fail=1
if [ "$fail" = 1 ]; then
  echo "ratchet: a flat type-channel count went UP. Remove the new use, or lower another row."
  exit 1
fi
echo "ratchet: ok"
