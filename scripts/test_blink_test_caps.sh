#!/bin/bash
# Proves that `scripts/blink_test_capped.sh`, the way each Taskfile task runs
# `blink test`, gives every test binary a memory and a process cap that
# `blink test` applies itself inside a gate run: a binary that keeps 128M
# under a 64M cap and one that starts 64 sleepers under a 32 process cap each
# end as aborted with the limit keys, and a plain test still runs. It also
# proves the default caps the script passes, and that with no delegated
# cgroup the script passes none and says so, so blink test still runs.
# Each fixture stops on its own, so a cap that does not hold reads as "ran",
# not as a hang; nothing here grows past about 200M or 100 processes.
#
#   scripts/test_blink_test_caps.sh <blink>
set -u
cd "$(dirname "$0")/.."
ROOT=$PWD
CAPPED="$ROOT/scripts/capped.sh"
RUNNER="$ROOT/scripts/blink_test_capped.sh"
BLINK=${1:?usage: scripts/test_blink_test_caps.sh <blink>}
case "$BLINK" in /*) ;; *) BLINK=$ROOT/$BLINK ;; esac

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
fail=0

pass() { echo "PASS: $1"; }
flunk() { echo "FAIL: $1"; fail=1; }

# Each case starts as a fresh top-level gate run, as test_capped_child.sh does.
run() {
    env -u BLINK_GATE_SCOPE -u BLINK_GATE_CAP -u BLINK_CHILD_CAP -u BLINK_CHILD_CAP_MODE -u BLINK_CHILD_CGROUP \
        -u BLINK_CHILD_CAPPED -u BLINK_OWN_CGROUP -u BLINK_TEST_MEMORY -u BLINK_TEST_PROCESSES "$@"
}

mkdir -p "$WORK/caps" "$WORK/plain"
cat > "$WORK/caps/test_caps_hog.bl" <<'EOF'
test "keeps 128M" {
    let mut keep: List[List[Int]] = []
    for _i in 0..128 {
        let mut block: List[Int] = []
        for j in 0..131072 {
            block.push(j)
        }
        keep.push(block)
    }
    assert_eq(keep.len(), 128)
}
EOF
cat > "$WORK/caps/test_caps_forker.bl" <<'EOF'
import std.process.{Child}

test "starts 64 sleepers" {
    let mut kids: List[Child] = []
    for _i in 0..64 {
        match process.spawn("sleep", ["30"]) {
            Ok(c) => kids.push(c)
            Err(_) => {}
        }
    }
    for c in kids {
        let _ = process.signal(c, 15)
        let _ = process.wait(c)
    }
    assert_eq(kids.len(), 64)
}
EOF
cat > "$WORK/plain/test_caps_plain.bl" <<'EOF'
test "passes" {
    assert_eq(1 + 1, 2)
}
EOF
cp "$WORK/plain/test_caps_plain.bl" "$WORK/caps/"
# A stand-in for blink that prints the arguments the script gives it.
printf '%s\n' '#!/bin/bash' 'echo "$* ${BLINK_OWN_CGROUP:-unset}"' > "$WORK/stub"
chmod +x "$WORK/stub"
cd "$WORK"

# file_line <file> <json lines>: the record:file line of one fixture.
file_line() { grep '"record":"file"' <<< "$2" | grep -F "\"file\":\"$1\""; }

if command -v systemd-run >/dev/null 2>&1 &&
    systemd-run --user --scope -q -p Delegate=yes -p MemoryMax=256M -p TasksMax=256 true >/dev/null 2>&1; then

    out=$(run BLINK_TEST_MEMORY=64M BLINK_TEST_PROCESSES=32 timeout 300 "$CAPPED" \
        "$RUNNER" "$BLINK" test caps/ --json --timeout 60s 2> "$WORK/err")
    rc=$?
    hog=$(file_line caps/test_caps_hog.bl "$out")
    forker=$(file_line caps/test_caps_forker.bl "$out")
    plain=$(file_line caps/test_caps_plain.bl "$out")
    case "$hog" in
        *'"outcome":"aborted","limit":"memory","limit_bytes":67108864,'*) pass "a test binary over its memory cap ends as aborted with limit memory" ;;
        *) flunk "memory cap (rc=$rc line=[$hog]: $(cat "$WORK/err"))" ;;
    esac
    case "$forker" in
        *'"outcome":"aborted","limit":"processes","limit_count":32,'*) pass "a test binary over its process cap ends as aborted with limit processes" ;;
        *) flunk "process cap (rc=$rc line=[$forker]: $(cat "$WORK/err"))" ;;
    esac
    case "$plain" in
        *'"outcome":"ran"'*) pass "a plain test binary still runs under the caps" ;;
        *) flunk "plain under the caps (rc=$rc line=[$plain]: $(cat "$WORK/err"))" ;;
    esac
    if [ "$rc" = 1 ]; then
        pass "a run with aborted files exits 1"
    else
        flunk "exit of a run with aborted files (rc=$rc: $(cat "$WORK/err"))"
    fi

    out=$(run timeout 60 "$CAPPED" "$RUNNER" "$WORK/stub" test caps/ 2> "$WORK/err")
    if [ "$out" = "test caps/ --memory 2G --processes 256 1" ] && [ ! -s "$WORK/err" ]; then
        pass "in a gate run the script passes --memory 2G --processes 256 by default"
    else
        flunk "default caps (out=[$out]: $(cat "$WORK/err"))"
    fi
else
    echo "SKIP: no systemd user scope with delegation on this machine, so blink test cannot cap a test binary's memory or processes here; the cap cases did not run"
fi

# No delegated cgroup: no cap flags, one line that says so, and blink test runs.
out=$(run BLINK_GATE_CAP=0 timeout 60 "$CAPPED" "$RUNNER" "$WORK/stub" test caps/ 2> "$WORK/err")
if [ "$out" = "test caps/ unset" ] &&
    grep -q '^blink_test_capped.sh: each test binary gets its time limit only, no memory or process cap$' "$WORK/err"; then
    pass "with BLINK_GATE_CAP=0 the script passes no cap flags and says so"
else
    flunk "no cgroup, stub (out=[$out]: $(cat "$WORK/err"))"
fi

out=$(run BLINK_GATE_CAP=0 timeout 300 "$CAPPED" "$RUNNER" "$BLINK" test plain/ --json 2> "$WORK/err")
rc=$?
case "$(file_line plain/test_caps_plain.bl "$out")" in
    *'"outcome":"ran"'*)
        if [ "$rc" = 0 ]; then
            pass "with no delegated cgroup blink test still runs, with no usage error"
        else
            flunk "no cgroup, blink test exit (rc=$rc: $(cat "$WORK/err"))"
        fi
        ;;
    *) flunk "no cgroup, blink test (rc=$rc out=[$out]: $(cat "$WORK/err"))" ;;
esac

[ "$fail" = 0 ] && echo "ok: blink test caps" || echo "FAILED: blink test caps"
exit "$fail"
