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
#   br_ids_in_test_comments  a `br <id>` in a `//` comment under tests/; absolute
#                            zero gate. Counted in the live tree only: a
#                            historical ref is materialized with src/ alone
#   module_let_mut           mutable module globals anywhere in src/: every
#                            column-0 `let mut`, pub or not. A global need not be
#                            pub to be shared state. Scoped to the whole surface on
#                            purpose: a row named after the files it exists to empty
#                            reads 0 by construction once they are deleted, and then
#                            gates nothing. The codegen-surface half of this rule
#                            lives in lint_codegen.sh rows L3
#   typecheck_module_let_mut the same count in src/typecheck.bl alone, where most
#                            of them live, so growth there shows on its own row
#   layout_decline_unhandled a layout decline read outside layout.bl that no
#                            diag_ice within the next three lines turns into
#                            an ICE (a swallowed decline is a guessed answer)
#   cg_name_string_compares  dispatch keyed on a spelled-out method, trait or fn
#                            name, anywhere on the codegen surface (the files
#                            lint_codegen.sh scans). Two spellings count: a
#                            name-like binding or call (`mname`, `trait_name`,
#                            `node_name(f)`) compared with a string literal, and
#                            any compare with a named constant (`== method_display`),
#                            which is the same string under another name. The
#                            rewrite answers these from a tid, so every one left
#                            is a question asked of a string. A call with nested
#                            parentheses on the left is not seen, so the count is
#                            a lower bound. Scoped to the whole surface rather than
#                            to cg_call.bl: a row that counts one file pays a ladder
#                            moved to a sibling as a deletion. Not all of src/:
#                            the typechecker resolves identifiers by name, which
#                            no tid answers
#   fallback_idiom           `if x >= 0 { x } else { ... }` anywhere in src/: a
#                            missing answer turned into a default instead of an
#                            error. lint_codegen.sh row L2 holds the codegen
#                            surface to zero; this row keeps the rest from growing
#   typecheck_str_keyed_tables
#                            module-scope Map[Str, _] fact tables in
#                            src/typecheck.bl: `^(pub )?let mut <name>: Map[Str`.
#                            A fact filed under a spelled name is a fact the tid
#                            cannot answer, and each table is a second place for
#                            a type to be described
#   node_pool_writes         writes to the parser's node pool, the non-pub
#                            `columns` (the head words, the Int and Str payload
#                            arenas, the shape tables and the child-slot
#                            columns), outside node_push, node_pop,
#                            node_replace, parser_reset, parser_rewind (which
#                            puts back the values node_replace and the writers
#                            recorded, then cuts the pool to a parse's end), the
#                            two plain-field writers and the store, shape, arena
#                            and child-slot helpers they call; absolute zero gate. A
#                            plain-field writer writes only a field the child
#                            table never reads. Any other write can leave a
#                            payload that its head word's shape does not
#                            describe. Counted in src/, lib/ and
#                            tests/: in parser.bl
#                            outside the writers, and in every file that imports
#                            `nodes` from parser or spells `parser.nodes`, the
#                            name the pool had before it was split into
#                            columns. A historical ref is
#                            materialized with src/ alone, so its count leaves out
#                            lib/ and tests/; the zero gate still holds the tree
#   str_substring_callers    a `.substring(` or `.substr(` call anywhere in src/,
#                            or a `.substr(` call anywhere in lib/; absolute zero
#                            gate. src/ reads text by byte offset, which
#                            Str.byte_slice names, and Str has no `substr`.
#                            lib/ may still call `substring`. Str.slice is gone
#                            too but is not counted: the text alone cannot tell
#                            it from List.slice and Bytes.slice
#   str_len_in_byte_args     a `.len()` inside the argument list of a
#                            `.byte_slice(`, `.byte_at(` or `.byte_index_of(`
#                            call in src/ or lib/; absolute zero gate. Str.len
#                            counts codepoints and those methods take byte
#                            offsets, so the bound is byte_len. Only a call on
#                            one line is seen, so the count is a lower bound
#   primitive_type_names_outside_spec
#                            a name `is_primitive_type` in src/typecheck.bl
#                            answers `=> 1` for that the table under "Compiler-Known
#                            Type Names (closed set)" in sections/07 does not
#                            list; absolute zero gate. The table is closed, so a
#                            name the compiler accepts and the spec lacks is a
#                            built-in the spec never allowed. One direction only:
#                            the spec may list a name the compiler lacks yet,
#                            because the spec leads the compiler. Fn and Tuple
#                            are exempt: `fn(A) -> B` and `(A, B)` reach the
#                            checker as annotations spelled so, and stay on the
#                            list until every reader tells them apart by their
#                            marker. A parse that finds no table, or no Int in
#                            the checker's list, counts as 1, so a changed layout
#                            cannot read as a clean 0, and so does a missing
#                            spec file. A root with no typecheck.bl counts 0
#
#   repo_tmp_in_tests_and_scripts
#                            a `.tmp/` path in a tests/*.bl or scripts/*.sh file;
#                            absolute zero gate. Scratch files go in a dir of their
#                            own under TMPDIR, so two runs at once never share
#                            one (compile_test_helpers.scratch_root() in a test,
#                            `mktemp -d` in a script). A path under a private
#                            tree (`{tree}/.tmp/`, `$work/.tmp/`) is not counted: it is
#                            the compiler's own `.tmp` inside a tree the test or
#                            script made. Nor is a read of `.tmp/*.o`. This script
#                            and its self-test are not scanned, because they name
#                            the pattern. Counted in the live tree only: a
#                            historical ref is materialized with src/ alone
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
# of failing every row against an empty tree.
#
# Every commit on the branch is also checked against its parent: each commit
# in RATCHET_BASE_REF..HEAD (default main) must not raise a tracked row. A
# tip-only compare lets a mid-branch rise through when a later commit pays it
# back. A merge commit rises only when it passes every parent. When the base
# ref does not resolve, or HEAD is on it, there is nothing to walk.
#
# Env overrides (used by scripts/test_ratchet.sh; normal runs need none):
#   RATCHET_SRC_DIR   root dir standing in for the repo root when computing
#                     "now" (must contain src/ and Taskfile.yml). Default: .
#   RATCHET_BASELINE  baseline file path. Default: scripts/ratchet_baseline.txt
#   RATCHET_HEAD1_DIR root dir standing in for the previous-commit snapshot,
#                     bypassing git entirely. Default: unset (materialize
#                     RATCHET_HEAD1_REF via git into a temp dir).
#   RATCHET_HEAD1_REF git ref to materialize when RATCHET_HEAD1_DIR is unset.
#   RATCHET_BASE_REF  the ref the branch walk starts from. Default: main. The
#                     walk is skipped when RATCHET_HEAD1_DIR is set.
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
# PCRE, for a pattern that needs a backreference.
pcnt() { rg -oP "$1" $2 2>/dev/null | wc -l | tr -d ' '; }

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

# Mutating calls on the pool and assignments into a slot or a field of one, spelled bare or as
# `parser.nodes`.
POOL_WRITE='\b(parser\.)?nodes(\.(push|pop|set|clear|insert|remove|truncate|append|extend|reverse|sort|swap)\(|\[[^]]*\](\.[a-z_]+)*\s*=[^=])'
# The same writes to a field of parser.bl's `columns` or to one chunk of it, plus a
# reassignment of a field or of the whole value.
COLUMN_WRITE='\bcolumns(\s*=[^=]|\.[a-z_]+(\[[^]]*\])?(\.(push|pop|set|clear|insert|remove|truncate|append|extend|reverse|sort|swap)\(|\[[^]]*\]\s*=[^=]|\s*=[^=]))'

pool_writes() {
  root="$1"
  total=0
  p="$root/src/parser.bl"
  if [ -f "$p" ]; then
    n=$(awk '
      /^(pub )?fn (node_push|node_pop|node_replace|parser_reset|parser_rewind|node_write_plain_int|node_write_plain_str|node_write_int|node_write_str|node_widen|node_store|node_overwrite|node_shape|node_shape_new|node_ints_drop|node_strs_drop|node_drop_child_slots_from)\(/ { inw = 1 }
      !inw { print }
      inw && /^}/ { inw = 0 }' "$p" | rg -o "$POOL_WRITE|$COLUMN_WRITE" | wc -l | tr -d ' ')
    total=$((total + n))
  fi
  files=$(rg -U -l -g '*.bl' 'import parser\.\{[^}]*\bnodes\b|\bparser\.nodes\b' \
    "$root/src" "$root/lib" "$root/tests" 2>/dev/null | rg -v '/src/parser\.bl$')
  for f in $files; do
    total=$((total + $(cnt "$POOL_WRITE" "$f")))
  done
  echo "$total"
}

# lib/ nests (std/, pkg/), so it is searched as a tree rather than through a glob.
lib_substr() {
  [ -d "$1/lib" ] || { echo 0; return; }
  rg -o -g '*.bl' '\.substr\(' "$1/lib" 2>/dev/null | wc -l | tr -d ' '
}

tests_br_ids() {
  [ -d "$1/tests" ] || { echo 0; return; }
  rg -o -g '*.bl' '//.*\bbr [0-9a-z]{6}\b' "$1/tests" 2>/dev/null | wc -l | tr -d ' '
}

# The PCRE group matches the whole balanced argument list, so a `.len()` nested in
# another call inside it still counts.
len_in_byte_args() {
  dirs="$1/src"
  [ -d "$1/lib" ] && dirs="$dirs $1/lib"
  rg -o -P -g '*.bl' '\.(?:byte_slice|byte_at|byte_index_of)(\((?:[^()]++|(?1))*\))' $dirs 2>/dev/null |
    rg -o '\.len\(\)' | wc -l | tr -d ' '
}

# A `.tmp/` path that is not inside a tree the test or script made itself. The
# lookbehinds name the private-tree prefixes; the compiler writes its own
# `.tmp/` inside such a tree, and that is the behavior under test there.
repo_tmp_uses() {
  dirs=""
  [ -d "$1/tests" ] && dirs="$dirs $1/tests"
  [ -d "$1/scripts" ] && dirs="$dirs $1/scripts"
  [ -n "$dirs" ] || { echo 0; return; }
  rg -o -P -g '*.bl' -g '*.sh' -g '!ratchet.sh' -g '!test_ratchet.sh' \
    '(?<![\w.])(?<!\{tree\}/)(?<!\$work/)\.tmp/(?!\*\.o)' $dirs 2>/dev/null | wc -l | tr -d ' '
}

SPEC_TYPES=sections/07_trust_modules_metadata.md

# First-column names of the closed table, one per line, without backticks or `[...]`.
spec_type_names() {
  awk '
    /^#### Compiler-Known Type Names \(closed set\)/ { on = 1; next }
    /^#### Shadowing Rules/ { on = 0 }
    on && /^\| `/ {
      split($0, col, "|")
      n = split(col[2], part, "`")
      for (i = 2; i <= n; i += 2) { s = part[i]; sub(/\[.*/, "", s); print s }
    }' "$1"
}

# Names is_primitive_type answers `=> 1` for, one per line.
primitive_type_arms() {
  awk '
    /^fn is_primitive_type\(/ { on = 1; next }
    on && /^}/ { on = 0 }
    on {
      t = $0; sub(/^[ \t]+/, "", t); sub(/[ \t]+$/, "", t)
      if (t ~ /^"/ && t ~ /=> 1$/) { split(t, q, "\""); print q[2] }
    }' "$1"
}

primitive_names_outside_spec() {
  tc="$1/src/typecheck.bl"
  spec="$1/$SPEC_TYPES"
  [ -f "$tc" ] || { echo 0; return; }
  [ -f "$spec" ] || {
    echo "ratchet: $SPEC_TYPES is missing; the type-name row cannot check src/typecheck.bl" >&2
    echo 1; return
  }
  table=$(spec_type_names "$spec")
  arms=$(primitive_type_arms "$tc")
  for need in Int Self Handler Buf; do
    printf '%s\n' "$table" | grep -qx "$need" || {
      echo "ratchet: the spec type table in $SPEC_TYPES has no \`$need\`; the parse found no table" >&2
      echo 1; return
    }
  done
  printf '%s\n' "$arms" | grep -qx Int || {
    echo "ratchet: is_primitive_type in src/typecheck.bl yielded no \`Int\`; the parse found no arms" >&2
    echo 1; return
  }
  printf '%s\n' "$arms" | while IFS= read -r a; do
    case "$a" in Fn|Tuple) continue ;; esac
    printf '%s\n' "$table" | grep -qx -- "$a" || {
      echo "ratchet: is_primitive_type answers for \`$a\`, which the spec type table does not list" >&2
      echo x
    }
  done | wc -l | tr -d ' '
}

# Takes a root dir instead of reading the repo directly, so the same row
# definitions run against the real tree, a materialized historical ref, or a
# synthetic test fixture without duplicating the row list three times.
compute_rows() {
  root="$1"
  allbl="$root/src/*.bl"
  cgbl="$root/src/cg_*.bl $root/src/cg.bl $root/src/layout.bl $root/src/cname.bl $root/src/mono.bl $root/src/ir.bl"
  tcbl="$root/src/typecheck.bl"
  tf="$root/Taskfile.yml"

  cat <<ROWS
br_ids_in_source $(( $(cnt '\bbr [0-9a-z]{6}\b' "$allbl $tf") + $(cnt '\b(g3sba0|qf1vzx|0kpmac)\b' "$allbl $tf") ))
br_ids_in_test_comments $(tests_br_ids "$root")
module_let_mut $(cnt '^(pub )?let mut ' "$allbl")
typecheck_module_let_mut $(cnt '^(pub )?let mut ' "$tcbl")
layout_decline_unhandled $(decline_unhandled "$root")
cg_name_string_compares $(cnt '\b[a-z_0-9]*(method|name|trait)[a-z_0-9]*(\([^()]*\))?\s*[!=]=\s*"|[!=]=\s*(method|trait)_[a-z_0-9]+\b' "$cgbl")
fallback_idiom $(pcnt 'if ([a-z_][a-z_0-9.]*) >= 0 \{ \1 \} else' "$allbl")
typecheck_str_keyed_tables $(cnt '^(pub )?let mut [A-Za-z_][A-Za-z_0-9]*: Map\[Str' "$tcbl")
node_pool_writes $(pool_writes "$root")
str_substring_callers $(( $(cnt '\.(substring|substr)\(' "$allbl") + $(lib_substr "$root") ))
str_len_in_byte_args $(len_in_byte_args "$root")
primitive_type_names_outside_spec $(primitive_names_outside_spec "$root")
repo_tmp_in_tests_and_scripts $(repo_tmp_uses "$root")
ROWS
}

# Writes a plain copy of every tracked .bl file, Taskfile.yml and the spec file
# the type-name row reads, as they stood at $1, into $2. A file that does not exist at $1 is simply absent,
# which compute_rows treats as a zero contribution.
materialize_ref() {
  ref="$1"
  outdir="$2"
  rm -rf "$outdir"
  mkdir -p "$outdir"
  git ls-tree -r --name-only "$ref" -- src Taskfile.yml "$SPEC_TYPES" 2>/dev/null | while IFS= read -r path; do
    case "$path" in
      *.bl|Taskfile.yml|"$SPEC_TYPES") ;;
      *) continue ;;
    esac
    mkdir -p "$outdir/$(dirname "$path")"
    git show "$ref:$path" > "$outdir/$path" 2>/dev/null
  done
}

# Row names the ratchet.sh at $1 defined. A row it lacked has no count there.
tracked_rows_at() {
  git show "$1:scripts/ratchet.sh" 2>/dev/null |
    sed -n 's/^\([a-z_][a-z_0-9]*\) \$.*/\1/p' | tr '\n' ' '
}

# Prints one line per row a commit in $1..HEAD raised above its parents.
walk_branch() {
  base_ref="$1"
  walk=$(mktemp -d)
  trap 'rm -rf "$walk"' EXIT
  git rev-list --reverse --parents "${base_ref}..HEAD" | while read -r c parents; do
    [ -n "$parents" ] || continue
    [ -d "$walk/$c" ] || materialize_ref "$c" "$walk/$c"
    rows_c=$(compute_rows "$walk/$c")
    for p in $parents; do
      [ -d "$walk/$p" ] || materialize_ref "$p" "$walk/$p"
      compute_rows "$walk/$p" | sed "s/^/$p /"
    done > "$walk/parents.txt"
    tracked=""
    for p in $parents; do tracked="$tracked $(tracked_rows_at "$p")"; done
    subject=$(git log -1 --format='%h %s' "$c")
    printf '%s\n' "$rows_c" | while read -r name n; do
      case " $tracked " in *" $name "*) ;; *) continue ;; esac
      before=$(awk -v n="$name" '$2==n && $3>m {m=$3} END {print m+0}' "$walk/parents.txt")
      [ "$n" -gt "$before" ] && echo "$subject: $name $before -> $n"
    done
  done
  rm -rf "$walk"
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
failmark=""
trap 'rm -f "$failmark"; [ -n "${head1_root:-}" ] && [ -z "${RATCHET_HEAD1_DIR:-}" ] && rm -rf "$head1_root"' EXIT
if [ -n "${RATCHET_HEAD1_DIR:-}" ]; then
  head1_root="$RATCHET_HEAD1_DIR"
  check_root "$head1_root"
  rows_head1=$(compute_rows "$head1_root")
elif git rev-parse --verify --quiet "${head1_ref}^{commit}" >/dev/null 2>&1; then
  head1_root=$(mktemp -d)
  materialize_ref "$head1_ref" "$head1_root"
  rows_head1=$(compute_rows "$head1_root")
  # A row added by the commit under test has no previous-commit count:
  # computing it over the older files answers 0 for a metric nobody tracked,
  # which would fail the new row for the fact of existing. Its baseline,
  # written in the same commit, is its first reference.
  head1_tracked=$(tracked_rows_at "$head1_ref")
else
  echo "ratchet: warning: '$head1_ref' does not resolve; skipping the previous-commit comparison for this run" >&2
  rows_head1="$rows_now"
fi

failmark=$(mktemp)

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
    br_ids_in_source|br_ids_in_test_comments|layout_decline_unhandled|node_pool_writes|str_substring_callers|str_len_in_byte_args|primitive_type_names_outside_spec|repo_tmp_in_tests_and_scripts)
      [ "$now" -gt 0 ] && mark="$mark NONZERO(must-be-zero)" ;;
  esac
  printf '%-26s %8s %8s %8s%s\n' "$name" "$base" "$h1" "$now" "$mark"
  [ -n "$mark" ] && printf x >> "$failmark"
done

base_ref="${RATCHET_BASE_REF:-main}"
if [ -z "${RATCHET_HEAD1_DIR:-}" ]; then
  if git rev-parse --verify --quiet "${base_ref}^{commit}" >/dev/null 2>&1; then
    raised=$(walk_branch "$base_ref")
    if [ -n "$raised" ]; then
      echo "ratchet: a commit on this branch raised a row above its parent, even if a later commit paid it back:"
      printf '%s\n' "$raised" | sed 's/^/  /'
      printf x >> "$failmark"
    fi
  else
    echo "ratchet: warning: '$base_ref' does not resolve; skipping the branch walk for this run" >&2
  fi
fi

if [ -s "$failmark" ]; then
  echo "ratchet: a tracked count went up against the baseline or the previous commit. Remove the new use, or lower another row."
  exit 1
fi
echo "ratchet: ok"

if [ "${RATCHET_NO_LINT:-0}" != 1 ] && [ -x scripts/lint_codegen.sh ]; then
  ./scripts/lint_codegen.sh || exit 1
fi
