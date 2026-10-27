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
# The ids br_ids_in_source knows, in place of br's list: one with a digit, one all letters.
export BR_IDS_FILE="$WORK/br_ids.txt"
printf 'q7tzp2\njkwqzv\n' > "$BR_IDS_FILE"
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
  # Two lines lifted from the real files, so the row regexes are proven against
  # the spellings they exist to count and not against invented text.
  cat > "$dir/src/cg_call.bl" <<'EOF'
if method == "connect" { return cc_build_call(node) }
EOF
  cat > "$dir/src/typecheck.bl" <<'EOF'
let mut named_type_map: Map[Str, Int] = Map()
EOF
  # The type-name row's inputs. Fn and Tuple are on the checker's list but not in the table,
  # and the table lists Spec_only, which the checker lacks: the allowances the row must keep.
  cat >> "$dir/src/typecheck.bl" <<'EOF'
fn is_primitive_type(name: Str) -> Int {
    if tc_declaration_shadows_builtin(name) != 0 { return 0 }
    match name.byte_len() {
        2 => match name {
            "Fn" => 1
            _ => 0
        }
        3 => match name {
            "Int" => 1
            "Buf" => 1
            _ => 0
        }
        4 => match name {
            "Cell" => 0
            _ => 0
        }
        5 => match name {
            "Tuple" => 1
            _ => 0
        }
        _ => 0
    }
}
EOF
  mkdir -p "$dir/sections"
  cat > "$dir/sections/07_trust_modules_metadata.md" <<'EOF'
#### Compiler-Known Type Names (closed set)

| Name | Home | Specified in | Declaring it |
|------|------|--------------|--------------|
| `Int`, `I8` | prelude | §3.2 | reserved |
| `Self` | prelude | §3.3 | reserved |
| `Handler[E]`, `Buf[T]` | prelude | §3.4 | reserved |
| `Spec_only` | prelude | §3.5 | reserved |

Prose naming `Stray` in backticks, outside the table.

#### Shadowing Rules

| `Later` | after the table | x | y |
EOF
  # The node pool with its writers and its columns, a test that imports the pool across
  # lines and only reads it, and a file whose own local list is named `nodes`.
  cat > "$dir/src/parser.bl" <<'EOF'
pub let mut nodes: List[AstNode] = []
let mut columns: NodeColumns = NodeColumns { kinds: [], child_at: [], child_slots: [] }

pub fn parser_reset() {
    nodes.clear()
    columns = NodeColumns { kinds: [], child_at: [], child_slots: [] }
}

pub fn node_push(n: AstNode) -> Int {
    let id = nodes.len()
    nodes.push(n)
    columns.kinds.push(n.kind)
    columns.child_slots.push(id)
    columns.child_at.push(node_child_run(id))
    id
}

pub fn node_pop() {
    let _ = nodes.pop()
    let _ = columns.kinds.pop()
    let _ = columns.child_at.pop()
    node_drop_child_slots_from(0)
}

fn node_replace(id: Int, n: AstNode) {
    nodes.set(id, n)
    columns.kinds.set(id, n.kind)
    columns.child_slots.push(id)
    columns.child_at.set(id, node_child_run(id))
}

fn node_child_run(id: Int) -> Int {
    columns.child_slots.len() - 1
}

fn node_drop_child_slots_from(start: Int) {
    let _ = columns.child_slots.pop()
}

pub fn node_kind(id: Int) -> Int { columns.kinds[id] }

fn node_push_slot_children(id: Int, out: List[Int]) { out.push(columns.child_slots[columns.child_at[id]]) }
EOF
  cat > "$dir/src/free_names.bl" <<'EOF'
fn collect() {
    let mut nodes: List[Int] = []
    nodes.push(1)
}
EOF
  mkdir -p "$dir/tests" "$dir/lib/std"
  cat > "$dir/tests/test_pool_reader.bl" <<'EOF'
import parser.{
    nodes,
    node_kind,
}

test "reads" {
    assert(nodes.len() == 0 || node_kind(0) == nodes[0].kind)
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

# The type-name row: is_primitive_type may not answer for a name the spec table lacks. Each
# case reads back which row failed, so another row rising cannot satisfy it.
check_type_names() {
  label="$1"; want="$2"; file="$3"; sedexpr="$4"
  d="$WORK/tn_$label"
  rm -rf "$d"
  cp -r "$BASE" "$d"
  sed -i "$sedexpr" "$d/$file"
  out=$(RATCHET_SRC_DIR="$d" RATCHET_BASELINE="$BASELINE" RATCHET_HEAD1_DIR="$BASE" ./scripts/ratchet.sh 2>&1)
  rc=$?
  if [ "$want" = fail ]; then
    if [ $rc = 0 ]; then
      echo "FAIL primitive_type_names_outside_spec-$label: ratchet.sh passed"
      fail=1
    elif ! printf '%s\n' "$out" | rg -q '^primitive_type_names_outside_spec .*NONZERO'; then
      echo "FAIL primitive_type_names_outside_spec-$label: the run failed, but not on this row"
      printf '%s\n' "$out"
      fail=1
    else
      echo "PASS primitive_type_names_outside_spec-$label: failed on this row"
    fi
  elif [ $rc != 0 ]; then
    echo "FAIL primitive_type_names_outside_spec-$label: ratchet.sh failed"
    printf '%s\n' "$out"
    fail=1
  else
    echo "PASS primitive_type_names_outside_spec-$label: passed"
  fi
}

check_type_names stray fail src/typecheck.bl 's/"Cell" => 0/"Cell" => 1/'
# A backticked name in prose, or after the table, is not in the table.
check_type_names prose-name fail src/typecheck.bl 's/"Cell" => 0/"Stray" => 1/'
check_type_names after-table-name fail src/typecheck.bl 's/"Cell" => 0/"Later" => 1/'
# Empty parses read as 1, not as a clean 0.
check_type_names no-table fail sections/07_trust_modules_metadata.md 's/Compiler-Known Type Names (closed set)/Renamed/'
check_type_names table-lost-handler fail sections/07_trust_modules_metadata.md 's/`Handler\[E\]`, //'
check_type_names no-arms fail src/typecheck.bl 's/=> 1/=> 0/'
# The spec may list a name the compiler lacks: Spec_only is in the base table already.
check_type_names spec-leads pass sections/07_trust_modules_metadata.md 's/`Spec_only`/`Spec_only`, `Ahead`/'

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

check_row module_let_mut           codegen.bl   'pub let mut other_global2: Int = 0'
check_row br_ids_in_source         codegen.bl   '// also see br xyz987'
# A bare id, an all-letter one, and one in a file outside the codegen layer.
check_row br_ids_in_source         codegen.bl   '// q7tzp2: why this is here'
check_row br_ids_in_source         codegen.bl   'let tag = "jkwqzv_run"'
check_row br_ids_in_source         typecheck.bl '// see jkwqzv'
d="$WORK/row_br_ids_taskfile"
rm -rf "$d"
cp -r "$BASE" "$d"
printf '# the q7tzp2 regression\n' >> "$d/Taskfile.yml"
if RATCHET_SRC_DIR="$d" RATCHET_BASELINE="$BASELINE" RATCHET_HEAD1_DIR="$BASE" ./scripts/ratchet.sh > /dev/null 2>&1; then
  echo "FAIL br_ids_in_source: a bare id in Taskfile.yml did not fail ratchet.sh"
  fail=1
else
  echo "PASS br_ids_in_source: a bare id in Taskfile.yml failed ratchet.sh"
fi
d="$WORK/row_br_ids_words"
rm -rf "$d"
cp -r "$BASE" "$d"
printf '// the parser reads deadbe and cafe12 as a string\n' >> "$d/src/typecheck.bl"
if RATCHET_SRC_DIR="$d" RATCHET_BASELINE="$BASELINE" RATCHET_HEAD1_DIR="$BASE" ./scripts/ratchet.sh > "$d.out" 2>&1 &&
    grep -qE '^br_ids_in_source +0 +0 +0$' "$d.out"; then
  echo "PASS br_ids_in_source: words and hex that are not ids do not count"
else
  echo "FAIL br_ids_in_source counted a token that is not an id:"; cat "$d.out"
  fail=1
fi
mkdir -p "$BASE/tests"
printf '%s\n' 'test "x" { assert(true) }' > "$BASE/tests/test_fixture.bl"
check_tests_row() {
  d="$WORK/tests_row"
  rm -rf "$d"
  cp -r "$BASE" "$d"
  printf '%s\n' '// see br xyz987' >> "$d/tests/test_fixture.bl"
  if RATCHET_SRC_DIR="$d" RATCHET_BASELINE="$BASELINE" RATCHET_HEAD1_DIR="$BASE" ./scripts/ratchet.sh > /dev/null 2>&1; then
    echo "FAIL br_ids_in_test_comments: a +1 on this row did not fail ratchet.sh"
    fail=1
  else
    echo "PASS br_ids_in_test_comments: +1 correctly failed ratchet.sh"
  fi
}
check_tests_row
check_row layout_decline_unhandled cname.bl     'let swallowed = d.decline_reason'

# The two name-keyed rows. A plain "the script failed" check would pass if some
# other row rose instead, so these also read back which row carries the UP mark.
check_named_row() {
  row="$1"; file="$2"; extra="$3"
  d="$WORK/named_$row"
  rm -rf "$d"
  cp -r "$BASE" "$d"
  printf '%s\n' "$extra" >> "$d/src/$file"
  out=$(RATCHET_SRC_DIR="$d" RATCHET_BASELINE="$BASELINE" RATCHET_HEAD1_DIR="$BASE" ./scripts/ratchet.sh 2>&1)
  if [ $? = 0 ]; then
    echo "FAIL $row: a +1 on this row did not fail ratchet.sh"
    fail=1
  elif ! printf '%s\n' "$out" | rg -q "^$row .*UP\\(baseline\\).*UP\\(head~1\\)"; then
    echo "FAIL $row: the run failed, but not on the row under test"
    printf '%s\n' "$out"
    fail=1
  else
    echo "PASS $row: +1 correctly failed ratchet.sh on this row"
  fi
}

check_named_row cg_name_string_compares cg_call.bl \
  'if method == "isatty" { return cc_build_call(node) }'

# A compare in a sibling codegen file must count too: the row is scoped to the
# whole surface so a ladder moved out of cg_call.bl cannot read as a deletion.
# cg_expr.bl is absent from the fixture, so the append creates it.
check_named_row cg_name_string_compares cg_expr.bl \
  'if name == "read_file" { return c_runtime_helper("read_file") }'

# A new table is also a new module global, so the let-mut rows rise with it;
# check_named_row reads back that this row carries the mark as well.
check_named_row typecheck_str_keyed_tables typecheck.bl \
  'let mut tc_new_fact_table: Map[Str, List[Int]] = Map()'

# A module global need not be pub to be shared state.
check_named_row module_let_mut codegen.bl 'let mut em_scratch: Int = 0'
check_named_row typecheck_module_let_mut typecheck.bl 'let mut tc_walk_depth: Int = 0'

# The name row counts every spelling of the same question: a name-like binding
# other than `method`/`name`, a name read through a call, a compare with a named
# constant, a `!=`, and a compare in a codegen file outside the cg_*.bl glob.
check_named_row cg_name_string_compares cg_call.bl \
  'if mname == "len" { return cc_list_len(node) }'
check_named_row cg_name_string_compares cg_reg.bl \
  'if node_name(f) == "main" { has_main = true }'
check_named_row cg_name_string_compares cg_call.bl \
  'if mname == method_display && cc_is_scalar_display_kind(kind) { return 1 }'
check_named_row cg_name_string_compares mono.bl \
  'if trait_name != "Eq" { continue }'
check_named_row cg_name_string_compares cg.bl \
  'if method == "main" { return 1 }'

# The fallback idiom counts anywhere in src/, a field path included.
check_named_row fallback_idiom escape.bl \
  'let key = if decl >= 0 { decl } else { hit }'
check_named_row fallback_idiom cg_eff.bl \
  'let fwd = if th.forward_to >= 0 { th.forward_to } else { 0 }'

# Both spellings of the old offset read count, in any src/ file.
check_named_row str_substring_callers lexer.bl \
  'let word = source.substring(start, scan_pos - start)'
check_named_row str_substring_callers typecheck.bl \
  'let head = name.substr(0, dot)'

# In lib/, `substr` counts and `substring` does not: lib/ may still read by codepoint.
LIBSUBSTR="$WORK/lib_substr"
rm -rf "$LIBSUBSTR"
cp -r "$BASE" "$LIBSUBSTR"
printf '%s\n' 'fn head(s: Str) -> Str { s.substr(0, 1) }' >> "$LIBSUBSTR/lib/std/text.bl"
out=$(RATCHET_SRC_DIR="$LIBSUBSTR" RATCHET_BASELINE="$BASELINE" RATCHET_HEAD1_DIR="$BASE" ./scripts/ratchet.sh 2>&1)
if [ $? = 0 ]; then
  echo "FAIL str_substring_callers-lib: a lib/ substr did not fail ratchet.sh"
  fail=1
elif ! printf '%s\n' "$out" | rg -q '^str_substring_callers .*NONZERO'; then
  echo "FAIL str_substring_callers-lib: the run failed, but not on str_substring_callers"
  printf '%s\n' "$out"
  fail=1
else
  echo "PASS str_substring_callers-lib: a lib/ substr failed ratchet.sh"
fi
LIBSUBSTRING="$WORK/lib_substring"
rm -rf "$LIBSUBSTRING"
cp -r "$BASE" "$LIBSUBSTRING"
printf '%s\n' 'fn head(s: Str) -> Str { s.substring(0, 1) }' >> "$LIBSUBSTRING/lib/std/text.bl"
if RATCHET_SRC_DIR="$LIBSUBSTRING" RATCHET_BASELINE="$BASELINE" RATCHET_HEAD1_DIR="$BASE" ./scripts/ratchet.sh > /dev/null 2>&1; then
  echo "PASS str_substring_callers-lib-substring: a lib/ substring passed ratchet.sh"
else
  echo "FAIL str_substring_callers-lib-substring: a lib/ substring failed ratchet.sh"
  fail=1
fi

# A codepoint length used as a byte offset counts in src/ and lib/, nested calls
# included; byte_len in the same place does not.
check_named_row str_len_in_byte_args lexer.bl \
  'let tail = raw.byte_slice(0, raw.len() - 1)'
check_named_row str_len_in_byte_args typecheck.bl \
  'let last = s.byte_at(max(0, s.len() - 1))'
LENARGS="$WORK/lib_len_args"
rm -rf "$LENARGS"
cp -r "$BASE" "$LENARGS"
printf '%s\n' 'fn from_end(s: Str, n: Str) -> Option[Int] { s.byte_index_of(n, s.len() - n.len()) }' >> "$LENARGS/lib/std/text.bl"
out=$(RATCHET_SRC_DIR="$LENARGS" RATCHET_BASELINE="$BASELINE" RATCHET_HEAD1_DIR="$BASE" ./scripts/ratchet.sh 2>&1)
if [ $? = 0 ]; then
  echo "FAIL str_len_in_byte_args-lib: a lib/ len in byte_index_of did not fail ratchet.sh"
  fail=1
elif ! printf '%s\n' "$out" | rg -q '^str_len_in_byte_args .*NONZERO'; then
  echo "FAIL str_len_in_byte_args-lib: the run failed, but not on str_len_in_byte_args"
  printf '%s\n' "$out"
  fail=1
else
  echo "PASS str_len_in_byte_args-lib: a lib/ len in byte_index_of failed ratchet.sh"
fi
BYTELEN="$WORK/lib_byte_len_args"
rm -rf "$BYTELEN"
cp -r "$BASE" "$BYTELEN"
printf '%s\n' 'fn chop(s: Str) -> Str { s.byte_slice(0, s.byte_len() - 1) }' >> "$BYTELEN/lib/std/text.bl"
if RATCHET_SRC_DIR="$BYTELEN" RATCHET_BASELINE="$BASELINE" RATCHET_HEAD1_DIR="$BASE" ./scripts/ratchet.sh > /dev/null 2>&1; then
  echo "PASS str_len_in_byte_args-byte-len: a byte_len bound passed ratchet.sh"
else
  echo "FAIL str_len_in_byte_args-byte-len: a byte_len bound failed ratchet.sh"
  fail=1
fi

# A branch on one value that answers with another is not the idiom: the row
# needs the same name on both sides, or it counts every signed compare.
NOFALLBACK="$WORK/no_fallback"
rm -rf "$NOFALLBACK"
cp -r "$BASE" "$NOFALLBACK"
printf '%s\n' 'let v = if a >= 0 { b } else { c }' >> "$NOFALLBACK/src/escape.bl"
if ! RATCHET_SRC_DIR="$NOFALLBACK" RATCHET_BASELINE="$BASELINE" RATCHET_HEAD1_DIR="$BASE" ./scripts/ratchet.sh > /dev/null 2>&1; then
  echo "FAIL fallback_idiom-distinct: a branch that answers with another value was counted"
  fail=1
else
  echo "PASS fallback_idiom-distinct: a branch that answers with another value is not counted"
fi

# An indented table is a function local, not a module-scope fact table, so the
# row must not count it. Without this the regex could be a bare substring match.
NOLOCAL="$WORK/no_local_table"
rm -rf "$NOLOCAL"
cp -r "$BASE" "$NOLOCAL"
printf '%s\n' '    let mut inside_a_fn: Map[Str, Int] = Map()' >> "$NOLOCAL/src/typecheck.bl"
if ! RATCHET_SRC_DIR="$NOLOCAL" RATCHET_BASELINE="$BASELINE" RATCHET_HEAD1_DIR="$BASE" ./scripts/ratchet.sh > /dev/null 2>&1; then
  echo "FAIL typecheck_str_keyed_tables-local: an indented (function-local) table was counted as a module-scope one"
  fail=1
else
  echo "PASS typecheck_str_keyed_tables-local: a function-local table is not counted"
fi

# A decline read whose ICE sits four lines away is unhandled: the window is
# the same line plus the next three, so this must count.
check_row layout_decline_unhandled cname.bl     'let far = d.decline_reason
// one
// two
// three
diag_ice("TooLate", far)'

# node_pool_writes is an absolute zero gate over src/, lib/ and tests/: each
# write below bypasses the writers that keep the columns in step with the
# pool, and must fail on that row.
check_pool_write() {
  label="$1"; file="$2"; extra="$3"
  d="$WORK/pool_$label"
  rm -rf "$d"
  cp -r "$BASE" "$d"
  printf '%s\n' "$extra" >> "$d/$file"
  out=$(RATCHET_SRC_DIR="$d" RATCHET_BASELINE="$BASELINE" RATCHET_HEAD1_DIR="$BASE" ./scripts/ratchet.sh 2>&1)
  if [ $? = 0 ]; then
    echo "FAIL node_pool_writes-$label: a write outside the writers did not fail ratchet.sh"
    fail=1
  elif ! printf '%s\n' "$out" | rg -q '^node_pool_writes .*NONZERO'; then
    echo "FAIL node_pool_writes-$label: the run failed, but not on node_pool_writes"
    printf '%s\n' "$out"
    fail=1
  else
    echo "PASS node_pool_writes-$label: a write outside the writers failed ratchet.sh"
  fi
}

check_pool_write parser-push src/parser.bl 'fn scratch() -> Int {
    nodes.push(AstNode {})
    0
}'
check_pool_write test-pop tests/test_pool_reader.bl 'fn drop_one() { let _ = nodes.pop() }'
check_pool_write test-set tests/test_pool_reader.bl 'fn swap_in() { nodes.set(0, AstNode {}) }'
check_pool_write test-field tests/test_pool_reader.bl 'fn rekind() { nodes[0].kind = 3 }'
check_pool_write lib-qualified lib/std/pool_user.bl 'fn drop_one() { let _ = parser.nodes.pop() }'
check_pool_write parser-column-push src/parser.bl 'fn scratch() { columns.child_slots.push(0) }'
check_pool_write parser-column-set src/parser.bl 'fn scratch() { columns.child_at.set(0, 1) }'
check_pool_write parser-column-slot src/parser.bl 'fn scratch() { columns.kinds[0] = 3 }'

# repo_tmp_in_tests_and_scripts is an absolute zero gate: a `.tmp/` path added to a
# test or a script must fail on that row, inside a tree the file made itself too.
check_repo_tmp() {
  label="$1"; file="$2"; extra="$3"; want="$4"
  d="$WORK/repotmp_$label"
  rm -rf "$d"
  cp -r "$BASE" "$d"
  mkdir -p "$d/$(dirname "$file")"
  printf '%s\n' "$extra" >> "$d/$file"
  out=$(RATCHET_SRC_DIR="$d" RATCHET_BASELINE="$BASELINE" RATCHET_HEAD1_DIR="$BASE" ./scripts/ratchet.sh 2>&1)
  rc=$?
  hit=0
  printf '%s\n' "$out" | rg -q '^repo_tmp_in_tests_and_scripts .*NONZERO' && hit=1
  if [ "$want" = fail ] && [ "$rc" = 0 ]; then
    echo "FAIL repo_tmp-$label: a .tmp/ scratch path did not fail ratchet.sh"
    fail=1
  elif [ "$want" = fail ] && [ "$hit" = 0 ]; then
    echo "FAIL repo_tmp-$label: the run failed, but not on repo_tmp_in_tests_and_scripts"
    printf '%s\n' "$out"
    fail=1
  elif [ "$want" = pass ] && [ "$hit" = 1 ]; then
    echo "FAIL repo_tmp-$label: a name that only ends in .tmp was counted"
    printf '%s\n' "$out"
    fail=1
  else
    echo "PASS repo_tmp-$label"
  fi
}

check_repo_tmp test-bare tests/test_scratch_user.bl 'let p = ".tmp/probe/x.bl"' fail
check_repo_tmp test-var-prefixed tests/test_scratch_user.bl 'let p = "{dir}/.tmp/probe.bl"' fail
check_repo_tmp script-mktemp scripts/some_gate.sh 'f=$(mktemp .tmp/gate-XXXXXX)' fail
check_repo_tmp test-root-prefixed tests/test_scratch_user.bl 'let p = "{root}/.tmp/probe.bl"' fail
check_repo_tmp test-suffix-name-not-counted tests/test_scratch_user.bl 'let p = "{dir}/plain.tmp/x"' pass
check_repo_tmp test-private-tree tests/test_scratch_user.bl 'shell_exec("mkdir -p {tree}/.tmp")
write_file("{tree}/.tmp/x.o", "")' fail
check_repo_tmp script-private-tree scripts/some_gate.sh 'mkdir -p "$work/.tmp/"' fail
check_repo_tmp taskfile-scratch Taskfile.yml '      - mkdir -p .tmp/x' fail
check_repo_tmp test-object-read tests/test_scratch_user.bl 'shell_exec("cp .tmp/*.o {dir}/")' fail
check_pool_write parser-column-field src/parser.bl 'fn scratch() { columns.child_slots = [] }'
check_pool_write parser-column-whole src/parser.bl 'fn scratch() { columns = NodeColumns { kinds: [], child_at: [], child_slots: [] } }'

# A steady write that the baseline and HEAD~1 already hold still fails.
POOL_STEADY="$WORK/pool_steady"
rm -rf "$POOL_STEADY"
cp -r "$BASE" "$POOL_STEADY"
printf '%s\n' 'fn drop_one() { let _ = nodes.pop() }' >> "$POOL_STEADY/tests/test_pool_reader.bl"
POOL_STEADY_BASELINE="$WORK/pool_steady_baseline.txt"
RATCHET_SRC_DIR="$POOL_STEADY" RATCHET_BASELINE="$POOL_STEADY_BASELINE" ./scripts/ratchet.sh --update > /dev/null
if RATCHET_SRC_DIR="$POOL_STEADY" RATCHET_BASELINE="$POOL_STEADY_BASELINE" RATCHET_HEAD1_DIR="$POOL_STEADY" ./scripts/ratchet.sh > /dev/null 2>&1; then
  echo "FAIL node_pool_writes-absolute-zero: baseline=1, head~1=1, now=1 should still fail"
  fail=1
else
  echo "PASS node_pool_writes-absolute-zero: a steady pool write fails even though it does not increase"
fi

# A file's own list that is named `nodes` is not the pool.
POOL_LOCAL="$WORK/pool_local_list"
rm -rf "$POOL_LOCAL"
cp -r "$BASE" "$POOL_LOCAL"
printf '%s\n' 'fn more(nodes: List[Int]) { nodes.push(2) }' >> "$POOL_LOCAL/src/free_names.bl"
if ! RATCHET_SRC_DIR="$POOL_LOCAL" RATCHET_BASELINE="$BASELINE" RATCHET_HEAD1_DIR="$BASE" ./scripts/ratchet.sh > /dev/null 2>&1; then
  echo "FAIL node_pool_writes-local-list: a push to a local list named nodes was counted"
  fail=1
else
  echo "PASS node_pool_writes-local-list: a local list named nodes is not counted"
fi

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
cp ./scripts/ratchet.sh ./scripts/br_ids.sh "$GITWORK/scripts/"
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

# The branch walk: every commit in main..HEAD against its parents. The tip
# compare alone cannot see a rise that a later commit on the branch paid back.
WALKWORK="$WORK/walkrepo"
mkdir -p "$WALKWORK/scripts" "$WALKWORK/src"
cp ./scripts/ratchet.sh ./scripts/br_ids.sh "$WALKWORK/scripts/"
chmod +x "$WALKWORK/scripts/ratchet.sh"
echo 'pub let mut a: Int = 0' > "$WALKWORK/src/codegen.bl"
: > "$WALKWORK/Taskfile.yml"
(
  cd "$WALKWORK" || exit 1
  git init -q -b main .
  git config user.email t@example.com
  git config user.name t
  ./scripts/ratchet.sh --update > /dev/null
  git add -A
  git commit -q -m base

  git checkout -q -b neutral
  echo '// no count change' >> src/codegen.bl
  git commit -q -am "neutral edit"
  if ! ./scripts/ratchet.sh > /dev/null 2>&1; then
    echo "FAIL git-walk-neutral: a branch whose commits raise nothing must pass"
    exit 1
  fi
  echo "PASS git-walk-neutral: a branch whose commits raise nothing passes"

  git checkout -q main
  git checkout -q -b paid_back
  echo 'pub let mut b: Int = 0' >> src/codegen.bl
  git commit -q -am "raise a row"
  sed -i '/pub let mut b/d' src/codegen.bl
  git commit -q -am "pay it back"
  walk_out=$(./scripts/ratchet.sh 2>&1)
  if [ $? = 0 ]; then
    echo "FAIL git-walk-paid-back: a mid-branch rise paid back by a later commit must fail"
    printf '%s\n' "$walk_out"
    exit 1
  fi
  if ! printf '%s\n' "$walk_out" | rg -q 'raise a row: module_let_mut 1 -> 2$'; then
    echo "FAIL git-walk-paid-back: the run failed, but did not name the commit and row that rose"
    printf '%s\n' "$walk_out"
    exit 1
  fi
  echo "PASS git-walk-paid-back: a mid-branch rise is caught although the tip paid it back"

  # A merge of main brings main's own counts. The merge rises only when it
  # passes every parent, so a row main raised is not charged to the branch.
  git checkout -q main
  echo 'pub let mut m: Int = 0' > src/main_only.bl
  git add -A
  git commit -q -m "main raises a row"
  git checkout -q neutral
  git merge -q --no-edit main > /dev/null 2>&1 || { echo "FAIL git-walk-merge: fixture merge conflicted"; exit 1; }
  ./scripts/ratchet.sh --update > /dev/null
  git commit -q -am "rebaseline" > /dev/null 2>&1 || true
  if ! RATCHET_HEAD1_REF=HEAD ./scripts/ratchet.sh > /dev/null 2>&1; then
    echo "FAIL git-walk-merge: a merge of main was charged with a row main raised"
    RATCHET_HEAD1_REF=HEAD ./scripts/ratchet.sh 2>&1 | sed 's/^/    /'
    exit 1
  fi
  echo "PASS git-walk-merge: a merge rises only when it passes every parent"
)
if [ $? != 0 ]; then fail=1; fi

if [ "$fail" != 0 ]; then
  echo "test_ratchet: FAILED"
  exit 1
fi
echo "test_ratchet: all checks passed"
