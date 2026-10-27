#!/bin/bash
# Proves `scripts/capped.sh --child` caps one test child inside a gate run: a
# memory hog, a fork loop and a sleep past the time limit each fail with one
# line that names the limit hit, a crash and a plain failure name no limit, a
# pass still passes, the exit code passes through, a child killed by its own
# cap gives no line about the gate's cap, and a nested --child stays in its
# parent child's caps. With no systemd-run, each child gets prlimit caps and a
# time limit, and the gate prints the one notice for that, not each child.
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

# Each case starts as a fresh top-level gate run, as test_capped.sh does.
run() {
    env -u BLINK_GATE_SCOPE -u BLINK_GATE_CAP -u BLINK_CHILD_CAP -u BLINK_CHILD_CAP_MODE -u BLINK_CHILD_CGROUP \
        -u BLINK_CHILD_MEMORY_MAX -u BLINK_CHILD_TASKS_MAX -u BLINK_CHILD_SWAP_MAX -u BLINK_CHILD_TIMEOUT "$@"
}

# gate <env assignments...> -- <shell text>: run the shell text as a gate's
# body, with $CAPPED in its env. Its stderr goes to $WORK/err.
gate() {
    local envs=()
    while [ "$1" != -- ]; do envs+=("$1"); shift; done
    shift
    run "${envs[@]}" CAPPED="$CAPPED" timeout 60 "$CAPPED" bash -c "$1" 2> "$WORK/err"
}

child_lines() { grep -c "^capped.sh: the child $1" "$WORK/err"; }
any_child_lines() { grep -c '^capped.sh: the child' "$WORK/err"; }
gate_lines() { grep -c '^capped.sh: the run ' "$WORK/err"; }

# The same caps the gate run asks for, with Delegate=yes: a user manager that
# cannot delegate gets the prlimit path, which the second half covers.
if command -v systemd-run >/dev/null 2>&1 &&
    systemd-run --user --scope -q -p Delegate=yes -p MemoryMax=64M -p MemorySwapMax=0 -p TasksMax=64 -p OOMPolicy=continue true >/dev/null 2>&1; then

    caps=$(gate BLINK_CHILD_MEMORY_MAX=64M BLINK_CHILD_TASKS_MAX=64 -- \
        '"$CAPPED" --child bash -c '\''d=/sys/fs/cgroup$(cut -d: -f3 /proc/self/cgroup); echo "${d##*/} $(cat "$d/memory.max") $(cat "$d/pids.max")"'\''')
    case "$caps" in
        "c-"*" 67108864 64") pass "a child runs in a cgroup of its own with the child memory and task caps" ;;
        *) flunk "child cgroup (got [$caps]: $(cat "$WORK/err"))" ;;
    esac

    out=$(gate -- '"$CAPPED" --child bash -c "echo hi; exit 0"')
    rc=$?
    if [ "$out" = hi ] && [ "$rc" = 0 ] && [ ! -s "$WORK/err" ]; then
        pass "a passing child passes, with nothing on stderr"
    else
        flunk "passing child (out=[$out] rc=$rc: $(cat "$WORK/err"))"
    fi

    gate -- '"$CAPPED" --child bash -c "exit 3"'
    rc=$?
    if [ "$rc" = 3 ] && [ "$(any_child_lines)" = 0 ]; then
        pass "a failing child keeps its exit code and names no limit"
    else
        flunk "failing child (rc=$rc: $(cat "$WORK/err"))"
    fi

    gate -- '"$CAPPED" --child bash -c "kill -SEGV \$\$"'
    rc=$?
    if [ "$rc" = 139 ] && [ "$(any_child_lines)" = 0 ]; then
        pass "a crash stays a crash and names no limit"
    else
        flunk "crash (rc=$rc: $(cat "$WORK/err"))"
    fi

    # A command substitution holds its whole output in memory: 512M here, eight
    # times the cap.
    hog='x=$(head -c 512M /dev/zero | tr "\\0" a); echo "${#x}"'
    printf '%s' "$hog" > "$WORK/hog"
    gate BLINK_CHILD_MEMORY_MAX=64M BLINK_CHILD_SWAP_MAX=0 -- '"$CAPPED" --child bash '"$WORK/hog" > /dev/null
    rc=$?
    if [ "$rc" != 0 ] && [ "$(child_lines 'hit its memory cap (MemoryMax=64M)')" = 1 ] && [ "$(gate_lines)" = 0 ]; then
        pass "a memory hog dies at the child cap with one line naming it, and none about the gate"
    else
        flunk "child memory hog (rc=$rc: $(cat "$WORK/err"))"
    fi

    # 200 sleepers against a cap of 64 tasks; bash retries a failed fork, so the
    # loop ends once the sleepers end.
    forks='for i in $(seq 200); do sleep 3 & done 2>/dev/null; wait'
    printf '%s' "$forks" > "$WORK/forks"
    gate BLINK_CHILD_TASKS_MAX=64 -- '"$CAPPED" --child bash '"$WORK/forks" > /dev/null
    rc=$?
    if [ "$rc" != 124 ] && [ "$(child_lines 'hit its process cap (TasksMax=64)')" = 1 ] && [ "$(gate_lines)" = 0 ]; then
        pass "a fork loop stops at the child task cap with one line naming it, and none about the gate"
    else
        flunk "child fork loop (rc=$rc: $(cat "$WORK/err"))"
    fi

    start=$EPOCHSECONDS
    gate BLINK_CHILD_TIMEOUT=2 -- '"$CAPPED" --child sleep 30'
    rc=$?
    took=$((EPOCHSECONDS - start))
    if [ "$rc" = 124 ] && [ "$took" -lt 15 ] && [ "$(child_lines 'ran past its time limit (2s)')" = 1 ]; then
        pass "a sleep past the time limit ends with exit 124 and one line naming the limit"
    else
        flunk "child time limit (rc=$rc took=${took}s: $(cat "$WORK/err"))"
    fi

    # --timeout overrides BLINK_CHILD_TIMEOUT for one call.
    start=$EPOCHSECONDS
    gate BLINK_CHILD_TIMEOUT=600 -- '"$CAPPED" --child --timeout 2 sleep 30'
    rc=$?
    took=$((EPOCHSECONDS - start))
    if [ "$rc" = 124 ] && [ "$took" -lt 15 ] && [ "$(child_lines 'ran past its time limit (2s)')" = 1 ]; then
        pass "--timeout sets the time limit of one child"
    else
        flunk "--timeout (rc=$rc took=${took}s: $(cat "$WORK/err"))"
    fi

    # A child that ignores SIGTERM gets SIGKILL after the grace, exit 137; that
    # is still the time limit, not a memory kill.
    start=$EPOCHSECONDS
    gate BLINK_CHILD_TIMEOUT=1 BLINK_CHILD_KILL_AFTER=1 -- '"$CAPPED" --child bash -c "trap \"\" TERM; sleep 30"'
    rc=$?
    took=$((EPOCHSECONDS - start))
    if [ "$rc" = 137 ] && [ "$took" -lt 15 ] && [ "$(child_lines 'ran past its time limit (1s)')" = 1 ] &&
        [ "$(child_lines 'hit its memory')" = 0 ]; then
        pass "a child that ignores SIGTERM is killed at the time limit and the line names the time limit"
    else
        flunk "child that ignores SIGTERM (rc=$rc took=${took}s: $(cat "$WORK/err"))"
    fi

    # A --child inside a child runs in place: it must not leave its parent's
    # cgroup and with it the parent's caps.
    nested=$(gate -- '"$CAPPED" --child bash -c '\''cut -d: -f3 /proc/self/cgroup; "$CAPPED" --child cut -d: -f3 /proc/self/cgroup'\''')
    first=$(echo "$nested" | head -1)
    second=$(echo "$nested" | sed -n 2p)
    case "$first" in */c-*) in_child=1 ;; *) in_child=0 ;; esac
    if [ "$in_child" = 1 ] && [ "$first" = "$second" ]; then
        pass "a nested --child stays in its parent child's cgroup"
    else
        flunk "nested --child (first=[$first] second=[$second]: $(cat "$WORK/err"))"
    fi

    # A child's background process ends with the child, so the child's cgroup
    # can go and no stray outlives its row.
    out=$(gate -- '"$CAPPED" --child bash -c "sleep 300 & echo \$!"; d=/sys/fs/cgroup$(cut -d: -f3 /proc/self/cgroup); ls -d "${d%/*}"/kids/c-* 2>/dev/null | wc -l')
    pid=$(echo "$out" | head -1)
    if [ "$(echo "$out" | wc -l)" = 2 ] && [ -n "$pid" ] && [ "$(echo "$out" | tail -1)" = 0 ] && ! kill -0 "$pid" 2>/dev/null; then
        pass "a child's leftover processes end with it and its cgroup is removed"
    else
        flunk "leftover child processes (out=[$out]: $(cat "$WORK/err"))"
    fi

    out=$(gate BLINK_CHILD_CAP=0 -- '"$CAPPED" --child cut -d: -f3 /proc/self/cgroup')
    case "$out" in
        */gate) pass "BLINK_CHILD_CAP=0 runs a child in place, with no cgroup of its own" ;;
        *) flunk "BLINK_CHILD_CAP=0 (cgroup [$out]: $(cat "$WORK/err"))" ;;
    esac
else
    echo "SKIP: no systemd user scope with delegation on this machine; the cgroup cases did not run"
fi

# --- No systemd-run: prlimit caps each child ----------------------------------

# A PATH with the tools capped.sh and the cases need, minus systemd-run.
P="$WORK/noscope"
mkdir -p "$P"
for t in bash sh env cat cut ps wc id tr head sleep seq timeout grep uname prlimit; do
    p=$(command -v "$t") && ln -sf "$p" "$P/$t"
done

if command -v prlimit >/dev/null 2>&1; then
    out=$(gate PATH="$P" BLINK_CHILD_MEMORY_MAX=64M -- 'for i in 1 2 3; do "$CAPPED" --child bash -c "ulimit -v"; done')
    rc=$?
    child_notices=$(grep -c '^capped.sh: .*each child' "$WORK/err")
    if [ "$out" = "$(printf '65536\n65536\n65536')" ] && [ "$rc" = 0 ] && [ "$child_notices" = 1 ]; then
        pass "no systemd-run: prlimit caps each child's address space, and the gate prints one notice for three children"
    else
        flunk "no systemd-run: child prlimit (out=[$out] rc=$rc: $(cat "$WORK/err"))"
    fi

    gate PATH="$P" BLINK_CHILD_TIMEOUT=2 -- '"$CAPPED" --child sleep 30'
    rc=$?
    if [ "$rc" = 124 ] && [ "$(child_lines 'ran past its time limit (2s)')" = 1 ]; then
        pass "no systemd-run: a sleep past the time limit still names the limit"
    else
        flunk "no systemd-run: child time limit (rc=$rc: $(cat "$WORK/err"))"
    fi
else
    echo "SKIP: no prlimit on this machine; the prlimit child cases did not run"
fi

[ "$fail" = 0 ] && echo "ok: capped.sh --child" || echo "FAILED: capped.sh --child"
exit "$fail"
