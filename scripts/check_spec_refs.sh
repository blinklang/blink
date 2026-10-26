#!/bin/bash
# The spec-ref gate of `task ci`: every section ref in the spec, the error
# catalog and the language reference must name a numbered heading that
# exists. A section number is both an identifier other files cite and a
# position that moves when someone changes the spec, so nothing stops a ref
# from becoming wrong; this gate fails the build at the line that cites it.
#
# A ref is `§` and a number (§3, §3c, §3b.5, §4.16.7), or prose such as
# `section 9.3` or `sections 9.3 and 9.4`. Punctuation after it is not part
# of it (`§3.2.`, `§3.6's`). These forms fail: a number with no heading; a
# file:line coordinate (`§07:163`, `§3.6:2330`), which moves with every edit
# above it; a range (`§4.1-4.3`); a number joined to more text (`§4.4.x`,
# `§3.1a`); and `§ 3.4`. A ref inside a fenced block counts the same. An
# unnumbered `####` heading has no number of its own, so a ref to its text
# cites the number it is in.
#
# The headings must nest: X.Y.Z must come under X.Y (the last heading with
# one number fewer), which finds a subsection that stays in the old section
# after the numbers change. Each number names one heading. Gaps in the
# numbering are allowed.
#
# The tables of ERROR_CATALOG.md must also have a valid format: each row has
# as many cells as its header, each `Spec ref` cell is empty or a
# comma-separated list of § refs, each code in a defining table is a code,
# no code or name appears twice across the tables that define codes, and
# each row of the implemented-codes table matches a defining row.
#
# decisions/ and DECISIONS.md are not gated: they record past votes, and a
# ref there was correct when someone wrote it.
#
#   scripts/check_spec_refs.sh   (env SPEC_REFS_ROOT, default the repo root)
#
# Exit 0 when every ref resolves, 1 with one or more broken (each printed as
# `file:line ref -> reason`), 2 when an input cannot be read: a missing file,
# a fence that never closes, no numbered heading, no `Spec ref` table, a
# catalog table of no known kind, or a catalog row whose cell count does not
# match its header.
set -u
export LC_ALL=C
here=$(cd "$(dirname "$0")" && pwd)
. "$here/spec_md.sh"
cd "${SPEC_REFS_ROOT:-$here/..}" || exit 2

work=$(mktemp -d) || exit 2
trap 'rm -rf "$work"' EXIT

specs=(sections/*.md)
if [ ! -f "${specs[0]}" ]; then
    echo "spec-refs: cannot read: no sections/*.md under $PWD" >&2
    exit 2
fi
gated=("${specs[@]}" ERROR_CATALOG.md llms.md llms-full.md)
for f in "${gated[@]}"; do
    if [ ! -f "$f" ] || [ ! -r "$f" ]; then
        echo "spec-refs: cannot read $f" >&2
        exit 2
    fi
done

spec_headings "${specs[@]}" > "$work/heads" || { echo "spec-refs: cannot read the headings" >&2; exit 2; }
if [ ! -s "$work/heads" ]; then
    echo "spec-refs: cannot read: no numbered heading in sections/*.md" >&2
    exit 2
fi
md_table_rows ERROR_CATALOG.md > "$work/rows" || { echo "spec-refs: cannot read the tables of ERROR_CATALOG.md" >&2; exit 2; }

: > "$work/problems"
: > "$work/unreadable"

# Each number names one heading, and X.Y.Z comes under X.Y. A file starts
# its own chapter, so the nesting starts again in each file. Numbers compare
# as text: 07 and 7 are two headings.
awk -F'\t' '
    $2 != curf { curf = $2; split("", last) }
    {
        num = $1; at = $2 ":" $3
        if (num in def) print at " " num " -> also defined at " def[num]
        else def[num] = at
        n = split(num, parts, ".")
        if (n > 1) {
            parent = parts[1]
            for (i = 2; i < n; i++) parent = parent "." parts[i]
            got = ((n - 1) in last) ? last[n - 1] : ""
            if (got "" != parent "")
                print at " " num " -> the heading sits under " (got == "" ? "no numbered heading" : got) ", not under its parent " parent
        }
        last[n] = num
        for (k in last) if (k + 0 > n) delete last[k]
    }
' "$work/heads" >> "$work/problems" || { echo "spec-refs: the nesting check failed to run" >&2; exit 2; }

# Three kinds of table. A `Name | Code | ...` table defines codes (live,
# retired, ICE), and no code or name may appear twice across them. A
# `Code | Name | Implementation` table lists defined codes again, so each of
# its rows must match a defining row. A `Range | Category` table is the
# legend. A table with any other header stops the gate with exit 2, so a new
# kind of table cannot skip the checks without notice.
awk -F'\t' -v f=ERROR_CATALOG.md -v bad="$work/unreadable" '
    $2 == "bare" {
        print f ":" $1 " -> a table row with no leading |; start each table line with |" > bad
        next
    }
    $2 == "head" {
        ncol = $3; kind = ""; spec = 0
        hdr = $4
        for (i = 2; i <= ncol; i++) hdr = hdr " | " $(3 + i)
        if ($4 == "Name" && $5 == "Code") kind = "def"
        else if (hdr == "Code | Name | Implementation") kind = "list"
        else if (hdr == "Range | Category") kind = "legend"
        else print f ":" $1 " -> a table header the gate does not know: " hdr > bad
        for (i = 1; i <= ncol; i++) {
            if (kind != "def") continue
            h = $(3 + i)
            if (h == "Spec ref") { spec = i; nspec++ }
            else if (tolower(h) ~ /^spec *refs?$/) print f ":" $1 " -> a Spec ref column spelt " h > bad
        }
        next
    }
    $3 != ncol {
        print f ":" $1 " -> the row has " $3 " cells, its table header has " ncol " (escape a | in a cell as \\|)" > bad
        next
    }
    $2 == "sep" || kind == "legend" { next }
    kind == "list" {
        if ($4 in listed) print f ":" $1 " " $4 " -> also listed at " f ":" listed[$4]
        else listed[$4] = $1
        nl++; lline[nl] = $1; lcode[nl] = $4; lname[nl] = $5
        next
    }
    kind == "def" {
        if (spec) {
            c = $(3 + spec)
            if (c != "" && c !~ /^§[0-9]+[a-z]?(\.[0-9]+)*(, §[0-9]+[a-z]?(\.[0-9]+)*)*$/)
                print f ":" $1 " -> the Spec ref cell is not a comma-separated list of § refs: " c
        }
        # A retired or internal row may have no code; a live row (a table
        # with a Spec ref column) always has one.
        cd = $5
        if (cd ~ /^[EWVI][0-9][0-9][0-9][0-9][a-z]?$/) {
            if (cd in codes) print f ":" $1 " " cd " -> code also at " f ":" codes[cd]
            else { codes[cd] = $1; named[cd] = $4 }
        } else if (cd != "—" || spec) {
            print f ":" $1 " " cd " -> not a diagnostic code (a letter E, W, V or I, four digits, an optional lower-case letter)"
        }
        nm = $4
        if (nm in names) print f ":" $1 " " nm " -> name also at " f ":" names[nm]
        else names[nm] = $1
    }
    END {
        if (!nspec) print f " -> no table with a Spec ref column" > bad
        for (i = 1; i <= nl; i++) {
            cd = lcode[i]
            if (!(cd in codes))
                print f ":" lline[i] " " cd " -> no defining table has this code"
            else if (named[cd] != lname[i])
                print f ":" lline[i] " " cd " -> named " lname[i] " here, " named[cd] " at " f ":" codes[cd]
        }
    }
' "$work/rows" >> "$work/problems" || { echo "spec-refs: the catalog check failed to run" >&2; exit 2; }

if [ -s "$work/unreadable" ]; then
    sed 's/^/  /' "$work/unreadable"
    echo "spec-refs: cannot read ERROR_CATALOG.md as tables" >&2
    exit 2
fi

awk -v heads="$work/heads" '
    BEGIN {
        while ((getline l < heads) > 0) { split(l, h, "\t"); known[h[1]] = 1 }
        sign = "§"; slen = length(sign)
        NUM = "^[0-9]+[a-z]?(\\.[0-9]+)*"
    }
    function report(label, why) { print FILENAME ":" FNR " " label " -> " why }
    # judge prints a problem for one ref. <label> is the ref as cited up to
    # its number, <num> the number, <after> the text that follows it.
    function judge(label, num, after) {
        if (num ~ /^0[0-9]/ || after ~ /^:[0-9]/) {
            match(after, /^(:[0-9]+)?/)
            report(label substr(after, 1, RLENGTH), "a file:line coordinate, not a section ref; cite the section number")
        } else if (after ~ /^(-|–)(§)?[0-9]/) {
            match(after, /^(-|–)(§)?[0-9]+[a-z]?(\.[0-9]+)*/)
            report(label substr(after, 1, RLENGTH), "a range is not a ref; cite each section")
        } else if (after ~ /^\.?[A-Za-z0-9_]/) {
            match(after, /^\.?[A-Za-z0-9_]+/)
            report(label substr(after, 1, RLENGTH), "not a section number")
        } else if (!(num in known)) {
            report(label, "no numbered heading has this number")
        }
    }
    {
        s = $0
        while ((p = index(s, sign)) > 0) {
            s = substr(s, p + slen)
            if (s ~ /^ [0-9]/) {
                match(substr(s, 2), NUM)
                report(sign " " substr(s, 2, RLENGTH), "no space between § and the number")
            } else if (match(s, NUM)) {
                num = substr(s, 1, RLENGTH)
                judge(sign num, num, substr(s, RLENGTH + 1))
            }
        }
        s = $0
        while (match(s, /(^|[^A-Za-z0-9_])[Ss]ections? [0-9]/)) {
            s = substr(s, RSTART)
            if (s !~ /^[Ss]/) s = substr(s, 2)
            match(s, /^[Ss]ections? /)
            word = substr(s, 1, RLENGTH)
            s = substr(s, RLENGTH + 1)
            match(s, NUM)
            num = substr(s, 1, RLENGTH)
            s = substr(s, RLENGTH + 1)
            judge(word num, num, s)
            # `sections 9.3, 9.4 and 9.5` cites each number in the list.
            while (word ~ /s $/ && match(s, /^(,|,? and|,? or) [0-9]/)) {
                s = substr(s, RLENGTH)
                match(s, NUM)
                num = substr(s, 1, RLENGTH)
                s = substr(s, RLENGTH + 1)
                judge(num, num, s)
            }
        }
    }
' "${gated[@]}" >> "$work/problems" || { echo "spec-refs: cannot read the gated files" >&2; exit 2; }

if [ -s "$work/problems" ]; then
    count=$(grep -c . "$work/problems")
    sed 's/^/  /' "$work/problems"
    echo "spec-refs: FAIL $count broken ref(s) or heading(s) in ${#gated[@]} gated files"
    exit 1
fi
echo "spec-refs: ok every ref in ${#gated[@]} gated files names one of $(grep -c . "$work/heads") numbered headings"
