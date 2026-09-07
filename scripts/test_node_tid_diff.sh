#!/bin/sh
# Self-test for the node-tid diff harness (BLINK_MONO_DIFF=1), on two
# hand-written files:
#   generic.bl   a generic body with a nested generic call. Every node codegen
#                reads inside the mono instance must come from the recorded
#                table: HIT > 0, and MISS-IN-CTX / MISMATCH / TABLE-ONLY all 0.
#   plain.bl     no generic body at all, so the mono pass records nothing and
#                every read falls back: HIT = 0 and MISS > 0. This is the
#                negative check — it pins the documented gap Stage 2 must close
#                rather than a hook that fakes a failure.
set -u
cd "$(dirname "$0")/.."
BLINK=${BLINK:-build/blink}
WORK=.tmp/node_tid_diff
rm -rf "$WORK"
mkdir -p "$WORK"
fail=0

cat > "$WORK/generic.bl" <<'EOF'
import std.io

fn wrap[T](x: T) -> T { x }

fn outer[T](x: T) -> T {
    let y = wrap(x)
    y
}

fn main() {
    let a = outer(7)
    let b = outer("hi")
    io.println("{a}{b}")
}
EOF

cat > "$WORK/plain.bl" <<'EOF'
import std.io

fn add(a: Int, b: Int) -> Int { a + b }

fn main() {
    let s = add(1, 2)
    io.println("{s}")
}
EOF

totals_line() {
  BLINK_MONO_DIFF=1 "$BLINK" build --emit c "$1" -o "$WORK/out.c" > "$WORK/stdout.txt" 2> "$WORK/err.txt" || true
  /usr/bin/grep -E '^NODE-TID-DIFF TOTALS' "$WORK/err.txt" | tail -1
}

field() {
  printf '%s\n' "$1" | tr ' ' '\n' | /usr/bin/grep "^$2=" | cut -d= -f2
}

check() { # label actual op expected
  label="$1"; got="$2"; op="$3"; want="$4"
  case "$op" in
    eq) [ "$got" = "$want" ] && ok=1 || ok=0 ;;
    gt) [ "$got" -gt "$want" ] 2>/dev/null && ok=1 || ok=0 ;;
    *) ok=0 ;;
  esac
  if [ "$ok" = "1" ]; then
    echo "ok   $label ($got)"
  else
    echo "FAIL $label: got '$got', want $op $want"
    fail=1
  fi
}

gen=$(totals_line "$WORK/generic.bl")
if [ -z "$gen" ]; then
  echo "FAIL generic fixture: no 'NODE-TID-DIFF TOTALS' line under BLINK_MONO_DIFF=1"
  cat "$WORK/err.txt" | tail -5
  exit 1
fi
echo "generic: $gen"
check "generic HIT > 0"          "$(field "$gen" HIT)"          gt 0
check "generic MISS-IN-CTX == 0" "$(field "$gen" MISS-IN-CTX)"  eq 0
check "generic MISMATCH == 0"    "$(field "$gen" MISMATCH)"     eq 0
check "generic TABLE-ONLY == 0"  "$(field "$gen" TABLE-ONLY)"   eq 0

plain=$(totals_line "$WORK/plain.bl")
if [ -z "$plain" ]; then
  echo "FAIL plain fixture: no 'NODE-TID-DIFF TOTALS' line under BLINK_MONO_DIFF=1"
  exit 1
fi
echo "plain:   $plain"
check "plain HIT == 0"    "$(field "$plain" HIT)"  eq 0
check "plain MISS > 0"    "$(field "$plain" MISS)" gt 0

# The gate must be off by default. Cleared explicitly, so an exported
# BLINK_MONO_DIFF in the caller's environment cannot fail this check.
BLINK_MONO_DIFF= "$BLINK" build --emit c "$WORK/generic.bl" -o "$WORK/out.c" > /dev/null 2> "$WORK/off.txt" || true
if /usr/bin/grep -q 'NODE-TID-DIFF' "$WORK/off.txt"; then
  echo "FAIL harness is not gated: NODE-TID-DIFF printed with BLINK_MONO_DIFF unset"
  fail=1
else
  echo "ok   gate off by default"
fi

if [ "$fail" != "0" ]; then
  echo "test-node-tid-diff: FAIL"
  exit 1
fi
echo "test-node-tid-diff: ok"
