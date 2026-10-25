#!/bin/bash
# Proves scripts/check_build_warnings.sh goes red on one warning, counts a site
# once when both entry points report it, never drops a warning that has no
# span, and exits 2 (not 0) when the check itself did not run clean. Runs the
# script against a fake blink that prints canned `check --json` output, so it
# takes well under a second and never touches build/.
set -u
cd "$(dirname "$0")/.."

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
fail=0

# The fake answers `check --json src/<entry>.bl` with $FAKE/<entry>.out on
# stdout, $FAKE/<entry>.err on stderr and the exit code in $FAKE/<entry>.rc.
# Like the real blink, it prints the diagnostic rows on stderr and only the
# status line on stdout.
FAKE="$WORK/fake"
cat > "$WORK/blink" <<'EOF'
#!/bin/bash
[ "$1" = check ] && [ "$2" = --json ] || { echo "fake blink: unexpected args: $*" >&2; exit 9; }
e=$(basename "$3" .bl)
[ -f "$FAKE/$e.out" ] && cat "$FAKE/$e.out"
[ -f "$FAKE/$e.err" ] && cat "$FAKE/$e.err" >&2
exit "$(cat "$FAKE/$e.rc" 2>/dev/null || echo 0)"
EOF
chmod +x "$WORK/blink"
export FAKE

W_UNUSED='{"severity":"warning","name":"UnusedVariable","code":"W0600","message":"variable `x` is never read","span":{"file":"src/parser.bl","line":12,"col":5},"help":"prefix with `_`"}'
W_SHADOW='{"severity":"warning","name":"ShadowedBinding","code":"W0601","message":"`y` shadows","span":{"file":"lib/std/path.bl","line":3,"col":9}}'
W_NOLOC='{"severity":"warning","name":"ManifestLint","code":"W0900","message":"no location here","span":{"file":"","line":0,"col":0}}'
W_NOSPAN='{"severity":"warning","name":"NoSpan","code":"W0901","message":"span object absent"}'
E_ROW='{"severity":"error","name":"TypeMismatch","code":"E0200","message":"bad","span":{"file":"src/a.bl","line":1,"col":1}}'

# reset: both entries clean.
reset() {
    rm -rf "$FAKE"
    mkdir -p "$FAKE"
    for e in cli blinkc_main; do
        echo "{\"status\":\"ok\",\"file\":\"src/$e.bl\"}" > "$FAKE/$e.out"
    done
}

# add <entry> <row>: print a row on the entry's stderr, where blink prints
# its diagnostics.
add() {
    echo "$2" >> "$FAKE/$1.err"
}

# add_out <entry> <row>: print a row on stdout, before the status line.
add_out() {
    { echo "$2"; cat "$FAKE/$1.out"; } > "$FAKE/$1.out.new"
    mv "$FAKE/$1.out.new" "$FAKE/$1.out"
}

# expect <exit> "<label>" [<text the output must hold> ...]
expect() {
    want="$1"; label="$2"; shift 2
    out=$(WARNING_GATE_BLINK="$WORK/blink" ./scripts/check_build_warnings.sh 2>&1)
    rc=$?
    ok=1
    [ "$rc" = "$want" ] || ok=0
    for needle in "$@"; do
        grep -qF -- "$needle" <<< "$out" || ok=0
    done
    if [ "$ok" = 1 ]; then
        echo "PASS: $label"
    else
        echo "FAIL: $label (want exit $want, got $rc)"
        sed 's/^/    /' <<< "$out"
        fail=1
    fi
}

reset
expect 0 "a clean build passes" "warning-gate: ok"

reset; add cli "$W_UNUSED"
expect 1 "one warning goes red and names its site" \
    "src/parser.bl:12:5 W0600 UnusedVariable: variable \`x\` is never read" \
    "warning-gate: FAIL 1 distinct warning site(s)"

reset; add cli "$W_UNUSED"; add blinkc_main "$W_UNUSED"
expect 1 "a site both entry points reach counts once" "FAIL 1 distinct"

reset; add cli "$W_UNUSED"; add blinkc_main "$W_SHADOW"
expect 1 "sites from each entry point add up" \
    "src/parser.bl:12:5 W0600" "lib/std/path.bl:3:9 W0601" "FAIL 2 distinct"

reset; add cli '{"severity":"warning","name":"Multi","code":"W0602","message":"line one\nline\ttwo","span":{"file":"src/b.bl","line":2,"col":1}}'
expect 1 "a message over several lines stays one site" \
    'src/b.bl:2:1 W0602 Multi: line one\nline two' "FAIL 1 distinct"

reset; add cli "$W_NOLOC"
expect 1 "a warning with an empty span still counts" \
    "<no location> W0900 ManifestLint: no location here" "FAIL 1 distinct"

reset; add blinkc_main "$W_NOSPAN"
expect 1 "a warning with no span object still counts" \
    "<no location> W0901 NoSpan: span object absent" "FAIL 1 distinct"

reset; add_out cli "$W_UNUSED"
expect 1 "a warning row on stdout counts too" "src/parser.bl:12:5 W0600" "FAIL 1 distinct"

reset; echo "warning: manifest says something" > "$FAKE/cli.err"
expect 1 "a warning printed as text on stderr still counts" \
    "warning: manifest says something" "FAIL 1 distinct"

reset; echo "warning: manifest says something" > "$FAKE/cli.err"; cp "$FAKE/cli.err" "$FAKE/blinkc_main.err"
expect 1 "a stderr warning both entry points print counts once" "FAIL 1 distinct"

reset; printf 'note\tsee warning: tabbed\n' > "$FAKE/cli.err"
expect 1 "a stderr warning with a tab in the line still counts" \
    "$(printf 'stderr: note\tsee warning: tabbed')" "FAIL 1 distinct"

reset; echo "resolving dependencies..." > "$FAKE/cli.err"
expect 0 "stderr chatter that is not a warning passes"

reset; add cli "$E_ROW"
expect 2 "an error row means the check did not run clean" "src/a.bl:1:1 E0200" "(it reported an error)"

reset; add_out cli "$E_ROW"
expect 2 "an error row on stdout means the check did not run clean" "src/a.bl:1:1 E0200" "(it reported an error)"

reset; add cli '{"severity":"ice","name":"Ice","code":"I0001","message":"boom"}'
expect 2 "an ice row means the check did not run clean" "(it reported an error)"

reset; add cli '{"severity":"advice","name":"X","code":"A1","message":"m"}'
expect 2 "a row of a severity the gate does not know fails" "A1 X: m" "(it printed a row of a severity this gate does not know)"

reset; add cli '{"severity":"warning","name":"N","code":"W1","message":5,"span":{"file":"src/a.bl","line":1,"col":1}}'
expect 2 "a warning row whose message is not a string fails, never drops" "(it printed a row this gate cannot read)" '"message":5'

reset; add cli '{"severity":"warning","name":"N","code":"W1","message":"m","span":"src/a.bl"}'
expect 2 "a warning row whose span is not an object fails, never drops" "(it printed a row this gate cannot read)"

reset; : > "$FAKE/blinkc_main.out"
expect 2 "no status line means the check did not run" "(it printed no single ok status line)"

reset; echo '{"status":"error","file":"src/cli.bl"}' > "$FAKE/cli.out"
expect 2 "a status other than ok fails" "(it printed no single ok status line)"

reset; echo 3 > "$FAKE/cli.rc"
expect 2 "a check that exits non-zero fails" "(check exited 3)"

reset; add_out cli "this is not json"
expect 2 "output the gate cannot parse fails" "(it printed a row this gate cannot read)" "this is not json"

reset; add cli "$W_UNUSED"; echo 3 > "$FAKE/blinkc_main.rc"
expect 2 "a failed check outranks warnings from the other entry point" "(check exited 3)"

exit "$fail"
