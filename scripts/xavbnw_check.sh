#!/usr/bin/env bash
# xavbnw_check.sh — failing-test harness for br xavbnw.
#
# For each stdlib file that still load-bears on @module(""), strip the
# annotation, run `task regen` + `task test`, and report pass/fail.
# Files are restored on EXIT so a Ctrl-C mid-iteration can't leave the
# stdlib mutated.
#
# list.bl deliberately omitted: list_concat/list_slice are runtime-bridge
# symbols (build/runtime.h provides BLINK_RT_FN blink_list_concat), and
# method dispatch in codegen_methods.bl emits c_fn_name("list_concat")
# expecting the bare runtime form. Stripping @module("") from list.bl
# breaks that pairing until C-mangling is driven by node_source_module()
# instead of the @module-as-codegen-hack — tracked by br gcec5v
# (project:tc83pp).

set -u

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"

declare -A FILES=(
  ["lib/std/str.bl"]="A — bare cross-module calls"
  ["lib/std/sb.bl"]="A — bare cross-module calls"
  ["lib/std/bytes.bl"]="A — bare cross-module calls"
  ["lib/std/num.bl"]="B — codegen_derive hardcoded literals"
)

if ! git diff --quiet -- "${!FILES[@]}"; then
  echo "xavbnw-check: refusing to run — target stdlib files have uncommitted edits."
  echo "Commit or stash before running this harness."
  exit 2
fi

LOG_DIR=$(mktemp -d)
trap 'rm -rf "$LOG_DIR"; git checkout -- "${!FILES[@]}" 2>/dev/null || true' EXIT

pass=0
fail=0
declare -a failures

for f in "${!FILES[@]}"; do
  echo "=== xavbnw-check: $f (Class ${FILES[$f]}) ==="

  if ! grep -qE '^@module\(""\)' "$f"; then
    echo "  SKIP: no @module(\"\") at start of $f — nothing to strip."
    continue
  fi
  sed -i '/^@module("")$/d' "$f"

  # task regen guards the gen1/gen2 self-host invariant; task test exercises
  # the user-facing surface where Class B/C failures land. Both must pass.
  log="$LOG_DIR/$(basename "$f").log"
  if ! task regen > "$log" 2>&1; then
    echo "  FAIL (regen) — see $log (last 20 lines):"
    tail -n 20 "$log" | sed 's/^/    /'
    fail=$((fail + 1))
    failures+=("$f (Class ${FILES[$f]})")
  elif ! task test >> "$log" 2>&1; then
    echo "  FAIL (test) — see $log (last 30 lines):"
    tail -n 30 "$log" | sed 's/^/    /'
    fail=$((fail + 1))
    failures+=("$f (Class ${FILES[$f]})")
  else
    echo "  PASS"
    pass=$((pass + 1))
  fi

  git checkout -- "$f"
done

echo
echo "=== xavbnw-check summary ==="
echo "  pass: $pass / ${#FILES[@]}"
echo "  fail: $fail / ${#FILES[@]}"
if [ "$fail" -gt 0 ]; then
  echo "  failing files:"
  for f in "${failures[@]}"; do
    echo "    - $f"
  done
  exit 1
fi
echo "xavbnw-check: ok — all files regen-clean without @module(\"\")"
