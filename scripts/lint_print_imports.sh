#!/usr/bin/env sh
# Lint L8: the C printer knows no types.
#
# cg_print.bl may import only cg_emit, ir and diagnostics.
# cg_emit.bl may import nothing from the compiler except diagnostics.
# Neither file may name a TyKind branch or read the ty_pool.
#
# Exit 0 when clean, 1 with one line per violation. Violation lines use the wording
# "must not import" so scripts/lint_codegen.sh row L8 can count them.
#   scripts/lint_print_imports.sh                    check src/
#   LINT_SRC_DIR=<dir> scripts/lint_print_imports.sh check another tree (self-test)
set -u
cd "$(dirname "$0")/.." || exit 2
SRC="${LINT_SRC_DIR:-src}"

status=0
fail() { echo "L8 import_dag: $1"; status=1; }

# Source with line comments removed, so prose never trips a pattern.
code() { sed 's#//.*##' "$1"; }

# One record per import statement. A selective import may break its brace list over
# several lines; those lines are joined until the closing brace.
imports() {
    code "$1" | awk '
        /^import / { rec = $0; open = index($0, "{") > 0 && index($0, "}") == 0; if (!open) { print rec }; next }
        open { rec = rec " " $0; if (index($0, "}") > 0) { open = 0; print rec } }
    ' | sed 's/  */ /g; s/ *$//; s/{ /{/; s/ }/}/; s/,}/}/'
}

modules() {
    imports "$1" | sed 's/^import \([A-Za-z0-9_.]*[A-Za-z0-9_]\).*/\1/'
}

PRINT="$SRC/cg_print.bl"
EMIT="$SRC/cg_emit.bl"
for f in "$PRINT" "$EMIT"; do
    if [ ! -f "$f" ]; then echo "L8 import_dag: $f not found"; exit 2; fi
done

for m in $(modules "$PRINT"); do
    case "$m" in
        cg_emit|ir|diagnostics|std.*) ;;
        *) fail "cg_print.bl must not import $m (allowed: cg_emit ir diagnostics std.*)" ;;
    esac
done

for m in $(modules "$EMIT"); do
    case "$m" in
        diagnostics|std.*) ;;
        *) fail "cg_emit.bl must not import $m (allowed: diagnostics std.*)" ;;
    esac
done

for f in "$PRINT" "$EMIT"; do
    if code "$f" | grep -q 'TyKind\.'; then fail "$(basename "$f") must not import type knowledge: it branches on a TyKind"; fi
    if code "$f" | grep -q 'ty_pool\|tp_kind\|tp_name\|tp_args\|tc_tid_'; then fail "$(basename "$f") must not import type knowledge: it reads the type pool"; fi
done

[ $status -eq 0 ] && echo "L8 ok: cg_print and cg_emit import no type knowledge"
exit $status
