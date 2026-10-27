#!/bin/bash
# Proves scripts/capped.sh caps a run once and only once: a nested call runs in
# the same cgroup, the exit code passes through, a memory hog and a fork loop
# die at small caps and each gets a one-line report, BLINK_GATE_CAP=0 runs
# in place, a slice with no unit still gets a capped scope, the scope caps swap
# at 2G unless BLINK_GATE_SWAP_MAX says otherwise, with no systemd-run on PATH
# the run falls back to prlimit, then to ulimit, and a Taskfile dispatcher
# hands its body the vars set on the command line.
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
notices() { grep -c '^capped.sh: ' "$WORK/err"; }

# This test runs inside a gate that capped.sh already capped; each case starts
# as a fresh top-level run.
run() { env -u BLINK_GATE_SCOPE -u BLINK_GATE_CAP "$@"; }

own_cgroup=$(cut -d: -f3 /proc/self/cgroup)

# A PATH that holds the tools capped.sh and the cases need, minus systemd-run
# and systemctl, and minus prlimit when the second argument is "noprlimit".
fake_path() {
    dir="$WORK/$1"
    mkdir -p "$dir"
    for t in bash sh env cat cut ps wc id tr head sleep seq timeout grep uname; do
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
    notices=$(notices)
    if [ "$out" = "as=65536 scope=prlimit" ] && [ "$rc" = 5 ] && [ "$notices" = 1 ]; then
        pass "no systemd-run: prlimit caps the address space, with one notice, exit code kept"
    else
        flunk "no systemd-run: prlimit (out=[$out] rc=$rc notices=$notices: $(cat "$WORK/err"))"
    fi
    out=$(run PATH="$P" BLINK_GATE_MEMORY_MAX=64M "$CAPPED" "$CAPPED" bash -c 'ulimit -v' 2> "$WORK/err")
    notices=$(notices)
    if [ "$out" = 65536 ] && [ "$notices" = 1 ]; then
        pass "no systemd-run: a nested call does not cap twice"
    else
        flunk "no systemd-run: nested call (out=[$out] notices=$notices)"
    fi
else
    echo "SKIP: no prlimit on this machine"
fi

# Darwin: ps -L lists keywords, RLIMIT_NPROC counts processes, and ulimit -v
# does not hold. Stubs stand in for uname and ps: three processes of this user.
P=$(fake_path darwin noprlimit)
rm -f "$P/uname" "$P/ps"
printf '#!/bin/sh\necho Darwin\n' > "$P/uname"
printf '#!/bin/sh\n[ "$*" = "-ax -o uid=" ] || exit 1\nu=$(id -u)\nprintf "%%s\\n" "$u" 0 "$u" 0 "$u"\n' > "$P/ps"
chmod +x "$P/uname" "$P/ps"
# The cap lands on the hard nproc limit: ulimit -u cannot go above it, and on
# Linux the real processes of this user count against a lower one.
hard=$(ulimit -Hu)
[ "$hard" = unlimited ] && hard=100003
out=$(run PATH="$P" BLINK_GATE_TASKS_MAX=$((hard - 3)) "$CAPPED" bash -c 'echo "$(ulimit -u) $(ulimit -v)"' 2> "$WORK/err")
if [ "$out" = "$hard unlimited" ] && [ "$(notices)" = 1 ]; then
    pass "Darwin: the process cap counts this user's processes, and no address space cap"
else
    flunk "Darwin (out=[$out]: $(cat "$WORK/err"))"
fi

P=$(fake_path noprlimit noprlimit)
out=$(run PATH="$P" BLINK_GATE_MEMORY_MAX=64M "$CAPPED" bash -c 'echo "as=$(ulimit -v) scope=$BLINK_GATE_SCOPE"' 2> "$WORK/err")
rc=$?
notices=$(notices)
if [ "$out" = "as=65536 scope=ulimit" ] && [ "$rc" = 0 ] && [ "$notices" = 1 ]; then
    pass "no systemd-run and no prlimit: ulimit caps the address space, with one notice"
else
    flunk "no systemd-run and no prlimit: ulimit (out=[$out] rc=$rc: $(cat "$WORK/err"))"
fi

# --- Taskfile dispatchers ----------------------------------------------------

missing=
for t in $(sed -n 's/^  \([a-z0-9-]*\):$/\1/p' Taskfile.yml); do
    if sed -n "/^  $t:\$/,/^  [^ ]/p" Taskfile.yml | grep -Eq '[&*]capped$|scripts/capped.sh --name'; then
        grep -q "^  __$t:\$" Taskfile.yml || missing="$missing $t"
    fi
done
if [ -z "$missing" ]; then
    pass "each capped Taskfile task has a __<task> body"
else
    flunk "capped Taskfile tasks with no __<task> body:$missing"
fi

# The capped re-run gets the vars set on the command line, and only those, and
# its body sees them. dispatch prints the dispatcher's command; body runs that
# command with --dry, through capped.sh's opt-out path, and prints the body's
# `blink test` line, which holds BUILD_DIR and JOBS.
dispatch() {
    env -u BLINK_GATE_SCOPE -u BLINK_GATE_CAP task --dry --verbose "$@" 2>&1 |
        grep -o 'scripts/capped.sh --name .*'
}
body() {
    (unset BLINK_GATE_SCOPE; export BLINK_GATE_CAP=0; eval "$1 --dry") 2>&1 |
        grep -o '[^ ]*blink test tests/ --parallel .*'
}
# A value equal to its default is not passed on, so JOBS must differ from it.
default_jobs=$(./scripts/default_jobs.sh)
jobs=$((default_jobs + 1))
line=$(dispatch test JOBS="$jobs" BUILD_DIR=bd BLINKC='/a b/x' VERSION=1.2 FMT_SEMANTIC=0 CORPUS_LINT=0 CORPUS_PM_SLICE=s)
plain=$(dispatch test BUILD_DIR=build JOBS="$default_jobs")
case "$line" in
    *" test --verbose BUILD_DIR=bd BLINKC='/a b/x' JOBS=$jobs VERSION=1.2 FMT_SEMANTIC=0 CORPUS_LINT=0 CORPUS_PM_SLICE=s") forwarded=1 ;;
    *) forwarded=0 ;;
esac
case "$plain" in
    *" test --verbose") bare=1 ;;
    *) bare=0 ;;
esac
got=$(body "$line")
got_plain=$(body "$plain")
if [ "$forwarded" = 1 ] && [ "$bare" = 1 ] && [ "$got" = "bd/blink test tests/ --parallel $jobs" ] &&
    [ "$got_plain" = "build/blink test tests/ --parallel $default_jobs" ]; then
    pass "a dispatcher forwards the vars set on the command line, and no others, to its body"
else
    flunk "dispatcher vars (with vars: [$line] -> [$got], without: [$plain] -> [$got_plain])"
fi

# A Task that ignores the cmd-level if: runs the dispatcher inside the capped
# run; capped.sh must stop there, not exec task again.
out=$(env BLINK_GATE_SCOPE=selftest "$CAPPED" --name selftest echo ran 2> "$WORK/err")
rc=$?
if [ "$rc" = 2 ] && [ -z "$out" ] && grep -q 'Task 3.47' "$WORK/err"; then
    pass "a dispatcher inside its own capped run stops with one line"
else
    flunk "dispatcher inside its capped run (out=[$out] rc=$rc: $(cat "$WORK/err"))"
fi

# --- Opt-out -----------------------------------------------------------------

out=$(env -u BLINK_GATE_SCOPE BLINK_GATE_CAP=0 "$CAPPED" cut -d: -f3 /proc/self/cgroup 2> "$WORK/err")
notices=$(notices)
if [ "$out" = "$own_cgroup" ] && [ "$notices" = 1 ]; then
    pass "BLINK_GATE_CAP=0 runs in place, with one notice"
else
    flunk "BLINK_GATE_CAP=0 (cgroup [$out], want [$own_cgroup]; notices=$notices)"
fi

# --- systemd scope ------------------------------------------------------------

# The same properties capped.sh asks for: a user manager with no memory or pids
# controller starts a bare scope but not this one, and capped.sh falls back.
if ! command -v systemd-run >/dev/null 2>&1 ||
    ! systemd-run --user --scope -q -p MemoryMax=64M -p MemorySwapMax=0 -p TasksMax=64 -p OOMPolicy=continue true >/dev/null 2>&1; then
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
# A slice with no unit adds that notice; nothing else may print.
extra=$(grep -v '^capped.sh: .* has no unit, so this run gets a plain user scope' "$WORK/err")
if [ "$in_scope" = 1 ] && [ "$first" = "$second" ] && [ -z "$extra" ]; then
    pass "the run gets one scope, and a nested call stays in it"
else
    flunk "one scope (first=[$first] second=[$second] err=[$(cat "$WORK/err")])"
fi

out=$(run "$CAPPED" --name selftest-probe cut -d: -f3 /proc/self/cgroup)
case "$out" in
    */blink-gate-selftest-probe-*.scope) pass "--name names the scope" ;;
    *) flunk "--name (cgroup [$out])" ;;
esac

# A kernel with no swap accounting (swapaccount=0) has no memory.swap.max.
caps=$(run BLINK_GATE_MEMORY_MAX=64M BLINK_GATE_TASKS_MAX=64 "$CAPPED" bash -c 'd=/sys/fs/cgroup$(cut -d: -f3 /proc/self/cgroup); echo "$(cat "$d/memory.max") $(cat "$d/pids.max") $(cat "$d/memory.swap.max" 2>/dev/null || echo none)"')
case "$caps" in
    "67108864 64 2147483648")
        swap_files=1
        pass "the scope carries the memory, swap (2G by default) and task caps"
        ;;
    "67108864 64 none")
        swap_files=0
        pass "the scope carries the memory and task caps"
        echo "SKIP: no swap accounting in this kernel; the swap cases did not run"
        ;;
    *)
        swap_files=0
        flunk "scope caps (got [$caps])"
        ;;
esac

if [ "$swap_files" = 1 ]; then
    swap='cat /sys/fs/cgroup$(cut -d: -f3 /proc/self/cgroup)/memory.swap.max'
    out=$(run BLINK_GATE_SWAP_MAX=32M "$CAPPED" bash -c "$swap")
    out_inf=$(run BLINK_GATE_SWAP_MAX=infinity "$CAPPED" bash -c "$swap")
    if [ "$out" = 33554432 ] && [ "$out_inf" = max ]; then
        pass "BLINK_GATE_SWAP_MAX sets the swap cap, and infinity lifts it"
    else
        flunk "swap override (32M: [$out], infinity: [$out_inf])"
    fi
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
notices=$(notices)
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

# default.target has a unit but is not a slice, so no scope can start in it.
out=$(run BLINK_GATE_SLICE=default.target "$CAPPED" cut -d: -f3 /proc/self/cgroup 2> "$WORK/err")
rc=$?
notices=$(notices)
case "$out" in
    */blink-gate-*.scope) where=scope ;;
    *) where=none ;;
esac
if [ "$rc" = 0 ] && [ "$where" = scope ] && [ "$notices" = 1 ]; then
    pass "a unit that cannot hold a scope: a plain capped user scope, with one notice"
else
    flunk "unit that is not a slice (rc=$rc cgroup [$out]: $(cat "$WORK/err"))"
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
