#!/bin/sh
# Import DAG for the tid reading layer. layout.bl decides storage and asks cname.bl for
# every C symbol name, so the edge layout -> cname must exist and no edge may point
# back up from cname into layout, the IR, or any emitter. Neither module may read the
# old codegen tables (codegen_types).
#   scripts/lint_import_dag.sh            check src/
#   LINT_SRC_DIR=<dir> scripts/lint_import_dag.sh   check another tree (self-test)
set -u
SRC="${LINT_SRC_DIR:-src}"
fail=0

imports_of() {
    # One module name per line: the token after `import`, before any `.{` or `.`.
    grep -E '^import ' "$1" | sed -E 's/^import +([A-Za-z0-9_]+).*/\1/'
}

require_import() {
    if ! imports_of "$SRC/$1" | grep -qx "$2"; then
        echo "L8 import_dag: $1 must import $2"
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

for f in layout.bl cname.bl; do
    if [ ! -f "$SRC/$f" ]; then
        echo "L8 import_dag: $SRC/$f not found"
        exit 2
    fi
done

require_import layout.bl cname
forbid_import cname.bl '^(layout|ir|cg_.*|codegen.*)$'
forbid_import layout.bl '^codegen_types$'

if [ "$fail" -ne 0 ]; then
    echo "L8 import_dag: FAIL"
    exit 1
fi
echo "L8 import_dag: ok"
