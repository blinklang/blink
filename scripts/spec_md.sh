# Readers for the spec markdown. The checks that judge it load this file, so
# each check gets the same headings and the same table cells. Both readers
# skip fenced blocks: a `#` line or a `|` line in an example is not part of
# the document's structure. Run them under LC_ALL=C.

# The fence rule of CommonMark: a fence opens on 3 or more ` or ~ (a ` fence
# has no ` in its info string) and closes only on a line of the same mark, at
# least as long, with no info string. A shorter or tagged line inside is
# text, so a spec example can show a fenced block inside its own fence. A
# fence that never closes would hide the rest of its file from every check,
# so it stops the reader with exit 2.
_spec_md_fence='
    function in_fence(   s, mark, rest) {
        if (FNR == 1) fence_end()
        s = $0
        sub(/^[ \t]*/, "", s)
        if (match(s, /^(````*|~~~~*)/)) {
            mark = substr(s, 1, RLENGTH)
            rest = substr(s, RLENGTH + 1)
            if (fmark == "") {
                if (mark ~ /^`/ && rest ~ /`/) return 0
                fmark = mark; fat = FILENAME ":" FNR
                return 1
            }
            if (substr(mark, 1, 1) == substr(fmark, 1, 1) && length(mark) >= length(fmark) && rest ~ /^[ \t]*$/) {
                fmark = ""
                return 1
            }
        }
        return fmark != ""
    }
    function fence_end() {
        if (fmark == "") return
        print fat " -> a fence opens here and never closes" > "/dev/stderr"
        fmark = ""  # END runs after exit; report once
        exit 2
    }
    END { fence_end() }
'

# spec_headings <file>...: one line per numbered heading, in file order:
#   <number>\t<file>\t<line>
# A numbered heading is `#`..`######` after at most 3 spaces, then an
# optional `§`, then a number such as 3, 3b, 3b.5 or 4.16.7, with an
# optional trailing `.` (`## 1. Name`).
spec_headings() {
    awk "$_spec_md_fence"'
        in_fence() { next }
        match($0, /^ ? ? ?#+/) {
            hashes = substr($0, 1, RLENGTH)
            sub(/^ */, "", hashes)
            rest = substr($0, RLENGTH + 1)
            if (length(hashes) > 6 || rest !~ /^[ \t]/) next
            sub(/^[ \t]+/, "", rest)
            sub(/^§/, "", rest)
            if (!match(rest, /^[0-9]+[a-z]?(\.[0-9]+)*\.?([ \t]|$)/)) next
            num = substr(rest, 1, RLENGTH)
            sub(/[ \t]+$/, "", num)
            sub(/\.$/, "", num)
            printf "%s\t%s\t%d\n", num, FILENAME, FNR
        }
    ' "$@"
}

# md_table_rows <file>: one line per table line:
#   <line>\t<kind>\t<cell count>\t<cell>\t<cell>...
# <kind> is head for the first line of a table, sep for its `|---|` line and
# row for the rest. Cells are split on each `|` that has no `\` before it, as
# GitHub renders them, so a `|` inside backticks splits a cell there too; a
# `\|` stays in its cell as written. A tab inside a cell becomes a space.
# GitHub also reads a table whose lines have no leading `|`; such a table's
# `---|---` line comes out as kind bare with no cells, so a check can refuse
# what it would otherwise not see.
md_table_rows() {
    awk "$_spec_md_fence"'
        function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); gsub(/\t/, " ", s); return s }
        FNR == 1 { intable = 0 }
        in_fence() { intable = 0; next }
        $0 !~ /^[ \t]*\|/ {
            if (!intable && $0 ~ /^[ \t]*:?-+:?[ \t]*\|[ \t:|-]*$/) printf "%d\tbare\t0\n", FNR
            intable = 0
            next
        }
        {
            if (!intable) kind = "head"
            else if ($0 ~ /^[ \t]*\|[ \t:|-]*-[ \t:|-]*$/) kind = "sep"
            else kind = "row"
            intable = 1
            s = $0
            sub(/^[ \t]*\|/, "", s)
            sub(/[ \t]+$/, "", s)
            if (s ~ /\|$/ && s !~ /\\\|$/) s = substr(s, 1, length(s) - 1)
            n = 0; cell = ""; out = ""
            len = length(s)
            for (i = 1; i <= len; i++) {
                ch = substr(s, i, 1)
                if (ch == "\\" && substr(s, i + 1, 1) == "|") { cell = cell "\\|"; i++; continue }
                if (ch == "|") { out = out "\t" trim(cell); n++; cell = ""; continue }
                cell = cell ch
            }
            out = out "\t" trim(cell); n++
            printf "%d\t%s\t%d%s\n", FNR, kind, n, out
        }
    ' "$1"
}
