#!/bin/bash
# Proves `scripts/capped.sh --child` caps one test child inside a gate run: a
# memory hog, a fork loop and a sleep past the time limit each fail with one
# line that names the limit hit, a crash and a plain failure name no limit, a
# pass still passes, the exit code passes through, a child killed by its own
# cap gives no line about the gate's cap, and a nested --child stays in its
# parent child's caps. It also proves the --report file, a fork refused at the
# gate's cap, "infinity", a signal to the wrapper, and that a child OOM while
# the gate reclaims page cache names no gate cap. With no systemd-run, each
# child gets prlimit caps and a time limit, and the gate prints the one notice
# for that, not each child. `--own-cgroup` gives a command a cgroup with only
# that command in it inside a delegated gate run, and runs it in place, with a
# line that says why, anywhere else, and it names an OOM kill in that cgroup.
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

# A runner that starts this test in the background without job control makes
# it ignore SIGINT, and a shell cannot trap a signal ignored at its start, so
# each case starts with SIGINT at its default where env can do that.
defsig=()
env --default-signal=INT true 2>/dev/null && defsig=(--default-signal=INT)

# Each case starts as a fresh top-level gate run, as test_capped.sh does.
run() {
    env ${defsig[@]+"${defsig[@]}"} -u BLINK_GATE_SCOPE -u BLINK_GATE_CAP -u BLINK_CHILD_CAP -u BLINK_CHILD_CAP_MODE -u BLINK_CHILD_CGROUP \
        -u BLINK_CHILD_CAPPED -u BLINK_CHILD_MEMORY_MAX -u BLINK_CHILD_TASKS_MAX -u BLINK_CHILD_SWAP_MAX \
        -u BLINK_CHILD_TIMEOUT -u BLINK_CHILD_KILL_AFTER "$@"
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
# A killed process can stay a zombie until its new parent reaps it, and
# kill -0 still finds a zombie.
alive() {
    local st
    st=$(ps -o stat= -p "$1" 2>/dev/null) && [ "${st#Z}" = "$st" ]
}

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

    # A child at its cap must die at once, not page out to the swap that the
    # gate's other children share.
    printf '%s' 'cat "/sys/fs/cgroup$(cut -d: -f3 /proc/self/cgroup)/memory.swap.max"' > "$WORK/swap_max"
    swaps=$(gate -- '"$CAPPED" --child bash '"$WORK/swap_max"'
        BLINK_CHILD_SWAP_MAX=64M "$CAPPED" --child bash '"$WORK/swap_max"'
        BLINK_CHILD_SWAP_MAX=infinity "$CAPPED" --child bash '"$WORK/swap_max")
    if [ -e "/sys/fs/cgroup$(cut -d: -f3 /proc/self/cgroup)/memory.swap.max" ]; then
        if [ "$(echo $swaps)" = "0 67108864 max" ] && [ ! -s "$WORK/err" ]; then
            pass "a child gets no swap unless BLINK_CHILD_SWAP_MAX gives it some"
        else
            flunk "child swap cap (got [$(echo $swaps)]: $(cat "$WORK/err"))"
        fi
    else
        echo "SKIP: this kernel keeps no swap account; the child swap cap case did not run"
    fi

    # A child's cgroup goes when the child ends, whatever the way it ends, so
    # a gate of thousands of children leaves none behind.
    hog='x=$(head -c 512M /dev/zero | tr "\\0" a)'
    printf '%s' "$hog" > "$WORK/hog_quiet"
    left=$(gate BLINK_CHILD_MEMORY_MAX=64M BLINK_CHILD_TIMEOUT=1 -- 'for i in 1 2 3; do
            "$CAPPED" --child true; "$CAPPED" --child false; "$CAPPED" --child sleep 5
        done
        "$CAPPED" --child bash '"$WORK/hog_quiet"'
        d=/sys/fs/cgroup$(cut -d: -f3 /proc/self/cgroup); ls "${d%/*}/kids" | grep -c "^c-"')
    if [ "$left" = 0 ]; then
        pass "each child's cgroup is removed when the child ends"
    else
        flunk "child cgroups left behind (got [$left]: $(cat "$WORK/err"))"
    fi

    # A child may make cgroups below its own, as a Blink program does for a
    # memory or processes limit, and leave a process in one. rmdir takes only
    # an empty cgroup with no cgroup below it, so the gate must end and remove
    # them from the deepest up. The check runs inside the gate: the end of the
    # gate's scope removes the whole tree anyway.
    printf '%s' 'd=/sys/fs/cgroup$(cut -d: -f3 /proc/self/cgroup); mkdir "$d/sub" && mkdir "$d/sub/leaf" && { sleep 30 > /dev/null 2>&1 & echo $! > "$d/sub/leaf/cgroup.procs" && echo "$d $!"; }' > "$WORK/sub_cg"
    nested=$(gate -- '"$CAPPED" --child bash '"$WORK/sub_cg"' > "'"$WORK"'/sub_out"
        read -r d p < "'"$WORK"'/sub_out"
        [ -n "$d" ] || { echo "no cgroup"; exit 0; }
        if [ -d "$d" ]; then echo "kept"; else echo "gone"; fi
        st=$(ps -o stat= -p "$p") && [ "${st#Z}" = "$st" ] && { echo "alive"; kill -9 "$p"; }
        true')
    if [ "$nested" = gone ]; then
        pass "a child's own sub-cgroups and the process left in them go when the child ends"
    else
        flunk "nested child cgroups (got [$(echo $nested)]: $(cat "$WORK/err"))"
    fi

    # A slice with no unit gives the gate a plain user scope, which must still
    # hand each child a cgroup of its own.
    where=$(gate BLINK_GATE_SLICE=blink-no-such-unit-test.slice -- '"$CAPPED" --child cut -d: -f3 /proc/self/cgroup')
    case "$where" in
        */blink-no-such-unit-test.slice/*) flunk "plain scope (ran in the slice with no unit: [$where])" ;;
        */blink-gate-*.scope/kids/c-*) pass "a plain user scope still gives each child a cgroup of its own" ;;
        *) flunk "plain scope child cgroup (got [$where]: $(cat "$WORK/err"))" ;;
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
    if [ "$rc" = 139 ] && [ "$(any_child_lines)" = 0 ] && ! grep -q 'Segmentation fault' "$WORK/err"; then
        pass "a crash stays a crash, names no limit, and adds no job line to stderr"
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
    if [ "$(echo "$out" | wc -l)" = 2 ] && [ -n "$pid" ] && [ "$(echo "$out" | tail -1)" = 0 ] && ! alive "$pid"; then
        pass "a child's leftover processes end with it and its cgroup is removed"
    else
        flunk "leftover child processes (out=[$out]: $(cat "$WORK/err"))"
    fi

    # A child may exit 124 itself; only a spent time limit names the limit.
    gate BLINK_CHILD_TIMEOUT=60 -- '"$CAPPED" --child bash -c "exit 124"'
    rc=$?
    if [ "$rc" = 124 ] && [ "$(any_child_lines)" = 0 ]; then
        pass "a child that exits 124 before its time limit names no limit"
    else
        flunk "fast exit 124 (rc=$rc: $(cat "$WORK/err"))"
    fi

    # systemd's "infinity" lifts one cap; the other cap still holds.
    caps=$(gate BLINK_CHILD_MEMORY_MAX=infinity BLINK_CHILD_TASKS_MAX=64 -- \
        '"$CAPPED" --child bash -c '\''d=/sys/fs/cgroup$(cut -d: -f3 /proc/self/cgroup); echo "${d##*/} $(cat "$d/memory.max") $(cat "$d/pids.max")"'\''')
    case "$caps" in
        "c-"*" max 64") pass "BLINK_CHILD_MEMORY_MAX=infinity lifts the memory cap and keeps the task cap" ;;
        *) flunk "memory cap infinity (got [$caps]: $(cat "$WORK/err"))" ;;
    esac

    # A gate started from a shell that a child left BLINK_CHILD_CAPPED in
    # still caps its own children.
    caps=$(gate BLINK_CHILD_CAPPED=1 BLINK_CHILD_MEMORY_MAX=64M -- \
        '"$CAPPED" --child bash -c '\''d=/sys/fs/cgroup$(cut -d: -f3 /proc/self/cgroup); echo "${d##*/} $(cat "$d/memory.max")"'\''')
    case "$caps" in
        "c-"*" 67108864") pass "an inherited BLINK_CHILD_CAPPED does not lift a new gate's child caps" ;;
        *) flunk "inherited BLINK_CHILD_CAPPED (got [$caps]: $(cat "$WORK/err"))" ;;
    esac

    # A signal to the wrapper ends the child at once and removes its cgroup.
    # Job control keeps SIGINT at its default in the background wrapper, as a
    # terminal's Ctrl-C would reach a foreground one.
    sigs=TERM
    [ ${#defsig[@]} -gt 0 ] && sigs="TERM INT"
    [ ${#defsig[@]} -gt 0 ] || echo "SKIP: env has no --default-signal; the SIGINT cases did not run"
    for sig in $sigs; do
        start=$EPOCHSECONDS
        out=$(gate -- 'set -m; "$CAPPED" --child bash -c "echo \$\$ > '"$WORK"'/kidpid; exec sleep 300" > /dev/null & w=$!; set +m
            for _ in $(seq 50); do [ -s '"$WORK"'/kidpid ] && break; sleep 0.1; done
            kill -'"$sig"' "$w"; wait "$w"; echo "rc=$?"
            d=/sys/fs/cgroup$(cut -d: -f3 /proc/self/cgroup); ls -d "${d%/*}"/kids/c-* 2>/dev/null | wc -l')
        took=$((EPOCHSECONDS - start))
        kidpid=$(cat "$WORK/kidpid" 2>/dev/null)
        rm -f "$WORK/kidpid"
        want=143
        [ "$sig" = INT ] && want=130
        if [ "$out" = "$(printf 'rc=%s\n0' "$want")" ] && [ "$took" -lt 15 ] && [ -n "$kidpid" ] && ! alive "$kidpid"; then
            pass "SIG$sig to the wrapper ends the child at once and removes its cgroup"
        else
            flunk "SIG$sig to the wrapper (out=[$out] took=${took}s kid=[$kidpid]: $(cat "$WORK/err"))"
            [ -n "$kidpid" ] && kill "$kidpid" 2>/dev/null
        fi
    done

    # The report file gets the line of the cap that ended a failed child.
    # Here a fork loop in a subshell fills the task cap, then the hog the
    # memory cap; bash retries the hog's forks until the sleepers end.
    printf '%s\n%s' '( for i in $(seq 100); do sleep 1 & done ) 2>/dev/null' "$hog" > "$WORK/both"
    gate BLINK_CHILD_MEMORY_MAX=64M BLINK_CHILD_SWAP_MAX=0 BLINK_CHILD_TASKS_MAX=64 -- \
        '"$CAPPED" --child --report '"$WORK/report"' bash '"$WORK/both" > /dev/null
    rc=$?
    case "$(cat "$WORK/report")" in
        "capped.sh: the child hit its memory cap (MemoryMax=64M)"*)
            if [ "$rc" != 0 ] && [ "$(child_lines 'hit its process cap (TasksMax=64)')" = 1 ]; then
                pass "a child that hits both caps prints both and reports the memory cap that ended it"
            else
                flunk "both caps (rc=$rc: $(cat "$WORK/err"))"
            fi
            ;;
        *) flunk "both caps report (rc=$rc report=[$(cat "$WORK/report")]: $(cat "$WORK/err"))" ;;
    esac

    # A child that passed in spite of a cap hit has nothing to report.
    printf '%s\n%s' '( for i in $(seq 100); do sleep 1 & done ) 2>/dev/null' 'exit 0' > "$WORK/forks_pass"
    gate BLINK_CHILD_TASKS_MAX=64 -- '"$CAPPED" --child --report '"$WORK/report"' bash '"$WORK/forks_pass" > /dev/null
    rc=$?
    if [ "$rc" = 0 ] && [ ! -s "$WORK/report" ] && [ "$(child_lines 'hit its process cap (TasksMax=64)')" = 1 ]; then
        pass "a child that passes after a cap hit leaves the report file empty"
    else
        flunk "passing child after a cap hit (rc=$rc report=[$(cat "$WORK/report")]: $(cat "$WORK/err"))"
    fi

    # Forks the gate's own cap refuses leave the child's count at 0, so the
    # line must come from the gate's count. A sibling may own that count, so
    # it is not the child's reason in the report.
    printf '%s' 'for i in $(seq 200); do sleep 3 & done 2>/dev/null; wait; exit 1' > "$WORK/gate_forks"
    gate BLINK_GATE_TASKS_MAX=64 BLINK_CHILD_TASKS_MAX=256 -- \
        '"$CAPPED" --child --report '"$WORK/report"' bash '"$WORK/gate_forks" > /dev/null
    if [ ! -s "$WORK/report" ] &&
        grep -q '^capped.sh: the gate refused .* forks at its process cap (TasksMax=64) while this child ran; exit ' "$WORK/err"; then
        pass "a child whose forks the gate's cap refused names the gate's cap, but not as its reason"
    else
        flunk "gate fork cap (report=[$(cat "$WORK/report")]: $(cat "$WORK/err"))"
    fi

    # A sibling's fork loop at the gate's cap is not the reason another child
    # failed: the report stays empty and the child's own error stands. The
    # sibling starts once the child has made its last fork; a fork the cap
    # refuses at the child's start would fail it for a reason of its own.
    printf '%s' 'sleep 3 & : > "$1"; wait; exit 1' > "$WORK/child_sleep"
    rm -f "$WORK/started"
    gate BLINK_GATE_TASKS_MAX=64 -- '"$CAPPED" --child --report '"$WORK/report"' bash '"$WORK/child_sleep $WORK/started"' & c=$!
        while [ ! -e '"$WORK/started"' ]; do sleep 0.1; done
        bash '"$WORK/gate_forks"' 2>/dev/null &
        wait $c; echo "rc=$?"; wait' > "$WORK/out"
    if [ "$(cat "$WORK/out")" = rc=1 ] && [ ! -s "$WORK/report" ]; then
        pass "a sibling's forks at the gate's cap do not become another child's reason"
    else
        flunk "sibling at the gate cap (out=[$(cat "$WORK/out")] report=[$(cat "$WORK/report")]: $(cat "$WORK/err"))"
    fi

    # Ctrl-C ends a loop of children, as it ends a loop of plain commands: the
    # wrapper dies by the signal, so the loop's shell sees it.
    [ ${#defsig[@]} -gt 0 ] && out=$(gate -- 'set -m; bash -c '\''for i in 1 2 3; do "$CAPPED" --child sleep 3; echo "iter $i"; done'\'' & w=$!; set +m
        sleep 1; kill -INT -- "-$w"; wait "$w"; echo "rc=$?"')
    if [ ${#defsig[@]} = 0 ]; then
        :
    elif [ "$out" = rc=130 ]; then
        pass "Ctrl-C to a loop of children ends the loop"
    else
        flunk "Ctrl-C to a loop (out=[$out]: $(cat "$WORK/err"))"
    fi

    # Page cache from a big read fills the gate's cap and makes it reclaim;
    # with a child killed at its own cap, that is still no OOM of the gate.
    # The file is written and synced first: dirty pages from a write in the
    # gate wait on the disk, and under load the gate can then truly OOM. Its
    # pages then leave the cache, or the read would charge none to the gate.
    dd if=/dev/zero of="$WORK/fill" bs=1M count=400 conv=fsync status=none
    dd if="$WORK/fill" iflag=nocache count=0 status=none
    gate BLINK_GATE_MEMORY_MAX=128M BLINK_GATE_SWAP_MAX=0 BLINK_CHILD_MEMORY_MAX=48M BLINK_CHILD_SWAP_MAX=0 -- \
        '"$CAPPED" --child bash '"$WORK/hog"' > /dev/null; cat '"$WORK/fill"' > /dev/null'
    rc=$?
    rm -f "$WORK/fill"
    if [ "$rc" = 0 ] && [ "$(child_lines 'hit its memory cap (MemoryMax=48M)')" = 1 ] && [ "$(gate_lines)" = 0 ]; then
        pass "a child OOM while the gate reclaims page cache prints no line about the gate's cap"
    else
        flunk "child OOM with gate reclaim (rc=$rc: $(cat "$WORK/err"))"
    fi

    out=$(gate BLINK_CHILD_CAP=0 -- '"$CAPPED" --child cut -d: -f3 /proc/self/cgroup')
    case "$out" in
        */gate) pass "BLINK_CHILD_CAP=0 runs a child in place, with no cgroup of its own" ;;
        *) flunk "BLINK_CHILD_CAP=0 (cgroup [$out]: $(cat "$WORK/err"))" ;;
    esac

    # --own-cgroup gives a command a cgroup with no process in it but the
    # command, so a Blink program there can apply memory and processes limits
    # to its own children (it needs to own its whole cgroup). The cgroup has
    # no caps of its own: the gate's caps hold over it. Builtins only, so no
    # helper process sits in the cgroup while it is read.
    printf '%s' 'd=/sys/fs/cgroup$(cut -d: -f3 /proc/self/cgroup); exec bash -c '\''d=$1; mapfile -t p < "$d/cgroup.procs"; read -r ctl < "$d/cgroup.controllers"; read -r m < "$d/memory.max"; read -r t < "$d/pids.max"; printf "%s %s [%s] %s %s %s\n" "${d##*/}" "${#p[@]}" "$ctl" "$m" "$t" "${BLINK_OWN_CGROUP:-unset}"'\'' _ "$d"' > "$WORK/own_probe"
    own=$(gate -- '"$CAPPED" --own-cgroup bash '"$WORK/own_probe")
    case "$own" in
        "o-"*" 1 [memory pids] max max 1")
            if [ ! -s "$WORK/err" ]; then
                pass "--own-cgroup runs the command alone in a cgroup with no caps of its own and sets BLINK_OWN_CGROUP=1"
            else
                flunk "--own-cgroup printed a notice: $(cat "$WORK/err")"
            fi
            ;;
        *) flunk "--own-cgroup (got [$own]: $(cat "$WORK/err"))" ;;
    esac

    # The cgroup goes when the command ends, with the cgroups a Blink program
    # made below it and a process left in one, and the exit code passes through.
    # The command names its cgroup, so a run in place cannot pass as one in o-.
    printf '%s' 'd=/sys/fs/cgroup$(cut -d: -f3 /proc/self/cgroup); echo "${d##*/}"; mkdir "$d/blink.self" && { sleep 30 > /dev/null 2>&1 & echo $! > "$d/blink.self/cgroup.procs"; }; exit 5' > "$WORK/own_left"
    out=$(gate -- '"$CAPPED" --own-cgroup bash '"$WORK/own_left"'; echo "rc=$?"
        d=/sys/fs/cgroup$(cut -d: -f3 /proc/self/cgroup); ls "${d%/*}/kids" | grep -c "^o-"')
    case "$out" in
        "o-"*"$(printf '\nrc=5\n0')")
            if [ ! -s "$WORK/err" ]; then
                pass "--own-cgroup keeps the exit code and removes its cgroup tree when the command ends"
            else
                flunk "--own-cgroup cleanup printed a notice: $(cat "$WORK/err")"
            fi
            ;;
        *) flunk "--own-cgroup cleanup (out=[$out]: $(cat "$WORK/err"))" ;;
    esac

    # A signal to the script ends the command and removes its cgroup tree.
    out=$(gate -- '"$CAPPED" --own-cgroup sleep 30 & p=$!; sleep 1; kill -TERM "$p"; wait "$p"; echo "rc=$?"
        d=/sys/fs/cgroup$(cut -d: -f3 /proc/self/cgroup); ls "${d%/*}/kids" | grep -c "^o-"')
    if [ "$out" = "$(printf 'rc=143\n0')" ]; then
        pass "a signal to --own-cgroup ends the command and removes its cgroup"
    else
        flunk "--own-cgroup signal (out=[$out]: $(cat "$WORK/err"))"
    fi

    # The command is out of the gate's leaf, so the run's report cannot count
    # a kill at the run's memory cap there; --own-cgroup says it itself.
    printf '%s' "$hog" > "$WORK/hog"
    gate BLINK_GATE_MEMORY_MAX=64M BLINK_GATE_SWAP_MAX=0 -- '"$CAPPED" --own-cgroup bash '"$WORK/hog" > /dev/null
    rc=$?
    if [ "$rc" = 137 ] && grep -q "^capped.sh: the run's memory cap fired while bash ran in its own cgroup, and the OOM killer killed [1-9][0-9]* of its processes; exit 137\$" "$WORK/err"; then
        pass "a kill at the run's memory cap in an --own-cgroup command gets a line of its own"
    else
        flunk "--own-cgroup at the run's memory cap (rc=$rc: $(cat "$WORK/err"))"
    fi

    # A kill at a cap the command set below its cgroup, as blink test does for
    # each test binary, is the command's to report. The command moves itself
    # out first, as the Blink runtime does: a cgroup with processes in it
    # cannot pass controllers down.
    printf '%s' 'd=/sys/fs/cgroup$(cut -d: -f3 /proc/self/cgroup); mkdir "$d/self" "$d/sub" && echo 0 > "$d/self/cgroup.procs" && echo "+memory +pids" > "$d/cgroup.subtree_control" && echo 32M > "$d/sub/memory.max" && echo 0 > "$d/sub/memory.swap.max" && bash -c '\''echo 0 > "$1/cgroup.procs" && exec bash "$2"'\'' _ "$d/sub" '"$WORK/hog"'; echo "sub rc=$?"' > "$WORK/own_sub"
    out=$(gate -- '"$CAPPED" --own-cgroup bash '"$WORK/own_sub")
    if [ "$out" = "sub rc=137" ] && ! grep -q '^capped.sh:' "$WORK/err"; then
        pass "a kill at a cap below an --own-cgroup command gives no line"
    else
        flunk "--own-cgroup with its own cap (out=[$out]: $(cat "$WORK/err"))"
    fi

    # The ways that give no cgroup run the command in place, without
    # BLINK_OWN_CGROUP even when the caller's env has it, and print why.
    own_where='"$CAPPED" --own-cgroup bash -c '\''echo "$(cut -d: -f3 /proc/self/cgroup) ${BLINK_OWN_CGROUP:-unset}"'\'''
    out=$(gate BLINK_CHILD_CAP=0 BLINK_OWN_CGROUP=1 -- "$own_where")
    case "$out" in
        */gate" unset")
            if grep -q '^capped.sh: .* gets no cgroup of its own: BLINK_CHILD_CAP=0' "$WORK/err"; then
                pass "BLINK_CHILD_CAP=0 runs an --own-cgroup command in place and says why"
            else
                flunk "BLINK_CHILD_CAP=0 --own-cgroup notice: $(cat "$WORK/err")"
            fi
            ;;
        *) flunk "BLINK_CHILD_CAP=0 --own-cgroup (got [$out]: $(cat "$WORK/err"))" ;;
    esac

    # Inside a child, a cgroup of its own would take the command out of the
    # child's caps.
    out=$(gate -- '"$CAPPED" --child '"$own_where")
    case "$out" in
        */c-*" unset")
            if grep -q '^capped.sh: .* gets no cgroup of its own: it runs inside a child' "$WORK/err"; then
                pass "--own-cgroup inside a child stays in the child's cgroup and says why"
            else
                flunk "--own-cgroup in a child notice: $(cat "$WORK/err")"
            fi
            ;;
        *) flunk "--own-cgroup in a child (got [$out]: $(cat "$WORK/err"))" ;;
    esac
else
    echo "SKIP: no systemd user scope with delegation on this machine; the cgroup cases did not run"
fi

# A child in a process group of its own must not read the terminal: it would
# stop for ever when it has no time limit.
if command -v script >/dev/null 2>&1; then
    out=$(run CAPPED="$CAPPED" timeout 30 script -qec '"$CAPPED" --child --timeout 0 head -c1; echo "rc=$?"' /dev/null < /dev/null 2>&1)
    rc=$?
    case "$out" in
        *rc=0*) pass "a child with no time limit does not stop on the terminal" ;;
        *) flunk "child on a terminal (rc=$rc out=[$out])" ;;
    esac
else
    echo "SKIP: no script command; the terminal case did not run"
fi

# --- --own-cgroup with no delegated gate scope ----------------------------------

# own_in_place <label> <run args...>: the command runs, without
# BLINK_OWN_CGROUP even when the caller's env has it, keeps its exit code, and
# one line says that it gets no cgroup of its own.
own_in_place() {
    local label=$1 out rc
    shift
    out=$(run BLINK_OWN_CGROUP=1 "$@" "$CAPPED" --own-cgroup bash -c 'echo "${BLINK_OWN_CGROUP:-unset}"; exit 4' 2> "$WORK/err")
    rc=$?
    if [ "$out" = unset ] && [ "$rc" = 4 ] && [ "$(grep -c '^capped.sh: .* gets no cgroup of its own: ' "$WORK/err")" = 1 ]; then
        pass "$label: an --own-cgroup command runs in place and one line says why"
    else
        flunk "$label: --own-cgroup (out=[$out] rc=$rc: $(cat "$WORK/err"))"
    fi
}
own_in_place "outside a gate run"
own_in_place "BLINK_GATE_CAP=0" BLINK_GATE_CAP=0 CAPPED="$CAPPED" timeout 60 "$CAPPED" bash -c '"$@"' _

# --- No systemd-run: prlimit caps each child ----------------------------------

# A PATH with the tools capped.sh and the cases need, minus systemd-run.
P="$WORK/noscope"
mkdir -p "$P"
for t in bash sh env cat cut ps wc id tr head sleep seq timeout grep uname prlimit dd rm; do
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
    out=$(gate PATH="$P" -- 'BLINK_CHILD_MEMORY_MAX=infinity "$CAPPED" --child bash -c "echo hi"')
    rc=$?
    if [ "$out" = hi ] && [ "$rc" = 0 ]; then
        pass "no systemd-run: BLINK_CHILD_MEMORY_MAX=infinity for one child sets no address space cap"
    else
        flunk "no systemd-run: memory infinity for one child (out=[$out] rc=$rc: $(cat "$WORK/err"))"
    fi

    gate PATH="$P" BLINK_CHILD_TASKS_MAX=infinity -- '"$CAPPED" --child bash -c "exit 0"'
    rc=$?
    if [ "$rc" = 0 ] && [ "$(grep -c 'integer expression\|syntax error' "$WORK/err")" = 0 ]; then
        pass "no systemd-run: BLINK_CHILD_TASKS_MAX=infinity runs the child"
    else
        flunk "no systemd-run: tasks infinity (rc=$rc: $(cat "$WORK/err"))"
    fi

    own_in_place "no systemd-run" PATH="$P" CAPPED="$CAPPED" timeout 60 "$CAPPED" bash -c '"$@"' _
else
    echo "SKIP: no prlimit on this machine; the prlimit child cases did not run"
fi

[ "$fail" = 0 ] && echo "ok: capped.sh --child" || echo "FAILED: capped.sh --child"
exit "$fail"
