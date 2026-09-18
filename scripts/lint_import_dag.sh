#!/bin/sh
# Import DAG for the tid reading layer. layout.bl decides storage and asks cname.bl for
# every C symbol name, so the edge layout -> cname must exist and no edge may point
# back up from cname into layout, the IR, or any emitter. Neither module may read the
# old codegen tables (codegen_types).
#
# unparse.bl is held to an allowlist rather than a forbid-list. It rebuilds what a
# program SAYS, and that is a property of what was written, not of what the program
# compiles to. An edge into types, the IR or an emitter would let the rebuilt text
# drift toward the lowered form, and a failing assert would then quote a condition
# the programmer never wrote. A forbid-list would have to grow with every new
# module; the allowlist fails closed instead.
#   scripts/lint_import_dag.sh            check src/
#   LINT_SRC_DIR=<dir> scripts/lint_import_dag.sh   check another tree (self-test)
set -u
SRC="${LINT_SRC_DIR:-src}"
fail=0

imports_of() {
    # One module name per line: the token after `import`, before any `.{` or `.`.
    grep -E '^import ' "$1" | sed -E 's/^import +([A-Za-z0-9_]+).*/\1/'
}

# Same, but keeping a dotted path whole, so std.str is distinguishable from std.io.
full_imports_of() {
    grep -E '^import ' "$1" | sed -E 's/^import +//; s/\{.*//; s/\.$//; s/[[:space:]].*//'
}

require_import() {
    if ! imports_of "$SRC/$1" | grep -qx "$2"; then
        echo "L8 import_dag: $1 must import $2"
        fail=1
    fi
}

allow_only_imports() {
    hits=$(full_imports_of "$SRC/$1" | grep -Ev "$2" || true)
    if [ -n "$hits" ]; then
        for h in $hits; do echo "L8 import_dag: $1 must not import $h"; done
        fail=1
    fi
}

forbid_import() {
    hits=$(imports_of "$SRC/$1" | grep -E "$2" || true)
    if [ -n "$hits" ]; then
        for h in $hits; do echo "L8 import_dag: $1 must not import $h"; done
        fail=1
    fi
}

# Each governed file is checked on its own. A single early exit over the whole
# set would let one missing file skip every other module's rules in silence,
# which is the shape a rule most easily rots into.
have() {
    [ -f "$SRC/$1" ] && return 0
    echo "L8 import_dag: $SRC/$1 not found"
    fail=1
    return 1
}

if have layout.bl; then
    require_import layout.bl cname
    forbid_import layout.bl '^codegen_types$'
fi
if have cname.bl; then
    forbid_import cname.bl '^(layout|ir|cg_.*|codegen.*)$'
fi
if have unparse.bl; then
    allow_only_imports unparse.bl '^(ast|parser|diagnostics|std\.str)$'
fi

if [ "$fail" -ne 0 ]; then
    echo "L8 import_dag: FAIL"
    exit 1
fi
echo "L8 import_dag: ok"
