#!/bin/bash
# Lint rows L1-L11 for the new codegen modules. Each row counts a construct
# that the codegen rewrite forbids (see docs/codegen-rewrite/harness.md for
# what each row means and how to add one). The scanned modules are only the
# new-codegen files:
#
#   src/layout.bl src/cname.bl src/mono.bl src/ir.bl src/cg_*.bl
#
# Files that do not exist yet contribute nothing. tests/ and docs/ are never
# scanned for violations; L11 reads tests/ only to find references.
#
# Gate rule, per row: now <= max(threshold, baseline), and a row above its
# threshold is also bound by now <= previous commit. A row above its
# threshold is DEBT: it may not grow and must reach the threshold before the
# release gate. A row at or under its threshold may grow up to the threshold
# and never past it. Every row is therefore a ratchet with a floor, and no
# commit can raise a row that is in debt.
#
#   scripts/lint_codegen.sh            gate
#   scripts/lint_codegen.sh --update   rewrite the baseline from the current counts
#   scripts/test_lint_codegen.sh       self-test: each row goes red on a fixture
#
# Previous-commit reference: HEAD when src/ or tests/ or scripts/ has
# uncommitted changes (the run precedes the commit that lands them), else
# HEAD~1. Override with LINT_HEAD1_REF.
#
# Env overrides (used by scripts/test_lint_codegen.sh):
#   LINT_SRC_DIR    root standing in for the repo (has src/ and tests/). Default: .
#   LINT_BASELINE   baseline file. Default: scripts/lint_codegen_baseline.txt
#   LINT_ALLOWLIST  pub let mut allowlist. Default: scripts/lint_pub_let_mut_allow.txt
#   LINT_HEAD1_DIR  root standing in for the previous commit (bypasses git)
#   LINT_HEAD1_REF  git ref to materialize when LINT_HEAD1_DIR is unset
set -u
cd "$(dirname "$0")/.." || exit 2

update_flag="${1:-}"
now_root="${LINT_SRC_DIR:-.}"
baseline="${LINT_BASELINE:-scripts/lint_codegen_baseline.txt}"
allowlist="${LINT_ALLOWLIST:-scripts/lint_pub_let_mut_allow.txt}"

case "$now_root" in *[[:space:]]*)
    echo "lint_codegen: root '$now_root' contains whitespace; rerun from a path without spaces" >&2
    exit 2 ;;
esac

# Row name, threshold. Order is the report order.
ROWS="
L1 ct_or_string_types 0
L2 sentinel_answers 0
L3 pub_let_mut_new 8
L3 pub_let_mut_unlisted 0
L4 typename_compares 0
L5 no_infer 0
L6 layout_outside_layer 0
L7 single_producer 0
L8 import_dag 0
L9 fn_length 0
L10 br_ids_in_source 0
L11 untested_pub_fns 0
"

# The producers rule 7 names, with the file that must define each. A name
# defined twice anywhere in src/ is a twin; a name missing while its owner
# exists is an unported producer.
PRODUCERS="
c_fn_name cname
c_fn_name_in cname
c_type_c_name cname
c_type_c_name_in cname
mangle_impl_method cname
mangle_impl_method_q cname
mangle_from_method cname
mangle_generic_name cname
derive_method_cname cname
c_type_of layout
carrier_tag_of layout
ensure_typedef_for layout
child_tid layout
tid_of_node layout
tid_of_binder layout
nominal_name_of layout
layout_of layout
"

# Files in scope under a root, as paths. Missing files are simply absent.
scope_files() {
    root="$1"
    for f in "$root"/src/layout.bl "$root"/src/cname.bl "$root"/src/mono.bl "$root"/src/ir.bl "$root"/src/cg_*.bl; do
        [ -f "$f" ] && echo "$f"
    done
}

# grep -nP over the scope files, printing file:line:text. Empty scope => no output.
scan() {
    pattern="$1"; shift
    [ $# -eq 0 ] && return 0
    grep -nHP -- "$pattern" "$@" 2>/dev/null || true
}

# compute_rows <root> <detail dir>: prints "name count" per row and writes
# the matching lines for each row to <detail dir>/<name>.txt.
compute_rows() {
    root="$1"
    det="$2"
    mkdir -p "$det"
    files=$(scope_files "$root")
    # shellcheck disable=SC2086
    set -- $files

    # L1: CT_* constants, type_from_name, the tp_* twin pool, sv_tp, ScopeVar.ctype/sname.
    scan '\bCT_[A-Z_]+\b|\btype_from_name(_tag)?\(|\btp_[a-z][a-z_0-9]*\(|\bsv_tp\(|\.(ctype|sname)\b' "$@" > "$det/ct_or_string_types.txt"

    # L2: a guessed answer where an ICE belongs: TYPE_UNKNOWN, the flat
    # fallback idiom, and a tid coalesced onto a default.
    scan '\bTYPE_UNKNOWN\b|if [a-z_]+ >= 0 \{ [a-z_]+ \} else|\b[a-z_0-9]*tid[a-z_0-9]*\s*\?\?\s' "$@" > "$det/sentinel_answers.txt"

    # L3: mutable module globals. Count, and names outside the allowlist.
    scan '^pub let mut [a-z_][a-z_0-9]*' "$@" > "$det/pub_let_mut_new.txt"
    : > "$det/pub_let_mut_unlisted.txt"
    if [ -s "$det/pub_let_mut_new.txt" ]; then
        allowed=$(grep -vE '^[[:space:]]*(#|$)' "$allowlist" 2>/dev/null | awk '{print $1}')
        while IFS= read -r line; do
            name=$(printf '%s' "$line" | sed -E 's/^.*pub let mut ([a-z_][a-z_0-9]*).*$/\1/')
            if ! printf '%s\n' "$allowed" | grep -qx -- "$name"; then
                echo "$line" >> "$det/pub_let_mut_unlisted.txt"
            fi
        done < "$det/pub_let_mut_new.txt"
    fi

    # L4: dispatch on a type's NAME as a string.
    scan '[=!]= "[A-Z][A-Za-z_0-9]*"|\btk_name\([^)]*\)\s*[=!]=|\.(starts_with|ends_with)\("(Option|Result|List|Map|Set|Tuple|Fn|Str|Int|Float|Bool|Bytes|Char)\b' "$@" > "$det/typename_compares.txt"

    # L5: a second inference engine.
    scan '\binfer_[a-z_0-9]+\(' "$@" > "$det/no_infer.txt"

    # L6: a C type spelling decided outside layout.bl (the record) and
    # cg_print.bl (the printer), or a TyKind test inside the printer.
    : > "$det/layout_outside_layer.txt"
    for f in "$@"; do
        case "$f" in */layout.bl|*/cg_print.bl) continue ;; esac
        scan '"(int64_t|int32_t|uint8_t|uint64_t|double|float|void|char|bool|_Bool|blink_(str|list|map|set|bytes|closure|option|result|tuple|ev|kops|Option|Result|Tuple)[A-Za-z_0-9]*)\**"' "$f" >> "$det/layout_outside_layer.txt"
    done
    for f in "$@"; do
        case "$f" in */cg_print.bl) scan '\bTyKind\.|\btc_tid_kind\(|\btype_kind\(' "$f" >> "$det/layout_outside_layer.txt" ;; esac
    done

    # L7: one definition per producer across ALL of src/, and no pub fn of
    # cname.bl/layout.bl defined a second time elsewhere.
    : > "$det/single_producer.txt"
    printf '%s\n' "$PRODUCERS" | while read -r name owner; do
        [ -z "$name" ] && continue
        defs=$(grep -lP -- "^(pub )?fn $name\(" "$root"/src/*.bl 2>/dev/null | tr '\n' ' ')
        n=$(printf '%s' "$defs" | wc -w | tr -d ' ')
        if [ "$n" -gt 1 ]; then
            echo "$name: defined $n times: $defs" >> "$det/single_producer.txt"
        elif [ "$n" -eq 0 ] && [ -f "$root/src/$owner.bl" ]; then
            echo "$name: src/$owner.bl exists but does not define it" >> "$det/single_producer.txt"
        fi
    done
    for f in "$root"/src/cname.bl "$root"/src/layout.bl; do
        [ -f "$f" ] || continue
        grep -oP '^pub fn \K[a-z_][a-z_0-9]*' "$f" | while read -r name; do
            others=$(grep -lP -- "^(pub )?fn $name\(" "$root"/src/*.bl 2>/dev/null | grep -v "^$f\$" | tr '\n' ' ')
            [ -n "$others" ] && echo "$name: also defined in $others" >> "$det/single_producer.txt"
        done
    done

    # L8: import DAG. Forbidden edges by importing file.
    : > "$det/import_dag.txt"
    for f in "$@"; do
        fb=$(basename "$f" .bl)
        imports=$(grep -oP '^import \K[a-z_][a-z_0-9]*' "$f" 2>/dev/null)
        for m in $imports; do
            bad=""
            case "$m" in codegen*|lowering) bad="old codegen module" ;; esac
            case "$fb" in
                layout) case "$m" in cg_*|mono|cname|ir|cg) bad="layout.bl imports nothing above it" ;; esac ;;
                cname)  case "$m" in cg_*|mono|ir|cg) bad="cname.bl imports only layout and below" ;; esac ;;
                ir)     case "$m" in cg_*|mono|cg) bad="ir.bl imports only layout and below" ;; esac ;;
                mono)   case "$m" in cg_*|cg) bad="mono never imports an emitter" ;; esac ;;
                cg_print) case "$m" in typecheck|layout|mono|ast|parser|cname) bad="the printer may not reason about types" ;; esac ;;
                cg_*)   case "$m" in cg_emit) bad="only cg_print may import cg_emit" ;; esac ;;
            esac
            case "$fb" in cg_*) case "$m" in cg) bad="the driver is the top of the DAG" ;; esac ;; esac
            [ -n "$bad" ] && echo "$f: import $m ($bad)" >> "$det/import_dag.txt"
        done
    done

    # L9: functions over 80 lines (signature line to the closing brace at column 0).
    : > "$det/fn_length.txt"
    for f in "$@"; do
        awk -v file="$f" '
            /^(pub )?fn / { start = NR; sig = $0 }
            /^}/ { if (start && NR - start + 1 > 80) printf "%s:%d: %d lines: %s\n", file, start, NR - start + 1, sig; start = 0 }
        ' "$f" >> "$det/fn_length.txt"
    done

    # L10: a br ticket id in source. Ids are six [0-9a-z] with at least one digit.
    scan '\bbr [0-9a-z]{6}\b|\b(ticket|bug|task|issue|fixes|closes)[: ]+#?(?=[0-9a-z]{6}\b)(?=[a-z]*[0-9])[0-9a-z]{6}\b|#(?=[0-9a-z]{6}\b)(?=[a-z]*[0-9])[0-9a-z]{6}\b' "$@" > "$det/br_ids_in_source.txt"

    # L11: every pub fn of the reading layer and mono must be named in some test.
    : > "$det/untested_pub_fns.txt"
    for f in "$root"/src/layout.bl "$root"/src/cname.bl "$root"/src/ir.bl "$root"/src/mono.bl; do
        [ -f "$f" ] || continue
        grep -oP '^pub fn \K[a-z_][a-z_0-9]*' "$f" | while read -r name; do
            if ! grep -qw -- "$name" "$root"/tests/test_*.bl 2>/dev/null; then
                echo "$f: pub fn $name has no test reference" >> "$det/untested_pub_fns.txt"
            fi
        done
    done

    printf '%s\n' "$ROWS" | while read -r _id name _thr; do
        [ -z "$name" ] && continue
        n=$(grep -c . "$det/$name.txt" 2>/dev/null || true)
        echo "$name ${n:-0}"
    done
}

# A plain copy of src/, tests/ and scripts/ as they stood at a ref.
materialize_ref() {
    rm -rf "$2"
    mkdir -p "$2"
    git archive "$1" src tests scripts 2>/dev/null | tar -x -C "$2"
}

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

rows_now=$(compute_rows "$now_root" "$work/now")

if [ "$update_flag" = "--update" ]; then
    printf '%s\n' "$rows_now" > "$baseline"
    echo "lint_codegen: baseline written"
    printf '%s\n' "$rows_now"
    exit 0
fi

[ -f "$baseline" ] || { echo "lint_codegen: no baseline; run scripts/lint_codegen.sh --update"; exit 1; }

if [ -z "$(git status --porcelain -- src tests scripts 2>/dev/null)" ]; then
    default_ref=HEAD~1
else
    default_ref=HEAD
fi
head1_ref="${LINT_HEAD1_REF:-$default_ref}"

head1_tracked=""
if [ -n "${LINT_HEAD1_DIR:-}" ]; then
    rows_head1=$(compute_rows "$LINT_HEAD1_DIR" "$work/head1")
elif git rev-parse --verify --quiet "${head1_ref}^{commit}" >/dev/null 2>&1; then
    materialize_ref "$head1_ref" "$work/head1_tree"
    rows_head1=$(compute_rows "$work/head1_tree" "$work/head1")
    # A row this script gained since that commit has no previous count; its
    # baseline, written in the same commit, is its first reference.
    # When that commit had no lint script at all, every row is new.
    if head1_script=$(git show "${head1_ref}:scripts/lint_codegen.sh" 2>/dev/null); then
        head1_tracked=$(printf '%s\n' "$head1_script" |
            sed -n 's/^L[0-9]* \([a-z_][a-z_0-9]*\) [0-9]*$/\1/p' | tr '\n' ' ')
    else
        head1_tracked=" "
    fi
else
    echo "lint_codegen: warning: '$head1_ref' does not resolve; skipping the previous-commit comparison" >&2
    rows_head1="$rows_now"
fi

fail=0
printf '%-4s %-22s %5s %8s %8s %8s\n' row metric thr baseline 'head~1' now
while read -r id name thr; do
    [ -z "$name" ] && continue
    now=$(printf '%s\n' "$rows_now" | awk -v n="$name" '$1==n{print $2}')
    base=$(awk -v n="$name" '$1==n{print $2}' "$baseline")
    [ -z "$base" ] && base=0
    h1=$(printf '%s\n' "$rows_head1" | awk -v n="$name" '$1==n{print $2}')
    [ -z "$h1" ] && h1=0
    if [ -n "$head1_tracked" ]; then
        case " $head1_tracked " in *" $name "*) ;; *) h1="$now" ;; esac
    fi
    limit="$thr"
    [ "$base" -gt "$limit" ] && limit="$base"
    mark=""
    [ "$now" -gt "$limit" ] && mark="$mark OVER(limit=$limit)"
    # Under the threshold a row may grow up to it; the previous-commit rule
    # only binds a row that is already in debt.
    [ "$now" -gt "$thr" ] && [ "$now" -gt "$h1" ] && mark="$mark UP(head~1)"
    [ -z "$mark" ] && [ "$now" -gt "$thr" ] && mark=" DEBT"
    printf '%-4s %-22s %5s %8s %8s %8s%s\n' "$id" "$name" "$thr" "$base" "$h1" "$now" "$mark"
    case "$mark" in
        *OVER*|*UP*)
            fail=1
            sed 's/^/       /' "$work/now/$name.txt"
            ;;
    esac
done <<EOF
$ROWS
EOF

if [ "$fail" -ne 0 ]; then
    echo "lint_codegen: FAIL. A row rose above its limit or above the previous commit. Remove the construct; the lint never gets an exception."
    exit 1
fi
echo "lint_codegen: ok"
