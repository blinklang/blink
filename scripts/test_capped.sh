#!/bin/bash
# Proves scripts/capped.sh caps a run once and only once: a nested call runs in
# the same cgroup, the exit code passes through, a memory hog and a fork loop
# die at small caps and each gets a one-line report, BLINK_GATE_CAP=0 runs
# in place, a slice with no unit still gets a capped scope, and with no
# systemd-run on PATH the run falls back to prlimit, then to ulimit.
# Every hog and fork loop here runs under a cap of 64M or 64 tasks, with a
# timeout, so this test cannot grow past a few hundred MB.
set -u
cd "$(dirname "$0")/.."
CAPPED="$PWD/scripts/capped.sh"

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
fail=0

pass() { echo "PASS: $1"; }
flunk() { echo "FAIL: $1"; fail=1; }

# This test runs inside a gate that capped.sh already capped; each case starts
# as a fresh top-level run.
run() { env -u BLINK_GATE_SCOPE -u BLINK_GATE_CAP "$@"; }

own_cgroup=$(cut -d: -f3 /proc/self/cgroup)

# A PATH that holds the tools capped.sh and the cases need, minus systemd-run
# and systemctl, and minus prlimit when the second argument is "noprlimit".
fake_path() {
    dir="$WORK/$1"
    mkdir -p "$dir"
    for t in bash sh env cat cut ps wc id tr head sleep seq timeout grep; do
        p=$(command -v "$t") && ln -sf "$p" "$dir/$t"
    done
    if [ "${2:-}" != noprlimit ]; then
        p=$(command -v prlimit) && ln -sf "$p" "$dir/prlimit"
    fi
    echo "$dir"
}

# --- No systemd-run: prlimit, then ulimit, else uncapped --------------------

if command -v prlimit >/dev/null 2>&1; then
    P=$(fake_path noscope)
    out=$(run PATH="$P" BLINK_GATE_MEMORY_MAX=64M "$CAPPED" bash -c 'echo "as=$(ulimit -v) scope=$BLINK_GATE_SCOPE"; exit 5' 2> "$WORK/err")
    rc=$?
    notices=$(grep -c '^capped.sh: ' "$WORK/err")
    if [ "$out" = "as=65536 scope=prlimit" ] && [ "$rc" = 5 ] && [ "$notices" = 1 ]; then
        pass "no systemd-run: prlimit caps the address space, with one notice, exit code kept"
    else
        flunk "no systemd-run: prlimit (out=[$out] rc=$rc notices=$notices: $(cat "$WORK/err"))"
    fi
    out=$(run PATH="$P" BLINK_GATE_MEMORY_MAX=64M "$CAPPED" "$CAPPED" bash -c 'ulimit -v' 2> "$WORK/err")
    notices=$(grep -c '^capped.sh: ' "$WORK/err")
    if [ "$out" = 65536 ] && [ "$notices" = 1 ]; then
        pass "no systemd-run: a nested call does not cap twice"
    else
        flunk "no systemd-run: nested call (out=[$out] notices=$notices)"
    fi
else
    echo "SKIP: no prlimit on this machine"
fi

P=$(fake_path noprlimit noprlimit)
out=$(run PATH="$P" BLINK_GATE_MEMORY_MAX=64M "$CAPPED" bash -c 'echo "as=$(ulimit -v) scope=$BLINK_GATE_SCOPE"' 2> "$WORK/err")
rc=$?
notices=$(grep -c '^capped.sh: ' "$WORK/err")
if [ "$out" = "as=65536 scope=ulimit" ] && [ "$rc" = 0 ] && [ "$notices" = 1 ]; then
    pass "no systemd-run and no prlimit: ulimit caps the address space, with one notice"
else
    flunk "no systemd-run and no prlimit: ulimit (out=[$out] rc=$rc: $(cat "$WORK/err"))"
fi

# --- Opt-out -----------------------------------------------------------------

out=$(env -u BLINK_GATE_SCOPE BLINK_GATE_CAP=0 "$CAPPED" cut -d: -f3 /proc/self/cgroup 2> "$WORK/err")
notices=$(grep -c '^capped.sh: ' "$WORK/err")
if [ "$out" = "$own_cgroup" ] && [ "$notices" = 1 ]; then
    pass "BLINK_GATE_CAP=0 runs in place, with one notice"
else
    flunk "BLINK_GATE_CAP=0 (cgroup [$out], want [$own_cgroup]; notices=$notices)"
fi

# --- systemd scope ------------------------------------------------------------

if ! command -v systemd-run >/dev/null 2>&1 || ! systemd-run --user --scope -q true >/dev/null 2>&1; then
    echo "SKIP: no systemd user scope on this machine; the scope cases did not run"
    [ "$fail" = 0 ] && echo "ok: capped.sh" || echo "FAILED: capped.sh"
    exit "$fail"
fi

# Each line: the cgroup, then the scope marker, at each level.
show='echo "$(cut -d: -f3 /proc/self/cgroup) $BLINK_GATE_SCOPE"'
out=$(run "$CAPPED" bash -c "$show; \"$CAPPED\" bash -c '$show'" 2> "$WORK/err")
first=$(echo "$out" | head -1)
second=$(echo "$out" | sed -n 2p)
cg=${first%% *}
case "$cg" in
    */blink-gate-*.scope) in_scope=1 ;;
    *) in_scope=0 ;;
esac
if [ "$in_scope" = 1 ] && [ "$first" = "$second" ] && [ ! -s "$WORK/err" ]; then
    pass "the run gets one scope, and a nested call stays in it"
else
    flunk "one scope (first=[$first] second=[$second] err=[$(cat "$WORK/err")])"
fi

out=$(run "$CAPPED" --name selftest-probe cut -d: -f3 /proc/self/cgroup)
case "$out" in
    */blink-gate-selftest-probe-*.scope) pass "--name names the scope" ;;
    *) flunk "--name (cgroup [$out])" ;;
esac

caps=$(run BLINK_GATE_MEMORY_MAX=64M BLINK_GATE_TASKS_MAX=64 "$CAPPED" bash -c 'd=/sys/fs/cgroup$(cut -d: -f3 /proc/self/cgroup); echo "$(cat "$d/memory.max") $(cat "$d/pids.max")"')
if [ "$caps" = "67108864 64" ]; then
    pass "the scope carries the memory and task caps"
else
    flunk "scope caps (got [$caps])"
fi

out=$(run "$CAPPED" bash -c 'x="a b"; echo "$x ${#x}"')
if [ "$out" = "a b 3" ]; then
    pass "the command reaches the shell unexpanded"
else
    flunk "the command was changed on the way in (got [$out])"
fi

for code in 0 1 7; do
    run "$CAPPED" bash -c "exit $code"
    rc=$?
    if [ "$rc" = "$code" ]; then
        pass "exit $code passes through"
    else
        flunk "exit $code came back as $rc"
    fi
done

out=$(run BLINK_GATE_SLICE=blink-gates-selftest-no-unit.slice "$CAPPED" cut -d: -f3 /proc/self/cgroup 2> "$WORK/err")
notices=$(grep -c '^capped.sh: ' "$WORK/err")
case "$out" in
    *blink-gates-selftest-no-unit.slice*) where=slice ;;
    */blink-gate-*.scope) where=scope ;;
    *) where=none ;;
esac
if [ "$where" = scope ] && [ "$notices" = 1 ]; then
    pass "a slice with no unit: a plain capped user scope, with one notice"
else
    flunk "slice with no unit (cgroup [$out], notices=$notices)"
fi

# A command substitution holds its whole output in memory: 512M here, eight
# times the cap.
hog='x=$(head -c 512M /dev/zero | tr "\\0" a); echo "${#x}"'
run BLINK_GATE_MEMORY_MAX=64M BLINK_GATE_SWAP_MAX=0 timeout 60 "$CAPPED" bash -c "$hog" > /dev/null 2> "$WORK/err"
rc=$?
lines=$(grep -c '^capped.sh: .*memory cap' "$WORK/err")
if [ "$rc" != 0 ] && [ "$rc" != 124 ] && [ "$lines" = 1 ]; then
    pass "a memory hog dies at the cap and the run says so in one line"
else
    flunk "memory hog (rc=$rc, report lines=$lines: $(cat "$WORK/err"))"
fi

# 200 sleepers against a cap of 64 tasks; bash retries a failed fork, so the
# loop ends by the timeout or once the sleepers end.
forks='for i in $(seq 200); do sleep 3 & done 2>/dev/null; wait'
run BLINK_GATE_TASKS_MAX=64 timeout 60 "$CAPPED" bash -c "$forks" > /dev/null 2> "$WORK/err"
rc=$?
lines=$(grep -c '^capped.sh: .*process cap' "$WORK/err")
if [ "$rc" != 124 ] && [ "$lines" = 1 ]; then
    pass "a fork loop stops at the task cap and the run says so in one line"
else
    flunk "fork loop (rc=$rc, report lines=$lines: $(cat "$WORK/err"))"
fi

[ "$fail" = 0 ] && echo "ok: capped.sh" || echo "FAILED: capped.sh"
exit "$fail"
