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
#   globals.bl   one ANNOTATED module-level global per initializer shape. An
#                annotation must not remove the initializer's type: typecheck
#                walks it either way, so no node in this file may reach codegen
#                without a tid. The fixture must also build clean, or the census
#                measures a run that stopped early.
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

cat > "$WORK/globals.bl" <<'EOF'
type Pt { x: Int, y: Int }
type GBox[T] { v: T }
type GWrap[T] { One(T)  Two }

let g_list: List[Int] = [1, 2, 3]
let g_empty: List[Int] = []
let g_map: Map[Str, Int] = Map()
let g_set: Set[Int] = Set()
let g_struct: Pt = Pt { x: 1, y: 2 }
let g_tuple: (Int, Str) = (7, "hi")
let g_closure: fn(Int) -> Int = fn(n: Int) -> Int { n + 1 }
let g_alias: List[Int] = g_list
let g_none: Option[Int] = None
let g_some: Option[Int] = Some(3)
let g_res: Result[Int, Str] = Ok(1)
let g_nested: List[Map[Str, Int]] = [Map()]
let g_deep: Map[Str, List[Int]] = Map()
let g_box: GBox[Int] = GBox { v: 1 }
let g_wrap: GWrap[Int] = GWrap.One(2)
pub let g_pub: List[Str] = ["a"]
let mut g_mut: List[Int] = [9]
const g_const: List[Int] = [4, 5]
pub const g_const_pub: Str = "k"

fn main() {
    let a = g_list.len() + g_empty.len() + g_map.len() + g_set.len()
    let b = a + g_struct.x + g_alias.len() + g_pub.len() + g_mut.len() + g_nested.len() + g_deep.len() + g_box.v
    let f = g_closure
    let c = f(b) + g_tuple.0
    let d = match g_none { Some(v) => v  None => c }
    let e = match g_some { Some(v) => v + d  None => d }
    let h = match g_res { Ok(v) => v + e  Err(_) => e }
    let k = match g_wrap { One(v) => v + h  Two => h }
    let m = g_const.len() + k + g_const_pub.len()
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

# Run this fixture directly rather than through totals_line, which drops the exit
# status. A build that stops early still prints a TOTALS line, so the census would
# read clean for a file the compiler never finished.
BLINK_MONO_DIFF=1 "$BLINK" build --emit c "$WORK/globals.bl" -o "$WORK/out.c" \
  > "$WORK/stdout.txt" 2> "$WORK/err.txt"
globals_status=$?
check "globals fixture builds clean" "$globals_status" eq 0
if [ "$globals_status" != "0" ]; then
  /usr/bin/grep -E '^(error|warning)' "$WORK/err.txt" | head -5
fi
globals=$(/usr/bin/grep -E '^NODE-TID-DIFF TOTALS' "$WORK/err.txt" | tail -1)
if [ -z "$globals" ]; then
  echo "FAIL globals fixture: no 'NODE-TID-DIFF TOTALS' line under BLINK_MONO_DIFF=1"
  tail -5 "$WORK/err.txt"
  exit 1
fi
echo "globals: $globals"
check "globals MISMATCH == 0"   "$(field "$globals" MISMATCH)"   eq 0
check "globals TABLE-ONLY == 0" "$(field "$globals" TABLE-ONLY)" eq 0
# UNTIDED counts the nodes for which neither channel holds a tid. The whole point of
# the fixture is that an annotated global leaves none, so assert the TOTALS figure and
# not a per-bucket slice: `site` names the codegen chokepoint that asked, not the node
# class, so filtering on it hides whole node kinds.
check "globals UNTIDED == 0" "$(field "$globals" UNTIDED)" eq 0
if [ "$(field "$globals" UNTIDED)" != "0" ]; then
  /usr/bin/grep -E '^NODE-TID-DIFF (BUCKET tag=UNTIDED|UNTIDED)' "$WORK/err.txt" | head -20
fi

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
