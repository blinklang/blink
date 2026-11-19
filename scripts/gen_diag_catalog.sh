#!/bin/sh
# Writes src/diag_catalog.bl from ERROR_CATALOG.md: the section of each live name and code, the
# name and code of each live row, and the rows of *Repairs at a suppression site*. The catalog
# is the one source; `task ci` fails while the committed file differs from what this writes.
#
#   scripts/gen_diag_catalog.sh            write src/diag_catalog.bl
#   scripts/gen_diag_catalog.sh --stdout   print it instead
#   scripts/gen_diag_catalog.sh --check    exit 1, with the diff, when the committed file is stale
#
# Exit 2 when the catalog cannot be read as expected: a Name | Code table under a section this
# script does not know, a section with no rows, or a repair row whose name is not a live row.
set -u
export LC_ALL=C
here=$(cd "$(dirname "$0")" && pwd)
. "$here/spec_md.sh"
ROOT=$(cd "${DIAG_CATALOG_ROOT:-$here/..}" && pwd) || exit 2
CAT="$ROOT/ERROR_CATALOG.md"
OUT="$ROOT/src/diag_catalog.bl"

[ -r "$CAT" ] || { echo "gen_diag_catalog: cannot read $CAT" >&2; exit 2; }

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# `## ` headings outside fences, as `<line>\tH\t<text>`, then the table rows; sorted by line,
# so each row follows the heading of its section.
awk "$_spec_md_fence"'
    in_fence() { next }
    /^## / { t = $0; sub(/^## +/, "", t); printf "%d\tH\t%s\n", FNR, t }
' "$CAT" > "$work/heads" || exit 2
md_table_rows "$CAT" > "$work/rows" || exit 2
sort -t "$(printf '\t')" -k1,1n "$work/heads" "$work/rows" > "$work/all"

awk -F'\t' -v out="$work/body" -v bad="$work/bad" -v f=ERROR_CATALOG.md '
    function esc(s) {
        gsub(/\\/, "\\\\", s); gsub(/"/, "\\\"", s); gsub(/\{/, "\\{", s); gsub(/\}/, "\\}", s)
        return s
    }
    $2 == "H" {
        section = $3
        kind = ""
        if (section == "Error Names") kind = "error"
        else if (section == "Warning Names") kind = "warning"
        else if (section == "Info Names") kind = "info"
        else if (section ~ /^Internal Compiler Errors/) kind = "ice"
        else if (section == "Retired Codes") kind = "retired"
        next
    }
    $2 == "head" {
        table = ""
        if ($4 == "Name" && $5 == "Code") {
            if (kind == "") print f ":" $1 " -> a Name | Code table under ## " section ", a section this script does not know" > bad
            table = "def"
        } else if ($3 == 2 && $4 == "Name" && $5 == "Repair") {
            table = "repair"
        }
        next
    }
    $2 != "row" { next }
    table == "def" && kind != "" && kind != "retired" {
        n++; nm[n] = $4; cd[n] = $5; kd[n] = kind; count[kind]++
        live[$4] = 1
        next
    }
    table == "repair" { r++; rname[r] = $4; rtext[r] = $5; rline[r] = $1; next }
    END {
        split("error warning info ice", ks, " ")
        for (i = 1; i <= 4; i++) if (!count[ks[i]]) print f " -> no " ks[i] " rows" > bad
        if (!r) print f " -> no Name | Repair table" > bad
        for (i = 1; i <= r; i++) if (!(rname[i] in live)) print f ":" rline[i] " " rname[i] " -> a repair row whose name is not a live row" > bad

        print "// The section of ERROR_CATALOG.md that lists a live name or code: \"error\", \"warning\"," > out
        print "// \"info\" or \"ice\". Any other string gets \"\", a retired name or code included." > out
        print "pub fn diag_catalog_kind(key: Str) -> Str {" > out
        print "    match key {" > out
        for (i = 1; i <= n; i++) printf "        \"%s\" | \"%s\" => \"%s\"\n", nm[i], cd[i], kd[i] > out
        print "        _ => \"\"" > out
        print "    }" > out
        print "}" > out
        print "" > out
        print "// The name of the live row that has this name or code, else \"\"." > out
        print "pub fn diag_catalog_name(key: Str) -> Str {" > out
        print "    match key {" > out
        for (i = 1; i <= n; i++) printf "        \"%s\" | \"%s\" => \"%s\"\n", nm[i], cd[i], nm[i] > out
        print "        _ => \"\"" > out
        print "    }" > out
        print "}" > out
        print "" > out
        print "// The code of the live row that has this name or code, else \"\"." > out
        print "pub fn diag_catalog_code(key: Str) -> Str {" > out
        print "    match key {" > out
        for (i = 1; i <= n; i++) printf "        \"%s\" | \"%s\" => \"%s\"\n", nm[i], cd[i], cd[i] > out
        print "        _ => \"\"" > out
        print "    }" > out
        print "}" > out
        print "" > out
        print "// The repair that *Repairs at a suppression site* gives for a live name, else \"\"." > out
        print "pub fn diag_catalog_repair(name: Str) -> Str {" > out
        print "    match name {" > out
        for (i = 1; i <= r; i++) printf "        \"%s\" => \"%s\"\n", rname[i], esc(rtext[i]) > out
        print "        _ => \"\"" > out
        print "    }" > out
        print "}" > out
    }
' "$work/all" || { echo "gen_diag_catalog: the catalog reader failed to run" >&2; exit 2; }

if [ -s "$work/bad" ]; then
    sed 's/^/  /' "$work/bad" >&2
    echo "gen_diag_catalog: cannot read ERROR_CATALOG.md as expected" >&2
    exit 2
fi

{
    echo "// AUTO-GENERATED by scripts/gen_diag_catalog.sh from ERROR_CATALOG.md. DO NOT EDIT."
    echo "// Run \`task gen-diag-catalog\` after a catalog change; \`task ci\` fails while this file is stale."
    echo ""
    cat "$work/body"
} > "$work/out"

if [ "${1:-}" = "--stdout" ]; then
    cat "$work/out"
    exit 0
fi
if [ "${1:-}" = "--check" ]; then
    if [ -f "$OUT" ] && cmp -s "$work/out" "$OUT"; then
        echo "diag-catalog: ok"
        exit 0
    fi
    echo "diag-catalog: FAIL src/diag_catalog.bl is stale against ERROR_CATALOG.md. Run: task gen-diag-catalog, then commit." >&2
    diff -u "$OUT" "$work/out" | head -40 >&2
    exit 1
fi
if [ -f "$OUT" ] && cmp -s "$work/out" "$OUT"; then
    echo "unchanged $OUT"
else
    cp "$work/out" "$OUT"
    echo "wrote $OUT"
fi
