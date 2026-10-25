#!/bin/bash
# The warning gate of `task ci`: the compiler's own build must print no
# warning. Runs `blink check --json` on both compiler entry points with this
# tree's compiler (gen1), so the lint that judges src/ and lib/ is the lint
# in src/. gen0's lint is older than the tree and would judge wrongly both
# ways. check runs every stage that warns in a build (check_pipeline.bl).
#
# A site counts once however many entry points reach it, so the count does
# not move when an import moves. Each site prints as
# `file:line:col code name: message`, and a warning with no span prints as
# `<no location>` and still counts. A warning that reaches stderr as text
# counts too: the gate never drops one because it did not come as JSON.
#
#   scripts/check_build_warnings.sh   (env WARNING_GATE_BLINK, default build/gen1/bin/blink)
#
# Exit 0 with no warning, 1 with one or more, 2 when a check did not run
# clean (non-zero exit, an error or ice row, no ok status line, or a row
# the gate cannot read), since such a run cannot vouch for a count of 0.
set -u
cd "$(dirname "$0")/.." || exit 2
blink="${WARNING_GATE_BLINK:-build/gen1/bin/blink}"
entries="src/cli.bl src/blinkc_main.bl"

if [ ! -x "$blink" ]; then
    echo "warning-gate: no compiler at $blink (run 'task gen1')" >&2
    exit 2
fi
command -v jq > /dev/null 2>&1 || { echo "warning-gate: missing tool: jq" >&2; exit 2; }

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# The two checks share nothing but their inputs, so they run side by side.
# Each PID is waited on by itself: a bare `wait` returns 0 and would hide a
# failure.
pids=()
for e in $entries; do
    n=$(basename "$e" .bl)
    ("$blink" check --json "$e" > "$work/$n.out" 2> "$work/$n.err") &
    pids+=("$!")
done
rcs=()
for p in "${pids[@]}"; do wait "$p"; rcs+=("$?"); done

# rows <file> <tag>: one tab-separated row per line of <file>, led by the
# severity, `status`, or <tag> for a line that is not a JSON object. A line
# jq cannot parse or format becomes a row too (`bad` for an object), so jq
# never drops a row or stops part way; if jq fails anyway, a `bad` row says so.
rows() {
    jq -R -r --arg tag "$2" '
        . as $line
        | (fromjson? // null) as $d
        | if ($d | type) != "object" then "\($tag)\t\($line)"
          elif $d.severity == null and $d.status != null then "status\t\($d.status)"
          else try (
            ($d.span // {}) as $s
            | (if ($s.file // "") == "" then "<no location>"
               else "\($s.file):\($s.line // 0):\($s.col // 0)" end) as $at
            # One row per line: a newline in the message would split it.
            | ($d.message // "" | gsub("\n"; "\\n") | gsub("\t"; " ")) as $m
            | "\($d.severity // "?")\t\($at) \($d.code // "?") \($d.name // "?"): \($m)"
          ) catch "bad\t\($line)"
          end' "$1" || printf 'bad\tjq failed on %s\n' "$1"
}

# blink prints the diagnostic rows on stderr and the status line on stdout;
# both streams are read the same way. A non-JSON line on stdout is output the
# gate cannot read; on stderr it is chatter, unless it names a warning.
# A raw line may hold a tab, so a row's text is all that follows its tag.
broken=0
i=0
: > "$work/sites"
for e in $entries; do
    n=$(basename "$e" .bl)
    rc=${rcs[$i]}; i=$((i + 1))
    { rows "$work/$n.out" bad; rows "$work/$n.err" text; } > "$work/$n.rows"
    awk -F'\t' '$1 == "warning" { sub(/^[^\t]*\t/, ""); print }' "$work/$n.rows" >> "$work/sites"
    awk -F'\t' '$1 == "text" { sub(/^[^\t]*\t/, ""); if (/(^|[^[:alnum:]_])warning([^[:alnum:]_]|$)/) print "stderr: " $0 }' "$work/$n.rows" >> "$work/sites"
    why=""
    if [ "$rc" != 0 ]; then
        why="check exited $rc"
    elif grep -q -E '^(error|ice)'$'\t' "$work/$n.rows"; then
        why="it reported an error"
    elif grep -q '^bad'$'\t' "$work/$n.rows"; then
        why="it printed a row this gate cannot read"
    elif grep -q -v -E '^(warning|status|text)'$'\t' "$work/$n.rows"; then
        why="it printed a row of a severity this gate does not know"
    elif [ "$(awk -F'\t' '$1 == "status" { print $2 }' "$work/$n.rows")" != ok ]; then
        why="it printed no single ok status line"
    fi
    if [ -n "$why" ]; then
        echo "warning-gate: FAIL the check of $e did not run clean ($why):"
        awk -F'\t' '$1 != "status" { sub(/^[^\t]*\t/, ""); print "  " $0 }' "$work/$n.rows"
        broken=1
    fi
done
[ "$broken" = 0 ] || exit 2

LC_ALL=C sort -u "$work/sites" > "$work/distinct"
count=$(grep -c . "$work/distinct" || true)
if [ "$count" -ne 0 ]; then
    sed 's/^/  /' "$work/distinct"
    echo "warning-gate: FAIL $count distinct warning site(s) in the compiler build ($entries)"
    exit 1
fi
echo "warning-gate: ok 0 warnings in the compiler build ($entries)"
