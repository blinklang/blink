#!/bin/bash
# Proves scripts/xfail_tickets.sh flags a test.failing row whose ticket is
# closed, unknown or missing, passes a row with an open ticket, ignores a row
# inside a raw-string probe program, and skips when br is missing. Uses fixed
# id lists, so it never reads the real br database.
set -u
cd "$(dirname "$0")/.."

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
fail=0

printf 'aaa111\n' > "$WORK/open"
printf 'aaa111\nbbb222\n' > "$WORK/all"

row() {
    printf 'test.failing(\n    "%s",\n    reason: "not built",\n%s) {\n    assert(1 == 2)\n}\n' "$1" "$2"
}
row "open ticket" '    ticket: "aaa111",
' > "$WORK/test_open.bl"
row "closed ticket" '    ticket: "bbb222",
' > "$WORK/test_closed.bl"
row "unknown ticket" '    ticket: "ccc333",
' > "$WORK/test_unknown.bl"
row "no ticket" '' > "$WORK/test_none.bl"
{
    printf 'test "probe" {\n    let src = #"\n'
    row "inside a probe" '    ticket: "zzz999",
'
    printf '"#\n}\n'
} > "$WORK/test_raw.bl"

check() {
    name="$1"; want="$2"; pattern="$3"; shift 3
    XFAIL_OPEN_IDS="$WORK/open" XFAIL_ALL_IDS="$WORK/all" ./scripts/xfail_tickets.sh "$@" > "$WORK/out.log" 2>&1
    got=$?
    if [ "$got" -ne "$want" ] || ! grep -qE -- "$pattern" "$WORK/out.log"; then
        echo "FAIL $name: want exit $want and /$pattern/, got exit $got"
        sed 's/^/    /' "$WORK/out.log"
        fail=1
    else
        echo "PASS $name"
    fi
}

check open-ticket 0 'ok \(1 test.failing rows' "$WORK/test_open.bl"
check closed-ticket 1 'test_closed.bl:1: ticket bbb222 is closed' "$WORK/test_closed.bl"
check unknown-ticket 1 'test_unknown.bl:1: ticket ccc333 is not a br ticket' "$WORK/test_unknown.bl"
check no-ticket 1 'test_none.bl:1: test.failing row names no ticket' "$WORK/test_none.bl"
check raw-string-probe 0 'ok \(0 test.failing rows' "$WORK/test_raw.bl"

XFAIL_BR=no-such-br-command ./scripts/xfail_tickets.sh "$WORK/test_closed.bl" > "$WORK/out.log" 2>&1
if [ $? -ne 0 ] || ! grep -q 'skipping' "$WORK/out.log"; then
    echo "FAIL no-br: a run without br must skip with exit 0"
    sed 's/^/    /' "$WORK/out.log"
    fail=1
else
    echo "PASS no-br"
fi

if [ "$fail" -ne 0 ]; then
    echo "test_xfail_tickets: FAILED"
    exit 1
fi
echo "test_xfail_tickets: all checks passed"
